#!/usr/bin/env python3
"""Do configure_file's job for OSAL's osconfig.h, from NASA's own template and defaults.

In a real build CMake fills vendor/osal/osconfig.h.in from OSAL_CONFIG_* variables. The DEFAULTS
for every one of those live in vendor/osal/default_config.cmake, checked into NASA's tree, so the
generated header is derivable rather than invented -- which matters, because these numbers are
array bounds that the shared layer's object tables are sized by. A hand-picked value here would
silently change the id-to-index arithmetic the translation is supposed to reproduce.

The previous hand-written shim was missing OS_MAX_RWLOCKS and OS_MAX_FILE_SYSTEMS entirely and
had OS_MAX_FILE_SYS, a name OSAL no longer uses -- which is exactly the drift this replaces.

Boolean OSAL_CONFIG_* options (the `set(... ON/OFF)` ones) become #define/#undef, matching what
osconfig.h.in's #cmakedefine lines do.

    tools/cfs/gen_osconfig.py <outdir>
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OSAL = os.path.join(ROOT, "vendor", "osal")

def defaults():
    txt = open(os.path.join(OSAL, "default_config.cmake")).read()
    txt = re.sub(r'#[^\n]*', '', txt)
    vals = {}
    for m in re.finditer(r'set\(\s*(OSAL_CONFIG_[A-Z_0-9]+)\s+([^\s)]+)', txt):
        vals[m.group(1)] = m.group(2)
    return vals

def main(argv):
    # `--help` IS NOT AN OUTPUT DIRECTORY, and this check exists because it was treated as one:
    # a stray `--help/cfe_target_config.c` sat in the tree for two days, created by one run of
    # `gen_*.py --help` that took the flag as argv[0] and called os.makedirs on it. Four
    # generators had the same shape. A tool that silently does the wrong thing when ASKED FOR
    # HELP is the most reliable way to leave litter in someone's checkout.
    if len(argv) == 1 and argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    if len(argv) != 1:
        print(__doc__)
        return 2
    outdir = argv[0]
    os.makedirs(outdir, exist_ok=True)
    vals = defaults()
    tmpl = open(os.path.join(OSAL, "osconfig.h.in")).read()

    # @VAR@ substitution, as configure_file does
    # configure_file expands an UNSET variable to the empty string. Reproduced, but reported:
    # OSAL_CONFIG_SHELL_CMD_INPUT_FILE_NAME has no default anywhere in the OSAL tree, because a
    # mission supplies it and it is only read when OSAL_CONFIG_INCLUDE_SHELL is on (it is off by
    # default). Silently emitting "" is right; silently emitting "" without saying so is how a
    # missing mission setting turns into a mystery later.
    # Not every placeholder in osconfig.h.in is an OSAL_CONFIG_* one. CMake itself supplies some,
    # and an earlier version of this generator matched only @OSAL_CONFIG_*@ -- so
    # OS_MODULE_FILE_EXTENSION came out as the LITERAL STRING "@CMAKE_SHARED_LIBRARY_SUFFIX@" in
    # both generated headers. The differential oracle could never catch that, because both sides
    # carried the same wrong literal.
    #
    # CMAKE_SHARED_LIBRARY_SUFFIX is CMake's per-platform shared-library extension (".so",
    # ".dylib"). This port has no shared libraries: modules are TempleOS .BIN files, which is a
    # PORT DECISION and is why it is recorded here rather than guessed per platform.
    PORT = {"CMAKE_SHARED_LIBRARY_SUFFIX": ".BIN"}

    unset = []
    def sub(m):
        name = m.group(1)
        if name in PORT:
            return PORT[name]
        if name not in vals:
            unset.append(name)
            return ""
        return vals[name]
    out = re.sub(r'@(OSAL_CONFIG_[A-Z_0-9]+)@', sub, tmpl)
    out = re.sub(r'@([A-Z_][A-Z_0-9]*)@', sub, out)

    # Anything still wrapped in @...@ was never substituted, and a header with a live CMake
    # placeholder in it is wrong even when both sides agree about it. Fail loudly.
    leftover = sorted(set(re.findall(r'@([A-Za-z_][A-Za-z_0-9]*)@', out)))
    if leftover:
        print("FAIL gen_osconfig — placeholders left unsubstituted in osconfig.h: "
              + ", ".join(leftover), file=sys.stderr)
        return 1

    # #cmakedefine NAME  ->  #define NAME / /* #undef NAME */, keyed on the variable's truthiness
    def cmakedef(m):
        macro, var = m.group(1), m.group(2) or ("OSAL_CONFIG_" + m.group(1))
        v = vals.get(var, "OFF")
        on = str(v).upper() not in ("OFF", "FALSE", "0", "NO", "N", "IGNORE", "NOTFOUND", "")
        return f"#define {macro} 1" if on else f"/* #undef {macro} */"
    out = re.sub(r'#cmakedefine\s+([A-Z_0-9]+)(?:\s+@([A-Z_0-9]+)@)?', cmakedef, out)

    dst = os.path.join(outdir, "osconfig.h")
    open(dst, "w").write(out)

    # The HolyC half, from the same substituted text, so the two cannot disagree about a bound.
    # These numbers size the shared layer's object tables; if the C and the translation ever
    # differed on one, every id-to-index calculation downstream would differ with it and the
    # transcript would fail somewhere far from the cause.
    hc = ["// GENERATED by tools/cfs/gen_osconfig.py -- do not edit.",
          "//",
          "// The HolyC half of the osconfig.h that CMake generates from NASA's osconfig.h.in and",
          "// default_config.cmake. Emitted beside the C from the same substitution, because these",
          "// are the array bounds OSAL's object tables are sized by.",
          "#ifndef OSCONFIG_HC",
          "#define OSCONFIG_HC"]
    for m in re.finditer(r'^#define\s+(OS_[A-Z_0-9]+)\s+(.+?)\s*$', out, re.M):
        name, val = m.group(1), m.group(2).strip()
        if val.startswith('"'):
            hc.append(f'#define {name} {val}')
        else:
            hc.append(f'#define {name} {val}')
    hc.append("#endif")
    hcpath = os.path.join(ROOT, "Kernel", "Cfs", "osal", "osconfig.HC")
    open(hcpath, "w").write("\n".join(hc) + "\n")
    n = len(re.findall(r'^#define\s+OS_', out, re.M))
    print(f"osconfig: {n} settings -> {dst} and Kernel/Cfs/osal/osconfig.HC")
    for name in sorted(set(unset)):
        print(f"osconfig:   unset in NASA's defaults, expanded empty: {name}")
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
