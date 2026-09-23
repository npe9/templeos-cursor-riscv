#!/usr/bin/env python3
"""Structural check on the two instruction tables in Kernel/RVExplore.HC.

VERIFICATION_PLAN P3, "the catalog is honest", as a gate rather than as a thing someone
notices. Both tables are flat strings with ';' between records and '|' between fields, so a
';' or '|' inside prose silently truncates a record and invents a new one. That happened: the
fence record's semantics field ended with "...succ-set; masks use letters i/o/r/w", which cut
the semantics short and produced a phantom record whose mnemonic was " masks use letters
i/o/r/w" -- and AsmComplete with an empty word listed it to the user.

Checks, in the order a failure is easiest to act on:
  1. every catalog record has exactly 7 fields, every example record exactly 5
  2. no mnemonic contains whitespace (the signature of a stray separator upstream)
  3. no duplicate mnemonics within a table
  4. every example resolves to a catalog entry, ignoring dots and underscores, so a motivation
     cannot be written for an instruction the catalog does not document
Exit 0 and print a one-line summary when clean, or list every violation and exit 1.
"""
import re
import sys
import os

DOC_FIELDS = 7
EX_FIELDS = 5


def grab(src, var):
    m = re.search(re.escape(var) + r' = "', src)
    if not m:
        raise SystemExit("check-asm-catalog: %s not found in RVExplore.HC" % var)
    i = m.end()
    j = src.index('";\n', i)
    return src[i:j]


def norm(mn):
    return mn.replace(".", "").replace("_", "").lower()


def check(name, body, want, bad):
    recs = [r for r in body.split(";") if r.strip()]
    seen = {}
    for k, r in enumerate(recs):
        fields = r.split("|")
        mn = fields[0]
        if len(fields) != want:
            bad.append("%s record %d (%r): %d fields, want %d -- a stray ; or | in the prose"
                       % (name, k, mn[:40], len(fields), want))
            continue
        if mn != mn.strip() or not mn or re.search(r"\s", mn):
            bad.append("%s record %d: mnemonic %r has whitespace" % (name, k, mn))
        if mn in seen:
            bad.append("%s: duplicate mnemonic %r (records %d and %d)" % (name, mn, seen[mn], k))
        else:
            seen[mn] = k
    return recs, seen


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        path = os.path.join(root, "Kernel", "RVExplore.HC")
    src = open(path, encoding="utf-8", errors="replace").read()
    bad = []
    doc_recs, doc_mn = check("catalog", grab(src, "rv_asm_doc_raw"), DOC_FIELDS, bad)
    ex_recs, ex_mn = check("examples", grab(src, "rv_asm_ex_raw"), EX_FIELDS, bad)

    doc_norm = {norm(m) for m in doc_mn}
    for mn in ex_mn:
        if norm(mn) not in doc_norm:
            bad.append("examples: %r has no catalog entry (not even ignoring dots)" % mn)

    if bad:
        for b in bad:
            print("FAIL check-asm-catalog -- " + b, file=sys.stderr)
        return 1

    covered = sum(1 for m in doc_mn if norm(m) in {norm(e) for e in ex_mn})
    print("Asm catalog: OK (%d documented, %d with motivation, %d examples, no orphans)"
          % (len(doc_recs), covered, len(ex_recs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
