// KThinTaskStubs.HC — RV_THIN_LOADER: minimal Adam TaskInit for MMIO+LoadBuf+Jump.
// Full KTask (Spawn/TaskEnd/ExeCmdLine/…) stays out (~23 KiB). SoftCall owns
// real TaskInit+Spawn+JobRunOne after KernelEntry (KernelTaskSoft →'KJ');
// thin never Spawns or Yields a servant queue.
#ifndef K_THIN_TASK_STUBS_HC
#define K_THIN_TASK_STUBS_HC
Bool TaskValidate(CTask *task)
{
  if (!task || task->addr != task || task->task_signature != TASK_SIGNATURE_VAL)
    return FALSE;
  return TRUE;
}

I64 TaskInit(CTask *task, I64 stk_size)
{
  // Minimal Adam: self-ring + heaps already set by RVKMain. Small hash for
  // thin Jump LoadBuf→HashAdd→HashFind (not full TASK_HASH_TABLE_SIZE).
  no_warn stk_size;
  if (!task)
    return 0;
  task->task_signature = TASK_SIGNATURE_VAL;
  task->addr = task->next_task = task->last_task = task->next_input_filter_task = task->last_input_filter_task = task;
  task->task_num = sys_num_spawned_tasks++;
  task->rflags = RFLAGG_NORMAL;
  task->win_inhibit = WIG_TASK_DFT;
  task->next_child_task = task->last_child_task = (&task->next_child_task)(U8 *) - offset(CTask.next_sibling_task);
  JobCtrlInit(&task->srv_ctrl);
  QueInit(&task->next_cc);
  QueInit(&task->next_except);
  QueInit(&task->next_ctrl);
  QueInit(&task->next_ode);
  task->hash_table = HashTableNew(RV_THIN_HASH_BUCKETS, task);
  task->stk = NULL;
  task->fpu_mmx = NULL;
  task->cur_dir = NULL;
  task->cur_dv = NULL;
  task->text_attr = WHITE << 4 + BLUE;
  task->border_src = BDS_CONST;
  task->border_attr = WHITE << 4 + BLUE;
  task->title_src = TTS_CONST;
  return task;
}

U0 TaskDerivedValsUpdate(CTask *task = NULL, Bool update_z_buf = TRUE)
{
  no_warn update_z_buf;
  if (!task)
    task = Fs;
  if (task)
    WinDerivedValsUpdate(task);
}

U0 RVKFixSpawnFrame(CTask *task)
{
  no_warn task;
}

CTask *Spawn(U0 (*fp_start_addr)(U8 *data), U8 *data = NULL, U8 *task_name = NULL, I64 target_cpu = -1, CTask *parent = NULL, I64 stk_size = 0, I64 flags = 1 << JOBf_ADD_TO_QUE)
{
  no_warn fp_start_addr;
  no_warn data;
  no_warn task_name;
  no_warn target_cpu;
  no_warn parent;
  no_warn stk_size;
  no_warn flags;
  return NULL;
}

U0 Exit()
{
  LBts(&Fs->task_flags, TASKf_KILL_TASK);
}

I64 TaskEnd()
{
  return Fs;
}

U0 TaskDel(CTask *task)
{
  no_warn task;
}

U0 TaskKillDying()
{
}

Bool Kill(CTask *task, Bool wait = TRUE, Bool just_break = FALSE)
{
  no_warn wait;
  no_warn just_break;
  if (TaskValidate(task))
    LBts(&task->task_flags, TASKf_KILL_TASK);
  return TRUE;
}

Bool Suspend(CTask *task = NULL, Bool state = TRUE)
{
  no_warn state;
  no_warn task;
  return FALSE;
}

Bool IsSuspended(CTask *task = NULL)
{
  no_warn task;
  return FALSE;
}

I64 BirthWait(CTask **_task, I64 task_num = -1)
{
  no_warn _task;
  no_warn task_num;
  return 0;
}

U0 DeathWait(CTask **_task, Bool send_exit = FALSE)
{
  no_warn _task;
  no_warn send_exit;
}

U0 TaskWait(CTask *task = NULL, Bool cmd_line_pmt = FALSE)
{
  no_warn task;
  no_warn cmd_line_pmt;
}

U0 TaskQueIns(CTask *task, CTask *pred = NULL)
{
  no_warn task;
  no_warn pred;
}

U0 TaskQueRem(CTask *task)
{
  no_warn task;
}

U0 SrvTaskCont()
{
}

U0 UserTaskCont()
{
}

I64 ExeCmdLine(CCmpCtrl *cc)
{
  no_warn cc;
  return 0;
}

U0 SrvCmdLine(I64 dummy = 0)
{
  no_warn dummy;
}

U0 UserCmdLine(I64 dummy = 0)
{
  no_warn dummy;
}
#endif
