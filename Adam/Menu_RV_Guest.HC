#define MENU_RV_GUEST_HC 1
#define RV_MENU_ID_NONE 0
#define RV_MENU_ID_TILE_H 1
#define RV_MENU_ID_TILE_V 2
#define RV_MENU_ID_MAX 3
#define RV_MENU_ID_CLOSE 4
#define RV_MENU_ID_ABOUT 5
#define RV_MENU_ID_HELP 6
#define RV_MENU_ID_FORM 7
#define RV_MENU_ID_CTRLS 8
I64 rv_menu_personal_n;
public U0 RVMenuPersonalInit()
{
  rv_menu_personal_n = 8;
}

public I64 RVMenuPersonalCount()
{
  if (!rv_menu_personal_n)
    RVMenuPersonalInit;
  return rv_menu_personal_n;
}

public U8 *RVMenuPersonalName(I64 i)
{
  if (i == 0)
    return "TileHorz";
  if (i == 1)
    return "TileVert";
  if (i == 2)
    return "WinMax";
  if (i == 3)
    return "Close";
  if (i == 4)
    return "About";
  if (i == 5)
    return "Help";
  if (i == 6)
    return "FormDemo";
  if (i == 7)
    return "CtrlsDemo";
  return "";
}

public I64 RVMenuPersonalId(I64 i)
{
  if (i == 0)
    return RV_MENU_ID_TILE_H;
  if (i == 1)
    return RV_MENU_ID_TILE_V;
  if (i == 2)
    return RV_MENU_ID_MAX;
  if (i == 3)
    return RV_MENU_ID_CLOSE;
  if (i == 4)
    return RV_MENU_ID_ABOUT;
  if (i == 5)
    return RV_MENU_ID_HELP;
  if (i == 6)
    return RV_MENU_ID_FORM;
  if (i == 7)
    return RV_MENU_ID_CTRLS;
  return RV_MENU_ID_NONE;
}

public I64 RVMenuPersonalWidth()
{
  if (!rv_menu_personal_n)
    RVMenuPersonalInit;
  return 12;
}
import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
// Soft-planted Kernel product CMenuEntry/CMenu layout (Bool pad[6] / U8 pad[7]).
// Soft Cmp+Call of this shape greens (+cmenuboolpad+cmenuprod); product Soft tips
// MenuEntryWidth/MenuNewHand Soft Cmp+Call OK; MenuFpOk/MenuLexI64Soft/MenuNewSubCmp/
// MenuNewCmp/MenuNewCmpCtrl Soft Cmp OK
// (+prodentrywidth+menunewhand+menufpok+menulexi64soft+menunewsubcmp+menunewcmp+menunewcmpctrl;
// Soft Call FpOk/LexI64/NewSubCmp/NewCmp/NewCmpCtrl soft-skip). Soft PopUp/DocTerm Soft
// tip Soft Cmp+Call green (+popupsoft+popupsoftfp+popupsoftwinfp+popupsoftwinfpcall+doctermsoft). MENU_RV_GUEST_CMP still gates Guest
// chrome vs live WinMgr PopUp/DocTerm (drop after Soft Call + wrap without Guest).
class CRVLiteMenuEntry
{
  I64 next;
  I64 sub;
  U8 name[32];
  I64 msg_code;
  I64 arg1;
  I64 arg2;
  Bool checked, dir, pad[6];
};

class CRVLiteMenu
{
  I64 next;
  I64 sub;
  I64 task;
  I64 flags;
  U8 attr, pad[7];
};

public CRVLiteMenuEntry *RVMenuEntryNew(I64 id)
{
  CRVLiteMenuEntry *e;
  I64 n;
  n = sizeof(CRVLiteMenuEntry);
  e = CAlloc(n);
  if (!e)
    return 0;
  e->arg1 = id;
  return e;
}

public CRVLiteMenu *RVMenuNew(I64 flags)
{
  CRVLiteMenu *m;
  I64 n;
  n = sizeof(CRVLiteMenu);
  m = CAlloc(n);
  if (!m)
    return 0;
  m->flags = flags;
  return m;
}

public I64 RVMenuGuestSelfTest()
{
  CRVLiteMenu s;
  CRVLiteMenu *m;
  I64 f;
  I64 n;
  s.flags = 8;
  if (s.flags != 8)
    return 1;
  n = sizeof(CRVLiteMenu);
  if (n != 40)
    return 2;
  m = RVMenuNew(8);
  if (!m)
    return 3;
  if (m->flags != 8) {
    Free(m);
    return 4;
  }
  f = m->flags;
  Free(m);
  return f;
}

public I64 RVMenuEntrySelfTest()
{
  CRVLiteMenu *m;
  CRVLiteMenuEntry *e;
  CRVLiteMenuEntry *nx;
  CRVLiteMenuEntry *sb;
  I64 t;
  I64 n;
  n = sizeof(CRVLiteMenuEntry);
  if (n != 80)
    return 2;
  m = RVMenuNew(8);
  if (!m)
    return 3;
  e = RVMenuEntryNew(1);
  if (!e) {
    Free(m);
    return 3;
  }
  nx = RVMenuEntryNew(2);
  if (!nx) {
    Free(e);
    Free(m);
    return 3;
  }
  sb = RVMenuEntryNew(3);
  if (!sb) {
    Free(nx);
    Free(e);
    Free(m);
    return 3;
  }
  e->next = nx;
  e->sub = sb;
  m->sub = e;
  if (m->sub != e) {
    Free(sb);
    Free(nx);
    Free(e);
    Free(m);
    return 4;
  }
  if (e->next != nx) {
    Free(sb);
    Free(nx);
    Free(e);
    Free(m);
    return 5;
  }
  if (e->sub != sb) {
    Free(sb);
    Free(nx);
    Free(e);
    Free(m);
    return 6;
  }
  if (nx->arg1 != 2) {
    Free(sb);
    Free(nx);
    Free(e);
    Free(m);
    return 7;
  }
  if (sb->arg1 != 3) {
    Free(sb);
    Free(nx);
    Free(e);
    Free(m);
    return 9;
  }
  t = e->arg1 + nx->arg1 + sb->arg1;
  Free(sb);
  Free(nx);
  Free(e);
  Free(m);
  if (t != 6)
    return 10;
  return 8;
}

class CRVLiteDocEntry
{
  I64 next;
  I64 type;
  I64 data;
  I64 tag;
  I64 id;
};

class CRVLiteDoc
{
  I64 head;
  I64 last;
  I64 flags;
  I64 print_n;
};

public CRVLiteDocEntry *RVDocEntryNewLite(I64 type, I64 data, I64 tag)
{
  CRVLiteDocEntry *e;
  I64 n;
  n = sizeof(CRVLiteDocEntry);
  e = CAlloc(n);
  if (!e)
    return 0;
  e->type = type;
  e->data = data;
  e->tag = tag;
  return e;
}

public CRVLiteDoc *RVDocNewLite(I64 flags)
{
  CRVLiteDoc *doc;
  I64 n;
  n = sizeof(CRVLiteDoc);
  doc = CAlloc(n);
  if (!doc)
    return 0;
  doc->flags = flags;
  return doc;
}

public I64 RVDocPrintLite(CRVLiteDoc *doc, I64 type, I64 data, I64 tag)
{
  CRVLiteDocEntry *e;
  CRVLiteDocEntry *last;
  if (!doc)
    return 0;
  e = RVDocEntryNewLite(type, data, tag);
  if (!e)
    return 0;
  e->id = doc->print_n + 1;
  if (!doc->head) {
    doc->head = e;
    doc->last = e;
  } else {
    last = doc->last;
    if (last)
      last->next = e;
    doc->last = e;
  }
  doc->print_n = doc->print_n + 1;
  return doc->print_n;
}

public I64 RVDocGuestSelfTest()
{
  CRVLiteDoc *doc;
  CRVLiteDocEntry *e0;
  CRVLiteDocEntry *e1;
  I64 n;
  I64 t;
  doc = RVDocNewLite(8);
  if (!doc)
    return 3;
  if (doc->flags != 8) {
    Free(doc);
    return 4;
  }
  n = RVDocPrintLite(doc, 1, 2, 0);
  if (n != 1) {
    if (doc->head)
      Free(doc->head);
    Free(doc);
    return 5;
  }
  n = RVDocPrintLite(doc, 3, 4, 0);
  if (n != 2) {
    e0 = doc->head;
    if (e0) {
      if (e0->next)
        Free(e0->next);
      Free(e0);
    }
    Free(doc);
    return 6;
  }
  e0 = doc->head;
  if (!e0) {
    Free(doc);
    return 7;
  }
  if (e0->type != 1) {
    if (e0->next)
      Free(e0->next);
    Free(e0);
    Free(doc);
    return 9;
  }
  e1 = e0->next;
  if (!e1) {
    Free(e0);
    Free(doc);
    return 10;
  }
  if (e1->data != 4) {
    Free(e1);
    Free(e0);
    Free(doc);
    return 11;
  }
  t = e0->type + e1->type + doc->print_n;
  Free(e1);
  Free(e0);
  Free(doc);
  if (t != 6)
    return 12;
  return 8;
}

public I64 RVDocPrintSelfTest()
{
  CRVLiteDoc *doc;
  CRVLiteDocEntry *e0;
  CRVLiteDocEntry *e1;
  CRVLiteDocEntry *e2;
  CRVLiteDocEntry *last;
  I64 n;
  I64 t;
  doc = RVDocNewLite(1);
  if (!doc)
    return 3;
  n = RVDocPrintLite(doc, 1, 10, 100);
  if (n != 1) {
    if (doc->head)
      Free(doc->head);
    Free(doc);
    return 4;
  }
  n = RVDocPrintLite(doc, 2, 20, 200);
  if (n != 2) {
    e0 = doc->head;
    if (e0) {
      if (e0->next)
        Free(e0->next);
      Free(e0);
    }
    Free(doc);
    return 5;
  }
  n = RVDocPrintLite(doc, 3, 30, 300);
  if (n != 3) {
    e0 = doc->head;
    if (e0) {
      e1 = e0->next;
      if (e1) {
        if (e1->next)
          Free(e1->next);
        Free(e1);
      }
      Free(e0);
    }
    Free(doc);
    return 6;
  }
  e0 = doc->head;
  if (!e0) {
    Free(doc);
    return 7;
  }
  e1 = e0->next;
  if (!e1) {
    Free(e0);
    Free(doc);
    return 9;
  }
  e2 = e1->next;
  if (!e2) {
    Free(e1);
    Free(e0);
    Free(doc);
    return 10;
  }
  last = doc->last;
  if (last != e2) {
    Free(e2);
    Free(e1);
    Free(e0);
    Free(doc);
    return 11;
  }
  if (e0->id != 1) {
    Free(e2);
    Free(e1);
    Free(e0);
    Free(doc);
    return 12;
  }
  if (e1->tag != 200) {
    Free(e2);
    Free(e1);
    Free(e0);
    Free(doc);
    return 13;
  }
  if (e2->data != 30) {
    Free(e2);
    Free(e1);
    Free(e0);
    Free(doc);
    return 14;
  }
  t = e0->tag + e1->id + e2->type + doc->print_n;
  Free(e2);
  Free(e1);
  Free(e0);
  Free(doc);
  if (t != 108)
    return 15;
  return 8;
}

public I64 RVPopUpLite(CRVLiteDoc *doc)
{
  if (!doc)
    return 0;
  if (!doc->head)
    return 0;
  return doc->print_n;
}

public I64 RVPopUpOkLite(I64 tag)
{
  if (!tag)
    return 0;
  return 1;
}

public I64 RVPopUpGuestSelfTest()
{
  CRVLiteDoc *doc;
  CRVLiteDocEntry *e0;
  CRVLiteDocEntry *e1;
  I64 n;
  I64 r;
  doc = RVDocNewLite(1);
  if (!doc)
    return 3;
  n = RVDocPrintLite(doc, 1, 1, 0);
  if (n != 1) {
    Free(doc);
    return 4;
  }
  n = RVDocPrintLite(doc, 2, 1, 0);
  if (n != 2) {
    e0 = doc->head;
    if (e0) {
      if (e0->next)
        Free(e0->next);
      Free(e0);
    }
    Free(doc);
    return 5;
  }
  r = RVPopUpLite(doc);
  if (r != 2) {
    e0 = doc->head;
    if (e0) {
      if (e0->next)
        Free(e0->next);
      Free(e0);
    }
    Free(doc);
    return 6;
  }
  r = RVPopUpOkLite(7);
  if (r != 1) {
    e0 = doc->head;
    if (e0) {
      if (e0->next)
        Free(e0->next);
      Free(e0);
    }
    Free(doc);
    return 7;
  }
  e0 = doc->head;
  e1 = e0->next;
  Free(e1);
  Free(e0);
  Free(doc);
  return 8;
}

public I64 RVDocTermLite(CRVLiteDoc *doc)
{
  CRVLiteDocEntry *e;
  I64 i;
  I64 n;
  I64 units;
  if (!doc)
    return 0;
  n = doc->print_n;
  if (!n)
    return 0;
  e = doc->head;
  units = 0;
  for (i = 0; i < n; i++) {
    if (!e)
      return 0;
    units = units + 1;
    e = e->next;
  }
  return units;
}

public I64 RVDocTermSelfTest()
{
  CRVLiteDoc *doc;
  CRVLiteDocEntry *e0;
  CRVLiteDocEntry *e1;
  CRVLiteDocEntry *e2;
  CRVLiteDocEntry *last;
  I64 n;
  I64 units;
  I64 sum;
  doc = RVDocNewLite(1);
  if (!doc)
    return 3;
  n = RVDocPrintLite(doc, 1, 10, 100);
  if (n != 1) {
    if (doc->head)
      Free(doc->head);
    Free(doc);
    return 4;
  }
  n = RVDocPrintLite(doc, 2, 20, 200);
  if (n != 2) {
    e0 = doc->head;
    if (e0) {
      if (e0->next)
        Free(e0->next);
      Free(e0);
    }
    Free(doc);
    return 5;
  }
  n = RVDocPrintLite(doc, 3, 30, 300);
  if (n != 3) {
    e0 = doc->head;
    if (e0) {
      e1 = e0->next;
      if (e1) {
        if (e1->next)
          Free(e1->next);
        Free(e1);
      }
      Free(e0);
    }
    Free(doc);
    return 6;
  }
  units = RVDocTermLite(doc);
  if (units != 3) {
    e0 = doc->head;
    if (e0) {
      e1 = e0->next;
      if (e1) {
        if (e1->next)
          Free(e1->next);
        Free(e1);
      }
      Free(e0);
    }
    Free(doc);
    return 7;
  }
  e0 = doc->head;
  if (!e0) {
    Free(doc);
    return 9;
  }
  e1 = e0->next;
  if (!e1) {
    Free(e0);
    Free(doc);
    return 10;
  }
  e2 = e1->next;
  if (!e2) {
    Free(e1);
    Free(e0);
    Free(doc);
    return 11;
  }
  last = doc->last;
  if (last != e2) {
    Free(e2);
    Free(e1);
    Free(e0);
    Free(doc);
    return 12;
  }
  sum = e0->type + e0->data + e0->tag;
  sum = sum + e1->type + e1->data + e1->tag;
  sum = sum + e2->type + e2->data + e2->tag;
  if (sum != 666) {
    Free(e2);
    Free(e1);
    Free(e0);
    Free(doc);
    return 13;
  }
  Free(e2);
  Free(e1);
  Free(e0);
  Free(doc);
  return 8;
}
