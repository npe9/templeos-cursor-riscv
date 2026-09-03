// Verifies native RISC-V GetRFlags/SetRFlags(mstatus), InvlPg(sfence.vma), CPUId(identity CSRs).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0;
  I64 f = GetRFlags;
  if (f != 0)
    r += 1;
  // mstatus is non-zero in M-mode
  SetRFlags(f);
  // round-trip the same value (safe restore)
  if (GetRFlags == f)
    r += 2;
  U8 id[32];
  MemSet(id, 0, 32);
  CPUId(0, id);
  I64 *idw = id;
  if (idw[3] != 0)
    r += 4;
  // misa (offset 24) is non-zero on any RISC-V hart
  InvlPg(0x80000000);
  // must not fault
  r += 8;
  return r;
  // 0xF
}
