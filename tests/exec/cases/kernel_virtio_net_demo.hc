// HolyC virtio-mmio net smoke: TX probe + RX drain/cb (self-test) + IRQ ACK.
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
I64 g_rx_cb_hits;
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}

U0 RxHit(U8 *pkt, I64 len)
{
  g_rx_cb_hits++;
  if (pkt && len > 0)
    ;
}

I64 main()
{
  I64 rc, n, pending0;
  g_rx_cb_hits = 0;
  Sh("virtio-net demo: mmio or pci\n");
  if (VirtioNetInit()) {
    Sh("no virtio-net device\n");
    return 0;
  }
  Sh("device up\n");
  rc = VirtioNetTxProbe();
  if (!rc)
    Sh("virtio-net: tx_ok\n");
  else {
    Sh("virtio-net: tx_fail\n");
    return rc;
  }
  VirtioNetIrqAck();
  pending0 = VirtioNetRxPending();
  VirtioNetSetRxCb(&RxHit);
  n = VirtioNetRxSelfTest();
  VirtioNetIrqService();
  if (n > 0 && g_rx_cb_hits > 0 && pending0 == 0)
    Sh("virtio-net: rx_ok\n");
  else
    Sh("virtio-net: rx_fail\n");
  return n > 0 && g_rx_cb_hits > 0 ? 0 : 1;
}
