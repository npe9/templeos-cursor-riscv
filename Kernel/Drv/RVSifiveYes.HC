// SiFive platform present (PLATFORM_SIFIVE_U / PLATFORM_SIFIVE_E via UART_SIFIVE).
// Owns SiFive UART0 TX/RXCTRL register pokes; CLINT/PLIC use CONFIG_* bases.
#include "RVSifivePlat.HH"
Bool RVSifivePresent()
{
  return TRUE;
}

I64 RVSifiveUartBase()
{
  return CONFIG_UART_BASE;
}

I64 RVSifiveClintBase()
{
  return CONFIG_CLINT_BASE;
}

I64 RVSifivePlicBase()
{
  return CONFIG_PLIC_BASE;
}

U0 RVSifiveUartInit()
{
  U32 *u = CONFIG_UART_BASE;
  u[2] = 1;
  // TXCTRL
  u[3] = 1;
  // RXCTRL
}

Bool RVSifiveUartPutS(U8 *st)
{
  U32 *u = CONFIG_UART_BASE;
  while (*st) {
    while (u[0] & 0x80000000)
      ;
    u[0] = *st++;
  }
  return TRUE;
}

Bool RVSifiveUartDataReady()
{
  U32 *u = CONFIG_UART_BASE;
  return (u[1] & 0x80000000) == 0;
}

I64 RVSifiveUartGetC()
{
  U32 *u = CONFIG_UART_BASE, v;
  while (TRUE) {
    v = u[1];
    if (!(v & 0x80000000))
      return v & 0xFF;
  }
  return 0;
}

I64 RVSifiveClintMtime()
{
  U64 *mtime = CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF;
  return *mtime;
}

U0 RVSifiveClintSetMtimecmp(I64 when)
{
  U64 *mtimecmp = CONFIG_CLINT_BASE + CONFIG_CLINT_MTIMECMP_OFF;
  *mtimecmp = when;
}

U0 RVSifiveClintArmTicks(I64 ticks_from_now)
{
  RVSifiveClintSetMtimecmp(RVSifiveClintMtime + ticks_from_now);
}

U0 RVSifivePlicEnable(I64 irq, I64 priority)
{
  U32 *prio = CONFIG_PLIC_BASE + irq * 4;
  U32 *en = CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF;
  if (priority <= 0)
    priority = 1;
  *prio = priority;
  *en = *en | (1 << irq);
}

U0 RVSifivePlicSetThreshold(I64 thr)
{
  U32 *t = CONFIG_PLIC_BASE + CONFIG_PLIC_THRESHOLD_OFF;
  *t = thr;
}

I64 RVSifivePlicClaim()
{
  U32 *c = CONFIG_PLIC_BASE + CONFIG_PLIC_CLAIM_OFF;
  return *c;
}

U0 RVSifivePlicComplete(I64 irq)
{
  U32 *c = CONFIG_PLIC_BASE + CONFIG_PLIC_CLAIM_OFF;
  *c = irq;
}
