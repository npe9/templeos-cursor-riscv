import U8 *DocNew(U8 *filename);
import U0 DocDel(U8 *doc);
import U8 *DocPrintF(U8 *doc,U8 *fmt,I64 a);
import I64 DocSize(U8 *doc);
public I64 RVDocPrintStockSelfTest()
{
  U8 *doc;
  I64 n0;
  I64 n1;
  doc=DocNew("LITE.DD");
  if (!doc)
    return 3;
  n0=DocSize(doc);
  DocPrintF(doc,"%d",8);
  n1=DocSize(doc);
  if (n1<=n0) {
    DocDel(doc);
    return 4;
  }
  DocDel(doc);
  return 8;
}
