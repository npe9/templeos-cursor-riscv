#!/usr/bin/env bash
# Compiler codegen semantics stress: curated exec oracles + negatives + soft pattern checks.
# Guest ExePutS / Compiler_RV remain covered by qemu-integration (kernel-exepubs / phase3);
# set STRESS_GUEST=1 to also invoke those smokes from this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOLYC="${HOLYC:-$ROOT/holyc-riscv}"
OUTDIR="$ROOT/build/stress/compiler"
ORACLE_MANIFEST="${COMPILER_STRESS_ORACLE:-$ROOT/tests/compiler/stress_oracle.tsv}"
NEG_DIR="$ROOT/tests/compiler/negative"
PAT_MANIFEST="${COMPILER_STRESS_PATTERNS:-$ROOT/tests/compiler/patterns.tsv}"
PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf-}"
OBJDUMP="${PREFIX}objdump"

mkdir -p "$OUTDIR"

if [ ! -f "$HOLYC" ]; then
  make -C "$ROOT" holyc-riscv >/dev/null
fi

pass=0
fail=0
warn=0

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Compiler stress (exec oracles + negatives + pattern soft checks)    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo "Compiler: $HOLYC"
echo "Oracle:   $ORACLE_MANIFEST"
echo ""

# --- Execute oracles (reuse harness) ---
if [ -f "$ORACLE_MANIFEST" ]; then
  echo "── execute oracles ──"
  set +e
  ORACLE_MANIFEST="$ORACLE_MANIFEST" "$ROOT/tests/scripts/run_exec_oracles.sh"
  orc=$?
  set -e
  if [ "$orc" -eq 0 ]; then
    echo "OK   exec-oracle subset"
    pass=$((pass + 1))
  elif [ "$orc" -eq 2 ]; then
    echo "FAIL exec-oracle subset — missing tools"
    fail=$((fail + 1))
  else
    echo "FAIL exec-oracle subset"
    fail=$((fail + 1))
  fi
else
  echo "FAIL missing $ORACLE_MANIFEST"
  fail=$((fail + 1))
fi

# --- Negative compiles ---
echo ""
echo "── negative compiles ──"
shopt -s nullglob
neg_any=0
for f in "$NEG_DIR"/*.hc; do
  neg_any=1
  base="$(basename "$f")"
  set +e
  "$HOLYC" "$f" -o "$OUTDIR/${base}.bin" >"$OUTDIR/${base}.out" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "OK   neg:$base (rejected)"
    pass=$((pass + 1))
  else
    echo "FAIL neg:$base — expected compile failure"
    fail=$((fail + 1))
  fi
done
shopt -u nullglob
if [ "$neg_any" -eq 0 ]; then
  echo "FAIL no negatives under $NEG_DIR"
  fail=$((fail + 1))
fi

# --- Optional pattern checks (soft|hard) ---
echo ""
echo "── pattern checks ──"
if [ -f "$PAT_MANIFEST" ] && command -v "$OBJDUMP" >/dev/null 2>&1; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      \#*|"") continue ;;
    esac
    line="${line%$'\r'}"
    IFS=$'\t' read -r name src _pat mode <<<"$line"
    [ -z "${name:-}" ] && continue
    mode="${mode:-soft}"
    fpath="$ROOT/$src"
    if [ ! -f "$fpath" ]; then
      echo "FAIL pat:$name — missing $src"
      fail=$((fail + 1))
      continue
    fi
    if ! "$HOLYC" "$fpath" -o "$OUTDIR/pat_${name}.bin" >"$OUTDIR/pat_${name}.out" 2>&1; then
      echo "FAIL pat:$name — compile error"
      fail=$((fail + 1))
      continue
    fi
    "$OBJDUMP" -D -b binary -m riscv:rv64 "$OUTDIR/pat_${name}.bin" \
      >"$OUTDIR/pat_${name}.dis" 2>/dev/null || true
    # Detect consecutive slli then srli. Hard rows forbid *useless* zext (clean lo);
    # bit31 U32 VA zext is intentional — keep that case out of hard patterns.
    hit=0
    if awk '
      /slli/ { prev=1; next }
      prev && /srli/ { found=1; exit }
      { prev=0 }
      END { exit found ? 0 : 1 }
    ' "$OUTDIR/pat_${name}.dis"; then
      hit=1
    fi
    if [ "$hit" -eq 1 ]; then
      if [ "$mode" = "hard" ]; then
        echo "FAIL pat:$name — forbidden slli;srli pair present"
        fail=$((fail + 1))
      else
        echo "WARN pat:$name — soft slli;srli still present"
        warn=$((warn + 1))
        pass=$((pass + 1))
      fi
    else
      echo "OK   pat:$name (no slli;srli pair)"
      pass=$((pass + 1))
    fi
  done <"$PAT_MANIFEST"

  # ICF_ASSIGN_ZERO: *p=0 must emit sd zero (and must not resurrect dead push/discard alone).
  sz_src="$ROOT/tests/compiler/cases/c_ptr_store_zero.hc"
  if [ -f "$sz_src" ]; then
    if "$HOLYC" "$sz_src" -o "$OUTDIR/pat_ptr_store_zero.bin" >"$OUTDIR/pat_ptr_store_zero.out" 2>&1; then
      "$OBJDUMP" -D -b binary -m riscv:rv64 "$OUTDIR/pat_ptr_store_zero.bin" \
        >"$OUTDIR/pat_ptr_store_zero.dis" 2>/dev/null || true
      if grep -Eq 'sd[[:space:]]+zero,' "$OUTDIR/pat_ptr_store_zero.dis"; then
        if grep -Eq 'addi[[:space:]]+t0,a0,0|mv[[:space:]]+t0,a0' "$OUTDIR/pat_ptr_store_zero.dis"; then
          echo "FAIL pat:ptr_store_zero — useless mv/addi t0,a0 before sd zero"
          fail=$((fail + 1))
        else
          echo "OK   pat:ptr_store_zero (sd zero, no addi t0,a0)"
          pass=$((pass + 1))
        fi
      else
        echo "FAIL pat:ptr_store_zero — expected sd zero in *p=0 codegen"
        fail=$((fail + 1))
      fi
    else
      echo "FAIL pat:ptr_store_zero — compile error"
      fail=$((fail + 1))
    fi
  fi

  # PjPutHex-style indexed store: sb must use address in t0 (not sb a0,0(a0)).
  idx_src="$ROOT/tests/compiler/cases/c_idx_store_sb.hc"
  if [ -f "$idx_src" ]; then
    if "$HOLYC" "$idx_src" -o "$OUTDIR/pat_idx_store_sb.bin" >"$OUTDIR/pat_idx_store_sb.out" 2>&1; then
      "$OBJDUMP" -D -b binary -m riscv:rv64 "$OUTDIR/pat_idx_store_sb.bin" \
        >"$OUTDIR/pat_idx_store_sb.dis" 2>/dev/null || true
      if grep -Eq 'sb[[:space:]]+a0,0\(a0\)' "$OUTDIR/pat_idx_store_sb.dis"; then
        echo "FAIL pat:idx_store_sb — sb a0,0(a0) (PjPutHex-class miscompile)"
        fail=$((fail + 1))
      elif grep -Eq 'sb[[:space:]]+a0,0\(t0\)' "$OUTDIR/pat_idx_store_sb.dis"; then
        echo "OK   pat:idx_store_sb (sb a0,0(t0))"
        pass=$((pass + 1))
      else
        echo "FAIL pat:idx_store_sb — expected sb a0,0(t0)"
        fail=$((fail + 1))
      fi
    else
      echo "FAIL pat:idx_store_sb — compile error"
      fail=$((fail + 1))
    fi
  fi

  # CR/LF: if (x=='\r'||x=='\n') must compare-and-branch on 13/10, no bool push/pop/sub/seqz.
  crlf_src="$ROOT/tests/compiler/cases/c_crlf_or.hc"
  if [ -f "$crlf_src" ]; then
    if "$HOLYC" "$crlf_src" -o "$OUTDIR/pat_crlf_or.bin" >"$OUTDIR/pat_crlf_or.out" 2>&1; then
      "$OBJDUMP" -D -b binary -m riscv:rv64 "$OUTDIR/pat_crlf_or.bin" \
        >"$OUTDIR/pat_crlf_or.dis" 2>/dev/null || true
      dis="$OUTDIR/pat_crlf_or.dis"
      # Condition core with bool elision: ld/li/b<cc> a0,t1 ×2 + j (no bool 0/1).
      # Branch POLARITY is deliberately not pinned. EmitBrRsRs/EmitCondBranch emit
      # fixed-width branches (inverted b<cc> over a j) instead of range-relaxed short
      # B-type: ±4KB oscillation prevented AOT convergence on Kernel+Compiler blobs
      # (pass cap → stale labels). So `bne a0,t1` + `j` is intended codegen here —
      # do NOT "fix" the emitter back to a single `beq`. The property under test is
      # real compare-and-branch against the literal in t1, not which way it jumps.
      n_br=$(grep -cE 'b(eq|ne)[[:space:]]+a0,t1' "$dis" || true)
      n_li13=$(grep -cE 'li[[:space:]]+t1,13' "$dis" || true)
      n_li10=$(grep -cE 'li[[:space:]]+t1,10' "$dis" || true)
      n_seqz=$(grep -cE 'seqz[[:space:]]' "$dis" || true)
      n_sub=$(grep -cE 'sub[[:space:]]+a0,t0,t1' "$dis" || true)
      n_beqz=$(grep -cE 'beqz[[:space:]]' "$dis" || true)
      # Budget 12 words: range-relaxed form ≈7, fixed-width form = 8; headroom for
      # prologue drift, but far below any bool-materializing lowering.
      core=$(awk '
        /li[[:space:]]+t1,13/ {start=NR-1; if(start<1) start=1; seen13=1}
        start && seen13 && (/j[[:space:]]/ && NR>start+3) {
          print NR-start+1; exit
        }
      ' "$dis")
      if [ "${n_li13:-0}" -ge 1 ] && [ "${n_li10:-0}" -ge 1 ] && [ "${n_br:-0}" -ge 2 ] &&
         [ "${n_seqz:-0}" -eq 0 ] && [ "${n_sub:-0}" -eq 0 ] && [ "${n_beqz:-0}" -eq 0 ] &&
         [ "${core:-99}" -le 12 ]; then
        echo "OK   pat:crlf_or (b<cc> a0,t1 ×2 imm13/10, core=${core} insn, no seqz/sub/beqz)"
        pass=$((pass + 1))
      else
        echo "FAIL pat:crlf_or — want beq|bne a0,t1 ×2 + li 13/10, no seqz/sub/beqz, core≤12 (got br=$n_br li13=$n_li13 li10=$n_li10 seqz=$n_seqz sub=$n_sub beqz=$n_beqz core=$core)"
        fail=$((fail + 1))
      fi
    else
      echo "FAIL pat:crlf_or — compile error"
      fail=$((fail + 1))
    fi
  fi
else
  echo "SKIP pattern checks (no manifest or $OBJDUMP)"
fi

# --- Optional guest path ---
if [ "${STRESS_GUEST:-0}" = "1" ]; then
  echo ""
  echo "── guest ExePutS (STRESS_GUEST=1) ──"
  set +e
  make -C "$ROOT" kernel-exepubs-smoke
  g1=$?
  make -C "$ROOT" kernel-phase3-smoke
  g2=$?
  set -e
  if [ "$g1" -eq 0 ] && [ "$g2" -eq 0 ]; then
    echo "OK   guest ExePutS + phase3"
    pass=$((pass + 1))
  else
    echo "FAIL guest smokes"
    fail=$((fail + 1))
  fi
else
  echo ""
  echo "NOTE guest ExePutS/Compiler_RV: covered by make qemu-integration"
  echo "     (kernel-exepubs-smoke, kernel-phase3-smoke). Set STRESS_GUEST=1 to re-run."
fi

echo ""
echo "── compiler-stress ──"
echo "  pass: $pass  fail: $fail  warn: $warn"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "✓ compiler-stress"
exit 0
