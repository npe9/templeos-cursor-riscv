// No SiFive CLINT and no Ibex timer (e.g. amd-microblaze-v). Selected via RVTimerSelected.HH.
I64 RVClintMtime()
{
  return 0;
}

U0 RVClintSetMtimecmp(I64 when)
{
  when = when;
}

U0 RVClintArmTicks(I64 ticks_from_now)
{
  ticks_from_now = ticks_from_now;
}

U0 RVIdleMs(I64 mS)
{
  mS = mS;
  Yield;
}
