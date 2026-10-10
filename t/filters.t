use lib 't/lib';
use Test::LibCLI;
run_tests();

__DATA__

=== TEST 1: include keeps only matching lines
--- input
show lines | include beta
--- output_like
^line 2: beta$
--- output_unlike
alpha
gamma



=== TEST 2: exclude drops matching lines
--- input
show lines | exclude beta
--- output_like
^line 1: alpha$
^line 3: gamma$
--- output_unlike
^line 2: beta$



=== TEST 3: count reports the number of lines
--- input
show lines | count
--- output_like
^3$



=== TEST 4: begin starts at the first match
--- input
show lines | begin beta
--- output_like
^line 2: beta$
^line 3: gamma$
--- output_unlike
^line 1: alpha$



=== TEST 5: between bounds the output by two matches
--- input
show lines | between alpha gamma
--- output_like
^line 1: alpha$
^line 2: beta$
^line 3: gamma$



=== TEST 6: grep matches a regular expression
--- input
show lines | grep be.a
--- output_like
^line 2: beta$
--- output_unlike
alpha
gamma



=== TEST 7: grep -v inverts the match
--- input
show lines | grep -v beta
--- output_like
^line 1: alpha$
^line 3: gamma$
--- output_unlike
^line 2: beta$



=== TEST 8: grep -i matches case-insensitively
--- input
show lines | grep -i BETA
--- output_like
^line 2: beta$



=== TEST 9: egrep supports extended syntax
--- input
show lines | egrep "(alpha|gamma)"
--- output_like
^line 1: alpha$
^line 3: gamma$
--- output_unlike
^line 2: beta$



=== TEST 10: an invalid regex is reported, not crashed
--- input
show lines | egrep (
--- output_like
Invalid pattern
--- output_unlike
^line 1: alpha$



=== TEST 11: filters chain together
--- input
show lines | exclude alpha | include gamma
--- output_like
^line 3: gamma$
--- output_unlike
^line 1: alpha$
^line 2: beta$
