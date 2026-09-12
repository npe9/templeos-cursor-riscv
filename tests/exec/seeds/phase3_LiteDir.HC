import Bool DirMk(U8 *filename,I64 entry_cnt=0);
import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);
public I64 AdamLiteDirProbe()
{
  DirMk("A:/Adam");
  FileWrite("A:/Adam/DIRMK.TXT","ok",2);
  return 1;
}
