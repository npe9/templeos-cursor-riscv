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
CFE_GATE = os.path.join(ROOT, "tests", "scripts", "run_cfs_xlat_smoke.sh")
CFE_MODULES = os.path.join(ROOT, "vendor", "cFE", "modules")
# The cFS APPS, each its own repository under vendor/. Same CMakeLists shape as a cFE module
# -- an unconditional source list plus an EDS branch -- which is why the depth parser below
# needs no change to read one.
# THE APP LIST LIVES IN cfs_dirs.py NOW, which is where check_structs and check_padding get the
# app DIRECTORIES from -- three lists for one fact was how MM's directories ended up duplicated.
from cfs_dirs import APPS  # noqa: F401


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


def cfe_module_sources(mod_dir):
    """A cFE module's sources, split into the ones CMake always builds and the ones it builds
    only under a condition.

    This does NOT evaluate CMake. It walks the file tracking if()/else()/endif() DEPTH: a
    source named at depth 0 is unconditional, and one inside any branch is reported with the
    condition guarding it. Judging which branch a configuration takes is left to a person.

    Depth is what matters, not the variable name. An earlier version matched the first
    `set(..._SRC ...)` it found and called that the base list, which got sbr exactly backwards:
    that module has NO unconditional set() at all -- it picks between a DIRECT and a HASH
    message map, defaulting to HASH -- so the parser reported the DIRECT branch as the build
    and cfe_sbr_map_direct.c as a missing 101 lines, when it is not in this configuration at
    all. A tool that exists to stop a wrong denominator must not invent one.
    """
    cm = os.path.join(mod_dir, "CMakeLists.txt")
    if not os.path.exists(cm):
        return [], []
    txt = re.sub(r"#[^\n]*", "", open(cm, errors="replace").read())
    base, cond, depth, guards = [], [], 0, []
    for line in txt.split("\n"):
        opened = re.match(r"\s*if\s*\(\s*(?:NOT\s+)?([A-Za-z0-9_]+)", line)
        elsed = re.match(r"\s*(?:else|elseif)\s*\(\s*([A-Za-z0-9_]*)", line)
        if opened:
            depth += 1
            guards.append(opened.group(1))
        elif elsed and depth:
            guards[-1] = (elsed.group(1) or ("else of " + guards[-1]))
        elif re.match(r"\s*endif\s*\(", line):
            depth = max(0, depth - 1)
            if guards:
                guards.pop()
        for f in re.findall(r"fsw/src/([A-Za-z0-9_.-]+\.c)", line):
            if depth == 0:
                if f not in base:
                    base.append(f)
            else:
                cond.append((f, guards[-1] if guards else "?"))
    return base, cond


def app_table_sources(app_dir):
    """The sources under add_cfe_tables -- fsw/tables/*.c -- which are NOT app code.

    THEY ARE A DIFFERENT BUILD PRODUCT. add_cfe_app compiles the five app sources into the app;
    add_cfe_tables compiles each of these and runs it through elf2cfetbl to emit a .tbl load
    file. They contain no functions at all: one file-scope aggregate initialiser and a
    CFE_TBL_FILEDEF macro each.

    They are reported SEPARATELY and do not count toward app coverage, because folding 280
    lines of default table data into the denominator would make the percentage mean two
    different things at once. Reported rather than dropped, because a group this tool knows
    about and does not print is a group nobody knows about.
    """
    cm = os.path.join(app_dir, "CMakeLists.txt")
    if not os.path.exists(cm):
        return []
    txt = re.sub(r"#[^\n]*", "", open(cm, errors="replace").read())
    out = []
    for f in re.findall(r"fsw/tables/([A-Za-z0-9_.-]+\.c)", txt):
        if f not in out:
            out.append(f)
    return out


def app_report():
    gated = set()
    if os.path.exists(CFE_GATE):
        txt = open(CFE_GATE, errors="replace").read()
        for m in re.finditer(r'SRC_C="(.*?)"', txt, re.S):
            gated.update(re.findall(r"([A-Za-z0-9_-]+\.c)", m.group(1)))
    rows = []
    for app in APPS:
        d = os.path.join(ROOT, "vendor", app)
        if not os.path.isdir(d):
            continue
        base, cond = cfe_module_sources(d)
        tbls = app_table_sources(d)
        if not base and not cond:
            continue
        src = os.path.join(d, "fsw", "src")
        tsrc = os.path.join(d, "fsw", "tables")

        def nl(base_dir, f):
            try:
                with open(os.path.join(base_dir, f), errors="replace") as fh:
                    return sum(1 for _ in fh)
            except OSError:
                return 0

        sizes = {f: nl(src, f) for f in base}
        sizes.update({f: nl(src, f) for f, _ in cond})
        tsizes = {f: nl(tsrc, f) for f in tbls}
        tot = sum(sizes[f] for f in base)
        done = sum(sizes[f] for f in base if f in gated)
        rows.append((app, base, cond, tbls, tot, done, sizes, tsizes))
    if not rows:
        return
    print("app-manifest: per cFS APP. Same shape as a cFE module -- unconditional sources, then")
    print("              the ones CMake selects with a condition -- plus add_cfe_tables, which is")
    print("              a different build product and is NOT in the percentage.")
    for app, base, cond, tbls, tot, done, sizes, tsizes in rows:
        pct = (100.0 * done / tot) if tot else 0.0
        print(f"    {app:<12} {len(base):>2} uncond {tot:>6} lines  {done:>6} gated ({pct:>3.0f}%)")
        for f in base:
            if f not in gated:
                print(f"        -      {f:<34} {sizes[f]:>5}")
        for f, g in cond:
            mark = "GATED " if f in gated else "  -   "
            print(f"        {mark} {f:<34} {sizes[f]:>5}  [{g}]")
        if tbls:
            n = sum(tsizes.values())
            print(f"        add_cfe_tables: {len(tbls)} file(s), {n} lines -- a .tbl build product,")
            print(f"        not app code (no functions; a file-scope initialiser and CFE_TBL_FILEDEF).")


def cfe_report():
    if not os.path.isdir(CFE_MODULES):
        return
    gated = set()
    if os.path.exists(CFE_GATE):
        txt = open(CFE_GATE, errors="replace").read()
        for m in re.finditer(r'SRC_C="(.*?)"', txt, re.S):
            gated.update(re.findall(r"([A-Za-z0-9_-]+\.c)", m.group(1)))
    rows = []
    for mod in sorted(os.listdir(CFE_MODULES)):
        d = os.path.join(CFE_MODULES, mod)
        if not os.path.isdir(d):
            continue
        base, cond = cfe_module_sources(d)
        if not base and not cond:
            continue
        src = os.path.join(d, "fsw", "src")
        def nl(f):
            pth = os.path.join(src, f)
            try:
                with open(pth, errors="replace") as fh:
                    return sum(1 for _ in fh)
            except OSError:
                return 0
        # Resolve the line counts HERE, not later: nl() closes over `src`, which moves on to
        # the next module before the printing loop runs, and every count came out 0.
        sizes = {f: nl(f) for f in base}
        sizes.update({f: nl(f) for f, _ in cond})
        tot = sum(sizes[f] for f in base)
        done = sum(sizes[f] for f in base if f in gated)
        rows.append((mod, base, cond, tot, done, sizes))
    print("cfe-manifest: per module. UNCONDITIONAL sources first; sources CMake selects with a")
    print("              condition are listed under them with the guard, because which branch a")
    print("              configuration takes is not something this tool decides.")
    for mod, base, cond, tot, done, sizes in rows:
        pct = (100.0 * done / tot) if tot else 0.0
        print(f"    {mod:<12} {len(base):>2} uncond {tot:>6} lines  {done:>6} gated ({pct:>3.0f}%)")
        for f in base:
            if f not in gated:
                print(f"        -      {f:<34} {sizes[f]:>5}")
        for f, g in cond:
            mark = "GATED " if f in gated else "  -   "
            print(f"        {mark} {f:<34} {sizes[f]:>5}  [{g}]")


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
    if "--cfe" in argv:
        cfe_report()
        app_report()
        return 0
    if remaining:
        print("  remaining, largest first:")
        for n_lines, name in sorted(remaining, reverse=True):
            print(f"    {name:<26} {n_lines:>5}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
