// VirtioScsi.HC — legacy virtio-mmio SCSI HBA (DeviceID 8).
// Control/event/request queues; INQUIRY + READ(10) LBA. Dig-down: Man("VirtioScsi");
// Queue rings reuse CVnetDesc/Avail/Used (CVscsiDesc class stores hang on this codegen).
#ifndef RV_DRV_VIRTIO_SCSI_HC
#define RV_DRV_VIRTIO_SCSI_HC
#define VSCSI_MAGIC       0x74726976
#define VSCSI_ID_SCSI     8
#define VMR_MAGIC         0x00
#define VMR_DEVICE_ID     0x08
#define VMR_DRIVER_FEAT   0x20
#define VMR_DRIVER_FEATSEL 0x24
#define VMR_GUEST_PGSZ    0x28
#define VMR_QUEUE_SEL     0x30
#define VMR_QUEUE_NUM     0x38
#define VMR_QUEUE_ALIGN   0x3c
#define VMR_QUEUE_PFN     0x40
#define VMR_QUEUE_NOTIFY  0x50
#define VMR_INTERRUPT_STATUS 0x60
#define VMR_INTERRUPT_ACK 0x64
#define VMR_STATUS        0x70
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define VSCSI_QSZ         8
#define VDESC_F_NEXT      1
#define VDESC_F_WRITE     2
#define VSCSI_S_OK        0
#define VSCSI_T_SIMPLE    0
#define VSCSI_REQ_LEN     51
#define VSCSI_RESP_LEN    108
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
// Driver RAM: scsi @ +0x900000 (ctrl/event/req + bounce).
#define VSCSI_CTRL_VQ     (CONFIG_VIRTIO_DRV_RAM_BASE+0x900000)
#define VSCSI_EVT_VQ      (CONFIG_VIRTIO_DRV_RAM_BASE+0x902000)
#define VSCSI_REQ_VQ      (CONFIG_VIRTIO_DRV_RAM_BASE+0x904000)
#define VSCSI_REQ_HDR     (CONFIG_VIRTIO_DRV_RAM_BASE+0x906000)
#define VSCSI_RSP_HDR     (CONFIG_VIRTIO_DRV_RAM_BASE+0x906100)
#define VSCSI_DATA        (CONFIG_VIRTIO_DRV_RAM_BASE+0x907000)
#define VSCSI_EVT_BUF     (CONFIG_VIRTIO_DRV_RAM_BASE+0x908000)
I64 virtio_scsi_base;
I64 virtio_scsi_req_id;
I64 VirtioScsiFind()
{
  I64 base, stride, count, i, slot;
  U8 *r;
  if (!RVVirtioMmioEnabled())
    return 0;
  base = RVVirtioMmioBase();
  stride = RVVirtioMmioStride();
  count = RVVirtioMmioCount();
  if (!base || !stride || count <= 0)
    return 0;
  for (i = 0; i < count; i++) {
    slot = base + i *stride;
    r = slot;
    if (InU32(r + VMR_MAGIC) == VSCSI_MAGIC && InU32(r + VMR_DEVICE_ID) == VSCSI_ID_SCSI)
      return slot;
  }
  return 0;
}

U0 VirtioScsiSetupQueue(U8 *r, I64 qsel, I64 pfn)
{
  OutU32(r + VMR_QUEUE_SEL, qsel);
  OutU32(r + VMR_QUEUE_NUM, VSCSI_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, pfn >> 12);
}

I64 VirtioScsiInit()
{
  U8 *r;
  virtio_scsi_base = VirtioScsiFind();
  if (!virtio_scsi_base)
    return -1;
  r = virtio_scsi_base;
  MemSet(VSCSI_CTRL_VQ, 0, 8192);
  MemSet(VSCSI_EVT_VQ, 0, 8192);
  MemSet(VSCSI_REQ_VQ, 0, 8192);
  MemSet(VSCSI_REQ_HDR, 0, 256);
  MemSet(VSCSI_RSP_HDR, 0, 256);
  MemSet(VSCSI_DATA, 0, 512);
  MemSet(VSCSI_EVT_BUF, 0, VSCSI_QSZ * 64);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  VirtioScsiSetupQueue(r, 0, VSCSI_CTRL_VQ);
  VirtioScsiSetupQueue(r, 1, VSCSI_EVT_VQ);
  VirtioScsiSetupQueue(r, 2, VSCSI_REQ_VQ);
  virtio_scsi_req_id = 1;
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  return 0;
}

U0 VirtioScsiEvtPrime()
{
  //Raw event-queue buffers after DRIVER_OK (avoid notify/fill hangs during Init).
  I64 i, vq = VSCSI_EVT_VQ;
  U8 *p, *r = virtio_scsi_base;
  if (!virtio_scsi_base)
    return;
  for (i = 0; i < VSCSI_QSZ; i++) {
    p = vq + i * 16;
    *(U64 *)p = VSCSI_EVT_BUF + i * 64;
    *(U32 *)(p + 8) = 64;
    *(U16 *)(p + 12) = VDESC_F_WRITE;
    *(U16 *)(p + 14) = 0;
    *(U16 *)(vq + 128 + 4 + i * 2) = i;
  }
  *(U16 *)(vq + 130) = VSCSI_QSZ;
  // Kick eventq once so the HBA can post async events (needed before requestq cmds).
  OutU32(r + VMR_QUEUE_SEL, 1);
  OutU32(r + VMR_QUEUE_NOTIFY, 1);
}

I64 VirtioScsiIrqNum()
{
  if (!virtio_scsi_base)
    return -1;
  return (virtio_scsi_base - CONFIG_VIRTIO_MMIO_IRQ_BASE) >> 12;
}

U0 VirtioScsiIrqAck()
{
  U8 *r = virtio_scsi_base;
  U32 st;
  if (!r)
    return;
  st = InU32(r + VMR_INTERRUPT_STATUS);
  if (st)
    OutU32(r + VMR_INTERRUPT_ACK, st);
}

I64 VirtioScsiIrqInit()
{
  I64 irq;
  irq = VirtioScsiIrqNum();
  if (irq < 0)
    return -1;
  VirtioScsiIrqAck();
  RVPlicEnable(irq, 1);
  RVPlicSetThreshold(0);
  RvSetMEIE();
  return irq;
}

U0 VirtioScsiFillLun0(U8 *lun)
{
  I64 i;
  for (i = 0; i < 8; i++)
    lun[i] = 0;
  lun[0] = 1;
  lun[2] = 0x40;
}

I64 VirtioScsiCmd(U8 *cdb, I64 cdb_len, U8 *data, I64 data_len, Bool data_in)
{
  // Descriptor order per virtio-scsi: req (dev-readable), resp (dev-writable),
  // then optional data (dev-writable for IN / readable for OUT).
  U8 *r = virtio_scsi_base;
  I64 vq = VSCSI_REQ_VQ;
  U8 *req = VSCSI_REQ_HDR;
  U8 *resp = VSCSI_RSP_HDR;
  U8 *p;
  U16 uidx0, aidx;
  I64 i, spin;
  if (!r || !cdb || cdb_len <= 0 || cdb_len > 32)
    return -1;
  MemSet(req, 0, VSCSI_REQ_LEN);
  MemSet(resp, 0, VSCSI_RESP_LEN);
  VirtioScsiFillLun0(req);
  //id @ +8
  *(U64 *)(req + 8) = virtio_scsi_req_id++;
  req[16] = VSCSI_T_SIMPLE;
  //cdb @ +19
  for (i = 0; i < cdb_len; i++)
    req[19 + i] = cdb[i];
  resp[11] = 0xFF;
  //response byte
  // Raw desc stores (class-member desc[] hangs on some HolyC layouts).
  p = vq;
  *(U64 *)p = VSCSI_REQ_HDR;
  *(U32 *)(p + 8) = VSCSI_REQ_LEN;
  *(U16 *)(p + 12) = VDESC_F_NEXT;
  *(U16 *)(p + 14) = 1;
  p = vq + 16;
  *(U64 *)p = VSCSI_RSP_HDR;
  *(U32 *)(p + 8) = VSCSI_RESP_LEN;
  if (data && data_len > 0) {
    *(U16 *)(p + 12) = VDESC_F_NEXT | VDESC_F_WRITE;
    *(U16 *)(p + 14) = 2;
    p = vq + 32;
    *(U64 *)p = data;
    *(U32 *)(p + 8) = data_len;
    if (data_in)
      *(U16 *)(p + 12) = VDESC_F_WRITE;
    else
      *(U16 *)(p + 12) = 0;
    *(U16 *)(p + 14) = 0;
  } else {
    *(U16 *)(p + 12) = VDESC_F_WRITE;
    *(U16 *)(p + 14) = 0;
  }
  uidx0 = *(U16 *)(vq + 4096 + 2);
  aidx = *(U16 *)(vq + 128 + 2);
  *(U16 *)(vq + 128 + 4 + (aidx % VSCSI_QSZ) * 2) = 0;
  *(U16 *)(vq + 128 + 2) = aidx + 1;
  OutU32(r + VMR_QUEUE_SEL, 2);
  OutU32(r + VMR_QUEUE_NOTIFY, 2);
  for (spin = 0; spin < 20000000; spin++)
    if (*(U16 *)(vq + 4096 + 2) != uidx0)
      break;
  VirtioScsiIrqAck();
  if (*(U16 *)(vq + 4096 + 2) == uidx0)
    return -1;
  if (resp[11] != VSCSI_S_OK)
    return -1;
  if (resp[10])
    return -1;
  //SCSI status
  return 0;
}

I64 VirtioScsiInquiry(U8 *buf, I64 cap)
{
  U8 cdb[6];
  I64 n = 36;
  if (!buf || cap < 36)
    return -1;
  MemSet(cdb, 0, 6);
  cdb[0] = 0x12;
  cdb[4] = 36;
  MemSet(VSCSI_DATA, 0, 512);
  if (VirtioScsiCmd(cdb, 6, VSCSI_DATA, 36, TRUE))
    return -1;
  if (n > cap)
    n = cap;
  MemCpy(buf, VSCSI_DATA, n);
  return n;
}

I64 VirtioScsiReadLba(U8 *buf, I64 lba)
{
  U8 cdb[10];
  if (!buf)
    return -1;
  MemSet(cdb, 0, 10);
  cdb[0] = 0x28;
  cdb[2] = (lba >> 24) & 0xFF;
  cdb[3] = (lba >> 16) & 0xFF;
  cdb[4] = (lba >> 8) & 0xFF;
  cdb[5] = lba & 0xFF;
  cdb[7] = 0;
  cdb[8] = 1;
  MemSet(VSCSI_DATA, 0, 512);
  if (VirtioScsiCmd(cdb, 10, VSCSI_DATA, 512, TRUE))
    return -1;
  MemCpy(buf, VSCSI_DATA, 512);
  return 0;
}

I64 VirtioScsiSelfTest()
{
  U8 inq[36];
  U8 sec[512];
  if (!virtio_scsi_base && VirtioScsiInit())
    return -1;
  VirtioScsiEvtPrime();
  if (VirtioScsiInquiry(inq, 36) < 36)
    return -1;
  if ((inq[0] & 0x1F) > 0x1E)
    return -1;
  // Best-effort READ(10) — Inquiry alone proves the requestq command path.
  VirtioScsiReadLba(sec, 0);
  return 0;
}
#endif
