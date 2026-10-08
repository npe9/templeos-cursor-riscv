#!/usr/bin/env python3
"""The oracle must not define a global that a gated NASA source also defines.

WHY THIS CANNOT BE LEFT TO THE LINKER. `CFE_TBL_Global_t CFE_TBL_Global;` with no initialiser
is a TENTATIVE DEFINITION in C. Two of them in two translation units MERGE, silently, with no
diagnostic -- so the oracle and NASA's own source can both "define" the object and the link
succeeds. Nothing tells you which one the exercise is reading.

HOW THE HOLE OPENS. A module's state lives in NASA's implementation file. Before that file is
gated, the C half of the differential oracle has to define the instance itself -- cfe_tbl_task.c
was not gated for a long time, so tests/cfs/oracle_ccsdspri.c carried CFE_TBL_Global with a
comment promising it would "go away the moment cfe_tbl_task.c is gated". That source IS gated
now, and the definition is still there. The comment was the only thing enforcing it, and a
comment is not a gate.

WHY IT MATTERS AND IS NOT COSMETIC. The two halves of this suite exist to compare NASA's C
against the translation. If the oracle defines a global NASA also defines, then the C half may
be reading a DIFFERENT OBJECT from the one NASA's gated code writes -- and worse, the oracle's
copy is declared with the ORACLE's idea of the type. The transcript would compare the
translation against a sizeof and a field layout that nothing checks against NASA, which is the
one thing this suite is built not to do.

It is about to happen a second time: MD_AppData sits in the oracle now because md_app.c is two
sources away from being gated.

WHAT COUNTS. A file-scope object definition that is not `static`, not `extern` and not a
function. A `static` one is private to the oracle and cannot merge with anything.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, "tests", "scripts")

# A driver, and the oracle it links. Read out of the driver rather than listed, so a new driver
# cannot be forgotten: ORACLE_C is the one file in SRC_C that is not under vendor/.
DRIVERS = ["run_cfs_xlat_smoke.sh", "run_osal_xlat_smoke.sh", "run_osal_printf_smoke.sh"]


def strip(src):
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    # string and char literals, so a brace or semicolon inside one cannot confuse the scan
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', src)
    return re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", src)


def depth_zero_lines(src):
    """Lines of `src` that start at brace depth 0 -- i.e. file scope."""
    out, depth = [], 0
    for line in src.split("\n"):
        if depth == 0:
            out.append(line)
        depth += line.count("{") - line.count("}")
        depth = max(0, depth)
    return out


OBJ = re.compile(
    r'^(?!\s)(?!static\b)(?!extern\b)(?!typedef\b)(?!return\b)'
    r'[A-Za-z_][A-Za-z0-9_]*(?:\s+[A-Za-z_][A-Za-z0-9_]*)*'   # the type words
    r'[\s\*]+([A-Za-z_]\w*)\s*(?:\[[^;]*\])?\s*(?:=[^;]*)?;\s*$')


def globals_of(path):
    """Non-static, non-extern file-scope OBJECT definitions in a C file."""
    try:
        src = strip(open(path, errors="replace").read())
    except OSError:
        return set()
    out = set()
    for line in depth_zero_lines(src):
        if "(" in line.split("=")[0]:
            continue                      # a function declaration or a function pointer
        m = OBJ.match(line)
        if m:
            out.add(m.group(1))
    return out


def main():
    bad, checked, oracles = [], 0, []
    for d in DRIVERS:
        p = os.path.join(SCRIPTS, d)
        if not os.path.exists(p):
            continue
        txt = open(p, errors="replace").read()
        srcs = []
        for m in re.finditer(r'SRC_C="(.*?)"', txt, re.S):
            srcs += [t for t in m.group(1).split() if t.endswith(".c")]
        # Resolve the shell variables the driver uses for its roots BY READING THE DRIVER'S OWN
        # ASSIGNMENTS, not from a list here.
        #
        # THIS USED TO BE A HARD-CODED DICT OF SIX AND IT WAS THE GATE'S BLIND SPOT. It held
        # $CFE, $OSAL, $PSP, $MD, $SHIM and $ROOT. When MM was gated the driver grew $MM, then
        # $CS, then $LC -- and a token like "$LC/fsw/src/lc_app.c" that no substitution touched
        # stayed non-absolute, failed the os.path.isabs test below, and was DROPPED. The gate
        # then reported a cheerful count and a pass. 27 of the cFS driver's 116 sources -- every
        # MM, CS and LC file, three whole applications -- were never compared against the oracle
        # at all. Nothing said so, because a gate that cannot FIND its subject passes.
        #
        # So the roots come from the script, and any token still carrying a `$` after
        # substitution is a HARD FAILURE below rather than a silent skip. A new application's
        # root is now picked up the moment the driver declares it.
        sub = {"$ROOT": ROOT}
        for name, val in re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)="([^"\n]*)"', txt, re.M):
            if "$(" in val or "${" in val:
                continue              # a command substitution or a default -- not a path root
            sub["$" + name] = val
        # The assignments reference each other ($CFE="$ROOT/vendor/cFE"), so expand to a fixed
        # point. Ten passes is far more than the two levels the drivers actually use.
        for _ in range(10):
            for k in list(sub):
                for k2, v2 in sub.items():
                    if k2 != k and k2 in sub[k]:
                        sub[k] = sub[k].replace(k2, v2)
        # Only NASA's own sources. SRC_C does not name the oracle -- the driver passes it to
        # the host compiler separately -- but filter anyway, because intersecting the oracle
        # with ITSELF would report every one of its globals as a conflict and this gate would
        # then be impossible to read.
        nasa, oracle = [], None
        for t in srcs:
            raw = t
            # longest variable name first, so $CS cannot be matched inside $CSOMETHING
            for k in sorted(sub, key=len, reverse=True):
                t = t.replace(k, sub[k])
            if "$" in t:
                print("FAIL check-oracle-globals — %s names a source this gate cannot resolve:"
                      % d, file=sys.stderr)
                print("    %s" % raw, file=sys.stderr)
                print("  The driver uses a shell variable whose assignment this gate could not"
                      " read, so", file=sys.stderr)
                print("  the path is not absolute and WOULD HAVE BEEN SILENTLY SKIPPED. That is"
                      " exactly", file=sys.stderr)
                print("  how three applications went unchecked. Fix the resolution, not this"
                      " message.", file=sys.stderr)
                return 1
            if os.sep + "vendor" + os.sep in t:
                nasa.append(t)
            else:
                # Not under vendor/ and not a $ left over: a generated or shim source. Those are
                # not NASA's, so they are not compared -- but say so rather than dropping it.
                pass
        # the oracle is named separately in the driver
        # The oracle is the one .c the driver compiles from tests/ rather than from vendor/ --
        # it is the argument to the host compile, not a member of SRC_C. Derived rather than
        # listed so a new driver cannot be added without this gate seeing its oracle.
        cand = re.findall(r'"\$ROOT/(tests/[A-Za-z0-9_/]+\.c)"', txt)
        cand = [c for c in cand if "/harness/" not in c]
        oracle = os.path.join(ROOT, cand[0]) if cand else None
        if not oracle or not os.path.exists(oracle):
            print("FAIL check-oracle-globals — could not find the oracle .c linked by %s. This"
                  % d, file=sys.stderr)
            print("  gate cannot pass by not finding its subject.", file=sys.stderr)
            return 1
        oracles.append(os.path.relpath(oracle, ROOT))
        og = globals_of(oracle)
        for f in nasa:
            if not os.path.exists(f):
                continue
            checked += 1
            for name in sorted(og & globals_of(f)):
                bad.append((os.path.relpath(oracle, ROOT), os.path.basename(f), name))
    if bad:
        print("FAIL check-oracle-globals — the oracle defines a global that a GATED NASA source",
              file=sys.stderr)
        print("  also defines. Two tentative definitions MERGE silently in C, so the link", file=sys.stderr)
        print("  succeeds and nothing says which object the exercise is reading. Delete the", file=sys.stderr)
        print("  oracle's copy: NASA's source owns it now.", file=sys.stderr)
        for o, f, n in bad:
            print("    %s defines %s, and so does %s" % (o, n, f), file=sys.stderr)
        return 1
    print("check-oracle-globals: %d gated NASA sources define no global that %s also defines"
          % (checked, " or ".join(sorted(set(oracles)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
