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
