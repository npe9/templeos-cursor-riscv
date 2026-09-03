#!/bin/bash
# Launch HolyC split bootloader + HolyC REPL blob on QEMU virt.
#
# Default: jump mode — pflash boot.bin + loader for hc_repl.blob.bin @ ENTRY_POINT.
#   --copy   copy-mode boot.bin only (embedded payload)
#   --dual   dual DRAM loaders (boot @ 0x80000000, payload @ PAYLOAD_ADDR)
#
# Guest images are HolyC AOT only (no gcc/ld). See docs/BAREMETAL.md.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
BOOT_BIN="$ROOT/build/bootloader/boot.bin"
REPL_BIN="$ROOT/build/hc_repl.blob.bin"
MODE=jump
ENTRY_POINT=0x80000000
PAYLOAD_ADDR=0x80200000
BOOT_ADDR=0x80000000
EXTRA=()

kcfg="$ROOT/templeos-riscv/include/generated/kconfig.mk"
if [ -f "$kcfg" ]; then
  # shellcheck source=/dev/null
  . "$kcfg"
  ENTRY_POINT="${ENTRY_POINT:-0x80000000}"
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [--copy|--dual] [--] [extra qemu args...]

  (default)  pflash HolyC boot.bin + loader hc_repl.blob.bin @ ENTRY_POINT ($ENTRY_POINT)
  --copy     pflash copy-mode boot.bin (embedded HolyC payload)
  --dual     loader boot.bin @ $BOOT_ADDR + blob @ $PAYLOAD_ADDR

Build first:  make bootloader-repl
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE=copy; shift ;;
    --dual) MODE=dual; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) EXTRA=("$@"); break ;;
  esac
done

case "$MODE" in
  copy)
    make -C "$ROOT" bootloader-repl BOOT_MODE=copy >/dev/null
    exec "$QEMU" -M virt -m 128M -bios none \
      -drive if=pflash,format=raw,file="$BOOT_BIN" -nographic "${EXTRA[@]}"
    ;;
  dual)
    make -C "$ROOT/bootstrap" -f Makefile.bootloader bootloader \
      BOOT_MODE=jump BOOTLOADER_BASE="$BOOT_ADDR" ENTRY_POINT="$PAYLOAD_ADDR" \
      PAD_PFLASH=0 >/dev/null
    make -C "$ROOT/bootstrap/hc_repl" blob >/dev/null
    # Dual mode: payload must be linked/loaded at PAYLOAD_ADDR — blob is
    # position-dependent for data; prefer default ENTRY_POINT=0x80000000 jump.
    exec "$QEMU" -M virt -m 128M -bios none \
      -device "loader,file=$BOOT_BIN,addr=$BOOT_ADDR" \
      -device "loader,file=$REPL_BIN,addr=$PAYLOAD_ADDR" \
      -nographic "${EXTRA[@]}"
    ;;
  *)
    make -C "$ROOT" bootloader-repl BOOT_MODE=jump >/dev/null
    exec "$QEMU" -M virt -m 128M -bios none \
      -drive if=pflash,format=raw,file="$BOOT_BIN" \
      -device "loader,file=$REPL_BIN,addr=$ENTRY_POINT" \
      -nographic "${EXTRA[@]}"
    ;;
esac
