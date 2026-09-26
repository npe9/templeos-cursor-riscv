// EdReplace() — DolDoc find-and-replace — runs without trapping, and actually replaces.
//
// It reaches Adam/DolDoc/DocFind.HC:463, which does
//     doc_e = doc_marker = DocSplitTag(doc, doc->cur_entry, ...);
//     do { if (doc_e==doc) ... else doc_e->...
// so DocSplitTag's result is DEREFERENCED. DocSplitTag lives in Adam/DolDoc/DocRecalc.HC, a unit
// Kernel_RV.PRJ cannot include (it also defines DocRecalc, which Kernel/RVDoc.HC defines, and the
// later body wins silently), so the name was an unresolved import and bootstrap/holy_rt.h wrote a
// stub returning 0 into the slot. A 0 there is not a silent no-op — it is a null dereference.
// DocSplitTag is now lifted verbatim into Kernel/RVDoc.HC.
//
// EdReplace is the non-interactive door in: it sets find_replace->pmt=FALSE and calls
// EdFindReplace directly, so no popup is involved.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  CDoc *doc;
  CDocEntry *doc_e;
  I64 n = -1, saw_bar = 0, saw_foo = 0;
  RVKernelInit();
  doc = DocNew();
  if (!doc)
    return 0;
  DocPutS(doc, "alpha Foo omega\n");
  doc->cur_entry = doc->head.next;
  doc->cur_col = 0;
  n = EdReplace(doc, "Foo", "Bar", FALSE);
  // Walk the entry stream and look at what the text entries now say.
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_TEXT && doc_e->tag) {
      if (StrFind("Bar", doc_e->tag))
        saw_bar = 1;
      if (StrFind("Foo", doc_e->tag))
        saw_foo = 1;
    }
    doc_e = doc_e->next;
  }
  return (n >= 0) * 1 + saw_bar * 2 + (!saw_foo) * 4 + 8;
  // 0xf — the 8 is "EdReplace returned at all", which is the trap assertion
}
