import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
#define RV_SOFT_DOC_SIG 0x44524356
class CRVSoftDoc
{
  I64 sig;
  I64 max_entries;
  I64 desc;
};
I64 g_put_doc;
I64 g_display_doc;
I64 g_border_doc;
I64 g_border_src;
CRVSoftDoc *SoftDocNew()
{
  CRVSoftDoc *doc;
  doc = CAlloc(sizeof(CRVSoftDoc));
  if (!doc)
    return 0;
  doc->sig = RV_SOFT_DOC_SIG;
  doc->max_entries = 0;
  doc->desc = 0;
  return doc;
}

CRVSoftDoc *SoftDocBorderNew(CRVSoftDoc *doc)
{
  CRVSoftDoc *b;
  if (!doc || doc->sig != RV_SOFT_DOC_SIG)
    return 0;
  b = SoftDocNew;
  if (!b)
    return 0;
  b->desc = 'Bord';
  b->max_entries = 1;
  return b;
}

I64 SoftDocTermWire(CRVSoftDoc *doc)
{
  CRVSoftDoc *bdoc;
  I64 old_put;
  I64 old_disp;
  I64 old_border;
  I64 old_bsrc;
  if (!doc || doc->sig != RV_SOFT_DOC_SIG)
    return 3;
  old_put = g_put_doc;
  old_disp = g_display_doc;
  old_border = g_border_doc;
  old_bsrc = g_border_src;
  g_put_doc = doc;
  g_display_doc = doc;
  g_border_src = 1;
  bdoc = SoftDocBorderNew(doc);
  if (!bdoc) {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    return 5;
  }
  g_border_doc = bdoc;
  if (g_put_doc != doc || g_display_doc != doc) {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    Free(bdoc);
    return 6;
  }
  if (g_border_doc != bdoc || bdoc->desc != 'Bord') {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    Free(bdoc);
    return 7;
  }
  g_put_doc = old_put;
  g_display_doc = old_disp;
  g_border_doc = old_border;
  g_border_src = old_bsrc;
  Free(bdoc);
  return 8;
}

I64 SoftDocTermNewSoft()
{
  CRVSoftDoc *pdoc;
  CRVSoftDoc *bdoc;
  I64 old_put;
  I64 old_disp;
  I64 old_border;
  I64 old_bsrc;
  old_put = g_put_doc;
  old_disp = g_display_doc;
  old_border = g_border_doc;
  old_bsrc = g_border_src;
  pdoc = SoftDocNew;
  if (!pdoc || pdoc->sig != RV_SOFT_DOC_SIG)
    return 3;
  pdoc->max_entries = 4096;
  pdoc->desc = 'Term';
  g_border_src = 1;
  g_put_doc = pdoc;
  g_display_doc = pdoc;
  bdoc = SoftDocBorderNew(pdoc);
  if (!bdoc) {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    Free(pdoc);
    return 5;
  }
  g_border_doc = bdoc;
  if (g_put_doc != pdoc || pdoc->desc != 'Term' || pdoc->max_entries != 4096) {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    Free(bdoc);
    Free(pdoc);
    return 6;
  }
  if (g_display_doc != pdoc) {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    Free(bdoc);
    Free(pdoc);
    return 7;
  }
  if (g_border_doc != bdoc || bdoc->desc != 'Bord') {
    g_put_doc = old_put;
    g_display_doc = old_disp;
    g_border_doc = old_border;
    g_border_src = old_bsrc;
    Free(bdoc);
    Free(pdoc);
    return 9;
  }
  g_put_doc = old_put;
  g_display_doc = old_disp;
  g_border_doc = old_border;
  g_border_src = old_bsrc;
  Free(bdoc);
  Free(pdoc);
  return 8;
}

public I64 RVDocTermSoftSelfTest()
{
  CRVSoftDoc *doc;
  I64 r;
  g_put_doc = 0;
  g_display_doc = 0;
  g_border_doc = 0;
  g_border_src = 0;
  doc = SoftDocNew;
  if (!doc)
    return 2;
  r = SoftDocTermWire(doc);
  Free(doc);
  if (r != 8)
    return r;
  return SoftDocTermNewSoft;
}
