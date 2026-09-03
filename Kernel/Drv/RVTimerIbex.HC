// OpenTitan / Ibex rv_timer @ CONFIG_IBEX_TIMER_BASE (QEMU -M opentitan @ 0x40100000).
// Same RVClint* API as RVTimerClint so callers stay CLINT-shaped.
// Regs (QEMU/OpenTitan): CTRL@0x04 ACTIVE; INTR_ENABLE@0x100; LOWER0@0x110/UPPER0@0x114;
// COMPARE_LOWER0@0x118 / COMPARE_UPPER0@0x11C. Default timebase 10 kHz (QEMU ibex_timer).
#ifndef RV_DRV_TIMER_IBEX_HC
#define RV_DRV_TIMER_IBEX_HC
#ifndef CONFIG_IBEX_TIMER_BASE
#define CONFIG_IBEX_TIMER_BASE 0x40100000
#endif
#define RV_IBEX_TMR_CTRL           0x04
#define RV_IBEX_TMR_CTRL_ACTIVE    1
#define RV_IBEX_TMR_INTR_ENABLE    0x100
#define RV_IBEX_TMR_INTR_STATE     0x104
#define RV_IBEX_TMR_LOWER0         0x110
#define RV_IBEX_TMR_UPPER0         0x114
#define RV_IBEX_TMR_COMPARE_LOWER0 0x118
#define RV_IBEX_TMR_COMPARE_UPPER0 0x11C
U0 RVIbexTimerEnsureActive()
{
  U32 *ctrl = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_CTRL;
  if (!(*ctrl & RV_IBEX_TMR_CTRL_ACTIVE))
    *ctrl = RV_IBEX_TMR_CTRL_ACTIVE;
}

I64 RVClintMtime()
{
  U32 *lo = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_LOWER0;
  U32 *hi = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_UPPER0;
  U32 l, h, h2;
  RVIbexTimerEnsureActive;
  // 64-bit consistent read (hi-lo-hi).
  do {
    h = *hi;
    l = *lo;
    h2 = *hi;
  } while (h != h2);
  return (h << 32) | l;
}

U0 RVClintSetMtimecmp(I64 when)
{
  U32 *cmp_lo = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_COMPARE_LOWER0;
  U32 *cmp_hi = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_COMPARE_UPPER0;
  U32 *ien = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_INTR_ENABLE;
  U32 *ist = CONFIG_IBEX_TIMER_BASE + RV_IBEX_TMR_INTR_STATE;
  RVIbexTimerEnsureActive;
  // Disable compare IRQ while updating; write UPPER then LOWER (OT order).
  *ien = 0;
  *cmp_hi = when >> 32;
  *cmp_lo = when;
  *ist = 1;
  // W1C
  *ien = 1;
}

U0 RVClintArmTicks(I64 ticks_from_now)
{
  RVClintSetMtimecmp(RVClintMtime + ticks_from_now);
}

U0 RVIdleMs(I64 mS)
{
  I64 t0, deadline, step;
  if (mS <= 0) {
    Yield;
    return;
  }
  step = CONFIG_TIMEBASE_FREQ / 1000;
  if (step <= 0)
    step = 1;
  t0 = RVClintMtime();
  deadline = t0 + mS *step;
  while (RVClintMtime() < deadline)
    Yield;
}
#endif
