// SiFive PWM — four compare channels per block, enough to blink something.
//
// The Unmatched enables pwm0 and pwm1 in its dts but names no consumer, so which channel reaches
// which LED or fan header is not documented anywhere this port can read. That makes it an
// experiment rather than a lookup: set a duty on a channel and see what changes. Harmless either
// way -- these outputs go to LED and fan headers, not to a rail.
#ifndef RV_DRV_SIFIVE_PWM_HC
#define RV_DRV_SIFIVE_PWM_HC
#ifndef CONFIG_SIFIVE_PWM0_BASE
#define CONFIG_SIFIVE_PWM0_BASE 0
#endif
#define RV_PWM_CFG    0x00
#define RV_PWM_COUNT  0x08
#define RV_PWM_S      0x10
#define RV_PWM_CMP0   0x20   /* cmp1..cmp3 follow at +4 each */
#define RV_PWM_CFG_SCALE   0x0F
#define RV_PWM_CFG_ZEROCMP 0x200
#define RV_PWM_CFG_ENALWAYS 0x1000
// pwm0 drives BOTH of this board's user LEDs (SiFive forum thread 5075, and measured here):
//   D2  an RGB LED  -- channels 1/2/3, found by driving each and looking: green, red, blue
//   D12 a single LED -- channel 0
// pwm1 is not LEDs at all: only PWM1_0 leaves the SoC, onto the expansion header.
//
// Channel 0 needs the counter FREE-RUNNING. With zerocmp set, cmp0 is the period and its own
// output only pulses at each wrap -- which is exactly why D12 is described as "flashing orange"
// by people who never set it. Free-running makes all four channels ordinary comparators against a
// 16-bit ramp, so duty is scaled up by 256 to match.
#define RV_LED_GREEN 1
#define RV_LED_RED   2
#define RV_LED_BLUE  3
#define RV_LED_D12   0
#define RV_PWM_SCALE_FREE 2   /* 16-bit ramp at scale 2 is a few kHz: no visible flicker */

#ifndef CONFIG_SIFIVE_PWM1_BASE
#define CONFIG_SIFIVE_PWM1_BASE 0
#endif

I64 RVPwmBase()
{
  return CONFIG_SIFIVE_PWM0_BASE;
}

I64 RVPwmBlockBase(I64 blk)
{
  //Channels are numbered 0..7 across the two blocks: 0-3 are pwm0, 4-7 are pwm1.
  if (blk)
    return CONFIG_SIFIVE_PWM1_BASE;
  return CONFIG_SIFIVE_PWM0_BASE;
}

U32 RVPwmRd(I64 off)
{
  if (!CONFIG_SIFIVE_PWM0_BASE)
    return 0;
  return *((CONFIG_SIFIVE_PWM0_BASE + off)(U32 *));
}

U0 RVPwmWr(I64 off, U32 v)
{
  if (!CONFIG_SIFIVE_PWM0_BASE)
    return;
  *((CONFIG_SIFIVE_PWM0_BASE + off)(U32 *)) = v;
}

I64 RVPwmFreeSet(I64 ch, I64 duty)
{
  // All four channels of pwm0 as plain brightness, including channel 0 (D12). The counter runs to
  // its full 16 bits instead of being reset by cmp0, so every compare is just a threshold on the
  // ramp. Active low, like the RGB legs: a bigger compare means more time un-asserted, means
  // brighter.
  I64 base = CONFIG_SIFIVE_PWM0_BASE, v;
  if (!base)
    return -1;
  if (ch < 0 || ch > 3)
    return 0;
  if (duty < 0)
    duty = 0;
  if (duty > 255)
    duty = 255;
  v = duty << 8;
  if (duty >= 255)
    v = 0xFFFF;
  *((base + RV_PWM_CMP0 + ch * 4)(U32 *)) = v;
  *((base + RV_PWM_CFG)(U32 *)) = RV_PWM_SCALE_FREE | RV_PWM_CFG_ENALWAYS;   // no zerocmp
  return 1;
}

I64 RVPwmAnySet(I64 ch, I64 duty)
{
  // ch 0..7 across both blocks; within a block only 1..3 are usable while cmp0 serves as the
  // period. Returns 1, 0 if that channel is not usable, -1 if the block is absent.
  I64 base = RVPwmBlockBase(ch / 4), idx = ch % 4;
  if (!base)
    return -1;
  if (!idx)
    return 0;                                   // cmp0 is the period here, not a free channel
  if (duty < 0)
    duty = 0;
  if (duty > 255)
    duty = 255;
  *((base + RV_PWM_CMP0)(U32 *)) = 255;
  if (duty >= 255)
    *((base + RV_PWM_CMP0 + idx * 4)(U32 *)) = 0xFFFF;
  else
    *((base + RV_PWM_CMP0 + idx * 4)(U32 *)) = duty;
  *((base + RV_PWM_CFG)(U32 *)) = 8 | RV_PWM_CFG_ZEROCMP | RV_PWM_CFG_ENALWAYS;
  return 1;
}

I64 RVPwmSet(I64 ch, I64 duty)
{
  // duty 0..255 on channel 1..3 (cmp0 is the period). Returns 1, or -1 if there is no PWM here.
  // scale 8 with a 16-bit counter gives a few hundred Hz off the bus clock -- fast enough that an
  // LED looks steady and a fan spins, slow enough to see a blink when driven by hand.
  if (!CONFIG_SIFIVE_PWM0_BASE)
    return -1;
  if (ch < 1 || ch > 3)
    return -1;
  if (duty < 0)
    duty = 0;
  if (duty > 255)
    duty = 255;
  RVPwmWr(RV_PWM_CMP0, 255);                                       // period
  // MEASURED on a HiFive Unmatched, because the obvious mapping is backwards here. The pin asserts
  // while "counter >= compare", and these LEDs are ACTIVE LOW: with compare 0 the pin is asserted
  // the whole time and the LED is DARK; with the compare out of reach it is never asserted and the
  // LED is fully lit. So brightness rises WITH the compare value, and duty maps straight onto it.
  // Read back live: cmp=0 dark, cmp=0xFFFF bright green, pwms counting.
  if (duty >= 255)
    RVPwmWr(RV_PWM_CMP0 + ch * 4, 0xFFFF);                         // always lit
  else
    RVPwmWr(RV_PWM_CMP0 + ch * 4, duty);                           // 0 = dark
  RVPwmWr(RV_PWM_CFG, 8 | RV_PWM_CFG_ZEROCMP | RV_PWM_CFG_ENALWAYS);
  return 1;
}

I64 RVPwmOff()
{
  if (!CONFIG_SIFIVE_PWM0_BASE)
    return -1;
  RVPwmWr(RV_PWM_CFG, 0);
  return 1;
}
#endif
