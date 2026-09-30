// Differential oracle, HolyC side: drives the 1:1 translation of OSAL's portable error module
// and prints the same transcript as tests/osal/oracle_osal.c does against the unmodified C.
// Standalone on purpose -- no kernel includes -- so the only things under test are the
// translation and the compiler.
#include "/Kernel/Cfs/osal/os_shared_errors.HC"

// --- the four TempleOS primitives the KERNEL provides ------------------------------------------
// This harness is standalone by design -- no kernel is linked, because the only thing under test
// is the translation -- so MemSet, MemCpy, StrCmp and StrLen have to be supplied here. They are
// the kernel's, not C's, and the semantics are matched deliberately:
//
//   MemSet/MemCpy  RVMemSet(dst,dat,size) / RVMemCpy(dst,src,size) in Kernel/KCmpStubsRV.HC --
//                  C's argument order, returning dst.
//   StrCmp         _STRCMP in Kernel/StrA.HC:85 returns only -1, 0 or +1, NOT a byte
//                  difference. Reproduced exactly: if this returned a difference while the
//                  kernel returns +-1, the oracle would be validating behaviour that does not
//                  ship. Every cFS call site compares against zero, so the two agree there.
//   StrLen         RVStrLen.
//
// These names would otherwise resolve against the host C runtime (they are in
// bootstrap/holy_rt_names.h) and the blob's import trailer is what would catch that -- the gate
// asserts the trailer is empty for exactly this reason.
U8 *MemSet(U8 *dst, I64 dat, I64 size)
{
  I64 i = 0;
  while (i < size) {
    dst[i] = dat & 0xFF;
    i++;
  }
  return dst;
}
U8 *MemCpy(U8 *dst, U8 *src, I64 size)
{
  I64 i = 0;
  while (i < size) {
    dst[i] = src[i];
    i++;
  }
  return dst;
}
I64 StrLen(U8 *st)
{
  I64 n = 0;
  while (st[n])
    n++;
  return n;
}
I64 StrCmp(U8 *st1, U8 *st2)
{
  I64 i = 0;
  while (st2[i]) {
    if (st1[i] != st2[i]) {
      if (st2[i] > st1[i])
        return -1;
      return 1;
    }
    i++;
  }
  if (st1[i])
    return 1;
  return 0;
}

// Three more the kernel provides, needed once osapi-filesys.c is in the build. The blob's
// import trailer is what caught their absence: without these they bound silently to the host C
// runtime and the transcript would still have passed.
//
// StrOcc and StrLastOcc are HolyC in Kernel/StrA.HC, so these are that code, not a rewrite of
// it. StrNCmp and StrMatch are asm externs (_STRNCMP at StrA.HC:322, _STRMATCH at :316) and
// these reproduce what the assembly does:
//   StrNCmp(st1, st2, n)     st2 in RSI, st1 in RDI, JA -> -1, so st1 < st2 is negative, the
//                            magnitude is only ever +-1, and n == 0 returns 0.
//   StrMatch(needle, hay)    ARGUMENTS REVERSED from C's strstr. NULL for either gives NULL,
//                            and an EMPTY needle returns the haystack pointer, as strstr does.
I64 StrOcc(U8 *src, I64 ch)
{
  I64 i = 0;
  if (!src)
    return 0;
  while (*src)
    if (*src++ == ch)
      i++;
  return i;
}

U8 *StrLastOcc(U8 *src, U8 *marker)
{
  I64 ch;
  U8 *res = NULL;
  while (ch = *src++)
    if (StrOcc(marker, ch))
      res = src - 1;
  return res;
}

I64 StrNCmp(U8 *st1, U8 *st2, I64 n)
{
  I64 i = 0;
  while (i < n) {
    if (!st2[i]) {
      if (st1[i])
        return 1;
      return 0;
    }
    if (st1[i] != st2[i]) {
      if (st2[i] > st1[i])
        return -1;
      return 1;
    }
    i++;
  }
  return 0;
}

U8 *StrMatch(U8 *needle, U8 *haystack_str)
{
  I64 i, j;
  if (!needle || !haystack_str)
    return NULL;
  if (!*needle)
    return haystack_str;
  i = 0;
  while (haystack_str[i]) {
    j = 0;
    while (needle[j] && haystack_str[i + j] == needle[j])
      j++;
    if (!needle[j])
      return &haystack_str[i];
    i++;
  }
  return NULL;
}
#define XUART 0x10000000
U0 S(U8 *s)
{
  U8 *u = XUART;
  while (*s)
    *u = *s++;
}

U0 D(I64 v)
{
  U8 d[24];
  I64 i = 0, j;
  if (v < 0) {
    S("-");
    v = -v;
  }
  if (!v)
    d[i++] = '0';
  while (v > 0) {
    d[i++] = '0' + v % 10;
    v /= 10;
  }
  j = i;
  while (j > 0) {
    U8 one[2];
    j--;
    one[0] = d[j];
    one[1] = 0;
    S(one);
  }
}

// The backend's error-name table, empty as a bare-metal target's is. It must be defined BEFORE
// the portable layer that walks it -- see os_shared_errors.HC for why include order does a
// linker's job here.
OS_ErrorTable_Entry OS_IMPL_ERROR_NAME_TABLE[1] = {{0, NULL}};

// Stands in for osapi-printf.c, which is part of the shared layer and not translated yet. The C
// oracle's stub prints the same fixed marker: what the transcript pins is which checks fire.
U0 OS_printf(U8 *fmt)
{
  S("bugcheck\n");
}

#include "/Kernel/Cfs/osal/osapi_errors.HC"
#include "/Kernel/Cfs/osal/osapi_version.HC"
#include "/Kernel/Cfs/osal/osapi_clock.HC"
#include "/Kernel/Cfs/osal/osapi_heap.HC"

// The four real backend calls osapi-idmap.c makes. The locks are no-ops here because the
// transcript runs single-threaded -- what is asserted is the LOCK BOOKKEEPING the portable
// layer does around them (the key it computes, the owner it records, the refcount it adjusts),
// not mutual exclusion.
I64 stub_lock_depth;
I64 stub_lock_calls;
I64 stub_wait_calls;

U0 OS_Lock_Global_Impl(U32 idtype)
{
  ++stub_lock_depth;
  ++stub_lock_calls;
}

U0 OS_Unlock_Global_Impl(U32 idtype)
{
  --stub_lock_depth;
}

U0 OS_WaitForStateChange_Impl(U32 idtype, U32 attempts)
{
  ++stub_wait_calls;
}

// OS_TaskGetId_Impl moved down to the task backend, and OS_TaskGetId deleted outright: now
// that osapi-task.c is translated, the REAL one comes from osapi_task.HC. It is what idmap
// calls to stamp `creator` on every record, so the stub's fixed 0x10001 becomes the initial
// value of stub_t_current instead, and every creator line before the task section is unchanged.

#include "/Kernel/Cfs/osal/osapi_idmap.HC"
// The types the backend below must see before it can declare itself -- see that file for why
// include order stands in for a header here.
#include "/Kernel/Cfs/osal/os_shared_countsem.HC"

// The countsem backend. Records what it was asked to do and reports a value back through
// GetInfo, so the transcript shows the portable layer passing arguments down and results up
// with no real semaphore anywhere.
U32 stub_cs_initial;
U32 stub_cs_options;
I64 stub_cs_gives;
I64 stub_cs_takes;
U32 stub_cs_last_msecs;

I32 OS_CountSemCreate_Impl(OS_object_token_t *token, U32 sem_initial_value, U32 options)
{
  stub_cs_initial = sem_initial_value;
  stub_cs_options = options;
  return OS_SUCCESS;
}
I32 OS_CountSemDelete_Impl(OS_object_token_t *token) { return OS_SUCCESS; }
I32 OS_CountSemGive_Impl(OS_object_token_t *token) { ++stub_cs_gives; return OS_SUCCESS; }
I32 OS_CountSemTake_Impl(OS_object_token_t *token) { ++stub_cs_takes; return OS_SUCCESS; }
I32 OS_CountSemTimedWait_Impl(OS_object_token_t *token, U32 msecs)
{
  stub_cs_last_msecs = msecs;
  return OS_SEM_TIMEOUT;
}
I32 OS_CountSemGetInfo_Impl(OS_object_token_t *token, OS_count_sem_prop_t *count_prop)
{
  count_prop->value = 42;
  return OS_SUCCESS;
}

// Types first, then the backends that need them, then the modules -- include order doing a
// linker's job, as everywhere else here.
#include "/Kernel/Cfs/osal/os_shared_mutex.HC"
#include "/Kernel/Cfs/osal/os_shared_binsem.HC"
#include "/Kernel/Cfs/osal/os_shared_rwlock.HC"
#include "/Kernel/Cfs/osal/os_shared_condvar.HC"
#include "/Kernel/Cfs/osal/os_shared_queue.HC"
#include "/Kernel/Cfs/osal/os_shared_task.HC"

// The other four resource backends, matching the C oracle's.
U32 stub_last_options;

I32 OS_MutSemCreate_Impl(OS_object_token_t *t, U32 options) { stub_last_options = options; return OS_SUCCESS; }
I32 OS_MutSemDelete_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_MutSemGetInfo_Impl(OS_object_token_t *t, OS_mut_sem_prop_t *p) { return OS_SUCCESS; }

I32 OS_BinSemCreate_Impl(OS_object_token_t *t, U32 v, U32 options) { stub_last_options = options; return OS_SUCCESS; }
I32 OS_BinSemDelete_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_BinSemGive_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_BinSemFlush_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_BinSemTake_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_BinSemTimedWait_Impl(OS_object_token_t *t, U32 ms) { return OS_SEM_TIMEOUT; }
I32 OS_BinSemGetInfo_Impl(OS_object_token_t *t, OS_bin_sem_prop_t *p) { p->value = 9; return OS_SUCCESS; }

I32 OS_RwLockCreate_Impl(OS_object_token_t *t, U32 options) { stub_last_options = options; return OS_SUCCESS; }
I32 OS_RwLockDelete_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_RwLockReadGive_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_RwLockReadTake_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_RwLockWriteTake_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_RwLockGetInfo_Impl(OS_object_token_t *t, OS_rwlock_prop_t *p) { return OS_SUCCESS; }

I32 OS_CondVarCreate_Impl(OS_object_token_t *t, U32 options) { stub_last_options = options; return OS_SUCCESS; }
I32 OS_CondVarDelete_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_CondVarLock_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_CondVarUnlock_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_CondVarSignal_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_CondVarBroadcast_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_CondVarWait_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_CondVarTimedWait_Impl(OS_object_token_t *t, OS_time_t *abs) { return OS_SEM_TIMEOUT; }
I32 OS_CondVarGetInfo_Impl(OS_object_token_t *t, OS_condvar_prop_t *p) { return OS_SUCCESS; }

#include "/Kernel/Cfs/osal/osapi_countsem.HC"
#include "/Kernel/Cfs/osal/osapi_mutex.HC"
#include "/Kernel/Cfs/osal/osapi_binsem.HC"
#include "/Kernel/Cfs/osal/osapi_rwlock.HC"
#include "/Kernel/Cfs/osal/osapi_condvar.HC"

// Defined AFTER the modules: these read OS_mutex_table / OS_rwlock_table, which
// osapi_mutex.HC and osapi_rwlock.HC define. Their forward declarations at the top of
// those files are what make a definition down here legal.
// These read last_owner out of the table, which is the only way the transcript can see the
// ownership tracking in OS_MutSemGive/Take: OS_mut_sem_prop_t exposes name and creator, and the
// OS_DEBUG warning is a no-op in this configuration. A real backend has the same access.
U32 stub_mx_owner_at_give, stub_mx_owner_at_take;
I32 OS_MutSemGive_Impl(OS_object_token_t *t)
{
  stub_mx_owner_at_give = OS_mutex_table[OS_ObjectIndexFromToken(t)].last_owner;
  return OS_SUCCESS;
}
I32 OS_MutSemTake_Impl(OS_object_token_t *t)
{
  stub_mx_owner_at_take = OS_mutex_table[OS_ObjectIndexFromToken(t)].last_owner;
  return OS_SUCCESS;
}

U32 stub_rw_writer_at_give;
I32 OS_RwLockWriteGive_Impl(OS_object_token_t *t)
{
  stub_rw_writer_at_give = OS_rwlock_table[OS_ObjectIndexFromToken(t)].last_writer;
  return OS_SUCCESS;
}

#include "/Kernel/Cfs/osal/osapi_task.HC"

// --- osapi-task.c backend --------------------------------------------------------------------
// OS_TaskGetId_Impl is the "who am I" the OS would answer; here the driver sets it, which is
// what makes OS_TaskExit, OS_TaskGetId and OS_TaskInstallDeleteHandler drivable at all.
U32 stub_t_current, stub_t_flags;
I64 stub_t_prio, stub_t_delay;
I64 stub_t_creates, stub_t_deletes, stub_t_detaches, stub_t_exits;
I64 stub_t_registers, stub_t_matches, stub_t_hookcalls, stub_t_startups;
I32 stub_t_setprio_rc;
U32 stub_t_sysdata_want;

I32 OS_TaskCreate_Impl(OS_object_token_t *t, U32 flags)
{
  stub_t_flags = flags;
  ++stub_t_creates;
  return OS_SUCCESS;
}
I32 OS_TaskDelete_Impl(OS_object_token_t *t) { ++stub_t_deletes; return OS_SUCCESS; }
I32 OS_TaskDetach_Impl(OS_object_token_t *t) { ++stub_t_detaches; return OS_SUCCESS; }
U0 OS_TaskExit_Impl() { ++stub_t_exits; }   // the real one never returns
I32 OS_TaskDelay_Impl(U32 ms) { stub_t_delay = ms; return OS_SUCCESS; }
I32 OS_TaskSetPriority_Impl(OS_object_token_t *t, U8 p)
{
  stub_t_prio = p;
  return stub_t_setprio_rc;
}
U32 OS_TaskGetId_Impl() { return stub_t_current; }
I32 OS_TaskGetInfo_Impl(OS_object_token_t *t, OS_task_prop_t *p) { return OS_SUCCESS; }
I32 OS_TaskMatch_Impl(OS_object_token_t *t) { ++stub_t_matches; return OS_SUCCESS; }
I32 OS_TaskRegister_Impl(U32 id) { ++stub_t_registers; return OS_SUCCESS; }
I32 OS_TaskValidateSystemData_Impl(U8 *sysdata, I64 sysdata_size)
{
  // Only the backend knows what a system task handle looks like, so the size rule is the
  // backend's. Making it reject one size lets the driver prove the EARLY RETURN in
  // OS_TaskFindIdBySystemData fires before any search happens.
  if (sysdata == NULL || sysdata_size != stub_t_sysdata_want)
    return OS_ERR_INVALID_SIZE;
  return OS_SUCCESS;
}
Bool OS_TaskIdMatchSystemData_Impl(U8 *ref, OS_object_token_t *t, OS_common_record_t *obj)
{
  U32 *want;
  want = ref;
  return obj->active_id == *want;
}
U0 task_delete_hook() { ++stub_t_hookcalls; }
U0 task_entry_a() { ++stub_t_startups; }

#include "/Kernel/Cfs/osal/osapi_network.HC"
#include "/Kernel/Cfs/osal/osapi_shell.HC"
#include "/Kernel/Cfs/osal/osapi_task_affinity.HC"
#include "/Kernel/Cfs/osal/os_shared_filesys.HC"

// --- osapi-network.c / osapi-shell.c / osapi-task-affinity.c backends -------------------------
// Three small modules that are almost pure dispatch: what the transcript pins is which checks
// fire, what gets handed to the backend, and what each does with a failure.
I64 stub_n_hostcalls, stub_n_idcalls, stub_sh_calls, stub_af_sets, stub_af_gets, stub_af_cores;
I32 stub_n_host_rc, stub_n_id_rc;
U8 stub_sh_cmd[32];
U8 stub_af_mask;

I32 OS_NetworkGetHostName_Impl(U8 *host_name, I64 name_len)
{
  ++stub_n_hostcalls;
  if (stub_n_host_rc != OS_SUCCESS)
    return stub_n_host_rc;
  // A real backend fills the buffer; this one writes a fixed name so the transcript can show
  // that the FAILURE path overwrites it with an empty string and the success path does not.
  StrNCpy(host_name, "sat1", name_len - 1);
  return OS_SUCCESS;
}
I32 OS_NetworkGetID_Impl(I32 *IdBuf)
{
  ++stub_n_idcalls;
  *IdBuf = 4242;
  return stub_n_id_rc;
}
I32 OS_ShellOutputToFile_Impl(OS_object_token_t *token, U8 *Cmd)
{
  ++stub_sh_calls;
  StrNCpy(stub_sh_cmd, Cmd, sizeof(stub_sh_cmd) - 1);
  return OS_SUCCESS;
}
U32 OS_TaskAffinityGetCoresConfigured_Impl()
{
  ++stub_af_cores;
  return 3;
}
I32 OS_TaskAffinitySetAffinity_Impl(OS_object_token_t *token, OS_cpuset_t cpuset)
{
  ++stub_af_sets;
  stub_af_mask = cpuset.affinity_mask[0];
  return OS_SUCCESS;
}
I32 OS_TaskAffinityGetAffinity_Impl(OS_object_token_t *token, OS_cpuset_t *cpuset)
{
  ++stub_af_gets;
  cpuset->affinity_mask[0] = 0x5A;
  return OS_SUCCESS;
}

#include "/Kernel/Cfs/osal/osapi_filesys.HC"

// --- osapi-filesys.c backend -------------------------------------------------------------
// A real backend is what gives a volume its host-side mount point, so StartVolume_Impl does
// that here: without it system_mountpt stays empty and OS_mount can never get past its
// "system mount point should be a non-empty string" check.
I64 stub_fs_starts, stub_fs_stops, stub_fs_formats, stub_fs_mounts, stub_fs_unmounts;
I64 stub_fs_checks, stub_fs_stats, stub_fs_repair;
I32 stub_fs_format_rc, stub_fs_mount_rc;

I32 OS_FileSysStartVolume_Impl(OS_object_token_t *token)
{
  OS_filesys_internal_record_t *fs;
  fs = &OS_filesys_table[OS_ObjectIndexFromToken(token)];
  ++stub_fs_starts;
  // Only give a host mount point to volumes that do not already have one: AddFixedMap sets
  // system_mountpt itself, and overwriting it would erase the caller's phys_path.
  if (fs->system_mountpt[0] == 0)
    StrNCpy(fs->system_mountpt, "/host/ram", OS_MAX_LOCAL_PATH_LEN - 1);
  return OS_SUCCESS;
}
I32 OS_FileSysStopVolume_Impl(OS_object_token_t *token) { ++stub_fs_stops; return OS_SUCCESS; }
I32 OS_FileSysFormatVolume_Impl(OS_object_token_t *token)
{
  ++stub_fs_formats;
  return stub_fs_format_rc;
}
I32 OS_FileSysMountVolume_Impl(OS_object_token_t *token)
{
  ++stub_fs_mounts;
  return stub_fs_mount_rc;
}
I32 OS_FileSysUnmountVolume_Impl(OS_object_token_t *token) { ++stub_fs_unmounts; return OS_SUCCESS; }
I32 OS_FileSysCheckVolume_Impl(OS_object_token_t *token, Bool repair)
{
  ++stub_fs_checks;
  stub_fs_repair = repair;
  return OS_SUCCESS;
}
I32 OS_FileSysStatVolume_Impl(OS_object_token_t *token, OS_statvfs_t *statbuf)
{
  ++stub_fs_stats;
  statbuf->block_size = 512;
  statbuf->total_blocks = 1000;
  statbuf->blocks_free = 640;
  return OS_SUCCESS;
}

// Dumps every filesys entry in use, in index order. An earlier draft printed
// OS_filesys_table[0] and [1] directly and was off by one: OS_ObjectIdFindNextFree starts its
// search at last_alloc + 1, so the FIRST volume allocated lands at index 1 and slot 0 stays
// empty. Printing what is there removes the assumption from the transcript.
U0 fs_dump(U8 *tag)
{
  I64 i = 0;
  OS_filesys_internal_record_t *fs;
  while (i < OS_MAX_FILE_SYSTEMS) {
    fs = &OS_filesys_table[i];
    if (fs->device_name[0] != 0 || fs->virtual_mountpt[0] != 0) {
      S(tag);
      S(" [");
      D(i);
      S("] dev=");
      S(fs->device_name);
      S(" virt=");
      S(fs->virtual_mountpt);
      S(" type=");
      D(fs->fstype);
      S(" flags=");
      D(fs->flags);
      S("\n");
    }
    ++i;
  }
}

#include "/Kernel/Cfs/osal/osapi_queue.HC"

// --- osapi-queue.c backend ------------------------------------------------------------------
// OS_QueueCreate_Impl is handed only (token, flags); the depth and data size the caller passed
// went into the table record, and a real backend reads them back through the token. The stub
// does the same, because that is the ONLY way this transcript can see Create stored them in
// the right fields -- OS_queue_prop_t exposes name and creator and nothing else.
U32 stub_q_flags, stub_q_put_flags;
I64 stub_q_depth, stub_q_size, stub_q_put_size, stub_q_timeout;
I64 stub_q_gets, stub_q_puts;

I32 OS_QueueCreate_Impl(OS_object_token_t *t, U32 flags)
{
  OS_queue_internal_record_t *q;
  q = &OS_queue_table[OS_ObjectIndexFromToken(t)];
  stub_q_flags = flags;
  stub_q_depth = q->max_depth;
  stub_q_size = q->max_size;
  return OS_SUCCESS;
}
I32 OS_QueueDelete_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_QueueGet_Impl(OS_object_token_t *t, U8 *data, I64 size, I64 *size_copied, I32 timeout)
{
  *size_copied = size;
  stub_q_timeout = timeout;
  ++stub_q_gets;
  return OS_SUCCESS;
}
I32 OS_QueuePut_Impl(OS_object_token_t *t, U8 *data, I64 size, U32 flags)
{
  stub_q_put_size = size;
  stub_q_put_flags = flags;
  ++stub_q_puts;
  return OS_SUCCESS;
}


// Counts what OS_ForEachObject visits.
I64 foreach_count;
U0 foreach_cb(U32 id, U8 *arg)
{
  ++foreach_count;
}

U0 Hx(U8 *tag, I64 v)
{
  U8 *hx = "0123456789abcdef";
  U8 one[2];
  I64 i, started = 0;
  S(tag);
  S("0x");
  one[1] = 0;
  for (i = 60; i >= 0; i -= 4) {
    I64 d = (v >> i) & 15;
    if (d || started || i == 0) {
      started = 1;
      one[0] = hx[d];
      S(one);
    }
  }
}

// THE RECORDING STUB BACKEND, matching the C oracle's. A fixed, made-up clock and fixed heap
// numbers, so the transcript asserts the portable layer's validation and dispatch rather than
// anything about a real clock -- a real one would make the transcript unreproducible, which is
// the opposite of what a gate needs.
I64 stub_setlocal_calls;

I32 OS_GetMonotonicTime_Impl(OS_time_t *time_struct)
{
  time_struct->ticks = 1234500000; // 123.45 s at 100 ns per tick
  return OS_SUCCESS;
}

I32 OS_GetLocalTime_Impl(OS_time_t *time_struct)
{
  time_struct->ticks = 500000000; // 50 s
  return OS_SUCCESS;
}

I32 OS_SetLocalTime_Impl(OS_time_t *time_struct)
{
  ++stub_setlocal_calls;
  return OS_SUCCESS;
}

I32 OS_HeapGetInfo_Impl(OS_heap_prop_t *heap_prop)
{
  heap_prop->free_bytes = 4096;
  heap_prop->free_blocks = 7;
  heap_prop->largest_free_block = 2048;
  return OS_SUCCESS;
}

U0 Nm(U8 *label, I32 rc, U8 *nm)
{
  S(label);
  S(" rc=");
  D(rc);
  S(" [");
  S(nm);
  S("]\n");
}

I64 main()
{
  U8 nm[OS_ERROR_NAME_LENGTH];
  U8 st[OS_STATUS_STRING_LENGTH];
  I32 rc;
  // The C gives stub_t_current a static initialiser; HolyC globals are zero-filled. It has to
  // hold the old fixed stub's value from the FIRST line, because idmap calls OS_TaskGetId to
  // stamp `creator` on every record created below, long before the task section runs.
  stub_t_current = 0x10001;
  // Hoisted, because the C evaluates printf's arguments before printf emits anything and the
  // NULL case LOGS -- inline, the marker would land in the middle of its own line.
  rc = OS_GetErrorName(OS_ERR_NAME_TAKEN, nm);
  Nm("known  ", rc, nm);
  rc = OS_GetErrorName(OS_FS_ERR_PATH_INVALID, nm);
  Nm("gap    ", rc, nm);
  rc = OS_GetErrorName(OS_SUCCESS, nm);
  Nm("first  ", rc, nm);
  rc = OS_GetErrorName(OS_ERR_INVALID_ARGUMENT, nm);
  Nm("last   ", rc, nm);
  rc = OS_GetErrorName(-999, nm);
  Nm("unknown", rc, nm);
  // OS_ERR_TRY_AGAIN exists in osapi-error.h and is deliberately NOT in the name table.
  rc = OS_GetErrorName(OS_ERR_TRY_AGAIN, nm);
  Nm("nottbl ", rc, nm);
  rc = OS_GetErrorName(OS_ERROR, NULL);
  S("null    rc=");
  D(rc);
  S("\n");
  S("status  [");
  S(OS_StatusToString(-42, st));
  S("]\n");
  S("status0 [");
  S(OS_StatusToString(0, st));
  S("]\n");
  S("statusn [");
  D(OS_StatusToString(-1, NULL) == NULL);
  S("]\n");
  // --- osapi-version.c ---------------------------------------------------------------
  {
    U8 vn[4];
    OS_GetVersionNumber(vn);
    S("ver     [");
    S(OS_GetVersionString);
    S("]\n");
    S("codename[");
    S(OS_GetVersionCodeName);
    S("]\n");
    S("vernum  ");
    D(vn[0]);
    S(".");
    D(vn[1]);
    S(".");
    D(vn[2]);
    S(".");
    D(vn[3]);
    S("\n");
    S("build   ");
    D(OS_GetBuildNumber);
    S("\n");
  }

  // --- osapi-clock.c -----------------------------------------------------------------
  {
    OS_time_t t, a, b, r;
    OS_heap_prop_t hp;
    I32 r1, r2, r3;
    t.ticks = 0;
    rc = OS_GetMonotonicTime(&t);
    S("mono    rc=");
    D(rc);
    S(" ticks=");
    D(t.ticks);
    S("\n");
    t.ticks = 0;
    rc = OS_GetLocalTime(&t);
    S("local   rc=");
    D(rc);
    S(" ticks=");
    D(t.ticks);
    S("\n");
    rc = OS_SetLocalTime(&t);
    S("setloc  rc=");
    D(rc);
    S(" n=");
    D(stub_setlocal_calls);
    S("\n");
    // Hoisted: all three log, and C evaluates every printf argument before printing anything,
    // so the three markers come BEFORE the line rather than inside it.
    r1 = OS_GetMonotonicTime(NULL);
    r2 = OS_GetLocalTime(NULL);
    r3 = OS_SetLocalTime(NULL);
    S("clknull ");
    D(r1);
    S(" ");
    D(r2);
    S(" ");
    D(r3);
    S("\n");
    // The three branches of FromRelativeMilliseconds: poll, a real delay measured from the stub
    // clock, and the indefinite-block sentinel.
    r = OS_TimeFromRelativeMilliseconds(OS_CHECK);
    S("rel0    ");
    D(r.ticks);
    S("\n");
    r = OS_TimeFromRelativeMilliseconds(100);
    S("rel100  ");
    D(r.ticks);
    S("\n");
    r = OS_TimeFromRelativeMilliseconds(-5);
    S("relneg  ");
    D(r.ticks);
    S("\n");
    t.ticks = 0;
    S("torel0  ");
    D(OS_TimeToRelativeMilliseconds(t));
    S("\n");
    t = OS_TimeMax;
    S("torelmx ");
    D(OS_TimeToRelativeMilliseconds(t));
    S("\n");
    t.ticks = 500000000 + 250 * OS_TIME_TICKS_PER_MSEC; // 250 ms past the stub clock
    S("torel250 ");
    D(OS_TimeToRelativeMilliseconds(t));
    S("\n");
    S("ticks   ");
    D(OS_TIME_TICKS_PER_MSEC);
    S(" ");
    D(OS_TIME_TICKS_PER_SECOND);
    S("\n");
    S("sign    ");
    D(OS_TimeGetSign(OS_TimeFromTotalMilliseconds(5)));
    S(" ");
    D(OS_TimeGetSign(OS_TimeFromTotalMilliseconds(0)));
    S(" ");
    D(OS_TimeGetSign(OS_TimeFromTotalMilliseconds(-5)));
    S("\n");
    a = OS_TimeFromTotalMilliseconds(3);
    b = OS_TimeFromTotalMilliseconds(4);
    r = OS_TimeAdd(a, b);
    S("addsub  ");
    D(r.ticks);
    S(" ");
    r = OS_TimeSubtract(a, b);
    D(r.ticks);
    S("\n");
    S("cmp     ");
    D(OS_TimeCompare(a, b));
    S(" ");
    D(OS_TimeEqual(a, a));
    S("\n");
    // --- osapi-heap.c ----------------------------------------------------------------
    hp.free_bytes = 0;
    rc = OS_HeapGetInfo(&hp);
    S("heap    rc=");
    D(rc);
    S(" ");
    D(hp.free_bytes);
    S(" ");
    D(hp.free_blocks);
    S(" ");
    D(hp.largest_free_block);
    S("\n");
    rc = OS_HeapGetInfo(NULL);
    S("heapnull ");
    D(rc);
    S("\n");
  }

  // --- osapi-idmap.c -------------------------------------------------------------------
  {
    OS_object_token_t token;
    OS_object_token_t token2;
    U32 idx;
    U32 id1, id2, found;
    U8 namebuf[OS_MAX_API_NAME];
    I32 r;
    OS_ObjectIdInit;
    // Transactions are refused until the API says it is initialised -- asserted BEFORE
    // pretending it is, because it is a real guard and easy to translate away.
    r = OS_ObjectIdTransactionInit(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, &token);
    S("id_uninit rc=");
    D(r);
    S("\n");
    OS_SharedGlobalVars.GlobalState = OS_INIT_MAGIC_NUMBER;
    S("id_bases ");
    D(OS_GetBaseForObjectType(OS_OBJECT_TYPE_OS_QUEUE));
    S(" ");
    D(OS_GetBaseForObjectType(OS_OBJECT_TYPE_OS_CONDVAR));
    S(" ");
    D(OS_GetMaxForObjectType(OS_OBJECT_TYPE_OS_TASK));
    S("\n");
    S("id_badtype ");
    D(OS_GetMaxForObjectType(0x7F));
    S(" ");
    D(OS_GetBaseForObjectType(0x7F));
    S("\n");
    r = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, "alpha", &token);
    id1 = token.obj_id;
    S("alloc1  rc=");
    D(r);
    Hx(" id=", OS_ObjectIdToInteger(id1));
    S(" idx=");
    D(token.obj_idx);
    S("\n");
    OS_ObjectIdFinalizeNew(OS_SUCCESS, &token, &id1);
    r = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, "beta", &token);
    id2 = token.obj_id;
    S("alloc2  rc=");
    D(r);
    Hx(" id=", OS_ObjectIdToInteger(id2));
    S(" idx=");
    D(token.obj_idx);
    S("\n");
    OS_ObjectIdFinalizeNew(OS_SUCCESS, &token, &id2);
    // A duplicate name -- and it SUCCEEDS, because idmap itself never records a name:
    // OS_ObjectIdFindNextFree sets name_entry to NULL and the resource modules fill it in
    // later. So the duplicate search finds nothing to collide with. Real behaviour, pinned.
    r = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, "alpha", &token);
    S("alloc_dup rc=");
    D(r);
    S("\n");
    r = OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_TASK, id1, &idx);
    S("toindex rc=");
    D(r);
    S(" idx=");
    D(idx);
    S("\n");
    S("toindex_wrongtype rc=");
    D(OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_QUEUE, id1, &idx));
    S("\n");
    r = OS_ConvertToArrayIndex(id2, &idx);
    S("convert rc=");
    D(r);
    S(" idx=");
    D(idx);
    S("\n");
    S("identify ");
    D(OS_IdentifyObject(id1));
    S(" ");
    D(OS_IdentifyObject(OS_ObjectIdFromInteger(0)));
    S("\n");
    r = OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TASK, "beta", &found);
    S("byname  rc=");
    D(r);
    S(" match=");
    D(OS_ObjectIdEqual(found, id2));
    S("\n");
    S("byname_miss rc=");
    D(OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TASK, "nope", &found));
    S("\n");
    S("byname_null rc=");
    D(OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TASK, NULL, &found));
    S("\n");
    r = OS_GetResourceName(id1, namebuf, OS_MAX_API_NAME);
    S("getname rc=");
    D(r);
    S(" [");
    S(namebuf);
    S("]\n");
    // Hoisted: OS_CHECK_POINTER is a BUGCHECK and logs, and C evaluates printf's arguments
    // before printing, so the marker belongs before this line rather than inside it.
    r = OS_GetResourceName(id1, NULL, OS_MAX_API_NAME);
    S("getname_null rc=");
    D(r);
    S("\n");
    S("getname_zero rc=");
    D(OS_GetResourceName(id1, namebuf, 0));
    S("\n");
    // Token transfer must MOVE the lock, not copy it: the source ends up unlocked.
    r = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, id1, &token);
    OS_ObjectIdTransferToken(&token, &token2);
    S("transfer rc=");
    D(r);
    S(" from_mode=");
    D(token.lock_mode);
    S(" to_id=");
    D(OS_ObjectIdEqual(token2.obj_id, id1));
    S(" to_idx=");
    D(token2.obj_idx);
    S("\n");
    OS_ObjectIdRelease(&token2);
    foreach_count = 0;
    OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_OBJECT_CREATOR_ANY, &foreach_cb, NULL);
    S("foreach_task ");
    D(foreach_count);
    S("\n");
    foreach_count = 0;
    OS_ForEachObject(OS_OBJECT_CREATOR_ANY, &foreach_cb, NULL);
    S("foreach_all ");
    D(foreach_count);
    S("\n");
    foreach_count = 0;
    OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_ObjectIdFromInteger(0x99999), &foreach_cb,
                           NULL);
    S("foreach_other ");
    D(foreach_count);
    S("\n");
    r = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_TASK, id1, &token);
    S("del_get rc=");
    D(r);
    S("\n");
    S("del_fin rc=");
    D(OS_ObjectIdFinalizeDelete(OS_SUCCESS, &token));
    S("\n");
    foreach_count = 0;
    OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_OBJECT_CREATOR_ANY, &foreach_cb, NULL);
    S("after_del ");
    D(foreach_count);
    S("\n");
    S("stale   rc=");
    D(OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, id1, &token));
    S("\n");
    // THE SERIAL WRAP. A control that removed the `serial >= OS_OBJECT_INDEX_MASK` reset left
    // this transcript unchanged, which meant the wrap was never reached. Serial advances by one
    // per allocation and starts at 0, so crossing 0xFFFF takes 65535 of them. After the reset
    // the serial is small again; without it, it climbs past the 16-bit field and corrupts the
    // type bits above it.
    {
      I64 n;
      U32 wrapped = 0;
      for (n = 0; n < 65600; ++n) {
        if (OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, NULL, &token) != OS_SUCCESS)
          break;
        OS_ObjectIdFinalizeNew(OS_SUCCESS, &token, &wrapped);
        if (OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_TASK, wrapped, &token) ==
            OS_SUCCESS)
          OS_ObjectIdFinalizeDelete(OS_SUCCESS, &token);
      }
      S("wrap_n  ");
      D(n);
      S("\n");
      S("wrap_id type=");
      D(OS_ObjectIdToType_Impl(wrapped));
      S(" serial=");
      D(OS_ObjectIdToSerialNumber_Impl(wrapped));
      S("\n");
    }
    S("locks   depth=");
    D(stub_lock_depth);
    S(" waits=");
    D(stub_wait_calls);
    S("\n");
  }

  // --- osapi-countsem.c ----------------------------------------------------------------
  {
    U32 sid, found;
    OS_count_sem_prop_t prop;
    U8 longname[OS_MAX_API_NAME + 8];
    I64 k;
    I32 r2;
    OS_CountSemAPI_Init;
    r2 = OS_CountSemCreate(&sid, "csA", 7, 0x1234);
    S("cs_create rc=");
    D(r2);
    S(" init=");
    D(stub_cs_initial);
    S(" opt=");
    D(stub_cs_options);
    S("\n");
    S("cs_type  ");
    D(OS_ObjectIdToType_Impl(sid));
    S("\n");
    r2 = OS_CountSemGive(sid);
    S("cs_give  rc=");
    D(r2);
    S(" n=");
    D(stub_cs_gives);
    S("\n");
    r2 = OS_CountSemTake(sid);
    S("cs_take  rc=");
    D(r2);
    S(" n=");
    D(stub_cs_takes);
    S("\n");
    r2 = OS_CountSemTimedWait(sid, 250);
    S("cs_wait  rc=");
    D(r2);
    S(" ms=");
    D(stub_cs_last_msecs);
    S("\n");
    // GetInfo fills the name from the COMMON record and the value from the backend -- two
    // different sources meeting in one struct, which is the point of the layer.
    r2 = OS_CountSemGetInfo(sid, &prop);
    S("cs_info  rc=");
    D(r2);
    S(" [");
    S(prop.name);
    S("] val=");
    D(prop.value);
    S(" creator=");
    D(OS_ObjectIdEqual(prop.creator, OS_TaskGetId));
    S("\n");
    r2 = OS_CountSemGetIdByName(&found, "csA");
    S("cs_byname rc=");
    D(r2);
    S(" match=");
    D(OS_ObjectIdEqual(found, sid));
    S("\n");
    S("cs_byname_miss rc=");
    D(OS_CountSemGetIdByName(&found, "nope"));
    S("\n");
    // The two argument checks that behave differently: NULL logs, too-long is silent. Hoisted,
    // because the markers belong before their lines as C's argument evaluation puts them.
    r2 = OS_CountSemCreate(NULL, "x", 0, 0);
    S("cs_nullid  rc=");
    D(r2);
    S("\n");
    r2 = OS_CountSemCreate(&sid, NULL, 0, 0);
    S("cs_nullname rc=");
    D(r2);
    S("\n");
    for (k = 0; k < OS_MAX_API_NAME + 7; ++k)
      longname[k] = 'L';
    longname[OS_MAX_API_NAME + 7] = 0;
    S("cs_longname rc=");
    D(OS_CountSemCreate(&sid, longname, 0, 0));
    S("\n");
    r2 = OS_CountSemGetInfo(sid, NULL);
    S("cs_nullprop rc=");
    D(r2);
    S("\n");
    S("cs_delete rc=");
    D(OS_CountSemDelete(sid));
    S("\n");
    S("cs_stale  rc=");
    D(OS_CountSemGive(sid));
    S("\n");
  }

  // --- the rest of the resource family --------------------------------------------------
  // Five modules identical in shape from outside, driven through the same sequence so a
  // divergence in any one shows up against its siblings.
  {
    U32 mid, bid, rid, vid, found;
    OS_mut_sem_prop_t mprop;
    OS_bin_sem_prop_t bprop;
    OS_rwlock_prop_t rprop;
    OS_condvar_prop_t vprop;
    OS_time_t wake;
    I32 a, b, c;
    OS_MutexAPI_Init;
    OS_BinSemAPI_Init;
    OS_RwLockAPI_Init;
    OS_CondVarAPI_Init;
    a = OS_MutSemCreate(&mid, "mxA", 0x11);
    S("mx_create rc=");
    D(a);
    S(" opt=");
    D(stub_last_options);
    S("\n");
    a = OS_MutSemGive(mid);
    b = OS_MutSemTake(mid);
    S("mx_type ");
    D(OS_ObjectIdToType_Impl(mid));
    S(" give=");
    D(a);
    S(" take=");
    D(b);
    S("\n");
    a = OS_MutSemGetInfo(mid, &mprop);
    S("mx_info rc=");
    D(a);
    S(" [");
    S(mprop.name);
    S("]\n");
    a = OS_BinSemCreate(&bid, "bsA", 1, 0x22);
    S("bs_create rc=");
    D(a);
    S(" opt=");
    D(stub_last_options);
    S("\n");
    a = OS_BinSemFlush(bid);
    b = OS_BinSemTimedWait(bid, 5);
    S("bs_type ");
    D(OS_ObjectIdToType_Impl(bid));
    S(" flush=");
    D(a);
    S(" wait=");
    D(b);
    S("\n");
    a = OS_BinSemGetInfo(bid, &bprop);
    S("bs_info rc=");
    D(a);
    S(" [");
    S(bprop.name);
    S("] val=");
    D(bprop.value);
    S("\n");
    a = OS_RwLockCreate(&rid, "rwA", 0x33);
    S("rw_create rc=");
    D(a);
    S(" opt=");
    D(stub_last_options);
    S("\n");
    a = OS_RwLockReadTake(rid);
    b = OS_RwLockWriteTake(rid);
    S("rw_type ");
    D(OS_ObjectIdToType_Impl(rid));
    S(" rt=");
    D(a);
    S(" wt=");
    D(b);
    S("\n");
    a = OS_RwLockGetInfo(rid, &rprop);
    S("rw_info rc=");
    D(a);
    S(" [");
    S(rprop.name);
    S("]\n");
    a = OS_CondVarCreate(&vid, "cvA", 0x44);
    S("cv_create rc=");
    D(a);
    S(" opt=");
    D(stub_last_options);
    S("\n");
    wake.ticks = 12345;
    a = OS_CondVarSignal(vid);
    b = OS_CondVarTimedWait(vid, &wake);
    S("cv_type ");
    D(OS_ObjectIdToType_Impl(vid));
    S(" sig=");
    D(a);
    S(" wait=");
    D(b);
    S("\n");
    // CondVarTimedWait has its own OS_CHECK_POINTER that its siblings lack -- a BUGCHECK, so
    // it logs. Hoisted so the marker lands before the line.
    a = OS_CondVarTimedWait(vid, NULL);
    S("cv_nullwake rc=");
    D(a);
    S("\n");
    a = OS_CondVarGetInfo(vid, &vprop);
    S("cv_info rc=");
    D(a);
    S(" [");
    S(vprop.name);
    S("]\n");
    S("types   ");
    D(OS_ObjectIdToType_Impl(mid));
    S(" ");
    D(OS_ObjectIdToType_Impl(bid));
    S(" ");
    D(OS_ObjectIdToType_Impl(rid));
    S(" ");
    D(OS_ObjectIdToType_Impl(vid));
    S("\n");
    S("byname  ");
    D(OS_MutSemGetIdByName(&found, "mxA") == OS_SUCCESS);
    S(" ");
    D(OS_BinSemGetIdByName(&found, "bsA") == OS_SUCCESS);
    S(" ");
    D(OS_RwLockGetIdByName(&found, "rwA") == OS_SUCCESS);
    S(" ");
    D(OS_CondVarGetIdByName(&found, "cvA") == OS_SUCCESS);
    S("\n");
    a = OS_MutSemDelete(mid);
    b = OS_BinSemDelete(bid);
    c = OS_RwLockDelete(rid);
    S("deletes ");
    D(a);
    S(" ");
    D(b);
    S(" ");
    D(c);
    S(" ");
    D(OS_CondVarDelete(vid));
    S("\n");
  }

  // --- osapi-queue.c -------------------------------------------------------------------------
  // The Get and Put size checks are ASYMMETRIC and easy to get backwards:
  //     Get rejects a buffer SMALLER than max_size  (size < max_size)
  //     Put rejects a payload LARGER  than max_size  (size > max_size)
  // One size proves nothing: at size == max_size both operators agree. Each is driven at
  // max_size-1, max_size and max_size+1, and the RETURN CODE is printed rather than pass/fail,
  // because the size-parameter check returns OS_ERR_INVALID_SIZE while the max_size mismatch
  // returns OS_QUEUE_INVALID_SIZE -- confusing the two would survive any "it rejected it" test.
  {
    U32 qid, qid2, qfound;
    OS_queue_prop_t qprop;
    I64 cp, huge;
    U8 buf[32];
    U8 qlong[OS_MAX_API_NAME + 8];
    I64 i;
    I32 r3, r4;

    OS_QueueAPI_Init;
    r3 = OS_QueueCreate(&qid, "qA", 4, 16, 0xA5);
    S("q_create rc=");
    D(r3);
    Hx(" flags=", stub_q_flags);
    S(" depth=");
    D(stub_q_depth);
    S(" size=");
    D(stub_q_size);
    S("\n");

    S("q_put_lt rc=");
    D(OS_QueuePut(qid, "p", 15, 0x77));
    S("\n");
    S("q_put_eq rc=");
    D(OS_QueuePut(qid, "p", 16, 0x77));
    S("\n");
    S("q_put_gt rc=");
    D(OS_QueuePut(qid, "p", 17, 0x77));
    S("\n");
    S("q_put_n  ");
    D(stub_q_puts);
    S(" last=");
    D(stub_q_put_size);
    Hx(" fl=", stub_q_put_flags);
    S("\n");

    // Poisoned, not zeroed: OS_QueueGet writes *size_copied = 0 on the reject path, and a
    // destination that started at 0 would let a missing store pass blind.
    cp = 0xEE;
    r3 = OS_QueueGet(qid, buf, 15, &cp, 5);
    S("q_get_lt rc=");
    D(r3);
    S(" cp=");
    D(cp);
    S("\n");
    cp = 0xEE;
    r3 = OS_QueueGet(qid, buf, 16, &cp, 5);
    S("q_get_eq rc=");
    D(r3);
    S(" cp=");
    D(cp);
    S("\n");
    cp = 0xEE;
    r3 = OS_QueueGet(qid, buf, 17, &cp, 5);
    S("q_get_gt rc=");
    D(r3);
    S(" cp=");
    D(cp);
    S("\n");
    S("q_get_n  ");
    D(stub_q_gets);
    S(" timeout=");
    D(stub_q_timeout);
    S("\n");

    // A BAD SIZE is a different code from a size that merely mismatches max_size.
    cp = 0xEE;
    r3 = OS_QueuePut(qid, "p", 0, 0);
    r4 = OS_QueueGet(qid, buf, 0, &cp, 0);
    S("q_zero   put=");
    D(r3);
    S(" get=");
    D(r4);
    S("\n");
    // size is size_t (unsigned) in NASA's C and I64 (signed) here. Both reject this, by
    // different routes: too large there, negative here.
    huge = 1 << 63;
    cp = 0xEE;
    r3 = OS_QueuePut(qid, "p", huge, 0);
    r4 = OS_QueueGet(qid, buf, huge, &cp, 0);
    S("q_huge   put=");
    D(r3);
    S(" get=");
    D(r4);
    S("\n");

    r3 = OS_QueueCreate(NULL, "x", 4, 16, 0);
    S("q_nullid   rc=");
    D(r3);
    S("\n");
    r3 = OS_QueueCreate(&qid2, NULL, 4, 16, 0);
    S("q_nullname rc=");
    D(r3);
    S("\n");
    i = 0;
    while (i < sizeof(qlong) - 1) {
      qlong[i] = 'q';
      ++i;
    }
    qlong[sizeof(qlong) - 1] = 0;
    S("q_longname rc=");
    D(OS_QueueCreate(&qid2, qlong, 4, 16, 0));
    S("\n");
    S("q_badsize  rc=");
    D(OS_QueueCreate(&qid2, "qB", 4, 0, 0));
    S("\n");
    // depth > OS_QUEUE_MAX_DEPTH is OS_QUEUE_INVALID_SIZE, not OS_ERR_INVALID_SIZE
    S("q_deep     rc=");
    D(OS_QueueCreate(&qid2, "qB", OS_QUEUE_MAX_DEPTH + 1, 16, 0));
    S("\n");
    cp = 0xEE;
    r3 = OS_QueuePut(qid, NULL, 4, 0);
    r4 = OS_QueueGet(qid, NULL, 4, &cp, 0);
    S("q_nulldata put=");
    D(r3);
    S(" get=");
    D(r4);
    S(" cp=");
    D(cp);
    S("\n");
    r3 = OS_QueueGet(qid, buf, 4, NULL, 0);
    S("q_nullcp   rc=");
    D(r3);
    S("\n");

    r3 = OS_QueueGetIdByName(&qfound, "qA");
    S("q_byname   rc=");
    D(r3);
    S(" match=");
    D(OS_ObjectIdEqual(qfound, qid));
    S("\n");
    S("q_byname_miss rc=");
    D(OS_QueueGetIdByName(&qfound, "nope"));
    S("\n");
    r3 = OS_QueueGetInfo(qid, &qprop);
    S("q_info     rc=");
    D(r3);
    S(" [");
    S(qprop.name);
    S("]\n");
    r3 = OS_QueueGetInfo(qid, NULL);
    S("q_nullprop rc=");
    D(r3);
    S("\n");
    S("q_delete   rc=");
    D(OS_QueueDelete(qid));
    S("\n");
    S("q_stale    rc=");
    D(OS_QueuePut(qid, "p", 4, 0));
    S("\n");
  }

  // --- osapi-task.c --------------------------------------------------------------------------
  // Three things here are easy to get wrong and invisible to a "did it return 0" test:
  //   - SetPriority writes the table ONLY when the backend succeeded, so the failing case must
  //     show the OLD priority still in place;
  //   - Delete calls the hook AFTER the record is finalized, so both "was it called" and "was
  //     it called once" matter. (The SAVE happening before is not observable: a control moved
  //     it after FinalizeDelete and the transcript did not change.);
  //   - FindIdBySystemData returns the backend's validation error EARLY, before any search, so
  //     a wrong size must not reach the match function.
  {
    U32 tid, tid2, tfound;
    OS_task_prop_t tprop;
    U8 tlong[OS_MAX_API_NAME + 8];
    U32 want;
    I64 i;
    I32 r5;

    // The C gives these static initialisers; HolyC globals are zero-filled, so the two that are
    // not zero have to be set here or the transcripts diverge for a harness reason.
    stub_t_setprio_rc = OS_SUCCESS;
    stub_t_sysdata_want = 4;

    OS_TaskAPI_Init;
    r5 = OS_TaskCreate(&tid, "tA", &task_entry_a, NULL, 4096, 100, 0x11);
    S("t_create  rc=");
    D(r5);
    Hx(" fl=", stub_t_flags);
    S(" n=");
    D(stub_t_creates);
    S("\n");
    r5 = OS_TaskGetInfo(tid, &tprop);
    S("t_info    rc=");
    D(r5);
    S(" [");
    S(tprop.name);
    S("] stack=");
    D(tprop.stack_size);
    S(" prio=");
    D(tprop.priority);
    S("\n");

    r5 = OS_TaskCreate(NULL, "x", &task_entry_a, NULL, 16, 1, 0);
    S("t_nullid   rc=");
    D(r5);
    S("\n");
    r5 = OS_TaskCreate(&tid2, "x", NULL, NULL, 16, 1, 0);
    S("t_nullfn   rc=");
    D(r5);
    S("\n");
    r5 = OS_TaskCreate(&tid2, NULL, &task_entry_a, NULL, 16, 1, 0);
    S("t_nullname rc=");
    D(r5);
    S("\n");
    i = 0;
    while (i < sizeof(tlong) - 1) {
      tlong[i] = 't';
      ++i;
    }
    tlong[sizeof(tlong) - 1] = 0;
    S("t_longname rc=");
    D(OS_TaskCreate(&tid2, tlong, &task_entry_a, NULL, 16, 1, 0));
    S("\n");
    S("t_zerostk  rc=");
    D(OS_TaskCreate(&tid2, "tB", &task_entry_a, NULL, 0, 1, 0));
    S("\n");

    r5 = OS_TaskGetIdByName(&tfound, "tA");
    S("t_byname   rc=");
    D(r5);
    S(" match=");
    D(OS_ObjectIdEqual(tfound, tid));
    S("\n");
    S("t_byname_miss rc=");
    D(OS_TaskGetIdByName(&tfound, "nope"));
    S("\n");

    // Priority: the backend succeeds, so the table must take the new value.
    r5 = OS_TaskSetPriority(tid, 55);
    S("t_prio_ok  rc=");
    D(r5);
    S(" impl=");
    D(stub_t_prio);
    S("\n");
    OS_TaskGetInfo(tid, &tprop);
    S("t_prio_tbl prio=");
    D(tprop.priority);
    S("\n");
    // Now the backend FAILS: the table must keep 55, not take 77.
    stub_t_setprio_rc = OS_ERROR;
    r5 = OS_TaskSetPriority(tid, 77);
    S("t_prio_bad rc=");
    D(r5);
    S(" impl=");
    D(stub_t_prio);
    S("\n");
    OS_TaskGetInfo(tid, &tprop);
    S("t_prio_keep prio=");
    D(tprop.priority);
    S("\n");
    stub_t_setprio_rc = OS_SUCCESS;

    r5 = OS_TaskDelay(250);
    S("t_delay    rc=");
    D(r5);
    S(" ms=");
    D(stub_t_delay);
    S("\n");

    // "Who am I" drives GetId and InstallDeleteHandler, both of which ask the backend.
    stub_t_current = tid;
    S("t_getid    match=");
    D(OS_ObjectIdEqual(OS_TaskGetId, tid));
    S("\n");
    S("t_hook_in  rc=");
    D(OS_TaskInstallDeleteHandler(&task_delete_hook));
    S("\n");

    // FindIdBySystemData: the wrong size must not reach the match function.
    want = OS_ObjectIdToInteger(tid);
    S("t_sysbad   rc=");
    D(OS_TaskFindIdBySystemData(&tfound, &want, 3));
    S("\n");
    r5 = OS_TaskFindIdBySystemData(&tfound, &want, 4);
    S("t_sysok    rc=");
    D(r5);
    S(" match=");
    D(OS_ObjectIdEqual(tfound, tid));
    S("\n");
    r5 = OS_TaskFindIdBySystemData(NULL, &want, 4);
    S("t_sysnull  rc=");
    D(r5);
    S("\n");

    // Delete runs the hook that was installed above, exactly once.
    r5 = OS_TaskDelete(tid);
    S("t_delete   rc=");
    D(r5);
    S(" del=");
    D(stub_t_deletes);
    S(" hook=");
    D(stub_t_hookcalls);
    S("\n");
    S("t_stale    rc=");
    D(OS_TaskDelete(tid));
    S("\n");

    // OS_TaskEntryPoint is what the backend calls in the new thread: it prepares the task, runs
    // the entry function, then exits -- which detaches and finalizes.
    OS_TaskCreate(&tid2, "tB", &task_entry_a, NULL, 2048, 60, 0);
    stub_t_current = tid2;
    OS_TaskEntryPoint(tid2);
    S("t_entry    ran=");
    D(stub_t_startups);
    S(" match=");
    D(stub_t_matches);
    S(" reg=");
    D(stub_t_registers);
    S(" detach=");
    D(stub_t_detaches);
    S(" exit=");
    D(stub_t_exits);
    S("\n");
    r5 = OS_TaskGetInfo(tid2, &tprop);
    S("t_gone     rc=");
    D(r5);
    S("\n");
  }

  // --- osapi-network.c, osapi-shell.c, osapi-task-affinity.c -----------------------------------
  // Each of these has one thing worth asserting beyond "it dispatched":
  //   network: on backend FAILURE, OS_NetworkGetHostName blanks the caller's buffer, and
  //            OS_NetworkGetID returns a hardcoded -1 rather than the backend's value;
  //   shell:   the stream is taken with LOCK_MODE_REFCOUNT, not GLOBAL;
  //   affinity: OS_TaskAffinityGetCoresConfigured asks the BACKEND while
  //            OS_TaskAffinityCoresConfigured returns what OSAL recorded -- two functions one
  //            character apart in meaning, exactly the kind of pair a template gets wrong.
  {
    U8 hname[32];
    OS_cpuset_t cpuset;
    U32 atid;
    I32 r6;

    stub_n_host_rc = OS_SUCCESS;
    stub_n_id_rc = OS_SUCCESS;

    S("net_init  rc=");
    D(OS_NetworkAPI_Init);
    S("\n");
    MemSet(hname, 'Z', sizeof(hname));
    r6 = OS_NetworkGetHostName(hname, sizeof(hname));
    S("net_host  rc=");
    D(r6);
    S(" [");
    S(hname);
    S("] n=");
    D(stub_n_hostcalls);
    S("\n");
    // The failure path must BLANK the buffer, so it is poisoned with a non-empty string first --
    // starting from the success value would let a missing blank pass.
    stub_n_host_rc = OS_ERROR;
    r6 = OS_NetworkGetHostName(hname, sizeof(hname));
    S("net_hfail rc=");
    D(r6);
    S(" empty=");
    D(hname[0] == 0);
    S(" n=");
    D(stub_n_hostcalls);
    S("\n");
    stub_n_host_rc = OS_SUCCESS;
    r6 = OS_NetworkGetHostName(NULL, 8);
    S("net_hnull rc=");
    D(r6);
    S("\n");
    S("net_hzero rc=");
    D(OS_NetworkGetHostName(hname, 0));
    S("\n");
    S("net_id    ");
    D(OS_NetworkGetID);
    S(" n=");
    D(stub_n_idcalls);
    S("\n");
    stub_n_id_rc = OS_ERROR;
    S("net_idbad ");
    D(OS_NetworkGetID);
    S(" n=");
    D(stub_n_idcalls);
    S("\n");
    stub_n_id_rc = OS_SUCCESS;

    r6 = OS_ShellOutputToFile(NULL, 1);
    S("sh_null   rc=");
    D(r6);
    S("\n");
    S("sh_badfd  rc=");
    D(OS_ShellOutputToFile("ls", 0x66000001));
    S(" n=");
    D(stub_sh_calls);
    S("\n");

    S("af_cores  impl=");
    D(OS_TaskAffinityGetCoresConfigured);
    S(" recorded=");
    D(OS_TaskAffinityCoresConfigured);
    S(" n=");
    D(stub_af_cores);
    S("\n");
    OS_SharedGlobalVars.CoresConfigured = 7;
    S("af_cores2 recorded=");
    D(OS_TaskAffinityCoresConfigured);
    S("\n");
    OS_TaskCreate(&atid, "tAff", &task_entry_a, NULL, 1024, 40, 0);
    MemSet(&cpuset, 0, sizeof(cpuset));
    cpuset.affinity_mask[0] = 0x81;
    r6 = OS_TaskAffinitySetAffinity(atid, cpuset);
    S("af_set    rc=");
    D(r6);
    S(" mask=");
    D(stub_af_mask);
    S(" n=");
    D(stub_af_sets);
    S("\n");
    MemSet(&cpuset, 0, sizeof(cpuset));
    r6 = OS_TaskAffinityGetAffinity(atid, &cpuset);
    S("af_get    rc=");
    D(r6);
    S(" mask=");
    D(cpuset.affinity_mask[0]);
    S(" n=");
    D(stub_af_gets);
    S("\n");
    // A bad id must not reach the backend, and the UNCONDITIONAL OS_ObjectIdRelease that
    // follows it must be harmless -- see the note in the translation.
    r6 = OS_TaskAffinityGetAffinity(0x11000099, &cpuset);
    S("af_badid  rc=");
    D(r6);
    S(" sets=");
    D(stub_af_sets);
    S(" gets=");
    D(stub_af_gets);
    S("\n");
  }

  // --- mutex and rwlock OWNERSHIP ---------------------------------------------------------------
  // These fields, and every check that reads them, were MISSING from the translation and no
  // behavioural gate noticed: nothing exposes last_owner through the public API, and the
  // OS_DEBUG warning that reads it is a no-op in this configuration. Found by
  // tools/cfs/check_structs.py comparing fields against NASA's struct.
  //
  // So the backend reads them, as a real one can. Take must RECORD the caller and Give must
  // CLEAR it -- and the order matters: Take_Impl runs BEFORE the store so it sees the old
  // value, while Give_Impl runs AFTER the clear and sees UNDEFINED.
  {
    U32 owner_mid, owner_rid, mxi, rwi;
    I32 r7;

    stub_t_current = 0x10007;
    OS_MutSemCreate(&owner_mid, "mxOwn", 0);
    OS_RwLockCreate(&owner_rid, "rwOwn", 0);
    OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_MUTEX, owner_mid, &mxi);
    OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_RWLOCK, owner_rid, &rwi);

    r7 = OS_MutSemTake(owner_mid);
    S("mx_take   rc=");
    D(r7);
    S(" seen_before=");
    D(stub_mx_owner_at_take);
    S("\n");
    S("mx_owner  stored=");
    D(OS_mutex_table[mxi].last_owner);
    S("\n");
    r7 = OS_MutSemGive(owner_mid);
    S("mx_give   rc=");
    D(r7);
    S(" seen_after=");
    D(stub_mx_owner_at_give);
    S("\n");

    // Taken by one task, given by another: NASA logs a warning (a no-op here) and clears
    // last_owner regardless, so the clear must still happen.
    OS_MutSemTake(owner_mid);
    stub_t_current = 0x10008;
    r7 = OS_MutSemGive(owner_mid);
    S("mx_cross  rc=");
    D(r7);
    S(" seen_after=");
    D(stub_mx_owner_at_give);
    S("\n");

    S("rw_wtake  rc=");
    D(OS_RwLockWriteTake(owner_rid));
    S("\n");
    S("rw_writer stored=");
    D(OS_rwlock_table[rwi].last_writer);
    S("\n");
    // ReadGive reads last_writer and does NOT clear it; WriteGive does.
    r7 = OS_RwLockReadGive(owner_rid);
    S("rw_rgive  rc=");
    D(r7);
    S(" still=");
    D(OS_rwlock_table[rwi].last_writer);
    S("\n");
    r7 = OS_RwLockWriteGive(owner_rid);
    S("rw_wgive  rc=");
    D(r7);
    S(" seen_after=");
    D(stub_rw_writer_at_give);
    S(" cleared=");
    D(OS_rwlock_table[rwi].last_writer);
    S("\n");
    stub_t_current = 0x10001;
  }

  // --- osapi-filesys.c ---------------------------------------------------------------------
  // The richest part is OS_TranslatePath, pure string logic with several ways to fail, and
  // OS_FileSys_FindVirtMountPoint underneath it -- whose whole reason for existing is that a
  // mount point of /mnt must NOT match a target of /mntx. The flag arithmetic in
  // mount/unmount is the other half: both mask out FIXED and then demand an EXACT flag set.
  {
    U32 fsid;
    OS_statvfs_t sb;
    os_fsinfo_t fsinfo;
    U8 local[OS_MAX_LOCAL_PATH_LEN];
    U8 phys[OS_FS_PHYS_NAME_LEN];
    U8 longpath[OS_MAX_PATH_LEN + 8];
    I64 i;
    I32 r8;

    stub_fs_format_rc = OS_SUCCESS;
    stub_fs_mount_rc = OS_SUCCESS;

    OS_FileSysAPI_Init;
    S("fs_init   rc=");
    D(OS_FileSysAPI_Init);
    S("\n");

    // mkfs FORMATS, initfs does not -- the one difference between them.
    r8 = OS_mkfs(NULL, "/dev/ram0", "RAMDISK", 512, 1000);
    S("fs_mkfs   rc=");
    D(r8);
    S(" starts=");
    D(stub_fs_starts);
    S(" formats=");
    D(stub_fs_formats);
    S("\n");
    r8 = OS_initfs(NULL, "/dev/ram1", "OTHER", 512, 1000);
    S("fs_initfs rc=");
    D(r8);
    S(" starts=");
    D(stub_fs_starts);
    S(" formats=");
    D(stub_fs_formats);
    S("\n");
    // RAM-disk detection: volname beginning "RAM" OR a non-NULL address. "OTHER" above got
    // neither, so the two entries must differ in fstype.
    fs_dump("fs_tbl  ");

    // Same device again: ALLOCATE fails and the historic code is substituted.
    S("fs_again  rc=");
    D(OS_mkfs(NULL, "/dev/ram0", "RAMDISK", 512, 1000));
    S("\n");
    S("fs_noname rc=");
    D(OS_mkfs(NULL, "", "RAMDISK", 512, 1000));
    S("\n");
    r8 = OS_mkfs(NULL, NULL, "RAMDISK", 512, 1000);
    S("fs_nulldv rc=");
    D(r8);
    S("\n");

    // A failed format must STOP the volume again rather than leave it half-made.
    stub_fs_format_rc = OS_ERROR;
    r8 = OS_mkfs(NULL, "/dev/ram2", "RAMDISK", 512, 1000);
    S("fs_badfmt rc=");
    D(r8);
    S(" stops=");
    D(stub_fs_stops);
    S("\n");
    stub_fs_format_rc = OS_SUCCESS;

    // mount: every failure is collapsed to OS_ERR_NAME_NOT_FOUND, including the
    // INCORRECT_OBJ_STATE and PATH_INVALID computed inside.
    S("fs_mntbad rc=");
    D(OS_mount("/dev/nope", "/mnt"));
    S("\n");
    r8 = OS_mount("/dev/ram0", "/mnt");
    S("fs_mount  rc=");
    D(r8);
    S(" mounts=");
    D(stub_fs_mounts);
    S("\n");
    S("fs_mnttwi rc=");
    D(OS_mount("/dev/ram0", "/mnt"));
    S("\n");

    // TranslatePath, once something is mounted at /mnt.
    MemSet(local, 0, sizeof(local));
    r8 = OS_TranslatePath("/mnt/file.txt", local);
    S("tp_ok     rc=");
    D(r8);
    S(" [");
    S(local);
    S("]\n");
    r8 = OS_TranslatePath("/mnt/", local);
    S("tp_root   rc=");
    D(r8);
    S(" [");
    S(local);
    S("]\n");
    S("tp_nodir  rc=");
    D(OS_TranslatePath("nodir", local));
    S("\n");
    S("tp_norel  rc=");
    D(OS_TranslatePath("/mnt/../etc/x", local));
    S("\n");
    S("tp_nomnt  rc=");
    D(OS_TranslatePath("/other/file", local));
    S("\n");
    r8 = OS_TranslatePath(NULL, local);
    S("tp_nullv  rc=");
    D(r8);
    S("\n");
    r8 = OS_TranslatePath("/mnt/x", NULL);
    S("tp_nulll  rc=");
    D(r8);
    S("\n");
    i = 0;
    while (i < sizeof(longpath) - 1) {
      longpath[i] = 'p';
      ++i;
    }
    longpath[0] = '/';
    longpath[sizeof(longpath) - 1] = 0;
    S("tp_long   rc=");
    D(OS_TranslatePath(longpath, local));
    S("\n");
    // A file name longer than OS_MAX_FILE_NAME (20) after the last '/'.
    S("tp_nlong  rc=");
    D(OS_TranslatePath("/mnt/abcdefghijklmnopqrstuvwxyz0123456789", local));
    S("\n");
    // THE PREFIX TRAP: /mnt must not match /mntx, and the mount point is /mnt.
    S("tp_prefix rc=");
    D(OS_TranslatePath("/mntx/file", local));
    S("\n");

    r8 = OS_FS_GetPhysDriveName(phys, "/mnt");
    S("fs_phys   rc=");
    D(r8);
    S(" [");
    S(phys);
    S("]\n");
    S("fs_physno rc=");
    D(OS_FS_GetPhysDriveName(phys, "/other"));
    S("\n");
    r8 = OS_FileSysStatVolume("/mnt", &sb);
    S("fs_stat   rc=");
    D(r8);
    S(" bs=");
    D(sb.block_size);
    S(" free=");
    D(sb.blocks_free);
    S(" n=");
    D(stub_fs_stats);
    S("\n");
    r8 = OS_chkfs("/mnt", TRUE);
    S("fs_chk    rc=");
    D(r8);
    S(" repair=");
    D(stub_fs_repair);
    S(" n=");
    D(stub_fs_checks);
    S("\n");

    r8 = OS_GetFsInfo(&fsinfo);
    S("fs_info   rc=");
    D(r8);
    S(" maxv=");
    D(fsinfo.MaxVolumes);
    S(" freev=");
    D(fsinfo.FreeVolumes);
    S(" maxfd=");
    D(fsinfo.MaxFds);
    S("\n");

    // A fixed map sets FIXED|READY|MOUNTED_* in one go and keeps its phys_path.
    S("fs_fixed  rc=");
    D(OS_FileSysAddFixedMap(&fsid, "/host/eeprom", "/eeprom"));
    S("\n");
    fs_dump("fs_tbl2 ");
    MemSet(local, 0, sizeof(local));
    r8 = OS_TranslatePath("/eeprom/cfg", local);
    S("tp_fixed  rc=");
    D(r8);
    S(" [");
    S(local);
    S("]\n");

    // FIXED is MASKED OUT of mount's flag check rather than rejected -- NASA's comment says
    // fixed maps "don't support mount/unmount" but that this is not enforced, to support
    // abstraction. Unmounting the fixed map leaves its flags at exactly FIXED|READY, which is
    // the only state where the mask is observable: masked it reads READY and mount proceeds,
    // unmasked it does not.
    S("fx_unmnt  rc=");
    D(OS_unmount("/eeprom"));
    S("\n");
    fs_dump("fx_tbl  ");
    r8 = OS_mount("/eeprom", "/eeprom");
    S("fx_remnt  rc=");
    D(r8);
    S(" mounts=");
    D(stub_fs_mounts);
    S("\n");
    r8 = OS_unmount("/mnt");
    S("fs_unmnt  rc=");
    D(r8);
    S(" n=");
    D(stub_fs_unmounts);
    S("\n");
    S("fs_unmnt2 rc=");
    D(OS_unmount("/mnt"));
    S("\n");
    S("tp_after  rc=");
    D(OS_TranslatePath("/mnt/file.txt", local));
    S("\n");
    S("fs_rmfs   rc=");
    D(OS_rmfs("/dev/ram0"));
    S("\n");
    S("fs_rmfs2  rc=");
    D(OS_rmfs("/dev/ram0"));
    S("\n");
  }
  return 0;
}
