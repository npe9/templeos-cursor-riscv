/* Differential-oracle driver for the OSAL PORTABLE layer.
 *
 * Same shape as tests/cfs/oracle_ccsdspri.c: link NASA's unmodified sources, print a transcript,
 * and require the HolyC translation to print it byte for byte.
 *
 * WHAT MAKES THIS LAYER TESTABLE WITHOUT AN OS. src/os/shared/src makes zero direct OS calls --
 * no pthread, no sem, no open/read/write, no malloc. Its job is validation, id mapping and
 * dispatch to 128 OS_*_Impl functions a backend supplies. So a RECORDING STUB backend is enough
 * to exercise it, and the transcript then asserts the dispatch decisions, which is the layer's
 * whole contract. No tasks, no hardware, no scheduler. */
#include <stdio.h>
#include <string.h>
#include "osapi.h"
#include "os-shared-errors.h"
#include "osapi-version.h"
#include "os-shared-clock.h"
#include "os-shared-heap.h"
#include "os-shared-idmap.h"
#include "os-shared-common.h"
#include "os-shared-task.h"
#include "os-shared-countsem.h"
#include "os-shared-mutex.h"
#include "os-shared-binsem.h"
#include "os-shared-rwlock.h"
#include "os-shared-condvar.h"

/* The backend's error-name table. A bare-metal target contributes no OS-specific errors, so
 * this is empty -- and empty is the interesting case, because it is the one that makes
 * OS_GetErrorName fall through both tables to its OS_UNKNOWN() path. */
const OS_ErrorTable_Entry_t OS_IMPL_ERROR_NAME_TABLE[] = {{0, NULL}};

/* OSAL's BUGCHECK macro logs through OS_printf before returning:
 *     BUGREPORT("\n**BUG** %s():%d:check '%s' FAILED --> %s\n\n", __func__, __LINE__, ...)
 * using __func__, __LINE__ and stringified macro arguments, none of which HolyC has. So the
 * translation keeps the CHECK and the RETURN and does not reproduce the wording, and this stub
 * prints a fixed marker on both sides. What the transcript then pins is WHICH CHECKS FIRE,
 * which is the behaviour; the message text is C preprocessor machinery.
 *
 * osapi-printf.c is itself part of the shared layer and will be translated later; until then
 * this stub stands in for it. */
void OS_printf(const char *fmt, ...)
{
    (void)fmt;
    printf("bugcheck\n");
}

/* THE RECORDING STUB BACKEND. This is what makes the portable layer testable with no OS: the
 * clock returns a fixed, made-up time and the heap fixed numbers, so the transcript below
 * asserts the layer's VALIDATION AND DISPATCH -- which argument checks fire, which _Impl gets
 * called, what it does with the result -- rather than anything about a real clock. A real clock
 * would make the transcript unreproducible, which is the opposite of what a gate needs. */
static int stub_setlocal_calls;

int32 OS_GetMonotonicTime_Impl(OS_time_t *time_struct)
{
    time_struct->ticks = 1234500000; /* 123.45 s at 100 ns per tick */
    return OS_SUCCESS;
}

int32 OS_GetLocalTime_Impl(OS_time_t *time_struct)
{
    time_struct->ticks = 500000000; /* 50 s */
    return OS_SUCCESS;
}

int32 OS_SetLocalTime_Impl(const OS_time_t *time_struct)
{
    ++stub_setlocal_calls;
    return OS_SUCCESS;
}

int32 OS_HeapGetInfo_Impl(OS_heap_prop_t *heap_prop)
{
    heap_prop->free_bytes         = 4096;
    heap_prop->free_blocks        = 7;
    heap_prop->largest_free_block = 2048;
    return OS_SUCCESS;
}

/* THE TWO PIECES idmap BORROWS FROM osapi-common.c, defined here rather than linked.
 * osapi-common.c's OS_API_Init calls every module's initialiser, so linking it would drag in
 * the whole of OSAL -- which is not translated. The HolyC side carries exactly these two in a
 * file marked PARTIAL and deliberately kept out of the coverage gate, so both sides have the
 * same minimal common and neither claims that module is done. */
OS_SharedGlobalVars_t OS_SharedGlobalVars;

int32 OS_NotifyEvent(OS_Event_t event, osal_id_t object_id, void *data)
{
    int32 Status = OS_SUCCESS;
    int32 ReturnCode;
    int   i;

    for (i = 0; i < OS_MAX_EVENT_HANDLER; i++)
    {
        if (OS_SharedGlobalVars.EventHandler[i] != NULL)
        {
            ReturnCode = OS_SharedGlobalVars.EventHandler[i](event, object_id, data);
            if (ReturnCode != OS_SUCCESS)
            {
                Status = OS_ERROR;
            }
        }
    }

    return Status;
}

size_t OS_strnlen(const char *s, size_t maxlen)
{
    const char *end = (const char *)memchr(s, 0, maxlen);
    if (end != NULL)
    {
        maxlen = end - s;
    }
    return maxlen;
}

/* The four real backend calls osapi-idmap.c makes. The locks are no-ops here because the
 * transcript runs single-threaded -- what is being asserted is the LOCK BOOKKEEPING the portable
 * layer does around them (the key it computes, the owner it records, the refcount it adjusts),
 * not mutual exclusion. */
static int stub_lock_depth;
static int stub_lock_calls;
static int stub_wait_calls;

void OS_Lock_Global_Impl(osal_objtype_t idtype)
{
    ++stub_lock_depth;
    ++stub_lock_calls;
}

void OS_Unlock_Global_Impl(osal_objtype_t idtype)
{
    --stub_lock_depth;
}

void OS_WaitForStateChange_Impl(osal_objtype_t idtype, uint32 attempts)
{
    ++stub_wait_calls;
}

osal_id_t OS_TaskGetId_Impl(void)
{
    return OS_ObjectIdFromInteger(0x10001);
}

osal_id_t OS_TaskGetId(void)
{
    return OS_ObjectIdFromInteger(0x10001);
}

/* The countsem backend. Records what it was asked to do and reports a value back through
 * GetInfo, so the transcript can show the portable layer passing arguments down and results up
 * without any real semaphore existing. */
static uint32 stub_cs_initial;
static uint32 stub_cs_options;
static int    stub_cs_gives;
static int    stub_cs_takes;
static uint32 stub_cs_last_msecs;

int32 OS_CountSemCreate_Impl(const OS_object_token_t *token, uint32 sem_initial_value, uint32 options)
{
    stub_cs_initial = sem_initial_value;
    stub_cs_options = options;
    return OS_SUCCESS;
}
int32 OS_CountSemDelete_Impl(const OS_object_token_t *token) { return OS_SUCCESS; }
int32 OS_CountSemGive_Impl(const OS_object_token_t *token) { ++stub_cs_gives; return OS_SUCCESS; }
int32 OS_CountSemTake_Impl(const OS_object_token_t *token) { ++stub_cs_takes; return OS_SUCCESS; }
int32 OS_CountSemTimedWait_Impl(const OS_object_token_t *token, uint32 msecs)
{
    stub_cs_last_msecs = msecs;
    return OS_SEM_TIMEOUT;
}
int32 OS_CountSemGetInfo_Impl(const OS_object_token_t *token, OS_count_sem_prop_t *count_prop)
{
    count_prop->value = 42;
    return OS_SUCCESS;
}

/* The other four resource backends. Each records the last option word it was handed and
 * reports a distinguishable value back, so the transcript shows arguments going down and
 * results coming up through five modules that look identical from outside. */
static uint32 stub_last_options;

int32 OS_MutSemCreate_Impl(const OS_object_token_t *t, uint32 options) { stub_last_options = options; return OS_SUCCESS; }
int32 OS_MutSemDelete_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_MutSemGive_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_MutSemTake_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_MutSemGetInfo_Impl(const OS_object_token_t *t, OS_mut_sem_prop_t *p) { return OS_SUCCESS; }

int32 OS_BinSemCreate_Impl(const OS_object_token_t *t, uint32 v, uint32 options) { stub_last_options = options; return OS_SUCCESS; }
int32 OS_BinSemDelete_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_BinSemGive_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_BinSemFlush_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_BinSemTake_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_BinSemTimedWait_Impl(const OS_object_token_t *t, uint32 ms) { return OS_SEM_TIMEOUT; }
int32 OS_BinSemGetInfo_Impl(const OS_object_token_t *t, OS_bin_sem_prop_t *p) { p->value = 9; return OS_SUCCESS; }

int32 OS_RwLockCreate_Impl(const OS_object_token_t *t, uint32 options) { stub_last_options = options; return OS_SUCCESS; }
int32 OS_RwLockDelete_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_RwLockReadGive_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_RwLockWriteGive_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_RwLockReadTake_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_RwLockWriteTake_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_RwLockGetInfo_Impl(const OS_object_token_t *t, OS_rwlock_prop_t *p) { return OS_SUCCESS; }

int32 OS_CondVarCreate_Impl(const OS_object_token_t *t, uint32 options) { stub_last_options = options; return OS_SUCCESS; }
int32 OS_CondVarDelete_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_CondVarLock_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_CondVarUnlock_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_CondVarSignal_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_CondVarBroadcast_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_CondVarWait_Impl(const OS_object_token_t *t) { return OS_SUCCESS; }
int32 OS_CondVarTimedWait_Impl(const OS_object_token_t *t, const OS_time_t *abs) { return OS_SEM_TIMEOUT; }
int32 OS_CondVarGetInfo_Impl(const OS_object_token_t *t, OS_condvar_prop_t *p) { return OS_SUCCESS; }

/* Counts what OS_ForEachObject visits. */
static int foreach_count;
static void foreach_cb(osal_id_t id, void *arg)
{
    ++foreach_count;
}

int main(void)
{
    os_err_name_t      nm;
    os_status_string_t st;

    /* A code near the front of the table, one past every gap in it (-20 to -27, -38 to -40,
     * -44 to -103), and one that is in neither table. The gaps matter: the lookup walks a list
     * rather than indexing, so a translation that "helpfully" indexed by value would pass the
     * first case and fail the second. */
    printf("known   rc=%d [%s]\n", (int)OS_GetErrorName(OS_ERR_NAME_TAKEN, &nm), nm);
    printf("gap     rc=%d [%s]\n", (int)OS_GetErrorName(OS_FS_ERR_PATH_INVALID, &nm), nm);
    printf("first   rc=%d [%s]\n", (int)OS_GetErrorName(OS_SUCCESS, &nm), nm);
    printf("last    rc=%d [%s]\n", (int)OS_GetErrorName(OS_ERR_INVALID_ARGUMENT, &nm), nm);
    printf("unknown rc=%d [%s]\n", (int)OS_GetErrorName(-999, &nm), nm);
    /* A code that EXISTS in osapi-error.h but is deliberately absent from the name table --
     * OS_ERR_TRY_AGAIN (-43) and OS_ERR_EMPTY_SET (-44) are not listed. Proving that is a
     * property of NASA's table, not an oversight in the translation. */
    printf("nottbl  rc=%d [%s]\n", (int)OS_GetErrorName(OS_ERR_TRY_AGAIN, &nm), nm);
    printf("null    rc=%d\n", (int)OS_GetErrorName(OS_ERROR, NULL));

    printf("status  [%s]\n", OS_StatusToString(-42, &st));
    printf("status0 [%s]\n", OS_StatusToString(0, &st));
    printf("statusn [%d]\n", (int)(OS_StatusToString(-1, NULL) == NULL));

    /* --- osapi-version.c ------------------------------------------------------------- */
    {
        uint8 vn[4];
        OS_GetVersionNumber(vn);
        printf("ver     [%s]\n", OS_GetVersionString());
        printf("codename[%s]\n", OS_GetVersionCodeName());
        printf("vernum  %d.%d.%d.%d\n", vn[0], vn[1], vn[2], vn[3]);
        printf("build   %lu\n", (unsigned long)OS_GetBuildNumber());
    }

    /* --- osapi-clock.c --------------------------------------------------------------- */
    {
        OS_time_t      t;
        OS_heap_prop_t hp;

        t.ticks = 0;
        printf("mono    rc=%d ticks=%ld\n", (int)OS_GetMonotonicTime(&t), (long)t.ticks);
        t.ticks = 0;
        printf("local   rc=%d ticks=%ld\n", (int)OS_GetLocalTime(&t), (long)t.ticks);
        printf("setloc  rc=%d n=%d\n", (int)OS_SetLocalTime(&t), stub_setlocal_calls);
        printf("clknull %d %d %d\n", (int)OS_GetMonotonicTime(NULL), (int)OS_GetLocalTime(NULL),
               (int)OS_SetLocalTime(NULL));

        /* The three branches of FromRelativeMilliseconds: poll, a real delay measured from the
         * stub clock, and the indefinite-block sentinel. */
        printf("rel0    %ld\n", (long)OS_TimeFromRelativeMilliseconds(OS_CHECK).ticks);
        printf("rel100  %ld\n", (long)OS_TimeFromRelativeMilliseconds(100).ticks);
        printf("relneg  %ld\n", (long)OS_TimeFromRelativeMilliseconds(-5).ticks);

        /* And back. A time in the past collapses to OS_CHECK; OS_TIME_MAX stays a block. */
        t.ticks = 0;
        printf("torel0  %d\n", (int)OS_TimeToRelativeMilliseconds(t));
        t = OS_TIME_MAX;
        printf("torelmx %d\n", (int)OS_TimeToRelativeMilliseconds(t));
        t.ticks = 500000000 + (250 * OS_TIME_TICKS_PER_MSEC); /* 250 ms past the stub clock */
        printf("torel250 %d\n", (int)OS_TimeToRelativeMilliseconds(t));

        /* The arithmetic helpers, which are where a tick-rate mistake would show. */
        printf("ticks   %d %d\n", (int)OS_TIME_TICKS_PER_MSEC, (int)OS_TIME_TICKS_PER_SECOND);
        printf("sign    %d %d %d\n", OS_TimeGetSign(OS_TimeFromTotalMilliseconds(5)),
               OS_TimeGetSign(OS_TimeFromTotalMilliseconds(0)),
               OS_TimeGetSign(OS_TimeFromTotalMilliseconds(-5)));
        printf("addsub  %ld %ld\n",
               (long)OS_TimeAdd(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(4)).ticks,
               (long)OS_TimeSubtract(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(4)).ticks);
        printf("cmp     %d %d\n", OS_TimeCompare(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(4)),
               (int)OS_TimeEqual(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(3)));

        /* --- osapi-heap.c ------------------------------------------------------------ */
        hp.free_bytes = 0;
        printf("heap    rc=%d %ld %ld %ld\n", (int)OS_HeapGetInfo(&hp), (long)hp.free_bytes,
               (long)hp.free_blocks, (long)hp.largest_free_block);
        printf("heapnull %d\n", (int)OS_HeapGetInfo(NULL));
    }

    /* --- osapi-idmap.c ---------------------------------------------------------------- */
    {
        OS_object_token_t token;
        OS_object_token_t token2;
        osal_index_t      idx;
        osal_id_t         id1, id2, found;
        char              namebuf[OS_MAX_API_NAME];
        int32             rc;

        OS_ObjectIdInit();
        /* Transactions are refused until the API says it is initialised -- so assert that
         * BEFORE pretending it is, because it is a real guard and easy to translate away. */
        printf("id_uninit rc=%d\n", (int)OS_ObjectIdTransactionInit(OS_LOCK_MODE_GLOBAL,
                                                                    OS_OBJECT_TYPE_OS_TASK, &token));
        OS_SharedGlobalVars.GlobalState = OS_INIT_MAGIC_NUMBER;

        printf("id_bases %lu %lu %lu\n", (unsigned long)OS_GetBaseForObjectType(OS_OBJECT_TYPE_OS_QUEUE),
               (unsigned long)OS_GetBaseForObjectType(OS_OBJECT_TYPE_OS_CONDVAR),
               (unsigned long)OS_GetMaxForObjectType(OS_OBJECT_TYPE_OS_TASK));
        printf("id_badtype %lu %lu\n", (unsigned long)OS_GetMaxForObjectType(0x7F),
               (unsigned long)OS_GetBaseForObjectType(0x7F));

        /* Allocate two tasks by name and watch the ids cycle rather than repeat. */
        rc = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, "alpha", &token);
        id1 = token.obj_id;
        printf("alloc1  rc=%d id=0x%lx idx=%lu\n", (int)rc, OS_ObjectIdToInteger(id1),
               (unsigned long)token.obj_idx);
        OS_ObjectIdFinalizeNew(OS_SUCCESS, &token, &id1);
        rc = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, "beta", &token);
        id2 = token.obj_id;
        printf("alloc2  rc=%d id=0x%lx idx=%lu\n", (int)rc, OS_ObjectIdToInteger(id2),
               (unsigned long)token.obj_idx);
        OS_ObjectIdFinalizeNew(OS_SUCCESS, &token, &id2);

        /* A duplicate name is refused, and that is the branch that returns OS_ERR_NAME_TAKEN
         * only because the name search SUCCEEDED -- an inverted condition that reads oddly. */
        rc = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, "alpha", &token);
        printf("alloc_dup rc=%d\n", (int)rc);

        printf("toindex rc=%d idx=%lu\n", (int)OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_TASK, id1, &idx),
               (unsigned long)idx);
        printf("toindex_wrongtype rc=%d\n",
               (int)OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_QUEUE, id1, &idx));
        printf("convert rc=%d idx=%lu\n", (int)OS_ConvertToArrayIndex(id2, &idx), (unsigned long)idx);
        printf("identify %lu %lu\n", (unsigned long)OS_IdentifyObject(id1),
               (unsigned long)OS_IdentifyObject(OS_ObjectIdFromInteger(0)));

        printf("byname  rc=%d match=%d\n", (int)OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TASK, "beta", &found),
               (int)OS_ObjectIdEqual(found, id2));
        printf("byname_miss rc=%d\n", (int)OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TASK, "nope", &found));
        printf("byname_null rc=%d\n", (int)OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TASK, NULL, &found));

        printf("getname rc=%d [%s]\n", (int)OS_GetResourceName(id1, namebuf, sizeof(namebuf)), namebuf);
        printf("getname_null rc=%d\n", (int)OS_GetResourceName(id1, NULL, sizeof(namebuf)));
        printf("getname_zero rc=%d\n", (int)OS_GetResourceName(id1, namebuf, 0));

        /* Token transfer must move the lock, not copy it: the source must end up unlocked. */
        rc = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, id1, &token);
        OS_ObjectIdTransferToken(&token, &token2);
        printf("transfer rc=%d from_mode=%d to_id=%d to_idx=%lu\n", (int)rc, (int)token.lock_mode,
               (int)OS_ObjectIdEqual(token2.obj_id, id1), (unsigned long)token2.obj_idx);
        OS_ObjectIdRelease(&token2);

        /* Iterate. Two tasks were created, so two should be visited. */
        foreach_count = 0;
        OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_OBJECT_CREATOR_ANY, foreach_cb, NULL);
        printf("foreach_task %d\n", foreach_count);
        foreach_count = 0;
        OS_ForEachObject(OS_OBJECT_CREATOR_ANY, foreach_cb, NULL);
        printf("foreach_all %d\n", foreach_count);
        /* A creator filter that matches nothing. */
        foreach_count = 0;
        OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_ObjectIdFromInteger(0x99999), foreach_cb, NULL);
        printf("foreach_other %d\n", foreach_count);

        /* Delete one and confirm the record returns to the pool. */
        rc = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_TASK, id1, &token);
        printf("del_get rc=%d\n", (int)rc);
        printf("del_fin rc=%d\n", (int)OS_ObjectIdFinalizeDelete(OS_SUCCESS, &token));
        foreach_count = 0;
        OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_OBJECT_CREATOR_ANY, foreach_cb, NULL);
        printf("after_del %d\n", foreach_count);
        printf("stale   rc=%d\n",
               (int)OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, id1, &token));

        /* THE SERIAL WRAP. A control that removed the `serial >= OS_OBJECT_INDEX_MASK` reset
         * left this transcript unchanged, which meant the wrap was never reached -- serial
         * starts at 0 and only two objects had been allocated. It advances by one per
         * allocation, so crossing 0xFFFF takes 65535 of them. Allocate and delete one task in
         * a loop until it crosses, then look at the id: after the reset the serial is small
         * again, and without the reset it keeps climbing past the 16-bit field and corrupts
         * the type bits above it. */
        {
            int      n;
            osal_id_t wrapped;
            for (n = 0; n < 65600; ++n)
            {
                if (OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TASK, NULL, &token) != OS_SUCCESS)
                {
                    break;
                }
                OS_ObjectIdFinalizeNew(OS_SUCCESS, &token, &wrapped);
                if (OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_TASK, wrapped,
                                       &token) == OS_SUCCESS)
                {
                    OS_ObjectIdFinalizeDelete(OS_SUCCESS, &token);
                }
            }
            printf("wrap_n  %d\n", n);
            printf("wrap_id type=%lu serial=%lu\n",
                   (unsigned long)OS_ObjectIdToType_Impl(wrapped),
                   (unsigned long)OS_ObjectIdToSerialNumber_Impl(wrapped));
        }

        /* The lock bookkeeping should balance out to zero depth. */
        printf("locks   depth=%d waits=%d\n", stub_lock_depth, stub_wait_calls);
    }

    /* --- osapi-countsem.c ------------------------------------------------------------- */
    {
        osal_id_t           sid, found;
        OS_count_sem_prop_t prop;
        char                longname[OS_MAX_API_NAME + 8];
        int                 k;

        OS_CountSemAPI_Init();
        printf("cs_create rc=%d init=%lu opt=%lu\n",
               (int)OS_CountSemCreate(&sid, "csA", 7, 0x1234), (unsigned long)stub_cs_initial,
               (unsigned long)stub_cs_options);
        printf("cs_type  %lu\n", (unsigned long)OS_ObjectIdToType_Impl(sid));
        printf("cs_give  rc=%d n=%d\n", (int)OS_CountSemGive(sid), stub_cs_gives);
        printf("cs_take  rc=%d n=%d\n", (int)OS_CountSemTake(sid), stub_cs_takes);
        printf("cs_wait  rc=%d ms=%lu\n", (int)OS_CountSemTimedWait(sid, 250),
               (unsigned long)stub_cs_last_msecs);

        /* GetInfo fills the name from the COMMON record and the value from the backend -- two
         * different sources meeting in one struct, which is the whole point of the layer. */
        printf("cs_info  rc=%d [%s] val=%d creator=%d\n", (int)OS_CountSemGetInfo(sid, &prop),
               prop.name, (int)prop.value, (int)OS_ObjectIdEqual(prop.creator, OS_TaskGetId()));
        printf("cs_byname rc=%d match=%d\n", (int)OS_CountSemGetIdByName(&found, "csA"),
               (int)OS_ObjectIdEqual(found, sid));
        printf("cs_byname_miss rc=%d\n", (int)OS_CountSemGetIdByName(&found, "nope"));

        /* The two argument checks that behave differently: NULL logs, too-long is silent. */
        printf("cs_nullid  rc=%d\n", (int)OS_CountSemCreate(NULL, "x", 0, 0));
        printf("cs_nullname rc=%d\n", (int)OS_CountSemCreate(&sid, NULL, 0, 0));
        for (k = 0; k < (int)sizeof(longname) - 1; ++k)
        {
            longname[k] = 'L';
        }
        longname[sizeof(longname) - 1] = 0;
        printf("cs_longname rc=%d\n", (int)OS_CountSemCreate(&sid, longname, 0, 0));
        printf("cs_nullprop rc=%d\n", (int)OS_CountSemGetInfo(sid, NULL));

        printf("cs_delete rc=%d\n", (int)OS_CountSemDelete(sid));
        printf("cs_stale  rc=%d\n", (int)OS_CountSemGive(sid));
    }

    /* --- the rest of the resource family --------------------------------------------- */
    /* Five modules that are the same shape from outside. Each is driven through the same
     * sequence so a divergence in any one of them shows up against its siblings. */
    {
        osal_id_t         mid, bid, rid, vid, found;
        OS_mut_sem_prop_t mprop;
        OS_bin_sem_prop_t bprop;
        OS_rwlock_prop_t  rprop;
        OS_condvar_prop_t vprop;
        OS_time_t         wake;

        OS_MutexAPI_Init();
        OS_BinSemAPI_Init();
        OS_RwLockAPI_Init();
        OS_CondVarAPI_Init();

        printf("mx_create rc=%d opt=%lu\n", (int)OS_MutSemCreate(&mid, "mxA", 0x11),
               (unsigned long)stub_last_options);
        printf("mx_type %lu give=%d take=%d\n", (unsigned long)OS_ObjectIdToType_Impl(mid),
               (int)OS_MutSemGive(mid), (int)OS_MutSemTake(mid));
        printf("mx_info rc=%d [%s]\n", (int)OS_MutSemGetInfo(mid, &mprop), mprop.name);

        printf("bs_create rc=%d opt=%lu\n", (int)OS_BinSemCreate(&bid, "bsA", 1, 0x22),
               (unsigned long)stub_last_options);
        printf("bs_type %lu flush=%d wait=%d\n", (unsigned long)OS_ObjectIdToType_Impl(bid),
               (int)OS_BinSemFlush(bid), (int)OS_BinSemTimedWait(bid, 5));
        printf("bs_info rc=%d [%s] val=%d\n", (int)OS_BinSemGetInfo(bid, &bprop), bprop.name,
               (int)bprop.value);

        printf("rw_create rc=%d opt=%lu\n", (int)OS_RwLockCreate(&rid, "rwA", 0x33),
               (unsigned long)stub_last_options);
        printf("rw_type %lu rt=%d wt=%d\n", (unsigned long)OS_ObjectIdToType_Impl(rid),
               (int)OS_RwLockReadTake(rid), (int)OS_RwLockWriteTake(rid));
        printf("rw_info rc=%d [%s]\n", (int)OS_RwLockGetInfo(rid, &rprop), rprop.name);

        printf("cv_create rc=%d opt=%lu\n", (int)OS_CondVarCreate(&vid, "cvA", 0x44),
               (unsigned long)stub_last_options);
        wake.ticks = 12345;
        printf("cv_type %lu sig=%d wait=%d\n", (unsigned long)OS_ObjectIdToType_Impl(vid),
               (int)OS_CondVarSignal(vid), (int)OS_CondVarTimedWait(vid, &wake));
        /* CondVarTimedWait has its own OS_CHECK_POINTER that its siblings lack -- a BUGCHECK,
         * so it logs. A generated template gave it the binsem shape and this caught it. */
        printf("cv_nullwake rc=%d\n", (int)OS_CondVarTimedWait(vid, NULL));
        printf("cv_info rc=%d [%s]\n", (int)OS_CondVarGetInfo(vid, &vprop), vprop.name);

        /* All four ids must be distinct types out of one shared table. */
        printf("types   %lu %lu %lu %lu\n", (unsigned long)OS_ObjectIdToType_Impl(mid),
               (unsigned long)OS_ObjectIdToType_Impl(bid), (unsigned long)OS_ObjectIdToType_Impl(rid),
               (unsigned long)OS_ObjectIdToType_Impl(vid));
        printf("byname  %d %d %d %d\n",
               (int)(OS_MutSemGetIdByName(&found, "mxA") == OS_SUCCESS),
               (int)(OS_BinSemGetIdByName(&found, "bsA") == OS_SUCCESS),
               (int)(OS_RwLockGetIdByName(&found, "rwA") == OS_SUCCESS),
               (int)(OS_CondVarGetIdByName(&found, "cvA") == OS_SUCCESS));
        printf("deletes %d %d %d %d\n", (int)OS_MutSemDelete(mid), (int)OS_BinSemDelete(bid),
               (int)OS_RwLockDelete(rid), (int)OS_CondVarDelete(vid));
    }
    return 0;
}
