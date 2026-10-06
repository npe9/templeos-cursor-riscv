#!/usr/bin/env python3
"""A variadic function's call sites must KNOW it is variadic, and no declaration may disagree.

WHY THIS EXISTS. A HolyC variadic function receives an implicit (argc, argv) pair, and the CALL
SITE is what builds it -- so a call compiled before the compiler has seen a `...` declaration
packs nothing, and the callee reads whatever the ABI left behind. Nothing is reported at compile
time. Nothing is reported at run time either, unless the callee actually reads argv: a format
string with no conversions passes, and the same call with a %d in it reads an arbitrary address.

Measured, both shapes were present in this tree at once and both were passing:

  - EVS_SendEvent, defined at the bottom of cfe_evs_utils.HC and called from four places above
    it with no prototype. It reached StrPrintNV as nargs=1 with args=NULL and faulted on a load
    from address 0 -- but only once EVS was wired into the differential driver. Before that the
    calls were never reached.
  - CFE_EVS_SendEvent, declared NON-VARIADIC in cfe_ta_task.HC (a three-parameter stub
    declaration left from when EVS was not translated) and defined VARIADIC in cfe_evs.HC, which
    is included after it. Every TA event call went through the non-variadic declaration and
    silently dropped NASA's arguments.

NOTHING ELSE HERE SEES EITHER. check_signatures.py compares the DEFINITION's arity against
NASA's and both definitions were right; check_coverage only asks whether a name exists; and the
transcript sees a dropped argument only where some driver line happens to format it. The second
shape in particular is invisible to every function-level gate, because the thing that is wrong
is a declaration, not a definition.

THE TWO PROPERTIES.

  1. AGREEMENT WITH NASA. Every HolyC declaration or definition of a name NASA declares variadic
     must itself be variadic, and vice versa. Tree-wide, so it does not depend on a driver.
  2. DECLARED BEFORE CALLED. Flattening each driver's #include graph in order gives the exact
     sequence the compiler sees; in that sequence the first variadic declaration of a name must
     come before every call to it.

    tools/cfs/check_variadic.py          # check
    tools/cfs/check_variadic.py -v       # and list what was checked
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS  # ONE copy of this list -- see cfs_dirs.py

# The drivers whose include order is the compiler's order. Both halves of the port are reached
# from one of these two.
DRIVERS = [
    os.path.join(ROOT, "tests", "exec", "cases", "cfs_xlat_ccsdspri.hc"),
    os.path.join(ROOT, "tests", "exec", "cases", "osal_xlat_errors.hc"),
]

VENDOR = [os.path.join(ROOT, "vendor", d) for d in ("cFE", "osal", "PSP", "shim")]

# A function declaration or definition at file scope: a return type in column 1, a name, a
# parameter list, then ';' or '{'. Deliberately anchored at the start of the line, because that
# is how both NASA's sources and this translation are formatted and it keeps calls out.
FUNC = re.compile(
    r'^(?:[A-Za-z_][\w]*\s+)+\**\s*([A-Za-z_]\w*)\s*\(([^;{)]*(?:\)[^;{)]*)*?)\)\s*(;|\{)',
    re.M)

# Names this port invents or deliberately reshapes, with the reason. A name here is NOT exempt
# from property 2 -- only from the comparison against NASA.
DEVIATIONS = {
    "EVS_GenerateEventTelemetry":
        "NASA takes a va_list; HolyC has no va_list, so the one parameter becomes the "
        "(nargs, args) pair -- it is NOT variadic here and must not be.",
    "CFE_ES_WriteToSysLog":
        "NASA's call sites are all `\"%s: ...\", __func__`. HolyC has no __func__, so the "
        "translation writes the function's name into the literal -- which produces the SAME "
        "TEXT, because that is what __func__ expands to. NOT ENFORCED BEYOND THIS LINE: nothing "
        "here counts the arguments at a call site, so a future `(\"x %d\", n)` is caught by no "
        "gate. The one-parameter declaration is the only thing holding that.",
    "OS_printf":
        "OSAL reaches it only through BUGCHECK, whose expansion is a single plain string. The "
        "cfe side declares it variadic, because EVS formats through it -- and because this "
        "exemption is by NAME, it covers both spellings. Property 3 below is what catches them "
        "meeting inside one include graph.",
    "StrPrintN": "this port's own, not NASA's",
    "StrPrintNV": "this port's own, not NASA's",
}


def strip_comments(txt):
    """Blank out // and /* */ so a call inside a comment is not a call."""
    txt = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), txt, flags=re.S)
    txt = re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), txt)
    return txt


def strip_strings(txt):
    """Blank out string literals, so a format string naming a function is not a call."""
    return re.sub(r'"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m.group(0)), txt)


def decls(txt):
    """[(name, is_variadic, is_definition, char offset)] for every file-scope declaration."""
    out = []
    for m in FUNC.finditer(txt):
        params = m.group(2)
        out.append((m.group(1), params.rstrip().endswith("..."), m.group(3) == "{", m.start()))
    return out


def nasa_variadics():
    """(set of names NASA declares variadic, set of every name NASA declares)."""
    va, allnames = set(), set()
    for root in VENDOR:
        for dirpath, _dirs, files in os.walk(root):
            for f in files:
                if not (f.endswith(".h") or f.endswith(".c")):
                    continue
                try:
                    txt = strip_comments(open(os.path.join(dirpath, f), errors="replace").read())
                except OSError:
                    continue
                for name, isva, _isdef, _off in decls(txt):
                    allnames.add(name)
                    if isva:
                        va.add(name)
    return va, allnames


def flatten(path, seen=None, out=None):
    """The ordered (file, line, text) sequence the compiler sees, following #include."""
    if seen is None:
        seen, out = set(), []
    rp = os.path.realpath(path)
    if rp in seen or not os.path.isfile(rp):
        return out
    seen.add(rp)
    for i, line in enumerate(open(rp, errors="replace").read().split("\n"), 1):
        m = re.match(r'\s*#include\s+"([^"]+)"', line)
        if m:
            inc = m.group(1)
            # The compiler resolves a leading '/' against HOLYC_INCLUDE_ROOT.
            cand = os.path.join(ROOT, inc.lstrip("/")) if inc.startswith("/") \
                else os.path.join(os.path.dirname(rp), inc)
            flatten(cand, seen, out)
            continue
        out.append((rp, i, line))
    return out


def main(argv):
    verbose = "-v" in argv
    nasa_va, nasa_all = nasa_variadics()

    hc_files = []
    for p in HCDIRS:
        if os.path.isdir(p):
            hc_files += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.endswith(".HC")]
    hc_files += [os.path.join(ROOT, "Kernel", "Cfs", "CfsStr.HC")]
    hc_files += DRIVERS
    hc_files = [f for f in hc_files if os.path.isfile(f)]

    bad = []
    # --- property 1: agreement with NASA ----------------------------------------------------
    hc_va = set()
    checked1 = 0
    for f in hc_files:
        txt = strip_comments(open(f, errors="replace").read())
        for name, isva, isdef, off in decls(txt):
            if isva:
                hc_va.add(name)
            if name in DEVIATIONS or name not in nasa_all:
                continue
            checked1 += 1
            line = txt[:off].count("\n") + 1
            kind = "definition" if isdef else "declaration"
            if name in nasa_va and not isva:
                bad.append("    %s:%d: %s of %s is NOT variadic; NASA's is.\n"
                           "      Its call sites pack no (argc, argv) and the callee reads "
                           "whatever the ABI left." % (os.path.relpath(f, ROOT), line, kind, name))
            elif name not in nasa_va and isva:
                bad.append("    %s:%d: %s of %s IS variadic; NASA's is not."
                           % (os.path.relpath(f, ROOT), line, kind, name))

    # --- property 2: declared variadic before called ----------------------------------------
    checked2 = 0
    for drv in DRIVERS:
        if not os.path.isfile(drv):
            continue
        seq = flatten(drv)
        # Where each variadic name is first declared, in compiler order.
        first = {}
        joined = "\n".join(t for _f, _l, t in seq)
        clean = strip_strings(strip_comments(joined))
        lines = clean.split("\n")
        # Re-run the declaration scan over the flattened text so offsets are comparable.
        for name, isva, _isdef, off in decls(clean):
            if isva and name not in first:
                first[name] = clean[:off].count("\n")
        for name in sorted(set(hc_va) | (nasa_va & set(re.findall(r'[A-Za-z_]\w*', clean)))):
            if name not in first:
                continue      # not declared in this driver's graph at all
            checked2 += 1
            call = re.compile(r'(^|[^\w.>])' + re.escape(name) + r'\s*\(')
            for i, line in enumerate(lines):
                if i >= first[name] or not call.search(line):
                    continue
                f, ln, _t = seq[i]
                bad.append("    %s:%d: calls %s, which is first declared variadic %d lines later "
                           "in %s's include order (%s).\n"
                           "      A HolyC call site builds (argc, argv) only if it already knows "
                           "the callee is variadic." %
                           (os.path.relpath(f, ROOT), ln, name, first[name] - i,
                            os.path.basename(drv), os.path.relpath(seq[first[name]][0], ROOT)))

    # --- property 3: one include graph, one answer -------------------------------------------
    # A name declared both ways inside a single driver's graph is the TA shape: one file's stub
    # declaration and another file's real definition, with the compiler believing whichever it
    # read first. DEVIATIONS does not excuse this one -- the two spellings can each be defensible
    # on their own and still be wrong together.
    checked3 = 0
    for drv in DRIVERS:
        if not os.path.isfile(drv):
            continue
        clean = strip_strings(strip_comments("\n".join(t for _f, _l, t in flatten(drv))))
        kinds = {}
        for name, isva, _isdef, off in decls(clean):
            kinds.setdefault(name, set()).add(isva)
        for name in sorted(kinds):
            checked3 += 1
            if len(kinds[name]) > 1:
                bad.append("    %s: %s is declared BOTH variadic and non-variadic in one "
                           "include graph.\n      The compiler believes whichever it read "
                           "first, and the call sites above the other one are wrong."
                           % (os.path.basename(drv), name))

    if bad:
        print("FAIL cfs-variadic — a variadic function's declarations disagree, or a call "
              "precedes one.", file=sys.stderr)
        print("  Neither is reported by the compiler, and neither is visible to any other gate "
              "here:", file=sys.stderr)
        print("  check_signatures compares DEFINITIONS, and a dropped vararg only reaches the",
              file=sys.stderr)
        print("  transcript where some driver line happens to format it.", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1

    if verbose:
        print("  NASA declares %d variadic functions; this port declares %d."
              % (len(nasa_va), len(hc_va)))
        for n, why in sorted(DEVIATIONS.items()):
            print("    deviation: %s — %s" % (n, why))
    print("cfs-variadic: %d declarations agree with NASA, %d variadic names declared before "
          "every call, %d names consistent within each include graph"
          % (checked1, checked2, checked3))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
