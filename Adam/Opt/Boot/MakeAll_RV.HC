// MakeAll_RV.HC — TempleOS MakeAll analogue for RISC-V (BootHDIns.HC shape).
// x86: Cmp("/Compiler/Compiler") + Cmp("/Kernel/Kernel").
// RV: guest Cmp of staged MakeOS Tiny + Runtime Seed/Svc/Kern + Adam/StartOS
// (see RVPhase3MakeOS / RVPhase3GuestRuntime). Destination: guest Cmp builds
// Kernel/Compiler BINs that boot Loads — host holyc-riscv is bootstrap only
// (COMPILER_RV.md P3).

U0 MakeAllRV()
{
  if (FileFind("A:/MakeOS/Tiny.PRJ"))
    Cmp("A:/MakeOS/Tiny.PRJ",,"A:/MakeOS/Tiny.BIN");
  if (FileFind("A:/Runtime/Seed.PRJ"))
    Cmp("A:/Runtime/Seed.PRJ",,"A:/Runtime/Seed.BIN");
  if (FileFind("A:/Runtime/Svc.PRJ"))
    Cmp("A:/Runtime/Svc.PRJ",,"A:/Runtime/Svc.BIN");
  if (FileFind("A:/Runtime/Kern.PRJ"))
    Cmp("A:/Runtime/Kern.PRJ",,"A:/Runtime/Kern.BIN");
  if (FileFind("A:/Adam/StartOS.PRJ"))
    Cmp("A:/Adam/StartOS.PRJ",,"A:/Adam/StartOS.BIN");
  // Next: stage Compiler_RV / Kernel_RV subsets on A: then Cmp those BINs for boot.
  if (!FileFind("A:/MakeOS/MAKEOS.OK"))
    throw;
  if (!FileFind("A:/Runtime/SEED.OK"))
    throw;
  if (!FileFind("A:/Runtime/SVC.OK"))
    throw;
  if (!FileFind("A:/Runtime/KERN.OK"))
    throw;
  if (!FileFind("A:/Adam/STARTOS.OK"))
    throw;
}

public U0 MakeOSRV()
{//Closed-loop gate: guest Cmp BINs on A: (RVPhase3MakeOS / GuestRuntime).
  MakeAllRV;
}
