/* This converts $LK,"::/Demo/ToHtmlToTXTDemo/DemoInPage.DD"$ to
an plain ASCII text document named, "OutPage.DD".

*/

Cd(__DIR__);;

#ifndef RV_NO_DEMO_AUTORUN
ToTXT("DemoInPage.DD.Z","~/DemoOutPage");
#endif
