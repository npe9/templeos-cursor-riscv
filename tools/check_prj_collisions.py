#!/usr/bin/env python3
"""Two bodies for one function name in Kernel_RV.PRJ — find them before the image does.

"It compiles clean" does NOT mean "it is safe to add". The duplicate-global check in host/parser.c
catches a same-name global with a different TYPE; nothing catches two definitions of one FUNCTION,
and the second body wins silently. Adding Adam/ARegistry.HC looked clean and would have replaced
Kernel/RVRegistry.HC's RegDft/RegExe/RegWrite — the port's own in-memory registry, gone, with no
diagnostic. Adam/ASnd.HC would have replaced Adam/ASnd_RV.HC's Play/Beat/MusicSet*.

    tools/check_prj_collisions.py                 # the files the PRJ compiles, against each other
    tools/check_prj_collisions.py Adam/Gr/GrDC.HC # …and what a candidate would collide with

Two things it has to get right to be useful:

  * the PRJ is full of `#ifdef RV_THIN_LOADER` / `#else` pairs, and the two branches are never
    compiled together — KThinKeyDevStubs.HC and KeyDev.HC both define PutS by design. The default
    build takes the #else side; -D names a symbol to treat as defined instead.
  * a prototype is not a definition. `public extern U0 Foo(...);` and a forward declaration inside
    another unit both match a naive regex; only a header that does NOT end in ';' is a body.

Exit status is 1 when there is a collision, so it works as a gate.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
HEAD = re.compile(r"^(?:public\s+)?[A-Za-z_][A-Za-z0-9_]*\s*\**\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def prj_files(defined, exclude=()):
    """The files Kernel_RV.PRJ compiles under `defined`, honouring #ifdef/#ifndef/#else/#endif."""
    out, stack = [], []           # stack of "is this branch live"
    prj = (ROOT / "Kernel" / "Kernel_RV.PRJ").read_text(errors="replace")
    for line in prj.split("\n"):
        s = line.strip()
        m = re.match(r"#(ifdef|ifndef)\s+([A-Za-z_][A-Za-z0-9_]*)", s)
        if m:
            live = (m.group(2) in defined) == (m.group(1) == "ifdef")
            stack.append(live)
            continue
        if s.startswith("#else"):
            if stack:
                stack[-1] = not stack[-1]
            continue
        if s.startswith("#endif"):
            if stack:
                stack.pop()
            continue
        if not all(stack):
            continue
        m = re.match(r'#include "([^"]+)"', s)
        if not m or m.group(1) in exclude:
            continue
        inc = m.group(1)
        for p in (ROOT / "Kernel" / (inc + ".HC"), ROOT / (inc.lstrip("/") + ".HC"),
                  ROOT / inc.lstrip("/")):
            if p.exists() and p.is_file():
                out.append(p)
                break
    return out


def defs(p):
    """Function names DEFINED here: a header at column 0 whose line does not end in ';'."""
    names = set()
    for line in p.read_text(errors="replace").split("\n"):
        m = HEAD.match(line)
        if not m:
            continue
        body = re.sub(r"//.*$", "", line).rstrip()
        if body.endswith(";"):
            continue                      # a prototype, or `extern U0 Foo(...);`
        names.add(m.group(1))
    return names


def main():
    args = [a for a in sys.argv[1:]]
    defined = {a[2:] for a in args if a.startswith("-D")}
    cands = [ROOT / a.lstrip("/") for a in args if not a.startswith("-D")]
    # A candidate may ALREADY be in the PRJ (you added it, then checked). Exclude it from the PRJ
    # scan under every spelling the PRJ uses: `/Adam/X.HC`, `Adam/X.HC`, and the bare `X` that
    # `#include "RVJob"` writes — otherwise the file collides with itself and the report says so
    # twice.
    exclude = set()
    for c in cands:
        rel = str(c.relative_to(ROOT))
        exclude |= {rel, "/" + rel, rel[:-3] if rel.endswith(".HC") else rel,
                    c.stem, "/" + c.stem}
    exclude = tuple(exclude)
    files = prj_files(defined, exclude)
    owner, bad = {}, []
    for p in files:
        rel = str(p.relative_to(ROOT))
        for n in defs(p):
            if n in owner and owner[n] != rel:
                bad.append((n, owner[n], rel))
            else:
                owner.setdefault(n, rel)
    for c in cands:
        rel = str(c.relative_to(ROOT))
        for n in sorted(defs(c)):
            if n in owner:
                bad.append((n, owner[n], rel))
    rels = {str(c.relative_to(ROOT)) for c in cands}
    from_cand = [x for x in bad if x[2] in rels]
    existing = [x for x in bad if x[2] not in rels]
    if existing:
        print("pre-existing in the PRJ (informational — the LATER body wins):")
        for n, a, b in sorted(existing):
            print("  %-26s %s  AND  %s" % (n, a, b))
    if cands:
        if from_cand:
            print("INTRODUCED by the candidate(s):")
            for n, a, b in sorted(from_cand):
                print("  %-26s %s  AND  %s" % (n, a, b))
            return 1
        print("candidate(s) add no collision (%d PRJ files scanned)" % len(files))
        # "No collision" is not the same as "safe to add". A file that is only `extern`
        # declarations adds NO bodies and, because the PRJ compiles with
        # OPTf_EXTERNS_TO_IMPORTS on, every name in it becomes an unresolved import that
        # bootstrap/holy_rt.h stubs to a function returning 0. Adam/AExts.HC is 89 externs and
        # zero bodies: adding it would make several demos COMPILE and then silently do nothing,
        # which is worse than the L0-FAIL it cures. See docs/ASM_PORTABILITY.md.
        warned = 0
        for c in cands:
            txt = (ROOT / c).read_text(errors="replace").splitlines()
            ext = sum(1 for l in txt if l.startswith("extern ") or l.startswith("public extern "))
            bodies = sum(1 for l in txt if l.startswith("}"))
            if ext and not bodies:
                if not warned:
                    print("")
                    print("WARNING — declarations only, so adding this defines NOTHING:")
                warned = 1
                print("  %-34s %d extern decl(s), 0 bodies -> %d phantom import slot(s)" % (c, ext, ext))
        if warned:
            print("  Each becomes a stub returning 0. Check tools/blob_imports.py after adding.")
        return 0
    # No candidate: this is a report, not a gate. Pre-existing duplicates are recorded above.
    if not existing:
        print("no collisions (%d PRJ files)" % len(files))
    return 0


sys.exit(main())
