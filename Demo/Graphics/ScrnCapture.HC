//See $LK,"::/Demo/Games/Stadium/StadiumGen.HC"$.

U0 Main()
{
  "Capture scrn...\n";
  PressAKey;
  GRScrnCaptureWrite("~/DemoScrnShot");
  "View captured scrn...\n";
  PressAKey;
  GRScrnCaptureRead("~/DemoScrnShot");
  PressAKey;
  DCFill;
}

#ifndef RV_NO_DEMO_AUTORUN
Main;
#endif
