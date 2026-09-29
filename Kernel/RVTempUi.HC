// Temp() — the board's two thermometers, from a HolyC prompt.
//
// The TMP451 at I2C 0x4c measures itself (the board, near the SoC) and a remote diode inside the
// FU740 (the die). Register 0x00 is the local integer degrees, 0x01 the remote; both are signed
// Celsius. Nothing here writes anything except an I2C register pointer.
#ifndef RV_TEMP_UI_HC
#define RV_TEMP_UI_HC
#help_index "Dbg"
U0 Temp()
{
  //Board and die temperature in degrees C.
  I64 loc, die;
  if (!RVI2cBase) {
    Print("Temp: this board has no I2C I know about\n");
    return;
  }
  loc = RVI2cRd8(RV_I2C_ADDR_TMP451, 0x00);
  die = RVI2cRd8(RV_I2C_ADDR_TMP451, 0x01);
  if (loc < 0 || die < 0) {
    Print("Temp: no answer from the TMP451 at 0x4C (loc=%d die=%d)\n", loc, die);
    Print("      ctr=0x%02X sr=0x%02X prer=0x%02X%02X\n", RVI2cRdReg(RV_I2C_CTR),
          RVI2cRdReg(RV_I2C_CMD), RVI2cRdReg(RV_I2C_PRERHI), RVI2cRdReg(RV_I2C_PRERLO));
    return;
  }
  Print("board %d C   die %d C\n", loc, die);
}
#endif
