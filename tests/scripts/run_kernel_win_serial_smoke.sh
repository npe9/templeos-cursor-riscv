#!/bin/bash
# UART dig-down while WinMgr/FB runs: feed help/regs/q on -serial; expect needles.
# Builds via kernel-win-interactive (HOLD=0) then a short QEMU with piped cmds.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTDIR="$ROOT/build/exec"
ELF="$OUTDIR/win_i.elf"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

EXPECT_READY="RVWinSerial ready"
EXPECT_HELP="RVWinSerial — UART TTY"
EXPECT_REGS="mstatus="
EXPECT_QUIT="RVWinSerial: quit WinMgr"
EXPECT_DONE="RVWinMgr interactive DONE"

command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP kernel-win-serial — missing $QEMU" >&2; exit 0; }

# Ensure win_i.elf exists (headless interactive build).
RVWIN_HOLD=0 RVWIN_RUN=0 "$SCRIPT_DIR/run_kernel_win_interactive.sh" || exit 1
[ -f "$ELF" ] || { echo "FAIL kernel-win-serial — no $ELF" >&2; exit 1; }

# Rebuild with HOLD so Run(0) waits for serial `q` (bounded by timeout).
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cat >"$T/win_serial.hc" <<'EOF'
#define RV_WIN_HOLD 1
#include "/tests/exec/cases/kernel_win_interactive.hc"
EOF
COMPILER="$ROOT/holyc-riscv"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
HARNESS="$ROOT/tests/exec/harness"
if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$T/win_serial.hc" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-win-serial — compile" >&2
  HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$T/win_serial.hc" -o "$T/blob.bin" >&2 || true
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o win_serial.elf \
    "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-win-serial — link" >&2; exit 1; }
cp "$T/win_serial.elf" "$OUTDIR/win_serial.elf"
ELF="$OUTDIR/win_serial.elf"

# Small delay so banner prints before cmds; then help/regs/q.
out="$( { sleep 0.4; printf 'help\nregs\nq\n'; sleep 0.2; } | $TIMEOUT 25 "$QEMU" \
  -M virt -m 256M -bios none -kernel "$ELF" \
  -device ramfb -display none -serial stdio \
  -device virtio-keyboard-device -device virtio-tablet-device 2>&1 | tr -d '\r')"

fail=0
for needle in "$EXPECT_READY" "$EXPECT_HELP" "$EXPECT_REGS" "$EXPECT_QUIT"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    echo "FAIL kernel-win-serial — missing: $needle" >&2
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -40 | sed 's/^/  got: /' >&2
  exit 1
fi
echo "Kernel-win-serial: OK ($EXPECT_READY + help + regs + quit)"
if printf '%s\n' "$out" | grep -qF "$EXPECT_DONE"; then
  echo "  $EXPECT_DONE present"
fi
exit 0
