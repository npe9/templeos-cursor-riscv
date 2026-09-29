// Sd() / SdRd() — the SD card at the prompt.
//
// Verification is built in: this board's card carries a GPT whose partition types are SiFive's own
// (5b193300-… = the SPL, 2e54b353-… = U-Boot), so block 0 must begin with a protective MBR ending
// 0x55 0xAA and block 1 must begin with "EFI PART". If those appear, the whole path -- controller,
// chip select, command ladder, block read -- is right, and not merely plausible.
#ifndef RV_SD_UI_HC
#define RV_SD_UI_HC
#help_index "Dbg"
U0 Sd()
{
  //Bring the card up and say what it is. Read-only: this card holds the board's boot chain.
  I64 r;
  U8 buf[512];
  if (!RVSpiBase) {
    Print("Sd: no QSPI2 on this board\n");
    return;
  }
  r = RVSdInit();
  if (r <= 0) {
    Print("Sd: no card answered (RVSdInit=%d). Is one in the slot? GpioRd(15) reads SD_CD.\n", r);
    return;
  }
  Print("Sd: card up, %s addressing\n", rv_sd_hc ? "block (SDHC/SDXC)" : "byte (SDSC)");
  if (RVSdReadBlk(0, buf)) {
    Print("Sd: block 0 would not read\n");
    return;
  }
  Print("  block 0: %02X %02X %02X %02X ... %02X %02X  %s\n", buf[0], buf[1], buf[2], buf[3],
        buf[510], buf[511], (buf[510] == 0x55 && buf[511] == 0xAA) ? "(MBR signature)" : "");
  if (RVSdReadBlk(1, buf)) {
    Print("  block 1 would not read\n");
    return;
  }
  if (buf[0] == 'E' && buf[1] == 'F' && buf[2] == 'I' && buf[3] == ' ')
    Print("  block 1: EFI PART — a GPT, as this board's card should have\n");
  else
    Print("  block 1: %02X %02X %02X %02X (not a GPT header)\n", buf[0], buf[1], buf[2], buf[3]);
}

U0 SdRd(I64 blk = 0)
{
  //Dump one 512-byte block as hex and ASCII, four lines' worth.
  U8 buf[512];
  I64 i, j, ch;
  if (!rv_sd_ready && RVSdInit() <= 0) {
    Print("SdRd: no card\n");
    return;
  }
  if (RVSdReadBlk(blk, buf)) {
    Print("SdRd: block %d would not read\n", blk);
    return;
  }
  Print("block %d:\n", blk);
  i = 0;
  while (i < 4) {
    Print("  %03X ", i * 16);
    j = 0;
    while (j < 16) {
      Print("%02X ", buf[i * 16 + j]);
      j++;
    }
    Print(" ");
    j = 0;
    while (j < 16) {
      ch = buf[i * 16 + j];
      if (ch >= 0x20 && ch < 0x7F)
        Print("%c", ch);
      else
        Print(".");
      j++;
    }
    Print("\n");
    i++;
  }
}
#endif
