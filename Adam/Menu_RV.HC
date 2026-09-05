// Menu_RV.HC — Adam MenuNew/MenuFile shape for RISC-V WinMgr (P3).
// Builds real CMenu/CMenuEntry trees via budgeted hand Lex (smoke SoT).
// MenuNewCmpCtrl uses soft-I64 CmpCtrl Lex when fps are absolute code addrs
// (RVCmpCtrlAddrsGet from Compiler unit). Kernel &CmpCtrlNew GOT is unsafe on
// split-AOT (illegal insn ≈0x8098 truncated ptr) — wire via WireCmpCtrlAddrs.
// About (RV_MENU_ID_ABOUT) → WinMgr PopUp (Job.HC fp_popup / PopUp_RV Spawn).
#ifndef MENU_RV_HC
#define MENU_RV_HC
// Guest Cmp (phase3 A:): PersonalMenu + Width via Menu_RV_Guest; wrap folds
// Guest_Lex before Guest (MENU_RV_GUEST_LEX_HC). No CMenu/CmpCtrl yet.
#ifdef MENU_RV_GUEST_CMP
#include "Menu_RV_Guest"
#else
#define RV_MENU_ID_NONE     0
#define RV_MENU_ID_TILE_H   1
#define RV_MENU_ID_TILE_V   2
#define RV_MENU_ID_MAX      3
#define RV_MENU_ID_CLOSE    4
#define RV_MENU_ID_ABOUT    5
#define RV_MENU_ID_HELP     6
#define RV_MENU_ID_FORM     7
#define RV_MENU_ID_CTRLS    8
#define RV_MENU_MAX         16
#define RV_MENU_NAME_MAX    24
#define RV_MENU_LEX_MAX_STEPS 2048
class CRVMenuEntry
{
  U8 name[RV_MENU_NAME_MAX];
  I64 id;
};
CRVMenuEntry rv_menu_personal[RV_MENU_MAX];
I64 rv_menu_personal_n;
I64 rv_menu_lex_hits;
I64 rv_menu_cmp_hits;
I64 rv_menu_cmp_soft_i64;
I64 rv_menu_src_embedded;
I64 rv_menu_lex_steps;
I64 rv_menu_lex_abort;
CMenu *rv_menu_cur;
// Optional CmpCtrl path (wired by interactive after CInit; NULL on Kernel-only smoke).
CCmpCtrl * (*rv_fp_CmpCtrlNew)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL);
I64 (*rv_fp_Lex)(CCmpCtrl *cc);
I64 (*rv_fp_LexExpressionI64)(CCmpCtrl *cc);
// kept for wire ABI; MenuNewSub soft-avoids Call
U0 (*rv_fp_CmpCtrlDel)(CCmpCtrl *cc);
Bool RVMenuFpOk(I64 fp)
{
  //Reject NULL / odd / halfword-trunc stubs (crash was insn@mepc=0x8098).
  if (!fp)
    return FALSE;
  if (fp & 1)
    return FALSE;
  // QEMU virt + harness text lives above DRAM base; reject tiny truncated vals.
  if (fp < 0x80000000)
    return FALSE;
  return TRUE;
}

Bool RVMenuFpsWired()
{
  //Safe readiness — non-NULL and look like real RV code pointers.
  return RVMenuFpOk(rv_fp_CmpCtrlNew) && RVMenuFpOk(rv_fp_Lex) && RVMenuFpOk(rv_fp_CmpCtrlDel);
}

U0 RVMenuTableLoad()
{
  I64 i = 0;
  rv_menu_personal_n = 0;
  StrCpy(rv_menu_personal[i].name, "TileHorz");
  rv_menu_personal[i++].id = RV_MENU_ID_TILE_H;
  StrCpy(rv_menu_personal[i].name, "TileVert");
  rv_menu_personal[i++].id = RV_MENU_ID_TILE_V;
  StrCpy(rv_menu_personal[i].name, "WinMax");
  rv_menu_personal[i++].id = RV_MENU_ID_MAX;
  StrCpy(rv_menu_personal[i].name, "Close");
  rv_menu_personal[i++].id = RV_MENU_ID_CLOSE;
  StrCpy(rv_menu_personal[i].name, "About");
  rv_menu_personal[i++].id = RV_MENU_ID_ABOUT;
  StrCpy(rv_menu_personal[i].name, "Help");
  rv_menu_personal[i++].id = RV_MENU_ID_HELP;
  StrCpy(rv_menu_personal[i].name, "FormDemo");
  rv_menu_personal[i++].id = RV_MENU_ID_FORM;
  StrCpy(rv_menu_personal[i].name, "CtrlsDemo");
  rv_menu_personal[i++].id = RV_MENU_ID_CTRLS;
  rv_menu_personal_n = i;
  rv_menu_src_embedded = 1;
}

I64 RVMenuIdFromName(U8 *name)
{
  if (!name)
    return RV_MENU_ID_NONE;
  if (!StrCmp(name, "TileHorz"))
    return RV_MENU_ID_TILE_H;
  if (!StrCmp(name, "TileVert"))
    return RV_MENU_ID_TILE_V;
  if (!StrCmp(name, "WinMax"))
    return RV_MENU_ID_MAX;
  if (!StrCmp(name, "Close"))
    return RV_MENU_ID_CLOSE;
  if (!StrCmp(name, "About"))
    return RV_MENU_ID_ABOUT;
  if (!StrCmp(name, "Help"))
    return RV_MENU_ID_HELP;
  if (!StrCmp(name, "FormDemo"))
    return RV_MENU_ID_FORM;
  if (!StrCmp(name, "CtrlsDemo"))
    return RV_MENU_ID_CTRLS;
  return RV_MENU_ID_NONE;
}

U0 MenuDelSub(CMenuEntry *tmpme)
{
  CMenuEntry *tmpse, *tmpse1;
  if (!tmpme)
    return;
  tmpse = tmpme->sub;
  while (tmpse) {
    tmpse1 = tmpse->next;
    MenuDelSub(tmpse);
    tmpse = tmpse1;
  }
  Free(tmpme);
}

public U0 MenuDel(CMenu *m)
{
  CMenuEntry *tmpme, *tmpme1;
  if (!m)
    return;
  if (rv_menu_cur == m)
    rv_menu_cur = NULL;
  tmpme = m->sub;
  while (tmpme) {
    tmpme1 = tmpme->next;
    MenuDelSub(tmpme);
    tmpme = tmpme1;
  }
  Free(m);
}

U0 RVMenuFlattenLeaves(CMenuEntry *tmpme)
{
  CMenuEntry *tmpse;
  I64 id;
  while (tmpme && rv_menu_personal_n < RV_MENU_MAX) {
    if (tmpme->dir) {
      tmpse = tmpme->sub;
      while (tmpse && rv_menu_personal_n < RV_MENU_MAX) {
        if (!tmpse->dir) {
          StrCpy(rv_menu_personal[rv_menu_personal_n].name, tmpse->name);
          id = RVMenuIdFromName(tmpse->name);
          if (id == RV_MENU_ID_NONE && tmpse->arg1 > 0)
            id = tmpse->arg1;
          rv_menu_personal[rv_menu_personal_n].id = id;
          rv_menu_personal_n++;
        } else
          RVMenuFlattenLeaves(tmpse);
        tmpse = tmpse->next;
      }
    } else {
      StrCpy(rv_menu_personal[rv_menu_personal_n].name, tmpme->name);
      id = RVMenuIdFromName(tmpme->name);
      if (id == RV_MENU_ID_NONE && tmpme->arg1 > 0)
        id = tmpme->arg1;
      rv_menu_personal[rv_menu_personal_n].id = id;
      rv_menu_personal_n++;
    }
    tmpme = tmpme->next;
  }
}

U0 RVMenuSyncFlat(CMenu *m)
{
  rv_menu_personal_n = 0;
  if (!m) {
    RVMenuTableLoad;
    return;
  }
  RVMenuFlattenLeaves(m->sub);
  if (rv_menu_personal_n <= 0)
    RVMenuTableLoad;
}
// ---- Budgeted hand Lex (smoke-safe; same grammar as MenuNewSub) ----
Bool RVMenuLexOk()
{
  rv_menu_lex_steps++;
  if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
    rv_menu_lex_abort = 1;
    return FALSE;
  }
  return TRUE;
}

U8 *RVMenuSkip(U8 *p)
{
  while (p && *p && RVMenuLexOk()) {
    if (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
      p++;
      continue;
    }
    break;
  }
  return p;
}

U8 *RVMenuReadIdent(U8 *p, U8 *out, I64 max)
{
  I64 n = 0;
  p = RVMenuSkip(p);
  if (!p || !out || max < 2) {
    if (out && max > 0)
      out[0] = 0;
    return p;
  }
  out[0] = 0;
  if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || *p == '_'))
    return p;
  while (*p && n < max - 1 && RVMenuLexOk()) {
    if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_'))
      break;
    out[n++] = *p++;
  }
  out[n] = 0;
  return p;
}

U8 *RVMenuReadI64(U8 *p, I64 *out)
{
  I64 v = 0;
  p = RVMenuSkip(p);
  if (!out)
    return p;
  *out = 0;
  if (!p)
    return p;
  while (*p >= '0' && *p <= '9' && RVMenuLexOk()) {
    v = v * 10 + (*p - '0');
    p++;
  }
  *out = v;
  return p;
}
U8 *RVMenuParseSub(U8 *p, CMenuEntry **out_next, CTask *task);
U8 *RVMenuParseEntry(U8 *p, CMenuEntry **out_me, CTask *task)
{
  U8 name[32];
  CMenuEntry *tmpme;
  I64 arg1 = 0, arg2 = 0;
  *out_me = NULL;
  p = RVMenuSkip(p);
  if (!p || !*p)
    return p;
  p = RVMenuReadIdent(p, name, 32);
  if (!name[0])
    return p;
  tmpme = CAlloc(sizeof(CMenuEntry), task);
  StrCpy(tmpme->name, name);
  p = RVMenuSkip(p);
  if (p && *p == '(') {
    tmpme->msg_code = MSG_KEY_DOWN_UP;
    p++;
    p = RVMenuSkip(p);
    if (p && *p && *p != ',' && *p != ')')
      p = RVMenuReadI64(p, &tmpme->msg_code);
    p = RVMenuSkip(p);
    if (p && *p == ',') {
      p++;
      p = RVMenuSkip(p);
      if (p && *p && *p != ',' && *p != ')')
        p = RVMenuReadI64(p, &arg1);
    }
    p = RVMenuSkip(p);
    if (p && *p == ',') {
      p++;
      p = RVMenuSkip(p);
      if (p && *p && *p != ',' && *p != ')')
        p = RVMenuReadI64(p, &arg2);
    }
    tmpme->arg1 = arg1;
    tmpme->arg2 = arg2;
    while (p && *p && *p != ')' && RVMenuLexOk())
      p++;
    if (p && *p == ')')
      p++;
    p = RVMenuSkip(p);
    if (p && *p == ';')
      p++;
  } else if (p && *p == '{') {
    tmpme->dir = TRUE;
    p++;
    p = RVMenuParseSub(p, &tmpme->sub, task);
    p = RVMenuSkip(p);
    if (p && *p == '}')
      p++;
  }
  *out_me = tmpme;
  return p;
}

U8 *RVMenuParseSub(U8 *p, CMenuEntry **out_next, CTask *task)
{
  CMenuEntry *tmpme, *last = NULL;
  *out_next = NULL;
  while (p && *p && RVMenuLexOk()) {
    p = RVMenuSkip(p);
    if (!*p || *p == '}')
      break;
    p = RVMenuParseEntry(p, &tmpme, task);
    if (!tmpme) {
      if (p && *p && *p != '}')
        p++;
      continue;
    }
    if (!last)
      *out_next = tmpme;
    else
      last->next = tmpme;
    last = tmpme;
  }
  return p;
}

CMenu *MenuNewHand(U8 *st, I64 flags, CTask *task)
{
  CMenu *m;
  CMenuEntry *tmpme, *last = NULL;
  U8 *p = st;
  rv_menu_lex_steps = 0;
  rv_menu_lex_abort = 0;
  if (!task)
    task = Fs;
  m = CAlloc(sizeof(CMenu), task);
  m->task = task;
  m->flags = flags;
  m->attr = BLUE << 4 + YELLOW;
  if (!p)
    return m;
  rv_menu_lex_hits++;
  while (p && *p && RVMenuLexOk()) {
    p = RVMenuParseEntry(p, &tmpme, task);
    if (!tmpme) {
      if (p && *p)
        p++;
      continue;
    }
    if (!last)
      m->sub = tmpme;
    else
      last->next = tmpme;
    last = tmpme;
  }
  if (rv_menu_lex_abort) {
    MenuDel(m);
    return NULL;
  }
  return m;
}
// ---- CmpCtrl path (Adam/Menu.HC MenuNewSub shape) ----
// Soft I64: PersonalMenu uses TileHorz(,1) empty slots. Adam calls
// LexExpressionI64 (JIT Call) which faults on RV for empty/simple args.
// Read TK_I64/CHAR directly; skip unknowns to ','/')' — no Call.
I64 MenuLexI64Soft(CCmpCtrl *cc)
{
  I64 v = 0, steps = 0;
  if (!cc || !rv_fp_Lex)
    return 0;
  if (cc->token == ',' || cc->token == ')')
    return 0;
  if (cc->token == TK_I64) {
    v = cc->cur_i64;
    rv_fp_Lex(cc);
    rv_menu_cmp_soft_i64++;
    return v;
  }
  if (cc->token == TK_CHAR_CONST) {
    v = cc->cur_i64;
    rv_fp_Lex(cc);
    rv_menu_cmp_soft_i64++;
    return v;
  }
  // Unknown / expression-like: skip to comma or paren (do not LexExpressionI64).
  while (cc->token && cc->token != ',' && cc->token != ')' && steps < 64) {
    rv_fp_Lex(cc);
    steps++;
  }
  rv_menu_cmp_soft_i64++;
  return 0;
}

CMenuEntry *MenuNewSubCmp(CCmpCtrl *cc, CTask *task)
{
  CMenuEntry *tmpme = NULL, *tmpse;
  if (!cc || !rv_fp_Lex)
    return NULL;
  if (cc->token == TK_IDENT) {
    tmpme = CAlloc(sizeof(CMenuEntry), task);
    if (StrLen(cc->cur_str) > 31)
      cc->cur_str[31] = 0;
    StrCpy(tmpme->name, cc->cur_str);
    if (rv_fp_Lex(cc) == '(') {
      tmpme->msg_code = MSG_KEY_DOWN_UP;
      if (rv_fp_Lex(cc) != ',' && cc->token != ')')
        tmpme->msg_code = MenuLexI64Soft(cc);
      if (cc->token == ',')
        rv_fp_Lex(cc);
      if (cc->token != ',' && cc->token != ')')
        tmpme->arg1 = MenuLexI64Soft(cc);
      if (cc->token == ',')
        rv_fp_Lex(cc);
      if (cc->token != ',' && cc->token != ')')
        tmpme->arg2 = MenuLexI64Soft(cc);
      if (cc->token != ')')
        rv_fp_Lex(cc);
      // tolerate missing ')' soft
      if (rv_fp_Lex(cc) != ';')
        ;
      rv_fp_Lex(cc);
    } else if (cc->token == '{') {
      rv_fp_Lex(cc);
      tmpme->dir = TRUE;
      tmpse = &tmpme->sub;
      while (tmpse && cc->token != '}' && cc->token != TK_EOF)
        tmpse = tmpse->next = MenuNewSubCmp(cc, task);
      if (cc->token == '}')
        rv_fp_Lex(cc);
    }
  }
  return tmpme;
}

CMenu *MenuNewCmp(U8 *st, I64 flags, CTask *task)
{
  CMenu *m;
  CMenuEntry *tmpse;
  CCmpCtrl *cc;
  I64 guard = 0;
  if (!RVMenuFpsWired)
    return NULL;
  if (!task)
    task = Fs;
  cc = rv_fp_CmpCtrlNew(st, CCF_DONT_FREE_BUF, NULL);
  if (!cc)
    return NULL;
  rv_menu_lex_hits++;
  rv_menu_cmp_hits++;
  rv_fp_Lex(cc);
  m = CAlloc(sizeof(CMenu), task);
  m->task = task;
  m->flags = flags;
  m->attr = BLUE << 4 + YELLOW;
  tmpse = &m->sub;
  while (tmpse && cc->token != TK_EOF && guard < RV_MENU_MAX * 4) {
    tmpse = tmpse->next = MenuNewSubCmp(cc, task);
    guard++;
  }
  rv_fp_CmpCtrlDel(cc);
  return m;
}

public CMenu *MenuNew(U8 *st, I64 flags = 0, CTask *task = NULL)
{
  //Adam MenuNew shape → CMenu. Hand Lex by default (smoke-safe).
  // Use MenuNewCmpCtrl when fps wired for full CmpCtrl Lex.
  CMenu *m;
  if (!task)
    task = Fs;
  m = MenuNewHand(st, flags, task);
  if (!m || !m->sub) {
    if (m)
      MenuDel(m);
    RVMenuTableLoad;
    return NULL;
  }
  if (rv_menu_cur)
    MenuDel(rv_menu_cur);
  rv_menu_cur = m;
  RVMenuSyncFlat(m);
  return m;
}

public CMenu *MenuNewCmpCtrl(U8 *st, I64 flags = 0, CTask *task = NULL)
{
  //CmpCtrl MenuNew when fps are absolute (WireCmpCtrlAddrs). Soft I64 args —
  // never LexExpressionI64 Call. Falls back to hand Lex MenuNew.
  CMenu *m;
  if (!task)
    task = Fs;
  if (!RVMenuFpsWired)
    return MenuNew(st, flags, task);
  m = MenuNewCmp(st, flags, task);
  if (!m || !m->sub) {
    if (m)
      MenuDel(m);
    return MenuNew(st, flags, task);
  }
  if (rv_menu_cur)
    MenuDel(rv_menu_cur);
  rv_menu_cur = m;
  RVMenuSyncFlat(m);
  return m;
}

I64 RVMenuCmpSelfTest()
{
  //TileHorz(,1) empty-comma via CmpCtrl when wired; else hand Lex.
  // Restore full PersonalMenu after — truncated flat menu made MenuActivate(4)
  // miss About (id=0) and left Apps PopUp unprobed.
  U8 *st = "Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "}\n" "Help {\n" "  About(,5);\n" "}\n";
  CMenu *m = MenuNewCmpCtrl(st);
  I64 n = 0;
  if (m)
    n = rv_menu_personal_n;
  RVMenuTableLoad;
  return n;
}

public CMenu *MenuFile(U8 *filename, I64 flags = 0, CTask *task = NULL)
{
  //Adam MenuFile uses #include via CmpCtrl; RV: FileRead → hand Lex MenuNew.
  // CmpCtrl path: prefer MenuNewCmpCtrl(st) at call sites when fps wired (MenuPush).
  U8 *buf;
  I64 sz = 0;
  CMenu *m;
  if (!filename || !filename[0])
    return NULL;
  buf = FileRead(filename, &sz);
  if (!buf || sz <= 0) {
    Free(buf);
    return NULL;
  }
  m = MenuNew(buf, flags, task);
  Free(buf);
  if (m)
    rv_menu_src_embedded = 0;
  return m;
}

public CTask *MenuTask()
{
  //Adam Menu.HC MenuTask — focus task with cur_menu (or parent).
  CTask *res = sys_focus_task;
  while (res && !res->cur_menu)
    res = res->parent_task;
  return res;
}

I64 MenuEntryWidth(CMenuEntry *tmpme)
{
  I64 res;
  CMenuEntry *tmpse;
  if (!tmpme)
    return 1;
  res = StrLen(tmpme->name);
  tmpse = tmpme->sub;
  while (tmpse) {
    res = MaxI64(res, StrLen(tmpse->name));
    tmpse = tmpse->next;
  }
  return res + 1;
}

public CMenu *MenuPush(U8 *st)
{
  //TempleOS MenuPush — stack pulldown for Demo/Games/*.HC (MassSpring).
  CMenu *m;
  if (!Fs)
    return NULL;
  m = MenuNewHand(st, 0, Fs);
  if (!m || !m->sub) {
    if (m)
      MenuDel(m);
    return NULL;
  }
  m->next = Fs->cur_menu;
  Fs->cur_menu = m;
  rv_menu_cur = m;
  RVMenuSyncFlat(m);
  return m;
}

public U0 MenuPop()
{
  //TempleOS MenuPop — restore prior pulldown.
  CMenu *m;
  if (!Fs)
    return;
  m = Fs->cur_menu;
  if (!m)
    return;
  Fs->cur_menu = m->next;
  if (rv_menu_cur == m)
    rv_menu_cur = Fs->cur_menu;
  MenuDel(m);
  if (Fs->cur_menu)
    RVMenuSyncFlat(Fs->cur_menu);
  else if (rv_menu_personal_n <= 0)
    RVMenuTableLoad;
}

public CMenuEntry *MenuSubEntryFind(CMenuEntry *haystack_first, U8 *needle_entry_name)
{
  //Adam Menu.HC MenuSubEntryFind — one level of pulldown names.
  while (haystack_first) {
    if (!StrCmp(haystack_first->name, needle_entry_name))
      return haystack_first;
    haystack_first = haystack_first->next;
  }
  return NULL;
}

public CMenuEntry *MenuEntryFind(CMenu *haystack_menu, U8 *needle_full_name)
{
  //Adam Menu.HC MenuEntryFind — "File/Open" style (two levels).
  U8 *st, *st2;
  CMenuEntry *tmpse;
  if (!haystack_menu || !needle_full_name)
    return NULL;
  st = StrNew(needle_full_name);
  st2 = StrNew(needle_full_name);
  tmpse = (&haystack_menu->sub)(U8 *) - offset(CMenuEntry.sub);
  while (*st && tmpse) {
    StrFirstRem(st, "/", st2);
    tmpse = MenuSubEntryFind(tmpse->sub, st2);
  }
  Free(st);
  Free(st2);
  return tmpse;
}

U0 RVMenuPersonalInit()
{
  //PersonalMenu via MenuFile of A:/Adam/PersonalMenu.DD (TempleOS shape).
  // Mount stages the DD under A:/Adam (DirMk fixed: LBEqu returns old bit so
  // FileFind Silent restore works). Root A:/PersonalMenu.DD is fallback; table
  // if MenuFile fails.
  CMenu *m;
  U8 *adam_path = "A:/Adam/PersonalMenu.DD";
  U8 *root_path = "A:/PersonalMenu.DD";
  U8 *src;
  if (rv_menu_personal_n > 0)
    return;
  if (!Fs || !Fs->cur_dv) {
    Print("RVMenuPersonalInit no FS — table fallback\n");
    RVMenuTableLoad;
    return;
  }
  m = MenuFile(adam_path);
  if (m && rv_menu_personal_n > 0 && !rv_menu_src_embedded) {
    Print("RVMenuPersonalInit MenuFile ok n=%d emb=%d path=%s\n", rv_menu_personal_n, rv_menu_src_embedded, adam_path);
    return;
  }
  rv_menu_personal_n = 0;
  m = MenuFile(root_path);
  if (!m || rv_menu_src_embedded || rv_menu_personal_n <= 0) {
    src = "Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "  WinMax(,3);\n" "  Close(,4);\n" "}\n" "Help {\n" "  About(,5);\n" "  Help(,6);\n" "  FormDemo(,7);\n" "  CtrlsDemo(,8);\n" "}\n";
    FileWrite(root_path, src, StrLen(src));
    Print("RVMenuPersonalInit staged %s bytes=%d\n", root_path, StrLen(src));
    rv_menu_personal_n = 0;
    m = MenuFile(root_path);
  }
  if (m && rv_menu_personal_n > 0 && !rv_menu_src_embedded) {
    Print("RVMenuPersonalInit MenuFile ok n=%d emb=%d path=%s\n", rv_menu_personal_n, rv_menu_src_embedded, root_path);
    return;
  }
  Print("RVMenuPersonalInit MenuFile miss — table fallback\n");
  RVMenuTableLoad;
}

I64 RVMenuPersonalCount()
{
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
  return rv_menu_personal_n;
}

U8 *RVMenuPersonalName(I64 i)
{
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
  if (i < 0 || i >= rv_menu_personal_n)
    return "";
  return rv_menu_personal[i].name;
}

I64 RVMenuPersonalId(I64 i)
{
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
  if (i < 0 || i >= rv_menu_personal_n)
    return RV_MENU_ID_NONE;
  return rv_menu_personal[i].id;
}

I64 RVMenuPersonalWidth()
{
  I64 i, w = 8, n, len;
  n = RVMenuPersonalCount;
  for (i = 0; i < n; i++) {
    len = StrLen(rv_menu_personal[i].name);
    if (len > w)
      w = len;
  }
  return w + 2;
}

public I64 RVMenuNew(U8 *st)
{
  CMenu *m = MenuNew(st);
  if (!m)
    return rv_menu_personal_n;
  return rv_menu_personal_n;
}

I64 RVMenuLexSelfTest()
{
  U8 *st = "Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "  WinMax(,3);\n" "  Close(,4);\n" "}\n" "Help {\n" "  About(,5);\n" "  Help(,6);\n" "  FormDemo(,7);\n" "  CtrlsDemo(,8);\n" "}\n";
  CMenu *m = MenuNew(st);
  if (!m)
    return 0;
  return rv_menu_personal_n;
}

public I64 RVMenuFile(U8 *filename)
{
  CMenu *m = MenuFile(filename);
  if (!m)
    return 0;
  return rv_menu_personal_n;
}

U0 RVMenuWireCmpCtrl(CCmpCtrl * (*fp_new)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL), I64 (*fp_lex)(CCmpCtrl *cc), I64 (*fp_lex_i64)(CCmpCtrl *cc), U0 (*fp_del)(CCmpCtrl *cc))
{
  //Prefer WireCmpCtrlAddrs on split-AOT. Direct &CmpCtrlNew from Kernel is unsafe.
  if (!RVMenuFpOk(fp_new) || !RVMenuFpOk(fp_lex) || !RVMenuFpOk(fp_del)) {
    rv_fp_CmpCtrlNew = NULL;
    rv_fp_Lex = NULL;
    rv_fp_LexExpressionI64 = NULL;
    rv_fp_CmpCtrlDel = NULL;
    return;
  }
  rv_fp_CmpCtrlNew = fp_new;
  rv_fp_Lex = fp_lex;
  rv_fp_LexExpressionI64 = fp_lex_i64;
  rv_fp_CmpCtrlDel = fp_del;
}

U0 RVMenuWireCmpCtrlAddrs(I64 *addrs)
{
  //addrs[0..3] = CmpCtrlNew, Lex, LexExpressionI64, CmpCtrlDel (Compiler-unit abs).
  if (!addrs) {
    RVMenuWireCmpCtrl(NULL, NULL, NULL, NULL);
    return;
  }
  RVMenuWireCmpCtrl(addrs[0], addrs[1], addrs[2], addrs[3]);
}
#endif // !MENU_RV_GUEST_CMP
#endif // MENU_RV_HC
