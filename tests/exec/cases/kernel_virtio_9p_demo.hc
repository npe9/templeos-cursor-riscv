// HolyC virtio-mmio 9p client smoke: read + export + overwrite + nested Tmkdir.
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}
// Nested/overwrite in primary TU (AOT-safe vs Kernel_RV.PRJ includes).
I64 V9pCreate(U8 *path, U8 *buf, I64 len)
{
  U32 fid;
  I64 n, rc;
  fid = NinePClientAllocFid(&ninep_client);
  rc = NinePClientWalkClone(&ninep_client, ninep_client.root_fid, fid);
  if (rc)
    return -2;
  rc = NinePClientLcreate(&ninep_client, fid, path, P9_O_RDWR | P9_O_TRUNC, P9_MODE_FILE, 0);
  if (rc) {
    NinePClientClunk(&ninep_client, fid);
    return -4;
  }
  n = NinePClientWriteAll(&ninep_client, fid, buf, len);
  NinePClientClunk(&ninep_client, fid);
  return n;
}

I64 V9pOverwrite(U8 *path, U8 *buf, I64 len)
{
  U32 fid;
  fid = NinePClientAllocFid(&ninep_client);
  if (!NinePClientWalk(&ninep_client, ninep_client.root_fid, fid, path))
    NinePClientRemove(&ninep_client, fid);
  return V9pCreate(path, buf, len);
}

I64 V9pMkdirOne(U32 parent, U8 *name)
{
  U32 fid;
  fid = NinePClientAllocFid(&ninep_client);
  if (!NinePClientWalk(&ninep_client, parent, fid, name))
    return fid;
  NinePClientMkdir(&ninep_client, parent, name, P9_MODE_DIR, 0);
  fid = NinePClientAllocFid(&ninep_client);
  if (NinePClientWalk(&ninep_client, parent, fid, name))
    return 0;
  return fid;
}

I64 V9pNestedWrite(U8 *dir1, U8 *dir2, U8 *leaf, U8 *buf, I64 len)
{
  U32 d1, d2, fid, cfid;
  I64 n;
  d1 = V9pMkdirOne(ninep_client.root_fid, dir1);
  if (!d1)
    return -3;
  d2 = V9pMkdirOne(d1, dir2);
  NinePClientClunk(&ninep_client, d1);
  if (!d2)
    return -3;
  fid = NinePClientAllocFid(&ninep_client);
  if (!NinePClientWalk(&ninep_client, d2, fid, leaf))
    NinePClientRemove(&ninep_client, fid);
  cfid = NinePClientAllocFid(&ninep_client);
  if (NinePClientWalkClone(&ninep_client, d2, cfid)) {
    NinePClientClunk(&ninep_client, d2);
    return -2;
  }
  if (NinePClientLcreate(&ninep_client, cfid, leaf, P9_O_RDWR | P9_O_TRUNC, P9_MODE_FILE, 0)) {
    NinePClientClunk(&ninep_client, cfid);
    NinePClientClunk(&ninep_client, d2);
    return -4;
  }
  n = NinePClientWriteAll(&ninep_client, cfid, buf, len);
  NinePClientClunk(&ninep_client, cfid);
  NinePClientClunk(&ninep_client, d2);
  return n;
}

I64 main()
{
  I64 rc;
  Sh("virtio-9p demo: 9P2000.L client (mmio or pci)\n");
  rc = Virtio9pSelfTest("hello from 9p", 13);
  if (rc) {
    Sh("virtio-9p: read_fail\n");
    return rc;
  }
  rc = V9pCreate("export.txt", "guest->host 9p\n", 15);
  if (rc != 15) {
    Sh("virtio-9p: read_fail\n");
    return -4;
  }
  rc = V9pOverwrite("export.txt", "overwrite-9p\n", 13);
  if (rc != 13) {
    Sh("virtio-9p: read_fail\n");
    return -5;
  }
  rc = V9pNestedWrite("Home", "nest", "out.hc", "nested-9p\n", 10);
  if (rc != 10) {
    Sh("virtio-9p: read_fail\n");
    return -6;
  }
  Sh("virtio-9p: read_ok\n");
  return 0;
}
