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


def strip_comments_keep_strings(txt):
    """strip_comments, but a comment opener INSIDE a string literal is not one.

    THE SECOND STRIPPER EXISTS BECAUSE THE FIRST ONE'S DOCSTRING PREDICTED IT. The note above
    ends "a `//` inside a string literal is blanked, and so is a `/*`. No gate here is affected
    -- but it is a property to know rather than to discover." check_strings.py is the gate that
    is affected: string literals are its DATA, not something it strips separately, so a literal
    containing `//` would come back truncated and be reported as text NASA does not have.

    Nothing in the tree has such a literal today -- the twelve files that match `"[^"]*//` are
    all `#include "x.HC" // why`, where the comment is after the string. That is exactly the
    reason to use this rather than to rely on it: the first URL or the first "http://" in an
    event text would otherwise turn into a gate failure that looks like a translation defect.

    IT HANDLES `//` ONLY, AND THE ORDER THE CALLER USES IS THE REST OF THE ANSWER: remove block
    comments with a plain `/\\*.*?\\*/` pass first, then this one. The reverse order cannot work --
    a block comment may contain an apostrophe or a quote, which would unbalance the quote
    tracking for the rest of the file. Block comments are stripped by regex rather than here for
    the same reason the first stripper exists: a `/*` inside a string literal would then be a
    false opener, and the measured fact is that no literal in either tree contains one.

    Not a lexer either. It tracks double quotes and backslash escapes on a single line, which is
    what C and HolyC string literals are. A character literal holding a quote (`'"'`) would
    confuse it; neither NASA nor this translation has one.
    """
    out = []
    for line in txt.split("\n"):
        i = 0
        quoted = False
        cut = None
        while i < len(line):
            c = line[i]
            if quoted and c == "\\":
                i += 2
                continue
            if c == '"':
                quoted = not quoted
            elif not quoted and c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                cut = i
                break
            i += 1
        out.append(line if cut is None else line[:cut])
    return "\n".join(out)


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
    # 4. strip_comments_keep_strings must NOT cut inside a string literal, and the first
    #    stripper must -- the second control is what makes the first one mean anything.
    t3 = 'S("http://x"); // gone\nS("a\\"b // c"); keep;\n'
    out3 = strip_comments_keep_strings(t3)
    if "http://x" not in out3 or "a\\\"b // c" not in out3 or "gone" in out3 or "keep" not in out3:
        print("FAIL cfs-text — strip_comments_keep_strings mishandled a // inside a literal:"
              " %r" % out3)
        bad = 1
    if "http://x" in strip_comments(t3):
        print("FAIL cfs-text — strip_comments kept a // inside a literal, so the second"
              " stripper has no reason to exist and this control is vacuous")
        bad = 1
    if not bad:
        print("cfs-text: strip_comments keeps line numbers, and a /* inside a // comment does"
              " not open a block comment; strip_comments_keep_strings keeps a // inside a string"
              " literal where strip_comments does not (5 properties)")
    raise SystemExit(bad)
