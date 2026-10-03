/* Differential-oracle driver for NASA cFE's CCSDS primary header accessors.
 *
 * Links the UNMODIFIED vendor/cFE/modules/msg/fsw/src/cfe_msg_ccsdspri.c and prints a transcript
 * of every accessor. The HolyC translation prints the same transcript, and the two must match
 * byte for byte -- which is the only way to tell a translation bug from a compiler bug, since
 * both look identical from the outside. */
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "cfe_msg.h"
#include "cfe_fs.h"
/* Module-private: the global, the two lock helpers and the two byte swappers. Not on the public
 * include path, and included rather than redeclared because the struct's LAYOUT is part of what
 * this transcript compares. */
#include "cfe_fs_priv.h"
/* CFE_FS_EarlyInit and CFE_FS_RunBackgroundFileDump are ES-facing, not app-facing: they live in
 * core_private/cfe_fs_core_internal.h rather than cfe_fs.h. */
#include "cfe_fs_core_internal.h"
#include "cfe_sb.h"
#include "target_objtab.h"
#include "cfe_sbr.h"
#include "cfe_config.h"
#include "cfe_config_priv.h"
#include "cfe_config_ids.h"
#include "cfe_config_eds.h" /* module-private; declares CFE_Config_EdsState */
#include "cfe_config_init.h"      /* module-private; the init helpers */
#include "cfe_config_core_internal.h"
#include <stdarg.h>
#include "cfe_ta_task.h"
#include "cfe_evs_task.h"
#include "cfe_es_resetdata_typedef.h" /* CFE_ES_ResetData_t, for the simulated reset area */
#include "cfe_evs_dispatch.h"
#include "cfe_evs_core_internal.h" /* CFE_EVS_SetTypeEnable, CFE_EVS_EarlyInit, CFE_EVS_CleanUpApp */
#include "cfe_time_utils.h"     /* CFE_TIME_Global_t and the module's internal declarations */
#include "cfe_sb_priv.h"       /* CFE_SB_Global_t, the buffer descriptor and the pipe */
#include "cfe_sb_core_internal.h" /* CFE_SB_EarlyInit, which core_private declares */
#include "cfe_sb_dispatch.h"  /* CFE_SB_ProcessCmdPipePkt; the module's own private header */
#include "cfe_es_generic_pool.h" /* the pool record, descriptor and bucket; ES module-private */
#include "cfe_es_crc.h"          /* CFE_ES_ComputeCRC_GetParams and the algorithm typedef */
/* ES's module-private headers, in dependency order -- cfe_es_global.h does not include the
 * types it embeds, because cFE relies on cfe_es_module_all.h having pulled them in first. The
 * same ordering constraint check_padding.py's HDRS list records. */
#include "cfe_es_erlog_typedef.h"
#include "cfe_es_apps.h"
#include "cfe_es_appctrl.h"
#include "cfe_es_mempool.h"
#include "cfe_es_cds.h"
#include "cfe_es_perf.h"
#include "cfe_es_log.h"
#include "cfe_es_global.h"
#include "cfe_es_resource.h"  /* the four record tables' accessors and locators */
#include "cfe_sb_eventids.h"   /* the event ids the subscribe counters switch on */
#include "cfe_evs_msgids.h"   /* CFE_EVS_CMD_MID, CFE_EVS_SEND_HK_MID */
/* cfe_evs_dispatch.c's two local functions: NASA declares them at the top of that .c, not in a
 * header, so the driver repeats the declarations to reach them. */
void CFE_EVS_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr, CFE_SB_MsgId_t MsgId);
bool CFE_EVS_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength);
#include "cfe_evs_utils.h"
#include "cfe_evs_log.h"
#include "cfe_ta_msgids.h"
#include "cfe_ta_fcncodes.h"
#include "cfe_perfids.h"
#include "cfe_ta_dispatch.h"

#include "cfe_resourceid.h"
#include "cfe_resourceid_basevalue.h"

/* cfe_msg_objtab.c defines this and no header declares it -- the generated cfe_es_objtab.c is
 * what normally refers to it, by name, from the build system. */
extern const Target_ObjectTable_t CFE_MSG_ModuleEntry;
extern const Target_ObjectTable_t CFE_RESOURCEID_ModuleEntry;
extern const Target_ObjectTable_t CFE_FS_ModuleEntry;
extern const Target_ObjectTable_t CFE_EVS_ModuleEntry;
extern const Target_ObjectTable_t CFE_CONFIG_ModuleEntry;
extern const Target_ObjectTable_t CFE_TA_ModuleEntry;
extern const Target_ObjectTable_t CFE_TIME_ModuleEntry;
/* module-private, declared in no header on the include path */
extern CFE_TA_CpuTaskAffinity_t CFE_TA_CpuTaskAffinity[OS_MAX_TASKS];
int32 CFE_TA_TaskInit(void);
int32 CFE_TA_NoopCmd(const CFE_TA_NoopCmd_t *data);
int32 CFE_TA_ResetCountersCmd(const CFE_TA_ResetCountersCmd_t *data);
int32 CFE_TA_ReportHousekeepingCmd(const CFE_TA_SendHkCmd_t *data);
int32 CFE_TA_QueryAllTasksCmd(const CFE_TA_QueryAllTasksCmd_t *data);
void  CFE_TA_Cpu_Set(const uint8 *AffinityMask, OS_cpuset_t *cpuset);
int32 CFE_TA_SetTaskAffinityCmd(const CFE_TA_SetTaskAffinityCmd_t *data);
int32 CFE_TA_GetTaskAffinityCmd(const CFE_TA_GetTaskAffinityCmd_t *data);
int32 CFE_TA_SetStartupAffinity(const char *taskname);
int32 CFE_TA_OS_EventHandler(OS_Event_t event, osal_id_t object_id, void *data);
bool  CFE_TA_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength);
void  CFE_TA_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr, CFE_SB_MsgId_t MsgId);

/* Private to the SB module (declared in modules/sb/fsw/src/cfe_sb_priv.h, which is not on the
 * include path here and would drag in the rest of SB). Declared rather than included, because
 * the point is to link the one real function, not to pull a module we have not translated. */
size_t CFE_SB_MsgHdrSize(const CFE_MSG_Message_t *MsgPtr);

/* cfe_sb_util.c logs through ES on its failure paths. ES is not translated, so both sides get
 * the same stub: it records THAT a path logged, not what it said. The HolyC translation takes a
 * plain string rather than a format -- see Kernel/Cfs/cfe/cfe_sb_util.HC for why -- so the
 * wording is deliberately outside the comparison. */
/* CFE_ES_WriteToSysLog: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* Check functions for CFE_ResourceId_FindNext. "In use" is serial 6 or 7, chosen so the search
 * has to step over two occupied slots and land on the third -- a single occupied slot would
 * pass even if the do-while ran once instead of looping. */
static bool rid_in_use(CFE_ResourceId_t id)
{
    uint32 serial = CFE_ResourceId_GetSerial(id);
    return (serial == 6 || serial == 7);
}

static bool rid_all_in_use(CFE_ResourceId_t id)
{
    (void)id;
    return true;
}

/* Decimal only, one byte per field, space separated. Formatting is the one thing that would
 * differ between C's printf and HolyC for reasons that have nothing to do with the translation
 * being right, so it is removed from the comparison entirely. */
/* The one PSP symbol cfe_sb_msg_id_util.c's translation unit pulls in. The PSP is the layer a
 * port supplies, and the HolyC side has none either, so stubbing it here keeps both sides
 * comparing the same thing. None of the functions under test calls it. */
uint32 CFE_PSP_GetProcessorId(void)
{
    return 1;
}

/* cfe_msg_integrity.c calls into the TIME module, which is not translated yet. Both sides get
 * the same fixed clock, so the comparison stays about the message code. Nothing under test
 * depends on what the clock says -- only on the call happening at all. */

/* Counts entries CFE_Config_IterateAll visits. */
static int cfg_visits;
static void cfg_count_cb(void *Arg, CFE_ConfigId_t Id, const char *Name)
{
    (void)Arg;
    (void)Id;
    (void)Name;
    cfg_visits++;
}

/* Counts how many route ids ForEachRouteId hands back. */
static int sbr_visits;
static void sbr_count_cb(CFE_SBR_RouteId_t RouteId, void *ArgPtr)
{
    (void)RouteId;
    (void)ArgPtr;
    sbr_visits++;
}

extern const Target_ObjectTable_t CFE_SBR_ModuleEntry;
extern const Target_ObjectTable_t CFE_SB_ModuleEntry;

/* THE GENERIC POOL'S STORAGE AND ITS ACCESSORS. cfe_es_generic_pool.c never dereferences the
 * pool -- it addresses everything by OFFSET and goes through these two function pointers, so
 * that a pool can live somewhere that is not memory-mapped (a CDS in battery-backed RAM is the
 * case NASA has in mind). For an ordinary memory-mapped pool Retrieve just adds the offset to a
 * base and Commit does nothing, which is what cfe_es_mempool.c's Direct pair does and what
 * these reproduce. They live in the DRIVER rather than the translation because mempool.c is not
 * gated yet.
 *
 * 2048 bytes is chosen to make the pool-full path reachable: the largest bucket below is 256,
 * so a handful of allocations exhausts it. */
static unsigned char es_pool_mem[2048];

static int32 es_pool_retrieve(CFE_ES_GenPoolRecord_t *PoolRecPtr, size_t Offset,
                              CFE_ES_GenPoolBD_t **BdPtr)
{
    (void)PoolRecPtr;
    *BdPtr = (CFE_ES_GenPoolBD_t *)&es_pool_mem[Offset];
    return CFE_SUCCESS;
}

static int32 es_pool_commit(CFE_ES_GenPoolRecord_t *PoolRecPtr, size_t Offset,
                            const CFE_ES_GenPoolBD_t *BdPtr)
{
    (void)PoolRecPtr; (void)Offset; (void)BdPtr;
    return CFE_SUCCESS;
}

/* "123456789" -- the CRC-16/ARC check value for this exact input is 0xBB3D, stated in NASA's
 * comment on the CFE_ES_CrcType_16_ARC enumerator. Using the documented vector means the
 * transcript agreeing is evidence about the ALGORITHM and not just about two copies of a
 * table. */
static const unsigned char CRC_PROBE[] = "123456789";

/* A message LONGER THAN HALF THE LOG, for the truncation and wrap paths. 4100 bytes: the
 * per-message cap is CFE_PLATFORM_ES_SYSTEM_LOG_SIZE/2 = 4096, so this is just over it and
 * exercises the cap rather than merely approaching it. At file scope because the guest's stack
 * is not the place for it. */
static char es_big_msg[4101];

/* Non-static in cfe_es_generic_pool.c and declared in no header -- the same arrangement as
 * CFE_SBR_MsgIdHash above. They are declared here because the INVERTED BUCKET ID is the part of
 * this module most worth pinning: FindBucket returns NumBuckets - Index so that a valid bucket
 * is nonzero, every other function undoes it with the same subtraction, and an off-by-one there
 * would hand out blocks from the wrong bucket while every counter still agreed with itself. */
uint16                  CFE_ES_GenPoolFindBucket(CFE_ES_GenPoolRecord_t *PoolRecPtr, size_t ReqSize);
CFE_ES_GenPoolBucket_t *CFE_ES_GenPoolGetBucketState(CFE_ES_GenPoolRecord_t *PoolRecPtr,
                                                     uint16 BucketId);
/* ...and the two CRC algorithms, for the same reason: cfe_es_crc.h declares only GetParams, so
 * the algorithms can be reached only THROUGH the table unless they are declared. Both are
 * called directly below, so that the 0xBB3D check value is compared against the algorithm
 * itself and not only against whatever the table happens to point at. */
uint32 CFE_ES_ComputeCRC_Algo_NONE(const void *DataPtr, size_t DataLength, uint32 InputCRC);
uint32 CFE_ES_ComputeCRC_Algo_16_ARC(const void *DataPtr, size_t DataLength, uint32 InputCRC);
/* Non-static in cfe_es_mempool.c and declared in no header -- the third such case in this file,
 * after CFE_SBR_MsgIdHash and the generic pool's bucket helpers. It is wanted here because the
 * three tests it makes are the only check that a pool's BASE ADDRESS is real memory, which is
 * the one thing the pool cannot verify for itself. */
bool CFE_ES_ValidateHandle(CFE_ES_MemHandle_t Handle);

/* Non-static in cfe_sbr_map_hash.c but declared in no header at all -- not even the module's own
 * cfe_sbr_priv.h, which declares only Init_Map and SetRouteId. Declared here because the hash is
 * the part of this module most worth pinning: it is pure 32-bit overflow arithmetic. */
CFE_SB_MsgId_Atom_t CFE_SBR_MsgIdHash(CFE_SB_MsgId_t MsgId);

/* Also non-static and declared in no header anywhere -- the second such function found while
 * translating (see docs/CFS_UPSTREAM_NOTES.md). Its sibling CFE_Config_GetVersionString, which
 * is its only in-tree caller, is properly declared in cfe_config.h. */
void CFE_Config_GetMissionRevString(char *Buf, size_t Size, uint8 MissionRev, const char *LastOffcRel);


/* =========================== cFE fs module ======================================================
 * A SIMULATED FILE, identical on both sides of the oracle.
 *
 * fs is the first translated module that calls OSAL, and OSAL has a gate of its own (423
 * transcript lines, its own stub backend). Linking the two together here would make this
 * transcript depend on both at once and stop telling us which one moved. So both sides get the
 * same tiny in-memory file instead, and this gate stays about fs.
 *
 * The injection flags exist because three of the five Meta->OnEvent call sites are error paths.
 * A file that always succeeds would leave the function-pointer-member call -- the compiler
 * feature this module needed -- exercised on two sites out of five by the transcript that is
 * supposed to validate it. So the driver drives one create failure, one short header write and
 * one short record write. */
/* 4096, not 256. At 256 the simulated file could not hold even one CFE_TA_DiagInfo_t (2052
 * bytes), so QueryAllTasksCmd's SUCCESS branch -- and with it the one event that formats a
 * filename, an entry count and a file size together -- was unreachable, and the only thing the
 * transcript ever saw from that command was its short-write error. Same for the EVS log dump,
 * twenty event packets. The size is part of the comparison: the HolyC half declares the same
 * number, and fs_len appears in the transcript. */
static unsigned char fs_data[4096];
static long          fs_len;           /* bytes written so far */
static long          fs_pos;           /* current position */
static unsigned int  fs_fd;            /* 0 is OS_OBJECT_ID_UNDEFINED */
static int           fs_open_fail;     /* make OS_OpenCreate fail */
/* fs_wr_left is the number of bytes the file will still accept, not a per-call cap. A per-call
 * cap of 64 looked like it would make a record write fail and did not: the header write is 64
 * and every record is 10, so each individual write still fit and the run reported COMPLETE. */
static long          fs_wr_left;       /* < 0 = unlimited */
static int           fs_mut_create, fs_mut_take, fs_mut_give, fs_wakeups;
/* Steer the three mutex calls. Without these, cfe_fs_priv.c's three syslog lines are
 * unreachable -- including the only one in the whole translation that formats three
 * arguments (a status, an app id and a function name), which is exactly the kind of line a
 * restored argument list can be wrong in without anything noticing. */
static int           fs_mut_create_rc, fs_mut_take_rc, fs_mut_give_rc;

int32 OS_OpenCreate(osal_id_t *filedes, const char *path, int32 flags, int32 access_mode)
{
    (void)path; (void)flags; (void)access_mode;
    if (fs_open_fail)
    {
        return OS_ERROR;
    }
    fs_fd    = 7;
    *filedes = 7;
    fs_len   = 0;
    fs_pos   = 0;
    return OS_SUCCESS;
}

int32 OS_close(osal_id_t filedes)
{
    (void)filedes;
    fs_fd = 0;
    return OS_SUCCESS;
}

int32 OS_read(osal_id_t filedes, void *buffer, size_t nbytes)
{
    long n = (long)nbytes;
    (void)filedes;
    if (n > fs_len - fs_pos)
    {
        n = fs_len - fs_pos;
    }
    if (n < 0)
    {
        n = 0;
    }
    memcpy(buffer, &fs_data[fs_pos], (size_t)n);
    fs_pos += n;
    return (int32)n;
}

int32 OS_write(osal_id_t filedes, const void *buffer, size_t nbytes)
{
    long n = (long)nbytes;
    (void)filedes;
    if (fs_wr_left >= 0)
    {
        if (n > fs_wr_left)
        {
            n = fs_wr_left;
        }
        fs_wr_left -= n;
    }
    if (fs_pos + n > (long)sizeof(fs_data))
    {
        n = (long)sizeof(fs_data) - fs_pos;
    }
    memcpy(&fs_data[fs_pos], buffer, (size_t)n);
    fs_pos += n;
    if (fs_pos > fs_len)
    {
        fs_len = fs_pos;
    }
    return (int32)n;
}

int32 OS_lseek(osal_id_t filedes, osal_offset_t offset, uint32 whence)
{
    (void)filedes; (void)whence;
    fs_pos = offset;
    return (int32)offset;
}

/* ES's shared-data lock, counted. See the note beside the removed stub pair further down: the
 * real CFE_ES_LockSharedData takes CFE_ES_Global.SharedDataMutex, so the witness for "how many
 * times did ES lock" has to live here, in the mutex stub, and has to tell ES's mutex apart from
 * the FS and pool mutexes that come through the same stub. */
#define ES_SHARED_MUTEX_ID 0x1E5
static long es_lock_takes, es_lock_gives;

int32 OS_MutSemCreate(osal_id_t *sem_id, const char *sem_name, uint32 options)
{
    (void)sem_name; (void)options;
    ++fs_mut_create;
    *sem_id = 3;
    return fs_mut_create_rc;
}

int32 OS_MutSemTake(osal_id_t sem_id)
{
    if (sem_id == ES_SHARED_MUTEX_ID)
    {
        ++es_lock_takes;
    }
    ++fs_mut_take;
    return fs_mut_take_rc;
}

int32 OS_MutSemGive(osal_id_t sem_id)
{
    if (sem_id == ES_SHARED_MUTEX_ID)
    {
        ++es_lock_gives;
    }
    ++fs_mut_give;
    return fs_mut_give_rc;
}

/* Who the caller is USED TO BE THIS VARIABLE. cfe_es_api.c is gated, so CFE_ES_GetAppID is
 * real and answers from the ES tables -- see es_set_ctx and es_ctx_init below, which is where
 * the three paths through CFE_EVS_SendEvent (a registered app, an unregistered one, an id out
 * of range) are selected now. */

/* CFE_ES_GetAppID: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
void CFE_ES_BackgroundWakeup(void)
{
    ++fs_wakeups;
}

uint32 CFE_PSP_GetSpacecraftId(void)
{
    return 0x5A5A;
}

/* The requester's two callbacks. Three records of ten bytes, with record 1 deliberately EMPTY --
 * NASA's loop keeps going on a zero-size record, for holes in a table, and a getter that never
 * returns 0 would not exercise that. */
static unsigned char fs_rec[16];
static int           fs_events;

static bool fs_getdata(void *Meta, uint32 RecordNum, void **Buffer, size_t *BufSize)
{
    int i;
    (void)Meta;
    for (i = 0; i < 10; i++)
    {
        fs_rec[i] = (unsigned char)(0xA0 + RecordNum * 16 + i);
    }
    *Buffer  = fs_rec;
    *BufSize = (RecordNum == 1) ? 0 : 10;
    return RecordNum >= 3;
}

static void fs_onevent(void *Meta, CFE_FS_FileWriteEvent_t Event, int32 Status, uint32 RecordNum,
                       size_t BlockSize, size_t Position)
{
    (void)Meta;
    ++fs_events;
    printf("fs_event ev=%d st=%ld rec=%lu blk=%lu pos=%lu\n", (int)Event, (long)Status,
           (unsigned long)RecordNum, (unsigned long)BlockSize, (unsigned long)Position);
}


/* =========================== cFE ta module =====================================================
 * A SIMULATED OS AND BUS, identical on both sides.
 *
 * TA is the first translated module that is an APP: a task, a command pipe, a housekeeping
 * packet, and 17 event messages. SB, EVS and ES are not translated, so both sides get the same
 * recording stubs; the affinity side is a small table this driver controls, so the three-way
 * loop bound in CFE_TA_Cpu_Set and every branch of the two affinity commands can be driven.
 *
 * BOTH SPLITS ARE GONE. CFE_EVS_SendEvent and CFE_ES_WriteToSysLog each used to take a plain
 * string here, with the event id and the branch compared and the wording left out. EVS is
 * translated now and StrPrintNV formats, so both pass NASA's own arguments and the text they
 * produce is inside the byte-identical comparison. */
static int      ta_evs_count;
static int      ta_perf_depth;
static int      ta_evs_register_rc, ta_msginit_rc;
static int      ta_cores;            /* what OS_TaskAffinityCoresConfigured reports */
static int      ta_getid_rc, ta_setaff_rc, ta_getaff_rc;
static unsigned char ta_os_mask;     /* the one byte the simulated OS stores per task */

/* CFE_EVS_Register and CFE_EVS_SendEvent are NOT stubbed any more: cfe_evs.c is in the gate's
 * source list, so ta's events go through the real thing -- registration, filtering, the squelch
 * token bucket, the local log, the formatter and the two output ports. The `evs eid=N type=N`
 * lines this driver used to print are gone, and what replaces them is EVS_OutputPort's real
 * text through OS_printf. ta_evs_register_rc kept its meaning by moving: it is now what the
 * EVS app data says, not what a stub returns. */

void  CFE_ES_PerfLogAdd(uint32 Marker, uint32 EntryExit) { (void)Marker; (void)EntryExit; }
/* CFE_ES_ExitApp: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_ES_WaitForSystemState: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* --- the reset area, for CFE_EVS_EarlyInit ---------------------------------------------------
 * EVS's early init asks the PSP for the reset area, checks its SIZE against the whole of
 * CFE_ES_ResetData_t and panics if it is short, then takes the event log out of it. So the driver
 * supplies a real one, and the three things EarlyInit can be told are all steerable: the PSP
 * call's status, the size it reports, and the reset type. */
static CFE_ES_ResetData_t evs_reset_area;
static long               evs_resetarea_rc;   /* what CFE_PSP_GetResetArea returns */
static long               evs_resetarea_size; /* what it reports, 0 = the real sizeof */
static long               evs_reset_type;     /* what CFE_ES_GetResetType answers */
static long               evs_panics, evs_delay_ms;

int32 CFE_PSP_GetResetArea(cpuaddr *PtrToResetArea, uint32 *SizeOfResetArea)
{
    *PtrToResetArea = (cpuaddr)&evs_reset_area;
    if (evs_resetarea_size)
    {
        *SizeOfResetArea = (uint32)evs_resetarea_size;
    }
    else
    {
        *SizeOfResetArea = (uint32)sizeof(CFE_ES_ResetData_t);
    }
    return (int32)evs_resetarea_rc;
}

/* CFE_ES_GetResetType: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* NASA's CFE_PSP_Panic does not return; this one does, because EarlyInit's code AFTER the panic
 * is part of what the transcript compares -- it falls through to `return Status`. */
void CFE_PSP_Panic(int32 ErrorCode)
{
    ++evs_panics;
    printf("psp_panic %ld\n", (long)ErrorCode);
}

int32 OS_TaskDelay(uint32 millisecond)
{
    evs_delay_ms += millisecond;
    return OS_SUCCESS;
}

/* CFE_TIME_Tone1HzISR used to be stubbed here, because cfe_time_tone.c was not gated and
 * CFE_TIME_ExternalTone's whole body is a call to it. It is gated now, so the REAL one runs --
 * and the stub had to go on both sides at once, which is the shape every one of these removals
 * has had: the stub is what the gate was measuring until the translation arrived. */

/* NASA defines CFE_TIME_Global in cfe_time_task.c, which is not gated, so the driver supplies it
 * -- the same arrangement this file had for CFE_EVS_Global until cfe_evs_task.c landed. The
 * HolyC half does NOT need this: it defines the object in cfe_time_global.HC beside its type,
 * because HolyC has no usable forward declaration for a variable and three files use it before
 * cfe_time_task.HC would appear. One definition on each side either way. */
CFE_TIME_Global_t CFE_TIME_Global;
/* CFE_ES_IncrementTaskCounter: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* The simulated OS's semaphores, child tasks and timebase, for CFE_TIME_TaskInit. Every value
 * TaskInit branches on is a variable here, so the gate can walk the failure paths as well as the
 * happy one -- TaskInit has five of them and each returns a different status.
 *
 * time_sem_take_budget is a BUDGET, not a constant, and that is the whole reason the two 1Hz
 * child tasks are drivable at all: CFE_TIME_Tone1HzTask and CFE_TIME_Local1HzTask are
 * `while (true)` loops that exit only when OS_BinSemTake fails, so NASA's own loop termination
 * is what ends them. A stub that always succeeded would hang the oracle. */
static long  time_sems_created, time_sem_gives, time_sem_takes, time_childtasks;
static long  time_tb_lookups, time_timer_adds, time_timer_sets, time_synch_calls;
/* NOT initialised here, on purpose. OS_SUCCESS and CFE_SUCCESS are 0 so zero-initialisation
 * would do for five of these, but time_tb_rc has to start at OS_ERROR -- and the HolyC half's
 * globals are zero and nothing else. Both halves assign all six at the top of the block below,
 * so the two agree by construction instead of by a reader noticing the asymmetry. */
static int32 time_binsem_rc, time_childtask_rc;
static int32 time_tb_rc, time_timeradd_rc, time_timerset_rc;
static int   time_sem_take_budget;

int32 OS_BinSemCreate(osal_id_t *sem_id, const char *sem_name, uint32 sem_initial_value,
                      uint32 options)
{
    (void)sem_name; (void)sem_initial_value; (void)options;
    ++time_sems_created;
    *sem_id = 0x3330 + time_sems_created;
    return time_binsem_rc;
}

int32 OS_BinSemGive(osal_id_t sem_id)
{
    (void)sem_id;
    ++time_sem_gives;
    return OS_SUCCESS;
}

int32 OS_BinSemTake(osal_id_t sem_id)
{
    (void)sem_id;
    ++time_sem_takes;
    if (time_sem_take_budget <= 0)
    {
        return OS_ERROR;
    }
    --time_sem_take_budget;
    return OS_SUCCESS;
}

/* CFE_ES_CreateChildTask: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_SB_SubscribeLocal was stubbed here. It is real now (cfe_sb_api.c), and TIME is the only
 * caller -- CFE_TIME_SubscribeLocal wraps it for the four non-ground message ids. time_sub_local
 * counted the calls; SB counts the successful ones in StatTlmMsg.Payload.SubscriptionsInUse,
 * which is what the transcript reports instead. A LOCAL subscribe raises no subscription report,
 * which is what the transcript reports. */

/* Defaults to FAILING, which is NASA's documented expectation and not a shortcut: the comment on
 * CFE_TIME_TaskInit_Setup1HzTimer says a PSP that did not set up a timebase returns
 * OS_ERR_NAME_NOT_FOUND and the lookup failure is deliberately NOT reported. The gate drives
 * both answers. */
int32 OS_TimeBaseGetIdByName(osal_id_t *timebase_id, const char *timebase_name)
{
    (void)timebase_name;
    ++time_tb_lookups;
    *timebase_id = 0x5551;
    return time_tb_rc;
}

int32 OS_TimerAdd(osal_id_t *timer_id, const char *timer_name, osal_id_t timebase_id,
                  OS_ArgCallback_t callback_ptr, void *callback_arg)
{
    (void)timer_name; (void)timebase_id; (void)callback_ptr; (void)callback_arg;
    ++time_timer_adds;
    *timer_id = 0x6661;
    return time_timeradd_rc;
}

int32 OS_TimerSet(osal_id_t timer_id, uint32 start_time, uint32 interval_time)
{
    (void)timer_id; (void)start_time; (void)interval_time;
    ++time_timer_sets;
    return time_timerset_rc;
}

/* ES's STATE, 57,400 bytes. NASA defines CFE_ES_Global in cfe_es_api.c, which is not gated
 * yet, so the driver supplies it; the HolyC half defines it in cfe_es_global.HC beside its
 * type, for the reason recorded there. It is zero-initialised and ResetDataPtr is aimed at the
 * reset area below, which is what makes the system log writable: the log buffer and its three
 * indices live in memory that survives a processor reset, not in CFE_ES_Global itself. */
CFE_ES_Global_t CFE_ES_Global;
static CFE_ES_ResetData_t es_reset_area;

/* cfe_es_api.c and cfe_es_task.c are not gated, so three of their functions are stubs on BOTH
 * halves -- the same temporary arrangement CFE_SB_SendSubscriptionReport had until
 * cfe_sb_task.c landed, and it goes away the same way.
 *
 * The lock pair is a COUNTER rather than a no-op on purpose: the syslog's whole design is about
 * which reads happen inside it (the first block) and which deliberately do not (every block
 * after), and a transcript that cannot see the difference could not tell a correct dump from
 * one that held the lock for the entire file. */
static long es_bytecnt_errs;

/* THE LOCK PAIR IS REAL NOW: cfe_es_api.c is gated, and CFE_ES_LockSharedData takes
 * OS_MutSemTake(CFE_ES_Global.SharedDataMutex) for real. The counters above did not go away
 * with the stub -- they MOVED into the mutex stub, which bumps them only for ES's own mutex id.
 * That keeps the syslog-dump probe measuring the thing it was written to measure (exactly one
 * take/give pair however many blocks get written) and now measures it through NASA's code
 * instead of through a stub that could not get it wrong.
 *
 * ES_SHARED_MUTEX_ID is the id the startup sequence plants in CFE_ES_Global.SharedDataMutex. It
 * has to be distinct from the FS and pool mutexes, which share the same stub, or the counters
 * would pick up their traffic too. */
void CFE_ES_FileWriteByteCntErr(const char *Filename, size_t Requested, int32 Status)
{
    ++es_bytecnt_errs;
    printf("es_bytecnterr %s req=%lu stat=%ld\n", Filename, (unsigned long)Requested, (long)Status);
}

/* ---- what cfe_es_api.c calls and nothing gated defines ---------------------------------------
 * cfe_es_cds.c, cfe_es_cds_mempool.c, cfe_es_apps.c and cfe_es_erlog.c are all untranslated, so
 * fourteen of their functions are stubs here and in the HolyC half, written to match. This is
 * the arrangement CFE_SB_SendSubscriptionReport had until cfe_sb_task.c landed, and it comes
 * apart the same way: each stub disappears from BOTH halves on the commit that gates its source.
 *
 * CFE_ES_Global.CDSIsAvailable IS ZERO in this driver and stays that way, which is why the CDS
 * stubs can be this thin: CFE_ES_RegisterCDS, CFE_ES_GetCDSBlockIDByName and
 * CFE_ES_GetCDSBlockName all return CFE_ES_NOT_IMPLEMENTED before they reach the registry, and
 * the exercise checks that they do. */
static long  es_erlog_writes, es_cds_locks, es_cds_unlocks, es_starttasks, es_restarts;
static long  es_stats;
static int32 es_stat_rc       = OS_SUCCESS; /* what OS_stat says: Restart/Reload branch on it */
static int32 es_starttask_rc  = CFE_SUCCESS;
static long  es_taskdeletes, es_taskexits;
static int32 es_taskdelete_rc = OS_SUCCESS;

int32 CFE_ES_WriteToERLog(CFE_ES_LogEntryType_Enum_t EntryType, uint32 ResetType,
                          uint32 ResetSubtype, const char *Description)
{
    ++es_erlog_writes;
    printf("es_erlog type=%u rt=%lu rst=%lu %s\n", (unsigned)EntryType, (unsigned long)ResetType,
           (unsigned long)ResetSubtype, Description);
    return CFE_SUCCESS;
}

/* NASA's CFE_PSP_Restart does not return. This one does, because the code AFTER it in
 * CFE_ES_ResetCFE is part of what the transcript compares -- the "CFE_PSP_Restart returned"
 * syslog line and the CFE_ES_NOT_IMPLEMENTED that follows exist for exactly this case. */
void CFE_PSP_Restart(uint32 ResetType)
{
    ++es_restarts;
    printf("psp_restart %lu\n", (unsigned long)ResetType);
}

int32 OS_stat(const char *path, os_fstat_t *filestats)
{
    (void)filestats;
    ++es_stats;
    printf("os_stat %s rc=%ld\n", path, (long)es_stat_rc);
    return es_stat_rc;
}

int32 OS_TaskDelete(osal_id_t task_id)
{
    ++es_taskdeletes;
    printf("os_taskdelete %lu rc=%ld\n", (unsigned long)OS_ObjectIdToInteger(task_id),
           (long)es_taskdelete_rc);
    return es_taskdelete_rc;
}

/* NASA's OS_TaskExit does not return either, and the same reasoning applies: CFE_ES_ExitApp and
 * CFE_ES_ExitChildTask both have a `return` after it with NASA's own comment saying the code is
 * reached "except under unit test". This driver IS that case. */
void OS_TaskExit(void)
{
    ++es_taskexits;
    printf("os_taskexit\n");
}

/* THE DRIVER'S OSAL IDS ARE BARE 1-BASED INTEGERS, so index = id - 1 and osal id 1 lands on
 * table slot 0 -- which is the convention the resource-table probe already assumed when it
 * marked TaskTable[0] used for CFE_ES_TaskId_FromOSAL(1). The real OSAL strips type bits and
 * takes a modulus; that belongs to the OSAL translation and its own gate, not to this one. */
int32 OS_ObjectIdToArrayIndex(osal_objtype_t idtype, osal_id_t object_id, osal_index_t *ArrayIndex)
{
    unsigned long id = OS_ObjectIdToInteger(object_id);
    (void)idtype;
    if (id == 0 || id > OS_MAX_TASKS)
    {
        return OS_ERROR;
    }
    *ArrayIndex = (osal_index_t)(id - 1);
    return OS_SUCCESS;
}

/* THIS ONE IS NOT A THIN STUB AND COULD NOT BE. CFE_ES_RestartApp, ReloadApp and DeleteApp do
 * nothing except set a control request, and all three reach it through this function, which
 * decides whether the id is usable AND writes the "not valid" log line itself. A stub that
 * always succeeded would be more permissive than the real thing in the way this driver has been
 * bitten by twice (the SBR sentinel, the bare pipe id), and a stub that always failed would
 * make the three success paths unreachable.
 *
 * So NASA's own body from cfe_es_apps.c is reproduced here, on both halves, byte for byte in
 * behaviour. It is NOT the gate's translation of it -- when cfe_es_apps.c is gated this goes
 * away from both halves and the real one takes over, and the transcript must not move. */
CFE_ES_AppRecord_t *CFE_ES_LockUserAppRecord(CFE_ES_AppId_t AppID, const char *LogMsgAction)
{
    CFE_ES_AppRecord_t *AppRecPtr;
    bool                IsValid;

    IsValid   = false;
    AppRecPtr = CFE_ES_LocateAppRecordByID(AppID);
    CFE_ES_LockSharedData(__func__, __LINE__);
    if (!CFE_ES_AppRecordIsMatch(AppRecPtr, AppID))
    {
        CFE_ES_WriteToSysLog("%s: Invalid Application ID received for %s, AppID = %lu\n", __func__,
                             LogMsgAction, CFE_RESOURCEID_TO_ULONG(AppID));
    }
    else if (AppRecPtr->Type == CFE_ES_AppType_CORE)
    {
        CFE_ES_SysLogWrite_Unsync("%s: Cannot %s a CORE Application: %s.\n", __func__, LogMsgAction,
                                  CFE_ES_AppRecordGetName(AppRecPtr));
    }
    else if (AppRecPtr->AppState != CFE_ES_AppState_RUNNING)
    {
        CFE_ES_SysLogWrite_Unsync("%s: Cannot %s Application %s, It is not running.\n", __func__,
                                  LogMsgAction, CFE_ES_AppRecordGetName(AppRecPtr));
    }
    else
    {
        IsValid = true;
    }

    if (!IsValid)
    {
        CFE_ES_UnlockSharedData(__func__, __LINE__);
        AppRecPtr = NULL;
    }

    return AppRecPtr;
}

/* MORE PERMISSIVE THAN THE REAL THING, AND SAID SO HERE. NASA's CFE_ES_StartAppTask allocates a
 * task RECORD, fills in its start params and registers it; this hands back an id and nothing
 * else. So CFE_ES_CreateChildTask's success path is reachable, but the id it returns does not
 * resolve: CFE_ES_DeleteChildTask on it takes the "Task ID is not active" branch. The exercise
 * drives that deliberately rather than pretending otherwise. */
int32 CFE_ES_StartAppTask(CFE_ES_TaskId_t *TaskIdPtr, const char *TaskName,
                          CFE_ES_TaskEntryFuncPtr_t EntryFunc,
                          const CFE_ES_TaskStartParams_t *Params,
                          CFE_ES_AppId_t ParentAppId)
{
    (void)EntryFunc;
    ++es_starttasks;
    printf("es_starttask %s prio=%u stack=%lu app=%lu rc=%ld\n", TaskName,
           (unsigned)Params->Priority, (unsigned long)Params->StackSize,
           CFE_RESOURCEID_TO_ULONG(ParentAppId), (long)es_starttask_rc);
    *TaskIdPtr = CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(0x7770 + es_starttasks));
    return es_starttask_rc;
}

/* THE CDS GROUP. CDSIsAvailable is 0, so the three public entry points never reach these --
 * which is itself worth asserting, and the exercise does. They record, so a path that DID reach
 * one would show up in the transcript rather than passing silently. */
void CFE_ES_FormCDSName(char *FullCDSName, const char *CDSName, CFE_ES_AppId_t ThisAppId)
{
    (void)ThisAppId;
    printf("es_formcdsname %s\n", CDSName);
    strncpy(FullCDSName, CDSName, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
    FullCDSName[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1] = 0;
}

CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByID(CFE_ES_CDSHandle_t BlockID)
{
    (void)BlockID;
    printf("es_locatecds_byid\n");
    return NULL;
}

CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByName(const char *CDSName)
{
    printf("es_locatecds_byname %s\n", CDSName);
    return NULL;
}

int32 CFE_ES_RegisterCDSEx(CFE_ES_CDSHandle_t *HandlePtr, size_t UserBlockSize, const char *Name,
                           bool CriticalTbl)
{
    (void)HandlePtr;
    printf("es_registercdsex %s size=%lu crit=%d\n", Name, (unsigned long)UserBlockSize,
           (int)CriticalTbl);
    return CFE_ES_NOT_IMPLEMENTED;
}

int32 CFE_ES_LockCDS(void)
{
    ++es_cds_locks;
    return CFE_SUCCESS;
}

int32 CFE_ES_UnlockCDS(void)
{
    ++es_cds_unlocks;
    return CFE_SUCCESS;
}

int32 CFE_ES_CDSBlockWrite(CFE_ES_CDSHandle_t Handle, const void *DataToWrite)
{
    (void)DataToWrite;
    printf("es_cdswrite h=%lu\n", CFE_RESOURCEID_TO_ULONG(Handle));
    return CFE_ES_NOT_IMPLEMENTED;
}

int32 CFE_ES_CDSBlockRead(void *DataRead, CFE_ES_CDSHandle_t Handle)
{
    (void)DataRead;
    printf("es_cdsread h=%lu\n", CFE_RESOURCEID_TO_ULONG(Handle));
    return CFE_ES_NOT_IMPLEMENTED;
}

/* THE THREE MODULE-INFO COPIERS. CFE_ES_GetAppInfo and CFE_ES_GetLibInfo call them to fill the
 * parts of CFE_ES_AppInfo_t that describe the loaded object file -- name, entry point, address
 * ranges. These record and fill nothing, so the exercise asserts on the fields ES itself writes
 * (type, name, task counts, stack, priority) and NOT on the module fields, which stay zero from
 * the memset at the top of both callers. When cfe_es_apps.c is gated the fields start arriving
 * and the exercise grows to cover them. */
void CFE_ES_CopyModuleBasicInfo(const CFE_ES_ModuleLoadParams_t *ParamsPtr,
                                CFE_ES_AppInfo_t *AppInfoPtr)
{
    (void)AppInfoPtr;
    printf("es_copybasic %s\n", ParamsPtr->FileName);
}

void CFE_ES_CopyModuleStatusInfo(const CFE_ES_ModuleLoadStatus_t *StatusPtr,
                                 CFE_ES_AppInfo_t *AppInfoPtr)
{
    (void)AppInfoPtr;
    printf("es_copystatus mod=%lu\n", (unsigned long)OS_ObjectIdToInteger(StatusPtr->ModuleId));
}

void CFE_ES_CopyModuleAddressInfo(osal_id_t ModuleId, CFE_ES_AppInfo_t *AppInfoPtr)
{
    (void)AppInfoPtr;
    printf("es_copyaddr mod=%lu\n", (unsigned long)OS_ObjectIdToInteger(ModuleId));
}

/* NASA defines CFE_SB_Global in cfe_sb_task.c, which is not gated, so the driver supplies it --
 * the same arrangement this file has for CFE_TIME_Global and had for CFE_EVS_Global. The HolyC
 * half defines it in cfe_sb_global.HC beside its type, for the reason recorded there. */
CFE_SB_Global_t CFE_SB_Global;

/* SB's PIPE QUEUES, simulated. One queue of one entry per pipe is enough for the transaction
 * machinery: what cfe_sb_priv.c does is decide WHICH pipes to write to and how to undo the
 * accounting when a write fails, so the queue only has to be able to succeed, be full, and be
 * empty on demand. */
#define SBQ_MAX 32
static struct
{
    unsigned char Data[64];
    size_t        Size;
    bool          Full;
    bool          Created;
    char          Name[32];
} sbq[SBQ_MAX];
static long  sb_qputs, sb_qgets;
static int32 sb_queueput_rc = OS_SUCCESS; /* set to OS_QUEUE_FULL to force the undo path */
static int32 sb_queueget_rc = OS_SUCCESS;

/* CREATE, DELETE AND LOOKUP, and these three are why CFE_SB_CreatePipe no longer needs a stub.
 * The pipe table, the name check and the "reserved" slot in cfe_sb_api.c are all real now; what
 * is simulated is only the OS queue underneath them.
 *
 * sb_queuecreate_rc IS THE FAULT INJECTOR THAT ta_pipe_rc USED TO BE, and it is a better one.
 * The stub returned whatever number the test asked for; this returns an OSAL error and lets
 * CFE_SB_CreatePipe decide, so the transcript now shows CFE_SB_PIPE_CR_ERR (0xca000005) coming
 * out of NASA's own translation of OS_ERROR -- and the three DIFFERENT events it raises for
 * OS_ERR_NAME_TAKEN, OS_ERR_NO_FREE_IDS and everything else became reachable at the same time. */
static long  sb_qcreates, sb_qdeletes;
static int32 sb_queuecreate_rc = OS_SUCCESS;
static int   sb_next_qid       = 1; /* 0 is OS_OBJECT_ID_UNDEFINED, so ids start at 1 */

int32 OS_QueueCreate(osal_id_t *queue_id, const char *queue_name, size_t queue_depth,
                     size_t data_size, uint32 flags)
{
    int i;
    (void)queue_depth; (void)data_size; (void)flags;
    ++sb_qcreates;
    if (sb_queuecreate_rc != OS_SUCCESS)
    {
        return sb_queuecreate_rc;
    }
    /* the name check NASA's OSAL does, because CFE_SB_CreatePipe has a distinct event for it */
    for (i = 1; i < sb_next_qid && i < SBQ_MAX; i++)
    {
        if (sbq[i].Created && strcmp(sbq[i].Name, queue_name) == 0)
        {
            return OS_ERR_NAME_TAKEN;
        }
    }
    if (sb_next_qid >= SBQ_MAX)
    {
        return OS_ERR_NO_FREE_IDS;
    }
    i = sb_next_qid++;
    sbq[i].Created = true;
    sbq[i].Full    = false;
    snprintf(sbq[i].Name, sizeof(sbq[i].Name), "%s", queue_name);
    *queue_id = (osal_id_t)i;
    return OS_SUCCESS;
}

int32 OS_QueueDelete(osal_id_t queue_id)
{
    unsigned long i = (unsigned long)queue_id;
    ++sb_qdeletes;
    if (i >= SBQ_MAX || !sbq[i].Created)
    {
        return OS_ERR_INVALID_ID;
    }
    /* The id is NOT returned to the pool: a reused id would make a stale pipe descriptor look
     * valid, which is the one thing a queue simulation must not do to a lifetime test. */
    sbq[i].Created = false;
    sbq[i].Full    = false;
    sbq[i].Name[0] = 0;
    return OS_SUCCESS;
}

/* RESETTING THE BUS IS NOT ENOUGH TO RESET THE QUEUES. CFE_SB_EarlyInit clears CFE_SB_Global,
 * but the OS queue NAMES live in OSAL, not in SB -- so a second CFE_SB_AppInit after an
 * EarlyInit came back CFE_SB_PIPE_CR_ERR with OS_ERR_NAME_TAKEN, because SB_CMD_PIPE was still
 * registered from the first one. That is correct behaviour on both sides and it made the
 * exercise below meaningless, so this is the analogue of restarting OSAL too. */
static void sbq_reset(void)
{
    memset(sbq, 0, sizeof(sbq));
    sb_next_qid = 1;
}

int32 OS_QueueGetIdByName(osal_id_t *queue_id, const char *queue_name)
{
    int i;
    for (i = 1; i < sb_next_qid && i < SBQ_MAX; i++)
    {
        if (sbq[i].Created && strcmp(sbq[i].Name, queue_name) == 0)
        {
            *queue_id = (osal_id_t)i;
            return OS_SUCCESS;
        }
    }
    return OS_ERR_NAME_NOT_FOUND;
}

int32 OS_QueuePut(osal_id_t queue_id, const void *data, size_t size, uint32 timeout)
{
    unsigned long i = (unsigned long)queue_id;
    (void)timeout;
    ++sb_qputs;
    if (sb_queueput_rc != OS_SUCCESS)
    {
        return sb_queueput_rc;
    }
    if (i >= SBQ_MAX || size > sizeof(sbq[0].Data))
    {
        return OS_ERROR;
    }
    memcpy(sbq[i].Data, data, size);
    sbq[i].Size = size;
    sbq[i].Full = true;
    return OS_SUCCESS;
}

int32 OS_QueueGet(osal_id_t queue_id, void *data, size_t size, size_t *size_copied, int32 timeout)
{
    unsigned long i = (unsigned long)queue_id;
    (void)timeout;
    ++sb_qgets;
    if (sb_queueget_rc != OS_SUCCESS)
    {
        *size_copied = 0;
        return sb_queueget_rc;
    }
    if (i >= SBQ_MAX || !sbq[i].Full)
    {
        *size_copied = 0;
        return OS_QUEUE_EMPTY;
    }
    memcpy(data, sbq[i].Data, sbq[i].Size);
    *size_copied = sbq[i].Size;
    sbq[i].Full  = false;
    return OS_SUCCESS;
}

/* ES's task identity. One task, one app, and the names differ so CFE_SB_GetAppTskName takes its
 * "app.task" branch rather than the "they are the same" one. */
static long  sb_taskinfo_calls;
static int32 sb_taskinfo_rc = CFE_SUCCESS;

/* CFE_ES_GetTaskID: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_ES_TaskID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* THE OTHER TWO INDEX CONVERSIONS, and all four of them are STUBS MORE PERMISSIVE THAN THE REAL
 * THING -- which is a debt this file has paid before. The real CFE_ES_LibID_ToIndex and
 * CFE_ES_CounterID_ToIndex (cfe_es_api.c, not gated yet) subtract CFE_ES_LIBID_BASE and
 * CFE_ES_COUNTID_BASE; these take a small id AS the index, exactly the way the AppID stub
 * above does. When api.c lands, every site here that passes a bare 1 or 2 stops resolving --
 * the same break CFE_SB_PipeId_ToIndex caused when IT stopped being `id & 0xFF`, and the
 * reason the probes below use properly based ids where they can.
 *
 * CFE_ES_TaskID_ToIndex above is the most permissive of the four: it returns index 0 for ANY
 * id. The real one goes through OS_ObjectIdToArrayIndex. */
/* CFE_ES_LibID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_ES_CounterID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* The running task's OSAL id. CFE_ES_GetTaskRecordByContext XORs it into an ES task id, so the
 * value here decides which ES task record "the calling task" resolves to. A fixed 1 means the
 * context lookups land on table slot... whatever CFE_ES_TaskID_ToIndex says, which today is 0
 * for everything. */
static uint32 es_os_taskid = 1;

osal_id_t OS_TaskGetId(void)
{
    return es_os_taskid;
}

/* ---- THE DRIVER'S ES CONTEXT -----------------------------------------------------------------
 * "Who is calling" USED TO BE A VARIABLE and is now two table entries. While cfe_es_api.c was
 * stubbed, CFE_ES_GetAppID returned `ta_getappid` and a test changed the caller by assigning to
 * it. The real one walks OS_TaskGetId -> task record -> its AppId -> app record, so the caller
 * is whatever the ES tables say, and es_set_ctx is what moves it.
 *
 * THE IDS ARE PROPERLY BASED, which is the break this file predicted twice in writing. The old
 * *_ToIndex stubs took a bare 1 or 2 AS the index; the real CFE_ES_AppID_ToIndex subtracts
 * CFE_ES_APPID_BASE first, so every id here is BASE + slot and `1` is simply out of range.
 * Exactly what CFE_SB_PipeId_ToIndex did when it stopped being `id & 0xFF`.
 *
 * App slot 1 is "CFE_EVS" and slot 2 is "OTHER_APP" -- the same two names the removed
 * CFE_ES_GetAppIDByName stub answered for, so the EVS probes keep asking what they asked
 * before and now get the answer out of NASA's own name lookup. */
#define ES_CTX_APPID(slot) CFE_ResourceId_FromInteger(CFE_ES_APPID_BASE + (slot))
#define ES_LIBID(slot)     CFE_ResourceId_FromInteger(CFE_ES_LIBID_BASE + (slot))
#define ES_CTRID(slot)     CFE_ResourceId_FromInteger(CFE_ES_COUNTID_BASE + (slot))
#define ES_CTX_TASK_SLOT   0 /* osal id es_os_taskid == 1 maps to task table index 0 */

static void es_app_slot(uint32 slot, const char *name, CFE_ES_AppType_Enum_t type,
                        CFE_ES_AppState_Enum_t state)
{
    CFE_ES_AppRecord_t *arp = &CFE_ES_Global.AppTable[slot];

    memset(arp, 0, sizeof(*arp));
    CFE_ES_AppRecordSetUsed(arp, ES_CTX_APPID(slot));
    strncpy(arp->AppName, name, sizeof(arp->AppName) - 1);
    arp->Type       = type;
    arp->AppState   = state;
    arp->MainTaskId = CFE_ES_TaskId_FromOSAL(OS_ObjectIdFromInteger(es_os_taskid));
    arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
    strncpy(arp->StartParams.BasicInfo.FileName, "/cf/es_app.so",
            sizeof(arp->StartParams.BasicInfo.FileName) - 1);
}

/* The CALLING app. Only the task record's AppId moves, so the app records themselves stay
 * exactly as the startup sequence left them -- a test that changes the caller is not also
 * silently changing that app's name, type or state. */
static void es_set_ctx(uint32 slot)
{
    CFE_ES_TaskRecord_t *trp = &CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT];

    trp->AppId = CFE_ES_APPID_C(ES_CTX_APPID(slot));
}

static void es_ctx_init(void)
{
    CFE_ES_TaskRecord_t *trp = &CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT];

    es_app_slot(1, "CFE_EVS", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
    es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);

    memset(trp, 0, sizeof(*trp));
    CFE_ES_TaskRecordSetUsed(trp, CFE_ES_TaskId_FromOSAL(OS_ObjectIdFromInteger(es_os_taskid)));
    strncpy(trp->TaskName, "SBTESTTASK", sizeof(trp->TaskName) - 1);
    trp->StartParams.StackSize = 4096;
    trp->StartParams.Priority  = 55;
    CFE_ES_Global.RegisteredTasks = 1;
    CFE_ES_Global.RegisteredExternalApps = 2;
    es_set_ctx(1);
}

/* CFE_ES_GetTaskInfo: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_SB_PipeId_ToIndex, CFE_SB_DeletePipeWithAppId and CFE_SB_GetPipeName were stubbed here
 * while cfe_sb_api.c was untranslated. All three are real now. Removing the PipeId_ToIndex stub
 * is a change of behaviour on BOTH sides at once -- it was
 * `CFE_ResourceId_ToInteger(...) & 0xFF` and the real one goes through CFE_ResourceId_ToIndex
 * against CFE_SB_PIPEID_BASE -- and nothing here computes a pipe index by hand, so the two
 * halves move together.
 *
 * CFE_SB_SendSubscriptionReport is a NEW stub, not a leftover: it lives in cfe_sb_task.c, which
 * is not gated yet, and CFE_SB_SubscribeFull calls it on every successful GLOBAL subscribe. It
 * also does the counting ta_subscribes used to do, which is why the counter below is not a
 * second variable. */
/* CFE_SB_SendSubscriptionReport WAS stubbed here, and the previous commit's note said it would
 * stop being one when cfe_sb_task.c landed. It has. The stub counted calls; the real one does
 * nothing at all unless SubscriptionReporting is enabled, so there is no call count worth
 * reporting -- both prints below use SB's own SubscriptionsInUse instead, and the
 * enable/disable pair is exercised directly in the task section. */
static uint32 sb_api_idx;

/* THE SIMULATED MEMORY POOL IS GONE. CFE_ES_PoolCreateEx, CFE_ES_GetPoolBuf and
 * CFE_ES_PutPoolBuf were a hand-written bump allocator here -- an 8-byte size header per block,
 * a cursor that never rewound, and a comment explaining why a success stub would have proved
 * nothing. cfe_es_mempool.c and cfe_es_generic_pool.c are gated now, so every allocation in the
 * transcript goes through NASA's real pool: real buckets, a real free stack that recycles, real
 * check patterns, and the resource-id table in CFE_ES_Global.
 *
 * sb_getpool_rc WENT WITH IT, and that needed a replacement rather than a deletion: it was the
 * fault injector for every "allocation failed" path in TA, EVS, TIME and SB. es_pool_exhaust()
 * below is the real thing -- it moves the pool's TailPosition to its end, so the next
 * CFE_ES_GenPoolCreatePoolBlock finds no room and returns CFE_ES_ERR_MEM_BLOCK_SIZE from NASA's
 * own code. A pool with no free stack and no room is exactly what a full pool is.
 *
 * Two OSAL/PSP calls are still stubs. OS_MutSemCreate is ALREADY stubbed above, for FS, and the
 * pool's mutex uses that one -- one stub per OSAL call in this file, so a second definition
 * would be a link error rather than a second opinion, which is how that was found. */
static long es_mutsem_deletes;
static long es_psp_validates;
static int32 es_psp_validate_rc = CFE_PSP_SUCCESS;

int32 OS_MutSemDelete(osal_id_t sem_id)
{
    (void)sem_id;
    ++es_mutsem_deletes;
    return OS_SUCCESS;
}

int32 CFE_PSP_MemValidateRange(cpuaddr Address, size_t Size, uint32 MemoryType)
{
    (void)Address; (void)Size; (void)MemoryType;
    ++es_psp_validates;
    return es_psp_validate_rc;
}

/* AND DO NOT USE IT TO FAIL SB'S POOL CREATE. CFE_SB_InitBuffers' failure message prints
 * `gave adr 0x%lx` -- the partition's address -- so that line cannot be compared across a host
 * process and a QEMU guest. It is out of the transcript because the pool SUCCEEDS, not because
 * it is unreachable: exhausting SB's pool before EarlyInit is the obvious next use of this
 * helper, and it would resurrect a diff of 0x102e21bd8 against 0x808BB948. Same rule as
 * CFE_SB_CreatePipe's argument-check branch.
 *
 * Fill a pool so the next allocation cannot fit, and put it back. White-box on purpose: there
 * is no API for "make the next GetPoolBuf fail", and a 512 KiB pool cannot be exhausted a
 * block at a time inside a transcript. */
static size_t es_pool_saved_tail;

/* BOTH ARE NULL-SAFE, and that is not defensive padding: several of the sites that used to set
 * sb_getpool_rc back to CFE_SUCCESS run BEFORE SB's EarlyInit, where there is no pool and the
 * handle resolves to nothing. The old stub ignored its handle entirely so those lines were
 * no-ops; with the real pool they are lookups that can fail, and doing nothing is the correct
 * answer rather than a crash. */
static void es_pool_exhaust(CFE_ES_MemHandle_t Handle)
{
    CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(Handle);
    if (r != NULL && r->Pool.TailPosition != r->Pool.PoolMaxOffset)
    {
        /* The TailPosition test makes a second exhaust a no-op. There are ten call sites and
         * es_pool_saved_tail is ONE variable: without it, exhaust-exhaust-restore saves
         * PoolMaxOffset as the "real" tail and leaves the pool permanently full. Proving the
         * crash earlier in this session had a different cause did not make this safe. */
        es_pool_saved_tail   = r->Pool.TailPosition;
        r->Pool.TailPosition = r->Pool.PoolMaxOffset;
    }
}

static void es_pool_restore(CFE_ES_MemHandle_t Handle)
{
    CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(Handle);
    if (r != NULL)
    {
        r->Pool.TailPosition = es_pool_saved_tail;
    }
}

/* THE THREE COUNTERS THE TRANSCRIPT USED TO PRINT, now read out of NASA'S OWN POOL instead of
 * out of my stub's locals. That is the point of this change: AllocationCount is the pool's
 * record of every block it has ever handed out, and the per-bucket ReleaseCount is its record
 * of every one given back -- the same numbers CFE_ES_GetMemPoolStats reports to the ground.
 *
 * es_pool_puts sums ReleaseCount across the buckets because there is no aggregate: a free is
 * recorded against the bucket the block came from, which is also how NumFree is derived
 * (ReleaseCount - RecycleCount). */
static long es_pool_creates(void)
{
    return CFE_ES_ValidateHandle(CFE_SB_Global.Mem.PoolHdl) ? 1 : 0;
}

static long es_pool_gets(void)
{
    CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(CFE_SB_Global.Mem.PoolHdl);
    return (r == NULL) ? 0 : (long)r->Pool.AllocationCount;
}

static long es_pool_puts(void)
{
    CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(CFE_SB_Global.Mem.PoolHdl);
    long                    n = 0;
    uint16                  i;
    if (r != NULL)
    {
        for (i = 0; i < r->Pool.NumBuckets; ++i)
        {
            n += r->Pool.Buckets[i].ReleaseCount;
        }
    }
    return n;
}

/* A registered 1Hz synchronisation callback. CFE_TIME_NotifyTimeSynchApps walks the registry and
 * calls through a function POINTER, which is the one thing in TIME that cannot be checked by
 * reading a counter afterwards unless the callback itself bumps one. */
int32 TimeSynchProbe(void)
{
    ++time_synch_calls;
    return CFE_SUCCESS;
}

/* CFE_SB_CreatePipe, CFE_SB_Subscribe, CFE_SB_ReceiveBuffer and CFE_SB_TransmitMsg were the four
 * stubs every other module in this file was driven through: config, fs, ta, evs and time all
 * reach the bus by one of them. They are gone. Those paths now run SB's real argument checking,
 * real pipe table, real route lookup and real transaction machinery, on both sides.
 *
 * WHAT THE THREE COUNTERS BECAME, because each had to move to something the real code does:
 *   ta_pipe_created -> sb_qcreates, counted in the simulated OS_QueueCreate.
 *   ta_subscribes   -> SB's own StatTlmMsg.Payload.SubscriptionsInUse.
 *   ta_transmits    -> the delta in CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter, which
 *                      is SB's own count of a message sent to a message id nobody subscribed
 *                      to. Every housekeeping packet in this driver is exactly that, so the
 *                      number is the same one the stub reported -- but it is now SB's. */
/* sb_tx_reset() BEFORE EVERY sb_tx_since() IS MANDATORY. The difference is unsigned, so a
 * sb_tx_since() with no preceding reset reports a large positive number rather than an
 * obviously-wrong zero. */
static uint32 sb_tx_mark;

static void sb_tx_reset(void) { sb_tx_mark = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter; }

static int sb_tx_since(void)
{
    return (int)(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - sb_tx_mark);
}

/* The simulated OS's task table: one name, one id, one stored affinity byte. Everything the two
 * affinity commands branch on is a variable here. */
int32 OS_TaskGetIdByName(osal_id_t *task_id, const char *task_name)
{
    (void)task_name;
    *task_id = 0x2222;
    return ta_getid_rc;
}

int32 OS_TaskAffinitySetAffinity(osal_id_t task_id, OS_cpuset_t cpuset)
{
    (void)task_id;
    if (ta_setaff_rc == OS_SUCCESS)
    {
        ta_os_mask = cpuset.affinity_mask[0];
    }
    return ta_setaff_rc;
}

int32 OS_TaskAffinityGetAffinity(osal_id_t task_id, OS_cpuset_t *cpuset)
{
    (void)task_id;
    OS_CPUSET_ZERO(cpuset);
    cpuset->affinity_mask[0] = ta_os_mask;
    return ta_getaff_rc;
}

uint32 OS_TaskAffinityCoresConfigured(void) { return (uint32)ta_cores; }

int32 OS_RegisterEventHandler(OS_EventHandler_t handler) { (void)handler; return OS_SUCCESS; }

int32 OS_GetResourceName(osal_id_t object_id, char *buffer, size_t buffer_size)
{
    (void)object_id;
    strncpy(buffer, "STARTUP_TASK", buffer_size - 1);
    return OS_SUCCESS;
}

/* One row of the live affinity table, so the branch each command took is visible as STATE and
 * not only as an event id. */
static void ta_row(const char *tag, int i)
{
    printf("%s[%d] name=[%s] mask=%02x fromos=%02x type=%d status=%d\n", tag, i,
           CFE_TA_CpuTaskAffinity[i].TaskName, CFE_TA_CpuTaskAffinity[i].CpuMask.affinity_mask[0],
           CFE_TA_CpuTaskAffinity[i].CpuFromOS.affinity_mask[0],
           (int)CFE_TA_CpuTaskAffinity[i].Type, (int)CFE_TA_CpuTaskAffinity[i].Status);
}

static void ta_counters(const char *tag)
{
    printf("%s cc=%u cec=%u sc=%u sec=%u evs=%d\n", tag, CFE_TA_Global.CommandCounter,
           CFE_TA_Global.CommandErrorCounter, CFE_TA_Global.StartupCounter,
           CFE_TA_Global.StartupErrorCounter, ta_evs_count);
}

/* ---- what EVS needs from the layers it sits on ------------------------------------------- */
/* CFE_EVS_Global lives in cfe_evs_task.c, the one EVS source not translated yet, so the C side
 * defines it here. The HolyC side has it in cfe_evs_global.HC with the other declarations --
 * and when cfe_evs_task.c IS translated, that definition has to move there rather than be
 * duplicated. The log storage is ES's reset area in flight; EVS only holds a pointer. */
CFE_EVS_Global_t     CFE_EVS_Global;
static CFE_EVS_Log_t evs_log_storage;

/* Every one of these is deterministic on purpose: EVS times its squelch bucket off
 * CFE_PSP_GetTime, so a real clock would make the transcript depend on how fast the host is. */
static long long evs_psp_ns;      /* what CFE_PSP_GetTime reports, in ticks (= ns here) */
static int       evs_printf_lines;

/* CFE_ES_AppID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_ES_GetAppIDByName: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* CFE_ES_GetAppName: STUB REMOVED -- cfe_es_api.c is gated, the real one runs. */
/* Lives in cfe_evs_task.c, the last of EVS's six sources and not translated yet. */

void CFE_PSP_GetTime(OS_time_t *LocalTime)
{
    LocalTime->ticks = evs_psp_ns;
}

/* CFE_TIME_GetTime and CFE_TIME_Print are no longer stubbed: cfe_time_api.c is in SRC_C, so the
 * real ones run. Both were ALREADY inside the byte-identical comparison -- every
 * "1980-001-00:00:44.52768" in the transcript is a timestamp CFE_TIME_Print rendered -- the stub
 * just happened to agree with itself on both sides. Now the C half calls glibc's gmtime_r and
 * strftime and the HolyC half calls the calendar conversion written in cfe_time_api.HC, and the
 * transcript is what says whether they agree. */

void OS_printf(const char *String, ...)
{
    va_list ap;
    ++evs_printf_lines;
    va_start(ap, String);
    vprintf(String, ap);
    va_end(ap);
}

/* ---- cfe_config_init.c helpers ------------------------------------------------------------- */
/* Two module lists and a key/value list, so FindTargetKeyValue, IsModuleInList, IsPspModule and
 * FindStaticModName are exercised on data this driver controls rather than only on the generated
 * target config. The NULL terminators are what the walks stop on. */
static CFE_ConfigName_t ci_core[3] = {{"CFE_ES"}, {"CFE_SB"}, {NULL}};
static CFE_ConfigName_t ci_apps[2] = {{"ci_lab"}, {NULL}};
static CFE_StaticModuleLoadEntry_t ci_psp[3] = {{"soft_timebase", NULL}, {"eeprom_direct", NULL},
                                                {NULL, NULL}};
static CFE_ConfigKeyValue_t ci_kv[4] = {{"CFE_ES", "1.2.3"}, {"ci_lab", "4.5.6"},
                                        {"SOFT_TIMEBASE", "7.8.9"}, {NULL, NULL}};

static void ci_str(const char *tag, const char *s)
{
    printf("%s [%s]\n", tag, s == NULL ? "(null)" : s);
}

/* The file's bytes, so the big-endian conversion in WriteHeader is in the transcript rather than
 * merely implied by a return value. */
static void fs_dump(const char *tag, long n)
{
    long i;
    printf("%s", tag);
    for (i = 0; i < n; i++)
    {
        printf(" %02x", fs_data[i]);
    }
    printf("\n");
}

static void fs_hdr(const char *tag, const CFE_FS_Header_t *h)
{
    printf("%s ct=%08lx sub=%lu len=%lu sc=%lu pr=%lu app=%lu ts=%08lx tss=%08lx d=[%s]\n", tag,
           (unsigned long)h->ContentType, (unsigned long)h->SubType, (unsigned long)h->Length,
           (unsigned long)h->SpacecraftID, (unsigned long)h->ProcessorID,
           (unsigned long)h->ApplicationID, (unsigned long)h->TimeSeconds,
           (unsigned long)h->TimeSubSeconds, h->Description);
}

static void fs_parse(const char *tag, char *out, int32 rc)
{
    printf("%s rc=%ld [%s]\n", tag, (long)rc, out);
}

static void dump(const char *tag, CFE_MSG_Message_t *m)
{
    printf("%s %d %d %d %d %d %d\n", tag, m->CCSDS.Pri.StreamId[0], m->CCSDS.Pri.StreamId[1],
           m->CCSDS.Pri.Sequence[0], m->CCSDS.Pri.Sequence[1], m->CCSDS.Pri.Length[0],
           m->CCSDS.Pri.Length[1]);
}

int main(void)
{
    CFE_MSG_Message_t msg;
    CFE_MSG_HeaderVersion_t ver;
    CFE_MSG_Type_t type;
    CFE_MSG_ApId_t apid;
    CFE_MSG_SegmentationFlag_t seg;
    CFE_MSG_SequenceCount_t seq;
    CFE_MSG_Size_t size;
    bool hassec;
    int i;

    /* THE BUS HAS TO EXIST BEFORE ANYTHING SUBSCRIBES TO IT, and before cfe_sb_api.c was gated
     * it did not have to: CFE_SB_CreatePipe and CFE_SB_Subscribe were stubs that answered
     * without reading CFE_SB_Global. They are real now, and CFE_SB_Global is a zeroed global --
     * LastPipeId of 0 is not a valid resource id, so CFE_ResourceId_FindNext walks off the
     * table and the very first CFE_TA_TaskInit came back CFE_SB_MAX_PIPES_MET with 64 pipes
     * free. CFE_SB_EarlyInit is what sets LastPipeId to CFE_SB_PIPEID_BASE - 1 and stands up
     * the memory pool the destination blocks come from. cFE's own startup calls it first too;
     * the SB section below calls it again, deliberately, to exercise it. */
    /* ES'S RESET AREA HAS TO BE AIMED BEFORE ANYTHING CAN LOG, and that became load-bearing
     * the moment cfe_es_mempool.c was gated: the real pool calls CFE_ES_WriteToSysLog on every
     * failure path, the syslog writes into CFE_ES_Global.ResetDataPtr->SystemLog, and a NULL
     * there is a dereference of 0 rather than a dropped message. cFE does this in
     * CFE_ES_SetupResetVariables during startup; the syslog section below re-clears it. */
    memset(&es_reset_area, 0, sizeof(es_reset_area));
    CFE_ES_Global.ResetDataPtr                = &es_reset_area;
    CFE_ES_Global.ResetDataPtr->SystemLogMode = CFE_ES_LogMode_DISCARD;

    /* AND THE POOL-ID SPACE HAS TO BE OPENED, for the same reason and with the same symptom as
     * SB's LastPipeId: CFE_ES_Global is zeroed, 0 is not a valid resource id, so
     * CFE_ResourceId_FindNext walks off the table and CFE_ES_PoolCreateEx reports "no free
     * MemPool slots" with all ten free. cfe_es_start.c:178 does exactly this line. The symptom
     * was CFE_SB_GetBufferFromPool returning NULL and the driver dereferencing it -- a hundred
     * lines after SB's EarlyInit had quietly failed. */
    CFE_ES_Global.LastMemPoolId = CFE_ResourceId_FromInteger(CFE_ES_POOLID_BASE);

    /* AND ES'S OWN TABLES, because cfe_es_api.c is gated and "who is calling" now comes out of
     * them rather than out of a stub. The mutex id goes in first: the real
     * CFE_ES_LockSharedData takes CFE_ES_Global.SharedDataMutex, and the id is what lets the
     * OS_MutSemTake stub count ES's locks apart from the FS and pool ones. */
    CFE_ES_Global.SharedDataMutex = OS_ObjectIdFromInteger(ES_SHARED_MUTEX_ID);
    es_ctx_init();

    /* AND EVS'S LOG POINTER, for the same reason the reset area had to be aimed above: with a
     * real CFE_ES_GetAppID the caller is now a REGISTERED app, so events raised by the fs, ta
     * and sb sections actually reach EVS_AddLog instead of being refused for an out-of-range
     * app id -- and EVS_AddLog dereferences CFE_EVS_Global.EVS_LogPtr with no NULL check.
     * CFE_EVS_EarlyInit is what does this in cFE; the EVS section below calls it again and
     * re-points it at the same storage. */
    memset(&evs_log_storage, 0, sizeof(evs_log_storage));
    CFE_EVS_Global.EVS_LogPtr = &evs_log_storage;
    CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_EVS_LogMode_OVERWRITE;

    /* AND THE CONFIG SERVICE BEFORE THE BUS, which is cFE's own startup order -- ES, then
     * config, then everything else. It did not matter while CFE_ES_PoolCreateEx was a stub that
     * ignored its block-size arguments; with the real pool, CFE_SB_InitBuffers reads SB's block
     * sizes out of the config registry (CFE_CONFIGID_PLATFORM_SB_MEM_BLOCK_SIZE) and an empty
     * registry means ZERO block sizes, which CFE_ES_GenPoolInitialize correctly refuses. The
     * config section below calls it again and checks what it returns. */
    CFE_Config_Init();

    CFE_SB_EarlyInit();

    for (i = 0; i < (int)sizeof(msg); i++)
        ((unsigned char *)&msg)[i] = 0;
    dump("zero", &msg);

    printf("setver   rc=%ld\n", (long)CFE_MSG_SetHeaderVersion(&msg, 1));
    dump("afterver", &msg);
    printf("getver   rc=%ld v=%u\n", (long)CFE_MSG_GetHeaderVersion(&msg, &ver), (unsigned)ver);

    printf("settype  rc=%ld\n", (long)CFE_MSG_SetType(&msg, CFE_MSG_Type_Cmd));
    dump("aftertype", &msg);
    printf("gettype  rc=%ld t=%d\n", (long)CFE_MSG_GetType(&msg, &type), (int)type);

    printf("setapid  rc=%ld\n", (long)CFE_MSG_SetApId(&msg, 0x1AB));
    dump("afterapid", &msg);
    printf("getapid  rc=%ld a=%u\n", (long)CFE_MSG_GetApId(&msg, &apid), (unsigned)apid);

    printf("setsec   rc=%ld\n", (long)CFE_MSG_SetHasSecondaryHeader(&msg, true));
    printf("getsec   rc=%ld s=%d\n", (long)CFE_MSG_GetHasSecondaryHeader(&msg, &hassec), (int)hassec);
    dump("aftersec", &msg);

    printf("setseg   rc=%ld\n", (long)CFE_MSG_SetSegmentationFlag(&msg, CFE_MSG_SegFlag_Unsegmented));
    printf("getseg   rc=%ld g=%d\n", (long)CFE_MSG_GetSegmentationFlag(&msg, &seg), (int)seg);

    printf("setseq   rc=%ld\n", (long)CFE_MSG_SetSequenceCount(&msg, 0x2345));
    printf("getseq   rc=%ld q=%u\n", (long)CFE_MSG_GetSequenceCount(&msg, &seq), (unsigned)seq);
    dump("afterseq", &msg);

    printf("setsize  rc=%ld\n", (long)CFE_MSG_SetSize(&msg, 0x100));
    printf("getsize  rc=%ld z=%lu\n", (long)CFE_MSG_GetSize(&msg, &size), (unsigned long)size);
    dump("aftersize", &msg);

    /* Rejections matter as much as successes: a translation that accepts what the original
     * refuses is wrong in the direction that matters. */
    printf("badver   rc=%ld\n", (long)CFE_MSG_SetHeaderVersion(&msg, 0xFF));
    printf("badapid  rc=%ld\n", (long)CFE_MSG_SetApId(&msg, 0xFFFF));
    printf("badnull  rc=%ld\n", (long)CFE_MSG_GetType(NULL, &type));
    printf("badsize  rc=%ld\n", (long)CFE_MSG_SetSize(&msg, 0));
    dump("final", &msg);

    /* --- cfe_msg_msgid_v1.c, plus the SB opaque-id helpers it calls ------------------- */
    {
        CFE_SB_MsgId_t mid;
        for (i = 0; i < (int)sizeof(msg); i++)
            ((unsigned char *)&msg)[i] = 0;
        printf("setmid   rc=%ld\n", (long)CFE_MSG_SetMsgId(&msg, CFE_SB_ValueToMsgId(0x0801)));
        dump("aftermid", &msg);
        printf("getmid   rc=%ld m=%lu\n", (long)CFE_MSG_GetMsgId(&msg, &mid),
               (unsigned long)CFE_SB_MsgIdToValue(mid));
        /* Zero is CFE_SB_INVALID_MSG_ID, and above the platform bound is out of range. Both
         * must be refused, which is the behaviour that makes the opaque type worth having. */
        printf("midzero  rc=%ld\n", (long)CFE_MSG_SetMsgId(&msg, CFE_SB_ValueToMsgId(0)));
        printf("midhigh  rc=%ld\n", (long)CFE_MSG_SetMsgId(&msg, CFE_SB_ValueToMsgId(0x2000)));
        printf("midnull  rc=%ld\n", (long)CFE_MSG_GetMsgId(NULL, &mid));
        printf("midvalid v=%d z=%d h=%d\n", (int)CFE_SB_IsValidMsgId(CFE_SB_ValueToMsgId(0x1FFF)),
               (int)CFE_SB_IsValidMsgId(CFE_SB_ValueToMsgId(0)),
               (int)CFE_SB_IsValidMsgId(CFE_SB_ValueToMsgId(0x2000)));
        dump("midfinal", &msg);
    }

    /* --- cfe_msg_sechdr_fc.c ---------------------------------------------------------- */
    {
        CFE_MSG_CommandHeader_t cmd;
        CFE_MSG_FcnCode_t fc;
        for (i = 0; i < (int)sizeof(cmd); i++)
            ((unsigned char *)&cmd)[i] = 0;
        /* A function code only exists on a version-1 CCSDS command that declares a secondary
         * header. Version 1 is the bit pattern 000, so the field stays 0. */
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
        CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, true);
        printf("setfc    rc=%ld\n", (long)CFE_MSG_SetFcnCode(&cmd.Msg, 0x12));
        printf("getfc    rc=%ld f=%u\n", (long)CFE_MSG_GetFcnCode(&cmd.Msg, &fc), (unsigned)fc);
        printf("cmdhdr %d %d %d %d %d %d %d %d\n", cmd.Msg.CCSDS.Pri.StreamId[0],
               cmd.Msg.CCSDS.Pri.StreamId[1], cmd.Msg.CCSDS.Pri.Sequence[0],
               cmd.Msg.CCSDS.Pri.Sequence[1], cmd.Msg.CCSDS.Pri.Length[0],
               cmd.Msg.CCSDS.Pri.Length[1], cmd.Sec.FunctionCode, cmd.Sec.Checksum);
        printf("fcbig    rc=%ld\n", (long)CFE_MSG_SetFcnCode(&cmd.Msg, 0x80));
        /* Flip it to telemetry: the same call must now refuse, and zero the out-param. */
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Tlm);
        fc = 0x55;
        printf("fctlm    rc=%ld f=%u\n", (long)CFE_MSG_GetFcnCode(&cmd.Msg, &fc), (unsigned)fc);
        /* And a wrong CCSDS version refuses too, even as a command with a secondary header. */
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
        CFE_MSG_SetHeaderVersion(&cmd.Msg, 1);
        printf("fcver    rc=%ld\n", (long)CFE_MSG_SetFcnCode(&cmd.Msg, 0x7F));
        printf("fcnull   rc=%ld\n", (long)CFE_MSG_GetFcnCode(NULL, &fc));
    }

    /* --- header sizes ------------------------------------------------------------------
     * Not a function under test: a property. Every unit below indexes a secondary header at
     * an offset the compiler chose, so if the two languages lay these structs out differently
     * the transcripts would diverge somewhere far from the cause. Pin it here instead. */
    printf("sizes %d %d %d\n", (int)sizeof(CFE_MSG_Message_t), (int)sizeof(CFE_MSG_CommandHeader_t),
           (int)sizeof(CFE_MSG_TelemetryHeader_t));

    /* --- cfe_msg_sechdr_time.c -------------------------------------------------------- */
    {
        CFE_MSG_TelemetryHeader_t tlm;
        CFE_TIME_SysTime_t        t;
        for (i = 0; i < (int)sizeof(tlm); i++)
            ((unsigned char *)&tlm)[i] = 0;
        /* POISON THE TRAILING BYTES. The time field is Time[0..5] and Spare[] follows it, so a
         * translation that reads FOUR bytes starting at Time[4] instead of widening the one
         * byte there would run off the end -- and with zeros after it, come out right anyway.
         * That is not hypothetical: the first draft of this translation had exactly that bug,
         * the Seconds line caught it and the Subseconds line did not. Only the region after the
         * time field is poisoned; seeding the whole struct would set the CCSDS version bits and
         * SetMsgTime would refuse, changing the shape of the transcript instead of its values. */
        tlm.Spare[0] = 0xEE;
        tlm.Spare[1] = 0xEE;
        tlm.Spare[2] = 0xEE;
        tlm.Spare[3] = 0xEE;
        CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Tlm);
        CFE_MSG_SetHasSecondaryHeader(&tlm.Msg, true);
        t.Seconds    = 0x12345678;
        t.Subseconds = 0x9ABCDEF0;
        printf("settime  rc=%ld\n", (long)CFE_MSG_SetMsgTime(&tlm.Msg, t));
        printf("timebytes %d %d %d %d %d %d\n", tlm.Sec.Time[0], tlm.Sec.Time[1], tlm.Sec.Time[2],
               tlm.Sec.Time[3], tlm.Sec.Time[4], tlm.Sec.Time[5]);
        /* The round trip is lossy BY CONSTRUCTION: six header bytes hold a 32/16 split, so the
         * low 16 bits of Subseconds have nowhere to go. Reading back 0x9ABC0000, not
         * 0x9ABCDEF0, is correct behaviour and the transcript says so out loud. */
        t.Seconds    = 0;
        t.Subseconds = 0;
        printf("gettime  rc=%ld s=%lu u=%lu\n", (long)CFE_MSG_GetMsgTime(&tlm.Msg, &t),
               (unsigned long)t.Seconds, (unsigned long)t.Subseconds);
        /* On the wrong message type it must refuse AND zero the out-param. */
        CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Cmd);
        t.Seconds    = 0x11111111;
        t.Subseconds = 0x22222222;
        printf("timecmd  rc=%ld s=%lu u=%lu\n", (long)CFE_MSG_GetMsgTime(&tlm.Msg, &t),
               (unsigned long)t.Seconds, (unsigned long)t.Subseconds);
        printf("timeset2 rc=%ld\n", (long)CFE_MSG_SetMsgTime(&tlm.Msg, t));
        printf("timenull rc=%ld\n", (long)CFE_MSG_GetMsgTime(NULL, &t));
        printf("timespare %d %d %d %d\n", tlm.Spare[0], tlm.Spare[1], tlm.Spare[2], tlm.Spare[3]);
    }

    /* --- cfe_msg_sechdr_checksum.c ---------------------------------------------------- */
    {
        CFE_MSG_CommandHeader_t cmd;
        bool                    valid;
        for (i = 0; i < (int)sizeof(cmd); i++)
            ((unsigned char *)&cmd)[i] = 0;
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
        CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, true);
        CFE_MSG_SetSize(&cmd.Msg, sizeof(cmd));
        CFE_MSG_SetFcnCode(&cmd.Msg, 0x12);
        printf("gencsum  rc=%ld c=%u\n", (long)CFE_MSG_GenerateChecksum(&cmd.Msg),
               (unsigned)cmd.Sec.Checksum);
        valid = false;
        printf("valcsum  rc=%ld v=%d\n", (long)CFE_MSG_ValidateChecksum(&cmd.Msg, &valid),
               (int)valid);
        /* Corrupt one byte the checksum covered. It must now fail. A gate that only ever sees
         * the passing case would not notice a checksum that always returns "valid". */
        cmd.Sec.FunctionCode = 0x13;
        valid                = true;
        printf("badcsum  rc=%ld v=%d\n", (long)CFE_MSG_ValidateChecksum(&cmd.Msg, &valid),
               (int)valid);
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Tlm);
        printf("csumtlm  rc=%ld\n", (long)CFE_MSG_GenerateChecksum(&cmd.Msg));
        printf("csumnull rc=%ld\n", (long)CFE_MSG_ValidateChecksum(NULL, &valid));
    }

    /* --- cfe_msg_init.c, cfe_msg_initdefaulthdr_pri.c, cfe_msg_msgid_shared.c --------- */
    {
        unsigned char      buf[32];
        CFE_MSG_Message_t *mp = (CFE_MSG_Message_t *)buf;
        CFE_MSG_Type_t     mtype;
        for (i = 0; i < (int)sizeof(buf); i++)
            buf[i] = 0xEE;
        printf("init     rc=%ld\n", (long)CFE_MSG_Init(mp, CFE_SB_ValueToMsgId(0x1801), 32));
        dump("afterinit", mp);
        /* Init clears the WHOLE size it was given, not just the header -- byte 31 proves it. */
        printf("initclr  b8=%d b31=%d\n", buf[8], buf[31]);
        printf("initseg  rc=%ld g=%d\n", (long)CFE_MSG_GetSegmentationFlag(mp, &seg), (int)seg);
        /* An invalid msgid is explicitly ALLOWED here -- the real one may be filled in later --
         * so this must succeed while CFE_MSG_SetMsgId on the same value would refuse. */
        printf("initinv  rc=%ld\n", (long)CFE_MSG_Init(mp, CFE_SB_INVALID_MSG_ID, 32));
        dump("afterinv", mp);
        /* But a bad SIZE is refused, because the size always has to be real. */
        printf("initsz   rc=%ld\n", (long)CFE_MSG_Init(mp, CFE_SB_ValueToMsgId(0x1801), 0));
        printf("initnull rc=%ld\n", (long)CFE_MSG_Init(NULL, CFE_SB_ValueToMsgId(0x1801), 32));
        /* GetTypeFromMsgId decodes via a throwaway message rather than by masking a bit. */
        printf("typecmd  rc=%ld t=%d\n",
               (long)CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x1801), &mtype), (int)mtype);
        printf("typetlm  rc=%ld t=%d\n",
               (long)CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x0801), &mtype), (int)mtype);
        printf("typebad  rc=%ld\n",
               (long)CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x2000), &mtype));
        printf("typenull rc=%ld\n",
               (long)CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x1801), NULL));
    }

    /* --- cfe_msg_integrity.c ---------------------------------------------------------- */
    {
        CFE_MSG_TelemetryHeader_t tlm;
        CFE_MSG_CommandHeader_t   cmd;
        bool                      acc;
        /* OriginationAction stamps a time AND a checksum and ignores both return values,
         * because exactly one of them can apply to any given packet. The two cases below are
         * the proof: telemetry comes back timestamped with the checksum call having failed
         * harmlessly, and a command comes back checksummed with the time call having failed. */
        for (i = 0; i < (int)sizeof(tlm); i++)
            ((unsigned char *)&tlm)[i] = 0;
        CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Tlm);
        CFE_MSG_SetHasSecondaryHeader(&tlm.Msg, true);
        CFE_MSG_SetSize(&tlm.Msg, sizeof(tlm));
        acc = false;
        printf("origtlm  rc=%ld a=%d\n", (long)CFE_MSG_OriginationAction(&tlm.Msg, sizeof(tlm), &acc),
               (int)acc);
        printf("origtime %d %d %d %d %d %d\n", tlm.Sec.Time[0], tlm.Sec.Time[1], tlm.Sec.Time[2],
               tlm.Sec.Time[3], tlm.Sec.Time[4], tlm.Sec.Time[5]);
        for (i = 0; i < (int)sizeof(cmd); i++)
            ((unsigned char *)&cmd)[i] = 0;
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
        CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, true);
        CFE_MSG_SetSize(&cmd.Msg, sizeof(cmd));
        acc = false;
        printf("origcmd  rc=%ld a=%d\n", (long)CFE_MSG_OriginationAction(&cmd.Msg, sizeof(cmd), &acc),
               (int)acc);
        printf("origcsum f=%d c=%d\n", cmd.Sec.FunctionCode, cmd.Sec.Checksum);
        acc = false;
        printf("verify   rc=%ld a=%d\n",
               (long)CFE_MSG_VerificationAction(&cmd.Msg, sizeof(cmd), &acc), (int)acc);
        printf("orignull rc=%ld\n", (long)CFE_MSG_OriginationAction(NULL, 8, &acc));
        printf("verinull rc=%ld\n", (long)CFE_MSG_VerificationAction(&cmd.Msg, 8, NULL));
    }

    /* --- cfe_resourceid_api.c --------------------------------------------------------- */
    {
        CFE_ResourceId_t rid;
        uint32           idx;
        uint32           base = CFE_RESOURCEID_MAKE_BASE(1);

        /* The C has a CompileTimeAssert that MAX is one less than a power of two, because the
         * same constant is a numeric limit AND a bit mask. HolyC has no static assert, so the
         * property is checked here instead of being silently dropped. */
        printf("ridmask %d\n", (int)(((CFE_RESOURCEID_MAX + 1) & CFE_RESOURCEID_MAX) == 0));
        printf("ridbase %lu %lu\n", (unsigned long)base, (unsigned long)CFE_RESOURCEID_MAX);

        rid = CFE_ResourceId_FromInteger(base + 5);
        printf("ridsplit b=%lu s=%lu i=%lu\n", (unsigned long)CFE_ResourceId_GetBase(rid),
               (unsigned long)CFE_ResourceId_GetSerial(rid),
               (unsigned long)CFE_ResourceId_ToInteger(rid));
        printf("riddef d=%d u=%d\n", (int)CFE_ResourceId_IsDefined(rid),
               (int)CFE_ResourceId_IsDefined(CFE_RESOURCEID_UNDEFINED));

        idx = 0xAAAA;
        printf("ridx     rc=%ld i=%lu\n", (long)CFE_ResourceId_ToIndex(rid, base, 8, &idx),
               (unsigned long)idx);
        /* Id below BaseValue. ToInteger returns unsigned long, so the subtraction is 64-bit and
         * the result only comes back in range because it is stored into a uint32 first. */
        idx = 0xAAAA;
        printf("ridxlow  rc=%ld i=%lu\n",
               (long)CFE_ResourceId_ToIndex(CFE_ResourceId_FromInteger(5), base, 8, &idx),
               (unsigned long)idx);
        /* THE DISCRIMINATING CASE. 5 - 0xFFFFFFFF is 0xFFFFFFFF00000006 in 64 bits, which is far
         * above CFE_RESOURCEID_MAX and would be REJECTED -- but truncated to uint32 it is 6,
         * which is accepted and indexes slot 6. An implementation that keeps 64-bit width here
         * returns an error where NASA's returns success, and only this input says so. */
        idx = 0xAAAA;
        printf("ridxwrap rc=%ld i=%lu\n",
               (long)CFE_ResourceId_ToIndex(CFE_ResourceId_FromInteger(5), 0xFFFFFFFF, 8, &idx),
               (unsigned long)idx);
        idx = 0xAAAA;
        printf("ridxzero rc=%ld i=%lu\n", (long)CFE_ResourceId_ToIndex(rid, base, 0, &idx),
               (unsigned long)idx);
        printf("ridxnull rc=%ld\n", (long)CFE_ResourceId_ToIndex(rid, base, 8, NULL));

        /* FindNext walks the do-while: increment first, then test. Serials 6 and 7 are taken,
         * so starting at 5 must land on 8. */
        printf("ridnext  %lu\n",
               (unsigned long)CFE_ResourceId_ToInteger(CFE_ResourceId_FindNext(rid, 8, rid_in_use)));
        /* Everything taken: RemainingCount reaches zero, the increment yields UNDEFINED, and
         * the IsDefined check breaks the loop rather than spinning forever. */
        printf("ridfull  %lu\n", (unsigned long)CFE_ResourceId_ToInteger(
                                     CFE_ResourceId_FindNext(rid, 8, rid_all_in_use)));
        /* Serial at the top of its range wraps modulo the table size, not to zero. */
        printf("ridwrap  %lu\n",
               (unsigned long)CFE_ResourceId_ToInteger(CFE_ResourceId_FindNext(
                   CFE_ResourceId_FromInteger(base + CFE_RESOURCEID_MAX - 1), 4, rid_in_use)));
        printf("ridnull  %lu %lu\n",
               (unsigned long)CFE_ResourceId_ToInteger(CFE_ResourceId_FindNextEx(rid, NULL, NULL, rid_in_use)),
               (unsigned long)CFE_ResourceId_ToInteger(CFE_ResourceId_FindNextEx(rid, NULL, NULL, NULL)));
        printf("ridobj %s %lu\n", CFE_RESOURCEID_ModuleEntry.Name,
               (unsigned long)CFE_RESOURCEID_ModuleEntry.StackSize);
    }

    /* --- cfe_sb_msg_id_util.c and cfe_sb_util.c --------------------------------------- */
    {
        CFE_MSG_CommandHeader_t   cmd;
        CFE_MSG_TelemetryHeader_t tlm;
        char                      name[12];
        char                      shortbuf[4];
        int32                     n;

        /* MsgHdrSize answers from the packet's own two class bits, which is why the bus can ask
         * it where a payload starts without being told what kind of message it holds. */
        for (i = 0; i < (int)sizeof(cmd); i++)
            ((unsigned char *)&cmd)[i] = 0;
        for (i = 0; i < (int)sizeof(tlm); i++)
            ((unsigned char *)&tlm)[i] = 0;
        printf("hdrsz_none %lu\n", (unsigned long)CFE_SB_MsgHdrSize(&cmd.Msg));
        CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, true);
        CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
        CFE_MSG_SetHasSecondaryHeader(&tlm.Msg, true);
        CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Tlm);
        printf("hdrsz %lu %lu %lu\n", (unsigned long)CFE_SB_MsgHdrSize(&cmd.Msg),
               (unsigned long)CFE_SB_MsgHdrSize(&tlm.Msg),
               (unsigned long)CFE_SB_MsgHdrSize(NULL));

        /* GetUserData/Length and SetUserDataLength are the payload window, measured from that. */
        CFE_MSG_SetSize(&tlm.Msg, sizeof(tlm) + 8);
        printf("userdata off=%ld len=%ld\n",
               (long)((unsigned char *)CFE_SB_GetUserData(&tlm.Msg) - (unsigned char *)&tlm),
               (long)CFE_SB_GetUserDataLength(&tlm.Msg));
        CFE_SB_SetUserDataLength(&tlm.Msg, 20);
        printf("setuserlen len=%ld\n", (long)CFE_SB_GetUserDataLength(&tlm.Msg));
        /* Over the mission maximum: refused, and the size is left alone. */
        CFE_SB_SetUserDataLength(&tlm.Msg, 100000);
        printf("setuserbig len=%ld\n", (long)CFE_SB_GetUserDataLength(&tlm.Msg));
        printf("userdatanull %d %ld\n", (int)(CFE_SB_GetUserData(NULL) == NULL),
               (long)CFE_SB_GetUserDataLength(NULL));

        CFE_SB_TimeStampMsg(&tlm.Msg);
        printf("stamped %d %d %d %d %d %d\n", tlm.Sec.Time[0], tlm.Sec.Time[1], tlm.Sec.Time[2],
               tlm.Sec.Time[3], tlm.Sec.Time[4], tlm.Sec.Time[5]);

        /* MessageStringSet ZERO-FILLS the rest of the destination rather than just terminating,
         * so a short name completely erases a longer one. MessageStringGet reserves one byte for
         * the NUL and falls back to the default when the source is empty. */
        for (i = 0; i < (int)sizeof(name); i++)
            name[i] = 'Z';
        n = CFE_SB_MessageStringSet(name, "ABCDE", sizeof(name), 5);
        printf("strset n=%ld b0=%d b5=%d b11=%d\n", (long)n, name[0], name[5], name[11]);
        n = CFE_SB_MessageStringGet(shortbuf, name, NULL, sizeof(shortbuf), sizeof(name));
        printf("strget n=%ld s=%s\n", (long)n, shortbuf);
        n = CFE_SB_MessageStringGet(shortbuf, "", "dflt", sizeof(shortbuf), 0);
        printf("strdflt n=%ld s=%s\n", (long)n, shortbuf);
        printf("strbad %ld %ld\n", (long)CFE_SB_MessageStringGet(NULL, "x", NULL, 4, 1),
               (long)CFE_SB_MessageStringSet(NULL, "x", 4, 1));

        /* THE TOPIC-ID MAPPING, and the asymmetry in it. For instance 0 the COMMAND function
         * returns the GLOBAL TELEMETRY value -- 0x0865 rather than 0x1865 for topic 5 -- so the
         * type bit of the returned stream id says telemetry. Pinned here deliberately: this is
         * what NASA's code does today, and if upstream changes it this line will say so. */
        printf("topic_cmd  i0=0x%04lx i1=0x%04lx\n",
               (unsigned long)CFE_SB_CmdTopicIdToMsgId(5, 0),
               (unsigned long)CFE_SB_CmdTopicIdToMsgId(5, 1));
        printf("topic_tlm  i0=0x%04lx i1=0x%04lx\n",
               (unsigned long)CFE_SB_TlmTopicIdToMsgId(5, 0),
               (unsigned long)CFE_SB_TlmTopicIdToMsgId(5, 1));
        printf("topic_glob c=0x%04lx t=0x%04lx\n",
               (unsigned long)CFE_SB_GlobalCmdTopicIdToMsgId(5),
               (unsigned long)CFE_SB_GlobalTlmTopicIdToMsgId(5));
        /* Local* route through CFE_PSP_GetProcessorId, stubbed to 1 at the top of this file. */
        printf("topic_locl c=0x%04lx t=0x%04lx\n",
               (unsigned long)CFE_SB_LocalCmdTopicIdToMsgId(5),
               (unsigned long)CFE_SB_LocalTlmTopicIdToMsgId(5));
    }

    /* --- cfe_sbr_map_hash.c and cfe_sbr_route_unsorted.c ------------------------------ */
    {
        CFE_SBR_RouteId_t  rid, rid2;
        CFE_SBR_Throttle_t thr;
        uint32             coll = 0xBEEF;
        int                k;

        /* The C has a #error if the map size is not a power of two, because the size doubles as
         * the wrap mask. HolyC's preprocessor has no #error, so the property is checked here
         * rather than quietly dropped in translation. */
        printf("sbr_pow2 %d\n", (int)(((1024) & (1024 - 1)) == 0));

        /* THE HASH IS 32-BIT ARITHMETIC. Each step multiplies by 0x45d9f3b and overflows; the
         * wrap IS the algorithm. A spread of ids on purpose -- 0x0001 happens to hash the same
         * with and without the wrap, so a transcript testing only that would be blind to a
         * translation that computed in 64 bits. */
        printf("sbr_hash");
        for (k = 0; k < 6; k++)
        {
            static const uint16 ids[6] = {0x0001, 0x0801, 0x1801, 0x0865, 0x1FFF, 0x0102};
            printf(" %lu", (unsigned long)CFE_SBR_MsgIdHash(CFE_SB_ValueToMsgId(ids[k])));
        }
        printf("\n");

        CFE_SBR_Init();
        /* An empty table: nothing routes, and the invalid id is what comes back. */
        rid = CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(0x0801));
        printf("sbr_empty v=%d\n", (int)CFE_SBR_IsValidRouteId(rid));

        rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(0x0801), &coll);
        printf("sbr_add   v=%d idx=%u coll=%lu\n", (int)CFE_SBR_IsValidRouteId(rid),
               (unsigned)CFE_SBR_RouteIdToValue(rid), (unsigned long)coll);
        /* Round trip: id -> route -> id. */
        rid2 = CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(0x0801));
        printf("sbr_get   idx=%u mid=%lu\n", (unsigned)CFE_SBR_RouteIdToValue(rid2),
               (unsigned long)CFE_SB_MsgIdToValue(CFE_SBR_GetMsgId(rid2)));
        /* A second id lands in its own slot. */
        rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(0x1801), &coll);
        printf("sbr_add2  idx=%u coll=%lu\n", (unsigned)CFE_SBR_RouteIdToValue(rid),
               (unsigned long)coll);
        /* An invalid message id is refused and the collision count is still written. */
        coll = 0xBEEF;
        rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(0), &coll);
        printf("sbr_addbad v=%d coll=%lu\n", (int)CFE_SBR_IsValidRouteId(rid),
               (unsigned long)coll);

        /* The destination list head is stored and returned, never inspected -- BY cfe_sbr. It
         * is very much inspected by cfe_sb_priv.c, and this probe used to leave the sentinel in
         * place: harmless while CFE_SB_TransmitMsg was a stub, and a segfault the moment
         * cfe_sb_api.c was gated and the real one walked the route. The crash was in
         * CFE_SB_TransmitTxn_FindDestinations reading Active at 0x1234+4, three thousand lines
         * away from the line that planted it. Put it back. */
        CFE_SBR_SetDestListHeadPtr(rid2, (CFE_SB_DestinationD_t *)0x1234);
        printf("sbr_dest %d %d\n", (int)(CFE_SBR_GetDestListHeadPtr(rid2) == (void *)0x1234),
               (int)(CFE_SBR_GetDestListHeadPtr(CFE_SBR_INVALID_ROUTE_ID) == NULL));
        CFE_SBR_SetDestListHeadPtr(rid2, NULL);

        /* The sequence counter wraps at the 14-bit CCSDS field, not at the width of the type. */
        for (k = 0; k < 3; k++)
            CFE_SBR_IncrementSequenceCounter(rid2);
        printf("sbr_seq %u\n", (unsigned)CFE_SBR_GetSequenceCounter(rid2));
        printf("sbr_seqbad %u\n", (unsigned)CFE_SBR_GetSequenceCounter(CFE_SBR_INVALID_ROUTE_ID));

        /* ForEachRouteId, unthrottled then throttled. The throttle reports where to resume, and
         * zero when it finished the range. */
        sbr_visits = 0;
        CFE_SBR_ForEachRouteId(sbr_count_cb, NULL, NULL);
        printf("sbr_each %d\n", sbr_visits);
        sbr_visits    = 0;
        thr.StartIndex = 0;
        thr.MaxLoop    = 1;
        thr.NextIndex  = 0xFFFF;
        CFE_SBR_ForEachRouteId(sbr_count_cb, NULL, &thr);
        printf("sbr_thr1 n=%d next=%lu\n", sbr_visits, (unsigned long)thr.NextIndex);
        sbr_visits    = 0;
        thr.StartIndex = 0;
        thr.MaxLoop    = 99;
        thr.NextIndex  = 0xFFFF;
        CFE_SBR_ForEachRouteId(sbr_count_cb, NULL, &thr);
        printf("sbr_thr2 n=%d next=%lu\n", sbr_visits, (unsigned long)thr.NextIndex);
        printf("sbr_obj %s\n", CFE_SBR_ModuleEntry.Name);
    }

    /* --- cfe_config_{lookup,get,set,eds_disabled}.c ----------------------------------- */
    {
        CFE_ConfigId_t          cid;
        CFE_Config_ArrayValue_t av, avget;
        char                    vbuf[64];
        static const uint32     ARR[3] = {11, 22, 33};

        /* Init is not translated (it needs the build-generated GLOBAL_CONFIGDATA), so the one
         * thing it would have set is set here on both sides. Everything else below is the
         * module's real API driving its real table. */
        CFE_Config_Global.UnknownString = "UNKNOWN";

        cid = CFE_Config_GetIdByName("CORE_VERSION_MAJOR");
        printf("cfg_id 0x%06lx %s\n", (unsigned long)CFE_RESOURCEID_TO_ULONG(cid),
               CFE_Config_GetName(cid));
        /* A name that is not in the generated table, and a NULL name. */
        printf("cfg_nosuch %lu %lu\n",
               (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_Config_GetIdByName("NOT_A_KEY")),
               (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_Config_GetIdByName(NULL)));
        /* An id below the base underflows the unsigned offset and is refused by the same
         * bounds check that catches one above the top -- the CFE_ResourceId_ToIndex trick. */
        printf("cfg_oob %s\n", CFE_Config_GetName(CFE_CONFIGID_C(CFE_ResourceId_FromInteger(1))));

        CFE_Config_SetValue(cid, 7);
        printf("cfg_val %lu\n", (unsigned long)CFE_Config_GetValue(cid));
        /* Reading the wrong type gives the type's zero, not the stored bits. */
        printf("cfg_wrongtype %d %d\n", (int)(CFE_Config_GetString(cid) == CFE_Config_Global.UnknownString),
               (int)(CFE_Config_GetObjPointer(cid) == NULL));

        CFE_Config_SetString(CFE_Config_GetIdByName("MISSION_NAME"), "benchtop");
        printf("cfg_str %s\n", CFE_Config_GetString(CFE_Config_GetIdByName("MISSION_NAME")));
        /* A STRING also reads back through GetObjPointer -- the one place two types overlap. */
        printf("cfg_strptr %d\n",
               (int)(CFE_Config_GetObjPointer(CFE_Config_GetIdByName("MISSION_NAME")) != NULL));

        av.NumElements = 3;
        av.ElementPtr  = ARR;
        CFE_Config_SetArrayValue(CFE_Config_GetIdByName("TA_AFFINITY_TABLE"), &av);
        avget = CFE_Config_GetArrayValue(CFE_Config_GetIdByName("TA_AFFINITY_TABLE"));
        printf("cfg_arr n=%lu first=%lu\n", (unsigned long)avget.NumElements,
               (unsigned long)(*(const uint32 *)avget.ElementPtr));
        avget = CFE_Config_GetArrayValue(cid);
        printf("cfg_arrbad n=%lu p=%d\n", (unsigned long)avget.NumElements,
               (int)(avget.ElementPtr == NULL));

        cfg_visits = 0;
        CFE_Config_IterateAll(NULL, cfg_count_cb);
        printf("cfg_iter %d of %d\n", cfg_visits, (int)CFE_ConfigIdOffset_MAX);

        /* The version-string helpers, which are the only formatted output in the module. Mission
         * revision 0 means an official release, 0xFF a development build, anything else a user
         * customisation -- three different strings from one uint8. */
        CFE_Config_GetMissionRevString(vbuf, sizeof(vbuf), 0, "v7.0.0");
        printf("cfg_rev0 %s\n", vbuf);
        CFE_Config_GetMissionRevString(vbuf, sizeof(vbuf), 0xFF, "v7.0.0");
        printf("cfg_revff %s\n", vbuf);
        CFE_Config_GetMissionRevString(vbuf, sizeof(vbuf), 42, "v7.0.0");
        printf("cfg_rev42 %s\n", vbuf);
        /* Truncation, which is snprintf's contract and therefore the translation's. */
        CFE_Config_GetMissionRevString(vbuf, 10, 42, "v7.0.0");
        printf("cfg_trunc [%s]\n", vbuf);
        CFE_Config_GetVersionString(vbuf, sizeof(vbuf), "cFE", "1.2.3", "Draco", "v7.0.0");
        printf("cfg_ver %s\n", vbuf);
        printf("cfg_eds %s\n", CFE_Config_EdsState("cFE"));
    }

    /* --- cfe_msg_objtab.c ------------------------------------------------------------- */
    /* One registration entry, no task. ES walks the collected table at every lifecycle phase,
     * so a port that skips these has modules that exist and never start. */
    printf("objtab %s %d %d %d %lu %lu\n", CFE_MSG_ModuleEntry.Name,
           (int)(CFE_MSG_ModuleEntry.EarlyInit == NULL), (int)(CFE_MSG_ModuleEntry.TaskMain == NULL),
           (int)(CFE_MSG_ModuleEntry.AppCleanupCb == NULL),
           (unsigned long)CFE_MSG_ModuleEntry.Priority, (unsigned long)CFE_MSG_ModuleEntry.StackSize);

    /* --- cfe_fs: layout ---------------------------------------------------------------- */
    /* sizeof and the offsets of every translated class, on both sides. check_padding.py already
     * compares these against the host C compiler, but that is a model on the HolyC side; this
     * puts the real compiled layout under the byte-identical transcript, which is stronger. */
    /* CFE_FS_ParseContext_t is deliberately absent: it lives inside cfe_fs_api.c, so this
     * driver cannot see it and a hand-written literal here would compare nothing. Its layout is
     * under tools/cfs/check_padding.py, which lifts the typedef out of the .c and measures it. */
    printf("fs_lay hdr=%zu meta=%zu ent=%zu cur=%zu dump=%zu glob=%zu\n",
           sizeof(CFE_FS_Header_t), sizeof(CFE_FS_FileWriteMetaData_t),
           sizeof(CFE_FS_BackgroundFileDumpEntry_t), sizeof(CFE_FS_CurrentFileState_t),
           sizeof(CFE_FS_BackgroundFileDumpState_t), sizeof(CFE_FS_Global_t));
    printf("fs_off pend=%zu name=%zu sub=%zu desc=%zu get=%zu ev=%zu\n",
           offsetof(CFE_FS_FileWriteMetaData_t, IsPending),
           offsetof(CFE_FS_FileWriteMetaData_t, FileName),
           offsetof(CFE_FS_FileWriteMetaData_t, FileSubType),
           offsetof(CFE_FS_FileWriteMetaData_t, Description),
           offsetof(CFE_FS_FileWriteMetaData_t, GetData),
           offsetof(CFE_FS_FileWriteMetaData_t, OnEvent));
    printf("fs_off2 mut=%zu fdump=%zu req=%zu comp=%zu entries=%zu curr=%zu fd=%zu cred=%zu "
           "recn=%zu fsz=%zu\n",
           offsetof(CFE_FS_Global_t, SharedDataMutexId), offsetof(CFE_FS_Global_t, FileDump),
           offsetof(CFE_FS_BackgroundFileDumpState_t, RequestCount),
           offsetof(CFE_FS_BackgroundFileDumpState_t, CompleteCount),
           offsetof(CFE_FS_BackgroundFileDumpState_t, Entries),
           offsetof(CFE_FS_BackgroundFileDumpState_t, Current),
           offsetof(CFE_FS_CurrentFileState_t, Fd), offsetof(CFE_FS_CurrentFileState_t, Credit),
           offsetof(CFE_FS_CurrentFileState_t, RecordNum),
           offsetof(CFE_FS_CurrentFileState_t, FileSize));

    /* --- cfe_fs_priv.c ----------------------------------------------------------------- */
    printf("fs_init rc=%ld create=%d mut=%lu\n", (long)CFE_FS_EarlyInit(), fs_mut_create,
           (unsigned long)OS_ObjectIdToInteger(CFE_FS_Global.SharedDataMutexId));
    CFE_FS_LockSharedData("drv");
    CFE_FS_UnlockSharedData("drv");
    printf("fs_lock take=%d give=%d\n", fs_mut_take, fs_mut_give);
    /* the three failure paths, each of which logs: the creation, the take and the give */
    fs_mut_create_rc = -11;
    printf("fs_init_nomutex rc=%ld\n", (long)CFE_FS_EarlyInit());
    fs_mut_create_rc = OS_SUCCESS;
    printf("fs_init_again rc=%ld\n", (long)CFE_FS_EarlyInit());
    fs_mut_take_rc = -12;
    CFE_FS_LockSharedData("take_fails");
    printf("fs_lock_takefail done\n");
    fs_mut_take_rc = OS_SUCCESS;
    fs_mut_give_rc = -13;
    CFE_FS_UnlockSharedData("give_fails");
    printf("fs_lock_givefail done\n");
    fs_mut_give_rc = OS_SUCCESS;

    /* --- cfe_fs_api.c: the default locations ------------------------------------------- */
    /* Every category, including the two that have no mount point and the three that have no
     * extension -- those return NULL, and a translation that returned "" instead would pass a
     * test that only looked at the five real ones. */
    {
        int cat;
        for (cat = 0; cat <= CFE_FS_FileCategory_MAX; cat++)
        {
            const char *mp = CFE_FS_GetDefaultMountPoint((CFE_FS_FileCategory_t)cat);
            const char *ex = CFE_FS_GetDefaultExtension((CFE_FS_FileCategory_t)cat);
            printf("fs_cat %d mp=[%s] ex=[%s]\n", cat, mp ? mp : "(null)", ex ? ex : "(null)");
        }
    }

    /* --- the byte swappers ------------------------------------------------------------- */
    {
        uint32          u = 0x11223344;
        CFE_FS_Header_t h;
        CFE_FS_ByteSwapUint32(&u);
        printf("fs_swap32 %08lx\n", (unsigned long)u);
        memset(&h, 0, sizeof(h));
        h.ContentType    = 0x01020304;
        h.SubType        = 0x05060708;
        h.Length         = 0x090a0b0c;
        h.SpacecraftID   = 0x0d0e0f10;
        h.ProcessorID    = 0x11121314;
        h.ApplicationID  = 0x15161718;
        h.TimeSeconds    = 0x191a1b1c;
        h.TimeSubSeconds = 0x1d1e1f20;
        CFE_FS_ByteSwapCFEHeader(&h);
        fs_hdr("fs_swaphdr", &h);
        CFE_FS_ByteSwapCFEHeader(&h);
        fs_hdr("fs_swapback", &h);
    }

    /* --- InitHeader / WriteHeader / ReadHeader / SetTimestamp -------------------------- */
    {
        CFE_FS_Header_t h;
        CFE_FS_Header_t rb;
        int32           rc;

        CFE_FS_InitHeader(NULL, "x", 1);          /* both NULL paths log and return */
        CFE_FS_InitHeader(&h, NULL, 1);
        /* A description LONGER than the field, so strncpy's no-terminator edge is in the
         * transcript: 31 chars plus the NUL the prior memset left. */
        CFE_FS_InitHeader(&h, "0123456789abcdefghijklmnopqrstuvwxyz", CFE_FS_SubType_ES_SYSLOG);
        fs_hdr("fs_inithdr", &h);

        printf("fs_wrhdr_null rc=%ld\n", (long)CFE_FS_WriteHeader(7, NULL));
        printf("fs_rdhdr_null rc=%ld\n", (long)CFE_FS_ReadHeader(NULL, 7));

        fs_wr_left = -1;
        fs_fd        = 7;
        fs_len       = 0;
        fs_pos       = 0;
        rc           = CFE_FS_WriteHeader(7, &h);
        printf("fs_wrhdr rc=%ld len=%ld\n", (long)rc, fs_len);
        /* The header on DISK is big endian; the caller's copy is restored to native. */
        fs_dump("fs_bytes", 32);
        fs_hdr("fs_after", &h);

        rc = CFE_FS_ReadHeader(&rb, 7);
        printf("fs_rdhdr rc=%ld\n", (long)rc);
        fs_hdr("fs_readback", &rb);

        /* A short read: truncate the file so OS_read cannot deliver 64 bytes. */
        fs_len = 20;
        printf("fs_rdhdr_short rc=%ld\n", (long)CFE_FS_ReadHeader(&rb, 7));

        /* SetTimestamp seeks to the byte offset of TimeSeconds, which NASA computes from the
         * struct with two char * casts -- without them C scales by sizeof(uint32) and gets 6. */
        fs_len = 64;
        fs_pos = 0;
        {
            CFE_TIME_SysTime_t ts;
            ts.Seconds    = 0x01234567;
            ts.Subseconds = 0x89abcdef;
            printf("fs_setts rc=%ld pos=%ld\n", (long)CFE_FS_SetTimestamp(7, ts), fs_pos);
            fs_dump("fs_tsbytes", 32);
            /* And the failure path: a write budget of 4 makes it a short write. */
            fs_wr_left = 4;
            printf("fs_setts_short rc=%ld\n", (long)CFE_FS_SetTimestamp(7, ts));
            fs_wr_left = -1;
        }
    }

    /* --- ParseInputFileNameEx --------------------------------------------------------- */
    {
        char o[32];
        printf("fs_parse_nullbuf rc=%ld\n",
               (long)CFE_FS_ParseInputFileNameEx(NULL, NULL, 32, 0, "x", "/cf", ".bin"));
        printf("fs_parse_zerosz rc=%ld\n",
               (long)CFE_FS_ParseInputFileNameEx(o, NULL, 0, 0, "x", "/cf", ".bin"));
        /* no input at all: NULL buffer AND NULL default, so the loop never runs */
        fs_parse("fs_parse_noinput", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, NULL, "/cf", ".bin"));
        /* bare name: default path and default extension both supplied */
        fs_parse("fs_parse_bare", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log", "/cf", ".bin"));
        /* name with its own extension: the default extension is not used */
        fs_parse("fs_parse_ext", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log.txt", "/cf", ".bin"));
        /* name with its own path: the default path is not used */
        fs_parse("fs_parse_path", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/ram/log", "/cf", ".bin"));
        /* duplicate separators, which the separator component collapses from both sides */
        fs_parse("fs_parse_dup", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/ram//sub///log..txt", "/cf",
                                             ".bin"));
        /* a multi-level path: the pathname component repeats until the LAST separator */
        fs_parse("fs_parse_deep", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/a/b/c/log.txt", "/cf",
                                             ".bin"));
        /* no default extension and none in the input: the parse ends early */
        fs_parse("fs_parse_noext", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log", "/cf", NULL));
        /* no default path and none in the input */
        fs_parse("fs_parse_nopath", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log", NULL, ".bin"));
        /* an EMPTY filename: the status stays INVALID_PATH even though a path was produced */
        fs_parse("fs_parse_empty", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/ram/", "/cf", ".bin"));
        /* too long for the output buffer: FNAME_TOO_LONG, and the result is still terminated */
        fs_parse("fs_parse_long", o,
                 CFE_FS_ParseInputFileNameEx(o, NULL, 12, 0, "/ram/averylongfilename.txt", "/cf",
                                             ".bin"));
        /* the InputBuffer form, which is NOT null terminated: 8 bytes of a longer buffer */
        fs_parse("fs_parse_buf", o,
                 CFE_FS_ParseInputFileNameEx(o, "/ram/ab.cdEXTRA", sizeof(o), 10, "unused", "/cf",
                                             ".bin"));
        /* an empty InputBuffer falls back to DefaultInput */
        fs_parse("fs_parse_bufempty", o,
                 CFE_FS_ParseInputFileNameEx(o, "", sizeof(o), 4, "fallback", "/cf", ".bin"));

        /* the category wrapper, for every category */
        {
            int cat;
            for (cat = 0; cat <= CFE_FS_FileCategory_MAX; cat++)
            {
                int32 rc = CFE_FS_ParseInputFileName(o, "nm", sizeof(o),
                                                     (CFE_FS_FileCategory_t)cat);
                printf("fs_parsecat %d rc=%ld [%s]\n", cat, (long)rc, o);
            }
        }
    }

    /* --- ExtractFilenameFromPath ------------------------------------------------------ */
    {
        char o[80];
        int32 rc;
        printf("fs_xf_null rc=%ld\n", (long)CFE_FS_ExtractFilenameFromPath(NULL, o));
        printf("fs_xf_null2 rc=%ld\n", (long)CFE_FS_ExtractFilenameFromPath("/a/b", NULL));
        o[0] = 0;
        rc   = CFE_FS_ExtractFilenameFromPath("/cf/apps/ci_lab.so", o);
        printf("fs_xf rc=%ld [%s]\n", (long)rc, o);
        /* no separator at all */
        o[0] = 0;
        rc   = CFE_FS_ExtractFilenameFromPath("bare.txt", o);
        printf("fs_xf_bare rc=%ld [%s]\n", (long)rc, o);
        /* the ONLY separator is at index 0, so DirMarkIdx == 0 and NASA's test is > 0:
         * "/name" is rejected as INVALID_PATH rather than yielding "name" */
        o[0] = 0;
        rc   = CFE_FS_ExtractFilenameFromPath("/name", o);
        printf("fs_xf_root rc=%ld [%s]\n", (long)rc, o);
        /* a trailing separator: an empty filename, which is still CFE_SUCCESS */
        o[0] = 0;
        rc   = CFE_FS_ExtractFilenameFromPath("/a/b/", o);
        printf("fs_xf_trail rc=%ld [%s]\n", (long)rc, o);
        /* the tail is OS_MAX_PATH_LEN or longer: FNAME_TOO_LONG */
        o[0] = 0;
        rc   = CFE_FS_ExtractFilenameFromPath(
            "/x/0123456789012345678901234567890123456789012345678901234567890123", o);
        printf("fs_xf_long rc=%ld [%s]\n", (long)rc, o);
    }

    /* --- the background file dump queue ----------------------------------------------- */
    {
        CFE_FS_FileWriteMetaData_t m;
        CFE_FS_FileWriteMetaData_t m2;
        int                        i;

        memset(&m, 0, sizeof(m));
        printf("fs_req_null rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(NULL));
        printf("fs_pend_null %d\n", (int)CFE_FS_BackgroundFileDumpIsPending(NULL));
        /* GetData and OnEvent must both be set, and they are checked together */
        printf("fs_req_nogetdata rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m));
        m.GetData = fs_getdata;
        printf("fs_req_noonevent rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m));
        m.OnEvent = fs_onevent;
        /* then a non-empty filename */
        printf("fs_req_noname rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m));
        strncpy(m.FileName, "/ram/dump.bin", sizeof(m.FileName) - 1);
        strncpy(m.Description, "a test dump", sizeof(m.Description) - 1);
        m.FileSubType = CFE_FS_SubType_ES_QUERYALL;
        printf("fs_req rc=%ld pend=%d wake=%d\n", (long)CFE_FS_BackgroundFileDumpRequest(&m),
               (int)CFE_FS_BackgroundFileDumpIsPending(&m), fs_wakeups);
        /* a second request for the SAME object is rejected while it is pending */
        printf("fs_req_again rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m));

        /* run it: open, header, three records with a hole, EOF, complete event */
        fs_open_fail = 0;
        fs_wr_left = -1;
        fs_fd        = 0;
        fs_len       = 0;
        fs_pos       = 0;
        fs_events    = 0;
        for (i = 0; i < 4; i++)
        {
            /* 8 ms of elapsed time is 80 bytes of credit: the 64-byte header plus two
             * 10-byte records overruns it, so the first call cannot reach EOF and the
             * multi-call path is in the transcript rather than assumed. */
            bool more = CFE_FS_RunBackgroundFileDump(8, NULL);
            printf("fs_run%d more=%d fd=%lu cred=%ld rec=%lu sz=%lu pend=%d comp=%lu\n", i,
                   (int)more, (unsigned long)OS_ObjectIdToInteger(CFE_FS_Global.FileDump.Current.Fd),
                   (long)CFE_FS_Global.FileDump.Current.Credit,
                   (unsigned long)CFE_FS_Global.FileDump.Current.RecordNum,
                   (unsigned long)CFE_FS_Global.FileDump.Current.FileSize,
                   (int)CFE_FS_BackgroundFileDumpIsPending(&m),
                   (unsigned long)CFE_FS_Global.FileDump.CompleteCount);
        }
        fs_dump("fs_filebytes", 32);
        printf("fs_events %d\n", fs_events);

        /* the CREATE failure path */
        memset(&m2, 0, sizeof(m2));
        m2.GetData = fs_getdata;
        m2.OnEvent = fs_onevent;
        strncpy(m2.FileName, "/ram/nope.bin", sizeof(m2.FileName) - 1);
        strncpy(m2.Description, "create fails", sizeof(m2.Description) - 1);
        printf("fs_req2 rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m2));
        fs_open_fail                           = 1;
        CFE_FS_Global.FileDump.Current.Credit   = 0;
        printf("fs_run_createfail more=%d pend=%d comp=%lu\n",
               (int)CFE_FS_RunBackgroundFileDump(1000, NULL),
               (int)CFE_FS_BackgroundFileDumpIsPending(&m2),
               (unsigned long)CFE_FS_Global.FileDump.CompleteCount);
        fs_open_fail = 0;

        /* the HEADER WRITE failure path: a 4-byte budget makes WriteHeader return 4, not 64 */
        printf("fs_req3 rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m2));
        fs_wr_left                            = 4;
        CFE_FS_Global.FileDump.Current.Credit = 0;
        printf("fs_run_hdrfail more=%d pend=%d\n", (int)CFE_FS_RunBackgroundFileDump(1000, NULL),
               (int)CFE_FS_BackgroundFileDumpIsPending(&m2));

        /* the RECORD WRITE failure path: the header fits, a record does not */
        printf("fs_req4 rc=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m2));
        fs_wr_left                            = 64;
        CFE_FS_Global.FileDump.Current.Credit = 0;
        printf("fs_run_recfail more=%d pend=%d\n", (int)CFE_FS_RunBackgroundFileDump(1000, NULL),
               (int)CFE_FS_BackgroundFileDumpIsPending(&m2));
        fs_wr_left = -1;

        /* nothing queued: the lock is taken, Curr stays NULL, and it returns false */
        printf("fs_run_idle more=%d\n", (int)CFE_FS_RunBackgroundFileDump(1000, NULL));

        /* the credit CAP: a huge elapsed time must not bank more than MAX_CREDIT */
        CFE_FS_Global.FileDump.Current.Credit = 0;
        CFE_FS_RunBackgroundFileDump(100000, NULL);
        printf("fs_credit_cap %ld\n", (long)CFE_FS_Global.FileDump.Current.Credit);

        /* the queue FULL path. The check is RequestCount + 1 == CompleteCount + 4, so three
         * objects can be queued and the fourth is refused. */
        {
            static CFE_FS_FileWriteMetaData_t q[5];
            int k;
            for (k = 0; k < 5; k++)
            {
                memset(&q[k], 0, sizeof(q[k]));
                q[k].GetData = fs_getdata;
                q[k].OnEvent = fs_onevent;
                q[k].FileName[0] = 'q';
                q[k].FileName[1] = (char)('0' + k);
                printf("fs_qfill%d rc=%ld\n", k, (long)CFE_FS_BackgroundFileDumpRequest(&q[k]));
            }
        }
        printf("fs_lockcount take=%d give=%d\n", fs_mut_take, fs_mut_give);
    }

    /* --- cfe_fs_objtab.c -------------------------------------------------------------- */
    /* The first registration entry here with a non-NULL hook: FS has no task but does have
     * global data, so EarlyInit is set and TaskMain is not. */
    printf("fs_objtab %s %d %d %d %lu %lu\n", CFE_FS_ModuleEntry.Name,
           (int)(CFE_FS_ModuleEntry.EarlyInit == NULL), (int)(CFE_FS_ModuleEntry.TaskMain == NULL),
           (int)(CFE_FS_ModuleEntry.AppCleanupCb == NULL),
           (unsigned long)CFE_FS_ModuleEntry.Priority, (unsigned long)CFE_FS_ModuleEntry.StackSize);

    /* --- cfe_config_init.c ------------------------------------------------------------- */
    /* The last piece of the config module, and it was blocked on build output rather than on
     * translation: GLOBAL_CONFIGDATA, the CFE_CONFIGID_* id macros and
     * CFE_Config_SetupPlatformConfigInfo, which is declared in cfe_config_external.h and
     * defined nowhere in the tree. tools/cfs/gen_platform_config.py compiles and runs NASA's
     * OWN generator for the last one. */
    {
        CFE_ConfigName_t *ci_set[2];
        int32             rc;

        /* the case-insensitive comparison, including the two ways it can be unequal */
        printf("ci_eq %d %d %d %d %d %d\n", (int)CFE_Config_StrCaseEq("CFE_ES", "cfe_es"),
               (int)CFE_Config_StrCaseEq("CFE_ES", "CFE_ES"),
               (int)CFE_Config_StrCaseEq("CFE_ES", "CFE_SB"),
               (int)CFE_Config_StrCaseEq("CFE", "CFE_ES"),      /* prefix: shorter first */
               (int)CFE_Config_StrCaseEq("CFE_ES", "CFE"),      /* prefix: longer first */
               (int)CFE_Config_StrCaseEq("", ""));

        ci_str("ci_kv_hit", CFE_Config_FindTargetKeyValue(ci_kv, "cfe_es"));
        ci_str("ci_kv_miss", CFE_Config_FindTargetKeyValue(ci_kv, "CFE_EVS"));
        ci_str("ci_kv_nulllist", CFE_Config_FindTargetKeyValue(NULL, "CFE_ES"));
        ci_str("ci_kv_nullkey", CFE_Config_FindTargetKeyValue(ci_kv, NULL));

        ci_str("ci_mod_hit", CFE_Config_IsModuleInList(ci_core, "cfe_sb"));
        ci_str("ci_mod_miss", CFE_Config_IsModuleInList(ci_core, "CFE_TBL"));
        ci_str("ci_mod_null", CFE_Config_IsModuleInList(NULL, "CFE_SB"));

        ci_str("ci_psp_hit", CFE_Config_IsPspModule(ci_psp, "EEPROM_DIRECT"));
        ci_str("ci_psp_miss", CFE_Config_IsPspModule(ci_psp, "nope"));
        ci_str("ci_psp_null", CFE_Config_IsPspModule(NULL, "x"));

        /* the set walk: found in the FIRST list, found in the SECOND, and in neither */
        ci_set[0] = ci_core;
        ci_set[1] = ci_apps;
        ci_str("ci_set_first", CFE_Config_FindStaticModName(ci_set, 2, "cfe_es"));
        ci_str("ci_set_second", CFE_Config_FindStaticModName(ci_set, 2, "CI_LAB"));
        ci_str("ci_set_none", CFE_Config_FindStaticModName(ci_set, 2, "nothing"));
        ci_str("ci_set_zerolen", CFE_Config_FindStaticModName(ci_set, 0, "cfe_es"));

        /* and the whole initialisation. Note this MEMSETS the registry, so it has to come after
         * the config get/set lines above. */
        rc = CFE_Config_Init();
        printf("ci_init rc=%ld\n", (long)rc);
        ci_str("ci_mission", CFE_Config_GetString(CFE_CONFIGID_MISSION_NAME));
        ci_str("ci_missionver", CFE_Config_GetString(CFE_CONFIGID_MISSION_SRCVER));
        printf("ci_ver %lu %lu %lu %lu %lu\n",
               (unsigned long)CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_MAJOR),
               (unsigned long)CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_MINOR),
               (unsigned long)CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_REVISION),
               (unsigned long)CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_MISSION_REV),
               (unsigned long)CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_BUILDNUM));
        ci_str("ci_baseline", CFE_Config_GetString(CFE_CONFIGID_CORE_VERSION_BASELINE));
        /* CFE_CONFIGID_CORE_VERSION_DESCRIPTION is DELIBERATELY NOT PRINTED. NASA builds the
         * string into a LOCAL array in CFE_Config_SetupBasicBuildInfo and hands it to
         * CFE_Config_SetString, which stores the POINTER and copies nothing -- so the id holds
         * a pointer into dead stack the moment that function returns. Measured here before it
         * was removed: [cFE v7.0.1+de251(Draco) DEV BUILD, based on v7.0.1, EDS disa] where
         * "v7.0.1+dev1 " and "disabled" belonged. Printing it would put stack contents in a
         * transcript that has to match byte for byte between two different machines.
         * docs/CFS_UPSTREAM_NOTES.md #8. The formatter itself is covered by cfg_ver above.
         * What IS checked is that the id was set at all, i.e. that it is not the fallback: */
        printf("ci_desc_set %d\n",
               (int)(CFE_Config_GetString(CFE_CONFIGID_CORE_VERSION_DESCRIPTION) !=
                     CFE_Config_Global.UnknownString));
        ci_str("ci_date", CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_DATE));
        ci_str("ci_user", CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_USER));
        ci_str("ci_host", CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_HOST));
        /* the MOD_SRCVER_* ids: set only for modules that are BOTH in the name table and in a
         * static module list, which is how SetupModuleVersions skips dynamically loaded ones */
        ci_str("ci_mod_msg", CFE_Config_GetString(CFE_CONFIGID_MOD_SRCVER_MSG));
        ci_str("ci_mod_es", CFE_Config_GetString(CFE_CONFIGID_MOD_SRCVER_ES));
        /* and the three platform arrays the generated code installs */
        {
            CFE_Config_ArrayValue_t av;
            av = CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_MEM_BLOCK_SIZE);
            printf("ci_arr_es n=%lu first=%lu last=%lu\n", (unsigned long)av.NumElements,
                   (unsigned long)((const size_t *)av.ElementPtr)[0],
                   (unsigned long)((const size_t *)av.ElementPtr)[av.NumElements - 1]);
            av = CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_CDS_MEM_BLOCK_SIZE);
            printf("ci_arr_cds n=%lu first=%lu last=%lu\n", (unsigned long)av.NumElements,
                   (unsigned long)((const size_t *)av.ElementPtr)[0],
                   (unsigned long)((const size_t *)av.ElementPtr)[av.NumElements - 1]);
            av = CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_SB_MEM_BLOCK_SIZE);
            printf("ci_arr_sb n=%lu first=%lu last=%lu\n", (unsigned long)av.NumElements,
                   (unsigned long)((const size_t *)av.ElementPtr)[0],
                   (unsigned long)((const size_t *)av.ElementPtr)[av.NumElements - 1]);
        }
    }

    /* --- cfe_config_objtab.c ---------------------------------------------------------- */
    /* CONFIG's EarlyInit runs FIRST of all modules: the registry has to exist before anything
     * else in the startup sequence can read a value out of it. */
    printf("ci_objtab %s %d %d %d %lu %lu\n", CFE_CONFIG_ModuleEntry.Name,
           (int)(CFE_CONFIG_ModuleEntry.EarlyInit == NULL),
           (int)(CFE_CONFIG_ModuleEntry.TaskMain == NULL),
           (int)(CFE_CONFIG_ModuleEntry.AppCleanupCb == NULL),
           (unsigned long)CFE_CONFIG_ModuleEntry.Priority,
           (unsigned long)CFE_CONFIG_ModuleEntry.StackSize);

    /* --- cfe_ta: layout ----------------------------------------------------------------- */
    printf("ta_lay aff=%zu diag=%zu glob=%zu hk=%zu setcmd=%zu cpuset=%zu\n",
           sizeof(CFE_TA_CpuTaskAffinity_t), sizeof(CFE_TA_DiagInfo_t), sizeof(CFE_TA_Global_t),
           sizeof(CFE_TA_HousekeepingTlm_t), sizeof(CFE_TA_SetTaskAffinityCmd_t),
           sizeof(OS_cpuset_t));
    printf("ta_off name=%zu mask=%zu fromos=%zu type=%zu status=%zu | cores=%zu arr=%zu\n",
           offsetof(CFE_TA_CpuTaskAffinity_t, TaskName),
           offsetof(CFE_TA_CpuTaskAffinity_t, CpuMask),
           offsetof(CFE_TA_CpuTaskAffinity_t, CpuFromOS),
           offsetof(CFE_TA_CpuTaskAffinity_t, Type), offsetof(CFE_TA_CpuTaskAffinity_t, Status),
           offsetof(CFE_TA_DiagInfo_t, CoresConfigured),
           offsetof(CFE_TA_DiagInfo_t, CpuTaskAffinity));

    /* --- CFE_TA_Cpu_Set ----------------------------------------------------------------- */
    /* Driven DIRECTLY, because nothing else can see it: OS_CPUSET_ZERO and OS_CPUSET_SET are
     * macros in the C, so check_coverage never looks for them and check_signatures never
     * compares them. With OS_MAX_CPUS == 1 the loop runs at most once, so the three-way bound
     * is the whole of the behaviour and the mask byte is the whole of the output. */
    {
        OS_cpuset_t   cs;
        unsigned char mask[8];
        int           k;

        for (k = 0; k < 8; k++)
        {
            mask[k] = 0xFF;
        }
        ta_cores = 1;
        CFE_TA_Cpu_Set(mask, &cs);
        printf("ta_cpuset all1 cores=1 -> %02x\n", cs.affinity_mask[0]);

        mask[0] = 0x00;
        CFE_TA_Cpu_Set(mask, &cs);
        printf("ta_cpuset bit0clr cores=1 -> %02x\n", cs.affinity_mask[0]);

        mask[0] = 0x01;
        CFE_TA_Cpu_Set(mask, &cs);
        printf("ta_cpuset bit0set cores=1 -> %02x\n", cs.affinity_mask[0]);

        /* CoresConfigured is the tightest of the three bounds: at 0 the loop never runs and the
         * mask stays zeroed however many bits the ground sent. */
        ta_cores = 0;
        mask[0]  = 0xFF;
        CFE_TA_Cpu_Set(mask, &cs);
        printf("ta_cpuset all1 cores=0 -> %02x\n", cs.affinity_mask[0]);
        ta_cores = 1;
    }

    /* --- CFE_TA_EarlyInit ---------------------------------------------------------------- */
    /* With no table in the config registry: the live array stays empty. The id was set to the
     * TA affinity table pointer by CFE_Config_Init above, which for this port is NULL. */
    printf("ta_early rc=%ld\n", (long)CFE_TA_EarlyInit());
    ta_row("ta_early_row", 0);

    /* Now with a table, including the empty-string terminator that stops the copy early. */
    {
        static CFE_TA_CpuTaskAffinity_t tbl[4];
        memset(tbl, 0, sizeof(tbl));
        strncpy(tbl[0].TaskName, "CFE_ES", sizeof(tbl[0].TaskName) - 1);
        tbl[0].Type = CFE_TA_Mask;
        tbl[0].CpuMask.affinity_mask[0] = 0x01;
        strncpy(tbl[1].TaskName, "CFE_SB", sizeof(tbl[1].TaskName) - 1);
        tbl[1].Type = CFE_TA_OsDefault;
        /* tbl[2].TaskName is "" -- the terminator. tbl[3] must NOT be copied. */
        strncpy(tbl[3].TaskName, "NEVER", sizeof(tbl[3].TaskName) - 1);
        CFE_Config_SetObjPointer(CFE_CONFIGID_TA_AFFINITY_TABLE, tbl);
        printf("ta_early2 rc=%ld\n", (long)CFE_TA_EarlyInit());
        ta_row("ta_early2_row", 0);
        ta_row("ta_early2_row", 1);
        ta_row("ta_early2_row", 2);
        ta_row("ta_early2_row", 3);
    }

    /* --- CFE_TA_TaskInit: the success path and all five failures ------------------------- */
    ta_evs_register_rc = CFE_SUCCESS;
    sb_queuecreate_rc  = OS_SUCCESS;
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
    ta_cores           = 1;
    printf("ta_init rc=%ld pipes=%ld subs=%u\n", (long)CFE_TA_TaskInit(), sb_qcreates,
           CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
    printf("ta_init_diag cores=%u max=%u app=%lu\n", CFE_TA_Global.CFE_TA_DiagInfo.CoresConfigured,
           CFE_TA_Global.CFE_TA_DiagInfo.TACoresMax,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TA_Global.TA_AppID));

    ta_evs_register_rc = -77;
    printf("ta_init_evsfail rc=%ld\n", (long)CFE_TA_TaskInit());
    ta_evs_register_rc = CFE_SUCCESS;
    /* The create failure is now an OSAL error, and CFE_SB_CreatePipe turns it into
     * CFE_SB_PIPE_CR_ERR -- NASA's code deciding, where a stub used to return -78. */
    sb_queuecreate_rc = OS_ERROR;
    printf("ta_init_pipefail rc=%ld\n", (long)CFE_TA_TaskInit());
    sb_queuecreate_rc = OS_SUCCESS;
    /* And the subscribe failure is the destination block allocation failing, which is the one
     * real way CFE_SB_SubscribeFull fails for a caller who owns a valid pipe:
     * CFE_SB_DEST_BLK_ERR_EID and CFE_SB_BUF_ALOC_ERR. */
    es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
    printf("ta_init_subfail rc=%ld\n", (long)CFE_TA_TaskInit());
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);

    /* --- the simple commands -------------------------------------------------------------- */
    printf("ta_noop rc=%ld\n", (long)CFE_TA_NoopCmd(NULL));
    CFE_TA_Global.CommandCounter      = 7;
    CFE_TA_Global.CommandErrorCounter = 8;
    CFE_TA_Global.StartupCounter      = 9;
    CFE_TA_Global.StartupErrorCounter = 10;
    sb_tx_reset();
    printf("ta_hk rc=%ld tx=%d pay=%u/%u/%u/%u\n", (long)CFE_TA_ReportHousekeepingCmd(NULL),
           sb_tx_since(), CFE_TA_Global.TA_TlmPkt.Payload.CommandCounter,
           CFE_TA_Global.TA_TlmPkt.Payload.CommandErrorCounter,
           CFE_TA_Global.TA_TlmPkt.Payload.StartupCounter,
           CFE_TA_Global.TA_TlmPkt.Payload.StartupErrorCounter);
    /* The reset command returns NO_COUNTER_INCREMENT, not SUCCESS -- deliberately, so the
     * dispatcher does not bump the counter it just cleared. */
    printf("ta_reset rc=%ld\n", (long)CFE_TA_ResetCountersCmd(NULL));
    ta_counters("ta_reset_after");

    /* --- SetTaskAffinityCmd: every branch -------------------------------------------------- */
    {
        CFE_TA_SetTaskAffinityCmd_t cmd;

        memset(&cmd, 0, sizeof(cmd));
        strncpy(cmd.Payload.TaskName, "CFE_ES", sizeof(cmd.Payload.TaskName) - 1);
        cmd.Payload.AffinityMask[0] = 0x01;

        ta_getid_rc = OS_SUCCESS;
        ta_setaff_rc = OS_SUCCESS;
        ta_getaff_rc = OS_SUCCESS;
        ta_os_mask = 0;
        printf("ta_set_ok rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&cmd));
        ta_row("ta_set_ok_row", 0);

        /* the OS refuses the set */
        ta_setaff_rc = -5;
        printf("ta_set_setfail rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&cmd));
        ta_row("ta_set_setfail_row", 0);
        ta_setaff_rc = OS_SUCCESS;

        /* the set works but the read-back does not */
        ta_getaff_rc = -6;
        printf("ta_set_getfail rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&cmd));
        ta_row("ta_set_getfail_row", 0);
        ta_getaff_rc = OS_SUCCESS;

        /* a task that is not in the list: the walk stops at the first empty name */
        strncpy(cmd.Payload.TaskName, "NOT_THERE", sizeof(cmd.Payload.TaskName) - 1);
        printf("ta_set_notfound rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&cmd));
        ta_counters("ta_set_after");
    }

    /* --- GetTaskAffinityCmd ---------------------------------------------------------------- */
    {
        CFE_TA_GetTaskAffinityCmd_t cmd;

        memset(&cmd, 0, sizeof(cmd));
        strncpy(cmd.Payload.TaskName, "CFE_ES", sizeof(cmd.Payload.TaskName) - 1);

        /* no discrepancy: the OS reports what the table already holds */
        ta_os_mask = CFE_TA_CpuTaskAffinity[0].CpuFromOS.affinity_mask[0];
        printf("ta_get_same rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&cmd));
        ta_row("ta_get_same_row", 0);

        /* a discrepancy: the OS reports something else, and TA adopts it */
        ta_os_mask = 0x01;
        CFE_TA_CpuTaskAffinity[0].CpuFromOS.affinity_mask[0] = 0x00;
        printf("ta_get_diff rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&cmd));
        ta_row("ta_get_diff_row", 0);

        ta_getaff_rc = -8;
        printf("ta_get_fail rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&cmd));
        ta_row("ta_get_fail_row", 0);
        ta_getaff_rc = OS_SUCCESS;

        strncpy(cmd.Payload.TaskName, "NOT_THERE", sizeof(cmd.Payload.TaskName) - 1);
        printf("ta_get_notfound rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&cmd));
        ta_counters("ta_get_after");
    }

    /* --- SetStartupAffinity: the three Types, the add path, and a failed lookup ------------ */
    {
        ta_getid_rc  = OS_SUCCESS;
        ta_getaff_rc = OS_SUCCESS;
        ta_os_mask   = 0x01;

        /* CFE_ES is in the list with Type == CFE_TA_Mask after the set above */
        printf("ta_startup_mask rc=%ld\n", (long)CFE_TA_SetStartupAffinity("CFE_ES"));
        ta_row("ta_startup_mask_row", 0);

        /* CFE_SB is in the list with Type == CFE_TA_OsDefault */
        printf("ta_startup_osdef rc=%ld\n", (long)CFE_TA_SetStartupAffinity("CFE_SB"));
        ta_row("ta_startup_osdef_row", 1);

        /* a name not in the list is ADDED at the first empty slot */
        printf("ta_startup_add rc=%ld\n", (long)CFE_TA_SetStartupAffinity("BRAND_NEW"));
        ta_row("ta_startup_add_row", 2);

        /* an invalid Type */
        CFE_TA_CpuTaskAffinity[1].Type = 99;
        printf("ta_startup_badtype rc=%ld\n", (long)CFE_TA_SetStartupAffinity("CFE_SB"));
        ta_row("ta_startup_badtype_row", 1);
        CFE_TA_CpuTaskAffinity[1].Type = CFE_TA_OsDefault;

        /* the name lookup fails: the loop never runs at all */
        ta_getid_rc = -9;
        printf("ta_startup_noid rc=%ld\n", (long)CFE_TA_SetStartupAffinity("CFE_ES"));
        ta_getid_rc = OS_SUCCESS;

        /* The two OS failures inside the loop. Each logs a line carrying the TASK NAME and the
         * STATUS, and neither was reachable before -- the block above only ever had the OS
         * succeed, so the arguments in those two syslog calls were translated and never read. */
        ta_getaff_rc = -21;
        printf("ta_startup_getfail rc=%ld\n", (long)CFE_TA_SetStartupAffinity("CFE_ES"));
        ta_getaff_rc = OS_SUCCESS;
        ta_setaff_rc = -22;
        printf("ta_startup_setfail rc=%ld\n", (long)CFE_TA_SetStartupAffinity("CFE_ES"));
        ta_setaff_rc = OS_SUCCESS;
        ta_counters("ta_startup_after");

        /* and the OS event handler, which is the only caller of SetStartupAffinity in flight */
        printf("ta_evh_alloc rc=%ld\n", (long)CFE_TA_OS_EventHandler(OS_EVENT_RESOURCE_ALLOCATED, 1, NULL));
        printf("ta_evh_created rc=%ld\n", (long)CFE_TA_OS_EventHandler(OS_EVENT_RESOURCE_CREATED, 1, NULL));
        printf("ta_evh_deleted rc=%ld\n", (long)CFE_TA_OS_EventHandler(OS_EVENT_RESOURCE_DELETED, 1, NULL));
        printf("ta_evh_startup rc=%ld\n", (long)CFE_TA_OS_EventHandler(OS_EVENT_TASK_STARTUP, 1, NULL));
        ta_row("ta_evh_startup_row", 3);
        ta_counters("ta_evh_after");
    }

    /* --- QueryAllTasksCmd: through the TRANSLATED fs module and the simulated file ---------- */
    {
        CFE_TA_QueryAllTasksCmd_t cmd;

        memset(&cmd, 0, sizeof(cmd));
        strncpy(cmd.Payload.FileName, "/ram/ta.log", sizeof(cmd.Payload.FileName) - 1);

        fs_open_fail = 0;
        fs_wr_left   = -1;
        fs_fd        = 0;
        fs_len       = 0;
        fs_pos       = 0;
        printf("ta_query rc=%ld len=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&cmd), fs_len);
        fs_dump("ta_query_bytes", 16);
        ta_counters("ta_query_after");

        /* the file cannot be created */
        fs_open_fail = 1;
        printf("ta_query_nocreate rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&cmd));
        fs_open_fail = 0;

        /* the header write comes up short */
        fs_wr_left = 4;
        printf("ta_query_hdrfail rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&cmd));

        /* the header fits and the diagnostic packet does not */
        fs_wr_left = 64;
        printf("ta_query_datafail rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&cmd));
        fs_wr_left = -1;
        ta_counters("ta_query_errs");
    }

    /* --- cfe_ta_dispatch.c ------------------------------------------------------------------ */
    /* The CONDITIONAL source: CMakeLists picks this one when EDS is off, which is this port.
     * CFE_TA_TaskMain calls CFE_TA_TaskPipe, so a port that translated only the two
     * unconditional sources would have a task whose message loop dispatches to nothing. */
    {
        union
        {
            CFE_SB_Buffer_t             Buf;
            CFE_TA_SetTaskAffinityCmd_t Set;
            CFE_TA_QueryAllTasksCmd_t   Query;
            unsigned char               Bytes[128];
        } sb;
        int cc;

        memset(&sb, 0, sizeof(sb));
        CFE_MSG_Init(CFE_MSG_PTR(sb.Set.CommandHeader), CFE_SB_ValueToMsgId(CFE_TA_CMD_MID),
                     sizeof(CFE_TA_SetTaskAffinityCmd_t));

        /* the length check, both ways */
        printf("ta_len_ok %d\n",
               (int)CFE_TA_VerifyCmdLength(&sb.Buf.Msg, sizeof(CFE_TA_SetTaskAffinityCmd_t)));
        printf("ta_len_bad %d\n", (int)CFE_TA_VerifyCmdLength(&sb.Buf.Msg, 9999));

        /* every command code, then one that does not exist */
        for (cc = 0; cc <= 5; cc++)
        {
            CFE_MSG_SetFcnCode(&sb.Buf.Msg, cc);
            /* give each command the length IT expects, so the routing rather than the length
             * check is what the transcript shows */
            switch (cc)
            {
                case CFE_TA_NOOP_CC:
                case CFE_TA_RESET_COUNTERS_CC:
                    CFE_MSG_SetSize(&sb.Buf.Msg, sizeof(CFE_TA_NoopCmd_t));
                    break;
                case CFE_TA_QUERY_ALL_TASKS_CC:
                    CFE_MSG_SetSize(&sb.Buf.Msg, sizeof(CFE_TA_QueryAllTasksCmd_t));
                    break;
                case CFE_TA_SET_TASK_AFFINITY_CC:
                    CFE_MSG_SetSize(&sb.Buf.Msg, sizeof(CFE_TA_SetTaskAffinityCmd_t));
                    break;
                case CFE_TA_GET_TASK_AFFINITY_CC:
                    CFE_MSG_SetSize(&sb.Buf.Msg, sizeof(CFE_TA_GetTaskAffinityCmd_t));
                    break;
                default:
                    break;
            }
            printf("ta_cc %d:\n", cc);
            CFE_TA_ProcessGroundCommand(&sb.Buf, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID));
        }
        ta_counters("ta_cc_after");

        /* TaskPipe: the housekeeping id, the command id, and one that is neither */
        CFE_MSG_SetFcnCode(&sb.Buf.Msg, CFE_TA_NOOP_CC);
        CFE_MSG_SetSize(&sb.Buf.Msg, sizeof(CFE_TA_NoopCmd_t));
        CFE_MSG_SetMsgId(&sb.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TA_SEND_HK_MID));
        printf("ta_pipe_hk:\n");
        CFE_TA_TaskPipe(&sb.Buf);
        CFE_MSG_SetMsgId(&sb.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID));
        printf("ta_pipe_cmd:\n");
        CFE_TA_TaskPipe(&sb.Buf);
        CFE_MSG_SetMsgId(&sb.Buf.Msg, CFE_SB_ValueToMsgId(0x1FFF));
        printf("ta_pipe_unknown:\n");
        CFE_TA_TaskPipe(&sb.Buf);
        ta_counters("ta_pipe_after");
    }

    /* --- cfe_ta_objtab.c --------------------------------------------------------------------- */
    /* The first entry here with every field filled in: TA is an app, not a library. */
    printf("ta_objtab %s %d %d %d %lu %lu\n", CFE_TA_ModuleEntry.Name,
           (int)(CFE_TA_ModuleEntry.EarlyInit == NULL), (int)(CFE_TA_ModuleEntry.TaskMain == NULL),
           (int)(CFE_TA_ModuleEntry.AppCleanupCb == NULL),
           (unsigned long)CFE_TA_ModuleEntry.Priority,
           (unsigned long)CFE_TA_ModuleEntry.StackSize);
    printf("ta_cleanup rc=%ld\n", (long)CFE_TA_CleanUpApp(1));

    /* --- cfe_evs: the real event service ------------------------------------------------ */
    /* Three of EVS's six sources, and with them the CFE_EVS_SendEvent stub is gone: the ta
     * events above now go through registration, filtering, the squelch bucket, the local log
     * and the formatter, and come out of EVS_OutputPort as real text. That text is the
     * strongest thing in this transcript, because it is the packet payload: the first
     * formatted string in this translation that is INSIDE the byte-identical comparison. */
    {
        CFE_EVS_BinFilter_t  filters[3];
        EVS_AppData_t       *adp;
        /* PROPERLY BASED IDS. These were a bare 1 and 2 while the *_ToIndex functions were
         * stubs that took a small id AS the index. The real CFE_ES_AppID_ToIndex subtracts
         * CFE_ES_APPID_BASE, so a bare 1 is out of range and EVS_GetAppDataByID returns NULL --
         * which this probe then dereferenced. The ids now match what es_ctx_init planted. */
        CFE_ES_AppId_t       evsid  = CFE_ES_APPID_C(ES_CTX_APPID(1));
        CFE_ES_AppId_t       othrid = CFE_ES_APPID_C(ES_CTX_APPID(2));
        int                  k;

        /* Stand EVS up the way cfe_evs_task.c would: the log in the reset area, the format
         * and port defaults, an unlimited squelch bucket, and EVS registered as app 1. */
        memset(&CFE_EVS_Global, 0, sizeof(CFE_EVS_Global));
        memset(&evs_log_storage, 0, sizeof(evs_log_storage));
        CFE_EVS_Global.EVS_LogPtr                            = &evs_log_storage;
        CFE_EVS_Global.EVS_AppID                             = evsid;
        CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode  = CFE_EVS_MsgFormat_LONG;
        CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort         = CFE_EVS_PORT1_BIT;
        CFE_EVS_Global.EVS_EventBurstMax                     = 0; /* squelch off for now */
        CFE_EVS_Global.EVS_LogPtr->LogMode                   = CFE_EVS_LogMode_OVERWRITE;
        evs_psp_ns                                           = 0;
        sb_tx_reset();
        evs_printf_lines                                     = 0;

        /* --- CFE_EVS_Register ----------------------------------------------------------- */
        /* The caller is whatever CFE_ES_GetAppID says, which this driver points at app 1. */
        es_set_ctx(1);
        printf("evs_reg_badscheme rc=%ld\n", (long)CFE_EVS_Register(NULL, 0, 99));
        printf("evs_reg_nullfilters rc=%ld\n", (long)CFE_EVS_Register(NULL, 2, CFE_EVS_EventFilter_BINARY));

        filters[0].EventID = 10;
        filters[0].Mask    = 0x0001;
        filters[1].EventID = 20;
        filters[1].Mask    = 0x0000;
        filters[2].EventID = 30;
        filters[2].Mask    = 0xFFFF;
        printf("evs_reg rc=%ld\n", (long)CFE_EVS_Register(filters, 3, CFE_EVS_EventFilter_BINARY));
        adp = EVS_GetAppDataByID(evsid);
        printf("evs_reg_state used=%d active=%d tokens=%ld mask=%u\n", (int)EVS_AppDataIsUsed(adp),
               adp->ActiveFlag, (long)adp->SquelchTokens, EVS_EventArrayToBitMask(adp));
        /* The three supplied filters, then the first unused slot: NASA marks those FREE_SLOT
         * (-1), which in a uint16 EventID is 0xFFFF. */
        for (k = 0; k < 4; k++)
        {
            printf("evs_reg_filter[%d] id=%u mask=%04x count=%u\n", k, adp->BinFilters[k].EventID,
                   adp->BinFilters[k].Mask, adp->BinFilters[k].Count);
        }

        /* more filters than the table holds: truncated, with a syslog line */
        printf("evs_reg_trunc rc=%ld\n",
               (long)CFE_EVS_Register(filters, 99, CFE_EVS_EventFilter_BINARY));

        /* --- CFE_EVS_SendEvent, through the whole pipeline ------------------------------ */
        /* Re-register with the three filters, then send. Every successful send prints the
         * port line, which carries the formatted text, the app name, the ids and the time. */
        CFE_EVS_Register(filters, 3, CFE_EVS_EventFilter_BINARY);
        printf("evs_send_nullspec rc=%ld\n",
               (long)CFE_EVS_SendEvent(1, CFE_EVS_EventType_INFORMATION, NULL));

        printf("evs_send_plain rc=%ld\n",
               (long)CFE_EVS_SendEvent(1, CFE_EVS_EventType_INFORMATION, "plain text"));
        /* the conversions EVS's own call sites use */
        printf("evs_send_fmt rc=%ld\n",
               (long)CFE_EVS_SendEvent(2, CFE_EVS_EventType_ERROR, "s=%s u=%u d=%d x=%08x",
                                       "name", 7u, -3, 0xbeefu));

        /* a message LONGER than the 122-byte payload: truncated, and marked with '$' */
        printf("evs_send_long rc=%ld\n",
               (long)CFE_EVS_SendEvent(3, CFE_EVS_EventType_INFORMATION,
                                       "%s%s%s%s%s%s%s%s%s%s%s%s%s",
                                       "0123456789", "0123456789", "0123456789", "0123456789",
                                       "0123456789", "0123456789", "0123456789", "0123456789",
                                       "0123456789", "0123456789", "0123456789", "0123456789",
                                       "0123456789"));
        printf("evs_trunc_count %u\n", CFE_EVS_Global.EVS_TlmPkt.Payload.MessageTruncCounter);

        /* event 10 has mask 0x0001: the FIRST send gets through (count 0), the second is
         * filtered because Mask & Count is nonzero */
        printf("evs_filt_first rc=%ld\n",
               (long)CFE_EVS_SendEvent(10, CFE_EVS_EventType_INFORMATION, "filtered id pass 1"));
        printf("evs_filt_second rc=%ld\n",
               (long)CFE_EVS_SendEvent(10, CFE_EVS_EventType_INFORMATION, "filtered id pass 2"));
        /* mask 0 never filters; mask 0xFFFF filters everything after the first */
        printf("evs_filt_mask0 rc=%ld\n",
               (long)CFE_EVS_SendEvent(20, CFE_EVS_EventType_INFORMATION, "mask zero"));
        printf("evs_filt_maskall rc=%ld\n",
               (long)CFE_EVS_SendEvent(30, CFE_EVS_EventType_INFORMATION, "mask all"));
        printf("evs_filt_maskall2 rc=%ld\n",
               (long)CFE_EVS_SendEvent(30, CFE_EVS_EventType_INFORMATION, "mask all again"));

        /* The type switch. This used to be a driver stub answering CFE_EVS_GetTypeEnable;
          * cfe_evs_task.c is translated now, so the real one runs and the switch is the app's own
          * EventTypesActive array -- reached through CFE_EVS_SetTypeEnable, which is also
          * translated. Two more functions inside the comparison for the same two lines. */
        CFE_EVS_SetTypeEnable(CFE_EVS_EventType_INFORMATION, false);
        printf("evs_typeoff rc=%ld\n",
               (long)CFE_EVS_SendEvent(4, CFE_EVS_EventType_INFORMATION, "type disabled"));
        CFE_EVS_SetTypeEnable(CFE_EVS_EventType_INFORMATION, true);

        /* the per-app active flag does the same, one level earlier */
        adp             = EVS_GetAppDataByID(evsid);
        adp->ActiveFlag = false;
        printf("evs_inactive rc=%ld\n",
               (long)CFE_EVS_SendEvent(5, CFE_EVS_EventType_INFORMATION, "app inactive"));
        adp->ActiveFlag = true;

        printf("evs_counters sent=%u app=%u\n",
               CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter, adp->EventCount);

        /* --- the "not registered" path -------------------------------------------------- */
        /* App 2 has never registered, so its first event logs and counts, and its second is
         * silent -- EVS remembers it has already complained about that app. */
        es_set_ctx(2);
        printf("evs_unreg1 rc=%ld\n",
               (long)CFE_EVS_SendEvent(6, CFE_EVS_EventType_ERROR, "from an unregistered app"));
        printf("evs_unreg2 rc=%ld\n",
               (long)CFE_EVS_SendEvent(7, CFE_EVS_EventType_ERROR, "again"));
        printf("evs_unreg_count %u\n", CFE_EVS_Global.EVS_TlmPkt.Payload.UnregisteredAppCounter);
        es_set_ctx(1);

        /* --- SendEventWithAppID and SendTimedEvent -------------------------------------- */
        printf("evs_withid_bad rc=%ld\n",
               (long)CFE_EVS_SendEventWithAppID(8, CFE_EVS_EventType_INFORMATION,
                                                CFE_ES_APPID_C(CFE_ResourceId_FromInteger(99)),
                                                "bad id"));
        printf("evs_withid rc=%ld\n",
               (long)CFE_EVS_SendEventWithAppID(9, CFE_EVS_EventType_INFORMATION, evsid,
                                                "by app id"));
        {
            CFE_TIME_SysTime_t ts;
            ts.Seconds    = 123;
            ts.Subseconds = 456;
            printf("evs_timed rc=%ld\n",
                   (long)CFE_EVS_SendTimedEvent(ts, 11, CFE_EVS_EventType_INFORMATION, "timed"));
        }

        /* --- the squelch bucket --------------------------------------------------------- */
        /* With a burst budget the token count is what decides. Each event costs 1000 and the
         * clock does not move, so a burst of 3 drains to the floor and the next send is
         * refused with CFE_EVS_APP_SQUELCHED.
         *
         * EIGHT iterations, not five. At five the token count walked 2000, 1000, 0, -1000,
         * -2000 and never reached LOWER_THRESHOLD, so a negative control that DOUBLED the floor
         * left this transcript byte-identical -- the clamp was translated and never exercised.
         * Eight reaches -3000 and then stays there, which is the clamp itself. */
        CFE_EVS_Global.EVS_EventBurstMax = 3;
        adp                              = EVS_GetAppDataByID(evsid);
        adp->SquelchTokens               = 3000;
        adp->SquelchedCount              = 0;
        adp->LastSquelchCreditableTime.ticks = 0;
        evs_psp_ns                       = 0;
        for (k = 0; k < 8; k++)
        {
            printf("evs_squelch%d rc=%ld tok=%ld cnt=%u\n", k,
                   (long)CFE_EVS_SendEvent(40 + k, CFE_EVS_EventType_INFORMATION, "burst"),
                   (long)adp->SquelchTokens, adp->SquelchedCount);
        }
        /* move the clock forward a second: 15 events/sec * 1000 ms = 15000 credits, capped at
         * EventBurstMax * 1000 */
        evs_psp_ns = 1000000000LL;
        printf("evs_squelch_credit rc=%ld tok=%ld\n",
               (long)CFE_EVS_SendEvent(50, CFE_EVS_EventType_INFORMATION, "after a second"),
               (long)adp->SquelchTokens);
        CFE_EVS_Global.EVS_EventBurstMax = 0;

        /* --- ResetFilter / ResetAllFilters ---------------------------------------------- */
        adp = EVS_GetAppDataByID(evsid);
        printf("evs_resetf_known rc=%ld count=%u\n", (long)CFE_EVS_ResetFilter(10),
               adp->BinFilters[0].Count);
        printf("evs_resetf_unknown rc=%ld\n", (long)CFE_EVS_ResetFilter(999));
        adp->BinFilters[1].Count = 5;
        adp->BinFilters[2].Count = 6;
        printf("evs_resetall rc=%ld c1=%u c2=%u\n", (long)CFE_EVS_ResetAllFilters(),
               adp->BinFilters[1].Count, adp->BinFilters[2].Count);
        /* both reject an unregistered caller */
        es_set_ctx(2);
        printf("evs_resetf_unreg rc=%ld\n", (long)CFE_EVS_ResetFilter(10));
        printf("evs_resetall_unreg rc=%ld\n", (long)CFE_EVS_ResetAllFilters());
        es_set_ctx(1);

        /* --- the helpers nothing else reaches ------------------------------------------- */
        printf("evs_bitmask bad0=%d badbig=%d ok=%d\n", (int)EVS_IsInvalidBitMask(0, 1),
               (int)EVS_IsInvalidBitMask(0x10, 2), (int)EVS_IsInvalidBitMask(0x5, 3));
        EVS_SetTypes(adp, 0x0, true);
        printf("evs_settypes none=%u\n", EVS_EventArrayToBitMask(adp));
        EVS_SetTypes(adp, CFE_EVS_ALL_EVENT_TYPES_MASK, true);
        printf("evs_settypes all=%u\n", EVS_EventArrayToBitMask(adp));
        EVS_SetTypes(adp, CFE_EVS_DEBUG_BIT | CFE_EVS_ERROR_BIT, false);
        printf("evs_settypes cleared=%u\n", EVS_EventArrayToBitMask(adp));
        EVS_SetTypes(NULL, 0xFF, true); /* the NULL guard */
        printf("evs_settypes nullsafe=%u\n", EVS_EventArrayToBitMask(NULL));

        printf("evs_findid known=%d unknown=%d\n",
               (int)(EVS_FindEventID(20, adp->BinFilters) == &adp->BinFilters[1]),
               (int)(EVS_FindEventID(999, adp->BinFilters) == NULL));

        /* EVS_GetApplicationInfo by name, which is how the ground addresses an app */
        {
            EVS_AppData_t *byname = NULL;
            printf("evs_byname_ok rc=%ld match=%d\n", (long)EVS_GetApplicationInfo(&byname, "CFE_EVS"),
                   (int)(byname == EVS_GetAppDataByID(evsid)));
            printf("evs_byname_unreg rc=%ld null=%d\n",
                   (long)EVS_GetApplicationInfo(&byname, "OTHER_APP"), (int)(byname == NULL));
            printf("evs_byname_nosuch rc=%ld\n", (long)EVS_GetApplicationInfo(&byname, "NOPE"));
        }
    }

    /* --- cfe_evs_log.c -------------------------------------------------------------------- */
    {
        CFE_EVS_LongEventTlm_t   entry;
        CFE_EVS_SetLogModeCmd_t  modecmd;
        CFE_EVS_WriteLogDataFileCmd_t wrcmd;
        int                      k;

        EVS_ClearLog();
        printf("evs_log_clear next=%u count=%u full=%u ovf=%u\n", CFE_EVS_Global.EVS_LogPtr->Next,
               CFE_EVS_Global.EVS_LogPtr->LogCount, CFE_EVS_Global.EVS_LogPtr->LogFullFlag,
               CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter);

        /* fill past the end: 20 entries fill it, the 21st wraps in OVERWRITE mode */
        memset(&entry, 0, sizeof(entry));
        for (k = 0; k < 22; k++)
        {
            entry.Payload.PacketID.EventID = (uint16)(100 + k);
            EVS_AddLog(&entry);
        }
        printf("evs_log_wrap next=%u count=%u full=%u ovf=%u first=%u\n",
               CFE_EVS_Global.EVS_LogPtr->Next, CFE_EVS_Global.EVS_LogPtr->LogCount,
               CFE_EVS_Global.EVS_LogPtr->LogFullFlag,
               CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter,
               CFE_EVS_Global.EVS_LogPtr->LogEntry[0].Payload.PacketID.EventID);

        /* DISCARD mode: the overflow counter still climbs but nothing is written */
        CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_EVS_LogMode_DISCARD;
        entry.Payload.PacketID.EventID     = 777;
        EVS_AddLog(&entry);
        printf("evs_log_discard next=%u ovf=%u at2=%u\n", CFE_EVS_Global.EVS_LogPtr->Next,
               CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter,
               CFE_EVS_Global.EVS_LogPtr->LogEntry[2].Payload.PacketID.EventID);

        /* SetLogModeCmd, both valid modes and one that is not */
        memset(&modecmd, 0, sizeof(modecmd));
        modecmd.Payload.LogMode = CFE_EVS_LogMode_OVERWRITE;
        printf("evs_setmode_ovr rc=%ld mode=%u\n", (long)CFE_EVS_SetLogModeCmd(&modecmd),
               CFE_EVS_Global.EVS_LogPtr->LogMode);
        modecmd.Payload.LogMode = CFE_EVS_LogMode_DISCARD;
        printf("evs_setmode_dis rc=%ld mode=%u\n", (long)CFE_EVS_SetLogModeCmd(&modecmd),
               CFE_EVS_Global.EVS_LogPtr->LogMode);
        modecmd.Payload.LogMode = 7;
        printf("evs_setmode_bad rc=%ld mode=%u\n", (long)CFE_EVS_SetLogModeCmd(&modecmd),
               CFE_EVS_Global.EVS_LogPtr->LogMode);
        modecmd.Payload.LogMode = CFE_EVS_LogMode_OVERWRITE;
        CFE_EVS_SetLogModeCmd(&modecmd);

        /* WriteLogDataFileCmd, through the translated fs module and the simulated file */
        memset(&wrcmd, 0, sizeof(wrcmd));
        strncpy(wrcmd.Payload.LogFilename, "/ram/evs.log", sizeof(wrcmd.Payload.LogFilename) - 1);
        fs_open_fail = 0;
        fs_wr_left   = -1;
        fs_fd        = 0;
        fs_len       = 0;
        fs_pos       = 0;
        printf("evs_wrlog rc=%ld len=%ld\n", (long)CFE_EVS_WriteLogDataFileCmd(&wrcmd), fs_len);
        fs_dump("evs_wrlog_bytes", 16);

        fs_open_fail = 1;
        printf("evs_wrlog_nocreate rc=%ld\n", (long)CFE_EVS_WriteLogDataFileCmd(&wrcmd));
        fs_open_fail = 0;

        fs_wr_left = 4;
        printf("evs_wrlog_hdrfail rc=%ld\n", (long)CFE_EVS_WriteLogDataFileCmd(&wrcmd));

        fs_wr_left = 64;
        printf("evs_wrlog_datafail rc=%ld\n", (long)CFE_EVS_WriteLogDataFileCmd(&wrcmd));
        fs_wr_left = -1;

        printf("evs_printf_lines %d\n", evs_printf_lines);
    }

    /* --- TA's events, through the real EVS -------------------------------------------------
     * The TA block above ran with CFE_EVS_Global zeroed, so every event it sent was dropped
     * before it reached the formatter: the ids and the branch taken were compared, the WORDING
     * was not. Now EVS is standing and app 1 is registered, so running the same commands again
     * puts TA's twenty event strings -- the affinity masks, the file sizes, the status codes,
     * the message ids -- inside the byte-identical comparison. That is the half of the TA
     * translation nothing has checked until now, and the half where the arguments live. */
    {
        CFE_TA_SetTaskAffinityCmd_t setcmd;
        CFE_TA_GetTaskAffinityCmd_t getcmd;
        CFE_TA_QueryAllTasksCmd_t   wrcmd;
        union
        {
            CFE_SB_Buffer_t             Buf;
            CFE_TA_SetTaskAffinityCmd_t Set;
            unsigned char               Bytes[128];
        } sb;

        /* EVS is still registered as app 1 from the block above; make TA the caller of record
         * and clear the filters so nothing is suppressed. */
        es_set_ctx(1);
        CFE_EVS_ResetAllFilters();
        CFE_EVS_Global.EVS_EventBurstMax = 0;
        CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = CFE_EVS_PORT1_BIT;

        ta_cores           = 1;
        ta_evs_register_rc = CFE_SUCCESS;
        sb_queuecreate_rc  = OS_SUCCESS;
        es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
        printf("tae_init rc=%ld\n", (long)CFE_TA_TaskInit());
        printf("tae_noop rc=%ld\n", (long)CFE_TA_NoopCmd(NULL));
        printf("tae_reset rc=%ld\n", (long)CFE_TA_ResetCountersCmd(NULL));

        /* QueryAllTasks: the success line carries the filename, the entry count and the file
         * size, and each failure line carries a status code in a different conversion. */
        memset(&wrcmd, 0, sizeof(wrcmd));
        strncpy(wrcmd.Payload.FileName, "/ram/tasks.dat", sizeof(wrcmd.Payload.FileName) - 1);
        fs_open_fail = 0;
        fs_wr_left   = -1;
        fs_fd        = 0;
        fs_len       = 0;
        fs_pos       = 0;
        printf("tae_qall rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&wrcmd));
        fs_open_fail = 1;
        printf("tae_qall_nocreate rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&wrcmd));
        fs_open_fail = 0;
        fs_wr_left = 4;
        printf("tae_qall_hdrfail rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&wrcmd));
        fs_wr_left = 64;
        printf("tae_qall_wrfail rc=%ld\n", (long)CFE_TA_QueryAllTasksCmd(&wrcmd));
        fs_wr_left = -1;

        /* SetTaskAffinity: the success event prints the mask twice with "0x%016llX", which is
         * the only 64-bit conversion in the whole translation. */
        memset(&setcmd, 0, sizeof(setcmd));
        strncpy(setcmd.Payload.TaskName, "CFE_ES", sizeof(setcmd.Payload.TaskName) - 1);
        setcmd.Payload.AffinityMask[0] = 0x01;
        ta_getid_rc  = OS_SUCCESS;
        ta_setaff_rc = OS_SUCCESS;
        ta_getaff_rc = OS_SUCCESS;
        ta_os_mask   = 0;
        printf("tae_set rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&setcmd));
        ta_setaff_rc = -5;
        printf("tae_set_setfail rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&setcmd));
        ta_setaff_rc = OS_SUCCESS;
        ta_getaff_rc = -6;
        printf("tae_set_getfail rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&setcmd));
        ta_getaff_rc = OS_SUCCESS;
        strncpy(setcmd.Payload.TaskName, "NO_SUCH", sizeof(setcmd.Payload.TaskName) - 1);
        printf("tae_set_notfound rc=%ld\n", (long)CFE_TA_SetTaskAffinityCmd(&setcmd));

        /* GetTaskAffinity: the discrepancy event takes no arguments, the success one takes
         * three. */
        memset(&getcmd, 0, sizeof(getcmd));
        strncpy(getcmd.Payload.TaskName, "CFE_ES", sizeof(getcmd.Payload.TaskName) - 1);
        printf("tae_get rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&getcmd));
        ta_os_mask = 0x02;
        printf("tae_get_diff rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&getcmd));
        ta_getaff_rc = -6;
        printf("tae_get_fail rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&getcmd));
        ta_getaff_rc = OS_SUCCESS;
        strncpy(getcmd.Payload.TaskName, "NO_SUCH", sizeof(getcmd.Payload.TaskName) - 1);
        printf("tae_get_notfound rc=%ld\n", (long)CFE_TA_GetTaskAffinityCmd(&getcmd));

        /* The dispatcher's three events: a bad length, a bad command code and a bad message id.
         * Each prints a message id with a different hex conversion -- %X, %08x and %08X -- and
         * those three spellings are exactly what the formatter had to learn. */
        memset(&sb, 0, sizeof(sb));
        CFE_MSG_Init(CFE_MSG_PTR(sb.Set.CommandHeader), CFE_SB_ValueToMsgId(CFE_TA_CMD_MID),
                     sizeof(CFE_TA_SetTaskAffinityCmd_t));
        CFE_MSG_SetFcnCode(&sb.Buf.Msg, CFE_TA_NOOP_CC);
        printf("tae_len_bad %d\n", (int)CFE_TA_VerifyCmdLength(&sb.Buf.Msg, 9999));
        CFE_MSG_SetFcnCode(&sb.Buf.Msg, 0x7E);
        CFE_TA_ProcessGroundCommand(&sb.Buf, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID));
        printf("tae_badcc done\n");
        CFE_MSG_Init(CFE_MSG_PTR(sb.Set.CommandHeader), CFE_SB_ValueToMsgId(0x1FFF),
                     sizeof(CFE_TA_SetTaskAffinityCmd_t));
        CFE_TA_TaskPipe(&sb.Buf);
        printf("tae_badmid done\n");

        printf("tae_counters cc=%u cec=%u evs=%u printed=%d\n", CFE_TA_Global.CommandCounter,
               CFE_TA_Global.CommandErrorCounter,
               CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter, evs_printf_lines);
    }

    /* --- cfe_evs_task.c and cfe_evs_dispatch.c: EVS AS A TASK -------------------------------
     * The other three sources, and with them the module is complete. EarlyInit takes the event
     * log out of the PSP reset area; TaskInit registers EVS and subscribes; twenty ground
     * commands and a dispatcher route them. Every one of those commands ends in an event, and
     * most of them are CFE_EVS_EventType_DEBUG -- which the DEFAULT type mask has OFF, so the
     * first thing this block does is what a ground operator does: enable DEBUG. That is also why
     * the transcript lost nine lines when cfe_evs_task.c arrived: the driver's old
     * CFE_EVS_GetTypeEnable stub answered "enabled" for every type, and the real one reads the
     * app's own EventTypesActive array. */
    {
        CFE_EVS_BitMaskCmd_Payload_t          *bm;
        CFE_EVS_AppNameCmd_Payload_t          *an;
        CFE_EVS_AppNameBitMaskCmd_Payload_t   *anbm;
        CFE_EVS_AppNameEventIDCmd_Payload_t   *aneid;
        CFE_EVS_AppNameEventIDMaskCmd_Payload_t *aneidm;
        union
        {
            CFE_SB_Buffer_t                 Buf;
            CFE_EVS_EnablePortsCmd_t        Ports;
            CFE_EVS_EnableAppEventTypeCmd_t AppType;
            CFE_EVS_SetFilterCmd_t          Filter;
            CFE_EVS_ResetFilterCmd_t        RstFilter;
            CFE_EVS_EnableAppEventsCmd_t    AppEvt;
            CFE_EVS_SetEventFormatModeCmd_t Fmt;
            CFE_EVS_SetLogModeCmd_t         LogMode;
            CFE_EVS_WriteAppDataFileCmd_t   AppData;
            CFE_EVS_WriteLogDataFileCmd_t   LogData;
            unsigned char                   Bytes[256];
        } c;
        int cc;

        /* --- CFE_EVS_EarlyInit ------------------------------------------------------------ */
        /* the PSP refuses */
        evs_resetarea_rc = -31;
        printf("evt_early_nopsp rc=%ld panics=%ld delay=%ld\n", (long)CFE_EVS_EarlyInit(),
               evs_panics, evs_delay_ms);
        evs_resetarea_rc = CFE_PSP_SUCCESS;
        /* the area is there and is too small for CFE_ES_ResetData_t */
        evs_resetarea_size = 64;
        printf("evt_early_short rc=%ld panics=%ld\n", (long)CFE_EVS_EarlyInit(), evs_panics);
        evs_resetarea_size = 0;
        /* a power-on reset clears the log */
        evs_reset_type = CFE_PSP_RST_TYPE_POWERON;
        memset(&evs_reset_area, 0, sizeof(evs_reset_area));
        printf("evt_early_poweron rc=%ld\n", (long)CFE_EVS_EarlyInit());
        printf("evt_early_state fmt=%u port=%u logmode=%u logen=%u burst=%lu next=%u count=%u\n",
               CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode,
               CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort,
               CFE_EVS_Global.EVS_TlmPkt.Payload.LogMode,
               CFE_EVS_Global.EVS_TlmPkt.Payload.LogEnabled,
               (unsigned long)CFE_EVS_Global.EVS_EventBurstMax,
               CFE_EVS_Global.EVS_LogPtr->Next, CFE_EVS_Global.EVS_LogPtr->LogCount);
        /* a processor reset with a GOOD log restores it; with a bad one clears it */
        evs_reset_type = 1;
        CFE_EVS_Global.EVS_LogPtr->LogMode     = CFE_EVS_LogMode_OVERWRITE;
        CFE_EVS_Global.EVS_LogPtr->LogFullFlag = false;
        CFE_EVS_Global.EVS_LogPtr->Next        = 3;
        CFE_EVS_Global.EVS_LogPtr->LogCount    = 3;
        printf("evt_early_restore rc=%ld next=%u\n", (long)CFE_EVS_EarlyInit(),
               CFE_EVS_Global.EVS_LogPtr->Next);
        CFE_EVS_Global.EVS_LogPtr->LogMode = 99; /* neither OVERWRITE nor DISCARD */
        printf("evt_early_badlog rc=%ld next=%u mode=%u\n", (long)CFE_EVS_EarlyInit(),
               CFE_EVS_Global.EVS_LogPtr->Next, CFE_EVS_Global.EVS_LogPtr->LogMode);

        /* --- CFE_EVS_TaskInit ------------------------------------------------------------- */
        es_set_ctx(1);
        sb_queuecreate_rc = OS_SUCCESS;
        es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
        printf("evt_init rc=%ld appid=%lu\n", (long)CFE_EVS_TaskInit(),
               (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_EVS_Global.EVS_AppID));
        sb_queuecreate_rc = OS_ERROR;
        printf("evt_init_pipefail rc=%ld\n", (long)CFE_EVS_TaskInit());
        sb_queuecreate_rc = OS_SUCCESS;
        es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
        printf("evt_init_subfail rc=%ld\n", (long)CFE_EVS_TaskInit());
        es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
        printf("evt_init_again rc=%ld\n", (long)CFE_EVS_TaskInit());

        /* --- enable DEBUG, so the twenty commands' events are visible -------------------- */
        memset(&c, 0, sizeof(c));
        bm          = &c.Ports.Payload;
        bm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
        printf("evt_enatype rc=%ld\n", (long)CFE_EVS_EnableEventTypeCmd(&c.Ports));
        bm->BitMask = 0x80; /* out of range: only four bits are defined */
        printf("evt_enatype_badmask rc=%ld\n", (long)CFE_EVS_EnableEventTypeCmd(&c.Ports));

        /* --- the simple commands --------------------------------------------------------- */
        printf("evt_noop rc=%ld\n", (long)CFE_EVS_NoopCmd(&c.Buf));
        printf("evt_rstcnt rc=%ld\n", (long)CFE_EVS_ResetCountersCmd(&c.Buf));
        printf("evt_clearlog rc=%ld next=%u\n", (long)CFE_EVS_ClearLogCmd(&c.Buf),
               CFE_EVS_Global.EVS_LogPtr->Next);

        /* --- the ports and the format mode ----------------------------------------------- */
        bm->BitMask = CFE_EVS_PORT2_BIT;
        printf("evt_enaport rc=%ld port=%u\n", (long)CFE_EVS_EnablePortsCmd(&c.Ports),
               CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort);
        printf("evt_disport rc=%ld port=%u\n", (long)CFE_EVS_DisablePortsCmd(&c.Ports),
               CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort);
        bm->BitMask = 0x80;
        printf("evt_enaport_badmask rc=%ld\n", (long)CFE_EVS_EnablePortsCmd(&c.Ports));
        printf("evt_disport_badmask rc=%ld\n", (long)CFE_EVS_DisablePortsCmd(&c.Ports));
        bm->BitMask = CFE_EVS_DEBUG_BIT;
        printf("evt_distype rc=%ld\n", (long)CFE_EVS_DisableEventTypeCmd(&c.Ports));
        bm->BitMask = 0x80;
        printf("evt_distype_badmask rc=%ld\n", (long)CFE_EVS_DisableEventTypeCmd(&c.Ports));
        bm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
        CFE_EVS_EnableEventTypeCmd(&c.Ports);

        memset(&c, 0, sizeof(c));
        c.Fmt.Payload.MsgFormat = CFE_EVS_MsgFormat_SHORT;
        printf("evt_fmt_short rc=%ld mode=%u\n", (long)CFE_EVS_SetEventFormatModeCmd(&c.Fmt),
               CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode);
        c.Fmt.Payload.MsgFormat = CFE_EVS_MsgFormat_LONG;
        printf("evt_fmt_long rc=%ld mode=%u\n", (long)CFE_EVS_SetEventFormatModeCmd(&c.Fmt),
               CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode);
        c.Fmt.Payload.MsgFormat = 9;
        printf("evt_fmt_bad rc=%ld\n", (long)CFE_EVS_SetEventFormatModeCmd(&c.Fmt));

        /* --- the per-app commands --------------------------------------------------------
         * Each of the eight takes an app NAME and runs the same four-way branch on what
         * EVS_GetApplicationInfo says: found, not registered, illegal id, no such app. The
         * driver's CFE_ES_GetAppIDByName answers for "CFE_EVS" and refuses everything else, so
         * three of the four are reachable by name alone. */
        memset(&c, 0, sizeof(c));
        anbm = &c.AppType.Payload;
        strncpy(anbm->AppName, "CFE_EVS", sizeof(anbm->AppName) - 1);
        anbm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
        printf("evt_enaapptype rc=%ld\n", (long)CFE_EVS_EnableAppEventTypeCmd(&c.AppType));
        anbm->BitMask = CFE_EVS_DEBUG_BIT;
        printf("evt_disapptype rc=%ld\n", (long)CFE_EVS_DisableAppEventTypeCmd(&c.AppType));
        anbm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
        CFE_EVS_EnableAppEventTypeCmd(&c.AppType);
        anbm->BitMask = 0x80;
        printf("evt_enaapptype_badmask rc=%ld\n", (long)CFE_EVS_EnableAppEventTypeCmd(&c.AppType));
        printf("evt_disapptype_badmask rc=%ld\n",
               (long)CFE_EVS_DisableAppEventTypeCmd(&c.AppType));
        anbm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
        strncpy(anbm->AppName, "OTHER_APP", sizeof(anbm->AppName) - 1);
        printf("evt_enaapptype_unreg rc=%ld\n", (long)CFE_EVS_EnableAppEventTypeCmd(&c.AppType));
        printf("evt_disapptype_unreg rc=%ld\n",
               (long)CFE_EVS_DisableAppEventTypeCmd(&c.AppType));
        strncpy(anbm->AppName, "NOPE", sizeof(anbm->AppName) - 1);
        printf("evt_enaapptype_nosuch rc=%ld\n", (long)CFE_EVS_EnableAppEventTypeCmd(&c.AppType));

        memset(&c, 0, sizeof(c));
        an = &c.AppEvt.Payload;
        strncpy(an->AppName, "CFE_EVS", sizeof(an->AppName) - 1);
        printf("evt_disappevt rc=%ld active=%u\n", (long)CFE_EVS_DisableAppEventsCmd(&c.AppEvt),
               EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID)->ActiveFlag);
        printf("evt_enaappevt rc=%ld active=%u\n", (long)CFE_EVS_EnableAppEventsCmd(&c.AppEvt),
               EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID)->ActiveFlag);
        printf("evt_rstappcnt rc=%ld\n", (long)CFE_EVS_ResetAppCounterCmd(&c.AppEvt));
        printf("evt_rstallfilt rc=%ld\n", (long)CFE_EVS_ResetAllFiltersCmd(&c.AppEvt));
        strncpy(an->AppName, "OTHER_APP", sizeof(an->AppName) - 1);
        printf("evt_disappevt_unreg rc=%ld\n", (long)CFE_EVS_DisableAppEventsCmd(&c.AppEvt));
        printf("evt_enaappevt_unreg rc=%ld\n", (long)CFE_EVS_EnableAppEventsCmd(&c.AppEvt));
        printf("evt_rstappcnt_unreg rc=%ld\n", (long)CFE_EVS_ResetAppCounterCmd(&c.AppEvt));
        printf("evt_rstallfilt_unreg rc=%ld\n", (long)CFE_EVS_ResetAllFiltersCmd(&c.AppEvt));

        /* --- the filter commands ---------------------------------------------------------- */
        memset(&c, 0, sizeof(c));
        aneidm = &c.Filter.Payload;
        strncpy(aneidm->AppName, "CFE_EVS", sizeof(aneidm->AppName) - 1);
        aneidm->EventID = 77;
        aneidm->Mask    = 0x00ff;
        printf("evt_addfilt rc=%ld\n", (long)CFE_EVS_AddEventFilterCmd(&c.Filter));
        printf("evt_addfilt_dup rc=%ld\n", (long)CFE_EVS_AddEventFilterCmd(&c.Filter));
        aneidm->Mask = 0x000f;
        printf("evt_setfilt rc=%ld\n", (long)CFE_EVS_SetFilterCmd(&c.Filter));
        aneidm->EventID = 999;
        printf("evt_setfilt_noevt rc=%ld\n", (long)CFE_EVS_SetFilterCmd(&c.Filter));
        strncpy(aneidm->AppName, "OTHER_APP", sizeof(aneidm->AppName) - 1);
        printf("evt_setfilt_unreg rc=%ld\n", (long)CFE_EVS_SetFilterCmd(&c.Filter));
        printf("evt_addfilt_unreg rc=%ld\n", (long)CFE_EVS_AddEventFilterCmd(&c.Filter));

        memset(&c, 0, sizeof(c));
        aneid = &c.RstFilter.Payload;
        strncpy(aneid->AppName, "CFE_EVS", sizeof(aneid->AppName) - 1);
        aneid->EventID = 77;
        printf("evt_rstfilt rc=%ld\n", (long)CFE_EVS_ResetFilterCmd(&c.RstFilter));
        printf("evt_delfilt rc=%ld\n", (long)CFE_EVS_DeleteEventFilterCmd(&c.RstFilter));
        printf("evt_delfilt_again rc=%ld\n", (long)CFE_EVS_DeleteEventFilterCmd(&c.RstFilter));
        aneid->EventID = 999;
        printf("evt_rstfilt_noevt rc=%ld\n", (long)CFE_EVS_ResetFilterCmd(&c.RstFilter));
        strncpy(aneid->AppName, "OTHER_APP", sizeof(aneid->AppName) - 1);
        printf("evt_rstfilt_unreg rc=%ld\n", (long)CFE_EVS_ResetFilterCmd(&c.RstFilter));
        printf("evt_delfilt_unreg rc=%ld\n", (long)CFE_EVS_DeleteEventFilterCmd(&c.RstFilter));
        /* fill every slot, then ask for one more */
        memset(&c, 0, sizeof(c));
        aneidm = &c.Filter.Payload;
        strncpy(aneidm->AppName, "CFE_EVS", sizeof(aneidm->AppName) - 1);
        for (cc = 0; cc < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS + 1; cc++)
        {
            aneidm->EventID = (uint16)(200 + cc);
            printf("evt_addfilt[%d] rc=%ld\n", cc, (long)CFE_EVS_AddEventFilterCmd(&c.Filter));
        }

        /* --- the two file commands, through the translated fs module --------------------- */
        memset(&c, 0, sizeof(c));
        strncpy(c.AppData.Payload.AppDataFilename, "/ram/evs_app.dat",
                sizeof(c.AppData.Payload.AppDataFilename) - 1);
        fs_open_fail = 0;
        fs_wr_left   = -1;
        fs_fd        = 0;
        fs_len       = 0;
        fs_pos       = 0;
        printf("evt_wrapp rc=%ld len=%ld\n", (long)CFE_EVS_WriteAppDataFileCmd(&c.AppData),
               fs_len);
        fs_dump("evt_wrapp_bytes", 16);
        fs_open_fail = 1;
        printf("evt_wrapp_nocreate rc=%ld\n", (long)CFE_EVS_WriteAppDataFileCmd(&c.AppData));
        fs_open_fail = 0;
        fs_wr_left   = 4;
        printf("evt_wrapp_hdrfail rc=%ld\n", (long)CFE_EVS_WriteAppDataFileCmd(&c.AppData));
        fs_wr_left = 80;
        printf("evt_wrapp_wrfail rc=%ld\n", (long)CFE_EVS_WriteAppDataFileCmd(&c.AppData));
        fs_wr_left = -1;

        /* --- housekeeping: the packet EVS downlinks ------------------------------------- */
        sb_tx_reset();
        printf("evt_hk rc=%ld tx=%d\n", (long)CFE_EVS_SendHkCmd(&c.Buf), sb_tx_since());
        printf("evt_hk_app0 id=%lu en=%u sent=%u sq=%u\n",
               (unsigned long)CFE_RESOURCEID_TO_ULONG(
                   CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppID),
               CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppEnableStatus,
               CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppMessageSentCounter,
               CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppMessageSquelchedCounter);
        /* entry 1 is the first UNUSED slot, and entries 2.. are what upstream note #10 is
         * about: the clear loop never advances, so they keep the previous cycle's contents. */
        printf("evt_hk_app1 id=%lu  app2 id=%lu\n",
               (unsigned long)CFE_RESOURCEID_TO_ULONG(
                   CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[1].AppID),
               (unsigned long)CFE_RESOURCEID_TO_ULONG(
                   CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[2].AppID));

        /* --- cfe_evs_dispatch.c ---------------------------------------------------------- */
        memset(&c, 0, sizeof(c));
        CFE_MSG_Init(CFE_MSG_PTR(c.Ports.CommandHeader), CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID),
                     sizeof(CFE_EVS_EnablePortsCmd_t));
        printf("evt_len_ok %d\n",
               (int)CFE_EVS_VerifyCmdLength(&c.Buf.Msg, sizeof(CFE_EVS_EnablePortsCmd_t)));
        printf("evt_len_bad %d\n", (int)CFE_EVS_VerifyCmdLength(&c.Buf.Msg, 4242));
        for (cc = 0; cc <= 21; cc++)
        {
            CFE_MSG_SetFcnCode(&c.Buf.Msg, (CFE_MSG_FcnCode_t)cc);
            printf("evt_cc %d:\n", cc);
            CFE_EVS_ProcessGroundCommand(&c.Buf, CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID));
        }
        printf("evt_cc_after cc=%u cec=%u\n", CFE_EVS_Global.EVS_TlmPkt.Payload.CommandCounter,
               CFE_EVS_Global.EVS_TlmPkt.Payload.CommandErrorCounter);
        /* and the packet router: the housekeeping id, the command id, and one that is neither */
        CFE_MSG_SetFcnCode(&c.Buf.Msg, CFE_EVS_NOOP_CC);
        CFE_MSG_SetMsgId(&c.Buf.Msg, CFE_SB_ValueToMsgId(CFE_EVS_SEND_HK_MID));
        printf("evt_pipe_hk:\n");
        CFE_EVS_ProcessCommandPacket(&c.Buf);
        CFE_MSG_SetMsgId(&c.Buf.Msg, CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID));
        CFE_MSG_SetSize(&c.Buf.Msg, sizeof(CFE_EVS_NoopCmd_t));
        printf("evt_pipe_cmd:\n");
        CFE_EVS_ProcessCommandPacket(&c.Buf);
        CFE_MSG_SetMsgId(&c.Buf.Msg, CFE_SB_ValueToMsgId(0x1EEE));
        printf("evt_pipe_unknown:\n");
        CFE_EVS_ProcessCommandPacket(&c.Buf);

        /* --- the log commands and CleanUpApp -------------------------------------------- */
        memset(&c, 0, sizeof(c));
        c.LogMode.Payload.LogMode = CFE_EVS_LogMode_DISCARD;
        printf("evt_setlogmode rc=%ld mode=%u\n", (long)CFE_EVS_SetLogModeCmd(&c.LogMode),
               CFE_EVS_Global.EVS_LogPtr->LogMode);
        printf("evt_cleanup_bad rc=%ld\n", (long)CFE_EVS_CleanUpApp(99));
        printf("evt_cleanup rc=%ld used=%u\n", (long)CFE_EVS_CleanUpApp(1),
               EVS_AppDataIsUsed(EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID)));

        /* --- cfe_evs_objtab.c ------------------------------------------------------------ */
        printf("evt_objtab %s %d %d %d %lu %lu\n", CFE_EVS_ModuleEntry.Name,
               (int)(CFE_EVS_ModuleEntry.EarlyInit == NULL),
               (int)(CFE_EVS_ModuleEntry.TaskMain == NULL),
               (int)(CFE_EVS_ModuleEntry.AppCleanupCb == NULL),
               (unsigned long)CFE_EVS_ModuleEntry.Priority,
               (unsigned long)CFE_EVS_ModuleEntry.StackSize);
    }

    /* --- cfe_time_task.c, cfe_time_tone.c, cfe_time_dispatch.c, cfe_time_objtab.c ---------
     *
     * TIME AS A TASK, and before this block the module was only ever reached SIDEWAYS: EVS and
     * TA housekeeping call CFE_SB_TimeStampMsg, which calls CFE_TIME_GetTime, and CFE_TIME_Print
     * rendered the timestamps. So cfe_time_api.c and cfe_time_utils.c were gated for coverage,
     * signatures, constants and byte layout while the transcript exercised a handful of their
     * functions. The three sources below are the module's own behaviour, and they are the ones
     * where getting it wrong does not look like a crash.
     *
     * THE LOCAL CLOCK IS A VARIABLE IN THIS FILE (evs_psp_ns, read by CFE_PSP_GetTime), so every
     * number here is determined. That matters more for TIME than anywhere else in this gate:
     * tone validation is a COMPARISON of two latched clock values against a window, so a
     * wall-clock would make the answers un-pinnable. */
    {
        union
        {
            CFE_SB_Buffer_t                 Buf;
            CFE_TIME_NoopCmd_t              Noop;
            CFE_TIME_ResetCountersCmd_t     Reset;
            CFE_TIME_SendDiagnosticCmd_t    Diag;
            CFE_TIME_SetStateCmd_t          State;
            CFE_TIME_SetSourceCmd_t         Source;
            CFE_TIME_SetSignalCmd_t         Signal;
            CFE_TIME_AddDelayCmd_t          AddDelay;
            CFE_TIME_SetTimeCmd_t           SetTime;
            CFE_TIME_SetMETCmd_t            SetMET;
            CFE_TIME_SetSTCFCmd_t           SetSTCF;
            CFE_TIME_SetLeapSecondsCmd_t    SetLeaps;
            CFE_TIME_AddAdjustCmd_t         AddAdj;
            CFE_TIME_AddOneHzAdjustmentCmd_t Add1Hz;
            CFE_TIME_SendHkCmd_t            Hk;
            CFE_TIME_OneHzCmd_t             OneHz;
            CFE_TIME_ToneSignalCmd_t        ToneSig;
            CFE_TIME_ToneDataCmd_t          ToneData;
            CFE_TIME_FakeToneCmd_t          ToneSend;
            unsigned char                   raw[256];
        } tc;
        volatile CFE_TIME_ReferenceState_t *rs;

        time_binsem_rc    = OS_SUCCESS;
        time_childtask_rc = CFE_SUCCESS;
        time_tb_rc        = OS_ERROR;
        time_timeradd_rc  = OS_SUCCESS;
        time_timerset_rc  = OS_SUCCESS;

        /* --- cfe_time_task.c: EarlyInit is CFE_TIME_InitData ------------------------------ */
        printf("tim_earlyinit rc=%ld\n", (long)CFE_TIME_EarlyInit());
        rs = CFE_TIME_GetReferenceState();
        printf("tim_init src=%d sig=%d fly=%d vmet=%lu minel=%lu maxel=%lu\n",
               (int)CFE_TIME_Global.ClockSource, (int)CFE_TIME_Global.ClockSignal,
               (int)CFE_TIME_Global.ServerFlyState, (unsigned long)CFE_TIME_Global.VirtualMET,
               (unsigned long)CFE_TIME_Global.MinElapsed,
               (unsigned long)CFE_TIME_Global.MaxElapsed);
        printf("tim_init2 maxlocal=%lu.%lu over=%lu under=%lu setstate=%d flystate=%d\n",
               (unsigned long)CFE_TIME_Global.MaxLocalClock.Seconds,
               (unsigned long)CFE_TIME_Global.MaxLocalClock.Subseconds,
               (unsigned long)CFE_TIME_Global.ToneOverLimit,
               (unsigned long)CFE_TIME_Global.ToneUnderLimit,
               (int)rs->ClockSetState, (int)rs->ClockFlyState);

        /* --- cfe_time_task.c: TaskInit, and its five failure paths ------------------------
         * Each of the five is reached by making exactly one stub fail, and each returns a
         * DIFFERENT status -- which is the property worth pinning, because a TaskInit that
         * returned CFE_SUCCESS from a failed semaphore create would start two child tasks that
         * pend on nothing. */
        /* The statuses print as SIGNED DECIMAL, not %08lX. cFE's error codes are negative
         * int32, so %lX sign-extends to sixteen digits on this host and the HolyC half would
         * have to reproduce that width rule exactly to match -- a transcript difference that
         * would be about printf, not about the translation. */
        time_binsem_rc = OS_ERROR;
        printf("tim_init_semfail rc=%ld sems=%ld\n", (long)CFE_TIME_TaskInit(), time_sems_created);
        time_binsem_rc    = OS_SUCCESS;
        time_childtask_rc = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
        printf("tim_init_taskfail rc=%ld tasks=%ld\n", (long)CFE_TIME_TaskInit(), time_childtasks);
        time_childtask_rc = CFE_SUCCESS;
        sb_queuecreate_rc = OS_ERROR;
        printf("tim_init_pipefail rc=%ld\n", (long)CFE_TIME_TaskInit());
        sb_queuecreate_rc = OS_SUCCESS;
        es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
        printf("tim_init_subfail rc=%ld subs=%u\n", (long)CFE_TIME_TaskInit(),
               CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
        es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
        printf("tim_init rc=%ld sems=%ld tasks=%ld subs=%u tb=%ld timers=%ld\n",
               (long)CFE_TIME_TaskInit(), time_sems_created, time_childtasks,
               CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse,
               time_tb_lookups, time_timer_adds);
        /* ...and again with a timebase present, which is the only way OS_TimerAdd/OS_TimerSet
         * are reached at all. */
        time_tb_rc = OS_SUCCESS;
        printf("tim_init_tb rc=%ld adds=%ld sets=%ld\n", (long)CFE_TIME_TaskInit(),
               time_timer_adds, time_timer_sets);
        time_timerset_rc = OS_ERROR;
        printf("tim_init_tbsetfail rc=%ld sets=%ld\n", (long)CFE_TIME_TaskInit(),
               time_timer_sets);
        time_timerset_rc = OS_SUCCESS;
        time_tb_rc       = OS_ERROR;

        /* --- cfe_time_tone.c: the 1Hz tone interrupt -------------------------------------
         * A tone is VALID when it lands about one second after the previous one, and the window
         * is ToneUnderLimit..ToneOverLimit in subseconds. Three tones: one that establishes the
         * previous latch, one a clean second later, and one only half a second later. */
        /* ONE SECOND IS 10,000,000 TICKS, not 1,000,000,000: OS_TIME_TICKS_PER_SECOND is 1e7
         * because a tick is 100 ns (docs/CFS_PLAN.md -- the constant the enum-blind
         * check_constants.py was hiding). The first draft of this block stepped by 1e9 and every
         * tone came back INVALID with the window never reached, which looked like a translation
         * bug and was an arithmetic one in the DRIVER. Everything here also stays under
         * MaxLocalClock, 27 seconds, because past that the local clock rolls over and
         * TimeSinceTone stops meaning what the names say. */
        evs_psp_ns = 10000000; /* 1.0 s */
        CFE_TIME_Tone1HzISR();
        printf("tim_tone1 int=%lu err=%lu vmet=%lu good=%d\n",
               (unsigned long)CFE_TIME_Global.ToneIntCounter,
               (unsigned long)CFE_TIME_Global.ToneIntErrorCounter,
               (unsigned long)CFE_TIME_Global.VirtualMET, (int)CFE_TIME_Global.IsToneGood);
        evs_psp_ns += 10000000; /* 2.0 s -- a clean second after the last tone */
        CFE_TIME_Tone1HzISR();
        printf("tim_tone2 int=%lu err=%lu vmet=%lu good=%d gives=%ld\n",
               (unsigned long)CFE_TIME_Global.ToneIntCounter,
               (unsigned long)CFE_TIME_Global.ToneIntErrorCounter,
               (unsigned long)CFE_TIME_Global.VirtualMET, (int)CFE_TIME_Global.IsToneGood,
               time_sem_gives);
        evs_psp_ns += 5000000; /* 2.5 s -- only half a second, so INVALID */
        CFE_TIME_Tone1HzISR();
        printf("tim_tone_early int=%lu err=%lu vmet=%lu good=%d\n",
               (unsigned long)CFE_TIME_Global.ToneIntCounter,
               (unsigned long)CFE_TIME_Global.ToneIntErrorCounter,
               (unsigned long)CFE_TIME_Global.VirtualMET, (int)CFE_TIME_Global.IsToneGood);

        /* --- cfe_time_tone.c: ToneSend builds the "time at the tone" packet -------------- */
        CFE_TIME_ToneSend();
        printf("tim_tonesend internal=%lu met=%lu.%lu stcf=%lu.%lu leaps=%d state=%d\n",
               (unsigned long)CFE_TIME_Global.InternalCount,
               (unsigned long)CFE_TIME_Global.ToneDataCmd.Payload.AtToneMET.Seconds,
               (unsigned long)CFE_TIME_Global.ToneDataCmd.Payload.AtToneMET.Subseconds,
               (unsigned long)CFE_TIME_Global.ToneDataCmd.Payload.AtToneSTCF.Seconds,
               (unsigned long)CFE_TIME_Global.ToneDataCmd.Payload.AtToneSTCF.Subseconds,
               (int)CFE_TIME_Global.ToneDataCmd.Payload.AtToneLeapSeconds,
               (int)CFE_TIME_Global.ToneDataCmd.Payload.AtToneState);

        /* --- cfe_time_tone.c: ToneData, ToneVerify and the DUPLICATE REJECTION ------------
         * The second call passes the IDENTICAL pair, and NASA's two function-static PrevTime1 /
         * PrevTime2 are what notice. That is the only place in TIME whose correctness depends on
         * a static local keeping its value between calls, so the match counter not moving on the
         * second call is what says the statics work (tests/exec/cases/e_static_local_class_zero.hc
         * gates the compiler property itself). */
        CFE_TIME_ToneData(&CFE_TIME_Global.ToneDataCmd.Payload);
        printf("tim_tonedata data=%lu match=%lu matcherr=%lu pend=%lu.%lu pstate=%d\n",
               (unsigned long)CFE_TIME_Global.ToneDataCounter,
               (unsigned long)CFE_TIME_Global.ToneMatchCounter,
               (unsigned long)CFE_TIME_Global.ToneMatchErrorCounter,
               (unsigned long)CFE_TIME_Global.PendingMET.Seconds,
               (unsigned long)CFE_TIME_Global.PendingMET.Subseconds,
               (int)CFE_TIME_Global.PendingState);
        CFE_TIME_ToneData(&CFE_TIME_Global.ToneDataCmd.Payload);
        printf("tim_tonedup data=%lu match=%lu matcherr=%lu\n",
               (unsigned long)CFE_TIME_Global.ToneDataCounter,
               (unsigned long)CFE_TIME_Global.ToneMatchCounter,
               (unsigned long)CFE_TIME_Global.ToneMatchErrorCounter);
        CFE_TIME_ToneSignal();
        printf("tim_tonesig sig=%lu\n", (unsigned long)CFE_TIME_Global.ToneSignalCounter);

        /* --- cfe_time_tone.c: the local 1Hz ISR and the two child-task loops -------------- */
        CFE_TIME_Local1HzISR();
        printf("tim_local1hz lint=%lu gives=%ld\n",
               (unsigned long)CFE_TIME_Global.LocalIntCounter, time_sem_gives);
        time_sem_take_budget = 2;
        CFE_TIME_Tone1HzTask();
        printf("tim_tonetask tasks=%lu takes=%ld\n",
               (unsigned long)CFE_TIME_Global.ToneTaskCounter, time_sem_takes);
        time_sem_take_budget = 2;
        CFE_TIME_Local1HzTask();
        printf("tim_localtask tasks=%lu takes=%ld autofly=%d\n",
               (unsigned long)CFE_TIME_Global.LocalTaskCounter, time_sem_takes,
               (int)CFE_TIME_Global.AutoStartFly);

        /* --- cfe_time_tone.c: Local1HzStateMachine enters FLYWHEEL -----------------------
         * CFE_PLATFORM_TIME_CFG_START_FLY is 2 seconds since the last tone, so the clock jumps
         * five seconds forward and the state machine has to notice by itself. */
        evs_psp_ns += 30000000; /* 5.5 s: 3 s since the tone, past START_FLY (2) */
        CFE_TIME_Local1HzStateMachine();
        rs = CFE_TIME_GetReferenceState();
        printf("tim_fly fly=%d autofly=%d serverfly=%d\n", (int)rs->ClockFlyState,
               (int)CFE_TIME_Global.AutoStartFly, (int)CFE_TIME_Global.ServerFlyState);
        /* ...and LATCH_FLY (8 s) rolls the time-at-tone forward while flywheeling. */
        evs_psp_ns += 90000000; /* 14.5 s: 12 s since the tone, past LATCH_FLY (8) */
        CFE_TIME_Local1HzStateMachine();
        rs = CFE_TIME_GetReferenceState();
        printf("tim_fly_latch met=%lu.%lu latch=%lu.%lu\n",
               (unsigned long)rs->AtToneMET.Seconds, (unsigned long)rs->AtToneMET.Subseconds,
               (unsigned long)rs->AtToneLatch.Seconds,
               (unsigned long)rs->AtToneLatch.Subseconds);

        /* --- cfe_time_tone.c: NotifyTimeSynchApps calls through a function pointer -------- */
        CFE_TIME_Global.SynchCallback[0].Ptr = TimeSynchProbe;
        CFE_TIME_Global.IsToneGood           = false;
        CFE_TIME_NotifyTimeSynchApps();
        printf("tim_synch_badtone calls=%ld\n", time_synch_calls);
        CFE_TIME_Global.IsToneGood = true;
        CFE_TIME_NotifyTimeSynchApps();
        printf("tim_synch calls=%ld\n", time_synch_calls);
        CFE_TIME_Global.SynchCallback[0].Ptr = NULL;

        /* --- cfe_time_dispatch.c: the GROUND COMMANDS ------------------------------------
         * Two levels of routing, and the counters are what tell them apart: an unrecognised
         * MESSAGE ID is an event and nothing else, while an unrecognised COMMAND CODE and a
         * wrong LENGTH both bump CommandErrorCounter. */
        CFE_TIME_Global.CommandCounter      = 0;
        CFE_TIME_Global.CommandErrorCounter = 0;
        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_NoopCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_NOOP_CC);
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_noop ok=%u err=%u\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter);

        /* a recognised code with the WRONG length */
        CFE_MSG_SetSize(&tc.Buf.Msg, sizeof(CFE_TIME_NoopCmd_t) + 4);
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_badlen ok=%u err=%u\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter);

        /* an unrecognised command code */
        CFE_MSG_SetSize(&tc.Buf.Msg, sizeof(CFE_TIME_NoopCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, 99);
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_badcc ok=%u err=%u\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter);

        /* an unrecognised MESSAGE id: an event, and NEITHER counter moves */
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(0x18FF), sizeof(CFE_TIME_NoopCmd_t));
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_badmid ok=%u err=%u\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter);

        /* the four non-ground message ids this task subscribes to */
        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_SEND_HK_MID),
                     sizeof(CFE_TIME_SendHkCmd_t));
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_hk ok=%u err=%u transmits=%d\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter, sb_tx_since());
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_TONE_CMD_MID),
                     sizeof(CFE_TIME_ToneSignalCmd_t));
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_tonesig sig=%lu\n", (unsigned long)CFE_TIME_Global.ToneSignalCounter);
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_SEND_CMD_MID),
                     sizeof(CFE_TIME_FakeToneCmd_t));
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_tonesend internal=%lu\n", (unsigned long)CFE_TIME_Global.InternalCount);
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_ONEHZ_CMD_MID),
                     sizeof(CFE_TIME_OneHzCmd_t));
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_cmd_onehz lint=%lu int=%lu err=%lu\n",
               (unsigned long)CFE_TIME_Global.LocalIntCounter,
               (unsigned long)CFE_TIME_Global.ToneIntCounter,
               (unsigned long)CFE_TIME_Global.ToneIntErrorCounter);

        /* --- cfe_time_task.c: the SERVER commands this build really executes -------------- */
        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_SetLeapSecondsCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_SET_LEAP_SECONDS_CC);
        tc.SetLeaps.Payload.LeapSeconds = 37;
        CFE_TIME_TaskPipe(&tc.Buf);
        rs = CFE_TIME_GetReferenceState();
        printf("tim_setleaps ok=%u leaps=%d\n", CFE_TIME_Global.CommandCounter,
               (int)rs->AtToneLeapSeconds);

        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_SetMETCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_SET_MET_CC);
        tc.SetMET.Payload.Seconds      = 1000;
        tc.SetMET.Payload.MicroSeconds = 500000;
        CFE_TIME_TaskPipe(&tc.Buf);
        rs = CFE_TIME_GetReferenceState();
        printf("tim_setmet ok=%u met=%lu.%lu\n", CFE_TIME_Global.CommandCounter,
               (unsigned long)rs->AtToneMET.Seconds, (unsigned long)rs->AtToneMET.Subseconds);
        /* and the rejected form: a microseconds value that is not microseconds */
        tc.SetMET.Payload.MicroSeconds = 1000000;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_setmet_bad ok=%u err=%u\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter);

        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_SetStateCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_SET_STATE_CC);
        tc.State.Payload.ClockState = CFE_TIME_ClockState_VALID;
        CFE_TIME_TaskPipe(&tc.Buf);
        rs = CFE_TIME_GetReferenceState();
        printf("tim_setstate ok=%u setstate=%d\n", CFE_TIME_Global.CommandCounter,
               (int)rs->ClockSetState);
        tc.State.Payload.ClockState = 99;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_setstate_bad err=%u\n", CFE_TIME_Global.CommandErrorCounter);

        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_AddOneHzAdjustmentCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_ADD_ONE_HZ_ADJUSTMENT_CC);
        tc.Add1Hz.Payload.Seconds    = 1;
        tc.Add1Hz.Payload.Subseconds = 0x20000000;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_add1hz ok=%u adj=%lu.%lu dir=%d\n", CFE_TIME_Global.CommandCounter,
               (unsigned long)CFE_TIME_Global.OneHzAdjust.Seconds,
               (unsigned long)CFE_TIME_Global.OneHzAdjust.Subseconds,
               (int)CFE_TIME_Global.OneHzDirection);
        /* the 1Hz adjustment is APPLIED by the state machine, not by the command */
        CFE_TIME_Local1HzStateMachine();
        rs = CFE_TIME_GetReferenceState();
        printf("tim_1hz_applied stcf=%lu.%lu\n", (unsigned long)rs->AtToneSTCF.Seconds,
               (unsigned long)rs->AtToneSTCF.Subseconds);
        CFE_TIME_Global.OneHzAdjust.Seconds    = 0;
        CFE_TIME_Global.OneHzAdjust.Subseconds = 0;

        /* --- cfe_time_task.c: the four commands this CONFIGURATION disables ---------------
         * SetSource and SetSignal need CFE_PLATFORM_TIME_CFG_SOURCE / _SIGNAL, and the two delay
         * commands need _CLIENT. All three are 0 here, so the branch that runs is NASA's
         * "invalid without ..." one -- which still COUNTS the command and reports it. That
         * branch is the one this build exercises, and it is easy to mistake for unimplemented. */
        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_SetSourceCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_SET_SOURCE_CC);
        tc.Source.Payload.TimeSource = CFE_TIME_SourceSelect_EXTERNAL;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_setsource_cfg ok=%u err=%u\n", CFE_TIME_Global.CommandCounter,
               CFE_TIME_Global.CommandErrorCounter);
        tc.Source.Payload.TimeSource = 99;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_setsource_bad err=%u\n", CFE_TIME_Global.CommandErrorCounter);

        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_SetSignalCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_SET_SIGNAL_CC);
        tc.Signal.Payload.ToneSource = CFE_TIME_ToneSignalSelect_REDUNDANT;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_setsignal_cfg err=%u\n", CFE_TIME_Global.CommandErrorCounter);

        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_AddDelayCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_ADD_DELAY_CC);
        tc.AddDelay.Payload.Seconds      = 0;
        tc.AddDelay.Payload.MicroSeconds = 1000;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_adddelay_cfg err=%u\n", CFE_TIME_Global.CommandErrorCounter);
        tc.AddDelay.Payload.MicroSeconds = 1000000;
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_adddelay_bad err=%u\n", CFE_TIME_Global.CommandErrorCounter);

        /* --- cfe_time_task.c: diagnostics and ResetCounters ------------------------------ */
        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_SendDiagnosticCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_SEND_DIAGNOSTIC_CC);
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_diag ok=%u atmet=%lu.%lu leaps=%d state=%d\n",
               CFE_TIME_Global.CommandCounter,
               (unsigned long)CFE_TIME_Global.DiagPacket.Payload.AtToneMET.Seconds,
               (unsigned long)CFE_TIME_Global.DiagPacket.Payload.AtToneMET.Subseconds,
               (int)CFE_TIME_Global.DiagPacket.Payload.AtToneLeapSeconds,
               (int)CFE_TIME_Global.DiagPacket.Payload.ClockStateAPI);

        memset(&tc, 0, sizeof(tc));
        CFE_MSG_Init(&tc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID),
                     sizeof(CFE_TIME_ResetCountersCmd_t));
        CFE_MSG_SetFcnCode(&tc.Buf.Msg, CFE_TIME_RESET_COUNTERS_CC);
        CFE_TIME_TaskPipe(&tc.Buf);
        printf("tim_reset ok=%u err=%u tone=%lu toneerr=%lu int=%lu internal=%lu\n",
               CFE_TIME_Global.CommandCounter, CFE_TIME_Global.CommandErrorCounter,
               (unsigned long)CFE_TIME_Global.ToneMatchCounter,
               (unsigned long)CFE_TIME_Global.ToneMatchErrorCounter,
               (unsigned long)CFE_TIME_Global.ToneIntCounter,
               (unsigned long)CFE_TIME_Global.InternalCount);

        /* --- cfe_sb_init.c and cfe_sb_buf.c: SB's BUFFER LIFETIME --------------------------
         *
         * The whole of cfe_sb_buf.c is one invariant: a buffer is freed when the LAST reference
         * to it goes away. A message transmitted to three subscribed pipes is ONE buffer with
         * UseCount 3, and the third release is what returns it to the pool. The pool on this
         * side is a real bump allocator for that reason -- a stub handing back one address would
         * make the accounting agree with itself and prove nothing.
         *
         * The tracking list is a circular doubly-linked list whose EMPTY state points at itself,
         * which is what removes every null check from Add and Remove. The identity comparisons
         * below are how that is observable: "is this node its own next" is the empty test. */
        {
            CFE_SB_BufferD_t      *b1;
            CFE_SB_BufferD_t      *b2;
            CFE_SB_DestinationD_t *d1;
            CFE_SB_MsgId_t         sbmid = CFE_SB_INVALID_MSG_ID;
            size_t                 sbsz  = 0;

            printf("sb_earlyinit rc=%ld pools=%ld gets=%ld subrep=%u\n", (long)CFE_SB_EarlyInit(),
                   es_pool_creates(), es_pool_gets(), (unsigned int)CFE_SB_Global.SubscriptionReporting);
            printf("sb_init_lists intransit_self=%d zerocopy_self=%d\n",
                   (int)(CFE_SB_Global.InTransitList.Next == &CFE_SB_Global.InTransitList &&
                         CFE_SB_Global.InTransitList.Prev == &CFE_SB_Global.InTransitList),
                   (int)(CFE_SB_Global.ZeroCopyList.Next == &CFE_SB_Global.ZeroCopyList &&
                         CFE_SB_Global.ZeroCopyList.Prev == &CFE_SB_Global.ZeroCopyList));
            /* %08lx, not %lX: the HolyC half prints through Hx8, which is eight LOWERCASE
             * digits with no width choice. The format is this driver's own, so it moves to meet
             * the helper rather than the helper growing a width argument it has no other use
             * for. */
            printf("sb_init_pipe lastpipe=0x%08lx\n",
                   (unsigned long)CFE_ResourceId_ToInteger(CFE_SB_Global.LastPipeId));
            CFE_MSG_GetMsgId(CFE_MSG_PTR(CFE_SB_Global.StatTlmMsg.TelemetryHeader), &sbmid);
            CFE_MSG_GetSize(CFE_MSG_PTR(CFE_SB_Global.StatTlmMsg.TelemetryHeader), &sbsz);
            printf("sb_init_stats mid=0x%08x size=%u\n",
                   (unsigned int)CFE_SB_MsgIdToValue(sbmid), (unsigned int)sbsz);

            /* The two failure paths, each by failing exactly one call. The mutex one returns
             * CFE_STATUS_EXTERNAL_RESOURCE_FAIL rather than OSAL's own code, which is the thing
             * worth pinning: EarlyInit translates OSAL failures into cFE ones. */
            fs_mut_create_rc = OS_ERROR;
            printf("sb_earlyinit_mutexfail rc=%ld\n", (long)CFE_SB_EarlyInit());
            fs_mut_create_rc = OS_SUCCESS;
            /* THE POOL-CREATE FAILURE PATH IS NOT DRIVEN, and the reason is a real limit on
             * this whole method rather than a gap in the driver. NASA's own diagnostic is
             *   CFE_ES_WriteToSysLog("%s: PoolCreate failed for SB Buffers, gave adr 0x%lx,..."
             * and that %lx is the PARTITION'S ADDRESS. This gate compares a transcript from
             * NASA's C on the host against the translation running under QEMU, in a different
             * address space, so a line carrying a pointer value cannot agree no matter how
             * correct both sides are -- and NASA's C is compiled UNMODIFIED here, so the format
             * is not ours to change. The mutex path above is driven because its diagnostic
             * carries only an integer. docs/CFS_PLAN.md records the constraint. */

            /* AND THIS CALL IS LOAD-BEARING. The mutex-failure run above returns EARLY, before
             * CFE_SB_InitBuffers -- so it leaves the global MEMSET AND ABANDONED, with both
             * tracking-list heads NULL rather than pointing at themselves. The next
             * CFE_SB_TrackingListAdd then dereferences NULL. It segfaulted exactly that way once:
             * the first version of this block had the restore here as an afterthought to the
             * pool-failure step, and removing that step took the restore with it. */
            CFE_SB_EarlyInit();

            /* A buffer. AllocatedSize is the request PLUS the descriptor header, which is what
             * CFE_SB_BUFFERD_CONTENT_OFFSET is for, and the HolyC side spells that number out
             * because it has no offsetof -- so these two numbers agreeing is the check that the
             * spelled-out 48 is right. */
            b1 = CFE_SB_GetBufferFromPool(100);
            printf("sb_getbuf nonnull=%d use=%u alloc=%lu inuse=%u peak=%u mem=%u\n",
                   (int)(b1 != NULL), (unsigned int)b1->UseCount, (unsigned long)b1->AllocatedSize,
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse,
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.PeakSBBuffersInUse,
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
            printf("sb_getbuf_link singleton=%d\n",
                   (int)(b1->Link.Next == &b1->Link && b1->Link.Prev == &b1->Link));

            /* The tracking list, observed by identity rather than by a count. */
            CFE_SB_TrackingListAdd(&CFE_SB_Global.InTransitList, &b1->Link);
            printf("sb_listadd head_next_b1=%d b1_next_head=%d b1_prev_head=%d\n",
                   (int)(CFE_SB_Global.InTransitList.Next == &b1->Link),
                   (int)(b1->Link.Next == &CFE_SB_Global.InTransitList),
                   (int)(b1->Link.Prev == &CFE_SB_Global.InTransitList));
            b2 = CFE_SB_GetBufferFromPool(200);
            CFE_SB_TrackingListAdd(&CFE_SB_Global.InTransitList, &b2->Link);
            printf("sb_listadd2 head_prev_b2=%d b1_next_b2=%d inuse=%u mem=%u\n",
                   (int)(CFE_SB_Global.InTransitList.Prev == &b2->Link),
                   (int)(b1->Link.Next == &b2->Link),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse,
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
            CFE_SB_TrackingListRemove(&b1->Link);
            printf("sb_listremove head_next_b2=%d b1_singleton=%d\n",
                   (int)(CFE_SB_Global.InTransitList.Next == &b2->Link),
                   (int)(b1->Link.Next == &b1->Link && b1->Link.Prev == &b1->Link));

            /* THREE REFERENCES, THREE RELEASES, and the pool sees exactly one free -- on the
             * third. b2 is still on the in-transit list, so the free path also has to take it
             * off, which is why ReturnBufferToPool calls TrackingListRemove unconditionally. */
            CFE_SB_IncrBufUseCnt(b2);
            CFE_SB_IncrBufUseCnt(b2);
            printf("sb_use3 use=%u puts=%ld\n", (unsigned int)b2->UseCount, es_pool_puts());
            CFE_SB_DecrBufUseCnt(b2);
            printf("sb_use2 use=%u puts=%ld inuse=%u\n", (unsigned int)b2->UseCount, es_pool_puts(),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
            CFE_SB_DecrBufUseCnt(b2);
            printf("sb_use1 use=%u puts=%ld inuse=%u\n", (unsigned int)b2->UseCount, es_pool_puts(),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
            CFE_SB_DecrBufUseCnt(b2);
            printf("sb_use0 puts=%ld inuse=%u mem=%u head_self=%d\n", es_pool_puts(),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse,
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.MemInUse,
                   (int)(CFE_SB_Global.InTransitList.Next == &CFE_SB_Global.InTransitList));

            /* The 0x7FFF ceiling: NASA leaves the top bit of a uint16 alone, so a count that has
             * run away stops climbing instead of wrapping to zero and freeing a live buffer. */
            b1->UseCount = 0x7FFE;
            CFE_SB_IncrBufUseCnt(b1);
            printf("sb_use_below use=%u\n", (unsigned int)b1->UseCount);
            CFE_SB_IncrBufUseCnt(b1);
            printf("sb_use_ceiling use=%u\n", (unsigned int)b1->UseCount);
            /* ...and a decrement at zero does nothing, rather than wrapping to 0xFFFF */
            b1->UseCount = 0;
            CFE_SB_DecrBufUseCnt(b1);
            printf("sb_use_floor use=%u puts=%ld\n", (unsigned int)b1->UseCount, es_pool_puts());

            /* Destination blocks. MemInUse follows the POOL's returned size, not the requested
             * one, because a real pool rounds up to a block size. */
            d1 = CFE_SB_GetDestinationBlk();
            printf("sb_getdest nonnull=%d mem=%u\n", (int)(d1 != NULL),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
            printf("sb_putdest rc=%ld mem=%u\n", (long)CFE_SB_PutDestinationBlk(d1),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
            printf("sb_putdest_null rc=%ld\n", (long)CFE_SB_PutDestinationBlk(NULL));

            /* And the allocation failure path: a null back, and NO counter moved.
             *
             * EXHAUSTING THE TAIL IS NOT THE SAME AS AN EMPTY POOL, and the two lines below are
             * the difference. A 156-byte buffer request fails: no 156-byte block is on the free
             * stack and there is no room to create one. A 32-byte DESTINATION request SUCCEEDS,
             * because sb_putdest above returned a 32-byte block and the real pool RECYCLES it.
             *
             * The simulated bump allocator would have returned NULL for both -- it never
             * reused anything. The second line was called sb_getdest_fail and asserted a
             * failure that stopped happening the moment NASA's pool was gated; it reports what
             * it observes now, which is a better fact than the one it used to assert. */
            es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
            printf("sb_getbuf_fail null=%d inuse=%u\n",
                   (int)(CFE_SB_GetBufferFromPool(100) == NULL),
                   (unsigned int)CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
            printf("sb_getdest_recycled null=%d\n", (int)(CFE_SB_GetDestinationBlk() == NULL));
            es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
        }

        /* --- cfe_sb_priv.c: the pipe table, the destination list, the recursion guard ------
         *
         * Everything here is reachable WITHOUT a pipe existing, which is the half of
         * cfe_sb_priv.c that does not depend on cfe_sb_api.c. The transaction EXECUTION paths
         * need real pipes and queues and come with api.c. */
        {
            CFE_SB_PipeD_t           *pd;
            CFE_SB_DestinationD_t     d1;
            CFE_SB_DestinationD_t     d2;
            CFE_SB_DestinationD_t     d3;
            CFE_SBR_RouteId_t         rid;
            CFE_SB_TransmitTxn_State_t ttxn;
            CFE_SB_ReceiveTxn_State_t  rtxn;
            CFE_SB_MessageTxn_State_t *txn;
            char                       tskname[OS_MAX_API_NAME * 2];

            printf("sbp_validmsgid ok=%ld bad=%ld\n",
                   (long)CFE_SB_ValidateMsgId(CFE_SB_ValueToMsgId(CFE_SB_CMD_MID)),
                   (long)CFE_SB_ValidateMsgId(CFE_SB_INVALID_MSG_ID));

            /* The pipe table: locate in range, locate out of range, and the used/free flag.
             *
             * THE ID HAS TO CARRY THE BASE NOW. This probe used to pass a bare 3, which worked
             * because CFE_SB_PipeId_ToIndex was stubbed here as `id & 0xFF`. The real one
             * (cfe_sb_api.c) subtracts CFE_SB_PIPEID_BASE and range-checks, so a bare 3 is not
             * a pipe id at all: Locate returned NULL and the next line wrote through it. A
             * stub that is more permissive than the thing it stands in for does not fail when
             * it is replaced -- it moves the failure to the caller. */
            pd = CFE_SB_LocatePipeDescByID(
                CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(CFE_SB_PIPEID_BASE + 3)));
            printf("sbp_locate inrange=%d used=%d outofrange=%d\n", (int)(pd != NULL),
                   (int)(pd != NULL && CFE_SB_PipeDescIsUsed(pd)),
                   (int)(CFE_SB_LocatePipeDescByID(
                             CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(3))) == NULL));
            CFE_SB_PipeDescSetUsed(pd, CFE_ResourceId_FromInteger(0x1234));
            printf("sbp_setused used=%d id=0x%08lx match=%d\n", (int)CFE_SB_PipeDescIsUsed(pd),
                   (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_SB_PipeDescGetID(pd)),
                   (int)CFE_SB_PipeDescIsMatch(pd, CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(0x1234))));
            printf("sbp_slotused=%d\n",
                   (int)CFE_SB_CheckPipeDescSlotUsed(
                       CFE_ResourceId_FromInteger(CFE_SB_PIPEID_BASE + 3)));
            CFE_SB_PipeDescSetFree(pd);
            printf("sbp_setfree used=%d nullmatch=%d\n", (int)CFE_SB_PipeDescIsUsed(pd),
                   (int)CFE_SB_PipeDescIsMatch(NULL, CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(3))));

            /* THE RECURSION GUARD: granted once, denied while held, granted again after finish.
             * A negative bit is always granted -- that is how the receive-side events opt out. */
            printf("sbp_guard a=%lu b=%lu", (unsigned long)CFE_SB_RequestToSendEvent(
                                                CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), 3),
                   (unsigned long)CFE_SB_RequestToSendEvent(
                       CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), 3));
            CFE_SB_FinishSendEvent(CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), 3);
            printf(" c=%lu neg=%lu\n",
                   (unsigned long)CFE_SB_RequestToSendEvent(
                       CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), 3),
                   (unsigned long)CFE_SB_RequestToSendEvent(
                       CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), -1));
            CFE_SB_FinishSendEvent(CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), 3);

            /* The app.task name, both branches. */
            printf("sbp_tskname %s\n",
                   CFE_SB_GetAppTskName(CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), tskname));
            sb_taskinfo_rc = CFE_ES_ERR_RESOURCEID_NOT_VALID;
            printf("sbp_tskname_bad %s\n",
                   CFE_SB_GetAppTskName(CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(1)), tskname));
            sb_taskinfo_rc = CFE_SUCCESS;

            /* THE DESTINATION LIST. Three nodes, inserted at the FRONT each time, then removed
             * from the middle, the end and finally as the only one -- the four branches of
             * CFE_SB_RemoveDestNode, which is the function whose pointer surgery a count cannot
             * check. Identity comparisons, like the buffer tracking list. */
            rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), NULL);
            memset(&d1, 0, sizeof(d1));
            memset(&d2, 0, sizeof(d2));
            memset(&d3, 0, sizeof(d3));
            d1.PipeId = CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(11));
            d2.PipeId = CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(12));
            d3.PipeId = CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(13));
            CFE_SB_AddDestNode(rid, &d1);
            CFE_SB_AddDestNode(rid, &d2);
            CFE_SB_AddDestNode(rid, &d3);
            printf("sbp_destadd head_d3=%d d3_next_d2=%d d1_next_null=%d\n",
                   (int)(CFE_SBR_GetDestListHeadPtr(rid) == &d3), (int)(d3.Next == &d2),
                   (int)(d1.Next == NULL));
            printf("sbp_destfind d2=%d miss=%d\n",
                   (int)(CFE_SB_GetDestPtr(rid, d2.PipeId) == &d2),
                   (int)(CFE_SB_GetDestPtr(rid, CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(99)))
                         == NULL));
            CFE_SB_RemoveDestNode(rid, &d2); /* middle */
            printf("sbp_destrm_mid d3_next_d1=%d d1_prev_d3=%d d2_clear=%d\n",
                   (int)(d3.Next == &d1), (int)(d1.Prev == &d3),
                   (int)(d2.Next == NULL && d2.Prev == NULL));
            CFE_SB_RemoveDestNode(rid, &d1); /* last */
            printf("sbp_destrm_last d3_next_null=%d head_d3=%d\n", (int)(d3.Next == NULL),
                   (int)(CFE_SBR_GetDestListHeadPtr(rid) == &d3));
            CFE_SB_RemoveDestNode(rid, &d3); /* only */
            printf("sbp_destrm_only head_null=%d\n",
                   (int)(CFE_SBR_GetDestListHeadPtr(rid) == NULL));

            /* THE TRANSACTION SETTERS. First writer wins, independently, for the event and the
             * status -- which is what lets the setup sequence run without each step checking the
             * one before. */
            txn = CFE_SB_TransmitTxn_Init(&ttxn, &ttxn);
            printf("sbp_txn_init ok=%d transmit=%d maxpipes=%u status=%ld\n",
                   (int)CFE_SB_MessageTxn_IsOK(txn), (int)txn->IsTransmit,
                   (unsigned int)txn->MaxPipes, (long)CFE_SB_MessageTxn_GetStatus(txn));
            CFE_SB_MessageTxn_SetContentSize(txn, 100);
            printf("sbp_txn_size ok=%d size=%u\n", (int)CFE_SB_MessageTxn_IsOK(txn),
                   (unsigned int)CFE_SB_MessageTxn_GetContentSize(txn));
            CFE_SB_MessageTxn_SetRoutingMsgId(txn, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID));
            printf("sbp_txn_mid ok=%d mid=0x%08x\n", (int)CFE_SB_MessageTxn_IsOK(txn),
                   (unsigned int)CFE_SB_MsgIdToValue(CFE_SB_MessageTxn_GetRoutingMsgId(txn)));
            /* too big, then an invalid id: the FIRST failure keeps both fields */
            CFE_SB_MessageTxn_SetContentSize(txn, CFE_MISSION_SB_MAX_SB_MSG_SIZE + 1);
            printf("sbp_txn_toobig ok=%d evt=%u status=%ld size=%u\n",
                   (int)CFE_SB_MessageTxn_IsOK(txn), (unsigned int)txn->TransactionEventId,
                   (long)CFE_SB_MessageTxn_GetStatus(txn),
                   (unsigned int)CFE_SB_MessageTxn_GetContentSize(txn));
            CFE_SB_MessageTxn_SetRoutingMsgId(txn, CFE_SB_INVALID_MSG_ID);
            printf("sbp_txn_firstwins evt=%u status=%ld\n", (unsigned int)txn->TransactionEventId,
                   (long)CFE_SB_MessageTxn_GetStatus(txn));

            /* The timeout modes, including the rejected one. */
            txn = CFE_SB_ReceiveTxn_Init(&rtxn, &rtxn);
            CFE_SB_MessageTxn_SetTimeout(txn, CFE_SB_POLL);
            printf("sbp_timeout poll=%d os=%ld", (int)txn->TimeoutMode,
                   (long)CFE_SB_MessageTxn_GetOsTimeout(txn));
            CFE_SB_MessageTxn_SetTimeout(txn, CFE_SB_PEND_FOREVER);
            printf(" pend=%d os=%ld", (int)txn->TimeoutMode,
                   (long)CFE_SB_MessageTxn_GetOsTimeout(txn));
            CFE_SB_MessageTxn_SetTimeout(txn, -99);
            printf(" bad_evt=%u status=%ld\n", (unsigned int)txn->TransactionEventId,
                   (long)CFE_SB_MessageTxn_GetStatus(txn));

            /* A NULL reference pointer is rejected, with a DIFFERENT event per direction. */
            txn = CFE_SB_TransmitTxn_Init(&ttxn, NULL);
            printf("sbp_null_tx evt=%u status=%ld\n", (unsigned int)txn->TransactionEventId,
                   (long)CFE_SB_MessageTxn_GetStatus(txn));
            txn = CFE_SB_ReceiveTxn_Init(&rtxn, NULL);
            printf("sbp_null_rx evt=%u status=%ld endpoint=%d\n",
                   (unsigned int)txn->TransactionEventId, (long)CFE_SB_MessageTxn_GetStatus(txn),
                   (int)txn->IsEndpoint);
            CFE_SB_MessageTxn_SetEndpoint(txn, true);
            printf("sbp_endpoint=%d\n", (int)txn->IsEndpoint);

            /* The subscribe counters: six event ids mean "failed", one means "duplicate". */
            CFE_SB_Global.HKTlmMsg.Payload.SubscribeErrorCounter          = 0;
            CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter  = 0;
            CFE_SB_IncrementSubscribeCounters(CFE_SB_SUB_INV_PIPE_EID);
            CFE_SB_IncrementSubscribeCounters(CFE_SB_MAX_DESTS_MET_EID);
            CFE_SB_IncrementSubscribeCounters(CFE_SB_DUP_SUBSCRIP_EID);
            CFE_SB_IncrementSubscribeCounters(CFE_SB_INIT_EID); /* not an error */
            printf("sbp_subcnt err=%u dup=%u\n",
                   (unsigned int)CFE_SB_Global.HKTlmMsg.Payload.SubscribeErrorCounter,
                   (unsigned int)CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter);
        }

        /* --- cfe_sb_api.c: the PUBLIC bus ------------------------------------------------
         *
         * Everything above drove SB through another module. This drives it directly, and it
         * starts from a clean bus because the sections above left pipes, routes and
         * subscriptions behind -- CFE_SB_EarlyInit is the reset, and running it here means the
         * numbers below are about these calls and not about how many times EVS was initialised.
         *
         * WHAT IS NOT DRIVEN, and why: every path through CFE_SB_CreatePipe's argument check
         * raises an event that prints `ptr=0x%lx`, the address of the caller's own variable.
         * A host process and a QEMU guest put that variable in different places, so NONE of
         * the four bad-argument cases can be compared -- not just the NULL one. */
        {
            CFE_SB_PipeId_t  pipe1;
            CFE_SB_PipeId_t  pipe2;
            CFE_SB_PipeId_t  found;
            CFE_SB_Buffer_t *zbuf;
            CFE_SB_Buffer_t *rcvd;
            CFE_SB_Qos_t     qos;
            char             pname[OS_MAX_API_NAME];
            uint8            opts;
            CFE_MSG_Message_t tmsg;

            CFE_SB_EarlyInit();
            sb_queuecreate_rc = OS_SUCCESS;
            es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
            memset(&qos, 0, sizeof(qos));

            printf("api_create1 rc=%ld pipes=%u\n",
                   (long)CFE_SB_CreatePipe(&pipe1, 4, "APIPIPE1"),
                   CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
            printf("api_create2 rc=%ld pipes=%u peak=%u\n",
                   (long)CFE_SB_CreatePipe(&pipe2, 4, "APIPIPE2"),
                   CFE_SB_Global.StatTlmMsg.Payload.PipesInUse,
                   CFE_SB_Global.StatTlmMsg.Payload.PeakPipesInUse);
            /* the same name twice: OS_ERR_NAME_TAKEN, which has its own event */
            printf("api_create_taken rc=%ld err=%u\n",
                   (long)CFE_SB_CreatePipe(&found, 4, "APIPIPE1"),
                   CFE_SB_Global.HKTlmMsg.Payload.CreatePipeErrorCounter);

            /* the name comes back, and the id can be found from it */
            printf("api_name rc=%ld name=%s\n",
                   (long)CFE_SB_GetPipeName(pname, sizeof(pname), pipe1), pname);
            printf("api_byname rc=%ld same=%d\n",
                   (long)CFE_SB_GetPipeIdByName(&found, "APIPIPE2"),
                   (int)CFE_RESOURCEID_TEST_EQUAL(found, pipe2));
            printf("api_byname_bad rc=%ld err=%u\n",
                   (long)CFE_SB_GetPipeIdByName(&found, "NOSUCHPIPE"),
                   CFE_SB_Global.HKTlmMsg.Payload.GetPipeIdByNameErrorCounter);

            /* options round-trip, then the two refusals */
            printf("api_setopts rc=%ld\n", (long)CFE_SB_SetPipeOpts(pipe1, CFE_SB_PIPEOPTS_IGNOREMINE));
            printf("api_getopts rc=%ld opts=0x%02x\n", (long)CFE_SB_GetPipeOpts(pipe1, &opts),
                   (unsigned int)opts);
            printf("api_getopts_null rc=%ld\n", (long)CFE_SB_GetPipeOpts(pipe1, NULL));
            printf("api_setopts_bad rc=%ld errs=%u\n",
                   (long)CFE_SB_SetPipeOpts(CFE_SB_INVALID_PIPE, 0),
                   CFE_SB_Global.HKTlmMsg.Payload.PipeOptsErrorCounter);
            CFE_SB_SetPipeOpts(pipe1, 0);

            /* subscriptions: the three public forms, then a duplicate */
            printf("api_sub rc=%ld subs=%u\n",
                   (long)CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0931), pipe1),
                   CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
            printf("api_subex rc=%ld subs=%u\n",
                   (long)CFE_SB_SubscribeEx(CFE_SB_ValueToMsgId(0x0931), pipe2, qos, 4),
                   CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
            printf("api_sublocal rc=%ld subs=%u\n",
                   (long)CFE_SB_SubscribeLocal(CFE_SB_ValueToMsgId(0x0932), pipe1, 4),
                   CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
            printf("api_sub_dup rc=%ld dup=%u\n",
                   (long)CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0931), pipe1),
                   CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter);
            printf("api_sub_badpipe rc=%ld\n",
                   (long)CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0931), CFE_SB_INVALID_PIPE));
            printf("api_sub_badmid rc=%ld\n",
                   (long)CFE_SB_Subscribe(CFE_SB_INVALID_MSG_ID, pipe1));

            /* a zero-copy buffer: take one, release it, and ask for an impossible one */
            zbuf = CFE_SB_AllocateMessageBuffer(64);
            printf("api_alloc got=%d inuse=%u\n", (int)(zbuf != NULL),
                   CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
            printf("api_release rc=%ld inuse=%u\n", (long)CFE_SB_ReleaseMessageBuffer(zbuf),
                   CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
            printf("api_release_null rc=%ld\n", (long)CFE_SB_ReleaseMessageBuffer(NULL));
            printf("api_alloc_huge got=%d\n",
                   (int)(CFE_SB_AllocateMessageBuffer(CFE_MISSION_SB_MAX_SB_MSG_SIZE + 1) != NULL));

            /* THE ROUND TRIP, and this is the one the four stubs made impossible: transmit a
             * message to a message id two pipes subscribed to, then receive it on each. */
            memset(&tmsg, 0, sizeof(tmsg));
            CFE_MSG_Init(&tmsg, CFE_SB_ValueToMsgId(0x0931), sizeof(tmsg));
            printf("api_tx rc=%ld nosubs=%u\n", (long)CFE_SB_TransmitMsg(&tmsg, true),
                   CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter);
            rcvd = NULL;
            printf("api_rx1 rc=%ld got=%d\n", (long)CFE_SB_ReceiveBuffer(&rcvd, pipe1, OS_CHECK),
                   (int)(rcvd != NULL));
            rcvd = NULL;
            printf("api_rx2 rc=%ld got=%d\n", (long)CFE_SB_ReceiveBuffer(&rcvd, pipe2, OS_CHECK),
                   (int)(rcvd != NULL));
            rcvd = NULL;
            printf("api_rx_empty rc=%ld\n", (long)CFE_SB_ReceiveBuffer(&rcvd, pipe1, OS_CHECK));
            printf("api_rx_badpipe rc=%ld\n",
                   (long)CFE_SB_ReceiveBuffer(&rcvd, CFE_SB_INVALID_PIPE, OS_CHECK));
            printf("api_rx_nullptr rc=%ld\n", (long)CFE_SB_ReceiveBuffer(NULL, pipe1, OS_CHECK));

            /* unsubscribe: the real one, one with no subscription, and the two refusals */
            printf("api_unsub rc=%ld subs=%u\n",
                   (long)CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(0x0931), pipe1),
                   CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
            printf("api_unsub_none rc=%ld\n",
                   (long)CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(0x0931), pipe1));
            printf("api_unsub_badpipe rc=%ld\n",
                   (long)CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(0x0931), CFE_SB_INVALID_PIPE));
            printf("api_unsub_badmid rc=%ld\n",
                   (long)CFE_SB_Unsubscribe(CFE_SB_INVALID_MSG_ID, pipe1));
            printf("api_unsublocal rc=%ld\n",
                   (long)CFE_SB_UnsubscribeLocal(CFE_SB_ValueToMsgId(0x0932), pipe1));

            /* delete: the owner can, a different app cannot, and a bad id cannot */
            printf("api_del_notowner rc=%ld\n",
                   (long)CFE_SB_DeletePipeWithAppId(pipe1,
                                                    CFE_ES_APPID_C(CFE_ResourceId_FromInteger(
                                                        CFE_ES_APPID_BASE + 42))));
            printf("api_del rc=%ld pipes=%u queues_deleted=%ld\n", (long)CFE_SB_DeletePipe(pipe1),
                   CFE_SB_Global.StatTlmMsg.Payload.PipesInUse, sb_qdeletes);
            printf("api_del_again rc=%ld errs=%u\n", (long)CFE_SB_DeletePipe(pipe1),
                   CFE_SB_Global.HKTlmMsg.Payload.DeletePipeErrorCounter);
            printf("api_del2 rc=%ld pipes=%u\n", (long)CFE_SB_DeletePipe(pipe2),
                   CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
            printf("api_toindex rc=%ld\n",
                   (long)CFE_SB_PipeId_ToIndex(CFE_SB_INVALID_PIPE, &sb_api_idx));
        }

        /* --- cfe_sb_task.c and cfe_sb_dispatch.c: SB AS AN APPLICATION ------------------
         *
         * The bus commanding itself. Everything above called SB as a library; this builds
         * command packets and pushes them through the dispatcher, which is the path a ground
         * command actually takes.
         *
         * CFE_SB_TaskMain is NOT driven, and cannot be: its loop pends forever on
         * CFE_SB_ReceiveBuffer and ends in CFE_ES_ExitApp. Every function it calls IS driven,
         * individually -- AppInit here, ProcessCmdPipePkt through the packets below. */
        {
            union
            {
                CFE_SB_Buffer_t               Buf;
                CFE_SB_NoopCmd_t              Noop;
                CFE_SB_ResetCountersCmd_t     Reset;
                CFE_SB_SendSbStatsCmd_t       Stats;
                CFE_SB_EnableRouteCmd_t       Route;
                CFE_SB_WriteRoutingInfoCmd_t  WrFile;
                CFE_SB_SendPrevSubsCmd_t      PrevSubs;
                CFE_SB_EnableSubReportingCmd_t SubRpt;
                CFE_SB_SendHkCmd_t            Hk;
            } sc;
            CFE_SB_PipeId_t tpipe;
            CFE_SB_Qos_t    tqos;
            void           *gbuf;
            size_t          gsize;
            bool            geof;
            int             cc;

            memset(&tqos, 0, sizeof(tqos));
            sbq_reset();
            CFE_SB_EarlyInit();
            sb_queuecreate_rc = OS_SUCCESS;
            es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
            es_set_ctx(1);

            /* --- CFE_SB_AppInit: the success path and three of its eight failure returns -
             *
             * AppInit has EIGHT `return Status` points. Three are driven: the create-pipe
             * failure twice over (once by OS_ERR_NAME_TAKEN, once by OS_ERROR -- the same
             * return, two different OSAL causes) and the subscribe failure by way of the
             * memory pool. The CFE_EVS_Register, PutPoolBuf and init-event returns are NOT
             * taken, because the driver has no way to make the real EVS or the real pool fail
             * at just those points. Said plainly rather than counted as four. */
            printf("sbt_init rc=%ld pipes=%u\n", (long)CFE_SB_AppInit(),
                   CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
            /* ALL FOUR FILTER PAIRS, because nothing else can see them: the
             * CFE_PLATFORM_SB_FILTERED_EVENTn macros expand to other macro names, so
             * check_constants.py files every one under "not a literal and so NOT compared".
             * The C half fills these with NASA's real macros; a wrong name in the translation
             * diverges here and nowhere else. */
            printf("sbt_init_filters %u/0x%04x %u/0x%04x %u/0x%04x %u/0x%04x\n",
                   CFE_SB_Global.EventFilters[0].EventID, CFE_SB_Global.EventFilters[0].Mask,
                   CFE_SB_Global.EventFilters[1].EventID, CFE_SB_Global.EventFilters[1].Mask,
                   CFE_SB_Global.EventFilters[2].EventID, CFE_SB_Global.EventFilters[2].Mask,
                   CFE_SB_Global.EventFilters[3].EventID, CFE_SB_Global.EventFilters[3].Mask);
            /* the fixed fields AppInit populates, which nothing else sets */
            printf("sbt_init_fixed maxids=%u maxpipes=%u maxmem=%u maxdepth=%u maxsubs=%u\n",
                   CFE_SB_Global.StatTlmMsg.Payload.MaxMsgIdsAllowed,
                   CFE_SB_Global.StatTlmMsg.Payload.MaxPipesAllowed,
                   CFE_SB_Global.StatTlmMsg.Payload.MaxMemAllowed,
                   CFE_SB_Global.StatTlmMsg.Payload.MaxPipeDepthAllowed,
                   CFE_SB_Global.StatTlmMsg.Payload.MaxSubscriptionsAllowed);
            /* the create-pipe failure: the name is already taken by the pipe just made */
            printf("sbt_init_again rc=%ld\n", (long)CFE_SB_AppInit());
            sbq_reset();
            CFE_SB_EarlyInit();
            sb_queuecreate_rc = OS_ERROR;
            printf("sbt_init_pipefail rc=%ld\n", (long)CFE_SB_AppInit());
            sb_queuecreate_rc = OS_SUCCESS;
            sbq_reset();
            CFE_SB_EarlyInit();
            es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
            printf("sbt_init_poolfail rc=%ld\n", (long)CFE_SB_AppInit());
            es_pool_restore(CFE_SB_Global.Mem.PoolHdl);

            /* A clean bus with one real pipe and one subscription, for the commands below. */
            sbq_reset();
            CFE_SB_EarlyInit();
            printf("sbt_setup rc=%ld\n", (long)CFE_SB_AppInit());
            CFE_SB_CreatePipe(&tpipe, 4, "SBTPIPE");
            CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0941), tpipe);

            /* --- the counters, and the only two functions that touch them ---------------- */
            CFE_SB_Global.HKTlmMsg.Payload.CommandCounter      = 11;
            CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter = 22;
            CFE_SB_IncrCmdCtr(CFE_SUCCESS);
            CFE_SB_IncrCmdCtr(CFE_SB_BAD_ARGUMENT);
            printf("sbt_incr ok=%u err=%u\n", CFE_SB_Global.HKTlmMsg.Payload.CommandCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
            CFE_SB_ResetCounters();
            printf("sbt_reset ok=%u err=%u nosub=%u dup=%u send=%u recv=%u int=%u\n",
                   CFE_SB_Global.HKTlmMsg.Payload.CommandCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.MsgSendErrorCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.MsgReceiveErrorCounter,
                   CFE_SB_Global.HKTlmMsg.Payload.InternalErrorCounter);

            /* --- the dispatcher: every ground command code, in order --------------------- */
            for (cc = 0; cc <= 11; cc++)
            {
                memset(&sc, 0, sizeof(sc));
                CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID),
                             sizeof(CFE_SB_NoopCmd_t));
                CFE_MSG_SetFcnCode(&sc.Buf.Msg, (CFE_MSG_FcnCode_t)cc);
                /* the three file commands and the two route commands carry a payload, so
                 * their length differs; set it per code so only the UNKNOWN codes 6 and 12
                 * reach the bad-code branch rather than the bad-length one */
                switch (cc)
                {
                    case CFE_SB_ENABLE_ROUTE_CC:
                    case CFE_SB_DISABLE_ROUTE_CC:
                        CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_EnableRouteCmd_t));
                        sc.Route.Payload.MsgId = CFE_SB_ValueToMsgId(0x0941);
                        sc.Route.Payload.Pipe  = tpipe;
                        break;
                    case CFE_SB_WRITE_ROUTING_INFO_CC:
                    case CFE_SB_WRITE_PIPE_INFO_CC:
                    case CFE_SB_WRITE_MAP_INFO_CC:
                        CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_WriteRoutingInfoCmd_t));
                        break;
                    default:
                        break;
                }
                CFE_SB_ProcessCmdPipePkt(&sc.Buf);
                printf("sbt_cmd[%d] ok=%u err=%u\n", cc,
                       CFE_SB_Global.HKTlmMsg.Payload.CommandCounter,
                       CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
            }

            /* a code no branch knows, and one with the wrong length */
            memset(&sc, 0, sizeof(sc));
            CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), sizeof(CFE_SB_NoopCmd_t));
            CFE_MSG_SetFcnCode(&sc.Buf.Msg, 99);
            CFE_SB_ProcessCmdPipePkt(&sc.Buf);
            printf("sbt_cmd_badcode err=%u\n", CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
            CFE_MSG_SetFcnCode(&sc.Buf.Msg, CFE_SB_NOOP_CC);
            CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_NoopCmd_t) + 4);
            CFE_SB_ProcessCmdPipePkt(&sc.Buf);
            printf("sbt_cmd_badlen err=%u\n", CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);

            /* the housekeeping request, which has no function code at all */
            memset(&sc, 0, sizeof(sc));
            CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_SEND_HK_MID),
                         sizeof(CFE_SB_SendHkCmd_t));
            sb_tx_reset();
            CFE_SB_ProcessCmdPipePkt(&sc.Buf);
            printf("sbt_hk tx=%d meminuse=%u unmarked=%u pool=%lu\n", sb_tx_since(),
                   CFE_SB_Global.HKTlmMsg.Payload.MemInUse,
                   CFE_SB_Global.HKTlmMsg.Payload.UnmarkedMem,
                   (unsigned long)CFE_RESOURCEID_TO_ULONG(
                       CFE_SB_Global.HKTlmMsg.Payload.MemPoolHandle));

            /* --- the subscription-report control mid, and its three codes ---------------- */
            for (cc = 9; cc <= 12; cc++)
            {
                memset(&sc, 0, sizeof(sc));
                CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_SUB_RPT_CTRL_MID),
                             sizeof(CFE_SB_EnableSubReportingCmd_t));
                CFE_MSG_SetFcnCode(&sc.Buf.Msg, (CFE_MSG_FcnCode_t)cc);
                if (cc == CFE_SB_SEND_PREV_SUBS_CC)
                {
                    CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_SendPrevSubsCmd_t));
                }
                CFE_SB_ProcessCmdPipePkt(&sc.Buf);
                printf("sbt_subrpt[%d] report=%u err=%u seg=%u entries=%u\n", cc,
                       CFE_SB_Global.SubscriptionReporting,
                       CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter,
                       CFE_SB_Global.PrevSubMsg.Payload.PktSegment,
                       CFE_SB_Global.PrevSubMsg.Payload.Entries);
            }

            /* a message id SB does not route to itself */
            memset(&sc, 0, sizeof(sc));
            CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(0x09FF), sizeof(CFE_SB_NoopCmd_t));
            CFE_SB_ProcessCmdPipePkt(&sc.Buf);
            printf("sbt_badmid err=%u\n", CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);

            /* --- the subscription report itself, with reporting ENABLED ------------------ */
            CFE_SB_SetSubscriptionReporting(CFE_SB_ENABLE);
            printf("sbt_subrpt_on rc=%ld state=%u\n",
                   (long)CFE_SB_SendSubscriptionReport(CFE_SB_ValueToMsgId(0x0941), tpipe, tqos),
                   CFE_SB_Global.SubscriptionReporting);
            CFE_SB_SetSubscriptionReporting(CFE_SB_DISABLE);
            printf("sbt_subrpt_off rc=%ld\n",
                   (long)CFE_SB_SendSubscriptionReport(CFE_SB_ValueToMsgId(0x0941), tpipe, tqos));

            /* --- the route commands' two refusals, which the loop above did not reach ---- */
            memset(&sc, 0, sizeof(sc));
            CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID),
                         sizeof(CFE_SB_EnableRouteCmd_t));
            CFE_MSG_SetFcnCode(&sc.Buf.Msg, CFE_SB_ENABLE_ROUTE_CC);
            sc.Route.Payload.MsgId = CFE_SB_INVALID_MSG_ID;
            sc.Route.Payload.Pipe  = tpipe;
            printf("sbt_enrt_badmid rc=%ld err=%u\n", (long)CFE_SB_EnableRouteCmd(&sc.Route),
                   CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
            sc.Route.Payload.MsgId = CFE_SB_ValueToMsgId(0x09AB); /* valid, but unsubscribed */
            printf("sbt_enrt_noroute rc=%ld err=%u\n", (long)CFE_SB_EnableRouteCmd(&sc.Route),
                   CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
            printf("sbt_dsrt_noroute rc=%ld err=%u\n", (long)CFE_SB_DisableRouteCmd(&sc.Route),
                   CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);

            /* --- the three data getters, called the way the file writer calls them ------- */
            gbuf = NULL; gsize = 0;
            geof = CFE_SB_WriteRouteInfoDataGetter(&CFE_SB_Global.BackgroundFile, 0, &gbuf, &gsize);
            printf("sbt_getroute eof=%d size=%u dests=%u\n", (int)geof, (unsigned int)gsize,
                   CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.NumDestinations);
            printf("sbt_getroute_e0 msgid=0x%04x state=%u app=%s pipe=%s\n",
                   (unsigned int)CFE_SB_MsgIdToValue(
                       CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].MsgId),
                   CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].State,
                   CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].AppName,
                   CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].PipeName);
            /* RecordNum IS the pipe-table index, so probing slot 0 proved nothing: whichever
             * slot CFE_SB_AppInit's command pipe landed in is the one with data in it. Ask. */
            CFE_SB_PipeId_ToIndex(CFE_SB_Global.CmdPipe, &sb_api_idx);
            gbuf = NULL; gsize = 0;
            geof = CFE_SB_WritePipeInfoDataGetter(&CFE_SB_Global.BackgroundFile, sb_api_idx,
                                                  &gbuf, &gsize);
            printf("sbt_getpipe eof=%d size=%u used=%d depth=%u/%u app=%s\n", (int)geof,
                   (unsigned int)gsize, (int)(gbuf != NULL),
                   CFE_SB_Global.BackgroundFile.Buffer.PipeInfo.CurrentQueueDepth,
                   CFE_SB_Global.BackgroundFile.Buffer.PipeInfo.MaxQueueDepth,
                   CFE_SB_Global.BackgroundFile.Buffer.PipeInfo.AppName);
            /* and an UNUSED slot, which is still a record but writes nothing */
            gbuf = NULL; gsize = 0;
            geof = CFE_SB_WritePipeInfoDataGetter(&CFE_SB_Global.BackgroundFile,
                                                  CFE_PLATFORM_SB_MAX_PIPES - 2, &gbuf, &gsize);
            printf("sbt_getpipe_free eof=%d size=%u used=%d\n", (int)geof, (unsigned int)gsize,
                   (int)(gbuf != NULL));
            gbuf = NULL; gsize = 0;
            geof = CFE_SB_WritePipeInfoDataGetter(&CFE_SB_Global.BackgroundFile,
                                                  CFE_PLATFORM_SB_MAX_PIPES - 1, &gbuf, &gsize);
            printf("sbt_getpipe_last eof=%d size=%u\n", (int)geof, (unsigned int)gsize);
            gbuf = NULL; gsize = 0;
            geof = CFE_SB_WriteMsgMapInfoDataGetter(&CFE_SB_Global.BackgroundFile, 0, &gbuf, &gsize);
            printf("sbt_getmap eof=%d size=%u idx=%u\n", (int)geof, (unsigned int)gsize,
                   CFE_SB_Global.BackgroundFile.Buffer.MsgMapInfo.Index);

            /* --- the background event handler, every event it knows and one it does not -- */
            snprintf(CFE_SB_Global.BackgroundFile.FileWrite.FileName,
                     sizeof(CFE_SB_Global.BackgroundFile.FileWrite.FileName), "/ram/sbt.dat");
            CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile,
                                              CFE_FS_FileWriteEvent_COMPLETE, 0, 7, 0, 123);
            CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile,
                                              CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR, -5, 0, 64, 0);
            CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile,
                                              CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR, -6, 1, 32, 0);
            CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile,
                                              CFE_FS_FileWriteEvent_CREATE_ERROR, -7, 0, 0, 0);
            CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile,
                                              CFE_FS_FileWriteEvent_UNDEFINED, 0, 0, 0, 0);
            printf("sbt_bgevents done\n");

            /* --- cfe_sb_objtab.c --------------------------------------------------------- */
            printf("sbt_objtab %s %d %d %d %lu %lu\n", CFE_SB_ModuleEntry.Name,
                   (int)(CFE_SB_ModuleEntry.EarlyInit == NULL),
                   (int)(CFE_SB_ModuleEntry.TaskMain == NULL),
                   (int)(CFE_SB_ModuleEntry.AppCleanupCb == NULL),
                   (unsigned long)CFE_SB_ModuleEntry.Priority,
                   (unsigned long)CFE_SB_ModuleEntry.StackSize);
        }

        /* --- cfe_es_generic_pool.c and cfe_es_crc.c: THE REAL ALLOCATOR -----------------
         *
         * Every CFE_ES_GetPoolBuf in the transcript above goes to a hand-written bump
         * allocator further up this file, because NASA's real pool lives in ES and ES was not
         * translated. This drives the real one directly -- the generic layer, which holds all
         * of the allocation logic; cfe_es_mempool.c is the thin wrapper that adds a resource
         * id and a mutex, and it needs CFE_ES_Global, which is the next commit.
         *
         * The pool is addressed by OFFSET and reached through a Retrieve/Commit pair, so the
         * driver supplies the memory-mapped pair -- which is exactly what
         * CFE_ES_MemPoolDirectRetrieve will do once mempool.c lands. */
        {
            CFE_ES_GenPoolRecord_t pool;
            size_t                 blocksizes[4];
            size_t                 off1, off2, off3, off4, sz;
            CFE_ES_BlockStats_t    bstat;
            CFE_ES_MemOffset_t     freesz, totalsz;
            uint16                 nbuckets;
            uint32                 alloccnt, errcnt;
            int32                  st;
            int                    k;

            memset(es_pool_mem, 0, sizeof(es_pool_mem));

            /* UNSORTED ON PURPOSE: GenPoolInitialize bubble-sorts them, and the order it ends
             * up with is what decides every bucket id. */
            blocksizes[0] = 128;
            blocksizes[1] = 32;
            blocksizes[2] = 256;
            blocksizes[3] = 64;
            st = CFE_ES_GenPoolInitialize(&pool, 0, sizeof(es_pool_mem), 8, 4, blocksizes,
                                          es_pool_retrieve, es_pool_commit);
            printf("gp_init rc=%ld buckets=%u sorted=%lu/%lu/%lu/%lu align=%lu\n", (long)st,
                   pool.NumBuckets, (unsigned long)pool.Buckets[0].BlockSize,
                   (unsigned long)pool.Buckets[1].BlockSize,
                   (unsigned long)pool.Buckets[2].BlockSize,
                   (unsigned long)pool.Buckets[3].BlockSize, (unsigned long)pool.AlignMask);
            printf("gp_valid=%d\n", (int)CFE_ES_GenPoolValidateState(&pool));

            /* THE BUCKET ID IS INVERTED: the LARGEST bucket is 1 and "nothing fits" is 0. */
            printf("gp_bucket 1=%u 32=%u 33=%u 256=%u 257=%u\n",
                   CFE_ES_GenPoolFindBucket(&pool, 1), CFE_ES_GenPoolFindBucket(&pool, 32),
                   CFE_ES_GenPoolFindBucket(&pool, 33), CFE_ES_GenPoolFindBucket(&pool, 256),
                   CFE_ES_GenPoolFindBucket(&pool, 257));
            printf("gp_state 0=%d 1=%lu 4=%lu 5=%d\n",
                   (int)(CFE_ES_GenPoolGetBucketState(&pool, 0) == NULL),
                   (unsigned long)CFE_ES_GenPoolGetBucketState(&pool, 1)->BlockSize,
                   (unsigned long)CFE_ES_GenPoolGetBucketState(&pool, 4)->BlockSize,
                   (int)(CFE_ES_GenPoolGetBucketState(&pool, 5) == NULL));

            /* three allocations, two of them from the same bucket */
            st = CFE_ES_GenPoolGetBlock(&pool, &off1, 20);
            printf("gp_get20 rc=%ld off=%lu tail=%lu\n", (long)st, (unsigned long)off1,
                   (unsigned long)pool.TailPosition);
            st = CFE_ES_GenPoolGetBlock(&pool, &off2, 30);
            printf("gp_get30 rc=%ld off=%lu tail=%lu\n", (long)st, (unsigned long)off2,
                   (unsigned long)pool.TailPosition);
            st = CFE_ES_GenPoolGetBlock(&pool, &off3, 200);
            printf("gp_get200 rc=%ld off=%lu tail=%lu\n", (long)st, (unsigned long)off3,
                   (unsigned long)pool.TailPosition);
            printf("gp_size1 rc=%ld sz=%lu\n", (long)CFE_ES_GenPoolGetBlockSize(&pool, &sz, off1),
                   (unsigned long)sz);
            printf("gp_size3 rc=%ld sz=%lu\n", (long)CFE_ES_GenPoolGetBlockSize(&pool, &sz, off3),
                   (unsigned long)sz);
            /* too big for any bucket, and a size query outside the pool */
            printf("gp_get_huge rc=%ld\n", (long)CFE_ES_GenPoolGetBlock(&pool, &off4, 1000));
            printf("gp_size_oob rc=%ld\n", (long)CFE_ES_GenPoolGetBlockSize(&pool, &sz, 0));
            printf("gp_size_past rc=%ld\n",
                   (long)CFE_ES_GenPoolGetBlockSize(&pool, &sz, pool.TailPosition + 8));

            /* RECYCLING: free the 20-byte block and ask for another that fits the same bucket.
             * The offset must come back IDENTICAL -- that is the whole point of the free stack,
             * and a pool that created a new block instead would still "work". */
            printf("gp_put1 rc=%ld sz=%lu\n", (long)CFE_ES_GenPoolPutBlock(&pool, &sz, off1),
                   (unsigned long)sz);
            st = CFE_ES_GenPoolGetBlock(&pool, &off4, 25);
            printf("gp_recycle rc=%ld same=%d tail_unchanged=%d\n", (long)st,
                   (int)(off4 == off1), (int)(pool.TailPosition == off3 + 256));
            /* The block is LIVE again after the recycle, so freeing it once more is legitimate
             * -- the first version of this probe called that a double free and reported errs=0
             * as if the counter were broken. The free AFTER it is the real double free: the
             * descriptor already says DEALLOCATED, so the bucket id derived from it is out of
             * range, GetBucketState returns NULL, and the pool counts a validation error. */
            printf("gp_put_recycled rc=%ld errs=%u\n",
                   (long)CFE_ES_GenPoolPutBlock(&pool, &sz, off1), pool.ValidationErrorCount);
            printf("gp_double_free rc=%ld errs=%u\n",
                   (long)CFE_ES_GenPoolPutBlock(&pool, &sz, off1), pool.ValidationErrorCount);

            CFE_ES_GenPoolGetUsage(&pool, &freesz, &totalsz);
            printf("gp_usage free=%lu total=%lu\n", (unsigned long)freesz,
                   (unsigned long)totalsz);
            CFE_ES_GenPoolGetCounts(&pool, &nbuckets, &alloccnt, &errcnt);
            printf("gp_counts buckets=%u alloc=%u errs=%u\n", nbuckets, alloccnt, errcnt);
            for (k = 0; k <= 5; k++)
            {
                memset(&bstat, 0, sizeof(bstat));
                CFE_ES_GenPoolGetBucketUsage(&pool, (uint16)k, &bstat);
                printf("gp_bucketuse[%d] size=%lu created=%u free=%u\n", k,
                       (unsigned long)bstat.BlockSize, bstat.NumCreated, bstat.NumFree);
            }

            /* MinSize is pure arithmetic over the list: smallest block plus a descriptor */
            printf("gp_minsize n4=%lu n0=%lu\n",
                   (unsigned long)CFE_ES_GenPoolCalcMinSize(4, blocksizes, 10),
                   (unsigned long)CFE_ES_GenPoolCalcMinSize(0, blocksizes, 10));

            /* REBUILD: the descriptors are still in the storage, the record is not. A FRESH
             * record over the same memory with the same block sizes recovers the state from
             * the check patterns alone -- which is what a CDS does after a reboot. Done before
             * the argument-check failures below, because those overwrite the record. */
            CFE_ES_GenPoolInitialize(&pool, 0, sizeof(es_pool_mem), 8, 4, blocksizes,
                                     es_pool_retrieve, es_pool_commit);
            printf("gp_rebuild rc=%ld tail=%lu alloc=%u\n", (long)CFE_ES_GenPoolRebuild(&pool),
                   (unsigned long)pool.TailPosition, pool.AllocationCount);
            CFE_ES_GenPoolGetBucketUsage(&pool, 4, &bstat);
            printf("gp_rebuild_b4 created=%u free=%u\n", bstat.NumCreated, bstat.NumFree);

            /* the three failure returns in Initialize */
            printf("gp_init_nobuckets rc=%ld\n",
                   (long)CFE_ES_GenPoolInitialize(&pool, 0, sizeof(es_pool_mem), 8, 0,
                                                  blocksizes, es_pool_retrieve, es_pool_commit));
            printf("gp_init_badalign rc=%ld\n",
                   (long)CFE_ES_GenPoolInitialize(&pool, 0, sizeof(es_pool_mem), 6, 4,
                                                  blocksizes, es_pool_retrieve, es_pool_commit));
            blocksizes[1] = 0;
            printf("gp_init_zerosize rc=%ld\n",
                   (long)CFE_ES_GenPoolInitialize(&pool, 0, sizeof(es_pool_mem), 8, 4,
                                                  blocksizes, es_pool_retrieve, es_pool_commit));
            blocksizes[1] = 32;

            /* --- cfe_es_crc.c ----------------------------------------------------------- */
            printf("crc_none rc=%u\n", CFE_ES_ComputeCRC_Algo_NONE(CRC_PROBE, 9, 0));
            /* CRC-16/ARC of "123456789" is 0xBB3D -- the check value in NASA's own comment on
             * the enumerator, which is why this input and not another. */
            printf("crc_arc rc=0x%04x\n", CFE_ES_ComputeCRC_Algo_16_ARC(CRC_PROBE, 9, 0));
            printf("crc_arc_seeded rc=0x%04x\n", CFE_ES_ComputeCRC_Algo_16_ARC(CRC_PROBE, 9, 1));
            printf("crc_arc_empty rc=0x%04x\n", CFE_ES_ComputeCRC_Algo_16_ARC(CRC_PROBE, 0, 7));
            /* GetParams: NONE has a NULL algorithm in the table ON PURPOSE, so it falls through
             * to the catch-all; an out-of-range type does too. Both come back non-NULL with a
             * usable algorithm, which is the contract. */
            for (k = 0; k <= 2; k++)
            {
                printf("crc_params[%d] null=%d algo_none=%d\n", k,
                       (int)(CFE_ES_ComputeCRC_GetParams(k) == NULL),
                       (int)(CFE_ES_ComputeCRC_GetParams(k)->Algorithm ==
                             CFE_ES_ComputeCRC_Algo_NONE));
            }
            printf("crc_params_arc result=0x%04x\n",
                   CFE_ES_ComputeCRC_GetParams(CFE_ES_CrcType_16_ARC)->Algorithm(CRC_PROBE, 9, 0));
        }

        /* --- cfe_es_resource.c: HOW ES FINDS A RECORD ------------------------------------
         *
         * Four tables -- apps, libraries, tasks, counters -- and three ways into each: by ID,
         * by NAME, and BY CALLING CONTEXT. The third is what every cFS call that says "the
         * calling application" is built on, and it is the one that cannot be checked by
         * reading a counter: it asks OSAL which task is running, maps that to an ES task
         * record, and reads the app id out of it.
         *
         * THE TABLES ARE POPULATED BY HAND HERE because cfe_es_apps.c is not gated -- there is
         * no CFE_ES_AppCreate to call. Writing the records directly is what lets the lookups
         * be exercised at all, and the accessors used to write them are the same ones the
         * lookups use to read, which is a weakness worth naming: a SetUsed/IsUsed pair that
         * agreed on the wrong field would pass. check_padding is what rules that out -- it
         * measures AppId at offset 0 against NASA's compiler. */
        {
            CFE_ES_AppRecord_t        *arp;
            CFE_ES_LibRecord_t        *lrp;
            CFE_ES_TaskRecord_t       *trp;
            CFE_ES_GenCounterRecord_t *crp;

            memset(CFE_ES_Global.AppTable, 0, sizeof(CFE_ES_Global.AppTable));
            memset(CFE_ES_Global.LibTable, 0, sizeof(CFE_ES_Global.LibTable));
            memset(CFE_ES_Global.TaskTable, 0, sizeof(CFE_ES_Global.TaskTable));
            memset(CFE_ES_Global.CounterTable, 0, sizeof(CFE_ES_Global.CounterTable));

            /* App 2 named "ESPROBE", library 1 named "ESLIB", counter 3 named "ESCTR".
             * THE IDS ARE PROPERLY BASED NOW. They were bare small integers while the four
             * *_ToIndex functions were stubs that took them AS the index; cfe_es_api.c is
             * gated, so the real ones subtract CFE_ES_APPID_BASE, CFE_ES_LIBID_BASE and
             * CFE_ES_COUNTID_BASE and a bare 2 does not resolve. That break was recorded in
             * advance beside the stubs, and it arrived: this probe handed NULL to
             * CFE_ES_AppRecordIsUsed and faulted. "slot 5" and "slot 999" keep their meaning
             * -- a free slot and one past the table -- because the base is added to both. */
            arp = &CFE_ES_Global.AppTable[2];
            CFE_ES_AppRecordSetUsed(arp, ES_CTX_APPID(2));
            strncpy((char *)arp->AppName, "ESPROBE", sizeof(arp->AppName) - 1);
            lrp = &CFE_ES_Global.LibTable[1];
            CFE_ES_LibRecordSetUsed(lrp, ES_LIBID(1));
            strncpy((char *)lrp->LibName, "ESLIB", sizeof(lrp->LibName) - 1);
            crp = &CFE_ES_Global.CounterTable[3];
            CFE_ES_CounterRecordSetUsed(crp, ES_CTRID(3));
            strncpy((char *)crp->CounterName, "ESCTR", sizeof(crp->CounterName) - 1);

            /* BY NAME: a hit, a miss, and the record's own id read back. */
            printf("rs_appbyname found=%d id=%lu name=%s\n",
                   (int)(CFE_ES_LocateAppRecordByName("ESPROBE") != NULL),
                   (unsigned long)CFE_RESOURCEID_TO_ULONG(
                       CFE_ES_AppRecordGetID(CFE_ES_LocateAppRecordByName("ESPROBE"))),
                   CFE_ES_AppRecordGetName(CFE_ES_LocateAppRecordByName("ESPROBE")));
            printf("rs_appbyname_miss null=%d\n",
                   (int)(CFE_ES_LocateAppRecordByName("NOSUCHAPP") == NULL));
            printf("rs_libbyname found=%d name=%s\n",
                   (int)(CFE_ES_LocateLibRecordByName("ESLIB") != NULL),
                   CFE_ES_LibRecordGetName(CFE_ES_LocateLibRecordByName("ESLIB")));
            printf("rs_libbyname_miss null=%d\n",
                   (int)(CFE_ES_LocateLibRecordByName("NOSUCHLIB") == NULL));
            printf("rs_ctrbyname found=%d name=%s\n",
                   (int)(CFE_ES_LocateCounterRecordByName("ESCTR") != NULL),
                   CFE_ES_CounterRecordGetName(CFE_ES_LocateCounterRecordByName("ESCTR")));
            printf("rs_ctrbyname_miss null=%d\n",
                   (int)(CFE_ES_LocateCounterRecordByName("NOSUCHCTR") == NULL));

            /* AN UNUSED SLOT IS NOT A NAME MATCH even when the bytes happen to be right. Slot
             * 4 gets the name without the id, so IsUsed is false and the scan must skip it. */
            strncpy((char *)CFE_ES_Global.AppTable[4].AppName, "ESGHOST",
                    sizeof(CFE_ES_Global.AppTable[4].AppName) - 1);
            printf("rs_ghost null=%d\n", (int)(CFE_ES_LocateAppRecordByName("ESGHOST") == NULL));

            /* BY ID: in range, out of range, and the match test that confirms it. */
            arp = CFE_ES_LocateAppRecordByID(CFE_ES_APPID_C(ES_CTX_APPID(2)));
            printf("rs_appbyid nonnull=%d match=%d used=%d\n", (int)(arp != NULL),
                   (int)CFE_ES_AppRecordIsMatch(arp, CFE_ES_APPID_C(ES_CTX_APPID(2))),
                   (int)CFE_ES_AppRecordIsUsed(arp));
            printf("rs_appbyid_oor null=%d\n",
                   (int)(CFE_ES_LocateAppRecordByID(
                             CFE_ES_APPID_C(ES_CTX_APPID(999))) == NULL));
            printf("rs_match_null=%d\n",
                   (int)CFE_ES_AppRecordIsMatch(NULL,
                                                CFE_ES_APPID_C(ES_CTX_APPID(2))));
            lrp = CFE_ES_LocateLibRecordByID(CFE_ES_LIBID_C(ES_LIBID(1)));
            printf("rs_libbyid nonnull=%d match=%d\n", (int)(lrp != NULL),
                   (int)CFE_ES_LibRecordIsMatch(lrp, CFE_ES_LIBID_C(ES_LIBID(1))));
            crp = CFE_ES_LocateCounterRecordByID(
                CFE_ES_COUNTERID_C(ES_CTRID(3)));
            printf("rs_ctrbyid nonnull=%d match=%d\n", (int)(crp != NULL),
                   (int)CFE_ES_CounterRecordIsMatch(
                       crp, CFE_ES_COUNTERID_C(ES_CTRID(3))));

            /* WHAT THIS DOES AND DOES NOT CHECK, because the first version of this comment
             * claimed more than the numbers support. CFE_RESOURCEID_MARK is 0 in the SIMPLE
             * resourceid variant this port builds -- it is 0x02000000 only under EDS -- so the
             * XOR is a NO-OP here and a round trip cannot distinguish "XOR with 0" from "no
             * XOR at all".
             *
             * It is still not vacuous: `id7=7` pins the round trip's PLUMBING -- that both
             * conversions exist and are inverses. The CONSTANT itself is owned by
             * check_constants.py, which was shown to fail on a MARK of 0x02000000 before the
             * transcript even runs, and that is the stronger guard of the two. Under EDS both
             * numbers here change, which is the configuration-dependence the resourceid
             * translation already records. */
            printf("rs_osal_rt id7=%lu back=%lu\n",
                   (unsigned long)CFE_ES_TaskId_ToOSAL(
                       CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(7))),
                   (unsigned long)CFE_RESOURCEID_TO_ULONG(
                       CFE_ES_TaskId_FromOSAL(CFE_ES_TaskId_ToOSAL(
                           CFE_ES_TASKID_C(CFE_ResourceId_FromInteger(7))))));

            /* BY CONTEXT. es_os_taskid is what OS_TaskGetId reports, and the task record it
             * lands on has to be marked used AND carry the app id, or the two-hop lookup
             * returns NULL at the first or the second step. Both failures are driven. */
            trp = &CFE_ES_Global.TaskTable[0];
            CFE_ES_TaskRecordSetUsed(trp, CFE_ResourceId_FromInteger(
                                              CFE_RESOURCEID_TO_ULONG(CFE_ES_TaskId_FromOSAL(1))));
            strncpy((char *)trp->TaskName, "ESTASK", sizeof(trp->TaskName) - 1);
            trp->AppId = CFE_ES_APPID_C(ES_CTX_APPID(2));
            printf("rs_ctx_task nonnull=%d name=%s\n",
                   (int)(CFE_ES_GetTaskRecordByContext() != NULL),
                   CFE_ES_TaskRecordGetName(&CFE_ES_Global.TaskTable[0]));
            printf("rs_ctx_app nonnull=%d name=%s\n",
                   (int)(CFE_ES_GetAppRecordByContext() != NULL),
                   CFE_ES_AppRecordGetName(&CFE_ES_Global.AppTable[2]));
            /* step 2 fails: the task's app id points at a free slot */
            trp->AppId = CFE_ES_APPID_C(ES_CTX_APPID(5));
            printf("rs_ctx_app_noapp null=%d\n", (int)(CFE_ES_GetAppRecordByContext() == NULL));
            /* step 1 fails: the task record is free */
            CFE_ES_TaskRecordSetFree(trp);
            printf("rs_ctx_task_free null=%d app_null=%d\n",
                   (int)(CFE_ES_GetTaskRecordByContext() == NULL),
                   (int)(CFE_ES_GetAppRecordByContext() == NULL));

            /* THE FOUR SLOT-USED PREDICATES FAIL SAFE BY SAYING "TAKEN". An out-of-range id
             * gives NULL, and claiming the slot is in use is what makes
             * CFE_ResourceId_FindNext move on rather than hand it out -- so the answer for a
             * bad id is TRUE, which reads backwards until you know why. */
            printf("rs_slot app2=%d app5=%d appoor=%d\n",
                   (int)CFE_ES_CheckAppIdSlotUsed(ES_CTX_APPID(2)),
                   (int)CFE_ES_CheckAppIdSlotUsed(ES_CTX_APPID(5)),
                   (int)CFE_ES_CheckAppIdSlotUsed(ES_CTX_APPID(999)));
            printf("rs_slot lib1=%d lib5=%d ctr3=%d ctr0=%d\n",
                   (int)CFE_ES_CheckLibIdSlotUsed(ES_LIBID(1)),
                   (int)CFE_ES_CheckLibIdSlotUsed(ES_LIBID(5)),
                   (int)CFE_ES_CheckCounterIdSlotUsed(ES_CTRID(3)),
                   (int)CFE_ES_CheckCounterIdSlotUsed(ES_CTRID(0)));

            /* SetFree really frees: the same lookups that found these must stop finding them. */
            CFE_ES_AppRecordSetFree(&CFE_ES_Global.AppTable[2]);
            CFE_ES_LibRecordSetFree(&CFE_ES_Global.LibTable[1]);
            CFE_ES_CounterRecordSetFree(&CFE_ES_Global.CounterTable[3]);
            printf("rs_freed app=%d lib=%d ctr=%d\n",
                   (int)(CFE_ES_LocateAppRecordByName("ESPROBE") == NULL),
                   (int)(CFE_ES_LocateLibRecordByName("ESLIB") == NULL),
                   (int)(CFE_ES_LocateCounterRecordByName("ESCTR") == NULL));

            /* AND PUT THE DRIVER'S CONTEXT BACK. This block memset all four ES tables and then
             * freed the records it made, including TaskTable[0] -- which is the task record
             * CFE_ES_GetAppID walks to answer "who is calling". Everything after this point
             * that asks ES who it is would get CFE_ES_ERR_RESOURCEID_NOT_VALID, silently, and
             * the transcript would still match because both halves would be equally wrong. */
            es_ctx_init();
        }

        /* --- cfe_es_syslog.c: THE SYSTEM LOG ---------------------------------------------
         *
         * CFE_ES_WriteToSysLog appears in every module's error path and has been a six-line
         * recording stub in this file since EVS. The real thing is an 8 KiB RING BUFFER IN THE
         * RESET AREA, and its output IS the comparison: every "syslog ..." line already in the
         * transcript above goes through a stub, and these go through NASA's formatter, its
         * timestamp, its whitespace strip and its wrap logic.
         *
         * The reset area has to be aimed first -- the log lives there, not in CFE_ES_Global --
         * which is the one thing a caller must do before any of this works. */
        {
            CFE_ES_SysLogReadBuffer_t rdbuf;
            int                       k;

            memset(&es_reset_area, 0, sizeof(es_reset_area));
            CFE_ES_Global.ResetDataPtr = &es_reset_area;
            CFE_ES_Global.ResetDataPtr->SystemLogMode = CFE_ES_LogMode_DISCARD;
            CFE_ES_SysLogClear_Unsync();
            printf("sl_clear w=%lu e=%lu n=%u\n",
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx,
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogEndIdx,
                   CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);

            /* THE APPEND PATH, directly -- no timestamp, no formatting, just the ring. The
             * copy is MessageLen-1 bytes and the last byte is forced to a newline, so a string
             * that ends in one is unchanged and one that does not gets its last character
             * REPLACED. Both are below, and the second is the surprising one. */
            printf("sl_app1 rc=%ld w=%lu n=%u\n", (long)CFE_ES_SysLogAppend_Unsync("first\n"),
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx,
                   CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
            printf("sl_app2 rc=%ld w=%lu\n", (long)CFE_ES_SysLogAppend_Unsync("no-newline"),
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
            printf("sl_bytes");
            for (k = 0; k < 17; k++)
                printf(" %02x", (unsigned int)(unsigned char)CFE_ES_Global.ResetDataPtr->SystemLog[k]);
            printf("\n");
            /* an empty message is not logged at all, and does not count */
            printf("sl_empty rc=%ld w=%lu n=%u\n", (long)CFE_ES_SysLogAppend_Unsync(""),
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx,
                   CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);

            /* THE FORMATTER. This is the one whose output the transcript is really comparing:
             * NASA's timestamp, then the format, then ALL trailing whitespace stripped and
             * exactly one newline added -- whether or not the caller supplied one. */
            printf("sl_write rc=%ld\n", (long)CFE_ES_SysLogWrite_Unsync("plain %d %s\n", 42, "txt"));
            printf("sl_write_nonl rc=%ld\n", (long)CFE_ES_SysLogWrite_Unsync("no newline %u", 7u));
            printf("sl_write_ws rc=%ld\n", (long)CFE_ES_SysLogWrite_Unsync("trailing   \t\n\n"));

            /* MODE: the two valid values and one that is not. DISCARD is the default, which is
             * the opposite of what a ring buffer usually does -- the FIRST messages after a
             * fault are the ones that explain it. */
            printf("sl_mode_ov rc=%ld m=%u\n", (long)CFE_ES_SysLogSetMode(CFE_ES_LogMode_OVERWRITE),
                   CFE_ES_Global.ResetDataPtr->SystemLogMode);
            printf("sl_mode_di rc=%ld m=%u\n", (long)CFE_ES_SysLogSetMode(CFE_ES_LogMode_DISCARD),
                   CFE_ES_Global.ResetDataPtr->SystemLogMode);
            printf("sl_mode_bad rc=%ld m=%u\n", (long)CFE_ES_SysLogSetMode(99),
                   CFE_ES_Global.ResetDataPtr->SystemLogMode);

            /* A SINGLE MESSAGE MAY NOT EXCEED HALF THE LOG, and that check comes before any
             * wrap logic -- so it reports TRUNCATED and still logs 4096 bytes. */
            memset(es_big_msg, 'A', sizeof(es_big_msg) - 1);
            es_big_msg[sizeof(es_big_msg) - 1] = 0;
            CFE_ES_SysLogClear_Unsync();
            printf("sl_huge rc=%ld w=%lu\n", (long)CFE_ES_SysLogAppend_Unsync(es_big_msg),
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);

            /* READ BACK: start a read, then pull blocks. The log has not wrapped, so this is
             * NOT a fragment and no tag is prepended. */
            CFE_ES_SysLogReadStart_Unsync(&rdbuf);
            printf("sl_rdstart frag=%d left=%lu last=%lu end=%lu\n", (int)rdbuf.IsFragment,
                   (unsigned long)rdbuf.SizeLeft, (unsigned long)rdbuf.LastOffset,
                   (unsigned long)rdbuf.EndIdx);
            CFE_ES_SysLogReadData(&rdbuf);
            printf("sl_rd1 block=%lu left=%lu first=%c\n", (unsigned long)rdbuf.BlockSize,
                   (unsigned long)rdbuf.SizeLeft, rdbuf.Data[0]);
            CFE_ES_SysLogReadData(&rdbuf);
            printf("sl_rd2 block=%lu left=%lu\n", (unsigned long)rdbuf.BlockSize,
                   (unsigned long)rdbuf.SizeLeft);

            /* THE WRAP, and the FRAGMENT TAG it produces. In OVERWRITE mode a message that will
             * not fit resets WriteIdx to 0 and records the old tail in EndIdx -- so a reader
             * starting at WriteIdx is now mid-message, IsFragment is true, and
             * CFE_ES_SysLogReadData prepends the literal "<<FRAGMENT>> ". That string is in
             * the dump file, which is why it is checked here character for character. */
            CFE_ES_SysLogClear_Unsync();
            CFE_ES_SysLogSetMode(CFE_ES_LogMode_OVERWRITE);
            for (k = 0; k < 3; k++)
                CFE_ES_SysLogAppend_Unsync(es_big_msg);
            printf("sl_wrapped w=%lu e=%lu n=%u\n",
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx,
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogEndIdx,
                   CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
            CFE_ES_SysLogReadStart_Unsync(&rdbuf);
            printf("sl_frag_start frag=%d left=%lu last=%lu end=%lu\n", (int)rdbuf.IsFragment,
                   (unsigned long)rdbuf.SizeLeft, (unsigned long)rdbuf.LastOffset,
                   (unsigned long)rdbuf.EndIdx);
            CFE_ES_SysLogReadData(&rdbuf);
            printf("sl_frag_tag %.13s| block=%lu frag=%d\n", rdbuf.Data,
                   (unsigned long)rdbuf.BlockSize, (int)rdbuf.IsFragment);

            /* DISCARD at the very end of the buffer: too little room even for a timestamp, so
             * the whole message goes and the return is FULL rather than TRUNCATED. */
            CFE_ES_SysLogClear_Unsync();
            CFE_ES_SysLogSetMode(CFE_ES_LogMode_DISCARD);
            CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE - 4;
            printf("sl_full rc=%ld\n", (long)CFE_ES_SysLogAppend_Unsync("too late\n"));
            CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE - 64;
            printf("sl_trunc rc=%ld w=%lu\n", (long)CFE_ES_SysLogAppend_Unsync(es_big_msg),
                   (unsigned long)CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);

            /* THE DUMP, to the simulated filesystem, and the lock counters with it: exactly
             * ONE take/give pair however many blocks get written, because NASA locks only for
             * the first read and says at length why. */
            CFE_ES_SysLogClear_Unsync();
            CFE_ES_SysLogSetMode(CFE_ES_LogMode_DISCARD);
            CFE_ES_SysLogWrite_Unsync("dumped entry %d\n", 1);
            CFE_ES_Global.TaskData.HkPacket.Payload.SysLogEntries =
                CFE_ES_Global.ResetDataPtr->SystemLogEntryNum;
            es_lock_takes = 0;
            es_lock_gives = 0;
            fs_len = 0;
            fs_pos = 0;
            printf("sl_dump rc=%ld takes=%ld gives=%ld len=%ld\n",
                   (long)CFE_ES_SysLogDump("/ram/syslog.dat"), es_lock_takes, es_lock_gives,
                   (long)fs_len);
            /* and the two failure paths: a create that fails, and a write that fails */
            fs_open_fail = 1;
            printf("sl_dump_nocreate rc=%ld\n", (long)CFE_ES_SysLogDump("/ram/syslog.dat"));
            fs_open_fail = 0;
            fs_len = 0;
            fs_pos = 0;
            fs_wr_left = 8;
            printf("sl_dump_wrfail rc=%ld errs=%ld\n", (long)CFE_ES_SysLogDump("/ram/syslog.dat"),
                   es_bytecnt_errs);
            fs_wr_left = -1;
        }


        /* --- cfe_time_objtab.c ------------------------------------------------------------ */
        printf("tim_objtab %s %d %d %d %lu %lu\n", CFE_TIME_ModuleEntry.Name,
               (int)(CFE_TIME_ModuleEntry.EarlyInit == NULL),
               (int)(CFE_TIME_ModuleEntry.TaskMain == NULL),
               (int)(CFE_TIME_ModuleEntry.AppCleanupCb == NULL),
               (unsigned long)CFE_TIME_ModuleEntry.Priority,
               (unsigned long)CFE_TIME_ModuleEntry.StackSize);
    }
    return 0;
}




