// Verifies native RISC-V port-I/O-as-MMIO primitives (load/store at address) in KUtilsRV.HC.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  U8 buf[64];
  MemSet(buf, 0, 64);
  OutU8(&buf[0], 0x41);
  if (InU8(&buf[0]) == 0x41)
    r += 1;
  OutU16(&buf[2], 0x1234);
  if (InU16(&buf[2]) == 0x1234)
    r += 2;
  OutU32(&buf[4], 0xDEADBEEF);
  if (InU32(&buf[4]) == 0xDEADBEEF)
    r += 4;
  U32 port = 0xAA, dst[3];
  MemSet(dst, 0, 12);
  RepInU32(dst, 3, &port);
  if (dst[0] == 0xAA && dst[1] == 0xAA && dst[2] == 0xAA)
    r += 8;
  U32 src[3], oport = 0;
  src[0] = 1;
  src[1] = 2;
  src[2] = 3;
  RepOutU32(src, 3, &oport);
  if (oport == 3)
    r += 16;
  // last write wins
  U16 p16 = 0x55, d16[2];
  d16[0] = 0;
  d16[1] = 0;
  RepInU16(d16, 2, &p16);
  if (d16[0] == 0x55 && d16[1] == 0x55)
    r += 32;
  return r;
  // 0x3F
}
