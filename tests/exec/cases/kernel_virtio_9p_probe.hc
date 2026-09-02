// Minimal virtio-9p Tversion probe — MemCpy descriptor publish (RAM-visible).
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVVirtioSelected.HH"
#include "/Kernel/KUtilsRV.HC"
#define MEM_UART 0x10000000
#define VMR_QUEUE_SEL     0x30
#define VMR_QUEUE_NUM     0x38
#define VMR_QUEUE_ALIGN   0x3c
#define VMR_QUEUE_PFN     0x40
#define VMR_QUEUE_NOTIFY  0x50
#define VMR_STATUS        0x70
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define V9P_VQ            (CONFIG_VIRTIO_DRV_RAM_BASE+0x300000)
#define V9P_REQ           (CONFIG_VIRTIO_DRV_RAM_BASE+0x302000)
#define V9P_RSP           (CONFIG_VIRTIO_DRV_RAM_BASE+0x304000)
#define VDESC_F_NEXT      1
#define VDESC_F_WRITE     2
class CV9pDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CV9pAvail
{
  U16 flags;
  U16 idx;
  U16 ring[8];
  U16 used_ev;
};

class CV9pUsedElem
{
  U32 id;
  U32 len;
};

class CV9pUsed
{
  U16 flags;
  U16 idx;
  CV9pUsedElem ring[8];
  U16 avail_ev;
};
CV9pDesc ninep_desc_tmp[2];
CV9pAvail ninep_avail_tmp;
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}

I64 main()
{
  I64 base, i, slot;
  U8 *r, *req, *rsp;
  CV9pUsed *used;
  U16 u0;
  I64 spin;
  Sh("probe\n");
  base = RVVirtioMmioBase();
  r = 0;
  for (i = 0; i < 8; i++) {
    slot = base + i * 0x1000;
    if (InU32(slot) == 0x74726976 && InU32(slot + 8) == 9) {
      r = slot;
      break;
    }
  }
  if (!r) {
    Sh("no dev\n");
    return 1;
  }
  req = V9P_REQ;
  rsp = V9P_RSP;
  MemSet(V9P_VQ, 0, 8192);
  req[0] = 0x11;
  req[4] = 100;
  req[5] = 1;
  req[7] = 0;
  req[8] = 0x20;
  req[9] = 0;
  req[11] = 8;
  req[12] = '9';
  req[13] = 'P';
  req[14] = '2';
  req[15] = '0';
  req[16] = '0';
  req[17] = '0';
  req[18] = '.';
  req[19] = 'L';
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + 0x20, 0);
  OutU32(r + 0x24, 0);
  OutU32(r + 0x28, 4096);
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NUM, 8);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, V9P_VQ >> 12);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  ninep_desc_tmp[0].addr = V9P_REQ;
  ninep_desc_tmp[0].len = 24;
  ninep_desc_tmp[0].flags = VDESC_F_NEXT;
  ninep_desc_tmp[0].next = 1;
  ninep_desc_tmp[1].addr = V9P_RSP;
  ninep_desc_tmp[1].len = 8192;
  ninep_desc_tmp[1].flags = VDESC_F_WRITE;
  ninep_desc_tmp[1].next = 0;
  MemCpy(V9P_VQ, ninep_desc_tmp, 32);
  if (*(U64 *)V9P_VQ != V9P_REQ) {
    Sh("bad mem\n");
    return 7;
  }
  ninep_avail_tmp.flags = 0;
  ninep_avail_tmp.idx = 1;
  ninep_avail_tmp.ring[0] = 0;
  ninep_avail_tmp.used_ev = 0;
  MemCpy(V9P_VQ + 128, &ninep_avail_tmp, 20);
  if (*(U16 *)(V9P_VQ + 130) != 1) {
    Sh("bad avail\n");
    return 8;
  }
  used = V9P_VQ + 4096;
  u0 = InU16(V9P_VQ + 4098);
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  for (spin = 0; spin < 200000000; spin++)
    if (InU16(V9P_VQ + 4098) != u0)
      break;
  if (InU16(V9P_VQ + 4098) == u0) {
    Sh("timeout\n");
    return 2;
  }
  if (rsp[4] != 101) {
    Sh("bad type\n");
    return 3;
  }
  Sh("version ok\n");
  return 0;
}
