// NinePClient.HC — 9P2000.L protocol (version, attach, walk, open/create, read/write, readdir, clunk).
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
  I64 off, rlen, msize, vlen;
  U8 type;
  if (!c || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7;
  NinePPutU32(req, off, c->msize);
  off += 4;
  off = NinePPutStr(req, off, "9P2000.L");
  // size[4] in 9P COUNTS ITSELF. This wrote off-4 for every message type in this file, which is
  // four bytes short, and it survived because the virtio transports never made it matter: QEMU's
  // 9pfs takes the length from the virtqueue descriptor, not from the field. The first transport
  // that honours the field -- NinePEth, where a datagram carries no length of its own -- had the
  // server truncating every request by four bytes. Tversion still "worked" because its trailing
  // string is not validated; Twalk lost the tail of the filename and came back Rlerror.
  NinePPutU32(req, 0, off);
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
  // What the SERVER agreed to, which need not be what we asked for. 9P says a server that does
  // not know the requested version answers with one it does know (or "unknown"), so a client
  // that reads only the reply type believes it negotiated .L against a plain 9P2000 server --
  // and then hangs on the first Tlopen, because opcode 12 means nothing there.
  //
  // Measured against Inferno's Styx (listen + export /): we send "9P2000.L", it answers
  // "9P2000" and msize=8192, Tattach succeeds, and Tlopen gets NO REPLY AT ALL. Recording the
  // dialect is what lets a caller pick Topen over Tlopen instead of stalling.
  vlen = NinePGetU16(rsp, 11);
  c->dialect = P9_DIALECT_NONE;
  if (vlen >= 8 && !MemCmp(rsp + 13, "9P2000.L", 8))
    c->dialect = P9_DIALECT_2000L;
  else if (vlen >= 6 && !MemCmp(rsp + 13, "9P2000", 6))
    c->dialect = P9_DIALECT_2000;
  if (c->dialect == P9_DIALECT_NONE)
    return -6;
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
  NinePPutU32(req, 0, off);
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
  NinePPutU32(req, 0, off);
  req[4] = P9_TWALK;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RWALK) {
    c->tag++;
    return -3;
  }
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientWalkClone(CNinePClient *c, U32 fid, U32 newfid)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 4 + 2;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 11, newfid);
  NinePPutU16(req, 15, 0);
  NinePPutU32(req, 0, off);
  req[4] = P9_TWALK;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RWALK) {
    c->tag++;
    return -3;
  }
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
  NinePPutU32(req, 0, off);
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
  NinePPutU32(req, 0, off);
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

I64 NinePClientLcreate(CNinePClient *c, U32 fid, U8 *name, U32 flags, U32 mode, U32 gid)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !name || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4;
  NinePPutU32(req, 7, fid);
  off = NinePPutStr(req, off, name);
  NinePPutU32(req, off, flags);
  off += 4;
  NinePPutU32(req, off, mode);
  off += 4;
  NinePPutU32(req, off, gid);
  off += 4;
  NinePPutU32(req, 0, off);
  req[4] = P9_TLCREATE;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RLCREATE)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientMkdir(CNinePClient *c, U32 dfid, U8 *name, U32 mode, U32 gid)
{
  U8 *req, *rsp;
  I64 off, rlen;
  U8 type;
  if (!c || !name || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4;
  NinePPutU32(req, 7, dfid);
  off = NinePPutStr(req, off, name);
  NinePPutU32(req, off, mode);
  off += 4;
  NinePPutU32(req, off, gid);
  off += 4;
  NinePPutU32(req, 0, off);
  req[4] = P9_TMKDIR;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RMKDIR)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  c->tag++;
  return 0;
}

I64 NinePClientRemove(CNinePClient *c, U32 fid)
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
  NinePPutU32(req, 0, off);
  req[4] = P9_TREMOVE;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RREMOVE)
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
  NinePPutU32(req, 0, off);
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

I64 NinePClientWrite(CNinePClient *c, U32 fid, U64 offset, U8 *buf, I64 len)
{
  U8 *req, *rsp;
  I64 off, rlen, i, chunk, maxc;
  U8 type;
  U32 cnt;
  if (!c || !buf || len <= 0 || !ninep_req_buf || !ninep_rsp_buf)
    return -1;
  maxc = c->msize - P9_IOHDRSZ;
  if (maxc > P9_WRITE_CHUNK)
    maxc = P9_WRITE_CHUNK;
  if (maxc < 64)
    return -5;
  chunk = len;
  if (chunk > maxc)
    chunk = maxc;
  req = ninep_req_buf;
  rsp = ninep_rsp_buf;
  off = 7 + 4 + 8 + 4;
  NinePPutU32(req, 7, fid);
  NinePPutU32(req, 11, offset & 0xFFFFFFFF);
  NinePPutU32(req, 15, (offset >> 32) & 0xFFFFFFFF);
  NinePPutU32(req, 19, chunk);
  for (i = 0; i < chunk; i++)
    req[23 + i] = buf[i];
  off = 23 + chunk;
  NinePPutU32(req, 0, off);
  req[4] = P9_TWRITE;
  NinePPutU16(req, 5, c->tag);
  rlen = NinePClientCall(c, off);
  if (rlen <= 0)
    return -2;
  type = rsp[4];
  if (type != P9_RWRITE)
    return -3;
  if (NinePGetU16(rsp, 5) != c->tag)
    return -4;
  cnt = NinePGetU32(rsp, 7);
  c->tag++;
  return cnt;
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
  NinePPutU32(req, 0, off);
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

I64 NinePClientWriteAll(CNinePClient *c, U32 fid, U8 *buf, I64 len)
{
  I64 off, n, left;
  if (!c || !buf || len < 0)
    return -1;
  off = 0;
  left = len;
  while (left > 0) {
    n = NinePClientWrite(c, fid, off, buf + off, left);
    if (n <= 0)
      return -2;
    off += n;
    left -= n;
  }
  return off;
}

I64 NinePClientWritePath(CNinePClient *c, U8 *path, U8 *buf, I64 len)
{
  U32 fid;
  I64 n, rc;
  if (!c || !path || !path[0] || !buf || len < 0)
    return -1;
  // Single path component. Nested/overwrite: NinePClientWritePathEx / seed NinepWritePath.
  fid = NinePClientAllocFid(c);
  rc = NinePClientWalkClone(c, c->root_fid, fid);
  if (rc)
    return -2;
  rc = NinePClientLcreate(c, fid, path, P9_O_RDWR | P9_O_TRUNC, P9_MODE_FILE, 0);
  if (rc) {
    NinePClientClunk(c, fid);
    return -4;
  }
  n = NinePClientWriteAll(c, fid, buf, len);
  NinePClientClunk(c, fid);
  return n;
}
// Walk to `name` under `parent`, creating it as a directory if it is not there. Returns a fid
// for the directory, or 0. The walk-first order matters: Tmkdir on an existing name is an error
// on a real server, so trying the walk is how "already there" stays a success.
U32 NinePClientMkdirWalk(CNinePClient *c, U32 parent, U8 *name)
{
  U32 fid;
  fid = NinePClientAllocFid(c);
  if (!NinePClientWalk(c, parent, fid, name))
    return fid;
  NinePClientMkdir(c, parent, name, P9_MODE_DIR, 0);
  fid = NinePClientAllocFid(c);
  if (NinePClientWalk(c, parent, fid, name))
    return 0;
  return fid;
}
// Write `path` with as many directory components as it has, creating the parents. This is what
// NinePClientWritePath's own comment has pointed at all along -- the name was referenced and
// never written, so a nested write simply failed, and the seed image's NinepWritePath was the
// only thing that could do it. Ported here when NinepSmoke moved onto the kernel's 9p client.
I64 NinePClientWritePathEx(CNinePClient *c, U8 *path, U8 *buf, I64 len)
{
  U8 comp[128];
  U32 dir, next, fid, cfid;
  I64 i, j, rc, n;
  if (!c || !path || !path[0] || !buf || len < 0)
    return -1;
  dir = c->root_fid;
  i = 0;
  while (TRUE) {
    j = 0;
    while (path[i] && path[i] != '/' && j < 127)
      comp[j++] = path[i++];
    comp[j] = 0;
    if (!j)
      return -1;
    if (!path[i])
      break;
    // a separator follows, so this component is a directory on the way to the leaf
    while (path[i] == '/')
      i++;
    next = NinePClientMkdirWalk(c, dir, comp);
    if (dir != c->root_fid)
      NinePClientClunk(c, dir);
    if (!next)
      return -3;
    dir = next;
  }
  // comp is the leaf. Remove a stale one first: Tlcreate over an existing name fails.
  fid = NinePClientAllocFid(c);
  if (!NinePClientWalk(c, dir, fid, comp))
    NinePClientRemove(c, fid);
  cfid = NinePClientAllocFid(c);
  if (NinePClientWalkClone(c, dir, cfid)) {
    if (dir != c->root_fid)
      NinePClientClunk(c, dir);
    return -2;
  }
  rc = NinePClientLcreate(c, cfid, comp, P9_O_RDWR | P9_O_TRUNC, P9_MODE_FILE, 0);
  if (rc) {
    NinePClientClunk(c, cfid);
    if (dir != c->root_fid)
      NinePClientClunk(c, dir);
    return -4;
  }
  n = NinePClientWriteAll(c, cfid, buf, len);
  NinePClientClunk(c, cfid);
  if (dir != c->root_fid)
    NinePClientClunk(c, dir);
  return n;
}
#endif
