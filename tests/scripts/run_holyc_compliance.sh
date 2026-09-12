#!/bin/bash
# HolyC language compliance runner (compile + optional minimum code size).
# Manifest columns (tab-separated): path, category, expect, min_code_bytes
#   expect: pass | pass_any | xfail
#   min_code_bytes: empty = default for pass (48), 0 = skip size check
#
# Suites: --suite syntax | corpus | parity | all
#   parity: tests/holyc/compliance/manifest_parity.tsv (TempleOS/x86 HolyC–style compile coverage)

set -u

SUITE="all"
STRICT_XPASS=0
QUIET=0
RUN_EXEC_ORACLE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --suite)
      SUITE="$2"
      shift 2
      ;;
    --strict-xpass)
      STRICT_XPASS=1
      shift
      ;;
    --quiet|-q)
      QUIET=1
      shift
      ;;
    --exec)
      RUN_EXEC_ORACLE=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 1

HOLYC="$ROOT/holyc-riscv"
DEFAULT_MIN=48

if [ ! -x "$HOLYC" ] && [ -f "$HOLYC" ]; then
  chmod +x "$HOLYC" 2>/dev/null || true
fi

if [ ! -f "$HOLYC" ]; then
  echo "Building holyc-riscv..." >&2
  make -C "$ROOT" holyc-riscv >/dev/null || exit 1
fi

if [ ! -f "$HOLYC" ]; then
  echo "error: $HOLYC not found after build" >&2
  exit 1
fi

run_manifest() {
  local manifest="$1"
  local label="$2"
  [ -f "$manifest" ] || return 0

  local pass=0 fail=0 xpass=0 xfail_ok=0
  local line_no=0

  _log() {
    if [ "$QUIET" -eq 0 ] || [ "${2:-0}" -eq 1 ]; then
      echo "$1"
    fi
  }

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    case "$line" in
      \#*|"") continue ;;
    esac

    IFS=$'\t' read -r relpath category expect minbytes <<<"$line"
    if [ -z "${relpath:-}" ]; then
      continue
    fi

    expect="${expect:-pass}"
    minbytes="${minbytes:-}"

    if [ "$expect" = "pass" ] && [ -z "$minbytes" ]; then
      minbytes="$DEFAULT_MIN"
    fi
    if [ "$expect" = "pass_any" ]; then
      minbytes=0
      expect=pass
    fi

    local fpath="$ROOT/$relpath"
    if [ ! -f "$fpath" ]; then
      echo "MISSING $relpath ($label line $line_no)" >&2
      fail=$((fail + 1))
      continue
    fi

    local out
    # HOLYC_PRINT_SIZE: `-o` puts the compiler in quiet mode, so the "Code size:"
    # line parsed below is otherwise suppressed and every case reads as size 0.
    out="$(HOLYC_PRINT_SIZE=1 "$HOLYC" "$fpath" -o /tmp/holyc_compliance_$$.bin 2>&1)"
    local rc=$?
    local sz
    sz="$(echo "$out" | sed -n 's/.*Code size: \([0-9][0-9]*\).*/\1/p' | tail -1)"
    [ -n "$sz" ] || sz=0

    local ok_compile=0
    if [ $rc -eq 0 ]; then
      ok_compile=1
    fi

    case "$expect" in
      pass)
        if [ $ok_compile -ne 1 ]; then
          _log "FAIL $relpath ($category) — compile error" 1
          [ "$QUIET" -eq 1 ] && echo "$out" | tail -8 >&2
          fail=$((fail + 1))
        elif [ -n "$minbytes" ] && [ "$minbytes" -gt 0 ] && [ "$sz" -lt "$minbytes" ]; then
          _log "FAIL $relpath ($category) — code size $sz < min $minbytes" 1
          fail=$((fail + 1))
        else
          _log "OK   $relpath ($category) size=$sz" 0
          pass=$((pass + 1))
        fi
        ;;
      xfail)
        if [ $ok_compile -eq 1 ]; then
          if [ "$STRICT_XPASS" -eq 1 ]; then
            _log "XPASS $relpath ($category) — expected fail, got size=$sz" 1
            fail=$((fail + 1))
          else
            _log "XPASS $relpath ($category) size=$sz (allowed)" 0
            xpass=$((xpass + 1))
          fi
        else
          _log "XFAIL $relpath ($category) (expected)" 0
          xfail_ok=$((xfail_ok + 1))
        fi
        ;;
      *)
        echo "error: bad expect '$expect' in $manifest line $line_no" >&2
        exit 2
        ;;
    esac
  done <"$manifest"

  echo ""
  echo "── $label ──"
  echo "  pass: $pass  fail: $fail  xfail_ok: $xfail_ok  xpass: $xpass"
  TOTAL_FAIL=$((TOTAL_FAIL + fail))
  return 0
}

TOTAL_FAIL=0

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  HolyC ↔ TempleOS language compliance (host compile checks)          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo "Compiler: $HOLYC"
echo "Suite:    $SUITE"
echo ""

if [ "$SUITE" = "syntax" ] || [ "$SUITE" = "all" ]; then
  run_manifest "$ROOT/tests/holyc/compliance/manifest_syntax.tsv" "Syntax / feature matrix"
fi

if [ "$SUITE" = "corpus" ] || [ "$SUITE" = "all" ]; then
  run_manifest "$ROOT/tests/holyc/compliance/manifest_templeos_tree.tsv" "TempleOS tree (curated .HC)"
fi

if [ "$SUITE" = "parity" ] || [ "$SUITE" = "all" ]; then
  run_manifest "$ROOT/tests/holyc/compliance/manifest_parity.tsv" "x86 HolyC–style parity (compile)"
fi

echo ""
EXEC_FAIL=0
if [ "$RUN_EXEC_ORACLE" -eq 1 ]; then
  echo ""
  chmod +x "$ROOT/tests/scripts/run_exec_oracles.sh" 2>/dev/null || true
  if ! "$ROOT/tests/scripts/run_exec_oracles.sh"; then
    EXEC_FAIL=1
  fi
fi

if [ "$TOTAL_FAIL" -eq 0 ] && [ "$EXEC_FAIL" -eq 0 ]; then
  echo "Compliance run: OK (no required failures)"
  exit 0
fi
if [ "$TOTAL_FAIL" -ne 0 ]; then
  echo "Compliance run: FAILED ($TOTAL_FAIL compile manifest failure(s))"
fi
if [ "$EXEC_FAIL" -ne 0 ]; then
  echo "Compliance run: FAILED (execution oracle suite)"
fi
exit 1
