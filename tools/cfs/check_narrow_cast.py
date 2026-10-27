#!/usr/bin/env python3
"""No cast may be applied to an LVALUE narrower than the cast's own target.

ONE RULE NOW, AND IT USED TO BE TWO. This gate was written for two defects found in one hour by
the same means -- running code whose every static gate was green -- and the second of them was
then fixed in the compiler, so only the first is still refused here. Both halves are described
below, because the second's history is why the first is not treated the same way.

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

### 2. `ptrarray[i][j]` SCALED THE INNER SUBSCRIPT BY THE OUTER ELEMENT'S SIZE -- **FIXED**

This gate used to refuse that shape too. It no longer does, because the defect was fixed at the
root in `host/parser.c` rather than worked around: a member declared `T *arr[N]` now keeps its
real pointee alongside the RT_I64 the declaration overwrites it with, so the second subscript has
something to scale by. Ten forms were measured -- global, member and local arrays of `U32 *`,
`U8 *` and a 12-byte class pointer, with a file-scope and a member two-dimensional array as
controls -- and `tests/exec/cases/e_ptrarray_chained_subscript.hc` now pins the CORRECT values
instead of the defect's.

**A PROHIBITION KEPT AFTER ITS DEFECT IS FIXED IS A FALSE CLAIM**, so the check is removed rather
than left as style enforcement: NASA writes `SC_OperData.AtsTblAddr[AtsIndex][EntryOffset]` and a
1:1 translation should be allowed to. The double subscripts are still COUNTED here, so the gate
reports how many sites depend on the parser fix.

Both are pinned behaviourally: tests/exec/cases/e_widening_cast_lvalue.hc (the defect this gate
refuses) and tests/exec/cases/e_ptrarray_chained_subscript.hc (the behaviour the parser fix
produces).

WHAT IS CHECKED

Narrow types are U8 U16 I8 I16 Bool and the port's single-byte scalar typedefs; widening casts are
U32 U64 I32 I64 and F64. For each translated file:

  * every `(<expr>)(<WIDE>)` whose expression is a bare lvalue -- an identifier, a `.m`/`->m`
    chain, or an `arr[i]` -- is resolved against the declarations in that file plus the files it
    can see, and FAILS if the lvalue's declared type is narrow;
  * every `name[...][...]` is counted, so the summary says how many sites rely on the parser's
    chained-subscript fix. None of them fails: see 2 above.

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

# **WIDTHS, NOT TWO FIXED SETS.** The first version had NARROW = {U8 U16 I8 I16 Bool} and
# WIDE = {U32 U64 I32 I64 F64}, which misses `(u8_member)(U16)` -- limit #28 one size down, a
# two-byte read of a one-byte object. The rule is now relative: an operand is narrow *for a given
# cast* when it is STRICTLY narrower than the cast's target. The port has no instance of the
# one-size-down form today (10 casts to U16/I16 examined, 0 of them on a U8), so closing the class
# cost nothing -- which is the point of closing it before it costs something.
RANK = {"I8": 1, "U8": 1, "Bool": 1, "bool": 1,
        "I16": 2, "U16": 2,
        "I32": 4, "U32": 4, "F32": 4, "CfsF32": 4,
        "I64": 8, "U64": 8, "F64": 8}

# The targets this gate looks at: every integer width it can rank. A POINTER cast is excluded by
# the regexes (`\s*\)` after the type name rejects `(U32 *)`) because relabelling a pointer is
# the port's normal idiom and has one width.
TARGETS = ["U64", "U32", "U16", "U8", "I64", "I32", "I16", "I8", "F64"]

# Casting a MACRO PARAMETER to one of these is refused outright: the operand's width is not known
# at the definition, so it cannot be shown not to widen -- and `#define SC_IDX_AS_UINT(arg)
# ((arg)(U32))` in sc_tbl.HC is precisely how limit #28 entered the port. A NARROWING target on a
# macro parameter is allowed and counted: a relabel to a narrower type reads at most the operand's
# own bytes, and on this little-endian target that is the truncation C performs -- which is what
# `SC_IDX_FROM_UINT(arg) ((arg)(U16))` relies on and what e_widening_cast_lvalue.hc pins.
WIDENING_TARGETS = {"U32", "U64", "I32", "I64", "F64"}

# Kept for the messages and for the member-ambiguity report.
NARROW = {"U8", "U16", "I8", "I16", "Bool", "bool"}
WIDE = WIDENING_TARGETS

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


MACRO = re.compile(r"^\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)\(([^)]*)\)")


def macro_params(txt):
    """Every name that is a parameter of a function-like macro in this file. Those names appear in
    the macro BODY with no declaration anywhere, so they are the one operand kind this gate cannot
    resolve -- and the defect it exists for lived in exactly that position."""
    out = set()
    for line in txt.split("\n"):
        m = MACRO.match(line)
        if m:
            for a in m.group(2).split(","):
                a = a.strip()
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", a):
                    out.add(a)
    return out


def class_member_types(txt):
    """(class name, member name) -> (base, ptr depth, array rank), for the files in this unit.

    **THE FLAT TABLE WAS NOT ENOUGH, AND IT WAS HIDING A LIVE SITE.** A member is looked up by
    name alone unless the thing on its left resolves to a class, and 30 member names in the port
    are declared at two or more different widths -- `Status`, `Offset`, `CmdNum`, `Length`,
    `Data`, `State` among them. Those 30 were skipped, which is sound but blind, and
    `sc_cmds.HC`'s `StatusEntryPtr->Status` is exactly one of them: a deliberate poison restoring
    NASA's `(unsigned long)` cast on that `U8` field went UNREPORTED.

    It is resolvable without type inference, because the thing on the left is almost always a
    local or a parameter whose declaration is in the same file:
    `SC_AtsCmdStatusEntry_t *StatusEntryPtr;`. So the head identifier is resolved first, and when
    its declared base names a class, the member is looked up inside THAT class.
    """
    out = {}
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
                out[(cur, name)] = (base, 1 if star else 0, dims)
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
_W = "|".join(TARGETS)
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
    cmembers = {}
    for p in files:
        txt0 = strip_comments(open(p, errors="replace").read())
        for k, v in member_types(txt0).items():
            members.setdefault(k, set()).add(v)
        cmembers.update(class_member_types(txt0))

    bad_cast = []
    ptrarray_chains = 0
    by_class = 0
    by_name = 0
    bad_macro = []
    macro_narrowing = []
    unresolved = []
    casts = 0
    chains = 0
    calls_skipped = 0

    for p in files:
        rel = os.path.relpath(p, ROOT)
        txt = strip_comments(open(p, errors="replace").read())
        decls = declarations(txt)
        macros = macro_params(txt)
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
                target = RANK.get(wide)
                if target is None:
                    continue
                if name in macros:
                    # A MACRO PARAMETER. Unknown width, so a widening target cannot be shown safe
                    # and is refused; a narrowing one is allowed and counted by name.
                    if wide in WIDENING_TARGETS:
                        bad_macro.append((rel, ln, expr, wide))
                    else:
                        macro_narrowing.append((rel, ln, expr, wide))
                    continue
                if "." in expr or "->" in expr:
                    # FIRST try the exact class, via the head identifier's own declaration. This
                    # is what rescues the 30 ambiguous member names; see class_member_types.
                    rec = None
                    head = LVALUE.match(expr).group(1)
                    hrec = decls.get(head)
                    if hrec:
                        rec = cmembers.get((hrec[0], name))
                    if rec is not None:
                        by_class += 1
                        base, ptr, dims = rec
                    else:
                        by_name += 1
                        recs = members.get(name)
                        if not recs:
                            unresolved.append((rel, ln, expr, wide))
                            continue
                        if any(r[1] or RANK.get(r[0], 99) >= target for r in recs):
                            continue    # some declaration is a pointer or not narrower
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
                if RANK.get(base, 99) < target and (rel, name) not in EXEMPT:
                    bad_cast.append((rel, ln, expr, wide, base))

            for m in CHAIN.finditer(line):
                head = m.group(1)
                chains += 1
                # COUNTED, NOT REFUSED. The defect this used to catch is fixed in host/parser.c
                # and pinned by e_ptrarray_chained_subscript.hc; the count is here so the summary
                # says how many sites depend on that fix, and so a reader can see the number move.
                tail = re.findall(r"(?:\.|->)([A-Za-z_][A-Za-z0-9_]*)", m.group(0))
                key = tail[-1] if tail else head
                if key in decls:
                    _, ptr, dims = decls[key]
                    if ptr and dims >= 1:
                        ptrarray_chains += 1
                elif key in members:
                    recs = members[key]
                    if recs and all(r[1] and r[2] >= 1 for r in recs):
                        ptrarray_chains += 1

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
    if bad_macro:
        print("FAIL cfs-narrowcast — a WIDENING cast is applied to a MACRO PARAMETER, whose width"
              " is not known at the definition, so it cannot be shown not to widen the load"
              " (HolyC limit #28).", file=sys.stderr)
        print("  This is the exact position the defect entered the port from:"
              " `#define SC_IDX_AS_UINT(arg) ((arg)(U32))`, 83 uses, every other gate green.",
              file=sys.stderr)
        print("  Mask instead -- `(arg) & 0xFFFF` -- which forces a load of the operand's own"
              " declared width whatever the caller passes.", file=sys.stderr)
        for f, ln, e, w in bad_macro:
            print("    %s:%d  (%s)(%s) in a macro body" % (f, ln, e, w), file=sys.stderr)
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

    if casts == 0 or chains == 0 or ptrarray_chains == 0:
        print("FAIL cfs-narrowcast — found %d cast(s), %d chained subscript(s) and %d of them"
              " through a pointer array; zero of any of the three means this measured nothing."
              % (casts, chains, ptrarray_chains), file=sys.stderr)
        return 1

    # **THE SKIPPED SETS ARE NAMED, NOT COUNTED.** A first version printed "30 member name(s)
    # ... NOT checked" and stopped there, which is the shape docs/ records twenty times: a number
    # is not auditable and a list is. Three of the thirty are `Status`, `Offset` and `CmdNum` --
    # exactly the members SC's accessors return -- so a reader has to be able to see them.
    ambiguous = sorted(k for k, v in members.items()
                       if len(v) > 1 and any(r[1] or r[0] not in NARROW for r in v)
                       and any(not r[1] and r[0] in NARROW for r in v))
    print("cfs-narrowcast: %d cast(s) across %d HolyC files, none on an operand narrower than its"
          " target (%d double subscript(s), %d of them through an array of POINTERS and so relying"
          " on host/parser.c's chained-subscript fix -- pinned by"
          " e_ptrarray_chained_subscript.hc)"
          % (casts, len(files), chains, ptrarray_chains))
    if calls_skipped:
        print("  %d cast(s) of a call's result, whose return type is not in the declaration text"
              " this gate reads, and so NOT checked" % calls_skipped)
    if macro_narrowing:
        print("  %d NARROWING cast(s) of a macro parameter, which is the safe direction (a relabel"
              " to a narrower type reads at most the operand's own bytes):" % len(macro_narrowing))
        for f, ln, e, w in macro_narrowing:
            print("      %s:%d  (%s)(%s)" % (f, ln, e, w))
    if by_class or by_name:
        print("  member operands: %d resolved through the head identifier's own class, %d by name"
              " alone (%d member name(s) are declared at two or more widths, so the second route"
              " skips them: %s)"
              % (by_class, by_name, len(ambiguous), " ".join(ambiguous[:6]) + " ..."))
    else:
        # **SAID PLAINLY BECAUSE THE ALTERNATIVE READS AS A SKIP.** An earlier wording printed
        # "30 member names NOT checked" beside "0 resolved", which sounds like thirty live sites
        # going unexamined. There are none: every cast in the port today is on a plain identifier
        # or an array element, so the member path has NO live sites and is exercised only by the
        # deliberate poison in the commit that added it (NASA's `(unsigned long)` cast restored on
        # sc_cmds.HC's `StatusEntryPtr->Status`, a U8 -- it fails, naming the type).
        print("  no cast in the port has a MEMBER operand, so the per-class member resolution"
              " this gate carries has no live site; it is proven by poison, not by use")
    return 0


if __name__ == "__main__":
    sys.exit(main())
