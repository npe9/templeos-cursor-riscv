// Runs the real TempleOS kernel's StrPrintJoin (Kernel/StrPrint.HC) formatting into a buffer;
// returns 0x3f only if every byte of "n=1337." came out right (end-to-end kernel-printf check).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U8 buf[64];
  I64 args[1];
  args[0] = 1337;
  StrPrintJoin(buf, "n=%d.", 1, args);
  return (buf[0]=='n')*1 + (buf[1]=='=')*2 + (buf[2]=='1')*4 +
         (buf[3]=='3')*8 + (buf[5]=='7')*16 + (buf[6]=='.')*32;
}
