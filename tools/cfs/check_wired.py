#!/usr/bin/env python3
"""Every translated file must be REACHABLE from a driver, or say why it is not.

THE HOLE THIS CLOSES. The nine gates beside it are all driven from SRC_C -- the list of NASA
sources the smoke script compiles -- so they measure the translation only where the C half
names its counterpart. A .HC file that is complete, parses, and is included by NOBODY is
invisible to every one of them except check_padding (which scans the tree). It is not a
hypothetical: cfe_sb_api.HC landed in exactly that state, 1,300 lines that no gate compiled.

The outcome that looks like success, again. A file nothing includes cannot fail a gate, so the
tree grows green while the thing it claims to translate is not being run. This makes that state
NAMED rather than silent: a file is either in a driver's include closure, or it is in
UNWIRED_OK below with a reason, and anything else is a failure.

Exit 0 and print a count, or exit 1 and name each file.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SCRIPTS = os.path.join(ROOT, "tests", "scripts")


def driver_roots():
    """The HolyC half of every differential smoke script, read FROM the scripts.

    Hardcoding the list here was the first version, and it was wrong within a minute of being
    run: it named two drivers and there are three. run_osal_printf_smoke.sh has its own, and
    the two files only it includes came back as unwired. A list of roots that can silently be
    short is the same blind spot this gate exists to close, one level up -- so the roots are
    parsed out of the scripts, and a script whose SRC_HC does not resolve is a failure rather
    than one fewer root.
    """
    roots = []
    bad = []
    for name in sorted(os.listdir(SCRIPTS)):
        if not name.endswith(".sh"):
            continue
        text = open(os.path.join(SCRIPTS, name), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'^\s*SRC_HC="\$ROOT/([^"]+)"', text, re.M):
            cand = os.path.normpath(os.path.join(ROOT, m.group(1)))
            if os.path.isfile(cand):
                roots.append(cand)
            else:
                bad.append((name, m.group(1)))
    return roots, bad

# Translated files that NOTHING includes yet, each with the reason and what would change it.
# A reason is required: "not wired yet" with no account of what is blocking it is how a
# permanent exception gets written as a temporary one.
UNWIRED_OK = {
    "Kernel/Cfs/CfsApps.HC":
        "the hand-written TempleOS cFS demo apps, not a translation of NASA code; they are "
        "built by the kernel image, not by a differential driver.",
    "Kernel/Cfs/CfsSb.HC":
        "the hand-written software bus the demo apps run on, predating the 1:1 translation; "
        "it goes away when the translated SB can host them.",
    "Kernel/Cfs/cfe/cfe_sb_api.HC":
        "translated, NOT yet driven. Wiring it means replacing four injectable stubs in "
        "tests/cfs/oracle_ccsdspri.c (CFE_SB_CreatePipe, CFE_SB_Subscribe, "
        "CFE_SB_ReceiveBuffer, CFE_SB_TransmitMsg) that every other module's exercise is "
        "driven against -- the fault injection has to move down to the simulated OSAL queue "
        "and memory pool first. Until then no gate but check_padding reads this file.",
}


def includes_of(path):
    """The #include targets of one HolyC file, resolved to repo-relative paths."""
    out = []
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    for m in re.finditer(r'^\s*#include\s+"([^"]+)"', text, re.M):
        target = m.group(1)
        if target.startswith("/"):
            # HOLYC_INCLUDE_ROOT-relative, as the compiler resolves it
            cand = os.path.join(ROOT, target.lstrip("/"))
        else:
            cand = os.path.join(os.path.dirname(path), target)
        cand = os.path.normpath(cand)
        if os.path.isfile(cand):
            out.append(cand)
    return out


def closure(roots):
    seen = set()
    stack = list(roots)
    while stack:
        p = os.path.normpath(stack.pop())
        if p in seen:
            continue
        seen.add(p)
        stack.extend(includes_of(p))
    return seen


def main():
    roots, bad_roots = driver_roots()
    if bad_roots:
        # A root that is not there would make files look unwired for a reason that has nothing
        # to do with them, so say so plainly rather than printing fifty names.
        for script, target in bad_roots:
            print(f"FAIL cfs-wired — {script} names SRC_HC={target}, which does not exist",
                  file=sys.stderr)
        return 1
    if not roots:
        print("FAIL cfs-wired — no smoke script names a SRC_HC driver; this gate would pass "
              "by finding nothing", file=sys.stderr)
        return 1

    reached = closure(roots)

    translated = []
    for base, _dirs, files in os.walk(os.path.join(ROOT, "Kernel", "Cfs")):
        for f in files:
            if f.endswith(".HC"):
                translated.append(os.path.normpath(os.path.join(base, f)))
    translated.sort()

    unwired = [p for p in translated if p not in reached]
    rel_unwired = [os.path.relpath(p, ROOT) for p in unwired]

    bad = [r for r in rel_unwired if r not in UNWIRED_OK]
    # An allowlist entry for a file that IS wired now is stale, and a stale exception is how
    # the list stops meaning anything. Both directions are failures.
    stale = [r for r in UNWIRED_OK if r not in rel_unwired]

    if bad or stale:
        print("FAIL cfs-wired — a translated file is not reachable from any driver.",
              file=sys.stderr)
        for r in bad:
            print(f"    {r}", file=sys.stderr)
            print("        No driver includes it, so no gate but check_padding reads it.",
                  file=sys.stderr)
            print("        Either include it from a driver, or add it to UNWIRED_OK in",
                  file=sys.stderr)
            print("        tools/cfs/check_wired.py WITH the reason and what unblocks it.",
                  file=sys.stderr)
        for r in stale:
            print(f"    {r}", file=sys.stderr)
            print("        Listed in UNWIRED_OK but a driver DOES include it now. Remove the",
                  file=sys.stderr)
            print("        entry -- a stale exception is how the list stops meaning anything.",
                  file=sys.stderr)
        return 1

    print(f"cfs-wired: {len(translated) - len(unwired)} of {len(translated)} translated files "
          f"are compiled by one of {len(roots)} drivers "
          f"({len(unwired)} declared unwired, with reasons)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
