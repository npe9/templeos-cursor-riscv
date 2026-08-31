// fs.hc -- HolyC-owned memfs at a fixed physical arena (no 0x87001xxx base/cwd slots).
// Layout matches C MemFile / EdC bridge: used I32 @0, name[64] @4, data[65536] @68,
// len I32 @65604, stride 65608. C seed boot + EdC write the same arena at MEMFS_BASE.
#define MEMFS_BASE   0x85000000
#define MEMFS_MAX    64
#define MEMFS_CAP    65536
#define MEMFS_STRIDE 65608
#define MEMFS_OFF_USED 0
#define MEMFS_OFF_NAME 4
#define MEMFS_OFF_DATA 68
#define MEMFS_OFF_LEN  65604
#define MEMFS_CWD    (MEMFS_BASE+MEMFS_MAX*MEMFS_STRIDE)
U8 FsResolveBuf[64];
U8 FsTmp[160];
U8 *FsBase()
{
  return MEMFS_BASE;
}

U8 *FsCwd()
{
  return MEMFS_CWD;
}

I64 FsStrLen(U8 *s)
{
  I64 n = 0;
  if (!s)
    return 0;
  while (*s) {
    n++;
    s++;
  }
  return n;
}

U0 FsStrCpy(U8 *d, U8 *s)
{
  if (!d)
    return;
  if (!s) {
    *d = 0;
    return;
  }
  while (*s) {
    *d = *s;
    d++;
    s++;
  }
  *d = 0;
}

I64 FsStrCmp(U8 *a, U8 *b)
{
  if (!a)
    a = "";
  if (!b)
    b = "";
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a - *b;
}

I64 FsStrNCmp(U8 *a, U8 *b, I64 n)
{
  I64 i;
  for (i = 0; i < n; i++) {
    if (a[i] != b[i])
      return a[i] - b[i];
    if (!a[i])
      return 0;
  }
  return 0;
}
// Resolve name into FsResolveBuf (cwd-relative, fold . / ..).
U0 FsResolve(U8 *name)
{
  U8 *cwd;
  I64 n, i, o;
  if (!name)
    name = "";
  cwd = FsCwd();
  if (!cwd)
    cwd = "";
  n = 0;
  i = 0;
  o = 0;
  if (name[0] == '/')
    name++;
  else
    while (cwd[n]) {
      FsTmp[n] = cwd[n];
      n++;
    }
  while (name[i] && n < 150) {
    FsTmp[n] = name[i];
    n++;
    i++;
  }
  FsTmp[n] = 0;
  i = 0;
  while (FsTmp[i]) {
    if (FsTmp[i] == '.' && (FsTmp[i + 1] == '/' || !FsTmp[i + 1])) {
      if (FsTmp[i + 1])
        i = i + 2;
      else
        i++;
    } else if (FsTmp[i] == '.' && FsTmp[i + 1] == '.' && (FsTmp[i + 2] == '/' || !FsTmp[i + 2])) {
      if (o > 0) {
        o--;
        while (o > 0 && FsResolveBuf[o - 1] != '/')
          o--;
      }
      if (FsTmp[i + 2])
        i = i + 3;
      else
        i = i + 2;
    } else {
      while (FsTmp[i] && FsTmp[i] != '/' && o < 62) {
        FsResolveBuf[o] = FsTmp[i];
        o++;
        i++;
      }
      if (FsTmp[i] == '/') {
        if (o < 62) {
          FsResolveBuf[o] = '/';
          o++;
        }
        i++;
      }
    }
  }
  FsResolveBuf[o] = 0;
}

U8 *FsSlot(I64 i)
{
  return FsBase() + i *MEMFS_STRIDE;
}

I64 FsSlotUsed(I64 i)
{
  return *(I32 *)(FsSlot(i) + MEMFS_OFF_USED);
}

U0 FsSetUsed(I64 i, I64 v)
{
  *(I32 *)(FsSlot(i) + MEMFS_OFF_USED) = v;
}

U8 *FsName(I64 i)
{
  return FsSlot(i) + MEMFS_OFF_NAME;
}

U8 *FsData(I64 i)
{
  return FsSlot(i) + MEMFS_OFF_DATA;
}

I64 FsLenAt(I64 i)
{
  return *(I32 *)(FsSlot(i) + MEMFS_OFF_LEN);
}

U0 FsSetLen(I64 i, I64 v)
{
  *(I32 *)(FsSlot(i) + MEMFS_OFF_LEN) = v;
}

I64 FsLookup(U8 *full)
{
  I64 i;
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i) && !FsStrCmp(FsName(i), full))
      return i;
  return -1;
}

I64 FsFind(U8 *name)
{
  FsResolve(name);
  return FsLookup(FsResolveBuf);
}

I64 FsCreate(U8 *name)
{
  I64 i, j;
  U8 *dst, *src;
  FsResolve(name);
  i = FsLookup(FsResolveBuf);
  if (i >= 0)
    return i;
  for (i = 0; i < MEMFS_MAX; i++)
    if (!FsSlotUsed(i)) {
      FsSetUsed(i, 1);
      FsSetLen(i, 0);
      dst = FsName(i);
      src = FsResolveBuf;
      j = 0;
      // Walk bytes via pointer bump — FsName(i)[j] used I64 stride under the JIT.
      while (*src && j < 63) {
        *dst = *src;
        dst++;
        src++;
        j++;
      }
      *dst = 0;
      dst = FsData(i);
      *dst = 0;
      return i;
    }
  return -1;
}

I64 Del(U8 *name)
{
  I64 i = FsFind(name);
  U8 *nm;
  if (i < 0) {
    "Del: no such file\n";
    return -1;
  }
  FsSetUsed(i, 0);
  FsSetLen(i, 0);
  nm = FsName(i);
  *nm = 0;
  return 0;
}

I64 FileWrite(U8 *name, U8 *data, I64 len)
{
  I64 i, k;
  U8 *dst, *src;
  i = FsCreate(name);
  if (i < 0) {
    "FileWrite: fs full\n";
    return -1;
  }
  if (len < 0)
    len = 0;
  if (len > MEMFS_CAP - 1)
    len = MEMFS_CAP - 1;
  dst = FsData(i);
  src = data;
  for (k = 0; k < len; k++) {
    *dst = *src;
    dst++;
    src++;
  }
  *dst = 0;
  FsSetLen(i, len);
  return len;
}

U8 *FileRead(U8 *name)
{
  I64 i = FsFind(name);
  if (i < 0)
    return 0;
  return FsData(i);
}

I64 FileCount()
{
  I64 i, n = 0;
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i))
      n++;
  return n;
}

U8 *FileName(I64 idx)
{
  I64 i, k = 0;
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i)) {
      if (k == idx)
        return FsName(i);
      k++;
    }
  return 0;
}

I64 FileSize(I64 idx)
{
  I64 i, k = 0;
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i)) {
      if (k == idx)
        return FsLenAt(i);
      k++;
    }
  return 0;
}

I64 FileLen(U8 *name)
{
  I64 i = FsFind(name);
  if (i < 0)
    return -1;
  return FsLenAt(i);
}

I64 Cd(U8 *name)
{
  U8 *cwd;
  I64 i;
  cwd = FsCwd();
  if (!cwd)
    return -1;
  if (!name || !name[0] || (name[0] == '/' && !name[1])) {
    cwd[0] = 0;
  } else if (name[0] == '.' && name[1] == '.' && (!name[2] || name[2] == '/')) {
    /* pop one directory off cwd (T/ -> empty) */
    i = 0;
    while (cwd[i])
      i++;
    if (i > 0 && cwd[i - 1] == '/')
      i--;
    while (i > 0 && cwd[i - 1] != '/')
      i--;
    cwd[i] = 0;
  } else {
    i = 0;
    while (name[i] && i < 90) {
      FsTmp[i] = name[i];
      i++;
    }
    if (i && FsTmp[i - 1] != '/') {
      FsTmp[i] = '/';
      i++;
    }
    FsTmp[i] = 0;
    FsResolve(FsTmp);
    i = 0;
    while (FsResolveBuf[i] && i < 94) {
      cwd[i] = FsResolveBuf[i];
      i++;
    }
    cwd[i] = 0;
  }
  UartStr("cwd: /");
  UartStr(cwd);
  PutCh('\n');
  return 0;
}

U0 Pwd()
{
  "/%s\n", FsCwd();
}

U8 *CwdStr()
{
  return FsCwd();
}

I64 IsDir(U8 *name)
{
  I64 i, cl;
  i = 0;
  while (name[i] && i < 90) {
    FsTmp[i] = name[i];
    i++;
  }
  if (i && FsTmp[i - 1] != '/') {
    FsTmp[i] = '/';
    i++;
  }
  FsTmp[i] = 0;
  FsResolve(FsTmp);
  cl = FsStrLen(FsResolveBuf);
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i) && !FsStrNCmp(FsName(i), FsResolveBuf, cl))
      return 1;
  return 0;
}

I64 DirMk(U8 *name)
{
  I64 i;
  i = 0;
  while (name[i] && i < 80) {
    FsTmp[i] = name[i];
    i++;
  }
  if (i && FsTmp[i - 1] != '/') {
    FsTmp[i] = '/';
    i++;
  }
  FsTmp[i] = '.';
  FsTmp[i + 1] = 'd';
  FsTmp[i + 2] = 'i';
  FsTmp[i + 3] = 'r';
  FsTmp[i + 4] = 0;
  if (FsCreate(FsTmp) < 0) {
    "DirMk: fs full\n";
    return -1;
  }
  return 0;
}

I64 DirDel(U8 *name)
{
  I64 i, cl, k;
  i = 0;
  while (name[i] && i < 90) {
    FsTmp[i] = name[i];
    i++;
  }
  if (i && FsTmp[i - 1] != '/') {
    FsTmp[i] = '/';
    i++;
  }
  FsTmp[i] = 0;
  FsResolve(FsTmp);
  cl = FsStrLen(FsResolveBuf);
  for (k = 0; k < MEMFS_MAX; k++)
    if (FsSlotUsed(k) && !FsStrNCmp(FsName(k), FsResolveBuf, cl) && FsStrCmp(FsName(k) + cl, ".dir")) {
      "DirDel: not empty\n";
      return -1;
    }
  for (k = 0; k < MEMFS_MAX; k++)
    if (FsSlotUsed(k) && !FsStrNCmp(FsName(k), FsResolveBuf, cl)) {
      FsSetUsed(k, 0);
      FsSetLen(k, 0);
      FsName(k)[0] = 0;
    }
  return 0;
}
