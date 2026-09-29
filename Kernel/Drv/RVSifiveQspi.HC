// SiFive QSPI: just enough to turn the direct-mapped flash reader on.
//
// QSPI0 on the FU740 has a second window (0x20000000, 256 MiB) that reads the SPI-NOR as ordinary
// memory -- but only while fctrl.en is set, and firmware leaves it CLEAR. Measured on the board:
// fctrl=0 with ffmt=0x30007, i.e. the flash instruction format is already programmed (SPL needs it
// to load itself) and only the memory-mapped reader was switched off afterwards. So `Dump(0x20000000)`
// reads zeros until this flips one bit.
//
// This is the only write in the file, and it is on the READ path: enabling the mapped reader issues
// no erase and no program command, and the format it reads with was chosen by firmware. Nothing here
// can alter the flash contents.
#ifndef RV_DRV_SIFIVE_QSPI_HC
#define RV_DRV_SIFIVE_QSPI_HC
#ifndef CONFIG_SIFIVE_QSPI0_BASE
#define CONFIG_SIFIVE_QSPI0_BASE 0
#endif
#ifndef CONFIG_SIFIVE_QSPI0_MAP_BASE
#define CONFIG_SIFIVE_QSPI0_MAP_BASE 0
#endif
#define RV_QSPI_FCTRL  0x60   /* bit 0: en — memory-mapped flash reads */
#define RV_QSPI_FFMT   0x64   /* the instruction format those reads use */

I64 RVQspiBase()
{
  return CONFIG_SIFIVE_QSPI0_BASE;
}

I64 RVQspiMapBase()
{
  return CONFIG_SIFIVE_QSPI0_MAP_BASE;
}

I64 RVQspiFctrl()
{
  if (!CONFIG_SIFIVE_QSPI0_BASE)
    return -1;
  return *((CONFIG_SIFIVE_QSPI0_BASE + RV_QSPI_FCTRL)(U32 *));
}

I64 RVQspiFfmt()
{
  if (!CONFIG_SIFIVE_QSPI0_BASE)
    return -1;
  return *((CONFIG_SIFIVE_QSPI0_BASE + RV_QSPI_FFMT)(U32 *));
}

I64 RVQspiFlashMap(I64 on)
{
  //Turn the direct-mapped flash reader on or off. Returns the new fctrl, or -1 if this board has none.
  // The cast form, deliberately. This function used to say
  //     U32 *fctrl; fctrl = CONFIG_SIFIVE_QSPI0_BASE + RV_QSPI_FCTRL;
  // and the host compiler scaled the offset by the pointee size: 0x10040000 + 0x60 came out as
  // 0x10040180, disassembled straight out of the compiler. So every read-modify-write in here
  // went to the wrong register in the QSPI block, while RVQspiFctrl above -- which already used
  // the cast form -- read the right one. That is precisely the "fctrl.en won't set on this
  // board" this port recorded as a hardware quirk: the bit was being written somewhere else and
  // then read back, correctly, as still zero. See tests/exec/cases/e_ptr_assign_const_base.hc.
  I64 fc = CONFIG_SIFIVE_QSPI0_BASE + RV_QSPI_FCTRL;
  if (!CONFIG_SIFIVE_QSPI0_BASE)
    return -1;
  if (on)
    *(fc(U32 *)) = *(fc(U32 *)) | 1;
  else
    *(fc(U32 *)) = *(fc(U32 *)) & ~1;
  return *(fc(U32 *));
}
#endif
