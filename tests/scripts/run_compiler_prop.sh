#!/usr/bin/env bash
# Property-based HolyC compiler semantic equivalence across opt tiers.
# See tests/compiler/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${HOLYC_BIN:-$ROOT/holyc-riscv}"
COMP_DIR="$ROOT/tests/compiler"

if [[ ! -x "$BIN" ]]; then
  echo "Building holyc-riscv..." >&2
  make -C "$ROOT" holyc-riscv >/dev/null || {
    echo "error: missing $BIN (run make / make holyc-riscv)" >&2
    exit 1
  }
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required for compiler-prop" >&2
  exit 1
fi

export ROOT HOLYC_BIN="$BIN"
export QEMU_TIMEOUT_SEC="${QEMU_TIMEOUT_SEC:-1}"
exec python3 "$COMP_DIR/run_compiler_prop.py" "$@"
