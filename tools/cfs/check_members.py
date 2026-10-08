#!/usr/bin/env python3
"""Every struct member a translated FUNCTION touches must be one NASA's same function touches.

WHY THIS GATE EXISTS, and it is the gate that was missing when a one-line defect got through.
cs_app_cmds.HC was GENERATED from its twin cs_eeprom_cmds.HC... no: from cs_table_cmds.HC, by an
explicit name map, because NASA's two sources are line-for-line twins. The map rewrote

    CS_AppData.RecomputeTablesEntryPtr = ResultsEntry;   /* cs_table_cmds.c, correct there */

and did NOT rewrite it, because `RecomputeTablesEntryPtr` is not any of the words the map knew
about. NASA's cs_app_cmds.c:161 assigns RecomputeAppEntryPtr. So CS's app recompute command handed
its child task a pointer stored in the WRONG member -- CS_RecomputeAppChildTask reads
RecomputeAppEntryPtr, which was still NULL -- and every gate passed:

  - check_coverage: the function exists.          - check_signatures: its signature matches.
  - check_structs/padding: both members exist.    - check_constants: no constant involved.
  - check_strings: every literal is NASA's.       - check_variadic: the call agrees.
  - the HolyC compiler: a pointer assignment between two class pointers is accepted, because a
    cast in HolyC RELABELS rather than converts.
  - the C compiler never saw it: the oracle compiles NASA's C, not the translation.

It was caught by the TRANSCRIPT -- `ptr=1` against `ptr=0` on one line of CS's exercise -- and
only because that exercise happened to print the pointer as a comparison. A member swap in a
function nobody exercises would still be there.

### WHAT IT COMPARES

For every function the translation and NASA both define: the SET of names appearing after a `.`
or `->`. Members are the one part of this translation that is never renamed -- check_structs and
check_padding enforce that field for field -- so the two sets should agree, and a name in the
translation's set that is not in NASA's is either a defect or one of the five documented
expansions below.

53 extra names across 1042 functions, five distinct, every one a macro or compound literal
NASA writes and HolyC has no spelling for:

  Msg        (33)  CFE_MSG_PTR(x) is `&(x).Msg`, written out
  Seconds     (9)  `CFE_TIME_SysTime_t PktTime = { 0 }` and `= CFE_TIME_ZERO_VALUE`, which is the
  Subseconds  (9)  compound literal (CFE_TIME_SysTime_t){0, 0} -- HolyC has neither spelling, so
                   the two members are assigned explicitly
  ticks       (1)  the same thing for OS_time_t
  FileSize    (1)  OS_FILESTAT_SIZE(x) is `((x).FileSize)`, written out

Each is allowed only WHERE ITS CAUSE IS PRESENT IN NASA'S OWN BODY for that function: `Msg` needs
CFE_MSG_PTR, `FileSize` needs OS_FILESTAT_SIZE, and the three initialiser members need the
AGGREGATE FORM -- `= { 0 }` or CFE_TIME_ZERO_VALUE -- and NOT merely the type's name. Keying those
three on the type was the first version and it was too weak by exactly the amount that matters:
any body that declared a CFE_TIME_SysTime_t would have excused a `.Seconds` swap anywhere in it.
The narrower rule allows the same 45, which is how it was checked rather than argued.

### THE OTHER DIRECTION IS MEASURED AND NOT YET GATED, AND THE REASON IS PRECISE

A member NASA's body touches and the translation's does not is 35 cases, 26 distinct names, and
the first one examined explains the shape: CFE_TIME_SetSourceCmd's `CFE_TIME_Global.CommandCounter++`
lives inside `#if (CFE_PLATFORM_TIME_CFG_SOURCE == true)`, which is FALSE in this configuration,
so the translation correctly omits it and says so at the site. Gating that direction means
evaluating NASA's #if blocks -- the same work check_coverage's CONFIG_EXCLUDED does by hand -- and
it is a separate change rather than a line in this one. The count is printed so it can be watched.

### WHAT IT IS NOT

Not a type checker: it compares names, so assigning the right member the wrong VALUE is invisible
here. Not a lexer: strings are blanked first, because `CFE_SB_LockSharedData("cfe_sb_task.c", 310)`
otherwise contributes a member named `c` -- which it did, five times, in the first run.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS, ROOT, app_dirs                       # noqa: E402
from cfs_text import strip_comments                               # noqa: E402

MEMBER = re.compile(r'(?:\.|->)\s*([A-Za-z_][A-Za-z0-9_]*)')
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# A function definition: a return type and name, a parameter list with no `;` in it, then `{`.
# The same shape check_coverage uses, and it misses the same things -- which is safe here,
# because a function this does not find is a function it does not check.
DEFN = re.compile(r'^[A-Za-z_][A-Za-z0-9_ \t\*]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*\{',
                  re.M | re.S)

# name -> what must appear in NASA'S OWN BODY for that name to be allowed. A rule keyed on the
# cause, so the same member is still refused in a function where the cause is absent.
EXPANSIONS = {
    "Msg": ("CFE_MSG_PTR",),
    "FileSize": ("OS_FILESTAT_SIZE",),
    # KEYED ON THE INITIALISER FORM, NOT ON THE TYPE NAME, and that distinction was the whole
    # point of a review. A first version keyed these three on `CFE_TIME_SysTime_t` and `OS_time_t`
    # -- so ANY NASA body that merely DECLARED one of those types excused a `.Seconds` reference
    # anywhere in the translation of that function, which is most of cfe_time and exactly where
    # such a swap is most likely. The docstring claimed a cause-keyed rule "cannot excuse the same
    # name somewhere it does not apply", and for those three it could. Requiring the aggregate
    # form instead -- `= { 0 }` or CFE_TIME_ZERO_VALUE, the compound literal
    # `(CFE_TIME_SysTime_t){0, 0}` -- keeps the allowed count at exactly 45, so the narrower rule
    # costs nothing and the docstring is now true.
    "Seconds": ("= { 0 }", "CFE_TIME_ZERO_VALUE"),
    "Subseconds": ("= { 0 }", "CFE_TIME_ZERO_VALUE"),
    "ticks": ("= { 0 }",),
}


def bodies(path):
    """name -> body text (braces included), comments removed and strings blanked."""
    text = STRING.sub('""', strip_comments(open(path, errors="replace").read()))
    out = {}
    for m in DEFN.finditer(text):
        name = m.group(1)
        i = text.index("{", m.start())
        depth = 0
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    out.setdefault(name, text[i:j + 1])
                    break
    return out


def main():
    by_name = {}
    for root in [os.path.join(ROOT, "vendor", "cFE"), os.path.join(ROOT, "vendor", "osal")] + \
            list(app_dirs()):
        for dirpath, _, filenames in os.walk(root):
            for fn in filenames:
                if fn.endswith((".c", ".h")):
                    by_name.setdefault(fn, []).append(os.path.join(dirpath, fn))
    if not by_name:
        print("FAIL cfs-members — no NASA sources under vendor/; this gate would pass on an "
              "empty haystack, which is the not-found shape it exists to avoid.", file=sys.stderr)
        return 1

    compared = allowed = refs = 0
    absent = 0
    bad = []
    for hcdir in HCDIRS:
        if not os.path.isdir(hcdir):
            continue
        for fn in sorted(os.listdir(hcdir)):
            if not fn.endswith(".HC"):
                continue
            base = fn[:-3]
            sources = by_name.get(base + ".c", []) + by_name.get(base + ".h", [])
            if not sources:
                continue
            theirs_all = {}
            for p in sources:
                theirs_all.update(bodies(p))
            for name, body in bodies(os.path.join(hcdir, fn)).items():
                if name not in theirs_all:
                    continue
                compared += 1
                nasa_body = theirs_all[name]
                theirs = set(MEMBER.findall(nasa_body))
                ours = set(MEMBER.findall(body))
                refs += len(ours)
                absent += len(theirs - ours)
                for member in sorted(ours - theirs):
                    causes = EXPANSIONS.get(member)
                    if causes and any(c in nasa_body for c in causes):
                        allowed += 1
                        continue
                    bad.append((os.path.join(os.path.basename(hcdir), fn), name, member))

    if bad:
        print("FAIL cfs-members — these functions touch a struct member NASA's own body for the",
              file=sys.stderr)
        print("     same function does not. A member SWAP passes every other gate and the", file=sys.stderr)
        print("     compiler, because a HolyC cast relabels rather than converts:", file=sys.stderr)
        for path, func, member in bad[:40]:
            print("  %s  %s  ->%s" % (path, func, member), file=sys.stderr)
        if len(bad) > 40:
            print("  ... and %d more" % (len(bad) - 40), file=sys.stderr)
        print("     Fix the translation, or add the name to tools/cfs/check_members.py's",
              file=sys.stderr)
        print("     EXPANSIONS keyed on the MACRO in NASA's body that produces it.", file=sys.stderr)
        return 1

    print("cfs-members: %d member references across %d functions are all members NASA's own body "
          "touches (%d allowed by a named macro expansion; %d members NASA touches and the "
          "translation does not, NOT yet gated -- see the docstring)"
          % (refs, compared, allowed, absent))
    return 0


if __name__ == "__main__":
    sys.exit(main())
