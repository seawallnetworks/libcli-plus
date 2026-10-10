use lib 't/lib';
use Test::LibCLI;
run_tests();

__DATA__

=== TEST 1: ctrl-a jumps to start, ctrl-e to end
--- input eval
"show counters<CTRL-A>X<CTRL-E>\n"
--- output_like
^Invalid command "Xshow"$
--- output_unlike
^RAN show counters$



=== TEST 2: ctrl-b moves left so an inserted char lands mid-word
--- input eval
"shw<CTRL-B>o\n"
--- output_like
^router> show$
^Incomplete command$



=== TEST 3: ctrl-k kills to end of line
--- input eval
"show counters junk<CTRL-A><CTRL-E>\n"
--- output_like
counters



=== TEST 4: ctrl-w deletes the previous word
--- input eval
"show counters junk<CTRL-W>\n"
--- output_like
^RAN show counters$



=== TEST 5: backspace at an empty line rings the bell, no crash
--- input eval
"<DEL>show version\n"
--- output_like
^RAN show version$



=== TEST 6: ctrl-u then a fresh command
--- input eval
"nonsense here<CTRL-U>show version\n"
--- output_like
^RAN show version$
--- output_unlike
nonsense



=== TEST 7: insert a character in the middle of the line
--- input eval
"shw counters<CTRL-A><CTRL-F><CTRL-F>o\n"
--- output_like
^RAN show counters$



=== TEST 8: ctrl-z leaves config mode back to exec
--- input
enable
configure terminal
<CTRL-Z>
show version
--- output_like
^router# show version$
^RAN show version$



=== TEST 9: a very long line is truncated at the buffer limit, no crash
--- input eval
"show " . ("x" x 5000) . "\n"
--- output_like
Invalid command



=== TEST 10: control characters do not crash the editor
--- input eval
"\x01\x02\x05\x06show version\n"
--- output_like
^RAN show version$
