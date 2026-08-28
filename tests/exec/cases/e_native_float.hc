// Verifies native RISC-V Sqrt/Floor/Trunc/Round (RV64D) in KUtilsRV.HC. Negatives & halfway values
// are the discriminating cases: Floor(-2.5)=-3, Trunc(-2.5)=-2, Round(-2.5)=-3 (ties away from 0).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  if (Sqrt(16.0) == 4.0)                          r += 1;
  if (Sqrt(2.0) > 1.4142 && Sqrt(2.0) < 1.4143)   r += 2;
  if (Floor(-2.5) == -3.0)                        r += 4;
  if (Floor(2.7) == 2.0)                          r += 8;
  if (Trunc(-2.5) == -2.0)                        r += 16;
  if (Trunc(2.7) == 2.0)                          r += 32;
  if (Round(-2.5) == -3.0)                        r += 64;
  if (Round(2.5) == 3.0)                          r += 128;
  if (Round(-0.5) == -1.0)                        r += 256;
  if (Round(0.5) == 1.0)                          r += 512;
  return r;                                       // 0x3FF
}
