#!/bin/bash
# Build one HolyC plat-demo kernel for a Kconfig machine profile.
# Artifacts coexist under build/kernels/<machine>/ (and build/exec/<machine>_plat.elf).
#
# Usage: build_kernel_plat.sh <machine>
#   machine = virt | sifive_u | spike | … (see make list-kernels)
#
# Temporarily applies defconfig-<machine> (rewrites Kernel/RVAutoConf.HH + *Selected.HH),
# compiles tests/exec/cases/kernel_plat_demo.hc (or RV32 asm for opentitan),
# snapshots config into the outdir, then restores the previous templeos-riscv/.config.
#
# Policy: no SKIP=OK. Unknown / non-board targets fail. Missing toolchain fails.
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
  opentitan) DEFCONFIG=opentitan ;;
  visionfive2|visionfive-2|jh7110) DEFCONFIG=visionfive2 ;;
  milkv_mars|milkv-mars|mars) DEFCONFIG=milkv_mars ;;
  hifive_unmatched|hifive-unmatched|unmatched|fu740) DEFCONFIG=hifive_unmatched ;;
  none|host)
    echo "FAIL build kernel ($MACHINE_IN) — not a TempleOS/RV board target (excluded from plat matrix)" >&2
    exit 1 ;;
  *)
    if [ -f "$TOS/configs/${MACHINE_IN}_defconfig" ]; then
      DEFCONFIG="$MACHINE_IN"
    else
      echo "error: unknown machine '$MACHINE_IN' (no configs/${MACHINE_IN}_defconfig)" >&2
      exit 2
    fi ;;
esac

for t in "$GCC" "$OBJCOPY" "$LD"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL build kernel — missing $t" >&2; exit 1; }
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

# This build applies a foreign board's Kconfig and puts the previous one back, so
# leave the generated headers exactly as found — content *and* mtime. Without the
# snapshot the round trip invalidates every AOT unit whose .d includes them.
# shellcheck source=tests/scripts/kconfig_snapshot.sh
. "$SCRIPT_DIR/kconfig_snapshot.sh"
kconfig_snapshot_begin

restore_cfg() {
  if [ "$SAVE_HAD_CFG" -eq 1 ]; then
    # Write-if-different, matching kconfig.py: restoring identical bytes must not
    # move .config's mtime, or the header rule looks stale on every plat build.
    cmp -s "$SAVE_CFG" "$TOS/.config" || cp "$SAVE_CFG" "$TOS/.config"
    make -C "$TOS" syncconfig >/dev/null
  else
    make -C "$TOS" defconfig-virt >/dev/null
  fi
  kconfig_snapshot_end
  rm -f "$SAVE_CFG"
  cleanup_lock
}
trap restore_cfg EXIT

make -C "$TOS" "defconfig-$DEFCONFIG" >/dev/null

MARCH=rv64imafdc
MABI=lp64d
ENTRY_POINT=0x80000000
if [ -f "$TOS/include/generated/kconfig.mk" ]; then
  # shellcheck disable=SC1090
  . "$TOS/include/generated/kconfig.mk"
fi
MARCH="${MARCH:-rv64imafdc}"
MABI="${MABI:-lp64d}"

T="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$T'; restore_cfg" EXIT

# --- OpenTitan: RV32 asm plat smoke (HolyC is RV64-only until ARCH_RISCV32) ---
if [ "$DEFCONFIG" = opentitan ]; then
  "$GCC" -march=rv32imc -mabi=ilp32 -nostdlib -ffreestanding -fno-builtin \
    -T "$HARNESS/link_opentitan.ld" -o "$T/plat.elf" "$HARNESS/opentitan_plat.S" \
    || { echo "FAIL build kernel — opentitan RV32 link" >&2; exit 1; }
  cp "$T/plat.elf" "$KDIR/plat.elf"
  cp "$T/plat.elf" "$EXEC_DIR/${DEFCONFIG}_plat.elf"
  cp "$T/plat.elf" "$EXEC_DIR/plat-$DEFCONFIG.elf"
  "$OBJCOPY" -O binary "$KDIR/plat.elf" "$KDIR/plat.bin" 2>/dev/null || true
  cp "$TOS/.config" "$KDIR/.config"
  cp "$ROOT/Kernel/RVAutoConf.HH" "$KDIR/RVAutoConf.HH"
  mkdir -p "$KDIR/DrvSelected"
  for f in RVUartSelected.HH RVPlicSelected.HH RVSifiveSelected.HH RVVirtioSelected.HH RVFbSelected.HH RVTimerSelected.HH; do
    [ -f "$ROOT/Kernel/Drv/$f" ] && cp "$ROOT/Kernel/Drv/$f" "$KDIR/DrvSelected/$f"
  done
  python3 "$TOS/scripts/kconfig.py" qemu-args >"$KDIR/qemu-args.txt" 2>"$KDIR/qemu-system.txt" || true
  {
    echo "machine=$DEFCONFIG"
    echo "elf=$KDIR/plat.elf"
    echo "output_format=elf"
    echo "note=RV32 asm harness until ARCH_RISCV32; drivers RVUartIbex+RVTimerIbex ready"
    echo "compat_elf=$EXEC_DIR/${DEFCONFIG}_plat.elf"
    date -u +'built=%Y-%m-%dT%H:%M:%SZ'
  } >"$KDIR/BUILD_INFO.txt"
  echo "Built kernel ($DEFCONFIG): $KDIR/plat.elf (RV32 asm plat harness)"
  exit 0
fi

# Board description for the C half of the image. The HolyC half gets its addresses
# from Kernel/RVAutoConf.HH; the C harness (oracle_out.c + bootstrap/holy_rt.h) had
# them baked in at virt's values, so trap_report / the crash monitor / the ^C IRQ path
# all talked to virt's 16550 at 0x10000000 no matter which board was built. On a SiFive
# board 0x10000000 is the PRCI, so those writes went into the clock controller and
# nothing was printed. Read the applied .config and pass the real ones through.
CFG="$TOS/.config"
cfg_val() { sed -n "s/^$1=//p" "$CFG" | tail -1; }
CFG_UART_SIFIVE="$(cfg_val CONFIG_UART_SIFIVE)"
CFG_UART_BASE="$(cfg_val CONFIG_UART_BASE)"
CFG_UART_IRQ="$(cfg_val CONFIG_UART_IRQ)"
CFG_CLINT_BASE="$(cfg_val CONFIG_CLINT_BASE)"
CFG_PLIC_BASE="$(cfg_val CONFIG_PLIC_BASE)"
# Per-hart / per-context offsets. The runtime's defaults are hart 0 / context 0; a board whose image
# runs on hart 1 (hifive_unmatched) arms a parked hart's mtimecmp and claims on the S7's PLIC context
# unless these follow the Kconfig the HolyC drivers already use.
CFG_CLINT_MTIMECMP_OFF="$(cfg_val CONFIG_CLINT_MTIMECMP_OFF)"
CFG_PLIC_ENABLE_OFF="$(cfg_val CONFIG_PLIC_ENABLE_OFF)"
CFG_PLIC_THRESHOLD_OFF="$(cfg_val CONFIG_PLIC_THRESHOLD_OFF)"
CFG_PLIC_CLAIM_OFF="$(cfg_val CONFIG_PLIC_CLAIM_OFF)"

# Shared harness objects (machine-independent RV64).
# sifive_e uses slim oracle_out_plat.o (16 KiB DTIM); others use full oracle_out.o.
ORACLE_SRC="$HARNESS/oracle_out.c"
ORACLE_OBJ="$EXEC_DIR/oracle_out.o"
ORACLE_DEFS=""
LINK_LD="$HARNESS/link_exec.ld"
if [ "$DEFCONFIG" = sifive_e ]; then
  ORACLE_SRC="$HARNESS/oracle_out_plat.c"
  ORACLE_OBJ="$EXEC_DIR/oracle_out_plat.o"
  LINK_LD="$HARNESS/link_sifive_e.ld"
elif [ "$DEFCONFIG" = visionfive2 ]; then
  LINK_LD="$HARNESS/link_visionfive2.ld"
elif [ "$DEFCONFIG" = milkv_mars ]; then
  LINK_LD="$HARNESS/link_milkv_mars.ld"
elif [ "$DEFCONFIG" = hifive_unmatched ]; then
  # FU740 board image links at 0x80200000 — SPL+OpenSBI own the first 2 MiB of DDR.
  LINK_LD="$HARNESS/link_hifive_unmatched.ld"
fi

# Every board: tell the C harness where the CLINT and PLIC actually are. This used to be
# passed only for SiFive-UART boards, which was enough while holy_rt.h only used the CLINT for
# its timer. It now reads mtime as the tick source for GetTSC/tS (rdtime is an illegal
# instruction on SiFive cores), so a wrong base is a wrong timestamp -- and xiangshan's CLINT
# is at 0x38000000 while the header defaults to virt's 0x02000000.
if [ -n "$CFG_CLINT_BASE" ]; then
  ORACLE_DEFS="$ORACLE_DEFS -DHOLY_CLINT_BASE=${CFG_CLINT_BASE}ULL -DHOLY_CLINT_MTIMECMP_OFF=${CFG_CLINT_MTIMECMP_OFF:-0x4000}ULL"
  ORACLE_TAG="clint${CFG_CLINT_BASE}-tc${CFG_CLINT_MTIMECMP_OFF:-0x4000}"
else
  # No CLINT at all (amd_microblaze_v, opentitan): rdtime is the only tick source there.
  ORACLE_DEFS="$ORACLE_DEFS -DHOLY_NO_CLINT=1"
  ORACLE_TAG="noclint"
fi
if [ -n "$CFG_PLIC_BASE" ]; then
  ORACLE_DEFS="$ORACLE_DEFS -DHOLY_PLIC=${CFG_PLIC_BASE} -DHOLY_PLIC_ENABLE_OFF=${CFG_PLIC_ENABLE_OFF:-0x2000} -DHOLY_PLIC_THRESHOLD_OFF=${CFG_PLIC_THRESHOLD_OFF:-0x200000} -DHOLY_PLIC_CLAIM_OFF=${CFG_PLIC_CLAIM_OFF:-0x200004}"
  ORACLE_TAG="${ORACLE_TAG}-pe${CFG_PLIC_ENABLE_OFF:-0x2000}"
fi
# SiFive-UART boards (not sifive_e, which already has its own slim SiFive oracle):
# compile the full oracle for the SiFive register LAYOUT at the board's own base.
# -DHOLY_UART_BASE alone cannot do this — TXDATA is a 32-bit word at +0 with a FULL
# bit, not a byte THR, and RXDATA is at +4, not an LSR at +5.
if [ "$CFG_UART_SIFIVE" = y ] && [ "$DEFCONFIG" != sifive_e ]; then
  ORACLE_DEFS="$ORACLE_DEFS -DHOLY_UART_SIFIVE=1 -DUART_BASE=${CFG_UART_BASE}UL -DHOLY_UART_BASE=${CFG_UART_BASE}ULL"
  ORACLE_DEFS="$ORACLE_DEFS -DHOLY_UART_IRQ=${CFG_UART_IRQ:-0}"
  ORACLE_TAG="sfu${CFG_UART_BASE}-irq${CFG_UART_IRQ:-0}-${ORACLE_TAG}"
fi

# ONE place computes the object path, and it is derived from BOTH the source file and every
# -D that goes with it. Keying it on the flags alone is not enough and cost a matrix failure:
# sifive_e compiles the SLIM oracle_out_plat.c while virt and friends compile the full
# oracle_out.c, and both have their CLINT at 0x02000000 -- so they collided on one path, and
# because the staleness test below is mtime-only, sifive_e was handed the full oracle and blew
# its 16 KiB DTIM budget at link time. Same hazard this script already documents for the UART
# flags, arrived at from a different direction.
ORACLE_OBJ="$EXEC_DIR/$(basename "$ORACLE_SRC" .c)-${ORACLE_TAG}.o"

need_oracle=0
if [ ! -f "$ORACLE_OBJ" ] || [ "$ORACLE_SRC" -nt "$ORACLE_OBJ" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$ORACLE_OBJ" ]; then
  need_oracle=1
fi
# Which hart the image runs on. Hart 0 on the FU740/FU540 is the S7/E51 management
# core (rv64imac, no F/D) and cannot execute this rv64imafdc/lp64d image at all, so
# those boards boot on hart 1. As with the oracle, the variant gets its own object
# path: the staleness test below is mtime-only and would otherwise hand one board's
# crt0 to the next.
CRT_DEFS=""
CRT_OBJ="$EXEC_DIR/crt0.o"
BOOT_HARTID=0
case "$DEFCONFIG" in
  hifive_unmatched|sifive_u)
    BOOT_HARTID=1
    CRT_DEFS="-DBOOT_HARTID=1"
    CRT_OBJ="$EXEC_DIR/crt0-hart1.o" ;;
esac

need_crt=0
if [ ! -f "$CRT_OBJ" ] || [ "$HARNESS/crt0.S" -nt "$CRT_OBJ" ]; then
  need_crt=1
fi

if [ "$need_oracle" -eq 1 ]; then
  UART_DEF="$ORACLE_DEFS"
  if [ "$DEFCONFIG" = sifive_e ]; then
    UART_DEF="-DUART_BASE=0x10013000UL"
  fi
  # shellcheck disable=SC2086
  "$GCC" -march="$MARCH" -mabi="$MABI" -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    $UART_DEF -c "$ORACLE_SRC" -o "$ORACLE_OBJ" \
    || { echo "FAIL build kernel — harness compile" >&2; exit 1; }
fi
if [ "$need_crt" -eq 1 ]; then
  # shellcheck disable=SC2086
  "$GCC" -march="$MARCH" -mabi="$MABI" -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    $CRT_DEFS -c "$HARNESS/crt0.S" -o "$CRT_OBJ" \
    || { echo "FAIL build kernel — crt0" >&2; exit 1; }
fi

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL build kernel — HolyC compile error ($DEFCONFIG)" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$LINK_LD" -nostdlib --no-warn-mismatch -o plat.elf \
    "$CRT_OBJ" "$ORACLE_OBJ" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL build kernel — link error ($DEFCONFIG)" >&2; exit 1; }

cp "$T/plat.elf" "$KDIR/plat.elf"
cp "$T/plat.elf" "$EXEC_DIR/${DEFCONFIG}_plat.elf"
cp "$T/plat.elf" "$EXEC_DIR/plat-$DEFCONFIG.elf"

"$OBJCOPY" -O binary "$KDIR/plat.elf" "$KDIR/plat-ram.bin" 2>/dev/null || true
if [ -f "$KDIR/plat-ram.bin" ]; then
  cp "$KDIR/plat-ram.bin" "$EXEC_DIR/${DEFCONFIG}_plat.bin"
fi

OUTPUT_FMT=elf
if [ -f "$TOS/include/generated/kconfig.mk" ]; then
  # shellcheck disable=SC1090
  . "$TOS/include/generated/kconfig.mk"
fi
if [ "${OUTPUT_FORMAT:-elf}" = firmware ]; then
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
elif [ -f "$KDIR/plat-ram.bin" ]; then
  cp "$KDIR/plat-ram.bin" "$KDIR/plat.bin"
fi

# JH7110 boards: also build a QEMU virt harness twin.
# Virt already places UART/CLINT/PLIC at the JH7110 bases (0x10000000 /
# 0x02000000 / 0x0C000000). Board plat keeps DDR@0x40200000 + REG_SHIFT=2;
# plat-qemu.elf uses virt DRAM@0x80000000 + REG_SHIFT=0 for the byte 16550.
JH7110_QEMU=0
if [ "$DEFCONFIG" = visionfive2 ] || [ "$DEFCONFIG" = milkv_mars ]; then
  JH7110_QEMU=1
  AUTOCONF="$ROOT/Kernel/RVAutoConf.HH"
  SAVE_AUTO="$T/RVAutoConf.board.HH"
  cp "$AUTOCONF" "$SAVE_AUTO"
  if ! grep -q '^#define CONFIG_UART_REG_SHIFT 2$' "$AUTOCONF"; then
    echo "FAIL build kernel — expected CONFIG_UART_REG_SHIFT 2 for $DEFCONFIG qemu twin" >&2
    exit 1
  fi
  sed -i.bak 's/^#define CONFIG_UART_REG_SHIFT 2$/#define CONFIG_UART_REG_SHIFT 0/' "$AUTOCONF"
  rm -f "$AUTOCONF.bak"
  if ! grep -q '^#define CONFIG_UART_REG_SHIFT 0$' "$AUTOCONF"; then
    cp "$SAVE_AUTO" "$AUTOCONF"
    echo "FAIL build kernel — REG_SHIFT patch failed for $DEFCONFIG plat-qemu" >&2
    exit 1
  fi
  if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob-qemu.bin" >/dev/null 2>&1; then
    cp "$SAVE_AUTO" "$AUTOCONF"
    echo "FAIL build kernel — HolyC compile error ($DEFCONFIG plat-qemu)" >&2
    HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob-qemu.bin" 2>&1 | tail -20 >&2
    exit 1
  fi
  # link_exec.ld places the AOT blob via the literal object name blob_in.o
  mkdir -p "$T/qemu"
  ( cd "$T/qemu" && cp ../blob-qemu.bin blob.bin && \
    "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
    "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o plat-qemu.elf \
      "$CRT_OBJ" "$ORACLE_OBJ" blob_in.o ) \
    >/dev/null 2>&1 || {
      cp "$SAVE_AUTO" "$AUTOCONF"
      echo "FAIL build kernel — link error ($DEFCONFIG plat-qemu)" >&2
      exit 1
    }
  cp "$SAVE_AUTO" "$AUTOCONF"
  cp "$T/qemu/plat-qemu.elf" "$KDIR/plat-qemu.elf"
  cp "$T/qemu/plat-qemu.elf" "$EXEC_DIR/${DEFCONFIG}_plat-qemu.elf"
fi

# HiFive Unmatched twin. Unlike the JH7110 boards this needs NO config rewrite: -M sifive_u
# already has the FU540/FU740 UART/CLINT/PLIC map, so the same blob works. The only thing that
# differs is the link address — the board image sits at 0x80200000 because SPL+OpenSBI own the
# first 2 MiB, while `-M sifive_u -bios none -kernel` enters at 0x80000000. Without the twin
# the board image loads on QEMU and is simply never entered (silent, looks like a hang).
if [ "$DEFCONFIG" = hifive_unmatched ]; then
  mkdir -p "$T/qemu"
  ( cd "$T/qemu" && cp ../blob.bin blob.bin && \
    "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
    "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o plat-qemu.elf \
      "$CRT_OBJ" "$ORACLE_OBJ" blob_in.o ) \
    >/dev/null 2>&1 || { echo "FAIL build kernel — link error ($DEFCONFIG plat-qemu)" >&2; exit 1; }
  cp "$T/qemu/plat-qemu.elf" "$KDIR/plat-qemu.elf"
  cp "$T/qemu/plat-qemu.elf" "$EXEC_DIR/${DEFCONFIG}_plat-qemu.elf"
  echo "  + QEMU twin (-M sifive_u, entry 0x80000000): $KDIR/plat-qemu.elf"
fi

cp "$TOS/.config" "$KDIR/.config"
cp "$ROOT/Kernel/RVAutoConf.HH" "$KDIR/RVAutoConf.HH"
mkdir -p "$KDIR/DrvSelected"
for f in RVUartSelected.HH RVPlicSelected.HH RVSifiveSelected.HH RVVirtioSelected.HH RVFbSelected.HH RVTimerSelected.HH; do
  [ -f "$ROOT/Kernel/Drv/$f" ] && cp "$ROOT/Kernel/Drv/$f" "$KDIR/DrvSelected/$f"
done
python3 "$TOS/scripts/kconfig.py" qemu-args >"$KDIR/qemu-args.txt" 2>"$KDIR/qemu-system.txt" || true
if [ "$JH7110_QEMU" -eq 1 ]; then
  {
    echo "# BOARD plat.bin @ ${ENTRY_POINT:-0x40200000} (U-Boot go / OpenOCD)"
    echo "# QEMU harness (no native -M): JH7110 UART/CLINT/PLIC bases on virt"
    echo "#   -M virt -bios none -kernel build/kernels/${DEFCONFIG}/plat-qemu.elf"
    echo "#   REG_SHIFT=0 + DRAM@0x80000000 for virt byte 16550; board plat keeps shift=2"
  } >>"$KDIR/qemu-args.txt"
fi
ENTRY_HEX="${ENTRY_POINT:-0x80000000}"
{
  echo "machine=$DEFCONFIG"
  echo "elf=$KDIR/plat.elf"
  echo "output_format=$OUTPUT_FMT"
  if [ -f "$KDIR/plat-ram.bin" ]; then
    echo "ram_bin=$KDIR/plat-ram.bin"
  fi
  if [ "$OUTPUT_FMT" = firmware ]; then
    echo "firmware_bin=$KDIR/plat.bin"
    echo "firmware_elf=$KDIR/plat-fw.elf"
  elif [ -f "$KDIR/plat.bin" ]; then
    echo "plat_bin=$KDIR/plat.bin"
    echo "loader_hint=-device loader,file=plat.bin,addr=${ENTRY_HEX} -device loader,addr=${ENTRY_HEX},cpu-num=${BOOT_HARTID}"
  fi
  if [ "$JH7110_QEMU" -eq 1 ]; then
    echo "qemu_elf=$KDIR/plat-qemu.elf"
    echo "qemu_note=-M virt -bios none -kernel plat-qemu.elf (JH7110 map overlap)"
  fi
  echo "compat_elf=$EXEC_DIR/${DEFCONFIG}_plat.elf"
  date -u +'built=%Y-%m-%dT%H:%M:%SZ'
} >"$KDIR/BUILD_INFO.txt"

if [ "$OUTPUT_FMT" = elf ]; then
  echo "Built kernel ($DEFCONFIG): $KDIR/plat.elf"
  if [ -f "$KDIR/plat.bin" ]; then
    echo "  + flat RAM bin: $KDIR/plat.bin ($(wc -c <"$KDIR/plat.bin") bytes)"
  fi
  if [ "$JH7110_QEMU" -eq 1 ]; then
    echo "  + QEMU harness: $KDIR/plat-qemu.elf (-M virt, JH7110 UART/CLINT/PLIC)"
  fi
fi
