// Verifies native RISC-V ModU64 / BFieldExtU32 / BFieldOrU32 in KUtilsRV.HC.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  U64 q = 100;
  I64 m = ModU64(&q, 7);           // 100/7=14 rem 2
  r += (m == 2) * 1;
  r += (q == 14) * 2;
  U8 buf[8];
  MemSet(buf, 0, 8);
  BFieldOrU32(buf, 4, 11);         // set bits 4..11 -> byte0=0xF0, byte1=0x0F
  r += (BFieldExtU32(buf, 4, 11) == 0xFF) * 4;
  r += (buf[0] == 0xF0) * 8;
  r += (buf[1] == 0x0F) * 16;
  r += (BFieldExtU32(buf, 6, 9) == 0xF) * 32;   // middle 4 bits
  U64 q2 = 55;
  I64 m0 = ModU64(&q2, 0);         // d==0 guard
  r += (m0 == 0 && q2 == 55) * 64;
  return r;                        // 0x7F
}
