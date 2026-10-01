#!/usr/bin/env python3
"""Every function defined in a gated NASA .c must be defined somewhere in the HolyC translation.

WHY THIS EXISTS. The differential oracle compares TRANSCRIPTS, so it only ever sees functions the
driver calls. A function nobody calls is invisible to it: the C side links it from NASA's source,
the HolyC side simply does not have it, and 105 identical lines say nothing at all about the
omission. That is not hypothetical -- CFE_MSG_GetNextSequenceCount was missing from the
translation of cfe_msg_ccsdspri.c for four commits, while the commit that introduced it claimed
the module was complete, twice.

This is a coarse check by design: it matches on NAMES, not signatures or behaviour. Name presence
is what "did you forget one" needs, and the oracle already covers behaviour for everything the
transcript touches. A name here with a wrong body is caught by the transcript or not at all.

    tools/cfs/check_coverage.py <nasa.c> [nasa.c ...]     # HolyC side is Kernel/Cfs/cfe/*.HC
"""
import re, sys, os, glob, subprocess, importlib.util

# CONFIGURATION-EXCLUDED FUNCTIONS, each pinned to the macro whose #if keeps it out of the build.
#
# NASA guards whole function bodies on platform switches, so a .c file contains functions this
# configuration does NOT compile -- and the C the oracle links does not contain them either. The
# transcript cannot tell that from a missing translation, and neither could this tool: its first
# run against the time module reported six absent functions that are absent on BOTH sides.
#
# THE GUARD IS VERIFIED, not trusted. Every macro named here is evaluated with the host C
# preprocessor against the real headers, and an entry whose macro is TRUE is a FAILURE -- so this
# list cannot become a place to hide a function that really is missing. Flip
# CFE_PLATFORM_TIME_CFG_SERVER in the platform config and this gate goes red, which is the
# behaviour you want: a port that changes configuration has to re-translate what the change
# brings in.
CONFIG_EXCLUDED = {
    ("cfe_time_utils.c", "CFE_TIME_SetSource"):  "CFE_PLATFORM_TIME_CFG_SOURCE",
    ("cfe_time_utils.c", "CFE_TIME_SetSignal"):  "CFE_PLATFORM_TIME_CFG_SIGNAL",
    ("cfe_time_utils.c", "CFE_TIME_SetDelay"):   "CFE_PLATFORM_TIME_CFG_CLIENT",
    ("cfe_time_api.c",   "CFE_TIME_ExternalMET"):  "CFE_PLATFORM_TIME_CFG_SRC_MET",
    ("cfe_time_api.c",   "CFE_TIME_ExternalGPS"):  "CFE_PLATFORM_TIME_CFG_SRC_GPS",
    ("cfe_time_api.c",   "CFE_TIME_ExternalTime"): "CFE_PLATFORM_TIME_CFG_SRC_TIME",
    ("cfe_time_tone.c",  "CFE_TIME_ToneSendMET"):  "CFE_PLATFORM_TIME_CFG_SRC_MET",
    ("cfe_time_tone.c",  "CFE_TIME_ToneSendGPS"):  "CFE_PLATFORM_TIME_CFG_SRC_GPS",
    ("cfe_time_tone.c",  "CFE_TIME_ToneSendTime"): "CFE_PLATFORM_TIME_CFG_SRC_TIME",
}


def guard_values(names):
    """{macro: int} as the host C preprocessor sees it, or (None, error)."""
    _spec = importlib.util.spec_from_file_location(
        "check_padding", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "check_padding.py"))
    cp = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(cp)
    src = os.path.join(ROOT, "build", "cfs", "check_coverage_guards.c")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    hdrs = list(cp.HDRS) + ["cfe_platform_cfg.h", "cfe_mission_cfg.h"]
    body = ["#include <stdio.h>"] + ['#include "%s"' % h for h in hdrs] + ["int main(void){"]
    for n in sorted(names):
        body += ["#ifdef %s" % n,
                 '  printf("%%s %%d\\n", "%s", (int)(%s));' % (n, n),
                 "#else",
                 '  printf("%%s UNDEF\\n", "%s");' % n,
                 "#endif"]
    body.append("  return 0; }")
    open(src, "w").write("\n".join(body) + "\n")
    exe = src[:-2]
    cc = os.environ.get("HOSTCC", "cc")
    r = subprocess.run([cc, "-O0", "-w"] + cp.INC + ["-o", exe, src],
                       capture_output=True, text=True)
    if r.returncode:
        return None, r.stderr
    out = {}
    for line in subprocess.run([exe], capture_output=True, text=True).stdout.split("\n"):
        p = line.split()
        if len(p) == 2:
            out[p[0]] = None if p[1] == "UNDEF" else int(p[1])
    return out, None

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Every translated unit, cFE and OSAL alike. Scanning both rather than one directory per gate
# means a function can move between them without the check losing sight of it.
HCDIRS = [os.path.join(ROOT, "Kernel", "Cfs", "cfe"),
          os.path.join(ROOT, "Kernel", "Cfs", "osal")]

# A C function DEFINITION at file scope: a line starting in column 1 with a type, a name, an
# argument list, and an opening brace on that line or the next. `static inline` in a header is
# not our business; these are .c files.
C_DEF = re.compile(
    r'^[A-Za-z_][A-Za-z0-9_ \t\*]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*$', re.M)

def c_functions(path):
    src = open(path, errors='replace').read()
    # strip comments so a prototype inside one cannot count
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    out = set()
    lines = src.split('\n')
    for i, line in enumerate(lines):
        m = C_DEF.match(line + '\n')
        if not m:
            continue
        # the next non-blank line must open a body
        for nxt in lines[i+1:]:
            if nxt.strip() == '':
                continue
            if nxt.lstrip().startswith('{'):
                out.add(m.group(1))
            break
    return out

def hc_defined():
    names = set()
    files = []
    for d in HCDIRS:
        files += glob.glob(os.path.join(d, "*.HC"))
    for f in files:
        src = open(f, errors='replace').read()
        src = re.sub(r'//[^\n]*', '', src)
        for m in re.finditer(
                r'^(?:U0|I8|U8|I16|U16|I32|U32|I64|U64|F64|Bool|[A-Z][A-Za-z0-9_]*)\s+\**'
                r'([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*$', src, re.M):
            names.add(m.group(1))
    return names

def main(argv):
    if not argv:
        print(__doc__)
        return 2
    have = hc_defined()
    # Resolve every guard FIRST, so an entry that no longer excludes anything is a failure rather
    # than a silent exemption.
    gv, err = guard_values(set(CONFIG_EXCLUDED.values()))
    if gv is None:
        print("FAIL cfs-coverage — could not evaluate the CONFIG_EXCLUDED guards with the host C",
              file=sys.stderr)
        print("  preprocessor, so an excluded function cannot be told from a missing one.",
              file=sys.stderr)
        print("\n".join(str(err).split("\n")[:12]), file=sys.stderr)
        return 1
    live = sorted({m for m in CONFIG_EXCLUDED.values() if gv.get(m)})
    if live:
        print("FAIL cfs-coverage — these guards are TRUE in this configuration, so the functions",
              file=sys.stderr)
        print("  they exclude ARE built and have to be translated. CONFIG_EXCLUDED is verified",
              file=sys.stderr)
        print("  against the real headers for exactly this reason:", file=sys.stderr)
        for m in live:
            for (f, fn), mm in sorted(CONFIG_EXCLUDED.items()):
                if mm == m:
                    print("    %-34s %s: %s" % (m + " = %d" % gv[m], f, fn), file=sys.stderr)
        return 1

    missing, excluded = [], []
    for c in argv:
        if not os.path.exists(c):
            print(f"FAIL cfs-coverage — no such file: {c}", file=sys.stderr)
            return 1
        base = os.path.basename(c)
        for fn in sorted(c_functions(c)):
            if fn in have:
                continue
            if (base, fn) in CONFIG_EXCLUDED:
                excluded.append((base, fn, CONFIG_EXCLUDED[(base, fn)]))
                continue
            missing.append((base, fn))
    if missing:
        print("FAIL cfs-coverage — defined in NASA's C, absent from the HolyC translation.", file=sys.stderr)
        print("  The transcript cannot see these: nothing calls them, so it stays green.", file=sys.stderr)
        for f, fn in missing:
            print(f"    {f}: {fn}", file=sys.stderr)
        return 1
    n = sum(len(c_functions(c)) for c in argv)
    for f, fn, m in excluded:
        print("  not in this configuration: %s: %s (%s is 0)" % (f, fn, m))
    print(f"cfs-coverage: {n - len(excluded)} functions across {len(argv)} NASA sources, all "
          f"present in the translation ({len(excluded)} excluded by a verified #if)")
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
