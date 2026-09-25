// GetKey — the one blocking key read, shared by the windowing and the UART paths.
//
// Stock TempleOS code calls GetKey(&sc) and expects it to block until a key arrives. There was
// no GetKey on RV at all: Kernel/EdLite.HC called one that did not exist, and every stock demo
// driven by the keyboard (Demo/Games/Digits.HC, TicTacToe.HC, …) had nothing to read from.
//
// Two sources, checked in that order, because a build can have either or both:
//   1. window messages — virtio-keyboard → RVWinMgrPumpInput → TaskMsg → MSG_KEY_DOWN
//   2. the UART — `make tos` and every headless smoke drive the guest over serial
//
// Defined here, after Drv/RVUart.HC, because it needs the UART; EdLite is included earlier and
// carries a forward declaration.
//
// BOUNDED WAIT. Stock blocks forever. A headless smoke with no input source would then wedge
// CI with no output, which is the failure mode this tree keeps re-learning, so the wait is
// bounded by rv_getkey_spin_max and returns 0. Set it to 0 for stock blocking behaviour on an
// interactive build. rv_getkey_timeouts counts every bounded exit so a caller can tell "the
// user pressed nothing" from "there was nobody to press anything".
I64 rv_getkey_spin_max = 2000000;
I64 rv_getkey_timeouts;
I64 rv_getkey_chars;

I64 GetKey(I64 *_scan_code = NULL, Bool echo = TRUE, Bool raw = FALSE)
{
  I64 ch = 0, sc = 0, spins = 0;
  no_warn echo;
  no_warn raw;
  while (TRUE) {
    //ScanMsg walks Fs's message queue — on a bare kernel with no TaskInit'd Fs that is a
    //NULL+0x18 load fault, so the UART path below has to stay reachable without it.
    if (Fs && TaskValidate(Fs) && ScanMsg(&ch, &sc, 1 << MSG_KEY_DOWN) == MSG_KEY_DOWN) {
      rv_getkey_chars++;
      break;
    }
    if (RVUartDataReady) {
      ch = RVUartTryGet & 0xFF;
      sc = 0;
      rv_getkey_chars++;
      break;
    }
    if (rv_getkey_spin_max && ++spins > rv_getkey_spin_max) {
      rv_getkey_timeouts++;
      ch = 0;
      sc = 0;
      break;
    }
    Yield;
  }
  // No echo: stock echoes into the put doc, and doing that here would interleave with the UART
  // transcript every smoke greps. Callers that want it can PutChar.
  if (_scan_code)
    *_scan_code = sc;
  return ch;
}

Bool KeyAvailable()
{//TRUE when GetKey would return without waiting — for poll loops that must not block.
  I64 ch, sc;
  if (RVUartDataReady)
    return TRUE;
  if (Fs && TaskValidate(Fs) && ScanMsg(&ch, &sc, 1 << MSG_KEY_DOWN) == MSG_KEY_DOWN) {
    //ScanMsg consumes; there is no peek, so re-post it for the GetKey that follows.
    TaskMsg(Fs, NULL, MSG_KEY_DOWN, ch, sc, 0);
    return TRUE;
  }
  return FALSE;
}
