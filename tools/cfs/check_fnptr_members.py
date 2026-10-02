#!/usr/bin/env python3
"""A function-pointer class MEMBER must have NASA's return kind and parameter count.

WHY THIS EXISTS, and it is a hole three other gates each had a good reason not to cover:

  - check_structs.py  compares field NAMES and ORDER, and says so: not types.
  - check_padding.py  compares OFFSETS and SIZES -- and a function pointer is eight bytes
                      whatever it points at, so it cannot see this either.
  - check_signatures.py compares function PARAMETERS, not the types of class members.

So `CFE_TIME_SynchCallbackRegEntry_t.Ptr` was declared `U0 (*Ptr)()` for three commits while
NASA's typedef is `int32 (*)(void)` -- the 1Hz callback RETURNS a status, which
CFE_TIME_NotifyTimeSynchApps discards. Every gate was green. What refused it in the end was the
host C compiler, on the ORACLE's side, the first time a driver assigned a real callback to the
member; a port that never drove TIME would still have it wrong.

WHAT IS COMPARED, and what is not. The RETURN KIND -- `U0` against `void`, anything else against
anything else -- and the PARAMETER COUNT. Not the parameter types: the two languages spell them
differently and check_signatures already owns that comparison for functions. An empty HolyC
parameter list `(*f)()` is reported as UNDECLARED rather than as zero, because this port writes
both forms and `()` against NASA's `(void)` is a different claim from `()` against `(uint32)`.

    tools/cfs/check_fnptr_members.py
"""
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

_spec = importlib.util.spec_from_file_location(
    "check_structs", os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_structs.py"))
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)

# `<ret> (*Name)(<params>);` as a class member, in either language. The return run may carry
# qualifiers and stars; cFE writes `volatile CFE_TIME_SynchCallbackPtr_t Ptr` for the typedef
# form, which the TYPEDEF pass below resolves instead.
MEMBER_FN = re.compile(r'^\s*((?:const\s+|volatile\s+|unsigned\s+|signed\s+)*'
                       r'[A-Za-z_]\w*(?:\s*\*+)?)\s*\(\s*\*+\s*([A-Za-z_]\w*)\s*\)'
                       r'\s*\(([^;]*)\)\s*;', re.M)
# `<type> Name;` where <type> is a typedef that is itself a function pointer.
MEMBER_PLAIN = re.compile(r'^\s*(?:const\s+|volatile\s+)*([A-Za-z_]\w*)\s+\**\s*'
                          r'([A-Za-z_]\w*)\s*;', re.M)
# `typedef <ret> (*Name)(<params>);` -- AND A QUALIFIER MAY SIT BETWEEN THE STAR AND THE NAME.
# cfe_es_crc.h writes
#     typedef uint32 (*const CFE_ES_ComputeCRC_Algo_t)(const void *, size_t, uint32);
# a CONST function pointer, and without `(?:const\s+|volatile\s+)*` after the stars this regex
# captured `const` as the typedef's NAME -- so CFE_ES_ComputeCRC_Params_t.Algorithm came back
# with no NASA counterpart, and it registered a bogus typedef called "const" on the way past.
# That is the THIRD time this one file has had a regex that could not read a spelling NASA
# actually uses, which is why unpaired is a failure here: each gap was found by the gate
# refusing rather than by anyone noticing.
TYPEDEF_FN = re.compile(r'typedef\s+((?:const\s+|unsigned\s+|signed\s+)*[A-Za-z_]\w*'
                        r'(?:\s*\*+)?)\s*\(\s*\*+\s*(?:const\s+|volatile\s+)*'
                        r'([A-Za-z_]\w*)\s*\)\s*\(([^;]*)\)\s*;')
# ...and `typedef <ret>((*Name)(<params>));`, which is how OSAL writes two of them:
#     typedef osal_task((*osal_task_entry)(void));
# The first version of this file matched only the form above, so the two members of
# OS_task_internal_record_t that use it came back as HAVING NO NASA COUNTERPART -- and that was
# reported as a note on a PASSING run. A checker that cannot find the upstream thing has a third
# outcome besides match and mismatch, and it is the one that looks like success. Unpaired members
# are a FAILURE now, which is what turned this regex gap into something visible.
TYPEDEF_FN2 = re.compile(r'typedef\s+((?:const\s+|unsigned\s+|signed\s+)*[A-Za-z_]\w*'
                         r'(?:\s*\*+)?)\s*\(\s*\(\s*\*+\s*(?:const\s+|volatile\s+)*'
                         r'([A-Za-z_]\w*)\s*\)'
                         r'\s*\(([^;]*)\)\s*\)\s*;')


def arity(params):
    """Parameter count. An empty list is ZERO, which is what it means in HolyC.

    This is NOT C's rule, where `(*f)()` is an unspecified list rather than an empty one. HolyC
    has no such form -- `(*external_sync)(U32)` in os_shared_time.HC is how a parameter is
    written -- so `()` is a claim of no parameters and is compared as one. Reading it as
    "declares nothing" would have excused the one real mismatch in the tree.
    """
    p = params.strip()
    if p in ("", "void", "U0"):
        return 0
    depth, n, cur = 0, 0, ""
    for ch in p:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            n += 1
            cur = ""
        else:
            cur += ch
    return n + 1


# `typedef void <Name>;` -- a name that IS void. OSAL has one, and it is in the return position
# of the two members above: `typedef void osal_task;` then
# `typedef osal_task((*osal_task_entry)(void));`. Without resolving it, NASA's return reads as
# "a value" and the translation's correct `U0` looks like the mismatch -- a checker reporting the
# translation for its own blind spot, which is worse than not checking.
VOID_ALIAS = re.compile(r'typedef\s+void\s+([A-Za-z_]\w*)\s*;')
_void_names = {"void", "U0"}


def is_void(ret):
    return re.sub(r'\b(const|volatile|unsigned|signed)\b', '', ret).strip() in _void_names


def nasa_fn_typedefs():
    out = {}
    for d in cs.NASA_DIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not (fn.endswith(".h") or fn.endswith(".c")):
                continue
            txt = cs.strip_comments(open(os.path.join(d, fn), errors="replace").read())
            for m in VOID_ALIAS.finditer(txt):
                _void_names.add(m.group(1))
            for pat in (TYPEDEF_FN, TYPEDEF_FN2):
                for m in pat.finditer(txt):
                    out.setdefault(m.group(2), (m.group(1), m.group(3)))
    return out


def struct_bodies(dirs, exts, pattern_list):
    """{name: (body, file)} for every struct/class declaration under dirs."""
    out = {}
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not any(fn.endswith(e) for e in exts):
                continue
            txt = cs.strip_comments(open(os.path.join(d, fn), errors="replace").read())
            for pat, gname, gbody in pattern_list:
                for m in re.finditer(pat, txt, re.S):
                    out.setdefault(m.group(gname), (m.group(gbody), fn))
    return out


def fn_members(body, typedefs):
    """{name: (is_void, arity_or_None, how)} for the function-pointer members of one body."""
    out = {}
    for m in MEMBER_FN.finditer(body):
        out[m.group(2)] = (is_void(m.group(1)), arity(m.group(3)), "inline")
    for m in MEMBER_PLAIN.finditer(body):
        td = typedefs.get(m.group(1))
        if td and m.group(2) not in out:
            out[m.group(2)] = (is_void(td[0]), arity(td[1]), "typedef " + m.group(1))
    return out


def main():
    nasa = struct_bodies(cs.NASA_DIRS, (".h", ".c"), [
        (r'typedef\s+(?:const\s+)?struct\s*(?:\w+\s*)?\{(?P<body>.*?)\}\s*(?P<name>\w+)\s*;',
         "name", "body"),
        (r'\bstruct\s+(?P<name>\w+)\s*\{(?P<body>.*?)\}\s*;', "name", "body"),
    ])
    hc = struct_bodies(cs.HCDIRS, (".HC",), [
        (r'\bclass\s+(?P<name>\w+)\s*\{(?P<body>.*?)\}\s*;', "name", "body"),
    ])
    tds = nasa_fn_typedefs()

    bad, checked, unpaired = [], 0, []
    for cname, (cbody, cfile) in sorted(hc.items()):
        if cname not in nasa:
            continue
        nbody, nfile = nasa[cname]
        hmem = fn_members(cbody, {})
        nmem = fn_members(nbody, tds)
        for name, (hvoid, harity, _how) in sorted(hmem.items()):
            if name not in nmem:
                unpaired.append("%s.%s: the translation declares a function pointer and no "
                                "member of that name in NASA's %s resolves to one -- either the "
                                "name is wrong or this tool cannot read NASA's spelling" % (
                                    cname, name, nfile))
                continue
            nvoid, narity, nhow = nmem[name]
            checked += 1
            if hvoid != nvoid:
                bad.append("%s.%s: NASA returns %s (%s), translation returns %s" % (
                    cname, name, "void" if nvoid else "a value", nhow,
                    "U0" if hvoid else "a value"))
            elif harity != narity:
                bad.append("%s.%s: NASA takes %d parameter(s) (%s), translation takes %d" % (
                    cname, name, narity, nhow, harity))

    if unpaired:
        print("FAIL cfs-fnptr — a function-pointer member has no NASA counterpart to compare.",
              file=sys.stderr)
        print("  Not finding the upstream declaration is NOT a pass. It was a note on a green",
              file=sys.stderr)
        print("  run until the two OSAL members written as typedef osal_task((*f)(void)) showed",
              file=sys.stderr)
        print("  what that note was hiding.", file=sys.stderr)
        for u in unpaired:
            print("    " + u, file=sys.stderr)
        return 1

    if bad:
        print("FAIL cfs-fnptr — a function-pointer class member does not match NASA's.",
              file=sys.stderr)
        print("  check_structs compares names, check_padding compares bytes, and a function",
              file=sys.stderr)
        print("  pointer is eight bytes whatever it points at -- so only this looks here.",
              file=sys.stderr)
        for b in bad:
            print("    " + b, file=sys.stderr)
        return 1

    print("cfs-fnptr: %d function-pointer class member(s) match NASA's return kind and "
          "parameter count" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
