// fs.hc -- HolyC memfs at a fixed physical arena. No 0x87001xxx host slots.
#define MEMFS_BASE   0x85000000
#define MEMFS_MAX    64
#define MEMFS_CAP    65536
#define MEMFS_STRIDE 65608
#define MEMFS_OFF_USED 0
#define MEMFS_OFF_NAME 4
#define MEMFS_OFF_DATA 68
#define MEMFS_OFF_LEN  65604
U8 hc_cwd[96];
U8 FsResolveBuf[64];
U8 FsTmp[160];
U8 *FsBase()
{
  return MEMFS_BASE;
}

U8 *FsCwd()
{
  return hc_cwd;
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

U0 FsInit()
{
  I64 n = MEMFS_MAX *MEMFS_STRIDE;
  MemSet(FsBase(), 0, n);
  hc_cwd[0] = 0;
}
