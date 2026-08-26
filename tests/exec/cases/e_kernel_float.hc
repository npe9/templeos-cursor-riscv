// The kernel's own StrPrintJoin %f float formatter runs on RISC-V and produces "3.2500".
// Regression guard for: an F64-element array decays to its address (an integer) and must NOT
// be typed F64 — otherwise passing it as an argument (StrPrintJoin's argv) mangles it to 0.
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){
  I64 j;
  pow10_I64 = CAlloc(sizeof(F64)*617, NULL);
  for (j=-308; j<=308; j++) pow10_I64[j+309] = Pow10(ToF64(j));
  U8 b[64];
  F64 a[1]; a[0] = 3.25;
  StrPrintJoin(b, "%.4f", 1, a);              // a is an F64 array passed as argv
  return (StrLen(b)==6)*1 + (b[0]=='3')*2 + (b[1]=='.')*4 +
         (b[2]=='2')*8 + (b[3]=='5')*16 + (b[4]=='0')*32;   // 0x3f
}
