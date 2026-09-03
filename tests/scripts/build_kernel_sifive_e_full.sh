#!/bin/bash
# Build FE310 / sifive_e fuller tiny-Kernel (dual artifact vs slim plat.elf).
# Output: build/kernels/sifive_e/kernel-fe310.elf
#
# Layout (product model):
#   XIP @ 0x20400000 — reset trampoline + Kernel (oracle + HolyC blob)
#   DTIM @ 0x80000000 — bootloader (.boot), .data, .bss, stack
# Import slots host-prepatched (XIP is ROM). No DRAM beyond 16 KiB DTIM.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOS="$ROOT/templeos-riscv"
HARNESS="$ROOT/tests/exec/harness"
OUT_BASE="$ROOT/build/kernels"
EXEC_DIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_fe310_full.hc"
PATCH="$SCRIPT_DIR/patch_fe310_xip_imports.py"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"

for t in "$GCC" "$OBJCOPY" "$LD"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL build fe310-full — missing $t" >&2; exit 1; }
done
[ -f "$COMPILER" ] || [ -x "$COMPILER" ] || make -C "$ROOT" holyc-riscv >/dev/null

KDIR="$OUT_BASE/sifive_e"
mkdir -p "$KDIR" "$EXEC_DIR"

LOCKDIR="$ROOT/build/.kernel-plat.lock"
mkdir -p "$ROOT/build"
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  sleep 0.1
done
cleanup_lock() { rmdir "$LOCKDIR" 2>/dev/null || true; }
trap cleanup_lock EXIT

SAVE_CFG="$(mktemp)"
SAVE_HAD_CFG=0
if [ -f "$TOS/.config" ]; then
  cp "$TOS/.config" "$SAVE_CFG"
  SAVE_HAD_CFG=1
fi

restore_cfg() {
  if [ "$SAVE_HAD_CFG" -eq 1 ]; then
    cp "$SAVE_CFG" "$TOS/.config"
    make -C "$TOS" syncconfig >/dev/null
  else
    make -C "$TOS" defconfig-virt >/dev/null
  fi
  rm -f "$SAVE_CFG"
  cleanup_lock
}
trap restore_cfg EXIT

make -C "$TOS" defconfig-sifive_e >/dev/null

MARCH=rv64imafdc
MABI=lp64d
if [ -f "$TOS/include/generated/kconfig.mk" ]; then
  # shellcheck disable=SC1090
  . "$TOS/include/generated/kconfig.mk"
fi
MARCH="${MARCH:-rv64imafdc}"
MABI="${MABI:-lp64d}"

T="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$T'; restore_cfg" EXIT

ORACLE_SRC="$HARNESS/oracle_out_fe310.c"
ORACLE_OBJ="$EXEC_DIR/oracle_out_fe310.o"
CRT_SRC="$HARNESS/crt0_sifive_e_boot.S"
CRT_OBJ="$EXEC_DIR/crt0_sifive_e_boot.o"
LINK_LD="$HARNESS/link_sifive_e_full.ld"

"$GCC" -march="$MARCH" -mabi="$MABI" -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
  -DUART_BASE=0x10013000UL -c "$ORACLE_SRC" -o "$ORACLE_OBJ" \
  || { echo "FAIL build fe310-full — oracle compile" >&2; exit 1; }
"$GCC" -march="$MARCH" -mabi="$MABI" -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
  -c "$CRT_SRC" -o "$CRT_OBJ" \
  || { echo "FAIL build fe310-full — crt0 boot compile" >&2; exit 1; }

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL build fe310-full — HolyC compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -30 >&2
  exit 1
fi

BLOB_SZ=$(wc -c <"$T/blob.bin" | tr -d ' ')

( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$LINK_LD" -nostdlib --no-warn-mismatch -o kernel-fe310.elf \
    "$CRT_OBJ" "$ORACLE_OBJ" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL build fe310-full — link error" >&2; exit 1; }

chmod +x "$PATCH"
python3 "$PATCH" "$T/kernel-fe310.elf" \
  || { echo "FAIL build fe310-full — XIP import patch" >&2; exit 1; }

# Sanity: blob must be in XIP VMA, not DTIM.
BLOB_VMA=$(riscv64-unknown-elf-objdump -h "$T/kernel-fe310.elf" | awk '/\.user_blob/{print $4; exit}')
BLOB_VMA_DEC=$((16#$BLOB_VMA))
if [ "$BLOB_VMA_DEC" -lt $((0x20400000)) ] || [ "$BLOB_VMA_DEC" -ge $((0x80000000)) ]; then
  echo "FAIL build fe310-full — .user_blob VMA 0x$BLOB_VMA not in XIP" >&2
  exit 1
fi

cp "$T/kernel-fe310.elf" "$KDIR/kernel-fe310.elf"
cp "$T/kernel-fe310.elf" "$EXEC_DIR/kernel-fe310.elf"
cp "$T/blob.bin" "$KDIR/kernel-fe310.blob.bin"

{
  echo "machine=sifive_e"
  echo "artifact=kernel-fe310.elf"
  echo "role=Kernel_FE310.PRJ XIP + DTIM bootloader (UART+CLINT+PLIC+SiFive+MemMap)"
  echo "blob_bytes=$BLOB_SZ"
  echo "blob_vma=0x$BLOB_VMA"
  echo "dtim_bytes=16384"
  echo "layout=XIP kernel + DTIM bootloader/data/bss/stack"
  echo "imports=host-prepatched (patch_fe310_xip_imports.py)"
  echo "link=$LINK_LD"
  echo "note=plat.elf remains slim XIP matrix path; RV32 HolyC emit later (after RV64 drivers)"
  date -u +'built=%Y-%m-%dT%H:%M:%SZ'
} >"$KDIR/KERNEL_FE310_INFO.txt"

echo "Built FE310 full: $KDIR/kernel-fe310.elf (blob=${BLOB_SZ} B @ XIP 0x$BLOB_VMA; bootloader in DTIM)"
