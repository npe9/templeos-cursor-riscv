// Exercises several real TempleOS kernel functions end to end (Str2I64, StrPrintHex, Str*, math).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U8 a[32], b[32];
  StrCpy(a, "HolyC");
  StrPrintHex(b, 0xBEEF, 4);
  return (Str2I64("255", 10, NULL) == 255) * 1 + (Str2I64("0x10", 16, NULL) == 16) * 2 + (StrLen(a) == 5) * 4 + (StrCmp(a, "HolyC") == 0) * 8 + (b[0] == 'B' && b[3] == 'F') * 16 + (ToI64(Sqrt(169.0)) == 13) * 32;
  // 0x3f if all pass
}
