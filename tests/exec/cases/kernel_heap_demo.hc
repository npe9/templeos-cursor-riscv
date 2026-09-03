// The kernel's OWN memory subsystem on a real CHeapCtrl. TempleOS's CAlloc/MAllocAligned/MSize are
// real compiled functions; only MAlloc/Free are x86 asm (_MALLOC/_FREE). Defining MAlloc/Free in
// HolyC overrides the runtime stubs, so the kernel's own CAlloc calls THESE — a faithful port of the
// allocator: a real CHeapCtrl (real malloc_free_lst free list, used_u8s/alloced_u8s accounting) over
// a physical RAM pool, with the real CMemUsed header so the kernel's MSize/Free stay compatible.
#include "/Kernel/Kernel_RV.PRJ"
CHeapCtrl *the_heap = 0x82000000;
U8 *heap_next = 0x82000400;
U8 *heap_end = 0x86000000;
U8 *MAlloc(I64 size, CTask *mem_task = NULL)
{
  I64 need = (size + offset(CMemUsed.start) + 15) & (~15);
  CMemUnused *f = the_heap->malloc_free_lst, *prev = NULL;
  while (f && f->size < need) {
    prev = f;
    f = f->next;
  }
  U8 *chunk;
  I64 usize;
  if (f) {
    if (prev)
      prev->next = f->next;
    else
      the_heap->malloc_free_lst = f->next;
    chunk = f;
    usize = f->size;
  } else {
    if (heap_next + need > heap_end)
      return NULL;
    chunk = heap_next;
    heap_next += need;
    usize = need;
    the_heap->alloced_u8s += need;
  }
  CMemUsed *u = chunk;
  u->hc = the_heap;
  u->size = usize;
  the_heap->used_u8s += usize;
  return chunk + offset(CMemUsed.start);
}

U0 Free(U8 *ptr)
{
  if (!ptr)
    return;
  CMemUsed *u = ptr - offset(CMemUsed.start);
  I64 sz = u->size;
  CMemUnused *fu = u;
  fu->size = sz;
  fu->next = the_heap->malloc_free_lst;
  the_heap->malloc_free_lst = fu;
  the_heap->used_u8s -= sz;
}

I64 MSize(U8 *ptr)
{
  if (!ptr)
    return 0;
  CMemUsed *u = ptr - offset(CMemUsed.start);
  return u->size - offset(CMemUsed.start);
}

I64 main()
{
  RVKernelInit();
  Print("real heap: CHeapCtrl@0x%X\n", the_heap);
  U8 *a = CAlloc(100, NULL), *b = CAlloc(200, NULL), *c = CAlloc(50, NULL);
  StrCpy(a, "chunk-A");
  StrCpy(b, "chunk-B");
  StrCpy(c, "chunk-C");
  Print("  CAlloc x3: a='%s' b='%s' c='%s' MSize(b)>=200:%d\n", a, b, c, MSize(b) >= 200);
  Free(b);
  U8 *d = CAlloc(150, NULL);
  Print("  free(b)+CAlloc: reused b's chunk=%d  used_u8s=%d\n", d == b, the_heap->used_u8s);
  return 0;
}
