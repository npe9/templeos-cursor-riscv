#!/bin/bash
# HolyC platform smoke: Kernel/Drv UART+CLINT via Kconfig (RVAutoConf.HH).
# Usage: run_kernel_plat_smoke.sh [virt|sifive_u|spike|…]
#
# Builds (or refreshes) build/kernels/<machine>/plat.elf via build_kernel_plat.sh,
# then loads it with matching QEMU -M / load mode.
#
# Policy: skips are not allowed. Missing QEMU / build failure / missing PASS → fail.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SH="$SCRIPT_DIR/build_kernel_plat.sh"
MACHINE="${1:-virt}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

# Map friendly arg → defconfig + QEMU -M + load mode.
# load: kernel (-bios none -kernel ELF) | bios (-bios ELF) | loader (-device loader…)
#        | ot_kernel (opentitan: -kernel only, no -bios none)
#        | jh7110_virt (VisionFive 2 / Mars: plat-qemu.elf on -M virt)
DEFCONFIG=""
QEMU_M=""
LOAD="kernel"
ELF_NAME="plat.elf"
# Second needle, required in addition to "plat-smoke: PASS" when set. PASS comes from
# HolyC RVUartPutS (CONFIG_UART_BASE), so it passes even when the C half of the image
# is writing bytes into some other device. A needle printed by the C harness is the
# only thing that tests the C board description.
EXTRA_NEEDLE=""
BOARD_ENTRY=""
BOARD_HART=0
# Space-separated extra argv (avoid empty-array + set -u on Bash 3.2 / macOS).
QEMU_EXTRA_STR="-bios none"
case "$MACHINE" in
  virt)
    DEFCONFIG=virt; QEMU_M=virt ;;
  sifive_u)
    DEFCONFIG=sifive_u; QEMU_M=sifive_u ;;
  spike)
    DEFCONFIG=spike; QEMU_M=spike ;;
  shakti_c)
    DEFCONFIG=shakti_c; QEMU_M=shakti_c; LOAD=bios; QEMU_EXTRA_STR="" ;;
  sifive_e)
    DEFCONFIG=sifive_e; QEMU_M=sifive_e ;;
  microchip_icicle|microchip-icicle-kit)
    DEFCONFIG=microchip_icicle; QEMU_M=microchip-icicle-kit; QEMU_EXTRA_STR="-bios none" ;;
  xiangshan|xiangshan-kunminghu)
    DEFCONFIG=xiangshan; QEMU_M=xiangshan-kunminghu; LOAD=bios; QEMU_EXTRA_STR="-smp 1" ;;
  amd_microblaze_v|amd-microblaze-v-generic)
    DEFCONFIG=amd_microblaze_v; QEMU_M=amd-microblaze-v-generic; LOAD=loader; QEMU_EXTRA_STR="" ;;
  opentitan)
    DEFCONFIG=opentitan; QEMU_M=opentitan; LOAD=ot_kernel; QEMU_EXTRA_STR=""
    QEMU="${QEMU_SYSTEM:-qemu-system-riscv32}" ;;
  visionfive2|visionfive-2|jh7110)
    # No native -M; UART/CLINT/PLIC bases match virt. Smoke uses plat-qemu.elf.
    DEFCONFIG=visionfive2; QEMU_M=virt; LOAD=jh7110_virt; ELF_NAME=plat-qemu.elf ;;
  milkv_mars|milkv-mars|mars)
    DEFCONFIG=milkv_mars; QEMU_M=virt; LOAD=jh7110_virt; ELF_NAME=plat-qemu.elf ;;
  hifive_unmatched|hifive-unmatched|unmatched|fu740)
    # No QEMU machine models the FU740, but -M sifive_u (FU540) has the same
    # UART/CLINT/PLIC map for everything this kernel touches. Unlike the JH7110
    # boards we do NOT run a re-linked twin: `-device loader` puts the REAL board
    # plat.bin at its real 0x80200000 and points the boot hart's reset PC there, so the
    # gate tests the artifact that goes on the hardware, at its own link address.
    DEFCONFIG=hifive_unmatched; QEMU_M=sifive_u; LOAD=board_loader
    BOARD_ENTRY=0x80200000
    # Hart 1, not hart 0. On the FU740 (and the FU540 that -M sifive_u models) hart 0
    # is the S7/E51 management core: rv64imac, no F/D, so it cannot execute this
    # rv64imafdc/lp64d image. crt0.S is built -DBOOT_HARTID=1 for this board.
    BOARD_HART=1
    QEMU_EXTRA_STR="-bios none -smp 2"
    # ORACLE comes from oracle_out.c's putc_uart. On this board that is a 32-bit
    # TXDATA write at 0x10010000; the old byte-THR-at-0x10000000 harness printed
    # nothing at all (0x10000000 is the FU740 PRCI). Requiring it is what makes
    # this gate fail if the SiFive harness ever stops being selected.
    EXTRA_NEEDLE="ORACLE " ;;
  none|host)
    echo "FAIL plat smoke ($MACHINE) — not a TempleOS/RV board target (excluded from matrix)" >&2
    exit 1 ;;
  *)
    echo "usage: $0 [virt|sifive_u|spike|shakti_c|sifive_e|microchip_icicle|xiangshan|amd_microblaze_v|opentitan|visionfive2|milkv_mars|hifive_unmatched]" >&2
    exit 2 ;;
esac

command -v "$QEMU" >/dev/null 2>&1 || { echo "FAIL plat smoke — missing $QEMU" >&2; exit 1; }

chmod +x "$BUILD_SH"
if ! out="$("$BUILD_SH" "$DEFCONFIG" 2>&1)"; then
  printf '%s\n' "$out" >&2
  exit 1
fi
# Build must never SKIP — treat leftover SKIP lines as failure.
if printf '%s\n' "$out" | grep -q '^SKIP '; then
  echo "FAIL plat smoke ($DEFCONFIG) — build printed SKIP (skips not allowed)" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
printf '%s\n' "$out"

ELF="$ROOT/build/kernels/$DEFCONFIG/$ELF_NAME"
[ -f "$ELF" ] || { echo "FAIL plat smoke — missing $ELF" >&2; exit 1; }

if [ "$LOAD" = board_loader ]; then
  BIN="$ROOT/build/kernels/$DEFCONFIG/plat.bin"
  [ -f "$BIN" ] || { echo "FAIL plat smoke — missing $BIN" >&2; exit 1; }
  # The link address is a property of the artifact, not of this script: read it out
  # of the ELF rather than trusting the literal above, so a re-linked image fails
  # here instead of silently never being entered.
  ELF_ENTRY="$(riscv64-unknown-elf-readelf -h "$ELF" 2>/dev/null | sed -n 's/.*Entry point address: *//p')"
  if [ -n "$ELF_ENTRY" ] && [ "$((ELF_ENTRY))" -ne "$((BOARD_ENTRY))" ]; then
    echo "FAIL plat smoke ($DEFCONFIG) — ELF entry $ELF_ENTRY != board entry $BOARD_ENTRY" >&2
    echo "  (loading at $BOARD_ENTRY would place the image where it is never entered)" >&2
    exit 1
  fi
fi

# shellcheck disable=SC2086
case "$LOAD" in
  bios)
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -bios "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  loader)
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -device "loader,file=$ELF,cpu-num=0" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  ot_kernel)
    # OpenTitan rejects -bios none as a filename; -kernel loads flash @ ENTRY.
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  jh7110_virt)
    # JH7110 map overlap on virt (same UART/CLINT/PLIC bases; see PLATFORM.md).
    out="$($TIMEOUT 20 "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  board_loader)
    # Real board image at its real link address. -kernel cannot do this: on sifive_u
    # it enters at DRAM base, so a 0x80200000 image would load and never run.
    # The first loader writes the bin, the second sets the boot hart's reset PC.
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR \
            -device "loader,file=$BIN,addr=$BOARD_ENTRY" \
            -device "loader,addr=$BOARD_ENTRY,cpu-num=$BOARD_HART" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  *)
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
esac
if printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
  if [ -n "$EXTRA_NEEDLE" ] && ! printf '%s\n' "$out" | grep -qF "$EXTRA_NEEDLE"; then
    echo "FAIL plat smoke ($DEFCONFIG) — HolyC said PASS but the C harness needle" >&2
    echo "  '$EXTRA_NEEDLE' never appeared: the C half of the image is printing to" >&2
    echo "  the wrong device (see oracle_out.c HOLY_UART_SIFIVE)." >&2
    printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
    exit 1
  fi
  echo "Plat smoke ($DEFCONFIG): OK"
  exit 0
fi
echo "FAIL plat smoke ($DEFCONFIG) — expected plat-smoke: PASS" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
exit 1
