// Soft tip: Soft #include unmodified stock DocInit_RV (Kernel doldoc via Soft plant).
// Soft AOT: WireAsmHash plants CDolDocGlbls+doldoc abs addr into asm_hash (no Soft-local
// doldoc shadow). Soft prelude: DolDocDefines + DHT_* + imports + CHashDefineStr lite.
#include "A:/Compiler/DolDocDefines.HC"
#define HTT_DEFINE_STR 0x4
#define DHT_DOC_CMD 1
#define DHT_DOC_FLAG 2
#define DHT_COLOR 4
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
import Bool Bt(U8 *bf, I64 n);
import Bool Bts(U8 *bf, I64 n);
import I64 DefineLoad(U8 *dname, U8 *st);
import I64 DefineLstLoad(U8 *dname, U8 *lst);
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
#include "A:/Compiler/DocInit_RV_Stock.HC"
public I64 RVDocInitStockSelfTest()
{
  DocInit;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 0;
  if (!doldoc.hash)
    return 2;
  if (!HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return 3;
  return 1;
}
