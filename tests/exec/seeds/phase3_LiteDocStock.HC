import U8 *DocNew(U8 *filename);
import U0 DocDel(U8 *doc);
public I64 RVDocStockSelfTest()
{
  U8 *doc;
  doc=DocNew("LITE.DD");
  if (!doc)
    return 3;
  DocDel(doc);
  return 8;
}
