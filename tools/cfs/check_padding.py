#!/usr/bin/env python3
"""A translated `class` must have NASA's struct's LAYOUT, not just its fields.

WHY THIS EXISTS. HolyC classes are fully packed -- no inter-member padding, no alignment, no
tail padding. That is authentic TempleOS and the kernel depends on it, and it is NOT what a C
compiler does. So every byte the C compiler inserts is a layout the translation has to
reproduce explicitly, and nothing else here can see it:

  - check_structs.py compares field NAMES and ORDER. Both sides can agree perfectly and still
    disagree about where the fields are.
  - the transcript sees a field's VALUE, which is the same on both sides as long as each side
    reads the field it wrote. A struct is only written as bytes when something writes it to a
    file or a wire, and cFE does that for file headers, not for its state records.

Measured, on cFE's CFE_FS_FileWriteMetaData_t -- the first struct in this translation where C
pads at all:

    volatile bool IsPending;                     1 byte  at 0       HolyC: 0
    char FileName[CFE_MISSION_MAX_PATH_LEN];     64      at 1       HolyC: 1
    CFE_FS_SubType_Enum_t FileSubType;           uint32  at 68      HolyC: 65
    char Description[CFE_FS_HDR_DESC_MAX_LEN];   32      at 72      HolyC: 69
    CFE_FS_FileWriteGetData_t GetData;           ptr     at 104     HolyC: 101
    CFE_FS_FileWriteOnEvent_t OnEvent;           ptr     at 112     HolyC: 109
    sizeof                                               120        HolyC: 117

An application instantiates that object in its own memory and hands cFE a pointer to it, so a
three-byte disagreement is not cosmetic: the two sides are not describing the same object.

HOW. The C side is the real host C compiler -- offsetof and sizeof out of NASA's own headers,
never a model. The HolyC side IS a model (sum the member sizes), because running the HolyC
compiler would mean building and booting a blob for every struct. The model's premise is
therefore pinned as an execution oracle of its own, tests/exec/cases/e_class_packing.hc, which
asserts the packing rule for the exact shapes this file relies on. A model that is wrong fails
in the direction of approving a mismatch, which is why it does not get to be an assumption.

    tools/cfs/check_padding.py            # check
    tools/cfs/check_padding.py -v         # and print every struct's layout
"""
import glob
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CFE = os.path.join(ROOT, "vendor", "cFE")
OSAL = os.path.join(ROOT, "vendor", "osal")

# The name mapping and the field lists are check_structs.py's job and are not duplicated here:
# if the two tools ever disagreed about which class mirrors which struct, one of them would be
# checking something else entirely.
_spec = importlib.util.spec_from_file_location(
    "check_structs", os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_structs.py"))
check_structs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_structs)

# The include set it takes to compile a probe that mentions every struct under test. This is the
# union of what the two gate scripts use. build/cfs comes BEFORE vendor/shim: both hold an
# osconfig.h, and the shim's is the hand-written stand-in while build/cfs/osconfig.h is
# generated from NASA's own template -- taking the shim's left OS_MAX_RWLOCKS undefined.
INC = ["-I" + p for p in [
    os.path.join(ROOT, "build", "cfs"),
    os.path.join(ROOT, "vendor", "shim"),
    os.path.join(OSAL, "src", "os", "inc"),
    os.path.join(OSAL, "src", "os", "shared", "inc"),
    os.path.join(OSAL, "src", "bsp", "shared", "inc"),
    os.path.join(ROOT, "vendor", "PSP", "fsw", "inc"),
    os.path.join(CFE, "cmake", "sample_defs"),
    os.path.join(CFE, "cmake", "target", "inc"),
] + sorted(glob.glob(os.path.join(CFE, "modules", "*", "fsw", "inc")))
  + sorted(glob.glob(os.path.join(CFE, "modules", "*", "fsw", "src")))
  + sorted(glob.glob(os.path.join(CFE, "modules", "*", "config")))
  + sorted(glob.glob(os.path.join(CFE, "modules", "*", "option_inc")))
  + sorted(glob.glob(os.path.join(CFE, "modules", "*", "private_inc")))]

# Headers the probe includes. A struct no header here declares cannot be measured and is
# REPORTED as unmeasured rather than skipped silently -- an unmeasured struct is the same blind
# spot this file exists to close.
HDRS = [
    "osapi.h", "os-shared-globaldefs.h", "os-shared-idmap.h", "os-shared-file.h",
    "os-shared-filesys.h", "os-shared-dir.h", "os-shared-task.h", "os-shared-queue.h",
    "os-shared-sockets.h", "os-shared-module.h", "os-shared-time.h", "os-shared-timebase.h",
    "os-shared-common.h", "os-shared-printf.h", "os-shared-select.h", "os-shared-shell.h",
    "os-shared-network.h", "os-shared-condvar.h", "os-shared-binsem.h", "os-shared-countsem.h",
    "os-shared-mutex.h", "os-shared-clock.h", "os-shared-errors.h", "os-shared-heap.h",
    "os-shared-rwlock.h",
    "cfe_fs_module_all.h", "cfe_fs_priv.h", "cfe_msg.h", "cfe_sb.h", "cfe_sbr.h",
    "cfe_config.h", "cfe_config_priv.h", "cfe_config_nametable.h", "cfe_resourceid.h",
    "cfe_time.h", "cfe_ta_task.h", "cfe_ta_tasklist.h", "cfe_evs_task.h", "cfe_evs_log_typedef.h",
    "target_config.h", "target_objtab.h",
    # The reset area. CFE_EVS_EarlyInit sizes the WHOLE of CFE_ES_ResetData_t and takes the event
    # log out of it, so the translation declares that type and the eight ES/TIME types under it.
    # They are types, not code -- no ES function is translated -- and this is what measures them.
    "cfe_es_resetdata_typedef.h", "cfe_es_perfdata_typedef.h", "cfe_es_erlog_typedef.h",
    "cfe_time_resetvars_typedef.h",
    # EVS's twenty-two COMMAND MESSAGES and their payloads. They live in the module's config
    # headers, which cfe_evs_task.h does not pull in, so none of them was measured -- and one of
    # them was wrong: CFE_EVS_SetLogMode_Payload_t had LogMode as a U16 because the comment said
    # "a uint16 typedef", and CFE_EVS_LogMode_Enum_t is a uint8. That made the command one byte
    # long and the dispatcher rejected it on length, which the transcript DID catch, three
    # modules later. This is what catches it at the declaration.
    "cfe_evs_module_all.h",
    # ES's command messages, and only one of them matters: cfe_sb_task.c sizes a memory-pool
    # block with sizeof(CFE_ES_RestartCmd_t) so that a ground-commanded reset can always
    # allocate (DCR6772). ES is not translated, but that ONE type's size is load-bearing in SB,
    # so SB's translation declares it and this is what keeps the declaration honest.
    "cfe_es_msg.h",
    # ES's own, as the module arrives: the generic pool's descriptor, bucket and record, and
    # the CRC parameter block. The pool record carries two FUNCTION POINTERS, so
    # check_fnptr_members.py reads it too.
    "cfe_es_generic_pool.h", "cfe_es_crc.h", "cfe_es_extern_typedefs.h",
    # TIME's own, for the same reason: its twenty-three messages, the seven enum typedefs their
    # fields are spelled with, and CFE_TIME_Global's internal types.
    "cfe_time_module_all.h", "cfe_time_utils.h",
    # SB's, and the same story a third time: its sixteen command and telemetry formats live in
    # the module's config headers and its internal types -- the buffer descriptor, the pipe, the
    # 512 KiB partition and CFE_SB_Global_t itself -- are declared in the implementation-private
    # cfe_sb_priv.h. Neither is reachable from cfe_sb.h, which is the PUBLIC header and the only
    # SB one that was on this list, so none of them was measured.
    "cfe_sb_module_all.h", "cfe_sb_priv.h",
]

# NASA .c files whose FILE-SCOPE typedefs have to be lifted into the probe. A module's private
# context and state structs are declared in the implementation file, not in a header, so there is
# nothing to #include: cfe_fs_api.c defines CFE_FS_ParseComponent_Enum_t and
# CFE_FS_ParseContext_t, and that context carries three separate pieces of C padding. The probe
# copies those declarations in verbatim. A struct this list misses is REPORTED as unmeasured, so
# forgetting an entry is visible rather than silent.
CSRC = [
    # OSAL's, for the same reason and newly reachable: osapi-idmap.c declares OS_creator_filter_t
    # and OS_objtype_state_t at file scope, and OS_objtype_state is a live global of the second.
    # check_structs.py began comparing them when osal/src/os/shared/src joined its NASA_DIRS, and
    # this gate then refused to call them measured -- which is the behaviour that makes the pair
    # of gates work: one notices the type exists, the other refuses to pretend it checked it.
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "src", "osapi-idmap.c"),
    os.path.join(CFE, "modules", "fs", "fsw", "src", "cfe_fs_api.c"),
    os.path.join(CFE, "modules", "resourceid", "fsw", "src", "cfe_resourceid_api.c"),
    os.path.join(CFE, "modules", "sbr", "fsw", "src", "cfe_sbr_route_unsorted.c"),
    # CFE_SB_RemovePipeCallback_t is declared INSIDE cfe_sb_api.c -- an implementation-file
    # typedef, which is the shape neither gate reaches by default. The translation writes four
    # bytes of padding into it by hand (a CFE_SB_PipeId_t followed by a char *), and until this
    # line the only thing standing behind that number was my arithmetic.
    os.path.join(CFE, "modules", "sb", "fsw", "src", "cfe_sb_api.c"),
]

# HolyC primitive sizes. U0/I0 is the zero-size position marker (CDirEntry.start), which the
# compiler gives size 0 -- see docs/HOLYC_STRUCT_LIMITS.md limit #4.
PRIM = {"U0": 0, "I0": 0, "Bool": 1, "I8": 1, "U8": 1, "I16": 2, "U16": 2,
        "I32": 4, "U32": 4, "I64": 8, "U64": 8, "F64": 8}

# A HolyC member: `U32 name;`, `U8 *p;`, `U8 name[64][4];`, `I32 (*fn)(args);`, `Cls inner;`
HC_FN = re.compile(r'^\s*([A-Za-z_]\w*)[\w \t\*]*\(\s*\*+\s*([A-Za-z_]\w*)\s*\)\s*\([^;]*\)\s*;')
HC_MEM = re.compile(r'^\s*([A-Za-z_]\w*)\s*((?:\*\s*)*)([A-Za-z_]\w*)\s*((?:\[[^\]]*\])*)\s*;')


def eval_int(expr, vals):
    """An integer constant expression, or None. `(OS_MAX_NUM_OPEN_FILES + 7) / 8` is a real
    array bound in osapi-select.h, so a bare isdigit() check is not enough."""
    e = expr.strip()
    if re.fullmatch(r'-?\d+', e):
        return int(e)
    if re.fullmatch(r'0[xX][0-9a-fA-F]+', e):
        return int(e, 16)
    toks = re.findall(r'[A-Za-z_]\w*|\d+|\S', e)
    if not toks or not all(tk in "()+*/- " or tk.isdigit() or tk in vals for tk in toks):
        return None
    try:
        return int(eval("".join(str(vals[tk]) if tk in vals else tk for tk in toks)))
    except Exception:
        return None


def lifted_typedefs():
    """The file-scope `typedef enum {...} N;` / `typedef struct {...} N;` text from CSRC, in
    declaration order, so the probe can measure a struct that lives in a .c."""
    out = []
    for path in CSRC:
        if not os.path.exists(path):
            continue
        txt = check_structs.strip_comments(open(path, errors="replace").read())
        for m in re.finditer(r'typedef\s+(?:enum|struct)\s*(?:\w+\s*)?\{', txt):
            i, depth = m.end(), 1
            while i < len(txt) and depth:
                if txt[i] == '{':
                    depth += 1
                elif txt[i] == '}':
                    depth -= 1
                i += 1
            end = txt.find(';', i)
            if end > 0:
                out.append(txt[m.start():end + 1])
    return out


def hc_defines():
    """Integer `#define NAME value` from the translation, for array bounds like

        U8 name[OS_MAX_API_NAME];

    The model cannot guess these and must not: an unevaluated bound would make the class look
    one element long. Only plain integers and simple sums of already-known names are resolved;
    anything else stays unknown and reaches the caller as a failure.
    """
    vals = {}
    pend = []

    for d in (os.path.join(ROOT, "Kernel", "Cfs", "osal"), os.path.join(ROOT, "Kernel", "Cfs", "cfe")):
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            for line in open(os.path.join(d, fn), errors="replace"):
                m = re.match(r'\s*#define\s+([A-Za-z_]\w*)\s+(.+?)\s*$', line)
                if m:
                    # `#define OS_FS_DEV_NAME_LEN 32 /**< Device name length */` -- the trailing
                    # doc comment is part of the line and has to come off the VALUE, or the
                    # expression never evaluates and the bound silently stays unknown.
                    v = re.sub(r'/\*.*', '', m.group(2))
                    v = re.sub(r'//.*', '', v).strip()
                    if v:
                        pend.append((m.group(1), v))
    for _ in range(8):
        again = []
        for name, expr in pend:
            v = eval_int(expr, vals)
            if v is None:
                again.append((name, expr))
            else:
                vals[name] = v
        if len(again) == len(pend):
            break
        pend = again
    return vals


def hc_class_bodies():
    """Every `class Name { ... };` body in the translation, by name."""
    out = {}
    for d in (os.path.join(ROOT, "Kernel", "Cfs", "osal"), os.path.join(ROOT, "Kernel", "Cfs", "cfe")):
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            txt = check_structs.strip_comments(open(os.path.join(d, fn), errors="replace").read())
            for m in re.finditer(r'\b(class|union)\s+(\w+)\s*\{(.*?)\}\s*;', txt, re.S):
                out[m.group(2)] = (m.group(3), fn, m.group(1))
    return out


def hc_layout(name, bodies, defines, seen=None):
    """(members, size) for a HolyC class under the packing rule, or (None, reason).

    members is a list of (field_name, offset, size). A type this does not know is an error, not
    a guess: guessing 8 is exactly how a model quietly approves a layout it never understood.
    """
    seen = seen or set()
    if name in seen:
        return None, "recursive class %s" % name
    if name not in bodies:
        return None, "no class %s in the translation" % name
    body, _, kind = bodies[name]
    off, members = 0, []
    widest = 0
    for stmt in body.split(";"):
        stmt = stmt.strip()
        if not stmt:
            continue
        stmt += ";"
        m = HC_FN.match(stmt)
        if m:
            members.append((m.group(2), off if kind == "class" else 0, 8))  # a code address
            widest = max(widest, 8)
            if kind == "class":
                off += 8
            continue
        m = HC_MEM.match(stmt)
        if not m:
            return None, "cannot parse member %r in class %s" % (stmt.strip(), name)
        ty, stars, fname, dims = m.group(1), m.group(2), m.group(3), m.group(4)
        if stars.strip():
            esz = 8
        elif ty in PRIM:
            esz = PRIM[ty]
        else:
            sub, why = hc_layout(ty, bodies, defines, seen | {name})
            if sub is None:
                return None, "member %s.%s has type %s: %s" % (name, fname, ty, why)
            esz = why                                 # hc_layout returns (members, size)
        n = 1
        for d in re.findall(r'\[([^\]]*)\]', dims):
            d = d.strip()
            if not d:
                continue
            dv = eval_int(d, defines)
            if dv is not None:
                n *= dv
            else:
                return None, "member %s.%s has an array bound %r the model could not resolve " \
                             "to an integer" % (name, fname, d)
        members.append((fname, off if kind == "class" else 0, esz * n))
        widest = max(widest, esz * n)
        if kind == "class":
            off += esz * n
    # A union's members all start at 0 and its size is the widest of them. HolyC has no
    # alignment, so there is no rounding up either.
    return members, (off if kind == "class" else widest)


def c_layouts(wanted, verbose=False):
    """{struct: (sizeof, [(field, offset)])} from the host C compiler, plus the unmeasured."""
    use_struct, dropped, dropped_fields = set(), set(), []
    wanted = {k: list(v) for k, v in wanted.items()}
    for _ in range(16):
        live = [(s, f) for s, f in sorted(wanted.items()) if s not in dropped]
        body = ["#include <stdio.h>", "#include <stddef.h>"]
        body += ['#include "%s"' % h for h in HDRS]
        body += lifted_typedefs()
        body.append("int main(void){")
        for s, fields in live:
            ty = ("struct " + s) if s in use_struct else s
            body.append('  printf("%%s SIZE %%zu\\n", "%s", sizeof(%s));' % (s, ty))
            for f in fields:
                body.append('  printf("%%s OFF %%s %%zu %%zu\\n", "%s", "%s", offsetof(%s, %s), '
                            'sizeof(((%s *)0)->%s));' % (s, f, ty, f, ty, f))
        body.append("  return 0; }")
        src = os.path.join(ROOT, "build", "cfs", "check_padding_probe.c")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        open(src, "w").write("\n".join(body) + "\n")
        exe = src[:-2]
        cc = os.environ.get("HOSTCC", "cc")
        r = subprocess.run([cc, "-O0", "-w"] + INC + ["-o", exe, src],
                           capture_output=True, text=True)
        if r.returncode == 0:
            break
        progress = False
        # A struct named by its tag rather than its typedef: retry as `struct Name`.
        for m in re.finditer(r"(?:undeclared identifier|unknown type name) '(\w+)'", r.stderr):
            if m.group(1) in wanted and m.group(1) not in use_struct:
                use_struct.add(m.group(1)); progress = True
        # Declared but not defined by any header on the list: unmeasurable here.
        for m in re.finditer(r"incomplete type '(?:struct )?(\w+)'", r.stderr):
            if m.group(1) in wanted and m.group(1) not in dropped:
                dropped.add(m.group(1)); progress = True
        # A field this configuration's #ifdefs exclude (OS_shared_global_vars.DebugLevel).
        for m in re.finditer(r"no member named '(\w+)' in '(?:struct )?(\w+)'", r.stderr):
            fld, s = m.group(1), m.group(2)
            if s in wanted and fld in wanted[s]:
                wanted[s].remove(fld); dropped_fields.append((s, fld)); progress = True
        if not progress:
            return None, r.stderr, dropped, dropped_fields
    else:
        return None, "the probe would not compile after 16 rounds", dropped, dropped_fields
    out = {}
    for line in subprocess.run([exe], capture_output=True, text=True).stdout.split("\n"):
        p = line.split()
        if len(p) == 3 and p[1] == "SIZE":
            out.setdefault(p[0], [0, []])[0] = int(p[2])
        elif len(p) == 5 and p[1] == "OFF":
            out.setdefault(p[0], [0, []])[1].append((p[2], int(p[3]), int(p[4])))
    return out, None, dropped, dropped_fields


def main(argv):
    verbose = "-v" in argv
    nasa = check_structs.nasa_structs()
    bodies = hc_class_bodies()
    defines = hc_defines()
    pairs = []
    unpaired = []
    for name in sorted(bodies):
        cand = check_structs.pair_name(name, nasa)
        if cand:
            pairs.append((name, cand))
        else:
            unpaired.append(name)
    # AN UNPAIRED CLASS IS DROPPED HERE, AND check_structs.py IS WHAT FAILS ON IT. The two gates
    # share pair_name() and nasa_structs(), and the smoke script runs structs first, so a class
    # with no counterpart stops the build there with the reason -- making it a failure here too
    # would be the same diagnostic twice.
    #
    # It is still printed, because a silent skip is how this project's recurring failure works:
    # a count of 229 "match" says nothing about how many were never looked at. The number went
    # from 4 to 3 when the bare-struct regex in check_structs stopped running away across
    # declarations and CFE_ES_GenPoolRecord -- the pool record, the largest struct in ES -- was
    # found for the first time.
    if not pairs:
        print("FAIL cfs-padding — no translated class maps to a NASA struct", file=sys.stderr)
        return 1

    wanted = {cand: nasa[cand][0] for _, cand in pairs}
    clay, err, unmeasured, absent_fields = c_layouts(wanted, verbose)
    if clay is None:
        print("FAIL cfs-padding — could not measure NASA's layouts with the host C compiler.",
              file=sys.stderr)
        print("\n".join(str(err).split("\n")[:20]), file=sys.stderr)
        return 1

    bad, checked, padded = [], 0, []
    for name, cand in pairs:
        if cand in unmeasured:
            continue
        csize, coffs = clay[cand]
        hmem, hsize = hc_layout(name, bodies, defines)
        if hmem is None:
            bad.append("    class %s: %s" % (name, hsize))
            continue
        # Compare only the fields the C probe could measure, in NASA's order.
        hoff = {f: (o, s) for f, o, s in hmem}
        diffs = [(f, o, s, hoff.get(f)) for f, o, s in coffs if not hoff.get(f) or hoff[f][0] != o]
        wide = [(f, o, s, hoff[f]) for f, o, s in coffs if f in hoff and hoff[f][1] != s]
        checked += 1
        if csize != hsize or diffs or wide:
            lines = ["    class %s (vs %s)" % (name, cand),
                     "        %-24s %18s   %s" % ("", "NASA (off/size)", "translation")]
            # A member at the WRONG WIDTH is a different mistake from missing padding, and
            # padding it over would bury the real one. Report the widths first.
            for f, o, s, h in wide:
                lines.append("        %-24s %8d /%4d   %8d /%4d   WIDTH" % (f, o, s, h[0], h[1]))
            for f, o, s, h in diffs:
                lines.append("        %-24s %8d /%4d   %8s /%4s   OFFSET" %
                             (f, o, s, h[0] if h else "-", h[1] if h else "-"))
            if csize != hsize:
                lines.append("        %-24s %8d        %8d        SIZEOF" % ("(whole struct)", csize, hsize))
            bad.append("\n".join(lines))
        elif any(o != sum(sz for _, _, sz in hmem[:i]) for i, (_, o, _) in enumerate(hmem)):
            padded.append(name)
        if verbose:
            print("  %-44s sizeof %d" % (cand, csize))
            for f, o, s in coffs:
                print("      %-28s %4d /%4d" % (f, o, s))

    if bad:
        print("FAIL cfs-padding — a translated class does not have NASA's LAYOUT.", file=sys.stderr)
        print("  HolyC classes are packed; where the C compiler aligns a member, the", file=sys.stderr)
        print("  translation has to carry the padding explicitly. Field names and order can", file=sys.stderr)
        print("  match perfectly while the two sides describe different objects.", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1
    # UNMEASURED IS A FAILURE, not a note. A gate that prints "I could not check this" and
    # exits 0 is the thing this project's own gate scripts forbid -- it scrolls past in a CI log
    # and the class is simply not covered. It was benign while every instance was chased by hand
    # (os-shared-rwlock.h for the header list, then CSRC for the three modules that declare a
    # context struct inside the .c); it stops being benign at es/tbl/evs, which are 37 sources
    # between them and declare private state structs in .c files throughout.
    if unmeasured:
        print("FAIL cfs-padding — a translated class's layout could not be MEASURED, which is",
              file=sys.stderr)
        print("  not the same as matching. Add the header that defines it to HDRS, or, if NASA",
              file=sys.stderr)
        print("  declares it inside a .c, add that source to CSRC:", file=sys.stderr)
        for s in sorted(unmeasured):
            print("    %s" % s, file=sys.stderr)
        return 1
    # And the two struct gates must cover the SAME set. They agree today; that is luck, not a
    # property -- check_structs maps a class the moment a NASA header or .c declares it, while
    # this one also needs it to be reachable from HDRS/CSRC.
    if checked != len(pairs):
        print("FAIL cfs-padding — check_structs.py maps %d classes, this gate measured %d. The"
              % (len(pairs), checked), file=sys.stderr)
        print("  two must cover the same set, or a class is under one gate and not the other.",
              file=sys.stderr)
        return 1
    for s, f in absent_fields:
        print("  not in this configuration: %s.%s (an #ifdef excludes it)" % (s, f))
    if unpaired:
        print("  not compared here, no NASA counterpart (check_structs.py owns this): %s"
              % ", ".join(unpaired))
    print("cfs-padding: %d translated classes have NASA's byte layout%s%s" %
          (checked, (" (%d carry explicit padding: %s)" % (len(padded), ", ".join(sorted(padded))))
           if padded else "",
           (", %d unpaired and so NOT measured" % len(unpaired)) if unpaired else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
