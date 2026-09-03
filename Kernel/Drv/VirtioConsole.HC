// VirtioConsole.HC — legacy virtio-mmio console (DeviceID 3).
// Port-0 TX (+ optional RX prime). Dig-down: Man("VirtioConsole"); VirtioConsoleInit;
// All ring stores are raw (class-member stores hang on some HolyC layouts).
#ifndef RV_DRV_VIRTIO_CONSOLE_HC
#define RV_DRV_VIRTIO_CONSOLE_HC
#define VCON_MAGIC        0x74726976
#define VCON_ID_CONSOLE   3
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
#define VCON_QSZ          8
#define VDESC_F_WRITE     2
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
#define VCON_RX_VQ        (CONFIG_VIRTIO_DRV_RAM_BASE+0x700000)
#define VCON_TX_VQ        (CONFIG_VIRTIO_DRV_RAM_BASE+0x702000)
#define VCON_RX_BUF       (CONFIG_VIRTIO_DRV_RAM_BASE+0x704000)
#define VCON_TX_BUF       (CONFIG_VIRTIO_DRV_RAM_BASE+0x706000)
#define VCON_BUF_STRIDE   256
I64 virtio_console_base;
I64 virtio_console_rx_last;
I64 virtio_console_tx_ok;
I64 VirtioConsoleFind()
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
    if (InU32(r + VMR_MAGIC) == VCON_MAGIC && InU32(r + VMR_DEVICE_ID) == VCON_ID_CONSOLE)
      return slot;
  }
  return 0;
}

U0 VirtioConsoleSetupQueue(U8 *r, I64 qsel, I64 pfn)
{
  OutU32(r + VMR_QUEUE_SEL, qsel);
  OutU32(r + VMR_QUEUE_NUM, VCON_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, pfn >> 12);
}

U0 VirtioConsolePutDesc(I64 vq, I64 idx, U64 addr, U32 len, U16 flags, U16 next)
{
  U8 *p = vq + idx * 16;
  *(U64 *)p = addr;
  *(U32 *)(p + 8) = len;
  *(U16 *)(p + 12) = flags;
  *(U16 *)(p + 14) = next;
}

I64 VirtioConsoleInit()
{
  U8 *r;
  virtio_console_base = VirtioConsoleFind();
  if (!virtio_console_base)
    return -1;
  r = virtio_console_base;
  MemSet(VCON_RX_VQ, 0, 8192);
  MemSet(VCON_TX_VQ, 0, 8192);
  MemSet(VCON_RX_BUF, 0, VCON_QSZ *VCON_BUF_STRIDE);
  MemSet(VCON_TX_BUF, 0, VCON_BUF_STRIDE);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  VirtioConsoleSetupQueue(r, 0, VCON_RX_VQ);
  VirtioConsoleSetupQueue(r, 1, VCON_TX_VQ);
  virtio_console_rx_last = 0;
  virtio_console_tx_ok = 0;
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  return 0;
}

U0 VirtioConsoleRxPrime()
{
  I64 i, vq = VCON_RX_VQ;
  if (!virtio_console_base)
    return;
  for (i = 0; i < VCON_QSZ; i++) {
    VirtioConsolePutDesc(vq, i, VCON_RX_BUF + i *VCON_BUF_STRIDE, VCON_BUF_STRIDE, VDESC_F_WRITE, 0);
    *(U16 *)(vq + 128 + 4 + i * 2) = i;
  }
  *(U16 *)(vq + 130) = VCON_QSZ;
}

I64 VirtioConsoleIrqNum()
{
  if (!virtio_console_base)
    return -1;
  return (virtio_console_base - CONFIG_VIRTIO_MMIO_IRQ_BASE) >> 12;
}

U0 VirtioConsoleIrqAck()
{
  U8 *r = virtio_console_base;
  U32 st;
  if (!r)
    return;
  st = InU32(r + VMR_INTERRUPT_STATUS);
  if (st)
    OutU32(r + VMR_INTERRUPT_ACK, st);
}

I64 VirtioConsoleIrqInit()
{
  I64 irq;
  irq = VirtioConsoleIrqNum();
  if (irq < 0)
    return -1;
  VirtioConsoleIrqAck();
  RVPlicEnable(irq, 1);
  RVPlicSetThreshold(0);
  RvSetMEIE();
  return irq;
}

I64 VirtioConsoleWrite(U8 *buf, I64 len)
{
  U8 *r = virtio_console_base;
  I64 vq = VCON_TX_VQ;
  U16 uidx0, aidx;
  I64 spin;
  if (!r || !buf || len <= 0)
    return -1;
  if (len > VCON_BUF_STRIDE)
    len = VCON_BUF_STRIDE;
  MemCpy(VCON_TX_BUF, buf, len);
  VirtioConsolePutDesc(vq, 0, VCON_TX_BUF, len, 0, 0);
  uidx0 = *(U16 *)(vq + 4096 + 2);
  aidx = *(U16 *)(vq + 128 + 2);
  *(U16 *)(vq + 128 + 4 + (aidx % VCON_QSZ) * 2) = 0;
  *(U16 *)(vq + 128 + 2) = aidx + 1;
  OutU32(r + VMR_QUEUE_SEL, 1);
  OutU32(r + VMR_QUEUE_NOTIFY, 1);
  for (spin = 0; spin < 2000000; spin++)
    if (*(U16 *)(vq + 4096 + 2) != uidx0)
      break;
  VirtioConsoleIrqAck();
  if (*(U16 *)(vq + 4096 + 2) == uidx0)
    return -1;
  virtio_console_tx_ok++;
  return len;
}

I64 VirtioConsolePuts(U8 *s)
{
  I64 n = 0;
  if (!s)
    return -1;
  while (s[n])
    n++;
  return VirtioConsoleWrite(s, n);
}

I64 VirtioConsoleRxPending()
{
  if (!virtio_console_base)
    return 0;
  return (U16)(*(U16 *)(VCON_RX_VQ + 4096 + 2) - (U16)virtio_console_rx_last);
}

I64 VirtioConsoleRead(U8 *buf, I64 cap)
{
  U8 *r = virtio_console_base;
  I64 vq = VCON_RX_VQ;
  U16 uidx, id, aidx;
  U32 plen;
  I64 n;
  if (!r || !buf || cap <= 0)
    return -1;
  if (!VirtioConsoleRxPending())
    return 0;
  uidx = (U16)virtio_console_rx_last;
  id = *(U32 *)(vq + 4096 + 4 + 8 * (uidx % VCON_QSZ));
  plen = *(U32 *)(vq + 4096 + 8 + 8 * (uidx % VCON_QSZ));
  virtio_console_rx_last = (U16)(uidx + 1);
  if (id >= VCON_QSZ)
    return 0;
  n = plen;
  if (n > cap)
    n = cap;
  if (n > 0)
    MemCpy(buf, VCON_RX_BUF + id *VCON_BUF_STRIDE, n);
  aidx = *(U16 *)(vq + 128 + 2);
  *(U16 *)(vq + 128 + 4 + (aidx % VCON_QSZ) * 2) = id;
  *(U16 *)(vq + 128 + 2) = aidx + 1;
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  VirtioConsoleIrqAck();
  return n;
}

I64 VirtioConsoleSelfTest()
{
  I64 rc;
  if (VirtioConsoleInit())
    return -1;
  rc = VirtioConsolePuts("virtio-console\n");
  if (rc < 0 && !virtio_console_base)
    return -1;
  return 0;
}
#endif
