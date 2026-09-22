// RISC-V kernel boot initialisation: the portable part of what the x86 KMain()/SysGlblsInit() do,
// with the hardware/x86 pieces (CPUId, IDE, interrupt tables, MP) left to phase 2. Populates the
// runtime tables the kernel's own code needs and wires a UART console so a program that #includes
// the kernel gets a working environment on the selected QEMU machine (Kconfig / RVAutoConf.HH).
// UART put/get live in Drv/RVUart.HC. Included after Drv/* in Kernel_RV.PRJ.
#ifndef RV_UART_BASE
#define RV_UART_BASE  CONFIG_UART_BASE
#endif
// Trampoline in this file so KeyDevAdd can take &fn (cross-include & is flaky).
// Optional mirror (WinMgr Term REPL): set while evaluating a Term line so Print
// lands in both UART and the graphical Term body.
Bool (*RVConsoleMirrorPutS)(U8 *st);
// Default 0 = mirror AND write the UART, which is right when the screen is a
// framebuffer and the UART is a separate device. Set to 1 when something else owns
// the wire — the RVDocVT presenter ships the whole grid as ANSI over that same UART,
// so a raw Print during evaluation overwrites the frame mid-render. With this set, a
// mirror that accepted the string suppresses the raw write.
I64 rv_console_mirror_only;
Bool RVConsolePutS(U8 *st)
{
  if (RVConsoleMirrorPutS && st) {
    if ((*RVConsoleMirrorPutS)(st) && rv_console_mirror_only)
      return TRUE;
  }
  return RVUartPutS(st);
}
// PutChars/LexPutToken use put_key; put_s-only left put_key=NULL → jalr 0 (mepc=0).
Bool RVConsolePutKey(I64 ch, I64 sc)
{
  U8 e[2];
  no_warn sc;
  e[0] = ch;
  e[1] = 0;
  if (RVConsoleMirrorPutS) {
    if (RVConsoleMirrorPutS(e) && rv_console_mirror_only)
      return TRUE;
  }
  return RVUartPutS(e);
}

U0 RVKernelInit()
{
  //Bring up the portable kernel environment on RISC-V. Call once before using the kernel.
  I64 i, j;
  // ExpandBuf / Compress.HC guards expanded_size against mem_mapped_space (stock top-of-map).
  // Host `_extern MEM_MAPPED_SPACE U8 *mem_mapped_space` allocates a separate BSS slot; it does
  // not alias KStartRV's U64 MEM_MAPPED_SPACE[1]. Assign the HolyC name ExpandBuf reads.
  if (!mem_mapped_space)
    mem_mapped_space = 0x100000000(U8 *);
#ifndef RV_THIN_LOADER
  // Base-10 power table: %f float formatting (StrPrint) and Str2F64 index it.
  // Thin gates StrPrint+StrScan — SoftCall never indexes pow10_I64.
  pow10_I64 = CAlloc(sizeof(F64) * (308 + 308 + 1));
  // Exact table: 10^0..10^22 are representable, so repeated *10.0 is exact and
  // 1.0/10^k is correctly rounded. Pow10() (runtime exp/log) was 3-4 ulps off,
  // which skewed every lexed F64 literal (1.5 -> 0x3FF7FFFFFFFFFFFD).
  pow10_I64[309] = 1.0;
  for (i = 1; i <= 308; i++)
    pow10_I64[i + 309] = pow10_I64[i + 308] * 10.0;
  for (i = 1; i <= 308; i++)
    pow10_I64[309 - i] = 1.0 / pow10_I64[309 + i];
#endif
  // Bit-reversal and pop-count tables (verbatim from SysGlblsInit).
  rev_bits_table = CAlloc(256);
  set_bits_table = CAlloc(256);
  for (i = 0; i < 256; i++)
    for (j = 0; j < 8; j++) {
      if (Bt(&i, 7 - j))
        LBts(rev_bits_table + i, j);
      if (Bt(&i, j))
        set_bits_table[i]++;
    }
  // Native console: UART StdOut + stock Ctrl-Alt cbs via KeyDevCtrlAltInit
  // (full KeyDevInit KDRaw chain deferred — hung PopUp/SrvCmdLine on RV).
  RVConsoleMirrorPutS = NULL;
  rv_console_mirror_only = 0;
  RVUartInit();
  MemSet(&keydev.put_key_head, 0, sizeof(CKeyDevEntry));
  QueInit(&keydev.put_key_head);
  KeyDevCtrlAltInit;
  // PutChars/LexPutToken need put_key (NULL → jalr 0 / mepc=0).
  KeyDevAdd(&RVConsolePutKey, &RVConsolePutS, CONFIG_UART_BASE, FALSE);
  Fs->display_flags = 0;
  LBts(&Fs->display_flags, DISPLAYf_NOT_RAW);
  kbd.scan_code = 0;
  SYS_CTRL_ALT_FLAGS[0] = 0;
  // Defense: x86 HPET fields must stay 0 — nonzero + HPET() load-faults at 0xFED000F0.
  cnts.HPET_freq = 0;
  cnts.HPET_kHz_freq = 0;
  cnts.HPET_initial = 0;
  // ScrnCast snd ring (stock SysGlblsInit / KMain) — RVSnd queues when record.
  QueInit(&scrncast.snd_head);
  scrncast.ona = scrncast.snd_head.ona = 0;
  scrncast.record = FALSE;
  scrncast.just_audio = FALSE;
}
// --- Minimal cooperative scheduler --------------------------------------------------------------
// A round-robin over fixed task slots, built on the RVTaskSwitch context-switch primitive. This is
// NOT the kernel's CTask scheduler (KTask.HC/Sched.HC, phase 2) — it is a small cooperative runtime
// so a RISC-V program can Spawn tasks that Yield to each other. Slot 0 is the caller ("main").
#define RV_MAX_TASKS  8
#define RV_CTX_WORDS  14      // ra, sp, s0..s11
I64 rv_sched_ctx[RV_MAX_TASKS *RV_CTX_WORDS];
Bool rv_sched_done[RV_MAX_TASKS];
I64 rv_sched_n = 1, rv_sched_cur = 0;
// n starts at 1: slot 0 is the caller
U0 RVYield()
{
  //Cooperatively hand the CPU to the next runnable task (round-robin).
  I64 prev = rv_sched_cur, start = rv_sched_cur;
  while (TRUE) {
    rv_sched_cur = (rv_sched_cur + 1) % rv_sched_n;
    if (!rv_sched_done[rv_sched_cur] || rv_sched_cur == prev || rv_sched_cur == start)
      break;
  }
  RVTaskSwitch(&rv_sched_ctx[prev *RV_CTX_WORDS], &rv_sched_ctx[rv_sched_cur *RV_CTX_WORDS]);
}

U0 RVTaskExit()
{
  //Mark the current task finished and yield away for good (never returns).
  rv_sched_done[rv_sched_cur] = TRUE;
  RVYield();
}

I64 RVSpawn(U0 (*fn)())
{
  //Create a task that begins at fn on a fresh 16 KB stack. Returns its slot, or -1 if full.
  if (rv_sched_n >= RV_MAX_TASKS)
    return -1;
  U8 *stk = CAlloc(16384);
  I64 slot = rv_sched_n;
  rv_sched_ctx[slot *RV_CTX_WORDS + 0] = fn;
  // ra -> entry
  rv_sched_ctx[slot *RV_CTX_WORDS + 1] = (stk + 16384 - 16) & (~15);
  // sp -> aligned stack top
  rv_sched_done[slot] = FALSE;
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
U8 *MAlloc(I64 size, CTask *mem_task = NULL)
{
  I64 need = (size + offset(CMemUsed.start) + 15) & (~15);
  CMemUnused *f = the_heap->malloc_free_lst, *prev = NULL;
  while (f && f->size < need) {
    prev = f;
    f = f->next;
  }
  U8 *chunk;
  I64 usize;
  CMemUnused *tail;
  if (f) {
    if (prev)
      prev->next = f->next;
    else
      the_heap->malloc_free_lst = f->next;
    chunk = f;
    usize = f->size;
    // Split the remainder back onto the free list. Without this, first-fit hands a whole
    // freed page to a 33-byte MStrPrint buffer and the rest is lost for good: the 64 MB
    // arena (0x82000400..fb at 0x86100000) drained in ~90 s of idle Win compositing and
    // MAlloc started returning NULL, which SPutChar uses unchecked -> MemCpy(NULL,..).
    // Keep a remainder only if it can still carry a header plus a payload.
    if (usize - need >= offset(CMemUsed.start) + 16) {
      tail = chunk + need;
      tail->size = usize - need;
      tail->next = the_heap->malloc_free_lst;
      the_heap->malloc_free_lst = tail;
      usize = need;
    }
  } else {
    if (heap_next + need > heap_end)
      return NULL;
    chunk = heap_next;
    heap_next += need;
    usize = need;
  }
  CMemUsed *u = chunk;
  u->hc = the_heap;
  u->size = usize;
  the_heap->used_u8s += usize;
  return chunk + offset(CMemUsed.start);
}

U0 Free(U8 *ptr)
{
  if (!ptr)
    return;
  CMemUsed *u = ptr - offset(CMemUsed.start);
  CMemUnused *fu = u;
  I64 sz = u->size;
  the_heap->used_u8s -= sz;
  // MAlloc adds it; without this used_u8s only ever grows
  fu->size = sz;
  fu->next = the_heap->malloc_free_lst;
  the_heap->malloc_free_lst = fu;
}
// MSize / MSize2 are the other two x86-asm allocator primitives (_MSIZE / _MSIZE2 in MAllocFree.HC);
// their RISC-V port must read the same CMemUsed header this MAlloc writes, or the kernel's MSize-using
// code (and CAlloc, which zeroes MSize() bytes) sees garbage sizes. Mirrors _MSIZE exactly: the chunk
// size lives in CMemUsed.size; MAllocAligned marks aligned chunks with a NEGATIVE size that points back
// to the real header, so follow it. MSize returns the usable size (chunk minus header); MSize2 the
// internal size (whole chunk).
I64 MSize2(U8 *src)
{
  if (!src)
    return 0;
  CMemUsed *u = src - offset(CMemUsed.start);
  I64 sz = u->size;
  if (sz < 0) {
    u = (src + sz) - offset(CMemUsed.start);
    sz = u->size;
  }
  return sz;
}

I64 MSize(U8 *src)
{
  if (!src)
    return 0;
  return MSize2(src) - offset(CMemUsed.start);
}
// --- Boot tasks / mount / Spawn helpers used by RVKMain (see RVKMain.HC) ----------------------
// A from-scratch boot: the kernel brings ITSELF up and schedules its first task, instead of a demo
// hand-wiring adam. Only the portable "bucket 1" of KMain() runs in RVKMain — set up the heap, create
// Adam, and Spawn the first task, then schedule it with the kernel's own Yield(). The display,
// block-device, file-system, compiler and StartOS buckets, and the x86 timer/interrupt/MP buckets,
// are named in the //x86: and //phase 3: comments in RVKMain.HC the way Kernel_RV.PRJ comments out
// KInts/MultiProc/FunSeg — the gap is auditable, not hidden.
U0 RVBootTask()
{
  //The first task Adam spawns: prints a boot banner and exits. Its line proves the kernel scheduled a
  //real CTask that its OWN Spawn() created — i.e. it booted itself, not that a demo set adam up.
  Print("TempleOS/RISC-V: Adam booted and scheduled its first task.\n");
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield();
}
I64 rv_boot_spins = 0;
U0 RVBootTask2()
{
  //A second task that NEVER yields inside its work loop. Only the machine-timer preemption Adam arms
  //lets Adam and the other task keep running while this one spins — so its progress is proof the
  //self-booted kernel PREEMPTS, not merely cooperates. Yields once at the end only to leave for good.
  I64 target = rv_boot_spins + 2000000;
  while (rv_boot_spins < target)
    rv_boot_spins++;
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield();
}
// Mount a RAM disk as drive `drv_let` and bring up the kernel's own RedSea filesystem on it — the
// RISC-V stand-in for KMain()'s BlkDevsInitAll / DskChg. Everything below BlkDevAdd is the kernel's
// own Kernel/BlkDev/*.HC: BlkDevInit auto-formats a blank RAM disk with RedSeaFmt, Drv() selects it.
// The x86 boot uses a physical ATA disk; on QEMU virt a BDT_RAM disk needs no device driver at all
// (BlkRead/BlkWrite MemCpy to/from the buffer). blocks*512 bytes are allocated from the heap.
// Ensure BlkDev + Drv letter tables (BlkDevsInitAll runtime half, no MountIDEAuto).
U0 RVBlkDevTablesInit()
{
  I64 i;
  // Per-field, not `if (blkdev.blkdevs) return;`. That guard tested ONE field and then
  // assigned three, so a run that stopped after the first store latched it: every later call
  // returned immediately and blkdev.drvs stayed NULL for the life of the image. Read out of a
  // live kernel-span image with gdb -- blkdevs=0x82000430, drvs=0, let_to_drv[0]=[1]=0 (not
  // 0xa0, which is what &NULL[1] would give had only the drvs store been lost, so execution
  // really did stop between the two CAllocs). RVMountRAMDisk calls this and is entitled to
  // assume it worked; instead BlkDevAdd -> DrvMakeFreeSlot did MemSet(NULL,0,sizeof(CDrv)).
  // Whatever unwinds between the CAllocs is still open (docs/NEXT_STEPS.md 3.1b-bis); this
  // makes a half-done run recoverable instead of permanent and silent.
  if (!blkdev.blkdevs)
    blkdev.blkdevs = CAlloc(sizeof(CBlkDev) * BLKDEVS_NUM);
  if (!blkdev.drvs) {
    blkdev.drvs = CAlloc(sizeof(CDrv) * DRVS_NUM);
    for (i = 0; i < DRVS_NUM; i++)
      blkdev.let_to_drv[i] = &blkdev.drvs[i];
  }
}
// G28 soft letter: plant signed CBlkDev+CDrv so Let2Drv(let) works without
// virtio / RedSeaFmt. Type follows Let2BlkDevType (A:→BDT_RAM, P:→ISO_FILE_READ
// stock map — 9P share letter). Soft plant clears RO/cache; does NOT set
// Fs->cur_dv — soft Cd / DirCur / DirNameAbs stay on !cur_dv `::/…` until Drv().
// Idempotent: returns existing Let2Drv if already signed. Quiet (no Print) for
// thin demos that call via Virtio9pConnect before console put_s is wired.
public CDrv *RVSoftLetPlantQuiet(U8 drv_let = 'A')
{
  CBlkDev *bd;
  CDrv *dv;
  I64 type;
  drv_let = ToUpper(drv_let);
  if (!('A' <= drv_let && drv_let <= 'Z'))
    return NULL;
  RVBlkDevTablesInit;
  if (dv = Let2Drv(drv_let, FALSE))
    return dv;
  type = Let2BlkDevType(drv_let);
  if (type == BDT_NULL)
    return NULL;
  bd = BlkDevNextFreeSlot(drv_let, type);
  // Soft letter-only: not a real ISO/ATA mount — drop RO/cache from type defaults.
  bd->flags &= ~(BDF_READ_ONLY | BDF_READ_CACHE);
  bd->unit = 0;
  bd->RAM_dsk = 0;
  bd->max_blk = 0;
  bd->bd_signature = BD_SIGNATURE_VAL;
  // No BDf_INITIALIZED — BlkDevAdd/BlkDevInit may still format later.
  dv = DrvMakeFreeSlot(drv_let);
  dv->bd = bd;
  dv->drv_offset = bd->drv_offset;
  dv->size = 0;
  dv->dv_signature = DRV_SIGNATURE_VAL;
  dv->fs_type = FSt_UNKNOWN;
  if (!blkdev.boot_drv_let)
    blkdev.boot_drv_let = drv_let;
  return dv;
}

public CDrv *RVSoftLetPlant(U8 drv_let = 'A')
{
  CDrv *dv;
  drv_let = ToUpper(drv_let);
  dv = RVSoftLetPlantQuiet(drv_let);
  if (dv)
    Print("RVSoftLetPlant: let=%c boot=%c type=%d (no cur_dv)\n", drv_let, blkdev.boot_drv_let, dv->bd->type);
  return dv;
}
// G28: plant P: as the virtfs/9P share letter (Let2Drv('P'); Cd("P:/…") soft).
// Idempotent; does not require virtio — Virtio9pConnect also calls quiet plant.
public CDrv *RVSoftLet9pPlant(U8 drv_let = 'P')
{
  CDrv *dv;
  drv_let = ToUpper(drv_let);
  if (!drv_let)
    drv_let = 'P';
  dv = RVSoftLetPlant(drv_let);
  if (dv) {
    dv->fs_type = FSt_9P;
    // Mark INIT so Drv('P') skips ISO BlkDevInit; FSt_9P is the real mount.
    if (dv->bd)
      LBts(&dv->bd->flags, BDf_INITIALIZED);
    Print("RVSoftLet9pPlant: let=%c fs=9P (9P share)\n", dv->drv_let);
  }
  return dv;
}

public CDrv *RVSoftLet9pPlantQuiet(U8 drv_let = 'P')
{
  CDrv *dv;
  drv_let = ToUpper(drv_let);
  if (!drv_let)
    drv_let = 'P';
  dv = RVSoftLetPlantQuiet(drv_let);
  if (dv) {
    dv->fs_type = FSt_9P;
    if (dv->bd)
      LBts(&dv->bd->flags, BDf_INITIALIZED);
  }
  return dv;
}
// TempleOS KMain HomeSet after BlkDevsInitAll/DskChg. Win/soft images often
// left blkdev.home_dir=NULL → stock Cd("~") StrLen(home_dir+2) mtval=2.
// SoftCd null→Cd("") stay-put for PopUp Cd; is separate and must stay green.
// Call after mount returns (not inside BlkDevAdd path — keeps format fast/honest).
public U0 RVHomeBringUp(U8 drv_let = 'A')
{
  U8 *path;
  if (!Fs || !Fs->cur_dv)
    return;
  drv_let = ToUpper(drv_let);
  if (!blkdev.boot_drv_let)
    blkdev.boot_drv_let = drv_let;
  path = MStrPrint("%c:/Home", drv_let);
  HomeSet(path);
  Free(path);
  Print("RVHomeBringUp: home=%s boot=%c\n", blkdev.home_dir, blkdev.boot_drv_let);
}

U0 RVMountRAMDisk(U8 drv_let, I64 blocks)
{
  // The runtime half of BlkDevsInitAll (its #exe half would emit the x86 MountIDEAuto): allocate the
  // block-device and drive tables and wire the drive-letter map. Guard against a second call.
  CBlkDev *bd;
  CDrv *dv;
  RVBlkDevTablesInit;
  drv_let = ToUpper(drv_let);
  // Reuse G28 soft letter if present (same BlkDev slot); else take a free slot.
  dv = Let2Drv(drv_let, FALSE);
  if (dv && dv->bd && dv->bd->bd_signature == BD_SIGNATURE_VAL && !(dv->bd->flags & BDF_INITIALIZED)) {
    bd = dv->bd;
    bd->type = BDT_RAM;
    bd->first_drv_let = drv_let;
  } else if (dv && dv->bd && (dv->bd->flags & BDF_INITIALIZED)) {
    Drv(drv_let);
    return;
  } else
    bd = BlkDevNextFreeSlot(drv_let, BDT_RAM);
  bd->unit = 0;
  bd->RAM_dsk = 0;
  bd->max_blk = blocks - 1;
  // RAM_dsk=0 -> BlkDevInit AMAllocs blocks*512 B
  BlkDevAdd(bd, I64_MIN, FALSE, TRUE);
  // -> BlkDevInit -> RedSeaFmt on a blank disk
  Drv(drv_let);
  // sets Fs->cur_dv, Fs->cur_dir="/"
}
// Spawn with ADD_TO_QUE=0, then link into adam's next_task ring.
// Spawn() already plants HolyRVCtxSw via RVKFixSpawnFrame (mepc=0-safe).
CTask *RVKSpawn(U0 (*entry)(), U8 *name, CTask *adam)
{
  CTask *t = Spawn(entry, NULL, name, -1, adam, 0, 0);
  if (!t->rip)
    Print("RVKSpawn WARNING: entry rip=0 for %s\n", name);
  t->next_task = adam->next_task;
  t->last_task = adam;
  adam->next_task->last_task = t;
  adam->next_task = t;
  return t;
}
// RVKMain lives in RVKMain.HC (included after RVFb/RVGr so boot can call RVSysGrInit).
