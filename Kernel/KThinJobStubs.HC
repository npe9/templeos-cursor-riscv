// KThinJobStubs.HC — RV_THIN_LOADER: SoftCall Jump never queues Jobs/Spawn servants.
// Full Job.HC stays out of thin PRJ (JobRunOne/TaskExe/…). SoftCall KernelTaskSoft
// proves JobQue JOBT_CALL + JobRunOne in Kernel.BIN (→'KJ').
#ifndef K_THIN_JOB_STUBS_HC
#define K_THIN_JOB_STUBS_HC
U0 JobDel(CJob *tmpc)
{
  if (tmpc) {
    Free(tmpc->aux_str);
    Free(tmpc);
  }
}

U0 JobQueDel(CJob *head)
{
  CJob *tmpc, *tmpc1;
  if (!head)
    return;
  tmpc = head->next;
  while (tmpc != head) {
    tmpc1 = tmpc->next;
    QueRem(tmpc);
    JobDel(tmpc);
    tmpc = tmpc1;
  }
}

U0 JobCtrlInit(CJobCtrl *ctrl)
{
  if (!ctrl)
    return;
  QueInit(&ctrl->next_waiting);
  QueInit(&ctrl->next_done);
  ctrl->flags = 0;
}

U0 TaskRstAwaitingMsg(CTask *task = NULL)
{
  no_warn task;
}

CJob *TaskExe(CTask *srv, CTask *master, U8 *data, I64 flags)
{
  no_warn srv;
  no_warn master;
  no_warn data;
  no_warn flags;
  return NULL;
}

CJob *TaskText(CTask *srv, CTask *master, U8 *data, I64 flags)
{
  no_warn srv;
  no_warn master;
  no_warn data;
  no_warn flags;
  return NULL;
}

CJob *TaskMsg(CTask *_srv, CTask *master, I64 msg_code, I64 arg1, I64 arg2, I64 flags)
{
  no_warn _srv;
  no_warn master;
  no_warn msg_code;
  no_warn arg1;
  no_warn arg2;
  no_warn flags;
  return NULL;
}

Bool JobResScan(CJob *rqst = NULL, I64 *_res = NULL)
{
  no_warn rqst;
  if (_res)
    *_res = 0;
  return FALSE;
}

I64 JobResGet(CJob *rqst = NULL)
{
  no_warn rqst;
  return 0;
}

I64 JobRunOne(I64 run_flags, CJobCtrl *ctrl)
{
  no_warn run_flags;
  no_warn ctrl;
  return 0;
}

I64 JobsHndlr(I64 run_flags, CTask *task = NULL)
{
  no_warn run_flags;
  no_warn task;
  return 0;
}
#endif
