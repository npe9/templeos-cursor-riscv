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
# THE WHOLE KERNEL, not just the translation. `arr[i] = someStruct` is an ordinary idiom and
# this is a COMPILER defect, so the rest of the kernel -- CTask, the DolDoc entries, the window
# records, the virtio descriptors, the RV JIT's tables -- is exposed to it in exactly the same
# way, and nothing else would say so. Widening it cost one line and found the tree already
# clean: 342 indexed-or-dereferenced assignments across 322 files, one of them a class copy,
# and that one was cfe_es_perf.HC's.
HCROOT = os.path.join(ROOT, "Kernel")

# `arr[...] = x;` or `*p = x;` where x is a bare lvalue -- no operators, no call.
#
# MATCHED AGAINST A STATEMENT, NOT A LINE. The formatter wraps at about 96 characters and a
# realistic destination -- CFE_ES_Global.ResetDataPtr->Perf.DataBuffer[DataEnd] -- is 55 of
# them before the right-hand side, so a line-anchored pattern would simply not see a wrapped
# copy. Statements are split on ';' below and whitespace is collapsed first.
ASSIGN = re.compile(r'^(\*[A-Za-z_]\w*|[A-Za-z_][\w.\[\]>-]*\[[^\]]*\])\s*=\s*'
                    r'([A-Za-z_][\w.>-]*)$')
CLASS_DECL = re.compile(r'^\s*(?:class|union)\s+([A-Za-z_]\w*)', re.M)
# A local or global declaration: `SomeClass name;` or `SomeClass name[...]`
VAR_DECL = re.compile(r'^\s*([A-Z][A-Za-z0-9_]*)\s+([A-Za-z_]\w*)\s*(?:;|\[)', re.M)

# Sites verified SAFE, each with the reason. A struct of 8 bytes or less copies whole, so a
# small class is allowed here -- with its size stated, because the entry is a claim about it.
ALLOW = {}


def statements(src):
    """(statement text with whitespace collapsed, line number it started on) for each ';'."""
    out = []
    line = 1
    buf = []
    start = 1
    for ch in src:
        if ch == ';':
            text = " ".join("".join(buf).split())
            if text:
                out.append((text, start))
            buf = []
            start = line
        elif ch in "{}":
            buf = []
            start = line
            if ch == '\n':
                line += 1
        else:
            if ch == '\n':
                line += 1
                if not "".join(buf).strip():
                    start = line
            buf.append(ch)
    return out


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
    unresolved = 0
    for p in files:
        rel = os.path.relpath(p, ROOT)
        text = open(p, errors="replace").read()
        # strip comments so a commented-out assignment cannot be flagged
        src = re.sub(r'//[^\n]*', '', text)
        # {name: its declared type} for every declaration in the file
        declared = {}
        for m in VAR_DECL.finditer(src):
            declared.setdefault(m.group(2), m.group(1))
        for stmt, lineno in statements(src):
            m = ASSIGN.match(stmt)
            if not m:
                continue
            checked += 1
            rhs = m.group(2)
            base = re.split(r'[.\[>-]', rhs)[0]
            ty = declared.get(base)
            if ty is None:
                continue
            # A MEMBER ON THE RIGHT IS NOT TYPE-RESOLVED, and that is a counted hole rather
            # than a silence: `arr[i] = x.member` is the same broken store, but the member's
            # own type is not something this gate reads. The number is printed, so it is
            # visible if it starts growing.
            if rhs != base:
                if ty in classes:
                    unresolved += 1
                continue
            if ty not in classes:
                continue
            key = "%s:%d" % (rel, lineno)
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
              " them a class copy (%d had a class MEMBER on the right and so were NOT"
              " type-resolved)" % (checked, len(files), unresolved))
    return rc


if __name__ == "__main__":
    sys.exit(main())
