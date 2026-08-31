// CLINT machine-timer primitive + an editable tick handler (MEM_* / this board).
// Run("timer.hc"); SetTrap("OnTick"); TrapInit(); TimerArm(1000000);  then Ticks().
// Edit OnTick, Run("timer.hc") again, and the next tick uses the new body.
I64 tick_count;
// OnTick -- OnTick(cause,epc,tval)
// NAME
//   OnTick - timer tick trap handler (re-arms mtimecmp).
// SYNOPSIS
//   OnTick(cause,epc,tval)
// DESCRIPTION
//   timer tick trap handler (re-arms mtimecmp).
// INPUTS
//   cause - argument
//   epc - argument
//   tval - argument
// OUTPUTS
//   timer tick trap handler (re-arms mtimecmp).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 OnTick(I64 cause, I64 epc, I64 tval)
{
  tick_count++;
  *(U64 *)MEM_MTIMECMP = *(U64 *)MEM_MTIME + 1000000;
  // re-arm (~0.1s @ 10MHz)
  return 0;
}
// Ticks -- Ticks()
// NAME
//   Ticks - return tick_count from OnTick.
// SYNOPSIS
//   Ticks()
// DESCRIPTION
//   return tick_count from OnTick.
// INPUTS
//   none
// OUTPUTS
//   return tick_count from OnTick.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 Ticks()
{
  return tick_count;
}
