// 9P2000.L over raw Ethernet: mount a host share through the GEM, read a file, write one back.
//
// This exercises Kernel/NineP/NinePEth.HC, the third NinePTransport. The point of the seam is that
// everything above it is the same code the virtio gates already cover, so what is under test here
// is only the link: frame in, frame out, tag matched, retried on loss.
//
// The peer is tools/ninep/eth9p.py in --mode qemu, which speaks QEMU's socket netdev framing
// (4-byte big-endian length, then a raw Ethernet frame). No tap device and no privileges, which is
// what makes this runnable as an ordinary gate.
// Virtio9p.HC needs the kernel's CDirEntry, so this takes the whole project the way
// kernel_virtio_9p_demo.hc does. A minimal include set was tried first and cannot work for that
// reason. (The earlier silence from a PRJ image was the hart-1 loader entry, not the include --
// a known-good case failed identically under it, which is what named the real culprit.)
#include "/Kernel/Kernel_RV.PRJ"
U0 Say(U8 *s)
{
  RVUartPutS(s);
}
// No StrPrint here: the minimal include set does not bring it in, and a debugging aid that drags
// half the kernel behind it is not worth the coupling.
U0 SayNum(U8 *label, I64 v)
{
  U8 d[24];
  I64 i = 0, j;
  RVUartPutS(label);
  if (v < 0) {
    RVUartPutS("-");
    v = -v;
  }
  if (!v)
    d[i++] = '0';
  while (v > 0) {
    d[i++] = '0' + v % 10;
    v /= 10;
  }
  j = i;
  while (j > 0) {
    U8 one[2];
    j--;
    one[0] = d[j];
    one[1] = 0;
    RVUartPutS(one);
  }
  RVUartPutS("\n");
}

I64 main()
{
  U8 buf[256];
  I64 rc, n, i;
  RVUartInit();
  Say("ninep-eth: start on ");
  Say(CONFIG_PLATFORM_NAME);
  Say("\n");
  if (!RVSifiveGemPresent) {
    Say("ninep-eth: no GEM\n");
    return 1;
  }
  // Pin the transport. On this machine there is no virtio to prefer, but saying so explicitly is
  // what keeps the virtio gates' probe order untouched.
  ninep_force_tp = NINEP_TP_ETH;
  rc = Virtio9pConnect("holy");
  if (rc) {
    SayNum("ninep-eth: connect_fail rc=", rc);
    return 2;
  }
  Say("ninep-eth: connect_ok\n");
  SayNum("ninep-eth: msize=", ninep_client.msize);
  // msize is the server's answer, and it must be small enough for one frame or the transport
  // could not have carried the Rversion that delivered it.
  if (ninep_client.msize > NINEP_ETH_CAP) {
    Say("ninep-eth: msize too big for a frame\n");
    return 3;
  }
  n = Virtio9pReadPath("test.txt", buf, 256);
  if (n <= 0) {
    SayNum("ninep-eth: read_fail n=", n);
    return 4;
  }
  buf[n] = 0;
  Say("ninep-eth: read_ok data=");
  Say(buf);
  Say("\n");
  rc = Virtio9pWritePath("out.txt", "eth9p-wrote-this", 16);
  if (rc <= 0) {
    SayNum("ninep-eth: write_fail rc=", rc);
    return 5;
  }
  Say("ninep-eth: write_ok\n");
  // Transport counters, so a pass that needed retries is visibly different from a clean one.
  SayNum("ninep-eth: txns=", ninep_eth_txn);
  SayNum("ninep-eth: retries=", ninep_eth_retries);
  return 0;
}
