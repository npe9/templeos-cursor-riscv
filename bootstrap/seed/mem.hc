// mem.hc -- HolyC heap (MAlloc/Free/MSize/CAlloc/MSize2). Arena at 0x86000000..0x86F00000.
// No C RuntimeRegister: this IS the REPL heap after boot.
#define HEAP_BASE 0x86000000
#define HEAP_END  0x86F00000
class CHolyBlk
{
  I64 size;
  CHolyBlk *next;
};
CHolyBlk *hc_free_list = 0;
U8 *hc_heap_brk = HEAP_BASE;
// MAlloc -- MAlloc(sz)
// NAME
//   MAlloc - allocate sz bytes from the HolyC heap
// SYNOPSIS
//   U8 *MAlloc(I64 sz);
// DESCRIPTION
//   First-fit free list, else bump from HEAP_BASE. 16-byte header {size,next}; payload 16-aligned.
// INPUTS
//   sz - byte count (<=0 coerced to 1)
// OUTPUTS
//   Pointer to block, or NULL if the arena is exhausted
// BUGS
//   Arena is fixed; never returned to a host allocator.
U8 *MAlloc(I64 sz)
{
  CHolyBlk *b, *best, **pp;
  U8 *p;
  if (sz <= 0)
    sz = 1;
  sz = (sz + 15) & -16;
  pp = &hc_free_list;
  while (*pp) {
    if ((*pp)->size >= sz) {
      b = *pp;
      *pp = b->next;
      b->next = 0;
      return (U8 *)(b + 1);
    }
    pp = &(*pp)->next;
  }
  if (hc_heap_brk + sizeof(CHolyBlk) + sz > HEAP_END)
    return 0;
  b = hc_heap_brk;
  hc_heap_brk = hc_heap_brk + sizeof(CHolyBlk) + sz;
  b->size = sz;
  b->next = 0;
  return (U8 *)(b + 1);
}
// Free -- Free(p)
// NAME
//   Free - return an MAlloc block to the free list
// SYNOPSIS
//   U0 Free(U8 *p);
U0 Free(U8 *p)
{
  CHolyBlk *b;
  if (!p)
    return;
  b = p - sizeof(CHolyBlk);
  b->next = hc_free_list;
  hc_free_list = b;
}
// MSize -- MSize(p)
// NAME
//   MSize - payload size of an MAlloc block
// SYNOPSIS
//   I64 MSize(U8 *p);
I64 MSize(U8 *p)
{
  CHolyBlk *b;
  if (!p)
    return 0;
  b = p - sizeof(CHolyBlk);
  return b->size;
}
// CAlloc -- CAlloc(sz)
U8 *CAlloc(I64 sz)
{
  U8 *p;
  I64 i;
  p = MAlloc(sz);
  if (!p)
    return 0;
  for (i = 0; i < sz; i++)
    p[i] = 0;
  return p;
}
// MSize2 -- MSize2(p)
I64 MSize2(U8 *p)
{
  return MSize(p);
}
