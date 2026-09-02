#!/bin/bash
# Build one HolyC plat-demo kernel for a Kconfig machine profile.
# Artifacts coexist under build/kernels/<machine>/ (and build/exec/<machine>_plat.elf).
#
# Usage: build_kernel_plat.sh <machine>
#   machine = virt | sifive_u | spike | … (see make list-kernels)
#
# Temporarily applies defconfig-<machine> (rewrites Kernel/RVAutoConf.HH + *Selected.HH),
# compiles tests/exec/cases/kernel_plat_demo.hc, snapshots config into the outdir,
# then restores the previous templeos-riscv/.config (or virt if none).
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOS="$ROOT/templeos-riscv"
HARNESS="$ROOT/tests/exec/harness"
OUT_BASE="$ROOT/build/kernels"
EXEC_DIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_plat_demo.hc"
MACHINE_IN="${1:-}"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"

if [ -z "$MACHINE_IN" ]; then
  echo "usage: $0 <machine>" >&2
  echo "  try: make list-kernels" >&2
  exit 2
fi

# Normalize aliases → defconfig stem (matches configs/*_defconfig).
case "$MACHINE_IN" in
  virt) DEFCONFIG=virt ;;
  sifive_u) DEFCONFIG=sifive_u ;;
  sifive_e) DEFCONFIG=sifive_e ;;
  spike) DEFCONFIG=spike ;;
  shakti_c) DEFCONFIG=shakti_c ;;
  microchip_icicle|microchip-icicle-kit) DEFCONFIG=microchip_icicle ;;
  xiangshan|xiangshan-kunminghu) DEFCONFIG=xiangshan ;;
  amd_microblaze_v|amd-microblaze-v-generic) DEFCONFIG=amd_microblaze_v ;;
  opentitan)
    echo "SKIP build kernel (opentitan) — RV32 / 128 KiB profile; use rv32 toolchain later (RV32.md)" >&2
    exit 0 ;;
  none)
    echo "SKIP build kernel (none) — empty machine; no CPU/RAM" >&2
    exit 0 ;;
  host)
    echo "SKIP build kernel (host) — legacy stub; not a QEMU -M" >&2
    exit 0 ;;
  *)
    if [ -f "$TOS/configs/${MACHINE_IN}_defconfig" ]; then
      DEFCONFIG="$MACHINE_IN"
    else
      echo "error: unknown machine '$MACHINE_IN' (no configs/${MACHINE_IN}_defconfig)" >&2
      exit 2
    fi ;;
esac

for t in "$GCC" "$OBJCOPY" "$LD"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP build kernel — missing $t" >&2; exit 0; }
done
[ -f "$COMPILER" ] || [ -x "$COMPILER" ] || make -C "$ROOT" holyc-riscv >/dev/null

KDIR="$OUT_BASE/$DEFCONFIG"
mkdir -p "$KDIR" "$EXEC_DIR"

# Serialize against concurrent plat builds / smokes stomping global headers.
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

make -C "$TOS" "defconfig-$DEFCONFIG" >/dev/null

# Shared harness objects (machine-independent).
if [ ! -f "$EXEC_DIR/crt0.o" ] || [ ! -f "$EXEC_DIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$EXEC_DIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$EXEC_DIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$EXEC_DIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$EXEC_DIR/oracle_out.o" || { echo "FAIL build kernel — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$EXEC_DIR/crt0.o" || { echo "FAIL build kernel — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$T'; restore_cfg" EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL build kernel — HolyC compile error ($DEFCONFIG)" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o plat.elf \
    "$EXEC_DIR/crt0.o" "$EXEC_DIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL build kernel — link error ($DEFCONFIG)" >&2; exit 1; }

cp "$T/plat.elf" "$KDIR/plat.elf"
cp "$T/plat.elf" "$EXEC_DIR/${DEFCONFIG}_plat.elf"
# Compat with earlier plat-$MACHINE.elf naming from smoke scripts.
cp "$T/plat.elf" "$EXEC_DIR/plat-$DEFCONFIG.elf"

# Optional firmware ROM image (Kconfig OUTPUT_FORMAT_FIRMWARE).
OUTPUT_FMT=elf
if [ -f "$TOS/include/generated/kconfig.mk" ]; then
  # shellcheck disable=SC1090
  . "$TOS/include/generated/kconfig.mk"
fi
if [ "${OUTPUT_FORMAT:-elf}" = firmware ]; then
  FW_MK="$ROOT/bootstrap/Makefile.firmware"
  FW_OUT="$ROOT/build/firmware"
  make -C "$ROOT/bootstrap" -f Makefile.firmware \
    PAYLOAD_ELF="$KDIR/plat.elf" \
    FLASH_BASE="${FLASH_BASE:-0x20000000}" \
    RAM_BASE="${RAM_BASE:-0x80000000}" \
    PFLASH_SIZE="${PFLASH_SIZE:-0x02000000}" \
    firmware >/dev/null
  cp "$FW_OUT/templeos-fw.bin" "$KDIR/plat.bin"
  cp "$FW_OUT/templeos-fw.elf" "$KDIR/plat-fw.elf"
  OUTPUT_FMT=firmware
  echo "Built firmware ($DEFCONFIG): $KDIR/plat.bin (flash @ ${FLASH_BASE:-0x20000000})"
fi

# Snapshot Kconfig + generated HolyC headers so flipping .config does not lose this board.
cp "$TOS/.config" "$KDIR/.config"
cp "$ROOT/Kernel/RVAutoConf.HH" "$KDIR/RVAutoConf.HH"
mkdir -p "$KDIR/DrvSelected"
for f in RVUartSelected.HH RVPlicSelected.HH RVSifiveSelected.HH RVVirtioSelected.HH RVFbSelected.HH; do
  [ -f "$ROOT/Kernel/Drv/$f" ] && cp "$ROOT/Kernel/Drv/$f" "$KDIR/DrvSelected/$f"
done
python3 "$TOS/scripts/kconfig.py" qemu-args >"$KDIR/qemu-args.txt" 2>"$KDIR/qemu-system.txt" || true
{
  echo "machine=$DEFCONFIG"
  echo "elf=$KDIR/plat.elf"
  echo "output_format=$OUTPUT_FMT"
  if [ "$OUTPUT_FMT" = firmware ]; then
    echo "firmware_bin=$KDIR/plat.bin"
    echo "firmware_elf=$KDIR/plat-fw.elf"
  fi
  echo "compat_elf=$EXEC_DIR/${DEFCONFIG}_plat.elf"
  date -u +'built=%Y-%m-%dT%H:%M:%SZ'
} >"$KDIR/BUILD_INFO.txt"

if [ "$OUTPUT_FMT" = elf ]; then
  echo "Built kernel ($DEFCONFIG): $KDIR/plat.elf"
fi
