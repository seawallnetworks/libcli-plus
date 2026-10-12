use lib 't/lib';
use Test::LibCLI;
run_tests();

__DATA__

=== TEST 1: run a subcommand without authentication
--- input
show counters
--- output_like
^router> show counters$
^RAN show counters$



=== TEST 2: abbreviated command words
--- input
sh co
--- output_like
^RAN show counters$



=== TEST 3: unknown command is rejected
--- input
bogus
--- output_like
^Invalid command "bogus"$
--- output_unlike
^RAN



=== TEST 4: required argument, optional flag and optional argument
--- input
set foo verbose count 3
--- output_like
^RAN set$
^OPTARG name=foo$
^OPTARG verbose=verbose$
^OPTARG count=3$



=== TEST 5: missing required argument
--- input
set
--- output_like
missing required argument 'name' for command 'set'
--- output_unlike
^RAN



=== TEST 6: login with a valid user, password not echoed
--- users
bob:s3cret
--- input
bob
s3cret
show version
--- output_like
^Username: bob$
Password:
^RAN show version$
--- output_unlike
s3cret
Access denied



=== TEST 7: login with a wrong password is denied
--- users
bob:s3cret
--- input
bob
wrong
--- output_like
Access denied
^Username:$
--- output_unlike
^router>



=== TEST 8: privileged command needs enable
--- input
reload
--- output_like
^Invalid command "reload"$
--- output_unlike
^RAN reload



=== TEST 9: enable with password, then run a privileged command
--- enable_password: letmein
--- input
enable
letmein
reload
--- output_like
^router# reload$
^RAN reload$
--- output_unlike
Access denied
letmein



=== TEST 10: enable with a wrong password is denied
--- enable_password: letmein
--- input
enable
nope
reload
--- output_like
Access denied
^Invalid command "reload"$



=== TEST 11: config mode changes the prompt and the hostname
--- input
enable
configure terminal
hostname edge1
exit
--- output_like
^router\(config\)# hostname edge1$
^edge1\(config\)# exit$
^edge1#$



=== TEST 12: include filter
--- input
show lines | include beta
--- output_like
^line 2: beta$
--- output_unlike
alpha
gamma



=== TEST 13: exclude filter
--- input
show lines | exclude beta
--- output_like
^line 1: alpha$
^line 3: gamma$
--- output_unlike
^line 2: beta$



=== TEST 14: count filter
--- input
show lines | count
--- output_like
^3$
--- output_unlike
^line



=== TEST 15: tab completes a unique subcommand
--- input
show cou<TAB>
--- output_like
^router> show counters$
^RAN show counters$



=== TEST 16: help lists subcommands
--- input
show ?
--- output_like
^  counters\s+Show counters$
^  version\s+Show version$



=== TEST 17: ctrl-u discards the line
--- input
bogus<CTRL-U>show version
--- output_like
^RAN show version$
--- output_unlike
Invalid command



=== TEST 18: up arrow recalls the previous command
--- input
show version
<UP>
--- output_like
RAN show version\n.*RAN show version



=== TEST 19: history lists earlier commands
--- input
show version
show counters
history
--- output_like
^Command history:$
^  0\. show version$
^  1\. show counters$



=== TEST 20: backspace edits the line
--- input eval
"show versionX\x7f\n"
--- output_like
^RAN show version$



=== TEST 21: a password may contain '?' (KNOWN BUG libcli.c:1544)
--- SKIP
--- users
bob:ab?
--- input
bob
ab?
show version
--- output_like
^RAN show version$
--- output_unlike
Access denied



=== TEST 22: editing a password mid-line does not corrupt it (KNOWN BUG libcli.c:1358)
--- SKIP
--- users
bob:ac
--- input eval
"bob\rabc\x1b[D\x7f\rshow version\r"
--- output_like
^RAN show version$
--- output_unlike
Access denied



=== TEST 23: exit is described as leaving the EXEC in exec mode
--- input
help
enable
configure terminal
help
--- output_like
^  exit\s+Exit from the EXEC$
^  exit\s+Exit from current mode$



=== TEST 24: '?' shows the same exit help as help
--- input
ex?
--- output_like
^  exit\s+Exit from the EXEC$
--- output_unlike
current mode
