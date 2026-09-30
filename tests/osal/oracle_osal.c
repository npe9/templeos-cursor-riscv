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
#include "os-shared-network.h"
#include "os-shared-shell.h"
#include "os-shared-task-affinity.h"
#include "os-shared-filesys.h"
#include "os-shared-file.h"
#include "os-shared-dir.h"
#include "os-shared-select.h"
#include "os-shared-module.h"
#include "osapi-task-affinity.h"
#include "os-shared-countsem.h"
#include "os-shared-mutex.h"
#include "os-shared-binsem.h"
#include "os-shared-rwlock.h"
#include "os-shared-condvar.h"
#include "os-shared-queue.h"
#include "os-shared-task.h"
#include "os-shared-network.h"
#include "os-shared-shell.h"
#include "os-shared-task-affinity.h"
#include "os-shared-filesys.h"
#include "os-shared-file.h"
#include "os-shared-dir.h"
#include "os-shared-select.h"
#include "os-shared-module.h"
#include "osapi-task-affinity.h"

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

/* OS_TaskGetId_Impl moved down to the task backend, and OS_TaskGetId deleted outright: now
 * that osapi-task.c is in the build, the REAL one links from NASA's source. It is what idmap
 * calls to stamp `creator` on every record, so the stub's fixed 0x10001 becomes the initial
 * value of stub_t_current instead, and every creator line before the task section is
 * unchanged. */

/* The countsem backend. Records what it was asked to do and reports a value back through
 * GetInfo, so the transcript can show the portable layer passing arguments down and results up
 * without any real semaphore existing. */
static uint32 stub_cs_initial;
static uint32 stub_cs_options;
static int    stub_cs_gives;
static int    stub_cs_takes;
static uint32 stub_cs_last_msecs;

/* --- osapi-module.c backend ---------------------------------------------------------------
 * OS_SymbolLookup_Impl returns a DISTINCT error so the transcript can show which of the two
 * lookups produced the final code: NASA only overwrites the backend's error when the STATIC
 * table succeeds, and with the static loader disabled it never does.
 */
static int    stub_m_loads, stub_m_unloads, stub_m_infos, stub_m_syms, stub_m_modsyms, stub_m_dumps;
static char   stub_m_lastpath[OS_MAX_LOCAL_PATH_LEN];
static int64  stub_m_dumplimit;
static int32  stub_m_sym_rc = OS_ERR_NOT_IMPLEMENTED;

int32 OS_ModuleLoad_Impl(const OS_object_token_t *token, const char *translated_path)
{
    ++stub_m_loads;
    strncpy(stub_m_lastpath, translated_path, sizeof(stub_m_lastpath) - 1);
    return OS_SUCCESS;
}
int32 OS_ModuleUnload_Impl(const OS_object_token_t *token) { ++stub_m_unloads; return OS_SUCCESS; }
int32 OS_ModuleGetInfo_Impl(const OS_object_token_t *token, OS_module_prop_t *module_prop)
{
    ++stub_m_infos;
    module_prop->entry_point    = 0xC0DE;
    module_prop->addr.valid     = 1;
    module_prop->addr.code_size = 256;
    return OS_SUCCESS;
}
int32 OS_SymbolLookup_Impl(cpuaddr *SymbolAddress, const char *SymbolName)
{
    ++stub_m_syms;
    if (strcmp(SymbolName, "known") == 0)
    {
        *SymbolAddress = 0xBEEF;
        return OS_SUCCESS;
    }
    return stub_m_sym_rc;
}
int32 OS_ModuleSymbolLookup_Impl(const OS_object_token_t *token, cpuaddr *SymbolAddress,
                                 const char *SymbolName)
{
    ++stub_m_modsyms;
    return stub_m_sym_rc;
}
int32 OS_SymbolTableDump_Impl(const char *filename, size_t size_limit)
{
    ++stub_m_dumps;
    strncpy(stub_m_lastpath, filename, sizeof(stub_m_lastpath) - 1);
    stub_m_dumplimit = (int64)size_limit;
    return OS_SUCCESS;
}

/* --- osapi-select.c backend --------------------------------------------------------------- */
static int    stub_sel_singles, stub_sel_multiples;
static uint32 stub_sel_flags_in;
static int64  stub_sel_lastabs;

int32 OS_SelectSingle_Impl(const OS_object_token_t *token, uint32 *StateFlags, OS_time_t abs_timeout)
{
    ++stub_sel_singles;
    stub_sel_flags_in = *StateFlags;
    stub_sel_lastabs  = abs_timeout.ticks;
    *StateFlags       = OS_STREAM_STATE_READABLE;
    return OS_SUCCESS;
}
int32 OS_SelectMultiple_Impl(OS_FdSet *ReadSet, OS_FdSet *WriteSet, OS_time_t abs_timeout)
{
    ++stub_sel_multiples;
    stub_sel_lastabs = abs_timeout.ticks;
    return OS_SUCCESS;
}

/* --- osapi-dir.c backend ------------------------------------------------------------------ */
static int  stub_d_creates, stub_d_opens, stub_d_closes, stub_d_reads, stub_d_rewinds, stub_d_removes;
static int  stub_d_pos;
static char stub_d_lastpath[OS_MAX_LOCAL_PATH_LEN];
static const char *stub_d_names[3] = {"alpha", "beta", "gamma"};

int32 OS_DirCreate_Impl(const char *local_path, uint32 access)
{
    ++stub_d_creates;
    strncpy(stub_d_lastpath, local_path, sizeof(stub_d_lastpath) - 1);
    return OS_SUCCESS;
}
int32 OS_DirOpen_Impl(const OS_object_token_t *token, const char *local_path)
{
    ++stub_d_opens;
    strncpy(stub_d_lastpath, local_path, sizeof(stub_d_lastpath) - 1);
    stub_d_pos = 0;
    return OS_SUCCESS;
}
int32 OS_DirClose_Impl(const OS_object_token_t *token) { ++stub_d_closes; return OS_SUCCESS; }
int32 OS_DirRead_Impl(const OS_object_token_t *token, os_dirent_t *dirent)
{
    ++stub_d_reads;
    if (stub_d_pos >= 3)
    {
        return OS_ERROR;
    }
    strncpy(dirent->FileName, stub_d_names[stub_d_pos], sizeof(dirent->FileName) - 1);
    ++stub_d_pos;
    return OS_SUCCESS;
}
int32 OS_DirRewind_Impl(const OS_object_token_t *token)
{
    ++stub_d_rewinds;
    stub_d_pos = 0;
    return OS_SUCCESS;
}
int32 OS_DirRemove_Impl(const char *local_path) { ++stub_d_removes; return OS_SUCCESS; }

/* --- osapi-file.c backend ----------------------------------------------------------------
 * A simulated file, because OS_cp is a READ/WRITE LOOP and the only way to test it is to make
 * reads and writes behave like real ones. Two details are deliberate:
 *
 *   GenericWrite_Impl writes AT MOST stub_f_wrchunk bytes and returns that count, which is
 *   what a real write does under pressure. OS_cp has an inner `while (wr_total < rd_size)`
 *   loop for exactly this, and with a chunk smaller than a block that loop is the only thing
 *   standing between a correct copy and silent data loss.
 *
 *   GenericRead_Impl returns short at end of file and then 0, which is what terminates OS_cp's
 *   outer loop.
 */
#define STUB_F_SRC_LEN 1000
static uint8 stub_f_src[STUB_F_SRC_LEN];
static uint8 stub_f_dst[STUB_F_SRC_LEN * 2];
static size_t stub_f_rdpos, stub_f_wrpos;
static size_t stub_f_wrchunk = 100;
static int    stub_f_opens, stub_f_closes, stub_f_removes, stub_f_renames, stub_f_chmods;
static int    stub_f_stats, stub_f_seeks, stub_f_allocs, stub_f_truncs;
static int32  stub_f_open_rc = OS_SUCCESS;
static char   stub_f_lastpath[OS_MAX_LOCAL_PATH_LEN];

int32 OS_FileOpen_Impl(const OS_object_token_t *token, const char *local_path, int32 flags,
                       int32 access_mode)
{
    ++stub_f_opens;
    strncpy(stub_f_lastpath, local_path, sizeof(stub_f_lastpath) - 1);
    return stub_f_open_rc;
}
int32 OS_GenericClose_Impl(const OS_object_token_t *token) { ++stub_f_closes; return OS_SUCCESS; }
int32 OS_GenericRead_Impl(const OS_object_token_t *token, void *buffer, size_t nbytes,
                          OS_time_t abstime)
{
    size_t n = STUB_F_SRC_LEN - stub_f_rdpos;
    if (n > nbytes)
    {
        n = nbytes;
    }
    memcpy(buffer, &stub_f_src[stub_f_rdpos], n);
    stub_f_rdpos += n;
    return (int32)n;
}
int32 OS_GenericWrite_Impl(const OS_object_token_t *token, const void *buffer, size_t nbytes,
                           OS_time_t abstime)
{
    size_t n = nbytes;
    if (n > stub_f_wrchunk)
    {
        n = stub_f_wrchunk;
    }
    memcpy(&stub_f_dst[stub_f_wrpos], buffer, n);
    stub_f_wrpos += n;
    return (int32)n;
}
int32 OS_GenericSeek_Impl(const OS_object_token_t *token, osal_offset_t offset, uint32 whence)
{
    ++stub_f_seeks;
    return (int32)offset;
}
int32 OS_FileChmod_Impl(const char *local_path, uint32 access_mode) { ++stub_f_chmods; return OS_SUCCESS; }
int32 OS_FileStat_Impl(const char *local_path, os_fstat_t *filestat)
{
    ++stub_f_stats;
    filestat->FileModeBits = OS_FILESTAT_MODE_READ | OS_FILESTAT_MODE_WRITE;
    filestat->FileSize     = 4321;
    return OS_SUCCESS;
}
int32 OS_FileRemove_Impl(const char *local_path) { ++stub_f_removes; return OS_SUCCESS; }
int32 OS_FileRename_Impl(const char *old_path, const char *new_path) { ++stub_f_renames; return OS_SUCCESS; }
int32 OS_FileAllocate_Impl(const OS_object_token_t *token, osal_offset_t offset, osal_offset_t length)
{
    ++stub_f_allocs;
    return OS_SUCCESS;
}
int32 OS_FileTruncate_Impl(const OS_object_token_t *token, osal_offset_t length)
{
    ++stub_f_truncs;
    return OS_SUCCESS;
}

/* --- osapi-filesys.c backend -------------------------------------------------------------
 * A real backend is what gives a volume its host-side mount point, so StartVolume_Impl does
 * that here: without it system_mountpt stays empty and OS_mount can never get past its
 * "system mount point should be a non-empty string" check.
 */
static int   stub_fs_starts, stub_fs_stops, stub_fs_formats, stub_fs_mounts, stub_fs_unmounts;
static int   stub_fs_checks, stub_fs_stats, stub_fs_repair;
static int32 stub_fs_format_rc = OS_SUCCESS;
static int32 stub_fs_mount_rc  = OS_SUCCESS;

int32 OS_FileSysStartVolume_Impl(const OS_object_token_t *token)
{
    OS_filesys_internal_record_t *fs = OS_OBJECT_TABLE_GET(OS_filesys_table, *token);
    ++stub_fs_starts;
    /* Only give a host mount point to volumes that do not already have one: AddFixedMap sets
     * system_mountpt itself, and overwriting it would erase the caller's phys_path. */
    if (fs->system_mountpt[0] == 0)
    {
        strncpy(fs->system_mountpt, "/host/ram", sizeof(fs->system_mountpt) - 1);
    }
    return OS_SUCCESS;
}
int32 OS_FileSysStopVolume_Impl(const OS_object_token_t *token) { ++stub_fs_stops; return OS_SUCCESS; }
int32 OS_FileSysFormatVolume_Impl(const OS_object_token_t *token)
{
    ++stub_fs_formats;
    return stub_fs_format_rc;
}
int32 OS_FileSysMountVolume_Impl(const OS_object_token_t *token)
{
    ++stub_fs_mounts;
    return stub_fs_mount_rc;
}
int32 OS_FileSysUnmountVolume_Impl(const OS_object_token_t *token) { ++stub_fs_unmounts; return OS_SUCCESS; }
int32 OS_FileSysCheckVolume_Impl(const OS_object_token_t *token, bool repair)
{
    ++stub_fs_checks;
    stub_fs_repair = repair;
    return OS_SUCCESS;
}
int32 OS_FileSysStatVolume_Impl(const OS_object_token_t *token, OS_statvfs_t *statbuf)
{
    ++stub_fs_stats;
    statbuf->block_size   = 512;
    statbuf->total_blocks = 1000;
    statbuf->blocks_free  = 640;
    return OS_SUCCESS;
}

/* Dumps every filesys entry in use, in index order. The driver used to print
 * OS_filesys_table[0] and [1] directly and was off by one: OS_ObjectIdFindNextFree starts its
 * search at last_alloc + 1, so the FIRST volume allocated lands at index 1 and slot 0 stayed
 * empty. Printing what is there, rather than where it was assumed to be, removes the
 * assumption from the transcript. */
static void fs_dump(const char *tag)
{
    int i;
    for (i = 0; i < OS_MAX_FILE_SYSTEMS; ++i)
    {
        if (OS_filesys_table[i].device_name[0] != 0 || OS_filesys_table[i].virtual_mountpt[0] != 0)
        {
            printf("%s [%d] dev=%s virt=%s type=%d flags=%u\n", tag, i,
                   OS_filesys_table[i].device_name, OS_filesys_table[i].virtual_mountpt,
                   (int)OS_filesys_table[i].fstype, (unsigned)OS_filesys_table[i].flags);
        }
    }
}

/* --- osapi-network.c / osapi-shell.c / osapi-task-affinity.c backends -------------------------
 * Three small modules that are almost pure dispatch: what the transcript pins is which checks
 * fire, what gets handed to the backend, and what each does with a failure.
 */
static int   stub_n_hostcalls, stub_n_idcalls, stub_sh_calls;
static int   stub_af_sets, stub_af_gets, stub_af_cores;
static int32 stub_n_host_rc = OS_SUCCESS;
static int32 stub_n_id_rc   = OS_SUCCESS;
static char  stub_sh_cmd[32];
static uint8 stub_af_mask;

int32 OS_NetworkGetHostName_Impl(char *host_name, size_t name_len)
{
    ++stub_n_hostcalls;
    if (stub_n_host_rc != OS_SUCCESS)
    {
        return stub_n_host_rc;
    }
    /* A real backend fills the buffer; this one writes a fixed name so the transcript can show
     * that the FAILURE path overwrites it with an empty string and the success path does not. */
    strncpy(host_name, "sat1", name_len - 1);
    return OS_SUCCESS;
}
int32 OS_NetworkGetID_Impl(int32 *IdBuf)
{
    ++stub_n_idcalls;
    *IdBuf = 4242;
    return stub_n_id_rc;
}
int32 OS_ShellOutputToFile_Impl(const OS_object_token_t *token, const char *Cmd)
{
    ++stub_sh_calls;
    strncpy(stub_sh_cmd, Cmd, sizeof(stub_sh_cmd) - 1);
    return OS_SUCCESS;
}
uint32 OS_TaskAffinityGetCoresConfigured_Impl(void)
{
    ++stub_af_cores;
    return 3;
}
int32 OS_TaskAffinitySetAffinity_Impl(const OS_object_token_t *token, const OS_cpuset_t cpuset)
{
    ++stub_af_sets;
    stub_af_mask = cpuset.affinity_mask[0];
    return OS_SUCCESS;
}
int32 OS_TaskAffinityGetAffinity_Impl(const OS_object_token_t *token, OS_cpuset_t *cpuset)
{
    ++stub_af_gets;
    cpuset->affinity_mask[0] = 0x5A;
    return OS_SUCCESS;
}

/* --- osapi-task.c backend ----------------------------------------------------------------
 * OS_TaskGetId_Impl is the "who am I" the OS would answer; here the driver sets it, which is
 * what makes OS_TaskExit, OS_TaskGetId and OS_TaskInstallDeleteHandler drivable at all.
 */
static osal_id_t stub_t_current = 0x10001;  /* what the old fixed stub returned */
static uint32    stub_t_flags;
static long      stub_t_prio, stub_t_delay;
static int       stub_t_creates, stub_t_deletes, stub_t_detaches, stub_t_exits;
static int       stub_t_registers, stub_t_matches, stub_t_hookcalls, stub_t_startups;
static int32     stub_t_setprio_rc = OS_SUCCESS;
static uint32    stub_t_sysdata_want = 4;

int32 OS_TaskCreate_Impl(const OS_object_token_t *token, uint32 flags)
{
    stub_t_flags = flags;
    ++stub_t_creates;
    return OS_SUCCESS;
}
int32 OS_TaskDelete_Impl(const OS_object_token_t *token) { ++stub_t_deletes; return OS_SUCCESS; }
int32 OS_TaskDetach_Impl(const OS_object_token_t *token)
{
    ++stub_t_detaches;
    return OS_SUCCESS;
}
void  OS_TaskExit_Impl(void) { ++stub_t_exits; }   /* the real one never returns */
int32 OS_TaskDelay_Impl(uint32 ms) { stub_t_delay = (long)ms; return OS_SUCCESS; }
int32 OS_TaskSetPriority_Impl(const OS_object_token_t *token, osal_priority_t p)
{
    stub_t_prio = (long)p;
    return stub_t_setprio_rc;
}
osal_id_t OS_TaskGetId_Impl(void) { return stub_t_current; }
int32 OS_TaskGetInfo_Impl(const OS_object_token_t *token, OS_task_prop_t *p) { return OS_SUCCESS; }
int32 OS_TaskMatch_Impl(const OS_object_token_t *token) { ++stub_t_matches; return OS_SUCCESS; }
int32 OS_TaskRegister_Impl(osal_id_t id) { ++stub_t_registers; return OS_SUCCESS; }
int32 OS_TaskValidateSystemData_Impl(const void *sysdata, size_t sysdata_size)
{
    /* Only the backend knows what a system task handle looks like, so the size rule is the
     * backend's. Making it reject one size lets the driver prove the EARLY RETURN in
     * OS_TaskFindIdBySystemData fires before any search happens. */
    if (sysdata == NULL || sysdata_size != stub_t_sysdata_want)
        return OS_ERR_INVALID_SIZE;
    return OS_SUCCESS;
}
bool OS_TaskIdMatchSystemData_Impl(void *ref, const OS_object_token_t *token,
                                   const OS_common_record_t *obj)
{
    const uint32 *want = ref;
    return (obj->active_id == *want);
}
static void task_delete_hook(void) { ++stub_t_hookcalls; }
static void task_entry_a(void) { ++stub_t_startups; }

/* --- osapi-queue.c backend ---------------------------------------------------------------
 * OS_QueueCreate_Impl is handed only (token, flags) -- the depth and the data size the caller
 * passed go into the table record, and a real backend reads them back out through the token.
 * The stub does the same, because that is the ONLY way this transcript can see that Create
 * stored them in the right fields: OS_queue_prop_t exposes name and creator and nothing else.
 */
static uint32 stub_q_flags, stub_q_put_flags;
static long   stub_q_depth, stub_q_size, stub_q_put_size, stub_q_timeout;
static int    stub_q_gets, stub_q_puts;

int32 OS_QueueCreate_Impl(const OS_object_token_t *token, uint32 flags)
{
    const OS_queue_internal_record_t *q = OS_OBJECT_TABLE_GET(OS_queue_table, *token);
    stub_q_flags = flags;
    stub_q_depth = (long)q->max_depth;
    stub_q_size  = (long)q->max_size;
    return OS_SUCCESS;
}
int32 OS_QueueDelete_Impl(const OS_object_token_t *token) { return OS_SUCCESS; }
int32 OS_QueueGet_Impl(const OS_object_token_t *token, void *data, size_t size,
                       size_t *size_copied, int32 timeout)
{
    *size_copied = size;
    stub_q_timeout = (long)timeout;
    ++stub_q_gets;
    return OS_SUCCESS;
}
int32 OS_QueuePut_Impl(const OS_object_token_t *token, const void *data, size_t size, uint32 flags)
{
    stub_q_put_size  = (long)size;
    stub_q_put_flags = flags;
    ++stub_q_puts;
    return OS_SUCCESS;
}

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
/* These read last_owner out of the table, which is the only way the transcript can see the
 * ownership tracking in OS_MutSemGive/Take: OS_mut_sem_prop_t exposes name and creator, and the
 * OS_DEBUG warning is a no-op in this configuration. A real backend has the same access. */
static osal_id_t stub_mx_owner_at_give;
static osal_id_t stub_mx_owner_at_take;
int32 OS_MutSemGive_Impl(const OS_object_token_t *t)
{
    stub_mx_owner_at_give = OS_mutex_table[OS_ObjectIndexFromToken(t)].last_owner;
    return OS_SUCCESS;
}
int32 OS_MutSemTake_Impl(const OS_object_token_t *t)
{
    stub_mx_owner_at_take = OS_mutex_table[OS_ObjectIndexFromToken(t)].last_owner;
    return OS_SUCCESS;
}
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
static osal_id_t stub_rw_writer_at_give;
int32 OS_RwLockWriteGive_Impl(const OS_object_token_t *t)
{
    stub_rw_writer_at_give = OS_rwlock_table[OS_ObjectIndexFromToken(t)].last_writer;
    return OS_SUCCESS;
}
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

        /* --- osapi-queue.c ---------------------------------------------------------------
         * The Get and Put size checks are ASYMMETRIC and easy to get backwards:
         *     Get rejects a buffer SMALLER than max_size  (size < max_size)
         *     Put rejects a payload LARGER  than max_size  (size > max_size)
         * One size proves nothing, because at size == max_size both operators agree. Each is
         * driven at max_size-1, max_size and max_size+1, and the RETURN CODE is printed rather
         * than pass/fail, because the size-parameter check returns OS_ERR_INVALID_SIZE while
         * the max_size mismatch returns OS_QUEUE_INVALID_SIZE -- confusing the two codes would
         * survive any "it rejected it" test.
         */
        {
            osal_id_t qid, qid2, qfound;
            OS_queue_prop_t qprop;
            size_t cp;
            char buf[32];
            char qlong[OS_MAX_API_NAME + 8];
            int i;

            OS_QueueAPI_Init();
            printf("q_create rc=%d flags=0x%lx depth=%ld size=%ld\n",
                   (int)OS_QueueCreate(&qid, "qA", 4, 16, 0xA5), (unsigned long)stub_q_flags,
                   stub_q_depth, stub_q_size);

            printf("q_put_lt rc=%d\n", (int)OS_QueuePut(qid, "p", 15, 0x77));
            printf("q_put_eq rc=%d\n", (int)OS_QueuePut(qid, "p", 16, 0x77));
            printf("q_put_gt rc=%d\n", (int)OS_QueuePut(qid, "p", 17, 0x77));
            printf("q_put_n  %d last=%ld fl=0x%lx\n", stub_q_puts, stub_q_put_size,
                   (unsigned long)stub_q_put_flags);

            /* Poisoned, not zeroed: OS_QueueGet writes *size_copied = 0 on the reject path,
             * and a destination that started at 0 would let a missing store pass blind. */
            cp = 0xEE;
            printf("q_get_lt rc=%d cp=%ld\n", (int)OS_QueueGet(qid, buf, 15, &cp, 5), (long)cp);
            cp = 0xEE;
            printf("q_get_eq rc=%d cp=%ld\n", (int)OS_QueueGet(qid, buf, 16, &cp, 5), (long)cp);
            cp = 0xEE;
            printf("q_get_gt rc=%d cp=%ld\n", (int)OS_QueueGet(qid, buf, 17, &cp, 5), (long)cp);
            printf("q_get_n  %d timeout=%ld\n", stub_q_gets, stub_q_timeout);

            /* A BAD SIZE is a different code from a size that merely mismatches max_size. */
            cp = 0xEE;
            printf("q_zero   put=%d get=%d\n", (int)OS_QueuePut(qid, "p", 0, 0),
                   (int)OS_QueueGet(qid, buf, 0, &cp, 0));
            /* size is size_t (unsigned) in NASA's C and I64 (signed) in the translation. Both
             * reject this, by different routes: too large there, negative here. */
            cp = 0xEE;
            printf("q_huge   put=%d get=%d\n",
                   (int)OS_QueuePut(qid, "p", (size_t)0x8000000000000000ULL, 0),
                   (int)OS_QueueGet(qid, buf, (size_t)0x8000000000000000ULL, &cp, 0));

            printf("q_nullid   rc=%d\n", (int)OS_QueueCreate(NULL, "x", 4, 16, 0));
            printf("q_nullname rc=%d\n", (int)OS_QueueCreate(&qid2, NULL, 4, 16, 0));
            for (i = 0; i < (int)sizeof(qlong) - 1; ++i) qlong[i] = 'q';
            qlong[sizeof(qlong) - 1] = '\0';
            printf("q_longname rc=%d\n", (int)OS_QueueCreate(&qid2, qlong, 4, 16, 0));
            printf("q_badsize  rc=%d\n", (int)OS_QueueCreate(&qid2, "qB", 4, 0, 0));
            /* depth > OS_QUEUE_MAX_DEPTH is OS_QUEUE_INVALID_SIZE, not OS_ERR_INVALID_SIZE */
            printf("q_deep     rc=%d\n",
                   (int)OS_QueueCreate(&qid2, "qB", OS_QUEUE_MAX_DEPTH + 1, 16, 0));
            cp = 0xEE;
            printf("q_nulldata put=%d get=%d cp=%ld\n", (int)OS_QueuePut(qid, NULL, 4, 0),
                   (int)OS_QueueGet(qid, NULL, 4, &cp, 0), (long)cp);
            printf("q_nullcp   rc=%d\n", (int)OS_QueueGet(qid, buf, 4, NULL, 0));

            printf("q_byname   rc=%d match=%d\n", (int)OS_QueueGetIdByName(&qfound, "qA"),
                   (int)OS_ObjectIdEqual(qfound, qid));
            printf("q_byname_miss rc=%d\n", (int)OS_QueueGetIdByName(&qfound, "nope"));
            printf("q_info     rc=%d [%s]\n", (int)OS_QueueGetInfo(qid, &qprop), qprop.name);
            printf("q_nullprop rc=%d\n", (int)OS_QueueGetInfo(qid, NULL));
            printf("q_delete   rc=%d\n", (int)OS_QueueDelete(qid));
            printf("q_stale    rc=%d\n", (int)OS_QueuePut(qid, "p", 4, 0));
        }

        /* --- osapi-task.c ----------------------------------------------------------------
         * Three things here are easy to get wrong and invisible to a "did it return 0" test:
         *   - SetPriority writes the table ONLY when the backend succeeded, so the failing
         *     case must show the OLD priority still in place;
         *   - Delete calls the hook AFTER the record is finalized, so both "was it called"
         *     and "was it called once" matter. (The SAVE happening before is not observable:
         *     a control moved it after FinalizeDelete and the transcript did not change.);
         *   - FindIdBySystemData returns the backend's validation error EARLY, before any
         *     search, so a wrong size must not reach the match function.
         */
        {
            osal_id_t tid, tid2, tfound;
            OS_task_prop_t tprop;
            char tlong[OS_MAX_API_NAME + 8];
            uint32 want;
            int i;

            OS_TaskAPI_Init();
            printf("t_create  rc=%d fl=0x%lx n=%d\n",
                   (int)OS_TaskCreate(&tid, "tA", task_entry_a, NULL, 4096, 100, 0x11),
                   (unsigned long)stub_t_flags, stub_t_creates);
            printf("t_info    rc=%d [%s] stack=%ld prio=%d\n", (int)OS_TaskGetInfo(tid, &tprop),
                   tprop.name, (long)tprop.stack_size, (int)tprop.priority);

            printf("t_nullid   rc=%d\n", (int)OS_TaskCreate(NULL, "x", task_entry_a, NULL, 16, 1, 0));
            printf("t_nullfn   rc=%d\n", (int)OS_TaskCreate(&tid2, "x", NULL, NULL, 16, 1, 0));
            printf("t_nullname rc=%d\n", (int)OS_TaskCreate(&tid2, NULL, task_entry_a, NULL, 16, 1, 0));
            for (i = 0; i < (int)sizeof(tlong) - 1; ++i) tlong[i] = 't';
            tlong[sizeof(tlong) - 1] = '\0';
            printf("t_longname rc=%d\n", (int)OS_TaskCreate(&tid2, tlong, task_entry_a, NULL, 16, 1, 0));
            printf("t_zerostk  rc=%d\n", (int)OS_TaskCreate(&tid2, "tB", task_entry_a, NULL, 0, 1, 0));

            printf("t_byname   rc=%d match=%d\n", (int)OS_TaskGetIdByName(&tfound, "tA"),
                   (int)OS_ObjectIdEqual(tfound, tid));
            printf("t_byname_miss rc=%d\n", (int)OS_TaskGetIdByName(&tfound, "nope"));

            /* Priority: the backend succeeds, so the table must take the new value. */
            printf("t_prio_ok  rc=%d impl=%ld\n", (int)OS_TaskSetPriority(tid, 55), stub_t_prio);
            OS_TaskGetInfo(tid, &tprop);
            printf("t_prio_tbl prio=%d\n", (int)tprop.priority);
            /* Now the backend FAILS: the table must keep 55, not take 77. */
            stub_t_setprio_rc = OS_ERROR;
            printf("t_prio_bad rc=%d impl=%ld\n", (int)OS_TaskSetPriority(tid, 77), stub_t_prio);
            OS_TaskGetInfo(tid, &tprop);
            printf("t_prio_keep prio=%d\n", (int)tprop.priority);
            stub_t_setprio_rc = OS_SUCCESS;

            printf("t_delay    rc=%d ms=%ld\n", (int)OS_TaskDelay(250), stub_t_delay);

            /* "Who am I" drives GetId and InstallDeleteHandler, both of which ask the backend. */
            stub_t_current = tid;
            printf("t_getid    match=%d\n", (int)OS_ObjectIdEqual(OS_TaskGetId(), tid));
            printf("t_hook_in  rc=%d\n", (int)OS_TaskInstallDeleteHandler(task_delete_hook));

            /* FindIdBySystemData: the wrong size must not reach the match function. */
            want = OS_ObjectIdToInteger(tid);
            printf("t_sysbad   rc=%d\n", (int)OS_TaskFindIdBySystemData(&tfound, &want, 3));
            printf("t_sysok    rc=%d match=%d\n",
                   (int)OS_TaskFindIdBySystemData(&tfound, &want, 4),
                   (int)OS_ObjectIdEqual(tfound, tid));
            printf("t_sysnull  rc=%d\n", (int)OS_TaskFindIdBySystemData(NULL, &want, 4));

            /* Delete runs the hook that was installed above, exactly once. */
            printf("t_delete   rc=%d del=%d hook=%d\n", (int)OS_TaskDelete(tid),
                   stub_t_deletes, stub_t_hookcalls);
            printf("t_stale    rc=%d\n", (int)OS_TaskDelete(tid));

            /* OS_TaskEntryPoint is what the backend calls in the new thread: it prepares the
             * task, runs the entry function, then exits -- which detaches and finalizes. */
            OS_TaskCreate(&tid2, "tB", task_entry_a, NULL, 2048, 60, 0);
            stub_t_current = tid2;
            OS_TaskEntryPoint(tid2);
            printf("t_entry    ran=%d match=%d reg=%d detach=%d exit=%d\n", stub_t_startups,
                   stub_t_matches, stub_t_registers, stub_t_detaches, stub_t_exits);
            printf("t_gone     rc=%d\n", (int)OS_TaskGetInfo(tid2, &tprop));
        }

        /* --- osapi-network.c, osapi-shell.c, osapi-task-affinity.c ------------------------
         * Each of these has one thing worth asserting beyond "it dispatched":
         *   network: on backend FAILURE, OS_NetworkGetHostName blanks the caller's buffer, and
         *            OS_NetworkGetID returns a hardcoded -1 rather than the backend's value;
         *   shell:   the stream is taken with LOCK_MODE_REFCOUNT, not GLOBAL;
         *   affinity: OS_TaskAffinityGetCoresConfigured asks the BACKEND while
         *            OS_TaskAffinityCoresConfigured returns what OSAL recorded -- two functions
         *            one character apart in meaning, which is exactly the kind of pair a
         *            template gets wrong.
         */
        {
            char        hname[32];
            OS_cpuset_t cpuset;
            osal_id_t   atid;

            printf("net_init  rc=%d\n", (int)OS_NetworkAPI_Init());
            memset(hname, 'Z', sizeof(hname));
            printf("net_host  rc=%d [%s] n=%d\n", (int)OS_NetworkGetHostName(hname, sizeof(hname)),
                   hname, stub_n_hostcalls);
            /* The failure path must BLANK the buffer, so poison it with a non-empty string
             * first -- starting from the success value would let a missing blank pass. */
            stub_n_host_rc = OS_ERROR;
            printf("net_hfail rc=%d empty=%d n=%d\n", (int)OS_NetworkGetHostName(hname, sizeof(hname)),
                   (int)(hname[0] == 0), stub_n_hostcalls);
            stub_n_host_rc = OS_SUCCESS;
            printf("net_hnull rc=%d\n", (int)OS_NetworkGetHostName(NULL, 8));
            printf("net_hzero rc=%d\n", (int)OS_NetworkGetHostName(hname, 0));
            printf("net_id    %d n=%d\n", (int)OS_NetworkGetID(), stub_n_idcalls);
            stub_n_id_rc = OS_ERROR;
            printf("net_idbad %d n=%d\n", (int)OS_NetworkGetID(), stub_n_idcalls);
            stub_n_id_rc = OS_SUCCESS;

            printf("sh_null   rc=%d\n", (int)OS_ShellOutputToFile(NULL, OS_ObjectIdFromInteger(1)));
            printf("sh_badfd  rc=%d n=%d\n",
                   (int)OS_ShellOutputToFile("ls", OS_ObjectIdFromInteger(0x66000001)),
                   stub_sh_calls);

            printf("af_cores  impl=%lu recorded=%lu n=%d\n",
                   (unsigned long)OS_TaskAffinityGetCoresConfigured(),
                   (unsigned long)OS_TaskAffinityCoresConfigured(), stub_af_cores);
            OS_SharedGlobalVars.CoresConfigured = 7;
            printf("af_cores2 recorded=%lu\n", (unsigned long)OS_TaskAffinityCoresConfigured());
            OS_TaskCreate(&atid, "tAff", task_entry_a, NULL, 1024, 40, 0);
            memset(&cpuset, 0, sizeof(cpuset));
            cpuset.affinity_mask[0] = 0x81;
            printf("af_set    rc=%d mask=%d n=%d\n", (int)OS_TaskAffinitySetAffinity(atid, cpuset),
                   (int)stub_af_mask, stub_af_sets);
            memset(&cpuset, 0, sizeof(cpuset));
            printf("af_get    rc=%d mask=%d n=%d\n", (int)OS_TaskAffinityGetAffinity(atid, &cpuset),
                   (int)cpuset.affinity_mask[0], stub_af_gets);
            /* A bad id must not reach the backend, and the UNCONDITIONAL OS_ObjectIdRelease
             * that follows it must be harmless -- see the note in the translation. */
            printf("af_badid  rc=%d sets=%d gets=%d\n",
                   (int)OS_TaskAffinityGetAffinity(OS_ObjectIdFromInteger(0x11000099), &cpuset),
                   stub_af_sets, stub_af_gets);
        }

        /* --- mutex and rwlock OWNERSHIP ----------------------------------------------------
         * These fields, and every check that reads them, were MISSING from the translation and
         * no behavioural gate noticed: nothing exposes last_owner through the public API, and
         * the OS_DEBUG warning that reads it is a no-op in this configuration. Found by
         * tools/cfs/check_structs.py comparing fields against NASA's struct.
         *
         * So the backend reads them, as a real one can. Take must RECORD the caller, and Give
         * must CLEAR it -- and the order matters: Take_Impl runs BEFORE the store, so it sees
         * the old value, while Give_Impl runs AFTER the clear and sees UNDEFINED.
         */
        {
            osal_id_t    owner_mid, owner_rid;
            osal_index_t mxi, rwi;

            stub_t_current = OS_ObjectIdFromInteger(0x10007);
            OS_MutSemCreate(&owner_mid, "mxOwn", 0);
            OS_RwLockCreate(&owner_rid, "rwOwn", 0);
            OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_MUTEX, owner_mid, &mxi);
            OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_RWLOCK, owner_rid, &rwi);

            printf("mx_take   rc=%d seen_before=%lu\n", (int)OS_MutSemTake(owner_mid),
                   (unsigned long)OS_ObjectIdToInteger(stub_mx_owner_at_take));
            printf("mx_owner  stored=%lu\n",
                   (unsigned long)OS_ObjectIdToInteger(OS_mutex_table[mxi].last_owner));
            printf("mx_give   rc=%d seen_after=%lu\n", (int)OS_MutSemGive(owner_mid),
                   (unsigned long)OS_ObjectIdToInteger(stub_mx_owner_at_give));

            /* Taken by one task, given by another: NASA logs a warning (a no-op here) and
             * clears last_owner regardless, so the clear must still happen. */
            OS_MutSemTake(owner_mid);
            stub_t_current = OS_ObjectIdFromInteger(0x10008);
            printf("mx_cross  rc=%d seen_after=%lu\n", (int)OS_MutSemGive(owner_mid),
                   (unsigned long)OS_ObjectIdToInteger(stub_mx_owner_at_give));

            printf("rw_wtake  rc=%d\n", (int)OS_RwLockWriteTake(owner_rid));
            printf("rw_writer stored=%lu\n",
                   (unsigned long)OS_ObjectIdToInteger(OS_rwlock_table[rwi].last_writer));
            /* ReadGive reads last_writer and does NOT clear it; WriteGive does. */
            printf("rw_rgive  rc=%d still=%lu\n", (int)OS_RwLockReadGive(owner_rid),
                   (unsigned long)OS_ObjectIdToInteger(OS_rwlock_table[rwi].last_writer));
            printf("rw_wgive  rc=%d seen_after=%lu cleared=%lu\n", (int)OS_RwLockWriteGive(owner_rid),
                   (unsigned long)OS_ObjectIdToInteger(stub_rw_writer_at_give),
                   (unsigned long)OS_ObjectIdToInteger(OS_rwlock_table[rwi].last_writer));
            stub_t_current = OS_ObjectIdFromInteger(0x10001);
        }

        /* --- osapi-filesys.c --------------------------------------------------------------
         * The richest part is OS_TranslatePath, which is pure string logic with several ways
         * to fail, and OS_FileSys_FindVirtMountPoint underneath it -- whose whole reason for
         * existing is that a mount point of /mnt/abc must NOT match a target of /mnt/abcd.
         * The flag arithmetic in mount/unmount is the other half: both mask out FIXED and then
         * demand an EXACT flag set, so a single wrong bit is a state error.
         */
        {
            osal_id_t    fsid;
            OS_statvfs_t sb;
            os_fsinfo_t  fsinfo;
            char         local[OS_MAX_LOCAL_PATH_LEN];
            char         phys[OS_FS_PHYS_NAME_LEN];
            char         longpath[OS_MAX_PATH_LEN + 8];
            int          i;

            OS_FileSysAPI_Init();
            printf("fs_init   rc=%d\n", (int)OS_FileSysAPI_Init());

            /* mkfs FORMATS, initfs does not -- the one difference between them. */
            printf("fs_mkfs   rc=%d starts=%d formats=%d\n",
                   (int)OS_mkfs(NULL, "/dev/ram0", "RAMDISK", 512, 1000),
                   stub_fs_starts, stub_fs_formats);
            printf("fs_initfs rc=%d starts=%d formats=%d\n",
                   (int)OS_initfs(NULL, "/dev/ram1", "OTHER", 512, 1000),
                   stub_fs_starts, stub_fs_formats);
            /* RAM-disk detection: volname beginning "RAM" OR a non-NULL address. "OTHER" above
             * got neither, so the two entries must have DIFFERENT fstype. */
            /* RAM-disk detection: volname beginning "RAM" OR a non-NULL address. "OTHER"
             * above got neither, so the two entries must differ in fstype. */
            fs_dump("fs_tbl  ");

            /* Same device again: ALLOCATE fails and the historic code is substituted. */
            printf("fs_again  rc=%d\n", (int)OS_mkfs(NULL, "/dev/ram0", "RAMDISK", 512, 1000));
            printf("fs_noname rc=%d\n", (int)OS_mkfs(NULL, "", "RAMDISK", 512, 1000));
            printf("fs_nulldv rc=%d\n", (int)OS_mkfs(NULL, NULL, "RAMDISK", 512, 1000));

            /* A failed format must STOP the volume again rather than leave it half-made. */
            stub_fs_format_rc = OS_ERROR;
            printf("fs_badfmt rc=%d stops=%d\n", (int)OS_mkfs(NULL, "/dev/ram2", "RAMDISK", 512, 1000),
                   stub_fs_stops);
            stub_fs_format_rc = OS_SUCCESS;

            /* mount: every failure is collapsed to OS_ERR_NAME_NOT_FOUND, including the
             * INCORRECT_OBJ_STATE and PATH_INVALID computed inside. */
            printf("fs_mntbad rc=%d\n", (int)OS_mount("/dev/nope", "/mnt"));
            printf("fs_mount  rc=%d mounts=%d\n", (int)OS_mount("/dev/ram0", "/mnt"),
                   stub_fs_mounts);
            printf("fs_mnttwi rc=%d\n", (int)OS_mount("/dev/ram0", "/mnt"));

            /* TranslatePath, once something is mounted at /mnt. */
            memset(local, 0, sizeof(local));
            printf("tp_ok     rc=%d [%s]\n", (int)OS_TranslatePath("/mnt/file.txt", local), local);
            printf("tp_root   rc=%d [%s]\n", (int)OS_TranslatePath("/mnt/", local), local);
            printf("tp_nodir  rc=%d\n", (int)OS_TranslatePath("nodir", local));
            printf("tp_norel  rc=%d\n", (int)OS_TranslatePath("/mnt/../etc/x", local));
            printf("tp_nomnt  rc=%d\n", (int)OS_TranslatePath("/other/file", local));
            printf("tp_nullv  rc=%d\n", (int)OS_TranslatePath(NULL, local));
            printf("tp_nulll  rc=%d\n", (int)OS_TranslatePath("/mnt/x", NULL));
            for (i = 0; i < (int)sizeof(longpath) - 1; ++i) longpath[i] = 'p';
            longpath[0] = '/';
            longpath[sizeof(longpath) - 1] = 0;
            printf("tp_long   rc=%d\n", (int)OS_TranslatePath(longpath, local));
            /* A file name longer than OS_MAX_FILE_NAME (20) after the last '/'. */
            printf("tp_nlong  rc=%d\n",
                   (int)OS_TranslatePath("/mnt/abcdefghijklmnopqrstuvwxyz0123456789", local));
            /* THE PREFIX TRAP: /mnt must not match /mntx, and the mount point is /mnt. */
            printf("tp_prefix rc=%d\n", (int)OS_TranslatePath("/mntx/file", local));

            printf("fs_phys   rc=%d [%s]\n", (int)OS_FS_GetPhysDriveName(phys, "/mnt"), phys);
            printf("fs_physno rc=%d\n", (int)OS_FS_GetPhysDriveName(phys, "/other"));
            printf("fs_stat   rc=%d bs=%ld free=%ld n=%d\n",
                   (int)OS_FileSysStatVolume("/mnt", &sb), (long)sb.block_size,
                   (long)sb.blocks_free, stub_fs_stats);
            printf("fs_chk    rc=%d repair=%d n=%d\n", (int)OS_chkfs("/mnt", true),
                   stub_fs_repair, stub_fs_checks);

            printf("fs_info   rc=%d maxv=%lu freev=%lu maxfd=%lu\n", (int)OS_GetFsInfo(&fsinfo),
                   (unsigned long)fsinfo.MaxVolumes, (unsigned long)fsinfo.FreeVolumes,
                   (unsigned long)fsinfo.MaxFds);

            /* A fixed map sets FIXED|READY|MOUNTED_* in one go and keeps its phys_path. */
            printf("fs_fixed  rc=%d\n", (int)OS_FileSysAddFixedMap(&fsid, "/host/eeprom", "/eeprom"));
            fs_dump("fs_tbl2 ");
            memset(local, 0, sizeof(local));
            printf("tp_fixed  rc=%d [%s]\n", (int)OS_TranslatePath("/eeprom/cfg", local), local);

            /* FIXED is MASKED OUT of mount's flag check rather than rejected -- NASA's
             * comment says fixed maps "don't support mount/unmount" but that this is not
             * enforced, to support abstraction. Unmounting the fixed map leaves its flags at
             * exactly FIXED|READY, which is the only state where the mask is observable:
             * masked it reads READY and mount proceeds, unmasked it does not. */
            printf("fx_unmnt  rc=%d\n", (int)OS_unmount("/eeprom"));
            fs_dump("fx_tbl  ");
            printf("fx_remnt  rc=%d mounts=%d\n", (int)OS_mount("/eeprom", "/eeprom"), stub_fs_mounts);
            printf("fs_unmnt  rc=%d n=%d\n", (int)OS_unmount("/mnt"), stub_fs_unmounts);
            printf("fs_unmnt2 rc=%d\n", (int)OS_unmount("/mnt"));
            printf("tp_after  rc=%d\n", (int)OS_TranslatePath("/mnt/file.txt", local));
            printf("fs_rmfs   rc=%d\n", (int)OS_rmfs("/dev/ram0"));
            printf("fs_rmfs2  rc=%d\n", (int)OS_rmfs("/dev/ram0"));
        }

        /* --- osapi-file.c -----------------------------------------------------------------
         * OS_cp is the centrepiece: a read/write loop where the backend returns SHORT writes,
         * so the inner `while (wr_total < rd_size)` retry loop is what stands between a
         * correct copy and silent data loss. 1000 bytes, 512-byte blocks, 100-byte writes --
         * so both loops run several times and neither divides evenly into the other.
         *
         * This section also makes OS_ShellOutputToFile's REFCOUNT lock mode reachable for the
         * first time: until osapi-file.c was translated nothing could allocate a stream, so
         * that call only ever hit its bad-id path.
         */
        {
            osal_id_t      fd, fd2;
            OS_file_prop_t fprop;
            os_fstat_t     fstat;
            int            i;
            long           sum;

            for (i = 0; i < STUB_F_SRC_LEN; ++i) stub_f_src[i] = (uint8)(i * 7 + 3);
            OS_FileAPI_Init();
            printf("f_init    rc=%d\n", (int)OS_FileAPI_Init());

            /* /mnt is not mounted at this point in the transcript -- fs_unmnt ran above -- so
             * remount it, otherwise every path here fails translation instead of testing the
             * file layer. */
            printf("f_remount rc=%d\n", (int)OS_mount("/dev/ram1", "/mnt"));

            printf("f_badmode rc=%d\n", (int)OS_OpenCreate(&fd, "/mnt/a.txt", OS_FILE_FLAG_NONE, 99));
            printf("f_nullfd  rc=%d\n", (int)OS_OpenCreate(NULL, "/mnt/a.txt", OS_FILE_FLAG_NONE, OS_READ_ONLY));
            printf("f_badpath rc=%d\n", (int)OS_OpenCreate(&fd, "relative", OS_FILE_FLAG_NONE, OS_READ_ONLY));
            printf("f_open    rc=%d opens=%d [%s]\n",
                   (int)OS_OpenCreate(&fd, "/mnt/a.txt", OS_FILE_FLAG_NONE, OS_READ_ONLY),
                   stub_f_opens, stub_f_lastpath);
            printf("f_fdinfo  rc=%d [%s] valid=%d\n", (int)OS_FDGetInfo(fd, &fprop), fprop.Path,
                   (int)fprop.IsValid);
            printf("f_opencheck  found=%d missing=%d\n", (int)OS_FileOpenCheck("/mnt/a.txt"),
                   (int)OS_FileOpenCheck("/mnt/zz.txt"));

            /* The shell now has a real stream to write to: REFCOUNT is finally exercised. */
            printf("f_shell   rc=%d n=%d\n", (int)OS_ShellOutputToFile("ls", fd), stub_sh_calls);

            printf("f_seek    rc=%d n=%d\n", (int)OS_lseek(fd, 1234, 0), stub_f_seeks);
            printf("f_alloc   rc=%d n=%d\n", (int)OS_FileAllocate(fd, 0, 64), stub_f_allocs);
            printf("f_trunc   rc=%d n=%d\n", (int)OS_FileTruncate(fd, 32), stub_f_truncs);
            printf("f_stat    rc=%d size=%ld mode=%lu n=%d\n", (int)OS_stat("/mnt/a.txt", &fstat),
                   (long)fstat.FileSize, (unsigned long)fstat.FileModeBits, stub_f_stats);
            printf("f_chmod   rc=%d n=%d\n", (int)OS_chmod("/mnt/a.txt", 0), stub_f_chmods);
            printf("f_remove  rc=%d n=%d\n", (int)OS_remove("/mnt/a.txt"), stub_f_removes);

            /* rename rewrites the recorded name of any OPEN stream naming the old file. */
            printf("f_rename  rc=%d n=%d\n", (int)OS_rename("/mnt/a.txt", "/mnt/b.txt"),
                   stub_f_renames);
            printf("f_renamed rc=%d [%s]\n", (int)OS_FDGetInfo(fd, &fprop), fprop.Path);
            printf("f_oc_new  found=%d old=%d\n", (int)OS_FileOpenCheck("/mnt/b.txt"),
                   (int)OS_FileOpenCheck("/mnt/a.txt"));
            printf("f_close   rc=%d n=%d\n", (int)OS_close(fd), stub_f_closes);
            printf("f_stale   rc=%d\n", (int)OS_close(fd));

            /* THE COPY. Short writes make the inner loop load-bearing. */
            stub_f_rdpos = 0;
            stub_f_wrpos = 0;
            printf("f_cp      rc=%d wrote=%ld opens=%d closes=%d\n",
                   (int)OS_cp("/mnt/src.bin", "/mnt/dst.bin"), (long)stub_f_wrpos,
                   stub_f_opens, stub_f_closes);
            sum = 0;
            for (i = 0; i < STUB_F_SRC_LEN; ++i) sum += (stub_f_dst[i] == stub_f_src[i]) ? 1 : 0;
            printf("f_cpsame  bytes=%ld of %d\n", sum, STUB_F_SRC_LEN);
            printf("f_cpnull  rc=%d\n", (int)OS_cp(NULL, "/mnt/x"));

            /* mv tries rename first and only falls back to copy when it fails. */
            stub_f_rdpos = 0;
            stub_f_wrpos = 0;
            printf("f_mv      rc=%d renames=%d wrote=%ld\n", (int)OS_mv("/mnt/s2", "/mnt/d2"),
                   stub_f_renames, (long)stub_f_wrpos);

            /* Open two, then close by name and close-all. */
            OS_OpenCreate(&fd, "/mnt/one.txt", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            OS_OpenCreate(&fd2, "/mnt/two.txt", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            printf("f_byname  rc=%d\n", (int)OS_CloseFileByName("/mnt/one.txt"));
            printf("f_bynone  rc=%d\n", (int)OS_CloseFileByName("/mnt/nope.txt"));
            printf("f_all     rc=%d closes=%d\n", (int)OS_CloseAllFiles(), stub_f_closes);
            printf("f_allagain rc=%d\n", (int)OS_CloseAllFiles());
        }

        /* --- osapi-dir.c ------------------------------------------------------------------
         * THREE DIFFERENT LOCK MODES in one module, and the transcript can see them because
         * of how references are accounted:
         *   Close  EXCLUSIVE -- deletes the record
         *   Read   GLOBAL    -- and releases afterwards
         *   Rewind NONE      -- and does NOT release, because NONE took nothing
         * Rewinding several times and then closing is the test: if Rewind took a real lock
         * without releasing it, each call would leak a reference and the EXCLUSIVE close
         * afterwards could not succeed.
         */
        {
            osal_id_t   did;
            os_dirent_t dent;
            int         i;

            OS_DirAPI_Init();
            printf("d_init    rc=%d\n", (int)OS_DirAPI_Init());
            printf("d_mkdir   rc=%d n=%d [%s]\n", (int)OS_mkdir("/mnt/sub", 0), stub_d_creates,
                   stub_d_lastpath);
            printf("d_mkbad   rc=%d\n", (int)OS_mkdir("relative", 0));
            printf("d_nullid  rc=%d\n", (int)OS_DirectoryOpen(NULL, "/mnt/sub"));
            printf("d_open    rc=%d n=%d [%s]\n", (int)OS_DirectoryOpen(&did, "/mnt/sub"),
                   stub_d_opens, stub_d_lastpath);
            printf("d_nullent rc=%d\n", (int)OS_DirectoryRead(did, NULL));
            for (i = 0; i < 4; ++i)
            {
                memset(&dent, 0, sizeof(dent));
                printf("d_read%d   rc=%d [%s]\n", i, (int)OS_DirectoryRead(did, &dent),
                       OS_DIRENTRY_NAME(dent));
            }
            /* Rewind, then read again: the listing must start over. */
            printf("d_rew     rc=%d n=%d\n", (int)OS_DirectoryRewind(did), stub_d_rewinds);
            memset(&dent, 0, sizeof(dent));
            printf("d_reread  rc=%d [%s]\n", (int)OS_DirectoryRead(did, &dent),
                   OS_DIRENTRY_NAME(dent));
            /* Several more rewinds, then close. A leaked reference per rewind would show here. */
            for (i = 0; i < 5; ++i) OS_DirectoryRewind(did);
            printf("d_rew5    n=%d\n", stub_d_rewinds);
            printf("d_close   rc=%d n=%d\n", (int)OS_DirectoryClose(did), stub_d_closes);
            printf("d_stale   rc=%d\n", (int)OS_DirectoryClose(did));
            printf("d_rewbad  rc=%d\n", (int)OS_DirectoryRewind(did));
            printf("d_rmdir   rc=%d n=%d\n", (int)OS_rmdir("/mnt/sub"), stub_d_removes);
        }

        /* --- osapi-select.c ---------------------------------------------------------------
         * Bit arithmetic over a fixed set: local_id >> 3 picks the byte and (local_id & 0x7)
         * the bit. The driver adds ids that are deliberately spread across byte boundaries --
         * 0, 7, 8 and 9 -- because an index split that used the wrong shift or mask would put
         * two of those in the same place, and adding one would appear to add another.
         */
        {
            OS_FdSet  rset;
            osal_id_t sfd[4];
            uint32    flags;
            int       i;

            printf("sel_zero  rc=%d\n", (int)OS_SelectFdZero(&rset));
            printf("sel_nullz rc=%d\n", (int)OS_SelectFdZero(NULL));
            for (i = 0; i < 4; ++i)
            {
                OS_OpenCreate(&sfd[i], "/mnt/sel.txt", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            }
            /* Four consecutive stream ids; print the indices so the byte/bit split is visible. */
            printf("sel_add   rc=%d %d %d %d\n", (int)OS_SelectFdAdd(&rset, sfd[0]),
                   (int)OS_SelectFdAdd(&rset, sfd[1]), (int)OS_SelectFdAdd(&rset, sfd[2]),
                   (int)OS_SelectFdAdd(&rset, sfd[3]));
            printf("sel_bytes %u %u %u\n", (unsigned)rset.object_ids[0],
                   (unsigned)rset.object_ids[1], (unsigned)rset.object_ids[2]);
            printf("sel_isset %d %d %d %d\n", (int)OS_SelectFdIsSet(&rset, sfd[0]),
                   (int)OS_SelectFdIsSet(&rset, sfd[1]), (int)OS_SelectFdIsSet(&rset, sfd[2]),
                   (int)OS_SelectFdIsSet(&rset, sfd[3]));
            printf("sel_clear rc=%d then %d %d\n", (int)OS_SelectFdClear(&rset, sfd[1]),
                   (int)OS_SelectFdIsSet(&rset, sfd[1]), (int)OS_SelectFdIsSet(&rset, sfd[2]));
            printf("sel_bytes2 %u %u %u\n", (unsigned)rset.object_ids[0],
                   (unsigned)rset.object_ids[1], (unsigned)rset.object_ids[2]);
            printf("sel_nullset %d\n", (int)OS_SelectFdIsSet(NULL, sfd[0]));
            printf("sel_badid rc=%d isset=%d\n",
                   (int)OS_SelectFdAdd(&rset, OS_ObjectIdFromInteger(0x66009999)),
                   (int)OS_SelectFdIsSet(&rset, OS_ObjectIdFromInteger(0x66009999)));

            flags = OS_STREAM_STATE_WRITABLE;
            printf("sel_single rc=%d in=%lu out=%lu n=%d\n",
                   (int)OS_SelectSingle(sfd[0], &flags, 250), (unsigned long)stub_sel_flags_in,
                   (unsigned long)flags, stub_sel_singles);
            printf("sel_snull rc=%d\n", (int)OS_SelectSingle(sfd[0], NULL, 250));
            printf("sel_sbad  rc=%d n=%d\n",
                   (int)OS_SelectSingle(OS_ObjectIdFromInteger(0x66009999), &flags, 250),
                   stub_sel_singles);
            /* SelectMultiple takes NO refcount and does not check its sets -- both NULL is
             * valid and must still reach the backend. */
            printf("sel_multi rc=%d n=%d\n", (int)OS_SelectMultiple(&rset, NULL, 100),
                   stub_sel_multiples);
            printf("sel_mnull rc=%d n=%d\n", (int)OS_SelectMultiple(NULL, NULL, 100),
                   stub_sel_multiples);
            for (i = 0; i < 4; ++i)
            {
                OS_close(sfd[i]);
            }
        }

        /* --- osapi-module.c ---------------------------------------------------------------
         * OSAL_CONFIG_INCLUDE_STATIC_LOADER is not set here, so the static symbol table
         * pointer is NULL, both `while (StaticSym != NULL)` loops never run, and the two
         * helpers return their INITIAL values. Those initialisers are the whole observable
         * behaviour of static lookup in this configuration, so the transcript pins them
         * directly rather than inferring them.
         */
        {
            osal_id_t        mid, mid2;
            OS_module_prop_t minfo;
            cpuaddr          addr;

            OS_ModuleAPI_Init();
            printf("m_init    rc=%d\n", (int)OS_ModuleAPI_Init());
            /* The two static helpers, called directly. */
            addr = 0;
            printf("m_stsym   rc=%d\n", (int)OS_SymbolLookup_Static(&addr, "any", NULL));
            printf("m_stload  rc=%d\n", (int)OS_ModuleLoad_Static("any"));

            printf("m_nullid  rc=%d\n", (int)OS_ModuleLoad(NULL, "m1", "/mnt/m1.o", 0));
            printf("m_nullnm  rc=%d\n", (int)OS_ModuleLoad(&mid, NULL, "/mnt/m1.o", 0));
            /* A bad FILENAME is only enforced after the static lookup misses -- and the object
             * has already been allocated by then, so the id is consumed either way. */
            printf("m_badfile rc=%d loads=%d\n", (int)OS_ModuleLoad(&mid, "mbad", "relative", 0),
                   stub_m_loads);
            printf("m_load    rc=%d loads=%d [%s]\n",
                   (int)OS_ModuleLoad(&mid, "m1", "/mnt/m1.o", 0x55), stub_m_loads,
                   stub_m_lastpath);
            printf("m_info    rc=%d [%s] [%s] ep=%lu valid=%lu n=%d\n",
                   (int)OS_ModuleInfo(mid, &minfo), minfo.name, minfo.filename,
                   (unsigned long)minfo.entry_point, (unsigned long)minfo.addr.valid,
                   stub_m_infos);
            printf("m_nullinfo rc=%d\n", (int)OS_ModuleInfo(mid, NULL));

            /* Symbol lookup: the backend's error survives, because the static table never
             * succeeds and NASA only overwrites on success. */
            addr = 0;
            printf("m_sym_ok  rc=%d addr=%lu n=%d\n", (int)OS_SymbolLookup(&addr, "known"),
                   (unsigned long)addr, stub_m_syms);
            printf("m_sym_no  rc=%d n=%d\n", (int)OS_SymbolLookup(&addr, "missing"), stub_m_syms);
            stub_m_sym_rc = OS_ERROR;
            printf("m_sym_err rc=%d\n", (int)OS_SymbolLookup(&addr, "missing"));
            stub_m_sym_rc = OS_ERR_NOT_IMPLEMENTED;
            printf("m_sym_nulla rc=%d\n", (int)OS_SymbolLookup(NULL, "x"));
            printf("m_sym_nulln rc=%d\n", (int)OS_SymbolLookup(&addr, NULL));
            printf("m_modsym  rc=%d n=%d\n", (int)OS_ModuleSymbolLookup(mid, &addr, "s"),
                   stub_m_modsyms);
            printf("m_modsymbad rc=%d\n",
                   (int)OS_ModuleSymbolLookup(OS_ObjectIdFromInteger(0x0A009999), &addr, "s"));

            printf("m_dump    rc=%d [%s] limit=%ld n=%d\n",
                   (int)OS_SymbolTableDump("/mnt/syms.txt", 4096), stub_m_lastpath,
                   (long)stub_m_dumplimit, stub_m_dumps);
            printf("m_dumpbad rc=%d n=%d\n", (int)OS_SymbolTableDump("relative", 4096),
                   stub_m_dumps);

            /* A DYNAMIC module calls the backend on unload; a static one would not. */
            printf("m_unload  rc=%d n=%d\n", (int)OS_ModuleUnload(mid), stub_m_unloads);
            printf("m_unload2 rc=%d\n", (int)OS_ModuleUnload(mid));
            (void)mid2;
        }

    }
    return 0;
}
