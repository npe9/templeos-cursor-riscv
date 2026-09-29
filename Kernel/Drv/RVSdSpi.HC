// SD card in SPI mode, on QSPI2 — read only.
//
// The board dts calls this an `mmc-spi-slot`, which is SD's SPI protocol: six-byte commands, R1
// responses, and a 0xFE token before each 512-byte data block. This card holds the board's whole
// boot chain (SPL in partition 1, U-Boot in partition 2), so there is deliberately NO write path
// here: CMD24 is not implemented, and nothing in this file can alter the card.
//
// The command set is the same ladder the mask ROM walks, which is why its failure codes are so
// recognisable: CMD0 (0x5 in the ZSBL's numbering), CMD8 (0x6), ACMD41 (0x7), CMD58 (0x8),
// CMD16 (0x9).
#ifndef RV_DRV_SD_SPI_HC
#define RV_DRV_SD_SPI_HC
#define RV_SD_SLOW_DIV 155   /* ~400 kHz for identification */
#define RV_SD_FAST_DIV 4     /* ~12.5 MHz once the card is up */
I64 rv_sd_ready, rv_sd_hc;   /* hc: block-addressed (SDHC/SDXC) rather than byte-addressed */

I64 RVSdXfer(I64 b)
{
  return RVSpiXfer(b);
}

I64 RVSdWaitReady()
{
  //The card holds MISO low while busy; 0xFF means it is listening.
  I64 i = 0, v;
  while (i < 100000) {
    v = RVSdXfer(0xFF);
    if (v == 0xFF)
      return 0;
    i++;
  }
  return -1;
}

I64 RVSdCmd(I64 cmd, U32 arg, I64 crc)
{
  // Six bytes: 0x40|cmd, the argument big-endian, then a CRC7<<1|1. Only CMD0 and CMD8 need a
  // real CRC in SPI mode; the rest are not checked, which is why the constants below are literal.
  I64 i, r;
  RVSdXfer(0xFF);
  RVSdXfer(0x40 | (cmd & 0x3F));
  RVSdXfer((arg >> 24) & 0xFF);
  RVSdXfer((arg >> 16) & 0xFF);
  RVSdXfer((arg >> 8) & 0xFF);
  RVSdXfer(arg & 0xFF);
  RVSdXfer(crc);
  i = 0;
  while (i < 16) {                    // R1 arrives within a few byte times; 0xFF means "not yet"
    r = RVSdXfer(0xFF);
    if (!(r & 0x80))
      return r;
    i++;
  }
  return -1;
}

I64 RVSdInit()
{
  // Returns 1 if a card answered, 0 if not, -1 if there is no controller. Leaves rv_sd_hc set for
  // block addressing. Every step here mirrors the mask ROM's own sequence.
  I64 i, r, ocr;
  if (!RVSpiBase)
    return -1;
  rv_sd_ready = 0;
  rv_sd_hc = 0;
  RVSpiSetup(RV_SD_SLOW_DIV);
  RVSpiCsOff();
  i = 0;
  while (i < 10) {                    // 80 clocks with CS high: the card needs them to wake
    RVSdXfer(0xFF);
    i++;
  }
  RVSpiCsOn();
  r = RVSdCmd(0, 0, 0x95);            // CMD0 GO_IDLE_STATE
  if (r != 1) {
    RVSpiCsOff();
    return 0;
  }
  r = RVSdCmd(8, 0x1AA, 0x87);        // CMD8 SEND_IF_COND
  if (r == 1) {
    RVSdXfer(0xFF);
    RVSdXfer(0xFF);
    RVSdXfer(0xFF);
    RVSdXfer(0xFF);                   // the R7 tail
  }
  i = 0;
  while (i < 20000) {                 // ACMD41 until the card leaves idle
    RVSdCmd(55, 0, 0x65);
    r = RVSdCmd(41, 0x40000000, 0x77);
    if (!r)
      break;
    i++;
  }
  if (r) {
    RVSpiCsOff();
    return 0;
  }
  r = RVSdCmd(58, 0, 0xFD);           // CMD58 READ_OCR: bit 30 is the block-addressing flag
  if (!r) {
    ocr = RVSdXfer(0xFF);
    rv_sd_hc = (ocr >> 6) & 1;
    RVSdXfer(0xFF);
    RVSdXfer(0xFF);
    RVSdXfer(0xFF);
  }
  if (!rv_sd_hc)
    RVSdCmd(16, 512, 0xFF);           // byte-addressed cards need the block length said out loud
  RVSpiCsOff();
  RVSpiSpeed(RV_SD_FAST_DIV);
  rv_sd_ready = 1;
  return 1;
}

I64 RVSdReadBlk(I64 blk, U8 *buf)
{
  //One 512-byte block. Returns 0, or -1 on any failure. Reads only.
  I64 i, r, tok;
  if (!rv_sd_ready)
    return -1;
  RVSpiCsOn();
  if (RVSdWaitReady()) {
    RVSpiCsOff();
    return -1;
  }
  r = RVSdCmd(17, rv_sd_hc ? blk : blk * 512, 0xFF);   // CMD17 READ_SINGLE_BLOCK
  if (r) {
    RVSpiCsOff();
    return -1;
  }
  i = 0;
  tok = 0xFF;
  while (i < 100000) {                // wait for the 0xFE data token
    tok = RVSdXfer(0xFF);
    if (tok != 0xFF)
      break;
    i++;
  }
  if (tok != 0xFE) {
    RVSpiCsOff();
    return -1;
  }
  i = 0;
  while (i < 512) {
    buf[i] = RVSdXfer(0xFF);
    i++;
  }
  RVSdXfer(0xFF);                     // the two CRC bytes, which SPI mode lets us ignore
  RVSdXfer(0xFF);
  RVSpiCsOff();
  return 0;
}
#endif
