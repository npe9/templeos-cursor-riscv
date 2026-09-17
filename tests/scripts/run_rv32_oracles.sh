#!/bin/bash
# RV32 P1 progress meter: compile every exec-oracle manifest case with --target rv32, boot it
# on qemu-system-riscv32 behind crt0_rv32.S (prints ORACLE <a1><a0>), and classify:
#   PASS   full 64-bit pattern matches the manifest
#   LOW32  only the low word matches (wide I64 not lowered yet)
#   IMPORT blob has a HOFYIMP1 trailer (calls the runtime; no rv32 runtime yet)
#   CFAIL / TRAP / FAIL
# RV32_ORACLE_VERBOSE=1 prints each case. RV32_ORACLE_EXPECT=<file> (one case path per line)
# lists cases that must PASS; any of them not passing fails the script (exit 1).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
MANIFEST="${ORACLE_MANIFEST:-$ROOT/tests/exec/oracle_manifest.tsv}"
HOLYC="$ROOT/holyc-riscv"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM_RV32:-qemu-system-riscv32}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
TSEC="${QEMU_TIMEOUT_SEC:-3}"
EXPECT_FILE="${RV32_ORACLE_EXPECT:-}"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP rv32 oracles — missing $t" >&2; exit 0; }
done

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
"$GCC" -march=rv32ima_zicsr -mabi=ilp32 -nostdlib -ffreestanding -c "$HARNESS/crt0_rv32.S" -o "$T/crt0.o" \
  || { echo "FAIL rv32 oracles — crt0" >&2; exit 1; }

STATUS="$T/status.tsv"; : >"$STATUS"   # bash 3.2 (macOS): no assoc arrays
n_pass=0 n_low=0 n_imp=0 n_cfail=0 n_trap=0 n_fail=0
while IFS=$'\t' read -r src want; do
  case "$src" in ''|'#'*) continue ;; esac
  name="$(basename "$src" .hc)"
  d="$T/$name"; mkdir -p "$d"
  if ! HOLYC_INCLUDE_ROOT="$ROOT" "$TIMEOUT" 60 "$HOLYC" --target rv32 "$ROOT/$src" -o "$d/blob.bin" >"$d/cc.log" 2>&1; then
    st=CFAIL; n_cfail=$((n_cfail+1))
  elif LC_ALL=C grep -q HOFYIMP1 "$d/blob.bin"; then
    st=IMPORT; n_imp=$((n_imp+1))
  else
    ( cd "$d" && "$OBJCOPY" -I binary -O elf32-littleriscv blob.bin blob_in.o && \
      "$LD" -m elf32lriscv -T "$HARNESS/link_rv32.ld" -nostdlib --no-warn-mismatch -o p.elf "$T/crt0.o" blob_in.o ) >"$d/ld.log" 2>&1
    out="$("$TIMEOUT" "$TSEC" "$QEMU" -M virt -bios none -kernel "$d/p.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
    got="$(printf '%s\n' "$out" | sed -n 's/^ORACLE \([0-9a-f]\{16\}\)$/\1/p' | head -1)"
    if [ -n "$got" ] && [ "$got" = "$want" ]; then st=PASS; n_pass=$((n_pass+1))
    elif [ -n "$got" ] && [ "${got:8}" = "${want:8}" ]; then st=LOW32; n_low=$((n_low+1))
    elif printf '%s\n' "$out" | grep -q '^TRAP'; then st=TRAP; n_trap=$((n_trap+1)); got="$(printf '%s\n' "$out" | grep '^TRAP' | head -1)"
    else st=FAIL; n_fail=$((n_fail+1))
    fi
  fi
  printf '%s\t%s\n' "$src" "$st" >>"$STATUS"
  [ "${RV32_ORACLE_VERBOSE:-0}" = 1 ] && printf '%-6s %s want=%s got=%s\n' "$st" "$name" "$want" "${got:-}"
  got=""
done < "$MANIFEST"

echo "RV32 oracles: PASS=$n_pass LOW32=$n_low IMPORT=$n_imp TRAP=$n_trap FAIL=$n_fail CFAIL=$n_cfail"
rc=0
if [ -n "$EXPECT_FILE" ]; then
  while read -r src; do
    case "$src" in ''|'#'*) continue ;; esac
    st="$(awk -F'\t' -v s="$src" '$1==s{print $2}' "$STATUS")"
    if [ "${st:-MISSING}" != PASS ]; then
      echo "FAIL rv32 oracles — expected PASS: $src (${st:-MISSING})" >&2; rc=1
    fi
  done < "$EXPECT_FILE"
fi
exit $rc
