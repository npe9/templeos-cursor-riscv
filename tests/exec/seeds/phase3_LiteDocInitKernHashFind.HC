// Soft tip: Soft HashFind into Kernel doldoc.hash via RVDocDolDocHashGet (no Soft doldoc glbl).
#define DHT_DOC_CMD 1
import I64 RVDocDolDocHashGet();
import I64 HashFind(U8 *needle, I64 table, I64 mask);
public I64 AdamLiteDocInitKernHashFindProbe()
{
  I64 ht;
  ht = RVDocDolDocHashGet();
  if (!ht)
    return 2;
  if (!HashFind("TX", ht, DHT_DOC_CMD))
    return 3;
  return 1;
}
