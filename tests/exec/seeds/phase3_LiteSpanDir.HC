import Bool DirMk(U8 *filename,I64 entry_cnt=0);
import I64 FileWrite(U8 *filename,U8 *fbuf,I64 size);
public I64 AdamLiteSpanDirProbe()
{
  DirMk("A:/Span");
  FileWrite("A:/Span/GAME.TXT","SPAN",4);
  return 1;
}
