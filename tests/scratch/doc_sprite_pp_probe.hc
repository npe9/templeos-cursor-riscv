// Focused DocSpriteIns stock cur_bin_num++ as MStrPrint vararg (no DrawIt).
#include "/Kernel/Kernel_RV.PRJ"

I64 main()
{
  CDoc *doc;
  CDocEntry *se;
  U8 elems[8];
  I64 r = 0, before, after;
  MemSet(elems, 0, 8);
  elems[0] = 1;
  // SPT end
  elems[1] = 0;
  doc = DocNew;
  if (!doc)
    return 0;
  before = doc->cur_bin_num;
  after = doc->max_entries;
  se = DocSpriteIns(doc, elems, "$$SP,\"\",LM=\"z\",BI=%d$$");
  r += (!!se) * 1;
  r += (se && (se->de_flags & DOCEF_HAS_BIN)) * 2;
  r += (se && (se->de_flags & DOCEF_LEFT_MACRO)) * 4;
  r += (doc->cur_bin_num == before + 1) * 8;
  r += (doc->max_entries == after) * 16;
  r += (se && se->bin_num == before) * 32;
  DocDel(doc);
  return r;
  // expect 0x3F when SpriteIns + typed member++ vararg are healthy
}
