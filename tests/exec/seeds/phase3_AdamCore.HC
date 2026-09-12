import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);
public I64 AdamRVCoreInit()
{
  FileWrite("A:/Adam/READY.TXT","Adam",4);
  FileWrite("A:/Adam/CORE.TXT","MakeAdam_RV_Core",16);
  return 1;
}
