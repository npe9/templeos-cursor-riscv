#!/usr/bin/env bash
# Export-fidelity stress for the HolyC REPL: mutate the memfs hard, then prove
# DumpChanges round-trips every dirty body off the box byte-for-byte.
#
# STATUS: UNVERIFIED — written but never executed. Expect to debug the guest-side
# quoting on first run.
#
# Why this shape: the smoke checks that DumpChanges *emits* frames. It does not
# check that what arrives equals what the guest holds. The interesting failures are
# (a) dirty-set collapse -- a file rewritten N times must export its LATEST body
# once, not N bodies or a stale one; and (b) FsLogCompact -- at FS_LOG_MAX (512)
# records FsJournal collapses the ring to the live dirty set and re-lays it, and
# the export must survive that with no lost or duplicated file.
#
# usage: tests/scratch/export_stress.sh
#        NFILE=24 NCHURN=600 tests/scratch/export_stress.sh   # force a compaction
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/repl-holyc.elf"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD="timeout"; command -v timeout >/dev/null 2>&1 || TIMEOUT_CMD=gtimeout

NFILE="${NFILE:-10}"     # distinct files
NCHURN="${NCHURN:-0}"    # extra rewrites of one file, to drive FsLogCompact

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
OUT="$W/recv"; EXP="$W/expect"; mkdir -p "$OUT" "$EXP"

if [ ! -f "$ELF" ]; then
  make -C "$ROOT" repl-holyc >/dev/null || { echo "FAIL: cannot build repl-holyc"; exit 2; }
fi

input=""
emit() { input+="$1"$'\n'; }

# Bodies stay single-line and quote-free: the REPL takes one compile unit per line,
# and an embedded double quote would terminate the HolyC string literal.
body_for() { printf 'stress-%s v%s tok=$LK,x$ end-%s' "$1" "$2" "$1"; }

emit 'MkDir("Home/st");'
for i in $(seq 1 "$NFILE"); do
  b="$(body_for "$i" 1)"
  printf '%s' "$b" > "$EXP/f$i.txt"
  emit "FileWrite(\"Home/st/f$i.txt\",\"$b\",${#b});"
done

# BSD seq counts DOWN when first > last (`seq 1 0` prints "1 0"), so every loop
# bound here must be guarded rather than relying on an empty range.
seq_up() { [ "$1" -ge 1 ] && seq 1 "$1"; }

# Rewrite the first half. Only the v2 body may come back.
for i in $(seq_up $((NFILE / 2))); do
  b="$(body_for "$i" 2)"
  printf '%s' "$b" > "$EXP/f$i.txt"
  emit "FileWrite(\"Home/st/f$i.txt\",\"$b\",${#b});"
done

# Churn one file to push the 512-record ring through FsLogCompact.
for i in $(seq_up "$NCHURN"); do
  b="churn-$i"
  emit "FileWrite(\"Home/st/churn.txt\",\"$b\",${#b});"
done
[ "$NCHURN" -gt 0 ] && printf 'churn-%s' "$NCHURN" > "$EXP/churn.txt"

emit 'FsChanges;'
emit 'DumpChanges;'
emit 'Print("STRESS_DONE\n");'

log="$W/stress.log"
printf '%s' "$input" | $TIMEOUT_CMD 300 "$QEMU" -M virt -m 128M -bios none \
  -kernel "$ELF" -nographic >"$log" 2>&1 || true

python3 "$ROOT/tools/uart_recv_dump.py" -o "$OUT" --keep-path <"$log" >"$W/recv.log" 2>&1

echo "--- manifest ---"
grep -a 'HC_CHANGES' "$log" | tail -2
echo "--- recovered ---"
find "$OUT" -type f | sed "s|$OUT/||" | sort | head -40

fail=0 checked=0
check() { # check <name>
  local want="$EXP/$1" got
  got="$(find "$OUT" -name "$1" | head -1)"
  if [ -z "$got" ]; then echo "MISSING $1"; fail=1; return; fi
  checked=$((checked + 1))
  if ! cmp -s "$got" "$want"; then
    echo "DIFF $1"
    echo "  want: $(cat "$want")"
    echo "  got : $(cat "$got")"
    fail=1
  fi
}
echo "--- byte compare ---"
for i in $(seq 1 "$NFILE"); do check "f$i.txt"; done
[ "$NCHURN" -gt 0 ] && check "churn.txt"

# A body must not arrive twice: dirty-set collapse is the property under test.
dupes="$(find "$OUT" -type f -exec basename {} \; | sort | uniq -d)"
if [ -n "$dupes" ]; then echo "DUPLICATE exports: $dupes"; fail=1; fi

grep -aq STRESS_DONE "$log" || { echo "WARN: guest did not reach end of script"; fail=1; }
echo "checked=$checked fail=$fail"
[ "$fail" -eq 0 ] && echo "export stress: OK"
exit "$fail"
