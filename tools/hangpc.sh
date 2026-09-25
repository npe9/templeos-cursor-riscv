#!/bin/bash
# hangpc.sh <Demo/X.HC> — sample the PC of a silent hang and name the function it is spinning in.
#
# tools/traploc.sh does this for a TRAP. A hang never traps, so the PC has to be SAMPLED: run under
# QMP, ask `info registers` three times a few seconds apart, and map each pc/ra through HOLYC_MAP.
# It is what turned two "silent L1-HANG, no top-level code at all" demos into answers:
#
#   Demo/Games/TheDead.HC       spinning in RVSnd/RVSndPcmFill, ra in JobsHndlr — playing its song
#                               from an unguarded autorun hidden behind a DolDoc binary tail
#   Demo/Lectures/FixedPoint.HC Main+0x16c, ra=Main+0x120 — its own for(i=1000000000;i;i--)
#
# QMP rather than gdb because `continue &` + `interrupt` in a gdb batch script silently samples
# nothing. The markers around the include say WHERE to look; this says what it is doing there.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
f="$1"; n=$(echo "$f" | sed 's|/|_|g; s|\.HC$||')
T=$(mktemp -d); M=$T/map
{
  echo '#include "/Kernel/Kernel_RV.PRJ"'
  bash -c "cd $R && sed -n \"s/^  echo '\(.*\)'\$/\1/p\" tools/survey_demo_one.sh" \
    | sed "s/\`/'/g" | sed '/^#include/d; /^#define RV_NO_DEMO_AUTORUN/d'
  echo 'Print("M1 booted\n");'
  echo '#define RV_NO_DEMO_AUTORUN'
  echo "#include \"/$f\""
  echo 'Print("M2 include done\n");'
  echo 'I64 main() { Print("M3 main\n"); return 0; }'
} > $T/probe.hc
HOLYC_NO_TIER2=1 HOLYC_MAP=$M HOLYC_INCLUDE_ROOT=$R $R/holyc-riscv $T/probe.hc -o $T/blob.bin >/dev/null 2>&1 \
  || { echo "$f COMPILE-FAIL"; rm -rf $T; exit 0; }
(cd $T && riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv blob.bin blob_in.o && \
 riscv64-unknown-elf-ld -T $R/tests/exec/harness/link_exec.ld -nostdlib --no-warn-mismatch \
 -o k.elf $R/build/exec/crt0.o $R/build/exec/oracle_out.o blob_in.o) >/dev/null 2>&1 \
 || { echo "$f LINK-FAIL"; rm -rf $T; exit 0; }
# QMP is steadier than gdb batch here: `info registers` three times, a few seconds apart.
qemu-system-riscv64 -M virt -m 128M -bios none -kernel $T/k.elf -nographic \
  -qmp unix:$T/qmp.sock,server,nowait >$T/q.log 2>&1 &
QP=$!
python3 - "$T" <<'QQ' > $T/pcs.txt
import json, os, socket, sys, time
T = sys.argv[1]
for _ in range(100):
    if os.path.exists(T + "/qmp.sock"): break
    time.sleep(0.1)
s = socket.socket(socket.AF_UNIX); s.settimeout(20); s.connect(T + "/qmp.sock")
f = s.makefile("rwb")
f.readline()                                   # greeting
f.write(b'{"execute":"qmp_capabilities"}\n'); f.flush(); f.readline()
for i in range(3):
    time.sleep(4)
    f.write(json.dumps({"execute": "human-monitor-command",
                        "arguments": {"command-line": "info registers"}}).encode() + b"\n")
    f.flush()
    r = json.loads(f.readline().decode())
    txt = r.get("return", "")
    pc = ra = 0
    for tok in txt.replace("=", " ").split():
        pass
    import re
    m = re.search(r"pc\s+([0-9a-fx]+)", txt)
    if m: pc = int(m.group(1), 16)
    m = re.search(r"\bra\s+([0-9a-fx]+)", txt)
    if m: ra = int(m.group(1), 16)
    print("SAMPLE %#x %#x" % (pc, ra))
QQ
kill $QP 2>/dev/null; wait $QP 2>/dev/null
python3 - "$M" "$T/pcs.txt" "$f" <<'PY'
import sys
m=[]
for l in open(sys.argv[1],errors="replace"):
    p=l.split()
    if len(p)>=2:
        try: m.append((int(p[0],16),p[1]))
        except ValueError: pass
m.sort()
def name(addr):
    off=addr-0x80800000               # .user_blob base, tests/exec/harness/link_exec.ld
    if off<0: return "outside the blob (harness/crt0)"
    best=(-1,"?")
    for a,nm in m:
        if a<=off and a>best[0]: best=(a,nm)
    return "%s+0x%x" % (best[1], off-best[0])
print("=====", sys.argv[3])
for l in open(sys.argv[2]):
    f=l.split()
    if len(f)<3: continue
    pc,ra=int(f[1],16),int(f[2],16)
    print("  pc=%#x %-34s ra=%#x %s" % (pc, name(pc), ra, name(ra)))
PY
rm -rf $T
