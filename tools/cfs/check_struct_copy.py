#!/usr/bin/env python3
"""No translated file copies a CLASS into an array slot or through a bare pointer.

THE DEFECT THIS REFUSES, measured in docs/HOLYC_STRUCT_LIMITS.md #21 and pinned by
tests/exec/cases/e_struct_copy_into_slot.hc: a struct assignment whose destination is `arr[i]`
or `*ptr` copies only the FIRST EIGHT BYTES. Silently -- no diagnostic, no refusal, and the
bytes past the first two words are left as they were. The same assignment to a plain variable,
to `var.member` or to `ptr->member` is whole, so it is the destination form that decides.

WHY A GATE AND NOT JUST A NOTE. The compiler already REFUSES the related case -- a class return
by value over eight bytes is a diagnostic -- so a reader has every reason to assume the
assignment is safe too. It is not, and the only instance in the tree was found by the
differential transcript: cfe_es_perf.c's capture path stored a twelve-byte log entry with
`Perf->DataBuffer[DataEnd] = EntryData` and the hardware timestamp never arrived. Every
performance log entry had a zero timestamp, which is the one thing a performance log is for.
Nothing else in the gate set could see it: the layout matches, the signatures match, the
function is in the blob. The defect is in the STORE.

HOW IT DECIDES WHAT IS A STRUCT. A destination of the dangerous shape is only a problem when
the thing being assigned is a CLASS. So the right-hand side has to be a bare lvalue whose
declared type is one of the classes the translation declares -- which this reads out of the
tree rather than listing. A scalar, a pointer or a call is not flagged: an 8-byte store covers
every scalar this port has.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HCROOT = os.path.join(ROOT, "Kernel", "Cfs")

# `arr[...] = x;` or `*p = x;` where x is a bare lvalue -- no operators, no call.
ASSIGN = re.compile(r'^\s*(\*[A-Za-z_]\w*|[A-Za-z_][\w.\[\]>-]*\[[^\]]*\])\s*=\s*'
                    r'([A-Za-z_][\w.>-]*)\s*;\s*$')
CLASS_DECL = re.compile(r'^\s*(?:class|union)\s+([A-Za-z_]\w*)', re.M)
# A local or global declaration: `SomeClass name;` or `SomeClass name[...]`
VAR_DECL = re.compile(r'^\s*([A-Z][A-Za-z0-9_]*)\s+([A-Za-z_]\w*)\s*(?:;|\[)', re.M)

# Sites verified SAFE, each with the reason. A struct of 8 bytes or less copies whole, so a
# small class is allowed here -- with its size stated, because the entry is a claim about it.
ALLOW = {}


def hc_files():
    out = []
    for root, _, fs in os.walk(HCROOT):
        for f in sorted(fs):
            if f.endswith(".HC"):
                out.append(os.path.join(root, f))
    return out


def main():
    files = hc_files()
    if not files:
        print("FAIL cfs-structcopy — no .HC files found under Kernel/Cfs; this gate would pass"
              " on an empty set, which is the shape it exists to refuse", file=sys.stderr)
        return 1

    classes = set()
    for p in files:
        classes |= set(CLASS_DECL.findall(open(p, errors="replace").read()))
    if not classes:
        print("FAIL cfs-structcopy — not one class was found in the translation, so nothing"
              " could be flagged", file=sys.stderr)
        return 1

    rc = 0
    checked = 0
    for p in files:
        rel = os.path.relpath(p, ROOT)
        text = open(p, errors="replace").read()
        # strip comments so a commented-out assignment cannot be flagged
        src = re.sub(r'//[^\n]*', '', text)
        # {name: its declared type} for every declaration in the file
        declared = {}
        for m in VAR_DECL.finditer(src):
            declared.setdefault(m.group(2), m.group(1))
        for i, line in enumerate(src.split("\n"), 1):
            m = ASSIGN.match(line)
            if not m:
                continue
            checked += 1
            rhs = m.group(2)
            base = re.split(r'[.\[>-]', rhs)[0]
            ty = declared.get(base)
            # Only a whole-struct copy matters: `x = s` where s IS the struct, not a member of
            # it. A member could be any type and this gate does not resolve member types.
            if ty is None or ty not in classes or rhs != base:
                continue
            key = "%s:%d" % (rel, i)
            if key in ALLOW:
                continue
            print("FAIL cfs-structcopy — %s copies a CLASS (%s) into an array slot or through"
                  % (key, ty), file=sys.stderr)
            print("  a bare pointer. That copies only the FIRST EIGHT BYTES, silently:"
                  " docs/HOLYC_STRUCT_LIMITS.md", file=sys.stderr)
            print("  #21, pinned by tests/exec/cases/e_struct_copy_into_slot.hc. Use MemCpy and"
                  " say why, as", file=sys.stderr)
            print("  cfe_es_perf.HC does -- or, if the class is 8 bytes or less, add the site"
                  " to ALLOW with", file=sys.stderr)
            print("  its size.", file=sys.stderr)
            print("    %s" % line.strip(), file=sys.stderr)
            rc = 1

    # A stale exemption is a failure, the same rule the other gates apply.
    for key in sorted(ALLOW):
        f = key.rsplit(":", 1)[0]
        if not os.path.exists(os.path.join(ROOT, f)):
            print("FAIL cfs-structcopy — ALLOW names %s, which does not exist" % key,
                  file=sys.stderr)
            rc = 1

    if rc == 0:
        print("cfs-structcopy: %d indexed or dereferenced assignments across %d files, none of"
              " them a class copy" % (checked, len(files)))
    return rc


if __name__ == "__main__":
    sys.exit(main())
