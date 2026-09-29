// SiFive SPI controller — byte transfers, for talking to the SD card on QSPI2.
//
// Register map from FU740-C000 Manual v1p6 Table 105. Only naturally aligned 32-bit accesses.
// txdata bit 31 is "FIFO full" (writes are IGNORED when set, which is a silent data loss if you
// do not check); rxdata bit 31 is "FIFO empty", so a read is only valid when that bit is clear.
#ifndef RV_DRV_SIFIVE_SPI_HC
#define RV_DRV_SIFIVE_SPI_HC
#ifndef CONFIG_SIFIVE_QSPI2_BASE
#define CONFIG_SIFIVE_QSPI2_BASE 0
#endif
#define RV_SPI_SCKDIV  0x00
#define RV_SPI_SCKMODE 0x04
#define RV_SPI_CSID    0x10
#define RV_SPI_CSDEF   0x14
#define RV_SPI_CSMODE  0x18
#define RV_SPI_DELAY0  0x28
#define RV_SPI_DELAY1  0x2C
#define RV_SPI_FMT     0x40
#define RV_SPI_TXDATA  0x48
#define RV_SPI_RXDATA  0x4C
#define RV_SPI_CSMODE_AUTO 0
#define RV_SPI_CSMODE_HOLD 2
#define RV_SPI_CSMODE_OFF  3
// fmt: [0] proto (0 = single), [2] dir (0 = rx populated, 1 = tx only), [3] endian (0 = MSB
// first), [19:16] len. SD wants 8-bit MSB-first single-lane with the rx FIFO populated.
#define RV_SPI_FMT_8BIT_RX (8 << 16)

I64 RVSpiBase()
{
  return CONFIG_SIFIVE_QSPI2_BASE;
}

U32 RVSpiRd(I64 off)
{
  return *((CONFIG_SIFIVE_QSPI2_BASE + off)(U32 *));
}

U0 RVSpiWr(I64 off, U32 v)
{
  *((CONFIG_SIFIVE_QSPI2_BASE + off)(U32 *)) = v;
}

U0 RVSpiSpeed(I64 div)
{
  //sck = pclk / (2 * (div + 1)). pclk is 130 MHz here (measured, not the 125 once assumed), so
  //div 155 is ~417 kHz and div 4 is 13 MHz -- both still inside what an SD card accepts.
  RVSpiWr(RV_SPI_SCKDIV, div);
}

U0 RVSpiSetup(I64 div)
{
  if (!CONFIG_SIFIVE_QSPI2_BASE)
    return;
  RVSpiSpeed(div);
  RVSpiWr(RV_SPI_SCKMODE, 0);                  // CPOL 0 CPHA 0, which is SD's SPI mode 0
  RVSpiWr(RV_SPI_CSID, 0);
  RVSpiWr(RV_SPI_CSDEF, 1);                    // CS idles high
  RVSpiWr(RV_SPI_CSMODE, RV_SPI_CSMODE_OFF);   // no automatic CS: the card protocol owns it
  RVSpiWr(RV_SPI_FMT, RV_SPI_FMT_8BIT_RX);
}

I64 RVSpiXfer(I64 out)
{
  // One byte each way — SPI is always full duplex, so every byte sent produces a byte received,
  // and the card's answers arrive in response to the 0xFF padding we send while listening.
  I64 spins = 0;
  U32 v;
  if (!CONFIG_SIFIVE_QSPI2_BASE)
    return -1;
  while (RVSpiRd(RV_SPI_TXDATA) & 0x80000000) {          // wait for room, or the write vanishes
    spins++;
    if (spins > 100000)
      return -1;
  }
  RVSpiWr(RV_SPI_TXDATA, out & 0xFF);
  spins = 0;
  while (TRUE) {
    v = RVSpiRd(RV_SPI_RXDATA);
    if (!(v & 0x80000000))
      return v & 0xFF;
    spins++;
    if (spins > 100000)
      return -1;
  }
}

U0 RVSpiCsOn()
{
  RVSpiWr(RV_SPI_CSMODE, RV_SPI_CSMODE_HOLD);
}

U0 RVSpiCsOff()
{
  RVSpiWr(RV_SPI_CSMODE, RV_SPI_CSMODE_OFF);
}
#endif
