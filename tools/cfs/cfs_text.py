#!/usr/bin/env python3
"""ONE strip_comments, because four copies had three bugs between them.

WHAT WENT WRONG, and it is the best argument in this directory for sharing a function. Four
gates each carried their own comment stripper, and three of them removed BLOCK comments first:

    re.sub(r'/\\*.*?\\*/', ..., flags=re.S)        # first
    re.sub(r'//[^\\n]*',   ..., )                  # second

That order makes a `/*` INSIDE A LINE COMMENT a real block-comment opener. The cFS differential
driver has had `// Kernel/Cfs/**.HC and nothing else` at line 562 since the kernel-include note
was written, and `Kernel/Cfs/**.HC` contains `/*`. It was harmless for months for one reason
only: there was no `*/` anywhere after it in the file.

Then an exercise added `mmc_c.Wid.Payload.Crc = 0; /* deliberately wrong */` six thousand lines
later, the stale `/*` paired with that `*/`, and everything between became whitespace.
check_variadic went from 177 declarations in that file to 36 -- and reported 1850 agreements
instead of 1933 AND STILL PASSED, because its property is "no declaration DISAGREES with NASA"
and a declaration it cannot see cannot disagree. The only visible symptom was a count going
DOWN, which is the thing this project has learned to chase.

THE FIX IS ONE PASS WITH AN ALTERNATION, so whichever opener comes first in the text wins:

    re.sub(r'//[^\\n]*|/\\*.*?\\*/', blank, txt, flags=re.S)

`re.sub` scans left to right and tries the alternatives in order at each position, so a `//`
comment is consumed whole -- including any `/*` inside it -- before a block comment can start.

NEWLINES ARE PRESERVED AND EVERYTHING ELSE BECOMES A SPACE. That is a superset of what the four
callers needed: check_struct_copy requires line numbers to survive (its docstring records a
finding reported at line 571 that was really at 735), and check_variadic counts newlines to turn
an offset into a line. Collapsing a comment to a single space breaks both.

THIS IS STILL NOT A LEXER. A `//` inside a string literal is blanked, and so is a `/*`. No gate
here is affected -- they strip strings separately where it matters -- but it is a property to
know rather than to discover.
"""
import re

_COMMENT = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)


def _blank(m):
    return re.sub(r'[^\n]', ' ', m.group(0))


def strip_comments(txt):
    """Comments out, line numbers and offsets intact."""
    return _COMMENT.sub(_blank, txt)


if __name__ == "__main__":
    # The driven control, because a stripper that silently eats code is the shape above.
    bad = 0
    # 1. a `/*` inside a line comment must NOT open a block comment
    t = "// see Kernel/Cfs/**.HC\nI64 keep_me(void);\nx = 0; /* real */\nI64 also(void);\n"
    out = strip_comments(t)
    for name in ("keep_me", "also"):
        if name not in out:
            print("FAIL cfs-text — %s was eaten by a /* inside a // comment" % name)
            bad = 1
    if "real" in out:
        print("FAIL cfs-text — a genuine block comment survived")
        bad = 1
    # 2. line numbers must not move
    if out.count("\n") != t.count("\n"):
        print("FAIL cfs-text — the newline count changed, so every line number after a comment"
              " would be wrong")
        bad = 1
    # 3. a multi-line block comment keeps its newlines
    t2 = "a;\n/* one\n   two */\nb;\n"
    if strip_comments(t2).count("\n") != t2.count("\n"):
        print("FAIL cfs-text — a multi-line block comment did not keep its newlines")
        bad = 1
    if not bad:
        print("cfs-text: strip_comments keeps line numbers, and a /* inside a // comment does"
              " not open a block comment (3 properties)")
    raise SystemExit(bad)
