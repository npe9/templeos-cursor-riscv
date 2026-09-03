// NinePTransport.HC — NinePTransport dispatch (send/recv + mount_tag hooks).
#ifndef NINEP_TRANSPORT_HC
#define NINEP_TRANSPORT_HC
#include "NineP.HH"
U8 *ninep_req_buf;
U8 *ninep_rsp_buf;
I64 ninep_tp_kind;
I64 NinePTransportSendRecv(I64 req_len)
{
  if (ninep_tp_kind == NINEP_TP_MMIO)
    return NinePVirtioMmioSendRecv(req_len);
  if (ninep_tp_kind == NINEP_TP_PCI)
    return NinePVirtioPciSendRecv(req_len);
  return -1;
}

I64 NinePTransportMountTag(U8 *buf, I64 cap)
{
  if (ninep_tp_kind == NINEP_TP_MMIO)
    return NinePVirtioMmioMountTag(buf, cap);
  if (ninep_tp_kind == NINEP_TP_PCI)
    return NinePVirtioPciMountTag(buf, cap);
  return -1;
}

I64 NinePTransportBindMmio()
{
  I64 rc;
  rc = NinePVirtioMmioInit();
  if (rc)
    return rc;
  ninep_tp_kind = NINEP_TP_MMIO;
  ninep_req_buf = NinePVirtioMmioReq();
  ninep_rsp_buf = NinePVirtioMmioRsp();
  return 0;
}

I64 NinePTransportBindPci()
{
  I64 rc;
  rc = NinePVirtioPciInit();
  if (rc)
    return rc;
  ninep_tp_kind = NINEP_TP_PCI;
  ninep_req_buf = NinePVirtioPciReq();
  ninep_rsp_buf = NinePVirtioPciRsp();
  return 0;
}
// Prefer MMIO (legacy virtio-9p-device); fall back to PCI when no mmio slot.
I64 NinePTransportBindAny()
{
  if (!NinePTransportBindMmio())
    return 0;
  return NinePTransportBindPci();
}
#endif
