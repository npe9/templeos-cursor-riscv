import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);
I64 StoreFwCount()
{
  return 8;
}
public I64 AdamLiteStoreFwProbe()
{
  I64 n;
  n=StoreFwCount;
  FileWrite("A:/Adam/STOREFW.TXT","STOREFW",7);
  return n;
}
