use lib 't/lib';
use Test::LibCLI;
run_tests();

__DATA__

=== TEST 1: a unique prefix completes to the full word
--- fixture: completion
--- input
neigh<TAB>adv<TAB>
--- output_like
^router> neighbor advertisement$
^RAN neighbor advertisement$



=== TEST 2: a common prefix is filled in, stopping where names differ
--- fixture: completion
--- input
inter<TAB>ether<TAB>
--- output_like
router> interface ether



=== TEST 3: double Tab lists the ambiguous completions
--- fixture: completion
--- input
interface ether<TAB><TAB>
--- output_like
ethernet
ethertype



=== TEST 4: '?' lists subcommands with help text
--- fixture: completion
--- input
interface ?
--- output_like
^  ethernet\s+Ethernet$
^  ethertype\s+Ethertype$



=== TEST 5: Tab on an empty command rings the bell, no crash
--- fixture: completion
--- input eval
"<TAB>\n"
--- output_unlike
RAN



=== TEST 6: validated argument accepts a valid value
--- fixture: validate
--- input
paint red
--- output_like
^RAN paint$
^OPTARG color=red$



=== TEST 7: validated argument rejects an invalid value
--- fixture: validate
--- input
paint mauve
--- output_like
Problem parsing command setting color with value mauve
--- output_unlike
^OPTARG color=mauve$



=== TEST 8: '?' after a validated argument name shows its help
--- fixture: validate
--- input
paint ?
--- output_like
<color>\s+A primary color



=== TEST 9: registering a duplicate optarg leaves a usable cli
--- fixture: dupoptarg
--- input
set hello
--- output_like
^RAN set$
^OPTARG name=hello$



=== TEST 10: Tab completion near the line-length limit does not overflow (KNOWN BUG libcli.c:1472)
--- SKIP
--- fixture: completion
--- input eval
"neighbor" . (" " x 4080) . "<TAB>\n"



=== TEST 11: a failed buildmode entry does not crash the cli (KNOWN BUG libcli.c:1781)
--- SKIP
--- fixture: buildmode
--- input
build go
ping
--- output_like
^RAN ping$
