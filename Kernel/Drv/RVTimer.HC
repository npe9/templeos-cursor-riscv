// CLINT machine timer — addresses from Kconfig (RVAutoConf.HH).
#ifndef RV_DRV_TIMER_HC
#define RV_DRV_TIMER_HC
I64 RVClintMtime()
{
  U64 *mtime = CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF;
  return *mtime;
}

U0 RVClintSetMtimecmp(I64 when)
{
  U64 *mtimecmp = CONFIG_CLINT_BASE + CONFIG_CLINT_MTIMECMP_OFF;
  *mtimecmp = when;
}

U0 RVClintArmTicks(I64 ticks_from_now)
{
  RVClintSetMtimecmp(RVClintMtime + ticks_from_now);
}

U0 RVIdleMs(I64 mS)
{
  //CLINT mtime pause that works without CTask jiffies (WinMgr exec / kernel-win-run).
  //Yield each lap so a live scheduler can run other tasks.
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
