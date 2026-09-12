// Probe: MEM_MAPPED_SPACE[0] vs stock mem_mapped_space after RVKernelInit.
#include "/Kernel/Kernel_RV.PRJ"

I64 main()
{
  I64 mms_i64;
  U8 *mms_ptr;

  RVKernelInit();

  Print("after RVKernelInit:\n");
  Print("  MEM_MAPPED_SPACE[0]=%X\n", MEM_MAPPED_SPACE[0]);
  mms_i64 = mem_mapped_space(I64);
  Print("  mem_mapped_space(I64)=%X\n", mms_i64);
  Print("  &MEM_MAPPED_SPACE=%X\n", &MEM_MAPPED_SPACE);
  Print("  &mem_mapped_space=%X\n", &mem_mapped_space);

  mem_mapped_space = 0x100000000(U8 *);
  Print("after mem_mapped_space=0x100000000:\n");
  Print("  MEM_MAPPED_SPACE[0]=%X\n", MEM_MAPPED_SPACE[0]);
  mms_i64 = mem_mapped_space(I64);
  Print("  mem_mapped_space(I64)=%X\n", mms_i64);
  Print("  &MEM_MAPPED_SPACE=%X\n", &MEM_MAPPED_SPACE);
  Print("  &mem_mapped_space=%X\n", &mem_mapped_space);

  // Same numeric limit via array path (should NOT affect mem_mapped_space if unaliased)
  MEM_MAPPED_SPACE[0] = 0x200000000;
  Print("after MEM_MAPPED_SPACE[0]=0x200000000:\n");
  Print("  MEM_MAPPED_SPACE[0]=%X\n", MEM_MAPPED_SPACE[0]);
  mms_i64 = mem_mapped_space(I64);
  Print("  mem_mapped_space(I64)=%X\n", mms_i64);

  return 0;
}
