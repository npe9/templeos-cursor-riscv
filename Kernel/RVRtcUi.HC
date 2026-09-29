// Rtc() — the battery-backed clock, which on this board lives inside the PMIC.
//
// The HiFive Unmatched has no standalone RTC: hifive-unmatched-a00.dts puts `dlg,da9063-rtc` inside
// the PMIC at I2C 0x58, kept alive by the coin cell. So the port's RTC line reading "0x0 RVRtcNo"
// was true only in the sense that there is no *goldfish* RTC (that is a QEMU device) -- the board's
// clock was simply somewhere this code had never looked.
//
// DA9063 counters are six consecutive registers from 0x40: seconds, minutes, hours, day, month,
// year (year counts from 2000). Reads only.
#ifndef RV_RTC_UI_HC
#define RV_RTC_UI_HC
#help_index "Dbg"
#define RV_DA9063_COUNT_S  0x40
U0 Rtc()
{
  //Date and time from the PMIC's battery-backed counters.
  I64 sec, mi, hr, dy, mo, yr;
  if (!RVI2cBase) {
    Print("Rtc: no I2C on this board\n");
    return;
  }
  sec = RVI2cRd8(RV_I2C_ADDR_PMIC, RV_DA9063_COUNT_S);
  mi  = RVI2cRd8(RV_I2C_ADDR_PMIC, RV_DA9063_COUNT_S + 1);
  hr  = RVI2cRd8(RV_I2C_ADDR_PMIC, RV_DA9063_COUNT_S + 2);
  dy  = RVI2cRd8(RV_I2C_ADDR_PMIC, RV_DA9063_COUNT_S + 3);
  mo  = RVI2cRd8(RV_I2C_ADDR_PMIC, RV_DA9063_COUNT_S + 4);
  yr  = RVI2cRd8(RV_I2C_ADDR_PMIC, RV_DA9063_COUNT_S + 5);
  if (sec < 0 || yr < 0) {
    Print("Rtc: no answer from the DA9063 at 0x58 (s=%d y=%d)\n", sec, yr);
    return;
  }
  // Each counter carries flag bits above its field: seconds/minutes 6 bits, hours 5, day 5,
  // month 4, year 6. Mask them rather than printing a plausible-looking wrong number.
  Print("%04d-%02d-%02d %02d:%02d:%02d  (DA9063, battery backed)\n",
        2000 + (yr & 0x3F), mo & 0x0F, dy & 0x1F, hr & 0x1F, mi & 0x3F, sec & 0x3F);
  Print("  raw s=%02X mi=%02X h=%02X d=%02X mo=%02X y=%02X\n", sec, mi, hr, dy, mo, yr);
}
#endif
