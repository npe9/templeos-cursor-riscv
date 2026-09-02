// Virtio9p.HC — 9P2000.L client facade (NinePClient + pluggable NinePTransport).
// Dig-down: Man("Virtio9p"); Virtio9pInit; Mount9p; Virtio9pSelfTest;
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
I64 Virtio9pConnect(U8 *tag)
{
  U8 mtag[64];
  if (NinePTransportBindMmio())
    return -1;
  if (NinePClientInit(&ninep_client, NINEP_TP_MMIO))
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
  return 0;
}

I64 Virtio9pInit()
{
  ninep_ready = 0;
  return Virtio9pConnect(0);
}

I64 Virtio9pVersion()
{
  if (NinePTransportBindMmio())
    return -1;
  if (NinePClientInit(&ninep_client, NINEP_TP_MMIO))
    return -2;
  return NinePClientVersion(&ninep_client);
}

I64 Virtio9pGetMountTag(U8 *buf, I64 cap)
{
  if (NinePTransportBindMmio())
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

I64 Mount9p(U8 *prefix, U8 *tag)
{
  U8 dent[512];
  U8 name[128];
  U8 local[160];
  U64 off;
  I64 n, i, ns, copied;
  U8 dtype;
  if (!prefix)
    prefix = "";
  if (Virtio9pConnect(tag))
    return -1;
  copied = 0;
  off = 0;
  while (1) {
    n = NinePClientReaddir(&ninep_client, ninep_client.root_fid, off, dent, 512);
    if (n <= 0)
      break;
    i = 0;
    i += 13;
    i += 8;
    dtype = dent[i];
    i += 1;
    ns = NinePGetU16(dent, i);
    i += 2;
    if (ns <= 0 || ns >= 120)
      break;
    MemSet(name, 0, 128);
    MemCpy(name, dent + i, ns);
    name[ns] = 0;
    i += ns;
    off += n;
    if (name[0] == '.')
      continue;
    if (dtype == P9_QTDIR)
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
// Man("Virtio9p") -- Virtio9p()
// NAME
//   Virtio9p - transport-agnostic 9P2000.L client (host virtfs import)
// SYNOPSIS
//   I64 Virtio9pInit();
//   I64 Mount9p(U8 *prefix, U8 *tag);
//   I64 Virtio9pReadPath(U8 *path, U8 *buf, I64 cap);
//   I64 Virtio9pSelfTest(U8 *expect, I64 expect_len);
// DESCRIPTION
//   Layered client: NinePClient core + NinePTransport (NinePVirtioMmio today;
//   NinePVirtioPci stub). Attach QEMU -virtfs / -fsdev on virtio-9p-device.
//   Mount9p(prefix, tag) reads host share root and imports regular files into
//   the memfs namespace at prefix/. Pass tag=0 to use the device mount_tag.
U0 Virtio9p()
{
  "Virtio9p: NinePClient + virtio-mmio transport (DeviceID 9)\n";
  "  Init=%d\n", Virtio9pInit();
}
#endif
