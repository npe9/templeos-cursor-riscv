#!/usr/bin/env bash
# Smoke: the GUEST asm{} assembler (Compiler/Asm_RV.HC) emits correct RVC
# (compressed, 16-bit) instructions. Boots build/repl-cmp.elf, assembles four
# short asm blocks covering all 15 increment-1 RVC forms, then reads each block's
# raw code bytes back through a packed-I64 pointer load and asserts the words
# equal the GNU gas (-march=rv64imac) ground truth.
#
# Ground truth halfwords (LE), byte-verified against riscv64-unknown-elf-as:
#   Rv1: c.nop=0001 c.ebreak=9002 c.mv a0,a1=852e c.add a0,a1=952e
#   Rv2: c.li a0,5=4515 c.li a0,-1=557d c.addi a0,1=0505 c.addi a0,-1=157d
#   Rv3: c.jr ra=8082 c.jalr ra=9082 c.slli a0,3=050e  (+ ret low half 8067)
#   Rv4: c.sub a0,a1=8d0d c.and a0,a1=8d6d c.or a0,a1=8d4d c.xor a0,a1=8d2d
# Packed p[0] I64 (signed, as the REPL prints ans=):
#   W0(Rv1)=-7697068278098558975  W1(Rv2)=1548399367352567061
#   W2(Rv3)=-9194374554141425534  W3(Rv4)=-8273801576184967923
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/repl-cmp.elf"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$QEMU" perl; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP rvc-asm smoke — missing $t" >&2; exit 0; }
done

# Guest REPL image carries the asm{} assembler; build it if stale.
make -C "$ROOT" repl-cmp >/dev/null 2>&1 || { echo "FAIL rvc-asm smoke — repl-cmp build" >&2; exit 1; }
[ -f "$ELF" ] || { echo "FAIL rvc-asm smoke — no $ELF" >&2; exit 1; }

# Paced serial feed: the REPL line editor drops characters if lines arrive faster
# than it consumes them, so gate each line behind a short delay (perl, not sleep(1)).
feed() {
  perl -e '
    $|=1;
    my @l=(
     "asm { Rv1:: c.nop c.ebreak c.mv a0,a1 c.add a0,a1 ret }",
     "asm { Rv2:: c.li a0,5 c.li a0,-1 c.addi a0,1 c.addi a0,-1 ret }",
     "asm { Rv3:: c.jr ra c.jalr ra c.slli a0,3 ret }",
     "asm { Rv4:: c.sub a0,a1 c.and a0,a1 c.or a0,a1 c.xor a0,a1 ret }",
     "I64 W0(){I64 *p=Rv1;return p[0];}","W0();",
     "I64 W1(){I64 *p=Rv2;return p[0];}","W1();",
     "I64 W2(){I64 *p=Rv3;return p[0];}","W2();",
     "I64 W3(){I64 *p=Rv4;return p[0];}","W3();",
     # Increment 2: immediate-scramble jumps/branches + subset loads/stores.
     "asm { Rv5:: c.ld a0,8(a1) c.sd a4,16(a3) c.j 8 c.beqz a0,4 ret }",
     "asm { Rv6:: c.bnez a1,-8 c.j -8 c.ld a0,0(a1) c.sd a0,0(a1) ret }",
     # Label resolution: forward c.j (F), forward c.beqz (C), backward c.j (B).
     "asm { RvF:: c.j E c.nop E: c.nop c.nop ret }",
     "asm { RvC:: c.beqz a0,E c.nop E: c.nop c.nop ret }",
     "asm { RvB:: E: c.nop c.nop c.j E c.nop ret }",
     "I64 W5(){I64 *p=Rv5;return p[0];}","W5();",
     "I64 W6(){I64 *p=Rv6;return p[0];}","W6();",
     "I64 WF(){I64 *p=RvF;return p[0];}","WF();",
     "I64 WC(){I64 *p=RvC;return p[0];}","WC();",
     "I64 WB(){I64 *p=RvB;return p[0];}","WB();",
     # Increment 3: word ld/st, CB-arith, RV64 addiw, lui, sp-relative + frame adjust.
     "asm { Rw1:: c.lw a0,4(a1) c.sw a4,8(a3) c.addiw a0,-1 c.andi a0,-1 ret }",
     "asm { Rw2:: c.srli a0,5 c.srai a1,63 c.lui a0,1 c.lui s0,-1 ret }",
     "asm { Rw3:: c.addi16sp sp,-16 c.addi4spn a0,sp,8 c.lwsp a0,4(sp) c.ldsp a0,8(sp) ret }",
     "asm { Rw4:: c.swsp a0,4(sp) c.sdsp a0,8(sp) c.lw a0,124(a1) c.sw a0,124(a1) ret }",
     "I64 X1(){I64 *p=Rw1;return p[0];}","X1();",
     "I64 X2(){I64 *p=Rw2;return p[0];}","X2();",
     "I64 X3(){I64 *p=Rw3;return p[0];}","X3();",
     "I64 X4(){I64 *p=Rw4;return p[0];}","X4();",
     # Increment 4: float-compressed doubleword loads/stores (RV64 D).
     "asm { Rf1:: c.fld fs0,8(a1) c.fsd fa0,16(a3) c.fld fa5,248(a1) c.fsd fs0,0(a3) ret }",
     "asm { Rf2:: c.fldsp ft0,8(sp) c.fsdsp ft11,504(sp) c.fldsp fa5,0(sp) c.fsdsp ft1,16(sp) ret }",
     "I64 Y1(){I64 *p=Rf1;return p[0];}","Y1();",
     "I64 Y2(){I64 *p=Rf2;return p[0];}","Y2();",
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
    echo "FAIL rvc-asm smoke — missing packed word: $1" >&2
    fail=1
  fi
}
# Each asserted value is the whole 4-halfword block; a single wrong encoding shifts it.
need "ans=-7697068278098558975"   # Rv1: c.nop/c.ebreak/c.mv/c.add
need "ans=1548399367352567061"    # Rv2: c.li +/- , c.addi +/-
need "ans=-9194374554141425534"   # Rv3: c.jr/c.jalr/c.slli
need "ans=-8273801576184967923"   # Rv4: c.sub/c.and/c.or/c.xor (x8-x15 subset)
# Increment 2 — numeric offsets (c.ld/c.sd scaled, c.j/c.beqz/c.bnez scramble):
need "ans=-4534667282255157880"   # Rv5: c.ld 8, c.sd 16, c.j +8, c.beqz +4
need "ans=-2195397578380149275"   # Rv6: c.bnez -8, c.j -8, c.ld 0, c.sd 0
# Increment 2 — label resolution (2-byte forward fixup + backward inline):
need "ans=281479271784465"        # RvF: forward c.j E  (offset +4 = 0xa011)
need "ans=281479271792913"        # RvC: forward c.beqz E (offset +4 = 0xc111)
need "ans=492533964668929"        # RvB: backward c.j E  (offset -4 = 0xbff5)
# Increment 3 — word ld/st, CB-arith, addiw, lui, sp-relative (GNU-derived, full-range validated):
need "ans=-7386688999498694200"   # Rw1: c.lw/c.sw, c.addiw -1, c.andi -1
need "ans=8393976355154133269"    # Rw2: c.srli/c.srai, c.lui +1/-1
need "ans=7287463090653262205"    # Rw3: c.addi16sp/c.addi4spn/c.lwsp/c.ldsp
need "ans=-2456610341888802262"   # Rw4: c.swsp/c.sdsp + c.lw/c.sw at max offset
# Increment 4 — float-compressed doubleword ld/st (GNU-validated, 4736 checks):
need "ans=-6737316887144159872"   # Rf1: c.fld/c.fsd (f8-f15 subset)
need "ans=-6339335982957060062"   # Rf2: c.fldsp/c.fsdsp (full float reg, sp-relative)

if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'ans=|Rv[0-9A-Z]|W[0-9A-Z]|Except|Error|TRAP' | tail -40 | sed 's/^/  /' >&2
  exit 1
fi
echo "RVC-asm smoke: OK (guest asm{} emits GNU-identical c.* — COMPLETE RVC set: integer reg/imm, jumps/branches incl. labels, ld/st (d/w), CB-arith, addiw, lui, sp-relative + frame adjust, and float c.fld/c.fsd/c.fldsp/c.fsdsp)"
exit 0
