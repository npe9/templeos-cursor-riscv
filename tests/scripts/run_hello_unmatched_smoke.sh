#!/bin/bash
# Build + gate tests/exec/harness/hello_unmatched.S — the minimal FU740 JTAG payload.
#
# Runs it on -M sifive_u, which models the same 1x management core + U54/U74 split as
# the FU740 (cpu 0 = sifive-e51 = rv64imac, cpu 1 = sifive-u54 = rv64gc). Both harts are
# exercised, because they must give DIFFERENT answers:
#
#   hart 1 (U54/U74): misa.D set   -> FPU probe runs -> "hello-unmatched: OK"
#   hart 0 (E51/S7):  misa.D clear -> names the wrong hart, no OK line
#
# That asymmetry is the gate. A payload that printed OK on both would not be telling
# you anything about the hart you are on, which is the single most likely way for a
# perfectly good TempleOS/RV image to look dead on this board.
#
# Artifacts: build/kernels/hifive_unmatched/hello.elf / hello.bin
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUT="$ROOT/build/kernels/hifive_unmatched"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
READELF="${RISCV_READELF:-riscv64-unknown-elf-readelf}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
ENTRY=0x80200000

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL hello-unmatched — missing $t" >&2; exit 1; }
done

mkdir -p "$OUT"
rm -f "$OUT/hello.o" "$OUT/hello.elf" "$OUT/hello.bin"
"$GCC" -march=rv64imafdc -mabi=lp64d -nostdlib -ffreestanding -fno-builtin \
  -c "$HARNESS/hello_unmatched.S" -o "$OUT/hello.o" \
  || { echo "FAIL hello-unmatched — assemble" >&2; exit 1; }
"$LD" -T "$HARNESS/link_hello_unmatched.ld" -nostdlib -o "$OUT/hello.elf" "$OUT/hello.o" \
  || { echo "FAIL hello-unmatched — link" >&2; exit 1; }
"$OBJCOPY" -O binary "$OUT/hello.elf" "$OUT/hello.bin" \
  || { echo "FAIL hello-unmatched — objcopy" >&2; exit 1; }

# The link address is the whole point of the payload; assert it rather than trust the .ld.
got_entry="$("$READELF" -h "$OUT/hello.elf" 2>/dev/null | sed -n 's/.*Entry point address: *//p')"
if [ -z "$got_entry" ] || [ "$((got_entry))" -ne "$((ENTRY))" ]; then
  echo "FAIL hello-unmatched — entry $got_entry != $ENTRY" >&2
  exit 1
fi
echo "hello-unmatched: $OUT/hello.bin ($(wc -c <"$OUT/hello.bin") bytes) entry $got_entry"

run_on() { # $1 = cpu-num
  $TIMEOUT 15 "$QEMU" -M sifive_u -smp 2 -bios none \
    -device "loader,file=$OUT/hello.bin,addr=$ENTRY" \
    -device "loader,addr=$ENTRY,cpu-num=$1" -nographic </dev/null 2>&1 | tr -d '\r'
}

rc=0

# --- U54/U74 hart: the positive case -------------------------------------------------
u="$(run_on 1)"
for n in "hello from the HiFive Unmatched" "hello: misa.D set" "hello: fadd.d 2.0+3.0 = 5" "hello-unmatched: OK"; do
  if ! printf '%s\n' "$u" | grep -qF "$n"; then
    echo "FAIL hello-unmatched (hart 1) — missing: $n" >&2
    printf '%s\n' "$u" | head -12 | sed 's/^/  got: /' >&2
    rc=1
  fi
done
[ "$rc" -eq 0 ] && echo "hello-unmatched (U54/U74 hart 1): OK — banner, misa.D, fadd.d 2+3=5"

# --- E51/S7 hart: must NOT claim OK, and must name the reason ------------------------
e="$(run_on 0)"
if printf '%s\n' "$e" | grep -qF "hello-unmatched: OK"; then
  echo "FAIL hello-unmatched (hart 0) — printed OK on the FPU-less management core;" >&2
  echo "  the misa.D check is not discriminating." >&2
  rc=1
elif ! printf '%s\n' "$e" | grep -qF "WRONG HART"; then
  echo "FAIL hello-unmatched (hart 0) — neither OK nor a WRONG HART diagnosis" >&2
  printf '%s\n' "$e" | head -12 | sed 's/^/  got: /' >&2
  rc=1
else
  echo "hello-unmatched (E51/S7 hart 0): correctly refuses — misa.D clear, WRONG HART"
fi

if [ "$rc" -eq 0 ]; then
  echo "hello-unmatched smoke: OK"
else
  echo "hello-unmatched smoke: FAIL" >&2
fi
exit "$rc"
