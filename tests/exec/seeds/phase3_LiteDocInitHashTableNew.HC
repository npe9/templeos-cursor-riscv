// Soft tip: HashTableNew Soft Call (stock DocInit doldoc.hash = HashTableNew(512)).
// Soft import must pass mem_task=0 -- 1-arg import leaves a1 garbage -> CAlloc hang.
import I64 HashTableNew(I64 size, I64 mem_task);
public I64 AdamLiteDocInitHashTableNewProbe()
{
  I64 ht;
  ht = HashTableNew(16, 0);
  if (!ht)
    return 2;
  return 1;
}
