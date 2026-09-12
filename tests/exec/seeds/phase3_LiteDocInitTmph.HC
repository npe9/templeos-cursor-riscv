// Soft tip rung B of the stock DocInit_RV Soft Cmp bisect ladder.
// Rung A + the stock CHashDefineStr *tmph assign-in-if HashFind ->
// HashLstAdd(tmph->data, ..., doldoc.hash) shape (Fs->hash_table walk).
#include "A:/Compiler/DolDocDefines.HC"
#define HTT_DEFINE_STR 0x4
#define DHT_DOC_CMD 1
#define DHT_DOC_FLAG 2
#define DHT_COLOR 4
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
import I64 HashFind(U8 *needle, I64 table, I64 mask);
import I64 HashTableNew(I64 size, I64 mem_task = 0);
import I64 HashLstAdd(U8 *lst, I64 type, I64 table);
// Soft tip lite layout: CHash(24)+CHashSrcSym(40)=64 so data matches stock offset.
class CHashDefineStr
{
  I64 next;
  U8 *str;
  U32 type;
  U32 use_cnt;
  U8 *src_link;
  U8 *idx;
  I64 dbg_info;
  U8 *import_name;
  I64 ie_lst;
  U8 *data;
  U8 **sub_idx;
  I64 cnt;
};

U0 DocInitRungB()
{
  CHashDefineStr *tmph;
  if (doldoc.hash && HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return;
  if (!doldoc.hash) {
    doldoc.hash = HashTableNew(512);
    if (!doldoc.hash)
      return;
  }
  if (tmph = HashFind("ST_DOC_CMDS", Fs->hash_table, HTT_DEFINE_STR))
    HashLstAdd(tmph->data, DHT_DOC_CMD, doldoc.hash);
  if (tmph = HashFind("ST_DOC_FLAGS", Fs->hash_table, HTT_DEFINE_STR))
    HashLstAdd(tmph->data, DHT_DOC_FLAG, doldoc.hash);
  if (tmph = HashFind("ST_COLORS", Fs->hash_table, HTT_DEFINE_STR))
    HashLstAdd(tmph->data, DHT_COLOR, doldoc.hash);
  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));
  doldoc.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
}

public I64 RVDocInitRungBSelfTest()
{
  DocInitRungB;
  if (!doldoc.hash)
    return 2;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 3;
  return 1;
}
