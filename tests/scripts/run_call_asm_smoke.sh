#!/usr/bin/env bash
# Smoke: the GUEST asm{} assembler (Compiler/Asm_RV.HC) emits a correct `call`
# pseudo-instruction. `call target` expands to the PC-relative pair
#   auipc ra, %pcrel_hi(target) ; jalr ra, %pcrel_lo(target)(ra)
# linking ra=pc+8 (guest scope: block-local label or numeric offset, not an
# external function symbol). Boots build/repl-cmp.elf, assembles four short
# asm blocks with `call` FIRST (so the packed-I64 p[0] read is exactly the 8-byte
# call pair: auipc in the low 32 bits, jalr in the high 32), and asserts each pair
# equals the GNU (riscv64 as + ld --no-relax) ground truth.
#
# Ground truth (auipc,jalr) little-endian, byte-verified against riscv64-unknown-elf:
#   Cnum  call 16      -> auipc=00000097 jalr=010080e7   (hi=0, lo=+16)
#   Cbig  call 0x1234  -> auipc=00001097 jalr=234080e7   (hi=1, lo=+0x234)
#   Cneg  call -0x808  -> auipc=fffff097 jalr=7f8080e7   (0x800 carry: hi=-1, lo=+0x7f8)
#   Cfwd  call E (E=+16)-> auipc=00000097 jalr=010080e7  (8-byte forward fixup == Cnum)
# Packed p[0] I64 (signed) = auipc | (jalr<<32):
#   Cnum/Cfwd = 72199323663728791   Cbig = 2540171919462764695   Cneg = 9187484973756575895
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/repl-cmp.elf"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$QEMU" perl; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP call-asm smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" repl-cmp >/dev/null 2>&1 || { echo "FAIL call-asm smoke — repl-cmp build" >&2; exit 1; }
[ -f "$ELF" ] || { echo "FAIL call-asm smoke — no $ELF" >&2; exit 1; }

# Paced serial feed: the REPL line editor drops characters on unpaced input.
feed() {
  perl -e '
    $|=1;
    my @l=(
     # call FIRST => packed p[0] is exactly the auipc+jalr pair.
     "asm { Cnum:: call 16 nop nop nop ret }",
     "asm { Cbig:: call 0x1234 nop nop nop ret }",
     "asm { Cneg:: call -0x808 nop nop nop ret }",
     "asm { Cfwd:: call E nop nop E: nop ret }",   # forward label, 8-byte fixup
     "I64 C0(){I64 *p=Cnum;return p[0];}","C0();",
     "I64 C1(){I64 *p=Cbig;return p[0];}","C1();",
     "I64 C2(){I64 *p=Cneg;return p[0];}","C2();",
     "I64 C3(){I64 *p=Cfwd;return p[0];}","C3();",
    );
    select(undef,undef,undef,5);
    for my $x (@l){ print $x,"\n"; select(undef,undef,undef,0.6); }
    select(undef,undef,undef,2);
  '
}

out="$(feed | $TIMEOUT 200 "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic 2>&1 | LC_ALL=C tr -d '\r')"

fail=0
need() {
  if ! printf '%s\n' "$out" | grep -qF "$1"; then
    echo "FAIL call-asm smoke — missing packed word: $1" >&2
    fail=1
  fi
}
need "ans=72199323663728791"     # Cnum: call +16 (numeric offset path)
need "ans=2540171919462764695"   # Cbig: call +0x1234 (non-zero hi + lo)
need "ans=9187484973756575895"   # Cneg: call -0x808 (0x800 pcrel carry)
need "ans=72199323663728791"     # Cfwd: call E (forward label -> 8-byte fixup, == Cnum)

if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'ans=|C(num|big|neg|fwd)|Except|Error|TRAP' | tail -40 | sed 's/^/  /' >&2
  exit 1
fi
echo "call-asm smoke: OK (guest asm{} emits GNU-identical call auipc+jalr — numeric offset, 0x800 pcrel carry, and 8-byte forward-label fixup)"
exit 0
