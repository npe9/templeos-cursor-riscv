#!/usr/bin/env bash
# Differential assembler tests: holyc-riscv --asm-dump vs GNU gas.
# See tests/asm/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${HOLYC_BIN:-$ROOT/holyc-riscv}"
ASM_DIR="$ROOT/tests/asm"

if [[ ! -x "$BIN" ]]; then
  echo "Building holyc-riscv..." >&2
  make -C "$ROOT" holyc-riscv >/dev/null || {
    echo "error: missing $BIN (run make / make holyc-riscv)" >&2
    exit 1
  }
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required for asm-gnu-diff" >&2
  exit 1
fi

export ROOT HOLYC_BIN="$BIN"
exec python3 "$ASM_DIR/run_asm_gnu_diff.py" "$@"
