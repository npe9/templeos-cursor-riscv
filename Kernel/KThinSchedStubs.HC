// KThinSchedStubs.HC — RV_THIN_LOADER: no x86 Yield/TaskFocus; host HolyYield + RVYieldInit.
// SoftCall KernelYieldSoft proves HolyRVCtxSw + next_task walk in Kernel.BIN (→'KY').
#ifndef K_THIN_SCHED_STUBS_HC
#define K_THIN_SCHED_STUBS_HC
U0 TaskFocusNext()
{
}

U0 TaskContextRestore()
{
}

U0 TaskEndNow()
{
  Exit;
}
// Yield is host `_extern _YIELD` (HolyYield); thin never runs the x86 Sched asm.
#endif
