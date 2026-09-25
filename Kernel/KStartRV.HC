// RISC-V stand-in for KStart16/KStart32/KStart64: the boot-time data the x86 startup code
// exports as asm labels. Each is a one-element array so the name is an address, as it is
// on x86 (`*SYS_RUN_LEVEL(I64 *)`, `MEM_E820` as a table base). Phase 2 of
// docs/RISCV_PORT_PLAN.md fills these from the device tree in the RISC-V startup.
U64 MEM_HEAP_BASE[1];
U64 MEM_HEAP_LIMIT[1];
U64 MEM_PAGE_SIZE[1];
U64 MEM_MAPPED_SPACE[1];
U64 MEM_2MEG_NUM[1];
U64 MEM_1GIG_NUM[1];
U64 MEM_512GIG_NUM[1];
U64 MEM_PML2[1];
U64 MEM_PML3[1];
U64 MEM_PML4[1];
U64 SYS_HEAP_DBG_FLAG[1];
U64 SYS_CTRL_ALT_FLAGS[1];
U64 SYS_CODE_BP[1];
U64 SYS_DATA_BP[1];
U64 SYS_PROGRESSES[1];
U64 SYS_FOCUS_TASK[1];
U64 SYS_CPU_STRUCTS[1];
U64 SYS_MP_CNT[1];
U64 SYS_MP_CNT_INITIAL[1];
U64 SYS_MP_CNT_LOCK[1];
U64 SYS_CACHE_LINE_WIDTH[1];
U64 SYS_SEMAS[1];
U64 SYS_BOOT_SRC[1];
U64 SYS_BOOT_BLK[1];
U64 SYS_BOOT_PATCH_TABLE_BASE[1];
U64 SYS_RUN_LEVEL[1];
U64 MEM_BOOT_BASE[1];
U64 MEM_E801[1];
U64 MEM_PHYSICAL_SPACE[1];
U64 SYS_PCI_BUSES[1];
U64 SYS_GDT[1];
U64 SYS_ENTER_LONG_MODE[1];
U8 MEM_E820[1024];
// CMemE820 table
U8 SYS_GDT_PTR[16];
U8 _RET[4];
U8 COREAP_16BIT_INIT[1];
U8 COREAP_16BIT_INIT_END[1];
// x86 `RET` label the debugger compares task->rip against
// Keyboard.HC scan-code tables (asm data in the x86 file)
U8 NORMAL_KEY_SCAN_DECODE_TABLE[256];
U8 SHIFT_KEY_SCAN_DECODE_TABLE[256];
U8 CTRL_KEY_SCAN_DECODE_TABLE[256];
// Functions the excluded x86 files define (KInts, MultiProc, FunSeg): stubs with the same
// signatures so the rest of the kernel compiles; phase 2 ports them.
U8 *IntEntryGet(I64 irq)
{
  return NULL;
}

U8 *IntEntrySet(I64 irq, U0 (*fp_new_hndlr)(), I64 type = 0, I64 dpl = 0)
{
  return NULL;
}

U8 *IntFaultHndlrsNew()
{
  return NULL;
}

U0 IntInit1()
{
}

U0 IntInit2()
{
}

U0 IntsInit()
{
}

U0 Core0Init()
{
}

U0 Core0StartMP()
{
  // Phase G: secondaries enter via crt0_smp (-smp N -bios none).
  // RVSmpMpCnt() reflects alive bits; full Seth JobQue / mp_cnt finalize still thin.
  // See Kernel/Drv/RVSmp.HC + make kernel-smp-smoke.
}

U0 CoreAPSethTask()
{
}

U0 MPHalt()
{
  while (TRUE)
    HLT;
}

U0 MPInt(U8 num, I64 cpu_num = 1)
{
}

U0 MPIntAll(U8 num)
{
}

U0 MPNMInt()
{
}

U0 TSSBusy(I64 tr, Bool val = OFF)
{
}

// JobQue is NOT here any more. The real single-hart one is Kernel/RVJob.HC, included after Job.HC
// because its body needs CAlloc/QueIns/Fs; the thin-loader stub is in KThinJobStubs.HC with the
// other thin job stubs. Keeping it here behind an #ifdef would have hidden it from
// tools/check_prj_collisions.py, which reads the PRJ's #ifdefs and not each file's.

CTask *SpawnQue(U0 (*fp_addr)(U8 *data), U8 *data = NULL, U8 *task_name = NULL, I64 target_cpu = 0, CTask *parent = NULL, I64 stk_size = 0, I64 flags = 0)
{
  return NULL;
}

Bool E(U8 *addr, I64 cnt = 512, I64 edf_dof_flags = 0)
{
  return FALSE;
}

Bool Man(U8 *st, I64 edf_dof_flags = 0)
{
  return FALSE;
}

CHash *FunSegFind(U8 *addr, I64 *_offset)
{
  return NULL;
}

Bool PutSrcLink(U8 *addr, I64 cnt = 1, U8 *buf = NULL)
{
  return FALSE;
}

U8 *SrcEdLink(U8 *addr, I64 cnt = 1, CTask *mem_task = NULL)
{
  return NULL;
}

U8 *SrcFileName(U8 *addr, I64 cnt = 1, CTask *mem_task = NULL)
{
  return NULL;
}

I64 SrcLineNum(U8 *addr, I64 cnt = 1)
{
  return 0;
}

U0 StrPrintFunSeg(U8 *buf, I64 addr, I64 field_len, I64 flags)
{
}
