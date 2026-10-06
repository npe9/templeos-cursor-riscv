#!/usr/bin/env python3
"""Compare a translated module's function SIGNATURES against NASA's.

WHY THIS EXISTS. tools/cfs/check_coverage.py proves a function NAME is present; it says nothing
about the arity or the pointer-ness. When the OSAL semaphore family was generated from a
template, two signatures came out wrong and both passed the coverage check because the names
existed:

    OS_MutSemCreate      lost its `options` parameter entirely
    OS_CondVarTimedWait  was given `uint32 msecs` where NASA takes `const OS_time_t *`
                         -- an absolute wake time, not a relative delay

Both were found by diffing signatures by hand. This makes that a command.

The comparison normalises the type spellings, because the two languages genuinely differ there
and those differences are not defects:

    osal_id_t / uint32 / uint16   ->  NUM        (all 32-bit-or-less unsigned scalars)
    osal_id_t * / uint32 *        ->  PTRNUM
    const char * / void * / U8 *  ->  PTRB       (a byte pointer either way)
    size_t / osal_blockcount_t    ->  SZ
    int32                         ->  SNUM
    OS_time_t *                   ->  TIME
    OS_<x>_prop_t *               ->  PROP
    <any> name[N]                 ->  same as <any> *name (an array parameter IS a pointer)
    OS_ArgCallback_t / a spelled-out function pointer  ->  FN

What it does NOT normalise is how many parameters there are or whether one is a pointer, which
is exactly what a template gets wrong.

A HANDFUL of signatures genuinely cannot be 1:1, because HolyC has no struct-return ABI (see
docs/HOLYC_STRUCT_LIMITS.md). Those are listed in DEVIATIONS below, each with its reason, and
each pinned to the EXACT pair of normalised signatures. A listed deviation that no longer
applies is itself a failure -- otherwise the list would quietly grow into a place to hide real
defects, which is the failure mode this whole checker exists to prevent.

Takes the SAME argument list as check_coverage.py -- the gated NASA sources -- and finds the
HolyC side by name across Kernel/Cfs/{cfe,osal}, so a gate wires the two in checks identically
and a function can move between files without the check losing sight of it.

    tools/cfs/check_signatures.py <nasa.c> [nasa.c ...]
"""
import re, sys, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HCDIRS = [os.path.join(ROOT, "Kernel", "Cfs", "cfe"),
          os.path.join(ROOT, "Kernel", "Cfs", "osal")]

C_TYPES = [(r'\bconst\b', ' '),
           # A plain `uint32 *` -- an obvious gap that was missing until the checker was first
           # pointed at cFE, where CFE_ResourceId_ToIndex takes one.
           (r'\buint32\s*\*', ' PTRNUM '), (r'\buint16\s*\*', ' PTRNUM '),
           (r'\bint32\s*\*', ' PTRNUM '), (r'\bbool\s*\*', ' PTRNUM '),
           # Plain `int *`, not int32 * -- OS_Milli2Ticks takes one, and `int` is
           # 32-bit on this target so the translation's I32 * is the same thing.
           (r'\bint\s*\*', ' PTRNUM '),
           # cFE's own opaque types, by the same logic as OSAL's.
           (r'\bCFE_MSG_Message_t\s*\*', ' PTRB '),
           # cFE's sizes and enums. The translation spells all of these I64, so the C maps to
           # the same token -- a representation choice, like OS_lock_mode_t above, not a defect.
           (r'\bCFE_MSG_(?:Size|Type|SegmentationFlag)_t\s*\*', ' PTRSZ '),
           (r'\bCFE_MSG_(?:Size|Type|SegmentationFlag)_t\b', ' SZ '),
           # TIME's SIGNED enum typedefs, ahead of the catch-all below. Four of the module's
           # seven are int16 and three are uint8, and the catch-all cannot tell: it maps every
           # CFE_*_t to NUM, which made CFE_TIME_SetState look like a mismatch when the
           # translation correctly used I32. The signedness is not cosmetic --
           # CFE_TIME_ClockState_INVALID is -1, which is WHY NASA's typedef is signed -- so the
           # rule is added rather than the function exempted.
           (r'\bCFE_TIME_(?:ClockState|ToneSignalSelect|FlywheelState|SetState)_Enum_t\s*\*',
            ' PTRSNUM '),
           (r'\bCFE_TIME_(?:ClockState|ToneSignalSelect|FlywheelState|SetState)_Enum_t\b',
            ' SNUM '),
           # `cpuaddr` IS AN UNSIGNED INTEGER WIDE ENOUGH FOR A POINTER, which on this target
           # is 64 bits, and the translation writes it U64. NEITHER had a rule, so both
           # normalised to the EMPTY STRING and CFE_ES_InitializeFileSystems_CheckFreeSpace
           # and _ReformatVolume "matched" as two blanks -- found only because adding the U64
           # rule below broke the accidental agreement. An unrecognised type on both sides is
           # not a match; it is two gaps of the same shape. (`cpusize` is the sibling and gets
           # the rule too, pre-emptively, so it cannot repeat the trick.)
           (r'\bcpuaddr\s*\*', ' PTRSZ '), (r'\bcpuaddr\b', ' SZ '),
           (r'\bcpusize\s*\*', ' PTRSZ '), (r'\bcpusize\b', ' SZ '),
           # CFE_TBL_Handle_t IS `int16` IN THIS CONFIGURATION, i.e. SIGNED, and the catch-all
           # below maps every CFE_*_t to NUM. Same shape as CFE_Status_t directly below and the
           # TIME enums above: the catch-all cannot see signedness, so the rule is added rather
           # than the sixteen api.c functions exempted. cfe_tbl_api_typedefs.h offers two
           # typedefs chosen by CFE_OMIT_DEPRECATED_6_8 -- `CFE_TBL_HandleId_t` (a resource id)
           # and `int16` -- and the symbol is not defined here, so the int16 one applies. A port
           # that flipped that switch would need this rule changed with it.
           (r'\bCFE_TBL_Handle_t\s*\*', ' PTRSNUM '), (r'\bCFE_TBL_Handle_t\b', ' SNUM '),
           # CFE_Status_t is `int32`, and every cFE error code is NEGATIVE -- so the catch-all
           # below, which maps every CFE_*_t to NUM, had it as unsigned. Caught when
           # CFE_SB_MessageTxn_SetEventAndStatus became the first translated function to take
           # one as a PARAMETER rather than return it; the translation's I32 was right and the
           # tool was wrong, which is the failure mode worth not having.
           (r'\bCFE_Status_t\s*\*', ' PTRSNUM '),
           (r'\bCFE_Status_t\b', ' SNUM '),
           # ES's memory sizes and addresses, ahead of the catch-all for the same reason
           # CFE_MSG_Size_t is: both are `uint64` in this configuration, the translation spells
           # them I64, and the catch-all below maps every CFE_*_t to NUM -- a FOUR-byte id. It
           # made CFE_ES_GenPoolGetUsage look like a mismatch when the translation was right,
           # which is this tool's one unacceptable failure: blaming the translation for a rule
           # it does not have.
           (r'\bCFE_ES_Mem(?:Offset|Address)_t\s*\*', ' PTRSZ '),
           (r'\bCFE_ES_Mem(?:Offset|Address)_t\b', ' SZ '),
           # CFE_ES_MemPoolBuf_t IS `typedef void *` -- a POINTER, not an id. The catch-all
           # below maps every CFE_*_t to NUM, so a pool buffer looked like a 4-byte handle and
           # all three of mempool.c's get/put/info signatures came back as mismatches when the
           # translation's U8 * was right. Third time the catch-all has been too eager (see
           # CFE_Status_t and CFE_ES_MemOffset_t above); each one is a rule added rather than a
           # function exempted, because an exemption would stop comparing the arity too.
           (r'\bCFE_ES_MemPoolBuf_t\s*\*', ' PTRB '),
           (r'\bCFE_ES_MemPoolBuf_t\b', ' PTRB '),
           # CFE_ES_StackPointer_t is `typedef void *` -- a POINTER, exactly like
           # osal_stackptr_t below ("aka osal_stackptr_t in proposed OSAL change", says the
           # header). Without this rule the generic CFE_*_t scalar handling called it NUM and
           # the gate reported NASA as NUM against CFE_ES_CreateChildTask's translated PTRB.
           (r'\bCFE_ES_StackPointer_t\b', ' PTRB '),
           (r'\bCFE_\w+_t\s*\*', ' PTRNUM '),
           (r'\bCFE_\w+_t\b', ' NUM '),
           (r'\bosal_id_t\s*\*', ' PTRNUM '), (r'\bchar\s*\*', ' PTRB '),
           (r'\bvoid\s*\*', ' PTRB '), (r'\buint8\s*\*', ' PTRB '),
           (r'\bsize_t\s*\*', ' PTRSZ '), (r'\bOS_time_t\s*\*', ' TIME '),
           (r'\bOS_\w+_prop_t\s*\*', ' PROP '), (r'\bOS_object_token_t\s*\*', ' TOK '),
           (r'\bosal_id_t\b', ' NUM '), (r'\buint32\b', ' NUM '), (r'\buint16\b', ' NUM '),
           (r'\buint8\b', ' NUM '),
           (r'\bosal_blockcount_t\b', ' SZ '), (r'\bsize_t\b', ' SZ '), (r'\bint32\b', ' SNUM '),
           # int16 used to normalise to NOTHING on this side and I16 to nothing on the other, so
           # the two matched by both being invisible -- which also meant a translation that got
           # the WIDTH or the SIGNEDNESS of an int16 parameter wrong would have passed. Both get
           # a token now. This is what caught cfe_time_task.c's three *Impl helpers: NASA's
           # Direction there is CFE_TIME_AdjustDirection_Enum_t, a uint8, and the translation had
           # written I16 by analogy with cfe_time_utils.c -- where NASA really does write int16.
           (r'\bint16\b', ' SNUM '),
           # The remaining OSAL typedefs, by shape rather than one at a time. osal_index_t and
           # osal_objtype_t are 32-bit scalars; os_err_name_t and os_status_string_t are
           # char arrays, so a pointer to one is a byte pointer.
           # osal_stackptr_t is `typedef void *` -- a POINTER, so the generic osal_*_t rule
           # below would wrongly call it a scalar. Like osal_status_t, it must come first.
           (r'\bosal_stackptr_t\b', ' PTRB '),
           (r'\bos_\w+_t\s*\*', ' PTRB '), (r'\bosal_\w+_t\s*\*', ' PTRNUM '),
           # osal_status_t is `typedef int32` -- SIGNED. It must be matched before the generic
           # osal_*_t rule below, which would otherwise call it unsigned. That masked a real
           # find: OS_StatusToString was the one place an int32 had been translated as I64.
           (r'\bosal_status_t\b', ' SNUM '),
           # osal_offset_t is `typedef long` -- a SIGNED 64-bit scalar, which is the I64
           # the translation uses. The generic osal_*_t rule below would call it a plain
           # unsigned NUM, so like osal_status_t it has to be matched first.
           (r'\bosal_offset_t\b', ' SZ '),
           (r'\bosal_\w+_t\b', ' NUM '),
           # An ENUM parameter. HolyC has no enum, so the translation spells these I64 and this
           # maps the C to the same token. That is a deliberate representation choice, not a
           # defect: both are passed in one register. The check still catches arity and
           # pointer-ness, which is what it is for.
           (r'\bOS_lock_mode_t\b', ' SZ '), (r'\bOS_Event_t\b', ' SZ '),
           # The socket enums, by the same rule: HolyC has no enum, the translation
           # spells them I64, and both are passed in one register.
           (r'\bOS_SocketDomain_t\b', ' SZ '), (r'\bOS_SocketType_t\b', ' SZ '),
           (r'\bOS_SocketShutdownMode_t\b', ' SZ '), (r'\bOS_socket_option_t\b', ' SZ ')]
H_TYPES = [(r'\bCFE_MSG_Message\s*\*', ' PTRB '), (r'\bCFE_\w+\s*\*', ' PTRNUM '),
           # A cFE opaque type passed BY VALUE -- CFE_SB_MsgId, CFE_SBR_RouteId. These are
           # classes wrapping one integer, so they normalise the same as the C's typedefs.
           (r'\bCFE_[A-Za-z]\w*\b(?!\s*\()', ' NUM '),
           (r'\bU32\s*\*', ' PTRNUM '), (r'\bU16\s*\*', ' PTRNUM '),
           (r'\bI32\s*\*', ' PTRNUM '), (r'\bBool\s*\*', ' PTRNUM '),
           (r'\bU8\s*\*', ' PTRB '), (r'\bI64\s*\*', ' PTRSZ '),
           (r'\bOS_time_t\s*\*', ' TIME '), (r'\bOS_\w+_prop_t\s*\*', ' PROP '),
           (r'\bOS_object_token_t\s*\*', ' TOK '),
           # A lowercase os_*_t POINTER, mirroring the same rule on the C side: these are
           # os_fsinfo_t, os_err_name_t and friends, and the C normalises them to PTRB.
           (r'\bos_\w+_t\s*\*', ' PTRB '),
           # U64 NORMALISES LIKE I64, and the honest reading of that is that this gate does
           # not compare the SIGNEDNESS OF A SIZE at all: the C side maps `size_t` and
           # `CFE_MSG_Size_t` to the same SZ token, so it never could. The mapping is here
           # because a translation needs to be ABLE to say `size_t` is unsigned --
           # CFE_SB_MessageStringSet's two sizes were I64, three tbl callers pass -1 meaning
           # "no limit", and as a signed value that copied NOTHING. Found by the differential
           # transcript, not by this gate; recorded so nobody reads a pass here as a claim
           # about size signedness.
           # THE POINTER FORM FIRST, which is the order every other pair in this table uses
           # and which I got wrong: adding the bare rule alone turned `U64 *SymbolAddress` into
           # `SZ *` and the name-strip left `SZ`, so OSAL's two symbol-lookup seam functions
           # reported a pointer parameter as a value. They had been AGREEING AS TWO BLANKS
           # before, `cpuaddr *` and `U64 *` both unrecognised -- the same accidental match as
           # the ES pair above, found the same way.
           (r'\bU64\s*\*', ' PTRSZ '), (r'\bU64\b', ' SZ '),
           (r'\bI64\b', ' SZ '), (r'\bU32\b', ' NUM '),
           (r'\bU16\b', ' NUM '), (r'\bU8\b', ' NUM '), (r'\bI32\b', ' SNUM '),
           # THE POINTER FORM FIRST, AGAIN -- third time this ordering has mattered in two
           # days (U64, cpuaddr, now I16). `I16 *TblHandlePtr` without this rule became `SNUM *`
           # and the name-strip left SNUM, reporting four of api.c's pointer parameters as
           # values.
           (r'\bI16\s*\*', ' PTRSNUM '), (r'\bI16\b', ' SNUM ')]

# A function-pointer parameter, however it is spelled. The C uses typedefs (OS_ArgCallback_t,
# OS_ObjectMatchFunc_t, OS_Config_Callback_t); HolyC has no typedef so the translation writes
# them out. Same parameter either way.
# name -> (NASA's normalised signature, the translation's, why they differ).
DEVIATIONS = {
    'CFE_Config_GetArrayValue': (
        'NUM', 'NUM,PTRNUM',
        "returns CFE_ConfigObj_ArrayValue_t (16 bytes) BY VALUE; HolyC has no struct-return "
        "ABI, so the translation takes a destination pointer. Documented at the call site and "
        "in docs/HOLYC_STRUCT_LIMITS.md."),
    'CFE_ES_SysLog_vsnprintf': (
        'PTRB,SZ,PTRB,', 'PTRB,SZ,PTRB,SZ,PTRSZ',
        "takes a `va_list` as its last parameter, for the same reason and with the same "
        "consequence as EVS_GenerateEventTelemetry below: HolyC's variadic convention hands the "
        "callee an implicit (argc, argv) pair, so one parameter becomes two. It matters here "
        "because the formatted text IS the log entry -- CFE_ES_WriteToSysLog's output is "
        "compared character for character by the differential transcript."),
    'CFE_ES_StatusToString': (
        'SNUM,PTRNUM', 'SNUM,PTRB',
        "takes `CFE_StatusString_t *`, a POINTER TO AN ARRAY of CFE_STATUS_STRING_LENGTH "
        "chars -- so NASA's `*status_string` is the array and `sizeof(*status_string)` is 11. "
        "HolyC has no pointer-to-array type, so the parameter is a plain byte pointer to the "
        "caller's buffer and the size is written out as the constant NASA's sizeof resolves "
        "to. The returned pointer is the caller's own buffer either way, which is the part "
        "that has to stay true."),
    'EVS_GenerateEventTelemetry': (
        ',NUM,NUM,PTRNUM,PTRB,', ',NUM,NUM,PTRNUM,PTRB,SZ,PTRSZ',
        "takes a `va_list` as its last parameter. HolyC has no va_list type; a variadic "
        "function there receives an implicit (argc, argv) pair instead, which is the same "
        "triple StrPrintNV takes, so the one parameter becomes two. This is the seam that lets "
        "the event text -- which IS the packet payload -- be formatted by the translation and "
        "compared byte for byte. See the note at the top of cfe_evs_utils.HC."),
}

KEYWORDS = {'if', 'for', 'while', 'switch', 'return', 'else', 'do', 'sizeof'}

FN_TYPEDEF = re.compile(r'\b(?:(?:OS|CFE)_\w*(?:Callback|MatchFunc|CheckFunc|IncrementFunc|Func)\w*_t'
                        # CFE_SB_MessageTxn_PipeHandler_t is SB's per-pipe handler: the two
                        # directions pass different functions through ProcessPipes, which is the
                        # whole reason it is a pointer rather than a branch.
                        r'|osal_task_entry|OS_TimerSync_t|OS_EventHandler_t'
                        r'|CFE_SB_MessageTxn_PipeHandler_t)\b')
FN_SPELLED = re.compile(r'\(\s*\*+\s*\w*\s*\)\s*\([^)]*\)')

# Any type spelling, C or HolyC. The old version listed the return types one at a time and
# quietly skipped every function returning something not on the list.
#
# AND THE STORAGE CLASS IS PART OF THE SPELLING. Two identifiers were enough until
# cfe_tbl_internal.c, which defines CFE_TBL_HandleListGetNext and GetPrev as
# `static inline CFE_TBL_AccessDescriptor_t *` -- THREE words before the name, so neither
# matched and neither was compared. The hole was shaped exactly like the gate: it had always
# read `static void Foo(` fine (two words, with `static` standing in for the return type) and
# so looked like it handled storage classes. A SOURCE-FILE static inline is the only kind that
# reaches here -- a header one is check_header_inlines.py's business -- and there are two.
C_RET = r'(?:static[ \t]+)?(?:inline[ \t]+)?[A-Za-z_][A-Za-z0-9_]*(?:\s+[A-Za-z_][A-Za-z0-9_]*)?'
H_RET = r'[A-Za-z_][A-Za-z0-9_]*'

def sigs(path, ret_pat, prefix, types):
    src = open(path, errors='replace').read()
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.S)
    src = re.sub(r'//[^\n]*', ' ', src)
    out = {}
    # Anchored to COLUMN 1: a definition at file scope. Indented matches are statements --
    # with a general return-type pattern, `    if (a != b)\n    {` parsed as a function whose
    # return type was `if` and whose name was empty, and the check reported `: NASA (!=)`.
    for m in re.finditer(r'^(?:' + ret_pat + r')[ \t]+\**([A-Za-z_]\w*)[ \t]*\(([^;{]*?)\)\s*\{',
                         src, re.M | re.S):
        name, args = m.group(1), m.group(2)
        head = [w for w in m.group(0).split() if w not in ('static', 'inline')]
        if name in KEYWORDS or (head and head[0] in KEYWORDS):
            continue
        if name.endswith('_Impl'):
            continue          # the backend seam, declared not defined
        # split on commas that are NOT inside a function-pointer parameter list
        depth = 0
        parts, cur = [], ''
        for ch in args:
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
            if ch == ',' and depth == 0:
                parts.append(cur)
                cur = ''
            else:
                cur += ch
        if cur.strip():
            parts.append(cur)
        norm = []
        for a in ([] if args.strip() in ('', 'void') else parts):
            if FN_TYPEDEF.search(a) or FN_SPELLED.search(a):
                norm.append('FN')
                continue
            # An array parameter IS a pointer in C, so turn `T x[N]` into `T *x` and let the
            # type rules classify it. An earlier version returned PTRB unconditionally, which
            # threw the ELEMENT type away: `CFE_ConfigName_t *ModuleListSet[]` normalised to
            # PTRB while the identical `CFE_ConfigName_t **ModuleListSet` -- which is what C
            # passes and what the translation writes -- normalised to PTRNUM, and the checker
            # reported two spellings of one type as a mismatch.
            # The star has to go where the TYPE rules can see it, i.e. in front of the
            # parameter name, not at the end of the declarator. Appending it produced
            # `uint8 VersionNumbers *`, which `\buint8\s*\*` does not match, so
            # OS_GetVersionNumber's parameter fell through to the bare `uint8` rule and the OSAL
            # gate reported NASA as NUM against the translation's PTRB.
            if re.search(r'\[\s*\w*\s*\]', a):
                a = re.sub(r'([A-Za-z_]\w*)\s*\[\s*\w*\s*\]', r'* \1', a)
            for pat, rep in types:
                a = re.sub(pat, rep, a)
            # Drop the parameter NAME but not the tokens substituted above -- an earlier
            # version stripped both, which made `U8 *x` normalise to the empty string while an
            # array parameter (handled by the branch above) kept its PTRB, and the two then
            # compared unequal for no real reason.
            # PTRSNUM WAS MISSING FROM THIS KEEP-LIST and so was stripped like a parameter
            # name -- which means every `CFE_Status_t *` and every TIME-enum pointer parameter
            # has been normalising to the EMPTY STRING on BOTH sides and "matching" as two
            # blanks. The rules that produce PTRSNUM were added deliberately, each with a
            # comment about why signedness matters, and then thrown away one line later. Found
            # when CFE_TBL_Handle_t's pointer form became the first case where the two sides
            # were spelled differently enough to notice.
            a = re.sub(r'\b(?!PTRSNUM|PTRNUM|PTRSZ|PTRB|TIME|PROP|TOK|NUM|SZ|SNUM|FN\b)'
                       r'[A-Za-z_]\w*\b', ' ', a)
            a = re.sub(r'[\s\*]+', '', a)
            norm.append(a)
        out[name] = ','.join(norm)
    return out

def main(argv):
    if not argv:
        print(__doc__)
        return 2
    h = {}
    for d in HCDIRS:
        for f in sorted(glob.glob(os.path.join(d, "*.HC"))):
            h.update(sigs(f, H_RET, '', H_TYPES))
    c, seen = {}, {}
    for cp in argv:
        if not os.path.exists(cp):
            print(f"FAIL cfs-signatures — no such file: {cp}", file=sys.stderr)
            return 1
        for k, v in sigs(cp, C_RET, '', C_TYPES).items():
            c[k], seen[k] = v, os.path.basename(cp)
    bad, waived = [], []
    for name, csig in sorted(c.items()):
        if name not in h:
            continue          # absence is check_coverage.py's job; do not double-report it
        elif h[name] != csig:
            d = DEVIATIONS.get(name)
            if d and (d[0], d[1]) == (csig, h[name]):
                waived.append(f"  deviation: {name} — {d[2]}")
            else:
                bad.append(f"    {seen[name]}: {name}: "
                           f"NASA ({csig})  translation ({h[name]})")
                if d:
                    bad.append(f"      (a deviation IS recorded for {name}, but for "
                               f"({d[0]}) vs ({d[1]}) — it no longer describes this code)")
        elif name in DEVIATIONS:
            # The signatures now agree, so the recorded reason is stale. Fail: a register of
            # exceptions is only trustworthy while every entry is still load-bearing.
            bad.append(f"    {name}: signatures MATCH, but a deviation is still recorded for it "
                       f"in check_signatures.py — delete the entry.")
    if bad:
        print("FAIL cfs-signatures — the translation does not match NASA's signatures.", file=sys.stderr)
        print("  Arity or pointer-ness differs; the coverage check cannot see this.", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1
    for w in waived:
        print(w)
    n = len(c) - len(waived)
    print(f"cfs-signatures: {n} signatures match NASA's across {len(argv)} NASA sources"
          + (f", {len(waived)} deviate for a recorded reason" if waived else ""))
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
