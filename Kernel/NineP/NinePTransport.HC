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
  return -1;
}

I64 NinePTransportMountTag(U8 *buf, I64 cap)
{
  if (ninep_tp_kind == NINEP_TP_MMIO)
    return NinePVirtioMmioMountTag(buf, cap);
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
  ninep_tp_kind = NINEP_TP_PCI;
  return NinePVirtioPciInit();
}
#endif
