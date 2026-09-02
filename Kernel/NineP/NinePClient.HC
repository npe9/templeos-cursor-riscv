// NinePClient.HC — 9P2000.L protocol (version, attach, walk, open, read, readdir, clunk).
#ifndef NINEP_CLIENT_HC
#define NINEP_CLIENT_HC
#include "NineP.HH"
#include "NinePCodec.HC"
I64 NinePClientInit(CNinePClient *c, I64 tp_kind)
{
  if (!c)
    return -1;
  c->tp_kind = tp_kind;
  c->tag = 1;
  c->msize = P9_MSIZE_DEFAULT;
  c->root_fid = 0;
  c->next_fid = 1;
  return 0;
}

I64 NinePClientCall(CNinePClient *c, I64 req_len)
{
  if (!c || c->tp_kind != ninep_tp_kind)
    return -1;
  return NinePTransportSendRecv(req_len);
}

I64 NinePClientVersion(CNinePClient *c)
{
  U8 *req, *rsp;
  I64 off, rlen, msize;
  U8 type;
  if (!c || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7;
  NinePPutU32(req, off, c->msize);
  off += 4;
  off = NinePPutStr(req, off, "9P2000.L");
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TVERSION;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RVERSION)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  msize = NinePGetU32(rsp, 7);
  if (msize < 512)
    return -5;
  c->msize = msize;
  c->tag++;
  return 0;
}

I64 NinePClientAttach(CNinePClient *c, U8 *aname, U8 *uname)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !aname || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  if (!uname)
    uname = "holyc";
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 4;
  NinePPutU32(req, 7, c->root_fid);
  NinePPutU32(req, 11, P9_NOFID);
  off = NinePPutStr(req, off, uname);
  off = NinePPutStr(req, off, aname);
  NinePPutU32(req, off, 0);
  off += 4;
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TATTACH;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RATTACH)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientWalk(CNinePClient *c, U32 fid, U32 newfid, U8 *name)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !name || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 4 + 2;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 11, newfid);
  NinePPutU16(req, 15, 1);
  off = NinePPutStr(req, off, name);
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TWALK;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RWALK)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientClunk(CNinePClient *c, U32 fid)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TCLUNK;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RCLUNK)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientLopen(CNinePClient *c, U32 fid, U32 flags)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 4;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 11, flags);
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TLOPEN;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RLOPEN)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientRead(CNinePClient *c, U32 fid, U64 offset, U8 *buf, I64 cap)
{
  U8 *req, *rsp;
  I64 off, rlen, n, i;
  U8 type;
  U32 cnt;
  if (!c || !buf || cap <= 0 || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 8 + 4;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 11, offset & 0xFFFFFFFF);
  NinePPutU32(req, 15, (offset >> 32) & 0xFFFFFFFF);
  NinePPutU32(req, 19, cap);
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TREAD;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RREAD)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  cnt = NinePGetU32(rsp, 7);
  n = cnt;
  if (n > cap)
    n = cap;
  for (i = 0; i < n; i++)
    buf[i] = rsp[11 + i];
  c->tag++;
  return n;
}

I64 NinePClientReaddir(CNinePClient *c, U32 fid, U64 offset, U8 *buf, I64 cap)
{
  U8 *req, *rsp;
  I64 off, rlen, n, i;
  U8 type;
  U32 cnt;
  if (!c || !buf || cap <= 0 || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 8 + 4;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 11, offset & 0xFFFFFFFF);
  NinePPutU32(req, 15, (offset >> 32) & 0xFFFFFFFF);
  NinePPutU32(req, 19, cap);
  NinePPutU32(req, 0, off - 4);
  req[4] = P9_TREADDIR;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RREADDIR)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  cnt = NinePGetU32(rsp, 7);
  n = cnt;
  if (n > cap)
    n = cap;
  for (i = 0; i < n; i++)
    buf[i] = rsp[11 + i];
  c->tag++;
  return n;
}

U32 NinePClientAllocFid(CNinePClient *c)
{
  U32 f;
  if (!c)
    return 0;
  f = c->next_fid;
  c->next_fid++;
  return f;
}

I64 NinePClientReadPath(CNinePClient *c, U8 *path, U8 *buf, I64 cap)
{
  U32 fid;
  I64 n;
  if (!c || !path || !buf)
    return -1;
  fid = NinePClientAllocFid(c);
  if (NinePClientWalk(c, c->root_fid, fid, path))
    return -2;
  if (NinePClientLopen(c, fid, P9_O_RDONLY))
    return -3;
  n = NinePClientRead(c, fid, 0, buf, cap);
  NinePClientClunk(c, fid);
  return n;
}
#endif
