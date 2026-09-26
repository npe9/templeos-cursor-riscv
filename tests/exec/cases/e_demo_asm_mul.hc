// Demo/Asm/MulByHand.HC's shift-and-add multiply, translated x86 -> RISC-V, actually multiplies.
//
// Two functions with different lessons. The 8x8->16 one is Terry's Commodore-64 shift-and-add,
// which is machine-independent arithmetic written in machine-dependent code. The 64x64->128 one
// is where the ISAs genuinely differ: x86's MUL leaves a 128-bit product in the implicit pair
// RDX:RAX, while RV64M splits it into `mul` (low) and `mulhu` (high unsigned) — you ask for the
// second half by name.
//
// As with the division demo, the survey cannot check any of this: it compiles with
// RV_NO_DEMO_AUTORUN, which guards off the only call.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Asm/MulByHand.HC"
I64 opaque(I64 v) { return v; }
I64 main()
{
  U128 p;
  I64 r = 0;
  r += (MulU8(opaque(2), opaque(7)) == 14) * 1;
  r += (MulU8(opaque(100), opaque(10)) == 1000) * 2;      // 1000 > 255: the 16-bit result matters
  r += (MulU8(opaque(255), opaque(255)) == 65025) * 4;    // widest 8x8
  r += (MulU8(opaque(0), opaque(200)) == 0) * 8;
  r += (MulU8(opaque(1), opaque(37)) == 37) * 16;
  // 128-bit: the high half is the whole point, so check both halves.
  MulU64(opaque(0x0123456789ABCDEF), opaque(0x1000001), &p);
  r += (p.lo == 0x68ACF13578ABCDEF) * 32;
  r += (p.hi == 0x0000000000012345) * 64;
  // A product that is purely low, to be sure hi is cleared and not left over.
  MulU64(opaque(6), opaque(7), &p);
  r += (p.lo == 42 && p.hi == 0) * 128;
  return r;
  // 0xff
}
