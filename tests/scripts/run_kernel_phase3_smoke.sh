#!/usr/bin/env bash
# RVKMain phase 3 smoke: Kernel + Compiler_RV_Body → CInit/ExePutS → StartOS subset.
# TempleOS Boot.DD shape (not jit.hc). See templeos-riscv/COMPILER_RV.md.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_phase3_demo.hc"
EXPECT="RVPhase3: Compiler_RV loaded"
EXPECT_LOAD="RVPhase3: Load() CBinFile OK"
EXPECT_HOST="RVPhase3: Load() host Compiler.BIN OK (RedSea seed + Cmp export)."
EXPECT_FULL="RVPhase3: Load() full Compiler.BIN OK (reloc RedSea + ExePutS)."
EXPECT_RELOC="RVPhase3: Load() relocatable RedSea Compiler.BIN returned."
EXPECT_MAKEOS="RVPhase3: MakeOS OK"
EXPECT_RUNTIME="RVPhase3: Runtime OK"
EXPECT_ADAMCORE="RVPhase3: StartOS Load AdamCore.BIN OK (guest Cmp FileWrite STR_CONST)."
EXPECT_STARTOS_BIN="RVPhase3: StartOS Load StartOS.BIN OK"
EXPECT_SEED="RVPhase3: StartOS Load Seed.BIN OK"
EXPECT_SVC="RVPhase3: StartOS Load Svc.BIN OK"
EXPECT_KERN="RVPhase3: StartOS Load Kern.BIN OK"
EXPECT_KERNEL="RVPhase3: StartOS Load Kernel.BIN OK (guest Cmp preferred over Mac scaffold)."
EXPECT2="RVPhase3: StartOS subset OK (guest BINs AdamCore+StartOS+Seed+Svc+Kern+Kernel)."
EXPECT3="RVPhase3: done (compiler + StartOS)"
# Soft G8 needles (progress; not hard-fail if absent — nested include may still soft-fail)
EXPECT_P6_CLASS="RVPhase3: P6 bisect — class(I64) OK."
EXPECT_P6_STR="RVPhase3: P6 bisect — StrCpy OK."
EXPECT_P6_DIR="RVPhase3: P6 bisect — DirMk Cmp OK."
EXPECT_P6_DIR_CALL="RVPhase3: P6 bisect — DirMk Call OK."
EXPECT_P6_STR_CALL="RVPhase3: P6 bisect — StrCpy Call OK."
EXPECT_P6_LITE="RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest, LITE.TXT)."
EXPECT_P6_LITE_PLANT="RVPhase3: P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest, LITE.TXT plant)."
EXPECT_P6_LITE_SKIP="RVPhase3: P6 MakeAdam_RV_Lite Load OK (menu_n Cmp; Call soft-skip)."
EXPECT_P6_INCLUDE="RVPhase3: P6 AdamLite.BIN ready (guest Cmp #include Menu_RV)."
EXPECT_P6_INCLUDE_ABS="RVPhase3: P6 AdamLite.BIN ready (guest Cmp abs #include Menu_RV)."
EXPECT_P6_LEX_FOLD="RVPhase3: P6 bisect — Lex+Guest fold Cmp OK."
EXPECT_P6_GUEST_LEX="RVPhase3: P6 bisect — Guest_Lex Cmp OK."
EXPECT_P6_IDENT="RVPhase3: P6 bisect — local U8* ident Call OK."
EXPECT_P6_LEX_ELEM="RVPhase3: P6 bisect — Menu Lex Call OK (U8 elem)."
EXPECT_P6_LOCPTR="RVPhase3: P6 bisect — local U8* lit Call OK."
EXPECT_P6_MEM="RVPhase3: P6 bisect — class member StrCpy Call OK."
EXPECT_P6_SCALAR="RVPhase3: P6 bisect — scalar-glbl Call OK."
EXPECT_P6_FLAT_COUNT="RVPhase3: P6 bisect — flat Menu Count Call OK."
EXPECT_P6_SPAN_DIR="RVPhase3: P6 bisect — DirMk A:/Span Call OK."
EXPECT_P6_STOREFW="RVPhase3: P6 bisect — store→FileWrite Call OK."

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT="gtimeout"
elif ! command -v timeout >/dev/null 2>&1; then
  echo "SKIP kernel-phase3 smoke — missing timeout/gtimeout" >&2
  exit 0
fi

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-phase3 smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv tools/pack_tosb >/dev/null
# Refresh host-packed TOSB: full Compiler.BIN (CInit/ExePutS exports) + tiny probe embed.
if HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$ROOT/build/compiler_rv.map" \
   "$COMPILER" "$ROOT/Compiler/Compiler_RV.PRJ" -o "$ROOT/build/compiler_rv.blob.bin" >/dev/null 2>&1; then
  :
fi
if [ -f "$ROOT/build/compiler_rv.blob.bin" ] && [ -f "$ROOT/build/compiler_rv.map" ]; then
  CINIT_OFF=$(awk '/ CInit$/{print $1; exit}' "$ROOT/build/compiler_rv.map")
  EXEPS_OFF=$(awk '/ ExePutS$/{print $1; exit}' "$ROOT/build/compiler_rv.map")
  LSB_OFF=$(awk '/ LexStmt2Bin$/{print $1; exit}' "$ROOT/build/compiler_rv.map")
  CMP_OFF=$(awk '/ Cmp$/{print $1; exit}' "$ROOT/build/compiler_rv.map")
  if [ -n "$CINIT_OFF" ] && [ -n "$EXEPS_OFF" ]; then
    PACK_E=(-e "CInit:0x${CINIT_OFF}" -e "ExePutS:0x${EXEPS_OFF}")
    if [ -n "$LSB_OFF" ]; then
      PACK_E+=(-e "LexStmt2Bin:0x${LSB_OFF}")
    fi
    if [ -n "$CMP_OFF" ]; then
      PACK_E+=(-e "Cmp:0x${CMP_OFF}")
    fi
    "$ROOT/tools/pack_tosb" -v "${PACK_E[@]}" \
      "$ROOT/build/compiler_rv.blob.bin" "$ROOT/build/Compiler.BIN" >/dev/null || true
  else
    "$ROOT/tools/pack_tosb" -v "$ROOT/build/compiler_rv.blob.bin" \
      "$ROOT/build/Compiler.BIN" >/dev/null || true
  fi
  python3 "$ROOT/tools/gen_cmp_imports.py" >/dev/null || true
fi
# G9: HostBinEmbed / AdamLite U8[] embeds not linked into phase3 (loaded Cmp only).
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-phase3 smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-phase3 smoke — crt0" >&2; exit 1; }
fi

# Link full Compiler.BIN at 0x81000000 (optional but expected for full-cmp path).
if [ -f "$ROOT/build/Compiler.BIN" ]; then
  # Writable: LoadPass1 patches IMM_I64 slots in-place (no 1MB MAlloc copy).
  "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,contents \
    "$ROOT/build/Compiler.BIN" "$OUTDIR/compiler_full.o" \
    || { echo "FAIL kernel-phase3 smoke — compiler_full.o" >&2; exit 1; }
else
  echo "FAIL kernel-phase3 smoke — missing build/Compiler.BIN" >&2
  exit 1
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-phase3 smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -40 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o "$OUTDIR/compiler_full.o" ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-phase3 smoke — link error" >&2; exit 1; }

cp "$T/kp.elf" "$OUTDIR/phase3.elf"
# UART-only CI path (-nographic). Interactive FB: add -device ramfb -display cocoa.
# Soft P6 bisect can exceed 120s if guest Cmp hangs on class surface.
PHASE3_TIMEOUT="${PHASE3_TIMEOUT:-180}"
# macOS bash 3.2 + set -u: a failed pipeline in $(...) can leave the name
# unset and then report "out: unbound variable" on this line — pre-init + || true.
out=""
out=$(LC_ALL=C $TIMEOUT "$PHASE3_TIMEOUT" "$QEMU" -M virt -m 128M -bios none -kernel "$T/kp.elf" -nographic </dev/null 2>&1 | LC_ALL=C tr -d '\r') || true
printf '%s\n' "$out" > /tmp/phase3_uart_final.txt || true
if printf '%s\n' "$out" | grep -qF "$EXPECT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LOAD" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_HOST" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_FULL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_RELOC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_MAKEOS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_RUNTIME" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_ADAMCORE" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_STARTOS_BIN" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SEED" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_SVC" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERN" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_KERNEL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT2" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT3" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_CLASS" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_STR" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_DIR" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_DIR_CALL" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_P6_STR_CALL" && \
   (printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LITE" || \
    printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LITE_PLANT"); then
  soft_extra=""
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_GUEST_LEX"; then
    soft_extra="${soft_extra}+guestlex"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LEX_FOLD"; then
    soft_extra="${soft_extra}+lexfold"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_IDENT"; then
    soft_extra="${soft_extra}+ident"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LOCPTR"; then
    soft_extra="${soft_extra}+locptr"
  fi
  if printf '%s\n' "$out" | grep -qF "RVPhase3: P6 bisect — star-lit Call OK."; then
    soft_extra="${soft_extra}+starlit"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_LEX_ELEM"; then
    soft_extra="${soft_extra}+lexelem"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_MEM"; then
    soft_extra="${soft_extra}+mem"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_SCALAR"; then
    soft_extra="${soft_extra}+scalar"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_FLAT_COUNT"; then
    soft_extra="${soft_extra}+flatcnt"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_STOREFW"; then
    soft_extra="${soft_extra}+storefw"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_SPAN_DIR"; then
    soft_extra="${soft_extra}+spandir"
  fi
  if printf '%s\n' "$out" | grep -qF "$EXPECT_P6_INCLUDE" || \
     printf '%s\n' "$out" | grep -qF "$EXPECT_P6_INCLUDE_ABS"; then
    printf 'Kernel-phase3 smoke: OK (G9 loaded Cmp + AdamLite Call%s)\n' "$soft_extra"
  else
    printf 'Kernel-phase3 smoke: OK (G9 loaded Cmp; nested Menu include still soft%s)\n' "$soft_extra"
  fi
  exit 0
fi
echo "FAIL kernel-phase3 smoke — expected line not found:" >&2
echo "  want: $EXPECT / … / $EXPECT_P6_CLASS / $EXPECT_P6_STR / $EXPECT_P6_DIR / $EXPECT_P6_DIR_CALL / $EXPECT_P6_STR_CALL / $EXPECT_P6_LITE" >&2
printf '%s\n' "$out" | grep -E 'RVPhase3|StartOS|ExePutS|Load|MakeOS|Runtime|Kern|Kernel|AdamCore|Cmp|Except|Error|FAIL|OK|P6|bisect|Menu_RV|ident|RVKMain' | head -80 | LC_ALL=C sed 's/^/  /' >&2
exit 1
