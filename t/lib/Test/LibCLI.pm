package Test::LibCLI;

# Data-driven tests for libcli, in the style of Test::Nginx.
#
# Each block starts t/cli_driver on one end of a socketpair, types the
# block's input into cli_loop(), and checks the session output.  Every
# block is one subtest, so a test file plans "tests => scalar blocks()".
#
# Sections:
#
#   --- fixture: NAME        driver fixture (default "basic")
#   --- users                one "name:password" per line
#   --- enable_password: PW  password for "enable"
#   --- hostname: NAME       hostname shown in the prompt (default "router")
#   --- telnet               enable telnet protocol negotiation (presence)
#   --- input                keystrokes; each newline is sent as Enter (\r)
#   --- output               exact rendered output (see render())
#   --- output_like          one regex per line, each must match
#   --- output_unlike        one regex per line, none may match
#   --- exit_code: N         driver exit code (default 0)
#   --- timeout: SECONDS     default 10
#
# Test::Base's own "--- SKIP" section excludes a block from blocks(), so a
# block documenting a known, unfixed bug is marked SKIP and does not run.
#
# Key markers in input: <TAB> <ESC> <DEL> <UP> <DOWN> <LEFT> <RIGHT>
# <CTRL-X> (any letter) and <LT> for a literal "<".  Use "--- input eval"
# to generate input with Perl; newlines in the result are sent as Enter.
#
# Output assertions run against the session as a terminal would show it,
# with line-editor backspaces and redraws applied (see render()).
#
# Every block also fails if the driver dies on a signal, times out, or
# writes an AddressSanitizer or UndefinedBehaviorSanitizer report.

use Test::Base -Base;

use Errno qw(EAGAIN EINTR);
use File::Temp qw(tempfile);
use IO::Select;
use POSIX qw(WNOHANG);
use Socket;
use Time::HiRes qw(time);

our @EXPORT = qw(run_tests);

my $Driver = $ENV{LIBCLI_DRIVER} || 't/cli_driver';

$ENV{ASAN_OPTIONS}  ||= 'detect_leaks=0';
$ENV{UBSAN_OPTIONS} ||= 'print_stacktrace=1';

# With LIBCLI_VALGRIND set, each driver run is wrapped in Memcheck.  Use
# a non-sanitized driver for this (ASan and valgrind cannot coexist) by
# pointing LIBCLI_DRIVER at it; see "valgrind mode" in t/README.md.  This
# catches uninitialized-memory reads and leaks that ASan does not.
my @Valgrind = $ENV{LIBCLI_VALGRIND}
    ? ('valgrind', '-q', '--error-exitcode=99', '--leak-check=full',
       '--errors-for-leak-kinds=definite', '--track-origins=yes',
       '--suppressions=t/valgrind.supp')
    : ();

# Memcheck is ~20-30x slower, so stretch each block's timeout under it.
my $TimeoutScale = @Valgrind ? 30 : 1;

sub run_tests () {
    if (!-x $Driver) {
        Test::More::BAIL_OUT("$Driver not found; run \"make test\"");
    }

    my @blocks = Test::Base::blocks();

    # A file whose blocks are all marked SKIP has nothing to run; declare
    # it skipped rather than planning zero tests (which is an error).
    if (!@blocks) {
        Test::More::plan(skip_all => 'all blocks are marked SKIP');
        return;
    }

    Test::More::plan(tests => scalar @blocks);

    for my $block (@blocks) {
        Test::More::subtest($block->name, sub { run_block($block) });
    }
}

sub section ($$) {
    my ($block, $name) = @_;
    my $value = $block->$name;

    return undef if !defined $value;
    $value =~ s/\n\z//;

    return $value;
}

sub driver_args ($) {
    my $block = shift;
    my @args = ('--fixture', section($block, 'fixture') // 'basic');

    my $users = section($block, 'users');
    if (defined $users) {
        push @args, map { ('--user', $_) } grep { length } split /\n/, $users;
    }

    my $enable = section($block, 'enable_password');
    push @args, '--enable', $enable if defined $enable;

    my $hostname = section($block, 'hostname');
    push @args, '--hostname', $hostname if defined $hostname;

    push @args, '--telnet' if defined section($block, 'telnet');

    return @args;
}

my %Keys = (
    TAB   => "\t",
    ESC   => "\e",
    DEL   => "\x7f",
    UP    => "\e[A",
    DOWN  => "\e[B",
    RIGHT => "\e[C",
    LEFT  => "\e[D",
    LT    => '<',
);

sub encode_input ($) {
    my $input = shift;

    return '' if !defined $input;

    $input =~ s/\n/\r/g;
    $input =~ s/<CTRL-([A-Z])>/chr(ord($1) - 64)/ge;
    $input =~ s/<(TAB|ESC|DEL|UP|DOWN|RIGHT|LEFT|LT)>/$Keys{$1}/g;

    return $input;
}

# Run the driver, feed it $input, and return its output, exit status,
# stderr, and whether it timed out.
sub run_session ($$$) {
    my ($args, $input, $timeout) = @_;

    socketpair(my $ours, my $theirs, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
        or die "socketpair: $!";

    my ($errfh, $errfile) = tempfile(UNLINK => 1);

    my $pid = fork();
    die "fork: $!" if !defined $pid;

    if ($pid == 0) {
        close $ours;
        POSIX::dup2(fileno($theirs), 0) or POSIX::_exit(127);
        POSIX::dup2(fileno($errfh), 1) or POSIX::_exit(127);
        POSIX::dup2(fileno($errfh), 2) or POSIX::_exit(127);
        { exec @Valgrind, $Driver, @$args }
        print STDERR "exec $Driver: $!\n";
        POSIX::_exit(127);
    }

    close $theirs;
    $ours->blocking(0);

    my $output = '';
    my $deadline = time + $timeout;
    my $timed_out = 0;
    my $writing = length $input > 0;

    shutdown($ours, 1) if !$writing;

    for (;;) {
        my $left = $deadline - time;
        if ($left <= 0) {
            $timed_out = 1;
            last;
        }

        my $rsel = IO::Select->new($ours);
        my $wsel = $writing ? IO::Select->new($ours) : undef;
        my ($r, $w) = IO::Select->select($rsel, $wsel, undef, $left);

        if ($w && @$w) {
            my $n = syswrite($ours, $input);
            if (defined $n) {
                substr($input, 0, $n) = '';

            } elsif ($! != EAGAIN && $! != EINTR) {
                # The driver went away before reading all input.
                $input = '';
            }

            if (!length $input) {
                shutdown($ours, 1);
                $writing = 0;
            }
        }

        if ($r && @$r) {
            my $n = sysread($ours, my $buf, 65536);
            next if !defined $n && ($! == EAGAIN || $! == EINTR);
            last if !$n;
            $output .= $buf;
        }
    }

    close $ours;

    if ($timed_out) {
        kill 'KILL', $pid;
    }

    waitpid($pid, 0);
    my $status = $?;

    seek $errfh, 0, 0;
    my $stderr = do { local $/; <$errfh> } // '';
    close $errfh;

    return (render($output), $status, $stderr, $timed_out);
}

# Render the byte stream the way a simple terminal would show it, so tests
# assert on what the user sees rather than on line-editor redraw bytes:
# \b moves left, characters overwrite, \r returns to column 0, \a is
# dropped, and trailing spaces on each line are removed.
sub render ($) {
    my $raw = shift;
    my @lines = ('');
    my $col = 0;

    for my $ch (split //, $raw) {
        if ($ch eq "\n") {
            push @lines, '';
            $col = 0;

        } elsif ($ch eq "\r") {
            $col = 0;

        } elsif ($ch eq "\b") {
            $col-- if $col > 0;

        } elsif ($ch ne "\a") {
            my $line = \$lines[-1];
            $$line .= ' ' x ($col - length $$line) if $col > length $$line;
            substr($$line, $col, 1) = $ch;
            $col++;
        }
    }

    s/ +\z// for @lines;

    return join "\n", @lines;
}

sub run_block ($) {
    my $block = shift;

    my @args = driver_args($block);
    my $input = encode_input(scalar $block->input);
    my $timeout = (section($block, 'timeout') // 10) * $TimeoutScale;

    my ($output, $status, $stderr, $timed_out)
        = run_session(\@args, $input, $timeout);

    my $diag = "driver: $Driver @args\n--- output\n$output"
               . (length $stderr ? "\n--- stderr\n$stderr" : '');

    Test::More::ok(!$timed_out, "finished within ${timeout}s")
        or Test::More::diag($diag);

    Test::More::is($status & 127, 0, 'driver not killed by a signal')
        or Test::More::diag($diag);

    Test::More::unlike($stderr,
        qr/ERROR: AddressSanitizer|runtime error:|ERROR: LeakSanitizer|
           Invalid\ (?:read|write)|uninitialised|
           Mismatched\ free|definitely\ lost/x,
        'no sanitizer or valgrind reports') or Test::More::diag($diag);

    Test::More::is($status >> 8, section($block, 'exit_code') // 0,
        'driver exit code') or Test::More::diag($diag);

    my $expected = section($block, 'output');
    if (defined $expected) {
        (my $got = $output) =~ s/\s+\z//;
        Test::More::is($got, $expected, 'output')
            or Test::More::diag($diag);
    }

    for my $re (regex_lines(section($block, 'output_like'))) {
        Test::More::like($output, qr/$re/ms, "output matches /$re/")
            or Test::More::diag($diag);
    }

    for my $re (regex_lines(section($block, 'output_unlike'))) {
        Test::More::unlike($output, qr/$re/ms, "output lacks /$re/")
            or Test::More::diag($diag);
    }
}

sub regex_lines ($) {
    my $text = shift;

    return () if !defined $text;
    return grep { length } split /\n/, $text;
}

1;
