// SiFive GPIO (FU540/FU740 @ 0x10060000, and QEMU's sifive_u) — readable, and writable on purpose.
//
// The point of this file is that the board stops being a list of addresses: Gpio() at the prompt
// prints all 16 lines with the names the BOARD dts gives them, and GpioWr() can drive the ones that
// are safe to drive. See docs/UNMATCHED_JTAG.md for the full name table.
//
// SAFETY, and it is not theoretical. Several of the Unmatched's lines are ACTIVE LOW, and
// output_val resets to 0 -- so merely ENABLING output on one of them drives it low and does the
// thing. Pin 2 is PMICSHDN: enabling output there powers the board off. Pin 14 is EN_VDD_SD;
// 7/9/11/12 are USB-bridge, ULPI, USB-hub and ethernet-PHY resets. The guard therefore keys on the
// output_enable TRANSITION, never on the value the caller asked for: a guarded pin needs GpioArm()
// immediately before each write, and reads never touch output_en at all.
#ifndef RV_SIFIVE_GPIO_HC
#define RV_SIFIVE_GPIO_HC
#ifndef CONFIG_SIFIVE_GPIO_BASE
#define CONFIG_SIFIVE_GPIO_BASE 0
#endif
// Word indices into the U32 register block (the port's older constants use the same convention:
// RVSIFIVE_GPIO_OUTPUT_EN 2, RVSIFIVE_GPIO_PORT 3 -- do not mix these with byte offsets).
#define RV_GPIO_INPUT_VAL   0
#define RV_GPIO_INPUT_EN    1
#define RV_GPIO_OUTPUT_EN   2
#define RV_GPIO_OUTPUT_VAL  3
#define RV_GPIO_PINS        16
// Pins that may be driven without arming. On the HiFive Unmatched these are the header lines
// (J29.1, J8.1..J8.4) and nothing else; every other line runs a rail, a reset or the PMIC.
// Pin 10 is J8.2 on the Unmatched but is QEMU sifive_u's RESET line, so it is guarded too --
// the plat gate runs on both and must not reset the machine it is testing.
#define RV_GPIO_FREE_MASK   0x2019
I64 rv_gpio_armed = 0;

I64 RVGpioBase()
{
  return CONFIG_SIFIVE_GPIO_BASE;
}

U8 *RVGpioName(I64 pin)
{
  // The HiFive Unmatched's gpio-line-names, in order (hifive-unmatched-a00.dts). Other boards get
  // "-"; the names are documentation, never a thing the code branches on. Keyed on the PLATFORM and
  // not on the base address, because QEMU's sifive_u has a GPIO at the same 0x10060000 and its pins
  // are not these -- printing "PMICSHDN" for a pin that is nothing of the kind would be a lie the
  // operator then acts on.
#ifdef CONFIG_PLATFORM_HIFIVE_UNMATCHED
  if (pin < 0 || pin >= RV_GPIO_PINS)
    return "-";
#else
  no_warn pin;
  return "-";
#endif
  switch (pin) {
    case 0:  return "J29.1";
    case 1:  return "PMICNTB";
    case 2:  return "PMICSHDN";
    case 3:  return "J8.1";
    case 4:  return "J8.3";
    case 5:  return "PCIe_PWREN";
    case 6:  return "THERM";
    case 7:  return "UBRDG_RSTN";
    case 8:  return "PCIe_PERSTN";
    case 9:  return "ULPI_RSTN";
    case 10: return "J8.2";
    case 11: return "UHUB_RSTN";
    case 12: return "GEMGXL_RST";
    case 13: return "J8.4";
    case 14: return "EN_VDD_SD";
    case 15: return "SD_CD";
  }
  return "-";
}

I64 RVGpioGuarded(I64 pin)
{
  // TRUE unless the pin is in the free set. Out-of-range counts as guarded: refusing is the safe
  // answer to a bad argument.
  if (pin < 0 || pin >= RV_GPIO_PINS)
    return 1;
  if (RV_GPIO_FREE_MASK & (1 << pin))
    return 0;
  return 1;
}

I64 RVGpioRd(I64 pin)
{
  // input_val only. Does not write input_en: on a line already driven by the board, enabling the
  // input buffer is harmless but pointless, and this function's contract is "changes nothing".
  U32 *g = CONFIG_SIFIVE_GPIO_BASE;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  return (g[RV_GPIO_INPUT_VAL] >> pin) & 1;
}

I64 RVGpioIe(I64 pin)
{
  U32 *g = CONFIG_SIFIVE_GPIO_BASE;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  return (g[RV_GPIO_INPUT_EN] >> pin) & 1;
}

I64 RVGpioIeSet(I64 pin, I64 on)
{
  // Enable or disable the input BUFFER. Unguarded on purpose, including on the rails and resets:
  // input_en drives nothing, it only decides whether input_val reflects the pin. Firmware leaves it
  // clear on this board, which is why a freshly booted Gpio() shows in=0 for lines it is itself
  // holding high -- the level is real, the buffer just is not looking at it.
  U32 *g = CONFIG_SIFIVE_GPIO_BASE, bit;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  bit = 1 << pin;
  if (on)
    g[RV_GPIO_INPUT_EN] = g[RV_GPIO_INPUT_EN] | bit;
  else
    g[RV_GPIO_INPUT_EN] = g[RV_GPIO_INPUT_EN] & ~bit;
  return 1;
}

I64 RVGpioOe(I64 pin)
{
  U32 *g = CONFIG_SIFIVE_GPIO_BASE;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  return (g[RV_GPIO_OUTPUT_EN] >> pin) & 1;
}

I64 RVGpioOut(I64 pin)
{
  U32 *g = CONFIG_SIFIVE_GPIO_BASE;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  return (g[RV_GPIO_OUTPUT_VAL] >> pin) & 1;
}

U0 RVGpioArm()
{
  //Permit ONE guarded write. Consumed whether or not it succeeds.
  rv_gpio_armed = 1;
}

I64 RVGpioWr(I64 pin, I64 val)
{
  // Returns 1 written, 0 refused, -1 no GPIO on this board. The value is set BEFORE output_en so a
  // pin never spends a moment driven to the wrong level; that ordering is the whole reason an
  // active-low rail can be driven high safely.
  U32 *g = CONFIG_SIFIVE_GPIO_BASE, bit;
  I64 was_armed = rv_gpio_armed;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  bit = 1 << pin;
  if (RVGpioGuarded(pin)) {
    rv_gpio_armed = 0;
    if (!was_armed)
      return 0;
  }
  if (val)
    g[RV_GPIO_OUTPUT_VAL] = g[RV_GPIO_OUTPUT_VAL] | bit;
  else
    g[RV_GPIO_OUTPUT_VAL] = g[RV_GPIO_OUTPUT_VAL] & ~bit;
  g[RV_GPIO_OUTPUT_EN] = g[RV_GPIO_OUTPUT_EN] | bit;
  return 1;
}

I64 RVGpioRelease(I64 pin)
{
  // Stop driving: clear output_en. Guarded pins need arming for this too -- releasing a rail the
  // firmware left driven is as much of an event as driving one.
  U32 *g = CONFIG_SIFIVE_GPIO_BASE, bit;
  I64 was_armed = rv_gpio_armed;
  if (!CONFIG_SIFIVE_GPIO_BASE || pin < 0 || pin >= RV_GPIO_PINS)
    return -1;
  bit = 1 << pin;
  if (RVGpioGuarded(pin)) {
    rv_gpio_armed = 0;
    if (!was_armed)
      return 0;
  }
  g[RV_GPIO_OUTPUT_EN] = g[RV_GPIO_OUTPUT_EN] & ~bit;
  return 1;
}

#endif
