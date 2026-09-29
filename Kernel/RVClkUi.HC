// Clk() — what this machine's clocks ACTUALLY are, measured before they are decoded.
#ifndef RV_CLK_UI_HC
#define RV_CLK_UI_HC
#help_index "Dbg"
#ifndef CONFIG_UART_BASE
#define CONFIG_UART_BASE 0
#endif
// The console's rate. Every board file in this tree opens at 115200 8N1 and the smoke scripts
// agree, so a divisor read back from the UART is a direct statement about PCLK.
#define RV_CLK_CONSOLE_BAUD 115200
asm {
	RVClkRdMCycle::
	csrr	a0, 0xB00
	ret
}
// Core clock from first principles: mcycle counts core clocks, the CLINT's mtime counts rtcclk
// at CONFIG_TIMEBASE_FREQ (1 MHz on the FU740, and a number the board documents rather than one
// this port chose). Nothing here depends on the PRCI register map being right.
//
// The first mtime read is thrown away and the loop re-armed on a tick boundary, because at
// 1 MHz against a ~1 GHz core a partial first tick is a whole 0.1% of a short window.
I64 RVClkMeasureCoreHz(I64 ms)
{
  I64 t0, tw, c0, c1, dt, dc, want, spin;
#ifdef CONFIG_HAS_CLINT
  if (ms <= 0)
    ms = 100;
  want = CONFIG_TIMEBASE_FREQ / 1000 * ms;
  if (want <= 0)
    return 0;
  // Both waits are bounded. A stopped mtime is not expected -- it runs off the always-on rtcclk
  // -- but this is a verb typed at a prompt on a board with no debugger attached, and an
  // unbounded spin there costs a reset. Returning 0 makes Clk() say "not available" instead.
  spin = 0;
  t0 = *(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF);
  while (*(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF) == t0) {
    spin++;
    if (spin > 200000000)
      return 0;
  }
  t0 = *(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF);
  c0 = RVClkRdMCycle();
  // The second wait bails to whatever window it got rather than failing: a short measurement is
  // less precise but still true, and the ratio below does not care how long the window was.
  spin = 0;
  while (1) {
    tw = *(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF);
    if (tw - t0 >= want)
      break;
    spin++;
    if (spin > 200000000)
      break;
  }
  c1 = RVClkRdMCycle();
  dt = tw - t0;
  dc = c1 - c0;
  if (dt <= 0 || dc <= 0)
    return 0;
  return dc / dt * CONFIG_TIMEBASE_FREQ + (dc % dt) * CONFIG_TIMEBASE_FREQ / dt;
#else
  return 0;
#endif
}
// PCLK from the console divisor. SiFive UART: baud = f_in / (div + 1), and div is the seventh
// word of the block (offset 0x18). The console is demonstrably running at 115200, so this is a
// measurement -- but ONLY if something actually programmed that divisor for 115200.
//
// Today U-Boot does, and this port does not: RVSifiveUartInit writes txctrl and rxctrl and leaves
// div alone. After Stage A there is no U-Boot, so div holds whatever the ZSBL left, and
// 115200 * (div + 1) would then be a confident number that means nothing -- and it feeds the
// "your I2C prescaler is wrong by N%" warning below. So bound the answer: the FU740's PCLK comes
// off hfpclkpll, which cannot be below the 26 MHz crystal and is not plausibly above 500 MHz.
// Outside that, report that the divisor was not set by anything we can identify.
#define RV_CLK_PCLK_MIN 26000000
#define RV_CLK_PCLK_MAX 500000000
I64 RVClkUartPclkHz()
{
#ifdef CONFIG_UART_SIFIVE
  U32 *u = CONFIG_UART_BASE;
  I64 d, hz;
  if (!CONFIG_UART_BASE)
    return 0;
  d = u[6] & 0xFFFF;
  if (!d)
    return 0;
  hz = RV_CLK_CONSOLE_BAUD * (d + 1);
  if (hz < RV_CLK_PCLK_MIN || hz > RV_CLK_PCLK_MAX)
    return -hz;
  return hz;
#else
  return 0;
#endif
}

U0 RVClkPrintHz(U8 *label, I64 hz)
{
  if (!hz) {
    Print("  %s  (not available)\n", label);
    return;
  }
  Print("  %s  %d.%03d MHz  (%d Hz)\n", label, hz / 1000000, hz % 1000000 / 1000, hz);
}

U0 Clk()
{
  I64 core, pclk, dcore, dpclk, ddr, gem, hfp, lo, hi;
  Print("measured (no register map trusted):\n");
  core = RVClkMeasureCoreHz(100);
  RVClkPrintHz("core  (mcycle vs CLINT mtime)", core);
  pclk = RVClkUartPclkHz;
  if (pclk < 0) {
    // A negative answer is the range check failing: the divisor is set to something, but not to
    // anything that makes 115200 out of a credible PCLK. Say the raw number and believe nothing.
    Print("  pclk  (console divisor)       implausible: divisor implies %d Hz, ignoring it\n",
          -pclk);
    Print("        nothing this port runs sets that divisor, so after Stage A it is the ZSBL's\n");
    pclk = 0;
  } else
    RVClkPrintHz("pclk  (console divisor)      ", pclk);
#ifdef RV_SIFIVE_PRCI_HC
  if (RVPrciBase) {
    Print("PRCI @ 0x%08X, decoded with U-Boot's fu740 offsets:\n", RVPrciBase);
    dcore = RVPrciCorePllHz;
    ddr = RVPrciDdrPllHz;
    gem = RVPrciGemgxlPllHz;
    hfp = RVPrciHfpclkPllHz;
    dpclk = RVPrciPclkHz;
    RVClkPrintHz("corepll                      ", dcore);
    RVClkPrintHz("ddrpll                       ", ddr);
    RVClkPrintHz("gemgxlpll                    ", gem);
    RVClkPrintHz("hfpclkpll                    ", hfp);
    RVClkPrintHz("pclk = hfpclk / hfpclkdiv    ", dpclk);
    // Hoisted for the same reason as the accessors in RVSifivePrci.HC: nested calls in an
    // argument list hand the callee one repeated value. Printed the obvious way, this line
    // claimed corepllcfg was 0x80000000 when a raw Peek of 0x10000004 says 0x820544C2.
    {
      U32 r0, r1, r2, r3;
      r0 = RVPrciRd(RV_PRCI_COREPLLCFG);
      r1 = RVPrciRd(RV_PRCI_COREPLLOUTDIV);
      r2 = RVPrciRd(RV_PRCI_CORECLKSEL) & 1;
      r3 = RVPrciRd(RV_PRCI_COREPLLSEL) & 1;
      Print("  raw: corepllcfg 0x%08X out 0x%08X  clksel %d pllsel %d\n", r0, r1, r2, r3);
      r0 = RVPrciRd(RV_PRCI_HFPCLKPLLCFG);
      r1 = RVPrciRd(RV_PRCI_HFPCLKPLLOUTDIV);
      r2 = RVPrciRd(RV_PRCI_HFPCLKDIV) & 0xFFF;
      r3 = RVPrciRd(RV_PRCI_HFPCLKPLLSEL) & 1;
      Print("  raw: hfpclkcfg  0x%08X out 0x%08X  div 0x%03X sel %d\n", r0, r1, r2, r3);
    }
    // The decode checks itself against the measurement. Within 2% is agreement; outside it,
    // the offsets above are the thing to doubt, not the counters.
    if (core && dcore) {
      lo = core - core / 50;
      hi = core + core / 50;
      if (dcore < lo || dcore > hi)
        Print("  DISAGREE: corepll decodes to %d Hz but the core measures %d Hz\n", dcore, core);
      else
        Print("  agrees with the measured core clock, so the offsets above are confirmed\n");
    }
    if (core && !dcore)
      Print("  corepll decoded to 0 — the offset table is wrong for this chip\n");
    if (pclk && dpclk) {
      lo = pclk - pclk / 50;
      hi = pclk + pclk / 50;
      if (dpclk < lo || dpclk > hi)
        Print("  DISAGREE: pclk decodes to %d Hz but the console divisor says %d Hz\n",
              dpclk, pclk);
    }
  }
#endif
  // PCLK on this board is 130 MHz, and that is measured twice over: hfpclkpll decodes to 260 MHz
  // and the console's own divisor (1128 -> 115200 * 1129) gives 130.06 MHz. The OpenCores I2C
  // prescaler 0x0103 = 259 then yields PCLK/(5*260) = exactly 100 kHz -- so the divisor was
  // always right for this board, and it was this tree's "~96 kHz off 125 MHz" note that was
  // wrong. Report the real SCL rate if PCLK ever turns out to be something else.
  if (pclk) {
    if (pclk < 128000000 || pclk > 132000000) {
      Print("NOTE: the I2C prescaler (0x0103) is exactly 100 kHz at the 130 MHz PCLK this\n");
      Print("      board runs. Measured %d Hz, so I2C is actually at %d Hz.\n", pclk,
            pclk / 1300);
    }
  }
}
#endif
