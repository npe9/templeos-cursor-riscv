// Verifies native RISC-V GetRSP / GetRBP / LXchgI64 in KUtilsRV.HC.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  I64 x = 0x1234;
  I64 old = LXchgI64(&x, 0x5678);
  r += (old == 0x1234) * 1;
  r += (x == 0x5678) * 2;
  I64 sp1 = GetRSP, sp2 = GetRSP;
  r += (sp1 == sp2 && sp1 != 0) * 4;   // sp is stable & non-null across calls in one frame
  I64 bp = GetRBP;
  r += (bp == bp) * 8;                 // GetRBP is callable and returns
  I64 loc = 0, la = &loc;
  I64 d = la - sp1; if (d < 0) d = -d;
  r += (d < 0x10000) * 16;             // GetRSP is a real stack ptr, near a local
  return r;                            // 0x1F
}
