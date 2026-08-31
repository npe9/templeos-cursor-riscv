#!/usr/bin/env bash
# Emit the HolyC path list enforced by `make fmt` / `make fmt-check`.
# Same gofmt-style contract as docs/CONTRIBUTING.md and .cursor/rules/holyc-fmt.mdc.
#
# Scope (port-owned / CI-facing; expand over time — not the unreformed x86 corpus):
#   bootstrap/seed/
#   bootstrap/hc_repl/   (*.hc)
#   Kernel/**/*RV* + Kernel/Drv/
#   Compiler/**/*RV*
#   Adam/*RV*            (HolyC only; not *.PRJ)
#   tests/exec/cases/
#   tests/fmt/golden/    (not tests/fmt/cases/ — intentionally ugly inputs)
#
# Exclusions: tests/scratch/, tests/fmt/cases/, known unformattable fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

is_holyc() {
  case "$1" in
    *.hc|*.HC|*.HH|*.hh) return 0 ;;
    *) return 1 ;;
  esac
}

# Basename denylist:
# - fixtures that must not parse/format (syntax stress)
# - files where --fmt is not yet idempotent (trailing // on control lines; holyc_fmt.c)
excluded_basename() {
  case "$1" in
    e_misc_syntax.hc) return 0 ;;
    e_cast_deref_store.hc|e_f64_array_decay.hc|e_postfix_cast_store.hc|e_precedence.hc) return 0 ;;
    DskVirtioRV.HC) return 0 ;; # trailing // on while/for; holyc_fmt.c eats following stmts
    *) return 1 ;;
  esac
}

emit_find() {
  local dir="$1"
  shift
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  find "$dir" -type f "$@" -print
}

{
  emit_find bootstrap/seed \( -name '*.hc' -o -name '*.HC' -o -name '*.HH' -o -name '*.hh' \)
  emit_find bootstrap/hc_repl \( -name '*.hc' -o -name '*.HC' -o -name '*.HH' -o -name '*.hh' \)
  emit_find Kernel \( \( -name '*RV*' -o -name '*Rv*' \) \( -name '*.hc' -o -name '*.HC' -o -name '*.HH' -o -name '*.hh' \) \)
  emit_find Kernel/Drv \( -name '*.hc' -o -name '*.HC' -o -name '*.HH' -o -name '*.hh' \)
  emit_find Compiler \( \( -name '*RV*' -o -name '*Rv*' \) \( -name '*.hc' -o -name '*.HC' -o -name '*.HH' -o -name '*.hh' \) \)
  # Adam RV HolyC at top level (MakeAdam_RV_Core.HC, StartOS_RV.HC, …)
  if [[ -d Adam ]]; then
    find Adam -maxdepth 1 -type f \( -name '*RV*' -o -name '*_RV*' \) \
      \( -name '*.hc' -o -name '*.HC' -o -name '*.HH' -o -name '*.hh' \) -print
  fi
  emit_find tests/exec/cases \( -name '*.hc' -o -name '*.HC' \)
  emit_find tests/fmt/golden \( -name '*.hc' -o -name '*.HC' \)
} | sort -u | while IFS= read -r f; do
  base="$(basename "$f")"
  if excluded_basename "$base"; then
    continue
  fi
  # Never enforce on intentional ugly golden inputs
  case "$f" in
    tests/fmt/cases/*) continue ;;
    tests/scratch/*) continue ;;
  esac
  if is_holyc "$f"; then
    printf '%s\n' "$f"
  fi
done
