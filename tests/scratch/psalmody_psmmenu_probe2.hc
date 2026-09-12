#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Psalmody/Load.HC"
I64 main() {
  CTask *adam=0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs; CCtrl *tempo; I64 idx;
  MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  adam->task_signature=TASK_SIGNATURE_VAL; adam->addr=adam;
  QueInit(&adam->next_ode); QueInit(&adam->next_ctrl);
  gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVKernelInit;
  if (!RVGrInit(640,480) || !RVWinMgrInit()) { Print("PMM FAIL init\n"); return 1; }
  Print("PMM step init\n");
  Fs->put_doc = DocNew; Fs->display_doc = Fs->put_doc;
  idx = RVWinNew(2,70,2,40,"Psalmody","",TRUE);
  if (idx>=0) { RVWinBindTask(idx,Fs,RV_WIN_KIND_USER,FALSE); RVWinFocus(idx); }
  sys_focus_task = Fs;
  MemSet(&psm,0,sizeof(PsmCtrl));
  psm.head.next=psm.head.last=&psm.head;
  psm.clip.next=psm.clip.last=&psm.clip;
  psm.cur_note=&psm.head;
  psm.dc2=DCAlias;
  MenuPush("File { Abort(,CH_SHIFT_ESC); } Song { Record(,'z'); }");
  psm.record_entry=MenuEntryFind(Fs->cur_menu,"Song/Record");
  if (psm.record_entry) psm.record_entry->checked=FALSE;
  tempo=TempoNew;
  Print("PMM step before PsmMenu\n");
  PsmMenu(4);
  Print("PMM step after PsmMenu\n");
  TempoDel(tempo); MenuPop; DCDel(psm.dc2);
  Print("PMM ok\n");
  return 0;
}
