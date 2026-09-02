#!/bin/bash
# Interactive WinMgr: build win_i.elf, headless UART proof (paint + virtio-input),
# or launch cocoa hold (`make kernel-win-run` / RVWIN_HOLD=1).
#
# CI-safe default: -display none + hash/UART expects (no human staring at cocoa).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_win_interactive.hc"
EXPECT_HASH_PREFIX="RVWinMgr interactive hash="
EXPECT_DONE_PREFIX="RVWinMgr interactive DONE"
EXPECT_INPUT="input_ok=1"
EXPECT_PUT="put=1"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

HOLD="${RVWIN_HOLD:-0}"
RUN_QEMU="${RVWIN_RUN:-1}"
# kernel-win-run sets RVWIN_HOLD=1 RVWIN_DISPLAY=cocoa
DISPLAY_KIND="${RVWIN_DISPLAY:-none}"

for t in "$GCC" "$OBJCOPY" "$LD"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-win-interactive — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-win-interactive — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-win-interactive — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

COMPILE_SRC="$SRC"
if [ "$HOLD" = "1" ]; then
  cat >"$T/win_hold.hc" <<'EOF'
#define RV_WIN_HOLD 1
#include "/tests/exec/cases/kernel_win_interactive.hc"
EOF
  COMPILE_SRC="$T/win_hold.hc"
fi

if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$COMPILE_SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-win-interactive — compile error" >&2
  HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$COMPILE_SRC" -o "$T/blob.bin" >&2 || true
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o win_i.elf \
    "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-win-interactive — link error" >&2; exit 1; }

cp "$T/win_i.elf" "$OUTDIR/win_i.elf"
ELF="$OUTDIR/win_i.elf"

QEMU_BASE=( -M virt -m 256M -bios none -kernel "$ELF"
  -device ramfb -serial stdio
  -device virtio-keyboard-device -device virtio-tablet-device )

if [ "$HOLD" = "1" ]; then
  # Human path: visible display until ESC (cocoa on macOS, sdl/gtk elsewhere).
  if [ "$DISPLAY_KIND" = "cocoa" ] || [ "$DISPLAY_KIND" = "auto" ]; then
    case "$(uname -s)" in
      Darwin) DISPLAY_KIND=cocoa ;;
      *) DISPLAY_KIND=sdl ;;
    esac
  fi
  echo "Kernel-win-interactive: built $ELF"
  echo "Launching QEMU display=$DISPLAY_KIND (Tab/click/type; ESC quits)…"
  exec "$QEMU" "${QEMU_BASE[@]}" -display "$DISPLAY_KIND"
fi

# Headless proof (default / CI)
command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP kernel-win-interactive — missing $QEMU" >&2; exit 0; }

if [ "$RUN_QEMU" != "1" ]; then
  echo "Kernel-win-interactive: built $ELF (RVWIN_RUN=0 — skip QEMU)"
  echo "Run:"
  echo "  qemu-system-riscv64 ${QEMU_BASE[*]} -display cocoa"
  exit 0
fi

out="$($TIMEOUT 45 "$QEMU" "${QEMU_BASE[@]}" -display none </dev/null 2>&1 | tr -d '\r')"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_HASH_PREFIX"; then
  echo "FAIL kernel-win-interactive — no hash line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
  exit 1
fi
line="$(printf '%s\n' "$out" | grep -F "$EXPECT_HASH_PREFIX" | tail -1)"
if ! printf '%s\n' "$line" | grep -qF "$EXPECT_PUT"; then
  echo "FAIL kernel-win-interactive — DocPut missing:" >&2
  echo "  got: $line" >&2
  exit 1
fi
hash="$(printf '%s\n' "$line" | sed -n 's/.*hash=\(0x[0-9A-Fa-f]\{1,8\}\).*/\1/p')"
if [ -z "$hash" ] || [ "$hash" = "0x00000000" ]; then
  echo "FAIL kernel-win-interactive — bad hash: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_DONE_PREFIX"; then
  echo "FAIL kernel-win-interactive — no DONE line (hung in VirtioInput/pump?):" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
  exit 1
fi
done_line="$(printf '%s\n' "$out" | grep -F "$EXPECT_DONE_PREFIX" | tail -1)"
if ! printf '%s\n' "$done_line" | grep -qF "$EXPECT_INPUT"; then
  echo "FAIL kernel-win-interactive — virtio-input not ready:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi

echo "Kernel-win-interactive: OK ($line)"
echo "  $done_line"
echo "Human cocoa (one command): make kernel-win-run"
exit 0
