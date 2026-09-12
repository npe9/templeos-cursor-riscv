// Virtio9p.HC — 9P2000.L client facade (NinePClient + pluggable NinePTransport).
// Dig-down: Man("Virtio9p"); Virtio9pInit; Mount9p; NineExport; Virtio9pSelfTest;
#ifndef RV_DRV_VIRTIO_9P_HC
#define RV_DRV_VIRTIO_9P_HC
#include "../NineP/NineP.HH"
#include "../NineP/NinePCodec.HC"
#include "NinePVirtioMmio.HC"
#include "NinePVirtioPci.HC"
#include "../NineP/NinePTransport.HC"
#include "../NineP/NinePClient.HC"
CNinePClient ninep_client;
I64 ninep_ready;
U0 Virtio9pNormSharePath(U8 *path, U8 *out, I64 cap)
{
  I64 i, j;
  if (!out || cap <= 1)
    return;
  out[0] = 0;
  if (!path || !path[0])
    return;
  i = 0;
  if (path[0] && path[1] == ':') {
    if (path[2] == '/' || path[2] == '\\')
      i = 3;
    else
      i = 2;
  }
  while (path[i] == '/' || path[i] == '\\')
    i++;
  j = 0;
  while (path[i] && j < cap - 1) {
    if (path[i] == '\\')
      out[j] = '/';
    else
      out[j] = path[i];
    j++;
    i++;
  }
  out[j] = 0;
}
extern CDrv *RVSoftLet9pPlantQuiet(U8 drv_let = 'P');
I64 Virtio9pConnect(U8 *tag)
{
  U8 mtag[64];
  I64 tp;
  if (NinePTransportBindAny())
    return -1;
  tp = ninep_tp_kind;
  if (NinePClientInit(&ninep_client, tp))
    return -2;
  if (NinePClientVersion(&ninep_client))
    return -3;
  if (!tag || !tag[0]) {
    if (NinePTransportMountTag(mtag, 64) <= 0)
      return -4;
    tag = mtag;
  }
  if (NinePClientAttach(&ninep_client, tag, "holyc"))
    return -5;
  ninep_ready = 1;
  // G28: 9P share is drive letter P: (quiet — thin demos may lack put_s).
  // Select cur_dv so stock Cd("P:/…") / DirContext skip the !cur_dv soft path
  // (soft plant-only Cd stays ::/… until Connect — home smoke).
  RVSoftLet9pPlantQuiet('P');
  Drv('P');
  return 0;
}

I64 Virtio9pInit()
{
  ninep_ready = 0;
  return Virtio9pConnect(0);
}

I64 Virtio9pVersion()
{
  if (NinePTransportBindAny())
    return -1;
  if (NinePClientInit(&ninep_client, ninep_tp_kind))
    return -2;
  return NinePClientVersion(&ninep_client);
}

I64 Virtio9pGetMountTag(U8 *buf, I64 cap)
{
  if (NinePTransportBindAny())
    return -1;
  return NinePTransportMountTag(buf, cap);
}

I64 Virtio9pAttach(U8 *aname)
{
  if (!ninep_ready) {
    if (Virtio9pConnect(aname))
      return -1;
    return 0;
  }
  return NinePClientAttach(&ninep_client, aname, "holyc");
}

I64 Virtio9pReadPath(U8 *path, U8 *buf, I64 cap)
{
  if (!ninep_ready)
    return -1;
  return NinePClientReadPath(&ninep_client, path, buf, cap);
}

I64 Virtio9pWritePath(U8 *path, U8 *buf, I64 len)
{
  // Nested Tmkdir + Tremove overwrite: prefer primary-TU / seed NinepWritePath
  // (HolyC AOT miscompiles the fuller body under Kernel_RV.PRJ includes).
  if (!ninep_ready)
    return -1;
  return NinePClientWritePath(&ninep_client, path, buf, len);
}

I64 Virtio9pImportFile(U8 *host_path, U8 *local_path)
{
  U8 buf[4096];
  I64 n;
  if (!ninep_ready)
    return -1;
  n = NinePClientReadPath(&ninep_client, host_path, buf, 4095);
  if (n < 0)
    return n;
  buf[n] = 0;
  return FileWrite(local_path, buf, n);
}

I64 Virtio9pExportFile(U8 *local_path, U8 *host_path)
{
  U8 *buf;
  I64 sz, n;
  U8 name[128];
  if (!ninep_ready)
    return -1;
  if (!local_path || !local_path[0])
    return -2;
  if (!host_path || !host_path[0]) {
    Virtio9pNormSharePath(local_path, name, 128);
    host_path = name;
  }
  if (!host_path[0])
    return -3;
  sz = 0;
  buf = FileRead(local_path, &sz, NULL);
  if (!buf || sz < 0)
    return -4;
  n = Virtio9pWritePath(host_path, buf, sz);
  return n;
}

I64 NineExport(U8 *path)
{
  U8 name[128];
  if (!path || !path[0])
    return -1;
  if (!ninep_ready) {
    if (Virtio9pConnect(0))
      return -2;
  }
  Virtio9pNormSharePath(path, name, 128);
  if (!name[0])
    return -3;
  return Virtio9pExportFile(path, name);
}

I64 NineExportAs(U8 *local_path, U8 *host_name)
{
  if (!local_path || !local_path[0] || !host_name || !host_name[0])
    return -1;
  if (!ninep_ready) {
    if (Virtio9pConnect(0))
      return -2;
  }
  return Virtio9pExportFile(local_path, host_name);
}

I64 Mount9p(U8 *prefix, U8 *tag)
{
  U8 dent[512];
  U8 name[128];
  U8 local[160];
  U64 off, d_off;
  I64 n, i, ns, copied, ent;
  U8 qtype;
  U32 fid;
  if (!prefix)
    prefix = "";
  if (Virtio9pConnect(tag))
    return -1;
  fid = NinePClientAllocFid(&ninep_client);
  if (NinePClientWalkClone(&ninep_client, ninep_client.root_fid, fid))
    return -2;
  if (NinePClientLopen(&ninep_client, fid, P9_O_RDONLY | P9_O_DIRECTORY)) {
    NinePClientClunk(&ninep_client, fid);
    return -3;
  }
  copied = 0;
  off = 0;
  while (1) {
    n = NinePClientReaddir(&ninep_client, fid, off, dent, 512);
    if (n <= 0)
      break;
    i = 0;
    while (i + 24 <= n) {
      qtype = dent[i];
      d_off = NinePGetU64(dent, i + 13);
      ns = NinePGetU16(dent, i + 22);
      if (ns <= 0 || ns >= 120 || i + 24 + ns > n)
        break;
      MemSet(name, 0, 128);
      MemCpy(name, dent + i + 24, ns);
      name[ns] = 0;
      ent = 24 + ns;
      i += ent;
      off = d_off;
      if (name[0] == '.')
        continue;
      if (qtype & P9_QTDIR)
        continue;
      local[0] = 0;
      if (prefix[0]) {
        StrCpy(local, prefix);
        if (prefix[StrLen(prefix) - 1] != '/')
          StrCat(local, "/");
      }
      StrCat(local, name);
      if (Virtio9pImportFile(name, local) >= 0)
        copied++;
    }
    if (i == 0)
      break;
  }
  NinePClientClunk(&ninep_client, fid);
  return copied;
}

I64 Virtio9pSelfTest(U8 *expect, I64 expect_len)
{
  U8 buf[256];
  I64 n;
  if (Virtio9pConnect(0))
    return -1;
  n = NinePClientReadPath(&ninep_client, "test.txt", buf, 256);
  if (n < expect_len)
    return -2;
  if (MemCmp(buf, expect, expect_len))
    return -3;
  return 0;
}
// G28: FilesFind("P:/*") / nested "P:/dir/*" — real ninep_client Treaddir.
// dir=NULL/"" → share root; else walk path components then readdir.
CDirEntry *Virtio9pFilesFindMask(U8 *dir, U8 *mask, I64 fuf_flags)
{
  U8 dent[512], name[128], comp[128], *full, *p;
  U64 off, d_off;
  I64 n, i, ns, ent, ci;
  U8 qtype;
  U32 fid;
  CDirEntry *res = NULL, *tmpde;
  if (!ninep_ready || !mask)
    return NULL;
  // 9P2000.L: Treaddir needs an opened directory fid; parse all dirents per Rreaddir.
  fid = NinePClientAllocFid(&ninep_client);
  if (NinePClientWalkClone(&ninep_client, ninep_client.root_fid, fid))
    return NULL;
  if (dir && dir[0]) {
    p = dir;
    while (*p) {
      while (*p == '/')
        p++;
      if (!*p)
        break;
      ci = 0;
      while (*p && *p != '/' && ci < 127) {
        comp[ci] = *p;
        ci++;
        p++;
      }
      comp[ci] = 0;
      if (!comp[0])
        break;
      // Twalk in place (newfid==fid) for each path component.
      if (NinePClientWalk(&ninep_client, fid, fid, comp)) {
        NinePClientClunk(&ninep_client, fid);
        return NULL;
      }
    }
  }
  if (NinePClientLopen(&ninep_client, fid, P9_O_RDONLY | P9_O_DIRECTORY)) {
    NinePClientClunk(&ninep_client, fid);
    return NULL;
  }
  off = 0;
  while (1) {
    n = NinePClientReaddir(&ninep_client, fid, off, dent, 512);
    if (n <= 0)
      break;
    i = 0;
    while (i + 24 <= n) {
      qtype = dent[i];
      // qid.type (P9_QTDIR), not linux d_type
      d_off = NinePGetU64(dent, i + 13);
      ns = NinePGetU16(dent, i + 22);
      if (ns <= 0 || ns >= 120 || i + 24 + ns > n)
        break;
      MemSet(name, 0, 128);
      MemCpy(name, dent + i + 24, ns);
      name[ns] = 0;
      ent = 24 + ns;
      i += ent;
      off = d_off;
      if (name[0] == '.')
        continue;
      if (Bt(&fuf_flags, FUf_JUST_DIRS) && !(qtype & P9_QTDIR))
        continue;
      if (Bt(&fuf_flags, FUf_JUST_FILES) && (qtype & P9_QTDIR))
        continue;
      if (!FilesFindMatch(name, mask, fuf_flags))
        continue;
      tmpde = CAlloc(sizeof(CDirEntry));
      StrCpy(tmpde->name, name);
      if (qtype & P9_QTDIR)
        tmpde->attr = RS_ATTR_DIR;
      if (dir && dir[0])
        full = MStrPrint("P:/%s/%s", dir, name);
      else
        full = MStrPrint("P:/%s", name);
      tmpde->full_name = full;
      tmpde->next = res;
      res = tmpde;
    }
    if (i == 0)
      break;
  }
  NinePClientClunk(&ninep_client, fid);
  return res;
}
// Man("Virtio9p") -- Virtio9p()
// NAME
//   Virtio9p - transport-agnostic 9P2000.L client (host virtfs import/export)
// SYNOPSIS
//   I64 Virtio9pInit();
//   I64 Mount9p(U8 *prefix, U8 *tag);
//   I64 Virtio9pReadPath(U8 *path, U8 *buf, I64 cap);
//   I64 Virtio9pWritePath(U8 *path, U8 *buf, I64 len);
//   I64 NineExport(U8 *path);
//   I64 NineExportAs(U8 *local, U8 *host_name);
//   I64 Virtio9pSelfTest(U8 *expect, I64 expect_len);
// DESCRIPTION
//   Layered client: NinePClient + NinePTransport (MMIO first, PCI queues if no
//   mmio 9p). Attach QEMU -virtfs / -fsdev on virtio-9p-device or virtio-9p-pci.
//   Mount9p(prefix, tag) reads host share root and imports regular files into
//   the memfs namespace at prefix/. NineExport(path) / Virtio9pWritePath push
//   guest bytes onto the share (Tmkdir parents, Tlcreate or Tlopen+Twrite
//   overwrite). Nested paths like Home/a/b.hc create dirs on the share.
//   Pass tag=0 to use the device mount_tag. Successful Connect plants soft
//   letter P: (RVSoftLet9pPlant) so Let2Drv('P') / Cd("P:/…") grammar works.
U0 Virtio9p()
{
  "Virtio9p: NinePClient + virtio-mmio/pci transport (DeviceID 9)\n";
  "  Init=%d tp=%d\n", Virtio9pInit(), ninep_tp_kind;
}
#endif
