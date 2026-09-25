#!/bin/bash
# The framebuffer-parity oracle (docs/FB_PARITY_PLAN.md phase 1).
#
# Runs tests/exec/cases/kernel_gr_scenes.hc, which draws a fixed picture into an OFFSCREEN 8-bit DC
# per primitive and hashes the bitmap, and diffs the hashes against tests/gr_scene_hashes.tsv.
#
# Why it exists: every phase of the parity plan replaces part of Kernel/RVGr.HC with stock
# Adam/Gr code, and without this the only way to notice a changed pixel is to look at a screenshot.
# A scene hash names the primitive.
#
#   make kernel-gr-scenes-smoke              diff against the pinned table
#   GR_SCENE_PIN=1 make kernel-gr-scenes-smoke   rewrite the table (say which moved, and why)
#
# The hashes ARE expected to move when a phase lands. A scene moving that the change does not
# explain is the finding — chase it, do not re-pin it.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
SRC="$ROOT/tests/exec/cases/kernel_gr_scenes.hc"
PINNED="$ROOT/tests/gr_scene_hashes.tsv"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
WAIT="${GR_SCENE_WAIT:-180}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-gr-scenes — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-gr-scenes — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-gr-scenes — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
if ! HOLYC_NO_TIER2=1 HOLYC_INCLUDE_ROOT="$ROOT" "$ROOT/holyc-riscv" "$SRC" -o "$T/blob.bin" >"$T/c.log" 2>&1; then
  echo "FAIL kernel-gr-scenes — compile error" >&2; tail -5 "$T/c.log" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch \
    -o k.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 \
  || { echo "FAIL kernel-gr-scenes — link error" >&2; exit 1; }

out="$($TIMEOUT "$WAIT" "$QEMU" -M virt -m 128M -bios none -kernel "$T/k.elf" -nographic \
       </dev/null 2>&1 | LC_ALL=C tr -d '\r')"

if printf '%s' "$out" | LC_ALL=C grep -aq '^TRAP '; then
  echo "FAIL kernel-gr-scenes — TRAP:" >&2
  printf '%s\n' "$out" | LC_ALL=C grep -a '^TRAP ' >&2
  printf '%s\n' "$out" | LC_ALL=C grep -a '^GRSCENE ' | tail -3 >&2
  echo "  (the scene AFTER the last one printed is the one that faulted;" >&2
  echo "   tools/traploc.sh names the function)" >&2
  exit 1
fi
printf '%s' "$out" | LC_ALL=C grep -aq 'GRSCENE-END' \
  || { echo "FAIL kernel-gr-scenes — did not reach GRSCENE-END in ${WAIT}s" >&2; exit 1; }

printf '%s\n' "$out" | LC_ALL=C sed -n 's/^GRSCENE \([a-z_0-9]*\) \([0-9A-F]*\)$/\1\t\2/p' > "$T/got.tsv"
[ -s "$T/got.tsv" ] || { echo "FAIL kernel-gr-scenes — no scene lines" >&2; exit 1; }

if [ "${GR_SCENE_PIN:-0}" = "1" ]; then
  { echo "# Framebuffer-parity scene hashes — docs/FB_PARITY_PLAN.md phase 1."
    echo "# FNV-1a over width_internal*height bytes of an offscreen 8-bit DC body, padding included."
    echo "# Regenerate: GR_SCENE_PIN=1 make kernel-gr-scenes-smoke"
    echo "# The x86 column is blank until someone boots stock TempleOS and runs the same case;"
    echo "# when it is filled, a row where the two differ IS the parity gap for that primitive."
    printf '#scene\trv_hash\tx86_hash\n'
    while IFS="$(printf '\t')" read -r s h; do printf '%s\t%s\t\n' "$s" "$h"; done < "$T/got.tsv"
  } > "$PINNED"
  echo "PINNED $(wc -l < "$T/got.tsv" | tr -d ' ') scene(s) → tests/gr_scene_hashes.tsv"
  exit 0
fi

[ -f "$PINNED" ] || { echo "FAIL kernel-gr-scenes — no pinned table; GR_SCENE_PIN=1 to create" >&2; exit 1; }
fail=0
while IFS="$(printf '\t')" read -r s h; do
  want="$(LC_ALL=C awk -F'\t' -v s="$s" '$1==s {print $2}' "$PINNED")"
  if [ -z "$want" ]; then
    echo "FAIL kernel-gr-scenes — scene '$s' is not in the pinned table" >&2; fail=1
  elif [ "$want" != "$h" ]; then
    echo "FAIL kernel-gr-scenes — $s: pinned $want got $h" >&2; fail=1
  fi
done < "$T/got.tsv"
# A scene that VANISHED is as much a change as one that moved — a primitive that stopped being
# exercised must not look like a pass. Compared with comm, not a `while` in a pipeline: the
# subshell there cannot set `fail` in the parent.
LC_ALL=C awk -F'\t' '!/^#/ && NF {print $1}' "$PINNED" | sort > "$T/want_names"
LC_ALL=C cut -f1 "$T/got.tsv" | sort > "$T/got_names"
missing="$(comm -23 "$T/want_names" "$T/got_names")"
if [ -n "$missing" ]; then
  for s in $missing; do echo "FAIL kernel-gr-scenes — pinned scene '$s' did not run" >&2; done
  fail=1
fi
[ "$fail" = 0 ] || exit 1
echo "PASS kernel-gr-scenes — $(wc -l < "$T/got.tsv" | tr -d ' ') scenes match the pinned table"
