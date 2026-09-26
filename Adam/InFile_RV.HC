// InSetMs() lifted out of Adam/InFile.HC, because that unit cannot be added whole.
//
// `Demo/InFile/InSetIP.HC` fails with exactly one error —
//   "Argument 1 omitted, but 'InSetMs' has no declaration here to take a default from"
// which docs/DEMO_100.md §1 identifies as a callee with no declaration in scope, not a compiler
// bug. The fix is supposed to be `#include "/Adam/InFile.HC"` in Kernel_RV.PRJ. It is not, and the
// reason is measured rather than argued:
//
//   /Adam/InFile.HC:110:17: error: Undefined variable 'View'
//
// `InView()` is `Bool res=View;`, and `View` has NO BODY ANYWHERE in this tree — the only
// occurrence is `extern Bool View();` in Adam/AExts.HC, the 89-extern file docs/DEMO_100.md §0
// names as the trap. So the whole unit does not compile, and the five other things it defines
// (InGetStr/InPrint/InGetKey/InGetChar/InUntilKey/InUntilChar) are unreachable with it.
//
// Lifted VERBATIM instead — the same treatment Kernel/RVDoc.HC gives five DolDoc functions whose
// own units collide. Every callee is already in the image and resolved (measured with
// tools/blob_imports.py: adding this introduces ZERO new unresolved names): MsSet and the `ms`
// globals from Kernel/SerialDev/Mouse.HC, Line() from Adam/Gr/GrMath.HC, Sleep, and
// GR_WIDTH/GR_HEIGHT.
//
// Placement matters: this must come AFTER /Adam/Gr/GrMath.HC, which is where Line() — the
// fixed-point line stepper that drives the callback — actually lives.
//
// NOT lifted: InGetStr/InGetKey/InGetChar/InUntilKey/InUntilChar all block on GetKey() and put up
// a PopUpOk on a wrong key, so nothing about them can be asserted without an input device; and
// InView is the function that cannot compile at all. Demo/InFile/InPopUp.HC already surveys
// L1-HANG for exactly that reason.
#help_index "InFile;Help System/Training;Mouse"
I64 in_plot_l, in_plot_r;

Bool InSetMsPlot(I64 mS, I64 x, I64 y, I64 z)
{
  MsSet(x, y, z, in_plot_l, in_plot_r);
  Sleep(mS);
  return TRUE;
}

public U0 InSetMs(I64 mS=7, I64 x=I64_MAX, I64 y=I64_MAX, I64 z=I64_MAX,
		I64 l=I64_MAX, I64 r=I64_MAX)
{//Move mouse to spot at certain speed.
  if (!(0<=x<GR_WIDTH))
    x=ms.pos.x;
  if (!(0<=y<GR_HEIGHT))
    y=ms.pos.y;
  if (z==I64_MAX)
    z=ms.pos.z;
  if (!(FALSE<=l<=TRUE))
    l=ms.lb;
  if (!(FALSE<=r<=TRUE))
    r=ms.rb;
  in_plot_l=l; in_plot_r=r;
  Line(mS,ms.pos.x,ms.pos.y,ms.pos.z,x,y,z,&InSetMsPlot);
}
