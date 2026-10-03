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
LV = r'[A-Za-z_]\w*(?:(?:\.|->)[A-Za-z_]\w*)*'
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
DECL_MORE = re.compile(r',\s*(\**)\s*([A-Za-z_]\w*)\s*(?=[;,)\[=])')
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


def strip_comments(text):
    """Comments out, LINE NUMBERS INTACT.

    A block comment is replaced by its own newlines rather than by a space. Collapsing one
    moved every statement after it: the perf capture store, which is at cfe_es_perf.HC:735,
    was reported at 571 by a version of this that did not do this -- a correct finding with a
    line number pointing at an unrelated function, which is worse than no line number.
    """
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'/\*.*?\*/', lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


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


def declarators(src):
    """(name, type, pointer depth) for every declaration or parameter in `src`.

    ONE WALKER FOR BOTH THE NAME TABLE AND THE CLASS BODIES, because they drifted: the bodies
    were read with the plain pattern alone, so `I64 clus,size;` in CDirEntry contributed `clus`
    and not `size`, and `U0 (*Address)();` in OS_static_symbol_record_t contributed nothing --
    and both showed up as right-hand sides this gate could not resolve.
    """
    for m in DECL.finditer(src):
        yield m.group(3), m.group(1), len(m.group(2))
        pos = m.end()
        while True:
            mm = DECL_MORE.match(src, pos)
            if not mm:
                break
            yield mm.group(2), m.group(1), len(mm.group(1))
            pos = mm.end()
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
    parts = re.split(r'\.|->', expr)
    cands = declared.get(parts[0])
    if not cands:
        return None
    for p in parts[1:]:
        nxt = set()
        for ty, _ in cands:
            if ty in members and p in members[ty]:
                nxt.add(members[ty][p])
        if not nxt:
            return None
        cands = nxt
    return cands


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

    rc = 0
    checked = 0
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
    return rc


if __name__ == "__main__":
    sys.exit(main())
