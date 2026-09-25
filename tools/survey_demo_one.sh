#!/bin/bash
# survey_demo_one.sh <Demo/.../X.HC> — one row of the demo survey (docs/DEMO_SURVEY.md).
#
# L1 = the file compiles against the RV kernel, links into a real image, boots it, initialises
# graphics and survives. That is the level above "it compiles", and it only became measurable
# once the 141 unguarded autoruns were wrapped in #ifndef RV_NO_DEMO_AUTORUN — before that,
# including one of these files RAN it at load and any fault was blamed on the harness.
#
# Regenerate the whole survey:
#   find Demo -name '*.HC' | sort | xargs -P 4 -n 1 tools/survey_demo_one.sh > /tmp/survey.tsv
#
# Columns: <file> <L0-FAIL|LINK-FAIL|L1-TRAP|L1-HANG|L1-OK> [mcause]
R=/Users/npe/src/templeos-cursor-riscv
SP="${SURVEY_TMP:-$(mktemp -d)}"
f="$1"; n=$(echo "$f" | sed 's|/|_|g; s|\.HC$||')
mkdir -p "$SP"; c="$SP/$n.hc"; l="$SP/$n.log"; T=$(mktemp -d)
cat > "$c" <<HC
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/$f"
I64 main()
{
  CTask *adam = 0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400; heap_end = 0x86000000;
  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0); adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;
  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
  RVKernelInit();
  RVGrInit(640, 480);
  Fs->win_left = 0; Fs->win_right = 79; Fs->win_top = 0; Fs->win_bottom = 59;
  WinDerivedValsUpdate(Fs);
  Print("L1-LOADED\n");
  return 0;
}
HC
if ! HOLYC_NO_TIER2=1 HOLYC_INCLUDE_ROOT="$R" "$R/holyc-riscv" "$c" -o "$T/blob.bin" >"$l" 2>&1; then
  printf '%s\tL0-FAIL\n' "$f"; rm -rf "$T"; exit 0
fi
( cd "$T" && riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  riscv64-unknown-elf-ld -T "$R/tests/exec/harness/link_exec.ld" -nostdlib --no-warn-mismatch \
  -o k.elf "$R/build/exec/crt0.o" "$R/build/exec/oracle_out.o" blob_in.o ) >>"$l" 2>&1 || {
  printf '%s\tLINK-FAIL\n' "$f"; rm -rf "$T"; exit 0; }
out=$(timeout 25 qemu-system-riscv64 -M virt -m 128M -bios none -kernel "$T/k.elf" -nographic </dev/null 2>&1 | LC_ALL=C tr -d '\r')
rm -rf "$T"
if   printf '%s' "$out" | LC_ALL=C grep -aq "L1-LOADED"; then printf '%s\tL1-OK\n' "$f"
elif printf '%s' "$out" | LC_ALL=C grep -aq "TRAP";      then printf '%s\tL1-TRAP\t%s\n' "$f" "$(printf '%s' "$out" | LC_ALL=C grep -ao 'mcause=[^ ]* ([a-z-]*)' | head -1)"
else printf '%s\tL1-HANG\n' "$f"; fi
