#!/bin/bash
# Build HolyC → blob, link with bare-metal harness, run under qemu-system-riscv64, compare UART "ORACLE" line.
#
# Requires: holyc-riscv, riscv64-unknown-elf-{gcc,ld,objcopy}, qemu-system-riscv64, timeout (or gtimeout).
# Constraint: AOT blob entry must be I64 main() (see tests/exec/oracle_manifest.tsv header).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
MANIFEST="${ORACLE_MANIFEST:-$ROOT/tests/exec/oracle_manifest.tsv}"
OUTDIR="$ROOT/build/exec"
HOLYC="$ROOT/holyc-riscv"

PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf-}"
GCC="${PREFIX}gcc"
LD="${PREFIX}ld"
OBJCOPY="${PREFIX}objcopy"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need 'timeout' or 'gtimeout' for QEMU bounds" >&2
  exit 2
fi
TIMEOUT_SEC="${QEMU_TIMEOUT_SEC:-3}"

for tool in "$HOLYC" "$GCC" "$LD" "$OBJCOPY" "$QEMU"; do
  if ! command -v "$tool" >/dev/null 2>&1 && [ ! -x "$tool" ]; then
    echo "error: missing tool: $tool" >&2
    exit 2
  fi
done

if [ ! -f "$HOLYC" ]; then
  make -C "$ROOT" holyc-riscv >/dev/null
fi

mkdir -p "$OUTDIR"

build_harness_objs() {
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g \
    -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o"
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g \
    -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o"
}

if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ]; then
  build_harness_objs
elif [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
     [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ] || \
     [ "$HARNESS/link_exec.ld" -nt "$OUTDIR/crt0.o" ]; then
  build_harness_objs
fi

pass=0
fail=0
line_no=0

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  HolyC execution oracle tests (QEMU virt, UART ORACLE line)          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo "Manifest: $MANIFEST"
echo ""

while IFS= read -r line || [ -n "$line" ]; do
  line_no=$((line_no + 1))
  case "$line" in
    \#*|"") continue ;;
  esac

  line="${line%$'\r'}"

  src="${line%%	*}"
  expect_hex="${line#*	}"
  if [ "$src" = "$line" ]; then
    echo "SKIP $line (no tab separator)"
    continue
  fi
  expect_hex="$(echo "$expect_hex" | tr 'A-F' 'a-f' | tr -d '[:space:]')"
  if [ -z "${src:-}" ] || [ -z "${expect_hex:-}" ]; then
    continue
  fi

  fpath="$ROOT/$src"
  if [ ! -f "$fpath" ]; then
    echo "MISSING $src (line $line_no)"
    fail=$((fail + 1))
    continue
  fi

  if ! HOLYC_INCLUDE_ROOT="$ROOT" "$HOLYC" "$fpath" -o "$OUTDIR/blob.bin" >/dev/null 2>&1; then
    echo "FAIL $src — compile error"
    fail=$((fail + 1))
    continue
  fi

  (
    cd "$OUTDIR"
    "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o
    "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch \
      -o oracle.elf crt0.o oracle_out.o blob_in.o
  ) >/dev/null 2>&1 || {
    echo "FAIL $src — link error"
    fail=$((fail + 1))
    continue
  }

  # -nographic attaches the guest UART to stdio; without stdin redirected, QEMU consumes the manifest pipe.
  out="$($TIMEOUT_CMD "$TIMEOUT_SEC" "$QEMU" -M virt -bios none -kernel "$OUTDIR/oracle.elf" -nographic </dev/null 2>&1 || true)"
  got=""
  while IFS= read -r ol; do
    case "$ol" in
      ORACLE\ *)
        got="${ol#ORACLE }"
        break
        ;;
    esac
  done <<<"$out"
  got="$(echo "$got" | tr 'A-F' 'a-f' | tr -d '[:space:]')"

  if [ -z "$got" ]; then
    echo "FAIL $src — no ORACLE line (timeout or crash)"
    fail=$((fail + 1))
    continue
  fi

  if [ "$got" != "$expect_hex" ]; then
    echo "FAIL $src — expected ORACLE $expect_hex got $got"
    fail=$((fail + 1))
    continue
  fi

  echo "OK   $src → $got"
  pass=$((pass + 1))
done <"$MANIFEST"

echo ""
echo "Execution oracles: $pass pass, $fail fail"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
