// Soft tip rung A of the stock DocInit_RV Soft Cmp bisect ladder.
// Kernel doldoc (WireAsmHash CDolDocGlbls plant) + stock warm-path early
// return + HashTableNew + MemSet + plain indexed dft_de_flags plants.
// Rungs B/C/D add tmph assign-in-if, DefineLstLoad NUL literals, and the big
// shift-or chains; rung E is the unmodified stock #include.
#include "A:/Compiler/DolDocDefines.HC"
#define HTT_DEFINE_STR 0x4
#define DHT_DOC_CMD 1
#define DHT_DOC_FLAG 2
#define DHT_COLOR 4
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
import I64 HashFind(U8 *needle, I64 table, I64 mask);
import I64 HashTableNew(I64 size, I64 mem_task = 0);
U0 DocInitRungA()
{
  if (doldoc.hash && HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return;
  if (!doldoc.hash) {
    doldoc.hash = HashTableNew(512);
    if (!doldoc.hash)
      return;
  }
  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));
  MemSet(doldoc.dft_type_flags, 0, sizeof(doldoc.dft_type_flags));
  doldoc.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_LINK] = DOCEF_LINK | DOCEF_UNDERLINE | DOCEF_TAG;
  doldoc.dft_type_flags[DOCT_LINK] = DOCET_UNDERLINE;
}

public I64 RVDocInitRungASelfTest()
{
  DocInitRungA;
  if (!doldoc.hash)
    return 2;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 3;
  return 1;
}
