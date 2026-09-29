// SiFive L2 cache controller — configuration, and the flush a non-coherent DMA master needs.
//
// Offsets from FU740-C000 Manual v1p6 §14.3: Config 0x000, WayEnable 0x008, Flush64 0x200,
// Flush32 0x240. Flush64 takes a physical address and flushes the block containing it; the manual
// requires all 64 bits be written in a single access for the flush to take effect.
//
// Why this exists: GEM's DMA is NOT coherent on this SoC (the dts marks pcie dma-coherent and
// ethernet not), so descriptor rings and packet buffers in DRAM need flushing by hand. The neat
// alternative -- putting the rings in the L2 LIM at 0x08000000, which is outside the cacheable
// path -- is CLOSED on a board we take over: measured here, WayEnable reads 0x0F, meaning all 16
// ways are already cache, and the manual is explicit that "once a cache way is enabled, it can not
// be" disabled without a reset. The LIM is gone before we arrive.
#ifndef RV_DRV_SIFIVE_L2_HC
#define RV_DRV_SIFIVE_L2_HC
#ifndef CONFIG_SIFIVE_L2_BASE
#define CONFIG_SIFIVE_L2_BASE 0
#endif
#define RV_L2_CONFIG    0x000
#define RV_L2_WAYENABLE 0x008
#define RV_L2_FLUSH64   0x200
#define RV_L2_FLUSH32   0x240

I64 RVL2Base()
{
  return CONFIG_SIFIVE_L2_BASE;
}

I64 RVL2Config()
{
  if (!CONFIG_SIFIVE_L2_BASE)
    return -1;
  return *((CONFIG_SIFIVE_L2_BASE + RV_L2_CONFIG)(U32 *));
}

I64 RVL2WayEnable()
{
  if (!CONFIG_SIFIVE_L2_BASE)
    return -1;
  return *((CONFIG_SIFIVE_L2_BASE + RV_L2_WAYENABLE)(U8 *));
}

U0 RVL2Flush64(I64 addr)
{
  //Flush the cache block containing `addr`. One 64-bit write, as the manual requires.
  if (!CONFIG_SIFIVE_L2_BASE)
    return;
  *((CONFIG_SIFIVE_L2_BASE + RV_L2_FLUSH64)(I64 *)) = addr;
}

U0 RVL2FlushRange(I64 addr, I64 len)
{
  // Every 64-byte block the range touches. The block size is not assumed: Config[23:16] is
  // lgBlockBytes, so a part with a different line size still gets flushed correctly.
  I64 blk = 64, p, end;
  I64 cfg = RVL2Config();
  if (!CONFIG_SIFIVE_L2_BASE)
    return;
  if (cfg > 0)
    blk = 1 << ((cfg >> 24) & 0xFF);
  if (blk < 8 || blk > 4096)
    blk = 64;
  p = addr & ~(blk - 1);
  end = addr + len;
  while (p < end) {
    RVL2Flush64(p);
    p += blk;
  }
}
#endif
