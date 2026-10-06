#!/usr/bin/env python3
"""Every translated function is actually IN a driver's binary, not just in its source.

THE HOLE THIS CLOSES, and it is a different hole from check_wired's. check_wired asks whether
a .HC file is REACHABLE from a driver's include graph -- a question about include lines.
Everything else in the gate set reads source text: check_coverage counts function definitions,
check_signatures compares parameter lists, check_constants reads #defines, check_lock_sites
reads literals at call sites. Not one of them opens the binary.

So a file can be included, parse cleanly, pass every gate, and CONTRIBUTE NOTHING. That is not
hypothetical: docs/HOLYC_STRUCT_LIMITS.md #13 is exactly this failure, and it has now happened
twice. cfe_time_api.HC lost all forty-six of its functions to a re-included sibling, and
cfe_es_task.HC lost all twenty-eight the same way one commit before this file was written.

WHAT CAUGHT IT BOTH TIMES WAS LUCK, which is the argument for this gate. The first time, the
import trailer noticed -- but only because something CALLED one of the missing functions, so
the name appeared as an unresolved import in a unit that defines it. The second time, the file
happened to owe the driver a type, so the compiler said "Expected type" five hundred lines
away. A file whose functions are only called by the ground, like cfe_es_task.c's twenty-two
command handlers, offers neither tell: nothing calls them and nothing needs a type from them.

The property is simple and does not depend on anything calling anything: compile each driver
with HOLYC_MAP and require every function the translation claims to define to have an address.
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS  # ONE copy of this list -- see cfs_dirs.py
SCRIPTS = os.path.join(ROOT, "tests", "scripts")
COMPILER = os.path.join(ROOT, "holyc-riscv")

# A definition at column 1: a return type, a name, a parameter list, and NO trailing semicolon.
HC_DEF = re.compile(
    r'^(?:U0|I8|U8|I16|U16|I32|U32|I64|U64|F64|Bool|[A-Z][A-Za-z0-9_]*)\s*\**\s*'
    r'([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*$', re.M)

# Files whose functions are NOT expected in any driver's binary, each with the reason. Same
# rule as check_wired's UNWIRED_OK: a reason is required, and a stale entry is a failure.
NOT_IN_BLOB_OK = {}


def driver_roots():
    """The HolyC half of every differential smoke script, read FROM the scripts.

    Same source as check_wired.py's, and for the same reason: a hardcoded list of drivers was
    wrong within a minute the first time anyone ran one.
    """
    roots = []
    for name in sorted(os.listdir(SCRIPTS)):
        if not name.endswith(".sh"):
            continue
        text = open(os.path.join(SCRIPTS, name), errors="replace").read()
        for m in re.finditer(r'^\s*SRC_HC="\$ROOT/([^"]+)"', text, re.M):
            cand = os.path.normpath(os.path.join(ROOT, m.group(1)))
            if os.path.isfile(cand) and cand not in roots:
                roots.append(cand)
    return roots


def declared():
    """{function name: the .HC file that defines it}."""
    out = {}
    for d in HCDIRS:
        for f in sorted(glob.glob(os.path.join(d, "*.HC"))):
            rel = os.path.relpath(f, ROOT)
            src = re.sub(r'//[^\n]*', '', open(f, errors="replace").read())
            for m in HC_DEF.finditer(src):
                out.setdefault(m.group(1), rel)
    return out


def map_symbols(driver, tmp):
    """Every name HOLYC_MAP reports for one driver, or None if it did not compile."""
    mp = os.path.join(tmp, os.path.basename(driver) + ".map")
    env = dict(os.environ, HOLYC_INCLUDE_ROOT=ROOT, HOLYC_MAP=mp)
    r = subprocess.run([COMPILER, driver, "-o", os.path.join(tmp, "blob.bin")],
                       capture_output=True, env=env)
    if r.returncode != 0 or not os.path.exists(mp):
        return None
    names = set()
    for line in open(mp, errors="replace"):
        parts = line.split()
        if len(parts) >= 2:
            names.add(parts[1])
    return names


def main():
    if not os.path.exists(COMPILER):
        print("FAIL cfs-inblob — build holyc-riscv first", file=sys.stderr)
        return 1
    roots = driver_roots()
    if not roots:
        print("FAIL cfs-inblob — no smoke script names a SRC_HC driver; this gate would pass on"
              " an empty set, which is the shape it exists to refuse", file=sys.stderr)
        return 1

    present = set()
    with tempfile.TemporaryDirectory() as tmp:
        for d in roots:
            got = map_symbols(d, tmp)
            if got is None:
                print("FAIL cfs-inblob — %s did not compile, so this gate cannot see what it"
                      " contains" % os.path.relpath(d, ROOT), file=sys.stderr)
                return 1
            present |= got

    decl = declared()
    missing = {}
    for name, f in sorted(decl.items()):
        if f in NOT_IN_BLOB_OK:
            continue
        if name not in present:
            missing.setdefault(f, []).append(name)

    # A stale exemption is a failure, the same rule check_wired applies to UNWIRED_OK.
    for f in sorted(NOT_IN_BLOB_OK):
        if not any(v == f for v in decl.values()):
            print("FAIL cfs-inblob — NOT_IN_BLOB_OK names %s, which defines nothing; the entry"
                  " is stale" % f, file=sys.stderr)
            return 1

    if missing:
        print("FAIL cfs-inblob — these functions are DEFINED in the translation and are NOT in"
              " any driver's", file=sys.stderr)
        print("  binary. The source compiled and every static gate passed; the code is simply"
              " not there.", file=sys.stderr)
        print("  The usual cause is docs/HOLYC_STRUCT_LIMITS.md #13 -- a unit that re-includes a"
              " sibling", file=sys.stderr)
        print("  the driver already read loses EVERYTHING after that line, silently.",
              file=sys.stderr)
        for f in sorted(missing):
            names = missing[f]
            print("    %s: %d missing, first %s, last %s"
                  % (f, len(names), names[0], names[-1]), file=sys.stderr)
        return 1

    print("cfs-inblob: %d translated functions have an address in one of %d drivers' binaries"
          % (len(decl), len(roots)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
