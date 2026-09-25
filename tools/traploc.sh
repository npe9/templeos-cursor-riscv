#!/bin/bash
# traploc.sh <case.hc> — run one exec case and NAME the function its TRAP landed in.
#
# The harness prints `blob+0x<off>` on a fault; HOLYC_MAP maps blob offsets to symbols. Without
# this the offset is unattributable and a fault gets blamed on whatever was nearby in the source.
# Used to turn docs/DEMO_SURVEY.md's L1-TRAP list from seven mcause numbers into seven functions.
#
#   tools/traploc.sh /tmp/tos-demo-survey/Demo_DateTime.hc
#   Demo_DateTime  mcause=3 breakpoint  mtval=0x...  blob+0x3a354  UndefinedDefine+0xa8
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
W="${TRAPLOC_WAIT:-25}"
c="$1"; n=$(basename "$c" .hc)
T=$(mktemp -d); M=$T/map
HOLYC_NO_TIER2=1 HOLYC_MAP=$M HOLYC_INCLUDE_ROOT=$R $R/holyc-riscv "$c" -o $T/blob.bin >/dev/null 2>&1 \
  || { echo "$n	COMPILE-FAIL"; rm -rf $T; exit 0; }
(cd $T && riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv blob.bin blob_in.o && \
 riscv64-unknown-elf-ld -T $R/tests/exec/harness/link_exec.ld -nostdlib --no-warn-mismatch \
 -o k.elf $R/build/exec/crt0.o $R/build/exec/oracle_out.o blob_in.o) >/dev/null 2>&1 \
  || { echo "$n	LINK-FAIL"; rm -rf $T; exit 0; }
out=$(timeout "$W" qemu-system-riscv64 -M virt -m 128M -bios none -kernel $T/k.elf -nographic \
      </dev/null 2>&1 | LC_ALL=C tr -d '\r')
line=$(printf '%s' "$out" | LC_ALL=C grep -a '^TRAP mcause' | head -1)
if [ -z "$line" ]; then echo "$n	NO-TRAP"; rm -rf $T; exit 0; fi
off=$(printf '%s' "$line" | sed -n 's/.*blob+0x0*\([0-9a-f]*\).*/\1/p')
cause=$(printf '%s' "$line" | sed -n 's/.*mcause=0x0*\([0-9a-f]*\) (\([a-z-]*\)).*/\1 \2/p')
mtval=$(printf '%s' "$line" | sed -n 's/.*mtval=\(0x[0-9a-f]*\).*/\1/p')
# The map is unsorted, so take the greatest symbol address at or below the fault offset.
fn=$(python3 -c '
import sys
o=int(sys.argv[1],16); best=(-1,"?")
for l in open(sys.argv[2],errors="replace"):
    f=l.split()
    if len(f)<2: continue
    try: a=int(f[0],16)
    except ValueError: continue
    if a<=o and a>best[0]: best=(a,f[1])
print("%s+0x%x"%(best[1],o-best[0]))' "$off" "$M")
printf '%s\tmcause=%s\tmtval=%s\tblob+0x%s\t%s\n' "$n" "$cause" "$mtval" "$off" "$fn"
rm -rf $T
