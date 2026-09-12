// Soft tip: HashTableNew + HashLstAdd Soft Call (stock DocInit hash warm).
// Soft Call HashFind after Soft CALL_IMPORT remats ht wrong (r=3) — Soft Call
// HashLstAdd return count only. Soft Cmp of HashFind stays Soft Cmp-only tips.
#define DHT_DOC_CMD 1
import I64 HashTableNew(I64 size, I64 mem_task);
import I64 HashLstAdd(U8 *lst, I64 type, I64 table);
public I64 AdamLiteDocInitHashLstAddProbe()
{
  I64 ht;
  I64 n;
  ht = HashTableNew(16, 0);
  if (!ht)
    return 2;
  n = HashLstAdd("TX", DHT_DOC_CMD, ht);
  if (n < 1)
    return 3;
  return 1;
}
