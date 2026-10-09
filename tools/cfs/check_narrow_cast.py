#!/usr/bin/env python3
"""No widening cast may be applied to a narrow LVALUE, and no array of pointers may be
double-subscripted. Two defects, one gate, because they were found in one hour by the same means:
running code whose every static gate was green.

WHY THIS EXISTS

Both are shapes where the TEXT of the translation is faithful to NASA's C and the compiler does
something C does not. No gate that compares text, types, layouts or symbol tables can see either
one; `check_coverage`, `check_signatures`, `check_members`, `check_strings`, `check_padding`,
`check_structs` and `cfs-inblob` were all green with both of them in five gated SC sources.

### 1. A WIDENING CAST OF A NARROW LVALUE WIDENS THE LOAD

HolyC's cast is a postfix RELABEL. Relabelling an lvalue changes how many BYTES are read from its
address, so for a `U16` member whose neighbour holds 0xFFFF:

    (rec->Offset)(U32)    ==>  4294967295       # two U16 records read as one word
    rec->Offset & 0xFFFF  ==>  65535            # what C's (unsigned int) gives

A local is worse: its neighbour is whatever the frame put there, so the value is not merely wrong
but unpredictable from the source. Measured at 2155937791 for a 0xFFFF local.

HOW IT BIT. `sc_tbl.HC` translated NASA's `#define SC_IDX_AS_UINT(arg) ((unsigned int)(arg))` as
`((arg)(U32))` -- the obvious reading -- and the same for SC_IDNUM_AS_UINT. 83 uses between them.
It is invisible whenever the adjacent bytes are zero, which is most of the time, so the first
symptom was four consecutive `SC_ENTRY_OFFSET_INVALID` offsets printing 4294967295 against C's
65535.

### 2. `ptrarray[i][j]` SCALES THE INNER SUBSCRIPT BY THE OUTER ELEMENT'S SIZE

With `U32 *p32[2]` aimed at a `U32 store[16]`:

    p32[0][1]        ==>  (store[3] << 32) | store[2]    # stride 8, width 8
    q = p32[0]; q[1] ==>  store[1]                       # correct

Eight bytes, because an element of `p32` is a pointer. **A true two-dimensional array is fine**,
and the two shapes are spelled identically -- which is the whole difficulty, and the reason this
check has to resolve the declaration rather than pattern-match the use.

HOW IT BIT. Three `sc_global.HC` accessors wrote NASA's one-expression bodies literally. SC_LoadAts
then walked the ATS at twice the stride and reported 2 commands where C reported 4 -- a wrong
count three functions from the wrong stride.

Both are pinned behaviourally: tests/exec/cases/e_widening_cast_lvalue.hc and
tests/exec/cases/e_ptrarray_chained_subscript.hc.

WHAT IS CHECKED

Narrow types are U8 U16 I8 I16 Bool and the port's single-byte scalar typedefs; widening casts are
U32 U64 I32 I64 and F64. For each translated file:

  * every `(<expr>)(<WIDE>)` whose expression is a bare lvalue -- an identifier, a `.m`/`->m`
    chain, or an `arr[i]` -- is resolved against the declarations in that file plus the files it
    can see, and FAILS if the lvalue's declared type is narrow;
  * every `name[...][...]` is resolved, and FAILS if `name`'s declaration is a pointer ARRAY
    (`T *name[N]`) rather than a two-dimensional array (`T name[N][M]`).

WHAT IT CANNOT SEE, SAID PLAINLY

  * A cast of a FUNCTION CALL's result, `f(x)(U32)`, is not checked: the return type is not in the
    declaration text this gate reads. There are none in the port today and the count is printed.
  * A narrow lvalue reached through a POINTER whose target type is declared in another file is
    resolved only if that file is among the translated sources -- which all of them are, but a
    member of a class declared in a NASA header and not translated would be missed. The gate
    prints how many lvalues it could not resolve, and FAILS if that number is not zero, so a
    blind spot is a failure rather than a pass. That is the lesson from
    docs: "a gate that passes on what it cannot find".
  * Double subscripts inside the two HolyC DRIVER files are checked too, unlike check_shift_parens
    -- the driver is where `sc_ats_buf[i][j]` lives and it is a true 2-D array, so it belongs in
    the measured set rather than outside it.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import ROOT, HCDIRS
from cfs_text import strip_comments

NARROW = {"U8", "U16", "I8", "I16", "Bool", "bool"}
WIDE = {"U32", "U64", "I32", "I64", "F64"}

# The driver files. They are HolyC, they contain both shapes, and the 2-D arrays that back SC's
# exercise live there -- so they are in the set.
DRIVERS = [os.path.join(ROOT, "tests", "exec", "cases", "cfs_xlat_ccsdspri.hc"),
           os.path.join(ROOT, "tests", "exec", "cases", "osal_xlat_errors.hc")]

# Sites a human has looked at and signed off, with the reason. EMPTY, and that is deliberate:
# both defects were fixed rather than exempted. An entry here must say what makes the site safe,
# not that it is inconvenient.
EXEMPT = {}


def hc_files():
    out = []
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for root, _, names in os.walk(d):
            for n in sorted(names):
                if n.endswith(".HC"):
                    out.append(os.path.join(root, n))
    for d in DRIVERS:
        if os.path.exists(d):
            out.append(d)
    return out


# `T name[N];`  and  `T *name[N];`  and  `T name[N][M];`  at any indentation, member or global.
DECL = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(\*?)\s*([A-Za-z_][A-Za-z0-9_]*)\s*"
                  r"((?:\[[^\]]*\])*)\s*;")
# a scalar or pointer declaration without brackets
SCALAR = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(\*?)\s*([A-Za-z_][A-Za-z0-9_]*)\s*;")


# A declarator anywhere: a global, a local, a member, a PARAMETER, or one with an initialiser.
# The parameter case is why this is not just DECL/SCALAR: `U0 f(U16 *DataPointer16)` declares a
# POINTER, and a gate that cannot see it reports the cast of that pointer as unresolved -- which
# is how the first run of this gate produced thirteen "unresolved" lines that were all pointers.
ANYDECL = re.compile(r"(?:^|[(,]|\b)\s*([A-Za-z_][A-Za-z0-9_]*)\s+(\**)\s*"
                     r"([A-Za-z_][A-Za-z0-9_]*)\s*((?:\[[^\]]*\])*)\s*(?=[;,)=])")


def declarations(txt):
    """name -> (base type, pointer depth, array rank). Globals, locals, members and parameters all
    look the same here on purpose: the gate needs the TYPE, not the storage class.

    A name declared twice at different types keeps the WIDER reading, because this gate's job is
    to refuse a narrow one and a false pass is the failure mode that matters."""
    out = {}
    for line in txt.split("\n"):
        for m in ANYDECL.finditer(line):
            base, stars, name, brackets = m.groups()
            if base in ("return", "case", "else", "sizeof", "class", "union", "define"):
                continue
            dims = len(re.findall(r"\[[^\]]*\]", brackets or ""))
            rec = (base, len(stars), dims)
            if name in out and out[name] != rec:
                out[name] = ("?", 1, 0)     # ambiguous: treat as a pointer, i.e. not narrow
            else:
                out[name] = rec
    return out


def member_types(txt):
    """(class name, member name) -> base type, for resolving `x.m` and `p->m`. Flat across all
    classes: a member name is looked up by name alone, and a COLLISION between two classes with
    the same member name at different widths is reported rather than guessed."""
    out = {}
    collide = set()
    cur = None
    for line in txt.split("\n"):
        m = re.match(r"^\s*(?:class|union)\s+([A-Za-z_][A-Za-z0-9_]*)", line)
        if m:
            cur = m.group(1)
            continue
        if cur and line.strip() == "};":
            cur = None
            continue
        if cur:
            d = DECL.match(line) or SCALAR.match(line)
            if d:
                base, star, name = d.groups()[0], d.groups()[1], d.groups()[2]
                brackets = d.groups()[3] if len(d.groups()) > 3 else ""
                dims = len(re.findall(r"\[[^\]]*\]", brackets or ""))
                t = (base, 1 if star else 0, dims)
                if name in out and out[name] != t:
                    collide.add(name)
                out[name] = t
    for n in collide:
        out[n] = ("?", 1, 0)        # ambiguous: treated as a pointer, i.e. never flagged
    return out


# A postfix widening cast. TWO SPELLINGS, and the first version of this gate only had one:
# `(<expr>)(U32)` with the operand parenthesised, which found 12 sites, and `<lvalue>(U32)` with
# it bare, which is how the port actually writes them and found the other 150. A gate that matches
# the rarer spelling and reports a count is the shape docs/ calls "passes on what it cannot see";
# the count looked plausible, so the number is now printed per spelling.
#
# A POINTER cast is deliberately NOT matched: `\s*\)` after the type name excludes `(U32 *)`.
# Relabelling a pointer is the port's normal idiom and is not this defect -- the defect is reading
# a narrow OBJECT at a wider width.
_W = "|".join(sorted(WIDE))
CAST = re.compile(r"\(([^()]*)\)\s*\(\s*(" + _W + r")\s*\)")
CAST_BARE = re.compile(r"(?<![A-Za-z0-9_])((?:[A-Za-z_][A-Za-z0-9_]*)"
                       r"(?:(?:\.|->)[A-Za-z_][A-Za-z0-9_]*|\[[^\[\]]*\])*)"
                       r"\s*\(\s*(" + _W + r")\s*\)")
# `sizeof(U32)` is an identifier followed by a parenthesised type name and is not a cast.
NOT_A_CAST = {"sizeof", "offsetof", "return", "if", "while", "switch"}
# `name[...][...]` with no further subscript -- the chained form.
CHAIN = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*((?:\.|->)[A-Za-z_][A-Za-z0-9_]*)*"
                   r"\s*\[[^\[\]]*\]\s*\[")
# a bare lvalue: an identifier with optional `.m` / `->m` steps, or one `[i]`
LVALUE = re.compile(r"^\s*&?([A-Za-z_][A-Za-z0-9_]*)"
                    r"((?:(?:\.|->)[A-Za-z_][A-Za-z0-9_]*|\[[^\[\]]*\])*)\s*$")


def last_name(expr):
    """The name whose declared type decides the width: the LAST member of a `.`/`->` chain, or the
    identifier itself."""
    m = LVALUE.match(expr)
    if not m:
        return None
    head, rest = m.groups()
    steps = re.findall(r"(?:\.|->)([A-Za-z_][A-Za-z0-9_]*)", rest or "")
    return steps[-1] if steps else head


def main():
    files = hc_files()
    if not files:
        print("FAIL cfs-narrowcast — no translated files found, so this compared nothing.",
              file=sys.stderr)
        return 1

    # One flat member table over the whole translation: a member name is declared once at one
    # width in practice, and where it is not, member_types marks it '?' and this gate refuses.
    members = {}
    for p in files:
        for k, v in member_types(strip_comments(open(p, errors="replace").read())).items():
            members.setdefault(k, set()).add(v)

    bad_cast = []
    bad_chain = []
    unresolved = []
    casts = 0
    chains = 0
    calls_skipped = 0

    for p in files:
        rel = os.path.relpath(p, ROOT)
        txt = strip_comments(open(p, errors="replace").read())
        decls = declarations(txt)
        for ln, line in enumerate(txt.split("\n"), 1):
            seen_spans = []
            for m in list(CAST.finditer(line)) + list(CAST_BARE.finditer(line)):
                expr, wide = m.group(1), m.group(2)
                if m.end() in seen_spans:
                    continue        # the parenthesised form also matches the bare pattern
                seen_spans.append(m.end())
                if expr.strip() in NOT_A_CAST:
                    continue
                casts += 1
                if "(" in expr or ")" in expr:
                    continue
                # **`->` CONTAINS A MINUS SIGN.** The first version of this test read the raw
                # expression, so every `p->m(U32)` -- the single most common form of the defect,
                # and the one in sc_tbl.HC that started all this -- was skipped as "arithmetic".
                # The gate passed its own poison. The arrow is masked before the test.
                probe = expr.replace("->", "@")
                if re.search(r"[-+*/%&|^<>=!~]", probe):
                    continue        # an arithmetic expression is an rvalue; the relabel is safe
                name = last_name(expr)
                if name is None:
                    calls_skipped += 1
                    continue
                # **A MEMBER IS RESOLVED BY NAME, ACROSS EVERY CLASS IN THE PORT**, because
                # knowing which class a `->m` means needs the declared type of the thing on the
                # left, and that is real type inference. 81 member names are declared at two or
                # more different types, so a flat table that collapsed them to "ambiguous" left
                # those 81 unchecked -- and `Status`, `Offset` and `CmdNum` are all in that set.
                #
                # So the decision is made over the WHOLE SET of types the name is declared at:
                # narrow if EVERY declaration is narrow, skipped if ANY is wide or a pointer.
                # That cannot produce a false failure -- a flagged name is narrow whichever class
                # it came from -- and it leaves only the genuinely mixed names unchecked, which is
                # a far smaller set than "every name that appears twice".
                if "." in expr or "->" in expr:
                    recs = members.get(name)
                    if not recs:
                        unresolved.append((rel, ln, expr, wide))
                        continue
                    if any(r[1] or (r[0] not in NARROW) for r in recs):
                        continue        # at least one declaration is wide or a pointer
                    base, ptr, dims = sorted(recs)[0]
                else:
                    rec = decls.get(name)
                    if rec is None:
                        unresolved.append((rel, ln, expr, wide))
                        continue
                    base, ptr, dims = rec
                # A POINTER cast to U64 is an ADDRESS, not a narrow read. So is a BARE ARRAY NAME,
                # which decays to one -- `(cs_src_b)(U64)` on a `U8 cs_src_b[4096]` is the buffer's
                # address and the port uses it deliberately. Both were false positives on this
                # gate's first run, and both are excluded by the DECLARATION rather than by name.
                if ptr:
                    continue
                if dims and "[" not in expr:
                    continue
                if base in NARROW and (rel, name) not in EXEMPT:
                    bad_cast.append((rel, ln, expr, wide, base))

            for m in CHAIN.finditer(line):
                head = m.group(1)
                chains += 1
                tail = re.findall(r"(?:\.|->)([A-Za-z_][A-Za-z0-9_]*)", m.group(0))
                key = tail[-1] if tail else head
                if key in decls:
                    _, ptr, dims = decls[key]
                    if ptr and dims >= 1:
                        bad_chain.append((rel, ln, key))
                elif key in members:
                    # A MEMBER THAT IS AN ARRAY OF POINTERS, e.g. SC_OperData.AtsTblAddr[i][j].
                    # Flagged only when EVERY declaration of that member name is a pointer array,
                    # for the same reason the cast check uses the whole set.
                    recs = members[key]
                    if recs and all(r[1] and r[2] >= 1 for r in recs):
                        bad_chain.append((rel, ln, key))
                else:
                    unresolved.append((rel, ln, m.group(0), "chain"))

    rc = 0
    if bad_cast:
        print("FAIL cfs-narrowcast — a WIDENING cast is applied to a NARROW LVALUE, which in HolyC"
              " widens the LOAD rather than converting the value.", file=sys.stderr)
        print("  For a U16 member whose neighbour is non-zero, `(x)(U32)` reads FOUR bytes and"
              " returns both halves.", file=sys.stderr)
        print("  Use `x & 0xFFFF` (or `& 0xFF`), which forces a load of the declared width and is"
              " value-equivalent.", file=sys.stderr)
        print("  Pinned by tests/exec/cases/e_widening_cast_lvalue.hc.", file=sys.stderr)
        for f, ln, e, w, t in bad_cast:
            print("    %s:%d  (%s)(%s) where %s is %s" % (f, ln, e, w, e, t), file=sys.stderr)
        rc = 1
    if bad_chain:
        print("FAIL cfs-narrowcast — an ARRAY OF POINTERS is double-subscripted. HolyC scales the"
              " inner subscript by the size of an element of the OUTER array (8 bytes for a"
              " pointer), not by the pointee.", file=sys.stderr)
        print("  Hoist the row into a local: `T *Row = x[i]; ... Row[j]`.", file=sys.stderr)
        print("  A true two-dimensional array is FINE and is spelled identically, which is why"
              " this gate resolves the declaration.", file=sys.stderr)
        print("  Pinned by tests/exec/cases/e_ptrarray_chained_subscript.hc.", file=sys.stderr)
        for f, ln, n in bad_chain:
            print("    %s:%d  %s[..][..]" % (f, ln, n), file=sys.stderr)
        rc = 1
    if unresolved:
        print("FAIL cfs-narrowcast — %d site(s) whose declaration this gate could not find. A gate"
              " that passes on what it cannot resolve is the shape docs/ records twenty times, so"
              " an unresolved site is a FAILURE." % len(unresolved), file=sys.stderr)
        for f, ln, e, w in unresolved[:20]:
            print("    %s:%d  %s  (%s)" % (f, ln, e, w), file=sys.stderr)
        rc = 1
    if rc:
        return rc

    if casts == 0 or chains == 0:
        print("FAIL cfs-narrowcast — found %d cast(s) and %d chained subscript(s); zero of either"
              " means this compared nothing." % (casts, chains), file=sys.stderr)
        return 1

    ambiguous = sum(1 for v in members.values()
                    if len(v) > 1 and any(r[1] or r[0] not in NARROW for r in v)
                    and any(not r[1] and r[0] in NARROW for r in v))
    print("cfs-narrowcast: %d widening cast(s) and %d double subscript(s) across %d HolyC files;"
          " no widening cast lands on a narrow lvalue and no pointer array is chained"
          " (%d cast(s) of a call's result not checked, %d member name(s) declared at two"
          " different types and so NOT checked -- see the header)"
          % (casts, chains, len(files), calls_skipped, ambiguous))
    return 0


if __name__ == "__main__":
    sys.exit(main())
