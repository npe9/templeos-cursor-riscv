// SiFive PRCI — the clock tree, read-only, and a measurement that does not trust it.
//
// This port has always ASSUMED firmware's clocks. Every peripheral divisor it uses was computed
// for the post-U-Boot state, and nothing ever checked that assumption against the machine. When
// something finally did, the assumption was wrong in a harmless direction: PCLK is 130 MHz, not
// the 125 MHz this tree wrote down, which makes the I2C prescaler 0x0103 exactly 100 kHz rather
// than the "~96 kHz" the comments claimed. Becoming the SPL means configuring
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

// The cast form, not `U32 *p; p = CONFIG_SIFIVE_PRCI_BASE + off;`. That obvious spelling is
// MISCOMPILED by the host compiler: assigning `<integer constant> + <variable>` to an
// already-declared pointer scales the variable by the pointee size. Disassembled from the host
// compiler's own output for exactly that line:
//     lui  a0,0x10000      # the base
//     mv   a0,s1           # off
//     li   a0,4            # sizeof(U32), from nowhere in the source
//     mul  a0,t0,t1        # off * 4
//     add  a0,t0,t1        # base + off*4
// So RVPrciRd(0x04) read 0x10000010 and Clk reported 52 MHz for every PLL on the board while
// mcycle said 1.196 GHz. The same expression in an INITIALIZER, or with a variable base, does
// not scale -- which is why Kernel/Drv/RVSifiveYes.HC's PLIC reads and the GEM driver were never
// bitten. The guest compiler does not scale in any of the three forms, so the two disagree.
// tests/exec/cases/e_ptr_assign_const_base.hc pins all three.
U32 RVPrciRd(I64 off)
{
  if (!CONFIG_SIFIVE_PRCI_BASE)
    return 0;
  return *((CONFIG_SIFIVE_PRCI_BASE + off)(U32 *));
}
// Decode one SiFive PLL. cfg fields: divr[5:0] divf[14:6] divq[17:15] range[20:18]
// bypass[24] fse[25] lock[31]. fvco = fin/(divr+1) * 2 * (divf+1); fout = fvco >> divq.
//
// The `outdiv` register is NOT a rate divider on the output, which is what this port first assumed
// and the board disproved. Measured on the FU740 (raw words from Dump(0x10000000,6)):
//   corepllcfg   0x820544C2 -> divr 2 divf 275 divq 2 -> 26/3*2*276 = 4784 MHz >> 2 = 1196 MHz
//   coreplloutdiv 0x00000000
//   gemgxlpllcfg 0x8206B982 -> divr 2 divf 230 divq 5 -> 4004 MHz >> 5 = 125.125 MHz
//   gemgxlplloutdiv 0x80000000
// Treating outdiv as "divide by 2*(div+1)" would make the core 598 MHz -- but mcycle against the
// CLINT says 1.19 GHz, and 125.125 MHz is exactly the GMII clock a gigabit PHY needs, so neither
// output is divided. Bit 31 is a clock ENABLE, and Linux's fu740-prci agrees: it registers each
// of these as the bare WRPLL output. So the outdiv argument is kept for the raw dump and for the
// enable bit, and no division is applied.
I64 RVPrciPllHz(U32 cfg, U32 outdiv, I64 fin)
{
  I64 divr, divf, divq, fvco;
  if (!fin)
    return 0;
  if (cfg & 0x01000000)
    return fin;
  divr = cfg & 0x3F;
  divf = (cfg >> 6) & 0x1FF;
  divq = (cfg >> 15) & 7;
  fvco = fin / (divr + 1) * 2 * (divf + 1);
  return fvco >> divq;
}

Bool RVPrciPllOutEnabled(U32 outdiv)
{
  //Bit 31 of a *_plloutdiv register is the output clock enable.
  return (outdiv & 0x80000000) != 0;
}

Bool RVPrciPllLocked(U32 cfg)
{
  return (cfg & 0x80000000) != 0;
}

// Every RVPrciRd below is HOISTED into a local, and that is not style. Nested calls in the
// argument list of a non-variadic callee are broken in this compiler -- Kernel/RVWinSerial.HC
// carries the same workaround for RVWinMcausePrint. Written the obvious way,
//   RVPrciPllHz(RVPrciRd(CFG), RVPrciRd(OUTDIV), HFCLK)
// every nested read delivered the SAME value, so all four PLLs decoded from cfg = 0 and Clk
// reported 52 MHz for each of them on the board while the counters said 1.196 GHz. QEMU hid it
// completely: its PRCI reads back zeros, so cfg was legitimately 0 there and the wrong answer
// and the right answer were the same number.
I64 RVPrciCorePllHz()
{
  U32 cfg, od;
  cfg = RVPrciRd(RV_PRCI_COREPLLCFG);
  od = RVPrciRd(RV_PRCI_COREPLLOUTDIV);
  return RVPrciPllHz(cfg, od, RV_PRCI_HFCLK_HZ);
}

I64 RVPrciDdrPllHz()
{
  U32 cfg, od;
  cfg = RVPrciRd(RV_PRCI_DDRPLLCFG);
  od = RVPrciRd(RV_PRCI_DDRPLLOUTDIV);
  return RVPrciPllHz(cfg, od, RV_PRCI_HFCLK_HZ);
}

I64 RVPrciGemgxlPllHz()
{
  U32 cfg, od;
  cfg = RVPrciRd(RV_PRCI_GEMGXLPLLCFG);
  od = RVPrciRd(RV_PRCI_GEMGXLPLLOUTDIV);
  return RVPrciPllHz(cfg, od, RV_PRCI_HFCLK_HZ);
}

I64 RVPrciHfpclkPllHz()
{
  U32 cfg, od;
  cfg = RVPrciRd(RV_PRCI_HFPCLKPLLCFG);
  od = RVPrciRd(RV_PRCI_HFPCLKPLLOUTDIV);
  return RVPrciPllHz(cfg, od, RV_PRCI_HFCLK_HZ);
}
// PCLK is hfpclkpll divided by a FIXED 2 -- not by hfpclkdiv, which reads 0 on this board and is
// not what sets the rate. Measured: hfpclkpll decodes to 260 MHz and the console's own divisor
// (1128, so 115200 * 1129) puts PCLK at 130.06 MHz. 260/2 = 130. Linux's fu740-prci models pclk
// the same way, as a fixed /2 from hfpclkpll.
I64 RVPrciPclkHz()
{
  I64 f = RVPrciHfpclkPllHz;
  if (RVPrciRd(RV_PRCI_HFPCLKPLLSEL) & 1)
    f = RV_PRCI_HFCLK_HZ;
  return f / 2;
}
#endif
