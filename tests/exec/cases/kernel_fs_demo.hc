// A minimal filesystem on the virtio-blk device: a superblock + 15-entry directory in sector 0, file
// data bump-allocated in the following sectors. Pure HolyC over RVBlkRead/RVBlkWrite. The program is
// idempotent across boots: on a blank disk it formats and creates files; on a disk it already wrote,
// it reads them back — so running it twice on the same image proves the files PERSIST across reboots.
#include "/Kernel/Kernel_RV.PRJ"
class FSEntry
{
  U8 name[24];
  U32 start_blk;
  U32 size;
};

class FSSuper
{
  U32 magic, count, next_free, pad;
  FSEntry ent[15];
};

U0 FSFormat()
{
  FSSuper *s = CAlloc(512, NULL);
  s->magic = 0x52564653;
  s->count = 0;
  s->next_free = 1;
  RVBlkWrite(0, s);
}

I64 FSCreate(U8 *name, U8 *data, I64 len)
{
  FSSuper *s = CAlloc(512, NULL);
  RVBlkRead(0, s);
  if (s->count >= 15)
    return -1;
  I64 blocks = (len + 511) / 512, i;
  FSEntry *e = &s->ent[s->count];
  StrCpy(e->name, name);
  e->start_blk = s->next_free;
  e->size = len;
  U8 *blk = CAlloc(512, NULL);
  for (i = 0; i < blocks; i++) {
    I64 j;
    for (j = 0; j < 512; j++)
      blk[j] = (i * 512 + j < len) ? data[i * 512 + j] : 0;
    RVBlkWrite(s->next_free + i, blk);
  }
  s->next_free += blocks;
  s->count++;
  RVBlkWrite(0, s);
  return 0;
}

I64 FSRead(U8 *name, U8 *buf)
{
  FSSuper *s = CAlloc(512, NULL);
  RVBlkRead(0, s);
  I64 i;
  for (i = 0; i < s->count; i++)
    if (StrCmp(s->ent[i].name, name) == 0) {
      I64 blocks = (s->ent[i].size + 511) / 512, b;
      for (b = 0; b < blocks; b++) {
        U8 *t = CAlloc(512, NULL);
        RVBlkRead(s->ent[i].start_blk + b, t);
        I64 j;
        for (j = 0; j < 512; j++)
          buf[b * 512 + j] = t[j];
      }
      return s->ent[i].size;
    }
  return -1;
}

I64 main()
{
  RVKernelInit();
  if (RVBlkInit()) {
    Print("no block device\n");
    return 1;
  }
  FSSuper *s = CAlloc(512, NULL);
  RVBlkRead(0, s);
  if (s->magic != 0x52564653) {
    FSFormat();
    FSCreate("hello.txt", "Hello from the RISC-V filesystem!", 33);
    FSCreate("num.dat", "42", 2);
    Print("fresh disk: formatted, created hello.txt + num.dat\n");
  } else {
    U8 *buf = CAlloc(1024, NULL);
    I64 n = FSRead("hello.txt", buf);
    buf[n] = 0;
    Print("persisted: %d files, hello.txt='%s'\n", s->count, buf);
  }
  return 0;
}
