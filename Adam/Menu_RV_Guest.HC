// Menu_RV_Guest.HC — PersonalMenu extract for guest Cmp (MENU_RV_GUEST_CMP).
// Shared chrome surface with host Menu_RV: Count/Name/Id/Width + src_embedded/lex_hits.
// When Menu_RV_Guest_Lex is included first (wrap), Init fills ids via index hand Lex.
// No CMenu/CAlloc — nesting those still blocks flat Guest Cmp.
#ifndef MENU_RV_GUEST_HC
#define MENU_RV_GUEST_HC
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
I64 rv_menu_src_embedded;
I64 rv_menu_lex_hits;
public U0 RVMenuPersonalInit()
{
  I64 n;
  if (rv_menu_personal_n > 0)
    return;
#ifdef MENU_RV_GUEST_LEX_HC
  // PersonalMenu.DD shape — same SoT as host MenuFile / phase3 stage.
  n = RVMenuLexNew("Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "  WinMax(,3);\n" "  Close(,4);\n" "}\n" "Help {\n" "  About(,5);\n" "  Help(,6);\n" "  FormDemo(,7);\n" "  CtrlsDemo(,8);\n" "}\n");
  if (n > 0) {
    rv_menu_personal_n = n;
    rv_menu_src_embedded = 0;
    rv_menu_lex_hits = rv_menu_lex_parse_hits;
    return;
  }
#endif
  rv_menu_personal_n = 8;
  rv_menu_src_embedded = 1;
}

public I64 RVMenuPersonalCount()
{
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
  return rv_menu_personal_n;
}

public U8 *RVMenuPersonalName(I64 i)
{
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
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
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
  if (i < 0 || i >= rv_menu_personal_n)
    return RV_MENU_ID_NONE;
#ifdef MENU_RV_GUEST_LEX_HC
  if (rv_menu_lex_n > 0 && i < rv_menu_lex_n)
    return rv_menu_lex_id[i];
#endif
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
  // Longest PersonalMenu leaf ("CtrlsDemo") + pad — no StrLen import on guest.
  if (rv_menu_personal_n <= 0)
    RVMenuPersonalInit;
  return 12;
}
#endif
