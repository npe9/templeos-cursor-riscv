import U8 *DocNew(U8 *filename);
import U0 DocDel(U8 *doc);
import U8 *DocPrintF(U8 *doc,U8 *fmt,I64 a);
import I64 DocSize(U8 *doc);
import I64 RVDocTermWire(U8 *doc);
public I64 RVDocTermStockSelfTest()
{
  U8 *doc;
  I64 n0;
  I64 r;
  doc=DocNew("TERM.DD");
  if (!doc)
    return 3;
  n0=DocSize(doc);
  DocPrintF(doc,"%d",8);
  if (DocSize(doc)<=n0) {
    DocDel(doc);
    return 4;
  }
  r=RVDocTermWire(doc);
  DocDel(doc);
  return r;
}
