// Xilinx XPS Timer/Counter (xlnx.xps-timer) — QEMU amd-microblaze-v @ XPS_TIMER_BASE.
// Same RVClint* API as RVTimerClint / RVTimerIbex. Timer0 = free-running up-counter
// (mtime); Timer1 = one-shot for SetMtimecmp / IdleMs. Freq = CONFIG_TIMEBASE_FREQ
// (board: 100 MHz). Dig-down: Man("CLINT"); RVClintMtime; RVIdleMs;
#ifndef RV_DRV_TIMER_XPS_HC
#define RV_DRV_TIMER_XPS_HC
#ifndef CONFIG_XPS_TIMER_BASE
#define CONFIG_XPS_TIMER_BASE 0x41C00000
#endif
#ifndef CONFIG_TIMEBASE_FREQ
#define CONFIG_TIMEBASE_FREQ 100000000
#endif
#define XPS_T0_TCSR 0x00
#define XPS_T0_TLR  0x04
#define XPS_T0_TCR  0x08
#define XPS_T1_TCSR 0x10
#define XPS_T1_TLR  0x14
#define XPS_T1_TCR  0x18
#define XPS_TCSR_UDT  0x02
#define XPS_TCSR_ARHT 0x10
#define XPS_TCSR_LOAD 0x20
#define XPS_TCSR_ENIT 0x40
#define XPS_TCSR_ENT  0x80
#define XPS_TCSR_TINT 0x100
I64 xps_timer_free_on;
U0 RVXpsTimerEnsureFree()
{
  U8 *b = CONFIG_XPS_TIMER_BASE;
  if (xps_timer_free_on)
    return;
  // Timer0: count-up free-run from 0 with auto-reload (QEMU TCR = ~ptimer).
  OutU32(b + XPS_T0_TLR, 0);
  OutU32(b + XPS_T0_TCSR, XPS_TCSR_LOAD);
  OutU32(b + XPS_T0_TCSR, XPS_TCSR_ENT | XPS_TCSR_ARHT);
  xps_timer_free_on = 1;
}

I64 RVClintMtime()
{
  U8 *b = CONFIG_XPS_TIMER_BASE;
  RVXpsTimerEnsureFree;
  return InU32(b + XPS_T0_TCR);
}

U0 RVClintSetMtimecmp(I64 when)
{
  U8 *b = CONFIG_XPS_TIMER_BASE;
  I64 now, delta;
  RVXpsTimerEnsureFree;
  now = RVClintMtime();
  delta = when - now;
  if (delta < 1)
    delta = 1;
  if (delta > 0xFFFFFFFF)
    delta = 0xFFFFFFFF;
  // Timer1 one-shot down-count; clear TINT by writing the bit.
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_TINT);
  OutU32(b + XPS_T1_TLR, delta);
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_UDT | XPS_TCSR_LOAD);
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_UDT | XPS_TCSR_ENT | XPS_TCSR_ENIT);
}

U0 RVClintArmTicks(I64 ticks_from_now)
{
  RVClintSetMtimecmp(RVClintMtime + ticks_from_now);
}

U0 RVIdleMs(I64 mS)
{
  U8 *b = CONFIG_XPS_TIMER_BASE;
  I64 ticks;
  if (mS <= 0) {
    Yield;
    return;
  }
  ticks = (CONFIG_TIMEBASE_FREQ / 1000) * mS;
  if (ticks < 1)
    ticks = 1;
  if (ticks > 0xFFFFFFFF)
    ticks = 0xFFFFFFFF;
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_TINT);
  OutU32(b + XPS_T1_TLR, ticks);
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_UDT | XPS_TCSR_LOAD);
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_UDT | XPS_TCSR_ENT);
  while (!(InU32(b + XPS_T1_TCSR) & XPS_TCSR_TINT))
    Yield;
  OutU32(b + XPS_T1_TCSR, XPS_TCSR_TINT);
}
#endif
