#!/bin/bash
# Launch TempleOS bare-metal REPL on QEMU virt (-bios none -kernel).
#
# Default: flat bin @ 0x80000000 (virt reset ROM jumps there with -bios none).
# Use --elf for the debug ELF, or --loader for explicit load address.
#
# See docs/BAREMETAL.md.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
BMD="$ROOT/build/baremetal"
MODE=bin
LOAD_ADDR=0x80000000
EXTRA=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [--elf] [--loader [addr]] [--] [extra qemu args...]

  (default)  -bios none -kernel build/baremetal/repl.bin
  --elf      -bios none -kernel build/baremetal/repl.elf
  --loader   -bios none -device loader,addr=ADDR,file=repl.bin

Build first:  make baremetal
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --elf) MODE=elf; shift ;;
    --loader)
      MODE=loader
      shift
      if [ $# -gt 0 ] && [[ "$1" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
        LOAD_ADDR="$1"
        shift
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) EXTRA=("$@"); break ;;
  esac
done

make -C "$ROOT" baremetal >/dev/null

case "$MODE" in
  elf)
    exec "$QEMU" -M virt -m 128M -bios none -kernel "$BMD/repl.elf" -nographic "${EXTRA[@]}"
    ;;
  loader)
    exec "$QEMU" -M virt -m 128M -bios none \
      -device "loader,addr=$LOAD_ADDR,file=$BMD/repl.bin" -nographic "${EXTRA[@]}"
    ;;
  *)
    exec "$QEMU" -M virt -m 128M -bios none -kernel "$BMD/repl.bin" -nographic "${EXTRA[@]}"
    ;;
esac
