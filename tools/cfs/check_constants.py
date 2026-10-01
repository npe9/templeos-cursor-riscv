#!/usr/bin/env python3
"""Every numeric constant the translation spells out must have NASA's value.

WHY THIS EXISTS. HolyC has no enum and no CMake, so the translation re-states hundreds of
constants by hand: event ids, message ids, bit masks, array bounds, error codes. Each one is a
number typed from a header, and NOTHING ELSE HERE CHECKS IT.

  - check_coverage, check_signatures and check_seam look at functions.
  - check_structs and check_padding look at layout -- and a wrong array BOUND shows up there,
    which is the one corner that was already covered.
  - the transcript sees a constant only where some driver line happens to exercise it. A
    message id that nothing routes, an event id that no branch reaches, a bit mask used only
    in a command this gate does not send: all invisible.

Measured, on the first run against the EVS declarations, FIVE of ninety were wrong:

    CFE_MISSION_ES_MAX_APPLICATIONS   32   NASA: 16   (the MISSION limit is not the PLATFORM one)
    CFE_EVS_MAX_PORT_MSG_LENGTH      152   NASA: 161  (guessed the slack term)
    CFE_EVS_HK_TLM_MID              2054   NASA: 2049
    CFE_EVS_CMD_MID                 6150   NASA: 6145
    CFE_EVS_SEND_HK_MID             6151   NASA: 6153

The first would have made the housekeeping packet twice its real size -- which check_padding
WOULD have caught, because it sizes an array. The other four would not have been caught by
anything: three message ids and a buffer length, all of them the kind of value a port gets
wrong once and then builds on.

HOW. The same shape as check_padding.py: the authority is the host C preprocessor, not a model.
Every `#define NAME <number>` in Kernel/Cfs/**.HC whose name NASA also defines is compiled into
a probe that prints NASA's value, and the two are compared. Comparison is on the low 32 bits,
because `0xC2000001` in the translation and `((CFE_Status_t)0xc2000001)` in NASA's header are
the same bits reached by different spellings.

A name NASA does NOT define is NOT a failure: the translation legitimately invents names for
things HolyC cannot say -- a C enumerator is not a #define, so CFE_EVS_EventType_ERROR exists
only here. Those are counted and listed under -v so the list cannot quietly become a place to
hide a typo.

    tools/cfs/check_constants.py          # check
    tools/cfs/check_constants.py -v       # and list the names NASA does not define
"""
import glob
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The include path and the header list are check_padding.py's, for the same reason it does not
# duplicate check_structs.py's name mapping: two tools disagreeing about which headers are in
# this configuration would mean one of them is checking something else.
_spec = importlib.util.spec_from_file_location(
    "check_padding", os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_padding.py"))
check_padding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_padding)

# Only names that could plausibly be NASA's. A port-local constant (RV_*, HOLYC_*) is not under
# test, and neither is an include guard.
NAME = re.compile(r'^(CFE_|OS_|OSAL_)\w+$')
# `#define NAME 123`, `0x7F`, `-1`, `'$'`, a parenthesised expression of those, or a literal
# with a HolyC POSTFIX CAST -- `0xC2000002(I32)`, which is how NASA's own
# `((CFE_Status_t)0xc2000002)` has to be written here so the value compares equal to an I32.
# THAT SUFFIX WAS WHAT THIS REGEX MISSED. Adding the casts to 29 status codes dropped the
# compared count from 310 to 284 and the tool said nothing: a `#define` it cannot parse is a
# `#define` it never sees, and an unseen constant passes. The suffix is now part of the pattern
# and `literal()` applies the cast, so a cast value is compared like any other.
DEFINE = re.compile(r"^[ \t]*#define[ \t]+([A-Za-z_]\w*)[ \t]+"
                    r"(0[xX][0-9A-Fa-f]+(?:\((?:I|U)(?:8|16|32|64)\))?|-?\d+|'.'|\([^)]*\))"
                    r"[ \t]*(?://.*)?$", re.M)
# The postfix cast, split off by literal() below.
CASTED = re.compile(r"^(0[xX][0-9A-Fa-f]+)\((I|U)(8|16|32|64)\)$")


def hc_defines():
    """{name: (literal text, file)} for every numeric #define in the translation."""
    out = {}
    for d in (os.path.join(ROOT, "Kernel", "Cfs", "osal"), os.path.join(ROOT, "Kernel", "Cfs", "cfe")):
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            txt = open(os.path.join(d, fn), errors="replace").read()
            for m in DEFINE.finditer(txt):
                name, lit = m.group(1), m.group(2)
                if not NAME.match(name) or name.endswith("_HC"):
                    continue
                out.setdefault(name, (lit, fn))
    return out


def probe(names):
    """{name: value or None} as the host C preprocessor sees it. None = NASA does not define it."""
    src = os.path.join(ROOT, "build", "cfs", "check_constants_probe.c")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    # check_padding's list PLUS each module's "module_all" header, which is the superset a
    # module's own sources include. Without them a name like CFE_EVS_HK_TLM_MID is simply not
    # visible, and it would land in the "NASA does not define it" bucket and pass -- which is
    # how the first negative control on this tool failed to fire.
    hdrs = list(check_padding.HDRS) + [
        "cfe_evs_module_all.h", "cfe_ta_task.h", "cfe_ta_msgids.h", "cfe_ta_fcncodes.h",
        "cfe_evs_msgids.h", "cfe_evs_fcncodes.h", "cfe_sb_msgids.h", "cfe_es_msgids.h",
        "cfe_tbl_msgids.h", "cfe_time_msgids.h", "cfe_perfids.h", "cfe_platform_cfg.h",
        "cfe_mission_cfg.h", "cfe_error.h", "cfe_version.h",
        # The msg module's defaults (CCSDSVER, DEFAULT_APID, DEFAULT_SUBSYS, EDSVER) live in a
        # module-private header, and ta's task priority/stack in its platform config. Both were
        # found by the unseen-but-defined check rather than by anyone noticing.
        "cfe_msg_defaults.h", "cfe_ta_platform_cfg.h",
    ]
    body = ["#include <stdio.h>"] + ['#include "%s"' % h for h in hdrs]
    body.append("int main(void){")
    for n in names:
        body.append("#ifdef %s" % n)
        # The cast to long long is what makes a width-independent comparison possible; the
        # caller masks to 32 bits.
        body.append('  printf("%%s %%lld\\n", "%s", (long long)(%s));' % (n, n))
        body.append("#else")
        body.append('  printf("%%s UNDEF\\n", "%s");' % n)
        body.append("#endif")
    body.append("  return 0; }")
    open(src, "w").write("\n".join(body) + "\n")
    exe = src[:-2]
    cc = os.environ.get("HOSTCC", "cc")
    r = subprocess.run([cc, "-O0", "-w"] + check_padding.INC + ["-o", exe, src],
                       capture_output=True, text=True)
    if r.returncode:
        return None, r.stderr
    out = {}
    for line in subprocess.run([exe], capture_output=True, text=True).stdout.split("\n"):
        p = line.split()
        if len(p) != 2:
            continue
        out[p[0]] = None if p[1] == "UNDEF" else int(p[1])
    return out, None


def literal(lit):
    """The translation's spelling as an integer, or None if it is not a plain literal."""
    lit = lit.strip()
    if lit.startswith("'") and lit.endswith("'") and len(lit) == 3:
        return ord(lit[1])
    m = CASTED.match(lit)
    if m:
        # `0xC2000002(I32)` is NASA's `((CFE_Status_t)0xc2000002)`: the bits, narrowed to the
        # cast's width and sign-extended if it is signed. The comparison below masks to 32 bits
        # either way, so this only has to get the low word right.
        v = int(m.group(1), 16)
        bits = int(m.group(3))
        v &= (1 << bits) - 1
        if m.group(2) == "I" and v >> (bits - 1):
            v -= 1 << bits
        return v
    try:
        return int(lit, 0)
    except ValueError:
        return None


_VENDOR_DEFS = None


def vendor_defines(name):
    """True if NASA's tree defines this name as a #define anywhere.

    An ENUMERATOR is deliberately not counted: a C enum member is not a #define, so the
    translation has to invent a #define for it and there is nothing to compare against. The
    distinction this makes is the one that matters -- a #define NASA has and the probe cannot
    see means a header is missing from the list above."""
    global _VENDOR_DEFS
    if _VENDOR_DEFS is None:
        _VENDOR_DEFS = set()
        pat = re.compile(r'^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)', re.M)
        for root in (os.path.join(ROOT, "vendor", "cFE"), os.path.join(ROOT, "vendor", "osal"),
                     os.path.join(ROOT, "vendor", "PSP"), os.path.join(ROOT, "vendor", "shim"),
                     os.path.join(ROOT, "build", "cfs")):
            for dirpath, _dirs, files in os.walk(root):
                for f in files:
                    if not (f.endswith(".h") or f.endswith(".h.in")):
                        continue
                    try:
                        txt = open(os.path.join(dirpath, f), errors="replace").read()
                    except OSError:
                        continue
                    _VENDOR_DEFS.update(pat.findall(txt))
    return name in _VENDOR_DEFS


def main(argv):
    verbose = "-v" in argv
    mine = hc_defines()
    if not mine:
        print("FAIL cfs-constants — no numeric #define found in the translation", file=sys.stderr)
        return 1
    real, err = probe(sorted(mine))
    if real is None:
        print("FAIL cfs-constants — the probe did not compile.", file=sys.stderr)
        print("\n".join(str(err).split("\n")[:20]), file=sys.stderr)
        return 1

    bad, checked, local, skipped, unseen = [], 0, [], [], []
    for name in sorted(mine):
        lit, fn = mine[name]
        nasa = real.get(name)
        if nasa is None:
            # NASA does not define it HERE. Two very different cases, and conflating them is
            # how this tool's first negative control failed to fire: a name NASA defines
            # somewhere in the vendor tree that the probe cannot SEE is a missing header, not a
            # port-local constant, and it has to fail rather than be counted.
            if vendor_defines(name):
                unseen.append((name, fn))
            else:
                local.append((name, fn))
            continue
        v = literal(lit)
        if v is None:
            # A parenthesised expression. Its VALUE still has to be right, but this tool does
            # not evaluate HolyC; it is reported rather than silently passed.
            skipped.append((name, lit, fn))
            continue
        checked += 1
        if (v & 0xFFFFFFFF) != (nasa & 0xFFFFFFFF):
            bad.append("    %-44s %s: %s   NASA: %d" % (name, fn, lit, nasa))

    if bad:
        print("FAIL cfs-constants — a constant in the translation does not have NASA's value.",
              file=sys.stderr)
        print("  Every one of these is a number typed from a header, and nothing else here", file=sys.stderr)
        print("  checks it: a message id that nothing routes or an event id that no branch", file=sys.stderr)
        print("  reaches is invisible to the transcript.", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1

    if unseen:
        print("FAIL cfs-constants — NASA defines these, and the probe cannot SEE them, so their",
              file=sys.stderr)
        print("  values are NOT being compared. Add the header that defines each one to the",
              file=sys.stderr)
        print("  list in check_constants.py. A name that is merely uncompared passes, which is",
              file=sys.stderr)
        print("  exactly how this tool's first negative control failed to fire:", file=sys.stderr)
        for n, fn in unseen:
            print("    %-44s %s" % (n, fn), file=sys.stderr)
        return 1

    if verbose:
        print("  NASA does not define these (enumerators, or names this port invented):")
        for n, fn in local:
            print("    %-44s %s" % (n, fn))
        if skipped:
            print("  not a plain literal, so the value is not compared here:")
            for n, lit, fn in skipped:
                print("    %-44s %s: %s" % (n, fn, lit))
    print("cfs-constants: %d constants match NASA's values (%d names NASA does not define, "
          "%d expressions not compared)" % (checked, len(local), len(skipped)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
