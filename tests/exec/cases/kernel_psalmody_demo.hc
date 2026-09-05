// Psalmody API + host $IB staff embed smoke (Note2Ona/Menu/Tempo + IbStaffInit).
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Psalmody/PsalmodyCtrls.HC"
#include "/tests/exec/fixtures/ib_staff_embed.HC"
I64 main()
{
  I64 ona, note, oct;
  CCtrl *tempo;
  CMenu *m;
  CMenuEntry *ent;
  CTask *adam;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  adam = 0x86900000;
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
  QueInit(&adam->next_ode);
  QueInit(&adam->next_ctrl);
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVKernelInit();
  if (!RVGrInit(640, 480)) {
    Print("RVPsalmody init FAIL\n");
    return 1;
  }
  IbStaffInit;
  if (!g_ib_staff) {
    Print("RVPsalmody IB FAIL null\n");
    return 1;
  }
  // Psalmody BI=15 head is SPT_THICK (3) — prove host $IB carried trailer bytes.
  if (g_ib_staff[0] != 3) {
    Print("RVPsalmody IB FAIL first=%d\n", g_ib_staff[0]);
    return 1;
  }
  ona = Note2Ona(3, 4);
  note = Ona2Note(ona);
  oct = Ona2Octave(ona);
  if (ona != 51 || note != 3 || oct != 4) {
    Print("RVPsalmody Note2Ona FAIL ona=%d note=%d oct=%d\n", ona, note, oct);
    return 1;
  }
  MusicSettingsRst;
  Play("5qC");
  Snd(ona);
  Snd(0);
  m = MenuPush("File {" "  Open(,1);" "  Help(,2);" "}");
  if (!m) {
    Print("RVPsalmody MenuPush FAIL\n");
    return 1;
  }
  ent = MenuEntryFind(m, "File/Open");
  if (!ent) {
    Print("RVPsalmody MenuEntryFind FAIL\n");
    return 1;
  }
  tempo = TempoNew;
  if (!tempo) {
    Print("RVPsalmody TempoNew FAIL\n");
    return 1;
  }
  PopUpPickDir("~/Psalmody");
  PopUpEd("::/Apps/Psalmody/Help.DD", Fs);
  Print("RVPsalmody smoke ona=%d play=%d rst=%d menu=%d tempo=%d popup_file=%d ib=%d\n", ona, rv_snd_play_hits, rv_snd_rst_hits, ent->arg1, !!tempo, rv_popup_file_hits, g_ib_staff[0]);
  TempoDel(tempo);
  MenuPop;
  return 0;
}
