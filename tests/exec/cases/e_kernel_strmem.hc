// MemCmp, StrCat and MinI64 are the port's own native RISC-V asm.
//
// Kernel/KUtilsRV.HC already held nine such primitives — MemSet MemCpy StrLen StrCpy StrCmp
// StrNCmp StrICmp StrMatch StrIMatch — translated off the x86 in Kernel/KUtils.HC. These three
// were simply absent from that set (MinI64 missing beside a MaxI64 that has been there since the
// port began), so they were unresolved imports and bootstrap/holy_rt.h answered. Semantics match
// HolyMemCmp/HolyStrCat/HolyMinI64 exactly, so no caller's behaviour moves.
//
// BEHAVIOUR ONLY: the C runtime is also correct, so this cannot tell whose code ran. That is
// tests/scripts/check_blob_imports.sh's job. What this case IS for is the hand-written assembly —
// edge cases, not a happy path: zero counts, equality, both orders of difference, unsigned
// comparison above 0x7F, appending to an empty string and appending an empty string, and MinI64
// across zero and at equality.
#include "/Kernel/Kernel_RV.PRJ"
I64 opaque(I64 v) { return v; }
I64 main()
{
  U8 a[8], b[8], dst[32];
  I64 r = 0;
  // MemCmp
  MemCpy(a, "abcd", 5);
  MemCpy(b, "abcd", 5);
  r += (MemCmp(a, b, 4) == 0) * 1;
  r += (MemCmp(a, b, opaque(0)) == 0) * 2;      // zero count never reads
  b[2] = 'z';
  r += (MemCmp(a, b, 4) < 0) * 4;               // 'c' < 'z'
  r += (MemCmp(b, a, 4) > 0) * 8;               // and the other order
  r += (MemCmp(a, b, 2) == 0) * 16;             // difference is past the count
  // Unsigned: 0x80 must compare ABOVE 0x01, which a signed byte load would get backwards.
  a[0] = 0x80;
  b[0] = 0x01;
  r += (MemCmp(a, b, 1) > 0) * 32;
  // StrCat
  dst[0] = 0;
  r += (StrCat(dst, "ab") == dst) * 64;         // returns dst
  StrCat(dst, "cd");
  r += (StrLen(dst) == 4 && dst[0] == 'a' && dst[3] == 'd' && dst[4] == 0) * 128;
  StrCat(dst, "");                              // appending nothing keeps the terminator
  r += (StrLen(dst) == 4 && dst[4] == 0) * 256;
  // MinI64
  r += (MinI64(opaque(3), opaque(7)) == 3) * 512;
  r += (MinI64(opaque(7), opaque(3)) == 3) * 1024;
  r += (MinI64(opaque(-5), opaque(2)) == -5) * 2048;
  r += (MinI64(opaque(4), opaque(4)) == 4) * 4096;
  return r;
  // 0x1fff
}
