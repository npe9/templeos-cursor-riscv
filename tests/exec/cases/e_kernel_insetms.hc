// InSetMs() — lifted into Adam/InFile_RV.HC — actually moves the mouse to the requested spot.
//
// Why a value and not a survey row. Demo/InFile/InSetIP.HC fails with exactly one error,
// "Argument 1 omitted, but 'InSetMs' has no declaration here to take a default from", so the file
// compiles the moment anything declares InSetMs — which is precisely the L1-OK trap
// docs/DEMO_100.md §0 is about. InSetMs' whole job is to walk Line()'s fixed-point stepper from
// where the pointer is to where it was asked to go, calling MsSet at every step, so the honest
// check is where the pointer ends up.
//
// Asserted:
//   * InSetMs(0,100,50) leaves ms.pos.x==100 and ms.pos.y==50. The mouse starts at (0,0) after
//     MsInit, so both coordinates have to have been driven there. A stub cannot do it.
//   * a SECOND InSetMs(0,300,200,0,TRUE,FALSE) then leaves (300,200) — so the function walks from
//     wherever the pointer already is, not from the origin — and leaves ms.lb TRUE, ms.rb FALSE,
//     which is the l/r pair being carried through in_plot_l/in_plot_r into MsSet.
//
// The graphics and text-grid init is not decoration: MsSet clamps with ClampI64(x,0,GR_WIDTH-1),
// so without RVGrInit GR_WIDTH is 0 and every coordinate clamps to -1 (measured). MsInit is what
// sets ms.scale to 1.0; MsSet divides by it.
#include "/Kernel/Kernel_RV.PRJ"

I64 main()
{
  // Boot scaffolding: the sequence RVKMain uses, as tools/survey_demo_one.sh writes it.
  CTask *adam = 0x86900000;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  I64 x1, y1, x2, y2, lb, rb;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVKernelInit();
  RVGrInit(640, 480);
  text.cols = 80;
  text.rows = 60;
  text.font = sys_font_std;
  text.aux_font = sys_font_cyrillic;
  MsInit();

  InSetMs(0, 100, 50);
  x1 = ms.pos.x;
  y1 = ms.pos.y;
  InSetMs(0, 300, 200, 0, TRUE, FALSE);
  x2 = ms.pos.x;
  y2 = ms.pos.y;
  lb = ms.lb;
  rb = ms.rb;

  return (x1 == 100) * 0x01 + (y1 == 50) * 0x02 +
         (x2 == 300) * 0x04 + (y2 == 200) * 0x08 +
         (lb == TRUE) * 0x10 + (rb == FALSE) * 0x20;
  // 0x3f when all six hold.
}
