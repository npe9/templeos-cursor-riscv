#!/usr/bin/env python3
"""What NASA's BUILD contains, what the gates cover, and the fraction -- computed, not counted.

WHY THIS EXISTS. The denominator has been wrong twice, the same way both times: by reading the
DIRECTORY instead of the build recipe.

  - cFE's `msg` module: the directory holds more sources than CMakeLists compiles, and two
    commit messages called the module complete while three of its eight unconditional sources
    were untranslated.
  - OSAL: `osapi-debug.c` sits in src/os/shared/src and is appended to OSAL_SRCLIST only when
    OSAL_CONFIG_DEBUG_PRINTF is set, which this configuration does not set. Counting it gave a
    9,523-line shared layer where the real figure is 9,447 across 25 sources.

So this reads OSAL_SRCLIST out of vendor/osal/CMakeLists.txt, reads the source lists out of the
gate scripts, and prints the comparison. Two things make it a gate rather than a report:

  1. Gating a source NASA does NOT build unconditionally is a FAILURE. Translating an EDS
     variant or a debug-only file and counting it as progress is the exact error above, in the
     other direction.
  2. A source in the build that no gate mentions is listed as remaining, with its line count,
     so the number in docs/CFS_PLAN.md can be regenerated instead of hand-maintained.

    tools/cfs/check_manifest.py            # report and check
    tools/cfs/check_manifest.py --plan     # the markdown table rows, for pasting into the plan
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OSAL_CMAKE = os.path.join(ROOT, "vendor", "osal", "CMakeLists.txt")
GATES = [
    os.path.join(ROOT, "tests", "scripts", "run_osal_xlat_smoke.sh"),
    os.path.join(ROOT, "tests", "scripts", "run_osal_printf_smoke.sh"),
]


def osal_build_sources():
    """The sources in OSAL_SRCLIST -- the unconditional list only.

    The `if (OSAL_CONFIG_DEBUG_PRINTF) list(APPEND ...)` block after it is deliberately NOT
    followed: this configuration does not set that, so those files are not in the build.
    """
    txt = open(OSAL_CMAKE, errors="replace").read()
    m = re.search(r"set\(OSAL_SRCLIST\s*(.*?)\)", txt, re.S)
    if not m:
        return None, "could not find set(OSAL_SRCLIST ...) in vendor/osal/CMakeLists.txt"
    names = re.findall(r"src/os/shared/src/([A-Za-z0-9_.-]+\.c)", m.group(1))
    return names, None


def gated_sources():
    out = set()
    for g in GATES:
        if not os.path.exists(g):
            continue
        txt = open(g, errors="replace").read()
        # only the SRC_C assignment, so a source named in a comment does not count as gated
        for m in re.finditer(r'SRC_C="(.*?)"', txt, re.S):
            out.update(re.findall(r"osapi-[A-Za-z0-9_-]+\.c", m.group(1)))
    return out


def lines_of(name):
    p = os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "src", name)
    try:
        with open(p, errors="replace") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


def main(argv):
    build, err = osal_build_sources()
    if err:
        print("FAIL cfs-manifest — " + err, file=sys.stderr)
        return 1
    gated = gated_sources()

    # (1) anything gated must be in the unconditional build list
    stray = sorted(g for g in gated if g not in build)
    if stray:
        print("FAIL cfs-manifest — a gate covers a source NASA does not build unconditionally.",
              file=sys.stderr)
        print("  Translating a file the configuration excludes is not progress; it is the", file=sys.stderr)
        print("  directory-instead-of-recipe mistake in the other direction.", file=sys.stderr)
        for s in stray:
            print(f"    {s}", file=sys.stderr)
        return 1

    total = sum(lines_of(n) for n in build)
    done = sum(lines_of(n) for n in build if n in gated)
    remaining = sorted((lines_of(n), n) for n in build if n not in gated)

    if "--plan" in argv:
        for n in sorted(build, key=lambda x: -lines_of(x)):
            mark = "**yes**" if n in gated else "no"
            print(f"| `{n}` | {lines_of(n):,} | {mark} | |")
        return 0

    print(f"cfs-manifest: OSAL_SRCLIST has {len(build)} sources, {total:,} lines; "
          f"{len(gated)} gated, {done:,} lines ({100.0 * done / total:.0f}%)")
    if remaining:
        print("  remaining, largest first:")
        for n_lines, name in sorted(remaining, reverse=True):
            print(f"    {name:<26} {n_lines:>5}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
