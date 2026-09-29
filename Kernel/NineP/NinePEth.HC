// NinePEth.HC — 9P2000.L over raw Ethernet, as a third NinePTransport.
//
// Why this exists: on the HiFive Unmatched there is no virtio, so the two existing transports
// (virtio-mmio, virtio-pci) cannot bind. But the GEM transmits and receives on this board --
// verified on the wire, a frame captured by the router and a frame from the router decoded here --
// and the 9P client above is transport-agnostic by construction. So the board gets a real remote
// filesystem for the price of a send/recv pair, with the 721 lines of protocol untouched.
//
// Two properties of 9P make this much smaller than it sounds:
//   1. Messages are SELF-DELIMITING -- the first four bytes are the total size -- so a datagram
//      link needs no framing of its own, and a byte-stream link would need none either.
//   2. It is strictly request/response with a 16-bit tag. One outstanding request at a time means
//      reliability is a timeout and a retry, matched on that tag. No sequence numbers, no TCP.
//
// What this is NOT: a network stack. There is no ARP, no IP, no UDP. The peer is found by sending
// the first request to broadcast and remembering the source address of whatever answers.
#ifndef NINEP_ETH_HC
#define NINEP_ETH_HC
#include "NineP.HH"
#define NINEP_ETH_HDR    14
#define NINEP_ETH_MINFRM 60
// Retry budget. 9P over a switched LAN loses frames rarely, but "rarely" is not "never" and a
// hung mount is a much worse failure than a slow one.
#define NINEP_ETH_TRIES  4
#define NINEP_ETH_WAIT_MS 250
U8 ninep_eth_req[NINEP_ETH_CAP];
U8 ninep_eth_rsp[NINEP_ETH_CAP];
U8 ninep_eth_frm[NINEP_ETH_CAP + NINEP_ETH_HDR];
U8 ninep_eth_peer[6];
I64 ninep_eth_have_peer;
I64 ninep_eth_txn;
I64 ninep_eth_retries;

U8 *NinePEthReq()
{
  return ninep_eth_req;
}

U8 *NinePEthRsp()
{
  return ninep_eth_rsp;
}

I64 NinePEthInit()
{
  I64 i;
  if (!RVSifiveGemPresent)
    return -1;
  if (RVSifiveGemInit)
    return -2;
  for (i = 0; i < 6; i++)
    ninep_eth_peer[i] = 0xFF;
  ninep_eth_have_peer = 0;
  ninep_eth_txn = 0;
  ninep_eth_retries = 0;
  return 0;
}
// The mount tag. Nothing on a raw link advertises one the way virtio's config space does, so this
// is a fixed name the server is expected to serve. Kept short and obvious.
I64 NinePEthMountTag(U8 *buf, I64 cap)
{
  if (!buf || cap < 5)
    return -1;
  StrCpy(buf, "holy");
  return 4;
}

U0 NinePEthBuildFrame(I64 req_len)
{
  I64 i;
  for (i = 0; i < 6; i++)
    ninep_eth_frm[i] = ninep_eth_peer[i];
  // Source: the MAC RVSifiveGemInit programs. Not the board's EEPROM address -- the rings use
  // 02:00:00:00:00:01, and the server must reply to that or nothing comes back.
  ninep_eth_frm[6] = 0x02;
  ninep_eth_frm[7] = 0x00;
  ninep_eth_frm[8] = 0x00;
  ninep_eth_frm[9] = 0x00;
  ninep_eth_frm[10] = 0x00;
  ninep_eth_frm[11] = 0x01;
  ninep_eth_frm[12] = (NINEP_ETH_TYPE >> 8) & 0xFF;
  ninep_eth_frm[13] = NINEP_ETH_TYPE & 0xFF;
  for (i = 0; i < req_len; i++)
    ninep_eth_frm[NINEP_ETH_HDR + i] = ninep_eth_req[i];
  // Pad to the Ethernet minimum. The 9P size field says where the message really ends, so the
  // padding is invisible to the protocol.
  i = NINEP_ETH_HDR + req_len;
  while (i < NINEP_ETH_MINFRM) {
    ninep_eth_frm[i] = 0;
    i++;
  }
}
// One request, one response, with retries. Returns the response length, or negative.
I64 NinePEthSendRecv(I64 req_len)
{
  U8 rx[NINEP_ETH_CAP + NINEP_ETH_HDR];
  I64 flen, n, i, want_tag, got_tag, rsp_len, deadline, tries, sent;
  if (req_len < 7 || req_len > NINEP_ETH_CAP)
    return -1;
  // size[4] type[1] tag[2] -- the tag we must see echoed.
  want_tag = ninep_eth_req[5] | (ninep_eth_req[6] << 8);
  NinePEthBuildFrame(req_len);
  flen = NINEP_ETH_HDR + req_len;
  if (flen < NINEP_ETH_MINFRM)
    flen = NINEP_ETH_MINFRM;
  tries = 0;
  while (tries < NINEP_ETH_TRIES) {
    if (tries)
      ninep_eth_retries++;
    sent = RVSifiveGemTx(ninep_eth_frm, flen);
    if (sent) {
      tries++;
      continue;
    }
    deadline = GetTSC + CONFIG_TIMEBASE_FREQ / 1000 * NINEP_ETH_WAIT_MS;
    while (GetTSC < deadline) {
      if (!RVSifiveGemRxPending)
        continue;
      n = RVSifiveGemRx(rx, NINEP_ETH_CAP + NINEP_ETH_HDR);
      if (n < NINEP_ETH_HDR + 7)
        continue;
      if (rx[12] != ((NINEP_ETH_TYPE >> 8) & 0xFF) || rx[13] != (NINEP_ETH_TYPE & 0xFF))
        continue;
      got_tag = rx[NINEP_ETH_HDR + 5] | (rx[NINEP_ETH_HDR + 6] << 8);
      if (got_tag != want_tag)
        continue;
      rsp_len = rx[NINEP_ETH_HDR] | (rx[NINEP_ETH_HDR + 1] << 8) |
                (rx[NINEP_ETH_HDR + 2] << 16) | (rx[NINEP_ETH_HDR + 3] << 24);
      if (rsp_len < 7 || rsp_len > NINEP_ETH_CAP || rsp_len > n - NINEP_ETH_HDR)
        continue;
      for (i = 0; i < rsp_len; i++)
        ninep_eth_rsp[i] = rx[NINEP_ETH_HDR + i];
      // Learn the peer from the first thing that answers, then stop broadcasting.
      if (!ninep_eth_have_peer) {
        for (i = 0; i < 6; i++)
          ninep_eth_peer[i] = rx[6 + i];
        ninep_eth_have_peer = 1;
      }
      ninep_eth_txn++;
      return rsp_len;
    }
    tries++;
  }
  return -2;
}
#endif
