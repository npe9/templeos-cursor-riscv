#!/usr/bin/env bash
# RV64 codegen byte-identity gate for the portable-backend refactor (docs/MULTIARCH.md,
# plan milestones M1-M5). Compiles a fixed corpus of pure-codegen exec-oracle cases across
# the byte-affecting optimizer-env matrix and compares a sha256 manifest against a committed
# golden. The refactor re-expresses the RISC-V backend through a new TargetBackend interface;
# this gate proves the emitted rv64 bytes do not move at any step.
#
#   run_codegen_bytediff.sh record   # rewrite the golden from the current compiler (deliberate)
#   run_codegen_bytediff.sh check    # exit 1 if any (env,case) output differs from the golden
#   run_codegen_bytediff.sh          # default: check
#
# Corpus: the fast non-native e_* cases (the e_native_*/e_kernel_* cases are 20-70s each to
# compile — pre-existing compiler slowness — and the ~1MB kernel demos are excluded; `make ci`
# covers those behaviorally). Env matrix: the knobs that change emitted bytes.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOLYC="$ROOT/holyc-riscv"
CASES="$ROOT/tests/exec/cases"
GOLDEN="$ROOT/tests/asm/codegen_rv64_golden.txt"
TO=timeout; command -v gtimeout >/dev/null 2>&1 && TO=gtimeout
JOBS="${BYTEDIFF_JOBS:-6}"
TLIMIT="${BYTEDIFF_TIMEOUT:-60}"
export HOLYC ROOT TO TLIMIT
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# name;kv  — kv is the extra env (may be empty for the default build)
ENVS=(
  "default;"
  "no_opt;HOLYC_NO_OPT=1"
  "o1_4;HOLYC_O1_MODE=4"
  "no_promote;HOLYC_NO_PROMOTE=1"
  "no_tier2;HOLYC_NO_TIER2=1"
  "no_bool_elide;HOLYC_NO_BOOL_ELIDE=1"
  "no_tail_merge;HOLYC_NO_TAIL_MERGE=1"
  "no_call_tail;HOLYC_NO_CALL_TAIL=1"
  "no_dead_jmp;HOLYC_NO_DEAD_JMP=1"
)
# Exclude the native/kernel-header-heavy families and four asm/throw-heavy cases whose
# compile straddles the timeout nondeterministically (would flap the gate). All are covered
# behaviorally by `make exec-oracle`.
case_files() {
  ls "$CASES"/e_*.hc 2>/dev/null \
    | grep -vE '/e_(native|kernel)_' \
    | grep -vE '/(e_asm_la|e_demo_asm_div|e_demo_asm_mul|e_throw_fs_except_ch)\.hc$'
}

one() {  # arg: "name;kv;file"
  local name kv f out rc
  IFS=';' read -r name kv f <<<"$1"
  out="$(mktemp)"
  if env HOLYC_INCLUDE_ROOT="$ROOT" ${kv:+$kv} "$TO" "$TLIMIT" "$HOLYC" "$f" -o "$out" >/dev/null 2>&1 && [ -s "$out" ]; then
    printf '%s\t%s\t%s\n' "$name" "$(basename "$f")" "$(shasum -a 256 "$out" | awk '{print $1}')"
  else
    rc=$?
    printf '%s\t%s\t%s\n' "$name" "$(basename "$f")" "$([ "$rc" -eq 124 ] && echo TIMEOUT || echo COMPILE_FAIL)"
  fi
  rm -f "$out"
}
export -f one

manifest() {
  local pair name kv f
  for pair in "${ENVS[@]}"; do
    name="${pair%%;*}"; kv="${pair#*;}"
    for f in $(case_files); do printf '%s;%s;%s\n' "$name" "$kv" "$f"; done
  done | xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ '{}' | LC_ALL=C sort
}

[ -x "$HOLYC" ] || { echo "SKIP codegen-bytediff — build holyc-riscv first" >&2; exit 0; }

case "${1:-check}" in
  record)
    manifest > "$GOLDEN"
    echo "codegen-bytediff: recorded golden — $(wc -l < "$GOLDEN" | tr -d ' ') (env,case) rows → ${GOLDEN#$ROOT/}" ;;
  check)
    [ -f "$GOLDEN" ] || { echo "FAIL codegen-bytediff — no golden ($GOLDEN); run 'record' first" >&2; exit 1; }
    manifest > "$TMP/now.txt"
    if diff -u "$GOLDEN" "$TMP/now.txt" > "$TMP/d.txt"; then
      echo "codegen-bytediff: OK — $(wc -l < "$GOLDEN" | tr -d ' ') rv64 outputs byte-identical to golden"
    else
      echo "codegen-bytediff: RV64 CODEGEN CHANGED vs golden (re-record only if intended):" >&2
      sed -n '1,80p' "$TMP/d.txt" >&2
      exit 1
    fi ;;
  *) echo "usage: $0 {record|check}" >&2; exit 2 ;;
esac
