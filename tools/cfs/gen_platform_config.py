#!/usr/bin/env python3
"""CFE_Config_SetupPlatformConfigInfo -- generated, the way cFE's own build generates it.

WHY THIS EXISTS. cfe_config_init.c calls CFE_Config_SetupPlatformConfigInfo(), which is
declared in modules/config/fsw/inc/cfe_config_external.h and DEFINED NOWHERE IN THE TREE. It is
emitted per target during the build, and that is why the `config` module stopped at 61% once
get/set/lookup were translated: the remaining 275 lines were blocked on build-system output, not
on translation effort.

HOW. Not by writing a generator from scratch. cFE ships the generator -- a native C tool at
modules/config/tool/ that is compiled for the BUILD host, not the target, and run during the
build:

    cfeconfig_platformdata_tool initcode  <sysvar>   ->  the array CONTENTS
    cfeconfig_platformdata_tool entrylist <sysvar>   ->  the CFE_PLATFORMCFG_ENTRY lines

and modules/config/cmake/cfe_platform_cfg.c.in is the template the two get substituted into.
This script compiles NASA's tool with the host compiler, runs both subcommands, and fills
NASA's own template. So the C half is not a reimplementation of cFE's build: it IS cFE's build,
driven by something other than CMake.

The HolyC half cannot be. Those arrays are lists of CFE_PLATFORM_* macro names, and HolyC has
no cfe_platform_cfg.h to expand them from -- so a second probe, compiled against NASA's headers,
prints the RESOLVED INTEGERS and the HolyC is emitted with literals. One source of truth, two
outputs, same discipline as tools/cfs/gen_target_config.py: if the two sides could disagree
about a block size, the transcript would find out somewhere far away from the cause.

In this configuration the tool emits THREE entries, not five. CFE_PLATFORM_TBL_VALID_SCID and
_PRID have a count of 0 and the tool skips an empty list, which is faithful and is the kind of
thing a hand-written generator would have got wrong in the direction of emitting two empty
arrays.

    tools/cfs/gen_platform_config.py <outdir>
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CFE = os.path.join(ROOT, "vendor", "cFE")
TOOL = os.path.join(CFE, "modules", "config", "tool")

# The one target system this port builds. The name reaches the generated C only as a symbol
# suffix, but it has to be a valid C identifier and it has to match between the list file and
# the -D that names the table.
SYSVAR = "templeos_rv"

INC = ["-I" + p for p in [
    TOOL,
    os.path.join(ROOT, "build", "cfs"),
    os.path.join(ROOT, "vendor", "shim"),
    os.path.join(CFE, "modules", "core_private", "config"),
    os.path.join(CFE, "modules", "core_private", "fsw", "inc"),
    os.path.join(CFE, "modules", "config", "fsw", "inc"),
    os.path.join(CFE, "modules", "core_api", "fsw", "inc"),
    os.path.join(CFE, "modules", "core_api", "config"),
    os.path.join(CFE, "modules", "resourceid", "fsw", "inc"),
    os.path.join(CFE, "modules", "resourceid", "config"),
    os.path.join(CFE, "modules", "resourceid", "option_inc"),
    os.path.join(ROOT, "vendor", "osal", "src", "os", "inc"),
]
  + [os.path.join(CFE, "modules", m, "config") for m in
     ("es", "sb", "evs", "tbl", "time", "ta", "fs", "msg")]
  + [os.path.join(CFE, "modules", m, "fsw", "inc") for m in
     ("es", "sb", "evs", "tbl", "time", "ta", "fs", "msg")]]

# `static const <type> CFE_CONFIG_<NAME>_CONTENT[<n>] = {` in the tool's initcode output
ARRAY = re.compile(r'static\s+const\s+(\w+)\s+CFE_CONFIG_(\w+)_CONTENT\[(\d+)\]\s*=\s*\{(.*?)\};',
                   re.S)
ENTRY = re.compile(r'CFE_PLATFORMCFG_ENTRY\((\w+)\)')


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode:
        sys.stderr.write(" ".join(cmd[:3]) + " ...\n" + r.stderr[:3000])
        raise SystemExit("gen_platform_config: command failed")
    return r.stdout


def build_tool(out):
    """Compile NASA's cfeconfig_platformdata_tool for the host and return its path."""
    listc = os.path.join(out, "cfe_platform_list.c")
    tpl = open(os.path.join(TOOL, "cmake", "cfe_platform_list.c.in")).read()
    open(listc, "w").write(tpl.replace("@SYM_PREFIX@", "CFECONFIG_PLATFORMDATA")
                              .replace("@PLATFORM_OBJ_NAMES@", "CFE_PLATFORM(%s)" % SYSVAR))
    exe = os.path.join(out, "cfeconfig_platformdata_tool")
    cc = os.environ.get("HOSTCC", "cc")
    run([cc, "-O0", "-w"] + INC +
        ["-DMAP_ENTRY_LIST=CFECONFIG_PLATFORMDATA_" + SYSVAR, "-o", exe,
         os.path.join(TOOL, "cfeconfig_platformdata_tool.c"),
         os.path.join(TOOL, "cfeconfig_platformdata_table.c"),
         listc,
         os.path.join(ROOT, "build", "cfs", "cfe_configid_nametable.c")])
    return exe


def resolve_values(out, initcode, arrays):
    """The arrays hold CFE_PLATFORM_* macro NAMES. Compile a probe against NASA's headers and
    print the integers, because HolyC has no cfe_platform_cfg.h to expand them from."""
    src = os.path.join(out, "platcfg_values_probe.c")
    body = ["#include <stdio.h>", "#include <common_types.h>", "#include <cfe_platform_cfg.h>",
            initcode, "int main(void){"]
    for ty, name, n, _ in arrays:
        body.append('  printf("%%s", "%s");' % name)
        body.append('  for (size_t i = 0; i < %s; ++i) printf(" %%llu", '
                    '(unsigned long long)CFE_CONFIG_%s_CONTENT[i]);' % (n, name))
        body.append('  printf("\\n");')
    body.append("  return 0; }")
    open(src, "w").write("\n".join(body) + "\n")
    exe = src[:-2]
    cc = os.environ.get("HOSTCC", "cc")
    run([cc, "-O0", "-w"] + INC + ["-o", exe, src])
    vals = {}
    for line in run([exe]).strip().split("\n"):
        p = line.split()
        vals[p[0]] = [int(x) for x in p[1:]]
    return vals


def emit_holyc(path, arrays, entries, vals):
    L = []
    L.append("// GENERATED by tools/cfs/gen_platform_config.py -- do not edit.")
    L.append("//")
    L.append("// The HolyC half of CFE_Config_SetupPlatformConfigInfo, which cFE's build emits")
    L.append("// per target and which exists in no source tree. The C half the oracle links is")
    L.append("// produced by NASA's OWN generator (modules/config/tool, compiled for the host)")
    L.append("// filling NASA's own template; this half carries the same values as integers,")
    L.append("// because the C arrays are lists of CFE_PLATFORM_* macro names and HolyC has no")
    L.append("// cfe_platform_cfg.h to expand them from. See the generator for why.")
    L.append("//")
    L.append("// Three arrays, not five: CFE_PLATFORM_TBL_VALID_SCID and _PRID have a count of 0")
    L.append("// in this configuration and NASA's tool skips an empty list.")
    L.append("#ifndef CFE_PLATFORMCFG_TABLES_HC")
    L.append("#define CFE_PLATFORMCFG_TABLES_HC")
    L.append("")
    for ty, name, n, _ in arrays:
        hc = "I64" if ty in ("size_t", "uint64_t", "unsigned long") else "U32"
        L.append("%s CFE_CONFIG_%s_CONTENT[%s];" % (hc, name, n))
    L.append("")
    L.append("// HolyC has no initialised aggregates at file scope, so the contents are written")
    L.append("// by a function the harness calls once -- the same shape cfe_target_config.HC has.")
    L.append("U0 CFE_PlatformConfigTablesInit()")
    L.append("{")
    for ty, name, n, _ in arrays:
        v = vals[name]
        for i, x in enumerate(v):
            L.append("  CFE_CONFIG_%s_CONTENT[%d] = %d;" % (name, i, x))
    L.append("}")
    L.append("")
    # ONE DESCRIPTOR PER ENTRY, AT FILE SCOPE. NASA's template declares each as
    #     static const CFE_Config_ArrayValue_t ARR_##x = { ARRAY_LEN(x), ARRAY_NAME(x) };
    # and `static` is load-bearing: CFE_Config_SetArrayValue stores the POINTER to this object
    # and copies nothing. A single reused local was tried here first, and all three ids ended up
    # pointing at the same dead stack slot -- the transcript read NumElements as 2156050768.
    L.append("// One descriptor per entry, at FILE SCOPE, because CFE_Config_SetArrayValue")
    L.append("// retains the pointer and copies nothing -- NASA's template declares each of")
    L.append("// these `static const` for exactly that reason.")
    for ty, name, n, _ in arrays:
        L.append("CFE_Config_ArrayValue CFE_CONFIG_ARR_%s;" % name)
    L.append("")
    L.append("U0 CFE_Config_SetupPlatformConfigInfo()")
    L.append("{")
    # the translated class has no _t (HolyC has no typedef, so the class IS the name), and
    # CFE_CONFIGID_FROM_OFFSET's expansion is exactly what CFE_Config_OffsetToId computes --
    # CFE_ResourceId_FromInteger(CFE_CONFIGID_BASE + offset), both sides.
    for e in entries:
        name = e
        n = dict((a[1], a[2]) for a in arrays).get(name)
        if n is None:
            continue
        L.append("  CFE_CONFIG_ARR_%s.NumElements = %s;" % (name, n))
        L.append("  CFE_CONFIG_ARR_%s.ElementPtr = CFE_CONFIG_%s_CONTENT;" % (name, name))
        L.append("  CFE_Config_SetArrayValue(CFE_Config_OffsetToId(CFE_ConfigIdOffset_%s), "
                 "&CFE_CONFIG_ARR_%s);" % (name, name))
    L.append("}")
    L.append("#endif")
    open(path, "w").write("\n".join(L) + "\n")


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
        print(__doc__.strip().split("\n")[-1], file=sys.stderr)
        return 2
    out = argv[0]
    os.makedirs(out, exist_ok=True)
    exe = build_tool(out)
    initcode = run([exe, "initcode", SYSVAR])
    entrylist = run([exe, "entrylist", SYSVAR])

    arrays = ARRAY.findall(initcode)
    entries = ENTRY.findall(entrylist)
    if not arrays or not entries:
        print("FAIL gen_platform_config — NASA's tool produced no arrays or no entries",
              file=sys.stderr)
        return 1
    # The two outputs have to agree about WHICH entries exist, or the generated C would
    # reference an array the initcode never declared.
    names = {a[1] for a in arrays}
    for e in entries:
        if e not in names:
            print("FAIL gen_platform_config — entrylist names %s, initcode does not declare it"
                  % e, file=sys.stderr)
            return 1

    # the C half: NASA's template, NASA's generated content
    tpl = open(os.path.join(CFE, "modules", "config", "cmake", "cfe_platform_cfg.c.in")).read()
    cpath = os.path.join(out, "cfe_platformcfg_tables.c")
    open(cpath, "w").write(tpl.replace("@PLATCFG_CONTENT@", initcode)
                              .replace("@PLATCFG_LIST@", entrylist))

    vals = resolve_values(out, initcode, arrays)
    hpath = os.path.join(ROOT, "Kernel", "Cfs", "cfe", "cfe_platformcfg_tables.HC")
    emit_holyc(hpath, arrays, entries, vals)

    print("gen_platform_config: %d arrays, %d entries -> %s and %s"
          % (len(arrays), len(entries), os.path.relpath(cpath, ROOT),
             os.path.relpath(hpath, ROOT)))
    for ty, name, n, _ in arrays:
        print("    %-34s %s[%s]  first=%d last=%d"
              % (name, ty, n, vals[name][0], vals[name][-1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
