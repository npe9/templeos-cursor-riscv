// DocCollapse and DocRemSoftNewLines do their work, not merely resolve.
//
// Both were unresolved imports taking a stub that returns 0: DocCollapse from
// Adam/DolDoc/DocRecalcLib.HC and DocRemSoftNewLines from Adam/DolDoc/DocNew.HC, neither of which
// Kernel_RV.PRJ can include (they redefine six and seven names Kernel/RVDoc.HC defines). Both are
// U0, so unlike DocSplitTag their stubs could not trap — they were quiet wrongness:
// Adam/DolDoc/DocLink.HC:123,125 could not collapse a tree widget on link activation, and
// DocFind.HC:514 left stale DOCT_SOFT_NEW_LINE entries after an interactive per-hit replace.
//
// A U0 gives nothing to compare, so each assertion is a STATE CHANGE the stub cannot produce:
// DOCEf_CHECKED_COLLAPSED appearing and then clearing on a DOCEF_TREE entry, and a hand-inserted
// DOCT_SOFT_NEW_LINE entry being gone from the stream afterwards.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  CDoc *doc;
  CDocEntry *doc_e, *tree_e, *soft_e;
  I64 set = 0, cleared = 0, soft_before = 0, soft_after = 0;
  RVKernelInit();
  doc = DocNew();
  if (!doc)
    return 0;
  DocPutS(doc, "alpha\n");
  // A tree entry for DocCollapse to flip.
  // DOCEF_TAG + StrNew, not a string literal: RVDoc.HC has unguarded Free(doc_e->tag) sites (2499,
  // 3554) and DocEntryDel frees tag under DOCEF_TAG, so an entry in the permanent manifest must own
  // a heap tag. Neither of those sites is reachable for a DOCT_TEXT entry today; this is about not
  // leaving a literal where the surrounding code treats tag as allocated.
  tree_e = DocEntryNewBase(doc, DOCT_TEXT, DOCEF_TREE | DOCEF_TAG, 0, 0, 0);
  tree_e->tag = StrNew("tree", doc->mem_task);
  QueIns(tree_e, doc->head.last);
  DocCollapse(TRUE, doc);
  set = Bt(&tree_e->de_flags, DOCEf_CHECKED_COLLAPSED) != 0;
  DocCollapse(FALSE, doc);
  cleared = Bt(&tree_e->de_flags, DOCEf_CHECKED_COLLAPSED) == 0;
  // A soft newline for DocRemSoftNewLines to remove.
  soft_e = DocEntryNewBase(doc, DOCT_SOFT_NEW_LINE, 0, 0, 0, 0);
  QueIns(soft_e, doc->head.last);
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_SOFT_NEW_LINE)
      soft_before++;
    doc_e = doc_e->next;
  }
  DocRemSoftNewLines(doc, NULL);
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_SOFT_NEW_LINE)
      soft_after++;
    doc_e = doc_e->next;
  }
  return set * 1 + cleared * 2 + (soft_before == 1) * 4 + (soft_after == 0) * 8;
  // 0xf
}
