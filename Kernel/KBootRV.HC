// RISC-V kernel boot initialisation: the portable part of what the x86 KMain()/SysGlblsInit() do,
// with the hardware/x86 pieces (CPUId, IDE, interrupt tables, MP) left to phase 2. Populates the
// runtime tables the kernel's own code needs and wires a UART console so a program that #includes
// the kernel gets a working environment on the QEMU `virt` machine. Included last in Kernel_RV.PRJ
// so every global and function it touches is already defined.

// The QEMU virt 16550 UART is at 0x10000000; the kernel's PutS/Print reach it through this sink.
Bool RVUartPutS(U8 *st)
{
  U8 *uart=0x10000000;
  while (*st)
    *uart=*st++;
  return TRUE;
}

U0 RVKernelInit()
{//Bring up the portable kernel environment on RISC-V (QEMU virt). Call once before using the kernel.
  I64 i,j;

  // Base-10 power table: %f float formatting (StrPrint) and Str2F64 index it.
  pow10_I64=CAlloc(sizeof(F64)*(308+308+1));
  for (i=-308;i<=308;i++)
    pow10_I64[i+309]=Pow10(ToF64(i));

  // Bit-reversal and pop-count tables (verbatim from SysGlblsInit).
  rev_bits_table=CAlloc(256);
  set_bits_table=CAlloc(256);
  for (i=0;i<256;i++)
    for (j=0;j<8;j++) {
      if (Bt(&i,7-j))	LBts(rev_bits_table+i,j);
      if (Bt(&i,j))	set_bits_table[i]++;
    }

  // Native console: register a UART sink in the StdOut (keyboard-device) chain so the kernel's own
  // PutS()/Print() dispatch to the UART. (KeyDevInit's x86 input filters are phase 2.)
  MemSet(&keydev.put_key_head,0,sizeof(CKeyDevEntry));
  QueInit(&keydev.put_key_head);
  KeyDevAdd(NULL,&RVUartPutS,0x10000000,FALSE);
  Fs->display_flags=0;
  kbd.scan_code=0;
}

// --- UART input (QEMU virt 16550) --------------------------------------------------------------
// The kernel's own GetKey() blocks via the scheduler (phase 2). Until that exists, these polling
// helpers give a program interactive input over the same UART the console writes to.
#define RV_UART_BASE  0x10000000
#define RV_UART_LSR   0x10000005   // line status register; bit0 = data ready

Bool RVUartDataReady()
{
  U8 *lsr=RV_UART_LSR;
  return (*lsr & 1) != 0;
}

I64 RVUartGetC()
{//Block (poll) until a byte arrives on the UART, then return it.
  U8 *rbr=RV_UART_BASE;
  while (!RVUartDataReady())
    ;
  return *rbr;
}

I64 RVUartGetLine(U8 *buf,I64 max)
{//Read a line into buf (up to max-1 chars), echoing as we go. Returns the length. Stops on \n or \r.
  I64 n=0,ch;
  while (n<max-1) {
    ch=RVUartGetC;
    if (ch=='\r' || ch=='\n') {
      RVUartPutS("\n");
      break;
    }
    if (ch==8 || ch==127) {          // backspace / delete
      if (n>0) { n--; RVUartPutS("\b \b"); }
      continue;
    }
    buf[n++]=ch;
    U8 e[2]; e[0]=ch; e[1]=0; RVUartPutS(e);   // echo
  }
  buf[n]=0;
  return n;
}

// --- Minimal cooperative scheduler --------------------------------------------------------------
// A round-robin over fixed task slots, built on the RVTaskSwitch context-switch primitive. This is
// NOT the kernel's CTask scheduler (KTask.HC/Sched.HC, phase 2) — it is a small cooperative runtime
// so a RISC-V program can Spawn tasks that Yield to each other. Slot 0 is the caller ("main").
#define RV_MAX_TASKS  8
#define RV_CTX_WORDS  14      // ra, sp, s0..s11
I64  rv_sched_ctx[RV_MAX_TASKS*RV_CTX_WORDS];
Bool rv_sched_done[RV_MAX_TASKS];
I64  rv_sched_n=1, rv_sched_cur=0;    // n starts at 1: slot 0 is the caller

U0 RVYield()
{//Cooperatively hand the CPU to the next runnable task (round-robin).
  I64 prev=rv_sched_cur, start=rv_sched_cur;
  while (TRUE) {
    rv_sched_cur=(rv_sched_cur+1)%rv_sched_n;
    if (!rv_sched_done[rv_sched_cur] || rv_sched_cur==prev || rv_sched_cur==start)
      break;
  }
  RVTaskSwitch(&rv_sched_ctx[prev*RV_CTX_WORDS], &rv_sched_ctx[rv_sched_cur*RV_CTX_WORDS]);
}

U0 RVTaskExit()
{//Mark the current task finished and yield away for good (never returns).
  rv_sched_done[rv_sched_cur]=TRUE;
  RVYield();
}

I64 RVSpawn(U0 (*fn)())
{//Create a task that begins at fn on a fresh 16 KB stack. Returns its slot, or -1 if full.
  if (rv_sched_n>=RV_MAX_TASKS)
    return -1;
  U8 *stk=CAlloc(16384);
  I64 slot=rv_sched_n;
  rv_sched_ctx[slot*RV_CTX_WORDS+0]=fn;                 // ra -> entry
  rv_sched_ctx[slot*RV_CTX_WORDS+1]=(stk+16384-16)&(~15); // sp -> aligned stack top
  rv_sched_done[slot]=FALSE;
  rv_sched_n++;
  return slot;
}

// --- RISC-V port of the x86 _MALLOC/_FREE primitives (Kernel/Mem/MAllocFree.HC) -----------------
// MAlloc and Free are the only two allocator functions the kernel writes in x86 assembly; every
// layer above them — CAlloc, ACAlloc, MAllocAligned, MSize, HeapCtrlInit, the block pool — is the
// kernel's own HolyC and runs on RISC-V unchanged. This is their stand-in: a first-fit free list
// over a linear arena that carves the exact CMemUsed header the kernel expects (hc + size + start),
// so the real CAlloc/MAllocAligned/TaskInit/Spawn allocate against it. the_heap must be set up (by
// RVKMain, or a demo that drives the task subsystem directly) before the first allocation.
CHeapCtrl *the_heap = 0x82000000;
U8 *heap_next = 0x82000400, *heap_end = 0x86000000;
U8 *MAlloc(I64 size, CTask *mem_task=NULL)
{
  I64 need=(size+offset(CMemUsed.start)+15)&(~15);
  CMemUnused *f=the_heap->malloc_free_lst,*prev=NULL;
  while (f && f->size<need) { prev=f; f=f->next; }
  U8 *chunk; I64 usize;
  if (f) { if (prev) prev->next=f->next; else the_heap->malloc_free_lst=f->next; chunk=f; usize=f->size; }
  else   { if (heap_next+need>heap_end) return NULL; chunk=heap_next; heap_next+=need; usize=need; }
  CMemUsed *u=chunk; u->hc=the_heap; u->size=usize; the_heap->used_u8s+=usize;
  return chunk+offset(CMemUsed.start);
}
U0 Free(U8 *ptr)
{
  if (!ptr) return;
  CMemUsed *u=ptr-offset(CMemUsed.start);
  CMemUnused *fu=u; fu->size=u->size; fu->next=the_heap->malloc_free_lst; the_heap->malloc_free_lst=fu;
}
// MSize / MSize2 are the other two x86-asm allocator primitives (_MSIZE / _MSIZE2 in MAllocFree.HC);
// their RISC-V port must read the same CMemUsed header this MAlloc writes, or the kernel's MSize-using
// code (and CAlloc, which zeroes MSize() bytes) sees garbage sizes. Mirrors _MSIZE exactly: the chunk
// size lives in CMemUsed.size; MAllocAligned marks aligned chunks with a NEGATIVE size that points back
// to the real header, so follow it. MSize returns the usable size (chunk minus header); MSize2 the
// internal size (whole chunk).
I64 MSize2(U8 *src)
{
  if (!src) return 0;
  CMemUsed *u=src-offset(CMemUsed.start);
  I64 sz=u->size;
  if (sz<0) { u=(src+sz)-offset(CMemUsed.start); sz=u->size; }
  return sz;
}
I64 MSize(U8 *src)
{
  if (!src) return 0;
  return MSize2(src)-offset(CMemUsed.start);
}

// --- RVKMain: the RISC-V analogue of KMain() (bucket 1: tables + Adam + first Spawn) ------------
// A from-scratch boot: the kernel brings ITSELF up and schedules its first task, instead of a demo
// hand-wiring adam. Only the portable "bucket 1" of KMain() runs here — set up the heap, create
// Adam, and Spawn the first task, then schedule it with the kernel's own Yield(). The display,
// block-device, file-system, compiler and StartOS buckets, and the x86 timer/interrupt/MP buckets,
// are named in the //x86: and //phase 3: comments below the way Kernel_RV.PRJ comments out KInts/
// MultiProc/FunSeg — the gap is auditable, not hidden. Uses the proven Spawn()+RISC-V frame path.
U0 RVBootTask()
{//The first task Adam spawns: prints a boot banner and exits. Its line proves the kernel scheduled a
 //real CTask that its OWN Spawn() created — i.e. it booted itself, not that a demo set adam up.
  Print("TempleOS/RISC-V: Adam booted and scheduled its first task.\n");
  Bts(&Fs->task_flags,TASKf_KILL_TASK);
  Yield();
}

U0 RVKMain()
{
  // KMain()'s first act is adam_task=Fs. Adam is the root CTask; establish it and Fs before anything
  // allocates, because the real ACAlloc/CAlloc used during heap setup allocate against adam_task.
  CTask *adam=0x86900000;
  MemSet(adam,0,sizeof(CTask));
  Fs=adam; adam_task=adam;

  // Bring up the linear arena the RISC-V MAlloc carves from, plus the kernel's own block pool and
  // heap-control (BlkPoolInit/HeapCtrlInit run unchanged). KMain does this via BlkPoolsInit.
  MemSet(the_heap,0,sizeof(CHeapCtrl));
  heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp);
  adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192);        // TaskInit reads the init FPU state from here (see PRJ note)

  // Create Adam through the kernel's OWN TaskInit — the very call KStart64.HC makes for adam. It
  // fills in task_num, rflags, the code/data-heap free-list queues, the FPU save area, the hash
  // table, a real stack (setting rsp), the window fields, and seeds the self-looped next_task/
  // last_task ring. Adam's rsp is re-established at the first context switch away from RVKMain, so
  // the fresh stack TaskInit allocates is only a placeholder here. Everything TaskInit touches is
  // the kernel's own code; only MAlloc and SYS_FIXED_AREA underneath it are RISC-V ports.
  TaskInit(adam,0);

  // Per-CPU block (Gs): the scheduler reads Gs->seth_task. KMain sets this up via Core0Init.
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;

  RVYieldInit(&Fs);            // wire the kernel's Yield() to &Fs
  RVJiffiesInit(10000);        // 1 ms jiffy on QEMU virt's 10 MHz mtime (a platform fact, not a knob)
  RVKernelInit();              // portable tables + UART console (needs Fs valid and the heap up)

  // x86: SysGlblsInit / Mem32DevInit / UncachedAliasAlloc / LoadKernel / SysGrInit — VGA display + kernel image relocation.
  // x86: TimersInit / IntsInit / IntInit1 / IntInit2 / SetRFlags — the PIT/HPET timers and the 8259/APIC interrupt controllers.
  // phase 3: BlkDevsInitAll / DskChg(':') / HomeSet — bring up block devices and mount the file system.
  // phase 3: Load("/Compiler/Compiler") / ExeFile("StartOS") / SrvTaskCont — load the compiler and enter the Adam server loop.

  Print("RVKMain: spawning Adam's first task via the kernel's own Spawn()...\n");
  CTask *t=Spawn(&RVBootTask,NULL,"Boot Task",-1,adam,0,0);
  // RISC-V initial-frame fixup (as in the Spawn path): Spawn seeds an x86 return frame; re-seed the
  // on-stack callee-saved switch frame {s0..s11=0, ra=entry} that RVCtxSw pops on the first switch.
  I64 top=t->rsp+16; I64 *frame=(top-104)&(~15); I64 i;
  for (i=0;i<12;i++) frame[i]=0; frame[12]=t->rip; t->rsp=frame;
  t->next_task=adam->next_task; t->last_task=adam; adam->next_task->last_task=t; adam->next_task=t;

  // Schedule: Adam yields until its child has run and exited. The kernel's Yield() skips the killed
  // child on the next lap, so this loop ends once the boot task has set TASKf_KILL_TASK.
  while (!(t->task_flags & (1<<TASKf_KILL_TASK)))
    Yield();
  Print("RVKMain: boot task finished; Adam is scheduling.\n");
}
