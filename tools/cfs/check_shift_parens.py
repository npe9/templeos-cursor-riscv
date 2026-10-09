#!/usr/bin/env python3
"""No shift operand may be ambiguous between C's precedence and HolyC's.

WHY THIS EXISTS. `<<` and `>>` sit in OPPOSITE places in the two precedence tables.

  C       `*` `/` `%` bind tighter than `<<`, and `+` `-` bind tighter than `<<`,
          and `&` `|` `^` bind LOOSER.
  HolyC   **`<<` and `>>` are the TIGHTEST binary level there is** -- tighter than `*` and `/`,
          far tighter than `+` and `&`. host/parser.c:2729 says so in ParseExp's own comment,
          citing TempleOS's Compiler/CInit.HC binary_ops.

So one line of text means two different things:

                            C reads it as        HolyC reads it as
    1 << i % 32             1 << (i % 32)        (1 << i) % 32
    a + b << c              (a + b) << c         a + (b << c)
    x << n * 2              x << (n * 2)         (x << n) * 2

HOW IT BIT. NASA's HS_AppMonStatusRefresh writes

    HS_AppData.AppMonEnables[i / 32] |= (1 << (i % 32));

and the inner parentheses are redundant in C. I removed them as noise. For i = 0 both readings
give 1 -- which is every index an exercise naturally drives first -- and for i = 31 the C reading
is 0x80000000 while the HolyC reading is 0x80000000 % 32 = **0**, so the monitor was silently
never enabled. The same drop had been made in the matching clear in hs_monitors.c. It surfaced
only because HS's exercise drives monitor 31 deliberately, and then as a one-line transcript
divergence that could as easily have been read as a shift-codegen bug.

WHAT IS CHECKED. For every `<<` and `>>` in a translated source, BOTH operands must be
unambiguous: an atom, optionally with unary operators and postfix `[...]`, `(...)`, `.m`, `->m`,
and NOT adjacent to any binary operator at the same parenthesis depth. A chain of shifts
(`a << b << c`) is fine -- same operator, same associativity in both languages.

The rule is syntactic and deliberately stricter than necessary: `(a + b) << c` passes and
`a + b << c` fails even though a reader could work out which was meant. The point is that NOBODY
has to work it out, and that the port cannot accumulate a second instance.

WHAT IT DOES NOT COVER. The roots are HCDIRS -- the TRANSLATION under Kernel/Cfs. The two HolyC
DRIVER files (tests/exec/cases/*.hc) are HolyC too, contain shifts, and are NOT checked. That is a
real gap rather than a safe exclusion: a shift written the wrong way in a driver would diverge from
its C twin exactly as one in the translation would. It is left out because the drivers are test
code whose every line is already compared character for character against the C half by the
transcript, so the failure mode there is a DIVERGENCE and not a silent wrong answer -- which is the
opposite of the translation, where both halves can be wrong together only if the C is wrong too.
Widening the roots is one line if that reasoning ever stops holding.

This does NOT check the C side. NASA's sources are compiled by a C compiler and mean what C
says; it is only the translation that can be misread. check_strings and check_members compare the
two sides' text and neither can see an operator precedence.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# EXACTLY THE OPERATORS WHOSE ORDER RELATIVE TO `<<` DIFFERS BETWEEN THE TWO LANGUAGES, which
# is a shorter list than it first looks and the difference matters:
#
#   C (tight -> loose)      unary  >  * / %  >  + -  >  << >>  >  rel  >  eq  >  &  >  ^  >  |
#   HolyC                   unary  >  << >>  >  * /  >  + -  >  ...  &  ^  |  ...
#
#   * / % + -     C puts them TIGHTER than `<<`; HolyC puts `<<` tighter.   **ORDER DIFFERS**
#   & ^ |         looser than `<<` in BOTH.                                 same order
#   rel / eq      looser than `<<` in BOTH.                                 same order
#
# So `a << b | c` is `(a<<b) | c` in both and needs no parentheses, and the first version of this
# gate reported `(Word[0] << 8 | Word[1]) & Mask` in cfe_msg_ccsdspri.HC as a hazard. It is not
# one. A gate that cries wolf on correct code gets an exemption list instead of a fix, which is
# the failure mode docs/ records for check_defines' first version -- so the list is narrowed to
# the five that genuinely invert rather than exempting the site.
RISKY = ["*", "/", "%", "+", "-"]

IDENT = re.compile(r"[A-Za-z_]\w*|0[xX][0-9A-Fa-f]+|\d+")


def strip(src):
    """Remove comments and string/char literals, keeping the line structure."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2
        elif c in "\"'":
            q = c
            out.append(" ")
            i += 1
            while i < n and src[i] != q:
                if src[i] == "\\":
                    i += 1
                i += 1
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def skip_ws_back(s, i):
    while i >= 0 and s[i] in " \t\n":
        i -= 1
    return i


def skip_ws_fwd(s, i):
    while i < len(s) and s[i] in " \t\n":
        i += 1
    return i


def atom_end(s, i):
    """Consume one atom starting at i (already past whitespace); return the index after it,
    or -1 if there is no atom (which means the expression is malformed or we are at a bound)."""
    n = len(s)
    # unary operators and HolyC's postfix-cast-free prefix forms
    while i < n and s[i] in "~!-+&*":
        i += 1
        i = skip_ws_fwd(s, i)
    if i >= n:
        return -1
    if s[i] == "(":
        depth = 0
        while i < n:
            if s[i] == "(":
                depth += 1
            elif s[i] == ")":
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
    else:
        m = IDENT.match(s, i)
        if not m:
            return -1
        i = m.end()
    # postfix chain: [..] (..) .m ->m
    while True:
        j = skip_ws_fwd(s, i)
        if j < n and s[j] in "([":
            close = ")" if s[j] == "(" else "]"
            opn = s[j]
            depth = 0
            k = j
            while k < n:
                if s[k] == opn:
                    depth += 1
                elif s[k] == close:
                    depth -= 1
                    if depth == 0:
                        k += 1
                        break
                k += 1
            i = k
            continue
        if j + 1 < n and s[j] == "-" and s[j + 1] == ">":
            j = skip_ws_fwd(s, j + 2)
            m = IDENT.match(s, j)
            if not m:
                return i
            i = m.end()
            continue
        if j < n and s[j] == "." and not (j + 1 < n and s[j + 1].isdigit()):
            j = skip_ws_fwd(s, j + 1)
            m = IDENT.match(s, j)
            if not m:
                return i
            i = m.end()
            continue
        return i


def atom_start(s, i):
    """Consume one atom ENDING at i (inclusive, already past whitespace); return its start index,
    or -1 if there is none."""
    if i < 0:
        return -1
    if s[i] in ")]":
        opn = "(" if s[i] == ")" else "["
        close = s[i]
        depth = 0
        while i >= 0:
            if s[i] == close:
                depth += 1
            elif s[i] == opn:
                depth -= 1
                if depth == 0:
                    break
            i -= 1
        if i < 0:
            return -1
        # a parenthesised group may itself be the callee/index of something further left, which
        # does not matter: either way it is ONE atom and the token before it is what we want.
        j = skip_ws_back(s, i - 1)
        m = None
        k = j
        while k >= 0 and (s[k].isalnum() or s[k] == "_"):
            k -= 1
        if k < j:
            return k + 1
        return i
    k = i
    while k >= 0 and (s[k].isalnum() or s[k] == "_"):
        k -= 1
    if k == i:
        return -1
    start = k + 1
    # walk back over a member chain
    while True:
        j = skip_ws_back(s, start - 1)
        if j >= 1 and s[j] == ">" and s[j - 1] == "-":
            j2 = skip_ws_back(s, j - 2)
        elif j >= 0 and s[j] == ".":
            j2 = skip_ws_back(s, j - 1)
        else:
            return start
        if j2 < 0:
            return start
        s2 = atom_start(s, j2)
        if s2 < 0:
            return start
        start = s2


def op_at(s, i):
    """If a RISKY binary operator ends at i (scanning backwards) or starts at i (forwards is the
    caller's business), return its text. Checked longest-first so `<=` beats `<`."""
    for o in sorted(RISKY, key=len, reverse=True):
        if s.startswith(o, i):
            return o
    return None


def op_ending_at(s, i):
    for o in sorted(RISKY, key=len, reverse=True):
        j = i - len(o) + 1
        if j >= 0 and s.startswith(o, j):
            return o
    return None


def check(path):
    src = strip(open(path, errors="replace").read())
    bad = []
    for m in re.finditer(r"<<|>>", src):
        a, b = m.start(), m.end()
        line = src.count("\n", 0, a) + 1

        # ---- the RIGHT operand
        i = skip_ws_fwd(src, b)
        e = atom_end(src, i)
        if e > 0:
            j = skip_ws_fwd(src, e)
            if j < len(src):
                o = op_at(src, j)
                # `a >> b` followed by `>>` is a chain, and `->` is a member arrow the atom
                # scanner already consumed; neither is a hazard.
                if o and not src.startswith("<<", j) and not src.startswith(">>", j) \
                        and not src.startswith("->", j):
                    bad.append((line, "right", o))

        # ---- the LEFT operand
        i = skip_ws_back(src, a - 1)
        st = atom_start(src, i)
        if st > 0:
            j = skip_ws_back(src, st - 1)
            if j >= 0:
                o = op_ending_at(src, j)
                if o and not src.endswith("<<", 0, j + 1) and not src.endswith(">>", 0, j + 1):
                    # A UNARY operator is not a hazard: `~(1 << x)` and `-x >> 2` are
                    # unambiguous. The tell is what comes before the operator -- an operand means
                    # it is binary, an operator or an opening bracket means it is unary.
                    k = skip_ws_back(src, j - len(o))
                    if k >= 0 and (src[k].isalnum() or src[k] in "_)]"):
                        bad.append((line, "left", o))
    return bad


def main():
    files = 0
    shifts = 0
    bad = []
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".HC"):
                continue
            p = os.path.join(d, f)
            files += 1
            shifts += len(re.findall(r"<<|>>", strip(open(p, errors="replace").read())))
            for line, side, o in check(p):
                bad.append((os.path.relpath(p, ROOT), line, side, o))

    if bad:
        print("FAIL cfs-shiftparens — a shift operand means one thing in C and another in HolyC.",
              file=sys.stderr)
        print("  In C, `*` `/` `%` `+` `-` bind TIGHTER than `<<`; in HolyC `<<` is the TIGHTEST",
              file=sys.stderr)
        print("  binary level there is (host/parser.c:2729). Parenthesise the operand -- which is",
              file=sys.stderr)
        print("  usually restoring parentheses NASA already had.", file=sys.stderr)
        for f, line, side, o in bad:
            print("    %s:%d  %s operand is adjacent to `%s`" % (f, line, side, o), file=sys.stderr)
        return 1

    if shifts == 0:
        print("FAIL cfs-shiftparens — found NO shift operators at all, so this compared nothing.",
              file=sys.stderr)
        return 1

    print("cfs-shiftparens: %d shift operators across %d translated files have unambiguous "
          "operands (C and HolyC put `<<` on opposite sides of `*` `/` `%%` `+` `-`)"
          % (shifts, files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
