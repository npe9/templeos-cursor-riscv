// SiFive platform present (PLATFORM_SIFIVE_U / PLATFORM_SIFIVE_E via UART_SIFIVE).
// Owns SiFive UART0 TX/RXCTRL register pokes; CLINT/PLIC use CONFIG_* bases.
// Reset/power: test finisher (sim), AON WDT (FE310), or GPIO active-low (FU540).
#include "RVSifivePlat.HH"
#ifndef CONFIG_SIFIVE_TEST_BASE
#define CONFIG_SIFIVE_TEST_BASE 0
#endif
#ifndef CONFIG_SIFIVE_AON_BASE
#define CONFIG_SIFIVE_AON_BASE 0
#endif
#ifndef CONFIG_SIFIVE_GPIO_BASE
#define CONFIG_SIFIVE_GPIO_BASE 0
#endif
#ifndef CONFIG_SIFIVE_GPIO_RESET_PIN
#define CONFIG_SIFIVE_GPIO_RESET_PIN 32
#endif
#ifndef CONFIG_SIFIVE_UART1_BASE
#define CONFIG_SIFIVE_UART1_BASE 0
#endif
#ifndef CONFIG_SIFIVE_PRCI_BASE
#define CONFIG_SIFIVE_PRCI_BASE 0
#endif
#ifndef CONFIG_SIFIVE_ETH_BASE
#define CONFIG_SIFIVE_ETH_BASE 0
#endif
U32 RVSifiveUnimpInsn = 0;
Bool RVSifivePresent()
{
  return TRUE;
}

I64 RVSifiveUartBase()
{
  return CONFIG_UART_BASE;
}

I64 RVSifiveUart1Base()
{
  return CONFIG_SIFIVE_UART1_BASE;
}

I64 RVSifiveClintBase()
{
  return CONFIG_CLINT_BASE;
}

I64 RVSifivePlicBase()
{
  return CONFIG_PLIC_BASE;
}

I64 RVSifiveTestBase()
{
  return CONFIG_SIFIVE_TEST_BASE;
}

I64 RVSifiveAonBase()
{
  return CONFIG_SIFIVE_AON_BASE;
}

I64 RVSifiveGpioBase()
{
  return CONFIG_SIFIVE_GPIO_BASE;
}

I64 RVSifiveGpioResetPin()
{
  return CONFIG_SIFIVE_GPIO_RESET_PIN;
}

I64 RVSifivePrciBase()
{
  return CONFIG_SIFIVE_PRCI_BASE;
}

I64 RVSifiveEthBase()
{
  return CONFIG_SIFIVE_ETH_BASE;
}

Bool RVSifiveCanReset()
{
  if (CONFIG_SIFIVE_TEST_BASE)
    return TRUE;
  if (CONFIG_SIFIVE_AON_BASE)
    return TRUE;
  if (CONFIG_SIFIVE_GPIO_BASE && CONFIG_SIFIVE_GPIO_RESET_PIN < 32)
    return TRUE;
  return FALSE;
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
  // LF -> CRLF. Every caller in the tree writes a bare "\n", which a real serial terminal
  // renders as a staircase: line feed with no carriage return, so each line begins under the
  // END of the previous one. Measured on a HiFive Unmatched over its FT2232H console.
  // QEMU -nographic hides it completely because it cooks the output itself, which is exactly
  // why this survived until hardware. Translating in the driver rather than in a hundred
  // format strings is the only place it belongs; every consumer of this UART's output in
  // tests/scripts already pipes through `tr -d '\r'`.
  U32 *u = CONFIG_UART_BASE;
  while (*st) {
    if (*st == '\n') {
      while (u[0] & 0x80000000)
        ;
      u[0] = '\r';
    }
    while (u[0] & 0x80000000)
      ;
    u[0] = *st++;
  }
  return TRUE;
}

// A read of rxdata POPS the FIFO (FU740 manual: "reading rxdata dequeues"), so an emptiness test
// that reads it throws the byte away. DataReady used to do exactly that: every polled TryGet on the
// HiFive Unmatched lost the first byte it saw and returned the second — the ESC of every terminal
// reply the size probe waited for, which is how "[98;133R" got pasted into the first line typed.
// The one read is kept here until GetC asks for it.
I64 rv_sifive_rx_pending = -1;

Bool RVSifiveUartDataReady()
{
  U32 *u = CONFIG_UART_BASE, v;
  if (rv_sifive_rx_pending >= 0)
    return TRUE;
  v = u[1];
  if (v & 0x80000000)
    return FALSE;
  rv_sifive_rx_pending = v & 0xFF;
  return TRUE;
}

I64 RVSifiveUartGetC()
{
  U32 *u = CONFIG_UART_BASE, v;
  if (rv_sifive_rx_pending >= 0) {
    v = rv_sifive_rx_pending;
    rv_sifive_rx_pending = -1;
    return v;
  }
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

U0 RVSifiveHalt()
{
  while (TRUE)
    HLT;
}

Bool RVSifiveReset()
{
  U32 *p, bit;
  if (CONFIG_SIFIVE_TEST_BASE) {
    p = CONFIG_SIFIVE_TEST_BASE;
    *p = RVSIFIVE_TEST_RESET;
    RVSifiveHalt;
  }
  if (CONFIG_SIFIVE_AON_BASE) {
    p = CONFIG_SIFIVE_AON_BASE;
    p[RVSIFIVE_AON_WDOGKEY_OFF / 4] = RVSIFIVE_AON_WDOGKEY;
    p[RVSIFIVE_AON_WDOGCMP0 / 4] = 1;
    p[RVSIFIVE_AON_WDOGKEY_OFF / 4] = RVSIFIVE_AON_WDOGKEY;
    p[RVSIFIVE_AON_WDOGCOUNT / 4] = 0;
    p[RVSIFIVE_AON_WDOGKEY_OFF / 4] = RVSIFIVE_AON_WDOGKEY;
    p[RVSIFIVE_AON_WDOGCFG / 4] = RVSIFIVE_AON_WDOGCFG_RSTEN_ENALWAYS;
    RVSifiveHalt;
  }
  if (CONFIG_SIFIVE_GPIO_BASE && CONFIG_SIFIVE_GPIO_RESET_PIN < 32) {
    p = CONFIG_SIFIVE_GPIO_BASE;
    bit = 1 << CONFIG_SIFIVE_GPIO_RESET_PIN;
    p[RVSIFIVE_GPIO_OUTPUT_EN] = p[RVSIFIVE_GPIO_OUTPUT_EN] | bit;
    p[RVSIFIVE_GPIO_PORT] = p[RVSIFIVE_GPIO_PORT] & ~bit;
    RVSifiveHalt;
  }
  return FALSE;
}

Bool RVSifivePowerOff()
{
  U32 *p;
  if (CONFIG_SIFIVE_TEST_BASE) {
    p = CONFIG_SIFIVE_TEST_BASE;
    *p = RVSIFIVE_TEST_PASS;
  }
  RVSifiveHalt;
  return FALSE;
}

U0 RVSifiveFault()
{
  // Deliberate illegal insn (mcause=2). Pair with SetTrap + TrapInit.
  Call(&RVSifiveUnimpInsn);
}
