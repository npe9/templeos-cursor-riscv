#!/bin/bash
# HomeSet / Cd("~") needle — no RedSeaFmt (Fmt ClusAlloc hang is separate WIP).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_home_demo.hc"
EXPECT_SOFT_DIR='SoftCd DirCur ok dir=::/Apps/Span'
EXPECT_SOFT_A='SoftCd DirCur A: ok dir=::/Home'
EXPECT_SOFT_DNA='Soft DirNameAbs A: ok dir=::/Home'
EXPECT_SOFT_LET='Soft Let2Drv A: ok drv='
EXPECT_SOFT_DNA2='Soft DirNameAbs post-plant ok dir=::/Home'
EXPECT_SOFT_P='Soft Let2Drv P: ok drv='
EXPECT_SOFT_P_CD='SoftCd DirCur P: ok dir=::/Host'
EXPECT_SOFT_P_DNA='Soft DirNameAbs P: ok dir=::/Host'
EXPECT_CD='RVHomeBringUp Cd(~) ok dir='
EXPECT_SOFT='RVHomeBringUp SoftCd null stay-put ok'

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-home smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-home smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-home smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-home smoke — compile" >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o home.elf \
  "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || {
  echo "FAIL kernel-home smoke — link" >&2
  exit 1
}

out="$($TIMEOUT 20 "$QEMU" -M virt -bios none -kernel "$T/home.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_DIR"; then
  echo "FAIL kernel-home smoke — SoftCd DirCur ::/ honesty:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -FiE 'SoftCd|DirCur|FAIL' | head -10 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_A"; then
  echo "FAIL kernel-home smoke — SoftCd DirCur A:→::/ honesty:" >&2
  printf '%s\n' "$out" | grep -Fi SoftCd | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_DNA"; then
  echo "FAIL kernel-home smoke — Soft DirNameAbs A:→::/ honesty:" >&2
  printf '%s\n' "$out" | grep -FiE 'DirNameAbs|Soft|FAIL' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_LET"; then
  echo "FAIL kernel-home smoke — Soft Let2Drv A: plant honesty:" >&2
  printf '%s\n' "$out" | grep -FiE 'Let2Drv|SoftLet|Soft|FAIL' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_DNA2"; then
  echo "FAIL kernel-home smoke — Soft DirNameAbs post-plant ::/ honesty:" >&2
  printf '%s\n' "$out" | grep -FiE 'DirNameAbs|Soft|FAIL' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_P"; then
  echo "FAIL kernel-home smoke — Soft Let2Drv P: plant honesty:" >&2
  printf '%s\n' "$out" | grep -FiE 'Let2Drv|SoftLet|P:|FAIL' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_P_CD"; then
  echo "FAIL kernel-home smoke — SoftCd DirCur P:→::/ honesty:" >&2
  printf '%s\n' "$out" | grep -Fi SoftCd | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT_P_DNA"; then
  echo "FAIL kernel-home smoke — Soft DirNameAbs P:→::/ honesty:" >&2
  printf '%s\n' "$out" | grep -FiE 'DirNameAbs|Soft|FAIL' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVHomeBringUp Cd\(~\) ok dir=A:/Home home=A:/Home'; then
  echo "FAIL kernel-home smoke — Cd(~) needle:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -FiE 'Home|Cd|FAIL|SoftCd' | head -10 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SOFT"; then
  echo "FAIL kernel-home smoke — SoftCd null stay-put:" >&2
  printf '%s\n' "$out" | grep -Fi SoftCd | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
echo "Kernel-home smoke: OK ($EXPECT_SOFT_DIR / $EXPECT_SOFT_LET / $EXPECT_SOFT_P / $EXPECT_CD / $EXPECT_SOFT)"
exit 0
