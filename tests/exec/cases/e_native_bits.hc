// Verifies the native RISC-V bit-ops in Kernel/KUtilsRV.HC (Bt/Bts/Btr set-and-return-old on a byte
// array; Bsf/Bsr find lowest/highest set bit). Each check contributes a bit to the result.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U8 bf[16];
  I64 i;
  for (i = 0; i < 16; i++)
    bf[i] = 0;
  I64 r = 0;
  r += (Bts(bf, 5) == 0) * 1;
  // set bit 5, old 0
  r += (Bt(bf, 5) == 1) * 2;
  // now set
  r += (Bts(bf, 5) == 1) * 4;
  // set again, old 1
  r += (Btr(bf, 5) == 1) * 8;
  // reset, old 1
  r += (Bt(bf, 5) == 0) * 16;
  // now clear
  r += (Bts(bf, 12) == 0) * 32;
  // bit 12 = byte 1 bit 4
  r += (Bt(bf, 12) == 1) * 64;
  r += (Bsf(0x100) == 8) * 128;
  // lowest set bit
  r += (Bsr(0x100) == 8) * 256;
  // highest set bit
  r += (Bsf(0) == -1) * 512;
  // zero -> -1
  r += (Bsr(0xF0) == 7) * 1024;
  // highest of 0xF0
  r += (Bsf(0xF0) == 4) * 2048;
  // lowest of 0xF0
  return r;
  // all pass = 0xFFF
}
