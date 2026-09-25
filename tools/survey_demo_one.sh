#!/bin/bash
# survey_demo_one.sh <Demo/.../X.HC> — one row of the demo survey (docs/DEMO_SURVEY.md).
#
# L1 = the file compiles against the RV kernel, links into a real image, boots it, runs its own
# top-level code and reaches the end. That is the level above "it compiles".
#
# Two things had to be true before this could measure anything:
#
#  1. The 141 unguarded trailing autoruns needed #ifndef RV_NO_DEMO_AUTORUN. Before that,
#     including one of these files RAN it at load and the fault was blamed on the harness.
#  2. The kernel has to be booted BEFORE the demo is included. A demo's top-level statements
#     execute at load and plenty of them print; PutS derefs Fs, so booting inside main() made
#     18 of 32 demos fault in PutS before main ran. That was the harness, not the port.
#
# Regenerate the whole survey:
#   find Demo -name '*.HC' | sort | xargs -P 4 -n 1 tools/survey_demo_one.sh > /tmp/survey.tsv
#
# Columns: <file> <L0-FAIL|LINK-FAIL|L1-TRAP|L1-HANG|L1-OK> [mcause]
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
SP="${SURVEY_TMP:-/tmp/tos-demo-survey}"
W="${SURVEY_WAIT:-25}"
f="$1"
n=$(echo "$f" | sed 's|/|_|g; s|\.HC$||')
mkdir -p "$SP"
c="$SP/$n.hc"; l="$SP/$n.log"; T=$(mktemp -d)

{
  echo '#include "/Kernel/Kernel_RV.PRJ"'
  echo 'U0 SurveyBoot()'
  echo '{'
  echo '  CTask *adam = 0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;'
  echo '  MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;'
  echo '  MemSet(the_heap, 0, sizeof(CHeapCtrl));'
  echo '  heap_next = 0x82000400; heap_end = 0x86000000;'
  echo '  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;'
  echo '  ah = HeapCtrlInit(NULL, NULL, bp);'
  echo '  adam->code_heap = ah; adam->data_heap = ah;'
  echo '  MemSet(SYS_FIXED_AREA, 0, 8192);'
  echo '  TaskInit(adam, 0); adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;'
  echo '  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;'
  echo '  RVYieldInit(&Fs);'
  echo '  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);'
  echo '  RVKernelInit();'
  echo '  RVGrInit(640, 480);'
  echo '  Fs->win_left = 0; Fs->win_right = 79; Fs->win_top = 0; Fs->win_bottom = 59;'
  echo '  WinDerivedValsUpdate(Fs);'
  echo '}'
  echo '// Boot BEFORE the include — the demo`s top-level code runs at load and may print.'
  echo 'SurveyBoot;'
  echo '#define RV_NO_DEMO_AUTORUN'
  echo "#include \"/$f\""
  echo 'I64 main() { Print("L1-LOADED\n"); return 0; }'
} > "$c"

if ! HOLYC_NO_TIER2=1 HOLYC_INCLUDE_ROOT="$R" "$R/holyc-riscv" "$c" -o "$T/blob.bin" >"$l" 2>&1; then
  printf '%s\tL0-FAIL\n' "$f"; rm -rf "$T"; exit 0
fi
( cd "$T" && riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  riscv64-unknown-elf-ld -T "$R/tests/exec/harness/link_exec.ld" -nostdlib --no-warn-mismatch \
  -o k.elf "$R/build/exec/crt0.o" "$R/build/exec/oracle_out.o" blob_in.o ) >>"$l" 2>&1 || {
  printf '%s\tLINK-FAIL\n' "$f"; rm -rf "$T"; exit 0; }

out=$(timeout "$W" qemu-system-riscv64 -M virt -m 128M -bios none -kernel "$T/k.elf" \
      -nographic </dev/null 2>&1 | LC_ALL=C tr -d '\r')
rm -rf "$T"

if printf '%s' "$out" | LC_ALL=C grep -aq "L1-LOADED"; then
  printf '%s\tL1-OK\n' "$f"
elif printf '%s' "$out" | LC_ALL=C grep -aq "TRAP"; then
  printf '%s\tL1-TRAP\t%s\n' "$f" \
    "$(printf '%s' "$out" | LC_ALL=C grep -ao 'mcause=[^ ]* ([a-z-]*)' | head -1)"
else
  printf '%s\tL1-HANG\n' "$f"
fi
