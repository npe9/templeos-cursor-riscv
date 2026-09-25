U0 OnceDemo()
{//Set code to execute next reboot.
  Once("Beep;");
  Once("Dir;"); //You can issue multiple and they get queued.
  "Reboot ";
  if (YorN)
    BootRAM;
}

#ifndef RV_NO_DEMO_AUTORUN
OnceDemo;
#endif

//There are variants for adam $LK,"AOnce",A="MN:AOnce"$().
