#!/usr/bin/env python3
"""No translated file copies a CLASS into an array slot or through a bare pointer.

THE DEFECT THIS REFUSES, measured in docs/HOLYC_STRUCT_LIMITS.md #21 and pinned by
tests/exec/cases/e_struct_copy_into_slot.hc: a struct assignment whose destination is `arr[i]`
or `*ptr` copies only the FIRST EIGHT BYTES. Silently -- no diagnostic, no refusal, and the
bytes past the first two words are left as they were. The same assignment to a plain variable,
to `var.member` or to `ptr->member` is whole, so it is the destination form that decides.

WHY A GATE AND NOT JUST A NOTE. The compiler already REFUSES the related case -- a class return
by value over eight bytes is a diagnostic -- so a reader has every reason to assume the
assignment is safe too. It is not, and the first instance in the tree was found by the
differential transcript: cfe_es_perf.c's capture path stored a twelve-byte log entry with
`Perf->DataBuffer[DataEnd] = EntryData` and the hardware timestamp never arrived. Every
performance log entry had a zero timestamp, which is the one thing a performance log is for.
Nothing else in the gate set could see it: the layout matches, the signatures match, the
function is in the blob. The defect is in the STORE.

AND THE FIRST VERSION OF THIS GATE DID NOT CATCH THE SECOND INSTANCE, which is the reason the
type resolution below is as careful as it is. cfe_es_appctrl.c's `*RestartParamPtr =
AppRecPtr->StartParams;` is the same defect on a 344-byte structure -- the whole file name,
entry point, stack size and exception action of a restarting app -- and this gate reported
"none of them a class copy" with a reassuring count while it was present. Three separate holes
let it through, and all three are the same hole in different clothes: THE GATE COULD NOT FIND
SOMETHING AND TREATED NOT-FOUND AS CLEAN.

  1. `CFE_ES_AppRecord_t *AppRecPtr;` was not recognised as a DECLARATION at all, because the
     pattern had no room for the `*`. Pointer-to-record is how every function in cFS reaches a
     record, so this was not an edge case; it was the common case.
  2. A base name the gate could not resolve was skipped with no diagnostic and WITHOUT BEING
     COUNTED. The printed line said how many member-RHS cases went unresolved and said nothing
     at all about these.
  3. The resolution stopped at the base. `x->member` was declared a counted hole rather than
     followed, although the member's type is written down in the class declaration the gate
     had already parsed to get the class list.

So: declarations are parsed with pointer depth, locals and PARAMETERS both; member accesses are
followed through the class declarations; and an unresolved base is a FAILURE with the name
printed, not a skip. UNRESOLVED_OK records the ones that cannot be resolved, each with a reason,
on the same rule as the other gates' exemption lists -- a stale entry fails.

HOW IT DECIDES WHAT IS A STRUCT. A destination of the dangerous shape is only a problem when
the thing being assigned is a CLASS BY VALUE. So the right-hand side is resolved to a declared
type and a pointer depth: `rec` of a class type at depth 0 is flagged, `recptr` at depth 1 is
not, and neither is a scalar -- an 8-byte store covers every scalar this port has.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# THE WHOLE KERNEL, not just the translation. `arr[i] = someStruct` is an ordinary idiom and
# this is a COMPILER defect, so the rest of the kernel -- CTask, the DolDoc entries, the window
# records, the virtio descriptors, the RV JIT's tables -- is exposed to it in exactly the same
# way, and nothing else would say so.
HCROOT = os.path.join(ROOT, "Kernel")

# `arr[...] = x;` or `*p = x;` where x is a bare lvalue -- no operators, no call.
#
# MATCHED AGAINST A STATEMENT, NOT A LINE. The formatter wraps at about 96 characters and a
# realistic destination -- CFE_ES_Global.ResetDataPtr->Perf.DataBuffer[DataEnd] -- is 55 of
# them before the right-hand side, so a line-anchored pattern would simply not see a wrapped
# copy. Statements are split on ';' below and whitespace is collapsed first.
#
# THE RIGHT-HAND SIDE'S `->` IS MATCHED AS A UNIT. A character class holding both `>` and `-`
# also matches a bare minus, so `*_offset = addr-tmpfsc->base` came through as a "bare lvalue"
# and then went onto the unresolved list, where it was noise hiding the one entry that mattered.
#
# AND THE DESTINATION STOPS AT THE SUBSCRIPT, which is a measured fact and not a simplification:
# `arr[i].member = s` is a WHOLE copy. tests/exec/cases/e_struct_copy_into_slot.hc pins it with
# the rest. Allowing a trailing member selector here raised a false positive against
# cfe_ta_task.HC's `CFE_TA_CpuTaskAffinity[i].CpuFromOS = cpuget`, which is correct code.
# AND A DEREFERENCE IS ALLOWED ON THE RIGHT, which it was not, and that was a silent skip of
# the exact shape cFS uses most. `AppRecPtr->StartParams = *Params;` is how cfe_es_apps.c copies
# a 344-byte parameter block, and `*Params` did not match the right-hand side pattern at all --
# so a statement of that shape was not flagged, not exempted, and not even COUNTED. Measured, in
# tests/exec/cases/e_struct_copy_into_slot.hc: `ptr->member = *p` is a whole copy and
# `arr[i] = *p` is the first eight bytes, so the source form changes nothing and the destination
# still decides. The leading `*` is stripped before resolution.
#
# AND A SUBSCRIPT IS ALLOWED ON THE RIGHT TOO. `TaskList[NumTasks] = TaskList[0];` is NASA's own
# line in cfe_es_apps.c -- moving the main task to index 0 of a list it is building -- and a
# right-hand side with brackets did not match, so that statement was skipped in silence like the
# dereference was. The measured table says the DESTINATION decides and a source array element is
# fine, so `arr[i] = arr[j]` of a class is broken exactly as `arr[i] = s` is, and this is how the
# gate gets to say so. Subscripts are stripped before resolution: an element of `Class arr[]` has
# the element's type.
LV = (r'\*?[A-Za-z_]\w*(?:\[[^\]]*\])*'
      r'(?:(?:\.|->)[A-Za-z_]\w*(?:\[[^\]]*\])*)*')
ASSIGN = re.compile(r'^(\*[A-Za-z_]\w*|[A-Za-z_][\w.\[\]>-]*\[[^\]]*\])\s*=\s*('
                    + LV + r')$')
# `public class CHash` is how the kernel's own headers write one, so the modifier has to be
# allowed -- without it every class declared in a .HH went unseen, and with it every member
# access through one of them went unresolved.
CLASS_OPEN = re.compile(r'^[ \t]*(?:(?:public|extern|_extern|import|_import)\s+)*'
                        r'(?:class|union)\s+([A-Za-z_]\w*)[^\n;]*$', re.M)

# A declaration or a parameter: a type, any number of stars, a name, and a terminator that
# cannot be an operator. `;` and `[` are declarations; `,` and `)` are parameters; `=` is a
# declaration with an initialiser. The two-identifiers-in-a-row shape is what makes this safe
# to run unanchored, which it has to be, because a parameter is never at the start of a line.
#
# `(` is in the terminator set so that a FUNCTION DEFINITION's own name is collected -- `*drv =
# Drv2Let` assigns a function's address and the name has to resolve to something. Two
# identifiers in a row are still required, and a type must start with a capital, so a call site
# (`MemCpy(a, b)`, `return Foo(x)`) is not mistaken for one.
DECL = re.compile(r'(?<![\w.>-])([A-Z][A-Za-z0-9_]*)\s+(\**)\s*([A-Za-z_]\w*)\s*(?=[;,)\[=(])')
# `I64 op, rd, immI;` -- the second and later declarators have no type in front of them, so the
# pattern above sees only the first. Two of the names it could not resolve were this shape.
#
# AND A SUBSCRIPT CAN SIT BETWEEN THEM: `U8 line[160], *p;` declares an array and a pointer, and
# a version of this that matched the comma immediately after the first NAME stopped at the `[`
# and never collected `p` at all. `p` then resolved through the whole-tree fallback to an
# unrelated `p` of a class type, and the gate reported a correct `line[i++] = *p` byte copy as a
# class copy -- a checker blaming the translation for its own blind spot, which docs/ records as
# worse than no checker. Subscripts are skipped, with their brackets balanced.
DECL_MORE = re.compile(r'\s*,\s*(\**)\s*([A-Za-z_]\w*)')
# `U0 (*fp_hndlr)(I64 sc)` -- a function-pointer declarator. Its depth is 1 whatever it points
# at, which is all this gate needs: a pointer is never a class by value.
DECL_FNPTR = re.compile(r'\(\s*\*+\s*([A-Za-z_]\w*)\s*\)\s*\(')

# An object-like `#define` is a VALUE, not a variable, so it has no declaration to find -- and
# `arr[i] = TRUE` would otherwise be an unresolved right-hand side. The macro's own body is not
# followed: a macro cannot name a class by value in this tree, and if one ever does, this gate
# will say the name resolved to nothing rather than stay quiet about it.
DEFINE = re.compile(r'^[ \t]*#define[ \t]+([A-Za-z_]\w*)(?![\w(])', re.M)
# The compiler's own names, which are declared nowhere in the tree.
BUILTIN = {"TRUE", "FALSE", "NULL", "ON", "OFF"}
# HolyC's SUB-REGISTER SELECTORS, which look exactly like a member access and are not one:
# `res.u8[1] = d.u8[0]` byte-swaps an I64, and `u8` is a language feature, not a field. There
# are fourteen of them in Kernel/KMisc.HC's endian helpers alone, and every one came out as a
# right-hand side with no type until this set existed. A slice of an integer is an integer, so
# none of them can ever be a class by value.
SUBREG = {"u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64"}

# Sites verified SAFE, each with the reason. A struct of 8 bytes or less copies whole, so a
# small class is allowed here -- with its size stated, because the entry is a claim about it.
ALLOW = {
    # CFE_SBR_RouteId is ONE U16 -- two bytes, which the store handles at its own width and
    # without touching the neighbouring slots. That is not arithmetic: the narrow-class case in
    # tests/exec/cases/e_struct_copy_into_slot.hc writes a 2-byte class into one slot of an
    # array of them and reads the three after it back unchanged, because an 8-byte store here
    # would be the recorded array-deref store bug and CFE_SBR_MSGMAP is exactly the array it
    # would corrupt. NASA's own line is `CFE_SBR_MSGMAP[hash] = RouteId;` and it stays.
    "Kernel/Cfs/cfe/cfe_sbr_map_hash.HC:82": "CFE_SBR_RouteId is 2 bytes (one U16)",
}

# Right-hand sides whose base name this gate cannot resolve, each with the reason. An entry is
# a claim that the name is not a class-by-value, and a stale one fails.
UNRESOLVED_OK = {}


def statements(src):
    """(statement text with whitespace collapsed, line number it started on) for each ';'."""
    out = []
    lineno = 1
    buf = []
    start = 1
    for ch in src:
        if ch == ';':
            text = " ".join("".join(buf).split())
            if text:
                out.append((text, start))
            buf = []
            start = lineno
        elif ch in "{}":
            buf = []
            start = lineno
        else:
            if ch == '\n':
                lineno += 1
                if not "".join(buf).strip():
                    start = lineno
            buf.append(ch)
    return out


def hc_files(exts=(".HC",)):
    out = []
    for root, _, fs in os.walk(HCROOT):
        for f in sorted(fs):
            if f.endswith(exts):
                out.append(os.path.join(root, f))
    return out


# strip_comments LIVES IN cfs_text.py, because four gates each had their own and three of them
# removed BLOCK comments first -- which makes a `/*` inside a `//` comment a real opener. See
# that file for what it cost and for the one-pass fix; it carries its own driven control.
from cfs_text import strip_comments  # noqa: F401 -- re-exported for this gate's own callers


def class_members(src, classes):
    """{class name: {member name: (type, pointer depth)}} read from the declarations.

    The brace matching is deliberate rather than a regex: docs/ records a lazy `{(.*?)};` that
    spanned three structs and hid the largest one in ES from every gate at once.
    """
    out = {}
    for m in CLASS_OPEN.finditer(src):
        name = m.group(1)
        i = src.find("{", m.end())
        if i < 0:
            continue
        depth = 0
        j = i
        while j < len(src):
            if src[j] == '{':
                depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = src[i + 1:j]
        mem = {}
        # NESTED BLOCKS ARE FLATTENED, NOT STRIPPED. An anonymous union inside a class puts its
        # members in the enclosing scope in HolyC, so removing the block removed real members --
        # and the only cost of flattening a named one too is a resolution this gate did not
        # need, which fails out loud rather than quietly.
        flat = body.replace("{", " ").replace("}", " ")
        for mname, ty, depth in declarators(flat):
            mem.setdefault(mname, (ty, depth))
        out[name] = mem
    return out


def skip_subscripts(src, pos):
    """Past any `[...]` after a declarator's name, brackets balanced, and any space after it."""
    while pos < len(src):
        while pos < len(src) and src[pos] in " \t\n":
            pos += 1
        if pos >= len(src) or src[pos] != '[':
            break
        depth = 0
        while pos < len(src):
            if src[pos] == '[':
                depth += 1
            elif src[pos] == ']':
                depth -= 1
                if depth == 0:
                    pos += 1
                    break
            pos += 1
    return pos


def declarators(src):
    """(name, type, pointer depth) for every declaration or parameter in `src`.

    ONE WALKER FOR BOTH THE NAME TABLE AND THE CLASS BODIES, because they drifted: the bodies
    were read with the plain pattern alone, so `I64 clus,size;` in CDirEntry contributed `clus`
    and not `size`, and `U0 (*Address)();` in OS_static_symbol_record_t contributed nothing --
    and both showed up as right-hand sides this gate could not resolve.
    """
    for m in DECL.finditer(src):
        yield m.group(3), m.group(1), len(m.group(2))
        pos = skip_subscripts(src, m.end())
        while True:
            mm = DECL_MORE.match(src, pos)
            if not mm:
                break
            yield mm.group(2), m.group(1), len(mm.group(1))
            pos = skip_subscripts(src, mm.end())
            if pos >= len(src) or src[pos] not in ",":
                break
    for m in DECL_FNPTR.finditer(src):
        yield m.group(1), "<function pointer>", 1


def collect(src, into):
    """Add every declaration in `src` to {name: set of (type, pointer depth)}.

    A NAME CAN HAVE SEVERAL TYPES and this keeps all of them, because resolution here is not
    scope-aware: `cmd` is a different class in each of cfe_es_perf.HC's command handlers, and
    keeping only the last one made `cmd->FilterMask` unresolvable. Resolution then tries every
    candidate and FLAGS if any of them makes the right-hand side a class by value -- the
    conservative direction, because a false positive fails out loud and gets looked at, and a
    false negative is the thing this gate exists to not do.
    """
    for name, ty, depth in declarators(src):
        into.setdefault(name, set()).add((ty, depth))


def resolve(expr, declared, members):
    """The set of (type, pointer depth) `expr` can have, or None if nothing resolved."""
    # A LEADING `*` IS A DEREFERENCE AND MUST REDUCE THE DEPTH, not just be dropped. `arr[i] =
    # *p` where p points at a class IS the defect -- that is the measured broken form -- so
    # stripping the star and then reading p's own depth would have declared every such site a
    # pointer and safe. `*p` where p is `U8 *` is a byte and still correct.
    derefs = len(expr) - len(expr.lstrip("*"))
    expr = re.sub(r'\[[^\]]*\]', '', expr.lstrip("*"))
    parts = re.split(r'\.|->', expr)
    cands = declared.get(parts[0])
    if not cands:
        return None
    for p in parts[1:]:
        nxt = set()
        for ty, _ in cands:
            if ty in members and p in members[ty]:
                nxt.add(members[ty][p])
        # A real class member wins; a sub-register selector is only consulted when none of the
        # candidate types declares a field by that name.
        if not nxt and p in SUBREG:
            nxt.add(("<sub-register>", 0))
        if not nxt:
            return None
        cands = nxt
    if derefs:
        cands = {(ty, depth - derefs) for ty, depth in cands if depth >= derefs}
        if not cands:
            return None
    return cands


# --- LIMIT 26: a class PARAMETER passed by value carries only its first 8 bytes -------------
# The sibling of limit 21, which the rest of this file refuses, in the other syntactic
# position. Measured on the harness with a 72-byte class: the first field arrives correctly and
# `b.Name[0]` -- the ninth byte -- reads back as the value of the NEXT ARGUMENT. No diagnostic.
# WHAT THIS DOES NOT CHECK, measured: it scans DEFINITIONS, so a missing `&` at a CALL SITE is
# invisible to it -- and md_cmds.c has two such call sites, where NASA passes a 72-byte
# MD_SymAddr_t by value. Dropping the `&` in the exercise left this gate reporting 89 parameters
# and OK. The TRANSCRIPT catches it loudly rather than quietly: a 35-line diff including
# `CFE_TBL_GetAddress: Bad AppId=1114113`, because the struct's bytes bleed into the next
# argument register. So the call-site risk is self-revealing and is left to the transcript.
# Pinned by tests/exec/cases/e_class_byval_param.hc, which also shows the 8-byte case arriving
# WHOLE and the callee's write NOT reaching the caller -- so the first eight bytes really are a
# copy, which rules out "it is silently passed by reference" as the explanation.
#
# WHY IT NEEDS A GATE AND NOT A NOTE. It compiles clean and the FIRST FIELD IS ALWAYS RIGHT, so
# a one-field check passes and so does any class whose interesting member happens to be first.
# Eighty-six translated functions take a class by value today and NONE of them is broken,
# because every type involved fits in a register -- CFE_SB_MsgId 4 bytes, CFE_SBR_RouteId 2,
# CFE_SB_Qos_t 2, CFE_TIME_SysTime 8, OS_time_t 8, OS_cpuset_t 1. cFS passes small opaque
# wrappers by value and large structures by pointer, so the cliff was never reached. That is
# luck, not design: MD's MD_UpdateTableDwellEntry takes a 72-byte MD_SymAddr_t by value.
#
# THE SIZE IS MEASURED, NOT LISTED. It comes from check_padding's layout model -- the same one
# compared field for field and byte for byte against NASA -- so a class that GROWS past eight
# bytes fails this gate without anyone remembering to look at it again.
# EIGHT, MEASURED, NOT ASSUMED. The RISC-V LP64D ABI passes a 16-byte struct in a REGISTER
# PAIR, so 16 is exactly where a reader would expect this to work and where a threshold of 8
# would be rejecting correct code -- the one failure mode the other gates in this directory are
# written to avoid. Probed with both sizes at once: a 16-byte class reads its second word as the
# NEXT ARGUMENT (`B=77` where 77 was the tag), and an 8-byte class arrives whole with the tag
# intact. One register, never two. CFE_TIME_SysTime and OS_time_t are both exactly 8 and both
# work, which is why the limit is 8 and not 4.
# A CLASS LOCAL DECLARED WITH AN INITIALISER -- `MM_SymAddr_t x = Msg->Payload.y;` -- which
# carries only its FIRST EIGHT BYTES in this compiler, silently, where the SAME copy written as
# two statements is whole. docs/HOLYC_STRUCT_LIMITS.md #27, pinned by
# tests/exec/cases/e_class_decl_init.hc.
#
# WHY THIS NEEDED ITS OWN PATTERN. The ASSIGN check above looks at the DESTINATION form -- an
# array slot or a dereference -- and a declaration's destination is a plain local, so it was
# outside the scan entirely. The form cost a transcript divergence in mm_cmds.c: NASA writes
# `MM_SymAddr_t DestSymAddress = Msg->Payload.DestSymAddress;` in MM_FillMemCmd and declares
# then assigns in the other four handlers, so only one of the five broke -- and it broke by
# keeping the first eight bytes (the Offset) and losing the next sixty-four (the SymName), which
# sent a fill to the wrong address with the command built correctly.
#
# A SCALAR INITIALISER IS FINE and must not be flagged, so the type has to be a known class and
# the declarator must not be a pointer.
DECL_INIT = re.compile(r'^([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*=\s*(.+)$')

# Initialisers that are NOT a class copy: a literal, NULL, or an address-of. Each is 8 bytes or
# less by construction.
DECL_INIT_OK = re.compile(r'^\s*(?:NULL|&|-?\d|0[xX][0-9a-fA-F]|\'|")')


def check_decl_inits(files, sources, classes, members, tree_names, constants):
    """Refuse a class-typed local declared with an initialiser -- limit #27.

    EXEMPT BY SIZE, NOT BY SITE. The truncation is to the first eight bytes, so a class of eight
    bytes or less is copied WHOLE and the form is harmless -- measured in
    tests/exec/cases/e_class_decl_init.hc, which carries the 8-byte case as its control. The
    first version of this check flagged all seventeen existing sites, every one of them
    CFE_SB_MsgId, CFE_SBR_RouteId, OS_time_t or CFE_TIME_SysTime -- the cFE scalar wrappers, all
    4 or 8 bytes. A per-site allowlist for those would have been seventeen lines that say
    nothing and rot; the SIZE is the property.
    """
    import importlib.util as _iu
    here = os.path.dirname(os.path.abspath(__file__))
    _s = _iu.spec_from_file_location("check_padding", os.path.join(here, "check_padding.py"))
    cp = _iu.module_from_spec(_s)
    _s.loader.exec_module(cp)
    bodies = cp.hc_class_bodies()
    defines = cp.hc_defines()
    sizes = {}
    rc = 0
    checked = 0
    small = 0
    unsized = []
    for p in files:
        rel = os.path.relpath(p, ROOT)
        src = sources[p]
        declared = {}
        collect(src, declared)
        for name, cands in constants.items():
            declared.setdefault(name, cands)
        for name, cands in tree_names.items():
            declared.setdefault(name, cands)
        for stmt, lineno in statements(src):
            m = DECL_INIT.match(stmt)
            if not m:
                continue
            ty, _name, init = m.group(1), m.group(2), m.group(3)
            if ty not in classes:
                continue
            checked += 1
            if DECL_INIT_OK.match(init):
                continue
            key = "%s:%d" % (rel, lineno)
            if key in DECL_INIT_ALLOW:
                continue
            if ty not in sizes:
                _mem, _sz = cp.hc_layout(ty, bodies, defines)
                sizes[ty] = _sz if _mem is not None else None
            sz = sizes[ty]
            # AN UNSIZED CLASS IS A FAILURE, not a pass. A type this gate cannot measure is
            # exactly the case it must not wave through -- that is the not-found shape.
            if sz is None:
                unsized.append((key, ty, stmt))
                continue
            if sz <= BYVAL_LIMIT:
                small += 1
                continue
            print("FAIL cfs-structcopy — %s declares a CLASS local (%s) WITH AN INITIALISER."
                  % (key, ty), file=sys.stderr)
            print("  That copies only the FIRST EIGHT BYTES, silently, where the same copy as"
                  " two statements", file=sys.stderr)
            print("  is whole: docs/HOLYC_STRUCT_LIMITS.md #27, pinned by"
                  " tests/exec/cases/e_class_decl_init.hc.", file=sys.stderr)
            print("  Split it into a declaration and an assignment, and say why at the site --"
                  " as", file=sys.stderr)
            print("  Kernel/Cfs/mm/mm_cmds.HC's MM_FillMemCmd does.", file=sys.stderr)
            print("    %s;  (%s is %d bytes)" % (stmt, ty, sz), file=sys.stderr)
            rc = 1
    if unsized:
        print("FAIL cfs-structcopy — %d class local(s) declared with an initialiser whose TYPE"
              % len(unsized), file=sys.stderr)
        print("  this gate could not size, so it cannot say whether the copy is truncated:",
              file=sys.stderr)
        for key, ty, stmt in unsized[:20]:
            print("    %s  %s  in  %s;" % (key, ty, stmt), file=sys.stderr)
        rc = 1
    return rc, checked, small


# Class declarations with an initialiser that are known safe (8 bytes or less). Empty today; an
# entry needs the measured size in its comment.
DECL_INIT_ALLOW = set()

BYVAL_LIMIT = 8

# A function DEFINITION's parameter list: a name at column 1 followed by (...) and a brace.
FNDEF = re.compile(r'^([A-Za-z_]\w*)[\w \t\*]*?\b(\w+)\s*\(([^;{)]*)\)\s*\{', re.M)
# `Type name` with no star -- a by-value parameter.
BYVAL_PARAM = re.compile(r'^\s*(?:const\s+)?([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*$')

# Parameters verified safe although this gate cannot size them, each with the reason. A stale
# entry fails, on the same rule as ALLOW and UNRESOLVED_OK above.
BYVAL_UNSIZED_OK = {}


def check_byval_params(classes):
    """0 if every by-value class parameter in the TRANSLATION is 8 bytes or less."""
    import importlib.util as _iu
    here = os.path.dirname(os.path.abspath(__file__))
    _s = _iu.spec_from_file_location("check_padding", os.path.join(here, "check_padding.py"))
    cp = _iu.module_from_spec(_s)
    _s.loader.exec_module(cp)
    bodies = cp.hc_class_bodies()
    defines = cp.hc_defines()

    sizes, unsized = {}, []
    rc, n = 0, 0
    hits = []
    for d in cp.HCDIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".HC"):
                continue
            path = os.path.join(d, fn)
            src = strip_comments(open(path, errors="replace").read())
            for m in FNDEF.finditer(src):
                line = src[:m.start()].count("\n") + 1
                for prm in m.group(3).split(","):
                    pm = BYVAL_PARAM.match(prm)
                    if not pm or pm.group(1) not in classes:
                        continue
                    ty = pm.group(1)
                    n += 1
                    if ty not in sizes:
                        _mem, sz = cp.hc_layout(ty, bodies, defines)
                        sizes[ty] = sz if _mem is not None else None
                    sz = sizes[ty]
                    key = "%s:%d" % (os.path.relpath(path, ROOT), line)
                    if sz is None:
                        if key not in BYVAL_UNSIZED_OK:
                            unsized.append((key, m.group(2), ty))
                    elif sz > BYVAL_LIMIT:
                        hits.append((key, m.group(2), ty, sz))
    if hits:
        print("FAIL cfs-structcopy — a function takes a CLASS BY VALUE that is larger than"
              " %d bytes." % BYVAL_LIMIT, file=sys.stderr)
        print("  Only the first %d bytes arrive; the rest reads as the NEXT ARGUMENT's value,"
              " silently:" % BYVAL_LIMIT, file=sys.stderr)
        print("  docs/HOLYC_STRUCT_LIMITS.md #26. Take a pointer and record the deviation, as"
              " the", file=sys.stderr)
        print("  md_dwell_tbl.HC note does.", file=sys.stderr)
        for key, fname, ty, sz in hits:
            print("    %s  %s(%s) -- %s is %d bytes" % (key, fname, ty, ty, sz),
                  file=sys.stderr)
        rc = 1
    if unsized:
        print("FAIL cfs-structcopy — a by-value class parameter could not be SIZED, so this"
              " gate cannot", file=sys.stderr)
        print("  say whether it is within the %d-byte limit. Not-found is not clean:"
              % BYVAL_LIMIT, file=sys.stderr)
        for key, fname, ty in unsized:
            print("    %s  %s(%s)" % (key, fname, ty), file=sys.stderr)
        rc = 1
    for key in sorted(BYVAL_UNSIZED_OK):
        print("  by-value parameter allowed unsized: %s -- %s" % (key, BYVAL_UNSIZED_OK[key]))
    if rc == 0:
        big = max((s for s in sizes.values() if s is not None), default=0)
        print("cfs-byval: %d by-value class parameter(s) across %d type(s), largest %d bytes"
              " (limit %d, HolyC limit #26)" % (n, len(sizes), big, BYVAL_LIMIT))
    return rc


def main():
    files = hc_files()
    if not files:
        print("FAIL cfs-structcopy — no .HC files found under Kernel; this gate would pass"
              " on an empty set, which is the shape it exists to refuse", file=sys.stderr)
        return 1

    sources = {p: strip_comments(open(p, errors="replace").read()) for p in files}
    # THE SCAN AND THE NAME TABLE ARE DIFFERENT SETS. Assignments are only looked for in .HC
    # files, because that is where code is; but the kernel declares its classes, its globals and
    # most of its constants in .HH headers, so the table that resolves a name has to read those
    # too. Leaving them out is why `table->body[i] = tmph->next` could not be resolved: CHash is
    # declared in KernelA.HH, and a type this gate has never heard of is a type it cannot rule
    # out.
    whole = "\n".join(strip_comments(open(p, errors="replace").read())
                      for p in hc_files((".HC", ".HH")))
    classes = set(CLASS_OPEN.findall(whole))
    if not classes:
        print("FAIL cfs-structcopy — not one class was found, so nothing could be flagged",
              file=sys.stderr)
        return 1
    members = class_members(whole, classes)
    if not members:
        print("FAIL cfs-structcopy — not one class BODY was parsed, so every member access"
              " would go unresolved", file=sys.stderr)
        return 1

    # Globals are visible to every file, so the name table is built once over the whole tree and
    # then extended per file with that file's own declarations and parameters.
    # THE LOOKUP IS THE FILE FIRST AND THE TREE ONLY AS A FALLBACK, and the one-line version
    # that searched the whole tree at once was wrong in a way worth recording: `m` is a
    # CMemUnused pointer in Kernel/Mem/MemPag.HC and a CCfsMsg by value somewhere else, so a
    # tree-wide candidate set reported MemPag's page-hash store as a class copy. One-letter
    # names collide across 320 files. A name declared in the file being scanned is resolved
    # there and nowhere else; the tree is consulted only for names the file never declares,
    # which is how a global reaches its reader.
    tree_names = {}
    collect(whole, tree_names)
    constants = {}
    for name in set(DEFINE.findall(whole)) | BUILTIN:
        constants.setdefault(name, set()).add(("<not a variable>", 0))

    rc = check_byval_params(classes)
    checked = 0
    decl_checked = 0
    decl_small = 0
    unresolved = []
    for p in files:
        rel = os.path.relpath(p, ROOT)
        src = sources[p]
        declared = {}
        collect(src, declared)
        for name, cands in constants.items():
            declared.setdefault(name, cands)
        for name, cands in tree_names.items():
            declared.setdefault(name, cands)
        for stmt, lineno in statements(src):
            m = ASSIGN.match(stmt)
            if not m:
                continue
            checked += 1
            rhs = m.group(2)
            key = "%s:%d" % (rel, lineno)
            got = resolve(rhs, declared, members)
            if got is None:
                if key not in UNRESOLVED_OK:
                    unresolved.append((key, rhs, stmt))
                continue
            byval = sorted(t for t, ptr in got if ptr == 0 and t in classes)
            if not byval:
                continue
            ty = byval[0]
            if key in ALLOW:
                continue
            print("FAIL cfs-structcopy — %s copies a CLASS (%s) into an array slot or through"
                  % (key, ty), file=sys.stderr)
            print("  a bare pointer. That copies only the FIRST EIGHT BYTES, silently:"
                  " docs/HOLYC_STRUCT_LIMITS.md", file=sys.stderr)
            print("  #21, pinned by tests/exec/cases/e_struct_copy_into_slot.hc. Use MemCpy and"
                  " say why, as", file=sys.stderr)
            print("  cfe_es_perf.HC and cfe_es_appctrl.HC do -- or, if the class is 8 bytes or"
                  " less, add the", file=sys.stderr)
            print("  site to ALLOW with its size.", file=sys.stderr)
            print("    %s;" % stmt, file=sys.stderr)
            rc = 1

    drc, decl_checked, decl_small = check_decl_inits(files, sources, classes, members,
                                                     tree_names, constants)
    if drc:
        rc = drc

    # NOT-FOUND IS A FAILURE. The first version of this gate skipped these silently and that is
    # exactly how the appctrl copy survived it.
    if unresolved:
        print("FAIL cfs-structcopy — %d right-hand side(s) could not be resolved to a type, so"
              % len(unresolved), file=sys.stderr)
        print("  this gate cannot say whether they are class copies. Each is an indexed or"
              " dereferenced", file=sys.stderr)
        print("  assignment, which is the dangerous destination form. Resolve the declaration"
              " or, if the", file=sys.stderr)
        print("  name genuinely is not a class by value, add it to UNRESOLVED_OK with the"
              " reason:", file=sys.stderr)
        for key, rhs, stmt in unresolved[:20]:
            print("    %s  rhs=%s  in  %s;" % (key, rhs, stmt), file=sys.stderr)
        rc = 1

    # A stale exemption is a failure, the same rule the other gates apply.
    for name, table in (("ALLOW", ALLOW), ("UNRESOLVED_OK", UNRESOLVED_OK)):
        for key in sorted(table):
            f = key.rsplit(":", 1)[0]
            if not os.path.exists(os.path.join(ROOT, f)):
                print("FAIL cfs-structcopy — %s names %s, whose file does not exist"
                      % (name, key), file=sys.stderr)
                rc = 1

    if rc == 0:
        print("cfs-structcopy: %d indexed or dereferenced assignments across %d files, every"
              " right-hand side resolved to a type, none of them a class by value (%d class"
              " declarations read, %d exempt)"
              % (checked, len(files), len(members), len(ALLOW) + len(UNRESOLVED_OK)))
        print("cfs-declinit: %d class local(s) declared with an initialiser; %d are 8 bytes or"
              " less and so copied WHOLE, none is larger (limit #27, %d exempt by site)"
              % (decl_checked, decl_small, len(DECL_INIT_ALLOW)))
    return rc


if __name__ == "__main__":
    sys.exit(main())
