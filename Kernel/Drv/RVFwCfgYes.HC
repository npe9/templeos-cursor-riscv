// QEMU fw_cfg MMIO (virt): data@0 selector@8 dma@16. Base from Kconfig.
#ifndef RV_DRV_FWCFG_YES_HC
#define RV_DRV_FWCFG_YES_HC
#ifndef CONFIG_FW_CFG_BASE
#define CONFIG_FW_CFG_BASE 0x10100000
#endif
#define RV_FWCFG_BASE       CONFIG_FW_CFG_BASE
#define RV_FWCFG_DMA_HI     (CONFIG_FW_CFG_BASE+0x10)
#define RV_FWCFG_DMA_LO     (CONFIG_FW_CFG_BASE+0x14)
#define RV_FWCFG_SIGNATURE  0x00
#define RV_FWCFG_FILE_DIR   0x19
#define RV_FWCFG_DMA_READ   0x02
#define RV_FWCFG_DMA_SELECT 0x08
#define RV_FWCFG_DMA_WRITE  0x10
// fw_cfg DMA descriptor is global: QEMU writes completion asynchronously.
U32 rv_fwcfg_dma_desc[4];
// Size-correct MMIO stores (QEMU fw_cfg hangs on byte/half to some regs).
asm {
	RVFwCfgSw::
	sw	a1,0(a0)
	ret
}

I64 RVFwCfgBase()
{
  return CONFIG_FW_CFG_BASE;
}

Bool RVFwCfgPresent()
{
  return TRUE;
}

U32 RVFwCfgBe32(U32 d)
{
  //Bitmask endian — avoid .u8[] which can miscompile in thin AOT blobs.
  return ((d & 0xFF) << 24) | ((d & 0xFF00) << 8) | ((d >> 8) & 0xFF00) | ((d >> 24) & 0xFF);
}

U16 RVFwCfgBe16(U16 d)
{
  return ((d & 0xFF) << 8) | ((d >> 8) & 0xFF);
}

I64 RVFwCfgBe64(I64 d)
{
  return ((d & 0xFF) << 56) | ((d & 0xFF00) << 40) | ((d & 0xFF0000) << 24) | ((d & 0xFF000000) << 8) | ((d >> 8) & 0xFF000000) | ((d >> 24) & 0xFF0000) | ((d >> 40) & 0xFF00) | ((d >> 56) & 0xFF);
}

U0 RVFwCfgOut32(I64 addr, U32 v)
{
  RVFwCfgSw(addr, v);
}

U0 RVFwCfgDma(U32 control, U32 len, U8 *buf)
{
  //Issue one fw_cfg DMA op. control/len/addr in the descriptor are big-endian.
  I64 phys = &rv_fwcfg_dma_desc;
  I64 be_addr;
  I64 spins = 0;
  rv_fwcfg_dma_desc[0] = RVFwCfgBe32(control);
  rv_fwcfg_dma_desc[1] = RVFwCfgBe32(len);
  be_addr = RVFwCfgBe64(buf);
  rv_fwcfg_dma_desc[2] = be_addr & 0xFFFFFFFF;
  rv_fwcfg_dma_desc[3] = (be_addr >> 32) & 0xFFFFFFFF;
  RVFwCfgOut32(RV_FWCFG_DMA_HI, RVFwCfgBe32 ((phys >> 32) & 0xFFFFFFFF));
  RVFwCfgOut32(RV_FWCFG_DMA_LO, RVFwCfgBe32(phys & 0xFFFFFFFF));
  while (rv_fwcfg_dma_desc[0]) {
    if (RVFwCfgBe32(rv_fwcfg_dma_desc[0]) & 1)
      break;
    spins++;
    if (spins > 1000000)
      break;
  }
}

U0 RVFwCfgSelect(U16 sel)
{
  //16-bit BE selector via aligned 32-bit store of the halfword value.
  RVFwCfgOut32(CONFIG_FW_CFG_BASE + 8, RVFwCfgBe16(sel));
}

U8 RVFwCfgInU8()
{
  U8 *p = CONFIG_FW_CFG_BASE;
  return p[0];
}

Bool RVFwCfgSigOk()
{
  //TRUE if selector 0 reads the QEMU signature "QEMU" via DMA.
  U8 sig[4];
  sig[0] = 0;
  sig[1] = 0;
  sig[2] = 0;
  sig[3] = 0;
  RVFwCfgDma ((RV_FWCFG_SIGNATURE << 16) | RV_FWCFG_DMA_SELECT | RV_FWCFG_DMA_READ, 4, sig);
  return sig[0] == 'Q' && sig[1] == 'E' && sig[2] == 'M' && sig[3] == 'U';
}

I64 RVFwCfgFileCount()
{
  U32 count = 0;
  RVFwCfgDma ((RV_FWCFG_FILE_DIR << 16) | RV_FWCFG_DMA_SELECT | RV_FWCFG_DMA_READ, 4, &count);
  count = RVFwCfgBe32(count);
  if (!count || count > 512)
    return 0;
  return count;
}

I64 RVFwCfgFind(U8 *name)
{
  //Return fw_cfg selector for name, or -1. Walks etc/ file directory.
  U32 count = 0;
  U8 ent[64];
  I64 i, j, sel;
  if (!name)
    return -1;
  RVFwCfgDma ((RV_FWCFG_FILE_DIR << 16) | RV_FWCFG_DMA_SELECT | RV_FWCFG_DMA_READ, 4, &count);
  count = RVFwCfgBe32(count);
  if (!count || count > 512)
    return -1;
  for (i = 0; i < count; i++) {
    RVFwCfgDma(RV_FWCFG_DMA_READ, 64, ent);
    Bool match = TRUE;
    for (j = 0; name[j]; j++)
      if (ent[8 + j] != name[j]) {
        match = FALSE;
        break;
      }
    if (match && !ent[8 + j]) {
      sel = (ent[4] << 8) | ent[5];
      // directory entry select is BE u16 at offset 4
      return sel;
    }
  }
  return -1;
}

Bool RVFwCfgReadSel(I64 sel, U8 *buf, I64 len)
{
  if (sel < 0 || !buf || len <= 0)
    return FALSE;
  RVFwCfgDma ((sel << 16) | RV_FWCFG_DMA_SELECT | RV_FWCFG_DMA_READ, len, buf);
  return TRUE;
}

Bool RVFwCfgWriteSel(I64 sel, U8 *buf, I64 len)
{
  if (sel < 0 || !buf || len <= 0)
    return FALSE;
  RVFwCfgDma ((sel << 16) | RV_FWCFG_DMA_SELECT | RV_FWCFG_DMA_WRITE, len, buf);
  return TRUE;
}
#endif
