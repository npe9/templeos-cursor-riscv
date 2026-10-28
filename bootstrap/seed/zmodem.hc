// zmodem.hc -- guest → host file export (ZMODEM sz subset). UART TX is raw UartPut.
// Host: rz -y on the serial PTY, trzsz --zmodem (wraps lrzsz), or tools/uart_recv_zmodem.py.
// Native trzsz (tsz): seed/trzsz.hc — TrzszSend / tools/uart_recv_trzsz.py.
#define ZM_PAD '*'
#define ZM_DLE 0x18
#define ZM_HEX 'B'
#define ZM_BIN 'A'
#define ZM_CRCE 'h'
#define ZM_CRCG 'i'
#define ZM_CRCQ 'j'
#define ZM_CRCW 'k'
#define ZM_ZRQINIT 0
#define ZM_ZRINIT 1
#define ZM_ZACK 3
#define ZM_ZFILE 4
#define ZM_ZSKIP 5
#define ZM_ZFIN 8
#define ZM_ZRPOS 9
#define ZM_ZDATA 10
#define ZM_ZEOF 11
#define ZM_ZCHALLENGE 14
#define ZM_TO 40000000
U16 ZmCrcTab[256];
I64 ZmCrcOk;
I64 ZmType;
I64 ZmH0;
I64 ZmH1;
I64 ZmH2;
I64 ZmH3;
I64 ZmT0;
I64 ZmOpen;
U8 ZmPkt[160];
I64 ZmPn;
U8 ZmPref[64];
U0 ZmCrcInit()
{
  I64 i, j, crc;
  if (ZmCrcOk)
    return;
  for (i = 0; i < 256; i++) {
    crc = i << 8;
    for (j = 0; j < 8; j++) {
      if (crc & 0x8000)
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      else
        crc = (crc << 1) & 0xFFFF;
    }
    ZmCrcTab[i] = crc;
  }
  ZmCrcOk = 1;
}

I64 ZmCrcAdd(I64 crc, I64 b)
{
  I64 idx;
  crc &= 0xFFFF;
  b &= 255;
  idx = (crc >> 8) & 255;
  return (ZmCrcTab[idx] ^ (crc << 8) ^ b) & 0xFFFF;
}

I64 ZmCrcFin(I64 crc)
{
  crc = ZmCrcAdd(crc, 0);
  return ZmCrcAdd(crc, 0);
}

I64 ZmTryGet()
{
  I64 ch, rx, rhp, rtp, cap, rh, rt;
  UartRxDrain();
  rx = *(I64 *)MEM_HOST_SLOTS + 0x20;
  rhp = *(I64 *)MEM_HOST_SLOTS + 0x28;
  rtp = *(I64 *)MEM_HOST_SLOTS + 0x30;
  cap = *(I64 *)MEM_HOST_SLOTS + 0x38;
  if (!rx || !rhp || !rtp || cap < 2)
    return -1;
  rh = *(I64 *)rhp;
  rt = *(I64 *)rtp;
  if (rh == rt)
    return -1;
  ch = *(U8 *)(rx + rt);
  *(I64 *)rtp = (rt + 1) & (cap - 1);
  return ch;
}

I64 ZmWait1()
{
  I64 ch, n;
  n = 0;
  while (1) {
    ch = ZmTryGet();
    if (ch >= 0)
      return ch;
    n++;
    if (GetMTime() - ZmT0 > ZM_TO)
      return -1;
    if (n > 80000000)
      return -1;
  }
  return -1;
}

U0 ZmArm()
{
  ZmT0 = GetMTime();
}

U0 ZmSendLine(I64 c)
{
  c &= 255;
  if (c < 32 || c == 0x7F || (c >= 0x80 && c < 0xA0)) {
    UartPut(ZM_DLE);
    UartPut(c ^ 0x40);
  } else
    UartPut(c);
}

U0 ZmPutHex(I64 n)
{
  I64 d;
  n &= 255;
  d = n >> 4;
  if (d < 10)
    UartPut('0' + d);
  else
    UartPut('a' + d - 10);
  d = n & 15;
  if (d < 10)
    UartPut('0' + d);
  else
    UartPut('a' + d - 10);
}

U0 ZmShhdr(I64 type, I64 a, I64 b, I64 c, I64 d)
{
  I64 crc;
  UartPut(ZM_PAD);
  UartPut(ZM_PAD);
  UartPut(ZM_DLE);
  UartPut(ZM_HEX);
  ZmPutHex(type);
  ZmPutHex(a);
  ZmPutHex(b);
  ZmPutHex(c);
  ZmPutHex(d);
  crc = 0;
  crc = ZmCrcAdd(crc, type);
  crc = ZmCrcAdd(crc, a);
  crc = ZmCrcAdd(crc, b);
  crc = ZmCrcAdd(crc, c);
  crc = ZmCrcAdd(crc, d);
  crc = ZmCrcFin(crc);
  ZmPutHex(crc >> 8);
  ZmPutHex(crc);
  UartPut(13);
  UartPut(10);
  if (type != ZM_ZACK && type != ZM_ZFIN)
    UartPut(0x11);
}

U0 ZmSbhdr(I64 type, I64 a, I64 b, I64 c, I64 d)
{
  I64 crc;
  UartPut(ZM_PAD);
  UartPut(ZM_DLE);
  UartPut(ZM_BIN);
  ZmSendLine(type);
  ZmSendLine(a);
  ZmSendLine(b);
  ZmSendLine(c);
  ZmSendLine(d);
  crc = 0;
  crc = ZmCrcAdd(crc, type);
  crc = ZmCrcAdd(crc, a);
  crc = ZmCrcAdd(crc, b);
  crc = ZmCrcAdd(crc, c);
  crc = ZmCrcAdd(crc, d);
  crc = ZmCrcFin(crc);
  ZmSendLine(crc >> 8);
  ZmSendLine(crc);
}

U0 ZmSdata(U8 *p, I64 n, I64 end)
{
  I64 crc, i, b;
  crc = 0;
  i = 0;
  while (i < n) {
    b = p[i] & 255;
    ZmSendLine(b);
    crc = ZmCrcAdd(crc, b);
    i++;
  }
  UartPut(ZM_DLE);
  UartPut(end);
  crc = ZmCrcAdd(crc, end);
  crc = ZmCrcFin(crc);
  ZmSendLine(crc >> 8);
  ZmSendLine(crc);
}

I64 ZmHexN(I64 c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

I64 ZmHexByte()
{
  I64 a, b;
  a = ZmHexN(ZmWait1());
  b = ZmHexN(ZmWait1());
  if (a < 0 || b < 0)
    return -1;
  return (a << 4) | b;
}

U0 ZmPktAdd(I64 c)
{
  if (ZmPn < 158) {
    ZmPkt[ZmPn] = c;
    ZmPn++;
  }
}

U0 ZmPktDec(I64 n)
{
  U8 b[16];
  I64 i;
  if (n <= 0) {
    ZmPktAdd('0');
    return;
  }
  i = 0;
  while (n && i < 15) {
    b[i] = '0' + n % 10;
    i++;
    n = n / 10;
  }
  while (i) {
    i--;
    ZmPktAdd(b[i]);
  }
}

I64 ZmUnesc()
{
  I64 c;
  c = ZmWait1();
  if (c < 0)
    return -1;
  if (c != ZM_DLE)
    return c;
  c = ZmWait1();
  if (c < 0)
    return -1;
  if (c == ZM_CRCE || c == ZM_CRCG || c == ZM_CRCQ || c == ZM_CRCW)
    return c | 0x100;
  return (c ^ 0x40) & 255;
}

I64 ZmHdrCrc(I64 type)
{
  I64 crc;
  crc = 0;
  crc = ZmCrcAdd(crc, type);
  crc = ZmCrcAdd(crc, ZmH0);
  crc = ZmCrcAdd(crc, ZmH1);
  crc = ZmCrcAdd(crc, ZmH2);
  crc = ZmCrcAdd(crc, ZmH3);
  return ZmCrcFin(crc);
}

I64 ZmGetHdr()
{
  I64 c, n, type, got;
  ZmArm();
  n = 0;
  while (1) {
    c = ZmWait1();
    if (c < 0)
      return -1;
    if (c == 17 || c == 19)
      continue;
    if (c != ZM_PAD)
      continue;
    while (1) {
      c = ZmWait1();
      if (c < 0)
        return -1;
      if (c != ZM_PAD)
        break;
    }
    if (c != ZM_DLE)
      continue;
    c = ZmWait1();
    if (c < 0)
      return -1;
    if (c == ZM_HEX) {
      type = ZmHexByte();
      ZmH0 = ZmHexByte();
      ZmH1 = ZmHexByte();
      ZmH2 = ZmHexByte();
      ZmH3 = ZmHexByte();
      got = ZmHexByte();
      c = ZmHexByte();
      if (type < 0 || ZmH0 < 0 || ZmH1 < 0 || ZmH2 < 0 || ZmH3 < 0 || got < 0 || c < 0)
        return -1;
      got = (got << 8) | c;
      if (ZmHdrCrc(type) != got)
        continue;
      ZmType = type;
      return type;
    }
    if (c == ZM_BIN) {
      type = ZmUnesc();
      ZmH0 = ZmUnesc();
      ZmH1 = ZmUnesc();
      ZmH2 = ZmUnesc();
      ZmH3 = ZmUnesc();
      got = ZmUnesc();
      c = ZmUnesc();
      if (type < 0 || type > 255 || ZmH0 < 0 || ZmH1 < 0 || ZmH2 < 0 || ZmH3 < 0 || got < 0 || c < 0)
        return -1;
      got = ((got & 255) << 8) | (c & 255);
      if (ZmHdrCrc(type) != got)
        continue;
      ZmType = type;
      return type;
    }
    n++;
    if (n > 8)
      return -1;
  }
  return -1;
}
I64 ZmFcSaved;
I64 ZmodemBegin()
{
  I64 t;
  ZmFcSaved = UartFcGet();
  UartXonXoff(0);
  UartPut(0x11);
  /* XON — unblock host chardev before binary session */
  /* binary: XON/XOFF are protocol bytes */
  ZmCrcInit();
  ZmShhdr(ZM_ZRQINIT, 0, 0, 0, 0);
  while (1) {
    t = ZmGetHdr();
    if (t == ZM_ZRINIT) {
      ZmOpen = 1;
      return 1;
    }
    if (t == ZM_ZCHALLENGE) {
      ZmShhdr(ZM_ZACK, ZmH0, ZmH1, ZmH2, ZmH3);
      continue;
    }
    if (t < 0) {
      UartXonXoff(ZmFcSaved);
      UartStr("Zmodem: no rz (start host rz / uart_recv_zmodem.py)\n");
      ZmOpen = 0;
      return 0;
    }
  }
  UartXonXoff(ZmFcSaved);
  return 0;
}

U0 ZmodemEnd()
{
  I64 t;
  if (!ZmOpen)
    return;
  ZmShhdr(ZM_ZFIN, 0, 0, 0, 0);
  t = ZmGetHdr();
  if (t)
    t = 0;
  UartPut('O');
  UartPut('O');
  ZmOpen = 0;
  UartXonXoff(ZmFcSaved);
}

I64 ZmIsDotDir(U8 *nm)
{
  I64 n;
  if (!nm)
    return 1;
  n = FsStrLen(nm);
  if (n >= 4 && nm[n - 4] == '.' && nm[n - 3] == 'd' && nm[n - 2] == 'i' && nm[n - 1] == 'r')
    return 1;
  return 0;
}

I64 ZmodemSendFile(U8 *name)
{
  U8 *d, *nm, *s;
  I64 n, t, i;
  if (!ZmOpen)
    return -1;
  d = FileRead(name);
  n = FileLen(name);
  if (!d || n < 0)
    return -1;
  nm = name;
  i = FsFind(name);
  if (i >= 0)
    nm = FsName(i);
  if (nm[0] == '/')
    nm++;
  ZmShhdr(ZM_ZFILE, 0, 0, 0, 1);
  ZmPn = 0;
  s = nm;
  while (*s) {
    ZmPktAdd (*s);
    s++;
  }
  ZmPktAdd(0);
  ZmPktDec(n);
  ZmPktAdd(0);
  ZmSdata(ZmPkt, ZmPn, ZM_CRCW);
  t = ZmGetHdr();
  if (t == ZM_ZSKIP)
    return 0;
  if (t != ZM_ZRPOS && t != ZM_ZACK && t != ZM_ZRINIT)
    return -1;
  ZmSbhdr(ZM_ZDATA, 0, 0, 0, 0);
  ZmSdata(d, n, ZM_CRCE);
  ZmShhdr(ZM_ZEOF, n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255);
  t = ZmGetHdr();
  if (t != ZM_ZRINIT && t != ZM_ZACK)
    return -1;
  return n;
}
// ZmodemSend -- ZmodemSend("file")
// NAME
//   ZmodemSend - export a memfs file with ZMODEM (sz) over UART
// SYNOPSIS
//   U0 ZmodemSend(U8 *name);
// DESCRIPTION
//   Speaks a minimal sz subset (ZRQINIT, ZFILE, ZDATA, ZEOF, ZFIN) so host
//   `rz -y` or `trzsz --zmodem` can receive. TX is raw UartPut (no CRLF
//   mangling). Needs a receiver on the serial PTY within a few seconds.
// EXAMPLES
//   ZmodemSend("boot.hc");
//   ZmodemSend("Tutorials/A01_RV64I.hc");
// SEE ALSO
//   TrzszSend  ZmodemSendDir  ZmodemSendChanges  DumpFile  FsChanges
// BUGS
//   Handshake-only (not a unidirectional dump). Times out if no rz.
U0 ZmodemSend(U8 *name)
{
  if (FileLen(name) < 0) {
    UartStr("Zmodem: no such file: ");
    if (name)
      UartStr(name);
    PutCh('\n');
    return;
  }
  if (!ZmodemBegin())
    return;
  ZmodemSendFile(name);
  ZmodemEnd();
}

I64 ZmPrefOk(U8 *nm, U8 *pref, I64 pl)
{
  I64 i;
  if (!nm || pl <= 0)
    return 0;
  for (i = 0; i < pl; i++)
    if (nm[i] != pref[i])
      return 0;
  return 1;
}
// ZmodemSendDir -- ZmodemSendDir("Tutorials")
// NAME
//   ZmodemSendDir - ZMODEM-send every memfs file under a directory prefix
// SYNOPSIS
//   U0 ZmodemSendDir(U8 *name);
// DESCRIPTION
//   One ZMODEM session, one ZFILE per slot whose name is under the resolved
//   prefix (hierarchical memfs: Tutorials/, Lib/, …). Skips .dir markers.
// EXAMPLES
//   ZmodemSendDir("Tutorials");
//   ZmodemSendDir("Tmp");
// SEE ALSO
//   ZmodemSend  ExportFs  ZmodemSendChanges
U0 ZmodemSendDir(U8 *name)
{
  I64 i, n, pl, k;
  U8 *nm;
  if (!name)
    return;
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
  pl = FsStrLen(FsResolveBuf);
  if (!pl) {
    UartStr("ZmodemSendDir: empty prefix\n");
    return;
  }
  i = 0;
  while (i < pl && i < 63) {
    ZmPref[i] = FsResolveBuf[i];
    i++;
  }
  ZmPref[i] = 0;
  if (!ZmodemBegin())
    return;
  n = FileCount();
  k = 0;
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    if (!nm || ZmIsDotDir(nm))
      continue;
    if (!ZmPrefOk(nm, ZmPref, pl))
      continue;
    if (ZmodemSendFile(nm) >= 0)
      k++;
  }
  ZmodemEnd();
  "zmodem dir %s (%d files)\n", name, k;
}
// ExportFs -- ExportFs("path")
// Native trzsz: TrzszSend / TrzszSendDir / TrzszSendChanges in trzsz.hc.
// NAME
//   ExportFs - ZMODEM-send a file or a whole memfs directory
// SYNOPSIS
//   U0 ExportFs(U8 *path);
// DESCRIPTION
//   IsDir(path) → ZmodemSendDir, else ZmodemSend. Unified export entry.
// EXAMPLES
//   ExportFs("boot.hc");
//   ExportFs("Tutorials");
// SEE ALSO
//   ZmodemSend  ZmodemSendDir  FsChanges
U0 ExportFs(U8 *path)
{
  if (!path) {
    UartStr("ExportFs: need a path\n");
    return;
  }
  if (IsDir(path))
    ZmodemSendDir(path);
  else
    ZmodemSend(path);
}
// ZmodemSendChanges -- ZmodemSendChanges()
// NAME
//   ZmodemSendChanges - ZMODEM-send memfs files dirtied this session
// SYNOPSIS
//   U0 ZmodemSendChanges();
// DESCRIPTION
//   After FsEpochSeal (runs at end of boot), FileWrite/Del set dirty bits
//   and append journal records. Sends still-existing dirty files in one
//   session. Deleted names are listed by FsChanges but cannot be sent.
// EXAMPLES
//   FsChanges;
//   ZmodemSendChanges;
// SEE ALSO
//   FsChanges  FsDiff  DumpChanges  ZmodemSend
U0 ZmodemSendChanges()
{
  I64 i, k, n;
  U8 *nm;
  k = 0;
  for (i = 0; i < MEMFS_MAX; i++) {
    if (!FsSlotUsed(i) || !FsIsDirty(i))
      continue;
    nm = FsName(i);
    if (ZmIsDotDir(nm))
      continue;
    k++;
  }
  if (!k) {
    UartStr("ZmodemSendChanges: no dirty files\n");
    return;
  }
  if (!ZmodemBegin())
    return;
  n = 0;
  for (i = 0; i < MEMFS_MAX; i++) {
    if (!FsSlotUsed(i) || !FsIsDirty(i))
      continue;
    nm = FsName(i);
    if (ZmIsDotDir(nm))
      continue;
    if (ZmodemSendFile(nm) >= 0)
      n++;
  }
  ZmodemEnd();
  "zmodem changes (%d files)\n", n;
}

U0 SendChanges()
{
  ZmodemSendChanges();
}
// DumpChanges -- DumpChanges(since_epoch)
// NAME
//   DumpChanges - UART manifest of the dirty set, then DumpFile each body
// SYNOPSIS
//   U0 DumpChanges(I64 since_epoch=-1);
// DESCRIPTION
//   Emits $$HC_CHANGES epoch=A..B count=N dumps=M$$, one line per collapsed
//   path (same set as FsChanges), $$HC_END$$, then DumpFile for each still-
//   existing non-quiet file. Deleted / dir ops stay in the manifest only.
//   Host: tools/uart_recv_dump.py --keep-path (reuses $$HC_DUMP$$ frames).
// EXAMPLES
//   FileWrite("Home/t.hc", "x", 1);
//   DumpChanges;
// SEE ALSO
//   FsChanges  DumpFile  ZmodemSendChanges  FsCheckpoint
U0 DumpChanges(I64 since_epoch = -1)
{
  I64 n, i, op, dumps, since_lo;
  U8 *path, *path2;
  if (since_epoch < -1)
    since_epoch = -1;
  n = FsChangeCollect(since_epoch, 0, -1);
  dumps = 0;
  i = 0;
  while (i < n) {
    if (FsChangeCanDump(i))
      dumps++;
    i++;
  }
  if (since_epoch < 0)
    since_lo = 0;
  else
    since_lo = since_epoch;
  "$$HC_CHANGES epoch=%d..%d count=%d dumps=%d$$\n", since_lo, FsEpoch(), n, dumps;
  i = 0;
  while (i < n) {
    op = FsChangeOp(i);
    path = FsChangePath(i);
    path2 = FsChangePath2(i);
    if (op == FS_OP_RENAME && *path2)
      "  %c  %s -> %s\n", FsOpChar(op), path, path2;
    else
      "  %c  %s\n", FsOpChar(op), path;
    i++;
  }
  "$$HC_END$$\n";
  i = 0;
  while (i < n) {
    if (FsChangeCanDump(i)) {
      op = FsChangeOp(i);
      if (op == FS_OP_RENAME)
        path = FsChangePath2(i);
      else
        path = FsChangePath(i);
      DumpFile(path);
    }
    i++;
  }
}

I64 ZmCrc16(U8 *p, I64 n)
{
  I64 crc, i;
  ZmCrcInit();
  crc = 0;
  i = 0;
  while (i < n) {
    crc = ZmCrcAdd(crc, p[i]);
    i++;
  }
  return ZmCrcFin(crc);
}
