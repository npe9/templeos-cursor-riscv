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
#endif
