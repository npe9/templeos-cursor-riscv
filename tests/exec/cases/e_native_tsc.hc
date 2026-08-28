// Verifies native RISC-V GetTSC (rdtime CSR) in KUtilsRV.HC: monotonic, non-zero, advances.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  I64 t1 = GetTSC;
  I64 t2 = GetTSC;
  if (t1 != 0) r += 1;
  if (t2 >= t1) r += 2;              // monotonic non-decreasing
  I64 s = 0, i = 0;
  while (i < 2000000) { s += i; i++; }
  I64 t3 = GetTSC;
  if (t3 > t1) r += 4;              // mtime advanced during the busy loop
  if (s != 0) r += 8;              // loop not optimized away
  return r;                        // 0xF
}
