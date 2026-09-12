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
  I64 rc, gsz, i;
  U8 *got;
  CTask *adam = 0x86900000;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  // Boot scaffolding so FileRead HashFind sees live Fs+adam_task.
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVKernelInit();
  if (!blkdev.blkdevs) {
    blkdev.blkdevs = CAlloc(sizeof(CBlkDev) * BLKDEVS_NUM);
    blkdev.drvs = CAlloc(sizeof(CDrv) * DRVS_NUM);
    for (i = 0; i < DRVS_NUM; i++)
      blkdev.let_to_drv[i] = &blkdev.drvs[i];
  }
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
  // G28: Virtio9pConnect plants soft P: (RVSoftLet9pPlant).
  if (!Let2Drv('P', FALSE)) {
    Sh("virtio-9p: Let2Drv P FAIL\n");
    return -7;
  }
  Sh("virtio-9p: Let2Drv P ok\n");
  // G28 VFS: stock FileRead("P:/…") → NineP (no Virtio9pReadPath import).
  gsz = 0;
  got = FileRead("P:/test.txt", &gsz, NULL);
  if (!got || gsz < 13 || MemCmp(got, "hello from 9p", 13)) {
    Sh("virtio-9p: FileRead P FAIL\n");
    Free(got);
    return -8;
  }
  Free(got);
  Sh("virtio-9p: FileRead P ok\n");
  // G28: stock FilesFind("P:/*") after nested opens (Treaddir + d_off).
  
  {
    CDirEntry *de, *tmp;
    I64 nent = 0;
    Bool saw = FALSE;
    de = FilesFind("P:/*");
    tmp = de;
    while (tmp) {
      nent++;
      if (!StrCmp(tmp->name, "test.txt"))
        saw = TRUE;
      tmp = tmp->next;
    }
    DirTreeDel(de);
    if (!nent || !saw) {
      Sh("virtio-9p: FilesFind P FAIL\n");
      return -9;
    }
  }
  Sh("virtio-9p: FilesFind P ok\n");
  // Nested FilesFind after V9pNestedWrite created Home/nest/out.hc.
  
  {
    CDirEntry *de, *tmp;
    I64 nent = 0;
    Bool saw_nest = FALSE, saw_out = FALSE;
    de = FilesFind("P:/Home/*");
    tmp = de;
    while (tmp) {
      nent++;
      if (!StrCmp(tmp->name, "nest"))
        saw_nest = TRUE;
      tmp = tmp->next;
    }
    DirTreeDel(de);
    if (!nent || !saw_nest) {
      Sh("virtio-9p: FilesFind P/Home FAIL\n");
      return -10;
    }
    nent = 0;
    de = FilesFind("P:/Home/nest/*");
    tmp = de;
    while (tmp) {
      nent++;
      if (!StrCmp(tmp->name, "out.hc"))
        saw_out = TRUE;
      tmp = tmp->next;
    }
    DirTreeDel(de);
    if (!nent || !saw_out) {
      Sh("virtio-9p: FilesFind P/Home/nest FAIL\n");
      return -11;
    }
  }
  Sh("virtio-9p: FilesFind nested ok\n");
  // G28: DirContext Cd on FSt_9P — stock Cd("P:/…") then relative FilesFind("*").
  
  {
    CDirEntry *de, *tmp;
    I64 nent = 0;
    Bool saw_nest = FALSE, saw_out = FALSE;
    U8 *cwd;
    if (!Cd("P:/Home")) {
      Sh("virtio-9p: Cd P:/Home FAIL\n");
      return -12;
    }
    cwd = DirCur;
    if (!cwd || StrCmp(cwd, "P:/Home")) {
      Sh("virtio-9p: Cd DirCur FAIL\n");
      Free(cwd);
      return -13;
    }
    Free(cwd);
    de = FilesFind("*");
    tmp = de;
    while (tmp) {
      nent++;
      if (!StrCmp(tmp->name, "nest"))
        saw_nest = TRUE;
      tmp = tmp->next;
    }
    DirTreeDel(de);
    if (!nent || !saw_nest) {
      Sh("virtio-9p: DirContext FilesFind FAIL\n");
      return -14;
    }
    if (!Cd("nest")) {
      Sh("virtio-9p: Cd nest FAIL\n");
      return -15;
    }
    nent = 0;
    de = FilesFind("*");
    tmp = de;
    while (tmp) {
      nent++;
      if (!StrCmp(tmp->name, "out.hc"))
        saw_out = TRUE;
      tmp = tmp->next;
    }
    DirTreeDel(de);
    if (!nent || !saw_out) {
      Sh("virtio-9p: DirContext nest FAIL\n");
      return -16;
    }
    if (!Cd("P:/")) {
      Sh("virtio-9p: Cd P:/ FAIL\n");
      return -17;
    }
  }
  Sh("virtio-9p: DirContext Cd ok\n");
  Sh("virtio-9p: read_ok\n");
  return 0;
}
