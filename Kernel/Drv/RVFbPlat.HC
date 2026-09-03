#include "RVFbSelected.HH"
U0 RVFbPlatApplyPresent()
{
  RVFbSetPresent(RVFbPlatPresentKind());
  // Board defconfigs with SIMPLEFB_BASE≠0 bind here (no-op on virt/ramfb).
  RVFbSimpleFbTryBoard;
}
