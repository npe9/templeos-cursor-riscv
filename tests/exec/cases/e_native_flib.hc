// Verifies the native RISC-V FPU float library in KUtilsRV.HC: Exp/Ln (hand-written FPU asm) and the
// Log2/Log10/Pow10/Pow compositions. Tolerance checks (transcendentals are ~1 ULP, FMA-dependent).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  F64 d;
  if (Exp(0.0) == 1.0)                                       r += 1;
  d = Exp(2.0) - 7.38905609893065;      if (d < 0.0) d = -d; if (d < 1e-9)  r += 2;
  if (Ln(1.0) == 0.0)                                        r += 4;
  d = Ln(10.0) - 2.302585092994046;     if (d < 0.0) d = -d; if (d < 1e-11) r += 8;
  d = Log2(1024.0) - 10.0;              if (d < 0.0) d = -d; if (d < 1e-11) r += 16;
  d = Log10(1000000.0) - 6.0;           if (d < 0.0) d = -d; if (d < 1e-11) r += 32;
  d = Pow10(3.0) - 1000.0;             if (d < 0.0) d = -d; if (d < 1e-6)  r += 64;
  d = Pow(2.0, 10.0) - 1024.0;         if (d < 0.0) d = -d; if (d < 1e-9)  r += 128;
  d = Pow(9.0, 0.5) - 3.0;             if (d < 0.0) d = -d; if (d < 1e-12) r += 256;
  if (Pow(5.0, 0.0) == 1.0)                                 r += 512;
  return r;   // 0x3FF
}
