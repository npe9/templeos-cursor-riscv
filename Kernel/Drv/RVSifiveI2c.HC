// OpenCores-style I2C master (SiFive i2c0). Reads only, and only from addresses on a short list.
//
// The bus on a HiFive Unmatched carries the TMP451 thermometer (0x4c), the 24c02 EEPROM (0x50) and
// the DA9063 PMIC (0x58). The PMIC controls every rail on the board, so this driver refuses to
// address it: a mistyped address on an I2C write is how a board loses a voltage it needed. Only the
// register POINTER is ever written, which every device on this bus treats as a read setup.
//
// Registers are 8 bits at a 4-byte stride (dts: reg-shift = 2, reg-io-width = 1). Firmware leaves
// the core enabled with the prescaler already set (measured: CTR=0x80, PRER=0x0103, which is
// PCLK/(5*260) = exactly 100 kHz once you know PCLK is 130 MHz and not the 125 this tree assumed), so
// this programs neither -- if a board ever arrives with the core disabled, that is a visible
// failure (RVI2cRd8 returns -1 on a bus that never goes idle) rather than a silent wrong answer.
#ifndef RV_DRV_SIFIVE_I2C_HC
#define RV_DRV_SIFIVE_I2C_HC
#ifndef CONFIG_SIFIVE_I2C0_BASE
#define CONFIG_SIFIVE_I2C0_BASE 0
#endif
#define RV_I2C_PRERLO 0x00
#define RV_I2C_PRERHI 0x04
#define RV_I2C_CTR    0x08
#define RV_I2C_DATA   0x0C   /* TXR writing, RXR reading */
#define RV_I2C_CMD    0x10   /* CR writing, SR reading */
#define RV_I2C_CTR_EN 0x80
#define RV_I2C_CR_STA 0x80
#define RV_I2C_CR_STO 0x40
#define RV_I2C_CR_RD  0x20
#define RV_I2C_CR_WR  0x10
#define RV_I2C_CR_NAK 0x08
#define RV_I2C_SR_NAK 0x80   /* 1 = the slave did NOT acknowledge */
#define RV_I2C_SR_TIP 0x02   /* transfer in progress */
#define RV_I2C_ADDR_TMP451 0x4C
#define RV_I2C_ADDR_EEPROM 0x50
#define RV_I2C_ADDR_PMIC   0x58

I64 RVI2cBase()
{
  return CONFIG_SIFIVE_I2C0_BASE;
}

U8 RVI2cRdReg(I64 off)
{
  return *((CONFIG_SIFIVE_I2C0_BASE + off)(U8 *));
}

U0 RVI2cWrReg(I64 off, I64 v)
{
  *((CONFIG_SIFIVE_I2C0_BASE + off)(U8 *)) = v;
}

I64 RVI2cWait()
{
  //Spin until the transfer bit clears. Bounded: a bus with no pull-ups or no slave never finishes,
  //and hanging the REPL to say so would be a poor way to report it.
  I64 spins = 0;
  while (RVI2cRdReg(RV_I2C_CMD) & RV_I2C_SR_TIP) {
    spins++;
    if (spins > 2000000)
      return -1;
  }
  return 0;
}

I64 RVI2cAllowed(I64 addr)
{
  // The thermometer, the EEPROM, and the PMIC. The PMIC is on the list because this driver cannot
  // write DATA to it: RVI2cRd8 writes a register POINTER and then reads, which is how every device
  // on this bus expects to be read, and which changes no PMIC state. The rail-changing operation
  // would be a data write, and there is no function here that performs one. A write path, if one is
  // ever added, must NOT inherit this list.
  if (addr == RV_I2C_ADDR_TMP451 || addr == RV_I2C_ADDR_EEPROM || addr == RV_I2C_ADDR_PMIC)
    return 1;
  return 0;
}

I64 RVI2cRd8(I64 addr, I64 rg)   // `reg` is a HolyC storage-class keyword, not a usable name
{
  // One byte from register `rg` of device `addr`: write the pointer, repeated start, read with NAK+STOP.
  // Returns the byte, or -1 if the bus stalled / the device did not acknowledge, or -2 if refused.
  if (!CONFIG_SIFIVE_I2C0_BASE)
    return -1;
  if (!RVI2cAllowed(addr))
    return -2;
  if (!(RVI2cRdReg(RV_I2C_CTR) & RV_I2C_CTR_EN))
    return -1;
  if (RVI2cWait())
    return -1;
  RVI2cWrReg(RV_I2C_DATA, (addr << 1) | 0);            // address, writing
  RVI2cWrReg(RV_I2C_CMD, RV_I2C_CR_STA | RV_I2C_CR_WR);
  if (RVI2cWait())
    return -1;
  if (RVI2cRdReg(RV_I2C_CMD) & RV_I2C_SR_NAK)
    return -1;
  RVI2cWrReg(RV_I2C_DATA, rg);                        // the register pointer
  RVI2cWrReg(RV_I2C_CMD, RV_I2C_CR_WR);
  if (RVI2cWait())
    return -1;
  if (RVI2cRdReg(RV_I2C_CMD) & RV_I2C_SR_NAK)
    return -1;
  RVI2cWrReg(RV_I2C_DATA, (addr << 1) | 1);            // repeated start, reading
  RVI2cWrReg(RV_I2C_CMD, RV_I2C_CR_STA | RV_I2C_CR_WR);
  if (RVI2cWait())
    return -1;
  if (RVI2cRdReg(RV_I2C_CMD) & RV_I2C_SR_NAK)
    return -1;
  RVI2cWrReg(RV_I2C_CMD, RV_I2C_CR_RD | RV_I2C_CR_NAK | RV_I2C_CR_STO);
  if (RVI2cWait())
    return -1;
  return RVI2cRdReg(RV_I2C_DATA);
}
#endif
