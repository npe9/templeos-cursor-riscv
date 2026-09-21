// RVFsJournal.HC — a change journal over the kernel's filesystem.
//
// Ported from bootstrap/seed/{fs,zmodem,ops}.hc, which only ever existed in the thin JIT image
// retired in 080f729. That left dump-changes-smoke driving build/repl-holyc.elf -- aliased to
// the guest Compiler_RV image -- for FsLog/FsChanges/FsReplay/DumpChanges/Recover, none of
// which any built image carried.
//
// This is NOT a copy of the seed's version. The seed journaled its own memfs at a fixed arena
// (MEMFS_BASE 0x87800000) and collided with the kernel on FileWrite/FileRead/Dir/Del. Porting
// that wholesale would have given a journal over a second filesystem nothing else writes to --
// green smoke, inert feature. This journals the FS the image actually uses, so DumpChanges on
// the product image reports real changes.
//
// The ring is a kernel array rather than a fixed physical address: nothing outside needs to
// find it by poking memory, and an address that happens to be free today is how the seed's
// layout comments ended up three paragraphs long.
#ifndef RV_FS_JOURNAL_HC
#define RV_FS_JOURNAL_HC
#define FS_OP_CREATE 1
#define FS_OP_WRITE  2
#define FS_OP_UNLINK 3
#define FS_OP_RENAME 4
#define FS_OP_TRUNC  5
#define FS_OP_DIRMK  6
#define FS_OP_DIRDEL 7
#define FS_OP_EPOCH  8
#define FS_OP_WRAP   9
#define FSJ_PATH 72
#define FSJ_MAX  512
// 512 records, matching the seed's ring, so a fill loop of 520 still proves wrap honesty.
class CFsJRec
{
  U8 path[FSJ_PATH];
  U8 path2[FSJ_PATH];
  I64 op, size, hash, seq, epoch;
};
CFsJRec fsj_ring[FSJ_MAX];
I64 fsj_seq, fsj_epoch, fsj_head, fsj_count, fsj_gen, fsj_ready, fsj_wrapped;
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

public I64 FsEpoch()
{
  return fsj_epoch;
}

public I64 FsSeq()
{
  return fsj_seq;
}

U0 FsJCopyPath(U8 *dst, U8 *src)
{
  I64 i = 0;
  if (!src) {
    *dst = 0;
    return;
  }
  while (src[i] && i < FSJ_PATH - 1) {
    dst[i] = src[i];
    i++;
  }
  dst[i] = 0;
}

I64 FsJHash(U8 *buf, I64 len)
{
  I64 h = 0x811C9DC5, i = 0;
  if (!buf)
    return 0;
  while (i < len) {
    h = (h ^ buf[i]) * 0x01000193;
    h = h & 0xFFFFFFFF;
    i++;
  }
  return h;
}
// The hook. Every journaled operation lands here, and the ring is the only place it lands --
// so a caller that forgets to call this is invisible rather than half-recorded.
public U0 FsJournal(I64 op, U8 *path, U8 *path2, I64 size, I64 hash)
{
  CFsJRec *r;
  if (!fsj_ready)
    return;
  if (fsj_count >= FSJ_MAX) {
    // The ring is full and the oldest record is about to go. Say so in the journal itself
    // rather than letting the tail quietly disagree with the count.
    fsj_wrapped++;
    r = &fsj_ring[fsj_head];
    fsj_head = (fsj_head + 1) % FSJ_MAX;
    fsj_count--;
    fsj_gen++;
  }
  r = &fsj_ring[(fsj_head + fsj_count) % FSJ_MAX];
  FsJCopyPath(r->path, path);
  FsJCopyPath(r->path2, path2);
  r->op = op;
  r->size = size;
  r->hash = hash;
  r->seq = fsj_seq++;
  r->epoch = fsj_epoch;
  fsj_count++;
}
// What FileWrite calls through fsj_write_fn. Hashes the buffer it was HANDED rather than
// reading the file back: a read-back costs a second trip through the FS, and -- found the hard
// way -- fires FileRead's own PrintErr for every internal write whose name does not resolve on
// its own, which buried the journal output in "File not found" noise.
I64 FsJournalWrite(U8 *path, U8 *buf, I64 size)
{
  if (!path || !buf || size <= 0)
    return 0;
  FsJournal(FS_OP_WRITE, path, NULL, size, FsJHash(buf, size));
  return 0;
}

public U0 FsJournalInit()
{
  fsj_seq = 0;
  fsj_epoch = 0;
  fsj_head = 0;
  fsj_count = 0;
  fsj_gen = 0;
  fsj_wrapped = 0;
  fsj_ready = 1;
  fsj_write_fn = &FsJournalWrite;
}

I64 FsJIdx(I64 age)
{
  if (age < 0 || age >= fsj_count)
    return -1;
  return (fsj_head + age) % FSJ_MAX;
}
// FsLog -- FsLog(n)
// NAME
//   FsLog - print the tail of the raw change journal
// SYNOPSIS
//   U0 FsLog(I64 n=32);
// DESCRIPTION
//   The last n records, oldest to newest within the tail. Raw: every record as written, with
//   no collapsing, which is what tells you whether the ring wrapped and how often.
// EXAMPLES
//   FsLog;
//   FsLog(8);
// SEE ALSO
//   FsChanges  FsEpoch  FsReplay  DumpChanges
public U0 FsLog(I64 n = 32)
{
  I64 i, age, idx;
  CFsJRec *r;
  if (!fsj_ready) {
    "fs log empty\n";
    return;
  }
  if (n < 0)
    n = 0;
  if (n > fsj_count)
    n = fsj_count;
  "fs log tail %d/%d epoch=%d seq=%d gen=%d\n", n, fsj_count, fsj_epoch, fsj_seq, fsj_gen;
  if (fsj_wrapped)
    "  @  WRAP n=%d (ring %d, oldest dropped)\n", fsj_wrapped, FSJ_MAX;
  i = 0;
  while (i < n) {
    age = fsj_count - n + i;
    idx = FsJIdx(age);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (r->op == FS_OP_RENAME && r->path2[0])
      "  %c  %s -> %s  seq=%d  epoch=%d\n", FsOpChar(r->op), r->path, r->path2, r->seq, r->epoch;
    else
      "  %c  %s  size=%d  hash=0x%X  seq=%d\n", FsOpChar(r->op), r->path, r->size, r->hash, r->seq;
  }
  if (!n)
    "  (none)\n";
}
// FsChanges -- FsChanges(since)
// NAME
//   FsChanges - what changed, collapsed to one line per path
// SYNOPSIS
//   U0 FsChanges(I64 since_epoch=-1, I64 flags=0, I64 until_epoch=-1);
// DESCRIPTION
//   The journal read as a change SET rather than a history: repeated writes to one path
//   collapse to its latest record. since_epoch=-1 means since boot.
// EXAMPLES
//   FsChanges;
//   FsChanges(2);
// SEE ALSO
//   FsLog  DumpChanges  FsReplay  Recover
public U0 FsChangesEx(I64 since_epoch = -1, I64 flags = 0, I64 until_epoch = -1)
{
  I64 i, j, idx, jdx, n = 0, dup;
  CFsJRec *r, *q;
  no_warn flags;
  if (since_epoch < -1)
    since_epoch = -1;
  if (!fsj_ready) {
    "epoch=0 seq=0 since=0\n";
    "  (none)\n";
    return;
  }
  if (until_epoch >= 0)
    "epoch=%d seq=%d since=%d until=%d\n", fsj_epoch, fsj_seq, since_epoch, until_epoch;
  else if (since_epoch < 0)
    "epoch=%d seq=%d since=boot\n", fsj_epoch, fsj_seq;
  else
    "epoch=%d seq=%d since=%d\n", fsj_epoch, fsj_seq, since_epoch;
  i = 0;
  while (i < fsj_count) {
    idx = FsJIdx(i);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (since_epoch >= 0 && r->epoch < since_epoch)
      continue;
    if (until_epoch >= 0 && r->epoch > until_epoch)
      continue;
    if (r->op == FS_OP_EPOCH || r->op == FS_OP_WRAP)
      continue;
    // collapse: skip this record if a LATER one names the same path
    dup = 0;
    j = i;
    while (j < fsj_count) {
      jdx = FsJIdx(j);
      j++;
      if (jdx < 0)
        continue;
      q = &fsj_ring[jdx];
      if (q->op == FS_OP_EPOCH || q->op == FS_OP_WRAP)
        continue;
      if (!StrCmp(q->path, r->path)) {
        dup = 1;
        break;
      }
    }
    if (dup)
      continue;
    if (r->op == FS_OP_RENAME && r->path2[0])
      "  %c  %s -> %s  size=%d  hash=0x%X\n", FsOpChar(r->op), r->path, r->path2, r->size, r->hash;
    else
      "  %c  %s  size=%d  hash=0x%X\n", FsOpChar(r->op), r->path, r->size, r->hash;
    n++;
  }
  if (!n)
    "  (none)\n";
}
// FsReplay -- FsReplay(since)
// NAME
//   FsReplay - walk the journal and check every record still describes the filesystem
// SYNOPSIS
//   I64 FsReplay(I64 since_epoch=-1);
// DESCRIPTION
//   Re-reads each journaled path and compares its current size and hash against the record.
//   A write that was journaled but never reached the disk, or a file changed behind the
//   journal's back, shows up here as a mismatch. Returns the number of mismatches.
// SEE ALSO
//   FsChanges  Recover  FsLog
public I64 FsReplayEx(I64 since_epoch = -1)
{
  I64 i, idx, bad = 0, seen = 0, sz;
  U8 *buf;
  CFsJRec *r;
  if (!fsj_ready) {
    "fs replay: empty\n";
    return 0;
  }
  i = 0;
  while (i < fsj_count) {
    idx = FsJIdx(i);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (since_epoch >= 0 && r->epoch < since_epoch)
      continue;
    if (r->op != FS_OP_WRITE && r->op != FS_OP_CREATE)
      continue;
    seen++;
    if (!FileFind(r->path)) {
      // Journaled but gone now. A finding, not an error -- a later unlink is exactly this --
      // so it is counted rather than thrown, and probed with FileFind so the miss stays quiet.
      bad++;
      continue;
    }
    sz = 0;
    buf = FileRead(r->path, &sz);
    if (!buf) {
      bad++;
      continue;
    }
    if (sz != r->size || FsJHash(buf, sz) != r->hash)
      bad++;
    Free(buf);
  }
  if (bad)
    "fs replay: %d/%d mismatched\n", bad, seen;
  else
    "fs replay: ok (%d records)\n", seen;
  return bad;
}
// Seal the current epoch and start the next. Every record carries the epoch it was written in,
// so sealing is what makes "since=N" mean something later.
public I64 FsSeal(U8 *why)
{
  I64 was = fsj_epoch;
  if (!fsj_ready)
    return -1;
  FsJournal(FS_OP_EPOCH, "<epoch>", NULL, fsj_epoch, 0);
  fsj_epoch++;
  "epoch %d sealed (%s), now %d\n", was, why, fsj_epoch;
  return was;
}
// FsRecover -- FsRecover()
// NAME
//   FsRecover - drop journal records that no longer describe anything, then seal
// SYNOPSIS
//   I64 FsRecover();
// DESCRIPTION
//   A journal outlives the files it describes. This drops the records whose path can no longer
//   be read, reports how many went, and seals the epoch so what remains is a clean baseline.
// SEE ALSO
//   Recover  FsReplay  FsChanges
public I64 FsRecover()
{
  I64 i, idx, dropped = 0, kept = 0, sz;
  U8 *buf;
  CFsJRec *r;
  CFsJRec *keep;
  if (!fsj_ready)
    return 0;
  keep = MAlloc(sizeof(CFsJRec) * FSJ_MAX);
  if (!keep)
    return -1;
  i = 0;
  while (i < fsj_count) {
    idx = FsJIdx(i);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (r->op == FS_OP_WRITE || r->op == FS_OP_CREATE) {
      // FileFind, not FileRead: this is an existence probe, and FileRead prints its own error
      // for a miss -- which is the normal case here and drowned the result in red text.
      if (!FileFind(r->path)) {
        dropped++;
        continue;
      }
    }
    MemCpy(&keep[kept], r, sizeof(CFsJRec));
    kept++;
  }
  i = 0;
  while (i < kept) {
    MemCpy(&fsj_ring[i], &keep[i], sizeof(CFsJRec));
    i++;
  }
  Free(keep);
  fsj_head = 0;
  fsj_count = kept;
  "FsRecover: dropped %d, kept %d\n", dropped, kept;
  FsSeal("RECOVER");
  return dropped;
}
// Recover -- Recover()
// NAME
//   Recover - FsRecover under the name the seed image used
// SEE ALSO
//   FsRecover  FsChanges
public U0 Recover()
{
  FsRecover;
}
// Zero-argument spellings, which is how these are actually typed -- `FsChanges;` not
// `FsChanges(-1)`. A planted pub carries exactly the arguments it declares, so a three-parameter
// function reached through a one-argument pub gets GARBAGE in the other two: FsChanges printed
// `since=-1 until=0` and took the until-branch, because until_epoch held whatever was in the
// register. Declaring the arity the caller uses is the fix, and the Ex forms stay for a caller
// that wants a range.
public U0 FsChanges()
{
  FsChangesEx(-1, 0, -1);
}

public I64 FsReplay()
{
  return FsReplayEx(-1);
}

public U0 DumpChanges()
{
  DumpChangesEx(-1);
}
// Rename -- Rename(from, to)
// NAME
//   Rename - move a file and journal it as one record rather than two
// SYNOPSIS
//   I64 Rename(U8 *from, U8 *to);
// DESCRIPTION
//   Copy then unlink, recorded as a single FS_OP_RENAME carrying both paths -- which is what
//   lets FsChanges show `R from -> to` instead of an unlink and a create that a reader has to
//   pair up by eye.
// SEE ALSO
//   FsChanges  FsLog
public I64 Rename(U8 *from, U8 *to)
{
  I64 sz = 0, rc;
  U8 *buf;
  if (!from || !to)
    return -1;
  buf = FileRead(from, &sz);
  if (!buf) {
    "rename: cannot read %s\n", from;
    return -2;
  }
  rc = FileWrite(to, buf, sz);
  Free(buf);
  if (rc < 0) {
    "rename: cannot write %s\n", to;
    return -3;
  }
  Del(from);
  FsJournal(FS_OP_RENAME, from, to, sz, 0);
  "renamed %s -> %s\n", from, to;
  return 0;
}
// A '$' inside a Print format string is DOLDOC MARKUP, and on this image Print goes through a
// DolDoc console -- `"A$$B\n"` prints just `A` and swallows the rest. The dump protocol is built
// entirely out of $-delimited markers, so every one of them is emitted with the text formatted
// into a buffer first and the delimiters written as characters. PutChars(36) puts a literal $.
//
// The seed image never hit this because its Print went straight to the UART.
U0 FsJMark(U8 *body)
{
  PutChars('$');
  "%s", body;
  PutChars('$');
  "\n";
}
U8 *fsj_b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
// One base64 line per 48 input bytes (64 output chars), which keeps a frame readable in a
// terminal AND inside the smoke's captured log. tools/uart_recv_dump.py strips anything that is
// not base64 before decoding, so the line length is ours to pick.
U0 FsJDumpB64(U8 *buf, I64 len)
{
  I64 i = 0, col = 0, v;
  while (i < len) {
    v = buf[i] << 16;
    if (i + 1 < len)
      v |= buf[i + 1] << 8;
    if (i + 2 < len)
      v |= buf[i + 2];
    PutChars(fsj_b64[(v >> 18) & 63]);
    PutChars(fsj_b64[(v >> 12) & 63]);
    if (i + 1 < len)
      PutChars(fsj_b64[(v >> 6) & 63]);
    else
      PutChars('=');
    if (i + 2 < len)
      PutChars(fsj_b64[v & 63]);
    else
      PutChars('=');
    i += 3;
    col += 4;
    if (col >= 64) {
      "\n";
      col = 0;
    }
  }
  if (col)
    "\n";
}
// Emit one file as a $HC_DUMP frame, delimiters through FsJMark so DolDoc does not eat them.
U0 FsJDumpFile(U8 *path)
{
  I64 sz = 0;
  U8 *buf;
  U8 line[256];
  buf = FileRead(path, &sz);
  if (!buf)
    return;
  StrPrint(line, "HC_DUMP name=%s size=%d", path, sz);
  FsJMark(line);
  FsJDumpB64(buf, sz);
  FsJMark("HC_END");
  Free(buf);
}
// DumpChanges -- DumpChanges(since)
// NAME
//   DumpChanges - emit a manifest of what changed, then the bodies, over the UART
// SYNOPSIS
//   U0 DumpChanges(I64 since_epoch=-1);
// DESCRIPTION
//   Prints a $HC_CHANGES manifest naming every changed path, then a $HC_DUMP frame per
//   readable file with its contents base64-encoded. tools/uart_recv_dump.py reconstructs the
//   tree on the host from nothing but the serial log, so a guest with no disk and no network
//   can still hand back what it wrote.
// EXAMPLES
//   DumpChanges;
//   DumpChanges(3);   // only since epoch 3
// SEE ALSO
//   FsChanges  FsLog  FsReplay  Recover
public U0 DumpChangesEx(I64 since_epoch = -1)
{
  I64 i, j, idx, jdx, cnt = 0, dumps = 0, dup, sz;
  U8 *buf;
  U8 line[256];
  CFsJRec *r, *q;
  if (!fsj_ready) {
    FsJMark("HC_CHANGES epoch=0..0 count=0 dumps=0");
    FsJMark("HC_END");
    return;
  }
  // Two passes: the manifest has to carry the counts, so they are known before a byte of it is
  // printed. Collapsing matches FsChanges -- one line per path, newest record wins.
  i = 0;
  while (i < fsj_count) {
    idx = FsJIdx(i);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (since_epoch >= 0 && r->epoch < since_epoch)
      continue;
    if (r->op == FS_OP_EPOCH || r->op == FS_OP_WRAP)
      continue;
    dup = 0;
    j = i;
    while (j < fsj_count) {
      jdx = FsJIdx(j);
      j++;
      if (jdx < 0)
        continue;
      q = &fsj_ring[jdx];
      if (q->op == FS_OP_EPOCH || q->op == FS_OP_WRAP)
        continue;
      if (!StrCmp(q->path, r->path)) {
        dup = 1;
        break;
      }
    }
    if (dup)
      continue;
    cnt++;
    sz = 0;
    buf = FileRead(r->path, &sz);
    if (buf) {
      dumps++;
      Free(buf);
    }
  }
  if (since_epoch < 0)
    StrPrint(line, "HC_CHANGES epoch=0..%d count=%d dumps=%d", fsj_epoch, cnt, dumps);
  else
    StrPrint(line, "HC_CHANGES epoch=%d..%d count=%d dumps=%d", since_epoch, fsj_epoch, cnt, dumps);
  FsJMark(line);
  i = 0;
  while (i < fsj_count) {
    idx = FsJIdx(i);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (since_epoch >= 0 && r->epoch < since_epoch)
      continue;
    if (r->op == FS_OP_EPOCH || r->op == FS_OP_WRAP)
      continue;
    dup = 0;
    j = i;
    while (j < fsj_count) {
      jdx = FsJIdx(j);
      j++;
      if (jdx < 0)
        continue;
      q = &fsj_ring[jdx];
      if (q->op == FS_OP_EPOCH || q->op == FS_OP_WRAP)
        continue;
      if (!StrCmp(q->path, r->path)) {
        dup = 1;
        break;
      }
    }
    if (dup)
      continue;
    "%c %s\n", FsOpChar(r->op), r->path;
  }
  FsJMark("HC_END");
  // then the bodies, in the same order
  i = 0;
  while (i < fsj_count) {
    idx = FsJIdx(i);
    i++;
    if (idx < 0)
      continue;
    r = &fsj_ring[idx];
    if (since_epoch >= 0 && r->epoch < since_epoch)
      continue;
    if (r->op == FS_OP_EPOCH || r->op == FS_OP_WRAP)
      continue;
    dup = 0;
    j = i;
    while (j < fsj_count) {
      jdx = FsJIdx(j);
      j++;
      if (jdx < 0)
        continue;
      q = &fsj_ring[jdx];
      if (q->op == FS_OP_EPOCH || q->op == FS_OP_WRAP)
        continue;
      if (!StrCmp(q->path, r->path)) {
        dup = 1;
        break;
      }
    }
    if (dup)
      continue;
    FsJDumpFile(r->path);
  }
}
#endif
