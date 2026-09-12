// VirtioSnd.HC — legacy virtio-mmio sound (DeviceID 25).
// Control/event/tx/rx queues; PCM SET_PARAMS→PREPARE→START + TX period.
// Dig-down: Man("VirtioSnd"); VirtioSndInit; VirtioSndTx;
// Raw ring stores (class-member stores hang on some HolyC layouts).
#ifndef RV_DRV_VIRTIO_SND_HC
#define RV_DRV_VIRTIO_SND_HC
#define VSND_MAGIC        0x74726976
#define VSND_ID_SOUND     25
#define VMR_MAGIC         0x00
#define VMR_VERSION       0x04
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
#define VMR_CONFIG        0x100
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define VSND_QSZ          8
#define VDESC_F_NEXT      1
#define VDESC_F_WRITE     2
#define VSND_VQ_CTRL      0
#define VSND_VQ_EVENT     1
#define VSND_VQ_TX        2
#define VSND_VQ_RX        3
#define VSND_R_PCM_INFO   0x0100
#define VSND_R_PCM_SET_PARAMS 0x0101
#define VSND_R_PCM_PREPARE 0x0102
#define VSND_R_PCM_RELEASE 0x0103
#define VSND_R_PCM_START  0x0104
#define VSND_R_PCM_STOP   0x0105
#define VSND_S_OK         0x8000
#define VSND_PCM_FMT_S16  5
#define VSND_PCM_RATE_8000 1
#define VSND_PERIOD_BYTES 256
#define VSND_BUFFER_BYTES 1024
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
// Driver RAM: sound @ +0xa00000 (after SCSI @ +0x900000).
#define VSND_CTRL_VQ      (CONFIG_VIRTIO_DRV_RAM_BASE+0xa00000)
#define VSND_EVT_VQ       (CONFIG_VIRTIO_DRV_RAM_BASE+0xa02000)
#define VSND_TX_VQ        (CONFIG_VIRTIO_DRV_RAM_BASE+0xa04000)
#define VSND_RX_VQ        (CONFIG_VIRTIO_DRV_RAM_BASE+0xa06000)
#define VSND_CTRL_REQ     (CONFIG_VIRTIO_DRV_RAM_BASE+0xa08000)
#define VSND_CTRL_RSP     (CONFIG_VIRTIO_DRV_RAM_BASE+0xa09000)
#define VSND_EVT_BUF      (CONFIG_VIRTIO_DRV_RAM_BASE+0xa0a000)
#define VSND_TX_XFER      (CONFIG_VIRTIO_DRV_RAM_BASE+0xa0b000)
#define VSND_TX_STAT      (CONFIG_VIRTIO_DRV_RAM_BASE+0xa0b100)
#define VSND_TX_DATA      (CONFIG_VIRTIO_DRV_RAM_BASE+0xa0c000)
I64 virtio_snd_base;
I64 virtio_snd_stream;
I64 virtio_snd_started;
I64 virtio_snd_tx_ok;
I64 virtio_snd_tx_fail;
I64 virtio_snd_ctrl_ok;
I64 virtio_snd_streams;
I64 VirtioSndFind()
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
    if (InU32(r + VMR_MAGIC) == VSND_MAGIC && InU32(r + VMR_DEVICE_ID) == VSND_ID_SOUND)
      return slot;
  }
  return 0;
}

U0 VirtioSndSetupQueue(U8 *r, I64 qsel, I64 pfn)
{
  OutU32(r + VMR_QUEUE_SEL, qsel);
  OutU32(r + VMR_QUEUE_NUM, VSND_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, pfn >> 12);
}

U0 VirtioSndIrqAck()
{
  U8 *r = virtio_snd_base;
  U32 st;
  if (!r)
    return;
  st = InU32(r + VMR_INTERRUPT_STATUS);
  if (st)
    OutU32(r + VMR_INTERRUPT_ACK, st);
}

U0 VirtioSndEvtPrime()
{
  I64 i, vq = VSND_EVT_VQ;
  U8 *p, *r = virtio_snd_base;
  if (!virtio_snd_base)
    return;
  for (i = 0; i < VSND_QSZ; i++) {
    p = vq + i * 16;
    *(U64 *)p = VSND_EVT_BUF + i * 64;
    *(U32 *)(p + 8) = 64;
    *(U16 *)(p + 12) = VDESC_F_WRITE;
    *(U16 *)(p + 14) = 0;
    *(U16 *)(vq + 128 + 4 + i * 2) = i;
  }
  *(U16 *)(vq + 130) = VSND_QSZ;
  OutU32(r + VMR_QUEUE_SEL, VSND_VQ_EVENT);
  OutU32(r + VMR_QUEUE_NOTIFY, VSND_VQ_EVENT);
}

I64 VirtioSndCtrl(U8 *req, I64 req_len, U8 *rsp, I64 rsp_len)
{
  //Controlq: OUT request + IN status(/payload). Returns status code or -1.
  U8 *r = virtio_snd_base;
  I64 vq = VSND_CTRL_VQ;
  U8 *p;
  U16 uidx0, aidx;
  I64 spin, st;
  if (!r || !req || req_len <= 0 || !rsp || rsp_len < 4)
    return -1;
  MemCpy(VSND_CTRL_REQ, req, req_len);
  MemSet(VSND_CTRL_RSP, 0, rsp_len);
  p = vq;
  *(U64 *)p = VSND_CTRL_REQ;
  *(U32 *)(p + 8) = req_len;
  *(U16 *)(p + 12) = VDESC_F_NEXT;
  *(U16 *)(p + 14) = 1;
  p = vq + 16;
  *(U64 *)p = VSND_CTRL_RSP;
  *(U32 *)(p + 8) = rsp_len;
  *(U16 *)(p + 12) = VDESC_F_WRITE;
  *(U16 *)(p + 14) = 0;
  uidx0 = *(U16 *)(vq + 4096 + 2);
  aidx = *(U16 *)(vq + 128 + 2);
  *(U16 *)(vq + 128 + 4 + (aidx % VSND_QSZ) * 2) = 0;
  *(U16 *)(vq + 128 + 2) = aidx + 1;
  OutU32(r + VMR_QUEUE_SEL, VSND_VQ_CTRL);
  OutU32(r + VMR_QUEUE_NOTIFY, VSND_VQ_CTRL);
  for (spin = 0; spin < 20000000; spin++)
    if (*(U16 *)(vq + 4096 + 2) != uidx0)
      break;
  VirtioSndIrqAck();
  if (*(U16 *)(vq + 4096 + 2) == uidx0)
    return -1;
  MemCpy(rsp, VSND_CTRL_RSP, rsp_len);
  st = *(U32 *)VSND_CTRL_RSP;
  if (st == VSND_S_OK)
    virtio_snd_ctrl_ok++;
  return st;
}

I64 VirtioSndPcmHdr(I64 code, I64 stream_id)
{
  U8 req[8], rsp[4];
  MemSet(req, 0, 8);
  *(U32 *)req = code;
  *(U32 *)(req + 4) = stream_id;
  return VirtioSndCtrl(req, 8, rsp, 4);
}

I64 VirtioSndPcmSetParams(I64 stream_id)
{
  //S16 mono @ 8 kHz — matches ASnd_RV soft ring conceptual rate.
  U8 req[24], rsp[4];
  MemSet(req, 0, 24);
  *(U32 *)req = VSND_R_PCM_SET_PARAMS;
  *(U32 *)(req + 4) = stream_id;
  *(U32 *)(req + 8) = VSND_BUFFER_BYTES;
  *(U32 *)(req + 12) = VSND_PERIOD_BYTES;
  *(U32 *)(req + 16) = 0;
  //features
  req[20] = 1;
  //channels
  req[21] = VSND_PCM_FMT_S16;
  req[22] = VSND_PCM_RATE_8000;
  req[23] = 0;
  return VirtioSndCtrl(req, 24, rsp, 4);
}

I64 VirtioSndPcmStart(I64 stream_id)
{
  I64 st;
  st = VirtioSndPcmSetParams(stream_id);
  if (st != VSND_S_OK)
    return st;
  st = VirtioSndPcmHdr(VSND_R_PCM_PREPARE, stream_id);
  if (st != VSND_S_OK)
    return st;
  st = VirtioSndPcmHdr(VSND_R_PCM_START, stream_id);
  if (st != VSND_S_OK)
    return st;
  virtio_snd_stream = stream_id;
  virtio_snd_started = 1;
  return VSND_S_OK;
}

I64 VirtioSndInit()
{
  U8 *r;
  I64 st;
  virtio_snd_base = 0;
  virtio_snd_stream = 0;
  virtio_snd_started = 0;
  virtio_snd_tx_ok = 0;
  virtio_snd_tx_fail = 0;
  virtio_snd_ctrl_ok = 0;
  virtio_snd_streams = 0;
  virtio_snd_base = VirtioSndFind();
  if (!virtio_snd_base)
    return -1;
  r = virtio_snd_base;
  MemSet(VSND_CTRL_VQ, 0, 8192);
  MemSet(VSND_EVT_VQ, 0, 8192);
  MemSet(VSND_TX_VQ, 0, 8192);
  MemSet(VSND_RX_VQ, 0, 8192);
  MemSet(VSND_CTRL_REQ, 0, 256);
  MemSet(VSND_CTRL_RSP, 0, 4096);
  MemSet(VSND_EVT_BUF, 0, VSND_QSZ * 64);
  MemSet(VSND_TX_XFER, 0, 16);
  MemSet(VSND_TX_STAT, 0, 16);
  MemSet(VSND_TX_DATA, 0, VSND_BUFFER_BYTES);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  VirtioSndSetupQueue(r, VSND_VQ_CTRL, VSND_CTRL_VQ);
  VirtioSndSetupQueue(r, VSND_VQ_EVENT, VSND_EVT_VQ);
  VirtioSndSetupQueue(r, VSND_VQ_TX, VSND_TX_VQ);
  VirtioSndSetupQueue(r, VSND_VQ_RX, VSND_RX_VQ);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  virtio_snd_streams = InU32(r + VMR_CONFIG + 4);
  VirtioSndEvtPrime();
  //QEMU default: stream0 OUTPUT, stream1 INPUT when streams=2.
  st = VirtioSndPcmStart(0);
  if (st != VSND_S_OK) {
    virtio_snd_started = 0;
    return -2;
  }
  return 0;
}

I64 VirtioSndTx(U8 *pcm, I64 nbytes)
{
  //TX period: xfer hdr + PCM OUT + status IN. nbytes clamped to PERIOD.
  U8 *r = virtio_snd_base;
  I64 vq = VSND_TX_VQ;
  U8 *p;
  U16 uidx0, aidx;
  I64 spin, st, n;
  if (!r || !virtio_snd_started || !pcm || nbytes <= 0)
    return -1;
  n = nbytes;
  if (n > VSND_PERIOD_BYTES)
    n = VSND_PERIOD_BYTES;
  *(U32 *)VSND_TX_XFER = virtio_snd_stream;
  MemSet(VSND_TX_STAT, 0, 8);
  MemCpy(VSND_TX_DATA, pcm, n);
  if (n < VSND_PERIOD_BYTES)
    MemSet(VSND_TX_DATA + n, 0, VSND_PERIOD_BYTES - n);
  p = vq;
  *(U64 *)p = VSND_TX_XFER;
  *(U32 *)(p + 8) = 4;
  *(U16 *)(p + 12) = VDESC_F_NEXT;
  *(U16 *)(p + 14) = 1;
  p = vq + 16;
  *(U64 *)p = VSND_TX_DATA;
  *(U32 *)(p + 8) = VSND_PERIOD_BYTES;
  *(U16 *)(p + 12) = VDESC_F_NEXT;
  *(U16 *)(p + 14) = 2;
  p = vq + 32;
  *(U64 *)p = VSND_TX_STAT;
  *(U32 *)(p + 8) = 8;
  *(U16 *)(p + 12) = VDESC_F_WRITE;
  *(U16 *)(p + 14) = 0;
  uidx0 = *(U16 *)(vq + 4096 + 2);
  aidx = *(U16 *)(vq + 128 + 2);
  *(U16 *)(vq + 128 + 4 + (aidx % VSND_QSZ) * 2) = 0;
  *(U16 *)(vq + 128 + 2) = aidx + 1;
  OutU32(r + VMR_QUEUE_SEL, VSND_VQ_TX);
  OutU32(r + VMR_QUEUE_NOTIFY, VSND_VQ_TX);
  for (spin = 0; spin < 20000000; spin++)
    if (*(U16 *)(vq + 4096 + 2) != uidx0)
      break;
  VirtioSndIrqAck();
  if (*(U16 *)(vq + 4096 + 2) == uidx0) {
    virtio_snd_tx_fail++;
    return -1;
  }
  st = *(U32 *)VSND_TX_STAT;
  if (st != VSND_S_OK) {
    virtio_snd_tx_fail++;
    return -1;
  }
  virtio_snd_tx_ok++;
  return n;
}

I64 VirtioSndTxFromRing(I16 *ring, I64 ring_n, I64 *cursor)
{
  //Copy one period of S16 samples from a soft ring (wrap). Returns TX bytes or <0.
  I64 i, idx, n = VSND_PERIOD_BYTES / 2;
  I16 *dst = VSND_TX_DATA;
  if (!ring || ring_n <= 0 || !cursor)
    return -1;
  for (i = 0; i < n; i++) {
    idx = (*cursor + i) % ring_n;
    dst[i] = ring[idx];
  }
  *cursor = (*cursor + n) % ring_n;
  return VirtioSndTx(VSND_TX_DATA, VSND_PERIOD_BYTES);
}

I64 VirtioSndSelfTest()
{
  I64 i;
  I16 *p = VSND_TX_DATA;
  if (VirtioSndInit())
    return -1;
  for (i = 0; i < VSND_PERIOD_BYTES / 2; i++) {
    if ((i / 8) & 1)
      p[i] = 8000;
    else
      p[i] = -8000;
  }
  if (VirtioSndTx(VSND_TX_DATA, VSND_PERIOD_BYTES) < 0)
    return -1;
  if (virtio_snd_tx_ok < 1)
    return -1;
  return 0;
}
#endif
