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

### THE OTHER DIRECTION IS GATED TOO, AND GETTING IT RIGHT TOOK THREE TRIES

A member NASA's body touches and the translation's does not is the MIRROR defect -- a DROPPED
assignment -- and no other gate in this directory looks for one. The raw count was 35 across 26
names, almost all false, because NASA guards whole statements on platform switches:
CFE_TIME_SetSourceCmd's `CFE_TIME_Global.CommandCounter++` is inside
`#if (CFE_PLATFORM_TIME_CFG_SOURCE == true)`, FALSE here, correctly omitted and documented at the
site. So the pass needs to know what this configuration compiles.

**Try 1: `cc -E` and read the result.** 35 -> 21. Wrong, because `cc -E` also EXPANDS MACROS and
that INVENTS members: the preprocessed CFE_TA_Cpu_Set touches `.affinity_mask` because
OS_CPUSET_ZERO expands to it, while the translation -- correctly -- still calls OS_CPUSET_ZERO.

**Try 2: intersect the expanded body with NASA's raw body.** 21 -> 12. Still wrong, and the way it
was wrong is the lesson. CFE_TIME_ToneData has TWO bodies behind
`#ifdef CFE_PLATFORM_TIME_CFG_BIGENDIAN`: one that assigns `.Seconds` directly and one that calls
CFE_TIME_Copy. BIGENDIAN is undefined here, the translation took the CFE_TIME_Copy branch
correctly, and the gate reported `.Seconds` missing anyway -- because the EXPANDED body has it
from CFE_TIME_Copy and the RAW body has it from the DEAD branch. Two unrelated occurrences of one
name, paired by a set intersection that cannot see where either came from. That is exactly the
shape docs/ records as *"a cross-check is worth only the inputs the two tools do not share"*.

**Try 3, and what ships: preprocess for LINE LIVENESS ONLY.** `live_raw()` replaces every
non-directive line with a unique marker, keeps the directives verbatim, and preprocesses that --
so `#if` still evaluates against the real headers while NOTHING in the code can expand. The
markers that survive name the live lines, and NASA'S OWN TEXT for those lines is what the pass
reads. No expansion, no intersection, and the comparison is per-site rather than per-name.

That leaves 10, a RULE and a list, and NONE of them is a defect:

  - **DESIGNATED INITIALISERS** (3). NASA writes `{ .InitialValue = 0, .FinalXOR = 0 }`; HolyC has
    no designated-initialiser syntax, so the translation writes `{0, 0, ...}` positionally and
    names no field. Safe only because check_structs and check_padding pin the field ORDER against
    NASA's -- so this rule is really a claim about those two gates. **ANCHORED TO `{` OR `,`,**
    which C syntax requires and the first version did not: unanchored, `.PassCounter = 0` in a
    PLAIN ASSIGNMENT matched, so the rule swallowed the very defect this pass exists to find. The
    driven control came back green with the "positional" count up by one. A rule that cannot be
    shown to REFUSE anything is not a rule.
  - **REVERSE_EXEMPT** (7), each with its reason: five are a LOCAL UNION collapsed to one variable
    (`union { CFE_ES_AppId_t AppId; CFE_ES_LibId_t LibId; }` is one U32 here, because every
    resource id is), and two are `sizeof` through a `->`, which HolyC limit #16 refuses, so
    `sizeof(CDS->Cache.Data.Zero)` is written out as the constant 16. That 16 was CHECKED, not
    assumed: cfe_es_cds.h:126 declares `uint32 Zero[4]`.

BOTH DIRECTIONS HAVE A DRIVEN CONTROL. Forward: retype `RecomputeAppEntryPtr` as
`RecomputeTablesEntryPtr` in cs_app_cmds.HC and the gate names the function. Reverse: delete
`CS_AppData.HkPacket.Payload.PassCounter = 0;` from CS_ResetCountersCmd and it names that one.

### WHAT IT IS NOT

Not a type checker: it compares names, so assigning the right member the wrong VALUE is invisible
here. Not a lexer: strings are blanked first, because `CFE_SB_LockSharedData("cfe_sb_task.c", 310)`
otherwise contributes a member named `c` -- which it did, five times, in the first run.
"""
import importlib.util
import os
import re
import subprocess
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
    # HolyC HAS NO F32, so where NASA memcpys four bytes into a `float` and touches no member at
    # all, the translation reads the 32-bit BIT PATTERN out of LC_MultiType_t and converts it with
    # Kernel/Cfs/CfsF32.HC. The member access is therefore extra by construction.
    #
    # KEYED ON `float` IN NASA'S BODY, AND THAT IS NARROWER THAN IT LOOKS: exactly FIVE function
    # bodies in the whole NASA corpus mention the word, and two of those are in utstubs.c, which
    # is a unit-test stub this port does not gate. The other three are LC_FloatCompare,
    # LC_WPOffsetValid and LC_ValidateWDT -- the only places in cFS that handle a single-precision
    # value. Measured, not estimated.
    "Unsigned32": ("float",),
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


def designated(nasa_body, member):
    """True when NASA names this member with a DESIGNATED INITIALISER, `.Member = ...`.

    HolyC has no designated-initialiser syntax, so the translation writes the same values
    POSITIONALLY and names no field. That is safe only because check_structs and check_padding pin
    the field ORDER against NASA's, which is what makes a positional initialiser mean the same
    thing -- so this rule is really a claim about those two gates, not about this one.
    """
    # ANCHORED TO `{` OR `,`, which is what C syntax requires of a designated initialiser -- and
    # the first version was not, which made this rule swallow the very defect the reverse pass
    # exists to find. `.PassCounter = 0` in a PLAIN MEMBER ASSIGNMENT matched
    # `\.\s*PassCounter\s*=`, so deleting `CS_AppData.HkPacket.Payload.PassCounter = 0;` from
    # CS_ResetCountersCmd was excused rather than reported: the driven control came back rc=0 with
    # the "positional" count up by one. A rule that cannot be shown to REFUSE anything is not a
    # rule.
    return re.search(r"[{,]\s*\.\s*%s\s*=" % re.escape(member), nasa_body) is not None

# (holyc file, function, member) the REVERSE pass may not find in the translation, WITH THE REASON.
# Each is a claim about the translation that the next reader can check at the named site.
REVERSE_EXEMPT = {
    # NASA: `union { CFE_ES_AppId_t AppId; CFE_ES_LibId_t LibId; } IdBuf;` -- two names for one
    # word, chosen by which branch runs. Every resource id in this port is a bare U32, so the union
    # has nothing to overlay and collapses to one variable. Documented at both sites.
    ("cfe_es_startupscript.HC", "CFE_ES_ParseFileEntry", "AppId"): "local union collapsed to one U32",
    ("cfe_es_startupscript.HC", "CFE_ES_ParseFileEntry", "LibId"): "local union collapsed to one U32",
    ("cfe_es_task.HC", "CFE_ES_QueryOneCmd", "AppId"): "local union collapsed to one U32",
    ("cfe_es_task.HC", "CFE_ES_QueryOneCmd", "LibId"): "local union collapsed to one U32",
    ("cfe_es_task.HC", "CFE_ES_QueryOneCmd", "ResourceID"): "local union collapsed to one U32",
    # `sizeof(CDS->Cache.Data.Zero)` -- sizeof through a `->` is HolyC limit #16, so the constant
    # is written out. It is 16, and that was checked: cfe_es_cds.h:126 is `uint32 Zero[4]`.
    ("cfe_es_cds.HC", "CFE_ES_ClearCDS", "Data"): "sizeof through -> written out as 16 (limit #16)",
    ("cfe_es_cds.HC", "CFE_ES_ClearCDS", "Zero"): "sizeof through -> written out as 16 (limit #16)",
}

_DIRECTIVE = re.compile(r"^\s*#")
_LIVETOK = re.compile(r"__CFSLIVE_(\d+)__")


def live_raw(path, inc, cc):
    """NASA's own source with the lines this configuration does NOT compile blanked out.

    WHY NOT JUST `cc -E`. The obvious move is to preprocess and read the result, and the first
    version of this did -- but `cc -E` also EXPANDS MACROS, and that broke the reverse pass in a
    way worth recording. CFE_TIME_ToneData has TWO bodies behind
    `#ifdef CFE_PLATFORM_TIME_CFG_BIGENDIAN`: a byte-swapping one that assigns `.Seconds` and
    `.Subseconds` directly, and a CFE_TIME_Copy one. BIGENDIAN is not defined here, so the
    translation correctly took the second -- and the gate reported `.Seconds` missing anyway,
    because the expanded CFE_TIME_Copy contains `.Seconds` and the RAW text contains `.Seconds`
    in the DEAD branch. Two unrelated occurrences of one name, paired by a set intersection that
    could not see where either came from. That is the shape docs/ records as "a cross-check is
    worth only the inputs the two tools do not share".

    SO THIS PREPROCESSES FOR LINE LIVENESS ONLY. Every non-directive line is replaced by a unique
    marker and the directives are kept verbatim, so `#if` still evaluates against the real headers
    while nothing in the code can expand. The markers that survive name the live lines, and the
    ORIGINAL text of those lines is what comes back. Blanked lines keep their newline, so line
    numbers and brace matching are unaffected.
    """
    lines = open(path, errors="replace").read().split("\n")
    # A DIRECTIVE MAY CONTINUE ONTO THE NEXT LINE WITH A BACKSLASH, and replacing that
    # continuation with a marker breaks the directive -- mm_dump.c:263 is
    # `#if defined(A) || defined(B) \` over two lines, and clang answered "token is not a valid
    # binary operator in a preprocessor subexpression". Caught because this gate refuses to pass
    # when the preprocessor refuses it, which is the whole reason that check is there.
    keep = [False] * len(lines)
    cont = False
    for i, l in enumerate(lines):
        if _DIRECTIVE.match(l) or cont:
            keep[i] = True
            cont = l.rstrip().endswith("\\")
        else:
            cont = False
    probe = [l if keep[i] else ("__CFSLIVE_%d__" % i) for i, l in enumerate(lines)]
    tmp = os.path.join(ROOT, "build", "cfs", "members_liveprobe.c")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    open(tmp, "w").write("\n".join(probe) + "\n")
    r = subprocess.run([cc, "-E", "-w"] + inc + [tmp], capture_output=True, text=True)
    if r.returncode:
        return None
    live = {int(m.group(1)) for m in _LIVETOK.finditer(r.stdout)}
    # A directive line is neither live nor dead code; keep it so brace matching sees the braces
    # a conditional body opens, and blank everything the configuration excluded.
    return "\n".join(l if (i in live or keep[i]) else "" for i, l in enumerate(lines))


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

    # The reverse pass needs the host preprocessor and check_padding's include list, which is the
    # one place in this directory that already knows how to reach NASA's headers.
    spec = importlib.util.spec_from_file_location(
        "check_padding", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "check_padding.py"))
    cp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cp)
    cc = os.environ.get("HOSTCC", "cc")
    live_cache = {}

    def live_bodies(path):
        """NASA's own bodies with the lines this configuration excludes blanked, cached per file."""
        if path not in live_cache:
            text = live_raw(path, cp.INC, cc)
            if text is None:
                live_cache[path] = None
            else:
                tmp = os.path.join(ROOT, "build", "cfs", "members_live.c")
                os.makedirs(os.path.dirname(tmp), exist_ok=True)
                open(tmp, "w").write(text)
                live_cache[path] = bodies(tmp)
        return live_cache[path]

    compared = allowed = refs = 0
    rev_rule = rev_exempt = 0
    bad = []
    dropped = []
    cpp_failed = []
    for hcdir in HCDIRS:
        if not os.path.isdir(hcdir):
            continue
        for fn in sorted(os.listdir(hcdir)):
            if not fn.endswith(".HC"):
                continue
            base = fn[:-3]
            csources = by_name.get(base + ".c", [])
            sources = csources + by_name.get(base + ".h", [])
            if not sources:
                continue
            theirs_all = {}
            for p in sources:
                theirs_all.update(bodies(p))
            ours_all = bodies(os.path.join(hcdir, fn))
            short = os.path.join(os.path.basename(hcdir), fn)

            # --- FORWARD: a member the translation touches and NASA's body does not.
            for name, body in ours_all.items():
                if name not in theirs_all:
                    continue
                compared += 1
                nasa_body = theirs_all[name]
                theirs = set(MEMBER.findall(nasa_body))
                ours = set(MEMBER.findall(body))
                refs += len(ours)
                for member in sorted(ours - theirs):
                    causes = EXPANSIONS.get(member)
                    if causes and any(c in nasa_body for c in causes):
                        allowed += 1
                        continue
                    bad.append((short, name, member))

            # --- REVERSE: a member NASA's LIVE body touches and the translation's does not.
            # Only .c files: a header inline's body is compared where its .c lands.
            for p in csources:
                live = live_bodies(p)
                if live is None:
                    cpp_failed.append(os.path.relpath(p, ROOT))
                    continue
                for name, live_body in live.items():
                    if name not in ours_all:
                        continue
                    # live_body is NASA'S OWN TEXT with the excluded lines blanked -- no macro
                    # expansion, so no intersection is needed and none would be sound.
                    missing = set(MEMBER.findall(live_body)) - set(MEMBER.findall(ours_all[name]))
                    for member in sorted(missing):
                        if designated(live_body, member):
                            rev_rule += 1
                            continue
                        if (fn, name, member) in REVERSE_EXEMPT:
                            rev_exempt += 1
                            continue
                        dropped.append((short, name, member))

    if cpp_failed:
        print("FAIL cfs-members — the host C preprocessor refused %d NASA source(s), so the"
              % len(cpp_failed), file=sys.stderr)
        print("     reverse pass could not see what this configuration compiles. A gate that", file=sys.stderr)
        print("     cannot read its input must not report a pass:", file=sys.stderr)
        for p in cpp_failed[:10]:
            print("  %s" % p, file=sys.stderr)
        return 1

    if bad or dropped:
        if bad:
            print("FAIL cfs-members — these functions touch a struct member NASA's own body for",
                  file=sys.stderr)
            print("     the same function does not. A member SWAP passes every other gate and", file=sys.stderr)
            print("     the compiler, because a HolyC cast relabels rather than converts:", file=sys.stderr)
            for path, func, member in bad[:40]:
                print("  %s  %s  ->%s" % (path, func, member), file=sys.stderr)
            if len(bad) > 40:
                print("  ... and %d more" % (len(bad) - 40), file=sys.stderr)
            print("     Fix the translation, or add the name to tools/cfs/check_members.py's",
                  file=sys.stderr)
            print("     EXPANSIONS keyed on the MACRO in NASA's body that produces it.",
                  file=sys.stderr)
        if dropped:
            print("FAIL cfs-members — NASA's own body for these functions touches a member the",
                  file=sys.stderr)
            print("     translation does not, in code THIS CONFIGURATION COMPILES. That is a", file=sys.stderr)
            print("     DROPPED assignment, and no other gate looks for one:", file=sys.stderr)
            for path, func, member in dropped[:40]:
                print("  %s  %s  ->%s" % (path, func, member), file=sys.stderr)
            if len(dropped) > 40:
                print("  ... and %d more" % (len(dropped) - 40), file=sys.stderr)
            print("     Fix the translation, or record the site in tools/cfs/check_members.py's",
                  file=sys.stderr)
            print("     REVERSE_EXEMPT with the reason it cannot appear.", file=sys.stderr)
        return 1

    print("cfs-members: %d member references across %d functions are all members NASA's own body "
          "touches, and every member NASA's LIVE body touches is in the translation "
          "(%d allowed by a named macro expansion; %d positional where NASA designated, "
          "%d exempt by site)"
          % (refs, compared, allowed, rev_rule, rev_exempt))
    return 0


if __name__ == "__main__":
    sys.exit(main())
