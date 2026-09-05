// MakeAdam_RV_Lite.HC — thin Adam desktop stub beyond AdamCore (P6 probe surface).
//
// Guest: `#include "Menu_RV"` (Lex+Guest wrap) → PersonalInit (hand Lex when folded)
// + FileWrite + return 8. Avoid Count→local before multi-STR FileWrite unless
// CALL_IMPORT store is green (sibling). Not PopUp/DolDoc/full MakeAdam / CMenu.
#ifndef MAKEADAM_RV_LITE_HC
#define MAKEADAM_RV_LITE_HC
#include "Menu_RV"
public I64 AdamRVLiteInit()
{
  RVMenuPersonalInit;
  FileWrite("A:/Adam/LITE.TXT", "MakeAdam_RV_Lite", 16);
  return 8;
}
#endif
