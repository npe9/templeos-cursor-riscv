// Soft tip: Soft g_doldoc.hash = HashTableNew + HashLstAdd Soft Call.
// Soft glbl != Kernel doldoc (Soft Call Load would shadow Fs). Soft Call early
// (+docinithash): Soft Call HashLstAdd return-count only — Soft Call HashFind
// after Soft CALL_IMPORT remats g_doldoc.hash Soft-fail r=3 (same IC_BODY_SIZE
// Soft Call remat class as local ht Soft tip).
#define DHT_DOC_CMD 1
import I64 HashTableNew(I64 size, I64 mem_task);
import I64 HashLstAdd(U8 *lst, I64 type, I64 table);
class CDocInitSoftHash
{
  I64 hash;
};
CDocInitSoftHash g_doldoc;
public I64 AdamLiteDocInitHashProbe()
{
  I64 n;
  if (!g_doldoc.hash)
    g_doldoc.hash = HashTableNew(16, 0);
  if (!g_doldoc.hash)
    return 2;
  n = HashLstAdd("TX\0CR\0", DHT_DOC_CMD, g_doldoc.hash);
  if (n < 1)
    return 3;
  return 1;
}
