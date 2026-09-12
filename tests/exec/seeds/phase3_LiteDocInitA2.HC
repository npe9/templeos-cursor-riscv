// Soft tip micro-rung A2: A1 + write to Kernel doldoc.hash via imported HashTableNew.
import I64 HashTableNew(I64 size, I64 mem_task = 0);
public I64 RVDocInitA2SelfTest()
{
  if (!doldoc.hash)
    doldoc.hash = HashTableNew(512);
  if (!doldoc.hash)
    return 2;
  return 1;
}
