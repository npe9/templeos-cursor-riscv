// HolyC SiFive GEM smoke: TX probe + local-loopback RX drain/cb on sifive_u.
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVSifivePlat.HC"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVSifiveGem.HC"
I64 g_rx_cb_hits;
U0 RxHit(U8 *pkt, I64 len)
{
  g_rx_cb_hits++;
  if (pkt && len > 0)
    ;
}

I64 main()
{
  I64 rc, n;
  g_rx_cb_hits = 0;
  RVUartInit();
  RVUartPutS("sifive-gem demo: ");
  RVUartPutS(CONFIG_PLATFORM_NAME);
  RVUartPutS("\n");
  if (!RVSifiveGemPresent) {
    RVUartPutS("sifive-gem: absent\n");
    return 1;
  }
  if (RVSifiveGemInit()) {
    RVUartPutS("sifive-gem: init_fail\n");
    return 1;
  }
  RVUartPutS("sifive-gem: init_ok\n");
  rc = RVSifiveGemTxProbe();
  if (!rc)
    RVUartPutS("sifive-gem: tx_ok\n");
  else {
    RVUartPutS("sifive-gem: tx_fail\n");
    return rc;
  }
  RVSifiveGemSetRxCb(&RxHit);
  n = RVSifiveGemRxSelfTest();
  if (n > 0 && g_rx_cb_hits > 0)
    RVUartPutS("sifive-gem: rx_ok\n");
  else {
    RVUartPutS("sifive-gem: rx_fail\n");
    return 1;
  }
  RVUartPutS("sifive-gem: PASS\n");
  return 0;
}
