// Verifies native RISC-V StrMatch / StrIMatch in KUtilsRV.HC.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  U8 *hay = "hello world";
  r += (StrMatch("world", hay, 0) == hay + 6) * 1;
  r += (StrMatch("xyz", hay, 0) == 0) * 2;
  r += (StrMatch("hello", hay, 0) == hay) * 4;
  r += (StrIMatch("WORLD", hay, 0) == hay + 6) * 8;
  r += (StrIMatch("HELLO", hay, 0) == hay) * 16;
  r += (StrMatch("WORLD", hay, 0) == 0) * 32;
  // case-sensitive: no match
  return r;
  // 0x3F
}
