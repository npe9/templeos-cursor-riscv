// fs.hc -- HolyC-owned memfs at a fixed physical arena (no 0x87001xxx base/cwd slots).
// Layout matches C MemFile / EdC bridge: used I32 @0, name[64] @4, data[65536] @68,
// len I32 @65604, stride 65608. C seed boot + EdC write the same arena at MEMFS_BASE.
// Below QEMU virt's default 128MiB (ends 0x88000000): after host slots, before MEM_STACK.
// Do not use 0x85000000 (overlaps C heap_mem BSS) or 0x88000000 (needs -m >128M).
// MEMFS_MAX=96: hierarchical seeds (~70 files + .dir markers) + editor spill.
// Tree: /Home /Tmp /Boot /Lib /Apps /Asm /Doc /Doc/Datasheet /Tutorials
// Bare names (print.hc, A01_RV64I.hc) still resolve via unique-basename fallback.
#define MEMFS_BASE   0x87800000
#define MEMFS_MAX    96
#define MEMFS_CAP    65536
#define MEMFS_STRIDE 65608
#define MEMFS_OFF_USED 0
#define MEMFS_OFF_NAME 4
#define MEMFS_OFF_DATA 68
#define MEMFS_OFF_LEN  65604
#define MEMFS_CWD    (MEMFS_BASE+MEMFS_MAX*MEMFS_STRIDE)
#define FS_META_TRACK 96
#define FS_META_DIRTY 104
#define FS_DEL_MAX    32
#define FS_DELNM_OFF  200
#define FS_SNAPSZ_OFF 2248
#define FS_SNAPNM_OFF 2632
#define FS_SNAPHASH_OFF 8776
// Side ring of fixed records after snap+hash tables, still < MEM_STACK (0x87F00000).
// Bodies at MEMFS_CWD+FS_LOG_OFF; the cursor (seq/epoch/head/count) lives in HolyC
// globals AND is mirrored into the FS_LOG_HDR_OFF block below, so an external
// debugger can read the journal without symbols. FsLogHdrSync() keeps them in step.
// hc_repl/fs.hc FsInit() zeroes cwd..FS_LOG_OFF at boot; keep the two in sync.
#define FS_LOG_OFF    9216
#define FS_LOG_REC    144
#define FS_LOG_MAX    512
// Collapsed dirty-set (paths+ops) sits after the ring; still < MEM_STACK.
// JTAG/OpenOCD-readable journal header. The ring bytes were always in memory, but
// the cursor was not, so a halted-core dump found 512 fixed-size records with no way
// to tell which were valid, where the write cursor sat, or which epoch they belonged
// to. This 64-byte block is self-describing: find the magic and it names the ring's
// address, stride, capacity and live extent. Placed past the dirty-set tables, which
// end at FsChBase()+MEMFS_MAX*140 (= FS_LOG_OFF+FS_LOG_MAX*FS_LOG_REC+13440 = 96384).
// Absolute on QEMU virt: MEMFS_CWD 0x87E01B00 + 0x18000 = 0x87E19B00.
#define FS_LOG_HDR_OFF  98304
#define FS_LOG_HDR_SIZE 64
#define FS_LOG_HDR_VER  1
#define FS_FNV_OFF    0x811C9DC5
#define FS_FNV_PRIME  0x01000193
#define FS_EPOCH_BOOT 0
#define FS_OP_CREATE  1
#define FS_OP_WRITE   2
#define FS_OP_UNLINK  3
#define FS_OP_RENAME  4
#define FS_OP_TRUNC   5
#define FS_OP_DIRMK   6
#define FS_OP_DIRDEL  7
#define FS_OP_EPOCH   8
#define FS_OP_WRAP    9
#define FS_FLAG_QUIET 1
#define FS_CH_ALL     1
U8 FsResolveBuf[64];
U8 FsTmp[160];
U8 FsPath2[64];
U8 FsEmpty[2];
I64 FsDelN;
I64 FsSnapN;
I64 FsLogSeq;
I64 FsLogEpochId;
I64 FsLogHead;
I64 FsLogCount;
I64 FsLogGen;
I64 FsLogReady;
I64 FsChN;
I64 FsChBusy;
U8 FsFrom[64];
U8 FsTo[64];
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
    if (a[i] == 0)
      return 0;
  }
  return 0;
}
// Resolve name into FsResolveBuf (cwd-relative, fold . / ..).
// Accepts TempleOS prefixes (`::/`, `A:`…`Z:`, `~/`) as memfs absolute — dual-namespace
// bridge so UART Cd/FileFind match BlkDev/`::` muscle memory (see docs/PATHS.md).
U0 FsResolve(U8 *name)
{
  U8 *cwd;
  I64 n, i, o, abs;
  if (!name)
    name = "";
  /* Snapshot: Cd/FileFind often pass FsTmp; we rebuild into FsTmp below. */
  if (name != FsPath2) {
    i = 0;
    while (name[i] && i < 62) {
      FsPath2[i] = name[i];
      i++;
    }
    FsPath2[i] = 0;
    name = FsPath2;
  }
  abs = 0;
  if (name[0] == ':' && name[1] == ':') {
    name = name + 2;
    abs = 1;
  } else if (name[0] && name[1] == ':' && ((name[0] >= 'A' && name[0] <= 'Z') || (name[0] >= 'a' && name[0] <= 'z'))) {
    name = name + 2;
    abs = 1;
  } else if (name[0] == '~' && (!name[1] || name[1] == '/')) {
    if (name[1] == '/')
      name = name + 2;
    else
      name = name + 1;
    /* Rewrite snapshot as Home/… then treat absolute. */
    n = 0;
    FsTmp[n] = 'H';
    n++;
    FsTmp[n] = 'o';
    n++;
    FsTmp[n] = 'm';
    n++;
    FsTmp[n] = 'e';
    n++;
    FsTmp[n] = '/';
    n++;
    if (*name) {
      i = 0;
      while (name[i] && n < 62) {
        FsTmp[n] = name[i];
        n++;
        i++;
      }
    }
    FsTmp[n] = 0;
    i = 0;
    while (FsTmp[i] && i < 62) {
      FsPath2[i] = FsTmp[i];
      i++;
    }
    FsPath2[i] = 0;
    name = FsPath2;
    abs = 1;
  } else if (name[0] == ':' && (name[1] == '/' || !name[1])) {
    name = name + 1;
    abs = 1;
  }
  cwd = FsCwd();
  if (!cwd)
    cwd = "";
  n = 0;
  i = 0;
  o = 0;
  if (abs || name[0] == '/') {
    if (name[0] == '/')
      name++;
  } else
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

I64 FsTracking()
{
  return *(I64 *)(FsCwd() + FS_META_TRACK);
}

U0 FsSetTracking(I64 v)
{
  *(I64 *)(FsCwd() + FS_META_TRACK) = v;
}

I64 FsIsDirty(I64 slot)
{
  U8 *p;
  if (slot < 0)
    return 0;
  if (slot >= MEMFS_MAX)
    return 0;
  p = FsCwd() + FS_META_DIRTY + slot;
  return *p;
}

U0 FsSetDirty(I64 slot, I64 v)
{
  U8 *p;
  if (slot < 0)
    return;
  if (slot >= MEMFS_MAX)
    return;
  p = FsCwd() + FS_META_DIRTY + slot;
  *p = v;
}

U8 *FsDelAt(I64 i)
{
  return FsCwd() + FS_DELNM_OFF + i * 64;
}

U8 *FsSnapAt(I64 i)
{
  return FsCwd() + FS_SNAPNM_OFF + i * 64;
}

I32 *FsSnapSzP(I64 i)
{
  return (I32 *)(FsCwd() + FS_SNAPSZ_OFF + i * 4);
}

I32 *FsSnapHashP(I64 i)
{
  return (I32 *)(FsCwd() + FS_SNAPHASH_OFF + i * 4);
}

I64 FsHashBuf(U8 *p, I64 n)
{
  I64 h, i;
  h = FS_FNV_OFF;
  if (!p)
    return h;
  if (n < 0)
    n = 0;
  i = 0;
  while (i < n) {
    h = h ^ (*p & 0xFF);
    h = h *FS_FNV_PRIME;
    h = h & 0xFFFFFFFF;
    p++;
    i++;
  }
  return h;
}

U8 *FsLogBase()
{
  return FsCwd() + FS_LOG_OFF;
}

U8 *FsLogRec(I64 i)
{
  return FsLogBase() + i *FS_LOG_REC;
}

U8 *FsChBase()
{
  return FsLogBase() + FS_LOG_MAX *FS_LOG_REC;
}

U8 *FsLogHdrBase()
{
  return FsCwd() + FS_LOG_HDR_OFF;
}

U8 *FsChPathAt(I64 i)
{
  return FsChBase() + i * 64;
}

U8 *FsChPath2At(I64 i)
{
  return FsChBase() + MEMFS_MAX * 64 + i * 64;
}

U8 *FsChOpP(I64 i)
{
  return FsChBase() + MEMFS_MAX * 128 + i;
}

U8 *FsChFlgP(I64 i)
{
  return FsChBase() + MEMFS_MAX * 128 + MEMFS_MAX + i;
}

I32 *FsChSzP(I64 i)
{
  return (I32 *)(FsChBase() + MEMFS_MAX * 130 + i * 4);
}

// U32, not I32: this holds an FNV-1a hash, so a hash with bit 31 set must zero-extend.
// As I32 the (correct, 4-byte) signed load reported 0xE36FA7C0 as 0xFFFFFFFFE36FA7C0.
U32 *FsChHashP(I64 i)
{
  return (U32 *)(FsChBase() + MEMFS_MAX * 134 + i * 4);
}

U8 *FsChEpP(I64 i)
{
  return FsChBase() + MEMFS_MAX * 138 + i * 2;
}

U0 FsLogCopyPath(U8 *d, U8 *s)
{
  I64 n;
  if (!d)
    return;
  n = 0;
  if (!s) {
    *d = 0;
    return;
  }
  while (*s && n < 63) {
    *d = *s;
    d++;
    s++;
    n++;
  }
  *d = 0;
}

U0 FsLogStoreU32(U8 *p, I64 v)
{
  *p = v & 0xFF;
  p++;
  *p = (v >> 8) & 0xFF;
  p++;
  *p = (v >> 16) & 0xFF;
  p++;
  *p = (v >> 24) & 0xFF;
}

I64 FsLogLoadU32(U8 *p)
{
  I64 v;
  v = *p;
  p++;
  v = v | (*p << 8);
  p++;
  v = v | (*p << 16);
  p++;
  v = v | (*p << 24);
  return v;
}

U0 FsLogStoreU16(U8 *p, I64 v)
{
  *p = v & 0xFF;
  p++;
  *p = (v >> 8) & 0xFF;
}

I64 FsLogLoadU16(U8 *p)
{
  I64 v;
  v = *p;
  p++;
  v = v | (*p << 8);
  return v;
}

// Mirror the journal cursor into the JTAG-readable header. Every field an external
// reader needs is here, so the OpenOCD recipe is one address and no symbols:
//   +0  magic "TOSFSLOG"   +8  version      +12 hdr_size    +16 rec_size
//   +20 rec_max            +24 head         +28 count       +32 seq
//   +36 epoch              +40 chrono_start +44 gen         +48 ring_addr (lo,hi)
//   +56 self_addr (lo,hi)  -- this block's own address, so a reader that found the
//                             magic by scanning can recover the dump's base address
//                             and locate the ring without assuming any layout.
//                             ring_bytes is rec_size*rec_max; not stored.
// Records run chronologically from chrono_start, wrapping mod rec_max, for count
// records. All fields little-endian u32 (ring_addr is a u32 pair) to match the
// record encoding FsLogStoreU32 already uses.
U0 FsLogHdrSync()
{
  U8 *h, *p, *rp;
  I64 ring, start, self;
  h = FsLogHdrBase();
  p = h;
  *p = 'T';
  p++;
  *p = 'O';
  p++;
  *p = 'S';
  p++;
  *p = 'F';
  p++;
  *p = 'S';
  p++;
  *p = 'L';
  p++;
  *p = 'O';
  p++;
  *p = 'G';
  rp = FsLogBase();
  ring = rp(I64);
  // Oldest live record: the ring only wraps after FsLogCompact, but keep the same
  // rule FsLogChronoIdx uses so a reader never has to know which happened.
  if (FsLogCount < FS_LOG_MAX)
    start = 0;
  else
    start = FsLogHead;
  FsLogStoreU32(h + 8, FS_LOG_HDR_VER);
  FsLogStoreU32(h + 12, FS_LOG_HDR_SIZE);
  FsLogStoreU32(h + 16, FS_LOG_REC);
  FsLogStoreU32(h + 20, FS_LOG_MAX);
  FsLogStoreU32(h + 24, FsLogHead);
  FsLogStoreU32(h + 28, FsLogCount);
  FsLogStoreU32(h + 32, FsLogSeq);
  FsLogStoreU32(h + 36, FsLogEpochId);
  FsLogStoreU32(h + 40, start);
  FsLogStoreU32(h + 44, FsLogGen);
  FsLogStoreU32(h + 48, ring & 0xFFFFFFFF);
  FsLogStoreU32(h + 52, ring >> 32);
  self = h(I64);
  FsLogStoreU32(h + 56, self & 0xFFFFFFFF);
  FsLogStoreU32(h + 60, self >> 32);
}

U0 FsLogPut(I64 op, U8 *path, U8 *path2, I64 size, I64 flags, I64 hash, I64 epoch)
{
  U8 *r, *p;
  if (!path)
    path = FsEmpty;
  if (!path2)
    path2 = FsEmpty;
  r = FsLogRec(FsLogHead);
  FsLogStoreU32(r, FsLogSeq);
  p = r + 4;
  FsLogStoreU16(p, epoch);
  p = r + 6;
  *p = op;
  p = r + 7;
  *p = flags;
  p = r + 8;
  FsLogStoreU32(p, size);
  p = r + 12;
  FsLogStoreU32(p, hash);
  FsLogCopyPath(r + 16, path);
  FsLogCopyPath(r + 80, path2);
  FsLogSeq++;
  FsLogHead++;
  if (FsLogHead >= FS_LOG_MAX)
    FsLogHead = 0;
  if (FsLogCount < FS_LOG_MAX)
    FsLogCount++;
  // Single sync point: this is the only place seq/head/count move, and every epoch
  // change ends in a FS_OP_EPOCH record, so the header is never staler than the ring.
  FsLogHdrSync();
}

I64 FsLogChronoIdx(I64 age)
{
  I64 start;
  if (age < 0 || age >= FsLogCount)
    return -1;
  if (FsLogCount < FS_LOG_MAX)
    start = 0;
  else
    start = FsLogHead;
  return (start + age) % FS_LOG_MAX;
}

I64 FsChHit(I64 n, U8 *path)
{
  I64 i;
  U8 *p2;
  if (!path)
    return 0;
  if (*path == 0)
    return 0;
  for (i = 0; i < n; i++) {
    if (!FsStrCmp(FsChPathAt(i), path))
      return 1;
    p2 = FsChPath2At(i);
    if (*p2 && !FsStrCmp(p2, path))
      return 1;
  }
  return 0;
}

I64 FsChangeOp(I64 i)
{
  U8 *p;
  if (i < 0 || i >= FsChN)
    return 0;
  p = FsChOpP(i);
  return *p;
}

U8 *FsChangePath(I64 i)
{
  if (i < 0 || i >= FsChN)
    return FsEmpty;
  return FsChPathAt(i);
}

U8 *FsChangePath2(I64 i)
{
  if (i < 0 || i >= FsChN)
    return FsEmpty;
  return FsChPath2At(i);
}

I64 FsChangeSize(I64 i)
{
  if (i < 0 || i >= FsChN)
    return 0;
  return *FsChSzP(i);
}

I64 FsChangeHash(I64 i)
{
  if (i < 0 || i >= FsChN)
    return 0;
  return *FsChHashP(i);
}

I64 FsChangeEpochOf(I64 i)
{
  if (i < 0 || i >= FsChN)
    return 0;
  return FsLogLoadU16(FsChEpP(i));
}

I64 FsChangeFlagsOf(I64 i)
{
  U8 *p;
  if (i < 0 || i >= FsChN)
    return 0;
  p = FsChFlgP(i);
  return *p;
}

I64 FsChangeCollect(I64 since_epoch, I64 flags, I64 until_epoch)
{
  I64 age, idx, n, op, ep, show_q;
  U8 *r, *path, *path2, *p;
  n = 0;
  FsChN = 0;
  if (since_epoch < -1)
    since_epoch = -1;
  if (!FsLogReady)
    return 0;
  show_q = flags & FS_CH_ALL;
  age = FsLogCount - 1;
  while (age >= 0) {
    idx = FsLogChronoIdx(age);
    age--;
    if (idx < 0)
      continue;
    r = FsLogRec(idx);
    p = r + 6;
    op = *p;
    if (op == FS_OP_EPOCH || op == FS_OP_WRAP)
      continue;
    ep = FsLogLoadU16(r + 4);
    if (since_epoch >= 0 && ep <= since_epoch)
      continue;
    if (until_epoch >= 0 && ep > until_epoch)
      continue;
    p = r + 7;
    if (!show_q && (*p & FS_FLAG_QUIET))
      continue;
    path = r + 16;
    if (*path == 0)
      continue;
    path2 = r + 80;
    if (FsChHit(n, path))
      continue;
    if (op == FS_OP_RENAME && FsChHit(n, path2))
      continue;
    if (n >= MEMFS_MAX)
      break;
    FsLogCopyPath(FsChPathAt(n), path);
    FsLogCopyPath(FsChPath2At(n), path2);
    p = FsChOpP(n);
    *p = op;
    p = FsChFlgP(n);
    p[0] = r[7];
    *FsChSzP(n) = FsLogLoadU32(r + 8);
    *FsChHashP(n) = FsLogLoadU32(r + 12);
    FsLogStoreU16(FsChEpP(n), ep);
    n++;
  }
  FsChN = n;
  return n;
}

I64 FsChangeCount(I64 since_epoch = -1, I64 flags = 0)
{
  return FsChangeCollect(since_epoch, flags, -1);
}

U0 FsLogCompact()
{
  I64 n, i, save_track;
  n = FsChangeCollect(-1, FS_CH_ALL, -1);
  save_track = FsTracking();
  FsChBusy = 1;
  FsLogHead = 0;
  FsLogCount = 0;
  FsLogGen++;
  FsSetTracking(1);
  FsLogReady = 1;
  FsLogPut(FS_OP_WRAP, FsEmpty, FsEmpty, n, 0, 0, FsLogEpochId);
  i = 0;
  while (i < n) {
    FsLogPut(FsChangeOp(i), FsChangePath(i), FsChangePath2(i), FsChangeSize(i), FsChangeFlagsOf(i), FsChangeHash(i), FsChangeEpochOf(i));
    i++;
  }
  FsChBusy = 0;
  FsSetTracking(save_track);
}

U0 FsJournal(I64 op, U8 *path, U8 *path2, I64 size, I64 flags, I64 hash)
{
  if (!FsTracking())
    return;
  if (!FsLogReady)
    return;
  if (!FsChBusy && FsLogCount >= FS_LOG_MAX)
    FsLogCompact();
  FsLogPut(op, path, path2, size, flags, hash, FsLogEpochId);
}

I64 FsEpoch()
{
  return FsLogEpochId;
}

I64 FsSeq()
{
  if (FsLogSeq <= 1)
    return 0;
  return FsLogSeq - 1;
}

U8 FsOpChar(I64 op)
{
  if (op == FS_OP_CREATE)
    return 'C';
  if (op == FS_OP_WRITE)
    return 'W';
  if (op == FS_OP_UNLINK)
    return 'D';
  if (op == FS_OP_RENAME)
    return 'R';
  if (op == FS_OP_TRUNC)
    return 'T';
  if (op == FS_OP_DIRMK)
    return 'K';
  if (op == FS_OP_DIRDEL)
    return 'X';
  if (op == FS_OP_EPOCH)
    return 'E';
  if (op == FS_OP_WRAP)
    return '@';
  return '?';
}

I64 FsAllocSlot()
{
  I64 i, j;
  U8 *dst, *src;
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

U0 FsDelDrop(U8 *name)
{
  I64 i, j;
  U8 *s;
  if (!name)
    return;
  i = 0;
  while (i < FsDelN) {
    s = FsDelAt(i);
    if (!FsStrCmp(s, name)) {
      j = i + 1;
      while (j < FsDelN) {
        FsStrCpy(FsDelAt(j - 1), FsDelAt(j));
        j++;
      }
      FsDelN--;
      return;
    }
    i++;
  }
}

U0 FsOnWrite(I64 slot)
{
  if (!FsTracking())
    return;
  FsSetDirty(slot, 1);
  if (slot >= 0)
    FsDelDrop(FsName(slot));
}

U0 FsOnDel(U8 *name)
{
  U8 *d;
  I64 n;
  if (!FsTracking())
    return;
  if (!name)
    return;
  if (*name == 0)
    return;
  if (FsDelN >= FS_DEL_MAX)
    return;
  d = FsDelAt(FsDelN);
  n = 0;
  while (name[n] && n < 63) {
    d[n] = name[n];
    n++;
  }
  d[n] = 0;
  FsDelN++;
}

I64 FsLookup(U8 *full)
{
  I64 i;
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i) && !FsStrCmp(FsName(i), full))
      return i;
  return -1;
}

U8 *FsBaseName(U8 *s)
{
  U8 *b;
  if (!s)
    return "";
  b = s;
  while (*s) {
    if (*s == '/')
      b = s + 1;
    s++;
  }
  return b;
}

I64 FsQuietPath(U8 *path)
{
  U8 *b;
  I64 n;
  if (!path)
    return 0;
  b = FsBaseName(path);
  if (*b == '.')
    return 1;
  n = FsStrLen(b);
  if (n < 6)
    return 0;
  b = b + n - 6;
  if (b[0] == '.' && b[1] == 's' && b[2] == 'p' && b[3] == 'i' && b[4] == 'l' && b[5] == 'l')
    return 1;
  return 0;
}

I64 FsQuietFlag(U8 *path)
{
  if (FsQuietPath(path))
    return FS_FLAG_QUIET;
  return 0;
}

I64 FsLookupBase(U8 *full)
{
  I64 i, hit;
  U8 *want, *b;
  want = FsBaseName(full);
  if (!want)
    return -1;
  // *p, not !p[0]: unary-not of a local-pointer index overwrites saved ra
  // (SP+=8 then sd onto the frame) and ret jumps to pc 0x20..0xFF.
  if (*want == 0)
    return -1;
  if (*want == '.')
    return -1;
  hit = -1;
  i = 0;
  while (i < MEMFS_MAX) {
    if (FsSlotUsed(i)) {
      b = FsName(i);
      b = FsBaseName(b);
      if (*b != '.') {
        if (!FsStrCmp(b, want)) {
          if (hit >= 0)
            return hit;
          hit = i;
        }
      }
    }
    i++;
  }
  return hit;
}

I64 FsFind(U8 *name)
{
  I64 i;
  FsResolve(name);
  i = FsLookup(FsResolveBuf);
  if (i >= 0)
    return i;
  return FsLookupBase(FsResolveBuf);
}

I64 FsCreate(U8 *name)
{
  I64 i;
  FsResolve(name);
  i = FsLookup(FsResolveBuf);
  if (i < 0)
    i = FsLookupBase(FsResolveBuf);
  if (i >= 0)
    return i;
  i = FsAllocSlot();
  if (i >= 0)
    FsJournal(FS_OP_CREATE, FsName(i), FsEmpty, 0, FsQuietFlag(FsName(i)), 0);
  return i;
}

I64 Del(U8 *name)
{
  I64 i = FsFind(name);
  U8 *nm;
  if (i < 0) {
    "Del: no such file\n";
    return -1;
  }
  nm = FsName(i);
  FsJournal(FS_OP_UNLINK, nm, FsEmpty, 0, FsQuietFlag(nm), 0);
  FsOnDel(nm);
  FsSetDirty(i, 0);
  FsSetUsed(i, 0);
  FsSetLen(i, 0);
  *nm = 0;
  return 0;
}
// FsRename -- FsRename("from","to")
// NAME
//   FsRename - in-place memfs rename; journals FS_OP_RENAME
// SYNOPSIS
//   I64 FsRename(U8 *from, U8 *to);
// DESCRIPTION
//   Updates the source slot name (no copy of the body). If dest exists it is
//   unlinked first. Move/Rename call this so same-FS moves are not Copy+Del.
// EXAMPLES
//   FileWrite("Home/a.hc", "x", 1);
//   Rename("Home/a.hc", "Home/b.hc");
//   FsChanges;
// SEE ALSO
//   Move  Rename  Del  FsChanges
I64 FsRename(U8 *from, U8 *to)
{
  I64 src, dst, plen, tlen, i, n, k, h;
  U8 *p, *nm;
  if (!from || !to) {
    UartStr("Rename: need from and to\n");
    return -1;
  }
  if (*from == 0 || *to == 0) {
    UartStr("Rename: need from and to\n");
    return -1;
  }
  FsResolve(from);
  FsLogCopyPath(FsFrom, FsResolveBuf);
  FsResolve(to);
  FsLogCopyPath(FsTo, FsResolveBuf);
  if (!FsStrCmp(FsFrom, FsTo))
    return 0;
  src = FsLookup(FsFrom);
  if (src < 0)
    src = FsFind(from);
  if (src < 0) {
    "Rename: no such file: %s\n", from;
    return -1;
  }
  dst = FsLookup(FsTo);
  if (dst >= 0 && dst != src)
    Del(to);
  plen = FsStrLen(FsFrom);
  tlen = FsStrLen(FsTo);
  for (i = 0; i < MEMFS_MAX; i++) {
    if (!FsSlotUsed(i))
      continue;
    if (i == src)
      continue;
    p = FsName(i);
    if (FsStrNCmp(p, FsFrom, plen))
      continue;
    if (p[plen] != '/')
      continue;
    n = 0;
    while (n < tlen && n < 62) {
      FsTmp[n] = FsTo[n];
      n++;
    }
    k = plen;
    while (p[k] && n < 63) {
      FsTmp[n] = p[k];
      n++;
      k++;
    }
    FsTmp[n] = 0;
    FsLogCopyPath(p, FsTmp);
    FsOnWrite(i);
  }
  nm = FsName(src);
  FsLogCopyPath(nm, FsTo);
  h = FsHashBuf(FsData(src), FsLenAt(src));
  FsJournal(FS_OP_RENAME, FsFrom, FsTo, FsLenAt(src), FsQuietFlag(FsTo), h);
  FsOnWrite(src);
  "renamed %s -> %s\n", FsFrom, FsTo;
  return 0;
}
// Move -- Move("from","to")
// NAME
//   Move - in-place memfs rename (same as Rename / FsRename)
// SYNOPSIS
//   I64 Move(U8 *from, U8 *to);
// DESCRIPTION
//   Same-FS move updates the slot name and journals FS_OP_RENAME. Dest is
//   unlinked if it already exists. Not a copy+delete.
// EXAMPLES
//   Move("Home/a.hc", "Home/b.hc");
// SEE ALSO
//   Rename  FsRename  Copy  Del
I64 Move(U8 *from, U8 *to)
{
  return FsRename(from, to);
}
// Rename -- Rename("from","to")
// NAME
//   Rename - in-place memfs rename (alias of Move)
// SYNOPSIS
//   I64 Rename(U8 *from, U8 *to);
// SEE ALSO
//   Move  FsRename
I64 Rename(U8 *from, U8 *to)
{
  return FsRename(from, to);
}

I64 FileWrite(U8 *name, U8 *data, I64 len)
{
  I64 i, k, h;
  U8 *dst, *src, *nm;
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
  nm = FsName(i);
  h = FsHashBuf(FsData(i), len);
  FsJournal(FS_OP_WRITE, nm, FsEmpty, len, FsQuietFlag(nm), h);
  FsOnWrite(i);
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
  if (!name)
    *cwd = 0;
  else if (*name == 0)
    *cwd = 0;
  else if (*name == '/' && name[1] == 0)
    *cwd = 0;
  else if (*name == '.' && name[1] == '.' && (name[2] == 0 || name[2] == '/')) {
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
  // Same TempleOS boot-root form as Pwd (G28 one Cd/Pwd log story).
  UartStr("cwd: ::/");
  UartStr(cwd);
  PutCh('\n');
  return 0;
}

U0 Pwd()
{
  // TempleOS boot-root metaphor for UART memfs (internal storage stays slash paths).
  "::/%s\n", FsCwd();
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
  I64 i, n, slot;
  i = 0;
  while (name[i] && i < 80) {
    FsTmp[i] = name[i];
    i++;
  }
  if (i && FsTmp[i - 1] != '/') {
    FsTmp[i] = '/';
    i++;
  }
  n = i;
  FsTmp[i] = '.';
  FsTmp[i + 1] = 'd';
  FsTmp[i + 2] = 'i';
  FsTmp[i + 3] = 'r';
  FsTmp[i + 4] = 0;
  FsResolve(FsTmp);
  if (FsLookup(FsResolveBuf) >= 0)
    return 0;
  slot = FsAllocSlot();
  if (slot < 0) {
    "DirMk: fs full\n";
    return -1;
  }
  FsPath2[0] = 0;
  if (n > 0) {
    i = 0;
    while (i < n && i < 63) {
      FsPath2[i] = FsTmp[i];
      i++;
    }
    if (i > 0 && FsPath2[i - 1] == '/')
      i--;
    FsPath2[i] = 0;
  }
  FsJournal(FS_OP_DIRMK, FsPath2, FsEmpty, 0, FsQuietFlag(FsPath2), 0);
  return 0;
}

I64 MkDir(U8 *name)
{
  return DirMk(name);
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
  FsLogCopyPath(FsPath2, FsResolveBuf);
  if (cl > 0 && FsPath2[cl - 1] == '/')
    FsPath2[cl - 1] = 0;
  FsJournal(FS_OP_DIRDEL, FsPath2, FsEmpty, 0, FsQuietFlag(FsPath2), 0);
  for (k = 0; k < MEMFS_MAX; k++)
    if (FsSlotUsed(k) && !FsStrNCmp(FsName(k), FsResolveBuf, cl)) {
      FsOnDel(FsName(k));
      FsSetDirty(k, 0);
      FsSetUsed(k, 0);
      FsSetLen(k, 0);
      FsName(k)[0] = 0;
    }
  return 0;
}

I64 FsInSnap(U8 *name)
{
  I64 i;
  if (!name)
    return 0;
  for (i = 0; i < FsSnapN; i++)
    if (!FsStrCmp(FsSnapAt(i), name))
      return 1;
  return 0;
}

U0 FsSnapFill()
{
  I64 i;
  U8 *p;
  p = FsCwd() + FS_META_DIRTY;
  i = 0;
  while (i < MEMFS_MAX) {
    *p = 0;
    p++;
    i++;
  }
  FsDelN = 0;
  FsSnapN = 0;
  for (i = 0; i < MEMFS_MAX; i++)
    if (FsSlotUsed(i)) {
      FsStrCpy(FsSnapAt(FsSnapN), FsName(i));
      *FsSnapSzP(FsSnapN) = FsLenAt(i);
      *FsSnapHashP(FsSnapN) = FsHashBuf(FsData(i), FsLenAt(i));
      FsSnapN++;
    }
}
// FsEpochSealNamed -- FsEpochSealNamed(id, name)
// NAME
//   FsEpochSealNamed - seal a memfs epoch with a journal label
// SYNOPSIS
//   U0 FsEpochSealNamed(I64 id, U8 *name);
// DESCRIPTION
//   Clears the change journal, rebuilds the snap table (dirty/ZMODEM), enables
//   tracking, and appends FS_OP_EPOCH with path=name (BOOT / RECOVER / …).
//   Seed install must finish before FsEpochSeal(FS_EPOCH_BOOT).
// EXAMPLES
//   FsEpochSealNamed(1, "RECOVER");
// SEE ALSO
//   FsEpochSeal  FsRecover  FsSnap  FsCheckpoint
U0 FsEpochSealNamed(I64 id, U8 *name)
{
  if (id < 0)
    id = FS_EPOCH_BOOT;
  if (!name || !*name) {
    if (id == FS_EPOCH_BOOT)
      name = "BOOT";
    else
      name = "E";
  }
  FsSnapFill();
  FsLogSeq = 1;
  FsLogEpochId = id;
  FsLogHead = 0;
  FsLogCount = 0;
  FsLogGen = 0;
  FsLogReady = 1;
  FsEmpty[0] = 0;
  FsSetTracking(1);
  FsJournal(FS_OP_EPOCH, name, FsEmpty, 0, 0, 0);
  "fs epoch %d sealed (%s, snap %d files)\n", id, name, FsSnapN;
}
// FsEpochSeal -- FsEpochSeal(id)
// NAME
//   FsEpochSeal - seal a memfs epoch; mutations after this are journaled
// SYNOPSIS
//   U0 FsEpochSeal(I64 id);
// DESCRIPTION
//   Clears the change journal, rebuilds the boot snap table (dirty/ZMODEM),
//   enables tracking, and appends FS_OP_EPOCH. Seed install must finish
//   before FsEpochSeal(FS_EPOCH_BOOT) so seeds are not listed by FsChanges.
// EXAMPLES
//   FsEpochSeal(FS_EPOCH_BOOT);
// SEE ALSO
//   FsEpochSealNamed  FsEpoch  FsChanges  FsLog  FsSnap  FsRecover
U0 FsEpochSeal(I64 id)
{
  if (id == FS_EPOCH_BOOT)
    FsEpochSealNamed(id, "BOOT");
  else
    FsEpochSealNamed(id, 0);
}
// FsSnap -- FsSnap()
// NAME
//   FsSnap - boot baseline alias for FsEpochSeal(FS_EPOCH_BOOT)
// SYNOPSIS
//   U0 FsSnap();
// SEE ALSO
//   FsEpochSeal  FsChanges  ZmodemSendChanges  FsRecover
U0 FsSnap()
{
  FsEpochSeal(FS_EPOCH_BOOT);
}
// FsCheckpoint -- FsCheckpoint(name)
// NAME
//   FsCheckpoint - pin a named epoch; later mutations use the new id
// SYNOPSIS
//   I64 FsCheckpoint(U8 *name);
// DESCRIPTION
//   Appends FS_OP_EPOCH, bumps FsEpoch, returns the new id. Does not rebuild
//   the boot snap / dirty bits (ZmodemSendChanges still tracks since seal).
// EXAMPLES
//   FsCheckpoint("pre-cmp");
//   FileWrite("Home/t.hc", "x", 1);
//   FsDiff(0);
// SEE ALSO
//   FsEpoch  FsDiff  FsChanges
I64 FsCheckpoint(U8 *name)
{
  I64 id;
  if (!FsLogReady)
    FsEpochSeal(FS_EPOCH_BOOT);
  id = FsLogEpochId + 1;
  FsLogEpochId = id;
  if (!name)
    name = "ckpt";
  else if (*name == 0)
    name = "ckpt";
  FsJournal(FS_OP_EPOCH, name, FsEmpty, 0, 0, 0);
  "fs checkpoint %d (%s)\n", id, name;
  return id;
}
// FsChanges -- FsChanges(since_epoch, flags, until_epoch)
// NAME
//   FsChanges - list unique memfs paths changed since an epoch
// SYNOPSIS
//   U0 FsChanges(I64 since_epoch=-1, I64 flags=0, I64 until_epoch=-1);
// DESCRIPTION
//   Collapses the journal to one line per path (last op wins). since_epoch=-1
//   means since boot (all post-seal mutations). since_epoch=N keeps epoch>N.
//   until_epoch>=0 also requires epoch<=until (FsDiff range). Default hides
//   FS_FLAG_QUIET; pass FS_CH_ALL to include spill / .dirlist / .funlist.
//   Dirty bits still feed ZmodemSendChanges.
// EXAMPLES
//   FsChanges;
//   FileWrite("Home/t.hc", "x", 1);
//   FsChanges;
// SEE ALSO
//   FsLog  FsEpoch  FsDiff  DumpChanges  ZmodemSendChanges
U0 FsChanges(I64 since_epoch = -1, I64 flags = 0, I64 until_epoch = -1)
{
  I64 n, i, op, cur, seq;
  U8 *path, *path2;
  if (since_epoch < -1)
    since_epoch = -1;
  if (!FsLogReady) {
    UartStr("epoch=0 seq=0 since=0\n");
    UartStr("  (none)\n");
    return;
  }
  cur = FsEpoch();
  seq = FsSeq();
  if (until_epoch >= 0)
    "epoch=%d seq=%d since=%d until=%d\n", cur, seq, since_epoch, until_epoch;
  else if (since_epoch < 0)
    "epoch=%d seq=%d since=boot\n", cur, seq;
  else
    "epoch=%d seq=%d since=%d\n", cur, seq, since_epoch;
  n = FsChangeCollect(since_epoch, flags, until_epoch);
  i = 0;
  while (i < n) {
    op = FsChangeOp(i);
    path = FsChangePath(i);
    path2 = FsChangePath2(i);
    if (op == FS_OP_RENAME && *path2)
      "  %c  %s -> %s  size=%d  hash=0x%X\n", FsOpChar(op), path, path2, FsChangeSize(i), FsChangeHash(i);
    else
      "  %c  %s  size=%d  hash=0x%X\n", FsOpChar(op), path, FsChangeSize(i), FsChangeHash(i);
    i++;
  }
  if (!n)
    UartStr("  (none)\n");
}
// FsLog -- FsLog(n)
// NAME
//   FsLog - print the tail of the raw memfs change journal
// SYNOPSIS
//   U0 FsLog(I64 n=32);
// DESCRIPTION
//   Debug dump of the last n journal records (oldest→newest within the tail).
// EXAMPLES
//   FsLog;
//   FsLog(8);
// SEE ALSO
//   FsChanges  FsEpoch
U0 FsLog(I64 n = 32)
{
  I64 age, start, idx, op, i;
  U8 *r, *p, *path2;
  if (!FsLogReady) {
    UartStr("fs log empty\n");
    return;
  }
  if (n < 0)
    n = 0;
  if (n > FsLogCount)
    n = FsLogCount;
  "fs log tail %d/%d epoch=%d seq=%d gen=%d\n", n, FsLogCount, FsEpoch(), FsSeq(), FsLogGen;
  start = FsLogCount - n;
  i = 0;
  while (i < n) {
    age = start + i;
    idx = FsLogChronoIdx(age);
    i++;
    if (idx < 0)
      continue;
    r = FsLogRec(idx);
    p = r + 6;
    op = *p;
    path2 = r + 80;
    if (op == FS_OP_WRAP) {
      "  #%d e=%d @ WRAP n=%d gen=%d\n", FsLogLoadU32(r), FsLogLoadU16(r + 4), FsLogLoadU32(r + 8), FsLogGen;
      continue;
    }
    "  #%d e=%d %c %s", FsLogLoadU32(r), FsLogLoadU16(r + 4), FsOpChar(op), r + 16;
    if (*path2)
      " -> %s", path2;
    if (op == FS_OP_WRITE || op == FS_OP_TRUNC || op == FS_OP_CREATE)
      " size=%d hash=0x%X", FsLogLoadU32(r + 8), FsLogLoadU32(r + 12);
    PutCh('\n');
  }
  if (!n)
    UartStr("  (none)\n");
}
// FsDiff -- FsDiff(a, b)
// NAME
//   FsDiff - session snap drift, or journal ops with epoch in (a, b]
// SYNOPSIS
//   U0 FsDiff(I64 a=-1, I64 b=-1);
// DESCRIPTION
//   FsDiff; (both default) is the ZMODEM session view: FsChanges since boot,
//   then snap entries whose size or FNV hash changed (C EdC size-only).
//   FsDiff(a) / FsDiff(a,b) lists collapsed journal ops with epoch in (a, b]
//   (b defaults to FsEpoch). Quiet spill is hidden; FS_CH_ALL is FsChanges.
// EXAMPLES
//   FsDiff;
//   FsCheckpoint("a");
//   FileWrite("Home/t.hc", "xy", 2);
//   FsDiff(0);
// SEE ALSO
//   FsChanges  FsCheckpoint  ZmodemSendChanges  DumpFile  DumpChanges
U0 FsDiff(I64 a = -1, I64 b = -1)
{
  I64 i, k, sz, h, ha;
  U8 *nm;
  if (a < 0) {
    FsChanges();
    for (i = 0; i < FsSnapN; i++) {
      nm = FsSnapAt(i);
      k = FsLookup(nm);
      if (k < 0)
        continue;
      if (FsIsDirty(k))
        continue;
      sz = FsLenAt(k);
      h = FsHashBuf(FsData(k), sz);
      ha = *FsSnapHashP(i);
      if (sz != *FsSnapSzP(i) || h != ha)
        "  S  %s  %d -> %d  hash=0x%X -> 0x%X\n", nm, *FsSnapSzP(i), sz, ha, h;
    }
    return;
  }
  if (b < 0)
    b = FsEpoch();
  "diff epoch (%d, %d]\n", a, b;
  FsChanges(a, 0, b);
}

I64 FsChangeCanDump(I64 i)
{
  I64 op;
  U8 *path;
  op = FsChangeOp(i);
  if (op == FS_OP_UNLINK || op == FS_OP_DIRDEL || op == FS_OP_DIRMK)
    return 0;
  if (op == FS_OP_RENAME)
    path = FsChangePath2(i);
  else
    path = FsChangePath(i);
  if (!path)
    return 0;
  if (*path == 0)
    return 0;
  if (FileLen(path) < 0)
    return 0;
  return 1;
}
// Drop session-only slots (names not in the current snap table). Tracking off
// so cleanup does not append UNLINK noise before a Recover reseal.
I64 FsDropNonSnap()
{
  I64 i, n, save;
  U8 *nm;
  n = 0;
  save = FsTracking();
  FsSetTracking(0);
  for (i = 0; i < MEMFS_MAX; i++) {
    if (!FsSlotUsed(i))
      continue;
    nm = FsName(i);
    if (FsInSnap(nm))
      continue;
    FsSetDirty(i, 0);
    FsSetUsed(i, 0);
    FsSetLen(i, 0);
    *nm = 0;
    n++;
  }
  FsSetTracking(save);
  return n;
}
// FsReplay -- FsReplay(since_epoch)
// NAME
//   FsReplay - verify memfs against the journal since an epoch (no body rewrite)
// SYNOPSIS
//   I64 FsReplay(I64 since_epoch=-1);
// DESCRIPTION
//   Walks the journal chronologically for records with epoch > since_epoch
//   (since_epoch=-1 → all post-seal ops). Checks presence / size / FNV hash
//   where the log recorded them. Does NOT rebuild file bodies — the journal
//   stores metadata only. Returns the mismatch count (0 = tree matches log).
//   FS_OP_WRAP means history was compacted; remaining records are still checked.
// EXAMPLES
//   FileWrite("Home/t.hc", "x", 1);
//   FsReplay;
//   Recover;
// SEE ALSO
//   FsLog  FsChanges  FsRecover  Recover
// BUGS
//   Cannot restore WRITE/CREATE bytes from the ring; use DumpChanges first.
I64 FsReplay(I64 since_epoch = -1)
{
  I64 age, idx, op, ep, slot, sz, h, want_sz, want_h, miss, wrap_seen;
  U8 *r, *p, *path, *path2;
  miss = 0;
  wrap_seen = 0;
  if (since_epoch < -1)
    since_epoch = -1;
  if (!FsLogReady) {
    UartStr("fs replay: journal not ready\n");
    return -1;
  }
  "fs replay since=%d epoch=%d seq=%d gen=%d\n", since_epoch, FsEpoch(), FsSeq(), FsLogGen;
  age = 0;
  while (age < FsLogCount) {
    idx = FsLogChronoIdx(age);
    age++;
    if (idx < 0)
      continue;
    r = FsLogRec(idx);
    p = r + 6;
    op = *p;
    if (op == FS_OP_WRAP) {
      wrap_seen = 1;
      "  @ WRAP n=%d (history compacted — verify remaining only)\n", FsLogLoadU32(r + 8);
      continue;
    }
    if (op == FS_OP_EPOCH)
      continue;
    ep = FsLogLoadU16(r + 4);
    if (since_epoch >= 0 && ep <= since_epoch)
      continue;
    path = r + 16;
    path2 = r + 80;
    want_sz = FsLogLoadU32(r + 8);
    want_h = FsLogLoadU32(r + 12);
    if (op == FS_OP_UNLINK || op == FS_OP_DIRDEL) {
      if (op == FS_OP_DIRDEL) {
        if (IsDir(path)) {
          "  MISS  X still-present %s\n", path;
          miss++;
        } else
          "  OK    X %s\n", path;
      } else {
        if (FsFind(path) >= 0) {
          "  MISS  D still-present %s\n", path;
          miss++;
        } else
          "  OK    D %s\n", path;
      }
      continue;
    }
    if (op == FS_OP_DIRMK) {
      if (IsDir(path))
        "  OK    K %s\n", path;
      else {
        "  MISS  K absent %s\n", path;
        miss++;
      }
      continue;
    }
    if (op == FS_OP_RENAME) {
      if (FsFind(path) >= 0) {
        "  MISS  R from-still %s\n", path;
        miss++;
      } else if (FsFind(path2) < 0) {
        "  MISS  R to-absent %s\n", path2;
        miss++;
      } else
        "  OK    R %s -> %s\n", path, path2;
      continue;
    }
    slot = FsFind(path);
    if (slot < 0) {
      "  MISS  %c absent %s\n", FsOpChar(op), path;
      miss++;
      continue;
    }
    sz = FsLenAt(slot);
    h = FsHashBuf(FsData(slot), sz);
    if ((op == FS_OP_WRITE || op == FS_OP_TRUNC || op == FS_OP_CREATE) && want_sz && sz != want_sz) {
      "  DRIFT %c %s size %d != %d\n", FsOpChar(op), path, sz, want_sz;
      miss++;
      continue;
    }
    if ((op == FS_OP_WRITE || op == FS_OP_TRUNC) && want_h && h != want_h) {
      "  DRIFT %c %s hash 0x%X != 0x%X\n", FsOpChar(op), path, h, want_h;
      miss++;
      continue;
    }
    "  OK    %c %s\n", FsOpChar(op), path;
  }
  if (wrap_seen)
    UartStr("fs replay: WRAP seen — not a full power-cycle history\n");
  if (!miss)
    UartStr("fs replay: ok\n");
  else
    "fs replay: %d mismatch(es)\n", miss;
  return miss;
}
// FsRecover -- FsRecover()
// NAME
//   FsRecover - soft recover: drop non-snap files and reseal RECOVER epoch
// SYNOPSIS
//   I64 FsRecover();
// DESCRIPTION
//   Session clean without power-cycle. Deletes memfs slots whose names are not
//   in the current snap table (boot / last seal), then FsEpochSealNamed with
//   label RECOVER and a bumped epoch id. Clears the journal and rebuilds snap
//   from what remains. Does NOT reinstall pristine seed bytes from the host
//   blob — mutated snap files stay mutated until image rebuild / power-cycle.
// EXAMPLES
//   DumpChanges;
//   FsRecover;
// SEE ALSO
//   Recover  FsReplay  FsEpochSealNamed  FsDropNonSnap  FsChanges
// BUGS
//   Renames off a snap name look like session files and are dropped. Export first.
I64 FsRecover()
{
  I64 n, dropped, id;
  if (!FsLogReady)
    FsEpochSeal(FS_EPOCH_BOOT);
  n = FsChangeCount(-1, FS_CH_ALL);
  if (n > 0)
    "FsRecover: %d journaled path(s) — prefer DumpChanges / ZmodemSendChanges first\n", n;
  dropped = FsDropNonSnap();
  id = FsEpoch() + 1;
  FsEpochSealNamed(id, "RECOVER");
  "FsRecover: dropped %d session file(s); epoch %d (RECOVER)\n", dropped, id;
  UartStr("FsRecover: honest — mutated seeds kept; power-cycle for pristine reseed\n");
  return id;
}
