// Multi-hart / SMP helpers (TempleOS master/Seth shape).
// Boot secondaries with QEMU virt -smp N -bios none (all harts enter crt0_smp).
// OpenSBI HSM is not required for that path; use HSM when firmware owns hart bring-up.
#ifndef RV_DRV_SMP_HC
#define RV_DRV_SMP_HC
#ifndef CONFIG_CLINT_BASE
#define CONFIG_CLINT_BASE 0x02000000
#endif
#ifndef CONFIG_SMP_MAILBOX_BASE
#define CONFIG_SMP_MAILBOX_BASE 0x87001E00
#endif
// Shared mailbox with tests/exec/harness/crt0_smp.S (CONFIG_SMP_MAILBOX_BASE).
#define RV_SMP_ENTRY CONFIG_SMP_MAILBOX_BASE
#define RV_SMP_ARG   (CONFIG_SMP_MAILBOX_BASE+0x08)
#define RV_SMP_DONE  (CONFIG_SMP_MAILBOX_BASE+0x10)
#define RV_SMP_ALIVE (CONFIG_SMP_MAILBOX_BASE+0x18)
#define RV_SMP_MAX_HARTS 8
// RVHartId -- RVHartId()
// NAME
//   RVHartId - read mhartid
// SYNOPSIS
//   I64 RVHartId();
// DESCRIPTION
//   Hardware thread id (CSR mhartid). Hart 0 is the master (UART REPL / OS);
//   secondaries park then run Seth-style work via RVSmpWake.
// SEE ALSO
//   RVSmpWake  RVSmpAlive  GetMHartId  SMP
asm {
	RVHartId::
	csrr	a0,0xF14
	ret
}
// RVAmoAddI64 -- RVAmoAddI64(dst,inc)
// NAME
//   RVAmoAddI64 - atomic *dst += inc (amoadd.d), return old value
// SYNOPSIS
//   I64 RVAmoAddI64(I64 *dst,I64 inc);
// DESCRIPTION
//   A-extension amoadd.d. Use for shared counters across harts.
// SEE ALSO
//   LXchgI64  LBts  lock
asm {
	RVAmoAddI64::
	amoadd.d	a0,a1,(a0)
	ret
}
// RVSmpMsieEnable -- RVSmpMsieEnable()
// NAME
//   RVSmpMsieEnable - set mie.MSIE so MSIP can wake WFI
// SYNOPSIS
//   U0 RVSmpMsieEnable();
// DESCRIPTION
//   crt0_smp enables this on secondaries at park time; call on hart 0 if needed.
asm {
	RVSmpMsieEnable::
	li	t0,8
	csrs	mie,t0
	ret
}
// RVSmpMsip -- RVSmpMsip(hart,v)
// NAME
//   RVSmpMsip - write CLINT software-interrupt pending for hart
// SYNOPSIS
//   U0 RVSmpMsip(I64 hart,I64 v);
// DESCRIPTION
//   Stores to CLINT msip[hart] (CONFIG_CLINT_BASE + 4*hart). Nonzero wakes a
//   WFI-parked secondary when mie.MSIE is set (crt0_smp).
U0 RVSmpMsip(I64 hart, I64 v)
{
  U32 *msip = CONFIG_CLINT_BASE + hart * 4;
  *msip = v & 1;
}
// RVSmpAlive -- RVSmpAlive()
// NAME
//   RVSmpAlive - bitmask of harts that reached crt0_smp
// SYNOPSIS
//   I64 RVSmpAlive();
I64 RVSmpAlive()
{
  return *(I64 *)RV_SMP_ALIVE;
}
// RVSmpMpCnt -- RVSmpMpCnt()
// NAME
//   RVSmpMpCnt - count of harts with alive bit set
// SYNOPSIS
//   I64 RVSmpMpCnt();
// DESCRIPTION
//   popcount(RVSmpAlive). Not the full TempleOS mp_cnt finalize path.
I64 RVSmpMpCnt()
{
  I64 alive = RVSmpAlive(), n = 0, i;
  for (i = 0; i < RV_SMP_MAX_HARTS; i++)
    if (alive & (1 << i))
      n++;
  return n;
}
// RVSmpWakeHart -- RVSmpWakeHart(hart,fn,arg)
// NAME
//   RVSmpWakeHart - hand one job to a parked secondary hart
// SYNOPSIS
//   U0 RVSmpWakeHart(I64 hart,I64 (*fn)(I64),I64 arg);
// DESCRIPTION
//   Sets the shared mailbox (entry,arg), clears done, and pokes MSIP for hart.
//   Single mailbox — only one pending job. Wait with RVSmpWait.
U0 RVSmpWakeHart(I64 hart, I64 (*fn)(I64), I64 arg)
{
  if (hart < 1 || hart >= RV_SMP_MAX_HARTS)
    return;
  *(I64 *)RV_SMP_DONE = 0;
  *(I64 *)RV_SMP_ARG = arg;
  *(I64 *)RV_SMP_ENTRY = fn;
  RVSmpMsip(hart, 1);
}
// RVSmpWake -- RVSmpWake(fn,arg)
// NAME
//   RVSmpWake - hand one job to hart 1 (Seth-style default)
// SYNOPSIS
//   U0 RVSmpWake(I64 (*fn)(I64),I64 arg);
U0 RVSmpWake(I64 (*fn)(I64), I64 arg)
{
  RVSmpWakeHart(1, fn, arg);
}
// RVSmpWait -- RVSmpWait()
// NAME
//   RVSmpWait - spin until secondary posts rv_smp_done
// SYNOPSIS
//   U0 RVSmpWait();
U0 RVSmpWait()
{
  while (!*(I64 *)RV_SMP_DONE)
    ;
}
#endif
