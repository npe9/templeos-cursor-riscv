// Gpio() / PowerOff() — the prompt-facing half of the SiFive GPIO driver.
//
// Kept apart from Kernel/Drv/RVSifiveGpio.HC because that file is included by the thin plat image,
// which has no Print (its output is RVUartPutS straight at the board's UART). Registers live in the
// driver; anything that formats lives here.
#ifndef RV_GPIO_UI_HC
#define RV_GPIO_UI_HC
#help_index "Dbg"
U0 Gpio()
{
  //All 16 GPIO lines: the board's name for each, the level read back, and whether we drive it.
  I64 i;
  if (!RVGpioBase) {
    Print("Gpio: this board has no SiFive GPIO (CONFIG_SIFIVE_GPIO_BASE is 0)\n");
    return;
  }
  Print("GPIO @ 0x%08X   ie=input buffer on, in=level seen, oe=we drive it, out=level we drive\n", RVGpioBase);
  Print("                   in reads 0 while ie=0 whatever the pin does — GpioIe(pin,1) to look\n");
  i = 0;
  while (i < RV_GPIO_PINS) {
    if (RVGpioIe(i))
      Print("  %2d %-12s ie=1 in=%d oe=%d out=%d%s\n",
            i, RVGpioName(i), RVGpioRd(i), RVGpioOe(i), RVGpioOut(i),
            RVGpioGuarded(i) ? "  [guarded: GpioArm first]" : "");
    else
      Print("  %2d %-12s ie=0 in=? oe=%d out=%d%s\n",
            i, RVGpioName(i), RVGpioOe(i), RVGpioOut(i),
            RVGpioGuarded(i) ? "  [guarded: GpioArm first]" : "");
    i++;
  }
}

U0 PowerOff()
{
  //Drive PMICSHDN (pin 2, active low) low. The board switches off; nothing returns from here.
#ifndef CONFIG_PLATFORM_HIFIVE_UNMATCHED
  // Same reason as the name table: sifive_u shares the base address and shares none of the wiring.
  Print("PowerOff: only wired for the HiFive Unmatched's PMICSHDN\n");
  return;
#else
  if (!RVGpioBase) {
    Print("PowerOff: no GPIO on this board\n");
    return;
  }
#endif
  Print("PowerOff: driving PMICSHDN low - goodbye\n");
  RVGpioArm;
  RVGpioWr(2, 0);
  while (TRUE)
    ;
}
#endif
