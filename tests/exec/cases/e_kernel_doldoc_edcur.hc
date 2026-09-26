// EdCurU8 returns the character under the cursor, and EdGoToFun TERMINATES.
//
// Both were broken in a way no test could see. Adam/DolDoc/DocChar.HC was not in Kernel_RV.PRJ, so
// EdCurU8/EdCursorLeft/EdCursorRight were unresolved imports and bootstrap/holy_rt.h wrote a stub
// returning 0 into each slot. Two separate consequences:
//
//   * EdCurU8 is an ACCESSOR. Stock returns -1 when the entry is not text, never 0, so 0 is not
//     even a value it can produce — and every `EdCurU8(doc)==':'` in Adam/DolDoc/DocFind.HC was
//     false, which is exactly abort_on_dbl_colon, DolDoc's `Func::` dig-down.
//   * EdCursorRight is what advances doc->cur_entry, and EdGoToFun's loop is
//     `while (doc->cur_entry!=doc) { ... EdCursorRight(doc); }`. A no-op there is not a degraded
//     search, it is an INFINITE LOOP. This case running to completion at all is the assertion;
//     the harness QEMU timeout is what would catch a regression.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  CDoc *doc;
  CDocEntry *doc_e;
  I64 ch = -2, second = -2, moved = 0;
  RVKernelInit();
  doc = DocNew();
  if (!doc)
    return 0;
  DocPutS(doc, "I64 Foo()\n");
  // First text entry, cursor at its first column.
  doc_e = doc->head.next;
  while (doc_e != doc && doc_e->type_u8 != DOCT_TEXT)
    doc_e = doc_e->next;
  if (doc_e == doc)
    return 0;
  doc->cur_entry = doc_e;
  doc->cur_col = doc_e->min_col;
  ch = EdCurU8(doc);                  // 'I'
  EdCursorRight(doc);
  second = EdCurU8(doc);              // '6'
  moved = doc->cur_entry != doc_e || doc->cur_col != doc_e->min_col;
  // Termination, not a value: with a no-op EdCursorRight this never returns.
  EdGoToFun(doc, TRUE, TRUE);
  return (ch == 'I') * 1 + (second == '6') * 2 + (moved != 0) * 4 + 8;
  // 0xf — the 8 is "EdGoToFun returned"
}
