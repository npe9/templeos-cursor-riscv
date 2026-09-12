// KThinMemStubs.HC — RV_THIN_LOADER: linear-arena MAlloc (KBootRV) only.
// Drop MemPag/PageTables/BlkPool/HeapCtrl/MemPhysical (~19 KiB). SoftCall
// MemSoft owns HeapCtrl hash-bucket MAlloc/Free/MSize in Kernel.BIN; SoftCall
// MakeMemSoft owns MemPag/BlkPool stock FREE_PAG_HASH=0x100 in Kernel.BIN; SoftCall
// PhysMemSoft owns BlkPoolsInit+MemPageTable+Mem32Dev lite in Kernel.BIN; SoftCall
// Hash2Soft owns free_pag_hash2 stock FREE_PAG_HASH2=55 SoftCall-lite in Kernel.BIN;
// thin needs CAlloc/StrNew for RVKernelInit + LoadBuf.
#ifndef K_THIN_MEM_STUBS_HC
#define K_THIN_MEM_STUBS_HC
U0 SysBadFree(I64 *ptr)
{
  U8 *uart = CONFIG_UART_BASE;
  no_warn ptr;
  *uart = '!';
  while (TRUE)
    HLT;
}

U0 SysBadMAlloc(I64 *ptr)
{
  U8 *uart = CONFIG_UART_BASE;
  no_warn ptr;
  *uart = '?';
  while (TRUE)
    HLT;
}

U8 *AMAlloc(I64 size)
{
  return MAlloc(size, adam_task);
}

U8 *CAlloc(I64 size, CTask *mem_task = NULL)
{
  U8 *res = MAlloc(size, mem_task);
  if (res)
    MemSet(res, 0, size);
  return res;
}

U8 *ACAlloc(I64 size)
{
  return CAlloc(size, adam_task);
}

U8 *MAllocIdent(U8 *src, CTask *mem_task = NULL)
{
  U8 *res;
  I64 size;
  if (!src)
    return NULL;
  size = MSize(src);
  res = MAlloc(size, mem_task);
  if (res)
    MemCpy(res, src, size);
  return res;
}

U8 *AMAllocIdent(U8 *src)
{
  return MAllocIdent(src, adam_task);
}

U8 *MAllocAligned(I64 size, I64 alignment, CTask *mem_task = NULL, I64 misalignment = 0)
{
  I64 mask = alignment - 1;
  U8 *ptr = MAlloc(size + mask + sizeof(I64) + misalignment, mem_task), *res;
  if (!ptr)
    return NULL;
  res = (ptr + sizeof(I64) + mask) & ~mask + misalignment;
  res(I64 *)[-1] = ptr - res;
  return res;
}

U8 *CAllocAligned(I64 size, I64 alignment, CTask *mem_task = NULL, I64 misalignment = 0)
{
  U8 *res = MAllocAligned(size, alignment, mem_task, misalignment);
  if (res)
    MemSet(res, 0, size);
  return res;
}

U8 *StrNew(U8 *buf, CTask *mem_task = NULL)
{
  U8 *res;
  I64 size;
  if (buf) {
    size = StrLen(buf) + 1;
    res = MAlloc(size, mem_task);
    if (res)
      MemCpy(res, buf, size);
  } else {
    res = MAlloc(1, mem_task);
    if (res)
      *res = 0;
  }
  return res;
}

U8 *AStrNew(U8 *buf)
{
  return StrNew(buf, adam_task);
}
// --- unused on thin Jump path (signatures for any residual refs) -------------
U8 *MemPagAlloc(I64 pags, CBlkPool *bp = NULL)
{
  no_warn pags;
  no_warn bp;
  return NULL;
}

U0 MemPagFree(CMemBlk *m, CBlkPool *bp = NULL)
{
  no_warn m;
  no_warn bp;
}

CMemBlk *MemPagTaskAlloc(I64 pags, CHeapCtrl *hc)
{
  no_warn pags;
  no_warn hc;
  return NULL;
}

U0 MemPagTaskFree(CMemBlk *m, CHeapCtrl *hc)
{
  no_warn m;
  no_warn hc;
}

U0 BlkPoolAdd(CBlkPool *bp, CMemBlk *m, I64 pags)
{
  no_warn bp;
  no_warn m;
  no_warn pags;
}

U0 BlkPoolInit(CBlkPool *bp, I64 pags)
{
  no_warn bp;
  no_warn pags;
}

U0 BlkPoolsInit()
{
}

CHeapCtrl *HeapCtrlInit(CHeapCtrl *hc = NULL, CTask *task = NULL, CBlkPool *bp = NULL)
{
  no_warn bp;
  if (!hc)
    hc = ACAlloc(sizeof(CHeapCtrl));
  if (!hc)
    return NULL;
  hc->hc_signature = HEAP_CTRL_SIGNATURE_VAL;
  hc->mem_task = task;
  hc->bp = bp;
  QueInit(&hc->next_mem_blk);
  hc->last_mergable = NULL;
  hc->next_um = hc->last_um = (&hc->next_um)(U8 *) - offset(CMemUsed.next);
  return hc;
}

U0 HeapCtrlDel(CHeapCtrl *hc)
{
  if (hc)
    Free(hc);
}

I64 *MemPageTable(U8 *a)
{
  no_warn a;
  return NULL;
}

Bool Mem32DevIns(CMemRange *tmpmr)
{
  no_warn tmpmr;
  return FALSE;
}

U0 Mem32DevInit()
{
}

U8 *Mem32DevAlloc(I64 size, I64 alignment)
{
  no_warn size;
  no_warn alignment;
  return NULL;
}

U0 Mem32DevFree(U8 *base)
{
  no_warn base;
}

U8 *Mem64DevAlloc(I64 *_pages)
{
  no_warn _pages;
  return NULL;
}

U0 Mem64DevFree(U8 *base, I64 pages)
{
  no_warn base;
  no_warn pages;
}

U8 *UncachedAliasAlloc(U8 *addr, I64 size)
{
  no_warn addr;
  no_warn size;
  return addr;
}

I64 BIOSTotalMem()
{
  return 0x10000000;
}

I64 Scale2Mem(I64 min, I64 max, I64 limit = 0x40000000)
{
  no_warn min;
  no_warn max;
  no_warn limit;
  return min;
}
#endif
