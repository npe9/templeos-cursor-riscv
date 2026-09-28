// throw() must leave its code where HolyC catchers look: Fs->except_ch.
//
// The host compiler lowers throw to an intrinsic that stored the code in the planted __task
// block only. That is Fs->except_ch exactly as long as Fs still points at __task; the kernel
// repoints Fs at a CTask of its own (Fs = adam) and from then on PutExcept, DirContextNew's
// catch and the REPL's ExePutS catch all read 0. On the HiFive Unmatched a missing Print
// argument -- StrPrintJoin's throw('StrPrint') -- therefore came out as silence and ans=0.
// Expect 0x3: the code is readable through Fs, and a second throw replaces it.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  CTask *adam = 0x86900000;
  I64 r = 0;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  try {
    throw('Ab');
  } catch {
    if (Fs->except_ch == 'Ab') r |= 1;
    Fs->catch_except = TRUE;
  }
  try {
    throw('StrPrint');
  } catch {
    if (Fs->except_ch == 'StrPrint') r |= 2;
    Fs->catch_except = TRUE;
  }
  return r;
}
