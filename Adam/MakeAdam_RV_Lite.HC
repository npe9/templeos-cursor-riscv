// MakeAdam_RV_Lite.HC - thin Adam desktop stub beyond AdamCore (P6 probe surface).
//
// Guest: `#include "Menu_RV"` (Lex+Guest wrap) -> PersonalInit + LexSelfTest
// + FileWrite + return 8. Not PopUp/DolDoc/full MakeAdam / CMenu.
#ifndef MAKEADAM_RV_LITE_HC
#define MAKEADAM_RV_LITE_HC
#include "Menu_RV"
public I64 AdamRVLiteInit()
{
  I64 n;
  RVMenuPersonalInit;
  n = RVMenuLexSelfTest;
  if (n > 0)
    rv_menu_personal_n = n;
  FileWrite("A:/Adam/LITE.TXT", "MakeAdam_RV_Lite", 16);
  return 8;
}
#endif
