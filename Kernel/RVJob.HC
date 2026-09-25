// RVJob.HC — a single-hart JobQue, so JobResGet returns instead of spinning forever.
//
// Stock JobQue lives in Kernel/MultiProc.HC, which is x86 and not in this project. It hands the job
// to the Seth task of `target_cpu` and returns immediately; that servant runs it and posts the
// result on the CPU's done queue. RISC-V has no Seth tasks yet, so KStartRV.HC's stand-in returned
// NULL — and JobResGet(NULL) then spins in
//
//   while (tmpc1==tmpc1->next) { LBts(&Fs->task_flags,TASKf_IDLE); Yield; }
//
// on a done queue nothing will ever post to. `tools/hangpc.sh Demo/MultiCore/Lock.HC` samples
// `ra=JobResGet+0x14c` three times over for exactly that reason, and it is why
// Demo/MultiCore/Primes.HC ran while measuring nothing.
//
// One hart, so run the job HERE and hand back a FINISHED CJob on the caller's own done queue.
// JobResGet's `while (!Bt(&rqst->flags,JOBf_DONE))` is then already satisfied and its JobResScan
// dequeues and frees it.
//
// What this is NOT: parallel. Demo/MultiCore/Lock.HC exists to show that two cores racing on
// `glbl++` LOSE counts without a `lock` prefix; run serially, both totals come out correct. The
// demo prints real numbers instead of hanging, which is strictly better than a hang, but it no
// longer demonstrates the race. That needs Seth tasks per hart — Kernel/Drv/RVSmp.HC already has
// the hart wake.

CJob *JobQue(I64 (*fp_addr)(U8 *data), U8 *data = NULL,
             I64 target_cpu = 1, I64 flags = 1 << JOBf_FREE_ON_COMPLETE,
             I64 job_code = JOBT_CALL, U8 *aux_str = NULL, I64 aux1 = 0, I64 aux2 = 0)
{
  //Run a job. One hart: it runs before this returns. Stock: queue it to target_cpu's Seth task.
  //Set flags to zero if you wish to get the res, as stock documents.
  CJob *tmpc;
  no_warn target_cpu;
  if (!Fs)
    return NULL;
  tmpc = CAlloc(sizeof(CJob));
  tmpc->job_code = job_code;
  tmpc->addr = fp_addr;
  tmpc->fun_arg = data;
  tmpc->flags = flags;
  tmpc->aux1 = aux1;
  tmpc->aux2 = aux2;
  if (aux_str)
    tmpc->aux_str = AStrNew(aux_str);
  tmpc->ctrl = &Fs->srv_ctrl;
  tmpc->master_task = Fs;
  if (fp_addr)
    tmpc->res = (*fp_addr)(data);
  LBts(&tmpc->flags, JOBf_DONE);
  if (Bt(&tmpc->flags, JOBf_FREE_ON_COMPLETE)) {
    // The caller said it does not want the result, and there is no servant to free it later.
    // Freeing here is what keeps a loop of fire-and-forget jobs from growing the done queue.
    Free(tmpc->aux_str);
    Free(tmpc);
    return NULL;
  }
  QueIns(tmpc, Fs->srv_ctrl.last_done);
  return tmpc;
}
