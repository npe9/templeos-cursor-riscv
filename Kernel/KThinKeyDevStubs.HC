// KThinKeyDevStubs.HC — RV_THIN_LOADER: UART StdOut chain only (no Ctrl-Alt map).
// Full KeyDev.HC (~6 KiB) stays out; Print → PutS → KeyDevAdd(RVConsole*).
// SoftCall KeyDevSoft owns real PutKey/PutS priority + CtrlAltCBSet in Kernel.BIN.
#ifndef K_THIN_KEYDEV_STUBS_HC
#define K_THIN_KEYDEV_STUBS_HC
U0 PutKey(I64 ch = 0, I64 sc = 0)
{
  CKeyDevEntry *tmpk;
  if (ch || sc) {
    tmpk = keydev.put_key_head.next;
    if (!Bt(&Fs->display_flags, DISPLAYf_SILENT)) {
      while (tmpk != &keydev.put_key_head) {
        if ((!(sc & SCF_KEY_DESC) || tmpk->flags & KDF_HAS_DESCS) && (*tmpk->put_key)(ch, sc))
          break;
        tmpk = tmpk->next;
      }
    }
  }
}

U0 PutChars(U64 ch)
{
  while (ch) {
    PutKey(ch & 255, 0);
    ch >>= 8;
  }
}

U0 PutS(U8 *st)
{
  I64 ch;
  U8 *ptr;
  Bool cont = TRUE;
  CKeyDevEntry *tmpk;
  if (!st)
    return;
  tmpk = keydev.put_key_head.next;
  if (!Bt(&Fs->display_flags, DISPLAYf_SILENT)) {
    while (cont && tmpk != &keydev.put_key_head) {
      if (tmpk->put_s) {
        if ((*tmpk->put_s)(st))
          break;
      } else {
        ptr = st;
        while (ch = *ptr++)
          if ((*tmpk->put_key)(ch, 0))
            cont = FALSE;
      }
      tmpk = tmpk->next;
    }
  }
}

U0 KeyDescSet(U8 *fmt,...)
{
  no_warn fmt;
}

U0 KeyDevRem(CKeyDevEntry *tmpk)
{
  if (!tmpk)
    return;
  QueRem(tmpk);
  Free(tmpk);
}

CKeyDevEntry *KeyDevAdd(Bool (*fp_put_key)(I64 ch, I64 sc), Bool (*fp_puts)(U8 *st), I64 priority, Bool key_descs = FALSE)
{
  CKeyDevEntry *tmpk = keydev.put_key_head.last, *tmpk1 = ACAlloc(sizeof(CKeyDevEntry));
  if (!tmpk1)
    return NULL;
  tmpk1->put_key = fp_put_key;
  tmpk1->put_s = fp_puts;
  tmpk1->priority = priority;
  if (key_descs)
    tmpk1->flags |= KDF_HAS_DESCS;
  while (tmpk != &keydev.put_key_head && tmpk->priority > priority)
    tmpk = tmpk->last;
  QueIns(tmpk1, tmpk);
  return tmpk1;
}

U0 KeyDevCtrlAltInit()
{
}

U0 KeyDevInit()
{
}

U0 CtrlAltCBSet(U8 ch, U0 (*fp_hndlr)(I64 sc), U8 *no_shift_desc = NULL, U8 *shift_desc = NULL, Bool in_irq = FALSE)
{
  no_warn ch;
  no_warn fp_hndlr;
  no_warn no_shift_desc;
  no_warn shift_desc;
  no_warn in_irq;
}
#endif
