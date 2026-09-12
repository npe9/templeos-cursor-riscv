#include "A:/Compiler/Menu_RV"
import I64 FileWrite(U8 *filename, U8 *fbuf, I64 size);
public I64 AdamRVLiteInit()
{
  RVMenuPersonalInit;
  FileWrite("A:/Adam/LITE.TXT", "MakeAdam_RV_Lite", 16);
  return 8;
}
