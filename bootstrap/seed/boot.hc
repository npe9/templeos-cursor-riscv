// boot.hc -- the editable boot script, auto-Run at startup. Edit it and reboot (or
// Run("boot.hc")) to change what the system brings up. Each line runs before the next
// compiles, so you can load a driver and then use it (on a LATER line, not the same one).
Run("uart.hc");
Run("dir.hc");
UartStr("[boot] HolyC primitives loaded. Dir; to list, Run/Edit to change them live.\n");
