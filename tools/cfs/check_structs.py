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
    # osal/src/os/shared/SRC, not just its inc. OSAL declares a module's private state structs
    # in the implementation file the same way cFE does -- osapi-idmap.c defines
    # OS_creator_filter_t and OS_objtype_state_t, and OS_objtype_state is a live global of the
    # second one -- and this directory was not on the list, so neither was ever compared. The .c
    # files are already scanned for exactly this reason on the cFE side.
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "src"),
] + sorted(_glob.glob(os.path.join(ROOT, "vendor", "cFE", "modules", "*", "fsw", "inc"))) \
  + sorted(_glob.glob(os.path.join(ROOT, "vendor", "cFE", "modules", "*", "fsw", "src"))) \
  + sorted(_glob.glob(os.path.join(ROOT, "vendor", "cFE", "modules", "*", "config"))) \
  + sorted(_glob.glob(os.path.join(ROOT, "vendor", "cFE", "modules", "*", "option_inc"))) \
  + [os.path.join(ROOT, "vendor", "cFE", "cmake", "target", "inc")]
# modules/*/option_inc IS WHERE THE MESSAGE HEADERS LIVE -- `struct CFE_MSG_Message`,
# CFE_MSG_CommandHeader, CFE_MSG_TelemetryHeader and CCSDS_SpacePacket, in
# default_cfe_msg_hdr_pri.h. cFE keeps them there because the choice between a plain primary
# header and one with the APID extension is a build option, which is exactly why they are not in
# fsw/inc. The directory was missing from this list, so the BASE TYPE OF EVERY PACKET IN cFS had
# never been compared field for field or byte for byte by either layout gate -- the same hole,
# and the same directory-shaped cause, as modules/*/config below. Found while tracking down why
# eleven translated classes reported no NASA counterpart; seven of the eleven were these.
#
# modules/*/config IS WHERE EVERY MESSAGE STRUCT LIVES -- default_cfe_<mod>_msgdefs.h and
# _msgstruct.h -- and it was missing from this list. A translated class whose NASA counterpart is
# not found here is not reported: it has no pair, so both this gate and check_padding.py skip it
# in SILENCE, which is the one outcome every other tool in tools/cfs is written to avoid. Every
# command and telemetry payload in the port was in that hole, and one of them was wrong:
# CFE_EVS_SetLogMode_Payload_t carried LogMode as a U16 where CFE_EVS_LogMode_Enum_t is a uint8,
# which made the command one byte too long and the dispatcher rejected it on length. The
# transcript caught that, three modules after the declaration was written.

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
# A `struct X *` / `union X *` / `enum X` member needs the TAG KEYWORD allowed before the type
# name, and a member whose type is a MACRO CALL needs the parenthesised argument allowed after it.
# Without the first, NASA's self-referential list node
#     typedef struct CFE_SB_BufferLink { struct CFE_SB_BufferLink *Next, *Prev; } ...
# parsed as having NO fields; without the second, SB's
#     CFE_ES_STATIC_POOL_TYPE(CFE_PLATFORM_SB_BUF_MEMORY_BYTES) Partition;
# did too. Both then reported the TRANSLATION as having EXTRA fields -- the tool blaming the
# translation for its own blind spot, which is the one failure mode worse than not checking,
# because it costs a real investigation. Same shape as the `modules/*/config` glob that was
# missing from NASA_DIRS and as check_fnptr_members.py's first regex.
# A MULTI-WORD PRIMITIVE TYPE needs `long` and `short` in the leading run. cFE's own
# CFE_SB_Buffer_t union is
#     long long int LongInt;
#     long double   LongDouble;
# and with only the four qualifiers below, neither line parsed -- so NASA's side came back with
# two fields instead of four and the tool reported the TRANSLATION as having two EXTRA members
# that it correctly has. That is the third time this regex has blamed the translation for a
# spelling it could not read (see the two notes above), and it surfaced only when unions started
# being scanned at all.
FIELD = re.compile(r'^\s*(?:const\s+|volatile\s+|unsigned\s+|signed\s+|long\s+|short\s+)*'
                   r'(?:struct\s+|union\s+|enum\s+)?'
                   r'[A-Za-z_]\w*(?:\s*\([^;()]*\))?'
                   r'(?:\s*\*+|\s*const\b|\s*volatile\b)*'
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


def pair_name(name, nasa):
    """NASA's name for a translated class, or None.

    THE ONE PAIRING RULE, and it lives here because check_padding.py needs the same one. It did
    not have the same one: this function's third candidate -- STRIPPING a `_t` the translation
    carries and NASA's struct TAG does not, as in
        typedef struct OS_object_token OS_object_token_t;
    -- was added here first, and check_padding went on silently skipping the two types it
    resolves. Two gates with two copies of a join rule drift, and the drift is invisible because
    both still print a reassuring count. One function, imported.
    """
    for c in (name, name + "_t", name[:-2] if name.endswith("_t") else None):
        if c and c in nasa:
            return c
    return None


# A STRUCT BODY, AND IT HAD TO STOP BEING `(.*?)`. The lazy form looks safe and is not: it
# scans to the first `}` followed by `;`, so for
#     typedef struct A { ... } A_t;        <- `}` followed by a NAME, not `;`
#     typedef struct B { ... } B_t;
#     struct C { ... };                    <- the first `}` + `;` in the file
# the bare-struct pattern matched ONE region, called it `A`, and gave it a body containing all
# three structs' fields -- 1,280 characters in cfe_es_generic_pool.h -- and then, because the
# scan had consumed everything up to C's closing brace, `struct C` was NEVER FOUND. C was
# cfe_es_generic_pool.h's CFE_ES_GenPoolRecord: the pool record itself, the biggest struct in
# the module, and no gate was reading it. The wrong `A` body did no visible damage only because
# the typedef pattern runs first and setdefault keeps its correct version.
#
# This allows one level of nesting (an anonymous inner struct or union member) and nothing more,
# so a match cannot cross a closing brace that ends a declaration.
BODY = r'((?:[^{}]|\{[^{}]*\})*)'


def nasa_structs():
    out = {}
    for d in NASA_DIRS:
        if not os.path.isdir(d):
            continue
        # .c as well as .h: NASA declares a module's private context and state structs INSIDE
        # the implementation file -- cfe_fs_api.c defines CFE_FS_ParseContext_t, thirteen fields
        # with three separate pieces of C padding in it -- and scanning headers only left those
        # out of every gate. Headers are scanned first and setdefault keeps them, so a name that
        # appears in both is still taken from the header.
        for fn in sorted(os.listdir(d)):
            if not (fn.endswith(".h") or fn.endswith(".c")):
                continue
            txt = strip_comments(open(os.path.join(d, fn), errors="replace").read())
            # `typedef struct { ... } Name;` and `struct Name { ... };`
            # `typedef const struct { ... } Name;` is how cFE declares its target-config
            # types, and without the optional `const` none of them were being compared at all.
            # struct OR union, in both forms. Scanning only `struct` is what made every
            # translated union unpairable; a cFS union is an ordinary tagged or typedef'd type
            # (CFE_ES_CDS_AccessCacheData, OS_SockAddrData_t, CFE_Config_ValueBuffer) and there
            # was nothing to find it with.
            for m in re.finditer(r'typedef\s+(?:const\s+)?(?:struct|union)\s*(?:\w+\s*)?\{' + BODY +
                                 r'\}\s*(\w+)\s*;', txt, re.S):
                out.setdefault(m.group(2), (fields_of(m.group(1)), fn))
            for m in re.finditer(r'\b(?:struct|union)\s+(\w+)\s*\{' + BODY + r'\}\s*;', txt, re.S):
                out.setdefault(m.group(1), (fields_of(m.group(2)), fn))
    return out


# `U8 _pad0[4];`: a member the C compiler inserts as ALIGNMENT and HolyC therefore has to write
# by hand. It is not one of NASA's fields and must not be compared as one -- but it is not free
# to invent either, so tools/cfs/check_padding.py measures NASA's real offsets with the host C
# compiler and fails if a pad is missing, wrong, or there when C does not pad. One gate owns
# membership and order; the other owns the bytes.
# A translated class with NO NASA counterpart, and why. Every entry is a class this port
# INVENTED -- not one whose upstream the tool failed to find -- and anything not on the list is a
# failure, so the list cannot become a hiding place. Same discipline as OMITTED above and as
# CONFIG_EXCLUDED in check_coverage.py.
UNPAIRED_OK = {
    "CFE_SB_MemPartition_t":
        "NASA writes this member's type inline as CFE_ES_STATIC_POOL_TYPE(...), an ANONYMOUS "
        "union. HolyC has no anonymous member type, so the union is named here; there is no "
        "upstream struct of any name to pair with. cfe_sb_global.HC records the argument.",
    "CFE_TBL_MemPartition_t":
        "The same thing in cfe_tbl_task.h: CFE_TBL_BufParams_t's Partition member is an inline "
        "CFE_ES_STATIC_POOL_TYPE(CFE_PLATFORM_TBL_BUF_MEMORY_BYTES), an anonymous union, so "
        "again there is no upstream type of any name. This is the 512 KiB table buffer pool, "
        "the single largest object in the port; its SIZE is checked by check_padding through "
        "CFE_TBL_Global_t's member offsets, which is the property that matters.",
    # CFE_SB_Buffer WAS HERE, and its reason was WRONG: it said NASA's CFE_SB_Buffer_t is a
    # typedef of an anonymous union with no tagged upstream type. It is `typedef union CFE_SB_Msg
    # {...} CFE_SB_Buffer_t;` -- tagged, and perfectly pairable. The entry was written when this
    # gate did not scan unions at all, so "no counterpart" was the tool's own blind spot being
    # recorded as a fact about NASA's source. It pairs now and is compared like anything else.
    "CFE_ES_SysLogDumpBuffer_t":
        "NASA declares this as an ANONYMOUS union LOCAL inside CFE_ES_SysLogDump -- `union "
        "{ CFE_ES_SysLogReadBuffer_t LogData; CFE_FS_Header_t FileHdr; } Buffer;` -- so there "
        "is no upstream type of any name to pair with. HolyC needs the type named to declare a "
        "local of it. Its SIZE is still covered: a union is as large as its largest member, and "
        "BOTH members pair and are measured (CFE_ES_SysLogReadBuffer_t and CFE_FS_Header_t), so "
        "there is no way for this to be the wrong size while they are right.",
    "OS_EventHandlerSlot":
        "NASA's OS_SharedGlobalVars.EventHandler is an array of the function-pointer typedef "
        "OS_EventHandler_t; the translation wraps one pointer in a class so the member can be an "
        "array of a named type. Eight bytes per slot either way, which check_padding verifies "
        "through OS_shared_global_vars.EventHandler.",
}

PAD = re.compile(r'^_pad\d*$')


def hc_classes():
    out = {}
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            txt = strip_comments(open(os.path.join(d, fn), errors="replace").read())
            # `class` OR `union`. This said `class` only, and a HolyC `union` was therefore
            # invisible to this gate -- never paired, so never reported as unpaired, so it
            # PASSED. check_padding captures unions but could not pair them because
            # nasa_structs below did not scan them either, so it dropped them. The result: EVERY
            # TRANSLATED UNION IN THE PORT had never had its fields or its layout compared with
            # NASA's by anything -- six real ones, including CFE_SB_BackgroundFileBuffer_t,
            # which is the buffer SB's three file writers fill. Found when a newly translated
            # union appeared in check_padding's unpaired list, a list that exists only because
            # the silent skip was made visible one commit earlier.
            for m in re.finditer(r'\b(?:class|union)\s+(\w+)\s*\{' + BODY + r'\}\s*;', txt, re.S):
                out[m.group(1)] = ([f for f in fields_of(m.group(2)) if not PAD.match(f)], fn)
    return out


def main(argv):
    nasa = nasa_structs()
    mine = hc_classes()
    if not nasa:
        print("FAIL cfs-structs — no NASA headers found; is vendor/osal present?", file=sys.stderr)
        return 1

    bad, notes, checked, unpaired = [], [], 0, []
    # A STALE UNPAIRED_OK ENTRY IS A FAILURE, and this check exists because one rotted into a
    # false statement about NASA's source. CFE_SB_Buffer's entry said "CFE_SB_Buffer_t is a
    # typedef of an ANONYMOUS union, so there is no tagged upstream type". It is
    # `typedef union CFE_SB_Msg {...} CFE_SB_Buffer_t;` -- tagged all along. The entry was
    # written when this gate did not scan unions, so the TOOL'S BLIND SPOT had been recorded as
    # a fact about the upstream, and it sat there being quoted. Same discipline as
    # check_wired.py's: both directions fail.
    stale = sorted(k for k in UNPAIRED_OK if pair_name(k, nasa) is not None)
    if stale:
        print("FAIL cfs-structs — these are in UNPAIRED_OK but DO pair with NASA now.",
              file=sys.stderr)
        print("  Remove the entry and let them be compared. An exception that no longer applies",
              file=sys.stderr)
        print("  is worse than none: its stated reason is being trusted and is wrong.",
              file=sys.stderr)
        for k in stale:
            print("    %-30s pairs with %s" % (k, pair_name(k, nasa)), file=sys.stderr)
        return 1
    for name, (hfields, hfile) in sorted(mine.items()):
        cand = pair_name(name, nasa)
        if cand is None:
            # NOT SILENT. A translated class named after cFS or OSAL that pairs with nothing
            # upstream is either this port's own invention or a name this tool cannot resolve --
            # and the second case is the one that looks like success. Both land in UNPAIRED_OK or
            # they are reported. Every entry there carries the reason it has no counterpart.
            if name not in UNPAIRED_OK:
                unpaired.append(name + "  (" + hfile + ")")
            continue
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

    if unpaired:
        print("FAIL cfs-structs — a translated class has no NASA struct to compare against.",
              file=sys.stderr)
        print("  Not finding the other side is not a pass. If the class really is this port's",
              file=sys.stderr)
        print("  own, add it to UNPAIRED_OK with the reason; if it is not, the NAME or the",
              file=sys.stderr)
        print("  search path is wrong -- modules/*/option_inc was missing from NASA_DIRS and",
              file=sys.stderr)
        print("  that hid the base type of every cFS packet.", file=sys.stderr)
        for u in unpaired:
            print("    " + u, file=sys.stderr)
        return 1

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
