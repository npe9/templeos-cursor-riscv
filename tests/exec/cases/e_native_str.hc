// Verifies the native RISC-V string primitives in Kernel/KUtilsRV.HC compute correctly (StrCpy,
// StrLen, StrCmp, StrNCmp) — these run as the kernel's own RISC-V asm, not the C runtime override.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U8 a[16]; StrCpy(a, "hello");              // native StrCpy: a = "hello"
  I64 len = StrLen(a);                       // 5
  I64 c1 = (StrCmp(a, "hello") == 0);        // equal -> 1
  I64 c2 = (StrCmp(a, "help") < 0);          // 'l' < 'p' -> 1
  I64 c3 = (StrNCmp(a, "help", 3) == 0);     // "hel" == "hel" -> 1
  I64 c4 = (StrCmp("abc", "abd") < 0);       // 'c' < 'd' -> 1
  return len*16 + c1 + c2*2 + c3*4 + c4*8;   // 5*16 + 15 = 95 = 0x5F
}
