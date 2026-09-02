// VirtioInput.HC — legacy virtio-mmio input (DeviceID 18) for keyboard/mouse/tablet.
// Polls the event queue and prints EV_* events (or feeds a key callback).
// Dig-down: Man("VirtioInput"); VirtioInputInit; VirtioInputPoll;
#ifndef RV_DRV_VIRTIO_INPUT_HC
#define RV_DRV_VIRTIO_INPUT_HC
#define VIN_MAGIC         0x74726976
#define VIN_ID_INPUT      18
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
#define VMR_STATUS        0x70
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define VIN_QSZ           8
#define VDESC_F_WRITE     2
#define EV_SYN            0
#define EV_KEY            1
#define EV_REL            2
#define EV_ABS            3
#define VIN_CFG_EV_BITS   0x11
#define VIN_CFG_ABS_INFO  0x10
#define ABS_X             0
#define ABS_Y             1
#define VIN_ABS_DFLT_MAX  32767
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#define VIN_DEV_MAX       4
#define VIN_VQ_STRIDE     0x10000
#define VIN_VQ_DEV(d)     (CONFIG_VIRTIO_DRV_RAM_BASE+0x200000+(d)*VIN_VQ_STRIDE)
#define VIN_EVT_DEV(d)    (CONFIG_VIRTIO_DRV_RAM_BASE+0x202000+(d)*VIN_VQ_STRIDE)
class CVinDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CVinAvail
{
  U16 flags;
  U16 idx;
  U16 ring[VIN_QSZ];
  U16 used_ev;
};

class CVinUsedElem
{
  U32 id;
  U32 len;
};

class CVinUsed
{
  U16 flags;
  U16 idx;
  CVinUsedElem ring[VIN_QSZ];
  U16 avail_ev;
};

class CVinEvent
{
  U16 type;
  U16 code;
  I32 value;
};
I64 virtio_input_base;
I64 virtio_input_bases[VIN_DEV_MAX];
I64 virtio_input_last[VIN_DEV_MAX];
Bool virtio_input_is_ptr[VIN_DEV_MAX];
I64 virtio_input_count;
I64 virtio_input_poll_rr;
I64 virtio_input_events;
I64 virtio_input_abs_x_min;
I64 virtio_input_abs_x_max;
I64 virtio_input_abs_y_min;
I64 virtio_input_abs_y_max;
Bool VirtioInputReadAbsInfo(I64 dev, I64 axis, I64 *min_out, I64 *max_out)
{
  //Virtio-input cfg ABS_INFO (min/max) for tablet axis scaling in WinMgr.
  U8 *r;
  I64 sz, min, max;
  if (dev < 0 || dev >= virtio_input_count || !min_out || !max_out)
    return FALSE;
  r = virtio_input_bases[dev];
  OutU8(r + 0x100, VIN_CFG_ABS_INFO);
  OutU8(r + 0x101, axis);
  sz = InU8(r + 0x102);
  if (sz < 8)
    return FALSE;
  min = InU32(r + 0x108);
  max = InU32(r + 0x10c);
  *min_out = min;
  *max_out = max;
  return TRUE;
}

I64 VirtioInputMapAbs(I64 axis, I64 value, I64 out_max)
{
  //Map EV_ABS value into [0..out_max] using probed min/max (QEMU tablet: 0..0x7fff).
  I64 min, max, span, n;
  if (out_max <= 0)
    return 0;
  if (axis == ABS_X) {
    min = virtio_input_abs_x_min;
    max = virtio_input_abs_x_max;
  } else if (axis == ABS_Y) {
    min = virtio_input_abs_y_min;
    max = virtio_input_abs_y_max;
  } else
    return 0;
  if (max <= min)
    max = min + VIN_ABS_DFLT_MAX;
  span = max - min;
  n = (value - min) * out_max / span;
  if (n < 0)
    n = 0;
  if (n > out_max)
    n = out_max;
  return n;
}

Bool VirtioInputDevProbePointer(I64 dev)
{
  //Tablet/mouse exposes EV_ABS (ABS_X); virtio-keyboard does not.
  U8 *r;
  I64 sz;
  if (dev < 0 || dev >= virtio_input_count)
    return FALSE;
  r = virtio_input_bases[dev];
  OutU8(r + 0x100, VIN_CFG_EV_BITS);
  OutU8(r + 0x101, EV_ABS);
  sz = InU8(r + 0x102);
  if (sz < 1)
    return FALSE;
  return (InU8(r + 0x108) & 1) != 0;
}

I64 VirtioInputFindAll()
{
  //QEMU may expose virtio-keyboard + virtio-tablet as separate DeviceID-18 nodes.
  I64 base, stride, count, i, slot, n = 0;
  U8 *r;
  if (!RVVirtioMmioEnabled())
    return 0;
  base = RVVirtioMmioBase();
  stride = RVVirtioMmioStride();
  count = RVVirtioMmioCount();
  if (!base || !stride || count <= 0)
    return 0;
  for (i = 0; i < count && n < VIN_DEV_MAX; i++) {
    slot = base + i *stride;
    r = slot;
    if (InU32(r + VMR_MAGIC) == VIN_MAGIC && InU32(r + VMR_DEVICE_ID) == VIN_ID_INPUT) {
      virtio_input_bases[n] = slot;
      n++;
    }
  }
  virtio_input_count = n;
  if (n)
    virtio_input_base = virtio_input_bases[0];
  else
    virtio_input_base = 0;
  return n;
}

I64 VirtioInputInitOne(I64 dev)
{
  U8 *r;
  CVinDesc *desc;
  CVinAvail *avail;
  I64 vq, evt, i;
  if (dev < 0 || dev >= virtio_input_count)
    return -1;
  r = virtio_input_bases[dev];
  vq = VIN_VQ_DEV(dev);
  evt = VIN_EVT_DEV(dev);
  MemSet(vq, 0, 8192);
  MemSet(evt, 0, VIN_QSZ * 16);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NUM, VIN_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, vq >> 12);
  desc = vq;
  avail = vq + 128;
  for (i = 0; i < VIN_QSZ; i++) {
    desc[i].addr = evt + i * 16;
    desc[i].len = 8;
    desc[i].flags = VDESC_F_WRITE;
    desc[i].next = 0;
    avail->ring[i] = i;
  }
  avail->idx = VIN_QSZ;
  virtio_input_last[dev] = 0;
  virtio_input_is_ptr[dev] = VirtioInputDevProbePointer(dev);
  if (virtio_input_is_ptr[dev]) {
    //QEMU virtio-tablet advertises 0..0x7fff; WinMgr maps into text cols/rows.
    if (!VirtioInputReadAbsInfo(dev, ABS_X, &virtio_input_abs_x_min, &virtio_input_abs_x_max)) {
      virtio_input_abs_x_min = 0;
      virtio_input_abs_x_max = VIN_ABS_DFLT_MAX;
    }
    if (!VirtioInputReadAbsInfo(dev, ABS_Y, &virtio_input_abs_y_min, &virtio_input_abs_y_max)) {
      virtio_input_abs_y_min = 0;
      virtio_input_abs_y_max = VIN_ABS_DFLT_MAX;
    }
  }
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  return 0;
}

I64 VirtioInputInit()
{
  I64 i;
  if (!VirtioInputFindAll())
    return -1;
  virtio_input_poll_rr = 0;
  virtio_input_events = 0;
  virtio_input_abs_x_min = 0;
  virtio_input_abs_x_max = VIN_ABS_DFLT_MAX;
  virtio_input_abs_y_min = 0;
  virtio_input_abs_y_max = VIN_ABS_DFLT_MAX;
  for (i = 0; i < virtio_input_count; i++)
    if (VirtioInputInitOne(i))
      return -1;
  return 0;
}

I64 VirtioInputPending(I64 dev)
{
  CVinUsed *used;
  I64 vq;
  if (dev < 0 || dev >= virtio_input_count)
    return 0;
  vq = VIN_VQ_DEV(dev);
  used = vq + 4096;
  // used->idx is U16; subtract modulo 65536 (same pattern as VirtioNetRxPending).
  return (U16)(used->idx - (U16)virtio_input_last[dev]);
}

I64 VirtioInputPollOneDev(I64 dev, CVinEvent *ev)
{
  U8 *r;
  I64 vq, evt, slot;
  CVinUsed *used;
  CVinAvail *avail;
  U16 uidx, id;
  if (dev < 0 || dev >= virtio_input_count || !ev)
    return 0;
  if (!VirtioInputPending(dev))
    return 0;
  r = virtio_input_bases[dev];
  vq = VIN_VQ_DEV(dev);
  evt = VIN_EVT_DEV(dev);
  used = vq + 4096;
  avail = vq + 128;
  uidx = (U16)virtio_input_last[dev];
  id = used->ring[uidx % VIN_QSZ].id;
  // Always advance (VirtioNetRx pattern) so a bad descriptor cannot wedge Pending forever.
  virtio_input_last[dev] = (U16)(uidx + 1);
  if (id >= VIN_QSZ)
    return 0;
  slot = evt + id * 16;
  // Raw le16/le16/le32 read (matches VirtioNet buffer handling; avoids class layout quirks).
  ev->type = *(U16 *)slot;
  ev->code = *(U16 *)(slot + 2);
  ev->value = *(I32 *)(slot + 4);
  MemSet(slot, 0, 8);
  virtio_input_events++;
  avail->ring[avail->idx % VIN_QSZ] = id;
  avail->idx = avail->idx + 1;
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  return 1;
}

I64 VirtioInputPollOne(CVinEvent *ev)
{
  //Prefer keyboard devices over tablet/pointer so REL/ABS floods do not starve EV_KEY.
  I64 i, d, start;
  if (!virtio_input_count || !ev)
    return 0;
  start = virtio_input_poll_rr % virtio_input_count;
  for (i = 0; i < virtio_input_count; i++) {
    d = (start + i) % virtio_input_count;
    if (!virtio_input_is_ptr[d] && VirtioInputPollOneDev(d, ev)) {
      virtio_input_poll_rr = d + 1;
      return 1;
    }
  }
  for (i = 0; i < virtio_input_count; i++) {
    d = (start + i) % virtio_input_count;
    if (virtio_input_is_ptr[d] && VirtioInputPollOneDev(d, ev)) {
      virtio_input_poll_rr = d + 1;
      return 1;
    }
  }
  return 0;
}

I64 VirtioInputPoll(I64 max)
{
  CVinEvent ev;
  I64 n = 0;
  while (n < max && VirtioInputPollOne(&ev)) {
    if (ev.type == EV_KEY)
      "virtio-input: KEY code=%d value=%d\n", ev.code, ev.value;
    else if (ev.type == EV_REL)
      "virtio-input: REL code=%d value=%d\n", ev.code, ev.value;
    else if (ev.type == EV_ABS)
      "virtio-input: ABS code=%d value=%d\n", ev.code, ev.value;
    else if (ev.type == EV_SYN)
      "virtio-input: SYN\n";
    else
      "virtio-input: type=%d code=%d value=%d\n", ev.type, ev.code, ev.value;
    n++;
  }
  return n;
}
// Linux KEY_* → ASCII. shift=TRUE for shifted glyphs. Returns 0 if not a typeable key.
// Dig-down: used by RVWinMgrPumpInput for focused-window typing.
I64 VirtioInputKeyToChar(I64 code, Bool shift)
{
  if (code == 28)
    return '\n';
  // KEY_ENTER
  if (code == 57)
    return ' ';
  // KEY_SPACE
  if (code == 14)
    return 8;
  // KEY_BACKSPACE
  if (code == 15)
    return '\t';
  // KEY_TAB
  if (code >= 2 && code <= 11) {
    U8 *n0 = "1234567890";
    U8 *n1 = "!@#$%^&*()";
    I64 i = code - 2;
    if (shift)
      return n1[i];
    return n0[i];
  }
  if (code == 12) {
    if (shift)
      return '_';
    return '-';
  }
  if (code == 13) {
    if (shift)
      return '+';
    return '=';
  }
  if (code == 26) {
    if (shift)
      return '{';
    return '[';
  }
  if (code == 27) {
    if (shift)
      return '}';
    return ']';
  }
  if (code == 39) {
    if (shift)
      return ':';
    return ';';
  }
  if (code == 40) {
    if (shift)
      return '"';
    return '\'';
  }
  if (code == 41) {
    if (shift)
      return '~';
    return '`';
  }
  if (code == 43) {
    if (shift)
      return '|';
    return '\\';
  }
  if (code == 51) {
    if (shift)
      return '<';
    return ',';
  }
  if (code == 52) {
    if (shift)
      return '>';
    return '.';
  }
  if (code == 53) {
    if (shift)
      return '?';
    return '/';
  }
  // Letters: KEY_Q..KEY_P (16..25), KEY_A..KEY_L (30..38), KEY_Z..KEY_M (44..50)
  U8 *row;
  I64 base, i, ch;
  if (code >= 16 && code <= 25) {
    row = "qwertyuiop";
    base = 16;
  } else if (code >= 30 && code <= 38) {
    row = "asdfghjkl";
    base = 30;
  } else if (code >= 44 && code <= 50) {
    row = "zxcvbnm";
    base = 44;
  } else
    return 0;
  i = code - base;
  ch = row[i];
  if (shift && ch >= 'a' && ch <= 'z')
    ch = ch - 'a' + 'A';
  return ch;
}
#endif
