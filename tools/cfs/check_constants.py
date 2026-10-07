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
import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS, APPS  # ONE copy of these lists -- see cfs_dirs.py

# The include path and the header list are check_padding.py's, for the same reason it does not
# duplicate check_structs.py's name mapping: two tools disagreeing about which headers are in
# this configuration would mean one of them is checking something else.
_spec = importlib.util.spec_from_file_location(
    "check_padding", os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_padding.py"))
check_padding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_padding)

# Only names that could plausibly be NASA's. A port-local constant (RV_*, HOLYC_*) is not under
# test, and neither is an include guard.
# MD_ joined for the first cFS app. Without it NOT ONE of MD's constants was a candidate --
# the dwell table size, the four error codes, the signature length -- and the compared count
# would not have moved by one, with no diagnostic anywhere. A gate's own name filter is the
# quietest place a whole module can hide.
# THE APP PREFIXES COME FROM cfs_dirs.APPS, not from a hand-written alternation here. This had
# `MD_` written into it literally, and MM arrived with ~130 hand-resolved constants -- 60 event
# ids, 5 performance ids, the three MsgIds, 40 configuration values -- NOT ONE OF WHICH THIS
# GATE LOOKED AT. The tell was the count: it moved 1,313 to 1,346, and six of those 33 were the
# CFE_PSP_* and OS_* defines mm_utils.HC added. Everything else was include-graph expansion.
#
# That is the module_deps prefix list over again -- a hard-coded alternation is a list someone
# has to remember to extend, and the failure is silent. Four times there, once here.
NAME = re.compile(r'^(CFE_|OS_|OSAL_|%s)\w+$' % '|'.join(a + '_' for a in APPS))

# FOUR NASA NAMES WITH NO MODULE PREFIX AT ALL, so the filter above cannot reach them.
# md_dwell_pkt.h declares an ANONYMOUS enum whose members are spelled
# ONE_BYTE_MEM_ADDR_READ_ERR, TWO_BYTE_MEM_ADDR_READ_ERR, FOUR_BYTE_MEM_ADDR_READ_ERR and
# INVALID_DWELL_ADDR_LEN -- NASA's own spelling, not a transcription slip. They are the four
# values MD_GetDwellData returns, every one of which the transcript compares, and without this
# list they would be non-candidates and silently uncompared. Listed by name rather than by
# loosening the prefix pattern, because the pattern is what keeps port-local constants
# (RV_*, HOLYC_*) out of a gate that has no business judging them.
#
# FILE_CRC_BUFFER_SIZE is the fifth, and a different kind: it is not an interface value at all
# but mm_utils.c's own file-local `#define`, the size of the buffer MM_ComputeCRCFromFile reads
# into. It is here because the number is load-bearing -- CFE_ES_CalculateCRC is called with the
# bytes actually read, not with the buffer size, and a 450-byte exercise file is three reads of
# 200 precisely so the short last read is exercised.
NAME_EXTRA = {"ONE_BYTE_MEM_ADDR_READ_ERR", "TWO_BYTE_MEM_ADDR_READ_ERR",
              "FOUR_BYTE_MEM_ADDR_READ_ERR", "INVALID_DWELL_ADDR_LEN",
              "FILE_CRC_BUFFER_SIZE"}


def is_candidate(name):
    return bool(NAME.match(name)) or name in NAME_EXTRA
# `#define NAME 123`, `0x7F`, `-1`, `'$'`, a parenthesised expression of those, or a literal
# with a HolyC POSTFIX CAST -- `0xC2000002(I32)`, which is how NASA's own
# `((CFE_Status_t)0xc2000002)` has to be written here so the value compares equal to an I32.
# THAT SUFFIX WAS WHAT THIS REGEX MISSED. Adding the casts to 29 status codes dropped the
# compared count from 310 to 284 and the tool said nothing: a `#define` it cannot parse is a
# `#define` it never sees, and an unseen constant passes. The suffix is now part of the pattern
# and `literal()` applies the cast, so a cast value is compared like any other.
# THE TRAILING COMMENT CAN BE `/* */` TOO, and until it could, three constants were silently
# uncompared: OS_FS_DEV_NAME_LEN, OS_FS_PHYS_NAME_LEN and OS_FS_VOL_NAME_LEN are copied from
# osconfig.h WITH NASA's own `/**< ... */` doc comment on the line, and a #define this regex
# cannot parse is a #define it never sees. Same shape as the postfix cast above, found the same
# way -- by counting what the pattern DROPS rather than by trusting what it keeps.
DEFINE = re.compile(r"^[ \t]*#define[ \t]+([A-Za-z_]\w*)[ \t]+"
                    r"(0[xX][0-9A-Fa-f]+(?:\((?:I|U)(?:8|16|32|64)\))?|-?\d+|'.'|\([^)]*\))"
                    r"[ \t]*(?://.*|/\*.*\*/)?$", re.M)
# Every OTHER object-like #define with a NASA-shaped name: a string, an identifier, a macro
# call. They are NOT compared, and the count is printed so the size of that hole is a number
# rather than a silence. The three groups it holds, as of this commit:
#   - STRING constants NASA also defines -- pipe names, default file paths. These DO reach the
#     transcript (an event prints the pipe name), but only where something drives them.
#   - a #define whose value is another macro (CFE_ES_APPID_BASE, CFE_SB_PIPEID_BASE): comparing
#     one would mean expanding the TRANSLATION's macros, which expr_value does for
#     parenthesised expressions and not yet for macro calls.
#   - CFE_CONFIGID_*, which are runtime calls, not constants at all.
ANY_DEFINE = re.compile(r"^[ \t]*#define[ \t]+([A-Za-z_]\w*)[ \t]+(\S.*?)[ \t]*$", re.M)
# The postfix cast, split off by literal() below.
CASTED = re.compile(r"^(0[xX][0-9A-Fa-f]+)\((I|U)(8|16|32|64)\)$")


def hc_defines():
    """{name: (literal text, file)} for every numeric #define in the translation."""
    out = {}
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            txt = open(os.path.join(d, fn), errors="replace").read()
            for m in DEFINE.finditer(txt):
                name, lit = m.group(1), m.group(2)
                if not is_candidate(name) or name.endswith("_HC"):
                    continue
                out.setdefault(name, (lit, fn))
    return out


def unparsed_defines():
    """[(name, value, file)] for NASA-shaped #defines whose value DEFINE cannot read."""
    seen = set(hc_defines())
    out = []
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            txt = open(os.path.join(d, fn), errors="replace").read()
            for m in ANY_DEFINE.finditer(txt):
                name, val = m.group(1), m.group(2)
                if not is_candidate(name) or name.endswith("_HC") or name in seen:
                    continue
                out.append((name, val, fn))
    return out


# NASA .c files whose file-scope `#define`s the probe lifts. Every entry is a file the
# translation restates a constant from; a file missing here shows up as "NASA defines these and
# the probe cannot SEE them", which is this gate's loud path rather than a silent pass.
CSRC_DEFS = [
    os.path.join(ROOT, "vendor", "cFE", "modules", "sb", "fsw", "src", "cfe_sb_buf.c"),
    # The five constants of tbl's load-buffer serial encoding are file-scope #defines in
    # cfe_tbl_loadbuff.c: the two category values, the buffers-per-registry-entry limit, and
    # the two totals derived from them. TOTAL_LOAD_BUFFS in particular is the modulus the
    # whole encoding turns on, so a drift there would silently re-point every buffer id.
    os.path.join(ROOT, "vendor", "cFE", "modules", "tbl", "fsw", "src", "cfe_tbl_loadbuff.c"),
    os.path.join(ROOT, "vendor", "cFE", "modules", "msg", "fsw", "src", "cfe_msg_ccsdspri.c"),
    os.path.join(ROOT, "vendor", "cFE", "modules", "msg", "fsw", "src", "cfe_msg_sechdr_fc.c"),
    os.path.join(ROOT, "vendor", "cFE", "modules", "sbr", "fsw", "src", "cfe_sbr_map_hash.c"),
    os.path.join(ROOT, "vendor", "cFE", "modules", "evs", "fsw", "src", "cfe_evs_task.c"),
    # OS_MAX_PRIORITY is NOT an OSAL symbol -- cfe_es_task.c defines it itself, with NASA's own
    # comment "This define should be put in the OS API headers". A constant a .c file invents
    # is exactly what this list exists for.
    os.path.join(ROOT, "vendor", "cFE", "modules", "es", "fsw", "src", "cfe_es_task.c"),
    # cfe_es_backgroundtask.c invents its own sem name, child-task parameters, idle delay and
    # the job count (sizeof(table)/sizeof(table[0])). None of them is in a header.
    os.path.join(ROOT, "vendor", "cFE", "modules", "es", "fsw", "src", "cfe_es_backgroundtask.c"),
    # CFE_ES_PANIC_DELAY is cfe_es_start.c's own: half a second, and it is always followed by
    # CFE_PSP_Panic -- "Delay to allow the message to be read". Five functions in that file use
    # it and no header names it.
    os.path.join(ROOT, "vendor", "cFE", "modules", "es", "fsw", "src", "cfe_es_start.c"),
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "src", "osapi-file.c"),
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "src", "osapi-idmap.c"),
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "src", "osapi-timebase.c"),
    # FILE_CRC_BUFFER_SIZE is mm_utils.c's own, and it is load-bearing: CFE_ES_CalculateCRC is
    # called with the bytes actually READ, not with this size, so the two numbers have to be
    # different for the short-read fold to be exercised at all.
    os.path.join(ROOT, "vendor", "MM", "fsw", "src", "mm_utils.c"),
]


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
        # MD's own headers. md_interface_cfg.h and md_internal_cfg.h hold the DEFAULT_MD_*
        # values that MD_INTERFACE_CFGVAL/MD_INTERNAL_CFGVAL paste a name onto; md_app.h holds
        # the table-validation error codes.
        "md_interface_cfg.h", "md_internal_cfg.h", "md_eventids.h", "md_fcncodes.h",
        "md_msgids.h", "md_dwell_pkt.h", "md_version.h",
        # MM's. SIXTY-EIGHT constants were filed as "NASA does not define this" until these five
        # were added -- every event id, every performance id and all three MsgIds -- because an
        # id this probe cannot SEE is indistinguishable from an id this port invented. The
        # MM_INTERNAL_* and MM_INTERFACE_* values were already compared, reachable through
        # mm_app.h, which is exactly what made the gap look like a pass.
        "mm_eventids.h", "mm_perfids.h", "mm_msgids.h", "mm_fcncodes.h", "mm_version.h",
        # ES's event ids and its own platform config, as the module arrives. The gate refused
        # to pass on CFE_ES_SYSLOG2_EID rather than file it as "a name this port invented",
        # which is the behaviour that distinguishes a missing header from a local constant.
        "cfe_es_eventids.h", "cfe_es_platform_cfg.h", "cfe_es_msgids.h",
        # ES's task header: the command pipe's name and depth, and the 42-entry cap on what one
        # QueryAll dump can hold. None of the three is reachable from any header already here.
        "cfe_es_task.h",
        # The startup script's two sizes -- the 128-byte line buffer and the 8-token cap -- which
        # are the whole malformed-line detector: both buffers are declared ONE larger than these,
        # so filling one IS overrunning it. Nothing else in the module names them.
        "cfe_es_startupscript.h",
    ]
    body = ["#include <stdio.h>", "#include <stddef.h>"] + ['#include "%s"' % h for h in hdrs]
    # THE `#define`s NASA PUTS IN A .c FILE, lifted in textually. A constant the translation
    # restates from an implementation file was invisible to this probe -- `#ifdef` is false for
    # a name no header declares -- so it was filed as "a name this port invented" and never
    # compared, with a count that looked like a pass. That is the seventh instance of this
    # project's recurring shape, and the one that found it cost 8 bytes per allocation:
    # cfe_sb_buf.c's CFE_SB_BUFFERD_CONTENT_OFFSET is offsetof(CFE_SB_BufferD_t, Content), the
    # translation spelled it 48, and the real value is 56. Only the differential transcript
    # noticed. CSRC_DEFS is why the probe can now see them; check_structs.py scans .c files for
    # typedefs and check_padding.py lifts them for the same reason.
    # A MULTI-LINE #define HAS TO BE TAKEN WHOLE. Lifting only its first line leaves a dangling
    # backslash, and the continuation then swallows whatever is appended next -- so adding
    # cfe_es_task.c (whose CFE_ES_PERF_TRIGGERMASK_INT_SIZE is two lines) silently ate the
    # OS_MAX_PRIORITY define that came after it, and the gate reported OS_MAX_PRIORITY as
    # "NASA defines this and the probe cannot see it". The lifter now consumes continuations.
    for cf in CSRC_DEFS:
        if not os.path.isfile(cf):
            continue
        text = open(cf, errors="replace").read()
        # A #define that mentions one of the file's own OBJECTS cannot be lifted: the probe has
        # the macro but not the thing it names, and the probe then fails to COMPILE, which takes
        # every other constant down with it. cfe_es_backgroundtask.c's
        #   #define CFE_ES_BACKGROUND_NUM_JOBS (sizeof(TABLE) / sizeof(TABLE[0]))
        # is the case: the table is a file-scope array of function pointers that cannot be
        # lifted with it. Such a name is left to the "not a literal and so NOT compared" bucket,
        # which this tool reports as a NUMBER rather than a silence -- and the translation
        # spells it the same way NASA does, as a sizeof over its own copy of the table, so the
        # two derive it from the same place rather than both writing a number down.
        objects = set(re.findall(r'^[A-Za-z_][\w \t*]*?\b([A-Za-z_]\w*)\s*\[[^\]]*\]\s*=',
                                 text, re.M))
        objects |= set(re.findall(r'^[A-Za-z_][\w \t*]*?\b([A-Za-z_]\w*)\s*=\s*\{',
                                  text, re.M))
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            if re.match(r'^[ \t]*#[ \t]*define[ \t]+[A-Za-z_]\w*', lines[i]):
                chunk = [lines[i]]
                while lines[i].rstrip().endswith("\\") and i + 1 < len(lines):
                    i += 1
                    chunk.append(lines[i])
                joined = " ".join(chunk)
                if not any(re.search(r'\b%s\b' % re.escape(o), joined) for o in objects):
                    body.extend(chunk)
            i += 1
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

    # SECOND PASS, for the ENUMERATORS. `#ifdef NAME` is false for an enum member, so every
    # constant NASA spells as an enumerator came back UNDEF above, was classified as "a name this
    # port invented", and was NEVER COMPARED. That is not a small set and it cost a real bug:
    # OSAL declares OS_TIME_TICK_RESOLUTION_NS = 100 and OS_TIME_TICKS_PER_SECOND =
    # 1000000000 / OS_TIME_TICK_RESOLUTION_NS as enum members, the translation had 1 and
    # 1000000000, and this tool said nothing for several commits -- until the TIME module divided
    # by one of them and the differential transcript printed 00:00:01 against 00:01:40.
    #
    # So the undefined set is retried as EXPRESSIONS, with no #ifdef around them. A name that
    # does not exist is then a COMPILE ERROR, which poisons the whole probe -- so the set is
    # BISECTED rather than filtered by parsing diagnostics. Parsing was the first attempt and it
    # silently did nothing: clang stops after nineteen errors, and some failures are not
    # "undeclared identifier" at all, so one unparsed message ended the retry with every real
    # enumerator still unresolved. A bisect needs no diagnostics to be right.
    def try_set(group):
        """{name: value} for a group that compiles, or None if it does not."""
        if not group:
            return {}
        body2 = ["#include <stdio.h>"] + ['#include "%s"' % h for h in hdrs]
        body2.append("int main(void){")
        for nm in group:
            body2.append('  printf("%%s %%lld\\n", "%s", (long long)(%s));' % (nm, nm))
        body2.append("  return 0; }")
        s2 = src[:-2] + "_enum.c"
        open(s2, "w").write("\n".join(body2) + "\n")
        e2 = s2[:-2]
        if subprocess.run([cc, "-O0", "-w", "-o", e2, s2] + check_padding.INC,
                          capture_output=True, text=True).returncode:
            return None
        got = {}
        for line in subprocess.run([e2], capture_output=True, text=True).stdout.split("\n"):
            p = line.split()
            if len(p) == 2:
                got[p[0]] = int(p[1])
        return got

    def resolve(group):
        """Values for every name in `group` that names something, by halving."""
        got = try_set(group)
        if got is not None:
            return got
        if len(group) == 1:
            return {}          # this one name is what does not exist
        mid = len(group) // 2
        found = resolve(group[:mid])
        found.update(resolve(group[mid:]))
        return found

    unknown = [n for n in names if out.get(n) is None]

    # A PROBE THAT CANNOT BUILD AT ALL MUST NOT LOOK LIKE A SET OF UNDEFINED NAMES. resolve()
    # bisects on compile failure and gives up at one name, classifying it "NASA does not
    # define" -- which PASSES. That is right for a name NASA really lacks and catastrophic for
    # a probe broken by something else: every enumerator in cFS would stop being compared and
    # the only visible change would be a number nobody watches going up.
    #
    # Seen for real: two invocations of this gate running at once -- a standalone run while the
    # driver's run was in progress -- clobber each other's probe in build/cfs, and the loser
    # reported 1,267 compared with 39 "not defined" instead of 1,272 with 34. Five constants
    # stopped being compared and the run still exited 0.
    #
    # So the headers are built ONCE with no names in the body. If that fails, the gate fails.
    # `try_set([])` would be VACUOUS here -- it returns {} for an empty group without compiling
    # anything. The baseline has to be a group that does compile a body, so it is the literal
    # expression `0`: the headers are all included, one printf is emitted, and nothing depends
    # on a name existing.
    if unknown and try_set(["0"]) is None:
        return None, ("the enumerator probe cannot be built AT ALL, so no enumerator can be "
                      "resolved and every one of them would be filed as a name NASA does not "
                      "define -- which passes. Fix the probe; do not trust the count. "
                      "(A concurrent run of this gate clobbering build/cfs does this too: the "
                      "probe path is fixed, so two at once is one too many.)")
    for nm, v in resolve(unknown).items():
        out[nm] = v
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


# An expression's value, computed with THE TRANSLATION'S OWN numbers.
#
# A parenthesised `#define` used to be reported and skipped -- OS_TIME_TICKS_PER_MSEC is
# `(1000000 / OS_TIME_TICK_RESOLUTION_NS)`, and that is exactly the family where a wrong tick
# resolution hid for several commits. Compiling the expression as C would prove nothing: C's
# headers would supply NASA's value for every name inside it, so the answer would come back
# NASA's by construction. The expression has to be evaluated with the TRANSLATION's values,
# which is what makes it a check on the translation.
#
# So names are expanded from hc_defines() first, recursively, and only then is the arithmetic
# done -- in Python, over a restricted grammar, because these are shifts, sums and divisions and
# nothing else. A name the translation does not define falls back to the probe's value, which is
# right: OS_MAX_QUEUES comes from osconfig.h and is not the translation's to state.
EXPR_OK = re.compile(r'^[0-9xXa-fA-F\s()+\-*/<>|&~%]*$')


def expr_value(lit, mine, probe_vals, depth=0):
    # The expression's value using the translation's constants, or None.
    if depth > 12:
        return None
    s = lit.strip()
    for name in sorted(set(re.findall(r'[A-Za-z_]\w*', s)), key=len, reverse=True):
        if name in mine:
            sub = mine[name][0].strip()
        elif probe_vals.get(name) is not None:
            sub = str(probe_vals[name])
        else:
            return None
        s = re.sub(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'(?![A-Za-z0-9_])',
                   "(" + sub + ")", s)
    # A substituted value can itself be an expression -- the OS_*_BASE chain in
    # os_shared_idmap.HC is fifteen deep, each entry the previous one plus a limit -- so keep
    # expanding until only arithmetic is left.
    if re.search(r'[A-Za-z_]', re.sub(r'0[xX]', '', s)):
        return expr_value(s, mine, probe_vals, depth + 1)
    if not EXPR_OK.match(s):
        return None
    try:
        return int(eval(s, {"__builtins__": {}}, {}))
    except Exception:
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
                    # .c AS WELL AS .h. A NASA `#define` in an implementation file was invisible
                    # here, so any translated constant that restates one came back as "a name
                    # this port invented" and went UNCOMPARED -- with a count that looked like a
                    # pass. cfe_sb_buf.c's CFE_SB_BUFFERD_CONTENT_OFFSET is the one that found
                    # it: the translation said 48 where the real offset is 56, and only the
                    # differential transcript noticed, on a 100-byte allocation coming back 148
                    # against 156. The same reasoning put .c files in check_structs.py's scan.
                    if not (f.endswith(".h") or f.endswith(".h.in") or f.endswith(".c")):
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
            # A parenthesised expression: evaluated with the translation's own constants, so the
            # answer is a check on the translation and not a restatement of NASA's headers.
            v = expr_value(lit, mine, real)
            if v is None:
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
    unparsed = unparsed_defines()
    if verbose:
        print("  not a literal this tool reads, so NOT compared (strings, macro calls, ids):")
        for n, v, fn in unparsed:
            print("    %-44s %-44s %s" % (n, v[:44], fn))
    print("cfs-constants: %d constants match NASA's values (%d names NASA does not define, "
          "%d expressions not compared, %d #defines not a literal and so NOT compared -- "
          "run with -v)" % (checked, len(local), len(skipped), len(unparsed)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
