// KThinHashStubs.HC — RV_THIN_LOADER: lite HashStr/Add/Find/TableNew for thin
// Jump (LoadBuf→HashAdd→HashFind→Call). Full KHashA/KHashB + KDefine stay out
// (~17 KiB). SoftCall KernelHashSoft / JumpSoft also prove TableNew+Add+Find
// inside Kernel.BIN (→'KF'/'KL').
#ifndef K_THIN_HASH_STUBS_HC
#define K_THIN_HASH_STUBS_HC
// Power-of-two bucket count — SoftCall JumpSoft uses 16; Kernel.BIN exports ≪ 16.
#ifndef RV_THIN_HASH_BUCKETS
#define RV_THIN_HASH_BUCKETS 16
#endif
// --- live lite hash (KHashRV shape; index stores — RV AOT ** note) -------------
I64 HashStr(U8 *st)
{
  U64 h = 0, c, carry;
  if (!st)
    return 0;
  while (c = *st++) {
    carry = h >> 63;
    h = (h << 1) + c + carry;
  }
  carry = (h >> 15) & 1;
  return h + (h >> 16) + carry;
}

CHash **HashBucketFind(U8 *needle_str, CHashTable *haystack_table)
{
  I64 i;
  if (!needle_str || !haystack_table || !haystack_table->body)
    return NULL;
  i = HashStr(needle_str) & haystack_table->mask;
  return &haystack_table->body[i];
}

U0 HashAdd(CHash *tmph, CHashTable *table)
{
  I64 i;
  if (!tmph || !table || !table->body)
    return;
  i = HashStr(tmph->str) & table->mask;
  tmph->next = table->body[i];
  table->body[i] = tmph;
}

CHash *HashSingleTableFind(U8 *needle_str, CHashTable *haystack_table, I64 mask, I64 instance = 1)
{
  CHash *tmph;
  U8 *a, *b;
  I64 i;
  if (!needle_str || !haystack_table || !haystack_table->body || instance <= 0)
    return NULL;
  i = HashStr(needle_str) & haystack_table->mask;
  tmph = haystack_table->body[i];
  while (tmph) {
    if ((tmph->type & mask) && tmph->str) {
      a = tmph->str;
      b = needle_str;
      while (*a && *a == *b) {
        a++;
        b++;
      }
      if (!*a && !*b) {
        if (--instance == 0) {
          tmph->use_cnt++;
          return tmph;
        }
      }
    }
    tmph = tmph->next;
  }
  return NULL;
}

CHash *HashFind(U8 *needle_str, CHashTable *haystack_table, I64 mask, I64 instance = 1)
{
  CHash *res;
  while (haystack_table) {
    res = HashSingleTableFind(needle_str, haystack_table, mask, instance);
    if (res)
      return res;
    haystack_table = haystack_table->next;
  }
  return NULL;
}

CHashTable *HashTableNew(I64 size, CTask *mem_task = NULL)
{
  CHashTable *table;
  table = CAlloc(sizeof(CHashTable), mem_task);
  if (!table)
    return NULL;
  table->body = CAlloc(size << 3, mem_task);
  if (!table->body)
    return NULL;
  table->mask = size - 1;
  return table;
}

Bool HashRemDel(CHash *tmph, CHashTable *table, I64 instance = 1)
{
  no_warn tmph;
  no_warn table;
  no_warn instance;
  return FALSE;
}

U0 HashDel(CHashSrcSym *tmph)
{
  no_warn tmph;
}

U0 HashTableDel(CHashTable *table)
{
  no_warn table;
}

I64 HashTablePurge(CHashTable *table)
{
  no_warn table;
  return 0;
}

I64 HashTypeNum(CHash *tmph)
{
  no_warn tmph;
  return 0;
}

I64 HashVal(CHash *tmph)
{
  // Thin Jump uses CHashExport.val directly (like SoftCall JumpSoft).
  if (tmph && (tmph->type & HTT_EXPORT_SYS_SYM))
    return tmph(CHashExport *)->val;
  return 0;
}

CHashGeneric *HashGenericAdd(U8 *name, I64 type, I64 u0 = 0, I64 u1 = 0, I64 u2 = 0, CTask *task = NULL)
{
  no_warn name;
  no_warn type;
  no_warn u0;
  no_warn u1;
  no_warn u2;
  no_warn task;
  return NULL;
}

U0 HashSrcFileSet(CCmpCtrl *cc, CHashSrcSym *h, I64 line_num_offset = 0)
{
  no_warn cc;
  no_warn h;
  no_warn line_num_offset;
}

CHashGeneric *HashPublic(U8 *st, I64 mask, Bool val = TRUE)
{
  no_warn st;
  no_warn mask;
  no_warn val;
  return NULL;
}

I64 HashLstAdd(U8 *lst, I64 type, CHashTable *table)
{
  no_warn lst;
  no_warn type;
  no_warn table;
  return 0;
}

I64 HashDefineLstAdd(U8 *dname, I64 type, CHashTable *table)
{
  no_warn dname;
  no_warn type;
  no_warn table;
  return 0;
}

I64 FramePtr(U8 *name, CTask *task = NULL)
{
  no_warn name;
  no_warn task;
  return 0;
}

CHashGeneric *FramePtrAdd(U8 *name, I64 val = 0, CTask *task = NULL)
{
  no_warn name;
  no_warn val;
  no_warn task;
  return NULL;
}

I64 FramePtrSet(U8 *name, I64 val, CTask *task = NULL)
{
  no_warn name;
  no_warn val;
  no_warn task;
  return 0;
}

I64 FramePtrDel(U8 *name, CTask *task = NULL)
{
  no_warn name;
  no_warn task;
  return 0;
}

CHashDefineStr *DefineLoad(U8 *dname, U8 *st)
{
  no_warn dname;
  no_warn st;
  return NULL;
}

CHashDefineStr *DefineLstLoad(U8 *dname, U8 *lst)
{
  no_warn dname;
  no_warn lst;
  return NULL;
}

U0 UndefinedDefine(U8 *dname)
{
  no_warn dname;
}

U8 *Define(U8 *dname)
{
  no_warn dname;
  return NULL;
}

U8 *DefineSub(I64 sub, U8 *dname)
{
  no_warn sub;
  no_warn dname;
  return NULL;
}

I64 DefineCnt(U8 *dname)
{
  no_warn dname;
  return 0;
}

I64 DefineMatch(U8 *needle, U8 *haystack_dft = NULL, I64 flags = 0)
{
  no_warn needle;
  no_warn haystack_dft;
  no_warn flags;
  return -1;
}

U0 DefinePrint(U8 *dname, U8 *src,...)
{
  no_warn dname;
  no_warn src;
}

U0 SysDefinesLoad()
{
}
#endif
