#!/usr/bin/env python3
"""A translated `class` must have NASA's fields, in NASA's order.

WHY THIS EXISTS. Nothing else here looks inside a struct:

  - check_coverage.py   compares function NAMES.
  - check_signatures.py compares function PARAMETERS.
  - check_seam.py       compares the OS_*_Impl declarations.
  - the transcript      sees a field only if the driver makes something read it.

So `OS_SharedGlobalVars` was missing `CoresConfigured` -- the last field of NASA's struct -- for
several commits. It was found by eye while translating osapi-task-affinity.c, the first module
that reads it, and not by any gate. A missing field in the MIDDLE of a struct is worse: it
silently shifts every field after it, which is the same class of fault as the __task reserve
overrun, and a transcript can pass while the wrong bytes are being read.

This compares FIELD NAMES AND ORDER, not types. Types are partly covered by check_signatures
(anything that appears in a parameter) and the two languages spell them differently anyway; the
order and the membership are what a layout depends on and what a hand translation drops.

    tools/cfs/check_structs.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HCDIRS = [os.path.join(ROOT, "Kernel", "Cfs", "osal"), os.path.join(ROOT, "Kernel", "Cfs", "cfe")]
import glob as _glob

NASA_DIRS = [
    os.path.join(ROOT, "vendor", "osal", "src", "os", "inc"),
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "inc"),
] + sorted(_glob.glob(os.path.join(ROOT, "vendor", "cFE", "modules", "*", "fsw", "inc"))) \
  + sorted(_glob.glob(os.path.join(ROOT, "vendor", "cFE", "modules", "*", "fsw", "src"))) \
  + [os.path.join(ROOT, "vendor", "cFE", "cmake", "target", "inc")]

# A field the translation deliberately does NOT carry, with the reason. Pinned to the struct it
# belongs to, printed on every run, and a FAILURE if it stops applying -- the same discipline as
# DEVIATIONS in check_signatures.py, so the list cannot quietly become a place to hide a real
# omission.
OMITTED = {
    ("OS_shared_global_vars", "DebugLevel"):
        "declared under #ifdef OSAL_CONFIG_DEBUG_PRINTF, which this configuration does not set "
        "-- the same switch that keeps osapi-debug.c out of OSAL_SRCLIST. Carrying it would "
        "change the layout.",
}

# A member declaration. The run between the type and the name can interleave stars and
# qualifiers -- cFE declares `const Target_ObjectTable_t *const *CoreObjectTable;` -- and an
# earlier version stopped at the first `*`, silently dropping that field from NASA's side and
# then reporting the TRANSLATION as having an extra one.
FIELD = re.compile(r'^\s*(?:const\s+|volatile\s+|unsigned\s+|signed\s+)*'
                   r'[A-Za-z_]\w*(?:\s*\*+|\s*const\b|\s*volatile\b)*'
                   r'\s*\**\s*([A-Za-z_]\w*)\s*(?:\[[^\]]*\])*\s*;', re.M)
# a function-pointer member: `void (*name)(args);`
FIELD_FN = re.compile(r'^\s*[A-Za-z_][\w \t\*]*\(\s*\*+\s*([A-Za-z_]\w*)\s*\)\s*\([^;]*\)\s*;', re.M)


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', t)


def fields_of(body):
    """Field names in declaration order. Nested braces are not expected in these structs."""
    out = []
    for line in body.split(';'):
        line = line + ';'
        m = FIELD_FN.search(line) or FIELD.search(line)
        if m:
            out.append(m.group(1))
    return out


def nasa_structs():
    out = {}
    for d in NASA_DIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".h"):
                continue
            txt = strip_comments(open(os.path.join(d, fn), errors="replace").read())
            # `typedef struct { ... } Name;` and `struct Name { ... };`
            # `typedef const struct { ... } Name;` is how cFE declares its target-config
            # types, and without the optional `const` none of them were being compared at all.
            for m in re.finditer(r'typedef\s+(?:const\s+)?struct\s*(?:\w+\s*)?\{(.*?)\}\s*(\w+)\s*;',
                                 txt, re.S):
                out.setdefault(m.group(2), (fields_of(m.group(1)), fn))
            for m in re.finditer(r'\bstruct\s+(\w+)\s*\{(.*?)\}\s*;', txt, re.S):
                out.setdefault(m.group(1), (fields_of(m.group(2)), fn))
    return out


def hc_classes():
    out = {}
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            txt = strip_comments(open(os.path.join(d, fn), errors="replace").read())
            for m in re.finditer(r'\bclass\s+(\w+)\s*\{(.*?)\}\s*;', txt, re.S):
                out[m.group(1)] = (fields_of(m.group(2)), fn)
    return out


def main(argv):
    nasa = nasa_structs()
    mine = hc_classes()
    if not nasa:
        print("FAIL cfs-structs — no NASA headers found; is vendor/osal present?", file=sys.stderr)
        return 1

    bad, notes, checked = [], [], 0
    for name, (hfields, hfile) in sorted(mine.items()):
        # The translation names a class after NASA's typedef, sometimes without the _t.
        cand = name if name in nasa else (name + "_t" if name + "_t" in nasa else None)
        if cand is None:
            continue          # a class of this port's own; not NASA's to compare against
        nfields, nfile = nasa[cand]
        checked += 1
        expect = []
        for f in nfields:
            key = (cand, f)
            if key in OMITTED:
                notes.append(f"  omitted: {cand}.{f} — {OMITTED[key]}")
                continue
            expect.append(f)
        if hfields != expect:
            missing = [f for f in expect if f not in hfields]
            extra = [f for f in hfields if f not in expect]
            detail = ""
            if missing:
                detail += f"\n        missing: {', '.join(missing)}"
            if extra:
                detail += f"\n        extra:   {', '.join(extra)}"
            if not missing and not extra:
                detail = "\n        same fields, DIFFERENT ORDER -- the layout does not match"
            bad.append(f"    {hfile}: class {name} vs {nfile}: {cand}{detail}\n"
                       f"        NASA        {expect}\n"
                       f"        translation {hfields}")

    # a stale entry in OMITTED is itself a failure
    for (sname, fname), why in sorted(OMITTED.items()):
        if sname in nasa and fname not in nasa[sname][0]:
            bad.append(f"    {sname}.{fname}: recorded as omitted, but NASA's struct no longer "
                       f"has that field — delete the entry in check_structs.py")

    if bad:
        print("FAIL cfs-structs — a translated class does not match NASA's struct.", file=sys.stderr)
        print("  Field membership and ORDER are what a layout depends on; a field missing from", file=sys.stderr)
        print("  the middle shifts everything after it and the transcript can still pass.", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1
    for n in notes:
        print(n)
    print(f"cfs-structs: {checked} translated classes match NASA's structs field for field")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
