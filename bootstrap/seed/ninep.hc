// ninep.hc — REPL 9P2000.L client + Mount9p (virtio-mmio transport).
// QEMU: -fsdev local,id=hostshare,path=/path,security_model=none
//       -device virtio-9p-device,fsdev=hostshare,mount_tag=hostshare
#define NINEP_RAM        0x87500000
#define NINEP_VQ         NINEP_RAM
#define NINEP_REQ        (NINEP_RAM+0x2000)
#define NINEP_RSP        (NINEP_RAM+0x4000)
#define NINEP_QSZ        8
#define NINEP_MSIZE      65536
#define NINEP_MAGIC      0x74726976
#define NINEP_DEV_ID     9
#define P9_TVERSION      100
#define P9_RVERSION      101
#define P9_TATTACH       104
#define P9_RATTACH       105
#define P9_TWALK         110
#define P9_RWALK         111
#define P9_TLOPEN        12
#define P9_RLOPEN        13
#define P9_TREAD         116
#define P9_RREAD         117
#define P9_TCLUNK        120
#define P9_RCLUNK        121
#define P9_O_RDONLY      0
#define VDESC_F_NEXT     1
#define VDESC_F_WRITE    2
class CNinepDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CNinepAvail
{
  U16 flags;
  U16 idx;
  U16 ring[NINEP_QSZ];
  U16 used_ev;
};
I64 ninep_base;
U16 ninep_avail_idx;
U16 ninep_tag;
U32 ninep_root_fid;
U32 ninep_next_fid;
U0 NinepPutU32(U8 *p, I64 off, U32 v)
{
  p[off] = v & 0xFF;
  p[off + 1] = (v >> 8) & 0xFF;
  p[off + 2] = (v >> 16) & 0xFF;
  p[off + 3] = (v >> 24) & 0xFF;
}

U32 NinepGetU32(U8 *p, I64 off)
{
  return p[off] | (p[off + 1] << 8) | (p[off + 2] << 16) | (p[off + 3] << 24);
}

U16 NinepGetU16(U8 *p, I64 off)
{
  return p[off] | (p[off + 1] << 8);
}

I64 NinepPutStr(U8 *p, I64 off, U8 *s)
{
  I64 n = 0;
  if (!s)
    s = "";
  while (s[n])
    n++;
  p[off] = n & 0xFF;
  p[off + 1] = (n >> 8) & 0xFF;
  off += 2;
  MemCpy(p + off, s, n);
  return off + n;
}

I64 NinepFindMmio()
{
  I64 i, slot;
  for (i = 0; i < 8; i++) {
    slot = MEM_VIRTIO + i *MEM_VIRTIO_STRIDE;
    if (*(U32 *)slot == NINEP_MAGIC && *(U32 *)(slot + 8) == NINEP_DEV_ID)
      return slot;
  }
  return 0;
}

I64 NinepSend(I64 req_len)
{
  U8 *r;
  CNinepDesc dtmp[2];
  CNinepAvail atmp;
  U16 u0, aidx;
  I64 spin, pad;
  if (!ninep_base || req_len <= 0)
    return -1;
  pad = req_len;
  if (pad & 3)
    pad = pad + 4 - (pad & 3);
  r = ninep_base;
  MemSet(NINEP_RSP, 0, NINEP_MSIZE);
  dtmp[0].addr = NINEP_REQ;
  dtmp[0].len = pad;
  dtmp[0].flags = VDESC_F_NEXT;
  dtmp[0].next = 1;
  dtmp[1].addr = NINEP_RSP;
  dtmp[1].len = NINEP_MSIZE;
  dtmp[1].flags = VDESC_F_WRITE;
  dtmp[1].next = 0;
  MemCpy(NINEP_VQ, dtmp, 32);
  aidx = ninep_avail_idx;
  atmp.flags = 0;
  atmp.idx = aidx + 1;
  atmp.ring[aidx % NINEP_QSZ] = 0;
  atmp.used_ev = 0;
  MemCpy(NINEP_VQ + 128, &atmp, 20);
  ninep_avail_idx = aidx + 1;
  u0 = *(U16 *)(NINEP_VQ + 4098);
  *(U32 *)(r + 0x50) = 0;
  for (spin = 0; spin < 200000000; spin++)
    if (*(U16 *)(NINEP_VQ + 4098) != u0)
      break;
  if (*(U16 *)(NINEP_VQ + 4098) == u0)
    return -2;
  return NinepGetU32(NINEP_RSP, 0);
}

I64 NinepInit()
{
  U8 *r;
  ninep_base = NinepFindMmio();
  if (!ninep_base)
    return -1;
  r = ninep_base;
  ninep_avail_idx = 0;
  ninep_tag = 1;
  ninep_root_fid = 0;
  ninep_next_fid = 1;
  MemSet(NINEP_VQ, 0, 8192);
  *(U32 *)(r + 0x70) = 0;
  *(U32 *)(r + 0x70) = 1;
  *(U32 *)(r + 0x70) = 3;
  *(U32 *)(r + 0x20) = 0;
  *(U32 *)(r + 0x24) = 0;
  *(U32 *)(r + 0x28) = 4096;
  *(U32 *)(r + 0x30) = 0;
  *(U32 *)(r + 0x38) = NINEP_QSZ;
  *(U32 *)(r + 0x3c) = 4096;
  *(U32 *)(r + 0x40) = NINEP_VQ >> 12;
  *(U32 *)(r + 0x70) = 7;
  return 0;
}

I64 NinepVersion()
{
  U8 *req = NINEP_REQ;
  U8 *rsp = NINEP_RSP;
  I64 off = 7;
  NinepPutU32(req, 7, NINEP_MSIZE);
  off = 7 + 4;
  off = NinepPutStr(req, off, "9P2000.L");
  NinepPutU32(req, 0, off - 4);
  req[4] = P9_TVERSION;
  req[5] = ninep_tag & 0xFF;
  req[6] = (ninep_tag >> 8) & 0xFF;
  if (NinepSend(off) <= 0)
    return -2;
  if (rsp[4] != P9_RVERSION)
    return -3;
  ninep_tag++;
  return 0;
}

I64 NinepMountTag(U8 *buf, I64 cap)
{
  U16 n, i;
  if (!ninep_base || !buf)
    return -1;
  n = *(U32 *)(ninep_base + 0x100) & 0xFFFF;
  if (n <= 0 || n >= cap)
    return -2;
  for (i = 0; i < n; i++)
    buf[i] = *(U8 *)(ninep_base + 0x102 + i);
  buf[n] = 0;
  return n;
}

I64 NinepAttach(U8 *tag)
{
  U8 *req = NINEP_REQ;
  U8 *rsp = NINEP_RSP;
  I64 off = 7 + 4 + 4;
  NinepPutU32(req, 7, ninep_root_fid);
  NinepPutU32(req, 11, 0xFFFFFFFF);
  off = NinepPutStr(req, off, "holyc");
  off = NinepPutStr(req, off, tag);
  NinepPutU32(req, off, 0);
  off += 4;
  NinepPutU32(req, 0, off - 4);
  req[4] = P9_TATTACH;
  req[5] = ninep_tag & 0xFF;
  req[6] = (ninep_tag >> 8) & 0xFF;
  if (NinepSend(off) <= 0)
    return -2;
  if (rsp[4] != P9_RATTACH)
    return -3;
  ninep_tag++;
  return 0;
}

I64 NinepReadPath(U8 *path, U8 *buf, I64 cap)
{
  U8 *req = NINEP_REQ;
  U8 *rsp = NINEP_RSP;
  U32 fid;
  I64 off, n;
  fid = ninep_next_fid++;
  off = 7 + 4 + 4 + 2;
  NinepPutU32(req, 7, ninep_root_fid);
  NinepPutU32(req, 11, fid);
  req[15] = 1;
  req[16] = 0;
  off = NinepPutStr(req, off, path);
  NinepPutU32(req, 0, off - 4);
  req[4] = P9_TWALK;
  req[5] = ninep_tag & 0xFF;
  req[6] = (ninep_tag >> 8) & 0xFF;
  if (NinepSend(off) <= 0)
    return -2;
  if (rsp[4] != P9_RWALK)
    return -3;
  ninep_tag++;
  off = 7 + 4 + 4;
  NinepPutU32(req, 7, fid);
  NinepPutU32(req, 11, P9_O_RDONLY);
  NinepPutU32(req, 0, off - 4);
  req[4] = P9_TLOPEN;
  req[5] = ninep_tag & 0xFF;
  req[6] = (ninep_tag >> 8) & 0xFF;
  if (NinepSend(off) <= 0)
    return -4;
  if (rsp[4] != P9_RLOPEN)
    return -5;
  ninep_tag++;
  off = 7 + 4 + 8 + 4;
  NinepPutU32(req, 7, fid);
  NinepPutU32(req, 11, 0);
  NinepPutU32(req, 15, 0);
  NinepPutU32(req, 19, cap);
  NinepPutU32(req, 0, off - 4);
  req[4] = P9_TREAD;
  req[5] = ninep_tag & 0xFF;
  req[6] = (ninep_tag >> 8) & 0xFF;
  if (NinepSend(off) <= 0)
    return -6;
  if (rsp[4] != P9_RREAD)
    return -7;
  n = NinepGetU32(rsp, 7);
  if (n > cap)
    n = cap;
  MemCpy(buf, rsp + 11, n);
  ninep_tag++;
  off = 7 + 4;
  NinepPutU32(req, 7, fid);
  NinepPutU32(req, 0, off - 4);
  req[4] = P9_TCLUNK;
  req[5] = ninep_tag & 0xFF;
  req[6] = (ninep_tag >> 8) & 0xFF;
  NinepSend(off);
  ninep_tag++;
  return n;
}

I64 Mount9p(U8 *prefix, U8 *tag)
{
  U8 mtag[64];
  U8 buf[4096];
  I64 n;
  if (!prefix)
    prefix = "";
  if (NinepInit())
    return -1;
  if (NinepVersion())
    return -2;
  if (!tag || !tag[0]) {
    if (NinepMountTag(mtag, 64) <= 0)
      return -3;
    tag = mtag;
  }
  if (NinepAttach(tag))
    return -4;
  n = NinepReadPath("test.txt", buf, 4095);
  if (n < 0)
    return n;
  buf[n] = 0;
  if (prefix[0]) {
    U8 local[160];
    local[0] = 0;
    StrCpy(local, prefix);
    if (prefix[StrLen(prefix) - 1] != '/')
      StrCat(local, "/");
    StrCat(local, "test.txt");
    return FileWrite(local, buf, n);
  }
  return FileWrite("test.txt", buf, n);
}

I64 NinepSmoke()
{
  U8 buf[64];
  I64 n;
  if (NinepInit())
    return -1;
  if (NinepVersion())
    return -2;
  if (NinepAttach("hostshare"))
    return -3;
  n = NinepReadPath("test.txt", buf, 63);
  if (n < 13)
    return -4;
  buf[n] = 0;
  if (MemCmp(buf, "hello from 9p", 13))
    return -5;
  return 0;
}
// Man("Mount9p") — import host virtfs file into memfs (Run("ninep.hc") first).
//   Mount9p("host/", "hostshare");  // prefix optional; tag=0 reads mount_tag
//   NinepSmoke();                 // oracle helper for QEMU -virtfs smoke
