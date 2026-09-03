// No QEMU fw_cfg on this board.
#ifndef RV_DRV_FWCFG_NO_HC
#define RV_DRV_FWCFG_NO_HC
#define RV_FWCFG_SIGNATURE  0x00
#define RV_FWCFG_FILE_DIR   0x19
#define RV_FWCFG_DMA_READ   0x02
#define RV_FWCFG_DMA_SELECT 0x08
#define RV_FWCFG_DMA_WRITE  0x10
U32 rv_fwcfg_dma_desc[4];
I64 RVFwCfgBase()
{
  return 0;
}

Bool RVFwCfgPresent()
{
  return FALSE;
}

U0 RVFwCfgDma(U32 control, U32 len, U8 *buf)
{
}

U0 RVFwCfgSelect(U16 sel)
{
}

U8 RVFwCfgInU8()
{
  return 0;
}

Bool RVFwCfgSigOk()
{
  return FALSE;
}

I64 RVFwCfgFileCount()
{
  return 0;
}

I64 RVFwCfgFind(U8 *name)
{
  return -1;
}

Bool RVFwCfgReadSel(I64 sel, U8 *buf, I64 len)
{
  return FALSE;
}

Bool RVFwCfgWriteSel(I64 sel, U8 *buf, I64 len)
{
  return FALSE;
}
#endif
