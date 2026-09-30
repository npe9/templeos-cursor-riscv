// Differential oracle, HolyC side: drives the 1:1 translation of OSAL's portable error module
// and prints the same transcript as tests/osal/oracle_osal.c does against the unmodified C.
// Standalone on purpose -- no kernel includes -- so the only things under test are the
// translation and the compiler.
#include "/Kernel/Cfs/osal/os_shared_errors.HC"
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

U32 OS_TaskGetId_Impl()
{
  return OS_ObjectIdFromInteger(0x10001);
}

U32 OS_TaskGetId()
{
  return OS_ObjectIdFromInteger(0x10001);
}

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

// The other four resource backends, matching the C oracle's.
U32 stub_last_options;

I32 OS_MutSemCreate_Impl(OS_object_token_t *t, U32 options) { stub_last_options = options; return OS_SUCCESS; }
I32 OS_MutSemDelete_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_MutSemGive_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
I32 OS_MutSemTake_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
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
I32 OS_RwLockWriteGive_Impl(OS_object_token_t *t) { return OS_SUCCESS; }
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
  return 0;
}
