#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U8 buf[64];
  CArcCompress *arc;
  U8 *exp;
  I64 i;

  RVKernelInit();
  for (i = 0; i < 64; i++)
    buf[i] = i & 0x7F;
  Print("compress probe start mem_mapped_space=0x%X MEM[0]=0x%X\n",
    mem_mapped_space, MEM_MAPPED_SPACE[0]);
  arc = CompressBuf(buf, 64);
  if (!arc) {
    Print("FAIL null arc\n");
    return 1;
  }
  Print("arc type=%d csz=%d esz=%d\n", arc->compression_type, arc->compressed_size, arc->expanded_size);
  exp = ExpandBuf(arc);
  if (!exp) {
    Print("FAIL expand null\n");
    return 1;
  }
  for (i = 0; i < 64; i++)
    if (exp[i] != buf[i]) {
      Print("FAIL mismatch @%d got=%d\n", i, exp[i]);
      return 1;
    }
  Print("compress probe OK type=%d\n", arc->compression_type);
  Free(exp);
  Free(arc);
  return 0;
}
