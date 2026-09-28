// GetMcause reads the CSR. After a recovered load fault mcause holds 5 (the handler does not clear
// it); before any trap in this harness it is whatever reset left, so only the after-fault value is
// asserted, plus agreement with the runtime's own record of the same trap.
#include "/Kernel/Kernel_RV.PRJ"
I64 main() {
  I64 r = 0, *bad = 0x10;
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  RVTrapInit();
  if (RVTrapRecoverArm()) {
    // back here after the fault
    if (GetMcause() == 5) r |= 1;
    if (GetMcause() == RVTrapRecoverCause()) r |= 2;
    RVTrapRecoverDisarm();
    return r;
  }
  r = *bad;   // load from 0x10: load access fault (mcause 5)
  return 0x100;
}
