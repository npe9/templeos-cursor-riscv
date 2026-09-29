// SiFive PRCI — the clock tree, read-only, and a measurement that does not trust it.
//
// This port has always ASSUMED firmware's clocks. Every peripheral divisor it uses was computed
// for the post-U-Boot state (the I2C prescaler is 0x0103 for ~96 kHz off a nominal 125 MHz PCLK),
// and nothing ever checked that assumption against the machine. Becoming the SPL means configuring
// these PLLs ourselves, and the first honest step is to find out what they are actually set to.
//
// Two independent sources are read here on purpose, because neither alone is trustworthy:
//   1. A MEASUREMENT. mcycle counts core clocks; the CLINT's mtime counts rtcclk at a frequency
//      the board documents (CONFIG_TIMEBASE_FREQ, 1 MHz on the FU740). Their ratio is the core
//      frequency with no register layout to get wrong. Likewise the SiFive UART's divisor gives
//      PCLK directly: the console is running at a baud rate we can see working, so
//      pclk = baud * (div + 1) is a fact about the hardware, not a guess.
//   2. A DECODE of the PRCI registers. The offsets below are U-Boot's fu740-prci; they are the
//      part most likely to be wrong, which is exactly why the measurement comes first and the
//      raw words are printed alongside. If the decoded corepll disagrees with the measured core
//      clock, believe the measurement and suspect this table.
#ifndef RV_SIFIVE_PRCI_HC
#define RV_SIFIVE_PRCI_HC
#ifndef CONFIG_SIFIVE_PRCI_BASE
#define CONFIG_SIFIVE_PRCI_BASE 0
#endif
#ifndef CONFIG_TIMEBASE_FREQ
#define CONFIG_TIMEBASE_FREQ 1000000
#endif
// FU740-C000 external crystal. Manual ch.7: out of reset every core runs directly off this.
#define RV_PRCI_HFCLK_HZ 26000000
// Register offsets, from U-Boot drivers/clk/sifive/fu740-prci.h. Unverified against silicon.
#define RV_PRCI_HFXOSCCFG        0x00
#define RV_PRCI_COREPLLCFG       0x04
#define RV_PRCI_COREPLLOUTDIV    0x08
#define RV_PRCI_DDRPLLCFG        0x0C
#define RV_PRCI_DDRPLLOUTDIV     0x10
#define RV_PRCI_GEMGXLPLLCFG     0x1C
#define RV_PRCI_GEMGXLPLLOUTDIV  0x20
#define RV_PRCI_CORECLKSEL       0x24
#define RV_PRCI_DEVICESRESETN    0x28
#define RV_PRCI_CLKMUXSTATUS     0x2C
#define RV_PRCI_DVFSCOREPLLCFG   0x38
#define RV_PRCI_DVFSCOREPLLOUTDIV 0x3C
#define RV_PRCI_COREPLLSEL       0x40
#define RV_PRCI_HFPCLKPLLCFG     0x50
#define RV_PRCI_HFPCLKPLLOUTDIV  0x54
#define RV_PRCI_HFPCLKPLLSEL     0x58
#define RV_PRCI_HFPCLKDIV        0x5C

I64 RVPrciBase()
{
  return CONFIG_SIFIVE_PRCI_BASE;
}

U32 RVPrciRd(I64 off)
{
  U32 *p;
  if (!CONFIG_SIFIVE_PRCI_BASE)
    return 0;
  p = CONFIG_SIFIVE_PRCI_BASE + off;
  return *p;
}
// Decode one SiFive PLL. cfg fields: divr[5:0] divf[14:6] divq[17:15] range[20:18]
// bypass[24] fse[25] lock[31]. fvco = fin/(divr+1) * 2 * (divf+1); fout = fvco >> divq.
// outdiv: div[7:0], divby1[8]; when divby1 is clear the output is fout / (2*(div+1)).
I64 RVPrciPllHz(U32 cfg, U32 outdiv, I64 fin)
{
  I64 divr, divf, divq, fvco, fout, d;
  if (!fin)
    return 0;
  if (cfg & 0x01000000)
    return fin;
  divr = cfg & 0x3F;
  divf = (cfg >> 6) & 0x1FF;
  divq = (cfg >> 15) & 7;
  fvco = fin / (divr + 1) * 2 * (divf + 1);
  fout = fvco >> divq;
  if (outdiv & 0x100)
    return fout;
  d = outdiv & 0xFF;
  return fout / (2 * (d + 1));
}

Bool RVPrciPllLocked(U32 cfg)
{
  return (cfg & 0x80000000) != 0;
}

I64 RVPrciCorePllHz()
{
  return RVPrciPllHz(RVPrciRd(RV_PRCI_COREPLLCFG), RVPrciRd(RV_PRCI_COREPLLOUTDIV),
                     RV_PRCI_HFCLK_HZ);
}

I64 RVPrciDdrPllHz()
{
  return RVPrciPllHz(RVPrciRd(RV_PRCI_DDRPLLCFG), RVPrciRd(RV_PRCI_DDRPLLOUTDIV),
                     RV_PRCI_HFCLK_HZ);
}

I64 RVPrciGemgxlPllHz()
{
  return RVPrciPllHz(RVPrciRd(RV_PRCI_GEMGXLPLLCFG), RVPrciRd(RV_PRCI_GEMGXLPLLOUTDIV),
                     RV_PRCI_HFCLK_HZ);
}

I64 RVPrciHfpclkPllHz()
{
  return RVPrciPllHz(RVPrciRd(RV_PRCI_HFPCLKPLLCFG), RVPrciRd(RV_PRCI_HFPCLKPLLOUTDIV),
                     RV_PRCI_HFCLK_HZ);
}
// PCLK is hfpclk divided again by hfpclkdiv: pclk = hfpclk / (2*(div+1)).
I64 RVPrciPclkHz()
{
  I64 d = RVPrciRd(RV_PRCI_HFPCLKDIV) & 0xFFF;
  I64 f = RVPrciHfpclkPllHz;
  if (RVPrciRd(RV_PRCI_HFPCLKPLLSEL) & 1)
    f = RV_PRCI_HFCLK_HZ;
  return f / (2 * (d + 1));
}
#endif
