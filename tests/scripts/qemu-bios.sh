#!/bin/bash
# Launch TempleOS on QEMU virt.
#
# Default (RAM BIOS):  qemu -bios build/firmware/templeos-bios.elf
# Flash ROM (--pflash): qemu -bios none -drive if=pflash,file=build/firmware/templeos-fw.bin
#
# templeos-fw.bin is linked for flash @ 0x20000000 — do NOT pass it to -bios.
# See templeos-riscv/PLATFORM.md § Firmware / BIOS.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
MODE=ram
EXTRA=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [--pflash] [--] [extra qemu args...]

  (default)  -bios build/firmware/templeos-bios.elf   RAM-loaded M-mode payload
  --pflash   -bios none -drive if=pflash,...          flash ROM @ 0x20000000

Build images first:  make firmware
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pflash) MODE=pflash; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) EXTRA=("$@"); break ;;
  esac
done

make -C "$ROOT/bootstrap" -f Makefile.firmware firmware >/dev/null

if [ "$MODE" = pflash ]; then
  FW="$ROOT/build/firmware/templeos-fw.bin"
  exec "$QEMU" -M virt -m 128M -bios none \
    -drive if=pflash,format=raw,file="$FW" -nographic ${EXTRA+"${EXTRA[@]}"}
fi

BIOS="$ROOT/build/firmware/templeos-bios.elf"
exec "$QEMU" -M virt -m 128M -bios "$BIOS" -nographic ${EXTRA+"${EXTRA[@]}"}
