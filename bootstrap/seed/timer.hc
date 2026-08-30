// CLINT machine-timer primitive + an editable tick handler (QEMU virt).
// Run("timer.hc"); SetIsr("OnTick"); TrapInit(); TimerArm(1000000);  then Ticks().
// Edit OnTick, Run("timer.hc") again, and the next tick uses the new body.
I64 tick_count;
I64 OnTick(I64 cause, I64 epc, I64 tval) {
  tick_count++;
  *(U64 *)0x02004000 = *(U64 *)0x0200BFF8 + 1000000;    // re-arm mtimecmp (~0.1s @ 10MHz)
  return 0;
}
I64 Ticks() { return tick_count; }
