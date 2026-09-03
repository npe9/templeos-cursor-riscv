// SiFive platform absent (non-SiFive machine). Stubs — do not poke SiFive MMIO.
#include "RVSifivePlat.HH"
Bool RVSifivePresent()
{
  return FALSE;
}

I64 RVSifiveUartBase()
{
  return 0;
}

I64 RVSifiveUart1Base()
{
  return 0;
}

I64 RVSifiveClintBase()
{
  return 0;
}

I64 RVSifivePlicBase()
{
  return 0;
}

I64 RVSifiveTestBase()
{
  return 0;
}

I64 RVSifiveAonBase()
{
  return 0;
}

I64 RVSifiveGpioBase()
{
  return 0;
}

I64 RVSifiveGpioResetPin()
{
  return 32;
}

I64 RVSifivePrciBase()
{
  return 0;
}

I64 RVSifiveEthBase()
{
  return 0;
}

Bool RVSifiveCanReset()
{
  return FALSE;
}

U0 RVSifiveUartInit()
{
}

Bool RVSifiveUartPutS(U8 *st)
{
  return FALSE;
}

Bool RVSifiveUartDataReady()
{
  return FALSE;
}

I64 RVSifiveUartGetC()
{
  return -1;
}

I64 RVSifiveClintMtime()
{
  return 0;
}

U0 RVSifiveClintSetMtimecmp(I64 when)
{
}

U0 RVSifiveClintArmTicks(I64 ticks_from_now)
{
}

U0 RVSifivePlicEnable(I64 irq, I64 priority)
{
}

U0 RVSifivePlicSetThreshold(I64 thr)
{
}

I64 RVSifivePlicClaim()
{
  return 0;
}

U0 RVSifivePlicComplete(I64 irq)
{
}

Bool RVSifiveReset()
{
  return FALSE;
}

Bool RVSifivePowerOff()
{
  return FALSE;
}

U0 RVSifiveHalt()
{
  while (TRUE)
    HLT;
}

U0 RVSifiveFault()
{
}
