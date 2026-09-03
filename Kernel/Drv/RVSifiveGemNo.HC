// No SiFive GEM on this board (CONFIG_SIFIVE_ETH_BASE == 0).
#include "RVSifiveGem.HH"
I64 sifive_gem_base;
I64 sifive_gem_rx_pkts;
U0 (*sifive_gem_rx_cb)(U8 *pkt, I64 len);
I64 RVSifiveGemBase()
{
  return 0;
}

Bool RVSifiveGemPresent()
{
  return FALSE;
}

I64 RVSifiveGemIrqNum()
{
  return 0;
}

U0 RVSifiveGemSetRxCb(U0 (*fp)(U8 *pkt, I64 len))
{
  sifive_gem_rx_cb = fp;
}

I64 RVSifiveGemInit()
{
  sifive_gem_base = 0;
  return -1;
}

I64 RVSifiveGemTx(U8 *pkt, I64 len)
{
  return -1;
}

I64 RVSifiveGemRxPending()
{
  return 0;
}

I64 RVSifiveGemRx(U8 *pkt, I64 cap)
{
  return -1;
}

I64 RVSifiveGemRxDrain(I64 max)
{
  return 0;
}

I64 RVSifiveGemTxProbe()
{
  return -1;
}

I64 RVSifiveGemRxSelfTest()
{
  return -1;
}
