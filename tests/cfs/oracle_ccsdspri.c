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
#include "cfe_es_cds_mempool.h" /* CDSBlockWrite/Read and CDSReqdMinSize */
#include "cfe_es_core_internal.h" /* CFE_ES_RegisterCDSEx, which core_private declares */
#include "cfe_es_perf.h"
#include "cfe_es_log.h"
#include "cfe_es_global.h"
#include "cfe_es_resource.h"  /* the four record tables' accessors and locators */
#include "cfe_es_task.h"      /* ES's task and its twenty-two ground command handlers */
#include "cfe_es_msg.h"       /* and the message formats they take */
#include "cfe_es_perf.h"      /* the perf log, its dump state machine and its masks */
#include "cfe_es_dispatch.h"  /* CFE_ES_TaskPipe and the ground-command switch */
#include "cfe_es_start.h"     /* CFE_ES_SetupPerfVariables, which lives with ES's startup */
#include "cfe_es_startupscript.h" /* the parser, its two sizes and the line reader */
#include "cfe_sb_eventids.h"   /* the event ids the subscribe counters switch on */
#include "cfe_evs_msgids.h"   /* CFE_EVS_CMD_MID, CFE_EVS_SEND_HK_MID */
/* cfe_es_dispatch.c's local helper, declared the same way and for the same reason as the EVS
 * pair below: NASA puts it at the top of that .c and this exercise drives it directly, so the
 * ground-command switch can be reached without a full message round trip. */
void CFE_ES_ProcessGroundCmd(const CFE_SB_Buffer_t *SBBufPtr);

/* Declared early because three of the OSAL delete stubs that call it are defined above it --
 * they belong with the subsystems whose witnesses they carry, not with the object table. */
static void es_obj_mark(osal_id_t object_id);

/* cfe_es_appctrl.c's two staging functions. NASA puts only CFE_ES_ProcessControlRequest and
 * CFE_ES_RunAppTableScan in cfe_es_appctrl.h; these two are non-static but unheadered, and the
 * exercise calls _Finish directly because that is the only way to reach every row of the
 * control-request event table -- seven of the ten cannot be produced by a live request. */
uint32 CFE_ES_ProcessControlRequest_Start(CFE_ES_AppId_t AppId, char *OrigAppNameBuf,
                                          size_t                   OrigAppNameSz,
                                          CFE_ES_AppStartParams_t *RestartParamPtr);
void   CFE_ES_ProcessControlRequest_Finish(uint32 ControlReq, const char *AppName,
                                           CFE_Status_t StartupStatus, CFE_Status_t CleanupStatus,
                                           CFE_ES_AppId_t NewAppId);

/* CFE_ES_MainTaskSyncDelay LOOKS external -- its definition at cfe_es_start.c:886 has no
 * `static` -- but line 45 forward-declares it WITH `static`, and in C the first declaration's
 * linkage wins. So it is internal and neither half can call it; it is driven through
 * CFE_ES_Main and CFE_ES_CreateObjects, which are its only callers upstream too. */

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
#include "cfe_tbl_task.h"       /* CFE_TBL_Global_t, and the types it is built from */
#include "cfe_tbl_handlelink.h" /* the handle-link list node and its two methods */
#include "cfe_tbl_accdesc.h"    /* the per-app handle and its five accessors */
#include "cfe_tbl_transaction.h" /* CFE_TBL_TxnState_t and its eight accessors */
#include "cfe_tbl_loadbuff.h"  /* the load buffers and their thirteen accessors */
#include "cfe_tbl_regrec.h"    /* the registry record and its twenty */
#include "cfe_tbl_valresult.h" /* the ten validation result blocks and their five */
#include "cfe_tbl_codec.h"     /* the codec seam; passthru is the non-EDS branch */
#include "cfe_tbl_registry.h"  /* the eleven transaction steps that touch the registry */
#include "cfe_tbl_internal.h" /* the four concerns of internal.c, gated below */
#include "cfe_tbl_core_internal.h" /* CFE_TBL_EarlyInit, CFE_TBL_CleanUpApp, TaskMain */
#include "cfe_tbl_dump.h"      /* the three phases of a table dump */
#include "cfe_tbl_load.h"      /* the six-step guard a load passes through */
#include "cfe_tbl_dispatch.h"  /* CFE_TBL_TaskPipe and its twelve-row handler table */
/* MD -- the first cFS APP. md_app.h reaches MD_AppData_t and the message types;
 * md_tblstruct.h is not reachable from it and holds MD_DwellTableLoad_t. */
#include "md_app.h"
#include "md_dwell_pkt.h"
#include "md_dwell_tbl.h"
#include "md_cmds.h"
#include "md_dispatch.h"
#include "md_utils.h"
#include "md_tbldefs.h"
#include "md_tblstruct.h"
/* MM -- the second cFS APP. mm_app.h reaches MM_AppData_t, the message types and the
 * MM_VERIFY_* selectors; mm_filedefs.h is not reachable from it and holds
 * MM_LoadDumpFileHeader_t. mm_eventids.h and mm_perfids.h are reached through mm_utils.c
 * itself. */
#include "mm_app.h"
#include "mm_utils.h"
#include "mm_filedefs.h"
#include "mm_mem8.h"
#include "mm_mem16.h"
#include "mm_mem32.h"
#include "mm_dump.h"
#include "mm_load.h"
#include "mm_cmds.h"
#include "mm_msgids.h"
#include "mm_dispatch.h"
#include "mm_fcncodes.h"
#include "mm_internal_cfg.h"
#include "mm_interface_cfg.h"
/* CS -- the third cFS APP. cs_app.h reaches CS_AppData_t, the message types, the six table
 * entry types and (through cs_table_processing.h) CS_TableWrapper_t, so one header is enough.
 * cs_eventids.h, cs_compute.h and cs_utils.h are reached through CS's own sources. */
#include "cs_app.h"
#include "cs_utils.h"
#include "cs_compute.h"
#include "cs_table_processing.h"
/* TWO OF cs_utils.c's FUNCTIONS ARE IN NO HEADER. CS_CheckGenericNameMatch and
 * CS_SetGenericEntryState are not `static` -- they have external linkage and the exercise below
 * calls them -- but NASA declares neither in cs_utils.h, so a caller outside that file has to
 * state them. Copied verbatim from the definitions in cs_utils.c. */
bool CS_CheckGenericNameMatch(const char *Name1, const char *Name2);
CS_ChecksumState_Enum_t CS_SetGenericEntryState(void *EntryPtr, size_t Offset,
                                               CS_ChecksumState_Enum_t NewState);
#include "cfe_tbl_task_cmds.h" /* the ten ground-command handlers and the HK packers */

/* cfe_msg_objtab.c defines this and no header declares it -- the generated cfe_es_objtab.c is
 * what normally refers to it, by name, from the build system. */
/* The core object table itself, which tools/cfs/gen_target_config.py emits WRITABLE with spare
 * slots so this driver can plant entries into it -- see the note at the CreateObjects probe. */
extern Target_ObjectTable_t *CFE_CORE_MODULE_OBJTAB[4];
extern const Target_ObjectTable_t CFE_MSG_ModuleEntry;
extern const Target_ObjectTable_t CFE_RESOURCEID_ModuleEntry;
extern const Target_ObjectTable_t CFE_FS_ModuleEntry;
extern const Target_ObjectTable_t CFE_EVS_ModuleEntry;
extern const Target_ObjectTable_t CFE_CONFIG_ModuleEntry;
extern const Target_ObjectTable_t CFE_TA_ModuleEntry;
extern const Target_ObjectTable_t CFE_TIME_ModuleEntry;
extern const Target_ObjectTable_t CFE_TBL_ModuleEntry;
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
static int           fs_noexist;       /* make a READ-ONLY open fail: the file is not there */
/* fs_wr_left is the number of bytes the file will still accept, not a per-call cap. A per-call
 * cap of 64 looked like it would make a record write fail and did not: the header write is 64
 * and every record is 10, so each individual write still fit and the run reported COMPLETE. */
static long          fs_wr_left;       /* < 0 = unlimited */
static int           fs_mut_create, fs_mut_take, fs_mut_give;
/* Steer the three mutex calls. Without these, cfe_fs_priv.c's three syslog lines are
 * unreachable -- including the only one in the whole translation that formats three
 * arguments (a status, an app id and a function name), which is exactly the kind of line a
 * restored argument list can be wrong in without anything noticing. */
static int           fs_mut_create_rc, fs_mut_take_rc, fs_mut_give_rc;

/* `fs_noexist` SAYS "THE FILE IS NOT THERE", WHICH `fs_open_fail` COULD NOT. This stub had one
 * knob for both ideas, and cfe_tbl_dump.c is the first code in the port whose behaviour turns
 * on the difference: CFE_TBL_WriteSnapshotToFile opens the dump file READ-ONLY purely to decide
 * between CFE_TBL_OVERWRITE_DUMP_INF_EID and CFE_TBL_WRITE_DUMP_INF_EID, and then opens it for
 * WRITING. With one knob the read-only open always succeeded, so the file always "existed" and
 * the first-write event id was UNREACHABLE -- a branch no transcript could enter. Keyed on
 * access_mode so it cannot affect any existing line: every other caller of this stub writes. */
int32 OS_OpenCreate(osal_id_t *filedes, const char *path, int32 flags, int32 access_mode)
{
    (void)path; (void)flags;
    if (fs_open_fail)
    {
        return OS_ERROR;
    }
    if (fs_noexist && access_mode == OS_READ_ONLY)
    {
        return OS_ERROR;
    }
    fs_fd    = 7;
    *filedes = 7;
    /* A READ-ONLY OPEN MUST NOT TRUNCATE, which this stub used to do unconditionally -- it never
     * mattered until cfe_es_startupscript.c became the first thing in the port to OPEN A FILE
     * AND READ IT. Every other caller writes, so resetting the length was indistinguishable
     * from correct. The startup script is staged into fs_data before the call and would have
     * been erased by it. */
    if (access_mode != OS_READ_ONLY)
    {
        fs_len = 0;
    }
    fs_pos = 0;
    return OS_SUCCESS;
}

int32 OS_close(osal_id_t filedes)
{
    fs_fd = 0;
    es_obj_mark(filedes); /* also an OSAL object a dying task may own -- see es_obj_mark */
    return OS_SUCCESS;
}

/* MAKE OS_read FAIL. mm_utils.c's MM_ComputeCRCFromFile has a branch that runs only on a
 * NEGATIVE return -- it hands the error back INSTEAD of writing the caller's CRC -- and nothing
 * in the port had ever made a read fail, so that branch was unreachable. Defaults to 0, which
 * is "no change", so no existing transcript line can see it. */
static int32 fs_read_rc;

int32 OS_read(osal_id_t filedes, void *buffer, size_t nbytes)
{
    long n = (long)nbytes;
    (void)filedes;
    if (fs_read_rc != 0)
    {
        return fs_read_rc;
    }
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
/* ES's three BASED id spaces. Up here with the mutex id rather than beside es_ctx_init below,
 * because the ES stubs that hand back ids are declared before it. */
#define ES_CTX_APPID(slot) CFE_ResourceId_FromInteger(CFE_ES_APPID_BASE + (slot))
#define ES_LIBID(slot)     CFE_ResourceId_FromInteger(CFE_ES_LIBID_BASE + (slot))
#define ES_CTRID(slot)     CFE_ResourceId_FromInteger(CFE_ES_COUNTID_BASE + (slot))
static long es_lock_takes, es_lock_gives;

/* A DISTINCT ID PER CREATE, and the reason is CFE_TBL_EarlyInit. It creates TWO mutexes and
 * stores them in two different fields of CFE_TBL_Global; while this stub handed back the same
 * id for both, a translation that wrote the registry mutex into WorkBufMutex -- or stored one
 * twice -- produced exactly the transcript a correct one does. The ids start well above
 * ES_SHARED_MUTEX_ID (0x1E5), which the startup sequence plants directly rather than creating,
 * so nothing that keys on that constant is affected. */
int32 OS_MutSemCreate(osal_id_t *sem_id, const char *sem_name, uint32 options)
{
    (void)sem_name; (void)options;
    ++fs_mut_create;
    *sem_id = OS_ObjectIdFromInteger(0x3000 + fs_mut_create);
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
/* CFE_ES_BackgroundWakeup: STUB REMOVED -- its source is gated, the real one runs. */
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

/* CFE_ES_PerfLogAdd: STUB REMOVED -- its source is gated, the real one runs. */
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

/* evs_delays COUNTS CALLS, where evs_delay_ms SUMS MILLISECONDS, and MM is why both exist:
 * MM_SegmentBreak delays for MM_INTERNAL_PROCESSOR_CYCLE, which is 0 in this configuration, so
 * the millisecond total is a zero against a zero and asserts nothing at all. */
static long evs_delays;

int32 OS_TaskDelay(uint32 millisecond)
{
    ++evs_delays;
    evs_delay_ms += millisecond;
    return OS_SUCCESS;
}

/* OS_strnlen IS NASA'S OWN BODY, copied from vendor/osal/src/os/shared/src/osapi-common.c, not
 * a stub standing in for one. OSAL is not gated in THIS driver -- every OS_* here is a
 * simulation -- but this function touches no operating system at all, and mm_utils.c's
 * MM_ResolveSymAddr decides between "the offset IS the address" and "look the symbol up" on its
 * answer. A simulation would be this port inventing that decision. The gated translation lives
 * in Kernel/Cfs/osal/osapi_common.HC and the OSAL differential gate is what compares it. */
size_t OS_strnlen(const char *s, size_t maxlen)
{
    const char *end = (const char *)memchr(s, 0, maxlen);

    if (end != NULL)
    {
        /* actual length of string is difference */
        maxlen = end - s;
    }

    return maxlen;
}

/* CFE_TIME_Tone1HzISR used to be stubbed here, because cfe_time_tone.c was not gated and
 * CFE_TIME_ExternalTone's whole body is a call to it. It is gated now, so the REAL one runs --
 * and the stub had to go on both sides at once, which is the shape every one of these removals
 * has had: the stub is what the gate was measuring until the translation arrived. */

/* CFE_TIME_Global IS NASA'S, defined in cfe_time_task.c, which is gated. It was ALSO defined here, and
 * two tentative definitions merge SILENTLY in C -- the link succeeded and nothing
 * said which object the exercise was reading. tools/cfs/check_oracle_globals.py
 * found all five of these at once and now forbids them. */
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

/* THE BACKGROUND TASK'S DELAY, and its only way out. CFE_ES_BackgroundTask loops forever on
 * OS_BinSemTimedWait and breaks only on a status that is neither OS_SUCCESS nor
 * OS_SEM_TIMEOUT -- so a budget, exactly like time_sem_take_budget above, is what makes the
 * task drivable at all. es_bg_waits counts the passes; es_bg_wait_budget bounds them. */
static long es_bg_waits, es_bg_deletes;
static int  es_bg_wait_budget;

int32 OS_BinSemTimedWait(osal_id_t sem_id, uint32 msecs)
{
    ++es_bg_waits;
    if (es_bg_wait_budget <= 0)
    {
        return OS_ERROR;
    }
    --es_bg_wait_budget;
    return OS_SEM_TIMEOUT;
}

int32 OS_BinSemDelete(osal_id_t sem_id)
{
    ++es_bg_deletes;
    es_obj_mark(sem_id);
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

/* CFE_ES_Global IS NASA'S, defined in cfe_es_start.c, which is gated. It was ALSO defined here, and
 * two tentative definitions merge SILENTLY in C -- the link succeeded and nothing
 * said which object the exercise was reading. tools/cfs/check_oracle_globals.py
 * found all five of these at once and now forbids them. */
static CFE_ES_ResetData_t es_reset_area;

/* CFE_TBL_Global IS NASA'S, defined in cfe_tbl_task.c, which is gated. It was ALSO defined here, and
 * two tentative definitions merge SILENTLY in C -- the link succeeded and nothing
 * said which object the exercise was reading. tools/cfs/check_oracle_globals.py
 * found all five of these at once and now forbids them. */

/* MD_AppData IS NASA'S, defined in md_app.c, which is gated as of this commit. It sat HERE
 * until then, with the note that a C tentative definition in two translation units merges
 * SILENTLY -- and tools/cfs/check_oracle_globals.py, written four commits ago for exactly this
 * deadline, is what would have refused to let the overlap survive. */
/* The ground's view of a dwell table, 2,040 bytes. File scope because the HolyC half needs it
 * there -- limit 22, a big frame makes an unrelated file-scope read return zero -- and the two
 * halves stay one shape. */
/* MM_AppData IS NASA'S, defined in mm_app.c, which is gated as of this commit. It sat HERE
 * until then, with the note that a C tentative definition in two translation units merges
 * SILENTLY -- and tools/cfs/check_oracle_globals.py is what would have refused the overlap.
 * The same deadline MD_AppData had, met the same way. */

/* CS_AppData IS NASA'S, defined in cs_app.c, which is NOT yet gated -- so it lives here, the
 * way MD_AppData and MM_AppData each did until their app file arrived. It MOVES to
 * Kernel/Cfs/cs/cs_global.HC's side of the ledger when cs_app.c is gated in step 3, and
 * tools/cfs/check_oracle_globals.py is what will refuse to let the two definitions coexist --
 * a C tentative definition in two translation units merges SILENTLY. The HolyC half already
 * defines it in cs_global.HC, beside its type, for the reason recorded there. */
CS_AppData_t CS_AppData;

/* ===================== CS, THE THIRD cFS APP -- STEP 1'S STATE =====================
 *
 * CS reads memory DIRECTLY -- CFE_ES_CalculateCRC takes a raw pointer -- so every address the
 * exercise hands it points into one of the two buffers below, filled by cs_fill_sources() with
 * the same arithmetic on both halves. A CRC over equal bytes is equal wherever the bytes live;
 * what cannot cross is PRINTING an address, so every pointer-valued assertion below is a
 * COMPARISON against the pointer this driver handed over.
 *
 * THE SIX WRAPPERS ARE HAND-BUILT because CS_InitAllTables is cs_init.c -- step 2. cs_setup()
 * mirrors NASA's TABLE_INITIALIZERS field for field, with these eight arrays standing in for the
 * buffers table services will allocate once step 2 arrives. Both halves set the same eleven
 * fields in the same order: a wrapper setup that drifted would produce a transcript diff that
 * has nothing to do with CS.
 *
 * AND MaxBytesPerCycle IS SET HERE, which is not a detail. cs_app.c sets it (step 3); at zero
 * CS_DoChecksumChunk clamps every cycle to zero bytes, CurrOffset never advances,
 * CS_IsChecksumComplete is never true -- and the three recompute child tasks' `while
 * (!DoneWithEntry)` does not terminate. That is a QEMU timeout that looks exactly like a codegen
 * bug. It is deliberately set SMALLER than either buffer, so the chunking and the resume-from-
 * ByteOffset path are what the transcript sees rather than a single-shot CRC. */
#define CS_EX_BUDGET 64

static uint8 cs_src_a[200];
static uint8 cs_src_b[120];

static CS_Def_EepromMemory_Table_Entry_t cs_def_eep[CS_MAX_NUM_EEPROM_TABLE_ENTRIES];
static CS_Res_EepromMemory_Table_Entry_t cs_res_eep[CS_MAX_NUM_EEPROM_TABLE_ENTRIES];
static CS_Def_EepromMemory_Table_Entry_t cs_def_mem[CS_MAX_NUM_MEMORY_TABLE_ENTRIES];
static CS_Res_EepromMemory_Table_Entry_t cs_res_mem[CS_MAX_NUM_MEMORY_TABLE_ENTRIES];
static CS_Def_Tables_Table_Entry_t       cs_def_tbl[CS_MAX_NUM_TABLES_TABLE_ENTRIES];
static CS_Res_Tables_Table_Entry_t       cs_res_tbl[CS_MAX_NUM_TABLES_TABLE_ENTRIES];
static CS_Def_App_Table_Entry_t          cs_def_app[CS_MAX_NUM_APP_TABLE_ENTRIES];
static CS_Res_App_Table_Entry_t          cs_res_app[CS_MAX_NUM_APP_TABLE_ENTRIES];

static void cs_fill_sources(void)
{
    int i;
    for (i = 0; i < 200; ++i)
    {
        cs_src_a[i] = (uint8)(i * 7 + 3);
    }
    for (i = 0; i < 120; ++i)
    {
        cs_src_b[i] = (uint8)(i * 11 + 5);
    }
}

static void cs_setup(void)
{
    CS_TableWrapper_t *tw;
    int                i;

    memset(&CS_AppData, 0, sizeof(CS_AppData));
    memset(cs_def_eep, 0, sizeof(cs_def_eep));
    memset(cs_res_eep, 0, sizeof(cs_res_eep));
    memset(cs_def_mem, 0, sizeof(cs_def_mem));
    memset(cs_res_mem, 0, sizeof(cs_res_mem));
    memset(cs_def_tbl, 0, sizeof(cs_def_tbl));
    memset(cs_res_tbl, 0, sizeof(cs_res_tbl));
    memset(cs_def_app, 0, sizeof(cs_def_app));
    memset(cs_res_app, 0, sizeof(cs_res_app));

    CS_AppData.MaxBytesPerCycle = CS_EX_BUDGET;

    /* THE EIGHT TABLE HANDLES ARE EXPLICITLY INVALID, which NASA's initialiser does not do --
     * it leaves them zero, and CS_RegisterResultTable/CS_RegisterDefinitionTable fill them in.
     * That is step 2. Zero IS A VALID cFE TABLE HANDLE (cfe_tbl_internal.HC:110 records why
     * CFE_TBL_BAD_TABLE_HANDLE is -1 and not 0), and MD has already registered tables by the
     * time this runs -- so a wrapper left at zero would make CS_SetDefEntryState's
     * CFE_TBL_Modified mark one of MD's dwell tables as changed. -1 makes it fail predictably
     * instead, and the failure is the behaviour step 1 can honestly exercise. */
    for (i = 0; i < CS_NUM_TABLES; ++i)
    {
        CS_AppData.Tbl[i].DefHandle = CFE_TBL_BAD_TABLE_HANDLE;
        CS_AppData.Tbl[i].ResHandle = CFE_TBL_BAD_TABLE_HANDLE;
    }

    tw                = &CS_AppData.Tbl[CS_ChecksumType_CFECORE];
    tw->BaselineValue = &CS_AppData.HkPacket.Payload.CfeCoreBaseline;
    tw->ResEntrySize  = sizeof(CS_Res_EepromMemory_Table_Entry_t);
    tw->ResAddr       = &CS_AppData.CfeCoreCodeSeg;
    tw->NumEntries    = 1;

    tw                = &CS_AppData.Tbl[CS_ChecksumType_OSCORE];
    tw->BaselineValue = &CS_AppData.HkPacket.Payload.OSBaseline;
    tw->ResEntrySize  = sizeof(CS_Res_EepromMemory_Table_Entry_t);
    tw->ResAddr       = &CS_AppData.OSCodeSeg;
    tw->NumEntries    = 1;

    tw                       = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
    tw->DefTableName         = CS_DEF_EEPROM_TABLE_NAME;
    tw->ResTableName         = CS_RESULTS_EEPROM_TABLE_NAME;
    tw->GlobalState          = &CS_AppData.HkPacket.Payload.EepromCSState;
    tw->NumEntries           = CS_MAX_NUM_EEPROM_TABLE_ENTRIES;
    tw->DefEntrySize         = sizeof(CS_Def_EepromMemory_Table_Entry_t);
    tw->ResEntrySize         = sizeof(CS_Res_EepromMemory_Table_Entry_t);
    tw->DefStateOffset       = offsetof(CS_Def_EepromMemory_Table_Entry_t, State);
    tw->UpdateHandler        = CS_ProcessNewEepromMemoryDefinitionTable;
    tw->DefaultDefinitionPtr = CS_AppData.DefaultEepromDefTable;
    tw->DefAddr              = cs_def_eep;
    tw->ResAddr              = cs_res_eep;

    tw                       = &CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE];
    tw->DefTableName         = CS_DEF_MEMORY_TABLE_NAME;
    tw->ResTableName         = CS_RESULTS_MEMORY_TABLE_NAME;
    tw->GlobalState          = &CS_AppData.HkPacket.Payload.MemoryCSState;
    tw->NumEntries           = CS_MAX_NUM_MEMORY_TABLE_ENTRIES;
    tw->DefEntrySize         = sizeof(CS_Def_EepromMemory_Table_Entry_t);
    tw->ResEntrySize         = sizeof(CS_Res_EepromMemory_Table_Entry_t);
    tw->DefStateOffset       = offsetof(CS_Def_EepromMemory_Table_Entry_t, State);
    tw->UpdateHandler        = CS_ProcessNewEepromMemoryDefinitionTable;
    tw->DefaultDefinitionPtr = CS_AppData.DefaultMemoryDefTable;
    tw->DefAddr              = cs_def_mem;
    tw->ResAddr              = cs_res_mem;

    tw                       = &CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE];
    tw->DefTableName         = CS_DEF_TABLES_TABLE_NAME;
    tw->ResTableName         = CS_RESULTS_TABLES_TABLE_NAME;
    tw->GlobalState          = &CS_AppData.HkPacket.Payload.TablesCSState;
    tw->NumEntries           = CS_MAX_NUM_TABLES_TABLE_ENTRIES;
    tw->DefEntrySize         = sizeof(CS_Def_Tables_Table_Entry_t);
    tw->ResEntrySize         = sizeof(CS_Res_Tables_Table_Entry_t);
    tw->DefStateOffset       = offsetof(CS_Def_Tables_Table_Entry_t, State);
    tw->UpdateHandler        = CS_ProcessNewTablesDefinitionTable;
    tw->DefaultDefinitionPtr = CS_AppData.DefaultTablesDefTable;
    tw->DefAddr              = cs_def_tbl;
    tw->ResAddr              = cs_res_tbl;

    tw                       = &CS_AppData.Tbl[CS_ChecksumType_APP_TABLE];
    tw->DefTableName         = CS_DEF_APP_TABLE_NAME;
    tw->ResTableName         = CS_RESULTS_APP_TABLE_NAME;
    tw->GlobalState          = &CS_AppData.HkPacket.Payload.AppCSState;
    tw->NumEntries           = CS_MAX_NUM_APP_TABLE_ENTRIES;
    tw->DefEntrySize         = sizeof(CS_Def_App_Table_Entry_t);
    tw->ResEntrySize         = sizeof(CS_Res_App_Table_Entry_t);
    tw->DefStateOffset       = offsetof(CS_Def_App_Table_Entry_t, State);
    tw->UpdateHandler        = CS_ProcessNewAppDefinitionTable;
    tw->DefaultDefinitionPtr = CS_AppData.DefaultAppDefTable;
    tw->DefAddr              = cs_def_app;
    tw->ResAddr              = cs_res_app;
}

/* ======================= CS, step 1 of three: cs_utils.c ======================
 *
 * The twenty-six functions of CS's utility layer, in NASA's own order. Nothing here needs table
 * services or a child task; those are the two blocks after it.
 *
 * ITS OWN FUNCTION, ON BOTH HALVES, and only the HolyC half needs it to be: written as a block
 * inside main() this section grew that frame enough to make a FILE-SCOPE `&function` initialiser
 * read as zero, and the transcript died 1,900 lines earlier at `cp->Algorithm(...)` in the crc
 * section with `TRAP mcause=0x1 (insn-fault) mepc=0x0`. That is the open limit recorded as
 * "a stack frame zeroes a global", third sighting, and the measured fix is exactly this: a called
 * function gets its own frame and costs main() nothing. The diagnosis was cheap only because the
 * shape was already written down -- a section JUST added, plus a trap at mepc=0 somewhere else,
 * plus a function POINTER at the fault site. */
static void cs_block_utils(void)
{
        CS_TableWrapper_t                 *tw;
        CS_Res_EepromMemory_Table_Entry_t *re;
        CS_Def_EepromMemory_Table_Entry_t *de;
        CS_Res_Tables_Table_Entry_t       *rt;
        CS_Def_Tables_Table_Entry_t       *dt;
        CS_Res_App_Table_Entry_t          *ra;
        CS_Def_App_Table_Entry_t          *da;
        uint16                             st;
        bool                               csb;
        int                                k;

        cs_fill_sources();
        cs_setup();

        /* --- CS_CheckGenericNameMatch, and the two wrappers over it. The NULL-safety is the
         * whole point: four of the six wrappers have no DefTableName at all, so
         * CS_CheckDefTableNameMatch(name, CS_ChecksumType_CFECORE) asks whether a name
         * matches NULL. strcmp would fault. */
        printf("csu_namematch %d %d %d %d\n", (int)CS_CheckGenericNameMatch(NULL, NULL),
               (int)CS_CheckGenericNameMatch(NULL, "DefEepromTbl"),
               (int)CS_CheckGenericNameMatch("DefEepromTbl", "DefEepromTbl"),
               (int)CS_CheckGenericNameMatch("DefEepromTbl", "DefMemoryTbl"));
        printf("csu_tblnamematch d=%d%d%d r=%d%d%d\n",
               (int)CS_CheckDefTableNameMatch("DefEepromTbl", CS_ChecksumType_EEPROM_TABLE),
               (int)CS_CheckDefTableNameMatch("ResEepromTbl", CS_ChecksumType_EEPROM_TABLE),
               (int)CS_CheckDefTableNameMatch("DefEepromTbl", CS_ChecksumType_CFECORE),
               (int)CS_CheckResTableNameMatch("ResEepromTbl", CS_ChecksumType_EEPROM_TABLE),
               (int)CS_CheckResTableNameMatch("DefEepromTbl", CS_ChecksumType_EEPROM_TABLE),
               (int)CS_CheckResTableNameMatch("ResEepromTbl", CS_ChecksumType_OSCORE));

        /* --- CS_GetDefEntryAddr and CS_GetResEntryAddr. The answers are POINTERS, so every
         * line is a comparison against the array this driver handed the wrapper -- see the
         * note on cs_src_a above. The fourth column is the one that matters: index 16 is one
         * past the end of a 16-entry table and must be NULL, because that NULL return is the
         * ONLY terminator eleven `while (true)` loops in cs_utils.c have. */
        tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
        printf("csu_entryaddr def=%d%d%d%d res=%d%d%d%d codeseg=%d%d\n",
               (int)(CS_GetDefEntryAddr(tw, 0) == (void *)&cs_def_eep[0]),
               (int)(CS_GetDefEntryAddr(tw, 1) == (void *)&cs_def_eep[1]),
               (int)(CS_GetDefEntryAddr(tw, 15) == (void *)&cs_def_eep[15]),
               (int)(CS_GetDefEntryAddr(tw, 16) == NULL),
               (int)(CS_GetResEntryAddr(tw, 0) == (void *)&cs_res_eep[0]),
               (int)(CS_GetResEntryAddr(tw, 1) == (void *)&cs_res_eep[1]),
               (int)(CS_GetResEntryAddr(tw, 15) == (void *)&cs_res_eep[15]),
               (int)(CS_GetResEntryAddr(tw, 16) == NULL),
               /* The cFE core wrapper has NO definition table -- DefAddr is NULL -- and ONE
                * results entry, which is CS_AppData.CfeCoreCodeSeg itself. */
               (int)(CS_GetDefEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_CFECORE], 0) == NULL),
               (int)(CS_GetResEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_CFECORE], 1) == NULL));
        /* AND THE ODD-SIZED TABLES, whose stride is 42 and 22 rather than a multiple of 8 --
         * the arithmetic tests/exec/cases/e_tbl_wrapper_idiom.hc measures in isolation,
         * here through the generic indexer every CS loop goes through. */
        printf("csu_oddstride tbl=%d%d app=%d%d\n",
               (int)(CS_GetTablesDefEntry(1) == &cs_def_tbl[1]),
               (int)(CS_GetTablesDefEntry(23) == &cs_def_tbl[23]),
               (int)(CS_GetAppDefEntry(1) == &cs_def_app[1]),
               (int)(CS_GetAppDefEntry(23) == &cs_def_app[23]));

        /* --- CS_StateValid, and the four states. ENABLED and DISABLED are commandable;
         * EMPTY and UNDEFINED are not, and that distinction is what makes
         * CS_SetGenericEntryState refuse twice. */
        printf("csu_statevalid %d%d%d%d\n", (int)CS_StateValid(CS_ChecksumState_EMPTY),
               (int)CS_StateValid(CS_ChecksumState_ENABLED),
               (int)CS_StateValid(CS_ChecksumState_DISABLED),
               (int)CS_StateValid(CS_ChecksumState_UNDEFINED));

        /* --- CS_SetGenericEntryState, the generic poke. The THREE refusals and the one
         * write, and each line prints what the entry's State is AFTERWARDS -- a return value
         * saying "I refused" is not evidence that nothing was written. */
        de        = &cs_def_eep[3];
        de->State = CS_ChecksumState_EMPTY;
        st        = CS_SetGenericEntryState(de, offsetof(CS_Def_EepromMemory_Table_Entry_t, State),
                                            CS_ChecksumState_ENABLED);
        printf("csu_setgeneric from_empty prev=%u now=%u\n", (unsigned)st, (unsigned)de->State);
        de->State = CS_ChecksumState_ENABLED;
        st        = CS_SetGenericEntryState(de, offsetof(CS_Def_EepromMemory_Table_Entry_t, State),
                                            CS_ChecksumState_DISABLED);
        printf("csu_setgeneric enabled_to_disabled prev=%u now=%u\n", (unsigned)st,
               (unsigned)de->State);
        st = CS_SetGenericEntryState(de, offsetof(CS_Def_EepromMemory_Table_Entry_t, State),
                                     CS_ChecksumState_EMPTY);
        printf("csu_setgeneric to_empty prev=%u now=%u\n", (unsigned)st, (unsigned)de->State);
        /* AN OFFSET OTHER THAN ZERO IS THE REASON DefStateOffset EXISTS. The tables and app
         * entries keep State at offset 0 and the EEPROM/Memory entry keeps it at 8; this is
         * the same function reaching both. */
        dt        = &cs_def_tbl[2];
        dt->State = CS_ChecksumState_DISABLED;
        st = CS_SetGenericEntryState(dt, offsetof(CS_Def_Tables_Table_Entry_t, State),
                                     CS_ChecksumState_ENABLED);
        printf("csu_setgeneric tbl_off0 prev=%u now=%u\n", (unsigned)st, (unsigned)dt->State);

        /* --- CS_SetDefEntryState, which is the above PLUS two side effects, and they only
         * happen when the state actually MOVED. ResTblPtr is aimed at a results entry with
         * work in progress; a real move clears it, a no-op move leaves it. */
        tw             = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
        tw->ResTblPtr  = &cs_res_tbl[5];
        cs_res_tbl[5].ByteOffset        = 40;
        cs_res_tbl[5].TempChecksumValue = 0x1234;
        cs_res_tbl[5].ComputedYet       = true;
        de             = &cs_def_eep[4];
        de->State      = CS_ChecksumState_ENABLED;
        st             = CS_SetDefEntryState(tw, de, CS_ChecksumState_DISABLED);
        printf("csu_setdef moved prev=%u now=%u off=%u temp=%u yet=%u\n", (unsigned)st,
               (unsigned)de->State, (unsigned)cs_res_tbl[5].ByteOffset,
               (unsigned)cs_res_tbl[5].TempChecksumValue,
               (unsigned)cs_res_tbl[5].ComputedYet);
        cs_res_tbl[5].ByteOffset = 40;
        st = CS_SetDefEntryState(tw, de, CS_ChecksumState_DISABLED);
        printf("csu_setdef same prev=%u now=%u off=%u\n", (unsigned)st, (unsigned)de->State,
               (unsigned)cs_res_tbl[5].ByteOffset);
        /* AND WITH NO ResTblPtr AT ALL, which is the state five of the six wrappers are in
         * until a tables table names one of CS's own tables. CS_ResetTablesTblResultEntry is
         * NULL-safe for exactly this. */
        tw->ResTblPtr = NULL;
        de->State     = CS_ChecksumState_DISABLED;
        st            = CS_SetDefEntryState(tw, de, CS_ChecksumState_ENABLED);
        printf("csu_setdef noresptr prev=%u now=%u\n", (unsigned)st, (unsigned)de->State);

        /* --- CS_GetTableTypeAsString, all six plus the default. The default arm is
         * unreachable through CS's own code because every caller passes &CS_AppData.Tbl[n];
         * CS_GetTableId is a pointer SUBTRACTION, so a wrapper one past the end lands there
         * rather than indexing off a jump table. */
        printf("csu_typestr");
        for (k = 0; k < CS_NUM_TABLES; ++k)
        {
            printf(" %s", CS_GetTableTypeAsString(&CS_AppData.Tbl[k]));
        }
        /* `CS_AppData.Tbl + CS_NUM_TABLES`, NOT `&CS_AppData.Tbl[0] + CS_NUM_TABLES`. The
         * second spelling was the first draft and it produced the only transcript diff this whole
         * block had: adding an integer to `&array[i]` scales by EIGHT rather than by the element
         * size, so 6 * 8 = 48 bytes is still inside a 112-byte element 0, CS_GetTableId answered
         * 0, and the line read "cFE Core" where NASA's C read "Undef". A second surface of the
         * limit docs/HOLYC_STRUCT_LIMITS.md #4 records, pinned by
         * tests/exec/cases/e_amp_index_plus_int.hc. */
        printf(" %s\n", CS_GetTableTypeAsString(CS_AppData.Tbl + CS_NUM_TABLES));
        /* CS_GetTableId and CS_CheckTableId, the two halves of the pointer arithmetic. */
        printf("csu_tableid %d %d %d %d\n", (int)CS_GetTableId(&CS_AppData.Tbl[0]),
               (int)CS_GetTableId(&CS_AppData.Tbl[5]),
               (int)CS_CheckTableId(&CS_AppData.Tbl[4], CS_ChecksumType_TABLES_TABLE),
               (int)CS_CheckTableId(&CS_AppData.Tbl[4], CS_ChecksumType_APP_TABLE));

        /* --- THE SIX Zero*TempValues. Poison every entry first, so a function that cleared
         * nothing and a function that cleared everything are distinguishable -- and print the
         * LAST entry as well as the first, because a loop that stopped after one would
         * otherwise look right. */
        for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k)
        {
            cs_res_eep[k].TempChecksumValue = 0xAA00 + k;
            cs_res_eep[k].ByteOffset        = 0xBB00 + k;
            cs_res_mem[k].TempChecksumValue = 0xCC00 + k;
            cs_res_mem[k].ByteOffset        = 0xDD00 + k;
        }
        for (k = 0; k < CS_MAX_NUM_TABLES_TABLE_ENTRIES; ++k)
        {
            cs_res_tbl[k].TempChecksumValue = 0xEE00 + k;
            cs_res_tbl[k].ByteOffset        = 0xFF00 + k;
            cs_res_app[k].TempChecksumValue = 0x1100 + k;
            cs_res_app[k].ByteOffset        = 0x2200 + k;
        }
        CS_AppData.CfeCoreCodeSeg.TempChecksumValue = 0x3300;
        CS_AppData.CfeCoreCodeSeg.ByteOffset        = 0x4400;
        CS_AppData.OSCodeSeg.TempChecksumValue      = 0x5500;
        CS_AppData.OSCodeSeg.ByteOffset             = 0x6600;
        CS_ZeroEepromTempValues();
        CS_ZeroMemoryTempValues();
        CS_ZeroTablesTempValues();
        CS_ZeroAppTempValues();
        CS_ZeroCfeCoreTempValues();
        CS_ZeroOSTempValues();
        printf("csu_zerotemp eep=%u,%u,%u,%u mem=%u,%u tbl=%u,%u app=%u,%u seg=%u,%u,%u,%u\n",
               (unsigned)cs_res_eep[0].TempChecksumValue, (unsigned)cs_res_eep[0].ByteOffset,
               (unsigned)cs_res_eep[15].TempChecksumValue, (unsigned)cs_res_eep[15].ByteOffset,
               (unsigned)cs_res_mem[15].TempChecksumValue, (unsigned)cs_res_mem[15].ByteOffset,
               (unsigned)cs_res_tbl[23].TempChecksumValue, (unsigned)cs_res_tbl[23].ByteOffset,
               (unsigned)cs_res_app[23].TempChecksumValue, (unsigned)cs_res_app[23].ByteOffset,
               (unsigned)CS_AppData.CfeCoreCodeSeg.TempChecksumValue,
               (unsigned)CS_AppData.CfeCoreCodeSeg.ByteOffset,
               (unsigned)CS_AppData.OSCodeSeg.TempChecksumValue,
               (unsigned)CS_AppData.OSCodeSeg.ByteOffset);

        /* --- CS_InitializeDefaultTables, the cold-boot fallback. Poisoned first, and the
         * two NAME tables are checked at Name[0] AND Name[1]: NASA clears only the first
         * byte, so a translation that cleared the whole name would pass a weaker check and
         * fail this one. */
        for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k)
        {
            CS_AppData.DefaultEepromDefTable[k].State              = CS_ChecksumState_ENABLED;
            CS_AppData.DefaultEepromDefTable[k].NumBytesToChecksum = 99;
            CS_AppData.DefaultEepromDefTable[k].StartAddress       = 0x1000;
            CS_AppData.DefaultMemoryDefTable[k].State              = CS_ChecksumState_ENABLED;
            CS_AppData.DefaultMemoryDefTable[k].NumBytesToChecksum = 98;
            CS_AppData.DefaultMemoryDefTable[k].StartAddress       = 0x2000;
        }
        for (k = 0; k < CS_MAX_NUM_TABLES_TABLE_ENTRIES; ++k)
        {
            CS_AppData.DefaultTablesDefTable[k].State   = CS_ChecksumState_ENABLED;
            CS_AppData.DefaultTablesDefTable[k].Name[0] = 'Z';
            CS_AppData.DefaultTablesDefTable[k].Name[1] = 'Y';
            CS_AppData.DefaultAppDefTable[k].State      = CS_ChecksumState_ENABLED;
            CS_AppData.DefaultAppDefTable[k].Name[0]    = 'W';
            CS_AppData.DefaultAppDefTable[k].Name[1]    = 'V';
        }
        CS_InitializeDefaultTables();
        printf("csu_initdefault eep=%u,%u,%u mem=%u,%u,%u tbl=%u,%u,%u app=%u,%u,%u\n",
               (unsigned)CS_AppData.DefaultEepromDefTable[15].State,
               (unsigned)CS_AppData.DefaultEepromDefTable[15].NumBytesToChecksum,
               (unsigned)CS_AppData.DefaultEepromDefTable[15].StartAddress,
               (unsigned)CS_AppData.DefaultMemoryDefTable[15].State,
               (unsigned)CS_AppData.DefaultMemoryDefTable[15].NumBytesToChecksum,
               (unsigned)CS_AppData.DefaultMemoryDefTable[15].StartAddress,
               (unsigned)CS_AppData.DefaultTablesDefTable[23].State,
               (unsigned)CS_AppData.DefaultTablesDefTable[23].Name[0],
               (unsigned)CS_AppData.DefaultTablesDefTable[23].Name[1],
               (unsigned)CS_AppData.DefaultAppDefTable[23].State,
               (unsigned)CS_AppData.DefaultAppDefTable[23].Name[0],
               (unsigned)CS_AppData.DefaultAppDefTable[23].Name[1]);

        /* --- CS_GoToNextTable, seven calls from table 0. The seventh is the wrap, and the
         * PassCounter increment on it is the ONLY place in CS that counter moves. */
        CS_AppData.HkPacket.Payload.CurrentCSTable      = 0;
        CS_AppData.HkPacket.Payload.CurrentEntryInTable = 9;
        CS_AppData.HkPacket.Payload.PassCounter         = 0;
        printf("csu_gotonext");
        for (k = 0; k < 7; ++k)
        {
            CS_GoToNextTable();
            printf(" %u/%u/%u", (unsigned)CS_AppData.HkPacket.Payload.CurrentCSTable,
                   (unsigned)CS_AppData.HkPacket.Payload.CurrentEntryInTable,
                   (unsigned)CS_AppData.HkPacket.Payload.PassCounter);
        }
        printf("\n");

        /* --- THE FOUR BY-NAME LOOKUPS, and their asymmetry. The two RESULTS lookups accept
         * anything that is not EMPTY; the two DEFINITION lookups require CS_StateValid. So an
         * UNDEFINED entry -- CS looked and could not find what was named -- is findable in
         * the results table and NOT in the definition table, which is what lets "report its
         * baseline" answer while "enable it" refuses. Four columns per line: a hit, a miss,
         * the UNDEFINED case, and an EMPTY entry whose name still matches. */
        strncpy(cs_res_tbl[2].Name, "CS.ResTablesTbl", sizeof(cs_res_tbl[2].Name));
        cs_res_tbl[2].State = CS_ChecksumState_ENABLED;
        strncpy(cs_res_tbl[3].Name, "CS.Undef", sizeof(cs_res_tbl[3].Name));
        cs_res_tbl[3].State = CS_ChecksumState_UNDEFINED;
        strncpy(cs_res_tbl[4].Name, "CS.Empty", sizeof(cs_res_tbl[4].Name));
        cs_res_tbl[4].State = CS_ChecksumState_EMPTY;
        rt                  = NULL;
        printf("csu_restbl_byname hit=%d", (int)CS_GetTableResTblEntryByName(&rt, "CS.ResTablesTbl"));
        printf("@%d", (int)(rt == &cs_res_tbl[2]));
        rt = NULL;
        printf(" miss=%d", (int)CS_GetTableResTblEntryByName(&rt, "CS.Nope"));
        printf(" undef=%d", (int)CS_GetTableResTblEntryByName(&rt, "CS.Undef"));
        printf(" empty=%d\n", (int)CS_GetTableResTblEntryByName(&rt, "CS.Empty"));

        strncpy(cs_def_tbl[6].Name, "CS.DefTablesTbl", sizeof(cs_def_tbl[6].Name));
        cs_def_tbl[6].State = CS_ChecksumState_DISABLED;
        strncpy(cs_def_tbl[7].Name, "CS.Undef", sizeof(cs_def_tbl[7].Name));
        cs_def_tbl[7].State = CS_ChecksumState_UNDEFINED;
        dt                  = NULL;
        printf("csu_deftbl_byname hit=%d", (int)CS_GetTableDefTblEntryByName(&dt, "CS.DefTablesTbl"));
        printf("@%d", (int)(dt == &cs_def_tbl[6]));
        dt = NULL;
        printf(" miss=%d", (int)CS_GetTableDefTblEntryByName(&dt, "CS.Nope"));
        printf(" undef=%d\n", (int)CS_GetTableDefTblEntryByName(&dt, "CS.Undef"));

        strncpy(cs_res_app[1].Name, "CS", sizeof(cs_res_app[1].Name));
        cs_res_app[1].State = CS_ChecksumState_ENABLED;
        ra                  = NULL;
        printf("csu_resapp_byname hit=%d", (int)CS_GetAppResTblEntryByName(&ra, "CS"));
        printf("@%d", (int)(ra == &cs_res_app[1]));
        ra = NULL;
        printf(" miss=%d\n", (int)CS_GetAppResTblEntryByName(&ra, "NOPE"));

        strncpy(cs_def_app[8].Name, "TO_LAB_APP", sizeof(cs_def_app[8].Name));
        cs_def_app[8].State = CS_ChecksumState_ENABLED;
        da                  = NULL;
        printf("csu_defapp_byname hit=%d", (int)CS_GetAppDefTblEntryByName(&da, "TO_LAB_APP"));
        printf("@%d", (int)(da == &cs_def_app[8]));
        da = NULL;
        printf(" miss=%d\n", (int)CS_GetAppDefTblEntryByName(&da, "NOPE"));

        /* --- THE FOUR CS_FindEnabled*. They advance CurrentEntryInTable as a SIDE EFFECT,
         * which is how a cycle resumes where the last one stopped -- so each line prints the
         * counter as well as which entry came back. The second call on each is the
         * exhausted case: NULL, with the counter parked at the table bound. */
        for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k)
        {
            cs_res_eep[k].State = CS_ChecksumState_DISABLED;
        }
        cs_res_eep[5].State = CS_ChecksumState_ENABLED;
        CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
        re = CS_FindEnabledEepromEntry();
        printf("csu_findeep at=%d cur=%u", (int)(re == &cs_res_eep[5]),
               (unsigned)CS_AppData.HkPacket.Payload.CurrentEntryInTable);
        CS_AppData.HkPacket.Payload.CurrentEntryInTable = 6;
        re                                              = CS_FindEnabledEepromEntry();
        printf(" exhausted=%d cur=%u\n", (int)(re == NULL),
               (unsigned)CS_AppData.HkPacket.Payload.CurrentEntryInTable);

        cs_res_mem[0].State = CS_ChecksumState_ENABLED;
        CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
        re = CS_FindEnabledMemoryEntry();
        printf("csu_findmem at=%d cur=%u\n", (int)(re == &cs_res_mem[0]),
               (unsigned)CS_AppData.HkPacket.Payload.CurrentEntryInTable);

        cs_res_tbl[2].State                            = CS_ChecksumState_ENABLED;
        CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
        rt                                             = CS_FindEnabledTablesEntry();
        printf("csu_findtbl at=%d cur=%u\n", (int)(rt == &cs_res_tbl[2]),
               (unsigned)CS_AppData.HkPacket.Payload.CurrentEntryInTable);

        CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
        ra                                             = CS_FindEnabledAppEntry();
        printf("csu_findapp at=%d cur=%u\n", (int)(ra == &cs_res_app[1]),
               (unsigned)CS_AppData.HkPacket.Payload.CurrentEntryInTable);

        /* --- CS_ResetTablesTblResultEntry, both arms. The NULL one is not decoration: five
         * of the six wrappers have no ResTblPtr until a tables table names a CS table. */
        cs_res_tbl[9].ByteOffset        = 7;
        cs_res_tbl[9].TempChecksumValue = 8;
        cs_res_tbl[9].ComputedYet       = true;
        CS_ResetTablesTblResultEntry(&cs_res_tbl[9]);
        CS_ResetTablesTblResultEntry(NULL);
        printf("csu_resetres off=%u temp=%u yet=%u\n", (unsigned)cs_res_tbl[9].ByteOffset,
               (unsigned)cs_res_tbl[9].TempChecksumValue,
               (unsigned)cs_res_tbl[9].ComputedYet);

        /* --- CS_CheckRecomputeOneshot, the guard every command handler calls first. It
         * increments the error counter ITSELF, which is why a handler that forgets to return
         * would count one failure twice -- so the counter is printed, not just the answer.
         *
         * THE CALL IS HOISTED OUT OF THE printf, both halves, and this is the FOURTH time
         * that trap has been hit in this port: C evaluates every argument before printing
         * anything, so an argument that SENDS AN EVENT emits its line first, while HolyC's
         * S()/D() pair prints the label and then the event lands mid-line. Reading
         * CommandErrorCounter in the same call would be worse again -- the order of
         * evaluation against the call that increments it is unspecified in C. */
        CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
        CS_AppData.HkPacket.Payload.RecomputeInProgress = false;
        CS_AppData.HkPacket.Payload.OneShotInProgress   = false;
        csb = CS_CheckRecomputeOneshot();
        printf("csu_recompguard idle=%d err=%u\n", (int)csb,
               (unsigned)CS_AppData.HkPacket.Payload.CommandErrorCounter);
        CS_AppData.HkPacket.Payload.RecomputeInProgress = true;
        csb = CS_CheckRecomputeOneshot();
        printf("csu_recompguard recomp=%d err=%u\n", (int)csb,
               (unsigned)CS_AppData.HkPacket.Payload.CommandErrorCounter);
        CS_AppData.HkPacket.Payload.RecomputeInProgress = false;
        CS_AppData.HkPacket.Payload.OneShotInProgress   = true;
        csb = CS_CheckRecomputeOneshot();
        printf("csu_recompguard oneshot=%d err=%u\n", (int)csb,
               (unsigned)CS_AppData.HkPacket.Payload.CommandErrorCounter);
        CS_AppData.HkPacket.Payload.OneShotInProgress = false;
}


/* THE TWO BUFFERS MM'S GENERIC PATHS ACTUALLY DEREFERENCE. mm_dump.c's MM_DumpMemToFile and
 * MM_FillDumpInEventBuffer's RAM/EEPROM arm `memcpy` from the address they are given rather
 * than going through CFE_PSP_MemRead*, so the simulated window of literal addresses does not
 * work for them -- they need real memory. File scope on both halves (limit 22), and the same
 * shape, so the two can be filled identically.
 *
 * mmd_evbuf IS SIXTEEN BYTES AND NASA CLEARS FIFTEEN. The sixteenth is a poison byte: it says
 * MM_INTERNAL_MAX_DUMP_INEVENT_BYTES is the bound the clear used, which is the kind of constant
 * a translation can get wrong without any other line noticing. */
unsigned char mmd_src[250];
unsigned char mmd_evbuf[16];
unsigned char mmd_mts[4];
/* Per-width captures for mm_load's poke exercises -- see the note at their use. */
unsigned mml_bp[3];
unsigned mml_dv[3];
/* The thirteen command codes and their expected lengths, filled at use because the HolyC half
 * has no aggregate initialiser. */
unsigned mma_cc[13];
unsigned mma_sz[13];
static MD_DwellTableLoad_t md_load;
/* The dispatcher's command buffer. A CFE_SB_Buffer_t is only an 8-byte alignment union, so a
 * command is built in the LARGEST of the six command types -- MD_JamDwellCmd_t, 88 bytes --
 * and its address passed as the buffer; `&BufPtr->Msg` is at offset 0 either way. File scope
 * because the HolyC half needs it there (limit 22) and the two halves stay one shape. */
static MD_JamDwellCmd_t md_dcmd;
/* Backing memory for the load buffers the tbl exercise hands out, plus the four event ids it
 * walks. File scope because the HolyC half needs them there (limit 22, and HolyC has no
 * file-scope aggregate initialiser inside a function), and the two halves stay one shape. */
static unsigned char tbl_probe_mem[64];
static unsigned char tbl_probe_mem2[64];
static uint16        tbl_actv_ids[4];
static uint16        tbl_val_ids[5];
static CFE_TBL_TxnEventContext_t tbl_txctx;
/* A STEERABLE VALIDATION CALLBACK. It began as a pointer that exists only to be non-NULL --
 * CFE_TBL_SetupValidationRequest branches on whether it is set, never on what it does -- and
 * `tbl_val_rc` was added for cfe_tbl_load.c, where WHAT IT RETURNS decides between three
 * outcomes: zero is a pass, a NEGATIVE value raises CFE_TBL_VALIDATION_ERR_EID and zeroes the
 * buffer, and a POSITIVE value raises a DIFFERENT event (CFE_TBL_LOAD_VAL_ERR_EID) and becomes
 * CFE_STATUS_VALIDATION_FAILURE. Without the knob, two of those three are unreachable. */
static int32 tbl_val_rc;
static int32 tbl_val_stub(void *TblPtr)
{
    (void)TblPtr;
    return tbl_val_rc;
}

/* NASA declares this one in no header: it is a non-static "local helper function" in
 * cfe_tbl_loadbuff.c, reachable only through the event dispatcher in cfe_tbl_transaction.c,
 * which is still inside tbl's call cycle. So the exercise calls it directly -- as NASA's own
 * unit tests do -- and needs the prototype here. Its three format strings are the only output
 * cfe_tbl_loadbuff.c produces, which makes them the only part of it the byte-identical
 * transcript can check at all. */
bool CFE_TBL_SendActivationEventHelper(const CFE_TBL_TxnEvent_t *Event,
                                       CFE_TBL_TxnEventContext_t *Ctxt);
/* and its twin in cfe_tbl_valresult.c, declared in no header for the same reason. */
bool CFE_TBL_SendValidationEventHelper(const CFE_TBL_TxnEvent_t *Event,
                                       CFE_TBL_TxnEventContext_t *Ctxt);

/* cfe_tbl_internal.c, cfe_tbl_task.c and cfe_tbl_api.c are three of the EIGHT sources that
 * tools/cfs/module_deps.py shows must be gated together, so these three are stubs on both
 * halves -- exactly the arrangement the other six objtabs have had. They exist so that
 * CFE_TBL_ModuleEntry has three distinct non-NULL addresses to hold, which is the only
 * property the object table exercise asserts about them. */
/* --- FOUR STAND-INS FOR THE loadbuff+regrec PAIR ------------------------------------------
 * Named by tools/cfs/module_deps.py --cuts: two from cfe_tbl_internal.c and two from
 * cfe_tbl_transaction.c, both still inside tbl's call cycle.
 *
 * THE FIRST TWO STAND-INS ARE GONE: CFE_TBL_ForeachAccessDescriptor and
 * CFE_TBL_AcquireGlobalLoadBuff both live in cfe_tbl_internal.c, gated below, so the real
 * ones are linked now. The `tbl_foreach_visits` counter went with them -- a witness that
 * only a stub could keep -- and what replaces it is in the exercise: the list walk is now
 * observed through its EFFECT, the number of descriptors SetUpdated marks. */

/* CFE_TBL_TxnAddEvent and CFE_TBL_SendTransactionEvents WERE STAND-INS HERE and are real now
 * -- they live in cfe_tbl_transaction.c, gated below.
 *
 * AND SO ARE ALL FOUR cfe_tbl_registry.c STAND-INS: CFE_TBL_TxnFindRegByName, the counted
 * lock pair, and CFE_TBL_TxnRemoveAccessLink. The source is gated below, so the counted lock
 * now delegates to the REAL CFE_TBL_LockRegistry (which this driver's mutex still counts, so
 * the transcript witnesses every take and give), and RemoveAccessLink does the list surgery
 * it only pretended to do. `tbl_removelink_calls` went with it -- a counter is all a stub can
 * witness -- and what replaces it is the effect: a table whose last accessor leaves is
 * returned to the pool, which the exercise reads from the registry record itself. */

/* CFE_TBL_EarlyInit, CFE_TBL_CleanUpApp AND CFE_TBL_TaskMain WERE STUBS HERE. All three are
 * real now, so every hook cfe_tbl_objtab.c names is the function it claims to be -- the first
 * module whose object table is complete.
 *
 * AND THE LAST STAND-IN IS GONE TOO: CFE_TBL_TaskPipe lives in cfe_tbl_dispatch.c, gated
 * below, so tbl has NO stand-ins left anywhere in this driver. `tbl_taskpipe_calls` went with
 * it -- a counter is all a stub can witness -- and what replaces it is the dispatcher's own
 * three-way error plus the handlers it actually calls.
 *
 * NOTE THERE IS NO COMMAND-TABLE INIT CALL ON THIS SIDE. NASA's CFE_TBL_CmdHandlerTbl is a
 * `const` file-scope array with initialisers, which C builds at load time. HolyC has no
 * file-scope aggregate initialiser, so the translation fills it at runtime from
 * CFE_TBL_CmdHandlerTblInit() -- which the HolyC driver must call before any dispatch, and
 * does, beside CFE_PlatformConfigTablesInit. The asymmetry is the whole reason that function
 * exists; it has no counterpart here. */

/* cfe_es_api.c and cfe_es_task.c ARE gated now, and the three stubs this note described are
 * gone from both halves. The note is kept because it describes the arrangement a not-yet-gated
 * source still gets -- and because the claim in it rotted SILENTLY when those sources landed,
 * which is the same failure tools/cfs/check_oracle_globals.py found in the five duplicate
 * state globals above. A comment is not a gate.
 *
 * The lock pair is a COUNTER rather than a no-op on purpose: the syslog's whole design is about
 * which reads happen inside it (the first block) and which deliberately do not (every block
 * after), and a transcript that cannot see the difference could not tell a correct dump from
 * one that held the lock for the entire file. */

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
/* CFE_ES_FileWriteByteCntErr: STUB REMOVED -- cfe_es_task.c is gated, the real one runs and
 * raises CFE_ES_FILEWRITE_ERR_EID instead of printing. es_bytecnt_errs went with it; what
 * counts a short write now is the event in the transcript. */

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
static long  es_cds_locks, es_cds_unlocks, es_starttasks, es_restarts;
static long  es_stats;
static int32 es_stat_rc       = OS_SUCCESS; /* what OS_stat says: Restart/Reload branch on it */
static int32 es_starttask_rc  = CFE_SUCCESS;
static long  es_taskdeletes, es_taskexits;
static int32 es_taskdelete_rc = OS_SUCCESS;

/* CFE_ES_WriteToERLog: STUB REMOVED -- its source is gated, the real one runs. */
/* NASA's CFE_PSP_Restart does not return. This one does, because the code AFTER it in
 * CFE_ES_ResetCFE is part of what the transcript compares -- the "CFE_PSP_Restart returned"
 * syslog line and the CFE_ES_NOT_IMPLEMENTED that follows exist for exactly this case. */
void CFE_PSP_Restart(uint32 ResetType)
{
    ++es_restarts;
    printf("psp_restart %lu\n", (unsigned long)ResetType);
}

/* THE SIZE OS_stat REPORTS, which arrived with MM: mm_load.c's MM_VerifyLoadFileSize is the
 * first thing in the port to READ the stat buffer rather than only the return code, and it
 * compares the size against the file header's claim plus both headers. The stub ignored
 * `filestats` entirely before, which would have made every size check pass on a zero. */
static long es_stat_size;

int32 OS_stat(const char *path, os_fstat_t *filestats)
{
    ++es_stats;
    if (filestats != NULL)
    {
        filestats->FileSize = (size_t)es_stat_size;
    }
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

/* ---- WHAT cfe_es_start.c NEEDS: THE VOLATILE DISK AND TWO MORE PIECES OF BOARD --------------
 *
 * THE RAM DISK IS SIMULATED, not recorded, for the same reason the CDS is: the interesting code
 * is the part that decides whether to format it. A power-on reset calls OS_mkfs, a processor
 * reset calls OS_initfs and falls back to OS_mkfs, and a processor reset whose disk is over
 * CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED full unmounts, removes, re-makes and re-mounts it.
 * Tracking "does a volume exist" and "is it mounted" in two flags is enough to drive all of
 * that, and the block counts are steerable so the percentage is a knob.
 *
 * It is NOT a file system. Nothing is stored; OS_mkfs says a volume now exists and OS_mount
 * says it is reachable. cFE never writes to the RAM disk through these -- it writes through
 * OS_OpenCreate, which this driver simulates separately. */
static int   es_vol_exists;      /* a volume has been made (mkfs or initfs succeeded) */
static int   es_vol_mounted;
static long  es_mkfs_calls, es_initfs_calls, es_mount_calls, es_unmount_calls, es_rmfs_calls;
static int32 es_mkfs_rc    = OS_SUCCESS;
static int32 es_initfs_rc  = OS_SUCCESS;
static int32 es_mount_rc   = OS_SUCCESS;
static int32 es_unmount_rc = OS_SUCCESS;
static int32 es_rmfs_rc    = OS_SUCCESS;
static int32 es_statvol_rc = OS_SUCCESS;
/* The free-space check is `(blocks_free * 100) / total_blocks`, so these two ARE the percentage.
 * total_blocks of 0 takes the error arm, because the division would be by zero. */
static size_t es_vol_total_blocks = 100;
static size_t es_vol_blocks_free  = 90;

int32 OS_mkfs(char *address, const char *devname, const char *volname, size_t blocksize,
              osal_blockcount_t numblocks)
{
    ++es_mkfs_calls;
    printf("os_mkfs %s %s bs=%lu n=%lu rc=%ld\n", devname, volname, (unsigned long)blocksize,
           (unsigned long)numblocks, (long)es_mkfs_rc);
    if (es_mkfs_rc == OS_SUCCESS)
    {
        es_vol_exists = 1;
    }
    return es_mkfs_rc;
}

int32 OS_initfs(char *address, const char *devname, const char *volname, size_t blocksize,
                osal_blockcount_t numblocks)
{
    ++es_initfs_calls;
    printf("os_initfs %s %s rc=%ld\n", devname, volname, (long)es_initfs_rc);
    if (es_initfs_rc == OS_SUCCESS)
    {
        es_vol_exists = 1;
    }
    return es_initfs_rc;
}

int32 OS_mount(const char *devname, const char *mountpoint)
{
    ++es_mount_calls;
    printf("os_mount %s -> %s rc=%ld\n", devname, mountpoint, (long)es_mount_rc);
    if (es_mount_rc == OS_SUCCESS)
    {
        es_vol_mounted = 1;
    }
    return es_mount_rc;
}

int32 OS_unmount(const char *mountpoint)
{
    ++es_unmount_calls;
    printf("os_unmount %s rc=%ld\n", mountpoint, (long)es_unmount_rc);
    if (es_unmount_rc == OS_SUCCESS)
    {
        es_vol_mounted = 0;
    }
    return es_unmount_rc;
}

int32 OS_rmfs(const char *devname)
{
    ++es_rmfs_calls;
    printf("os_rmfs %s rc=%ld\n", devname, (long)es_rmfs_rc);
    if (es_rmfs_rc == OS_SUCCESS)
    {
        es_vol_exists = 0;
    }
    return es_rmfs_rc;
}

int32 OS_FileSysStatVolume(const char *name, OS_statvfs_t *statbuf)
{
    printf("os_statvol %s rc=%ld\n", name, (long)es_statvol_rc);
    statbuf->block_size   = CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE;
    statbuf->total_blocks = es_vol_total_blocks;
    statbuf->blocks_free  = es_vol_blocks_free;
    return es_statvol_rc;
}

/* ---- A REAL CORE OBJECT TABLE, for CFE_ES_CreateObjects --------------------------------------
 * CFE_CORE_MODULE_OBJTAB is just its own NULL terminator in this configuration, so both phases
 * of CreateObjects would walk nothing. These two entries are what make them run: one
 * library-only module (an EarlyInit and no TaskMain, so phase 2 skips it) and one with a
 * TaskMain, which takes a real app-table slot as a CORE app.
 *
 * The TaskMain is never CALLED -- this driver's OS_TaskCreate does not run entry points, for
 * the reason recorded there -- so it only has to be a valid address. */
static long  es_core_early_calls, es_core_taskmain_calls;
static int32 es_core_early_rc = CFE_SUCCESS;

static int32 es_core_early_init(void)
{
    ++es_core_early_calls;
    printf("es_core_earlyinit rc=%ld\n", (long)es_core_early_rc);
    return es_core_early_rc;
}

static void es_core_taskmain(void)
{
    ++es_core_taskmain_calls;
}

static Target_ObjectTable_t es_core_entry_lib  = {"COREL", es_core_early_init, NULL, NULL, 0, 0};
static Target_ObjectTable_t es_core_entry_task = {"CORET", es_core_early_init, es_core_taskmain,
                                                  NULL, 70, 4096};
/* CFE_ES_Main memsets the whole global, so the driver's planted state is saved around it. */
static CFE_ES_Global_t es_global_save;
static osal_id_t       es_scriptfd;

/* CFE_PSP_AttachExceptions installs the trap vectors -- NASA's own comment at the call site is
 * "Install exception Handlers ( Placeholder )", so it is a placeholder upstream too. And
 * CFE_PSP_GetVolatileDiskMem hands back the RAM the volatile file system is built in: this
 * returns a real buffer, because OS_mkfs is handed the address and a NULL would be a different
 * test than the one intended. */
static long es_attachexc;
static unsigned char es_ramdisk_mem[4096];
static int32 es_voldiskmem_rc = CFE_PSP_SUCCESS;

void CFE_PSP_AttachExceptions(void)
{
    ++es_attachexc;
    printf("psp_attachexc\n");
}

int32 CFE_PSP_GetVolatileDiskMem(cpuaddr *PtrToVolDisk, uint32 *SizeOfVolDisk)
{
    *PtrToVolDisk  = (cpuaddr)es_ramdisk_mem;
    *SizeOfVolDisk = sizeof(es_ramdisk_mem);
    return es_voldiskmem_rc;
}

/* ---- WHAT cfe_es_apps.c NEEDS FROM OSAL, which this driver does not compile ----------------
 * OSAL has its own differential driver (run_osal_xlat_smoke.sh) and its own transcript; here its
 * public API is stubbed, the same way CFE_PSP_* is. Every one of these stands in for a real OS
 * service and will still be a stub when every line of cFE is translated.
 *
 * THE OBJECT TABLE IS THE INTERESTING ONE. CFE_ES_CleanupTaskResources cannot be reached at all
 * without it: the real OS_ForEachObject walks the OS's own records and hands every object whose
 * creator is a given task to a callback, which is how a dead task's queues, semaphores, timers
 * and open files get released when nothing recorded that it made them. There is no OS here, so
 * the objects are a table of (id, type, deleted) and OS_ForEachObject walks that. It is enough
 * to drive all eight arms of the callback's switch, the per-type error codes, and -- by
 * refusing a delete -- the "number of found objects is not trending downward" guard. */
#define ES_OBJS_MAX 8
static uint32         es_obj_id[ES_OBJS_MAX];
static osal_objtype_t es_obj_type[ES_OBJS_MAX];
static int            es_obj_gone[ES_OBJS_MAX];
static int            es_objs_n;
static int32          es_objdel_rc = OS_SUCCESS;
static long           es_foreach_calls;

static void es_obj_add(uint32 id, osal_objtype_t type)
{
    es_obj_id[es_objs_n]   = id;
    es_obj_type[es_objs_n] = type;
    es_obj_gone[es_objs_n] = 0;
    ++es_objs_n;
}

static void es_objs_clear(void)
{
    es_objs_n    = 0;
    es_objdel_rc = OS_SUCCESS;
}

/* Marks the object gone. FOUR OF THE SIX DELETE ENTRY POINTS ALREADY EXISTED in this driver --
 * OS_close for the file simulation, OS_BinSemDelete for the background task, OS_QueueDelete for
 * SB's pipe queues and OS_MutSemDelete for ES's mempool -- each with witnesses an existing probe
 * reads. So they are not replaced; they call this, and keep their own return value. Only the two
 * that did not exist carry the refusal knob.
 *
 * OS_QueueDelete DELIBERATELY DOES NOT MARK. Its own body returns OS_ERR_INVALID_ID for an id
 * that is not one of SB's created queues, which an object-table id never is -- and that is the
 * CFE_ES_QUEUE_DELETE_ERR arm of the cleanup callback, reached for free and honestly. */
static void es_obj_mark(osal_id_t object_id)
{
    int i;
    for (i = 0; i < es_objs_n; ++i)
    {
        if (es_obj_id[i] == OS_ObjectIdToInteger(object_id))
        {
            es_obj_gone[i] = 1;
        }
    }
}

void OS_ForEachObject(osal_id_t creator_id, OS_ArgCallback_t callback_ptr, void *callback_arg)
{
    int i;
    ++es_foreach_calls;
    printf("os_foreach creator=%lu n=%d\n", (unsigned long)OS_ObjectIdToInteger(creator_id),
           es_objs_n);
    for (i = 0; i < es_objs_n; ++i)
    {
        if (!es_obj_gone[i])
        {
            callback_ptr(OS_ObjectIdFromInteger(es_obj_id[i]), callback_arg);
        }
    }
}

osal_objtype_t OS_IdentifyObject(osal_id_t object_id)
{
    int i;
    for (i = 0; i < es_objs_n; ++i)
    {
        if (es_obj_id[i] == OS_ObjectIdToInteger(object_id))
        {
            return es_obj_type[i];
        }
    }
    return OS_OBJECT_TYPE_UNDEFINED;
}

int32 OS_CountSemDelete(osal_id_t sem_id)
{
    printf("os_countsemdelete %lu rc=%ld\n", (unsigned long)OS_ObjectIdToInteger(sem_id),
           (long)es_objdel_rc);
    if (es_objdel_rc != OS_SUCCESS)
    {
        return es_objdel_rc;
    }
    es_obj_mark(sem_id);
    return OS_SUCCESS;
}

int32 OS_TimerDelete(osal_id_t timer_id)
{
    printf("os_timerdelete %lu rc=%ld\n", (unsigned long)OS_ObjectIdToInteger(timer_id),
           (long)es_objdel_rc);
    if (es_objdel_rc != OS_SUCCESS)
    {
        return es_objdel_rc;
    }
    es_obj_mark(timer_id);
    return OS_SUCCESS;
}

/* THE LOADER, which is the one real piece of hardware-adjacent machinery cFE cannot do without
 * and which this port has no equivalent of yet: there is no dlopen here and no ELF loader in the
 * guest. So a load succeeds or fails on command and hands back a made-up module id, and a symbol
 * lookup hands back a made-up address. Both are steerable because CFE_ES_LoadModule's three
 * failure paths -- load failed, symbol missing, unload-after-failure failed -- are the bulk of
 * what it does. */
static long  es_modloads, es_modunloads, es_modlookups, es_modinfos;
static int32 es_modload_rc   = OS_SUCCESS;
static int32 es_modunload_rc = OS_SUCCESS;
static int32 es_modlookup_rc = OS_SUCCESS;
static int32 es_modinfo_rc   = OS_SUCCESS;
static uint32 es_modinfo_valid = 1;

int32 OS_ModuleLoad(osal_id_t *module_id, const char *module_name, const char *filename,
                    uint32 flags)
{
    ++es_modloads;
    printf("os_moduleload %s %s flags=%lu rc=%ld\n", module_name, filename,
           (unsigned long)flags, (long)es_modload_rc);
    if (es_modload_rc == OS_SUCCESS)
    {
        *module_id = OS_ObjectIdFromInteger(0x6660 + es_modloads);
    }
    return es_modload_rc;
}

int32 OS_ModuleUnload(osal_id_t module_id)
{
    ++es_modunloads;
    printf("os_moduleunload %lu rc=%ld\n", (unsigned long)OS_ObjectIdToInteger(module_id),
           (long)es_modunload_rc);
    return es_modunload_rc;
}

/* THE LIBRARY ENTRY POINT IS ACTUALLY CALLED, unlike an app's, so it has to be a real function.
 * CFE_ES_LoadLibrary invokes the init symbol inline with the library's own id -- that is what
 * makes a library a library -- while an app's entry point goes into a task record whose task
 * this driver never runs. So the lookup hands back es_lib_init when a test asks for it and an
 * uncallable constant otherwise. */
static long  es_lib_inits;
static int32 es_lib_init_rc = CFE_SUCCESS;
static uint32 es_lib_init_id;

static int32 es_lib_init(CFE_ES_LibId_t LibId)
{
    ++es_lib_inits;
    es_lib_init_id = CFE_RESOURCEID_TO_ULONG(LibId);
    printf("es_lib_init id=%lu rc=%ld\n", (unsigned long)es_lib_init_id, (long)es_lib_init_rc);
    return es_lib_init_rc;
}

static cpuaddr es_modlookup_addr = (cpuaddr)0xE0000000;

int32 OS_ModuleSymbolLookup(osal_id_t module_id, cpuaddr *symbol_address, const char *symbol_name)
{
    ++es_modlookups;
    printf("os_modulesymlookup %s rc=%ld\n", symbol_name, (long)es_modlookup_rc);
    if (es_modlookup_rc == OS_SUCCESS)
    {
        /* A FIXED, FAKE ENTRY POINT by default. It must never be CALLED -- and it is not: the
         * main task entry goes into a task record this driver's OS_TaskCreate never runs. The
         * library entry point IS called, so the library test points this at es_lib_init. */
        *symbol_address = es_modlookup_addr;
    }
    return es_modlookup_rc;
}

int32 OS_ModuleInfo(osal_id_t module_id, OS_module_prop_t *module_prop)
{
    ++es_modinfos;
    printf("os_moduleinfo %lu rc=%ld\n", (unsigned long)OS_ObjectIdToInteger(module_id),
           (long)es_modinfo_rc);
    if (es_modinfo_rc == OS_SUCCESS)
    {
        module_prop->addr.valid        = es_modinfo_valid;
        module_prop->addr.code_address = 0x11110000;
        module_prop->addr.code_size    = 0x1000;
        module_prop->addr.data_address = 0x22220000;
        module_prop->addr.data_size    = 0x2000;
        module_prop->addr.bss_address  = 0x33330000;
        module_prop->addr.bss_size     = 0x3000;
    }
    return es_modinfo_rc;
}

/* OS_TaskCreate: the entry function is NEVER CALLED, which is the whole reason this driver can
 * run ES's app lifecycle in one thread. CFE_ES_StartAppTask passes CFE_ES_TaskEntryPoint, and
 * that function polls for a task record under the lock -- running it here would deadlock on the
 * shared-data mutex this same thread already holds. The task id it hands back is real enough for
 * the record ES then writes. */
static long   es_taskcreates;
static int32  es_taskcreate_rc = OS_SUCCESS;
/* THE ID HAS TO RESOLVE, which it did not have to before. The old CFE_ES_StartAppTask stub
 * handed back 0x7770+n on purpose -- documented as "the id it returns does not resolve" -- and
 * the real one LOCATES the task record for the id OSAL gives it and writes to it without a NULL
 * check, because NASA's comment there is "As this is a newly-created task, this shouldn't fail."
 * An id of 0, or one past OS_MAX_TASKS, makes CFE_ES_LocateTaskRecordByID return NULL and the
 * memset that follows is a segfault. So this allocates real ids: 1-based, index = id - 1, with 1
 * reserved for the calling task (es_os_taskid). */
static uint32 es_taskcreate_next = 2;

int32 OS_TaskCreate(osal_id_t *task_id, const char *task_name, osal_task_entry function_pointer,
                    osal_stackptr_t stack_pointer, size_t stack_size, osal_priority_t priority,
                    uint32 flags)
{
    ++es_taskcreates;
    printf("os_taskcreate %s stack=%lu prio=%u flags=%lu rc=%ld\n", task_name,
           (unsigned long)stack_size, (unsigned)priority, (unsigned long)flags,
           (long)es_taskcreate_rc);
    if (es_taskcreate_rc == OS_SUCCESS)
    {
        if (es_taskcreate_next > OS_MAX_TASKS)
        {
            es_taskcreate_next = 2;
        }
        *task_id = OS_ObjectIdFromInteger(es_taskcreate_next);
        ++es_taskcreate_next;
    }
    return es_taskcreate_rc;
}

/* CFE_PSP_SetDefaultExceptionEnvironment installs the trap handlers a new task runs under. It is
 * the BOARD, like the rest of the PSP exception interface. */
static long es_setexcenv;

void CFE_PSP_SetDefaultExceptionEnvironment(void)
{
    ++es_setexcenv;
}

/* CFE_ES_LockUserAppRecord: STUB REMOVED -- its source is gated, the real one runs. The
 * copy that lived here was NASA's own body, kept byte for byte in behaviour precisely so that
 * this swap would not move the transcript. It did not. */
/* CFE_ES_StartAppTask: STUB REMOVED -- its source is gated, the real one runs. It now makes a
 * real task RECORD, so CFE_ES_DeleteChildTask on the id it returns no longer takes the "Task ID
 * is not active" branch -- which is a transcript change the exercise had to account for. */
/* THE CDS GROUP: STUBS REMOVED -- cfe_es_cds.c and cfe_es_cds_mempool.c are gated, the real
 * ones run. All nine of them went at once: FormCDSName, LocateCDSBlockRecordByID and ByName,
 * RegisterCDSEx, LockCDS, UnlockCDS, CDSBlockWrite, CDSBlockRead and DeleteCDS. They recorded
 * and refused, so the three public CDS entry points returned CFE_ES_NOT_IMPLEMENTED and the
 * exercise asserted that CDSIsAvailable was 0. It is 1 now.
 *
 * ---- THE SIMULATED CRITICAL DATA STORE -------------------------------------------------------
 *
 * A CDS is non-volatile memory the processor CANNOT LOAD FROM: on a real spacecraft it is
 * battery-backed RAM or an EEPROM region, reached only through CFE_PSP_ReadFromCDS and
 * WriteToCDS, and its whole purpose is to still be there after a processor reset. There is no
 * such device here, so it is a byte array -- and that is better than a recording stub in a way
 * worth stating: THE REBUILD PATH BECOMES TESTABLE. Clearing CFE_ES_Global.CDSVars while leaving
 * es_cds_store alone is exactly what a processor reset looks like to cFE, so the exercise can
 * boot the CDS, write blocks, "reset", and watch CFE_ES_RebuildCDS find the registry and the
 * allocator recover the blocks from the descriptors that survived. Against a stub none of that
 * code could run at all.
 *
 * The size is small on purpose: 64 KiB is over the 36,884-byte minimum (a 36,876-byte header
 * holding 512 registry entries, plus an 8-byte trailer) with room for a handful of blocks, so
 * the "too small" refusal is one knob away and a full pool is reachable. */
#define ES_CDS_STORE_SIZE 65536
static unsigned char es_cds_store[ES_CDS_STORE_SIZE];
static uint32 es_cds_size = ES_CDS_STORE_SIZE;
static long   es_cds_reads, es_cds_writes;
/* Steerable, because every CDS function has a PSP-failure arm and nothing else can reach it. */
static int32  es_cds_getsize_rc = CFE_PSP_SUCCESS;
static int32  es_cds_read_rc    = CFE_PSP_SUCCESS;
static int32  es_cds_write_rc   = CFE_PSP_SUCCESS;
/* An offset past which writes fail, so a failure can be aimed at one step of a multi-step
 * operation -- clearing the store, or writing the end signature -- rather than all of them. */
static uint32 es_cds_write_fail_at = 0xFFFFFFFF;

int32 CFE_PSP_GetCDSSize(uint32 *SizeOfCDS)
{
    *SizeOfCDS = es_cds_size;
    return es_cds_getsize_rc;
}

int32 CFE_PSP_WriteToCDS(const void *PtrToDataToWrite, uint32 CDSOffset, uint32 NumBytes)
{
    ++es_cds_writes;
    if (es_cds_write_rc != CFE_PSP_SUCCESS || CDSOffset >= es_cds_write_fail_at)
    {
        return es_cds_write_rc != CFE_PSP_SUCCESS ? es_cds_write_rc : CFE_PSP_ERROR;
    }
    /* A real PSP bounds-checks against the device; so does this, and a refusal here is the
     * same CFE_PSP_ERROR an out-of-range offset would get on hardware. */
    if (CDSOffset + NumBytes > ES_CDS_STORE_SIZE)
    {
        return CFE_PSP_ERROR;
    }
    memcpy(&es_cds_store[CDSOffset], PtrToDataToWrite, NumBytes);
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_ReadFromCDS(void *PtrToDataFromRead, uint32 CDSOffset, uint32 NumBytes)
{
    ++es_cds_reads;
    if (es_cds_read_rc != CFE_PSP_SUCCESS)
    {
        return es_cds_read_rc;
    }
    if (CDSOffset + NumBytes > ES_CDS_STORE_SIZE)
    {
        return CFE_PSP_ERROR;
    }
    memcpy(PtrToDataFromRead, &es_cds_store[CDSOffset], NumBytes);
    return CFE_PSP_SUCCESS;
}

/* A PROCESSOR RESET, as cFE experiences one: the RAM copy of the CDS state is gone and the store
 * is not. Everything CFE_ES_CDS_EarlyInit rebuilds comes back out of es_cds_store. */
/* EXACTLY EIGHT BYTES, because a CDS signature is not NUL terminated: `_CDSEnd_` occupies the
 * last eight bytes of the store with nothing after it, so printing it as a string would run off
 * the end of the array. The HolyC half has no %.8s either, which is the other reason this is a
 * helper on both sides rather than a format. */
static void es_sig8(const unsigned char *p)
{
    int i;
    for (i = 0; i < 8; ++i)
    {
        putchar(p[i]);
    }
}

static void es_cds_reset(void)
{
    memset(&CFE_ES_Global.CDSVars, 0, sizeof(CFE_ES_Global.CDSVars));
    CFE_ES_Global.CDSIsAvailable = false;
}

/* CFE_ES_CopyModuleBasicInfo / CopyModuleStatusInfo / CopyModuleAddressInfo: STUBS REMOVED --
 * their source is gated, the real ones run. These three printed a line each and filled in NO
 * fields, so AppInfo's EntryPoint, FileName, StartAddress and the six module addresses were
 * whatever the callers' memset left. Three transcript lines go; the fields they were standing in
 * for arrive, and the exercise reads them. */
/* ---- what cfe_es_task.c calls and nothing gated defines -------------------------------------
 * The apps/CDS/perf/background/dispatch set again, plus the PSP and OSAL version calls. Each
 * goes away from BOTH halves on the commit that gates its source. */
static long  es_cdsdeletes, es_taskpipes, es_textseg;
static int32 es_bkginit_rc, es_cdsdelete_rc;
static int32 es_textseg_rc = CFE_PSP_SUCCESS;
static long  es_perf_remaining;

/* CFE_ES_AppCreate: STUB REMOVED -- its source is gated, the real one runs. */

/* CFE_ES_CleanUpApp: STUB REMOVED -- its source is gated, the real one runs. It lasted exactly
 * one commit: cfe_es_appctrl.c was gated before cfe_es_apps.c, so this stub existed only to let
 * the control-request path reach an end. */

/* CFE_ES_BackgroundInit: STUB REMOVED -- its source is gated, the real one runs. */
/* CFE_ES_DeleteCDS: STUB REMOVED -- cfe_es_cds.c is gated, the real one runs. */

/* CFE_ES_GetPerfLogDumpRemaining: STUB REMOVED -- its source is gated, the real one runs. */
/* CFE_ES_TaskPipe: STUB REMOVED -- its source is gated, the real one runs. */
/* The ER log's two background-writer callbacks. They are never CALLED here -- the FS
 * background writer is what calls them -- but their ADDRESSES go into the state object, and
 * the transcript prints whether each is NULL. */
/* CFE_ES_BackgroundERLogFileDataGetter: STUB REMOVED -- its source is gated, the real one runs. */
/* CFE_ES_BackgroundERLogFileEventHandler: STUB REMOVED -- its source is gated, the real one runs. */
int32 CFE_PSP_GetCFETextSegmentInfo(cpuaddr *PtrToCFESegment, uint32 *SizeOfCFESegment)
{
    ++es_textseg;
    /* A FIXED, SMALL SEGMENT, so the CRC in housekeeping is a number both halves compute from
     * the same bytes. Pointing it at real code would make the checksum depend on the
     * COMPILER, which is the one thing this comparison must not do. */
    *PtrToCFESegment  = (cpuaddr)"cFEtext";
    *SizeOfCFESegment = 7;
    return es_textseg_rc;
}

void CFE_PSP_GetVersionNumber(uint8 VersionNumbers[4])
{
    VersionNumbers[0] = 1;
    VersionNumbers[1] = 6;
    VersionNumbers[2] = 0;
    VersionNumbers[3] = 0;
}

const char *CFE_PSP_GetVersionString(void)
{
    return "1.6.0-psp";
}

void OS_GetVersionNumber(uint8 VersionNumbers[4])
{
    VersionNumbers[0] = 6;
    VersionNumbers[1] = 1;
    VersionNumbers[2] = 0;
    VersionNumbers[3] = 0;
}

const char *OS_GetVersionString(void)
{
    return "6.1.0-osal";
}

/* The heap, which only CFE_ES_SendHkCmd asks about. Steerable so the else branch -- three
 * zeroes in housekeeping rather than a missing packet -- is reachable. */
static int32 es_heap_rc = OS_SUCCESS;

int32 OS_HeapGetInfo(OS_heap_prop_t *heap_prop)
{
    heap_prop->free_bytes         = 100000;
    heap_prop->free_blocks        = 25;
    heap_prop->largest_free_block = 40000;
    return es_heap_rc;
}

/* ---- what cfe_es_erlog.c, cfe_es_backgroundtask.c and cfe_es_objtab.c call -----------------
 * The last three ES stubs from the apps/CDS/perf set, plus the PSP's exception interface --
 * which is the BOARD, and will still be a stub when every line of cFE is translated. */
static long  es_perfdumps, es_cdsearly;
static int32 es_cdsearly_rc;
static long  es_exc_count;                 /* what CFE_PSP_Exception_GetCount reports */
static int32 es_exc_summary_rc = CFE_PSP_SUCCESS;
static uint32 es_exc_taskid;               /* 0 = "a system exception, not a task's" */
static int32 es_exc_ctxsize = 4;           /* <0 means "no context available" */

/* CFE_ES_RunAppTableScan: STUB REMOVED -- its source is gated, the real one runs. */

/* CFE_ES_RunPerfLogDump: STUB REMOVED -- its source is gated, the real one runs. */
/* CFE_ES_CDS_EarlyInit: STUB REMOVED -- cfe_es_cds.c is gated, the real one runs. It is the
 * EarlyInit slot of ES's own module-table entry, which NASA spends on the CDS because the store
 * has to exist before any app can register with it. */

uint32 CFE_PSP_Exception_GetCount(void)
{
    return (uint32)es_exc_count;
}

int32 CFE_PSP_Exception_GetSummary(uint32 *ContextLogId, osal_id_t *TaskId, char *ReasonBuf,
                                   uint32 ReasonSize)
{
    *ContextLogId = 77;
    *TaskId       = OS_ObjectIdFromInteger(es_exc_taskid);
    strncpy(ReasonBuf, "simulated exception", ReasonSize - 1);
    ReasonBuf[ReasonSize - 1] = 0;
    return es_exc_summary_rc;
}

int32 CFE_PSP_Exception_CopyContext(uint32 ContextLogId, void *ContextBuf, uint32 ContextSize)
{
    if (es_exc_ctxsize > 0)
    {
        memset(ContextBuf, 0xC7, es_exc_ctxsize);
    }
    return es_exc_ctxsize;
}

/* ---- the PSP's TIMEBASE, which cfe_es_perf.c is built around -------------------------------
 * A performance log entry IS a hardware timestamp, so these will still be stubs when every
 * line of cFE is translated. es_perf_tb advances by one per read, which makes the timestamps
 * in a dumped log a predictable sequence rather than a wall clock -- the transcript compares
 * them. */
static uint32 es_perf_tb;

uint32 CFE_PSP_GetTimerTicksPerSecond(void)
{
    return 1000000;
}

uint32 CFE_PSP_GetTimerLow32Rollover(void)
{
    return 1000000;
}

void CFE_PSP_Get_Timebase(uint32 *Tbu, uint32 *Tbl)
{
    ++es_perf_tb;
    *Tbu = 0;
    *Tbl = es_perf_tb;
}

/* CFE_SB_Global IS NASA'S, defined in cfe_sb_task.c, which is gated. It was ALSO defined here, and
 * two tentative definitions merge SILENTLY in C -- the link succeeded and nothing
 * said which object the exercise was reading. tools/cfs/check_oracle_globals.py
 * found all five of these at once and now forbids them. */

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
 * CFE_ES_CounterID_ToIndex (cfe_es_api.c, gated since this note was written) subtract CFE_ES_LIBID_BASE and
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
 * CFE_SB_SendSubscriptionReport was a NEW stub when this paragraph was written: it lives in
 * cfe_sb_task.c, which IS gated now -- see the note just below, which already records that the
 * stub is gone. CFE_SB_SubscribeFull calls it on every successful GLOBAL subscribe. It
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
/* OS_SymbolLookup IS A SEAM IN THIS DRIVER, not a translation. This gate's scope is cFE and
 * the cFE translation sees OSAL only through its API -- the cfs case includes OSAL's module
 * TYPES (osapi_module_decl.HC) and none of its code, which is what check_seam exists to keep
 * true. osapi-module.c IS translated and IS gated, by run_osal_xlat_smoke.sh.
 *
 * So both halves supply the same stub, and MD_ResolveSymAddr's symbol branch is reachable on
 * purpose: md_sym_rc picks success or failure and md_sym_addr is the address a success yields.
 * Without this the branch is simply never taken and half of MD_ResolveSymAddr is untested. */
/* THE SIMULATED DWELL WINDOW -- the hardware MD needs and this port does not have, supplied
 * through the PSP the same way the other 22 CFE_PSP_* functions are.
 *
 * WHY A WINDOW AND NOT A REAL BUFFER'S ADDRESS. MD reads whatever address the ground gives it,
 * and NASA's own event text prints a resolved cpuaddr with %08X. A real buffer's address is a
 * host pointer on this half and a guest pointer on the other, so it can never appear in a
 * transcript that compares the two character for character. MD_ResolveSymAddr returns Offset
 * VERBATIM when SymName is empty, so the exercise hands MD literal addresses inside a FIXED
 * window -- the same constant in both halves -- and these three functions map the window onto
 * a buffer with a known pattern. The address in the transcript is then a number written in the
 * source, not a pointer.
 *
 * ADDITIVE, NOT A REPLACEMENT. CFE_PSP_MemValidateRange below is deliberately left alone: it is
 * the settable stub that ES's and TBL's pool paths already drive, and making it window-aware
 * would change behaviour for every existing caller. The bounds check lives here instead.
 *
 * THE BYTES ARE ASSEMBLED EXPLICITLY, little end first, rather than by casting the buffer to a
 * uint16/uint32. Both halves happen to be little-endian, but MD_GetDwellData memcpy's the low
 * NumBytes of the value straight into the dwell packet, so the packet's CONTENTS depend on that
 * choice and an assumption there would be an assumption about the transcript. */
#define MD_SIM_WINDOW_BASE 0x00100000
#define MD_SIM_WINDOW_SIZE 256
static uint8 md_sim_mem[MD_SIM_WINDOW_SIZE];
static long  md_sim_reads;

static void md_sim_fill(void)
{
    int i;
    for (i = 0; i < MD_SIM_WINDOW_SIZE; i++)
    {
        md_sim_mem[i] = (uint8)(0x40 + i); /* ascending and distinguishable */
    }
}

static int md_sim_in(cpuaddr a, int width)
{
    return a >= MD_SIM_WINDOW_BASE && (a - MD_SIM_WINDOW_BASE) + width <= MD_SIM_WINDOW_SIZE;
}

int32 CFE_PSP_MemRead8(cpuaddr MemoryAddress, uint8 *ByteValue)
{
    ++md_sim_reads;
    if (!md_sim_in(MemoryAddress, 1))
        return CFE_PSP_INVALID_MEM_ADDR;
    *ByteValue = md_sim_mem[MemoryAddress - MD_SIM_WINDOW_BASE];
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_MemRead16(cpuaddr MemoryAddress, uint16 *uint16Value)
{
    size_t o = (size_t)(MemoryAddress - MD_SIM_WINDOW_BASE);
    ++md_sim_reads;
    if (!md_sim_in(MemoryAddress, 2))
        return CFE_PSP_INVALID_MEM_ADDR;
    *uint16Value = (uint16)md_sim_mem[o] | ((uint16)md_sim_mem[o + 1] << 8);
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_MemRead32(cpuaddr MemoryAddress, uint32 *uint32Value)
{
    size_t o = (size_t)(MemoryAddress - MD_SIM_WINDOW_BASE);
    ++md_sim_reads;
    if (!md_sim_in(MemoryAddress, 4))
        return CFE_PSP_INVALID_MEM_ADDR;
    *uint32Value = (uint32)md_sim_mem[o] | ((uint32)md_sim_mem[o + 1] << 8) |
                   ((uint32)md_sim_mem[o + 2] << 16) | ((uint32)md_sim_mem[o + 3] << 24);
    return CFE_PSP_SUCCESS;
}


/* --- THE WRITE HALF OF THE SAME WINDOW, which arrived with MM ----------------------------------
 * MD only ever READ memory. MM pokes it, fills it and loads it from a file, so the simulated
 * window gains three stores -- same base, same size, same bytes. The name stays MD_SIM_* because
 * it is literally the same simulated hardware, and renaming it would touch MD's lines for
 * nothing.
 *
 * md_sim_writes COUNTS STORES, and it is the witness that distinguishes "the fill loop ran" from
 * "the fill loop returned success": MM's fill writes one byte at a time and reports a byte count
 * it computes from the segment arithmetic, not from the stores, so a loop that never stored
 * would still report the right number.
 *
 * md_sim_wfail_at MAKES ONE STORE FAIL, by offset, which is the only way into MM's
 * MM_PSP_WRITE_ERR_EID branch -- and that branch stops the segment loop mid-way, which is also
 * the only way to reach the short-load arm that turns a partial write into CFE_PSP_ERROR. -1
 * means "never", so no existing line can see it. */
static long md_sim_writes;
static long md_sim_wfail_at = -1;

static int md_sim_wfail(cpuaddr a)
{
    return md_sim_wfail_at >= 0 && (long)(a - MD_SIM_WINDOW_BASE) == md_sim_wfail_at;
}

int32 CFE_PSP_MemWrite8(cpuaddr MemoryAddress, uint8 ByteValue)
{
    ++md_sim_writes;
    if (!md_sim_in(MemoryAddress, 1) || md_sim_wfail(MemoryAddress))
        return CFE_PSP_INVALID_MEM_ADDR;
    md_sim_mem[MemoryAddress - MD_SIM_WINDOW_BASE] = ByteValue;
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_MemWrite16(cpuaddr MemoryAddress, uint16 uint16Value)
{
    size_t o = (size_t)(MemoryAddress - MD_SIM_WINDOW_BASE);
    ++md_sim_writes;
    if (!md_sim_in(MemoryAddress, 2) || md_sim_wfail(MemoryAddress))
        return CFE_PSP_INVALID_MEM_ADDR;
    md_sim_mem[o]     = (uint8)(uint16Value & 0xFF);
    md_sim_mem[o + 1] = (uint8)((uint16Value >> 8) & 0xFF);
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_MemWrite32(cpuaddr MemoryAddress, uint32 uint32Value)
{
    size_t o = (size_t)(MemoryAddress - MD_SIM_WINDOW_BASE);
    ++md_sim_writes;
    if (!md_sim_in(MemoryAddress, 4) || md_sim_wfail(MemoryAddress))
        return CFE_PSP_INVALID_MEM_ADDR;
    md_sim_mem[o]     = (uint8)(uint32Value & 0xFF);
    md_sim_mem[o + 1] = (uint8)((uint32Value >> 8) & 0xFF);
    md_sim_mem[o + 2] = (uint8)((uint32Value >> 16) & 0xFF);
    md_sim_mem[o + 3] = (uint8)((uint32Value >> 24) & 0xFF);
    return CFE_PSP_SUCCESS;
}


/* --- A SECOND SIMULATED REGION: EEPROM -------------------------------------------------------
 * MM pokes EEPROM through CFE_PSP_EepromWrite*, not CFE_PSP_MemWrite*, because on real hardware
 * the two are different devices: EEPROM has to be unlocked, programmed and waited on, which is
 * why MM wraps only the EEPROM paths in performance-log stamps. So it gets its own window rather
 * than sharing the RAM one -- a shared array would let a poke to EEPROM be satisfied by the RAM
 * path and nothing would notice.
 *
 * Its base is deliberately FAR from MD_SIM_WINDOW_BASE so that an address meant for one and sent
 * to the other falls outside and is refused rather than quietly working. */
#define MM_EEP_WINDOW_BASE 0x00200000
#define MM_EEP_WINDOW_SIZE 256
static unsigned char mm_eep_mem[MM_EEP_WINDOW_SIZE];
static long          mm_eep_writes;
static long          mm_eep_wfail_at = -1;

static int mm_eep_in(cpuaddr a, long width)
{
    return a >= MM_EEP_WINDOW_BASE && (long)(a - MM_EEP_WINDOW_BASE) + width <= MM_EEP_WINDOW_SIZE;
}

static int mm_eep_wfail(cpuaddr a)
{
    return mm_eep_wfail_at >= 0 && (long)(a - MM_EEP_WINDOW_BASE) == mm_eep_wfail_at;
}

int32 CFE_PSP_EepromWrite8(cpuaddr MemoryAddress, uint8 ByteValue)
{
    ++mm_eep_writes;
    if (!mm_eep_in(MemoryAddress, 1) || mm_eep_wfail(MemoryAddress))
        return CFE_PSP_INVALID_MEM_ADDR;
    mm_eep_mem[MemoryAddress - MM_EEP_WINDOW_BASE] = ByteValue;
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_EepromWrite16(cpuaddr MemoryAddress, uint16 uint16Value)
{
    size_t o = (size_t)(MemoryAddress - MM_EEP_WINDOW_BASE);
    ++mm_eep_writes;
    if (!mm_eep_in(MemoryAddress, 2) || mm_eep_wfail(MemoryAddress))
        return CFE_PSP_INVALID_MEM_ADDR;
    mm_eep_mem[o]     = (uint8)(uint16Value & 0xFF);
    mm_eep_mem[o + 1] = (uint8)((uint16Value >> 8) & 0xFF);
    return CFE_PSP_SUCCESS;
}

int32 CFE_PSP_EepromWrite32(cpuaddr MemoryAddress, uint32 uint32Value)
{
    size_t o = (size_t)(MemoryAddress - MM_EEP_WINDOW_BASE);
    ++mm_eep_writes;
    if (!mm_eep_in(MemoryAddress, 4) || mm_eep_wfail(MemoryAddress))
        return CFE_PSP_INVALID_MEM_ADDR;
    mm_eep_mem[o]     = (uint8)(uint32Value & 0xFF);
    mm_eep_mem[o + 1] = (uint8)((uint32Value >> 8) & 0xFF);
    mm_eep_mem[o + 2] = (uint8)((uint32Value >> 16) & 0xFF);
    mm_eep_mem[o + 3] = (uint8)((uint32Value >> 24) & 0xFF);
    return CFE_PSP_SUCCESS;
}


/* --- THE EEPROM BANK LOCK ---------------------------------------------------------------------
 * On real hardware CFE_PSP_EepromWriteEnable drives a write-protect line and the bank number
 * selects which part. Nothing in MM reads a bank's state back, so unlike the EepromWrite* trio
 * these need no simulated region -- only a settable return code and a count, which is what makes
 * mm_cmds.c's two commands drivable at all. */
static long  mm_eep_locks;
static int32 mm_eep_lock_rc = CFE_PSP_SUCCESS;
static uint32 mm_eep_last_bank;

int32 CFE_PSP_EepromWriteEnable(uint32 Bank)
{
    ++mm_eep_locks;
    mm_eep_last_bank = Bank;
    return mm_eep_lock_rc;
}

int32 CFE_PSP_EepromWriteDisable(uint32 Bank)
{
    ++mm_eep_locks;
    mm_eep_last_bank = Bank;
    return mm_eep_lock_rc;
}

/* OS_SymbolTableDump writes the loader's whole symbol table to a file. There is no loader and no
 * symbol table in this port -- OS_SymbolLookup is already a driver stub -- so this records the
 * request and returns a settable code. The SIZE LIMIT is part of the record because it is
 * MM_INTERNAL_MAX_DUMP_FILE_DATA_SYMTBL, a constant no other line in MM reads. */
static long  mm_symdumps;
static int32 mm_symdump_rc = OS_SUCCESS;
static long  mm_symdump_limit;

int32 OS_SymbolTableDump(const char *filename, size_t size_limit)
{
    ++mm_symdumps;
    mm_symdump_limit = (long)size_limit;
    printf("os_symdump %s limit=%ld rc=%ld\n", filename, mm_symdump_limit, (long)mm_symdump_rc);
    return mm_symdump_rc;
}

int32  md_sym_rc;
cpuaddr md_sym_addr;
int32 OS_SymbolLookup(cpuaddr *SymbolAddress, const char *SymbolName)
{
    (void)SymbolName;
    if (md_sym_rc == OS_SUCCESS)
        *SymbolAddress = md_sym_addr;
    return md_sym_rc;
}

static long es_psp_validates;
static int32 es_psp_validate_rc = CFE_PSP_SUCCESS;

int32 OS_MutSemDelete(osal_id_t sem_id)
{
    ++es_mutsem_deletes;
    es_obj_mark(sem_id);
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
/* CFE_EVS_Global IS NASA'S, defined in cfe_evs_task.c, which is gated. It was ALSO defined here, and
 * two tentative definitions merge SILENTLY in C -- the link succeeded and nothing
 * said which object the exercise was reading. tools/cfs/check_oracle_globals.py
 * found all five of these at once and now forbids them. */
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

/* --- cfe_tbl_dumpctl.c --------------------------------------------------------------
 * The dump-only rendezvous: four blocks, a resource-id allocator over them, and the five
 * header accessors that are the allocator's primitives. The whole id scheme is exercised
 * here once, because tbl repeats it in five id spaces and the other four are the same code
 * with a different base.
 *
 * ITS OWN FUNCTION, to stay structurally parallel with the HolyC half, where it has to be one:
 * limit 22 there means every local in main() spends from a single frame budget. Nothing forces
 * it on this side; the two halves being the same shape is worth more than the two lines saved.
 */
/* --- cfe_tbl_accdesc.c ---------------------------------------------------------------
 * The per-app handle: 256 access descriptors, a resource-id allocator over them, and the two
 * transaction entry points that hand one out and give it back.
 *
 * The interesting assertions are the two that are not about the allocator at all. First, a
 * transaction TAKES AND RELEASES the registry lock exactly once around the allocation, which
 * the driver's counting mutex witnesses. Second, releasing a descriptor only clears the
 * table's OwnerAppId IF THE CALLER OWNS IT -- a non-owner may hold a handle to a shared table
 * and releasing theirs must not un-own it for everyone.
 */
/* --- cfe_tbl_loadbuff.c + cfe_tbl_regrec.c -------------------------------------------
 * The pair, gated together because they are mutually recursive: regrec asks "which buffer is
 * this id" on every load and only loadbuff knows, while loadbuff asks regrec for the record
 * that owns a buffer.
 *
 * THE SERIAL ENCODING FIRST. One flat numbering over every buffer in the system -- four
 * shared, then two per table -- recovered with a modulo and a comparison. Then the three
 * buffer questions a registry record can answer, and finally the one branch that is the
 * reason ForeachAccessDescriptor had to be written faithfully rather than as a counter: a
 * load REFUSED because another application still holds the buffer it wants.
 */
/* --- cfe_tbl_valresult.c -------------------------------------------------------------
 * Validation is a REQUEST, not a call: the app owns the validation function, so Table
 * Services records the ask in one of ten blocks and the app answers it later from its own
 * task. The two paths that matter are the one where there IS a validation function (block
 * goes PENDING, the app will answer) and the one where there is not -- where the block is
 * still allocated, goes straight to PERFORMED, the buffer is marked valid on the spot, and
 * the only thing distinguishing "checked" from "nobody checked" is an INFORMATION event.
 */
/* --- cfe_tbl_passthru_codec.c --------------------------------------------------------
 * The codec that does nothing, which is the point: without EDS a table file is a raw image
 * of the table's memory, so encode and decode are a copy. What it really does is BYTE ORDER
 * -- a cFE table file header is big endian on the wire so a file written on one processor
 * loads on another -- plus one overflow check that is easy to read as a duplicate.
 */
/* --- cfe_tbl_transaction.c -----------------------------------------------------------
 * WHO IS ALLOWED TO DO THIS. Every public CFE_TBL_* call runs inside a transaction that
 * resolves the caller and the table, takes the registry lock, and collects events to send
 * after releasing it. The access model is four bits and one comparison, and that comparison
 * is the most important line in the module:
 *
 *     if ((AccessAllowed & AllowedContext) != AllowedContext)
 *
 * -- EVERY required bit must be present, not any. Table Services sets all of them.
 */
static void TblTransactionExercise(void)
{
    CFE_TBL_RegistryRec_t      *rr;
    CFE_TBL_AccessDescriptor_t *ad;
    CFE_TBL_TxnState_t          txn;
    CFE_ES_AppId_t              self;
    int                         rc;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B30);
    CFE_ES_GetAppID(&self);

    /* TxnInit: with a context check it resolves the caller; without, it does not look. */
    memset(&txn, 0xA5, sizeof(txn));
    printf("tbl_txinit ctx rc=%ld app=%lu", (long)CFE_TBL_TxnInit(&txn, true),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_TxnAppId(&txn)));
    memset(&txn, 0xA5, sizeof(txn));
    printf(" noctx rc=%ld app=%lu lock=%u\n", (long)CFE_TBL_TxnInit(&txn, false),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_TxnAppId(&txn)),
           (unsigned)txn.RegLockCount);

    /* THE NAME IS REFUSED WHILE THE REGISTRY IS LOCKED, and the refusal is a literal that
     * NASA intends to appear in logs as a bug report: "if this is seen in a log, it is a bug
     * in the caller that should be fixed". */
    CFE_TBL_TxnInit(&txn, true);
    txn.RegLockCount = 1;
    printf("tbl_txname locked=%s", CFE_TBL_TxnAppNameCaller(&txn));
    txn.RegLockCount = 0;
    printf(" unlocked=%s cached=%s\n", CFE_TBL_TxnAppNameCaller(&txn),
           CFE_TBL_TxnAppNameCaller(&txn));

    /* START FROM NAME: found, and not found (which reports and unlocks). */
    rr = &CFE_TBL_Global.Registry[2];
    CFE_TBL_InitRegistryRecord(rr);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 2));
    strncpy(rr->Config.Name, "CFE_TBL.Txn", sizeof(rr->Config.Name) - 1);
    rr->OwnerAppId = self;
    rc = (int)CFE_TBL_TxnStartFromName(&txn, "CFE_TBL.Txn", CFE_TBL_TxnContext_UNDEFINED);
    printf("tbl_txname_ok rc=%d regid=%lu lock=%u\n", rc,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_TxnRegId(&txn)),
           (unsigned)txn.RegLockCount);
    CFE_TBL_TxnFinish(&txn);
    printf("tbl_txfinish lock=%u\n", (unsigned)txn.RegLockCount);
    printf("tbl_txname_miss rc=0x%lx lock=%u events=%u id=%u\n",
           (unsigned long)(uint32)CFE_TBL_TxnStartFromName(&txn, "CFE_TBL.Nope",
                                                           CFE_TBL_TxnContext_UNDEFINED),
           (unsigned)txn.RegLockCount, (unsigned)CFE_TBL_TxnGetEventCount(&txn),
           (unsigned)txn.PendingEvents[0].EventId);

    /* START FROM HANDLE. An undefined handle is refused BEFORE the registry is locked -- the
     * comment says why: "this avoids locking the registry for lookups that will certainly
     * fail". */
    printf("tbl_txh_undef rc=0x%lx lock=%u\n",
           (unsigned long)(uint32)CFE_TBL_TxnStartFromHandle(&txn, CFE_TBL_HANDLEID_UNDEFINED,
                                                             CFE_TBL_TxnContext_UNDEFINED),
           (unsigned)txn.RegLockCount);

    /* a good descriptor owned by us, pointing at a good record owned by us */
    ad = &CFE_TBL_Global.Handles[9];
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9));
    ad->AppId    = self;
    ad->RegIndex = CFE_TBL_RegRecGetID(rr);
    /* ASKING FOR A CONTEXT IS WHAT MAKES THE CALLER BE RESOLVED AT ALL, and that is worth
     * pinning because it surprised me. TxnInit only calls CFE_ES_GetAppID when
     * AllowedContext != UNDEFINED, so a transaction started with UNDEFINED keeps AppId zero --
     * and a zero AppId then compares EQUAL to an unset CFE_TBL_Global.TableTaskAppId, which
     * grants TABLE_SERVICES. So UNDEFINED means "no context required" and incidentally yields
     * ctx=1 rather than the ctx=0 one might expect. Both cases are below. */
    rc = (int)CFE_TBL_TxnStartFromHandle(&txn,
                                         CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(
                                             CFE_TBL_HANDLE_BASE + 9)),
                                         CFE_TBL_TxnContext_UNDEFINED);
    printf("tbl_txh_nocheck rc=%d ctx=%u app=%lu\n", rc, (unsigned)txn.CallContext,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_TxnAppId(&txn)));
    CFE_TBL_TxnFinish(&txn);

    /* ...and with a real requirement, the caller IS resolved, and because we are both the
     * descriptor's owner and the table's owner we get OWNER_APP|ACCESSOR_APP = 6. */
    rc = (int)CFE_TBL_TxnStartFromHandle(&txn,
                                         CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(
                                             CFE_TBL_HANDLE_BASE + 9)),
                                         CFE_TBL_TxnContext_ACCESSOR_APP);
    printf("tbl_txh_ok rc=%d ctx=%u lock=%u regid=%lu\n", rc, (unsigned)txn.CallContext,
           (unsigned)txn.RegLockCount,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_TxnRegId(&txn)));

    /* FindAccessDescriptorForSelf walks the table's list looking for OUR descriptor. */
    rr->AccessList.Next = CFE_TBL_AccDescGetHandle(ad);
    txn.AccDescPtr      = NULL;
    printf("tbl_txself rc=%ld found=%d handle=%lu\n",
           (long)CFE_TBL_FindAccessDescriptorForSelf(&txn), (int)(txn.AccDescPtr == ad),
           (unsigned long)CFE_TBL_TxnHandleAsULong(&txn));
    /* and with the descriptor owned by somebody else, it finds nothing */
    ad->AppId      = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0xBEEF));
    txn.AccDescPtr = NULL;
    printf("tbl_txself_other rc=0x%lx found=%d\n",
           (unsigned long)(uint32)CFE_TBL_FindAccessDescriptorForSelf(&txn),
           (int)(txn.AccDescPtr != NULL));
    ad->AppId = self;
    CFE_TBL_TxnFinish(&txn);

    /* ACCESS DENIED: require a context bit the caller does not have. We own the table, so
     * demand TABLE_SERVICES, which only tbl itself gets. */
    rc = (int)CFE_TBL_TxnStartFromHandle(&txn,
                                        CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(
                                            CFE_TBL_HANDLE_BASE + 9)),
                                        CFE_TBL_TxnContext_TABLE_SERVICES);
    printf("tbl_txh_denied rc=0x%lx events=%u id=%u data2=%ld lock=%u\n", (unsigned long)(uint32)rc,
           (unsigned)CFE_TBL_TxnGetEventCount(&txn), (unsigned)txn.PendingEvents[0].EventId,
           (long)txn.PendingEvents[0].EventData2, (unsigned)txn.RegLockCount);

    /* AND AS TABLE SERVICES ITSELF every requirement passes, because AccessAllowed gets every
     * bit set. */
    CFE_TBL_Global.TableTaskAppId = self;
    rc = (int)CFE_TBL_TxnStartFromHandle(&txn,
                                        CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(
                                            CFE_TBL_HANDLE_BASE + 9)),
                                        CFE_TBL_TxnContext_ALL);
    printf("tbl_txh_root rc=%d ctx=%u\n", rc, (unsigned)txn.CallContext);
    CFE_TBL_TxnFinish(&txn);
    CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_UNDEFINED;

    /* A STALE DESCRIPTOR: the handle is good but the record it names is free. */
    ad->RegIndex = CFE_TBL_REGID_C(CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 77));
    printf("tbl_txh_stale rc=0x%lx lock=%u\n",
           (unsigned long)(uint32)CFE_TBL_TxnStartFromHandle(&txn,
                                                             CFE_TBL_HANDLEID_C(
                                                                 CFE_ResourceId_FromInteger(
                                                                     CFE_TBL_HANDLE_BASE + 9)),
                                                             CFE_TBL_TxnContext_UNDEFINED),
           (unsigned)txn.RegLockCount);
    ad->RegIndex = CFE_TBL_RegRecGetID(rr);

    /* THE NOTIFICATION LADDER: never loaded, then updated, then plain success. */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr  = rr;
    txn.AccDescPtr = ad;
    CFE_TBL_RegRecClearLoadInProgress(rr);
    rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
    printf("tbl_txnotify never=0x%lx", (unsigned long)(uint32)CFE_TBL_TxnGetNextNotification(&txn));
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 8),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    ad->Updated = true;
    printf(" updated=0x%lx", (unsigned long)(uint32)CFE_TBL_TxnGetNextNotification(&txn));
    ad->Updated = false;
    printf(" plain=%ld\n", (long)CFE_TBL_TxnGetNextNotification(&txn));

    /* EVENT OVERFLOW: NumPendingEvents counts PAST the limit so the overrun is evident, and
     * ProcessEvents clamps back before walking. */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    for (rc = 0; rc < CFE_TBL_MAX_EVENTS_PER_TXN + 3; rc++)
    {
        CFE_TBL_TxnAddEvent(&txn, CFE_TBL_ACTIVATE_ERR_EID, 0, rc);
    }
    printf("tbl_txoverflow count=%u limit=%d\n", (unsigned)CFE_TBL_TxnGetEventCount(&txn),
           CFE_TBL_MAX_EVENTS_PER_TXN);
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    /* the context must be filled: the helper renders it with %s and a NULL there is
     * undefined behaviour, not a blank. */
    tbl_txctx.Operation  = "Overflow";
    tbl_txctx.CallerName = "TXN_APP";
    tbl_txctx.TableName  = CFE_TBL_RegRecGetName(rr);
    printf("tbl_txclear processed=%u",
           (unsigned)CFE_TBL_TxnProcessEvents(&txn, CFE_TBL_SendActivationEventHelper, &tbl_txctx));
    CFE_TBL_TxnClearEvents(&txn);
    printf(" after=%u\n", (unsigned)CFE_TBL_TxnGetEventCount(&txn));

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

/* tbl_mkfile lives with the cfe_tbl_load.c block below, which is where it belongs; this
 * exercise needs it to build the table file its Load call reads. `static` on both the
 * declaration and the definition, deliberately -- a static forward declaration in front of a
 * NON-static definition makes the definition internal, which this project has been caught by
 * before. */
static void tbl_mkfile(const char *tblname, uint32 offset, uint32 numbytes, size_t datasize,
                       uint32 contenttype, uint16 subtype, uint8 fill);

/* --- cfe_tbl_api.c -------------------------------------------------------------
 * THE PUBLIC API, AND THE RIGHT WAY TO EXERCISE IT IS A LIFECYCLE. Nineteen functions, and
 * what matters is not each one alone but that an application can register a table, share it,
 * load it, validate it, manage it, read it and give it back -- with every step going through
 * the real transaction machinery, the real registry, the real buffers and the real events.
 *
 * So the order below is an app's order, not the file's: Register, Share, GetAddress(es), Load,
 * Validate, GetStatus/Manage, Update, GetInfo, Modified, NotifyByMessage, DumpToBuffer,
 * Unregister -- with the argument-check refusals folded in where they belong.
 *
 * TWO APP IDS ARE IN PLAY. es_set_ctx(1) is "CFE_EVS" and es_set_ctx(2) is "OTHER_APP"; the
 * transaction's access check is the whole point of this file, so the OWNER and the NON-OWNER
 * are both driven. */
static void TblApiExercise(void)
{
    CFE_TBL_Handle_t h1, h2, hbad;
    CFE_TBL_Handle_t handles[2];
    CFE_TBL_Info_t   info;
    CFE_TBL_RegistryRec_t      *rr;
    CFE_TBL_AccessDescriptor_t *ad1;
    CFE_TBL_AccessDescriptor_t *ad2;
    void            *addr;
    void           **addrs[2];
    void            *a0;
    void            *a1;
    int32            st;

    /* THE SETUP IS THE REAL STARTUP SEQUENCE, which is both more faithful and less work than
     * hand-building CFE_TBL_Global. CFE_TBL_EarlyInit creates the two mutexes, the 512 KiB
     * pool and the four shared load buffers; CFE_TBL_InitData seeds all five resource-id
     * spaces and the three packet headers. Between them that is exactly what the object table
     * and CFE_TBL_TaskInit do at boot, and both are gated code.
     *
     * THE FIRST DRAFT HAND-BUILT IT AND EVERY ASSERTION BELOW CASCADED INTO A FAILURE. It
     * memset the global and called CFE_ES_PoolCreate directly, which returned without a usable
     * handle -- `CFE_ES_GetPoolBuf: Err:Bad handle(0x00000000)` -- so CFE_TBL_SetupTableBuffers
     * failed, so Register failed, so all nineteen functions answered
     * CFE_TBL_ERR_INVALID_HANDLE and the whole block was one repeated number. The tell was
     * `tbl_apireg rc=-1006632959 handle=-1`: a handle of -1 is CFE_TBL_BAD_TABLE_HANDLE, so
     * nothing had been registered at all. */
    es_set_ctx(1);
    CFE_TBL_EarlyInit();
    CFE_TBL_InitData();
    CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_C(ES_CTX_APPID(1));

    /* --- THE HANDLE/ID CONVERSION, FIRST, BECAUSE I GOT IT WRONG --------------------------
     *
     * CFE_TBL_Handle_t is an int16 in this configuration and CFE_TBL_BAD_TABLE_HANDLE is **-1**,
     * not zero -- so handle 0 is a PERFECTLY GOOD handle and -1 is the only invalid one. The
     * first draft of the translation wrote CFE_TBL_HANDLE_IS_VALID as a test against zero
     * (CFE_TBL_HandleID_IsDefined), which would have made CFE_TBL_HandleToID(0) answer
     * UNDEFINED. check_constants caught the constant; nothing could catch the macro body,
     * because a macro body is neither a value nor a signature. These three lines are what now
     * catch it. */
    printf("tbl_handleid zero=%lu base=%lu bad=%d\n",
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_HandleToID(0)),
           (unsigned long)CFE_TBL_HANDLE_BASE,
           (int)!CFE_TBL_HandleID_IsDefined(CFE_TBL_HandleToID(CFE_TBL_BAD_TABLE_HANDLE)));
    printf("tbl_handleid roundtrip=%d fromundef=%d\n",
           (int)(CFE_TBL_HandleFromID(CFE_TBL_HandleToID(7)) == 7),
           (int)(CFE_TBL_HandleFromID(CFE_TBL_HANDLEID_UNDEFINED) == CFE_TBL_BAD_TABLE_HANDLE));

    /* --- THE NULL-ARGUMENT REFUSALS, which return before any transaction starts ---------- */
    printf("tbl_apinull reg1=%ld reg2=%ld share1=%ld share2=%ld\n",
           (long)CFE_TBL_Register(NULL, "X", 32, 0, NULL),
           (long)CFE_TBL_Register(&h1, NULL, 32, 0, NULL),
           (long)CFE_TBL_Share(NULL, "X"), (long)CFE_TBL_Share(&h1, NULL));
    printf("tbl_apinull load=%ld getaddr=%ld getaddrs1=%ld getaddrs2=%ld reladdrs=%ld info1=%ld\n",
           (long)CFE_TBL_Load(0, CFE_TBL_SRC_ADDRESS, NULL),
           (long)CFE_TBL_GetAddress(NULL, 0), (long)CFE_TBL_GetAddresses(NULL, 1, handles),
           (long)CFE_TBL_GetAddresses(addrs, 1, NULL), (long)CFE_TBL_ReleaseAddresses(1, NULL),
           (long)CFE_TBL_GetInfo(NULL, "X"));

    /* --- REGISTER, as CFE_EVS ------------------------------------------------------------ */
    es_set_ctx(1);
    tbl_val_rc = CFE_SUCCESS;
    st         = CFE_TBL_Register(&h1, "Api", 32, CFE_TBL_OPT_DEFAULT, tbl_val_stub);
    printf("tbl_apireg rc=%ld handle=%d id=%lu\n", (long)st, (int)h1,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_HandleToID(h1)));
    /* AND THE DUPLICATE, which is a WARNING and hands back the SAME handle -- the one path in
     * the registry that is a supported no-op rather than an error. */
    st = CFE_TBL_Register(&h2, "Api", 32, CFE_TBL_OPT_DEFAULT, tbl_val_stub);
    printf("tbl_apireg dup=%ld same=%d\n", (long)st, (int)(h2 == h1));

    /* --- SHARE, as OTHER_APP, which is what CFE_TBL_TxnContext_OTHER_APP is for ---------- */
    es_set_ctx(2);
    st = CFE_TBL_Share(&h2, "CFE_EVS.Api");
    printf("tbl_apishare rc=%ld different=%d users=%d\n", (long)st, (int)(h2 != h1),
           (int)(CFE_TBL_GetInfo(&info, "CFE_EVS.Api") == CFE_SUCCESS ? info.NumUsers : 0));
    st = CFE_TBL_Share(&hbad, "NO.SUCH");
    printf("tbl_apishare missing=%ld bad=%d\n", (long)st,
           (int)(hbad == CFE_TBL_BAD_TABLE_HANDLE));

    /* RESOLVE THE RECORD AND THE TWO DESCRIPTORS, rather than assuming where they landed.
     * THE FIRST DRAFT HARD-CODED Registry[0], Handles[0] and Handles[1] and SEVEN assertions
     * below read the wrong objects: `tbl_apival status=0` where a pending validation was
     * planted, `tbl_apimanage updated=0`, `tbl_apinotify enabled=0` right after a call that
     * returned CFE_SUCCESS, `tbl_apimod own=0 other=0`. Each was a plausible-looking zero.
     * CFE_TBL_InitData seeds LastRegId to the BASE, so the allocator does not start at index 0
     * -- which is exactly the kind of thing a hand-built global hides and the real startup
     * path does not. */
    rr  = CFE_TBL_LocateRegRecByName("CFE_EVS.Api");
    ad1 = CFE_TBL_LocateAccDescByHandle(CFE_TBL_HandleToID(h1));
    ad2 = CFE_TBL_LocateAccDescByHandle(CFE_TBL_HandleToID(h2));
    printf("tbl_apiresolve rr=%d ad1=%d ad2=%d distinct=%d\n", (int)(rr != NULL),
           (int)(ad1 != NULL), (int)(ad2 != NULL), (int)(ad1 != ad2));

    /* --- LOAD, FROM A FILE, as the OWNER ------------------------------------------------
     * FROM A FILE AND NOT FROM AN ADDRESS, deliberately: CFE_TBL_TxnLoadFromSourceAddr writes
     * "Addr 0x%08lX" of the caller's pointer into DataSource, and CFE_TBL_GetInfo reports
     * DataSource as LastFileLoaded -- so an address load put `last=Addr 0x102F99610` into the
     * transcript, an arm64 value the RISC-V half cannot match. A file load makes the same
     * field a filename, which also leaves the modified marker below readable.
     *
     * A non-owner is refused first: CFE_TBL_TxnContext_OWNER_APP is what Load requires, and
     * OTHER_APP holds only an accessor descriptor. */
    tbl_mkfile("CFE_EVS.Api", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x7E);
    printf("tbl_apiload notowner=%ld\n",
           (long)CFE_TBL_Load(h2, CFE_TBL_SRC_FILE, "/ram/load.tbl"));
    es_set_ctx(1);
    st = CFE_TBL_Load(h1, CFE_TBL_SRC_FILE, "/ram/load.tbl");
    printf("tbl_apiload rc=%ld\n", (long)st);

    /* --- GetAddress / ReleaseAddress ---------------------------------------------------- */
    addr = NULL;
    st   = CFE_TBL_GetAddress(&addr, h1);
    printf("tbl_apiaddr rc=%ld nonnull=%d first=%02x\n", (long)st, (int)(addr != NULL),
           addr == NULL ? 0 : (unsigned)((const uint8 *)addr)[0]);
    printf("tbl_apiaddr release=%ld\n", (long)CFE_TBL_ReleaseAddress(h1));
    /* AND THE PLURAL FORMS. Two handles, one good and one that was never registered: the
     * first non-success is KEPT and the loop keeps going, so `rc` is the bad one's status
     * while the good one's address still comes back. */
    handles[0] = h1;
    handles[1] = 0x7FFF;
    a0         = NULL;
    a1         = NULL;
    addrs[0]   = &a0;
    addrs[1]   = &a1;
    st         = CFE_TBL_GetAddresses(addrs, 2, handles);
    printf("tbl_apiaddrs rc=%ld good=%d bad=%d\n", (long)st, (int)(a0 != NULL),
           (int)(a1 == NULL));
    printf("tbl_apiaddrs release=%ld\n", (long)CFE_TBL_ReleaseAddresses(2, handles));

    /* --- VALIDATE, GetStatus, Manage ---------------------------------------------------- */
    /* With nothing pending, Validate says so and GetStatus says CFE_SUCCESS. */
    st = CFE_TBL_Validate(h1);
    printf("tbl_apival nopending=%ld", (long)st);
    st = CFE_TBL_GetStatus(h1);
    printf(" status=%ld\n", (long)st);
    /* Now plant a validation request and run it twice, on the two buffer selections -- and
     * WHAT THEY REACH IS DIFFERENT, which is not what the first draft's comment claimed.
     *
     * INACTIVE means the load-in-progress buffer, and there is no load in progress, so
     * CFE_TBL_GetLoadInProgressBuffer answers NULL and CFE_TBL_Validate takes its "no buffer,
     * it cannot be valid" arm: `result=-1` WITHOUT the validation function ever being called.
     * ACTIVE finds the real buffer and does call it, which is why `failed` reports the -3 the
     * stub was told to return. Two distinct arms, one of which never reaches the callback.
     *
     * In both cases the result goes into the validation-result BLOCK, not the return value --
     * `performed=0` means "the validation was carried out", not "the table is valid", which is
     * NASA's own distinction and the reason CFE_TBL_Manage loops on it. */
    CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0],
                                    CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
    CFE_TBL_Global.ValidationResults[0].BufferSelect = CFE_TBL_BufferSelect_INACTIVE;
    rr->PendingValId =
        CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
    printf("tbl_apival status=%ld\n", (long)CFE_TBL_GetStatus(h1));
    tbl_val_rc = CFE_SUCCESS;
    st         = CFE_TBL_Validate(h1);
    printf("tbl_apival performed=%ld result=%ld state=%u\n", (long)st,
           (long)CFE_TBL_Global.ValidationResults[0].Result,
           (unsigned)CFE_TBL_Global.ValidationResults[0].State);
    /* a FAILING validator takes the other event and leaves a non-zero result */
    CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0],
                                    CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
    CFE_TBL_Global.ValidationResults[0].BufferSelect = CFE_TBL_BufferSelect_ACTIVE;
    rr->PendingValId =
        CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
    tbl_val_rc = -3;
    st         = CFE_TBL_Validate(h1);
    printf("tbl_apival failed=%ld result=%ld\n", (long)st,
           (long)CFE_TBL_Global.ValidationResults[0].Result);
    tbl_val_rc = CFE_SUCCESS;

    /* --- MANAGE, which is the loop over GetStatus --------------------------------------- */
    /* Nothing pending: one pass, CFE_SUCCESS. */
    printf("tbl_apimanage idle=%ld\n", (long)CFE_TBL_Manage(h1));
    /* An UPDATE pending: Manage updates and reports CFE_TBL_INFO_UPDATED, which is the code a
     * caller watches for to know its table changed underneath it. */
    rr->Buffers[0].IsValid     = true;
    rr->Buffers[0].ActivateReq = true;
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    printf("tbl_apimanage updated=%ld\n", (long)CFE_TBL_Manage(h1));

    /* --- UPDATE on its own, and the no-op case ------------------------------------------ */
    printf("tbl_apiupdate nothing=%ld\n", (long)CFE_TBL_Update(h1));

    /* --- GetInfo, which is the one function that fills a struct for the caller ----------- */
    memset(&info, 0xA5, sizeof(info));
    st = CFE_TBL_GetInfo(&info, "CFE_EVS.Api");
    printf("tbl_apiinfo rc=%ld size=%lu users=%u loaded=%d dbl=%d dmp=%d usr=%d crit=%d "
           "crc=%d last=%s\n",
           (long)st, (unsigned long)info.Size, (unsigned)info.NumUsers,
           (int)info.TableLoadedOnce, (int)info.DoubleBuffered, (int)info.DumpOnly,
           (int)info.UserDefAddr, (int)info.Critical, (int)(info.Crc != 0),
           info.LastFileLoaded);
    printf("tbl_apiinfo missing=%ld\n", (long)CFE_TBL_GetInfo(&info, "NO.SUCH"));

    /* --- MODIFIED, which marks the table and notifies the OTHER holders ----------------- */
    /* h2 belongs to OTHER_APP, so calling Modified as CFE_EVS must set OTHER_APP's Updated
     * flag and NOT its own -- that is what CFE_TBL_NotifyOtherAppHelper is for. */
    ad1->Updated = false;
    ad2->Updated = false;
    st           = CFE_TBL_Modified(h1);
    printf("tbl_apimod rc=%ld own=%d other=%d\n", (long)st, (int)ad1->Updated,
           (int)ad2->Updated);
    /* and the name now carries the modified marker */
    CFE_TBL_GetInfo(&info, "CFE_EVS.Api");
    printf("tbl_apimod marked=%s\n", info.LastFileLoaded);

    /* --- NOTIFY BY MESSAGE: owner only -------------------------------------------------- */
    st = CFE_TBL_NotifyByMessage(h1, CFE_SB_ValueToMsgId(0x1888), 3, 0x1234);
    printf("tbl_apinotify owner=%ld enabled=%d mid=%04lx fcn=%u param=%lx\n", (long)st,
           (int)rr->Notify.Enabled, (unsigned long)CFE_SB_MsgIdToValue(rr->Notify.MsgId),
           (unsigned)rr->Notify.FcnCode, (unsigned long)rr->Notify.Param);
    es_set_ctx(2);
    printf("tbl_apinotify notowner=%ld\n",
           (long)CFE_TBL_NotifyByMessage(h2, CFE_SB_ValueToMsgId(0x1888), 3, 0x1234));
    es_set_ctx(1);

    /* --- DUMP TO BUFFER, both answers --------------------------------------------------- */
    /* With no dump pending at all, NO_DUMP_PENDING and nothing is logged. With a STALE id --
     * one that is valid but matches no block -- the same status comes back, the id is CLEARED,
     * and a syslog line says it was dropped. The `cleared` field is the difference. */
    printf("tbl_apidump none=%ld\n", (long)CFE_TBL_DumpToBuffer(h1));
    rr->DumpControlId =
        CFE_TBL_DUMPCTRLID_C(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + 1));
    st = CFE_TBL_DumpToBuffer(h1);
    printf("tbl_apidump stale=%ld cleared=%d\n", (long)st,
           (int)!CFE_TBL_DUMPCTRLID_IS_VALID(rr->DumpControlId));

    /* --- UNREGISTER, and the handle is dead afterwards ---------------------------------- */
    st = CFE_TBL_Unregister(h1);
    printf("tbl_apiunreg rc=%ld\n", (long)st);
    /* EACH CALL INTO A LOCAL FIRST. Both of these emit a syslog line, and C evaluates every
     * printf argument before printing any of them while the HolyC half prints incrementally --
     * so as arguments they put their log lines on opposite sides of the label. Fourth and fifth
     * instance of this trap in the project; it is always worth writing out. */
    st = CFE_TBL_Unregister(h1);
    printf("tbl_apiunreg again=%ld", (long)st);
    st = CFE_TBL_GetStatus(h1);
    printf(" status=%ld\n", (long)st);

    es_ctx_init();
}

/* --- cfe_tbl_load.c -------------------------------------------------------------
 * SIXTEEN FUNCTIONS, AND A LOAD IS THE MOST GUARDED OPERATION IN TABLE SERVICES. The exercise
 * follows the file path in order, because every step can refuse and the interesting thing
 * about each one is WHICH refusal it produces.
 *
 * THE FILE IS BUILT EXPLICITLY, NOT ROUND-TRIPPED THROUGH A DUMP, and that is not a style
 * choice. CFE_TBL_WriteSnapshotToFile leaves Tbl.Reserved and Tbl.Offset as uninitialised
 * stack -- see the note at tbl_dmphdr and in docs/CFS_PLAN.md -- and CFE_TBL_ReadHeaders reads
 * Offset to decide where the data lands. A dump-then-load exercise would therefore be
 * NONDETERMINISTIC between the two halves and would present as a load.c translation bug. So
 * tbl_mkfile below sets all four table-header fields itself. */
static void tbl_mkfile(const char *tblname, uint32 offset, uint32 numbytes, size_t datasize,
                       uint32 contenttype, uint16 subtype, uint8 fill)
{
    CFE_TBL_CombinedFileHdr_t hdr;
    CFE_TBL_TxnState_t        txn;
    osal_id_t                 fd;
    size_t                    k;

    memset(&txn, 0, sizeof(txn));
    /* THE WHOLE header, unlike NASA's partial memset -- this is driver code and may be
     * deterministic where the code under test is not. */
    memset(&hdr, 0, sizeof(hdr));
    CFE_FS_InitHeader(&hdr.Std, "Table Load Image", subtype);
    hdr.Std.ContentType   = contenttype;
    hdr.Std.TimeSeconds   = 0x11223344;
    hdr.Std.TimeSubSeconds = 0x55667788;
    hdr.Tbl.Reserved = 0;
    hdr.Tbl.Offset   = offset;
    hdr.Tbl.NumBytes = numbytes;
    strncpy(hdr.Tbl.TableName, tblname, sizeof(hdr.Tbl.TableName) - 1);

    fs_len     = 0;
    fs_pos     = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    CFE_TBL_WriteHeaders(&txn, fd, &hdr);
    for (k = 0; k < datasize; k++)
    {
        tbl_probe_mem2[k] = (uint8)(fill + k);
    }
    OS_write(fd, tbl_probe_mem2, datasize);
    OS_close(fd);
    /* THE CONTENT TYPE HAS TO BE POKED INTO THE FILE, not set in the struct. CFE_FS_WriteHeader
     * writes CFE_FS_FILE_CONTENT_ID itself, overwriting whatever the caller put there -- the
     * first draft set hdr.Std.ContentType and the badcontent case came back SUCCESS with
     * ct=63464531, which is "cFE1" in ASCII. It is the first four bytes of the file,
     * big-endian. (SubType survives, which is why that case needs no poke; and TimeSeconds does
     * NOT survive either -- WriteHeader stamps the current time -- which is why tbl_rdhdr
     * reports the clock's value and not the one tbl_mkfile asked for.) */
    if (contenttype != CFE_FS_FILE_CONTENT_ID)
    {
        fs_data[0] = (contenttype >> 24) & 0xFF;
        fs_data[1] = (contenttype >> 16) & 0xFF;
        fs_data[2] = (contenttype >> 8) & 0xFF;
        fs_data[3] = contenttype & 0xFF;
    }
    fs_pos = 0;
}

static void TblLoadExercise(void)
{
    CFE_TBL_TxnState_t        txn;
    CFE_TBL_RegistryRec_t    *rr;
    CFE_TBL_CombinedFileHdr_t hdr;
    CFE_TBL_LoadBuff_t       *lb;
    osal_id_t                 fd;
    int32                     st;
    int                       k;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B60);
    CFE_TBL_Global.WorkBufMutex  = OS_ObjectIdFromInteger(0x7B61);
    CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_C(ES_CTX_APPID(1));
    CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(
        CFE_TBL_LOADBUFFID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS +
        2 * CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1);

    /* --- WHAT THIS EXERCISE CANNOT REACH, AND WHY, said before the parts it can -----------
     *
     * CFE_TBL_ValidateTableHeaderId CANNOT BE CALLED FROM HERE. Like
     * CFE_TBL_HandleListGetSafeLink in cfe_tbl_internal.c, it is a non-static definition with
     * NO DECLARATION IN ANY HEADER, so this driver cannot name it. (check_coverage and
     * check_signatures both compare it; only the body is unexercised.)
     *
     * And it would not help much if it could: both accept lists are EMPTY in this
     * configuration -- cfe_platformcfg_tables.HC says so at its top, CFE_PLATFORM_TBL_VALID_SCID
     * and _PRID have a count of zero -- so the function always returns true and
     * CFE_TBL_ReadHeaders' CFE_TBL_ERR_BAD_SPACECRAFT_ID and CFE_TBL_ERR_BAD_PROCESSOR_ID arms
     * are UNREACHABLE. That is a configuration fact, the same kind the coverage gate already
     * records for the nine functions a verified #if excludes, not a gap someone forgot to
     * fill. A mission that configures a list is the thing that would reach them.
     */

    /* --- THE REGISTRY RECORD every step below works against ----------------------------- */
    /* Registry[11]'s own buffer pair is serial 4 + 2*11 = 26 and 27. */
    rr = &CFE_TBL_Global.Registry[11];
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 11));
    strncpy(rr->Config.Name, "LD_APP.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
    rr->Config.Size = 32;
    rr->OwnerAppId  = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    CFE_TBL_HandleLinkInit(&rr->AccessList);
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 26),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_LoadBuffSetAllocatedBlock(&rr->Buffers[0], tbl_probe_mem, sizeof(tbl_probe_mem));
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    {
        CFE_TBL_LoadBuffSetAllocatedBlock(&CFE_TBL_Global.LoadBuffs[k], tbl_probe_mem,
                                          sizeof(tbl_probe_mem));
    }
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    txn.RegId     = CFE_TBL_RegRecGetID(rr);

    /* --- CFE_TBL_ReadHeaders, four answers ---------------------------------------------- */
    /* A SHORT FILE first: no std header at all. */
    fs_len = 0;
    fs_pos = 0;
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    memset(&hdr, 0, sizeof(hdr));
    st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
    printf("tbl_rdhdr nostd=%ld\n", (long)st);
    OS_close(fd);
    /* WRONG CONTENT ID */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 32, 0xBADF00D, CFE_FS_SubType_TBL_IMG, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    memset(&hdr, 0, sizeof(hdr));
    st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
    printf("tbl_rdhdr badcontent=%ld ct=%08lx\n", (long)st, (unsigned long)hdr.Std.ContentType);
    OS_close(fd);
    /* WRONG SUBTYPE */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, 99, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    memset(&hdr, 0, sizeof(hdr));
    st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
    printf("tbl_rdhdr badsubtype=%ld sub=%lu\n", (long)st, (unsigned long)hdr.Std.SubType);
    OS_close(fd);
    /* AND A GOOD ONE: the whole header comes back, and the four table fields are exactly what
     * tbl_mkfile wrote -- which is the point of building it explicitly. */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    memset(&hdr, 0, sizeof(hdr));
    st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
    printf("tbl_rdhdr ok=%ld name=%s n=%lu off=%lu resv=%lu secs=%08lx\n", (long)st,
           hdr.Tbl.TableName, (unsigned long)hdr.Tbl.NumBytes, (unsigned long)hdr.Tbl.Offset,
           (unsigned long)hdr.Tbl.Reserved, (unsigned long)hdr.Std.TimeSeconds);

    /* --- CFE_TBL_ValidateFileIsLoadable, five answers ----------------------------------- */
    txn.RegRecPtr = NULL;
    printf("tbl_loadable notbl=%ld\n", (long)CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl));
    txn.RegRecPtr = rr;
    strncpy(hdr.Tbl.TableName, "OTHER.Tbl", sizeof(hdr.Tbl.TableName) - 1);
    printf("tbl_loadable wrongname=%ld\n", (long)CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl));
    strncpy(hdr.Tbl.TableName, "LD_APP.Tbl", sizeof(hdr.Tbl.TableName) - 1);
    hdr.Tbl.NumBytes = 0;
    printf("tbl_loadable zerolen=%ld\n", (long)CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl));
    hdr.Tbl.NumBytes = 16;
    hdr.Tbl.Offset   = 8;
    printf("tbl_loadable partial=%ld\n", (long)CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl));
    /* a partial load IS allowed once the table has been loaded before */
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    printf("tbl_loadable partialok=%ld\n", (long)CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl));
    rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
    hdr.Tbl.Offset            = 0;
    hdr.Tbl.NumBytes          = 32;
    printf("tbl_loadable ok=%ld\n", (long)CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl));

    /* --- CFE_TBL_ValidateLoadRequest, the five arms ------------------------------------- */
    /* Into locals: each refusal queues an event, and they are all sent at the end. */
    txn.RegRecPtr = NULL;
    printf("tbl_ldreq notbl=%ld\n", (long)CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE));
    txn.RegRecPtr = rr;
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    printf("tbl_ldreq inprogress=%ld\n",
           (long)CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE));
    CFE_TBL_RegRecClearLoadInProgress(rr);
    printf("tbl_ldreq badsrc=%ld\n", (long)CFE_TBL_ValidateLoadRequest(&txn, 99));
    /* A DUMP-ONLY TABLE CAN BE LOADED EXACTLY ONCE AND ONLY FROM AN ADDRESS. Not user-defined
     * is refused; user-defined but already loaded is refused; user-defined, unloaded, from a
     * FILE is refused; user-defined, unloaded, from an ADDRESS is allowed. */
    rr->Config.DumpOnly = true;
    CFE_TBL_RegRecClearLoadInProgress(rr);
    printf("tbl_ldreq dmp_notuser=%ld\n",
           (long)CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_ADDRESS));
    rr->Config.UserDefAddr = true;
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    CFE_TBL_RegRecClearLoadInProgress(rr);
    printf("tbl_ldreq dmp_loaded=%ld\n",
           (long)CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_ADDRESS));
    rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
    CFE_TBL_RegRecClearLoadInProgress(rr);
    printf("tbl_ldreq dmp_fromfile=%ld\n",
           (long)CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE));
    CFE_TBL_RegRecClearLoadInProgress(rr);
    st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_ADDRESS);
    printf("tbl_ldreq dmp_fromaddr=%ld lip=%d\n", (long)st,
           (int)CFE_TBL_RegRecIsLoadInProgress(rr));
    rr->Config.DumpOnly    = false;
    rr->Config.UserDefAddr = false;
    /* and the ordinary success, which RESERVES a working buffer as its whole side effect */
    CFE_TBL_RegRecClearLoadInProgress(rr);
    st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
    printf("tbl_ldreq ok=%ld lip=%d\n", (long)st, (int)CFE_TBL_RegRecIsLoadInProgress(rr));
    /* THE EVENT LIST HOLDS EIGHT AND THIS GROUP QUEUED MORE, which is why it is flushed here
     * instead of at the end of the block. A negative control found this: changing the event id
     * in CFE_TBL_ValidateLoadInProgress's positive arm left the transcript IDENTICAL, because by
     * the time that code ran the transaction had long overflowed and CFE_TBL_TxnAddEvent was
     * dropping everything. A real mutation that still passes means the driver never reaches it.
     *
     * `queued=%u` is NASA's own overflow witness: the counter "always increments ... to make it
     * evident if there was an overflow", and until now nothing read it. Above 8 means events
     * were lost. */
    printf("tbl_ldreq queued=%u overflow=%d\n", (unsigned)txn.NumPendingEvents,
           (int)(txn.NumPendingEvents > CFE_TBL_MAX_EVENTS_PER_TXN));
    strncpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
    CFE_TBL_SendTableLoadEvents(&txn);
    txn.NumPendingEvents = 0;

    /* --- CFE_TBL_LoadContentFromFile, four answers -------------------------------------- */
    /* TOO LARGE: a 32-byte buffer cannot take 32 bytes at offset 40. */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    OS_lseek(fd, 116, 0);
    printf("tbl_ldcontent toobig=%ld\n",
           (long)CFE_TBL_LoadContentFromFile(&txn, fd, 40, 32));
    OS_close(fd);
    /* SHORT: the header claims 32 bytes but only 8 follow. */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 8, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    OS_lseek(fd, 116, 0);
    printf("tbl_ldcontent short=%ld\n", (long)CFE_TBL_LoadContentFromFile(&txn, fd, 0, 32));
    OS_close(fd);
    /* TOO MUCH DATA: the header claims 32 and 40 follow. This is the one-byte read past the
     * end, and nothing else in the function would catch it. */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 40, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    OS_lseek(fd, 116, 0);
    printf("tbl_ldcontent extradata=%ld\n", (long)CFE_TBL_LoadContentFromFile(&txn, fd, 0, 32));
    OS_close(fd);
    /* AND EXACTLY RIGHT. first/last are the proof the DATA arrived, not just the status. */
    tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
    OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    OS_lseek(fd, 116, 0);
    st = CFE_TBL_LoadContentFromFile(&txn, fd, 0, 32);
    OS_close(fd);
    lb = CFE_TBL_GetLoadInProgressBuffer(rr);
    printf("tbl_ldcontent ok=%ld size=%lu first=%02x last=%02x\n", (long)st,
           (unsigned long)(lb == NULL ? 0 : CFE_TBL_LoadBuffGetContentSize(lb)),
           lb == NULL ? 0 : (unsigned)((const uint8 *)CFE_TBL_LoadBuffGetReadPointer(lb))[0],
           lb == NULL ? 0 : (unsigned)((const uint8 *)CFE_TBL_LoadBuffGetReadPointer(lb))[31]);

    /* flush again before the validation group, same reason */
    printf("tbl_ldcontent queued=%u\n", (unsigned)txn.NumPendingEvents);
    CFE_TBL_SendTableLoadFileEvents(&txn, "/ram/load.tbl", &hdr);
    txn.NumPendingEvents = 0;

    /* --- CFE_TBL_SetMetaDataFromFileHeader ---------------------------------------------- */
    /* The file time comes from the STD header, the CRC is recomputed, and IsValid is seeded
     * from whether a validation function exists -- a table with no validator is valid on
     * arrival, one with a validator is not until the validator says so. */
    hdr.Std.TimeSeconds    = 0x11223344;
    hdr.Std.TimeSubSeconds = 0x55667788;
    rr->Config.ValidationFuncPtr = NULL;
    CFE_TBL_SetMetaDataFromFileHeader(&txn, "/ram/load.tbl", &hdr.Std);
    printf("tbl_ldmeta src=%s secs=%08lx subs=%08lx valid=%d actreq=%d crc=%d\n",
           lb->DataSource, (unsigned long)lb->FileTime.Seconds,
           (unsigned long)lb->FileTime.Subseconds, (int)lb->IsValid, (int)lb->ActivateReq,
           (int)(lb->Crc != 0));
    rr->Config.ValidationFuncPtr = tbl_val_stub;
    CFE_TBL_SetMetaDataFromFileHeader(&txn, "/ram/load.tbl", &hdr.Std);
    printf("tbl_ldmeta withfunc valid=%d\n", (int)lb->IsValid);

    /* --- CFE_TBL_ValidateLoadInProgress, four answers ----------------------------------- */
    /* No validator is assumed success; a validator returning 0 succeeds; a POSITIVE return and
     * a NEGATIVE one raise DIFFERENT event ids, which NASA's own comment calls historical and
     * unexplained. */
    rr->Config.ValidationFuncPtr = NULL;
    printf("tbl_ldval nofunc=%ld valid=%d actreq=%d\n",
           (long)CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS), (int)lb->IsValid,
           (int)lb->ActivateReq);
    rr->Config.ValidationFuncPtr = tbl_val_stub;
    tbl_val_rc                   = CFE_SUCCESS;
    printf("tbl_ldval pass=%ld valid=%d\n",
           (long)CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS), (int)lb->IsValid);
    tbl_val_rc = 7;
    st         = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
    printf("tbl_ldval positive=%ld valid=%d\n", (long)st, (int)lb->IsValid);
    tbl_val_rc = -9;
    st         = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
    printf("tbl_ldval negative=%ld valid=%d cleared=%d\n", (long)st, (int)lb->IsValid,
           (int)(((const uint8 *)CFE_TBL_LoadBuffGetReadPointer(lb))[0] == 0));
    tbl_val_rc                   = CFE_SUCCESS;
    rr->Config.ValidationFuncPtr = NULL;
    /* and the no-buffer arm */
    CFE_TBL_RegRecClearLoadInProgress(rr);
    printf("tbl_ldval nobuf=%ld\n", (long)CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS));

    /* --- SEND WHAT THE VALIDATION GROUP QUEUED ------------------------------------------
     * Only that group is pending now, so these four lines are the two validation event ids --
     * CFE_TBL_LOAD_VAL_ERR_EID for a POSITIVE return and CFE_TBL_VALIDATION_ERR_EID for a
     * negative one -- plus the second of each pair, because the positive arm sets Status to
     * CFE_STATUS_VALIDATION_FAILURE, which is NEGATIVE, so it falls into the negative arm too
     * and queues BOTH. That cascade is NASA's and is the reason a single-id mutation is only
     * visible once the list is not overflowing.
     *
     * The FILE helper handles what needs the header in its text and FALLS THROUGH to the basic
     * one for the rest, so this one call renders events from both switches. The asymmetry is
     * the design -- a non-file load can never raise a file event. */
    printf("tbl_ldval queued=%u\n", (unsigned)txn.NumPendingEvents);
    strncpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
    CFE_TBL_SendTableLoadFileEvents(&txn, "/ram/load.tbl", &hdr);
    /* AND THE BASIC-ONLY PATH, which cannot render a file event at all. */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    strncpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
    CFE_TBL_TxnAddEvent(&txn, CFE_TBL_LOAD_IN_PROGRESS_ERR_EID, CFE_TBL_ERR_LOAD_IN_PROGRESS, 0);
    CFE_TBL_TxnAddEvent(&txn, CFE_TBL_FILE_LOADED_INF_EID, 0, 0);
    CFE_TBL_SendTableLoadEvents(&txn);

    /* --- CFE_TBL_TxnLoadFromFile, the whole path ---------------------------------------- */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    txn.RegId     = CFE_TBL_RegRecGetID(rr);
    strncpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
    fs_open_fail  = 1;
    printf("tbl_ldfile noopen=%ld\n", (long)CFE_TBL_TxnLoadFromFile(&txn, "/ram/load.tbl"));
    fs_open_fail = 0;
    tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x90);
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    txn.RegId     = CFE_TBL_RegRecGetID(rr);
    strncpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
    CFE_TBL_RegRecClearLoadInProgress(rr);
    CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
    st = CFE_TBL_TxnLoadFromFile(&txn, "/ram/load.tbl");
    lb = CFE_TBL_GetLoadInProgressBuffer(rr);
    printf("tbl_ldfile ok=%ld first=%02x src=%s secs=%08lx\n", (long)st,
           lb == NULL ? 0 : (unsigned)((const uint8 *)CFE_TBL_LoadBuffGetReadPointer(lb))[0],
           lb == NULL ? "?" : lb->DataSource,
           (unsigned long)(lb == NULL ? 0 : lb->FileTime.Seconds));

    /* --- CFE_TBL_TxnLoadFromSourceAddr, both shapes ------------------------------------- */
    /* A NORMAL table COPIES the caller's memory; a DUMP-ONLY table keeps the caller's POINTER,
     * which is what makes a user-defined-address dump-only table possible at all. `alloc=0`
     * below is how CFE_TBL_LoadBuffIsAllocated tells the two apart. */
    memset(tbl_probe_mem2, 0xE1, sizeof(tbl_probe_mem2));
    rr->Config.DumpOnly = false;
    st                  = CFE_TBL_TxnLoadFromSourceAddr(&txn, tbl_probe_mem2);
    /* `addrpfx` rather than the string: CFE_TBL_TxnLoadFromSourceAddr formats the caller's
     * POINTER into DataSource, so only the fixed prefix can be compared between the halves. */
    printf("tbl_ldaddr copy=%ld first=%02x isext=%d addrpfx=%d\n", (long)st,
           (unsigned)((const uint8 *)CFE_TBL_LoadBuffGetReadPointer(lb))[0],
           (int)(CFE_TBL_LoadBuffGetReadPointer(lb) == tbl_probe_mem2),
           (int)(strncmp(lb->DataSource, "Addr 0x", 7) == 0));
    rr->Config.DumpOnly = true;
    st                  = CFE_TBL_TxnLoadFromSourceAddr(&txn, tbl_probe_mem2);
    printf("tbl_ldaddr external=%ld isext=%d alloc=%d\n", (long)st,
           (int)(CFE_TBL_LoadBuffGetReadPointer(lb) == tbl_probe_mem2),
           (int)CFE_TBL_LoadBuffIsAllocated(lb));
    rr->Config.DumpOnly = false;
    CFE_TBL_LoadBuffSetAllocatedBlock(lb, tbl_probe_mem, sizeof(tbl_probe_mem));
    /* AND THE DataSource MUST BE PUT BACK TO A FIXED STRING. CFE_TBL_TxnLoadFromSourceAddr
     * wrote "Addr 0x%08lX" of the caller's POINTER into it, and CFE_TBL_LoadFinish's success
     * event prints the last file loaded -- so the transcript grew a line reading
     * `Successfully loaded 'LD_APP.Tbl' from 'Addr 0x10458D610'`, an arm64 address that the
     * RISC-V half has no way to match. The `src=%.5s` above prints only "Addr " for the same
     * reason. A pointer value in a differential transcript is always a defect in the
     * exercise. */
    strncpy(lb->DataSource, "/ram/load.tbl", OS_MAX_PATH_LEN - 1);

    /* --- CFE_TBL_LoadFinish, three answers, and CFE_TBL_AbortLoad ----------------------- */
    /* A FAILING status DISCARDS the working buffer and nothing else happens. */
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    printf("tbl_ldfinish failed=%ld lip=%d\n",
           (long)CFE_TBL_LoadFinish(&txn, CFE_TBL_ERR_ACCESS),
           (int)CFE_TBL_RegRecIsLoadInProgress(rr));
    /* THE FIRST SUCCESS IS A **DEBUG** EVENT, every later one INFORMATION -- NASA's reason is
     * that every table in the system loads once at startup and INFORMATION would flood the log
     * at the worst possible moment.
     *
     * AND THE WAY THAT SHOWS IN THE TRANSCRIPT IS AN ABSENCE: this driver's EVS filters DEBUG,
     * so the FIRST load produces NO event line and the second produces
     * `35: Successfully loaded ...`. One line for two calls is the assertion. The status is 0
     * both times and cannot tell them apart. */
    rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    rr->Buffers[0].IsValid     = true;
    rr->Buffers[0].ActivateReq = true;
    st                         = CFE_TBL_LoadFinish(&txn, CFE_SUCCESS);
    printf("tbl_ldfinish first=%ld loaded=%d last=%d\n", (long)st,
           (int)CFE_TBL_RegRecIsTableLoaded(rr),
           (int)CFE_RESOURCEID_TEST_EQUAL(CFE_TBL_Global.LastTblUpdated,
                                          CFE_TBL_RegRecGetID(rr)));
    /* and again, now that the table HAS been loaded once */
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    rr->Buffers[0].IsValid     = true;
    rr->Buffers[0].ActivateReq = true;
    printf("tbl_ldfinish again=%ld\n", (long)CFE_TBL_LoadFinish(&txn, CFE_SUCCESS));
    /* AND THE ABORT, which is the only function here that sends its event directly rather than
     * queueing it on the transaction. */
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    CFE_TBL_AbortLoad(rr);
    printf("tbl_ldabort lip=%d\n", (int)CFE_TBL_RegRecIsLoadInProgress(rr));
}

/* --- cfe_tbl_dump.c -------------------------------------------------------------
 * A DUMP IS THREE PHASES SEPARATED IN TIME, and the exercise follows them in order because
 * each one's output is the next one's input:
 *
 *   1. ALLOCATE   a dump control block, recording WHICH buffer is to be dumped
 *   2. SNAPSHOT   copy that buffer into a shared load buffer and stamp the time
 *   3. WRITE      the background task writes the snapshot to a file and frees both
 *
 * The split exists so a dump never blocks the caller on file I/O, and so a DUMP-ONLY table's
 * snapshot happens when its OWNER says so rather than when the command arrives. Phase 2
 * therefore has two shapes, and both are driven below. */
static void TblDumpExercise(void)
{
    CFE_TBL_TxnState_t     txn;
    CFE_TBL_RegistryRec_t *rr;
    CFE_TBL_DumpControl_t *dc;
    CFE_TBL_DumpCtrlId_t   dcid;
    CFE_TBL_LoadBuff_t    *lb;
    int32                  st;
    int                    k;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex        = OS_ObjectIdFromInteger(0x7B50);
    CFE_TBL_Global.WorkBufMutex         = OS_ObjectIdFromInteger(0x7B51);
    CFE_TBL_Global.LastDumpCtrlBlockId  = CFE_ResourceId_FromInteger(
        CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1);
    CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE +
                                                               (CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS + 2 * CFE_PLATFORM_TBL_MAX_NUM_TABLES) - 1);
    CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_C(ES_CTX_APPID(1));

    /* Registry[9]'s own buffer pair is serial 4 + 2*9 = 22 and 23. */
    rr = &CFE_TBL_Global.Registry[9];
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 9));
    strncpy(rr->Config.Name, "DMP_APP.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
    rr->Config.Size = 32;
    rr->OwnerAppId  = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    CFE_TBL_HandleLinkInit(&rr->AccessList);
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 22),
                            CFE_TBL_RegRecGetID(rr));
    memset(tbl_probe_mem, 0xC3, sizeof(tbl_probe_mem));
    CFE_TBL_LoadBuffSetAllocatedBlock(&rr->Buffers[0], tbl_probe_mem, sizeof(tbl_probe_mem));
    rr->Buffers[0].ContentSize = 32;
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);

    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    txn.RegId     = CFE_TBL_RegRecGetID(rr);

    /* --- PHASE 1: ALLOCATE, and the four ways it answers ------------------------------- */
    /* Into locals first: three of the four arms add a deferred event, and the events are sent
     * at the end of this block rather than per call -- which is the whole point of the
     * transaction's event list. */
    txn.RegRecPtr = NULL;
    st            = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
    printf("tbl_dmpalloc notbl=%ld undef=%d\n", (long)st, (int)!CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
    txn.RegRecPtr = rr;
    st            = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, (CFE_TBL_BufferSelect_Enum_t)99);
    printf("tbl_dmpalloc badsel=%ld undef=%d\n", (long)st,
           (int)!CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
    st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
    dc = CFE_TBL_LocateDumpCtrlByID(dcid);
    printf("tbl_dmpalloc ok=%ld valid=%d used=%d src=%d name=%s\n", (long)st,
           (int)CFE_TBL_DUMPCTRLID_IS_VALID(dcid),
           (int)(dc != NULL && CFE_TBL_DumpCtrlBlockIsUsed(dc)),
           (int)(dc != NULL && CFE_RESOURCEID_TEST_EQUAL(dc->SourceBuffId,
                                                         CFE_TBL_LoadBufferGetID(&rr->Buffers[0]))),
           dc == NULL ? "?" : dc->TableName);
    /* a dump is pending on this table now, so the next request on it is refused */
    rr->DumpControlId = dcid;
    st                = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
    printf("tbl_dmpalloc pending=%ld\n", (long)st);
    rr->DumpControlId = CFE_TBL_DUMPCTRLID_UNDEFINED;
    /* EXHAUSTION: every block used, so the allocator has nowhere to put the next one */
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    {
        CFE_TBL_DumpCtrlBlockSetUsed(&CFE_TBL_Global.DumpControlBlocks[k],
                                     CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + k));
    }
    st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
    printf("tbl_dmpalloc toomany=%ld undef=%d\n", (long)st,
           (int)!CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
    /* SEND WHAT THE FOUR CALLS QUEUED. Five events in one go, which is what a transaction's
     * deferred event list is for -- and the text is built by CFE_TBL_SendDumpEventHelper, so
     * every line below is that switch answering. */
    CFE_TBL_SendTableDumpEvents(&txn, "/ram/dump.tbl", CFE_TBL_RegRecGetName(rr));

    /* AND THE TWO DEFAULTS, which only show with a fresh transaction carrying one event. NASA
     * refuses to leave either field blank: NULL becomes "[none]" and "[unknown]". */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    CFE_TBL_TxnAddEvent(&txn, CFE_TBL_DUMP_PENDING_ERR_EID, CFE_TBL_INFO_DUMP_PENDING, 0);
    CFE_TBL_SendTableDumpEvents(&txn, NULL, NULL);

    /* --- PHASE 2: SNAPSHOT, both shapes -------------------------------------------------- */
    /* Reset the blocks the exhaustion test above filled, and give the shared load buffers real
     * memory so AcquireGlobalLoadBuff has something to hand out. */
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    {
        CFE_TBL_DumpCtrlBlockSetFree(&CFE_TBL_Global.DumpControlBlocks[k]);
        CFE_TBL_LoadBuffSetAllocatedBlock(&CFE_TBL_Global.LoadBuffs[k], tbl_probe_mem2,
                                          sizeof(tbl_probe_mem2));
    }
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    txn.RegId     = CFE_TBL_RegRecGetID(rr);
    st            = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
    /* A NORMAL TABLE SNAPSHOTS IMMEDIATELY: Prepare calls ExecuteDumpSnapshot itself, so the
     * state comes back PERFORMED and the source id is CLEARED -- the dump no longer refers to
     * the table's buffer, it owns a copy. */
    st = CFE_TBL_PrepareDumpSnapshotBuffer(&txn, dcid, "/ram/dump.tbl");
    dc = CFE_TBL_LocateDumpCtrlByID(dcid);
    printf("tbl_dmpprep normal=%ld state=%u srccleared=%d buf=%d enc=%ld first=%02x\n", (long)st,
           (unsigned)dc->State, (int)!CFE_TBL_LOADBUFFID_IS_VALID(dc->SourceBuffId),
           (int)(dc->DumpBufferPtr != NULL), (long)dc->EncodeStatus,
           dc->DumpBufferPtr == NULL
               ? 0
               : (unsigned)*(const uint8 *)CFE_TBL_LoadBuffGetReadPointer(dc->DumpBufferPtr));
    /* A DUMP-ONLY TABLE DOES NOT: the state is PENDING and the REGISTRY RECORD remembers the
     * block, because the snapshot has to wait for the owner to call CFE_TBL_Modified. */
    CFE_TBL_DumpCtrlBlockSetFree(dc);
    rr->Config.DumpOnly = true;
    st                  = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
    st                  = CFE_TBL_PrepareDumpSnapshotBuffer(&txn, dcid, "/ram/dump.tbl");
    dc                  = CFE_TBL_LocateDumpCtrlByID(dcid);
    printf("tbl_dmpprep dumponly=%ld state=%u remembered=%d\n", (long)st, (unsigned)dc->State,
           (int)CFE_RESOURCEID_TEST_EQUAL(rr->DumpControlId, dcid));
    rr->Config.DumpOnly      = false;
    rr->DumpControlId        = CFE_TBL_DUMPCTRLID_UNDEFINED;
    /* AND THE NO-BUFFER ARM, which is why AcquireGlobalLoadBuff's NULL return matters: mark
     * every shared buffer used and there is nothing to snapshot into. */
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    {
        CFE_TBL_LoadBuffSetUsed(&CFE_TBL_Global.LoadBuffs[k],
                                CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + k),
                                CFE_TBL_RegRecGetID(rr));
    }
    st = CFE_TBL_PrepareDumpSnapshotBuffer(&txn, dcid, "/ram/dump.tbl");
    printf("tbl_dmpprep nobuf=%ld\n", (long)st);
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    {
        CFE_TBL_LoadBuffSetFree(&CFE_TBL_Global.LoadBuffs[k]);
    }

    /* AND THE SNAPSHOT ON ITS OWN, with a source id that does not match anything. */
    dc               = &CFE_TBL_Global.DumpControlBlocks[0];
    dc->SourceBuffId = CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE +
                                                                        (CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS + 2 * CFE_PLATFORM_TBL_MAX_NUM_TABLES)));
    printf("tbl_dmpsnap badsrc=%ld\n", (long)CFE_TBL_ExecuteDumpSnapshot(dc));

    /* --- PHASE 3: WRITE, four outcomes -------------------------------------------------- */
    /* Set the block up as the background task expects to find it: used, PERFORMED, with a dump
     * buffer holding the snapshot. */
    memset(dc, 0, sizeof(*dc));
    CFE_TBL_DumpCtrlBlockSetUsed(dc, CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE));
    dc->State         = CFE_TBL_DUMP_PERFORMED;
    dc->EncodeStatus  = CFE_SUCCESS;
    dc->DumpBufferPtr = &CFE_TBL_Global.LoadBuffs[0];
    CFE_TBL_LoadBuffSetAllocatedBlock(dc->DumpBufferPtr, tbl_probe_mem2, sizeof(tbl_probe_mem2));
    dc->DumpBufferPtr->ContentSize = 32;
    strncpy(dc->DumpBufferPtr->DataSource, "/ram/dump.tbl", OS_MAX_PATH_LEN - 1);
    strncpy(dc->TableName, "DMP_APP.Tbl", sizeof(dc->TableName) - 1);

    /* THE FILE ALREADY EXISTS, which is the only thing the read-only open at the top of
     * WriteSnapshotToFile is for: it picks OVERWRITE_DUMP over WRITE_DUMP. */
    fs_len   = 0;
    fs_pos   = 0;
    fs_wr_left = -1;
    st       = CFE_TBL_WriteSnapshotToFile(dc);
    printf("tbl_dmpwrite overwrite=%ld bytes=%ld last=%s\n", (long)st, fs_len,
           CFE_TBL_Global.HkPacket.Payload.LastFileDumped);
    /* WHAT THE TABLE HEADER ACTUALLY CONTAINS, and the two fields deliberately NOT printed.
     *
     * The table header starts at byte 64, after CFE_FS_Header_t, and is
     * Reserved/Offset/NumBytes/TableName -- big-endian, because
     * CFE_TBL_EncodeHeadersToFile byte-swaps it on a little-endian host to keep the cFE file
     * standard. So NumBytes is at 72 and reads 00000020 for this 32-byte table.
     *
     * Reserved (64..67) AND Offset (68..71) ARE NOT ASSERTED, BECAUSE THEY ARE GARBAGE.
     * NASA's `memset(&FileHeader, 0, sizeof(CFE_TBL_File_Hdr_t))` clears 52 bytes from the
     * FRONT of a CombinedFileHdr_t, which is entirely inside Std -- none of it reaches Tbl --
     * and nothing assigns those two fields afterwards. They go into the file as whatever was
     * on the stack. A probe printed them and the two halves disagreed on the first run:
     *
     *     C   tbl_dmphdr resv=00000001 off=8d30a184
     *     HC  tbl_dmphdr resv=00000000 off=00000000
     *
     * That is upstream behaviour, not a translation defect, and it matters for what comes
     * next: CFE_TBL_ReadHeaders reads Offset and CFE_TBL_LoadFromFile decides where the data
     * lands from it. So a load.c exercise must build its header EXPLICITLY rather than
     * round-tripping one through a dump, or it will diff for a reason two sources away. */
    printf("tbl_dmphdr numbytes=%02x%02x%02x%02x name=%s\n", fs_data[72], fs_data[73],
           fs_data[74], fs_data[75], (const char *)&fs_data[76]);
    /* THE FILE DOES NOT EXIST YET -- and this branch was unreachable until the stub learned to
     * say so; see the note on fs_noexist at OS_OpenCreate. */
    fs_noexist = 1;
    fs_len     = 0;
    fs_pos     = 0;
    st         = CFE_TBL_WriteSnapshotToFile(dc);
    printf("tbl_dmpwrite first=%ld bytes=%ld\n", (long)st, fs_len);
    fs_noexist = 0;
    /* THE CREATE FAILS */
    fs_open_fail = 1;
    st           = CFE_TBL_WriteSnapshotToFile(dc);
    printf("tbl_dmpwrite nocreate=%ld\n", (long)st);
    fs_open_fail = 0;
    /* THE THREE WRITES ARE 64 + 52 + 32 BYTES, and each budget below stops one of them. The
     * numbers are not guessed: a full successful dump reports bytes=148 above, and the image is
     * 32, so the two headers are 116 and CFE_FS_Header_t is 64.
     *
     * A FIRST DRAFT USED 150 FOR THE IMAGE CASE and the write SUCCEEDED -- the line read
     * `shortimg=0 bytes=148`, byte-identical to the overwrite line above it, which is the
     * two-assertions-agreeing tell. The middle case, a cFE header that goes out and a TABLE
     * header that does not, was not in that draft at all, so CFE_TBL_WRITE_TBL_HDR_ERR_EID had
     * no way to appear. */
    fs_wr_left = 130; /* both headers out (116), image truncated to 14 */
    fs_len     = 0;
    fs_pos     = 0;
    st         = CFE_TBL_WriteSnapshotToFile(dc);
    printf("tbl_dmpwrite shortimg=%ld bytes=%ld\n", (long)st, fs_len);
    fs_wr_left = 80; /* cFE header out (64), table header truncated to 16 */
    fs_len     = 0;
    fs_pos     = 0;
    st         = CFE_TBL_WriteSnapshotToFile(dc);
    printf("tbl_dmpwrite shorttblhdr=%ld bytes=%ld\n", (long)st, fs_len);
    fs_wr_left = 10; /* not even the cFE header */
    fs_len     = 0;
    fs_pos     = 0;
    st         = CFE_TBL_WriteSnapshotToFile(dc);
    printf("tbl_dmpwrite shorthdr=%ld bytes=%ld\n", (long)st, fs_len);
    fs_wr_left = -1;

    /* --- AND THE BACKGROUND SWEEP, which is phase 3's only real caller ------------------ */
    /* Two blocks: one with a good snapshot, which gets written, and one whose encode FAILED,
     * which gets an event instead. Both must be freed either way -- that is the whole reason
     * NASA's comment says to "just accept the error and move on to eventually free the dump
     * ctrl buffer". */
    memset(&CFE_TBL_Global.DumpControlBlocks, 0, sizeof(CFE_TBL_Global.DumpControlBlocks));
    for (k = 0; k < 2; k++)
    {
        dc = &CFE_TBL_Global.DumpControlBlocks[k];
        CFE_TBL_DumpCtrlBlockSetUsed(dc,
                                     CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + k));
        dc->State         = CFE_TBL_DUMP_PERFORMED;
        dc->EncodeStatus  = (k == 0) ? CFE_SUCCESS : CFE_TBL_ERR_ACCESS;
        dc->DumpBufferPtr = &CFE_TBL_Global.LoadBuffs[k];
        CFE_TBL_LoadBuffSetUsed(dc->DumpBufferPtr,
                                CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + k),
                                CFE_TBL_RegRecGetID(rr));
        CFE_TBL_LoadBuffSetAllocatedBlock(dc->DumpBufferPtr, tbl_probe_mem2,
                                          sizeof(tbl_probe_mem2));
        dc->DumpBufferPtr->ContentSize = 32;
        strncpy(dc->DumpBufferPtr->DataSource, "/ram/bg.tbl", OS_MAX_PATH_LEN - 1);
        strncpy(dc->TableName, "DMP_APP.Tbl", sizeof(dc->TableName) - 1);
    }
    /* a third block is PENDING, not PERFORMED, and must be left completely alone */
    dc = &CFE_TBL_Global.DumpControlBlocks[2];
    CFE_TBL_DumpCtrlBlockSetUsed(dc, CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + 2));
    dc->State = CFE_TBL_DUMP_PENDING;
    fs_len    = 0;
    fs_pos    = 0;
    CFE_TBL_TableDumpExecuteBackground();
    printf("tbl_dmpbg free0=%d free1=%d pendingkept=%d buf0free=%d buf1free=%d bytes=%ld\n",
           (int)!CFE_TBL_DumpCtrlBlockIsUsed(&CFE_TBL_Global.DumpControlBlocks[0]),
           (int)!CFE_TBL_DumpCtrlBlockIsUsed(&CFE_TBL_Global.DumpControlBlocks[1]),
           (int)CFE_TBL_DumpCtrlBlockIsUsed(&CFE_TBL_Global.DumpControlBlocks[2]),
           (int)!CFE_TBL_LoadBuffIsUsed(&CFE_TBL_Global.LoadBuffs[0]),
           (int)!CFE_TBL_LoadBuffIsUsed(&CFE_TBL_Global.LoadBuffs[1]), fs_len);
}

/* --- cfe_tbl_task_cmds.c and cfe_tbl_dispatch.c ---------------------------------
 * THE GROUND COMMANDS, DRIVEN AS MESSAGES. Everything above this point called tbl's functions
 * directly; these go in through CFE_TBL_TaskPipe the way an uplinked packet does, so the
 * dispatcher's table, its length check and its three-way error are all under test at once.
 *
 * THE LENGTH SWEEP IS THE STRONGEST ASSERTION ABOUT THE TABLE. Sending every command code at a
 * size no command has makes each row report its own ExpectedLength in the event text -- so one
 * loop pins all ten rows' sizeof, and a handler wired to the wrong payload type shows up as a
 * different number rather than as silence.
 *
 * AND EVERY HANDLER RETURNS CFE_SUCCESS, so the only observable is the COUNTERS and the events.
 * CFE_TBL_TranslateCmdProcRet is the convention: a failed command is an incremented error
 * counter, not a failed return. */
static void TblCmdExercise(void)
{
    union
    {
        CFE_SB_Buffer_t          Buf;
        CFE_TBL_NoopCmd_t        Noop;
        CFE_TBL_LoadCmd_t        Load;
        CFE_TBL_DumpCmd_t        Dump;
        CFE_TBL_ValidateCmd_t    Validate;
        CFE_TBL_ActivateCmd_t    Activate;
        CFE_TBL_DumpRegistryCmd_t DumpReg;
        CFE_TBL_SendRegistryCmd_t SendReg;
        CFE_TBL_DeleteCDSCmd_t   DelCDS;
        CFE_TBL_AbortLoadCmd_t   Abort;
    } cmd;
    CFE_TBL_RegistryRec_t *rr;
    CFE_TBL_Handle_t       h1;
    void                  *buf;
    size_t                 bufsz;
    bool                   eof;
    int32                  st;
    int                    k;
    int                    regidx;

    /* The real startup sequence again, then one registered table to command at. */
    es_set_ctx(1);
    CFE_TBL_EarlyInit();
    CFE_TBL_InitData();
    CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_C(ES_CTX_APPID(1));
    tbl_val_rc                    = CFE_SUCCESS;
    CFE_TBL_Register(&h1, "Cmd", 32, CFE_TBL_OPT_DEFAULT, tbl_val_stub);
    rr = CFE_TBL_LocateRegRecByName("CFE_EVS.Cmd");
    /* The INDEX the long way round -- HolyC scales pointer arithmetic by the pointee, so both
     * halves divide an explicit byte difference. Printed because three assertions below depend
     * on it and it is NOT zero: CFE_TBL_InitData seeds LastRegId to the BASE. */
    regidx = (int)(((char *)rr - (char *)CFE_TBL_Global.Registry) /
                   (long)sizeof(CFE_TBL_RegistryRec_t));
    printf("tbl_cmdsetup reg=%ld rr=%d idx=%d\n", (long)h1, (int)(rr != NULL), regidx);

    /* --- THE THREE-WAY ERROR ------------------------------------------------------------ */
    memset(&cmd, 0, sizeof(cmd));
    CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_NoopCmd_t));
    /* UNKNOWN MESSAGE ID: the event fires and the error counter does NOT move, which is the
     * asymmetry worth pinning -- a message that was never ours should not count against us. */
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(0x1FFF));
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_pipe badmid cc=%u ec=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter);
    /* BAD COMMAND CODE on the right id: this one DOES count. */
    CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, 99);
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_pipe badcc cc=%u ec=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter);

    /* --- THE LENGTH SWEEP, which pins every row's ExpectedLength ------------------------ */
    /* A size no tbl command has. The smallest payload here is the 40-byte table name, so a
     * bare header plus one byte cannot collide -- and if it ever did, the command would RUN
     * instead of erroring and the count below would drop. */
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_NoopCmd_t) + 1);
    for (k = 0; k <= 9; k++)
    {
        CFE_MSG_SetFcnCode(&cmd.Buf.Msg, k);
        CFE_TBL_TaskPipe(&cmd.Buf);
    }
    /* BOTH COUNTERS STAY AT ZERO AND THAT IS CORRECT: the wrong-length arm raises its event
     * and deliberately does NOT count, because a handler that never ran cannot have counted
     * anything. So this line asserts almost nothing on its own -- THE ASSERTION IS THE TEN
     * `EVS 52` LINES ABOVE IT, each naming a different `Expected =`, which is what pins all
     * ten rows' sizeof. A handler wired to the wrong payload type changes a number there. */
    printf("tbl_pipe alllen cc=%u ec=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter);

    /* --- NOOP AND RESET, the two counter conventions ------------------------------------ */
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_NoopCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_NOOP_CC);
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd noop cc=%u ec=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter);
    /* RESET IS THE ONLY DONT_INC_CTR HANDLER: it zeroes the counters and must not then leave
     * one at 1. Both come back 0, which is the whole assertion. */
    CFE_TBL_Global.CommandCounter      = 7;
    CFE_TBL_Global.CommandErrorCounter = 3;
    CFE_TBL_Global.ValidationCounter   = 5;
    CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_ResetCountersCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_RESET_COUNTERS_CC);
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd reset cc=%u ec=%u val=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter, CFE_TBL_Global.ValidationCounter);

    /* --- THE HOUSEKEEPING REQUEST, which is a MSG_MSGTYPE row (no command code) --------- */
    /* It packs the HK payload, transmits it, and -- the part worth knowing -- is the only
     * caller of CFE_TBL_TableDumpExecuteBackground in flight code. */
    CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_SEND_HK_MID));
    CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_SendHkCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, 0);
    sb_tx_reset();
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd hk tx=%d tables=%u pending=%u freebufs=%u\n", sb_tx_since(),
           CFE_TBL_Global.HkPacket.Payload.NumTables,
           CFE_TBL_Global.HkPacket.Payload.NumLoadPending,
           CFE_TBL_Global.HkPacket.Payload.NumFreeSharedBufs);

    /* --- CFE_TBL_GetHkData's VALIDATION HARVEST ----------------------------------------- */
    /* A completed validation result is reported ONCE and then freed, so the counters move and
     * the block is released. A failing result bumps FailedValCounter instead. */
    CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0],
                                    CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
    CFE_TBL_Global.ValidationResults[0].State        = CFE_TBL_VALIDATION_PERFORMED;
    CFE_TBL_Global.ValidationResults[0].Result       = 0;
    CFE_TBL_Global.ValidationResults[0].CrcOfTable   = 0xABCD;
    CFE_TBL_Global.ValidationResults[0].BufferSelect = CFE_TBL_BufferSelect_ACTIVE;
    strncpy(CFE_TBL_Global.ValidationResults[0].TableName, "CFE_EVS.Cmd",
            sizeof(CFE_TBL_Global.ValidationResults[0].TableName) - 1);
    CFE_TBL_Global.SuccessValCounter = 0;
    CFE_TBL_Global.FailedValCounter  = 0;
    CFE_TBL_Global.ValidationCounter = 0;
    CFE_TBL_GetHkData();
    printf("tbl_hk valpass crc=%04x succ=%u fail=%u valcnt=%u active=%u name=%s freed=%d\n",
           (unsigned)CFE_TBL_Global.HkPacket.Payload.LastValCrc,
           CFE_TBL_Global.SuccessValCounter, CFE_TBL_Global.FailedValCounter,
           CFE_TBL_Global.ValidationCounter, CFE_TBL_Global.HkPacket.Payload.ActiveBuffer,
           CFE_TBL_Global.HkPacket.Payload.LastValTableName,
           (int)!CFE_TBL_ValidationResultIsUsed(&CFE_TBL_Global.ValidationResults[0]));
    /* and a FAILING one takes the other counter */
    CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0],
                                    CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
    CFE_TBL_Global.ValidationResults[0].State  = CFE_TBL_VALIDATION_PERFORMED;
    CFE_TBL_Global.ValidationResults[0].Result = -5;
    CFE_TBL_GetHkData();
    printf("tbl_hk valfail succ=%u fail=%u status=%ld\n", CFE_TBL_Global.SuccessValCounter,
           CFE_TBL_Global.FailedValCounter,
           (long)CFE_TBL_Global.HkPacket.Payload.LastValStatus);

    /* --- SEND REGISTRY: the command only sets a flag; HK does the packing ---------------- */
    memset(&cmd, 0, sizeof(cmd));
    CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID),
                 sizeof(CFE_TBL_SendRegistryCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_SEND_REGISTRY_CC);
    strncpy(cmd.SendReg.Payload.TableName, "CFE_EVS.Cmd",
            sizeof(cmd.SendReg.Payload.TableName) - 1);
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd sendreg cc=%u ec=%u armed=%d\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter,
           (int)CFE_TBL_REGID_IS_VALID(CFE_TBL_Global.HkTlmTblRegId));
    /* the NEXT housekeeping request packs it, sends it and CLEARS the id so it goes once */
    CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_SEND_HK_MID));
    CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_SendHkCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, 0);
    sb_tx_reset();
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd regtlm tx=%d cleared=%d size=%lu name=%s owner=%s\n", sb_tx_since(),
           (int)!CFE_TBL_REGID_IS_VALID(CFE_TBL_Global.HkTlmTblRegId),
           (unsigned long)CFE_TBL_Global.TblRegPacket.Payload.Size,
           CFE_TBL_Global.TblRegPacket.Payload.Name,
           CFE_TBL_Global.TblRegPacket.Payload.OwnerAppName);
    /* and a name that is not there is refused */
    memset(&cmd, 0, sizeof(cmd));
    CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID),
                 sizeof(CFE_TBL_SendRegistryCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_SEND_REGISTRY_CC);
    strncpy(cmd.SendReg.Payload.TableName, "NO.SUCH", sizeof(cmd.SendReg.Payload.TableName) - 1);
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd sendreg_missing ec=%u\n", CFE_TBL_Global.CommandErrorCounter);

    /* --- ABORT LOAD, and the DUMP-ONLY exclusion that is NOT defensive ------------------ */
    memset(&cmd, 0, sizeof(cmd));
    CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID),
                 sizeof(CFE_TBL_AbortLoadCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_ABORT_LOAD_CC);
    strncpy(cmd.Abort.Payload.TableName, "CFE_EVS.Cmd", sizeof(cmd.Abort.Payload.TableName) - 1);
    /* no load in progress: refused */
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_RegRecClearLoadInProgress(rr);
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd abort_noload cc=%u ec=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter);
    /* a load in progress on a DUMP-ONLY table is also refused -- NextBufferId holds the DUMP
     * buffer there, so aborting would abort a dump */
    /* A REAL BUFFER ID, resolved from the record's own index. The first draft passed
     * CFE_TBL_LoadBufferGetID(&rr->Buffers[0]) straight back, and after EarlyInit that buffer
     * has no id -- so IsLoadInProgress stayed FALSE, the dump-only arm was never entered, and
     * `abort_dumponly` reported the "No load started" refusal while `lip=0` quietly agreed
     * with it. Registry[k]'s own pair is serial 4 + 2k. */
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 4 + 2 * regidx),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
    rr->Config.DumpOnly = true;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd abort_dumponly cc=%u ec=%u lip=%d\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter, (int)CFE_TBL_RegRecIsLoadInProgress(rr));
    /* and a real load IS aborted */
    rr->Config.DumpOnly = false;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd abort_ok cc=%u lip=%d\n", CFE_TBL_Global.CommandCounter,
           (int)CFE_TBL_RegRecIsLoadInProgress(rr));
    /* a name that is not there */
    strncpy(cmd.Abort.Payload.TableName, "NO.SUCH", sizeof(cmd.Abort.Payload.TableName) - 1);
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd abort_missing ec=%u\n", CFE_TBL_Global.CommandErrorCounter);

    /* --- DELETE CDS: five arms, and the first is the interlock -------------------------- */
    memset(&cmd, 0, sizeof(cmd));
    CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID),
                 sizeof(CFE_TBL_DeleteCDSCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_DELETE_CDS_CC);
    /* STILL REGISTERED: refused, because a registered table means its owner is still running
     * and the CDS is the only copy of a critical table's contents. */
    strncpy(cmd.DelCDS.Payload.TableName, "CFE_EVS.Cmd",
            sizeof(cmd.DelCDS.Payload.TableName) - 1);
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd delcds_registered ec=%u\n", CFE_TBL_Global.CommandErrorCounter);
    /* NOT IN THE CRITICAL REGISTRY either: a different refusal */
    strncpy(cmd.DelCDS.Payload.TableName, "GONE.Tbl", sizeof(cmd.DelCDS.Payload.TableName) - 1);
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd delcds_notcrit ec=%u\n", CFE_TBL_Global.CommandErrorCounter);
    /* IN the critical registry but with no CDS of that name */
    strncpy(CFE_TBL_Global.CritReg[3].Name, "GONE.Tbl",
            sizeof(CFE_TBL_Global.CritReg[3].Name) - 1);
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd delcds_nocds ec=%u\n", CFE_TBL_Global.CommandErrorCounter);

    /* --- THE REGISTRY DUMP: a background job, and its getter ---------------------------- */
    /* The COMMAND only queues a request. */
    memset(&cmd, 0, sizeof(cmd));
    CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID),
                 sizeof(CFE_TBL_DumpRegistryCmd_t));
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_DUMP_REGISTRY_CC);
    strncpy(cmd.DumpReg.Payload.DumpFilename, "/ram/reg.log",
            sizeof(cmd.DumpReg.Payload.DumpFilename) - 1);
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd dumpreg cc=%u ec=%u pending=%d existed=%d file=%s\n",
           CFE_TBL_Global.CommandCounter, CFE_TBL_Global.CommandErrorCounter,
           (int)CFE_FS_BackgroundFileDumpIsPending(&CFE_TBL_Global.RegDumpState.FileWrite),
           (int)CFE_TBL_Global.RegDumpState.FileExisted,
           CFE_TBL_Global.RegDumpState.FileWrite.FileName);
    /* A SECOND REQUEST WHILE ONE IS PENDING IS SILENTLY DROPPED -- no event, and the error
     * counter still moves because CmdProcRet was never changed from its pessimistic default. */
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    CFE_TBL_TaskPipe(&cmd.Buf);
    printf("tbl_cmd dumpreg_again cc=%u ec=%u\n", CFE_TBL_Global.CommandCounter,
           CFE_TBL_Global.CommandErrorCounter);
    /* THE GETTER, called the way the background writer calls it. Record 0 is the registered
     * table; a record past the end returns no data; and the LAST index is what ends the job --
     * which is the return value's only meaning, not "did I write anything". */
    /* ON THE RECORD THAT EXISTS, resolved rather than assumed. The first draft asked for
     * record 0 and got an EMPTY slot -- CFE_TBL_InitData seeds LastRegId to the BASE, so the
     * allocator does not start at index 0 -- which printed `sz=0 name=` and then made the
     * unowned case below read a name left over from a different record. */
    buf   = NULL;
    bufsz = 0;
    eof   = CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, regidx, &buf, &bufsz);
    printf("tbl_reggetter used eof=%d sz=%lu name=%s owner=%s users=%u\n", (int)eof,
           (unsigned long)bufsz, CFE_TBL_Global.RegDumpState.DumpRecord.Name,
           CFE_TBL_Global.RegDumpState.DumpRecord.OwnerAppName,
           CFE_TBL_Global.RegDumpState.DumpRecord.NumUsers);
    /* AN EMPTY SLOT writes nothing and does NOT end the job -- the return value means "last
     * record", never "wrote something", which is how a sparse registry dumps without holes. */
    buf   = NULL;
    bufsz = 1;
    eof   = CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, regidx + 1, &buf, &bufsz);
    printf("tbl_reggetter empty eof=%d sz=%lu null=%d\n", (int)eof, (unsigned long)bufsz,
           (int)(buf == NULL));
    eof = CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState,
                                     CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1, &buf, &bufsz);
    printf("tbl_reggetter last eof=%d\n", (int)eof);
    /* AN UNOWNED entry reports "--UNOWNED--" rather than asking ES for a name it has not got */
    rr->OwnerAppId = CFE_TBL_NOT_OWNED;
    CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, regidx, &buf, &bufsz);
    printf("tbl_reggetter unowned owner=%s\n",
           CFE_TBL_Global.RegDumpState.DumpRecord.OwnerAppName);
    /* THE EVENT HANDLER's four cases plus the default it ignores. It runs in the ES background
     * task, which is why it uses SendEventWithAppID -- in that context the "current app" is ES
     * and the event would otherwise be misattributed. */
    strncpy(CFE_TBL_Global.RegDumpState.FileWrite.FileName, "/ram/reg.log",
            sizeof(CFE_TBL_Global.RegDumpState.FileWrite.FileName) - 1);
    CFE_TBL_Global.RegDumpState.FileExisted = false;
    CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_COMPLETE,
                                     CFE_SUCCESS, 7, 0, 128);
    CFE_TBL_Global.RegDumpState.FileExisted = true;
    CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_COMPLETE,
                                     CFE_SUCCESS, 7, 0, 128);
    CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState,
                                     CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR, -1, 3, 0, 0);
    CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState,
                                     CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR, -2, 0, 0, 0);
    CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState,
                                     CFE_FS_FileWriteEvent_CREATE_ERROR, -3, 0, 0, 0);
    /* the default arm: an event the switch does not name produces NOTHING, which is the
     * absence the next line asserts by being the only output */
    CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_MAX, 0,
                                     0, 0, 0);
    printf("tbl_regevents done\n");

    es_ctx_init();
}

/* --- cfe_tbl_task.c -------------------------------------------------------------
 * THREE FUNCTIONS, AND THE OBJECT TABLE IS FINALLY HONEST. cfe_tbl_objtab.c names
 * CFE_TBL_EarlyInit, CFE_TBL_TaskMain and CFE_TBL_CleanUpApp; two of the three now run in this
 * transcript and the third has a real body. The objtab exercise's claim -- three distinct
 * non-NULL addresses -- was true of three stubs too.
 *
 * POISON-FIRST WORKS HERE, unlike CFE_TBL_EarlyInit. CFE_TBL_InitData does NOT zero the
 * global; it writes eight specific places in it. So filling those places with a recognisable
 * value first turns every assertion below from "it is zero" (which a memset would also give)
 * into "it CHANGED to the right thing". */
static void TblTaskExercise(void)
{
    CFE_SB_MsgId_t mid_hk, mid_reg, mid_notify;
    long           x0;

    /* --- CFE_TBL_InitData, with the five id spaces poisoned first ------------------------ */
    CFE_TBL_Global.LastLoadBuffId         = CFE_ResourceId_FromInteger(0xBAD01);
    CFE_TBL_Global.LastValidationResultId = CFE_ResourceId_FromInteger(0xBAD02);
    CFE_TBL_Global.LastDumpCtrlBlockId    = CFE_ResourceId_FromInteger(0xBAD03);
    CFE_TBL_Global.LastRegId              = CFE_ResourceId_FromInteger(0xBAD04);
    CFE_TBL_Global.LastHandle             = CFE_ResourceId_FromInteger(0xBAD05);
    CFE_TBL_Global.TableTaskAppId         = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0xBAD06));
    memset(&CFE_TBL_Global.HkPacket, 0x5A, sizeof(CFE_TBL_Global.HkPacket));
    memset(&CFE_TBL_Global.TblRegPacket, 0x5A, sizeof(CFE_TBL_Global.TblRegPacket));
    memset(&CFE_TBL_Global.NotifyMsg, 0x5A, sizeof(CFE_TBL_Global.NotifyMsg));
    CFE_TBL_InitData();
    printf("tbl_initdata lb=%d vr=%d dc=%d reg=%d hnd=%d app=%lu\n",
           (int)(CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastLoadBuffId) ==
                 CFE_TBL_LOADBUFFID_BASE),
           (int)(CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastValidationResultId) ==
                 CFE_TBL_VALRESULTID_BASE),
           (int)(CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastDumpCtrlBlockId) ==
                 CFE_TBL_DUMPCTRLID_BASE),
           (int)(CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastRegId) == CFE_TBL_REGID_BASE),
           (int)(CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastHandle) == CFE_TBL_HANDLE_BASE),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.TableTaskAppId));
    /* THE THIRD HEADER IS INITIALISED TO AN INVALID MSG ID ON PURPOSE -- NASA's comment says
     * "Message ID is set when sent, so OK as 0 here". So `notify=0` is the right answer and is
     * not a failure to initialise: the 0x5A poison above is what makes that readable. */
    CFE_MSG_GetMsgId(CFE_MSG_PTR(CFE_TBL_Global.HkPacket.TelemetryHeader), &mid_hk);
    CFE_MSG_GetMsgId(CFE_MSG_PTR(CFE_TBL_Global.TblRegPacket.TelemetryHeader), &mid_reg);
    CFE_MSG_GetMsgId(CFE_MSG_PTR(CFE_TBL_Global.NotifyMsg.CommandHeader), &mid_notify);
    printf("tbl_initdata hk=0x%04lx reg=0x%04lx notify=0x%04lx\n",
           (unsigned long)CFE_SB_MsgIdToValue(mid_hk),
           (unsigned long)CFE_SB_MsgIdToValue(mid_reg),
           (unsigned long)CFE_SB_MsgIdToValue(mid_notify));

    /* --- CFE_TBL_TaskInit AND CFE_TBL_TaskMain, both paths ------------------------------ */
    /* TaskInit IS NOT CALLED DIRECTLY, and that is a deliberate retreat. SB and EVS are both
     * 100% gated, so CFE_EVS_Register, CFE_SB_CreatePipe and the two CFE_SB_Subscribe calls
     * are real code -- a pipe really is created and two real subscriptions are made. But the
     * pipe NAME is a process-wide resource, so a direct call leaves TBL_CMD_PIPE taken and
     * every later TaskMain fails at CreatePipe.
     *
     * THE OBVIOUS FIX DOES NOT WORK AND THE REASON IS WORTH RECORDING. Calling
     * CFE_SB_DeletePipe on the pipe TaskInit made SEGFAULTS the C reference, in
     * CFE_SB_GetDestPtr reading address 0x809 -- which is a MsgId being walked as a pointer.
     * The same CFE_SB_DeletePipe works earlier in this transcript (see api_del), so something
     * about the route state TaskInit's two subscriptions leave behind is different. Not chased
     * here, and NOT diagnosed: recorded as an observation so the next person does not spend
     * the afternoon this cost. It also means the first draft's claim -- that the crash came
     * from the POWER ON RESET below -- was wrong; moving the reset last did not help, and the
     * lldb backtrace is what settled it.
     *
     * So TaskMain creates the pipe itself, both times, and the two runs take the two paths. */
    CFE_ES_Global.SystemState      = CFE_ES_SystemState_CORE_READY;
    CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;

    /* FIRST RUN: TBL_CMD_PIPE is free, so TaskMain's TaskInit runs all five steps -- the
     * "cFE TBL Initialized" event above this line is the fifth. Then the loop exits when
     * CFE_SB_ReceiveBuffer fails, because OS_QueueGet returns OS_QUEUE_EMPTY on an empty
     * pipe: one pass, `Error reading cmd pipe`, one CFE_ES_ExitApp(CORE_APP_RUNTIME_ERROR).
     * taskpipe=0 because there was no message to dispatch. */
    /* `cmds=` REPLACED `taskpipe=`, and it is weaker. The old field counted calls inside this
     * driver's own CFE_TBL_TaskPipe; the real dispatcher is gated now, so what can be observed
     * is its EFFECT -- the two command counters it moves. Neither run dispatches anything, so
     * both read 0, which is the same thing the old field said and no more. Kept because it is
     * the real state rather than a stub's, and because the SYSLOG lines are what actually
     * separate the two paths; see the note below. */
    CFE_TBL_Global.CmdPipe             = CFE_SB_INVALID_PIPE;
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    x0                                 = es_taskexits;
    CFE_TBL_TaskMain();
    printf("tbl_taskmain_loop exits=%ld cmds=%u pipe=%d req=%u\n", es_taskexits - x0,
           (unsigned)(CFE_TBL_Global.CommandCounter + CFE_TBL_Global.CommandErrorCounter),
           (int)CFE_RESOURCEID_TEST_DEFINED(CFE_TBL_Global.CmdPipe),
           CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);

    /* SECOND RUN: the name is taken now, so TaskInit fails at CreatePipe, TaskMain takes the
     * `Application Init Failed` branch and calls CFE_ES_ExitApp(CORE_APP_INIT_ERROR) -- which
     * drives the real CFE_ES_ResetCFE and a POWER ON RESET, `psp_restart 2` in the transcript.
     * It goes LAST in the block for that reason.
     *
     * TWO ExitApp CALLS COME OUT OF ONE TaskMain here, and that is NASA's code behaving
     * exactly as written. CFE_ES_ExitApp "will not return" in flight; in this driver it does,
     * so control falls past the `if`, the loop is never entered because Status is already an
     * error, and the bottom CFE_ES_ExitApp(CORE_APP_RUNTIME_ERROR) runs too. The driver IS the
     * "except under unit test" case NASA's own comment names.
     *
     * AND THE TWO PRINTF LINES ARE IDENTICAL, which is worth stating rather than leaving for
     * someone to notice. `exits=1 taskpipe=0 req=9` both times: es_taskexits counts
     * OS_TaskExit, and the extra ExitApp in this run does a PROCESSOR RESET instead of
     * reaching OS_TaskExit, so the count does not move. (A third draft claimed `exits=2`
     * here; the transcript says otherwise.) What separates the two paths is the SYSLOG, which
     * is compared just as strictly: `Error reading cmd pipe` and one ExitApp line above
     * against `Application Init Failed`, a POWER ON RESET and three ExitApp lines here. The
     * printf fields are the weaker half of this assertion and are kept only because they say
     * both runs TERMINATED and neither dispatched a message. */
    CFE_TBL_Global.CommandCounter      = 0;
    CFE_TBL_Global.CommandErrorCounter = 0;
    x0                                 = es_taskexits;
    CFE_TBL_TaskMain();
    printf("tbl_taskmain_initfail exits=%ld cmds=%u req=%u\n", es_taskexits - x0,
           (unsigned)(CFE_TBL_Global.CommandCounter + CFE_TBL_Global.CommandErrorCounter),
           CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);

    CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
    CFE_ES_Global.SystemState      = CFE_ES_SystemState_UNDEFINED;
}

/* --- cfe_tbl_internal.c: CFE_TBL_EarlyInit -------------------------------------
 * THE OBJECT TABLE'S FIRST HOOK, and until this block it was only an ADDRESS. cfe_tbl_objtab.c
 * has held &CFE_TBL_EarlyInit since it was gated, and all the objtab exercise asserts is that
 * the three function pointers are distinct and non-NULL -- which passed just as well when
 * EarlyInit was a two-line stub. check_in_blob says it has an address; nothing said it runs.
 *
 * IT IS CHEAP NOW BECAUSE ES IS 100% GATED. CFE_ES_PoolCreate, CFE_ES_RegisterCDSEx,
 * CFE_ES_RestoreFromCDS and CFE_ES_CopyToCDS are all real code in this driver, so the 512 KiB
 * partition really is carved up and the critical-table registry really does go into the CDS.
 * The only thing standing in is OS_MutSemCreate, which the driver counts -- and counting is
 * exactly the right stand-in for it, because what EarlyInit does with a mutex is create it and
 * store the id.
 *
 * THREE RUNS, because the CDS has three outcomes and all three are survivable. NASA's words:
 * "failure to support critical tables is not a good enough reason to exit the cFE on start
 * up". Every CDS branch ends with Status = CFE_SUCCESS, so the RETURN VALUE cannot tell them
 * apart -- the syslog lines and the CDS handle are what distinguish them, and that is why the
 * transcript is the right instrument for this function. */
static CFE_ES_MemHandle_t tbl_early_pool1;
static CFE_ES_MemHandle_t tbl_early_pool2;

static void TblEarlyInitExercise(void)
{
    int32 st;
    int   c0;
    int   k, allocated, distinct;

    /* WHAT THIS BLOCK CANNOT ASSERT, said first because the first draft asserted it anyway.
     * CFE_RESOURCEID_UNDEFINED is 0 in this configuration and the SIMPLE resourceid mode makes
     * every wrapper the identity -- so `HkTlmTblRegId is undefined`, `all 128 registry records
     * are free`, `all 32 critical slots hold the BAD handle` and `the deepest access list is
     * detached` ALL READ THE SAME whether EarlyInit ran or not, because its own memset
     * produces them. The usual fix -- poison the memory first, as cfe_tbl_regrec.c's own
     * comment describes -- is unavailable here precisely because EarlyInit begins by zeroing
     * the whole 592 KiB global itself. Six fields were cut from this exercise for that reason.
     *
     * So what is left is everything NON-zero that EarlyInit produces: two mutex ids, a pool
     * handle, four shared load buffers of the right size at four DIFFERENT addresses, a CDS
     * handle -- and the one thing that genuinely distinguishes the recovery branch, below. */

    /* FIRST RUN: nothing in the CDS under this name yet, so RegisterCDSEx succeeds and the
     * else-branch saves the initial registry with CopyToCDS. */
    c0        = fs_mut_create;
    st        = CFE_TBL_EarlyInit();
    allocated = 0;
    distinct  = 1;
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    {
        if (CFE_TBL_LoadBuffIsAllocated(&CFE_TBL_Global.LoadBuffs[k]) &&
            CFE_TBL_Global.LoadBuffs[k].AllocationSize == CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE)
        {
            ++allocated;
        }
        if (k > 0 && CFE_TBL_LoadBuffGetReadPointer(&CFE_TBL_Global.LoadBuffs[k]) ==
                         CFE_TBL_LoadBuffGetReadPointer(&CFE_TBL_Global.LoadBuffs[k - 1]))
        {
            distinct = 0;
        }
    }
    /* creates=3 is NOT a mistake: EarlyInit makes two, and CFE_ES_PoolCreate makes the pool's
     * own mutex. The third one is the witness that the pool was really created rather than its
     * handle merely being set. And reg/wrk differ, which is what the per-create id above is
     * for -- see the note on OS_MutSemCreate. */
    tbl_early_pool1 = CFE_TBL_Global.Buf.PoolHdl;
    printf("tbl_early rc=%ld creates=%d reg=%lu wrk=%lu pool=%d bufs=%d distinct=%d\n", (long)st,
           fs_mut_create - c0, (unsigned long)OS_ObjectIdToInteger(CFE_TBL_Global.RegistryMutex),
           (unsigned long)OS_ObjectIdToInteger(CFE_TBL_Global.WorkBufMutex),
           (int)CFE_RESOURCEID_TEST_DEFINED(CFE_TBL_Global.Buf.PoolHdl), allocated, distinct);

    /* THE RECOVERY BRANCH, WITNESSED. Both CDS paths return CFE_SUCCESS -- NASA's words,
     * "failure to support critical tables is not a good enough reason to exit the cFE on start
     * up" -- so the return value cannot tell them apart and the first draft printed two nearly
     * identical lines while claiming they took different paths.
     *
     * What distinguishes them is CONTENT. Write a recognisable handle into the critical
     * registry and push it to the CDS; the next EarlyInit finds the entry already there,
     * takes the CFE_ES_CDS_ALREADY_EXISTS arm, and RestoreFromCDS brings that handle back
     * AFTER the loop that set every slot to the BAD handle. So `crit5=0x5151` is proof the
     * restore happened, and `critbad=31` is proof it overwrote the loop's work rather than
     * being merged with it. */
    CFE_TBL_Global.CritReg[5].CDSHandle = CFE_ES_CDSHANDLE_C(CFE_ResourceId_FromInteger(0x5151));
    CFE_ES_CopyToCDS(CFE_TBL_Global.CritRegHandle, CFE_TBL_Global.CritReg);
    c0        = fs_mut_create;
    st        = CFE_TBL_EarlyInit();
    allocated = 0;
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES; k++)
    {
        if (CFE_RESOURCEID_TEST_EQUAL(CFE_TBL_Global.CritReg[k].CDSHandle, CFE_ES_CDS_BAD_HANDLE))
        {
            ++allocated;
        }
    }
    tbl_early_pool2 = CFE_TBL_Global.Buf.PoolHdl;
    printf("tbl_early recovered rc=%ld creates=%d crit5=0x%lx critbad=%d\n", (long)st,
           fs_mut_create - c0,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.CritReg[5].CDSHandle), allocated);

    /* THIRD RUN: the mutex refuses, which is the ONE failure EarlyInit does not survive -- it
     * returns before the pool is ever created. Both mutex calls are on that path, so a count
     * of ONE create is the witness that it stopped at the first, and pool=0 that it never got
     * as far as CFE_ES_PoolCreate. */
    fs_mut_create_rc = -1;
    c0               = fs_mut_create;
    st               = CFE_TBL_EarlyInit();
    printf("tbl_early nomutex rc=%ld creates=%d pool=%d\n", (long)st, fs_mut_create - c0,
           (int)CFE_RESOURCEID_TEST_DEFINED(CFE_TBL_Global.Buf.PoolHdl));
    fs_mut_create_rc = OS_SUCCESS;

    /* AND HAND THE POOL RECORDS BACK, which this block has to do because
     * CFE_PLATFORM_ES_MAX_MEMORY_POOLS IS **TEN** and the two successful EarlyInits above each
     * took one. Without this, the next exercise to call CFE_ES_PoolCreate gets nothing:
     * TblApiExercise did, and every one of its nineteen assertions came back
     * CFE_TBL_ERR_INVALID_HANDLE because SetupTableBuffers could not allocate -- one repeated
     * number for a whole block, with `CFE_ES_GetPoolBuf: Err:Bad handle(0x00000000)` the only
     * clue. A FIXED-SIZE RESOURCE TABLE SHARED BETWEEN EXERCISES has to be given back.
     *
     * The deletes come last so they cannot disturb the measurements above, and the status is
     * printed rather than discarded -- `del1`/`del2` being 0 is what says the records are
     * actually free again. */
    printf("tbl_early pooldel=%ld %ld\n", (long)CFE_ES_PoolDelete(tbl_early_pool1),
           (long)CFE_ES_PoolDelete(tbl_early_pool2));
}

/* --- cfe_tbl_registry.c ---------------------------------------------------------
 * SIX OF THE ELEVEN STEPS, the ones nothing else reaches. TxnLockRegistry, TxnUnlockRegistry,
 * TxnRemoveAccessLink and TxnFindRegByName are already driven -- by tbl_adtxn's take/give
 * counts, by tbl_adrel_owner/other, and by tbl_findreg through CFE_TBL_FindTableInRegistry.
 *
 * Each step is given its own setup rather than being chained, because a chain would make one
 * wrong answer cascade into five unreadable ones. */
static void TblRegistryExercise(void)
{
    CFE_TBL_TxnState_t          txn;
    CFE_TBL_TableConfig_t       cfg;
    CFE_TBL_RegistryRec_t      *rr;
    CFE_TBL_AccessDescriptor_t *ad;
    CFE_TBL_LoadBuff_t         *lb;
    void                       *tp;
    int32                       st;
    int                         k;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B40);

    /* THE FOUR VALIDATORS IN ORDER, and the order is load-bearing: options are decoded before
     * the size is checked, because the size limit depends on the double-buffered flag that
     * ValidateTableOptions writes into this same config object.
     *
     * Each call into a local first -- three of the four arms emit a syslog line. */
    memset(&txn, 0, sizeof(txn));
    strncpy(txn.AppNameBuffer, "REG_APP", CFE_MISSION_MAX_API_LEN - 1);
    memset(&cfg, 0, sizeof(cfg));
    st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "", 0, 64, NULL);
    printf("tbl_cfg badname=%ld\n", (long)st);
    memset(&cfg, 0, sizeof(cfg));
    st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "Tbl", 0x0003, 64, NULL);
    printf("tbl_cfg badopt=%ld\n", (long)st);
    memset(&cfg, 0, sizeof(cfg));
    st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "Tbl", 0x0000, 0, NULL);
    printf("tbl_cfg badsize=%ld\n", (long)st);
    memset(&cfg, 0, sizeof(cfg));
    st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "Tbl", 0x0001, 2048, tbl_val_stub);
    printf("tbl_cfg good=%ld name=%s size=%lu dbl=%d fn=%d\n", (long)st, cfg.Name,
           (unsigned long)cfg.Size, (int)cfg.DoubleBuffered, (int)(cfg.ValidationFuncPtr != NULL));

    /* FOUR PENDING STATES, AND ONLY ONE IS EVER REPORTED. The tests run validation, then
     * update, then dump -- so a table with a pending validation AND a pending dump answers
     * VALIDATION_PENDING and the caller hears about the dump next time round. The last line
     * sets BOTH to prove the priority rather than assuming it. */
    /* THE BUFFER IDS HAVE TO BE REAL, and the serials are not free to choose. Four shared
     * buffers come first, so Registry[k]'s own pair is serial 4 + 2k -- Registry[4] is 12 and
     * 13. A zeroed buffer has an UNDEFINED id, CFE_TBL_LoadBufferGetID hands that straight
     * back, and the first draft of this block set LoadInProgress to UNDEFINED: the update arm
     * was never entered and `tbl_status update` printed the DUMP value, identical to the line
     * above it. Two assertions reading the same number is the tell. */
    rr = &CFE_TBL_Global.Registry[4];
    memset(rr, 0, sizeof(*rr));
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 4));
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    printf("tbl_status clean=%ld\n", (long)CFE_TBL_TxnGetTableStatus(&txn));
    rr->DumpControlId = CFE_TBL_DUMPCTRLID_C(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + 1));
    printf("tbl_status dump=%ld\n", (long)CFE_TBL_TxnGetTableStatus(&txn));
    /* AND IT HAS TO BE Buffers[0], SERIAL 12, FOR A SINGLE-BUFFERED TABLE. The first fix put
     * serial 13 into Buffers[1] -- the right serial for that slot -- and the arm STILL was not
     * entered, because CFE_TBL_LocateLoadBufferByID forces `Idx = 0` when the parent table is
     * not double-buffered. So serial 13 resolves to Buffers[0], whose id is undefined, IsMatch
     * fails, and nothing is pending. A buffer id must agree with the table's SHAPE, not just
     * with the slot it was written into. */
    lb = &rr->Buffers[0];
    CFE_TBL_LoadBuffSetUsed(lb, CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 12),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(lb));
    lb->IsValid     = true;
    lb->ActivateReq = true;
    printf("tbl_status update=%ld\n", (long)CFE_TBL_TxnGetTableStatus(&txn));
    rr->PendingValId = CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 1));
    printf("tbl_status valfirst=%ld\n", (long)CFE_TBL_TxnGetTableStatus(&txn));

    /* ALLOCATION, and the lock count is the thing worth watching: Allocate takes the registry
     * itself, so lockcnt must be back to zero on return and the mutex take/give must have
     * been counted once each. */
    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B40);
    /* LastRegId HAS TO NAME A REAL ID FIRST. CFE_TBL_GetNextRegId searches forward from it,
     * and a zeroed global means it searches forward from the undefined id and finds nothing --
     * so the FIRST allocation came back ERR_REGISTRY_FULL, the same value as the exhaustion
     * case below, and the pair asserted nothing. Seeding it with the LAST id wraps the search
     * to index 0. */
    CFE_TBL_Global.LastRegId = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE +
                                                          CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1);
    memset(&txn, 0, sizeof(txn));
    st = CFE_TBL_TxnAllocateRegistryEntry(&txn);
    printf("tbl_alloc rc=%ld id=%lu nonnull=%d used=%d lockcnt=%u\n", (long)st,
           (unsigned long)CFE_TBL_TxnRegIdAsULong(&txn), (int)(txn.RegRecPtr != NULL),
           (int)(txn.RegRecPtr != NULL && CFE_TBL_RegRecIsUsed(txn.RegRecPtr)),
           (unsigned)txn.RegLockCount);
    /* EXHAUSTION. Every slot marked used, so the next allocation must refuse AND must leave
     * the transaction's own fields cleared rather than half-filled. */
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_NUM_TABLES; k++)
    {
        CFE_TBL_RegRecSetUsed(&CFE_TBL_Global.Registry[k],
                              CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + k));
    }
    memset(&txn, 0, sizeof(txn));
    st = CFE_TBL_TxnAllocateRegistryEntry(&txn);
    printf("tbl_alloc full=%ld null=%d undef=%d\n", (long)st, (int)(txn.RegRecPtr == NULL),
           (int)!CFE_TBL_REGID_IS_VALID(txn.RegId));

    /* THE THREE WAYS A DUPLICATE REGISTRATION ENDS, plus the not-a-duplicate path that falls
     * through to allocation. Re-registering YOUR OWN table at the SAME size is a supported
     * no-op that returns a WARNING, which is the only path here that is not an error. */
    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B40);
    CFE_TBL_Global.LastRegId = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE +
                                                          CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1);
    CFE_TBL_Global.LastHandle = CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE +
                                                           CFE_PLATFORM_TBL_MAX_NUM_HANDLES - 1);
    rr = &CFE_TBL_Global.Registry[6];
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 6));
    strncpy(rr->Config.Name, "REG_APP.Dup", CFE_TBL_MAX_FULL_NAME_LEN - 1);
    rr->Config.Size = 512;
    rr->OwnerAppId  = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    memset(&txn, 0, sizeof(txn));
    txn.AppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    st        = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.Dup", 1024);
    printf("tbl_dup diffsize=%ld\n", (long)st);
    memset(&txn, 0, sizeof(txn));
    txn.AppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x2222));
    st        = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.Dup", 512);
    printf("tbl_dup notowned=%ld\n", (long)st);
    /* the accepted path needs an access descriptor this app already holds, because
     * CFE_TBL_FindAccessDescriptorForSelf is what turns "same table, same size" into a
     * warning rather than an error */
    ad = &CFE_TBL_Global.Handles[9];
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9));
    ad->AppId    = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    ad->RegIndex = CFE_TBL_RegRecGetID(rr);
    CFE_TBL_HandleListInsertLink(rr, ad);
    memset(&txn, 0, sizeof(txn));
    txn.AppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    st        = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.Dup", 512);
    printf("tbl_dup warn=%ld handle=%lu\n", (long)st,
           (unsigned long)CFE_TBL_TxnHandleAsULong(&txn));
    memset(&txn, 0, sizeof(txn));
    txn.AppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    st        = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.New", 512);
    printf("tbl_dup fresh=%ld allocated=%d\n", (long)st, (int)(txn.RegRecPtr != NULL));

    /* CONNECTING A DESCRIPTOR, and the three answers for Updated. A loaded load/dump table
     * says updated; a loaded DUMP-ONLY table does not (there is nothing for an accessor to be
     * notified about); and a record whose id no longer matches the transaction is not linked
     * at all -- that arm is not dead code, it is the re-allocated-under-us case. */
    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B40);
    rr = &CFE_TBL_Global.Registry[7];
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 7));
    CFE_TBL_HandleLinkInit(&rr->AccessList);
    /* "loaded" means ActiveBufferId IS DEFINED, so the buffer needs its id before it can be
     * made active -- Registry[7]'s pair is serial 4 + 2*7 = 18 and 19. Without this the table
     * reads never-loaded and `upd=0` below passes while testing the wrong branch. */
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 18),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    ad = &CFE_TBL_Global.Handles[11];
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 11));
    memset(&txn, 0, sizeof(txn));
    txn.AccDescPtr = ad;
    txn.RegRecPtr  = rr;
    txn.RegId      = CFE_TBL_RegRecGetID(rr);
    txn.AppId      = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x3333));
    CFE_TBL_TxnConnectAccessDescriptor(&txn);
    printf("tbl_connect upd=%d linked=%d app=%lu lockcnt=%u\n", (int)ad->Updated,
           (int)(CFE_TBL_LocateAccDescByHandle(rr->AccessList.Next) == ad),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(ad->AppId), (unsigned)txn.RegLockCount);
    rr->Config.DumpOnly = true;
    CFE_TBL_HandleLinkInit(&rr->AccessList);
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 11));
    CFE_TBL_TxnConnectAccessDescriptor(&txn);
    printf("tbl_connect dumponly upd=%d linked=%d\n", (int)ad->Updated,
           (int)(CFE_TBL_LocateAccDescByHandle(rr->AccessList.Next) == ad));
    rr->Config.DumpOnly = false;
    CFE_TBL_HandleLinkInit(&rr->AccessList);
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 11));
    txn.RegId = CFE_TBL_REGID_C(CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 99));
    CFE_TBL_TxnConnectAccessDescriptor(&txn);
    printf("tbl_connect mismatch upd=%d linked=%d\n", (int)ad->Updated,
           (int)(CFE_TBL_LocateAccDescByHandle(rr->AccessList.Next) == ad));

    /* AND THE POINTER ITSELF. Three answers, and the third is the one the whole lock scheme
     * exists for: handing the caller the ACTIVE buffer's address while recording in the
     * descriptor WHICH blob is being read, so nothing overwrites it until the address is
     * released. Into locals first -- the unowned arm emits a syslog line. */
    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B40);
    rr = &CFE_TBL_Global.Registry[8];
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 8));
    ad = &CFE_TBL_Global.Handles[12];
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 12));
    memset(&txn, 0, sizeof(txn));
    txn.AccDescPtr = ad;
    txn.RegRecPtr  = rr;
    txn.RegId      = CFE_TBL_RegRecGetID(rr);
    txn.Handle     = CFE_TBL_AccDescGetHandle(ad);
    tp             = (void *)1;
    st             = CFE_TBL_TxnGetTableAddress(&txn, &tp);
    printf("tbl_addr unowned=%ld null=%d\n", (long)st, (int)(tp == NULL));
    rr->OwnerAppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x4444));
    tp             = (void *)1;
    st             = CFE_TBL_TxnGetTableAddress(&txn, &tp);
    printf("tbl_addr neverloaded=%ld null=%d\n", (long)st, (int)(tp == NULL));
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 20),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_LoadBuffSetAllocatedBlock(&rr->Buffers[0], tbl_probe_mem, sizeof(tbl_probe_mem));
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    ad->Updated = true;
    tp          = NULL;
    st          = CFE_TBL_TxnGetTableAddress(&txn, &tp);
    printf("tbl_addr loaded=%ld isbuf0=%d locked=%d bufmatch=%d updcleared=%d\n", (long)st,
           (int)(tp == (void *)tbl_probe_mem), (int)ad->LockFlag,
           (int)CFE_RESOURCEID_TEST_EQUAL(ad->BufferIndex,
                                          CFE_TBL_LoadBufferGetID(&rr->Buffers[0])),
           (int)!ad->Updated);
}

/* --- cfe_tbl_internal.c ---------------------------------------------------------
 * FOUR UNRELATED CONCERNS, and this exercise takes them in the order they are cheapest to
 * observe: the three validators that decide whether a registration is legal at all, the name
 * marker, the doubly-linked access list, and the validation-request handoff.
 *
 * CFE_TBL_HandleListGetSafeLink, GetNext and GetPrev CANNOT BE CALLED FROM HERE. The last two
 * are `static inline` INSIDE cfe_tbl_internal.c and the first has no declaration in any
 * header -- so this driver reaches the safe-link trick only through InsertLink, RemoveLink
 * and ForeachAccessDescriptor, which is the real API anyway. Both ends of the list are still
 * covered, because removing the FRONT element and removing the LAST one are exactly the two
 * cases the head-node pointer exists to erase.
 *
 * (Note for the gates: those three are source-file static inlines, not header inlines, so
 * check_header_inlines does not look at them. check_coverage always did -- and
 * check_signatures did NOT, until this commit: its return-type pattern allowed two words
 * before the name, and `static inline CFE_TBL_AccessDescriptor_t *` is three, so GetNext and
 * GetPrev were never compared to NASA's. 30 of 32 was the number, and it printed as a pass. */

/* The chain printer. It follows Next from the head using the gated
 * CFE_TBL_LocateAccDescByHandle, which answers NULL for the undefined id and so terminates
 * the walk; the bound of 8 is there so a mistake in the list surgery prints a wrong answer
 * instead of hanging. The count beside it comes from NASA's own
 * ForeachAccessDescriptor/CountAccessDescHelper pair, so the two walks check each other. */
static void tbl_chain(CFE_TBL_RegistryRec_t *rr, const char *tag)
{
    CFE_TBL_AccessDescriptor_t *p;
    const CFE_TBL_HandleLink_t *lnk;
    uint32                      descs;
    int                         guard;

    printf("%s head=%lu chain=", tag, (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->AccessList.Next));
    lnk = &rr->AccessList;
    for (guard = 0; guard < 8; guard++)
    {
        p = CFE_TBL_LocateAccDescByHandle(lnk->Next);
        if (p == NULL)
        {
            break;
        }
        printf("%lu,", (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_AccDescGetHandle(p)));
        lnk = &p->Link;
    }
    descs = 0;
    CFE_TBL_ForeachAccessDescriptor(rr, CFE_TBL_CountAccessDescHelper, &descs);
    printf(" n=%u\n", (unsigned)descs);
}

static void TblInternalExercise(void)
{
    CFE_TBL_TableConfig_t        cfg;
    CFE_TBL_RegistryRec_t       *rr;
    CFE_TBL_AccessDescriptor_t  *adp[3];
    CFE_TBL_CritRegRec_t        *crp;
    CFE_TBL_ValidationResult_t  *vrp;
    CFE_TBL_ValidationResultId_t vid;
    CFE_TBL_RegId_t              found;
    uint16                       opts[9];
    char                         nbuf[20];
    char                         longname[CFE_MISSION_TBL_MAX_NAME_LENGTH + 4];
    int                          k;
    int32                        st;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B30);

    /* THE NINE OPTION WORDS THAT COVER EVERY BRANCH. Filled one at a time rather than with an
     * initialiser list because HolyC has no file-scope or local aggregate initialiser and the
     * two halves are kept reading the same. 0x6 is the interesting one: USR_DEF_ADDR INCLUDES
     * the dump-only bit, so asking for a user-defined address implies dump-only -- which means
     * the `else if (UserDefAddr)` arm can only be reached by 0x4, a caller who set the
     * user-defined mask bit WITHOUT the dump-only bit. That word is in the table for exactly
     * that reason.
     *
     *   0x0  single, load/dump, not user-def, not critical    accepted
     *   0x1  double-buffered                                   accepted
     *   0x2  dump-only                                         accepted
     *   0x3  dump-only AND double                              REFUSED
     *   0x4  user-def mask without dump-only                    REFUSED, and only reachable so
     *   0x6  USR_DEF_ADDR proper: user-def and dump-only        accepted
     *   0x8  critical                                          accepted
     *   0x9  critical and double                               accepted
     *   0xA  critical and dump-only                            REFUSED
     */
    opts[0] = 0x0000;
    opts[1] = 0x0001;
    opts[2] = 0x0002;
    opts[3] = 0x0003;
    opts[4] = 0x0004;
    opts[5] = 0x0006;
    opts[6] = 0x0008;
    opts[7] = 0x0009;
    opts[8] = 0x000A;
    for (k = 0; k < 9; k++)
    {
        memset(&cfg, 0, sizeof(cfg));
        st = CFE_TBL_ValidateTableOptions(&cfg, opts[k]);
        printf("tbl_opt %04x dbl=%d dmp=%d usr=%d crit=%d st=%ld\n", (unsigned)opts[k],
               (int)cfg.DoubleBuffered, (int)cfg.DumpOnly, (int)cfg.UserDefAddr,
               (int)cfg.Critical, (long)st);
    }

    /* SIZE, and the limit that depends on a flag the caller set in the SAME config object.
     * Both platform limits are 16384 in this configuration, so the single/double distinction
     * cannot be seen in the numbers -- what is still worth asserting is that Size is written
     * on success and left alone on failure. */
    memset(&cfg, 0, sizeof(cfg));
    printf("tbl_size zero=%ld sz=%lu\n", (long)CFE_TBL_ValidateTableSize(&cfg, 0),
           (unsigned long)cfg.Size);
    printf("tbl_size limit=%ld sz=%lu\n",
           (long)CFE_TBL_ValidateTableSize(&cfg, CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE),
           (unsigned long)cfg.Size);
    printf("tbl_size over=%ld sz=%lu\n",
           (long)CFE_TBL_ValidateTableSize(&cfg, CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE + 1),
           (unsigned long)cfg.Size);
    cfg.DoubleBuffered = true;
    printf("tbl_size dbllimit=%ld sz=%lu\n",
           (long)CFE_TBL_ValidateTableSize(&cfg, CFE_PLATFORM_TBL_MAX_DBL_TABLE_SIZE),
           (unsigned long)cfg.Size);

    /* THE NAME, which is both too-long and empty in one test: memchr over MAX_NAME_LENGTH
     * finding no NUL means the name does not terminate within the limit. A name of exactly 16
     * characters is already too long for that reason -- the NUL sits at index 16. */
    memset(&cfg, 0, sizeof(cfg));
    printf("tbl_name empty=%ld\n", (long)CFE_TBL_ValidateTableName(&cfg, "", "APP"));
    memset(longname, 'X', sizeof(longname));
    longname[CFE_MISSION_TBL_MAX_NAME_LENGTH] = '\0';
    printf("tbl_name exactly16=%ld\n", (long)CFE_TBL_ValidateTableName(&cfg, longname, "APP"));
    longname[CFE_MISSION_TBL_MAX_NAME_LENGTH - 1] = '\0';
    st = CFE_TBL_ValidateTableName(&cfg, longname, "APP");
    printf("tbl_name fifteen=%ld full=%s\n", (long)st, cfg.Name);
    st = CFE_TBL_ValidateTableName(&cfg, "Tbl", "APP");
    printf("tbl_name good=%ld full=%s\n", (long)st, cfg.Name);
    /* and the truncation arm: 15 + 1 + 15 + 1 fits 40, so the app name has to be long enough
     * to push the joined name past CFE_TBL_MAX_FULL_NAME_LEN by itself */
    st = CFE_TBL_ValidateTableName(&cfg, longname, "AN_APPLICATION_WITH_A_VERY_LONG_NAME");
    printf("tbl_name trunc=%ld full=%s\n", (long)st, cfg.Name);

    /* THE MODIFIED MARKER, both arms. The second name leaves no room for three more
     * characters, so the marker overwrites the tail rather than being dropped. */
    memset(nbuf, 0, sizeof(nbuf));
    strcpy(nbuf, "APP.Tbl");
    CFE_TBL_MarkNameAsModified(nbuf, sizeof(nbuf));
    printf("tbl_mark short=%s\n", nbuf);
    memset(nbuf, 'Y', sizeof(nbuf));
    nbuf[sizeof(nbuf) - 1] = '\0';
    CFE_TBL_MarkNameAsModified(nbuf, sizeof(nbuf));
    printf("tbl_mark maximal=%s len=%d\n", nbuf, (int)strlen(nbuf));

    /* THE ACCESS LIST. Three descriptors, each inserted at the front, so the chain comes out
     * reversed -- and then the three removals take the MIDDLE, the FRONT and the LAST
     * element, which is every case the head-node trick exists to flatten. */
    rr = &CFE_TBL_Global.Registry[3];
    CFE_TBL_HandleLinkInit(&rr->AccessList);
    for (k = 0; k < 3; k++)
    {
        adp[k] = &CFE_TBL_Global.Handles[10 + k];
        CFE_TBL_InitAccessDescriptor(adp[k]);
        CFE_TBL_AccDescSetUsed(adp[k], CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 10 + k));
    }
    tbl_chain(rr, "tbl_list empty");
    for (k = 0; k < 3; k++)
    {
        CFE_TBL_HandleListInsertLink(rr, adp[k]);
    }
    tbl_chain(rr, "tbl_list three");
    /* READ `attached=0 1 1` CAREFULLY -- it is not a mistake and not a bug to fix. The first
     * descriptor inserted is the LAST in the chain, so its Next is undefined, and
     * CFE_TBL_HandleLinkIsAttached tests Next ALONE. So the tail of a non-empty list reports
     * itself detached, which is narrower than what cfe_tbl_handlelink.h promises of it ("true
     * if the passed-in link is attached to another list node, indicating it is part of a
     * list"). The translation keeps NASA's one-line body; this transcript line is what pins
     * the behaviour so a later "tidy-up" of either half shows up as a diff. */
    printf("tbl_list attached=%d %d %d\n", (int)CFE_TBL_HandleLinkIsAttached(&adp[0]->Link),
           (int)CFE_TBL_HandleLinkIsAttached(&adp[1]->Link),
           (int)CFE_TBL_HandleLinkIsAttached(&adp[2]->Link));
    CFE_TBL_HandleListRemoveLink(rr, adp[1]);
    tbl_chain(rr, "tbl_list -middle");
    printf("tbl_list midattached=%d\n", (int)CFE_TBL_HandleLinkIsAttached(&adp[1]->Link));
    CFE_TBL_HandleListRemoveLink(rr, adp[2]);
    tbl_chain(rr, "tbl_list -front");
    CFE_TBL_HandleListRemoveLink(rr, adp[0]);
    tbl_chain(rr, "tbl_list -last");

    /* AND THE WALK THAT MARKS, which is the only reason the list exists: one table updated,
     * every app holding a handle to it told so. Two descriptors are back on the list and a
     * third is deliberately left OFF it, so the count is a claim about the list and not about
     * the handle array. */
    CFE_TBL_HandleListInsertLink(rr, adp[0]);
    CFE_TBL_HandleListInsertLink(rr, adp[1]);
    adp[0]->Updated = false;
    adp[1]->Updated = false;
    adp[2]->Updated = false;
    CFE_TBL_NotifyTblUsersOfUpdate(rr);
    printf("tbl_notify upd=%d %d off=%d\n", (int)adp[0]->Updated, (int)adp[1]->Updated,
           (int)adp[2]->Updated);

    /* THE VALIDATION-REQUEST HANDOFF, which is a flag and an id in one word. Three cases: an
     * undefined id is left ALONE (NASA's comment: "only write to the global if it was set to a
     * value"), a live id is consumed and returns its block, and a stale id -- one whose block
     * is no longer used -- is consumed and returns NULL. */
    vid = CFE_TBL_VALRESULTID_UNDEFINED;
    vrp = CFE_TBL_CheckValidationRequest(&vid);
    printf("tbl_valreq undef null=%d left=%d\n", (int)(vrp == NULL),
           (int)!CFE_TBL_VALRESULTID_IS_VALID(vid));
    CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[2],
                                    CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 2));
    vid = CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 2));
    vrp = CFE_TBL_CheckValidationRequest(&vid);
    printf("tbl_valreq live isblk2=%d cleared=%d\n",
           (int)(vrp == &CFE_TBL_Global.ValidationResults[2]),
           (int)!CFE_TBL_VALRESULTID_IS_VALID(vid));
    vid = CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 3));
    vrp = CFE_TBL_CheckValidationRequest(&vid);
    printf("tbl_valreq stale null=%d cleared=%d\n", (int)(vrp == NULL),
           (int)!CFE_TBL_VALRESULTID_IS_VALID(vid));

    /* THE CRITICAL-TABLE REGISTRY LOOKUP, and the second call is the one the code actually
     * leans on: searching for CFE_ES_CDS_BAD_HANDLE is how a FREE entry is found, because a
     * free entry is one whose handle is the bad one. */
    CFE_TBL_Global.CritReg[5].CDSHandle = CFE_ES_CDSHANDLE_C(CFE_ResourceId_FromInteger(0x5151));
    CFE_TBL_FindCriticalTblInfo(&crp, CFE_ES_CDSHANDLE_C(CFE_ResourceId_FromInteger(0x5151)));
    /* THE INDEX THE LONG WAY ROUND. `crp - CFE_TBL_Global.CritReg` is the idiomatic C, but
     * HolyC scales pointer arithmetic by the pointee and the two halves are kept reading the
     * same, so both divide an explicit byte difference. */
    printf("tbl_crit found=%d idx=%ld\n", (int)(crp != NULL),
           (long)(crp == NULL ? -1
                              : ((char *)crp - (char *)CFE_TBL_Global.CritReg) /
                                    (long)sizeof(CFE_TBL_CritRegRec_t)));
    CFE_TBL_FindCriticalTblInfo(&crp, CFE_ES_CDS_BAD_HANDLE);
    printf("tbl_crit free=%d idx=%ld\n", (int)(crp != NULL),
           (long)(crp == NULL ? -1
                              : ((char *)crp - (char *)CFE_TBL_Global.CritReg) /
                                    (long)sizeof(CFE_TBL_CritRegRec_t)));
    CFE_TBL_Global.CritReg[0].CDSHandle = CFE_ES_CDSHANDLE_C(CFE_ResourceId_FromInteger(0x1111));
    CFE_TBL_FindCriticalTblInfo(&crp, CFE_ES_CDSHANDLE_C(CFE_ResourceId_FromInteger(0x9999)));
    printf("tbl_crit absent=%d\n", (int)(crp == NULL));

    /* THE REGISTRY LOCK PAIR, which is NOT the counted one the transaction uses -- it is the
     * bare take/give, and its whole content is turning an OSAL status into a cFE one. The
     * driver's mutex returns what fs_mut_take_rc says, which is how the failure arm is
     * reached without a real mutex. */
    printf("tbl_reglock ok=%ld unlock=%ld\n", (long)CFE_TBL_LockRegistry(),
           (long)CFE_TBL_UnlockRegistry());
    fs_mut_take_rc = -1;
    fs_mut_give_rc = -1;
    printf("tbl_reglock failtake=%ld failgive=%ld\n", (long)CFE_TBL_LockRegistry(),
           (long)CFE_TBL_UnlockRegistry());
    fs_mut_take_rc = OS_SUCCESS;
    fs_mut_give_rc = OS_SUCCESS;

    /* THE NAME LOOKUP, through a whole transaction. Into a local first: the miss emits an
     * event, and C evaluates every printf argument before printing any of them. */
    found = CFE_TBL_FindTableInRegistry("NO.SUCH");
    printf("tbl_findreg miss=%d\n", (int)!CFE_TBL_REGID_IS_VALID(found));
    strncpy(rr->Config.Name, "APP.Found", CFE_TBL_MAX_FULL_NAME_LEN - 1);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
    found = CFE_TBL_FindTableInRegistry("APP.Found");
    printf("tbl_findreg hit=%d id=%lu\n", (int)CFE_TBL_REGID_IS_VALID(found),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(found));
}

static void TblCodecExercise(void)
{
    CFE_TBL_File_Hdr_t    hdr;
    CFE_TBL_RegistryRec_t *rr;
    CFE_TBL_TxnState_t     txn;
    uint32                 w;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));

    /* the swap itself, and that it is its own inverse */
    w = 0x01020304;
    CFE_TBL_ByteSwapUint32(&w);
    printf("tbl_cdswap once=%08lx", (unsigned long)w);
    CFE_TBL_ByteSwapUint32(&w);
    printf(" twice=%08lx\n", (unsigned long)w);

    /* THREE FIELDS SWAP, THE NAME DOES NOT -- which is why the header can be read as a
     * struct at all. */
    memset(&hdr, 0, sizeof(hdr));
    hdr.Reserved = 0x11223344;
    hdr.Offset   = 0x0000002A;
    hdr.NumBytes = 0x000000FF;
    strncpy(hdr.TableName, "CFE_TBL.Cdc", sizeof(hdr.TableName) - 1);
    CFE_TBL_ByteSwapTblHeader(&hdr);
    printf("tbl_cdhdr res=%08lx off=%08lx num=%08lx name=%s\n", (unsigned long)hdr.Reserved,
           (unsigned long)hdr.Offset, (unsigned long)hdr.NumBytes, hdr.TableName);
    CFE_TBL_ByteSwapTblHeader(&hdr);
    printf("tbl_cdhdr_back res=%08lx off=%08lx num=%08lx\n", (unsigned long)hdr.Reserved,
           (unsigned long)hdr.Offset, (unsigned long)hdr.NumBytes);

    /* THE SIZE CHECK, and the overflow case the first test exists for: Offset and NumBytes are
     * both 32-bit and come from a file, so their sum can WRAP -- a wrapped sum is smaller than
     * Offset and would otherwise pass the size test and then be used as a length. */
    rr = &CFE_TBL_Global.Registry[3];
    CFE_TBL_InitRegistryRecord(rr);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
    rr->Config.Size = 256;
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.Offset   = 0;
    hdr.NumBytes = 256;
    printf("tbl_cdsize exact=%ld", (long)CFE_TBL_ValidateCodecLoadSize(&txn, &hdr));
    hdr.NumBytes = 257;
    printf(" over=0x%lx", (unsigned long)(uint32)CFE_TBL_ValidateCodecLoadSize(&txn, &hdr));
    hdr.Offset   = 0xFFFFFFF0;
    hdr.NumBytes = 0x20; /* sum wraps to 0x10, which is < Offset and < Size */
    printf(" wrap=0x%lx events=%u\n",
           (unsigned long)(uint32)CFE_TBL_ValidateCodecLoadSize(&txn, &hdr),
           (unsigned)txn.NumPendingEvents);

    /* PARTIAL versus SHORT, which are different warnings for different reasons */
    memset(&hdr, 0, sizeof(hdr));
    hdr.Offset   = 0;
    hdr.NumBytes = 256;
    printf("tbl_cdfinal full=%ld", (long)CFE_TBL_CodecGetFinalStatus(&txn, &hdr));
    hdr.NumBytes = 128;
    printf(" short=0x%lx", (unsigned long)(uint32)CFE_TBL_CodecGetFinalStatus(&txn, &hdr));
    hdr.Offset   = 16;
    hdr.NumBytes = 256;
    printf(" partial=0x%lx\n", (unsigned long)(uint32)CFE_TBL_CodecGetFinalStatus(&txn, &hdr));

    /* the empty seam members, which still have to return the right thing */
    printf("tbl_cdseam cfg=%ld acquire_null=%d\n", (long)CFE_TBL_ValidateCodecConfig(&rr->Config),
           (int)(CFE_TBL_AcquireCodecBuffer(rr) == NULL));
    CFE_TBL_ReleaseCodecBuffer(&rr->Buffers[0]);

    /* ENCODE AND DECODE ARE A COPY, and both skip it when source and destination are the
     * same buffer -- the case a dump of an already-resident table hits. */
    rr->Buffers[0].BufferPtr      = tbl_probe_mem;
    rr->Buffers[0].AllocationSize = sizeof(tbl_probe_mem);
    rr->Buffers[1].BufferPtr      = tbl_probe_mem2;
    rr->Buffers[1].AllocationSize = sizeof(tbl_probe_mem2);
    memset(tbl_probe_mem, 0x5E, sizeof(tbl_probe_mem));
    memset(tbl_probe_mem2, 0, sizeof(tbl_probe_mem2));
    CFE_TBL_LoadBuffSetContentSize(&rr->Buffers[0], 12);
    printf("tbl_cdcopy enc=%ld dst=%02x len=%d",
           (long)CFE_TBL_EncodeOutputData(&txn, &rr->Buffers[0], &rr->Buffers[1]),
           (unsigned)tbl_probe_mem2[0], (int)CFE_TBL_LoadBuffGetContentSize(&rr->Buffers[1]));
    memset(tbl_probe_mem2, 0, sizeof(tbl_probe_mem2));
    CFE_TBL_LoadBuffSetContentSize(&rr->Buffers[1], 0);
    printf(" dec=%ld dst=%02x len=%d",
           (long)CFE_TBL_DecodeInputData(&txn, &rr->Buffers[0], &rr->Buffers[1]),
           (unsigned)tbl_probe_mem2[0], (int)CFE_TBL_LoadBuffGetContentSize(&rr->Buffers[1]));
    printf(" same=%ld\n",
           (long)CFE_TBL_EncodeOutputData(&txn, &rr->Buffers[0], &rr->Buffers[0]));

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

static void TblValResultExercise(void)
{
    CFE_TBL_ValidationResult_t *vr;
    CFE_TBL_RegistryRec_t      *rr;
    CFE_TBL_TxnState_t          txn;
    CFE_TBL_TxnEventContext_t   evctx;
    CFE_ResourceId_t            nid;
    uint32                      idx;
    int                         k, sent;
    int                         before;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_ES_GetAppID(&CFE_TBL_Global.TableTaskAppId);
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    /* THE ID SPACE HAS TO BE OPENED FIRST, the same line CFE_TBL_EarlyInit runs and the same
     * trap ES's exercises hit four times: CFE_TBL_Global is zeroed, 0 is not a valid resource
     * id, so CFE_ResourceId_FindNext starting there walks off the table and returns UNDEFINED
     * with all ten blocks free. The first draft of this exercise then dereferenced the NULL
     * that LocateValidationResultByID correctly returned -- a segfault on the C half, which is
     * the better place to find it. */
    CFE_TBL_Global.LastValidationResultId = CFE_ResourceId_FromInteger(
        CFE_TBL_VALRESULTID_BASE + CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1);

    /* the id space: first, last, one past (which WRAPS -- ToIndex is a modulo), undefined */
    printf("tbl_vridx first=%ld/%u last=%ld/%u past=%ld/%u undef=%ld\n",
           (long)CFE_TBL_ValidationResultId_ToIndex(
               CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE)), &idx),
           (unsigned)idx,
           (long)CFE_TBL_ValidationResultId_ToIndex(
               CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(
                   CFE_TBL_VALRESULTID_BASE + CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1)), &idx),
           (unsigned)idx,
           (long)CFE_TBL_ValidationResultId_ToIndex(
               CFE_TBL_VALRESULTID_C(CFE_ResourceId_FromInteger(
                   CFE_TBL_VALRESULTID_BASE + CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS)), &idx),
           (unsigned)idx,
           (long)CFE_TBL_ValidationResultId_ToIndex(CFE_TBL_VALRESULTID_UNDEFINED, &idx));

    /* the allocator primitives */
    nid = CFE_TBL_GetNextValResultBlock();
    vr  = CFE_TBL_LocateValidationResultByID(CFE_TBL_VALRESULTID_C(nid));
    /* vr is guarded the way NASA's own CheckValidationResultSlotUsed guards it: a NULL here
     * means the id was out of range, and IsUsed would dereference it. */
    printf("tbl_vralloc self=%d used=%d slotused=%d\n", (int)(vr == &CFE_TBL_Global.ValidationResults[0]),
           (int)(vr != NULL && CFE_TBL_ValidationResultIsUsed(vr)),
           (int)CFE_TBL_CheckValidationResultSlotUsed(CFE_ResourceId_FromInteger(0)));
    CFE_TBL_ValidationResultSetUsed(vr, nid);
    vr->State = CFE_TBL_VALIDATION_PERFORMED;
    printf("tbl_vrused used=%d id=%lu match=%d\n", (int)CFE_TBL_ValidationResultIsUsed(vr),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_ValidationResultGetId(vr)),
           (int)CFE_TBL_ValidationResultIsMatch(vr, CFE_TBL_VALRESULTID_C(nid)));
    CFE_TBL_ValidationResultSetFree(vr);
    printf("tbl_vrfree used=%d state=%d\n", (int)CFE_TBL_ValidationResultIsUsed(vr),
           (int)vr->State);

    /* A TABLE WITH A VALIDATION FUNCTION: the block goes PENDING and the app owes an answer. */
    rr = &CFE_TBL_Global.Registry[4];
    CFE_TBL_InitRegistryRecord(rr);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 4));
    strncpy(rr->Config.Name, "CFE_TBL.Val", sizeof(rr->Config.Name) - 1);
    rr->Config.ValidationFuncPtr = tbl_val_stub;
    rr->Buffers[0].BufferPtr      = tbl_probe_mem;
    rr->Buffers[0].AllocationSize = sizeof(tbl_probe_mem);
    rr->Buffers[0].Crc            = 0xFEEDFACE;
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 12),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    vr            = CFE_TBL_TxnSetupValidationRequest(&txn, CFE_TBL_BufferSelect_ACTIVE);
    printf("tbl_vrpending nonnull=%d state=%d crc=%08lx name=%s sel=%u events=%u reqs=%u\n",
           (int)(vr != NULL), (int)(vr == NULL ? -1 : vr->State),
           (unsigned long)(vr == NULL ? 0 : vr->CrcOfTable), vr == NULL ? "" : vr->TableName,
           (unsigned)(vr == NULL ? 0 : vr->BufferSelect), (unsigned)txn.NumPendingEvents,
           (unsigned)CFE_TBL_Global.NumValRequests);

    /* ASKING AGAIN WHILE ONE IS PENDING is refused, and the event carries the pending id. */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    vr            = CFE_TBL_TxnCheckValidationRequest(&txn);
    printf("tbl_vrinprog nonnull=%d events=%u id=%u data2=%ld\n", (int)(vr != NULL),
           (unsigned)txn.NumPendingEvents, (unsigned)txn.PendingEvents[0].EventId,
           (long)txn.PendingEvents[0].EventData2);

    /* NO VALIDATION FUNCTION: allocated anyway, straight to PERFORMED, buffer marked valid. */
    rr->Config.ValidationFuncPtr = NULL;
    rr->PendingValId             = CFE_TBL_VALRESULTID_UNDEFINED;
    rr->Buffers[0].IsValid       = false;
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    vr            = CFE_TBL_TxnSetupValidationRequest(&txn, CFE_TBL_BufferSelect_ACTIVE);
    printf("tbl_vrassumed nonnull=%d state=%d bufvalid=%d events=%u id=%u reqs=%u\n",
           (int)(vr != NULL), (int)(vr == NULL ? -1 : vr->State), (int)rr->Buffers[0].IsValid,
           (unsigned)txn.NumPendingEvents, (unsigned)txn.PendingEvents[0].EventId,
           (unsigned)CFE_TBL_Global.NumValRequests);

    /* AN ILLEGAL BUFFER SELECTOR never reaches a block at all. */
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    vr            = CFE_TBL_TxnSetupValidationRequest(&txn, (CFE_TBL_BufferSelect_Enum_t)99);
    printf("tbl_vrbadsel null=%d events=%u id=%u data2=%ld\n", (int)(vr == NULL),
           (unsigned)txn.NumPendingEvents, (unsigned)txn.PendingEvents[0].EventId,
           (long)txn.PendingEvents[0].EventData2);

    /* ALL TEN TAKEN, so the eleventh request has nowhere to put the answer. */
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS; k++)
    {
        CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[k],
                                        CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + k));
    }
    rr->Config.ValidationFuncPtr = tbl_val_stub;
    memset(&txn, 0, sizeof(txn));
    txn.RegRecPtr = rr;
    vr            = CFE_TBL_TxnSetupValidationRequest(&txn, CFE_TBL_BufferSelect_ACTIVE);
    printf("tbl_vrfull null=%d events=%u id=%u\n", (int)(vr == NULL),
           (unsigned)txn.NumPendingEvents, (unsigned)txn.PendingEvents[0].EventId);

    /* AND THE FOUR EVENT STRINGS, which are the only output this file produces. Two of them
     * carry a formatted number, and CFE_TBL_ASSUMED_VALID_INF_EID is the one that is
     * INFORMATION rather than ERROR -- visible in the EVS line's type field. */
    tbl_val_ids[0] = CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID;
    tbl_val_ids[1] = CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID;
    tbl_val_ids[2] = CFE_TBL_ASSUMED_VALID_INF_EID;
    tbl_val_ids[3] = CFE_TBL_VALIDATION_IN_PROGRESS_ERR_EID;
    tbl_val_ids[4] = 998;
    memset(&evctx, 0, sizeof(evctx));
    evctx.Operation  = "Validate";
    evctx.CallerName = "PROBE_APP";
    evctx.TableName  = "CFE_TBL.Val";
    for (k = 0; k < 5; k++)
    {
        CFE_TBL_TxnEvent_t ev;
        memset(&ev, 0, sizeof(ev));
        ev.EventId    = tbl_val_ids[k];
        ev.EventData2 = 0x1234ABCD;
        sent          = (int)CFE_TBL_SendValidationEventHelper(&ev, &evctx);
        printf("tbl_vrevt id=%u sent=%d\n", (unsigned)tbl_val_ids[k], sent);
    }
    /* THE WITNESS MOVED when CFE_TBL_SendTransactionEvents stopped being a stand-in. It used
     * to be a counter; the real one assembles the context, walks the pending events in the
     * order they were added, renders each through the helper, and CLEARS the list. So what
     * says it ran is the event text plus NumPendingEvents going to zero -- and the caller
     * name comes from the transaction, which is what proves the context assembly. */
    CFE_TBL_TxnAddEvent(&txn, CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID, 0, 0);
    CFE_TBL_TxnAddEvent(&txn, CFE_TBL_ASSUMED_VALID_INF_EID, 0, 0);
    txn.RegRecPtr = rr;
    strncpy(txn.AppNameBuffer, "TXN_APP", sizeof(txn.AppNameBuffer) - 1);
    before = (int)CFE_TBL_TxnGetEventCount(&txn);
    CFE_TBL_SendValidationEvents(&txn);
    printf("tbl_vrsend before=%d after=%u\n", before,
           (unsigned)CFE_TBL_TxnGetEventCount(&txn));

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

static void TblLoadBuffRegRecExercise(void)
{
    CFE_TBL_RegistryRec_t      *rr;
    CFE_TBL_AccessDescriptor_t *ad;
    CFE_TBL_LoadBuff_t         *lb;
    CFE_ResourceId_t            nid;
    uint32                      cat, idx, serial;
    uint32                      descs;
    int                         k;
    int                         stale_before, stale_got, stale_after;
    int                         before;
    CFE_TBL_TxnState_t          txn2;
    CFE_TBL_TxnEventContext_t   evctx;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.WorkBufMutex = OS_ObjectIdFromInteger(0x7B20);

    /* DECOMPOSE over the category boundary: 0..3 are shared, 4 onward are table 0's pair. */
    for (k = 0; k < 8; k++)
    {
        CFE_TBL_LoadBuffSerialDecompose(k, &cat, &idx);
        printf("tbl_lbdec s=%d cat=%u idx=%u\n", k, (unsigned)cat, (unsigned)idx);
    }

    /* COMPOSE IS NOT THE INVERSE: it rounds UP to the next serial in the asked-for category. */
    for (k = 0; k < 3; k++)
    {
        serial = k;
        CFE_TBL_LoadBuffSerialCompose(&serial, 0, 1);
        printf("tbl_lbcomp in=%d cat=0 idx=1 out=%u\n", k, (unsigned)serial);
        serial = k;
        CFE_TBL_LoadBuffSerialCompose(&serial, 2, 0);
        printf("tbl_lbcomp in=%d cat=2 idx=0 out=%u\n", k, (unsigned)serial);
    }

    /* LOCATE: a shared id lands in CFE_TBL_Global.LoadBuffs, a local id in the table's own
     * pair -- and a SINGLE-buffered table always uses local index 0 whichever is asked for. */
    rr = &CFE_TBL_Global.Registry[1];
    rr->Config.DoubleBuffered = true;
    printf("tbl_lbloc shared0=%d shared3=%d\n",
           (int)(CFE_TBL_LocateLoadBufferByID(
                     CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE))) ==
                 &CFE_TBL_Global.LoadBuffs[0]),
           (int)(CFE_TBL_LocateLoadBufferByID(CFE_TBL_LOADBUFFID_C(
                     CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 3))) ==
                 &CFE_TBL_Global.LoadBuffs[3]));
    /* table 1's pair is category 2, i.e. serial 4 + 1*2 = 6 and 7 */
    printf("tbl_lbloc dbl0=%d dbl1=%d\n",
           (int)(CFE_TBL_LocateLoadBufferByID(CFE_TBL_LOADBUFFID_C(
                     CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6))) ==
                 &rr->Buffers[0]),
           (int)(CFE_TBL_LocateLoadBufferByID(CFE_TBL_LOADBUFFID_C(
                     CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 7))) ==
                 &rr->Buffers[1]));
    rr->Config.DoubleBuffered = false;
    printf("tbl_lbloc sgl_collapses=%d\n",
           (int)(CFE_TBL_LocateLoadBufferByID(CFE_TBL_LOADBUFFID_C(
                     CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 7))) ==
                 &rr->Buffers[0]));

    /* THE HISTORICAL TELEMETRY INDEX: shared buffers report 0..3, a double-buffered table's
     * own pair reports -3 and -2, and anything unrecognised is -1. */
    printf("tbl_lbtlm sh0=%ld sh3=%ld loc0=%ld loc1=%ld\n",
           (long)CFE_TBL_LoadBuffIdToTlmIndex(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE))),
           (long)CFE_TBL_LoadBuffIdToTlmIndex(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 3))),
           (long)CFE_TBL_LoadBuffIdToTlmIndex(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6))),
           (long)CFE_TBL_LoadBuffIdToTlmIndex(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 7))));

    printf("tbl_lbkind sh_isshared=%d loc_isshared=%d loc_isprivate1=%d loc_isprivate0=%d\n",
           (int)CFE_TBL_LoadBuffIsShared(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE))),
           (int)CFE_TBL_LoadBuffIsShared(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6))),
           (int)CFE_TBL_LoadBuffIsPrivate(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6)),
               CFE_TBL_REGID_C(CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 1))),
           (int)CFE_TBL_LoadBuffIsPrivate(
               CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6)),
               CFE_TBL_REGID_C(CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE))));

    /* INIT SETS FOUR FIELDS EXPLICITLY, and in THIS configuration all four are zero anyway
     * (CFE_RESOURCEID_UNDEFINED is 0 and the SIMPLE resourceid mode makes every wrapper the
     * identity). The record is filled with 0x5A first, so what this asserts is that Init ran
     * at all -- and `lip` and `attached` are the two that would differ regardless. */
    rr = &CFE_TBL_Global.Registry[2];
    memset(rr, 0x5A, sizeof(*rr));
    CFE_TBL_InitRegistryRecord(rr);
    printf("tbl_rrinit owner=%lu val=%lu cds=%lu dump=%lu lip=%d attached=%d\n",
           (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->OwnerAppId),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->PendingValId),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->CDSHandle),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->DumpControlId),
           (int)(CFE_TBL_RegRecIsLoadInProgress(rr) != 0),
           (int)CFE_TBL_HandleLinkIsAttached(&rr->AccessList));

    /* name and id lookup */
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 2));
    strncpy(rr->Config.Name, "CFE_TBL.Probe", sizeof(rr->Config.Name) - 1);
    printf("tbl_rrfind byname=%d bymiss=%d byid=%d used=%d name=%s\n",
           (int)(CFE_TBL_LocateRegRecByName("CFE_TBL.Probe") == rr),
           (int)(CFE_TBL_LocateRegRecByName("CFE_TBL.Nope") == NULL),
           (int)(CFE_TBL_LocateRegRecByID(CFE_TBL_RegRecGetID(rr)) == rr),
           (int)CFE_TBL_RegRecIsUsed(rr), CFE_TBL_RegRecGetName(rr));

    /* THE BRANCH THIS WHOLE PAIR WAS SEQUENCED FOR. A double-buffered table wants its other
     * buffer for a new load. If another application still holds that buffer -- it called
     * CFE_TBL_GetAddress and has not released it, so LockFlag is set -- the load must be
     * REFUSED and the holder named. Reaching this needs a real walk of the access-descriptor
     * list, which is why CFE_TBL_ForeachAccessDescriptor is faithful in the driver and not a
     * counter: a walk of zero descriptors makes the refusal unreachable and the assertion
     * below would pass while testing nothing. */
    rr                        = &CFE_TBL_Global.Registry[0];
    CFE_TBL_InitRegistryRecord(rr);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE));
    rr->Config.DoubleBuffered = true;
    /* active is local idx 0 (serial 4), so the next local buffer is idx 1 (serial 5) */
    rr->Status.ActiveBufferId =
        CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 4));
    nid = CFE_TBL_GetNextLocalBufferId(rr);
    lb  = CFE_TBL_LocateLoadBufferByID(CFE_TBL_LOADBUFFID_C(nid));
    printf("tbl_nextlocal id=%lu isbuf1=%d\n", (unsigned long)CFE_ResourceId_ToInteger(nid),
           (int)(lb == &rr->Buffers[1]));
    /* mark it used by someone else so the exclusive check has to run */
    /* A DIFFERENT ID THAT NAMES THE SAME BLOB. 260 serials cover every buffer once, so
     * serial+260 decomposes to the same place -- which is precisely the case NASA's helper
     * comment calls out: "check if it refers to this memory blob (even if the ID is
     * different)". Using an unrelated id instead would land on another table's buffer and
     * the locked-buffer branch would never fire, which is how the first draft of this
     * exercise passed while testing nothing. */
    CFE_TBL_LoadBuffSetUsed(lb, CFE_ResourceId_FromInteger(CFE_ResourceId_ToInteger(nid) + 260),
                            CFE_TBL_RegRecGetID(rr));

    /* attach ONE access descriptor holding that buffer, locked */
    ad = &CFE_TBL_Global.Handles[7];
    CFE_TBL_InitAccessDescriptor(ad);
    CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 7));
    ad->AppId       = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0xABCD));
    ad->BufferIndex = CFE_TBL_LoadBufferGetID(lb);
    ad->LockFlag    = true;
    rr->AccessList.Next = CFE_TBL_AccDescGetHandle(ad);

    /* into a local first: this call emits the syslog line naming the holder, and the two
     * halves print in different orders otherwise -- see the note at tbl_stalelip. */
    /* WHAT `descs` REPLACED, AND WHAT IT DOES NOT. This line used to report a counter the
     * DRIVER kept inside its own copy of CFE_TBL_ForeachAccessDescriptor, and `visits=1` here
     * against `visits=0` at tbl_lockedclaim below was an assertion about CONTROL FLOW INSIDE
     * CFE_TBL_GetInactiveBufferExclusive -- one path walked the list, the other returned
     * before it. `descs` cannot tell those apart: it counts the list AFTER the call and reads
     * 1 at both sites. So this is a trade, not an upgrade. What is gained is real --
     * ForeachAccessDescriptor and CountAccessDescHelper had never been called by anything --
     * and what is lost went with the stub, because a counter inside gated code is not
     * something a driver may add.
     *
     * Third occurrence of the recorded trap: the witness moves when the stub goes, and the
     * replacement is rarely the same shape. */
    descs     = 0;
    stale_got = (CFE_TBL_GetInactiveBufferExclusive(rr) == NULL);
    CFE_TBL_ForeachAccessDescriptor(rr, CFE_TBL_CountAccessDescHelper, &descs);
    printf("tbl_lockedrefuse null=%d descs=%u\n", stale_got, (unsigned)descs);

    /* release the lock and the SAME call now claims the buffer for this table */
    ad->LockFlag       = false;
    descs = 0;
    lb    = CFE_TBL_GetInactiveBufferExclusive(rr);
    CFE_TBL_ForeachAccessDescriptor(rr, CFE_TBL_CountAccessDescHelper, &descs);
    printf("tbl_lockedclaim nonnull=%d descs=%u owner=%lu\n", (int)(lb != NULL), (unsigned)descs,
           (unsigned long)(lb == NULL ? 0 : CFE_RESOURCEID_TO_ULONG(lb->OwnerRegId)));

    /* THE STALE LOAD-IN-PROGRESS RECOVERY. A NextBufferId that no longer matches its buffer
     * is cleared rather than trusted, and the table is reported. */
    /* EACH VALUE INTO A LOCAL FIRST. The middle call emits a syslog line, and C evaluates
     * printf's arguments before printing any of them while the HolyC half prints
     * incrementally -- so an inline call would put that line on opposite sides of this one.
     * (C does not even specify the order among arguments, so this is the portable shape
     * regardless.) */
    CFE_TBL_RegRecSetLoadInProgress(
        rr, CFE_TBL_LOADBUFFID_C(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 2)));
    stale_before = (CFE_TBL_RegRecIsLoadInProgress(rr) != 0);
    stale_got    = (CFE_TBL_GetLoadInProgressBuffer(rr) != NULL);
    stale_after  = (CFE_TBL_RegRecIsLoadInProgress(rr) != 0);
    printf("tbl_stalelip before=%d got=%d after=%d\n", stale_before, stale_got, stale_after);

    /* the three buffer questions, now that one is active */
    printf("tbl_buf3 active=%d lip=%d inactive=%d loaded=%d\n",
           (int)(CFE_TBL_GetActiveBuffer(rr) == &rr->Buffers[0]),
           (int)(CFE_TBL_GetLoadInProgressBuffer(rr) == NULL),
           (int)(CFE_TBL_GetInactiveBuffer(rr) != NULL), (int)CFE_TBL_RegRecIsTableLoaded(rr));

    /* selected-buffer dispatch, including the default that returns NULL */
    printf("tbl_bufsel act=%d inact=%d bogus=%d\n",
           (int)(CFE_TBL_GetSelectedBuffer(rr, CFE_TBL_BufferSelect_ACTIVE) ==
                 CFE_TBL_GetActiveBuffer(rr)),
           (int)(CFE_TBL_GetSelectedBuffer(rr, CFE_TBL_BufferSelect_INACTIVE) ==
                 CFE_TBL_GetInactiveBuffer(rr)),
           (int)(CFE_TBL_GetSelectedBuffer(rr, (CFE_TBL_BufferSelect_Enum_t)99) == NULL));

    /* modified flag and load info */
    CFE_TBL_RegRecResetLoadInfo(rr, "/cf/probe.tbl", CFE_TIME_GetTime());
    printf("tbl_loadinfo file=%s modified=%d\n", CFE_TBL_RegRecGetLastFileLoaded(rr),
           (int)CFE_TBL_RegRecIsModified(rr));
    CFE_TBL_RegRecSetModifiedFlag(rr);
    printf("tbl_modified %d\n", (int)CFE_TBL_RegRecIsModified(rr));

    /* pending activation needs BOTH validated and requested */
    lb = CFE_TBL_LocateLoadBufferByID(CFE_TBL_RegRecGetLoadInProgress(rr));
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[1]));
    lb = &rr->Buffers[1];
    lb->IsValid     = false;
    lb->ActivateReq = true;
    printf("tbl_pending novalid=%d", (int)CFE_TBL_RegRecIsPendingActivation(rr));
    lb->IsValid = true;
    printf(" both=%d", (int)CFE_TBL_RegRecIsPendingActivation(rr));
    lb->ActivateReq = false;
    printf(" noreq=%d\n", (int)CFE_TBL_RegRecIsPendingActivation(rr));

    /* THE TWO FUNCTIONS THAT COMPOSE ALL OF THE ABOVE, which nothing had reached yet.
     *
     * PrepareNewLoadBuff picks the buffer for a new load: a double-buffered table gets its
     * own other buffer (exclusively, so the walk above runs), a single-buffered one borrows
     * from the shared pool. Either way the ACTIVE contents are copied forward first, because
     * a file may contain only part of a table, and the result is marked unvalidated. */
    rr = &CFE_TBL_Global.Registry[5];
    CFE_TBL_InitRegistryRecord(rr);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 5));
    rr->Config.DoubleBuffered     = true;
    rr->Buffers[0].BufferPtr      = tbl_probe_mem;
    rr->Buffers[0].AllocationSize = sizeof(tbl_probe_mem);
    rr->Buffers[1].BufferPtr      = tbl_probe_mem2;
    rr->Buffers[1].AllocationSize = sizeof(tbl_probe_mem2);
    memset(tbl_probe_mem, 0xC3, sizeof(tbl_probe_mem));
    CFE_TBL_LoadBuffSetContentSize(&rr->Buffers[0], 8);
    rr->Buffers[0].IsValid = true;
    /* A TABLE'S OWN BUFFERS NEED THEIR OWN IDS, or SetActiveBuffer stores a zero and
     * GetActiveBuffer resolves it to NULL -- which is faithful (an unset id IS undefined) but
     * means nothing is copied forward and the assertion below reads `copied=0`, passing while
     * testing the wrong path. Registry[5] is category 6, so its pair is serial 4+5*2 = 14
     * and 15. */
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 14),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_LoadBuffSetUsed(&rr->Buffers[1],
                            CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 15),
                            CFE_TBL_RegRecGetID(rr));
    CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
    lb = CFE_TBL_PrepareNewLoadBuff(rr);
    printf("tbl_prepdbl isbuf1=%d copied=%d first=%02x valid=%d actreq=%d\n",
           (int)(lb == &rr->Buffers[1]),
           (int)(lb == NULL ? -1 : (int)CFE_TBL_LoadBuffGetContentSize(lb)),
           (unsigned)(lb == NULL ? 0 : ((unsigned char *)CFE_TBL_LoadBuffGetReadPointer(lb))[0]),
           (int)(lb == NULL ? -1 : lb->IsValid), (int)(lb == NULL ? -1 : lb->ActivateReq));

    /* the single-buffered path, which goes through the shared pool via AcquireGlobalLoadBuff */
    rr = &CFE_TBL_Global.Registry[6];
    CFE_TBL_InitRegistryRecord(rr);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 6));
    rr->Config.DoubleBuffered                  = false;
    CFE_TBL_Global.LoadBuffs[0].BufferPtr      = tbl_probe_mem2;
    CFE_TBL_Global.LoadBuffs[0].AllocationSize = sizeof(tbl_probe_mem2);
    CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 3);
    lb                            = CFE_TBL_PrepareNewLoadBuff(rr);
    printf("tbl_prepsgl shared=%d isbuf0=%d owner=%lu valid=%d\n",
           (int)(lb == NULL ? -1 : (int)CFE_TBL_LoadBuffIsShared(CFE_TBL_LoadBufferGetID(lb))),
           (int)(lb == &CFE_TBL_Global.LoadBuffs[0]),
           (unsigned long)(lb == NULL ? 0 : CFE_RESOURCEID_TO_ULONG(lb->OwnerRegId)),
           (int)(lb == NULL ? -1 : lb->IsValid));

    /* TxnSetupActivationRequest: three refusals and one success, each with its own event. */
    memset(&txn2, 0, sizeof(txn2));
    txn2.RegRecPtr      = &CFE_TBL_Global.Registry[5];
    rr                  = txn2.RegRecPtr;
    rr->Config.DumpOnly = true;
    printf("tbl_actv dumponly null=%d events=%u id=%u\n",
           (int)(CFE_TBL_TxnSetupActivationRequest(&txn2) == NULL),
           (unsigned)txn2.NumPendingEvents, (unsigned)txn2.PendingEvents[0].EventId);
    rr->Config.DumpOnly = false;
    memset(&txn2, 0, sizeof(txn2));
    txn2.RegRecPtr = rr;
    CFE_TBL_RegRecClearLoadInProgress(rr);
    printf("tbl_actv nobuf null=%d events=%u id=%u\n",
           (int)(CFE_TBL_TxnSetupActivationRequest(&txn2) == NULL),
           (unsigned)txn2.NumPendingEvents, (unsigned)txn2.PendingEvents[0].EventId);
    memset(&txn2, 0, sizeof(txn2));
    txn2.RegRecPtr = rr;
    CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[1]));
    rr->Buffers[1].IsValid = false;
    printf("tbl_actv unvalidated null=%d events=%u id=%u\n",
           (int)(CFE_TBL_TxnSetupActivationRequest(&txn2) == NULL),
           (unsigned)txn2.NumPendingEvents, (unsigned)txn2.PendingEvents[0].EventId);
    memset(&txn2, 0, sizeof(txn2));
    txn2.RegRecPtr         = rr;
    rr->Buffers[1].IsValid = true;
    lb                     = CFE_TBL_TxnSetupActivationRequest(&txn2);
    printf("tbl_actv ok nonnull=%d events=%u actreq=%d\n", (int)(lb != NULL),
           (unsigned)txn2.NumPendingEvents, (int)(lb == NULL ? -1 : lb->ActivateReq));

    /* AND THE EVENT TEXT, which IS the comparison surface -- the only thing that compares the
     * three strings this file formats. The helper is called directly, as NASA's own unit tests
     * do: it is not static, and the dispatcher that would reach it lives in
     * cfe_tbl_transaction.c, which is still inside the cycle. An event id it does not know
     * returns false, which is how the dispatcher passes an event to the next helper. */
    /* AND THE EVENT NEEDS A REGISTERED APP, or EVS refuses it and the three strings this
     * file formats are never emitted -- `sent=1` would still be printed, because that is the
     * HELPER's return value, not EVS's. The first version of this exercise asserted exactly
     * that and compared nothing. */
    CFE_ES_GetAppID(&CFE_TBL_Global.TableTaskAppId);
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    /* filled at run time, not in the declaration: HolyC has no file-scope aggregate
     * initialiser, and the two halves are kept the same shape (recorded driver trap). */
    tbl_actv_ids[0] = CFE_TBL_ACTIVATE_DUMP_ONLY_ERR_EID;
    tbl_actv_ids[1] = CFE_TBL_ACTIVATE_ERR_EID;
    tbl_actv_ids[2] = CFE_TBL_UNVALIDATED_ERR_EID;
    tbl_actv_ids[3] = 999;
    memset(&evctx, 0, sizeof(evctx));
    evctx.Operation  = "Activate";
    evctx.CallerName = "PROBE_APP";
    evctx.TableName  = "CFE_TBL.Probe";
    for (k = 0; k < 4; k++)
    {
        CFE_TBL_TxnEvent_t ev;
        memset(&ev, 0, sizeof(ev));
        ev.EventId = tbl_actv_ids[k];
        /* into a local first -- this call EMITS the event, and the two halves print in
         * different orders otherwise. Third time; see the note at tbl_stalelip. */
        stale_got = (int)CFE_TBL_SendActivationEventHelper(&ev, &evctx);
        printf("tbl_actvevt id=%u sent=%d\n", (unsigned)tbl_actv_ids[k], stale_got);
    }
    /* and the wrapper, which only counts here because SendTransactionEvents is a stand-in */
    /* same, for the activation helper -- and with NO registry record on the transaction, so
     * the context's TableName falls back to the literal "[unknown]" rather than being left
     * blank. That fallback is one line in SendTransactionEvents and is visible in the text. */
    memset(&txn2, 0, sizeof(txn2));
    CFE_TBL_TxnAddEvent(&txn2, CFE_TBL_ACTIVATE_ERR_EID, 0, 0);
    strncpy(txn2.AppNameBuffer, "TXN_APP", sizeof(txn2.AppNameBuffer) - 1);
    before = (int)CFE_TBL_TxnGetEventCount(&txn2);
    CFE_TBL_SendActivationEvents(&txn2);
    printf("tbl_actvsend before=%d after=%u\n", before,
           (unsigned)CFE_TBL_TxnGetEventCount(&txn2));

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

static void TblAccDescExercise(void)
{
    CFE_TBL_AccessDescriptor_t *ad;
    CFE_TBL_RegistryRec_t      *rr;
    CFE_TBL_TxnState_t          txn;
    CFE_ResourceId_t            nid;
    uint32                      idx;
    int                         k, t0, g0;
    int                         before;

    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.RegistryMutex = OS_ObjectIdFromInteger(0x7B10);
    CFE_TBL_Global.LastHandle =
        CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES - 1);

    /* ToIndex DOES NOT BOUNDS CHECK, and that is the thing to know about every resource id
     * in cFS. Its last line is `*Idx = Serial % TableSize` -- a MODULO. The only rejection is
     * a serial above CFE_RESOURCEID_MAX. So one past the last handle WRAPS to index 0 and
     * reports success, and what actually establishes that a record is the one you asked for
     * is CFE_TBL_AccDescIsMatch comparing the id STORED IN the record. An id check that only
     * called ToIndex would read a live neighbour and believe it. */
    printf("tbl_adidx first=%ld/%u last=%ld/%u past=%ld/%u undef=%ld\n",
           (long)CFE_TBL_Handle_ToIndex(
               CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE)), &idx),
           (unsigned)idx,
           (long)CFE_TBL_Handle_ToIndex(
               CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(
                   CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES - 1)), &idx),
           (unsigned)idx,
           (long)CFE_TBL_Handle_ToIndex(
               CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(
                   CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES)), &idx),
           (unsigned)idx,
           (long)CFE_TBL_Handle_ToIndex(CFE_TBL_HANDLEID_UNDEFINED, &idx));

    ad = CFE_TBL_LocateAccDescByHandle(
        CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 5)));
    printf("tbl_adloc self=%d used=%d null=%d slotused=%d\n",
           (int)(ad == &CFE_TBL_Global.Handles[5]), (int)CFE_TBL_AccDescIsUsed(ad),
           (int)(CFE_TBL_LocateAccDescByHandle(CFE_TBL_HANDLEID_UNDEFINED) == NULL),
           (int)CFE_TBL_CheckAccessDescriptorSlotUsed(CFE_ResourceId_FromInteger(0)));

    /* init, mark used, read back, match, free -- the allocator primitives */
    nid = CFE_TBL_GetNextTableHandle();
    ad  = CFE_TBL_LocateAccDescByHandle(CFE_TBL_HANDLEID_C(nid));
    memset(ad, 0xEE, sizeof(*ad));
    CFE_TBL_InitAccessDescriptor(ad);
    printf("tbl_adinit id=%lu zeroed=%d linkdetached=%d\n",
           (unsigned long)CFE_ResourceId_ToInteger(nid),
           (int)(ad->LockFlag == false && ad->AppId == 0),
           (int)!CFE_TBL_HandleLinkIsAttached(&ad->Link));
    CFE_TBL_AccDescSetUsed(ad, nid);
    printf("tbl_adused used=%d back=%lu match=%d\n", (int)CFE_TBL_AccDescIsUsed(ad),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_AccDescGetHandle(ad)),
           (int)CFE_TBL_AccDescIsMatch(ad, CFE_TBL_HANDLEID_C(nid)));
    ad->AppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x4321));
    CFE_TBL_AccDescSetFree(ad);
    printf("tbl_adfree used=%d appid=%lu\n", (int)CFE_TBL_AccDescIsUsed(ad),
           (unsigned long)CFE_RESOURCEID_TO_ULONG(ad->AppId));

    /* A WHOLE TRANSACTION, and the lock is the thing being watched. */
    memset(&txn, 0, sizeof(txn));
    t0 = fs_mut_take;
    g0 = fs_mut_give;
    printf("tbl_adtxn rc=%ld handle=%lu nonnull=%d used=%d takes=%d gives=%d lockcnt=%u\n",
           (long)CFE_TBL_TxnAllocateAccDesc(&txn),
           (unsigned long)CFE_TBL_TxnHandleAsULong(&txn), (int)(txn.AccDescPtr != NULL),
           (int)(txn.AccDescPtr != NULL && CFE_TBL_AccDescIsUsed(txn.AccDescPtr)),
           fs_mut_take - t0, fs_mut_give - g0, (unsigned)txn.RegLockCount);

    /* RELEASE BY THE OWNER clears the table's owner; RemoveAccessLink is called once. */
    /* cfe_tbl_regrec.c IS gated now, so CFE_TBL_InitRegistryRecord is available -- the memset
     * stays because this exercise wants a record with NO buffers and NO access links, which
     * is what a zeroed one is; InitRegistryRecord would fill in defaults this test then has
     * to undo. */
    rr = &CFE_TBL_Global.Registry[3];
    memset(rr, 0, sizeof(*rr));
    rr->OwnerAppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    /* WHAT `regused` REPLACED, AND WHY IT IS SET FIRST. This line used to report a counter
     * inside the driver's own CFE_TBL_TxnRemoveAccessLink. That stand-in is gone, so what is
     * witnessed now is the real function's EFFECT: an unowned table with no remaining access
     * links is returned to the pool by CFE_TBL_RegRecSetFree. The record is marked USED here
     * on purpose -- a zeroed record already reads free, so asserting `regused=0` against a
     * record that was never used is the vacuous-zero shape this transcript has been caught by
     * before. `before=1` is in the line so the reader can see it was not. */
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
    before        = (int)CFE_TBL_RegRecIsUsed(rr);
    txn.AppId     = rr->OwnerAppId;
    txn.RegRecPtr = rr;
    CFE_TBL_TxnReleaseAccDesc(&txn);
    printf("tbl_adrel_owner owner=%lu freed=%d before=%d regused=%d\n",
           (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->OwnerAppId),
           (int)!CFE_TBL_AccDescIsUsed(txn.AccDescPtr), before,
           (int)CFE_TBL_RegRecIsUsed(rr));

    /* RELEASE BY A NON-OWNER must leave the table owned -- but it still FREES the
     * descriptor, and `freed=1` below is correct, not a bug. CFE_TBL_AccDescSetFree is
     * outside the ownership `if`: giving back your own handle always gives it back, and
     * only the un-owning of the TABLE is conditional. A reader checking "a non-owner should
     * change nothing" would misread that line. */
    memset(&txn, 0, sizeof(txn));
    CFE_TBL_TxnAllocateAccDesc(&txn);
    CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
    rr->OwnerAppId = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x1111));
    txn.AppId      = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x2222));
    txn.RegRecPtr  = rr;
    CFE_TBL_TxnReleaseAccDesc(&txn);
    /* and `regused=1` here is the other half of the same claim: the table is still OWNED, so
     * RemoveAccessLink's two-part test fails on the first part and the record stays. */
    printf("tbl_adrel_other owner=%lu freed=%d regused=%d\n",
           (unsigned long)CFE_RESOURCEID_TO_ULONG(rr->OwnerAppId),
           (int)!CFE_TBL_AccDescIsUsed(txn.AccDescPtr), (int)CFE_TBL_RegRecIsUsed(rr));

    /* EXHAUSTION. All 256 marked used, so the next transaction must refuse and must leave
     * the transaction's own fields cleared rather than half-filled. */
    for (k = 0; k < CFE_PLATFORM_TBL_MAX_NUM_HANDLES; k++)
    {
        CFE_TBL_AccDescSetUsed(&CFE_TBL_Global.Handles[k],
                               CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + k));
    }
    memset(&txn, 0, sizeof(txn));
    t0 = fs_mut_take;
    g0 = fs_mut_give;
    printf("tbl_adfull rc=0x%lx null=%d handle=%lu takes=%d gives=%d\n",
           /* uint32 FIRST: CFE_TBL_ERR_HANDLES_FULL is 0xCC00000B, which as a signed
            * int32 is negative, and casting straight to unsigned long sign-extends it to
            * sixteen hex digits where the HolyC half's Hx8 prints eight. */
           (unsigned long)(uint32)CFE_TBL_TxnAllocateAccDesc(&txn), (int)(txn.AccDescPtr == NULL),
           (unsigned long)CFE_TBL_TxnHandleAsULong(&txn), fs_mut_take - t0, fs_mut_give - g0);
    memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

static void TblDumpCtlExercise(void)
{
    CFE_TBL_DumpControl_t *bp;
    CFE_ResourceId_t       nid;
    uint32                 idx;
    int                    k;

        memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
        CFE_TBL_Global.LastDumpCtrlBlockId =
            CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE +
                                       CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1);

        /* ToIndex: the first slot, the last slot, one past the end, and an undefined id */
        printf("tbl_dcidx first=%ld/%u last=%ld/%u past=%ld undef=%ld\n",
               (long)CFE_TBL_DumpCtrlId_ToIndex(
                   CFE_TBL_DUMPCTRLID_C(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE)),
                   &idx), (unsigned)idx,
               (long)CFE_TBL_DumpCtrlId_ToIndex(
                   CFE_TBL_DUMPCTRLID_C(CFE_ResourceId_FromInteger(
                       CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1)),
                   &idx), (unsigned)idx,
               (long)CFE_TBL_DumpCtrlId_ToIndex(
                   CFE_TBL_DUMPCTRLID_C(CFE_ResourceId_FromInteger(
                       CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS)),
                   &idx),
               (long)CFE_TBL_DumpCtrlId_ToIndex(CFE_TBL_DUMPCTRLID_UNDEFINED, &idx));

        /* Locate: every slot resolves to its own address, and a bad id gives NULL */
        for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
        {
            bp = CFE_TBL_LocateDumpCtrlByID(
                CFE_TBL_DUMPCTRLID_C(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + k)));
            printf("tbl_dcloc k=%d self=%d used=%d\n", k,
                   (int)(bp == &CFE_TBL_Global.DumpControlBlocks[k]),
                   (int)(bp != NULL && CFE_TBL_DumpCtrlBlockIsUsed(bp)));
        }
        printf("tbl_dcloc_bad null=%d slotused=%d\n",
               (int)(CFE_TBL_LocateDumpCtrlByID(CFE_TBL_DUMPCTRLID_UNDEFINED) == NULL),
               (int)CFE_TBL_CheckDumpCtrlSlotUsed(CFE_ResourceId_FromInteger(0)));

        /* THE ALLOCATOR. Four blocks, so the fifth request must come back UNDEFINED --
         * exhaustion is the path that matters, because a dump request that silently
         * reused a block would overwrite another table's pending snapshot. */
        for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS + 1; k++)
        {
            nid = CFE_TBL_GetNextDumpCtrlBlock();
            bp  = CFE_TBL_LocateDumpCtrlByID(CFE_TBL_DUMPCTRLID_C(nid));
            printf("tbl_dcnext k=%d id=%lu got=%d", k,
                   (unsigned long)CFE_ResourceId_ToInteger(nid), (int)(bp != NULL));
            if (bp != NULL)
            {
                CFE_TBL_DumpCtrlBlockSetUsed(bp, nid);
                CFE_TBL_Global.LastDumpCtrlBlockId = nid;
                printf(" used=%d id_back=%lu match=%d",
                       (int)CFE_TBL_DumpCtrlBlockIsUsed(bp),
                       (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_DumpCtrlBlockGetId(bp)),
                       (int)CFE_TBL_DumpCtrlBlockIsMatch(bp, CFE_TBL_DUMPCTRLID_C(nid)));
            }
            printf("\n");
        }

        /* and freeing one puts BOTH fields back, which is what lets it be reallocated */
        bp = &CFE_TBL_Global.DumpControlBlocks[2];
        bp->State = CFE_TBL_DUMP_PERFORMED;
        CFE_TBL_DumpCtrlBlockSetFree(bp);
        printf("tbl_dcfree used=%d state=%d match=%d next=%lu\n",
               (int)CFE_TBL_DumpCtrlBlockIsUsed(bp), (int)bp->State,
               (int)CFE_TBL_DumpCtrlBlockIsMatch(bp, CFE_TBL_DUMPCTRLID_UNDEFINED),
               (unsigned long)CFE_ResourceId_ToInteger(CFE_TBL_GetNextDumpCtrlBlock()));
        memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
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

    /* AND THE OTHER THREE ID SPACES, for exactly the same reason and with the same symptom:
     * CFE_ES_RegisterGenCounter came back CFE_ES_NO_RESOURCE_IDS_AVAILABLE with every slot
     * free, because CFE_ResourceId_FindNext starting from 0 walks off the table. These are
     * cfe_es_start.c:175-177, the three lines next to the pool one already here. */
    CFE_ES_Global.LastAppId     = CFE_ResourceId_FromInteger(CFE_ES_APPID_BASE);
    CFE_ES_Global.LastLibId     = CFE_ResourceId_FromInteger(CFE_ES_LIBID_BASE);
    CFE_ES_Global.LastCounterId = CFE_ResourceId_FromInteger(CFE_ES_COUNTID_BASE);

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
        /* THE WAKEUP WITNESS IS THE SEMAPHORE NOW. CFE_ES_BackgroundWakeup was a stub that
         * bumped fs_wakeups; cfe_es_backgroundtask.c is gated, so the real one gives
         * CFE_ES_Global.BackgroundTask.WorkSem and time_sem_gives is what counts that. */
        printf("fs_req rc=%ld pend=%d wake=%ld\n", (long)CFE_FS_BackgroundFileDumpRequest(&m),
               (int)CFE_FS_BackgroundFileDumpIsPending(&m), time_sem_gives);
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
         * THE TABLES ARE POPULATED BY HAND HERE. When this was written cfe_es_apps.c was not
         * gated and there was no CFE_ES_AppCreate to call; it is gated now, and the hand-written
         * records stay because they let the exercise pick the ids. Writing the records directly is what lets the lookups
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

        /* --- cfe_es_api.c: ES'S PUBLIC API ------------------------------------------------
         *
         * Forty-six functions, and what they have in common is that almost none of them DO
         * anything: Restart, Reload and Delete set a control request and return, because an app
         * cannot be torn down from inside the caller's context -- the caller might BE the app.
         * So what this block checks is the DECISIONS: which id is accepted, which lock is held
         * while the decision is made, and what the syslog says when it is refused.
         *
         * Every id here is properly based. While the four *_ToIndex functions were stubs that
         * took a small integer AS the index, a bare 1 worked; the real ones subtract a base. */
        {
            CFE_ES_AppId_t     aid;
            CFE_ES_LibId_t     lid;
            CFE_ES_TaskId_t    tid;
            CFE_ES_CounterId_t cid;
            CFE_ES_AppInfo_t   ainfo;
            CFE_ES_TaskInfo_t  tinfo;
            CFE_StatusString_t sstr;
            char               nbuf[OS_MAX_API_NAME];
            uint32             idx;
            uint32             cnt;
            uint32             runstatus;
            int32              rc;

            /* --- the reset type, straight out of the reset area ------------------------- */
            CFE_ES_Global.ResetDataPtr->ResetVars.ResetType    = CFE_PSP_RST_TYPE_PROCESSOR;
            CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype = 7;
            idx = 0;
            printf("esa_resettype type=%ld sub=%lu\n", (long)CFE_ES_GetResetType(&idx),
                   (unsigned long)idx);
            printf("esa_resettype_null type=%ld\n", (long)CFE_ES_GetResetType(NULL));

            /* --- identity, by name and by context --------------------------------------- */
            printf("esa_appidbyname rc=%ld id=%lu\n",
                   (long)CFE_ES_GetAppIDByName(&aid, "CFE_EVS"),
                   CFE_RESOURCEID_TO_ULONG(aid));
            printf("esa_appidbyname_miss rc=%ld id=%lu\n",
                   (long)CFE_ES_GetAppIDByName(&aid, "NOSUCHAPP"),
                   CFE_RESOURCEID_TO_ULONG(aid));
            printf("esa_appidbyname_null rc=%ld\n", (long)CFE_ES_GetAppIDByName(NULL, "CFE_EVS"));
            printf("esa_libidbyname_miss rc=%ld id=%lu\n",
                   (long)CFE_ES_GetLibIDByName(&lid, "NOSUCHLIB"),
                   CFE_RESOURCEID_TO_ULONG(lid));
            printf("esa_appid rc=%ld id=%lu\n", (long)CFE_ES_GetAppID(&aid),
                   CFE_RESOURCEID_TO_ULONG(aid));
            printf("esa_taskid rc=%ld id=%lu\n", (long)CFE_ES_GetTaskID(&tid),
                   CFE_RESOURCEID_TO_ULONG(tid));

            /* --- names, and the buffer-length edge -------------------------------------- */
            printf("esa_appname rc=%ld name=%s\n",
                   (long)CFE_ES_GetAppName(nbuf, aid, sizeof(nbuf)), nbuf);
            printf("esa_appname_zero rc=%ld\n", (long)CFE_ES_GetAppName(nbuf, aid, 0));
            /* A SHORT BUFFER TRUNCATES AND DOES NOT FAIL: strncpy of BufferLength-1 then a
             * terminator, so four bytes of "CFE_EVS" come back as "CFE". */
            nbuf[4] = 'Z';
            printf("esa_appname_short rc=%ld name=%s tail=%d\n",
                   (long)CFE_ES_GetAppName(nbuf, aid, 4), nbuf, (int)nbuf[4]);
            printf("esa_appname_badid rc=%ld first=%d\n",
                   (long)CFE_ES_GetAppName(nbuf, CFE_ES_APPID_C(ES_CTX_APPID(9)), sizeof(nbuf)),
                   (int)nbuf[0]);
            printf("esa_libname_badid rc=%ld\n",
                   (long)CFE_ES_GetLibName(nbuf, CFE_ES_LIBID_C(ES_LIBID(9)), sizeof(nbuf)));

            /* --- the info packets ------------------------------------------------------- */
            /* THE MODULE FIELDS ARRIVE NOW. CFE_ES_CopyModuleBasicInfo, CopyModuleStatusInfo and
             * CopyModuleAddressInfo were stubs that printed a line and filled in nothing, so this
             * probe asserted only what ES itself writes. cfe_es_apps.c is gated, so the entry
             * point, the file name, the init symbol's address and the six module address ranges
             * are real -- the three lines those stubs printed are replaced by the fields they
             * were standing in for, which is strictly more than they were worth. */
            rc = CFE_ES_GetAppInfo(&ainfo, aid);
            printf("esa_appinfo rc=%ld type=%u name=%s main=%lu kids=%lu stack=%lu prio=%u\n",
                   (long)rc, (unsigned)ainfo.Type, ainfo.Name,
                   CFE_RESOURCEID_TO_ULONG(ainfo.MainTaskId),
                   (unsigned long)ainfo.NumOfChildTasks, (unsigned long)ainfo.StackSize,
                   (unsigned)ainfo.Priority);
            printf("esa_appinfo_mod entry=%s file=%s start=%08lx valid=%u\n", ainfo.EntryPoint,
                   ainfo.FileName, (unsigned long)ainfo.StartAddress,
                   (unsigned)ainfo.AddressesAreValid);
            printf("esa_appinfo_addr code=%08lx/%08lx data=%08lx/%08lx bss=%08lx/%08lx\n",
                   (unsigned long)ainfo.CodeAddress, (unsigned long)ainfo.CodeSize,
                   (unsigned long)ainfo.DataAddress, (unsigned long)ainfo.DataSize,
                   (unsigned long)ainfo.BSSAddress, (unsigned long)ainfo.BSSSize);
            /* OS_ModuleInfo failing, and succeeding with its own `valid` flag clear: the only two
             * ways AddressesAreValid comes back false. The six addresses are written either way,
             * from a ModuleInfo this driver zeroed first -- so a failure yields zeroes rather
             * than stale values, which is the property worth asserting. */
            es_modinfo_rc = OS_ERROR;
            CFE_ES_GetAppInfo(&ainfo, aid);
            printf("esa_appinfo_infofail valid=%u code=%08lx\n",
                   (unsigned)ainfo.AddressesAreValid, (unsigned long)ainfo.CodeAddress);
            es_modinfo_rc    = OS_SUCCESS;
            es_modinfo_valid = 0;
            CFE_ES_GetAppInfo(&ainfo, aid);
            printf("esa_appinfo_notvalid valid=%u code=%08lx\n",
                   (unsigned)ainfo.AddressesAreValid, (unsigned long)ainfo.CodeAddress);
            es_modinfo_valid = 1;
            printf("esa_appinfo_null rc=%ld\n", (long)CFE_ES_GetAppInfo(NULL, aid));
            printf("esa_appinfo_badid rc=%ld\n",
                   (long)CFE_ES_GetAppInfo(&ainfo, CFE_ES_APPID_C(ES_CTX_APPID(9))));
            printf("esa_moduleinfo_app rc=%ld\n",
                   (long)CFE_ES_GetModuleInfo(&ainfo, CFE_RESOURCEID_UNWRAP(aid)));
            printf("esa_moduleinfo_bad rc=%ld\n",
                   (long)CFE_ES_GetModuleInfo(&ainfo, CFE_ResourceId_FromInteger(0x990000)));
            rc = CFE_ES_GetTaskInfo(&tinfo, tid);
            printf("esa_taskinfo rc=%ld task=%s app=%s exec=%lu stack=%lu prio=%u\n", (long)rc,
                   tinfo.TaskName, tinfo.AppName, (unsigned long)tinfo.ExecutionCounter,
                   (unsigned long)tinfo.StackSize, (unsigned)tinfo.Priority);

            /* --- the four index conversions, and the base that makes them refuse -------- */
            idx = 0xFFFF;
            printf("esa_toidx app rc=%ld idx=%lu\n", (long)CFE_ES_AppID_ToIndex(aid, &idx),
                   (unsigned long)idx);
            printf("esa_toidx app_bare rc=%ld\n",
                   (long)CFE_ES_AppID_ToIndex(CFE_ES_APPID_C(CFE_ResourceId_FromInteger(1)),
                                              &idx));
            idx = 0xFFFF;
            printf("esa_toidx lib rc=%ld idx=%lu\n",
                   (long)CFE_ES_LibID_ToIndex(CFE_ES_LIBID_C(ES_LIBID(2)), &idx),
                   (unsigned long)idx);
            idx = 0xFFFF;
            printf("esa_toidx task rc=%ld idx=%lu\n", (long)CFE_ES_TaskID_ToIndex(tid, &idx),
                   (unsigned long)idx);
            printf("esa_toidx task_undef rc=%ld\n",
                   (long)CFE_ES_TaskID_ToIndex(CFE_ES_TASKID_UNDEFINED, &idx));
            printf("esa_toidx task_nullidx rc=%ld\n", (long)CFE_ES_TaskID_ToIndex(tid, NULL));
            idx = 0xFFFF;
            printf("esa_toidx ctr rc=%ld idx=%lu\n",
                   (long)CFE_ES_CounterID_ToIndex(CFE_ES_COUNTERID_C(ES_CTRID(2)), &idx),
                   (unsigned long)idx);

            /* --- the run loop and the execution counter --------------------------------- */
            /* RunLoop bumps the CALLING TASK's counter outside the lock, sets the app state to
             * RUNNING if it is below it, and returns false the moment the control request is
             * anything but APP_RUN. */
            CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_EARLY_INIT;
            runstatus = CFE_ES_RunStatus_APP_RUN;
            printf("esa_runloop first=%d state=%u exec=%lu\n",
                   (int)CFE_ES_RunLoop(&runstatus),
                   (unsigned)CFE_ES_Global.AppTable[1].AppState,
                   (unsigned long)CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT].ExecutionCounter);
            printf("esa_runloop null=%d\n", (int)CFE_ES_RunLoop(NULL));
            runstatus = CFE_ES_RunStatus_APP_EXIT;
            printf("esa_runloop_exitreq=%d\n", (int)CFE_ES_RunLoop(&runstatus));
            /* The control request wins over the caller's status, and is handed back through it */
            CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
            runstatus = CFE_ES_RunStatus_APP_RUN;
            printf("esa_runloop_ctlreq=%d out=%u\n", (int)CFE_ES_RunLoop(&runstatus),
                   (unsigned)runstatus);
            CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            CFE_ES_IncrementTaskCounter();
            printf("esa_exec exec=%lu\n",
                   (unsigned long)CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT].ExecutionCounter);

            /* --- waiting for a system state --------------------------------------------- */
            /* Already satisfied: returns at once and still moves the caller's app state. */
            CFE_ES_Global.SystemState          = CFE_ES_SystemState_OPERATIONAL;
            CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_EARLY_INIT;
            printf("esa_wait_met rc=%ld state=%u\n",
                   (long)CFE_ES_WaitForSystemState(CFE_ES_SystemState_APPS_INIT, 0),
                   (unsigned)CFE_ES_Global.AppTable[1].AppState);
            /* Not satisfied, and the timeout is the only thing that ends it. */
            evs_delay_ms = 0;
            printf("esa_wait_timeout rc=%ld delay=%ld\n",
                   (long)CFE_ES_WaitForSystemState(CFE_ES_SystemState_SHUTDOWN, 120),
                   (long)evs_delay_ms);

            /* --- restart, reload and delete: a control request, nothing more ------------- */
            /* BACK TO RUNNING FIRST. CFE_ES_WaitForSystemState above left the app at
             * LATE_INIT, and CFE_ES_LockUserAppRecord refuses anything that is not RUNNING --
             * which is a real refusal, driven deliberately a few lines further down, so it
             * must not be the accidental state here. */
            CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_RUNNING;
            es_stat_rc = OS_SUCCESS;
            printf("esa_restart rc=%ld req=%u\n", (long)CFE_ES_RestartApp(aid),
                   (unsigned)CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
            CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            es_stat_rc = OS_ERROR;
            printf("esa_restart_nofile rc=%ld req=%u\n", (long)CFE_ES_RestartApp(aid),
                   (unsigned)CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
            es_stat_rc = OS_SUCCESS;
            printf("esa_reload rc=%ld req=%u file=%s\n",
                   (long)CFE_ES_ReloadApp(aid, "/cf/new_app.so"),
                   (unsigned)CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest,
                   CFE_ES_Global.AppTable[1].StartParams.BasicInfo.FileName);
            CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            printf("esa_reload_nullname rc=%ld\n", (long)CFE_ES_ReloadApp(aid, NULL));
            printf("esa_delete rc=%ld req=%u\n", (long)CFE_ES_DeleteApp(aid),
                   (unsigned)CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
            CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            /* THE THREE REFUSALS, each from CFE_ES_LockUserAppRecord and each with its own log
             * line: a bad id, a CORE app, and an app that is not running. */
            printf("esa_restart_badid rc=%ld\n",
                   (long)CFE_ES_RestartApp(CFE_ES_APPID_C(ES_CTX_APPID(9))));
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
            printf("esa_restart_core rc=%ld\n", (long)CFE_ES_RestartApp(aid));
            CFE_ES_Global.AppTable[1].Type     = CFE_ES_AppType_EXTERNAL;
            CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_EARLY_INIT;
            printf("esa_restart_notrunning rc=%ld\n", (long)CFE_ES_RestartApp(aid));
            CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_RUNNING;

            /* --- child tasks ------------------------------------------------------------ */
            /* CFE_ES_StartAppTask is a stub that hands back an id without making a RECORD, so
             * the delete below takes the "Task ID is not active" branch -- driven on purpose
             * rather than pretended away. */
            es_starttask_rc = CFE_SUCCESS;
            printf("esa_child rc=%ld id=%lu\n",
                   (long)CFE_ES_CreateChildTask(&tid, "KID", (CFE_ES_ChildTaskMainFuncPtr_t)
                                                CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0),
                   CFE_RESOURCEID_TO_ULONG(tid));
            printf("esa_child_nullid rc=%ld\n",
                   (long)CFE_ES_CreateChildTask(NULL, "KID", (CFE_ES_ChildTaskMainFuncPtr_t)
                                                CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0));
            printf("esa_child_nullboth rc=%ld\n",
                   (long)CFE_ES_CreateChildTask(NULL, NULL, (CFE_ES_ChildTaskMainFuncPtr_t)
                                                CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0));
            printf("esa_child_nullname rc=%ld\n",
                   (long)CFE_ES_CreateChildTask(&tid, NULL, (CFE_ES_ChildTaskMainFuncPtr_t)
                                                CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0));
            printf("esa_child_nullfn rc=%ld\n",
                   (long)CFE_ES_CreateChildTask(&tid, "KID", NULL, NULL, 2048, 70, 0));
            printf("esa_child_del_inactive rc=%ld\n", (long)CFE_ES_DeleteChildTask(tid));
            /* The main task cannot be deleted as a child: the scan finds it in the app table. */
            printf("esa_child_del_main rc=%ld\n",
                   (long)CFE_ES_DeleteChildTask(
                       CFE_ES_TaskId_FromOSAL(OS_ObjectIdFromInteger(es_os_taskid))));
            /* And ExitChildTask from the MAIN task is refused for the same reason. */
            es_taskexits = 0;
            CFE_ES_ExitChildTask();
            printf("esa_child_exit_main exits=%ld\n", (long)es_taskexits);

            /* --- the generic counters --------------------------------------------------- */
            printf("esa_ctr_reg rc=%ld id=%lu\n",
                   (long)CFE_ES_RegisterGenCounter(&cid, "ESAPICTR"),
                   CFE_RESOURCEID_TO_ULONG(cid));
            printf("esa_ctr_dup rc=%ld\n", (long)CFE_ES_RegisterGenCounter(&cid, "ESAPICTR"));
            printf("esa_ctr_longname rc=%ld\n",
                   (long)CFE_ES_RegisterGenCounter(&cid, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
            CFE_ES_GetGenCounterIDByName(&cid, "ESAPICTR");
            CFE_ES_IncrementGenCounter(cid);
            CFE_ES_IncrementGenCounter(cid);
            cnt = 0;
            printf("esa_ctr_get rc=%ld n=%lu\n", (long)CFE_ES_GetGenCount(cid, &cnt),
                   (unsigned long)cnt);
            printf("esa_ctr_set rc=%ld\n", (long)CFE_ES_SetGenCount(cid, 41));
            CFE_ES_GetGenCount(cid, &cnt);
            printf("esa_ctr_after n=%lu\n", (unsigned long)cnt);
            printf("esa_ctr_name rc=%ld name=%s\n",
                   (long)CFE_ES_GetGenCounterName(nbuf, cid, sizeof(nbuf)), nbuf);
            printf("esa_ctr_byname_miss rc=%ld\n",
                   (long)CFE_ES_GetGenCounterIDByName(&cid, "NOSUCHCTR"));
            CFE_ES_GetGenCounterIDByName(&cid, "ESAPICTR");
            printf("esa_ctr_del rc=%ld\n", (long)CFE_ES_DeleteGenCounter(cid));
            printf("esa_ctr_del_again rc=%ld\n", (long)CFE_ES_DeleteGenCounter(cid));
            printf("esa_ctr_incr_gone rc=%ld\n", (long)CFE_ES_IncrementGenCounter(cid));

            /* --- the CDS group, all of it refused because CDSIsAvailable is 0 ------------ */
            printf("esa_cds_reg rc=%ld\n", (long)CFE_ES_RegisterCDS(&idx, 64, "CDSNAME"));
            printf("esa_cds_reg_null rc=%ld\n", (long)CFE_ES_RegisterCDS(NULL, 64, "CDSNAME"));
            printf("esa_cds_byname rc=%ld\n", (long)CFE_ES_GetCDSBlockIDByName(&idx, "CDSNAME"));
            printf("esa_cds_name rc=%ld\n",
                   (long)CFE_ES_GetCDSBlockName(nbuf, CFE_ES_CDS_BAD_HANDLE, sizeof(nbuf)));
            printf("esa_cds_copy_null rc=%ld\n",
                   (long)CFE_ES_CopyToCDS(CFE_ES_CDS_BAD_HANDLE, NULL));
            printf("esa_cds_restore_null rc=%ld\n",
                   (long)CFE_ES_RestoreFromCDS(NULL, CFE_ES_CDS_BAD_HANDLE));

            /* --- the CRC, and the status string ----------------------------------------- */
            printf("esa_crc rc=%lu\n",
                   (unsigned long)CFE_ES_CalculateCRC("123456789", 9, 0, CFE_ES_CrcType_16_ARC));
            printf("esa_crc_null rc=%lu\n",
                   (unsigned long)CFE_ES_CalculateCRC(NULL, 9, 0x1234, CFE_ES_CrcType_16_ARC));
            printf("esa_crc_zerolen rc=%lu\n",
                   (unsigned long)CFE_ES_CalculateCRC("123456789", 0, 0x1234,
                                                      CFE_ES_CrcType_16_ARC));
            printf("esa_status str=%s\n", CFE_ES_StatusToString(CFE_ES_FILE_IO_ERR, &sstr));
            printf("esa_status_null isnull=%d\n", (int)(CFE_ES_StatusToString(0, NULL) == NULL));

            /* --- ProcessAsyncEvent is one line: wake the background task ----------------- */
            /* Same move: the real CFE_ES_BackgroundWakeup gives the background semaphore. */
            time_sem_gives = 0;
            CFE_ES_ProcessAsyncEvent();
            printf("esa_async gives=%ld\n", time_sem_gives);

            /* --- ResetCFE, which does not return on real hardware ----------------------- */
            /* CFE_PSP_Restart is a stub that returns, so the code AFTER it runs -- the
             * "returned" syslog line and CFE_ES_NOT_IMPLEMENTED -- which is the only way this
             * function's tail is reachable at all. */
            /* AND THE ER LOG WITNESS IS THE LOG. es_erlog_writes counted a stub;
             * cfe_es_erlog.c is gated, so what says an entry was made is ERLogEntries, which
             * CFE_ES_WriteToERLogWithContext increments -- a stronger statement, because it
             * says the entry LANDED rather than that a function was called. */
            es_restarts                              = 0;
            CFE_ES_Global.ResetDataPtr->ERLogEntries = 0;
            printf("esa_reset_proc rc=%ld restarts=%ld erlog=%u\n",
                   (long)CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_PROCESSOR), (long)es_restarts,
                   CFE_ES_Global.ResetDataPtr->ERLogEntries);
            printf("esa_reset_power rc=%ld restarts=%ld\n",
                   (long)CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_POWERON), (long)es_restarts);
            printf("esa_reset_bad rc=%ld restarts=%ld\n", (long)CFE_ES_ResetCFE(99),
                   (long)es_restarts);

            /* --- ExitApp, on the one path that comes back -------------------------------- */
            /* An EXTERNAL app spins forever and a CORE app with an init or runtime error does
             * not return either, so the only reachable path is a CORE app with some other
             * status: it logs "Cannot Exit CORE Application" and falls through to the unlock. */
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
            CFE_ES_ExitApp(CFE_ES_RunStatus_APP_EXIT);
            printf("esa_exitapp_core req=%u\n",
                   (unsigned)CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
            CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            /* An out-of-range status is DOWNGRADED to APP_ERROR with a log line, not refused */
            CFE_ES_ExitApp(CFE_ES_RunStatus_MAX + 5);
            printf("esa_exitapp_badstatus req=%u\n",
                   (unsigned)CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;

            /* Leave ES exactly as it was found, or every probe after this inherits it. */
            es_ctx_init();
            CFE_ES_Global.SystemState = CFE_ES_SystemState_UNDEFINED;
        }

        /* --- cfe_es_task.c: ES'S TASK AND ITS GROUND COMMANDS ---------------------------
         *
         * Twenty-eight functions, and almost all of them end the same way: a counter moves and
         * an event goes out. So what this block compares is mostly EVENT TEXT, which is the
         * strongest thing in this transcript -- it is the packet payload, formatted by the
         * translation and compared character for character.
         *
         * EVERY HANDLER RETURNS CFE_SUCCESS. What distinguishes a command that worked from one
         * that was refused is which of the two counters moved, so the counters are printed
         * around each group rather than the return value being trusted. */
        {
            union
            {
                CFE_ES_NoopCmd_t              Noop;
                CFE_ES_ResetCountersCmd_t     ResetCtrs;
                CFE_ES_RestartCmd_t           Restart;
                CFE_ES_SendHkCmd_t            Hk;
                CFE_ES_StartAppCmd_t          StartApp;
                CFE_ES_StopAppCmd_t           StopApp;
                CFE_ES_RestartAppCmd_t        RestartApp;
                CFE_ES_ReloadAppCmd_t         ReloadApp;
                CFE_ES_QueryOneCmd_t          QueryOne;
                CFE_ES_QueryAllCmd_t          QueryAll;
                CFE_ES_QueryAllTasksCmd_t     QueryAllTasks;
                CFE_ES_ClearSysLogCmd_t       ClearSysLog;
                CFE_ES_OverWriteSysLogCmd_t   OverWriteSysLog;
                CFE_ES_WriteSysLogCmd_t       WriteSysLog;
                CFE_ES_ClearERLogCmd_t        ClearERLog;
                CFE_ES_WriteERLogCmd_t        WriteERLog;
                CFE_ES_ResetPRCountCmd_t      ResetPRCount;
                CFE_ES_SetMaxPRCountCmd_t     SetMaxPRCount;
                CFE_ES_DeleteCDSCmd_t         DeleteCDS;
                CFE_ES_SendMemPoolStatsCmd_t  MemPoolStats;
                CFE_ES_DumpCDSRegistryCmd_t   DumpCDSReg;
            } escmd;
            CFE_ES_CDSHandle_t cdsh; /* for the CDS probes, which register real blocks now */

            /* THE BUFFER IS A UNION OF EVERY COMMAND, not of the one being built, which is the
             * lesson cfe_sb_task.c's exercise paid for: a 20-byte buffer where a handler read
             * 72 agreed with the C anyway, because the garbage happened to start with a zero. */
            memset(&escmd, 0, sizeof(escmd));

            /* --- the two trivial ones, and what they do to the counters ----------------- */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            printf("est_noop rc=%ld cc=%u ec=%u\n", (long)CFE_ES_NoopCmd(&escmd.Noop),
                   CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);
            /* ResetCounters does NOT count itself -- zeroing and then incrementing would
             * report 1, which is not what "reset" means. */
            printf("est_resetctrs rc=%ld cc=%u ec=%u\n",
                   (long)CFE_ES_ResetCountersCmd(&escmd.ResetCtrs),
                   CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);

            /* --- restart: the refusal, then the one that does not come back ------------- */
            escmd.Restart.Payload.RestartType = 99;
            printf("est_restart_bad rc=%ld ec=%u\n", (long)CFE_ES_RestartCmd(&escmd.Restart),
                   CFE_ES_Global.TaskData.CommandErrorCounter);
            es_restarts                       = 0;
            escmd.Restart.Payload.RestartType = CFE_PSP_RST_TYPE_PROCESSOR;
            printf("est_restart_ok rc=%ld restarts=%ld cc=%u\n",
                   (long)CFE_ES_RestartCmd(&escmd.Restart), (long)es_restarts,
                   CFE_ES_Global.TaskData.CommandCounter);

            /* --- housekeeping, the widest packet in the module -------------------------- */
            CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount    = 3;
            CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = 7;
            CFE_ES_Global.ResetDataPtr->ResetVars.BootSource             = 2;
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.State              = 1;
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.Mode               = 1;
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.TriggerCount       = 11;
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.TriggerMask[0]     = 0x81;
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask[1]      = 0x42;
            es_perf_remaining                                            = 9;
            es_heap_rc                                                   = OS_SUCCESS;
            sb_tx_reset();
            printf("est_hk rc=%ld tx=%d\n", (long)CFE_ES_SendHkCmd(&escmd.Hk), sb_tx_since());
            printf("est_hk_p1 cc=%u ec=%u logbytes=%lu logsize=%lu entries=%u mode=%u\n",
                   CFE_ES_Global.TaskData.HkPacket.Payload.CommandCounter,
                   CFE_ES_Global.TaskData.HkPacket.Payload.CommandErrorCounter,
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.SysLogBytesUsed,
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.SysLogSize,
                   CFE_ES_Global.TaskData.HkPacket.Payload.SysLogEntries,
                   CFE_ES_Global.TaskData.HkPacket.Payload.SysLogMode);
            printf("est_hk_p2 apps=%u/%u tasks=%u libs=%u rst=%u/%u pr=%u/%u boot=%u\n",
                   CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredCoreApps,
                   CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredExternalApps,
                   CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredTasks,
                   CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredLibs,
                   CFE_ES_Global.TaskData.HkPacket.Payload.ResetType,
                   CFE_ES_Global.TaskData.HkPacket.Payload.ResetSubtype,
                   CFE_ES_Global.TaskData.HkPacket.Payload.ProcessorResets,
                   CFE_ES_Global.TaskData.HkPacket.Payload.MaxProcessorResets,
                   CFE_ES_Global.TaskData.HkPacket.Payload.BootSource);
            printf("est_hk_p3 perf=%u/%u trig=%u towrite=%u tmask0=%02x fmask1=%02x\n",
                   CFE_ES_Global.TaskData.HkPacket.Payload.PerfState,
                   CFE_ES_Global.TaskData.HkPacket.Payload.PerfMode,
                   CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerCount,
                   CFE_ES_Global.TaskData.HkPacket.Payload.PerfDataToWrite,
                   CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerMask[0],
                   CFE_ES_Global.TaskData.HkPacket.Payload.PerfFilterMask[1]);
            printf("est_hk_p4 heapfree=%lu blocks=%lu largest=%lu\n",
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.HeapBytesFree,
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.HeapBlocksFree,
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.HeapMaxBlockSize);
            /* A heap the OSAL cannot report gives three zeroes, not a missing packet. */
            es_heap_rc = OS_ERROR;
            CFE_ES_SendHkCmd(&escmd.Hk);
            printf("est_hk_noheap free=%lu blocks=%lu largest=%lu\n",
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.HeapBytesFree,
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.HeapBlocksFree,
                   (unsigned long)CFE_ES_Global.TaskData.HkPacket.Payload.HeapMaxBlockSize);
            es_heap_rc = OS_SUCCESS;

            /* --- StartApp: five refusals and the success -------------------------------- */
            /* THE EVENT TEXT IS THE COMPARISON for each of the six, and the counters below are
             * the second witness: a change that moved a branch without changing its wording
             * would show up there and nowhere else. */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            strncpy(escmd.StartApp.Payload.Application, "NEWAPP",
                    sizeof(escmd.StartApp.Payload.Application) - 1);
            strncpy(escmd.StartApp.Payload.AppEntryPoint, "NEWAPP_Main",
                    sizeof(escmd.StartApp.Payload.AppEntryPoint) - 1);
            strncpy(escmd.StartApp.Payload.AppFileName, "newapp",
                    sizeof(escmd.StartApp.Payload.AppFileName) - 1);
            escmd.StartApp.Payload.StackSize       = 0; /* means "use the default" */
            escmd.StartApp.Payload.Priority        = 80;
            escmd.StartApp.Payload.ExceptionAction = CFE_ES_ExceptionAction_RESTART_APP;
            /* CFE_ES_AppCreate IS REAL NOW, so a creation failure has to be made to happen
             * rather than returned: the module load is what fails. That also means the success
             * path below now runs the whole lifecycle -- OS_ModuleLoad, a symbol lookup, a task
             * record -- and the app really does end up in the app table, which is why the
             * counters at the end of this block moved. */
            printf("est_startapp rc=%ld\n", (long)CFE_ES_StartAppCmd(&escmd.StartApp));
            es_modload_rc = OS_ERROR;
            printf("est_startapp_createfail rc=%ld\n",
                   (long)CFE_ES_StartAppCmd(&escmd.StartApp));
            es_modload_rc = OS_SUCCESS;
            escmd.StartApp.Payload.Priority = 255 + 1; /* > OS_MAX_PRIORITY, but the field is u16 */
            printf("est_startapp_prio rc=%ld\n", (long)CFE_ES_StartAppCmd(&escmd.StartApp));
            escmd.StartApp.Payload.Priority        = 80;
            escmd.StartApp.Payload.ExceptionAction = 9;
            printf("est_startapp_exc rc=%ld\n", (long)CFE_ES_StartAppCmd(&escmd.StartApp));
            escmd.StartApp.Payload.ExceptionAction = CFE_ES_ExceptionAction_RESTART_APP;
            escmd.StartApp.Payload.AppEntryPoint[0] = 0;
            printf("est_startapp_noentry rc=%ld\n", (long)CFE_ES_StartAppCmd(&escmd.StartApp));
            strncpy(escmd.StartApp.Payload.AppEntryPoint, "NEWAPP_Main",
                    sizeof(escmd.StartApp.Payload.AppEntryPoint) - 1);
            escmd.StartApp.Payload.Application[0] = 0;
            printf("est_startapp_noname rc=%ld\n", (long)CFE_ES_StartAppCmd(&escmd.StartApp));
            printf("est_startapp_ctrs cc=%u ec=%u loads=%ld\n",
                   CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter, es_modloads);

            /* --- stop, restart and reload, by NAME this time ---------------------------- */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            memset(&escmd, 0, sizeof(escmd));
            strncpy(escmd.StopApp.Payload.Application, "OTHER_APP",
                    sizeof(escmd.StopApp.Payload.Application) - 1);
            printf("est_stopapp rc=%ld\n", (long)CFE_ES_StopAppCmd(&escmd.StopApp));
            CFE_ES_Global.AppTable[2].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            strncpy(escmd.StopApp.Payload.Application, "NOSUCHAPP",
                    sizeof(escmd.StopApp.Payload.Application) - 1);
            printf("est_stopapp_miss rc=%ld\n", (long)CFE_ES_StopAppCmd(&escmd.StopApp));
            strncpy(escmd.RestartApp.Payload.Application, "OTHER_APP",
                    sizeof(escmd.RestartApp.Payload.Application) - 1);
            es_stat_rc = OS_SUCCESS;
            printf("est_restartapp rc=%ld\n", (long)CFE_ES_RestartAppCmd(&escmd.RestartApp));
            CFE_ES_Global.AppTable[2].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            es_stat_rc = OS_ERROR;
            printf("est_restartapp_nofile rc=%ld\n",
                   (long)CFE_ES_RestartAppCmd(&escmd.RestartApp));
            es_stat_rc = OS_SUCCESS;
            strncpy(escmd.RestartApp.Payload.Application, "NOSUCHAPP",
                    sizeof(escmd.RestartApp.Payload.Application) - 1);
            printf("est_restartapp_miss rc=%ld\n",
                   (long)CFE_ES_RestartAppCmd(&escmd.RestartApp));
            memset(&escmd, 0, sizeof(escmd));
            strncpy(escmd.ReloadApp.Payload.Application, "OTHER_APP",
                    sizeof(escmd.ReloadApp.Payload.Application) - 1);
            strncpy(escmd.ReloadApp.Payload.AppFileName, "other_v2",
                    sizeof(escmd.ReloadApp.Payload.AppFileName) - 1);
            printf("est_reloadapp rc=%ld file=%s\n", (long)CFE_ES_ReloadAppCmd(&escmd.ReloadApp),
                   CFE_ES_Global.AppTable[2].StartParams.BasicInfo.FileName);
            CFE_ES_Global.AppTable[2].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
            strncpy(escmd.ReloadApp.Payload.Application, "NOSUCHAPP",
                    sizeof(escmd.ReloadApp.Payload.Application) - 1);
            printf("est_reloadapp_miss rc=%ld\n", (long)CFE_ES_ReloadAppCmd(&escmd.ReloadApp));
            printf("est_appctl_ctrs cc=%u ec=%u\n", CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);

            /* --- the three queries ------------------------------------------------------ */
            memset(&escmd, 0, sizeof(escmd));
            strncpy(escmd.QueryOne.Payload.Application, "CFE_EVS",
                    sizeof(escmd.QueryOne.Payload.Application) - 1);
            sb_tx_reset();
            printf("est_queryone rc=%ld tx=%d name=%s\n",
                   (long)CFE_ES_QueryOneCmd(&escmd.QueryOne), sb_tx_since(),
                   CFE_ES_Global.TaskData.OneAppPacket.Payload.AppInfo.Name);
            strncpy(escmd.QueryOne.Payload.Application, "NOSUCHAPP",
                    sizeof(escmd.QueryOne.Payload.Application) - 1);
            printf("est_queryone_miss rc=%ld\n", (long)CFE_ES_QueryOneCmd(&escmd.QueryOne));
            memset(&escmd, 0, sizeof(escmd));
            fs_len = 0;
            fs_pos = 0;
            printf("est_queryall rc=%ld len=%ld\n", (long)CFE_ES_QueryAllCmd(&escmd.QueryAll),
                   (long)fs_len);
            fs_open_fail = 1;
            printf("est_queryall_nocreate rc=%ld\n", (long)CFE_ES_QueryAllCmd(&escmd.QueryAll));
            fs_open_fail = 0;
            fs_len       = 0;
            fs_pos       = 0;
            printf("est_queryalltasks rc=%ld len=%ld\n",
                   (long)CFE_ES_QueryAllTasksCmd(&escmd.QueryAllTasks), (long)fs_len);
            fs_open_fail = 1;
            printf("est_queryalltasks_nocreate rc=%ld\n",
                   (long)CFE_ES_QueryAllTasksCmd(&escmd.QueryAllTasks));
            fs_open_fail = 0;

            /* --- the system log and the ER log ------------------------------------------ */
            CFE_ES_WriteToSysLog("a line to clear\n");
            printf("est_clearsyslog rc=%ld entries=%u\n",
                   (long)CFE_ES_ClearSysLogCmd(&escmd.ClearSysLog),
                   CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
            escmd.OverWriteSysLog.Payload.Mode = CFE_ES_LogMode_DISCARD;
            printf("est_overwrite rc=%ld mode=%u\n",
                   (long)CFE_ES_OverWriteSysLogCmd(&escmd.OverWriteSysLog),
                   CFE_ES_Global.ResetDataPtr->SystemLogMode);
            escmd.OverWriteSysLog.Payload.Mode = 99;
            printf("est_overwrite_bad rc=%ld mode=%u\n",
                   (long)CFE_ES_OverWriteSysLogCmd(&escmd.OverWriteSysLog),
                   CFE_ES_Global.ResetDataPtr->SystemLogMode);
            memset(&escmd, 0, sizeof(escmd));
            fs_len = 0;
            fs_pos = 0;
            printf("est_writesyslog rc=%ld len=%ld\n",
                   (long)CFE_ES_WriteSysLogCmd(&escmd.WriteSysLog), (long)fs_len);
            CFE_ES_Global.ResetDataPtr->ERLogIndex   = 5;
            CFE_ES_Global.ResetDataPtr->ERLogEntries = 5;
            printf("est_clearerlog rc=%ld idx=%u entries=%u\n",
                   (long)CFE_ES_ClearERLogCmd(&escmd.ClearERLog),
                   CFE_ES_Global.ResetDataPtr->ERLogIndex,
                   CFE_ES_Global.ResetDataPtr->ERLogEntries);
            /* The ER log dump is BACKGROUND work: the command only queues it, and asking
             * twice is a distinct error with its own event. */
            /* THE RETURN VALUE SAYS NOTHING HERE and that is worth stating once: every
             * handler in this file returns CFE_SUCCESS whatever happens, because the return
             * goes to the dispatcher, which only cares that the handler ran. The witnesses are
             * the two counters and the event. The FS background queue is four deep and the FS
             * section above has already used it, so whether the request is ACCEPTED depends on
             * what that left behind -- which is why the queue is drained first. */
            memset(&CFE_ES_Global.BackgroundERLogDumpState, 0,
                   sizeof(CFE_ES_Global.BackgroundERLogDumpState));
            memset(&CFE_FS_Global.FileDump, 0, sizeof(CFE_FS_Global.FileDump));
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            CFE_ES_WriteERLogCmd(&escmd.WriteERLog);
            printf("est_writeerlog cc=%u ec=%u pending=%d sub=%u getdata=%d onevent=%d file=%s\n",
                   CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter,
                   (int)CFE_ES_Global.BackgroundERLogDumpState.FileWrite.IsPending,
                   CFE_ES_Global.BackgroundERLogDumpState.FileWrite.FileSubType,
                   (int)(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.GetData != NULL),
                   (int)(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.OnEvent != NULL),
                   CFE_ES_Global.BackgroundERLogDumpState.FileWrite.FileName);
            /* And asking again while it is pending is a DISTINCT error with its own event. */
            CFE_ES_WriteERLogCmd(&escmd.WriteERLog);
            printf("est_writeerlog_again cc=%u ec=%u\n", CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);

            /* --- the processor reset counts --------------------------------------------- */
            printf("est_resetpr rc=%ld count=%u\n",
                   (long)CFE_ES_ResetPRCountCmd(&escmd.ResetPRCount),
                   CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount);
            escmd.SetMaxPRCount.Payload.MaxPRCount = 12;
            printf("est_setmaxpr rc=%ld max=%u\n",
                   (long)CFE_ES_SetMaxPRCountCmd(&escmd.SetMaxPRCount),
                   CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount);

            /* --- the CDS, whose four refusals each have their own event ------------------ */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            memset(&escmd, 0, sizeof(escmd));
            /* THE FOUR REFUSALS ARE REAL NOW. Until cfe_es_cds.c was gated these five probes
             * steered es_cdsdelete_rc on a stub, so all five asserted the same thing: that the
             * command handler turns whatever CFE_ES_DeleteCDS returns into the right event and
             * counter. That is worth one probe, not five. Each refusal below is now produced by
             * setting up the CDS so the real function has to reach it.
             *
             * The CDS has to exist first, which also means these probes run against the real
             * store: CFE_ES_CDS_EarlyInit wipes it, writes the signatures, creates the pool and
             * writes an empty registry. */
            printf("est_cds_init rc=%ld avail=%d\n", (long)CFE_ES_CDS_EarlyInit(),
                   (int)CFE_ES_Global.CDSIsAvailable);
            /* A block owned by an app that is not registered -- "APP" is not in the app table,
             * which is the condition CFE_ES_DeleteCDS inverts: a FAILED lookup means the owner
             * is gone and the block may go. */
            printf("est_cds_reg rc=%ld\n",
                   (long)CFE_ES_RegisterCDSEx(&cdsh, 64, "APP.TBL", false));
            strncpy(escmd.DeleteCDS.Payload.CdsName, "APP.TBL",
                    sizeof(escmd.DeleteCDS.Payload.CdsName) - 1);
            printf("est_deletecds rc=%ld\n", (long)CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS));
            /* Registered as a CRITICAL TABLE, so an ES command may not delete it: the Table flag
             * and the caller's claim about who it is have to agree. */
            printf("est_cds_reg_tbl rc=%ld\n",
                   (long)CFE_ES_RegisterCDSEx(&cdsh, 64, "APP.TBL", true));
            printf("est_deletecds_tbl rc=%ld\n", (long)CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS));
            /* Owned by an app that IS registered. "CFE_EVS" is app slot 1, and the owner name is
             * whatever precedes the dot. */
            printf("est_cds_reg_active rc=%ld\n",
                   (long)CFE_ES_RegisterCDSEx(&cdsh, 64, "CFE_EVS.TBL", false));
            strncpy(escmd.DeleteCDS.Payload.CdsName, "CFE_EVS.TBL",
                    sizeof(escmd.DeleteCDS.Payload.CdsName) - 1);
            printf("est_deletecds_active rc=%ld\n", (long)CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS));
            /* No such name in the registry. */
            strncpy(escmd.DeleteCDS.Payload.CdsName, "NO.SUCH",
                    sizeof(escmd.DeleteCDS.Payload.CdsName) - 1);
            printf("est_deletecds_miss rc=%ld\n", (long)CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS));
            /* A store that refuses the registry write-back, which is the last step of a delete
             * that otherwise succeeded -- the block is freed and the registry is not updated, so
             * the error comes out of CFE_ES_UpdateCDSRegistry and the log line is written after
             * the CDS lock is released. */
            printf("est_cds_reg_err rc=%ld\n",
                   (long)CFE_ES_RegisterCDSEx(&cdsh, 64, "OTHER.TBL", false));
            strncpy(escmd.DeleteCDS.Payload.CdsName, "OTHER.TBL",
                    sizeof(escmd.DeleteCDS.Payload.CdsName) - 1);
            es_cds_write_rc = CFE_PSP_ERROR;
            printf("est_deletecds_err rc=%ld\n", (long)CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS));
            es_cds_write_rc = CFE_PSP_SUCCESS;
            printf("est_deletecds_ctrs cc=%u ec=%u\n", CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);
            /* The registry dump walks a registry that is empty here, which is the case the
             * pre-loaded OsStatus makes report SUCCESS. */
            memset(&escmd, 0, sizeof(escmd));
            fs_len = 0;
            fs_pos = 0;
            printf("est_dumpcdsreg rc=%ld len=%ld\n",
                   (long)CFE_ES_DumpCDSRegistryCmd(&escmd.DumpCDSReg), (long)fs_len);
            fs_open_fail = 1;
            printf("est_dumpcdsreg_nocreate rc=%ld\n",
                   (long)CFE_ES_DumpCDSRegistryCmd(&escmd.DumpCDSReg));
            fs_open_fail = 0;

            /* --- the memory pool statistics --------------------------------------------- */
            memset(&escmd, 0, sizeof(escmd));
            escmd.MemPoolStats.Payload.PoolHandle = CFE_SB_Global.Mem.PoolHdl;
            sb_tx_reset();
            printf("est_mempoolstats rc=%ld tx=%d handle=%lu size=%lu\n",
                   (long)CFE_ES_SendMemPoolStatsCmd(&escmd.MemPoolStats), sb_tx_since(),
                   CFE_RESOURCEID_TO_ULONG(CFE_ES_Global.TaskData.MemStatsPacket.Payload.PoolHandle),
                   (unsigned long)CFE_ES_Global.TaskData.MemStatsPacket.Payload.PoolStats.PoolSize);
            escmd.MemPoolStats.Payload.PoolHandle = CFE_ES_MEMHANDLE_C(ES_CTX_APPID(9));
            printf("est_mempoolstats_bad rc=%ld\n",
                   (long)CFE_ES_SendMemPoolStatsCmd(&escmd.MemPoolStats));

            /* --- the short-write reporter, now a real event ----------------------------- */
            CFE_ES_FileWriteByteCntErr("/ram/x.log", 64, -7);

            /* --- CFE_ES_TaskMain, which DOES come back ---------------------------------- */
            /* The loop exits when CFE_SB_ReceiveBuffer fails, and OS_QueueGet returns
             * OS_QUEUE_EMPTY on an empty pipe -- so one pass, then CFE_ES_ExitApp. The caller
             * must be a CORE app for that to return: an EXTERNAL one spins forever in
             * `while (1) OS_TaskDelay(500)`. SystemState is set to CORE_READY first so the
             * WaitForSystemState before the loop does not spend 30,000 ms of simulated delay.
             */
            CFE_ES_Global.SystemState      = CFE_ES_SystemState_CORE_READY;
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
            es_taskpipes                   = 0;
            /* CFE_ES_BackgroundInit is real now, so what says it ran is the semaphore it
             * creates -- time_sems_created -- not a counter in a stub that no longer exists. */
            time_sems_created              = 0;
            es_taskexits                   = 0;
            evs_delay_ms                   = 0;
            sb_queuecreate_rc              = OS_SUCCESS;
            es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
            CFE_ES_TaskMain();
            printf("est_taskmain pipes=%ld bgsem=%ld exits=%ld delay=%ld req=%u\n",
                   es_taskpipes, time_sems_created, (long)es_taskexits, (long)evs_delay_ms,
                   CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;

            /* Leave ES as it was found. */
            es_ctx_init();
            CFE_ES_Global.SystemState = CFE_ES_SystemState_UNDEFINED;
        }

        /* --- cfe_es_perf.c and cfe_es_dispatch.c -----------------------------------------
         *
         * The performance log is the only part of ES that writes a file through a STATE
         * MACHINE rather than in one call, so the interesting thing to drive is the machine:
         * eleven states, a work credit that bounds how many run per pass, and a mutex held
         * from LOCK_DATA to UNLOCK_DATA.
         *
         * AND THE DISPATCHER IS THE FIRST TIME ES'S COMMANDS ARRIVE AS MESSAGES. Everything in
         * the est_ block above called a handler directly; these go in through CFE_ES_TaskPipe
         * with a message id, a function code and a length, which is the only path a real
         * ground command takes. */
        {
            union
            {
                CFE_SB_Buffer_t              Buf;
                CFE_ES_NoopCmd_t             Noop;
                CFE_ES_StartPerfDataCmd_t    StartPerf;
                CFE_ES_StopPerfDataCmd_t     StopPerf;
                CFE_ES_SetPerfFilterMaskCmd_t  FiltMask;
                CFE_ES_SetPerfTriggerMaskCmd_t TrigMask;
            } pc;
            CFE_ES_PerfData_t       *Perf  = &CFE_ES_Global.ResetDataPtr->Perf;
            CFE_ES_PerfDumpGlobal_t *PDump = &CFE_ES_Global.BackgroundPerfDumpState;
            int k;

            memset(&pc, 0, sizeof(pc));
            memset(PDump, 0, sizeof(*PDump));

            /* --- SetupPerfVariables: a POWER-ON reset initialises, a processor reset does not */
            memset(Perf, 0, sizeof(*Perf));
            CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
            printf("esp_setup_por ver=%u endian=%u ticks=%lu roll=%lu state=%u mode=%u masksz=%u\n",
                   Perf->MetaData.Version, Perf->MetaData.Endian,
                   (unsigned long)Perf->MetaData.TimerTicksPerSecond,
                   (unsigned long)Perf->MetaData.TimerLow32Rollover, Perf->MetaData.State,
                   Perf->MetaData.Mode, Perf->MetaData.FilterTriggerMaskSize);
            printf("esp_setup_por_masks filt0=%02x filt15=%02x trig0=%02x\n",
                   Perf->MetaData.FilterMask[0], Perf->MetaData.FilterMask[15],
                   Perf->MetaData.TriggerMask[0]);
            /* A processor reset touches ONE field -- the log survives, which is the point. */
            Perf->MetaData.Version     = 7;
            Perf->MetaData.TriggerCount = 99;
            CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_PROCESSOR);
            printf("esp_setup_pr ver=%u trig=%lu state=%u\n", Perf->MetaData.Version,
                   (unsigned long)Perf->MetaData.TriggerCount, Perf->MetaData.State);
            CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);

            /* --- the capture path, through CFE_ES_PerfLogAdd ---------------------------- */
            /* Idle: the first check in PerfLogAdd, which does not even take the lock. */
            /* THE PERF LOG'S LOCK IS A MUTEX, not a binary semaphore, so the witness for
              * "did it take the lock" is fs_mut_take -- what OS_MutSemTake counts. Reading
              * time_sem_takes here would have been a zero against a zero. */
            fs_mut_take = 0;
            CFE_ES_PerfLogAdd(3, 0);
            printf("esp_add_idle count=%lu takes=%d\n", (unsigned long)Perf->MetaData.DataCount,
                   fs_mut_take);
            /* Armed, with an all-ones filter mask and an all-zero trigger mask: entries are
             * recorded and nothing triggers, so DataCount climbs and State stays WAITING. */
            pc.StartPerf.Payload.TriggerMode = CFE_ES_PerfTrigger_START;
            CFE_ES_StartPerfDataCmd(&pc.StartPerf);
            es_perf_tb = 0;
            CFE_ES_PerfLogAdd(3, 0);
            CFE_ES_PerfLogAdd(3, 1);
            CFE_ES_PerfLogAdd(4, 0);
            printf("esp_add_armed count=%lu end=%lu start=%lu state=%u\n",
                   (unsigned long)Perf->MetaData.DataCount, (unsigned long)Perf->MetaData.DataEnd,
                   (unsigned long)Perf->MetaData.DataStart, Perf->MetaData.State);
            /* THE ENTRY WORD CARRIES THE MARKER AND THE EXIT BIT, which is the one piece of
             * bit-packing in the module: marker | (EntryExit << 31). */
            printf("esp_entries e0=%08lx t0=%lu e1=%08lx t1=%lu\n",
                   (unsigned long)Perf->DataBuffer[0].Data,
                   (unsigned long)Perf->DataBuffer[0].TimerLower32,
                   (unsigned long)Perf->DataBuffer[1].Data,
                   (unsigned long)Perf->DataBuffer[1].TimerLower32);
            /* A FILTERED marker is dropped before the lock. */
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask[0] = 0x00;
            fs_mut_take                                             = 0;
            CFE_ES_PerfLogAdd(3, 0);
            printf("esp_add_filtered count=%lu takes=%d\n",
                   (unsigned long)Perf->MetaData.DataCount, fs_mut_take);
            CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask[0] = 0xFF;
            /* AN OUT-OF-RANGE MARKER COMPLAINS ONCE, then is latched silent -- the second call
             * produces no syslog line at all, which is the behaviour worth pinning. */
            CFE_ES_PerfLogAdd(CFE_MISSION_ES_PERF_MAX_IDS, 0);
            CFE_ES_PerfLogAdd(CFE_MISSION_ES_PERF_MAX_IDS + 5, 0);
            printf("esp_add_badmarker reported=%d count=%lu\n",
                   (int)Perf->MetaData.InvalidMarkerReported,
                   (unsigned long)Perf->MetaData.DataCount);
            Perf->MetaData.InvalidMarkerReported = false;
            /* THE TRIGGER, in END mode: the first triggering marker stops the capture. */
            CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
            pc.StartPerf.Payload.TriggerMode = CFE_ES_PerfTrigger_END;
            CFE_ES_StartPerfDataCmd(&pc.StartPerf);
            Perf->MetaData.TriggerMask[0] = 0x10; /* marker 4 triggers */
            CFE_ES_PerfLogAdd(3, 0);
            printf("esp_trig_pre state=%u trigs=%lu\n", Perf->MetaData.State,
                   (unsigned long)Perf->MetaData.TriggerCount);
            CFE_ES_PerfLogAdd(4, 0);
            printf("esp_trig_end state=%u trigs=%lu count=%lu\n", Perf->MetaData.State,
                   (unsigned long)Perf->MetaData.TriggerCount,
                   (unsigned long)Perf->MetaData.DataCount);

            /* --- the two mask commands, in range and out ------------------------------- */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            pc.FiltMask.Payload.FilterMaskNum = 2;
            pc.FiltMask.Payload.FilterMask    = 0x5A;
            CFE_ES_SetPerfFilterMaskCmd(&pc.FiltMask);
            pc.FiltMask.Payload.FilterMaskNum = CFE_ES_PERF_8BIT_WORDS_IN_MASK;
            CFE_ES_SetPerfFilterMaskCmd(&pc.FiltMask);
            pc.TrigMask.Payload.TriggerMaskNum = 3;
            pc.TrigMask.Payload.TriggerMask    = 0xA5;
            CFE_ES_SetPerfTriggerMaskCmd(&pc.TrigMask);
            pc.TrigMask.Payload.TriggerMaskNum = 99;
            CFE_ES_SetPerfTriggerMaskCmd(&pc.TrigMask);
            printf("esp_masks filt2=%02x trig3=%02x cc=%u ec=%u\n", Perf->MetaData.FilterMask[2],
                   Perf->MetaData.TriggerMask[3], CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);

            /* --- Start and Stop, and the "write in progress" refusal ------------------- */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            pc.StartPerf.Payload.TriggerMode = 99; /* > END */
            CFE_ES_StartPerfDataCmd(&pc.StartPerf);
            pc.StartPerf.Payload.TriggerMode = CFE_ES_PerfTrigger_CENTER;
            CFE_ES_StartPerfDataCmd(&pc.StartPerf);
            printf("esp_start mode=%u state=%u cc=%u ec=%u\n", Perf->MetaData.Mode,
                   Perf->MetaData.State, CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);
            /* PendingState non-IDLE is what "a write is in progress" means to both commands. */
            PDump->PendingState = CFE_ES_PerfDumpState_INIT;
            CFE_ES_StartPerfDataCmd(&pc.StartPerf);
            CFE_ES_StopPerfDataCmd(&pc.StopPerf);
            printf("esp_busy cc=%u ec=%u\n", CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);
            PDump->PendingState = CFE_ES_PerfDumpState_IDLE;

            /* --- THE DUMP, one state at a time -------------------------------------------
             * Stop queues it; then each RunPerfLogDump call is given exactly enough credit to
             * advance, and the state is printed after each so the machine's path is in the
             * transcript rather than only its result. */
            memset(PDump, 0, sizeof(*PDump));
            Perf->MetaData.DataCount = 3;
            Perf->MetaData.DataStart = 0;
            fs_len                   = 0;
            fs_pos                   = 0;
            fs_mut_take              = 0;
            fs_mut_give              = 0;
            /* THE UNION BITES HERE and it is worth the comment: StartPerfCmd's TriggerMode is a
             * uint32 at payload offset 0 and StopPerfCmd's DataFileName is a char[64] at the
             * same offset, so setting the trigger mode above left a one-byte control character
             * as the filename -- and the dump went to "/ram/\001" rather than to the default.
             * Both halves agreed, because both had the same garbage. */
            memset(&pc, 0, sizeof(pc));
            CFE_ES_StopPerfDataCmd(&pc.StopPerf);
            printf("esp_stop pending=%u file=%s cc=%u\n", PDump->PendingState,
                   PDump->DataFileName, CFE_ES_Global.TaskData.CommandCounter);
            /* ElapsedTime 0 earns no credit, so the machine does not move at all. */
            printf("esp_dump_nocredit active=%d cur=%u\n", (int)CFE_ES_RunPerfLogDump(0, PDump),
                   PDump->CurrentState);
            for (k = 0; k < 8; k++)
            {
                printf("esp_dump[%d] active=%d cur=%u pend=%u ctr=%lu pos=%lu size=%lu\n", k,
                       (int)CFE_ES_RunPerfLogDump(1, PDump), PDump->CurrentState,
                       PDump->PendingState, (unsigned long)PDump->StateCounter,
                       (unsigned long)PDump->DataPos, (unsigned long)PDump->FileSize);
            }
            /* takes/gives are the PERF mutex, held from LOCK_DATA to UNLOCK_DATA -- several
              * states apart, which is the thing NASA flags at CFE_ES_PerfLogAdd. */
            printf("esp_dump_done len=%ld takes=%d gives=%d remaining=%lu\n", (long)fs_len,
                   fs_mut_take, fs_mut_give,
                   (unsigned long)CFE_ES_GetPerfLogDumpRemaining());
            /* And a dump whose file will not open goes straight back to IDLE. */
            memset(PDump, 0, sizeof(*PDump));
            fs_open_fail = 1;
            CFE_ES_StopPerfDataCmd(&pc.StopPerf);
            CFE_ES_RunPerfLogDump(1000, PDump);
            printf("esp_dump_nocreate cur=%u\n", PDump->CurrentState);
            fs_open_fail = 0;
            memset(PDump, 0, sizeof(*PDump));

            /* --- the dispatcher: a length check, twenty-four codes and three message ids -- */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            memset(&pc, 0, sizeof(pc));
            CFE_MSG_Init(&pc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_ES_CMD_MID),
                         sizeof(CFE_ES_NoopCmd_t));
            /* A GOOD length, then a bad one: the bad one never reaches a handler. */
            CFE_MSG_SetFcnCode(&pc.Buf.Msg, CFE_ES_NOOP_CC);
            CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t));
            CFE_ES_ProcessGroundCmd(&pc.Buf);
            CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t) + 4);
            CFE_ES_ProcessGroundCmd(&pc.Buf);
            printf("esp_len cc=%u ec=%u\n", CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);
            /* An unknown code, which is the dispatcher's own event. */
            CFE_MSG_SetFcnCode(&pc.Buf.Msg, 99);
            CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t));
            CFE_ES_ProcessGroundCmd(&pc.Buf);
            printf("esp_badcc ec=%u\n", CFE_ES_Global.TaskData.CommandErrorCounter);
            /* EVERY CODE WITH A DELIBERATELY WRONG LENGTH. What this pins is the TABLE -- that
             * each code maps to the type the handler expects -- and it does it without running
             * twenty-four handlers, because the length check fires first and names the
             * expected size in its event. A code mapped to the wrong type shows up as a
             * different "Expected =" number. */
            /* NINE BYTES, NOT ONE. A size of 1 is below the CCSDS header minimum and
              * CFE_MSG_SetSize refuses it, leaving the previous size in place -- which was
              * sizeof(CFE_ES_NoopCmd_t), so the six no-argument commands PASSED the length
              * check and ran, and the error count came out 20 instead of 25. Nine is a legal
              * size that no ES command has: the smallest payload is two bytes, so the
              * smallest command with one is ten. */
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t) + 1);
            for (k = 0; k <= 24; k++)
            {
                CFE_MSG_SetFcnCode(&pc.Buf.Msg, k);
                CFE_ES_ProcessGroundCmd(&pc.Buf);
            }
            printf("esp_alllen ec=%u\n", CFE_ES_Global.TaskData.CommandErrorCounter);
            /* TaskPipe: the housekeeping id, the command id, and one that is neither. */
            CFE_ES_Global.TaskData.CommandCounter      = 0;
            CFE_ES_Global.TaskData.CommandErrorCounter = 0;
            CFE_MSG_SetFcnCode(&pc.Buf.Msg, CFE_ES_NOOP_CC);
            CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t));
            CFE_MSG_SetMsgId(&pc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_ES_SEND_HK_MID));
            sb_tx_reset();
            CFE_ES_TaskPipe(&pc.Buf);
            printf("esp_pipe_hk tx=%d\n", sb_tx_since());
            CFE_MSG_SetMsgId(&pc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_ES_CMD_MID));
            CFE_ES_TaskPipe(&pc.Buf);
            CFE_MSG_SetMsgId(&pc.Buf.Msg, CFE_SB_ValueToMsgId(0x1FFF));
            CFE_ES_TaskPipe(&pc.Buf);
            printf("esp_pipe cc=%u ec=%u\n", CFE_ES_Global.TaskData.CommandCounter,
                   CFE_ES_Global.TaskData.CommandErrorCounter);

            /* Leave the perf log idle, or the next probe's PerfLogAdd calls start recording. */
            CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
            memset(PDump, 0, sizeof(*PDump));
        }

        /* --- cfe_es_startupscript.c: HOW A SPACECRAFT DECIDES WHAT TO RUN ---------------
         *
         * Eight comma-separated fields terminated by a semicolon, and this is the only thing
         * between a text file and the set of applications a flight computer boots with. The
         * parser is deliberately forgiving and every allowance is a decision about what a
         * half-written script does to a vehicle, so each one is driven here.
         *
         * The script is staged into the simulated file system and read back through
         * OS_OpenCreate/OS_read -- which is what made the read-only open stop truncating. */
        {
            const char *tok[CFE_ES_STARTSCRIPT_MAX_TOKENS_PER_LINE + 1];

            es_objs_clear();
            es_modload_rc = OS_SUCCESS;

            /* --- CFE_ES_ParseFileEntry: the two entry types and every refusal ---------- */
            /* A CFE_APP line. The priority, stack size and exception action come out of the
             * text through StrToUL, which is why "0x40" and "16384" both work. */
            tok[0] = "CFE_APP";
            tok[1] = "/cf/sch.so";
            tok[2] = "SCH_AppMain";
            tok[3] = "SCH";
            tok[4] = "0x40";
            tok[5] = "16384";
            tok[6] = "0x0";
            tok[7] = "0";
            printf("ess_app rc=%ld\n", (long)CFE_ES_ParseFileEntry(tok, 8));
            /* A priority over OS_MAX_TASK_PRIORITY is CLAMPED, not refused -- and an exception
             * action over RESTART_APP becomes PROC_RESTART, so a typo makes the spacecraft MORE
             * willing to reset itself. Both show up in the es_moduleload/os_taskcreate lines. */
            tok[3] = "SCH2";
            tok[4] = "999";
            tok[7] = "7";
            printf("ess_app_clamped rc=%ld\n", (long)CFE_ES_ParseFileEntry(tok, 8));
            /* A CFE_LIB line reads only four of the eight fields, and the entry symbol is
             * CALLED -- which is what makes it a library. */
            tok[0]            = "CFE_LIB";
            tok[1]            = "/cf/cfs_lib.so";
            tok[2]            = "CFS_LibInit";
            tok[3]            = "CFS_LIB";
            es_modlookup_addr = (cpuaddr)es_lib_init;
            printf("ess_lib rc=%ld\n", (long)CFE_ES_ParseFileEntry(tok, 8));
            es_modlookup_addr = (cpuaddr)0xE0000000;
            /* An unknown entry type is CFE_ES_ERR_APP_CREATE, not a parse error. */
            tok[0] = "CFE_WAT";
            printf("ess_badtype rc=%ld\n", (long)CFE_ES_ParseFileEntry(tok, 8));
            /* Too few fields. */
            tok[0] = "CFE_APP";
            printf("ess_short rc=%ld\n", (long)CFE_ES_ParseFileEntry(tok, 7));
            /* A file name the FS layer refuses. */
            tok[1] = "";
            printf("ess_badname rc=%ld\n", (long)CFE_ES_ParseFileEntry(tok, 8));

            /* CFE_ES_ReadStartupLine and CFE_ES_OpenStartupScript are `static` in NASA's .c,
             * so neither half can call them directly -- they are driven through
             * CFE_ES_StartApplications below, where the scripts are written with the whitespace
             * and the token shapes that prove the tokenisation: isgraph decides what is part of
             * a token, so the spaces and the newline are dropped and the ',' and ';' are the
             * only delimiters. The ParseFileEntry log lines show what came out. */
            /* --- CFE_ES_StartApplications, end to end --------------------------------- */
            /* A power-on reset reads the nonvolatile script only; a processor reset tries the
             * volatile copy first. Both go through the same simulated file. */
            memcpy(fs_data, "CFE_LIB, /cf/a.so, A_Init, A, 0, 0, 0x0, 0;\n!", 45);
            fs_len            = 45;
            es_modlookup_addr = (cpuaddr)es_lib_init;
            printf("ess_start_poweron\n");
            CFE_ES_StartApplications(CFE_PSP_RST_TYPE_POWERON, "/cf/cfe_es_startup.scr");
            memcpy(fs_data, "CFE_LIB, /cf/c.so, C_Init, C, 0, 0, 0x0, 0;\n!", 45);
            fs_len = 45;
            printf("ess_start_proc\n");
            CFE_ES_StartApplications(CFE_PSP_RST_TYPE_PROCESSOR, "/cf/cfe_es_startup.scr");
            es_modlookup_addr = (cpuaddr)0xE0000000;
            /* A MALFORMED LINE IS LOGGED AND SKIPPED, never fatal, and the detector is that
             * both buffers are one larger than the maximum: filling one IS overrunning it.
             * This line has nine fields. */
            memcpy(fs_data, "A,B,C,D,E,F,G,H,I;\n!", 21);
            fs_len = 21;
            printf("ess_start_toomany\n");
            CFE_ES_StartApplications(CFE_PSP_RST_TYPE_POWERON, "/cf/cfe_es_startup.scr");
            /* A script that will not open at all: two log lines and no parsing. */
            fs_open_fail = 1;
            printf("ess_start_noopen\n");
            CFE_ES_StartApplications(CFE_PSP_RST_TYPE_PROCESSOR, "/cf/cfe_es_startup.scr");
            fs_open_fail = 0;
            fs_len       = 0;
            fs_pos       = 0;
        }

        /* --- cfe_es_start.c: THE BOOT SEQUENCE ------------------------------------------
         *
         * cFE's main(). Five states in order, and the only failure mode in the whole file is a
         * panic -- five of its eight functions call CFE_PSP_Panic after a half-second delay
         * "to allow the message to be read".
         *
         * EVERYTHING HERE RUNS AGAINST A SAVED AND RESTORED GLOBAL. CFE_ES_Main's first act is
         * to memset CFE_ES_Global, which would destroy every record this driver planted, so the
         * boot is driven last and the state is put back afterwards. */
        {
            int32 rc;

            /* --- CFE_ES_SetupResetVariables: how a reset loop is detected -------------- */
            /* A power-on reset records the subtype and zeroes the counters. Three subtypes get
             * three different log lines and ER log entries. */
            printf("esb_reset_cycle\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_POWER_CYCLE,
                                       1);
            printf("esb_reset_cycle_v count=%u max=%u type=%u sub=%u boot=%u\n",
                   CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount,
                   CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount,
                   CFE_ES_Global.ResetDataPtr->ResetVars.ResetType,
                   CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype,
                   CFE_ES_Global.ResetDataPtr->ResetVars.BootSource);
            printf("esb_reset_hwcmd\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON,
                                       CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND, 2);
            printf("esb_reset_other\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, 99, 3);

            /* A PROCESSOR RESET THAT ES DID NOT CAUSE increments the counter. Under the maximum
             * it is logged as a processor reset; the watchdog and hw-command subtypes get
             * different text. */
            CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = false;
            printf("esb_reset_proc_wd\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_HW_WATCHDOG,
                                       1);
            printf("esb_reset_proc_wd_v count=%u sub=%u\n",
                   CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount,
                   CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype);
            CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = false;
            printf("esb_reset_proc_hw\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR,
                                       CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND, 1);

            /* OVER THE MAXIMUM, THE NEXT ONE IS ESCALATED TO A POWER-ON RESET -- which wipes
             * the reset area, so the loop is broken by losing state deliberately. The ER log
             * entry is written first, knowing it will not survive: "it's good to have the entry
             * just in case something fails". */
            CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset         = false;
            CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = 1;
            printf("esb_reset_max_wd\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_HW_WATCHDOG,
                                       1);
            CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset         = false;
            CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = 1;
            CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount    = 5;
            printf("esb_reset_max_hw\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR,
                                       CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND, 1);

            /* A reset ES DID cause was already logged on the way down, so this only updates the
             * variables -- no ER log entry, no counter change. */
            CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = true;
            printf("esb_reset_commanded\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, 42, 1);
            printf("esb_reset_commanded_v sub=%u caused=%d\n",
                   CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype,
                   (int)CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset);

            /* The reset area being unavailable or too small: both panic, and both return here
             * because CFE_PSP_Panic is a stub that does. */
            evs_resetarea_rc = CFE_PSP_ERROR;
            printf("esb_reset_noarea\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, 1, 1);
            evs_resetarea_rc = CFE_PSP_SUCCESS;
            evs_resetarea_size = 16;
            printf("esb_reset_small\n");
            CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, 1, 1);
            evs_resetarea_size = sizeof(CFE_ES_ResetData_t);

            /* --- CFE_ES_InitializeFileSystems: format or re-attach --------------------- */
            /* A power-on reset FORMATS; a processor reset RE-ATTACHES and falls back to
             * formatting. That difference is the volatile disk's whole purpose. */
            printf("esb_fs_poweron\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
            printf("esb_fs_poweron_v exists=%d mounted=%d\n", es_vol_exists, es_vol_mounted);
            printf("esb_fs_proc\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            /* A failed re-attach falls back to a format, with its own log line. */
            es_initfs_rc = OS_ERROR;
            printf("esb_fs_initfail\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            es_initfs_rc = OS_SUCCESS;
            /* THE DISK TOO FULL: unmount, remove, re-make, re-mount. 10 of 100 blocks free is
             * under the 30 percent reserve. */
            es_vol_blocks_free = 10;
            printf("esb_fs_full\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            es_vol_blocks_free = 90;
            /* And every failure arm: the memory, the format, the mount, the stat, and each step
             * of the reformat. */
            es_voldiskmem_rc = CFE_PSP_ERROR;
            printf("esb_fs_nomem\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
            es_voldiskmem_rc = CFE_PSP_SUCCESS;
            es_mkfs_rc       = OS_ERROR;
            printf("esb_fs_mkfsfail\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
            es_mkfs_rc  = OS_SUCCESS;
            es_mount_rc = OS_ERROR;
            printf("esb_fs_mountfail\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
            es_mount_rc   = OS_SUCCESS;
            es_statvol_rc = OS_ERROR;
            printf("esb_fs_statfail\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            es_statvol_rc = OS_SUCCESS;
            /* total_blocks of zero takes the same arm, because the division would be by zero. */
            es_vol_total_blocks = 0;
            printf("esb_fs_zeroblocks\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            es_vol_total_blocks = 100;
            /* The reformat's four steps, each refused in turn. */
            es_vol_blocks_free = 10;
            es_unmount_rc      = OS_ERROR;
            printf("esb_fs_unmountfail\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            es_unmount_rc = OS_SUCCESS;
            es_rmfs_rc    = OS_ERROR;
            printf("esb_fs_rmfsfail\n");
            CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
            es_rmfs_rc         = OS_SUCCESS;
            es_vol_blocks_free = 90;

            /* CFE_ES_MainTaskSyncDelay is effectively static -- see the note at the top of
             * this file -- so its two arms are driven through CFE_ES_CreateObjects and
             * CFE_ES_Main below. The timeout arm is the one that matters, and CreateObjects
             * reaches it whenever a core app's task does not come up RUNNING. */
            /* --- CFE_ES_CreateObjects, with a REAL core object table ------------------- */
            /* The table is empty in this configuration -- CFE_CORE_MODULE_OBJTAB is just its own
             * NULL terminator -- so the two phases would walk nothing. Planting two entries is
             * what makes them run: one library-only module (an EarlyInit and no TaskMain) and
             * one with a TaskMain, which takes a real app-table slot as a CORE app. */
            /* THE ENTRIES GO INTO THE TABLE, NOT OVER THE POINTER. GLOBAL_CONFIGDATA is
             * `const` in C and lives in .rodata, so writing its CoreObjectTable field through a
             * cast is a SIGBUS -- which is how this was found. CFE_CORE_MODULE_OBJTAB is a
             * separate object, emitted writable with spare slots by
             * tools/cfs/gen_target_config.py precisely so the driver can do this, and
             * GLOBAL_CONFIGDATA already points at it. */
            CFE_CORE_MODULE_OBJTAB[0] = &es_core_entry_lib;
            CFE_CORE_MODULE_OBJTAB[1] = &es_core_entry_task;
            CFE_CORE_MODULE_OBJTAB[2] = NULL;
            printf("esb_createobj\n");
            CFE_ES_CreateObjects();
            printf("esb_createobj_v coreapps=%u early=%ld tasks=%ld\n",
                   CFE_ES_Global.RegisteredCoreApps, es_core_early_calls, es_taskcreates);
            /* An EarlyInit that fails panics -- and returns, because the panic is a stub. */
            es_core_early_rc = -5;
            printf("esb_createobj_earlyfail\n");
            CFE_ES_CreateObjects();
            es_core_early_rc = CFE_SUCCESS;
            /* And a task that cannot be created: the reserved slot is wiped rather than left
             * claimed. */
            es_taskcreate_rc = OS_ERROR;
            printf("esb_createobj_taskfail\n");
            CFE_ES_CreateObjects();
            es_taskcreate_rc = OS_SUCCESS;
            CFE_CORE_MODULE_OBJTAB[0] = NULL;

            /* --- CFE_ES_Main: THE WHOLE BOOT ------------------------------------------- */
            /* Last, because its first act is to memset CFE_ES_Global. Everything above is
             * saved and restored around it. The five state transitions are in the log, in
             * order, and the startup script runs for real. */
            memcpy(&es_global_save, &CFE_ES_Global, sizeof(CFE_ES_Global));
            memcpy(fs_data, "CFE_LIB, /cf/a.so, A_Init, A, 0, 0, 0x0, 0;\n!", 45);
            fs_len            = 45;
            es_modlookup_addr = (cpuaddr)es_lib_init;
            printf("esb_main\n");
            CFE_ES_Main(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_POWER_CYCLE, 1,
                        "/cf/cfe_es_startup.scr");
            printf("esb_main_v state=%u coreapps=%u lastapp=%lu\n", CFE_ES_Global.SystemState,
                   CFE_ES_Global.RegisteredCoreApps,
                   CFE_RESOURCEID_TO_ULONG(CFE_ES_Global.LastAppId));
            /* The shared-data mutex failing is the one failure that stops the boot before
             * anything can be logged -- so it reports through OS_printf and panics. */
            fs_mut_create_rc = OS_ERROR;
            printf("esb_main_nomutex\n");
            CFE_ES_Main(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_POWER_CYCLE, 1,
                        "/cf/cfe_es_startup.scr");
            fs_mut_create_rc = OS_SUCCESS;
            memcpy(&CFE_ES_Global, &es_global_save, sizeof(CFE_ES_Global));
            es_modlookup_addr = (cpuaddr)0xE0000000;
            fs_len            = 0;
            fs_pos            = 0;
            es_ctx_init();
        }

        /* --- cfe_es_cds.c and cfe_es_cds_mempool.c: THE CRITICAL DATA STORE --------------
         *
         * The one piece of memory on a spacecraft that is expected to still be there after the
         * processor resets. It is not memory mapped -- NASA's comment at the cache is "Because
         * CDS memory is not memory mapped, this serves as temporary holding location for data
         * being actively accessed" -- so every byte in or out is a PSP call and everything
         * funnels through one 72-byte staging buffer.
         *
         * THE RESET IS WHY THE STORE IS SIMULATED RATHER THAN STUBBED. es_cds_reset wipes
         * CFE_ES_Global.CDSVars and leaves es_cds_store alone, which is exactly what cFE
         * experiences across a processor reset -- so the recovery path can actually run: the
         * signatures are found, the registry is read back, and CFE_ES_GenPoolRebuild recovers
         * the allocator from the block descriptors that survived in the store. A recording stub
         * cannot reach any of that code.
         *
         * The ES task block above already initialised the CDS and used it for the four delete
         * refusals. This drives what a command cannot reach. */
        {
            CFE_ES_CDSHandle_t   h1;
            CFE_ES_CDSHandle_t   h2;
            CFE_ES_CDS_RegRec_t *rr;
            unsigned char        cdsbuf[64];
            unsigned char        cdsback[64];
            uint32               idx;
            int32                rc;
            size_t               reqd;
            int                  k;

            /* --- the sizes, before anything is written --------------------------------- */
            reqd = CFE_ES_CDSReqdMinSize(1);
            printf("esd_minsize one=%lu entries=%lu\n", (unsigned long)reqd,
                   (unsigned long)CFE_ES_CDSReqdMinSize(CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES));

            /* --- EarlyInit's refusals -------------------------------------------------- */
            /* The mutex failing is the first thing that can go wrong, and the only one that
             * stops it before the store is even sized. */
            fs_mut_create_rc = OS_ERROR;
            es_cds_reset();
            printf("esd_init_mutexfail rc=%ld avail=%d\n", (long)CFE_ES_CDS_EarlyInit(),
                   (int)CFE_ES_Global.CDSIsAvailable);
            fs_mut_create_rc = OS_SUCCESS;
            /* The PSP refusing to say how big it is. */
            es_cds_getsize_rc = CFE_PSP_ERROR;
            es_cds_reset();
            printf("esd_init_sizefail rc=%ld avail=%d\n", (long)CFE_ES_CDS_EarlyInit(),
                   (int)CFE_ES_Global.CDSIsAvailable);
            es_cds_getsize_rc = CFE_PSP_SUCCESS;
            /* A STORE TOO SMALL IS REPORTED AND THEN IGNORED: Status stays CFE_SUCCESS and the
             * CDS is simply unavailable, so a spacecraft with a broken CDS still boots. The
             * minimum is 36,884 bytes of layout plus a pool big enough for 512 blocks. */
            es_cds_size = 1024;
            es_cds_reset();
            printf("esd_init_toosmall rc=%ld avail=%d\n", (long)CFE_ES_CDS_EarlyInit(),
                   (int)CFE_ES_Global.CDSIsAvailable);
            es_cds_size = ES_CDS_STORE_SIZE;

            /* --- a first boot: no signatures, so wipe and build ------------------------ */
            memset(es_cds_store, 0xAA, sizeof(es_cds_store));
            es_cds_reset();
            es_cds_reads  = 0;
            es_cds_writes = 0;
            rc            = CFE_ES_CDS_EarlyInit();
            printf("esd_firstboot rc=%ld avail=%d total=%lu data=%lu\n", (long)rc,
                   (int)CFE_ES_Global.CDSIsAvailable,
                   (unsigned long)CFE_ES_Global.CDSVars.TotalSize,
                   (unsigned long)CFE_ES_Global.CDSVars.DataSize);
            /* The signatures are in the store now, at each end, and the entry count is at
             * offset 8 -- which is what makes the next boot a recovery rather than a wipe. */
            printf("esd_sig begin=[");
            es_sig8(&es_cds_store[0]);
            printf("] end=[");
            es_sig8(&es_cds_store[ES_CDS_STORE_SIZE - 8]);
            printf("] regsize=%u\n", *(uint32 *)&es_cds_store[CDS_REG_SIZE_OFFSET]);

            /* --- register, write, read back -------------------------------------------- */
            printf("esd_reg rc=%ld\n", (long)CFE_ES_RegisterCDSEx(&h1, 64, "CDSAPP.ONE", false));
            printf("esd_reg_idx rc=%ld idx=%u\n", (long)CFE_ES_CDSHandle_ToIndex(h1, &idx), idx);
            rr = CFE_ES_LocateCDSBlockRecordByID(h1);
            printf("esd_reg_rec name=%s size=%lu usersize=%lu tbl=%d used=%d\n", rr->Name,
                   (unsigned long)rr->BlockSize,
                   (unsigned long)CFE_ES_CDSBlockRecordGetUserSize(rr), (int)rr->Table,
                   (int)CFE_ES_CDSBlockRecordIsUsed(rr));
            for (k = 0; k < 64; ++k)
            {
                cdsbuf[k] = (unsigned char)(0x40 + k);
            }
            printf("esd_write rc=%ld\n", (long)CFE_ES_CDSBlockWrite(h1, cdsbuf));
            memset(cdsback, 0, sizeof(cdsback));
            rc = CFE_ES_CDSBlockRead(cdsback, h1);
            printf("esd_read rc=%ld match=%d first=%02x last=%02x\n", (long)rc,
                   (int)(memcmp(cdsbuf, cdsback, 64) == 0), cdsback[0], cdsback[63]);

            /* --- THE RESET, and the recovery ------------------------------------------- */
            /* Everything in RAM is gone; the store is not. The signatures validate, the
             * registry is read back, and the pool is rebuilt from the descriptors in the store
             * -- so the handle from before the reset still reads its data. */
            es_cds_reset();
            rc = CFE_ES_CDS_EarlyInit();
            printf("esd_reboot rc=%ld avail=%d\n", (long)rc,
                   (int)CFE_ES_Global.CDSIsAvailable);
            rr = CFE_ES_LocateCDSBlockRecordByID(h1);
            printf("esd_reboot_rec name=%s used=%d size=%lu\n", rr->Name,
                   (int)CFE_ES_CDSBlockRecordIsUsed(rr), (unsigned long)rr->BlockSize);
            memset(cdsback, 0, sizeof(cdsback));
            rc = CFE_ES_CDSBlockRead(cdsback, h1);
            printf("esd_reboot_read rc=%ld match=%d\n", (long)rc,
                   (int)(memcmp(cdsbuf, cdsback, 64) == 0));
            /* AND THE NAME STILL FINDS IT, which is how an app that restarts gets its own store
             * back: re-registering the same name at the same size returns the alt-success code
             * CFE_ES_CDS_ALREADY_EXISTS -- not an error, high bit clear -- and the same handle. */
            rc = CFE_ES_RegisterCDSEx(&h2, 64, "CDSAPP.ONE", false);
            printf("esd_rereg rc=%ld same=%d\n", (long)rc,
                   (int)CFE_RESOURCEID_TEST_EQUAL(h1, h2));
            /* A DIFFERENT SIZE IS A REALLOCATION, and NASA says the alt-success code is
             * deliberately NOT returned for it: the old block is freed and a new one taken, so
             * the data is gone even though the name and the handle are the same. */
            rc = CFE_ES_RegisterCDSEx(&h2, 128, "CDSAPP.ONE", false);
            printf("esd_rereg_resize rc=%ld same=%d size=%lu\n", (long)rc,
                   (int)CFE_RESOURCEID_TEST_EQUAL(h1, h2),
                   (unsigned long)CFE_ES_LocateCDSBlockRecordByID(h2)->BlockSize);

            /* --- THE CRC IS THE ANSWER TO "DID THIS SURVIVE INTACT" -------------------- */
            /* Corrupt one byte of the user data in the store, behind the CDS's back, and the
             * read refuses. Nothing repairs it, because nothing can. */
            printf("esd_write2 rc=%ld\n", (long)CFE_ES_CDSBlockWrite(h2, cdsbuf));
            es_cds_store[CFE_ES_LocateCDSBlockRecordByID(h2)->BlockOffset + 4] ^= 0xFF;
            printf("esd_read_corrupt rc=%ld\n", (long)CFE_ES_CDSBlockRead(cdsback, h2));
            printf("esd_write3 rc=%ld\n", (long)CFE_ES_CDSBlockWrite(h2, cdsbuf));
            printf("esd_read_ok rc=%ld\n", (long)CFE_ES_CDSBlockRead(cdsback, h2));

            /* --- the refusals a caller can provoke ------------------------------------- */
            printf("esd_reg_zero rc=%ld\n", (long)CFE_ES_RegisterCDSEx(&h2, 0, "X.Y", false));
            printf("esd_reg_huge rc=%ld\n",
                   (long)CFE_ES_RegisterCDSEx(&h2, (size_t)1 << 30, "X.Y", false));
            printf("esd_write_badh rc=%ld\n",
                   (long)CFE_ES_CDSBlockWrite(CFE_ES_CDSHANDLE_C(
                                                  CFE_ResourceId_FromInteger(0x990000)),
                                              cdsbuf));
            printf("esd_read_badh rc=%ld\n",
                   (long)CFE_ES_CDSBlockRead(cdsback, CFE_ES_CDSHANDLE_C(
                                                          CFE_ResourceId_FromInteger(0x990000))));
            printf("esd_toidx_bad rc=%ld\n",
                   (long)CFE_ES_CDSHandle_ToIndex(CFE_ES_CDSHANDLE_C(
                                                      CFE_ResourceId_FromInteger(1)),
                                                  &idx));
            printf("esd_locate_bad null=%d\n",
                   (int)(CFE_ES_LocateCDSBlockRecordByID(CFE_ES_CDSHANDLE_C(
                             CFE_ResourceId_FromInteger(1))) == NULL));
            printf("esd_byname_miss null=%d\n",
                   (int)(CFE_ES_LocateCDSBlockRecordByName("NOPE.NOPE") == NULL));

            /* --- the cache's own bounds ------------------------------------------------- */
            /* Every fetch, flush and preload refuses zero and anything over the union's 72
             * bytes. It is the only bound checking the CDS has, because the store is reached by
             * call and not by pointer -- there is no fault to catch. */
            printf("esd_cache_zero rc=%ld\n",
                   (long)CFE_ES_CDS_CacheFetch(&CFE_ES_Global.CDSVars.Cache, 0, 0));
            printf("esd_cache_big rc=%ld\n",
                   (long)CFE_ES_CDS_CacheFetch(&CFE_ES_Global.CDSVars.Cache, 0, 1024));
            printf("esd_cache_preload_big rc=%ld\n",
                   (long)CFE_ES_CDS_CachePreload(&CFE_ES_Global.CDSVars.Cache, cdsbuf, 0, 1024));
            CFE_ES_Global.CDSVars.Cache.Size = 0;
            printf("esd_cache_flush_zero rc=%ld\n",
                   (long)CFE_ES_CDS_CacheFlush(&CFE_ES_Global.CDSVars.Cache));

            /* --- a store that reads back wrong ----------------------------------------- */
            /* An unreadable store: the first signature fetch fails, which is not "invalid" but
             * a PSP error, and it is reported as itself. */
            es_cds_read_rc = CFE_PSP_ERROR;
            printf("esd_validate_readfail rc=%ld\n", (long)CFE_ES_ValidateCDS());
            es_cds_read_rc = CFE_PSP_SUCCESS;
            /* A wrong END signature, with the beginning intact -- the case a store that was
             * grown or truncated would hit. */
            es_cds_store[ES_CDS_STORE_SIZE - 1] = 'X';
            printf("esd_validate_endbad rc=%ld\n", (long)CFE_ES_ValidateCDS());
            /* An entry count from a differently-configured build. The registry that follows
             * would be the wrong size, so this is CFE_ES_CDS_INVALID -- wipe and start again,
             * not an attempt to convert. */
            *(uint32 *)&es_cds_store[CDS_REG_SIZE_OFFSET] = 7;
            printf("esd_rebuild_wrongcount rc=%ld\n", (long)CFE_ES_RebuildCDS());
            /* And a store whose registry cannot be read at all. */
            *(uint32 *)&es_cds_store[CDS_REG_SIZE_OFFSET] = CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES;
            es_cds_read_rc                                = CFE_PSP_ERROR;
            printf("esd_rebuild_readfail rc=%ld\n", (long)CFE_ES_RebuildCDS());
            es_cds_read_rc = CFE_PSP_SUCCESS;

            /* --- a store that will not take a write ------------------------------------ */
            /* The wipe fails on its first flush. */
            es_cds_write_rc = CFE_PSP_ERROR;
            printf("esd_clear_fail rc=%ld\n", (long)CFE_ES_ClearCDS());
            printf("esd_sig_fail rc=%ld\n", (long)CFE_ES_InitCDSSignatures());
            printf("esd_initreg_fail rc=%ld\n", (long)CFE_ES_InitCDSRegistry());
            printf("esd_updatereg_fail rc=%ld\n", (long)CFE_ES_UpdateCDSRegistry());
            es_cds_write_rc = CFE_PSP_SUCCESS;
            /* THE END SIGNATURE FAILING WITH THE BEGINNING WRITTEN, which is the one partial
             * state the store can be left in -- and it is safe, because the next boot
             * validates the beginning, fails on the end, and wipes. */
            es_cds_write_fail_at = ES_CDS_STORE_SIZE - 8;
            printf("esd_sig_endfail rc=%ld\n", (long)CFE_ES_InitCDSSignatures());
            es_cds_write_fail_at = 0xFFFFFFFF;

            /* --- the pool, filled until it refuses -------------------------------------- */
            /* A 64 KiB store leaves about 28 KiB of pool after the 36,884-byte layout, so a
             * few hundred small blocks exhaust it -- and CFE_ES_RegisterCDS_AllocateBlock's
             * refusal is the allocator's, not the registry's. */
            memset(es_cds_store, 0, sizeof(es_cds_store));
            es_cds_reset();
            printf("esd_pool_init rc=%ld\n", (long)CFE_ES_CDS_EarlyInit());
            rc = CFE_SUCCESS;
            k  = 0;
            while (rc == CFE_SUCCESS && k < 600)
            {
                char nm[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN];
                snprintf(nm, sizeof(nm), "FILL.%03d", k);
                rc = CFE_ES_RegisterCDSEx(&h2, 64, nm, false);
                ++k;
            }
            printf("esd_pool_full after=%d rc=%ld\n", k, (long)rc);

            /* Leave the CDS in a clean, available state for anything after this. */
            memset(es_cds_store, 0, sizeof(es_cds_store));
            es_cds_reset();
            printf("esd_final rc=%ld avail=%d\n", (long)CFE_ES_CDS_EarlyInit(),
                   (int)CFE_ES_Global.CDSIsAvailable);
        }

        /* --- cfe_es_apps.c: THE APP LIFECYCLE ---------------------------------------------
         *
         * Loading a module, looking up its entry symbol, starting its task, and taking all of
         * that apart again. Six stubs went away from both halves of this driver on the commit
         * that gated this source -- CFE_ES_LockUserAppRecord, StartAppTask, AppCreate,
         * CleanUpApp and the three CopyModule*Info -- and every probe above that steered one of
         * them now steers an OSAL call instead, which is the honest place for the knob.
         *
         * WHAT IS WORTH DRIVING DIRECTLY is what the paths above cannot reach: LoadModule's
         * four outcomes, the whole of LoadLibrary (nothing else in cFE loads a library), and
         * CleanupTaskResources against the object table -- eight object kinds, an unknown kind,
         * a delete that refuses, and the trend guard that stops the sweep looping forever. */
        {
            CFE_ES_ModuleLoadParams_t mlp;
            CFE_ES_ModuleLoadStatus_t mls;
            CFE_ES_AppStartParams_t   sparams;
            CFE_ES_LibId_t            lid;
            CFE_ES_AppId_t            aid2;
            char                      nbuf[OS_MAX_API_NAME];
            uint32                    k;

            es_objs_clear();
            memset(&mlp, 0, sizeof(mlp));
            memset(&mls, 0, sizeof(mls));
            memset(&sparams, 0, sizeof(sparams));

            /* --- CFE_ES_LoadModule -----------------------------------------------------
             *
             * AN EMPTY FILE NAME IS NOT AN ERROR: a core app, or a library already linked in,
             * has nothing to load, so the module id stays undefined and the call succeeds. */
            printf("esm_load_nofile rc=%ld mod=%lu\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "NOFILE", &mlp, &mls),
                   (unsigned long)OS_ObjectIdToInteger(mls.ModuleId));

            /* The flags differ by resource kind, and that is the whole switch: an APP keeps its
             * symbols LOCAL so the module stays unloadable, a LIBRARY exposes them GLOBALLY --
             * which is zero, OSAL's default, so the library arm's OR is a no-op. */
            strncpy(mlp.FileName, "/cf/thing.so", sizeof(mlp.FileName) - 1);
            printf("esm_load_app rc=%ld\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "THING", &mlp, &mls));
            printf("esm_load_lib rc=%ld\n",
                   (long)CFE_ES_LoadModule(ES_LIBID(2), "THING", &mlp, &mls));
            printf("esm_load_other rc=%ld\n",
                   (long)CFE_ES_LoadModule(CFE_ResourceId_FromInteger(0x990000), "THING", &mlp,
                                           &mls));

            /* The load itself failing. */
            es_modload_rc = OS_ERROR;
            printf("esm_load_fail rc=%ld\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "THING", &mlp, &mls));
            es_modload_rc = OS_SUCCESS;

            /* An entry symbol, found and not found. THE UNLOAD AFTER A FAILED LOOKUP is the
             * part worth seeing: a bad entry symbol must not leak the module it loaded. */
            strncpy(mlp.InitSymbolName, "THING_Main", sizeof(mlp.InitSymbolName) - 1);
            printf("esm_load_sym rc=%ld addr=%08lx\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "THING", &mlp, &mls),
                   (unsigned long)mls.InitSymbolAddress);
            es_modlookup_rc = OS_ERROR;
            printf("esm_load_symfail rc=%ld unloads=%ld\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "THING", &mlp, &mls), es_modunloads);
            /* And the unload after that failure ALSO failing, which NASA can only report:
             * "There's not much we can do except notify." */
            es_modunload_rc = OS_ERROR;
            printf("esm_load_symfail_unloadfail rc=%ld\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "THING", &mlp, &mls));
            es_modunload_rc = OS_SUCCESS;
            es_modlookup_rc = OS_SUCCESS;

            /* The literal string "NULL" means "no entry symbol", which is how a startup-script
             * line says so -- no lookup happens at all. */
            strncpy(mlp.InitSymbolName, "NULL", sizeof(mlp.InitSymbolName) - 1);
            printf("esm_load_nullsym rc=%ld lookups=%ld\n",
                   (long)CFE_ES_LoadModule(ES_CTX_APPID(2), "THING", &mlp, &mls), es_modlookups);

            /* --- CFE_ES_LoadLibrary ----------------------------------------------------
             *
             * The same reserved-slot protocol as AppCreate, and three real differences: no
             * task, the entry symbol is called ONCE inline with the library's own id, and a
             * duplicate name reports the EXISTING library's id rather than UNDEFINED. */
            memset(&mlp, 0, sizeof(mlp));
            strncpy(mlp.FileName, "/cf/libthing.so", sizeof(mlp.FileName) - 1);
            strncpy(mlp.InitSymbolName, "LIBTHING_Init", sizeof(mlp.InitSymbolName) - 1);
            CFE_ES_Global.LastLibId = CFE_ResourceId_FromInteger(CFE_ES_LIBID_BASE);
            es_modlookup_addr       = (cpuaddr)es_lib_init;
            printf("esl_lib rc=%ld id=%lu libs=%u\n",
                   (long)CFE_ES_LoadLibrary(&lid, "LIBTHING", &mlp),
                   CFE_RESOURCEID_TO_ULONG(lid), CFE_ES_Global.RegisteredLibs);
            /* A duplicate library name hands back the id of the one already loaded -- the only
             * path in either loader where a failure returns a usable id. */
            printf("esl_lib_dup rc=%ld id=%lu\n",
                   (long)CFE_ES_LoadLibrary(&lid, "LIBTHING", &mlp),
                   CFE_RESOURCEID_TO_ULONG(lid));
            /* And one namespace with apps: a library may not take an app's name. */
            printf("esl_lib_appname rc=%ld\n", (long)CFE_ES_LoadLibrary(&lid, "CFE_EVS", &mlp));
            printf("esl_lib_nullname rc=%ld\n", (long)CFE_ES_LoadLibrary(&lid, NULL, &mlp));
            printf("esl_lib_nullparams rc=%ld\n",
                   (long)CFE_ES_LoadLibrary(&lid, "X", NULL));
            /* A name with no terminator inside the record's width, checked with memchr rather
             * than a length -- strlen on a caller's buffer is what runs off the end. */
            memset(nbuf, 'L', sizeof(nbuf));
            printf("esl_lib_longname rc=%ld\n", (long)CFE_ES_LoadLibrary(&lid, nbuf, &mlp));
            /* The load failing, and the init function returning an error. Both leave the slot
             * free again, and the id comes back UNDEFINED. */
            es_modload_rc = OS_ERROR;
            printf("esl_lib_loadfail rc=%ld id=%lu\n",
                   (long)CFE_ES_LoadLibrary(&lid, "LIBTWO", &mlp),
                   CFE_RESOURCEID_TO_ULONG(lid));
            es_modload_rc = OS_SUCCESS;
            es_lib_init_rc = -77;
            printf("esl_lib_initfail rc=%ld id=%lu libs=%u\n",
                   (long)CFE_ES_LoadLibrary(&lid, "LIBTWO", &mlp),
                   CFE_RESOURCEID_TO_ULONG(lid), CFE_ES_Global.RegisteredLibs);
            es_lib_init_rc = CFE_SUCCESS;
            /* Every slot taken. */
            for (k = 0; k < CFE_PLATFORM_ES_MAX_LIBRARIES; ++k)
            {
                CFE_ES_LibRecordSetUsed(&CFE_ES_Global.LibTable[k],
                                        CFE_ResourceId_FromInteger(CFE_ES_LIBID_BASE + k));
            }
            printf("esl_lib_nofree rc=%ld\n", (long)CFE_ES_LoadLibrary(&lid, "LIBFULL", &mlp));
            memset(CFE_ES_Global.LibTable, 0, sizeof(CFE_ES_Global.LibTable));
            CFE_ES_Global.RegisteredLibs = 0;
            es_modlookup_addr            = (cpuaddr)0xE0000000;

            /* --- CFE_ES_CleanupTaskResources, against the object table -------------------
             *
             * This is the only place a dead task's resources can be reclaimed from, because
             * nothing recorded that it made them: OS_ForEachObject hands over every object
             * whose creator it was, and the callback asks OS_IdentifyObject what each one is.
             * All eight kinds, in one sweep. */
            es_objs_clear();
            es_obj_add(0x7001, OS_OBJECT_TYPE_OS_BINSEM);
            es_obj_add(0x7002, OS_OBJECT_TYPE_OS_COUNTSEM);
            es_obj_add(0x7003, OS_OBJECT_TYPE_OS_MUTEX);
            es_obj_add(0x7004, OS_OBJECT_TYPE_OS_TIMECB);
            es_obj_add(0x7005, OS_OBJECT_TYPE_OS_STREAM);
            printf("esm_cleanup_sweep rc=%ld foreach=%ld\n",
                   (long)CFE_ES_CleanupTaskResources(CFE_ES_TASKID_C(
                       CFE_ResourceId_FromInteger(CFE_ES_TASKID_BASE + 5))),
                   es_foreach_calls);

            /* AN UNKNOWN KIND IS NOT COUNTED AT ALL -- not as found, not as a failure -- which
             * is what keeps the trend guard from being confused by a type OSAL grows later. */
            es_objs_clear();
            es_obj_add(0x7010, OS_OBJECT_TYPE_OS_DIR);
            printf("esm_cleanup_unknown rc=%ld\n",
                   (long)CFE_ES_CleanupTaskResources(CFE_ES_TASKID_C(
                       CFE_ResourceId_FromInteger(CFE_ES_TASKID_BASE + 6))));

            /* A QUEUE object: OS_QueueDelete's own body refuses an id that is not one of SB's
             * created queues, so this is the CFE_ES_QUEUE_DELETE_ERR arm -- and the object is
             * never marked gone, so it is also the "found objects are not trending downward"
             * guard that stops the sweep. */
            es_objs_clear();
            es_obj_add(0x7020, OS_OBJECT_TYPE_OS_QUEUE);
            printf("esm_cleanup_stuck rc=%ld\n",
                   (long)CFE_ES_CleanupTaskResources(CFE_ES_TASKID_C(
                       CFE_ResourceId_FromInteger(CFE_ES_TASKID_BASE + 7))));

            /* A delete that refuses outright, on a type whose error code is its own. */
            es_objs_clear();
            es_obj_add(0x7030, OS_OBJECT_TYPE_OS_TIMECB);
            es_objdel_rc = OS_ERROR;
            printf("esm_cleanup_refused rc=%ld\n",
                   (long)CFE_ES_CleanupTaskResources(CFE_ES_TASKID_C(
                       CFE_ResourceId_FromInteger(CFE_ES_TASKID_BASE + 8))));
            es_objdel_rc = OS_SUCCESS;

            /* NO OBJECTS AT ALL, and the task delete failing -- which is the one way
             * CFE_ES_TASK_DELETE_ERR comes out. A self-exited task reports
             * OS_ERR_INVALID_ID instead and that is NOT an error: NASA's comment is "there is
             * nothing else needed to do". */
            es_objs_clear();
            es_taskdelete_rc = OS_ERROR;
            printf("esm_cleanup_taskfail rc=%ld\n",
                   (long)CFE_ES_CleanupTaskResources(CFE_ES_TASKID_C(
                       CFE_ResourceId_FromInteger(CFE_ES_TASKID_BASE + 9))));
            es_taskdelete_rc = OS_ERR_INVALID_ID;
            printf("esm_cleanup_selfexited rc=%ld\n",
                   (long)CFE_ES_CleanupTaskResources(CFE_ES_TASKID_C(
                       CFE_ResourceId_FromInteger(CFE_ES_TASKID_BASE + 9))));
            es_taskdelete_rc = OS_SUCCESS;

            /* --- CFE_ES_AppCreate's refusals, which the ground command cannot reach ------ */
            printf("esm_create_nullname rc=%ld\n", (long)CFE_ES_AppCreate(&aid2, NULL, &sparams));
            printf("esm_create_nullparams rc=%ld\n",
                   (long)CFE_ES_AppCreate(&aid2, "X", NULL));
            memset(nbuf, 'A', sizeof(nbuf));
            printf("esm_create_longname rc=%ld\n",
                   (long)CFE_ES_AppCreate(&aid2, nbuf, &sparams));

            es_ctx_init();
            es_objs_clear();
        }

        /* --- cfe_es_appctrl.c: CARRYING OUT A CONTROL REQUEST -----------------------------
         *
         * cfe_es_api.c's RestartApp, ReloadApp and DeleteApp only STORE a request in the app
         * record -- the block above already asserted that, and that the app keeps running.
         * This is the other half: the four functions the background task runs later to
         * actually delete the app, maybe start it again, and say what happened.
         *
         * THE EVENT IS THE ASSERTION. One event comes out of each request, chosen from a
         * ten-row table indexed by RUN STATUS, and NASA writes that table with DESIGNATED
         * initialisers -- most rows set two of five fields and leave the rest zero, and every
         * branch in _Finish tests one of those fields against zero. HolyC has no designated
         * initialisers, so the translation writes all five fields of all ten rows positionally.
         * A row written one field off still compiles, still passes every structural gate, and
         * sends the wrong event. Nothing but this comparison would notice.
         *
         * So every row is driven, including the two reserved ones and an out-of-range request,
         * and the three branches inside a row -- cleanup failed, startup failed, nominal --
         * are driven separately on the rows that have them. */
        {
            CFE_ES_AppRecord_t *        arp = &CFE_ES_Global.AppTable[2];
            CFE_ES_AppTableScanState_t *sst = &CFE_ES_Global.BackgroundAppScanState;
            CFE_ES_AppId_t              a2  = CFE_ES_APPID_C(ES_CTX_APPID(2));
            CFE_ES_AppStartParams_t     sp;
            char                        nm[OS_MAX_API_NAME];
            uint32                      req;
            uint32                      burst;
            bool                        r;

            es_ctx_init();
            es_objs_clear();

            /* THE SQUELCH HAS TO COME OFF OR THIS BLOCK ASSERTS NOTHING. EVS's per-app token
             * bucket ran dry during the ES task block above -- "44: Events squelched, AppName
             * = CFE_EVS" is in the transcript -- and every event after that is dropped
             * silently. This block's entire assertion is WHICH EVENT came out, so it was
             * written, run, and produced thirty lines of path markers with no events at all.
             * Zeroing EVS_EventBurstMax is what the EVS block does for the same reason and
             * short-circuits EVS_CheckAndIncrementSquelchTokens. Restored at the end. */
            burst = CFE_EVS_Global.EVS_EventBurstMax;
            CFE_EVS_Global.EVS_EventBurstMax = 0;

            /* --- _Start: THE SNAPSHOT TAKEN UNDER THE LOCK --------------------------------
             *
             * NASA's reason for the copy is that the caller is about to delete the record it
             * just read: "This way it becomes private and can be accessed without concerns
             * about other threads/tasks, even after the global data records are eventually
             * cleared."
             *
             * AND THE COPY IS THE SECOND LIVE SITE OF docs/HOLYC_STRUCT_LIMITS.md #21.
             * NASA writes `*RestartParamPtr = AppRecPtr->StartParams;` -- a 344-byte struct
             * copy through a bare pointer, which in HolyC moves eight bytes and leaves the
             * rest at whatever the destination held. The entry point, stack size, priority
             * and exception action below are all past that eighth byte, so a translation that
             * wrote the assignment would restart the app with a zero stack and no entry
             * symbol. Each is printed. */
            strncpy(arp->StartParams.BasicInfo.InitSymbolName, "OTHER_AppMain",
                    sizeof(arp->StartParams.BasicInfo.InitSymbolName) - 1);
            arp->StartParams.MainTaskInfo.StackSize = 8192;
            arp->StartParams.MainTaskInfo.Priority  = 77;
            arp->StartParams.ExceptionAction        = CFE_ES_ExceptionAction_PROC_RESTART;

            arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RESTART;
            memset(&sp, 0, sizeof(sp));
            memset(nm, 0, sizeof(nm));
            req = CFE_ES_ProcessControlRequest_Start(a2, nm, sizeof(nm), &sp);
            printf("esc_start req=%u name=%s file=%s entry=%s stack=%lu prio=%u exc=%u\n", req,
                   nm, sp.BasicInfo.FileName, sp.BasicInfo.InitSymbolName,
                   (unsigned long)sp.MainTaskInfo.StackSize,
                   (unsigned)sp.MainTaskInfo.Priority, (unsigned)sp.ExceptionAction);

            /* A request that is not a restart or a reload does NOT copy the parameters. The
             * buffer is zeroed first, so an unconditional copy would show up here. */
            arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
            memset(&sp, 0, sizeof(sp));
            memset(nm, 0, sizeof(nm));
            req = CFE_ES_ProcessControlRequest_Start(a2, nm, sizeof(nm), &sp);
            printf("esc_start_nocopy req=%u name=%s file=[%s] stack=%lu\n", req, nm,
                   sp.BasicInfo.FileName, (unsigned long)sp.MainTaskInfo.StackSize);

            /* No record matches, so the snapshot is never taken and the request stays 0 --
             * which is CFE_ES_RunStatus_UNDEFINED, the table row with no name. That is how a
             * stale app id turns into the "[Req0]" event below rather than a wild read. */
            memset(nm, 0, sizeof(nm));
            req = CFE_ES_ProcessControlRequest_Start(CFE_ES_APPID_C(ES_CTX_APPID(9)), nm,
                                                     sizeof(nm), &sp);
            printf("esc_start_nomatch req=%u name=[%s]\n", req, nm);

            /* --- _Finish: ALL TEN ROWS, PLUS ONE PAST THE END ----------------------------
             *
             * The nominal case for each row: no cleanup error, no startup error, no new app
             * id. Rows 0, 8 and 9 have an ErrorEventID set and so send that instead; row 1
             * ("Run") has NOTHING set, which is NASA's //jphfix, and sends no event at all. */
            for (req = 0; req <= CFE_ES_RunStatus_MAX; ++req)
            {
                printf("esc_fin req=%u\n", req);
                CFE_ES_ProcessControlRequest_Finish(req, "OTHER_APP", CFE_SUCCESS, CFE_SUCCESS,
                                                    CFE_ES_APPID_UNDEFINED);
            }

            /* A new app id is appended to the nominal text, and only when it is defined. */
            printf("esc_fin_newid\n");
            CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_RELOAD, "OTHER_APP",
                                                CFE_SUCCESS, CFE_SUCCESS,
                                                CFE_ES_APPID_C(ES_CTX_APPID(4)));

            /* Cleanup failed, on a row that HAS a CleanupErrEventID. */
            printf("esc_fin_cleanuperr\n");
            CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_DELETE, "OTHER_APP",
                                                CFE_SUCCESS, CFE_ES_ERR_RESOURCEID_NOT_VALID,
                                                CFE_ES_APPID_UNDEFINED);

            /* Cleanup failed on a row that has NO CleanupErrEventID -- "Exception" -- so the
             * failure is swallowed and the nominal event goes out. NASA's note: "The
             * CleanupStatus is a dont-care when CleanupErrEventID is not set." */
            printf("esc_fin_cleanuperr_dontcare\n");
            CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_EXCEPTION, "OTHER_APP",
                                                CFE_SUCCESS, CFE_ES_ERR_RESOURCEID_NOT_VALID,
                                                CFE_ES_APPID_UNDEFINED);

            /* Startup failed, on a row that has a StartupErrEventID. */
            printf("esc_fin_startuperr\n");
            CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_RESTART, "OTHER_APP",
                                                CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_SUCCESS,
                                                CFE_ES_APPID_UNDEFINED);

            /* BOTH failed. Cleanup wins, because its branch is tested first. */
            printf("esc_fin_botherr\n");
            CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_RELOAD, "OTHER_APP",
                                                CFE_ES_ERR_RESOURCEID_NOT_VALID,
                                                CFE_ES_ERR_RESOURCEID_NOT_VALID,
                                                CFE_ES_APPID_UNDEFINED);

            /* A startup failure on a row with no StartupErrEventID -- "Exit" -- is a
             * dont-care the same way, and the nominal event goes out. */
            printf("esc_fin_startuperr_dontcare\n");
            CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_APP_EXIT, "OTHER_APP",
                                                CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_SUCCESS,
                                                CFE_ES_APPID_UNDEFINED);

            /* --- ProcessControlRequest: END TO END ---------------------------------------
             *
             * Snapshot, CleanUpApp, maybe AppCreate, event. Each of the seven live requests,
             * and the app record is re-planted each time because the real CleanUpApp would
             * have cleared it -- the stub does not, which is exactly why the loop has to. */
            for (req = CFE_ES_RunStatus_APP_RUN; req <= CFE_ES_RunStatus_SYS_DELETE; ++req)
            {
                /* THE WHOLE TABLE IS CLEARED, not just slot 2, and the reason is a residue the
                 * stub never produced: a successful restart really does create a NEW app record
                 * now, named OTHER_APP, in whatever slot was free. Re-planting slot 2 on the next
                 * pass then left TWO records with that name, so the following AppCreate reported
                 * a duplicate and the reload success path stopped being exercised. */
                memset(CFE_ES_Global.AppTable, 0, sizeof(CFE_ES_Global.AppTable));
                es_app_slot(1, "CFE_EVS", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
                es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
                strncpy(arp->StartParams.BasicInfo.InitSymbolName, "OTHER_AppMain",
                        sizeof(arp->StartParams.BasicInfo.InitSymbolName) - 1);
                arp->StartParams.MainTaskInfo.StackSize = 8192;
                arp->StartParams.MainTaskInfo.Priority  = 77;
                arp->ControlReq.AppControlRequest       = req;
                printf("esc_pcr req=%u\n", req);
                CFE_ES_ProcessControlRequest(a2);
            }

            /* Cleanup failing does NOT stop the restart, which is the behaviour NASA argues
             * for at length: a stale task id is a minor inconsistency in the old record and
             * should not cost the operator the new app. So AppCreate still runs.
             *
             * THE FAILURE IS REAL NOW RATHER THAN A RETURN CODE. Until cfe_es_apps.c was gated
             * this was `es_cleanup_rc = ...` on a stub; the real CFE_ES_CleanUpApp returns
             * CFE_ES_APP_CLEANUP_ERR only when its FailCount is non-zero, so something has to
             * actually fail to be reclaimed. An OSAL object of QUEUE type owned by the app's
             * main task does it: the cleanup callback calls OS_QueueDelete, whose own body
             * refuses an id that is not one of SB's created queues, and the error propagates
             * CFE_ES_QUEUE_DELETE_ERR out through CleanupTaskResources and FreeTasks. */
            es_objs_clear();
            es_obj_add(es_os_taskid, OS_OBJECT_TYPE_OS_QUEUE);
            es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
            arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RESTART;
            printf("esc_pcr_cleanupfail\n");
            CFE_ES_ProcessControlRequest(a2);

            /* And AppCreate failing. */
            es_objs_clear();
            es_modload_rc = CFE_ES_ERR_RESOURCEID_NOT_VALID;
            es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
            arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RELOAD;
            printf("esc_pcr_createfail\n");
            CFE_ES_ProcessControlRequest(a2);
            es_modload_rc = OS_SUCCESS;

            /* A stale app id: no snapshot, request 0, the unnamed row, "[Req0]". */
            printf("esc_pcr_stale\n");
            CFE_ES_ProcessControlRequest(CFE_ES_APPID_C(ES_CTX_APPID(9)));

            /* --- RunAppTableScan: WHAT MAKES A STORED REQUEST HAPPEN ---------------------
             *
             * A RUNNING app is not killed, it is ASKED. An app with a pending request moves
             * to WAITING and is given APP_KILL_TIMEOUT scan periods; only when that runs out
             * does the request get carried out. That window is the app's chance to exit
             * cleanly through CFE_ES_ExitApp. */
            es_ctx_init();
            es_objs_clear();
            memset(sst, 0, sizeof(*sst));

            /* Not due: no pending changes, the command counter has not moved, and the timer
             * has time left. The timer is decremented and nothing is scanned. */
            sst->LastScanCommandCount = CFE_ES_Global.TaskData.CommandCounter;
            sst->BackgroundScanTimer  = 1000;
            r                         = CFE_ES_RunAppTableScan(10, sst);
            printf("esc_scan_notdue r=%d timer=%u pend=%u\n", (int)r,
                   (unsigned)sst->BackgroundScanTimer, (unsigned)sst->PendingAppStateChanges);

            /* The command counter moving makes a scan due IMMEDIATELY, which is how a ground
             * command that stores a request is acted on at once rather than up to a second
             * later. Nothing is pending, so the scan finds nothing and the timer is reloaded. */
            ++CFE_ES_Global.TaskData.CommandCounter;
            r = CFE_ES_RunAppTableScan(10, sst);
            printf("esc_scan_cmdcount r=%d timer=%u pend=%u last=%u\n", (int)r,
                   (unsigned)sst->BackgroundScanTimer, (unsigned)sst->PendingAppStateChanges,
                   (unsigned)sst->LastScanCommandCount);

            /* A pending request on a RUNNING app: it moves to WAITING and gets the timeout.
             * Note it is NOT counted as a pending state change on this pass -- the branch
             * that counts runs only for apps already past RUNNING -- so the scan still
             * returns false and the next pass is a normal timed one. */
            arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
            sst->BackgroundScanTimer          = 0;
            r                                 = CFE_ES_RunAppTableScan(0, sst);
            printf("esc_scan_ask r=%d state=%u timer=%u pend=%u\n", (int)r,
                   (unsigned)arp->AppState, (unsigned)arp->ControlReq.AppTimerMsec,
                   (unsigned)sst->PendingAppStateChanges);

            /* Now it is WAITING, so each scan counts it and winds its timer down. One tick
             * short of the end, nothing happens except the countdown -- and the scan returns
             * TRUE, which is what makes the background task come back sooner. */
            sst->BackgroundScanTimer = 0;
            r                        = CFE_ES_RunAppTableScan(4000, sst);
            printf("esc_scan_wait r=%d state=%u timer=%u pend=%u\n", (int)r,
                   (unsigned)arp->AppState, (unsigned)arp->ControlReq.AppTimerMsec,
                   (unsigned)sst->PendingAppStateChanges);

            /* The timer reaches zero, the app id goes on the timeout list, and the request is
             * carried out AFTER the lock is released -- NASA: "This avoids needing to access
             * the global records outside of the lock." The es_cleanupapp line and the Stop
             * event below are that deletion. */
            sst->BackgroundScanTimer = 0;
            printf("esc_scan_fire\n");
            r = CFE_ES_RunAppTableScan(4000, sst);
            printf("esc_scan_fired r=%d used=%d pend=%u\n", (int)r,
                   (int)CFE_ES_AppRecordIsUsed(arp), (unsigned)sst->PendingAppStateChanges);

            /* A CORE app is skipped entirely, however it is set up: NASA's loop tests
             * Type == EXTERNAL. So a pending request on a core app is never carried out. */
            es_app_slot(2, "CORE_APP", CFE_ES_AppType_CORE, CFE_ES_AppState_WAITING);
            arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
            arp->ControlReq.AppTimerMsec      = 0;
            sst->BackgroundScanTimer          = 0;
            r                                 = CFE_ES_RunAppTableScan(0, sst);
            printf("esc_scan_core r=%d state=%u pend=%u\n", (int)r, (unsigned)arp->AppState,
                   (unsigned)sst->PendingAppStateChanges);

            /* Leave ES, and EVS's squelch, as the rest of the file expects to find them. */
            CFE_EVS_Global.EVS_EventBurstMax = burst;
            es_ctx_init();
            memset(sst, 0, sizeof(*sst));
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
            /* THE WITNESS MOVED. es_bytecnt_errs counted a stub; CFE_ES_FileWriteByteCntErr is
             * real now (cfe_es_task.c) and raises CFE_ES_FILEWRITE_ERR_EID instead, so what
             * says the short-write path fired is the event -- which is in the transcript
             * above this line -- and the count of EVS output lines it produced. */
            evs_printf_lines = 0;
            printf("sl_dump_wrfail rc=%ld evs=%ld\n", (long)CFE_ES_SysLogDump("/ram/syslog.dat"),
                   evs_printf_lines);
            fs_wr_left = -1;
        }


        /* --- cfe_tbl_handlelink.c -------------------------------------------------------
         * The first of table services' fifteen sources to be gated, and the only one that
         * never touches CFE_TBL_Global: two functions over a two-field list node. The node is
         * filled with 0xAB first, because CFE_TBL_HandleLinkInit's whole job is to write BOTH
         * fields and a zeroed node would not tell them apart from an untouched one. */
        {
            CFE_TBL_HandleLink_t   link;
            CFE_TBL_RegistryRec_t *deep;

            memset(&link, 0xAB, sizeof(link));
            CFE_TBL_HandleLinkInit(&link);
            printf("tbl_linkinit prev=%lu next=%lu attached=%d\n",
                   (unsigned long)CFE_TBL_HandleID_AsInt(link.Prev),
                   (unsigned long)CFE_TBL_HandleID_AsInt(link.Next),
                   (int)CFE_TBL_HandleLinkIsAttached(&link));

            link.Next = CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 3));
            printf("tbl_linkattach next=%lu attached=%d\n",
                   (unsigned long)CFE_TBL_HandleID_AsInt(link.Next),
                   (int)CFE_TBL_HandleLinkIsAttached(&link));

            /* PREV ALONE IS NOT ATTACHMENT. CFE_TBL_HandleLinkIsAttached reads only Next, which
             * is the asymmetry that makes the list walkable in one direction from any node and
             * is easy to get wrong by symmetry when translating. */
            CFE_TBL_HandleLinkInit(&link);
            link.Prev = CFE_TBL_HANDLEID_C(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 4));
            printf("tbl_linkprevonly prev=%lu attached=%d\n",
                   (unsigned long)CFE_TBL_HandleID_AsInt(link.Prev),
                   (int)CFE_TBL_HandleLinkIsAttached(&link));

            /* AND THROUGH THE DEEPEST REGISTRY RECORD, 61 KB into the global: this is where a
             * table's access list actually lives, and `Registry[MAX - 1]` is the address form
             * that resolved 117 KB before the object until the subscript fix. */
            deep = &CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1];
            memset(&deep->AccessList, 0xCD, sizeof(deep->AccessList));
            CFE_TBL_HandleLinkInit(&deep->AccessList);
            printf("tbl_linkdeep attached=%d off=%ld\n",
                   (int)CFE_TBL_HandleLinkIsAttached(&deep->AccessList),
                   (long)((char *)&deep->AccessList - (char *)&CFE_TBL_Global));
        }

        TblDumpCtlExercise();
        TblAccDescExercise();
        TblLoadBuffRegRecExercise();
        TblValResultExercise();
        TblCodecExercise();
        TblTransactionExercise();
        TblInternalExercise();
        TblRegistryExercise();
        TblEarlyInitExercise();
        TblDumpExercise();
        TblLoadExercise();
        TblApiExercise();
        TblCmdExercise();
        TblTaskExercise();
        /* --- tbl: CFE_TBL_Global IS 592,056 BYTES AND EVERY OFFSET IN IT HAS TO BE REACHABLE
         * ------------------------------------------------------------------------------------
         * This is not a translation of anything. It is the test that has to pass BEFORE the
         * 7,780 lines of table services are worth translating, because all of them reach
         * through this one object and the deepest member sits at offset 591,736.
         *
         * A RISC-V load or store carries a 12-bit signed immediate, so anything past 2,047
         * bytes from the base register needs the address built up first -- and this port has a
         * recorded codegen bug of exactly that shape (docs/, "indexed store into a large local
         * array" emitted a wild store at deep offsets). It was fixed for LOCALS and has never
         * been exercised at 590 KB on a global. If it is wrong here, every table function
         * built on top writes to the wrong place and the transcript blames the function.
         *
         * So: the offsets are printed as pointer differences, which is the compiler's own
         * arithmetic, and then a sentinel is written and read back through each one. The C
         * half computes the same differences from the same header, so a mismatch is a codegen
         * failure and not a layout disagreement -- check_padding already settled layout. */
        printf("tbl_off reg=%ld crit=%ld buf=%ld val=%ld dmp=%ld rds=%ld last=%ld whole=%ld\n",
               (long)((char *)&CFE_TBL_Global.Registry[0] - (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.CritReg[0] - (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.Buf - (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.ValidationResults[0] - (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.DumpControlBlocks[0] - (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.RegDumpState - (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.LastDumpCtrlBlockId - (char *)&CFE_TBL_Global),
               (long)sizeof(CFE_TBL_Global));

        /* the LAST element of every array, which is the deepest reach in each case */
        printf("tbl_off_end reg=%ld crit=%ld val=%ld dmp=%ld pool=%ld\n",
               (long)((char *)&CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1] -
                      (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES - 1] -
                      (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1] -
                      (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1] -
                      (char *)&CFE_TBL_Global),
               (long)((char *)&CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 1] -
                      (char *)&CFE_TBL_Global));

        /* AND NOW WRITE THROUGH EVERY ONE OF THEM AND READ IT BACK. A store that lands at the
         * wrong offset shows up two ways: the value read back is wrong, or a NEIGHBOUR changed.
         * Both are checked -- the neighbour sum is over the five members that follow the ones
         * written, and it has to stay zero. */
        memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
        CFE_TBL_Global.Registry[0].RegId                                      = 0x11111111;
        CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1].RegId    = 0x22222222;
        CFE_TBL_Global.CritReg[0].CDSHandle                                   = 0x33333333;
        CFE_TBL_Global.CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES - 1].CDSHandle = 0x44444444;
        CFE_TBL_Global.Buf.Partition.Data[0]                                  = 0x55;
        CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 1] = 0x66;
        CFE_TBL_Global.ValidationResults[0].CrcOfTable                        = 0x77777777;
        CFE_TBL_Global.ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1].CrcOfTable = 0x88888888;
        CFE_TBL_Global.DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1].TableName[0] = 'Z';
        CFE_TBL_Global.RegDumpState.FileExisted                               = true;
        CFE_TBL_Global.LastHandle               = CFE_ResourceId_FromInteger(0x99999999);
        CFE_TBL_Global.LastDumpCtrlBlockId      = CFE_ResourceId_FromInteger(0xAAAAAAAA);

        printf("tbl_deep %08lx %08lx %08lx %08lx %02x %02x %08lx %08lx %c %d %08lx %08lx\n",
               (unsigned long)CFE_TBL_Global.Registry[0].RegId,
               (unsigned long)CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1].RegId,
               (unsigned long)CFE_TBL_Global.CritReg[0].CDSHandle,
               (unsigned long)CFE_TBL_Global.CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES - 1].CDSHandle,
               (unsigned)CFE_TBL_Global.Buf.Partition.Data[0],
               (unsigned)CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 1],
               (unsigned long)CFE_TBL_Global.ValidationResults[0].CrcOfTable,
               (unsigned long)CFE_TBL_Global.ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1].CrcOfTable,
               CFE_TBL_Global.DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1].TableName[0],
               (int)CFE_TBL_Global.RegDumpState.FileExisted,
               (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastHandle),
               (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastDumpCtrlBlockId));

        /* the neighbours: every one of these is adjacent to something written above and must
         * still be zero. Registry[1] follows Registry[0], CritReg[1] follows CritReg[0],
         * ValidationResults[1] follows ValidationResults[0], and LastRegId, LastLoadBuffId and
         * LastValidationResultId sit between LastHandle and LastDumpCtrlBlockId. */
        printf("tbl_neigh %lu\n",
               (unsigned long)(CFE_TBL_Global.Registry[1].RegId + CFE_TBL_Global.CritReg[1].CDSHandle +
                               CFE_TBL_Global.ValidationResults[1].CrcOfTable +
                               CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastRegId) +
                               CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastLoadBuffId) +
                               CFE_RESOURCEID_TO_ULONG(CFE_TBL_Global.LastValidationResultId) +
                               CFE_TBL_Global.Buf.Partition.Data[1] +
                               CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 2]));
        memset(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));

        /* --- cfe_time_objtab.c ------------------------------------------------------------ */
        /* --- cfe_tbl_objtab.c ----------------------------------------------------------
         * tbl's entry in the core module object table: the whole contract between a core
         * service and cFE's startup, which walks the table twice -- EarlyInit for every
         * module, then TaskMain for every module. TBL is the ORDINARY shape, with all three
         * hooks present; ES is the one that is odd, having no Cleanup. */
        printf("tbl_objtab %s %d %d %d %lu %lu\n", CFE_TBL_ModuleEntry.Name,
               (int)(CFE_TBL_ModuleEntry.EarlyInit == NULL),
               (int)(CFE_TBL_ModuleEntry.TaskMain == NULL),
               (int)(CFE_TBL_ModuleEntry.AppCleanupCb == NULL),
               (unsigned long)CFE_TBL_ModuleEntry.Priority,
               (unsigned long)CFE_TBL_ModuleEntry.StackSize);
        /* and the three are DISTINCT addresses, which is what a positional initialiser can
         * silently get wrong where a designated one cannot */
        printf("tbl_objtab_distinct %d\n",
               (int)(CFE_TBL_ModuleEntry.EarlyInit != (void *)CFE_TBL_ModuleEntry.TaskMain &&
                     (void *)CFE_TBL_ModuleEntry.TaskMain != (void *)CFE_TBL_ModuleEntry.AppCleanupCb));

        /* --- md_utils.c (MD -- THE FIRST cFS APP) ------------------------------------
         * Nine functions. The bitmask reader, five validators, the two alignment checks and
         * the address resolver, plus the summariser that walks a dwell table.
         *
         * EVERY ADDRESS BELOW IS A LITERAL CONSTANT, and that is the whole reason this block
         * can exist. MD_ResolveSymAddr returns Offset verbatim when SymName is empty, so the
         * numbers the two halves print are the numbers written here -- not a host pointer on
         * one side and a guest pointer on the other. See docs/CFS_PLAN.md. */
        {
            uint16  masks[5] = {0x0001, 0x0002, 0x000A, 0xFFFF, 0x0000};
            int     mi, k;
            cpuaddr ra;
            long    before;

            /* MD_TableIsInMask. TableId 1 is the branch that does NOT shift -- `if (TableId -
             * 1)` is false -- and it is the one an off-by-one would get wrong. */
            for (mi = 0; mi < 5; mi++)
            {
                printf("md_mask %u %d%d%d%d\n", (unsigned)masks[mi],
                       (int)MD_TableIsInMask(1, masks[mi]), (int)MD_TableIsInMask(2, masks[mi]),
                       (int)MD_TableIsInMask(3, masks[mi]), (int)MD_TableIsInMask(4, masks[mi]));
            }

            /* the three range validators, each at both edges and one past each */
            printf("md_entryid %d%d%d%d\n", (int)MD_ValidEntryId(0), (int)MD_ValidEntryId(1),
                   (int)MD_ValidEntryId(MD_INTERFACE_DWELL_TABLE_SIZE),
                   (int)MD_ValidEntryId(MD_INTERFACE_DWELL_TABLE_SIZE + 1));
            printf("md_tableid %d%d%d%d\n", (int)MD_ValidTableId(0), (int)MD_ValidTableId(1),
                   (int)MD_ValidTableId(MD_INTERFACE_NUM_DWELL_TABLES),
                   (int)MD_ValidTableId(MD_INTERFACE_NUM_DWELL_TABLES + 1));
            printf("md_fieldlen %d%d%d%d%d%d\n", (int)MD_ValidFieldLength(0),
                   (int)MD_ValidFieldLength(1), (int)MD_ValidFieldLength(2),
                   (int)MD_ValidFieldLength(3), (int)MD_ValidFieldLength(4),
                   (int)MD_ValidFieldLength(5));

            /* The alignment pair. BOTH ARMS MATTER: NASA checks the address and then the SIZE,
             * so (8,6) must be rejected on the size alone -- a translation that dropped the
             * second branch would still pass a test that only ever moved the address. */
            printf("md_a32 %d%d%d%d\n", (int)MD_Verify32Aligned(8, 4), (int)MD_Verify32Aligned(9, 4),
                   (int)MD_Verify32Aligned(8, 6), (int)MD_Verify32Aligned(0, 0));
            printf("md_a16 %d%d%d%d\n", (int)MD_Verify16Aligned(8, 2), (int)MD_Verify16Aligned(7, 2),
                   (int)MD_Verify16Aligned(8, 3), (int)MD_Verify16Aligned(0, 0));

            /* MD_ValidAddrRange is a one-line wrapper over the PSP, so the only thing worth
             * asserting is that it passes the call through and reports both answers. The call
             * COUNTER is the part that says it was really called: a stub returning a constant
             * would satisfy the two booleans on its own. */
            before             = es_psp_validates;
            es_psp_validate_rc = CFE_PSP_SUCCESS;
            k                  = (int)MD_ValidAddrRange(0x00100000, 4);
            es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
            printf("md_addrrange %d%d calls=%ld\n", k, (int)MD_ValidAddrRange(0x00100000, 4),
                   es_psp_validates - before);
            es_psp_validate_rc = CFE_PSP_SUCCESS;

            /* MD_ResolveSymAddr, all three outcomes. The empty-SymName branch is the one the
             * rest of this port's MD exercises stand on. */
            {
                MD_SymAddr_t sa;
                memset(&sa, 0, sizeof(sa));
                sa.Offset = 0x00100040;
                ra        = 0xDEAD;
                printf("md_resolve_off %d %lu\n", (int)MD_ResolveSymAddr(&sa, &ra),
                       (unsigned long)ra);

                strcpy(sa.SymName, "MD_SIM_WINDOW");
                sa.Offset    = 0x20;
                md_sym_rc    = OS_SUCCESS;
                md_sym_addr  = 0x00100000;
                ra           = 0xDEAD;
                printf("md_resolve_sym %d %lu\n", (int)MD_ResolveSymAddr(&sa, &ra),
                       (unsigned long)ra);

                /* a lookup FAILURE must leave the caller's variable alone, which is a
                 * property of the branch and not of the return value */
                md_sym_rc = OS_ERROR;
                ra        = 0xDEAD;
                printf("md_resolve_fail %d %lu\n", (int)MD_ResolveSymAddr(&sa, &ra),
                       (unsigned long)ra);
                md_sym_rc = OS_SUCCESS;
            }

            /* MD_UpdateDwellControlInfo, three shapes of table.
             *   0: three entries, then a TERMINATOR, then a non-null entry after it. NASA's own
             *      comment says entries may follow a terminator and will not be processed, so
             *      the 99 below must not reach Rate.
             *   1: all 25 entries full -- the EntryIndex < MD_INTERFACE_DWELL_TABLE_SIZE bound,
             *      which is the other way out of the loop.
             *   2: terminator first, so all three totals are zero. */
            memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
            MD_AppData.MD_DwellTables[0].Entry[0].Length = 1;
            MD_AppData.MD_DwellTables[0].Entry[0].Delay  = 10;
            MD_AppData.MD_DwellTables[0].Entry[1].Length = 2;
            MD_AppData.MD_DwellTables[0].Entry[1].Delay  = 20;
            MD_AppData.MD_DwellTables[0].Entry[2].Length = 4;
            MD_AppData.MD_DwellTables[0].Entry[2].Delay  = 30;
            MD_AppData.MD_DwellTables[0].Entry[4].Length = 2;
            MD_AppData.MD_DwellTables[0].Entry[4].Delay  = 99;
            for (k = 0; k < MD_INTERFACE_DWELL_TABLE_SIZE; k++)
            {
                MD_AppData.MD_DwellTables[1].Entry[k].Length = 4;
                MD_AppData.MD_DwellTables[1].Entry[k].Delay  = 1;
            }
            for (k = 0; k < 3; k++)
            {
                MD_UpdateDwellControlInfo((uint16)k);
                printf("md_dwell_sum %d %u %u %lu\n", k,
                       (unsigned)MD_AppData.MD_DwellTables[k].AddrCount,
                       (unsigned)MD_AppData.MD_DwellTables[k].DataSize,
                       (unsigned long)MD_AppData.MD_DwellTables[k].Rate);
            }
            /* and the neighbour: table 3 was never touched and must still be zero */
            printf("md_dwell_neigh %u\n",
                   (unsigned)(MD_AppData.MD_DwellTables[3].AddrCount +
                              MD_AppData.MD_DwellTables[3].DataSize +
                              MD_AppData.MD_DwellTables[3].Rate));
        }

        /* --- md_dwell_tbl.c -- WHERE MD MEETS TABLE SERVICES ----------------------------
         * The validation callback the ground's table load is checked by, the three functions
         * under it, and the copy into working state. (The three CFE_TBL_GetAddress editors
         * come in the next block.)
         *
         * ADDRESS VALIDITY HERE IS THE PSP STUB, NOT THE DWELL WINDOW. MD_ValidAddrRange calls
         * CFE_PSP_MemValidateRange, whose return code this driver owns, so "out of range" is
         * set rather than arranged -- which is the only way to reach MD_INVALID_ADDR_ERROR
         * without also changing the address that NASA's event text prints. */
        {
            uint16 n, ac, sz;
            uint32 rate;
            int32  st;
            uint16 bad;
            int    i;

            /* EVERY CALL BELOW IS HOISTED OUT OF ITS printf, and that is not style. All five of
             * these functions EMIT EVS EVENTS, printf evaluates its arguments before printing
             * any of the format string, and the HolyC half prints incrementally with S()/D() --
             * so an inline call puts the event text on opposite sides of its own status line and
             * the two transcripts differ in ORDER while agreeing in content. Measured here as a
             * 26-line diff whose first line was `mdt_null -1073741820` against
             * `mdt_null <event text>`. Sixth instance in this project. */

            md_sim_fill();

            /* (a) the NULL table. First branch, and the only one that returns early. */
            st = MD_TableValidationFunc(NULL);
            printf("mdt_null %ld\n", (long)st);

            /* (b) an invalid Enabled flag. The flag is checked FIRST in the chain, so this
             * holds even with a bad signature underneath it -- which is what the second line
             * asserts, and it is the kind of ordering a reordered translation would lose. */
            memset(&md_load, 0, sizeof(md_load));
            md_load.Enabled = 7;
            st = MD_TableValidationFunc(&md_load);
            printf("mdt_enaflag %ld\n", (long)st);
            memset(md_load.Signature, 'x', sizeof(md_load.Signature)); /* no NUL anywhere */
            st = MD_TableValidationFunc(&md_load);
            printf("mdt_ena_beats_sig %ld\n", (long)st);

            /* (c) a signature with no terminator in 32 bytes, with a VALID enable flag */
            md_load.Enabled = MD_Dwell_States_DISABLED;
            st = MD_TableValidationFunc(&md_load);
            printf("mdt_siglen %ld\n", (long)st);

            /* (d) a valid table: three entries of 2 bytes in the simulated window, delays 1.
             * MD_ReadDwellTable's three outputs are asserted separately from the validation,
             * because NASA DISCARDS its return value at the call site -- the only thing that
             * proves it ran is the numbers it wrote. */
            memset(&md_load, 0, sizeof(md_load));
            strcpy(md_load.Signature, "SIG1");
            md_load.Enabled = MD_Dwell_States_ENABLED;
            for (i = 0; i < 3; i++)
            {
                md_load.Entry[i].Length           = 2;
                md_load.Entry[i].Delay            = 1;
                md_load.Entry[i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x20 + 2 * i;
            }
            ac = 0xFFFF; sz = 0xFFFF; rate = 0xFFFFFFFF;
            st = MD_ReadDwellTable(&md_load, &ac, &sz, &rate);
            printf("mdt_read st=%ld n=%u size=%u rate=%lu\n", (long)st, (unsigned)ac,
                   (unsigned)sz, (unsigned long)rate);
            st = MD_TableValidationFunc(&md_load);
            printf("mdt_valid %ld\n", (long)st);

            /* (e) ENABLED WITH A ZERO TOTAL RATE is the informational case NASA calls out: the
             * load is ACCEPTED and an event says it will never be processed. Status is success,
             * so only the event distinguishes it -- and md_dwell_pkt's md_zerorate line is the
             * other half of the same story. */
            for (i = 0; i < 3; i++)
            {
                md_load.Entry[i].Delay = 0;
            }
            st = MD_TableValidationFunc(&md_load);
            printf("mdt_zerorate %ld\n", (long)st);
            for (i = 0; i < 3; i++)
            {
                md_load.Entry[i].Delay = 1;
            }

            /* (f) MD_ValidTableEntry, one line per error class. The ORDER of NASA's checks is
             * the thing worth pinning: resolve, then range, then length, then alignment -- so a
             * length of 3 at a BAD address is INVALID_ADDR and the same length at a good one is
             * INVALID_LEN. A translation that reordered the chain would still return "an error"
             * for both. */
            {
                MD_TableLoadEntry_t e;
                int32               st;
                memset(&e, 0, sizeof(e));
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_len0 %ld\n", (long)st);

                e.Length = 2;
                strcpy(e.DwellAddress.SymName, "NO_SUCH_SYMBOL");
                md_sym_rc = OS_ERROR;
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_resolve %ld\n", (long)st);
                md_sym_rc = OS_SUCCESS;

                memset(&e, 0, sizeof(e));
                e.Length = 3;
                e.DwellAddress.Offset = MD_SIM_WINDOW_BASE;
                es_psp_validate_rc    = CFE_PSP_INVALID_MEM_ADDR;
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_range %ld\n", (long)st);
                es_psp_validate_rc    = CFE_PSP_SUCCESS;
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_len3 %ld\n", (long)st);

                e.Length = 4;
                e.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 2; /* 4-aligned? no */
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_align4 %ld\n", (long)st);
                e.Length = 2;
                e.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 1; /* 2-aligned? no */
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_align2 %ld\n", (long)st);
                e.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 2;
                st = MD_ValidTableEntry(&e);
                printf("mdt_entry_ok %ld\n", (long)st);
            }

            /* (g) MD_CheckTableEntries KEEPS COUNTING PAST THE FIRST ERROR, which is NASA's
             * own comment and the reason the informational event carries three totals. Entry 1
             * is given an unresolvable symbol, so good=1 bad=1 and the walk still runs to the
             * terminator at entry 3. ErrorEntryArg must be the FIRST bad index, not the last. */
            memset(&md_load, 0, sizeof(md_load));
            for (i = 0; i < 3; i++)
            {
                md_load.Entry[i].Length              = 2;
                md_load.Entry[i].Delay               = 1;
                md_load.Entry[i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x20 + 2 * i;
            }
            strcpy(md_load.Entry[1].DwellAddress.SymName, "NO_SUCH_SYMBOL");
            strcpy(md_load.Entry[2].DwellAddress.SymName, "ALSO_MISSING");
            md_sym_rc = OS_ERROR;
            bad = 0xFFFF;
            st  = MD_CheckTableEntries(&md_load, &bad);
            printf("mdt_check st=%ld firstbad=%u\n", (long)st, (unsigned)bad);
            md_sym_rc = OS_SUCCESS;

            /* (h) MD_CopyUpdatedTbl: the load structure into working state, with the addresses
             * RESOLVED. The entry past the terminator is copied too -- NASA's loop runs all 25
             * rows regardless -- and the derived totals come from MD_UpdateDwellControlInfo at
             * the end of it, so this one line also asserts that call happened. */
            memset(&md_load, 0, sizeof(md_load));
            memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
            strcpy(md_load.Signature, "COPY");
            md_load.Signature[6] = 0x7A;   /* past the NUL, so strncpy's zero-fill is visible */
            md_load.Enabled      = MD_Dwell_States_ENABLED;
            for (i = 0; i < 2; i++)
            {
                md_load.Entry[i].Length              = 4;
                md_load.Entry[i].Delay               = 3;
                md_load.Entry[i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 4 * i;
            }
            md_load.Entry[4].Length              = 1;   /* past the terminator */
            md_load.Entry[4].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x40;
            MD_CopyUpdatedTbl(&md_load, 1);
            printf("mdt_copy ena=%u n=%u size=%u rate=%lu a0=%lu a1=%lu a4=%lu sig=",
                   (unsigned)MD_AppData.MD_DwellTables[1].Enabled,
                   (unsigned)MD_AppData.MD_DwellTables[1].AddrCount,
                   (unsigned)MD_AppData.MD_DwellTables[1].DataSize,
                   (unsigned long)MD_AppData.MD_DwellTables[1].Rate,
                   (unsigned long)MD_AppData.MD_DwellTables[1].Entry[0].ResolvedAddress,
                   (unsigned long)MD_AppData.MD_DwellTables[1].Entry[1].ResolvedAddress,
                   (unsigned long)MD_AppData.MD_DwellTables[1].Entry[4].ResolvedAddress);
            for (i = 0; i < 8; i++)
            {
                printf("%02X", (unsigned char)MD_AppData.MD_DwellTables[1].Signature[i]);
            }
            /* and table 0 is untouched, which is what says TblIndex was honoured */
            printf(" neigh=%u\n", (unsigned)(MD_AppData.MD_DwellTables[0].AddrCount +
                                             MD_AppData.MD_DwellTables[0].Rate));
        }

        /* --- md_dwell_tbl.c, the three CFE_TBL_GetAddress editors -----------------------
         * These are what make MD an APP rather than a library: each asks Table Services for
         * the ground's buffer, edits it in place, tells tbl the buffer was modified, and
         * releases it. Nothing above this point in the whole transcript has used tbl from the
         * outside -- every tbl assertion so far was tbl's own code driven from inside its
         * module -- so this block is the first time the finished tbl module is a dependency
         * rather than a subject.
         *
         * THE SETUP IS THE REAL STARTUP SEQUENCE, the same one the tbl section uses: EarlyInit
         * builds the two mutexes, the 512 KiB pool and the four shared load buffers, and
         * InitData seeds the resource-id spaces. The registration status is PRINTED rather
         * than assumed, because the tbl section records what a failed setup looks like -- every
         * assertion collapsing to one repeated error code -- and a handle of -1 is
         * CFE_TBL_BAD_TABLE_HANDLE, i.e. nothing registered at all.
         *
         * ONE DELIBERATE DIFFERENCE FROM md_app.c: NASA registers with `CFE_TBL_OPT_DEFAULT |
         * CFE_TBL_OPT_CRITICAL`, a table backed by the Critical Data Store. This registers
         * plain OPT_DEFAULT, because the three functions under test do not care -- they take a
         * handle and call GetAddress -- and standing up the CDS belongs to md_app.c's own
         * exercise, where the CRITICAL option is actually the thing being translated. */
        {
            MD_DwellTableLoad_t *rb = NULL;
            int32                st;
            int                  i;
            CFE_TBL_RegistryRec_t *rr;

            /* GIVE BACK THE SLOTS THIS TRANSCRIPT LEAKED. The MemPool table is a FIXED-SIZE
             * RESOURCE SHARED BETWEEN EXERCISES and it is at TEN OF TEN by the time this block
             * runs -- CFE_TBL_EarlyInit is called six times above and only one section returns
             * its pool, so the rest are STALE HANDLES TO ONE BUFFER: CFE_TBL_Global's own 512
             * KiB partition, whose owning record was wiped when a section memset the global.
             * Without this, EarlyInit here fails with "No free MemPool slots available", every
             * handle comes back as CFE_TBL_BAD_TABLE_HANDLE (-1), and all six assertions below
             * collapse to one repeated error code -- which is exactly the failure the tbl
             * section already recorded, from the same cause.
             *
             * DISCRIMINATED BY BASE ADDRESS, NOT BY SIZE. SB's buffer pool is ALSO 524,288
             * bytes -- CFE_PLATFORM_SB_BUF_MEMORY_BYTES and CFE_PLATFORM_TBL_BUF_MEMORY_BYTES
             * are both 512 KiB -- so a size test would delete SB's pool too and break the
             * dwell packet's transmit in the next block. md_sent would then read 0 instead of
             * 2, which is the check that this reclaim was surgical.
             *
             * The COUNT is printed, not the addresses: a cpuaddr cannot be compared across a
             * host process and a QEMU guest, and the count can. */
            {
                int k, freed = 0;
                for (k = 0; k < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; k++)
                {
                    CFE_ES_MemPoolRecord_t *pr = &CFE_ES_Global.MemPoolTable[k];
                    if (CFE_ES_MemPoolRecordIsUsed(pr) &&
                        pr->BaseAddr == (cpuaddr)&CFE_TBL_Global.Buf.Partition)
                    {
                        if (CFE_ES_PoolDelete(pr->PoolID) == CFE_SUCCESS)
                        {
                            freed++;
                        }
                    }
                }
                printf("mdt_poolgc freed=%d\n", freed);
            }
            es_set_ctx(1);
            CFE_TBL_EarlyInit();
            CFE_TBL_InitData();
            CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_C(ES_CTX_APPID(1));
            memset(MD_AppData.MD_TableHandle, 0, sizeof(MD_AppData.MD_TableHandle));
            st = CFE_TBL_Register(&MD_AppData.MD_TableHandle[0], "DWELL_TABLE1",
                                  sizeof(MD_DwellTableLoad_t), CFE_TBL_OPT_DEFAULT,
                                  MD_TableValidationFunc);
            printf("mdt_reg st=%ld h=%d\n", (long)st, (int)MD_AppData.MD_TableHandle[0]);

            /* AND THE TABLE HAS TO BE LOADED BEFORE IT CAN BE EDITED. A freshly registered
             * table has no data, so CFE_TBL_GetAddress answers CFE_TBL_ERR_NEVER_LOADED
             * (0xCC000005) and all three editors take their error arm -- which is correct cFE
             * behaviour and was the first thing this block measured. The ground loads and then
             * edits, so the exercise does too. Loading from an ADDRESS rather than a file
             * because the file path is the one thing in a dump/load round trip that cannot be
             * compared (docs/CFS_PLAN.md on the uninitialised dump header). */
            memset(&md_load, 0, sizeof(md_load));
            strcpy(md_load.Signature, "LOADED");
            md_load.Enabled = MD_Dwell_States_DISABLED;
            for (i = 0; i < 3; i++)
            {
                md_load.Entry[i].Length              = 2;
                md_load.Entry[i].Delay               = 1;
                md_load.Entry[i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x20 + 2 * i;
            }
            st = CFE_TBL_Load(MD_AppData.MD_TableHandle[0], CFE_TBL_SRC_ADDRESS, &md_load);
            printf("mdt_load %ld\n", (long)st);

            /* THE REGISTRY RECORD, BY NAME. CFE_TBL_Modified's only observable effect is
             * RegRecPtr->Status.IsModified (and TimeOfLastUpdate, which is a time and cannot be
             * compared), and without reading it the Modified call in all three editors is
             * UNEXERCISED -- measured: deleting it from MD_UpdateTableEnabledField left the
             * transcript byte-identical, because the readback reads the same buffer the editor
             * wrote and does not care whether tbl was told. Resolved by name rather than by a
             * hard-coded index, which the tbl section records as a mistake it already made
             * seven times. The full name is the app prefix plus what Register was given. */
            /* THE REGISTRY RECORD, BY NAME. CFE_TBL_FindTableInRegistry returns a RESOURCE
             * ID, not an array index -- it came back as 0x1c0001, which indexes nothing -- so
             * the by-name locator is the right accessor and needs no index arithmetic at all. */
            rr = CFE_TBL_LocateRegRecByName("CFE_EVS.DWELL_TABLE1");
            printf("mdt_regrec found=%d name=%s\n", (int)(rr != NULL),
                   rr ? CFE_TBL_RegRecGetName(rr) : "?");

            /* (i) the ENABLED field. Written through the handle, then read back through a
             * SECOND GetAddress -- not from the pointer the editor used, which it released.
             * IsModified is CLEARED first, so reading it back is an assertion about this call
             * and not about whatever ran before. */
            if (rr != NULL)
            {
                rr->Status.IsModified = false;
            }
            st = MD_UpdateTableEnabledField(0, MD_Dwell_States_ENABLED);
            rb = NULL;
            i  = (int)CFE_TBL_GetAddress((void **)&rb, MD_AppData.MD_TableHandle[0]);
            printf("mdt_upd_ena st=%ld get=%d ena=%u mod=%d\n", (long)st, i,
                   (unsigned)(rb ? rb->Enabled : 0xFFFF),
                   (int)(rr != NULL ? rr->Status.IsModified : -1));
            CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);

            /* (j) one dwell entry. NASA takes MD_SymAddr_t BY VALUE here and the translation
             * takes a pointer -- docs/HOLYC_STRUCT_LIMITS.md #26, 72 bytes against an 8-byte
             * limit -- so the C half is called the way NASA declares it and the HolyC half
             * with an address. The READBACK is what makes that deviation safe to assert: the
             * whole 72 bytes have to arrive, which is precisely what a by-value call in HolyC
             * would NOT do. */
            {
                MD_SymAddr_t na;
                memset(&na, 0, sizeof(na));
                na.Offset = MD_SIM_WINDOW_BASE + 0x30;
                strcpy(na.SymName, "SYM_IN_ENTRY");
                if (rr != NULL)
                {
                    rr->Status.IsModified = false;
                }
                st = MD_UpdateTableDwellEntry(0, 2, 4, 9, na);
            }
            rb = NULL;
            i  = (int)CFE_TBL_GetAddress((void **)&rb, MD_AppData.MD_TableHandle[0]);
            printf("mdt_upd_dwell mod=%d st=%ld get=%d len=%u dly=%u off=%lu sym=%s\n",
                   (int)(rr != NULL ? rr->Status.IsModified : -1), (long)st, i,
                   (unsigned)(rb ? rb->Entry[2].Length : 0),
                   (unsigned)(rb ? rb->Entry[2].Delay : 0),
                   (unsigned long)(rb ? rb->Entry[2].DwellAddress.Offset : 0),
                   rb ? rb->Entry[2].DwellAddress.SymName : "?");
            CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);

            /* (k) the signature, and the bytes PAST its terminator, for the same reason as
             * md_dwell_pkt's: strncpy zero-fills and a memcpy would not. The buffer is poisoned
             * first so the zero-fill is observable -- the measured lesson from that block. */
            rb = NULL;
            CFE_TBL_GetAddress((void **)&rb, MD_AppData.MD_TableHandle[0]);
            if (rb != NULL)
            {
                memset(rb->Signature, 0x5A, sizeof(rb->Signature));
            }
            CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
            if (rr != NULL)
            {
                rr->Status.IsModified = false;
            }
            st = MD_UpdateTableSignature(0, "NEWSIG");
            rb = NULL;
            i  = (int)CFE_TBL_GetAddress((void **)&rb, MD_AppData.MD_TableHandle[0]);
            printf("mdt_upd_sig mod=%d st=%ld get=%d sig=",
                   (int)(rr != NULL ? rr->Status.IsModified : -1), (long)st, i);
            for (i = 0; i < 10; i++)
            {
                printf("%02X", (unsigned char)(rb ? rb->Signature[i] : 0));
            }
            printf(" last=%d\n", (int)(rb ? rb->Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1] : -1));
            CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);

            /* (l) AND ALL THREE ON A BAD HANDLE, which is the error arm each of them has. -1 is
             * CFE_TBL_BAD_TABLE_HANDLE; GetAddress refuses it and each editor raises its own
             * event and returns what GetAddress returned -- NOT CFE_SUCCESS, which the success
             * arm sets explicitly. Three different event ids for one shape of failure. */
            MD_AppData.MD_TableHandle[3] = -1;
            st = MD_UpdateTableEnabledField(3, MD_Dwell_States_ENABLED);
            printf("mdt_bad_ena %ld\n", (long)st);
            {
                MD_SymAddr_t na;
                memset(&na, 0, sizeof(na));
                st = MD_UpdateTableDwellEntry(3, 0, 1, 1, na);
            }
            printf("mdt_bad_dwell %ld\n", (long)st);
            st = MD_UpdateTableSignature(3, "X");
            printf("mdt_bad_sig %ld\n", (long)st);
        }

        /* --- md_cmds.c -- the six ground commands ---------------------------------------
         * THE TABLE FROM THE BLOCK ABOVE IS REUSED RATHER THAN RE-REGISTERED. Nothing between
         * here and there memsets CFE_TBL_Global, so MD_AppData.MD_TableHandle[0] is still a
         * registered and loaded CFE_EVS.DWELL_TABLE1 -- and re-running CFE_TBL_EarlyInit would
         * take another MemPool slot from a table that was at 10/10 before this transcript
         * reclaimed two. The occupancy is printed once as a TRIPWIRE: if it ever reads 10/10
         * again, that line says so immediately instead of six assertions cascading into -1
         * handles.
         *
         * HANDLES 1..3 ARE DELIBERATELY NOT REGISTERED, and that is what makes the partial
         * failure reachable. Start and Stop walk a MASK, call MD_UpdateTableEnabledField for
         * every table in it, and count the failures -- so a mask of 0x0003 succeeds for table 1
         * and fails for table 2, which is the "failed for %d of %d tables" arm. A command can
         * partly succeed, and Status and the two counters move independently.
         *
         * EVERY CALL IS HOISTED. All six handlers emit EVS events, so an inline call in a
         * printf argument would put the event text on the wrong side of its own status line --
         * the ordering trap this file has now hit six times. */
        {
            MD_StartDwellCmd_t   sd;
            MD_StopDwellCmd_t    pd;
            MD_JamDwellCmd_t     jd;
            MD_SetSignatureCmd_t sg;
            MD_NoopCmd_t         np;
            MD_ResetCountersCmd_t rc;
            MD_DwellTableLoad_t *rb = NULL;
            int32                st;
            int                  k, used = 0;

            for (k = 0; k < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; k++)
            {
                if (CFE_ES_MemPoolRecordIsUsed(&CFE_ES_Global.MemPoolTable[k]))
                {
                    used++;
                }
            }
            printf("mdc_pools %d/%d\n", used, CFE_PLATFORM_ES_MAX_MEMORY_POOLS);

            memset(&np, 0, sizeof(np));
            memset(&rc, 0, sizeof(rc));
            memset(&sd, 0, sizeof(sd));
            memset(&pd, 0, sizeof(pd));
            memset(&jd, 0, sizeof(jd));
            memset(&sg, 0, sizeof(sg));
            MD_AppData.CommandCounter      = 0;
            MD_AppData.CommandErrorCounter = 0;

            /* (a) Noop and ResetCounters. The Noop event carries the VERSION, which is the only
             * place those four constants reach the transcript. */
            st = MD_NoopCmd(&np);
            printf("mdc_noop st=%ld cc=%u ec=%u\n", (long)st, (unsigned)MD_AppData.CommandCounter,
                   (unsigned)MD_AppData.CommandErrorCounter);
            MD_AppData.CommandErrorCounter = 9;
            st                             = MD_ResetCountersCmd(&rc);
            printf("mdc_reset st=%ld cc=%u ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandCounter,
                   (unsigned)MD_AppData.CommandErrorCounter);

            /* (b) START on the registered table alone: the nominal arm. Countdown of 1 is what
             * makes the next wakeup issue a packet, so all four control fields are asserted. */
            sd.Payload.TableMask = 0x0001;
            st                   = MD_StartDwellCmd(&sd);
            printf("mdc_start1 st=%ld cc=%u ec=%u ena=%u cd=%lu cur=%u off=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandCounter, (unsigned)MD_AppData.CommandErrorCounter,
                   (unsigned)MD_AppData.MD_DwellTables[0].Enabled,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Countdown,
                   (unsigned)MD_AppData.MD_DwellTables[0].CurrentEntry,
                   (unsigned)MD_AppData.MD_DwellTables[0].PktOffset);

            /* (c) START on tables 1 AND 2: table 2 has no registered table, so the editor fails
             * for it and succeeds for table 1 -- "failed for 1 of 2 tables". The CONTROL
             * STRUCTURE is still updated for both, because NASA writes it before calling the
             * editor; only the Table Services copy is missed. That asymmetry is the point. */
            sd.Payload.TableMask = 0x0003;
            st                   = MD_StartDwellCmd(&sd);
            printf("mdc_start12 st=%ld cc=%u ec=%u ena2=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandCounter, (unsigned)MD_AppData.CommandErrorCounter,
                   (unsigned)MD_AppData.MD_DwellTables[1].Enabled);

            /* (d) an EMPTY mask: no table in it at all */
            sd.Payload.TableMask = 0x0000;
            st                   = MD_StartDwellCmd(&sd);
            printf("mdc_startnone st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);

            /* (e) STOP, both arms. Note Countdown goes to ZERO here where Start set it to 1. */
            pd.Payload.TableMask = 0x0001;
            st                   = MD_StopDwellCmd(&pd);
            printf("mdc_stop1 st=%ld cc=%u ena=%u cd=%lu\n", (long)st,
                   (unsigned)MD_AppData.CommandCounter,
                   (unsigned)MD_AppData.MD_DwellTables[0].Enabled,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Countdown);
            pd.Payload.TableMask = 0x0000;
            st                   = MD_StopDwellCmd(&pd);
            printf("mdc_stopnone st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);

            /* (f) JAM argument checks, which are index bounds and so are checked FIRST.
             *
             * EACH LINE CARRIES THE ERROR COUNTER, AND IT HAS TO. MD_JamDwellCmd sets Status to
             * CFE_SUCCESS at the top and an argument rejection only clears AllInputsValid, so
             * EVERY line below returns st=0 -- exactly what a function that did nothing would
             * return. The first version of this block printed the status alone and asserted
             * nothing about nine separate rejections. The counter is the signal; the status is
             * not. (NASA's own bookkeeping says so: the else arm at the end of the function
             * increments CommandErrorCounter and leaves Status untouched.) */
            jd.Payload.TableId = 0;
            jd.Payload.EntryId = 1;
            st                 = MD_JamDwellCmd(&jd);
            printf("mdc_jam_tbl0 st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            jd.Payload.TableId = MD_INTERFACE_NUM_DWELL_TABLES + 1;
            st                 = MD_JamDwellCmd(&jd);
            printf("mdc_jam_tblhi st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            jd.Payload.TableId = 1;
            jd.Payload.EntryId = 0;
            st                 = MD_JamDwellCmd(&jd);
            printf("mdc_jam_ent0 st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            jd.Payload.EntryId = MD_INTERFACE_DWELL_TABLE_SIZE + 1;
            st                 = MD_JamDwellCmd(&jd);
            printf("mdc_jam_enthi st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);

            /* (g) A VALID JAM, then the derived totals. The table is given three 2-byte entries
             * with delays first so the null-jam below has something to truncate. */
            for (k = 0; k < 3; k++)
            {
                MD_AppData.MD_DwellTables[0].Entry[k].Length          = 2;
                MD_AppData.MD_DwellTables[0].Entry[k].Delay           = 2;
                MD_AppData.MD_DwellTables[0].Entry[k].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x20;
            }
            MD_UpdateDwellControlInfo(0);
            printf("mdc_before n=%u size=%u rate=%lu\n",
                   (unsigned)MD_AppData.MD_DwellTables[0].AddrCount,
                   (unsigned)MD_AppData.MD_DwellTables[0].DataSize,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Rate);

            jd.Payload.TableId              = 1;
            jd.Payload.EntryId              = 3;
            jd.Payload.FieldLength          = 4;
            jd.Payload.DwellDelay           = 7;
            jd.Payload.DwellAddress.Offset  = MD_SIM_WINDOW_BASE + 0x40; /* 4-aligned */
            jd.Payload.DwellAddress.SymName[0] = '\0';
            st                              = MD_JamDwellCmd(&jd);
            printf("mdc_jam_ok st=%ld cc=%u len=%u dly=%u addr=%lu n=%u size=%u rate=%lu\n",
                   (long)st, (unsigned)MD_AppData.CommandCounter,
                   (unsigned)MD_AppData.MD_DwellTables[0].Entry[2].Length,
                   (unsigned)MD_AppData.MD_DwellTables[0].Entry[2].Delay,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Entry[2].ResolvedAddress,
                   (unsigned)MD_AppData.MD_DwellTables[0].AddrCount,
                   (unsigned)MD_AppData.MD_DwellTables[0].DataSize,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Rate);
            /* and the Table Services copy got it too -- read back through the handle, as a
             * STRING, because the null-jam path hands MD_UpdateTableDwellEntry a partially
             * initialised 72-byte struct and the bytes past the NUL are stack garbage */
            rb = NULL;
            k  = (int)CFE_TBL_GetAddress((void **)&rb, MD_AppData.MD_TableHandle[0]);
            printf("mdc_jam_tbl get=%d len=%u dly=%u off=%lu\n", k,
                   (unsigned)(rb ? rb->Entry[2].Length : 0),
                   (unsigned)(rb ? rb->Entry[2].Delay : 0),
                   (unsigned long)(rb ? rb->Entry[2].DwellAddress.Offset : 0));
            CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);

            /* (h) A NULL JAM, AND THE SILENT CONSEQUENCE. MD_ValidFieldLength ACCEPTS 0, so a
             * Jam with FieldLength 0 is the "null out this entry" command -- the status is
             * success either way. Nulling entry 2 TERMINATES the table there, and
             * MD_UpdateDwellControlInfo stops at the first zero Length, so AddrCount, DataSize
             * and Rate all drop even though two live entries still follow it. Only the derived
             * totals show that. */
            jd.Payload.EntryId     = 2;
            jd.Payload.FieldLength = 0;
            st                     = MD_JamDwellCmd(&jd);
            /* e2dly IS NOT DECORATION. The null path zeroes Length, Delay AND
             * ResolvedAddress, and the three derived totals can only see the Length: once an
             * entry is terminated, MD_UpdateDwellControlInfo stops there and NEVER READS that
             * entry's Delay. Measured -- deleting `DwellEntryPtr->Delay = 0;` left the whole
             * transcript byte-identical, because Rate was already 2 either way. The field has
             * to be read directly or the write is unexercised. */
            printf("mdc_jam_null st=%ld cc=%u n=%u size=%u rate=%lu e2len=%u e2dly=%u"
                   " e2addr=%lu e3len=%u\n",
                   (long)st, (unsigned)MD_AppData.CommandCounter,
                   (unsigned)MD_AppData.MD_DwellTables[0].AddrCount,
                   (unsigned)MD_AppData.MD_DwellTables[0].DataSize,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Rate,
                   (unsigned)MD_AppData.MD_DwellTables[0].Entry[1].Length,
                   (unsigned)MD_AppData.MD_DwellTables[0].Entry[1].Delay,
                   (unsigned long)MD_AppData.MD_DwellTables[0].Entry[1].ResolvedAddress,
                   (unsigned)MD_AppData.MD_DwellTables[0].Entry[2].Length);

            /* (i) the JAM rejection paths, one per event. The address ones are why the dwell
             * window is a literal: NASA prints "address 0x%08X" from the resolved cpuaddr. */
            jd.Payload.EntryId     = 4;
            jd.Payload.FieldLength = 2;
            strcpy(jd.Payload.DwellAddress.SymName, "NO_SUCH_SYMBOL");
            md_sym_rc = OS_ERROR;
            st        = MD_JamDwellCmd(&jd);
            printf("mdc_jam_resolve st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            md_sym_rc                          = OS_SUCCESS;
            jd.Payload.DwellAddress.SymName[0] = '\0';

            jd.Payload.FieldLength = 3;
            st                     = MD_JamDwellCmd(&jd);
            printf("mdc_jam_len3 st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);

            jd.Payload.FieldLength = 2;
            es_psp_validate_rc     = CFE_PSP_INVALID_MEM_ADDR;
            st                     = MD_JamDwellCmd(&jd);
            printf("mdc_jam_range st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            es_psp_validate_rc = CFE_PSP_SUCCESS;

            jd.Payload.FieldLength         = 4;
            jd.Payload.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x42; /* not 4-aligned */
            st                             = MD_JamDwellCmd(&jd);
            printf("mdc_jam_al4 st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            jd.Payload.FieldLength         = 2;
            jd.Payload.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x41; /* not 2-aligned */
            st                             = MD_JamDwellCmd(&jd);
            printf("mdc_jam_al2 %ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);

            /* (j) SET SIGNATURE: the length check comes FIRST, before the table id, so an
             * unterminated signature is rejected even with a bad table id underneath it. */
            memset(sg.Payload.Signature, 'z', sizeof(sg.Payload.Signature)); /* no NUL */
            sg.Payload.TableId = 99;
            st                 = MD_SetSignatureCmd(&sg);
            printf("mdc_sig_len st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            memset(sg.Payload.Signature, 0, sizeof(sg.Payload.Signature));
            strcpy(sg.Payload.Signature, "CMDSIG");
            sg.Payload.TableId = 99;
            st                 = MD_SetSignatureCmd(&sg);
            printf("mdc_sig_tbl st=%ld ec=%u\n", (long)st,
                   (unsigned)MD_AppData.CommandErrorCounter);
            sg.Payload.TableId = 1;
            st                 = MD_SetSignatureCmd(&sg);
            printf("mdc_sig_ok st=%ld cc=%u sig=%s\n", (long)st,
                   (unsigned)MD_AppData.CommandCounter,
                   MD_AppData.MD_DwellTables[0].Signature);
            /* and the Table Services copy, which MD_UpdateTableSignature wrote */
            rb = NULL;
            k  = (int)CFE_TBL_GetAddress((void **)&rb, MD_AppData.MD_TableHandle[0]);
            printf("mdc_sig_tblcopy get=%d sig=%s\n", k, rb ? rb->Signature : "?");
            CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
        }

        /* --- md_dwell_pkt.c -------------------------------------------------------------
         * The part of MD that actually reads memory. Four functions: the loop, the one read,
         * the send, and a three-line reset.
         *
         * THE DWELL BYTES ARE READ BACK WITH THEIR NEIGHBOURS. MD_GetDwellData's write is
         * `memcpy(&Data[TblPtr->PktOffset], &MemReadVal, NumBytes)` -- a 1-, 2- or 4-byte
         * store at a variable offset, which is the exact shape of the two codegen bugs in
         * docs (an 8-byte store emitted for a narrow one, and a wild store for a deep
         * variable index). Data[] is poisoned with 0xEE before each write and the bytes on
         * BOTH SIDES of the written region are printed, so a store that is too wide shows up
         * as a missing 0xEE rather than as a value that happens to look right. */
        {
            MD_DwellPacketControl_t *T = &MD_AppData.MD_DwellTables[0];
            MD_DwellPkt_t           *P = &MD_AppData.MD_DwellPkt[0];
            int                      i, n;
            CFE_MSG_Size_t           msz;
            uint32                   md_sends0;
            long                     r0;

            md_sim_fill();
            memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
            memset(MD_AppData.MD_DwellPkt, 0, sizeof(MD_AppData.MD_DwellPkt));
            /* INITIALISE THE PACKET HEADER, because without it MD_SendDwellPkt's transmit is
             * REJECTED and the send path is not exercised at all. The first version of this
             * block memset the packet and never called CFE_MSG_Init, so every
             * CFE_SB_TransmitMsg produced `Send Err:Invalid MsgId(0x0)in msg` -- identical on
             * both halves, so the transcript was satisfied while the function under test did
             * nothing. Found by reading the EVS text a mutation happened to print. This is
             * what md_app.c does at startup. */
            CFE_MSG_Init(CFE_MSG_PTR(P->TelemetryHeader),
                         CFE_SB_ValueToMsgId(MD_DWELL_PKT_MID_BASE), sizeof(MD_DwellPkt_t));

            /* (a) one write per width, each into a poisoned packet, neighbours printed */
            for (n = 0; n < 3; n++)
            {
                static const uint16 widths[3] = {1, 2, 4};
                memset(P->Payload.Data, 0xEE, sizeof(P->Payload.Data));
                T->Entry[0].Length          = widths[n];
                T->Entry[0].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x10;
                T->PktOffset                = 4;
                r0                          = md_sim_reads;
                i                           = (int)MD_GetDwellData(0, 0);
                printf("md_get w=%u st=%d off=%u reads=%ld data=", (unsigned)widths[n], i,
                       (unsigned)T->PktOffset, md_sim_reads - r0);
                for (i = 0; i < 10; i++)
                {
                    printf("%02X", P->Payload.Data[i]);
                }
                printf("\n");
            }

            /* (b) the four error returns, and the fact that PktOffset advances ANYWAY --
             * NASA's `TblPtr->PktOffset += NumBytes` sits OUTSIDE the success branch, so a
             * failed read still moves the write cursor. That is behaviour, not a bug, and it
             * is invisible to a test that only looks at the status. */
            for (n = 0; n < 4; n++)
            {
                static const uint16 badw[4] = {1, 2, 4, 3};
                memset(P->Payload.Data, 0xEE, sizeof(P->Payload.Data));
                T->Entry[0].Length = badw[n];
                /* widths 1,2,4 get an address OUTSIDE the window; width 3 is invalid itself */
                T->Entry[0].ResolvedAddress = (badw[n] == 3) ? (MD_SIM_WINDOW_BASE + 0x10) : 0x900;
                T->PktOffset                = 4;
                i                           = (int)MD_GetDwellData(0, 0);
                printf("md_get_err w=%u st=%d off=%u untouched=%d\n", (unsigned)badw[n], i,
                       (unsigned)T->PktOffset, (int)(P->Payload.Data[4] == 0xEE));
            }

            /* (c) MD_StartDwellStream, three lines and all three asserted */
            T->Countdown = 99;
            T->CurrentEntry = 7;
            T->PktOffset = 33;
            MD_StartDwellStream(0);
            printf("md_start %u %u %u\n", (unsigned)T->Countdown, (unsigned)T->CurrentEntry,
                   (unsigned)T->PktOffset);

            /* (d) THE LOOP. Three entries of two bytes each, one delay apiece, so Rate is 3
             * and each wakeup collects exactly one entry; the third fills the packet and sends
             * it. Printed after every call, because the interesting part is the STATE MACHINE
             * and not the final packet. */
            memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
            memset(P->Payload.Data, 0xEE, sizeof(P->Payload.Data));
            for (i = 0; i < 3; i++)
            {
                T->Entry[i].Length          = 2;
                T->Entry[i].Delay           = 1;
                T->Entry[i].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x20 + 2 * i;
            }
            MD_UpdateDwellControlInfo(0);
            T->Enabled = MD_Dwell_States_ENABLED;
            strcpy(T->Signature, "DW0");
            /* AND A BYTE AFTER THE TERMINATOR, because without it this test asserts nothing.
             * Measured: replacing NASA's strncpy with a plain memcpy of the same length left
             * the transcript BYTE-IDENTICAL, because the source field had been memset to zero
             * and a verbatim copy of zeros is indistinguishable from a zero-fill. The control
             * passed, which means the setup -- not the code -- was doing the work. With 0x7A
             * sitting past the NUL, strncpy still zero-fills the destination and a memcpy
             * carries the 0x7A across, and only the bytes AFTER the terminator show it. */
            T->Signature[5] = 0x7A;
            MD_StartDwellStream(0);
            /* AND A WITNESS THAT THE PACKET WAS REALLY TRANSMITTED. MD_SendDwellPkt returns
             * void, so nothing it does is observable from its own result; SB's own
             * NoSubscribersCounter is incremented by CFE_SB_TransmitMsg on a valid MsgId with
             * no subscribers, which is exactly this case. A send that is rejected for a bad
             * MsgId does NOT increment it, which is what makes it the right witness. */
            md_sends0 = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
            for (n = 0; n < 3; n++)
            {
                int st = (int)MD_DwellLoop(NULL);
                printf("md_loop %d st=%d cur=%u off=%u cd=%lu\n", n, st,
                       (unsigned)T->CurrentEntry, (unsigned)T->PktOffset,
                       (unsigned long)T->Countdown);
            }
            /* the packet, read out of MD_AppData rather than off the bus: CFE_SB_TimeStampMsg
             * puts a TIME in the header, which cannot be compared, and the payload is what MD
             * is actually responsible for */
            /* MASKED TO EIGHT BITS, because NoSubscribersCounter is a uint8 and it stood at
             * 254 when this block was reached -- the unmasked difference printed
             * 4294967042. A witness that wraps is not a witness. */
            printf("md_sent %lu\n",
                   (unsigned long)((CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter -
                                    md_sends0) & 0xFF));
            CFE_MSG_GetSize(CFE_MSG_PTR(P->TelemetryHeader), &msz);
            printf("md_pkt id=%u n=%u rate=%u bytes=%u size=%lu data=", (unsigned)P->Payload.TableId,
                   (unsigned)P->Payload.AddrCount, (unsigned)P->Payload.Rate,
                   (unsigned)P->Payload.ByteCount, (unsigned long)msz);
            for (i = 0; i < 10; i++)
            {
                printf("%02X", P->Payload.Data[i]);
            }
            /* AND THE SIGNATURE PAST ITS TERMINATOR. NASA copies it with strncpy, which
             * ZERO-FILLS the rest of the field; a MemCpy would carry whatever followed the
             * source string instead, and only the bytes AFTER the NUL would show it. */
            printf(" sig=");
            for (i = 0; i < 6; i++)
            {
                printf("%02X", (unsigned char)P->Payload.Signature[i]);
            }
            printf(" last=%d\n", (int)P->Payload.Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1]);

            /* (e) A ZERO-RATE TABLE IS NEVER PROCESSED, and that guard is load-bearing rather
             * than defensive: with every Delay zero, MD_DwellLoop's `while (Countdown == 0)`
             * would reload Countdown with a zero delay after sending and spin forever. The
             * Rate > 0 test is the only thing standing between this app and a hang. */
            memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
            for (i = 0; i < 3; i++)
            {
                T->Entry[i].Length          = 1;
                T->Entry[i].Delay           = 0;
                T->Entry[i].ResolvedAddress = MD_SIM_WINDOW_BASE;
            }
            MD_UpdateDwellControlInfo(0);
            T->Enabled = MD_Dwell_States_ENABLED;
            MD_StartDwellStream(0);
            r0 = md_sim_reads;
            n  = (int)MD_DwellLoop(NULL);
            printf("md_zerorate st=%d rate=%lu cd=%lu reads=%ld\n", n, (unsigned long)T->Rate,
                   (unsigned long)T->Countdown, md_sim_reads - r0);

            /* (f) THE ALREADY-FULL BRANCH: CurrentEntry >= AddrCount on entry, which NASA
             * reaches when a table is shortened after data was written. It sends immediately
             * and reloads Countdown from the LAST entry's delay. */
            memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
            for (i = 0; i < 3; i++)
            {
                T->Entry[i].Length          = 1;
                T->Entry[i].Delay           = 5 + i;
                T->Entry[i].ResolvedAddress = MD_SIM_WINDOW_BASE;
            }
            MD_UpdateDwellControlInfo(0);
            T->Enabled      = MD_Dwell_States_ENABLED;
            T->CurrentEntry = T->AddrCount;
            T->Countdown    = 42;
            r0              = md_sim_reads;
            md_sends0       = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
            n               = (int)MD_DwellLoop(NULL);
            /* THE WITNESS READS 2 PER DWELL PACKET, AND THAT IS THE POINT OF PRINTING IT.
             * The dwell send finds no subscribers, which increments this counter and makes SB
             * raise CFE_SB_SEND_NO_SUBS_EID; EVS then TRANSMITS that event packet over SB
             * (cfe_evs_utils.c:498) on MsgId 0x809, which also has no subscribers, and the
             * counter moves again. Verified rather than assumed: 0x809 accounts for 113 of the
             * 119 no-subscriber lines in this transcript.
             *
             * I first predicted 1 here, on the theory that cfe_sb_priv.c's SEND_NO_SUBS
             * REQUEST BIT made the event a per-route one-shot. It is not: both sends to 0x891
             * raise an event and both move the counter by 2. The prediction was wrong and the
             * second witness is what said so, which is why there are two of them. */
            printf("md_full st=%d cur=%u off=%u cd=%lu reads=%ld sent=%lu\n", n,
                   (unsigned)T->CurrentEntry, (unsigned)T->PktOffset,
                   (unsigned long)T->Countdown, md_sim_reads - r0,
                   (unsigned long)((CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter -
                                    md_sends0) & 0xFF));
        }

        /* --- md_app.c and md_dispatch.c -- MD's startup, loop and front door ------------
         * The last two sources, and a CYCLE: MD_AppMain calls MD_TaskPipe from the dispatcher
         * and the dispatcher's switch calls MD_SendHkCmd from the app. module_deps.py reports
         * them as 775 lines that have to go in together -- and it only said so once its owner
         * map stopped attributing MD_TaskPipe to the EDS variant.
         *
         * THIS BLOCK IS LAST AMONG THE MD BLOCKS ON PURPOSE. It re-runs CFE_TBL_EarlyInit to
         * clear the registry so MD can register its OWN four tables -- and the md_cmds block
         * depends on the table the md_dwell_tbl block registered. Placed earlier, it pulled
         * that table out from under md_cmds and every editor there answered
         * CFE_TBL_ERR_NEVER_LOADED: a 54-line diff that was entirely self-inflicted.
         *
         * MD_AppMain IS CALLED AFTER THE PIPE IT NEEDS IS ALREADY TAKEN, and that is a hang I
         * measured rather than reasoned about. Its loop treats CFE_SB_TIME_OUT as "no action",
         * so on a real pipe with MD_SB_TIMEOUT of 1000 ms nothing ends it. An AppInit that
         * FAILS sets APP_ERROR, and RunLoop's FIRST test -- on the caller's own RunStatus,
         * before any record lookup -- skips the loop. Calling MD_InitSoftwareBusServices first
         * takes MD_CMD_PIPE, so AppInit's CreatePipe refuses the duplicate. Each init function
         * is then exercised on its SUCCESS path directly and its FAILURE path through AppMain.
         *
         * Pre-setting the app's ControlReq did NOT work, and a direct MD_AppInit() call showed
         * why the loop was not the problem at all: it already returned 0xCA000005. `sample` on
         * the live process named the real culprit in one line -- CFE_ES_ExitApp waiting in
         * OS_TaskDelay, because this app is EXTERNAL and only a CORE app's ExitApp returns.
         * Reasoning got it wrong twice; the stack got it immediately. */
        {
            MD_SendHkCmd_t   hk;
            int32            st;
            int              k, used;
            long             x0;
            MD_HkTlm_t      *hp;

            for (used = 0, k = 0; k < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; k++)
            {
                CFE_ES_MemPoolRecord_t *pr = &CFE_ES_Global.MemPoolTable[k];
                if (CFE_ES_MemPoolRecordIsUsed(pr) &&
                    pr->BaseAddr == (cpuaddr)&CFE_TBL_Global.Buf.Partition)
                {
                    if (CFE_ES_PoolDelete(pr->PoolID) == CFE_SUCCESS)
                    {
                        used++;
                    }
                }
            }
            printf("mda_poolgc freed=%d\n", used);
            es_set_ctx(1);
            CFE_TBL_EarlyInit();
            CFE_TBL_InitData();
            CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_C(ES_CTX_APPID(1));
            for (used = 0, k = 0; k < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; k++)
            {
                if (CFE_ES_MemPoolRecordIsUsed(&CFE_ES_Global.MemPoolTable[k]))
                {
                    used++;
                }
            }
            printf("mda_pools %d/%d\n", used, CFE_PLATFORM_ES_MAX_MEMORY_POOLS);

            /* (a) MD_InitControlStructures: four zeroed blocks with Countdown 1, which is what
             * makes the first wakeup collect rather than wait. The Signature is strncpy'd from
             * "" over the whole field, so a byte DEEP in it must be zero too -- the field is
             * poisoned with 0xCC first so that says something. */
            memset(MD_AppData.MD_DwellTables, 0xCC, sizeof(MD_AppData.MD_DwellTables));
            MD_InitControlStructures();
            printf("mda_ctrl cd=%lu,%lu,%lu,%lu ena=%u sig0=%u sig20=%u n=%u\n",
                   (unsigned long)MD_AppData.MD_DwellTables[0].Countdown,
                   (unsigned long)MD_AppData.MD_DwellTables[1].Countdown,
                   (unsigned long)MD_AppData.MD_DwellTables[2].Countdown,
                   (unsigned long)MD_AppData.MD_DwellTables[3].Countdown,
                   (unsigned)MD_AppData.MD_DwellTables[0].Enabled,
                   (unsigned char)MD_AppData.MD_DwellTables[0].Signature[0],
                   (unsigned char)MD_AppData.MD_DwellTables[0].Signature[20],
                   (unsigned)MD_AppData.MD_DwellTables[0].AddrCount);

            /* (b) MD_InitSoftwareBusServices, the success path: the HK packet gets its MsgId,
             * four dwell packets get theirs, MD_CMD_PIPE is created and three subscriptions
             * made. The HK id is read back OUT of the header, because CFE_MSG_Init is the only
             * thing that puts it there. */
            MD_AppData.CmdPipe = CFE_SB_INVALID_PIPE;
            st                 = MD_InitSoftwareBusServices();
            {
                CFE_SB_MsgId_t mid = CFE_SB_INVALID_MSG_ID;
                CFE_MSG_GetMsgId(CFE_MSG_PTR(MD_AppData.HkPkt.TelemetryHeader), &mid);
                printf("mda_sbs st=%ld pipe=%d hkmid=0x%04x\n", (long)st,
                       (int)CFE_RESOURCEID_TEST_DEFINED(MD_AppData.CmdPipe),
                       (unsigned)CFE_SB_MsgIdToValue(mid));
            }

            /* (c) MD_InitTableServices, four CRITICAL tables. The names are built by snprintf
             * from MD_DWELL_TABLE_BASENAME, so printing two of them asserts that loop. The
             * file /cf/md_dw01.tbl EXISTS on this driver's RAM disk but is a dump of ANOTHER
             * table left by an earlier section, so CFE_TBL_Load answers
             * CFE_TBL_ERR_FILE_FOR_WRONG_TABLE and NASA's loop stops at the FIRST table --
             * which is why one handle is set and the fourth name is empty. NASA's event 102
             * names the offending file and table in the transcript. */
            memset(MD_AppData.MD_TableHandle, 0, sizeof(MD_AppData.MD_TableHandle));
            st = MD_InitTableServices();
            printf("mda_tbl st=%ld h=%d,%d,%d,%d names=%s,%s\n", (long)st,
                   (int)MD_AppData.MD_TableHandle[0], (int)MD_AppData.MD_TableHandle[1],
                   (int)MD_AppData.MD_TableHandle[2], (int)MD_AppData.MD_TableHandle[3],
                   MD_AppData.MD_TableName[0], MD_AppData.MD_TableName[3]);

            /* (d) MD_ManageDwellTable with nothing pending: GetStatus answers CFE_SUCCESS,
             * which matches none of the three cases, so the final else sets the flag and the
             * function returns that status. The point is that it TERMINATES -- the body is a
             * `while (!FinishedManaging)` whose only exit is one of four branches setting the
             * flag, and a translation that missed one would HANG rather than differ. */
            printf("mda_manage %ld\n", (long)MD_ManageDwellTable(0));

            /* (e) MD_SendHkCmd: the control state projected into the packet. The enable MASK is
             * the field worth checking -- each flag is shifted into its own bit, so tables 1
             * and 3 enabled must give 0x0005 and not 0x0003. */
            MD_AppData.CommandCounter                 = 11;
            MD_AppData.CommandErrorCounter            = 22;
            MD_AppData.MD_DwellTables[0].Enabled      = MD_Dwell_States_ENABLED;
            MD_AppData.MD_DwellTables[2].Enabled      = MD_Dwell_States_ENABLED;
            MD_AppData.MD_DwellTables[0].AddrCount    = 3;
            MD_AppData.MD_DwellTables[0].Rate         = 9;
            MD_AppData.MD_DwellTables[0].DataSize     = 6;
            MD_AppData.MD_DwellTables[0].PktOffset    = 4;
            MD_AppData.MD_DwellTables[0].CurrentEntry = 2;
            MD_AppData.MD_DwellTables[0].Countdown    = 5;
            memset(&hk, 0, sizeof(hk));
            st = MD_SendHkCmd(&hk);
            hp = &MD_AppData.HkPkt;
            printf("mda_hk st=%ld valid=%u invalid=%u mask=0x%04x n0=%u rate0=%u off0=%u"
                   " bytes0=%u ent0=%u cd0=%u\n",
                   (long)st, (unsigned)hp->Payload.ValidCmdCntr,
                   (unsigned)hp->Payload.InvalidCmdCntr, (unsigned)hp->Payload.DwellEnabledMask,
                   (unsigned)hp->Payload.DwellTblAddrCount[0],
                   (unsigned)hp->Payload.NumWaitsPerPkt[0],
                   (unsigned)hp->Payload.DwellPktOffset[0], (unsigned)hp->Payload.ByteCount[0],
                   (unsigned)hp->Payload.DwellTblEntry[0], (unsigned)hp->Payload.Countdown[0]);

            /* (f) MD_AppMain. THE APP MUST BE A **CORE** APP FOR ExitApp TO RETURN -- see the
             * note at the top of this block. And exits=0 IS NOT THE WITNESS: for a CORE app
             * with APP_ERROR, rather than one of the CORE_APP_*_ERROR statuses, ExitApp
             * REFUSES and logs `Cannot Exit CORE Application`. That syslog line is what proves
             * ExitApp was reached; a zero count is also what "never called" looks like. */
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
            x0                             = es_taskexits;
            MD_AppMain();
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
            printf("mda_appmain exits=%ld run=%lu cc=%u ec=%u\n", es_taskexits - x0,
                   (unsigned long)MD_AppData.RunStatus, (unsigned)MD_AppData.CommandCounter,
                   (unsigned)MD_AppData.CommandErrorCounter);
        
            /* --- md_dispatch.c: the length check, the switch, and the pipe router ---------
             * A CFE_SB_Buffer_t is only an 8-byte ALIGNMENT UNION, so a command is built in an
             * MD_JamDwellCmd_t -- the largest of the six at 88 bytes -- and its address passed
             * as the buffer. `&BufPtr->Msg` is at offset 0 either way, which is what makes
             * that substitution exact rather than convenient.
             *
             * THE COUNTERS ARE THE WITNESS, not the return values: MD_ProcessGroundCommand and
             * MD_TaskPipe both return void, and MD_VerifyCmdLength's bool says only whether
             * the length matched. What proves a command was ROUTED is which counter moved. */
            {
                MD_JamDwellCmd_t *cb = &md_dcmd;
                uint8             ccs[6];
                size_t            szs[6];
                int               i2;

                ccs[0] = MD_NOOP_CC;          szs[0] = sizeof(MD_NoopCmd_t);
                ccs[1] = MD_RESET_CNTRS_CC;   szs[1] = sizeof(MD_ResetCountersCmd_t);
                ccs[2] = MD_START_DWELL_CC;   szs[2] = sizeof(MD_StartDwellCmd_t);
                ccs[3] = MD_STOP_DWELL_CC;    szs[3] = sizeof(MD_StopDwellCmd_t);
                ccs[4] = MD_JAM_DWELL_CC;     szs[4] = sizeof(MD_JamDwellCmd_t);
                ccs[5] = MD_SET_SIGNATURE_CC; szs[5] = sizeof(MD_SetSignatureCmd_t);

                /* (g) MD_VerifyCmdLength both ways. The mismatch arm raises an event AND
                 * increments the error counter, so the counter is what separates them. */
                memset(cb, 0, sizeof(*cb));
                CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(MD_CMD_MID),
                             sizeof(MD_NoopCmd_t));
                MD_AppData.CommandErrorCounter = 0;
                i2 = (int)MD_VerifyCmdLength(CFE_MSG_PTR(cb->Header), sizeof(MD_NoopCmd_t));
                printf("mdd_len ok=%d ec=%u\n", i2, (unsigned)MD_AppData.CommandErrorCounter);
                i2 = (int)MD_VerifyCmdLength(CFE_MSG_PTR(cb->Header), sizeof(MD_NoopCmd_t) + 1);
                printf("mdd_len bad=%d ec=%u\n", i2, (unsigned)MD_AppData.CommandErrorCounter);

                /* (h) every command code through the switch, each with ITS OWN correct length
                 * so VerifyCmdLength passes and the handler actually runs. The counters after
                 * each dispatch are what say which arm was taken: a routing error would move
                 * the wrong one or neither. */
                for (i2 = 0; i2 < 6; i2++)
                {
                    memset(cb, 0, sizeof(*cb));
                    CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(MD_CMD_MID),
                                 szs[i2]);
                    CFE_MSG_SetFcnCode(CFE_MSG_PTR(cb->Header), ccs[i2]);
                    /* give Jam and SetSignature arguments that reach their success arm */
                    cb->Payload.TableId    = 1;
                    cb->Payload.EntryId    = 1;
                    cb->Payload.FieldLength = 0;
                    MD_AppData.CommandCounter      = 0;
                    MD_AppData.CommandErrorCounter = 0;
                    MD_ProcessGroundCommand((CFE_SB_Buffer_t *)cb);
                    printf("mdd_cc%d cc=%u ec=%u\n", (int)ccs[i2],
                           (unsigned)MD_AppData.CommandCounter,
                           (unsigned)MD_AppData.CommandErrorCounter);
                }

                /* (i) a command code nothing claims: the default arm */
                memset(cb, 0, sizeof(*cb));
                CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(MD_CMD_MID),
                             sizeof(MD_NoopCmd_t));
                CFE_MSG_SetFcnCode(CFE_MSG_PTR(cb->Header), 99);
                MD_AppData.CommandErrorCounter = 0;
                MD_ProcessGroundCommand((CFE_SB_Buffer_t *)cb);
                printf("mdd_badcc ec=%u\n", (unsigned)MD_AppData.CommandErrorCounter);

                /* (j) THE PIPE ROUTER, all four branches. MD_TaskPipe caches the three message
                 * ids in STATIC LOCALS on its first call -- named CMD_MID, SEND_HK_MID and
                 * WAKE_UP_MID, the same names cfe_es_dispatch, cfe_evs_dispatch and
                 * cfe_ta_dispatch already use. Those three collided once when a HolyC static
                 * local became a global under its bare name, and MD is the FOURTH user in one
                 * translation unit; if the scoping regressed, MD's cache would hold a cFE
                 * module's id and these four lines would route to the wrong handler. That is
                 * the check, not an aside.
                 *
                 * A WAKEUP runs the dwell loop, so md_sim_reads is its witness. A HK request
                 * runs MD_SendHkCmd, so the packet's ValidCmdCntr is its witness. A ground
                 * command with NOOP moves CommandCounter. An unknown id moves the error
                 * counter and nothing else. */
                md_sim_fill();
                memset(MD_AppData.MD_DwellTables, 0, sizeof(MD_AppData.MD_DwellTables));
                MD_AppData.MD_DwellTables[0].Enabled  = MD_Dwell_States_ENABLED;
                MD_AppData.MD_DwellTables[0].Entry[0].Length          = 2;
                MD_AppData.MD_DwellTables[0].Entry[0].Delay           = 1;
                MD_AppData.MD_DwellTables[0].Entry[0].ResolvedAddress = MD_SIM_WINDOW_BASE;
                MD_UpdateDwellControlInfo(0);
                MD_AppData.MD_DwellTables[0].Countdown = 1;
                memset(cb, 0, sizeof(*cb));
                CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(MD_WAKEUP_MID),
                             sizeof(MD_Wakeup_t));
                x0 = md_sim_reads;
                MD_TaskPipe((CFE_SB_Buffer_t *)cb);
                printf("mdd_pipe_wakeup reads=%ld\n", md_sim_reads - x0);

                MD_AppData.CommandCounter = 77;
                memset(cb, 0, sizeof(*cb));
                CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(MD_SEND_HK_MID),
                             sizeof(MD_SendHkCmd_t));
                MD_TaskPipe((CFE_SB_Buffer_t *)cb);
                printf("mdd_pipe_hk valid=%u\n",
                       (unsigned)MD_AppData.HkPkt.Payload.ValidCmdCntr);

                memset(cb, 0, sizeof(*cb));
                CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(MD_CMD_MID),
                             sizeof(MD_NoopCmd_t));
                CFE_MSG_SetFcnCode(CFE_MSG_PTR(cb->Header), MD_NOOP_CC);
                MD_AppData.CommandCounter      = 0;
                MD_AppData.CommandErrorCounter = 0;
                MD_TaskPipe((CFE_SB_Buffer_t *)cb);
                printf("mdd_pipe_cmd cc=%u ec=%u\n", (unsigned)MD_AppData.CommandCounter,
                       (unsigned)MD_AppData.CommandErrorCounter);

                memset(cb, 0, sizeof(*cb));
                CFE_MSG_Init(CFE_MSG_PTR(cb->Header), CFE_SB_ValueToMsgId(0x1899),
                             sizeof(MD_NoopCmd_t));
                MD_AppData.CommandCounter      = 0;
                MD_AppData.CommandErrorCounter = 0;
                MD_TaskPipe((CFE_SB_Buffer_t *)cb);
                printf("mdd_pipe_badmid cc=%u ec=%u\n", (unsigned)MD_AppData.CommandCounter,
                       (unsigned)MD_AppData.CommandErrorCounter);
            }
        }

        /* --- mm_utils.c (MM -- THE SECOND cFS APP) -----------------------------------------
         * Eight functions: the housekeeping reset, the segment break, the two parameter
         * validators, the two alignment checks, the address resolver and the file CRC.
         *
         * THE ADDRESSES ARE LITERAL CONSTANTS, for the reason recorded in docs/CFS_PLAN.md and
         * at the top of Kernel/Cfs/mm/mm_msg.HC: every event below renders the address, and a
         * host pointer and a guest pointer never agree. 0x00100000 is the base of the same
         * simulated window MD uses, and nothing here reads memory through it -- the PSP's
         * range check is this driver's own stub, so the address only has to be a NUMBER.
         *
         * AND THE RENDERING IS "%p", WHICH NO EARLIER GATED SOURCE USED. Six of these events
         * print "Addr = %p"; StrPrintN did not implement the conversion, and an unhandled one
         * does not consume its argument, so every argument after it would have shifted.
         * tools/cfs/check_formats.py is the static gate for that, and these lines are the
         * dynamic one. NO EXERCISE HERE PASSES ADDRESS ZERO THROUGH %p: C leaves the null
         * rendering implementation-defined and the two mainstream libcs disagree about it
         * ("0x0" against "(nil)"), which is a difference between HOSTS and not between halves.
         *
         * THE TWO VALIDATORS ARE WALKED AS A GRID, not as a list, because NASA's own comment
         * says the correctness of the cross product rests on MaxSize STAYING ZERO for the
         * (MemType, VerifyType) pairs no branch sets -- the zero then fails the size check at
         * the end. A list of hand-picked calls cannot say that; 42 cells can. */
        {
            cpuaddr                   A = 0x00100000; /* 8-aligned, and never zero: see above */
            int                       mt, vt, k;
            size_t                    widths[3];
            int32                     sv[8];
            uint32                    crc;
            osal_id_t                 fd;
            long                      before;
            CFE_ES_PerfData_t        *Perf = &CFE_ES_Global.ResetDataPtr->Perf;
            CFE_ES_StartPerfDataCmd_t spc;
            MM_SymAddr_t              sa;

            /* --- MM_ResetHk. IT CLEARS WHAT THE LAST COMMAND REPORTED AND NOTHING ELSE, which
             * is two properties and not one: the six payload fields go to their cleared values,
             * and the two COUNTERS are untouched -- this runs at the start of every command, so
             * a reset that cleared the counters would erase MM's whole command history.
             *
             * FileName[1] IS IN THE LINE DELIBERATELY. NASA writes only FileName[0], making it
             * an empty C STRING rather than a cleared buffer, so the 'Y' must survive. A
             * translation that reached for memset would pass a test that only read [0]. */
            MM_AppData.HkTlm.Payload.CommandCounter      = 11;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 22;
            MM_AppData.HkTlm.Payload.LastAction          = MM_LastAction_FILL;
            MM_AppData.HkTlm.Payload.MemType             = MM_MemType_MEM16;
            MM_AppData.HkTlm.Payload.Address             = CFE_ES_MEMADDRESS_C(0x00100040);
            MM_AppData.HkTlm.Payload.DataValue           = 0xAABBCCDD;
            MM_AppData.HkTlm.Payload.BytesProcessed      = 77;
            MM_AppData.HkTlm.Payload.FileName[0]         = 'Z';
            MM_AppData.HkTlm.Payload.FileName[1]         = 'Y';
            MM_ResetHk();
            printf("mmu_resethk la=%u mt=%u addr=%lu dv=%u bp=%u fn0=%u fn1=%u cc=%u ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.FileName[0],
                   (unsigned)MM_AppData.HkTlm.Payload.FileName[1],
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* --- MM_SegmentBreak. THREE CALLS AND NOT ONE DELAY, and the delay is the weakest
             * of the three witnesses: MM_INTERNAL_PROCESSOR_CYCLE is 0 in this configuration,
             * so summing the MILLISECONDS would be a zero against a zero -- evs_delays counts
             * CALLS for exactly that reason. The two performance-log entries are the real
             * assertion: 31 and 31 with the exit bit set, which pins the marker AND says both
             * stamps ran. Dropping PerfLogExit leaves a transcript that still says "it
             * delayed". The log is started here rather than assumed, because every other block
             * in this file has had its turn with it. */
            CFE_ES_Global.BackgroundPerfDumpState.CurrentState = CFE_ES_PerfDumpState_IDLE;
            CFE_ES_Global.BackgroundPerfDumpState.PendingState  = CFE_ES_PerfDumpState_IDLE;
            /* THE FILTER MASK IS SET HERE AND NOT LEFT TO StartPerfDataCmd, which does not
             * touch it: only a POWER-ON reset initialises the mask, and the es block earlier in
             * this file both zeroes the whole Perf area and then drives
             * CFE_ES_SetPerfFilterMaskCmd. The first run of this block recorded NOTHING for
             * exactly that reason -- a zero DataCount against a zero, with no event to say why,
             * because StartPerfDataCmd's own acknowledgement is a DEBUG event and this
             * configuration filters those out. */
            for (k = 0; k < CFE_ES_PERF_8BIT_WORDS_IN_MASK; k++)
            {
                Perf->MetaData.FilterMask[k]  = 0xFF;
                Perf->MetaData.TriggerMask[k] = 0x00;
            }
            memset(&spc, 0, sizeof(spc));
            spc.Payload.TriggerMode = CFE_ES_PerfTrigger_START;
            CFE_ES_StartPerfDataCmd(&spc);
            before = evs_delays;
            MM_SegmentBreak();
            printf("mmu_segbreak n=%u e0=0x%08lx e1=0x%08lx delays=%ld\n",
                   (unsigned)Perf->MetaData.DataCount,
                   (unsigned long)Perf->DataBuffer[0].Data,
                   (unsigned long)Perf->DataBuffer[1].Data, evs_delays - before);

            /* --- the alignment pair. BOTH ARMS MATTER, the same way MD's do: NASA checks the
             * address and then the SIZE, so (A, 6) must be rejected on the size alone. */
            printf("mmu_a32 %d%d%d%d\n", (int)MM_Verify32Aligned(A + 8, 4),
                   (int)MM_Verify32Aligned(A + 9, 4), (int)MM_Verify32Aligned(A + 8, 6),
                   (int)MM_Verify32Aligned(A, 0));
            printf("mmu_a16 %d%d%d%d\n", (int)MM_Verify16Aligned(A + 8, 2),
                   (int)MM_Verify16Aligned(A + 7, 2), (int)MM_Verify16Aligned(A + 8, 3),
                   (int)MM_Verify16Aligned(A, 0));

            /* --- MM_VerifyPeekPokeParams, as a grid: three legal widths against the five
             * memory types and one illegal type. THE STATUSES ARE COLLECTED BEFORE THEY ARE
             * PRINTED, because the calls EMIT EVENTS -- a printf interleaved with the loop
             * would be cut in half by the first event and the line would not exist.
             *
             * The diagonal is the point: RAM and EEPROM take any legal width, while MEM8,
             * MEM16 and MEM32 take exactly one each. That is a property of the hardware behind
             * the memory type and not of the command, and it is six rejections that a
             * translation dropping the `else if (SizeInBytes != N)` arms would turn into six
             * acceptances. */
            widths[0] = MM_INTERNAL_BYTE_BIT_WIDTH;
            widths[1] = MM_INTERNAL_WORD_BIT_WIDTH;
            widths[2] = MM_INTERNAL_DWORD_BIT_WIDTH;
            for (k = 0; k < 3; k++)
            {
                for (mt = 0; mt < 6; mt++)
                {
                    /* 1..5 are the five real memory types; the sixth column is 9, which is not
                     * a type at all. Written as an if rather than a ?: so the HolyC half can be
                     * read line for line against this one. */
                    int t = mt + 1;
                    if (mt == 5)
                    {
                        t = 9;
                    }
                    sv[mt] = MM_VerifyPeekPokeParams(A, (MM_MemType_Enum_t)t, widths[k]);
                }
                printf("mmu_pp w=%lu ram=%ld eep=%ld m8=%ld m16=%ld m32=%ld bad=%ld\n",
                       (unsigned long)widths[k], (long)sv[0], (long)sv[1], (long)sv[2],
                       (long)sv[3], (long)sv[4], (long)sv[5]);
            }
            /* An illegal WIDTH short-circuits before the memory type is looked at, so it is
             * called once rather than six times -- and 0xFFFFFFFF is the interesting value,
             * because the event renders it through NASA's (unsigned int) cast. */
            printf("mmu_pp_badw %ld %ld\n",
                   (long)MM_VerifyPeekPokeParams(A, MM_MemType_RAM, 7),
                   (long)MM_VerifyPeekPokeParams(A, MM_MemType_RAM, 0xFFFFFFFF));

            /* The misalignment arms, which the grid above cannot reach: it uses an 8-aligned
             * address throughout. */
            printf("mmu_pp_align %ld %ld %ld\n",
                   (long)MM_VerifyPeekPokeParams(A + 1, MM_MemType_RAM,
                                                 MM_INTERNAL_WORD_BIT_WIDTH),
                   (long)MM_VerifyPeekPokeParams(A + 1, MM_MemType_RAM,
                                                 MM_INTERNAL_DWORD_BIT_WIDTH),
                   (long)MM_VerifyPeekPokeParams(A + 2, MM_MemType_RAM,
                                                 MM_INTERNAL_DWORD_BIT_WIDTH));

            /* THE CASE OF %p's HEX DIGITS, WHICH NOTHING ABOVE CAN SEE. Every address in this
             * block is 0x001000xx, so its digits are all 0-4 and rendering %p in UPPER case
             * changed the transcript NOT AT ALL -- driven, and the mutation was invisible.
             * 0x00ABCDEF has every letter digit and is odd, so the 16-bit alignment check
             * rejects it and the event prints it. */
            printf("mmu_pp_hexcase %ld\n",
                   (long)MM_VerifyPeekPokeParams(0x00ABCDEF, MM_MemType_RAM,
                                                 MM_INTERNAL_WORD_BIT_WIDTH));

            /* And the PSP refusing the range. The CALL COUNTER is what says the PSP was really
             * asked: both statuses below would be satisfied by a validator that never called
             * it and returned the stub's code from a local variable. */
            before             = es_psp_validates;
            es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
            sv[0]              = MM_VerifyPeekPokeParams(A, MM_MemType_RAM,
                                                         MM_INTERNAL_BYTE_BIT_WIDTH);
            sv[1]              = MM_VerifyPeekPokeParams(A, MM_MemType_EEPROM,
                                                         MM_INTERNAL_BYTE_BIT_WIDTH);
            es_psp_validate_rc = CFE_PSP_SUCCESS;
            printf("mmu_pp_psp %ld %ld calls=%ld\n", (long)sv[0], (long)sv[1],
                   es_psp_validates - before);

            /* --- MM_VerifyLoadDumpParams, THE GRID. Seven memory types (0 and 6 are not
             * types) against six verification types (5 is not one), at a size of 16 bytes.
             *
             * WHY 16 AND NOT 4. It is above MM_INTERNAL_MAX_DUMP_INEVENT_BYTES, which is 15,
             * and below every other limit -- so DumpInEvent's column REJECTS while the other
             * four accept, and the grid distinguishes five different MaxSize values rather
             * than agreeing on "small enough for all of them". VerifyType 5 is refused before
             * the switch runs and emits NOTHING, which is the one cell with no event. */
            for (mt = 0; mt < 7; mt++)
            {
                for (vt = 0; vt < 6; vt++)
                {
                    sv[vt] = MM_VerifyLoadDumpParams(A, (MM_MemType_Enum_t)mt, 16, (uint8)vt);
                }
                printf("mmu_ldv mt=%d dump=%ld load=%ld evt=%ld fill=%ld wid=%ld bad=%ld\n", mt,
                       (long)sv[0], (long)sv[1], (long)sv[2], (long)sv[3], (long)sv[4],
                       (long)sv[5]);
            }

            /* The size boundaries, one pair per limit the grid above could only prove was
             * "bigger than 16". Each pair is MaxSize and MaxSize+1, so it pins the number. */
            sv[0] = MM_VerifyLoadDumpParams(A, MM_MemType_RAM, 1048576, MM_VERIFY_LOAD);
            sv[1] = MM_VerifyLoadDumpParams(A, MM_MemType_RAM, 1048577, MM_VERIFY_LOAD);
            sv[2] = MM_VerifyLoadDumpParams(A, MM_MemType_EEPROM, 131072, MM_VERIFY_LOAD);
            sv[3] = MM_VerifyLoadDumpParams(A, MM_MemType_EEPROM, 131073, MM_VERIFY_LOAD);
            printf("mmu_ldv_lim ram=%ld,%ld eep=%ld,%ld\n", (long)sv[0], (long)sv[1],
                   (long)sv[2], (long)sv[3]);
            sv[0] = MM_VerifyLoadDumpParams(A, MM_MemType_RAM, 15, MM_VERIFY_EVENT);
            sv[1] = MM_VerifyLoadDumpParams(A, MM_MemType_RAM, 200, MM_VERIFY_WID);
            sv[2] = MM_VerifyLoadDumpParams(A, MM_MemType_RAM, 201, MM_VERIFY_WID);
            /* ZERO IS ITS OWN REJECTION, written as `(SizeInBytes == 0) ||` rather than falling
             * out of the comparison -- an unsigned 0 is not greater than any MaxSize. */
            sv[3] = MM_VerifyLoadDumpParams(A, MM_MemType_RAM, 0, MM_VERIFY_DUMP);
            printf("mmu_ldv_edge evt15=%ld wid200=%ld wid201=%ld zero=%ld\n", (long)sv[0],
                   (long)sv[1], (long)sv[2], (long)sv[3]);

            /* The alignment arms, and MEM8's ABSENCE of one. MEM32 and MEM16 check the address
             * and the size; MEM8 has no check at all, because every address is byte aligned --
             * so the last of these four must be ACCEPTED, and it is the cell that says the
             * three arms were not written as one. */
            sv[0] = MM_VerifyLoadDumpParams(A + 1, MM_MemType_MEM32, 4, MM_VERIFY_LOAD);
            sv[1] = MM_VerifyLoadDumpParams(A, MM_MemType_MEM32, 6, MM_VERIFY_LOAD);
            sv[2] = MM_VerifyLoadDumpParams(A + 1, MM_MemType_MEM16, 2, MM_VERIFY_LOAD);
            sv[3] = MM_VerifyLoadDumpParams(A, MM_MemType_MEM16, 3, MM_VERIFY_LOAD);
            sv[4] = MM_VerifyLoadDumpParams(A + 1, MM_MemType_MEM8, 3, MM_VERIFY_LOAD);
            printf("mmu_ldv_align m32=%ld,%ld m16=%ld,%ld m8=%ld\n", (long)sv[0], (long)sv[1],
                   (long)sv[2], (long)sv[3], (long)sv[4]);

            /* --- THE MEMORY TYPE'S NAME, which only the last event in the function prints.
             * Five calls, five strings, and nothing else in MM reads MemTypeStr -- so without
             * these five the four snprintf call sites could all write "MEM_RAM", or nothing at
             * all, and every line above would be unchanged. */
            es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
            for (mt = 1; mt <= 5; mt++)
            {
                sv[mt - 1] = MM_VerifyLoadDumpParams(A, (MM_MemType_Enum_t)mt, 4, MM_VERIFY_LOAD);
            }
            es_psp_validate_rc = CFE_PSP_SUCCESS;
            printf("mmu_ldv_mtstr %ld %ld %ld %ld %ld\n", (long)sv[0], (long)sv[1], (long)sv[2],
                   (long)sv[3], (long)sv[4]);

            /* --- MM_ResolveSymAddr, all three outcomes, as MD's sibling does. The empty-name
             * branch is the one every MM exercise after this one stands on. */
            memset(&sa, 0, sizeof(sa));
            sa.Offset = 0x00100040;
            {
                cpuaddr ra = 0xDEAD;
                printf("mmu_resolve_off %ld %lu\n", (long)MM_ResolveSymAddr(&sa, &ra),
                       (unsigned long)ra);
                strcpy(sa.SymName, "MM_SIM_WINDOW");
                sa.Offset   = 0x20;
                md_sym_rc   = OS_SUCCESS;
                md_sym_addr = 0x00100000;
                ra          = 0xDEAD;
                printf("mmu_resolve_sym %ld %lu\n", (long)MM_ResolveSymAddr(&sa, &ra),
                       (unsigned long)ra);
                /* A LOOKUP FAILURE LEAVES THE CALLER'S VARIABLE ALONE, which is a property of
                 * the branch and not of the return value. */
                md_sym_rc = OS_ERROR;
                ra        = 0xDEAD;
                printf("mmu_resolve_fail %ld %lu\n", (long)MM_ResolveSymAddr(&sa, &ra),
                       (unsigned long)ra);
                md_sym_rc = OS_SUCCESS;
                /* THE NUL AT THE VERY END IS WRITTEN UNCONDITIONALLY, before anything looks at
                 * the name, and that is a safety measure on a 64-byte array the ground filled.
                 * Filling all 64 bytes with 'A' makes the last byte the only thing that can
                 * stop OS_strnlen at 63 -- and because the name is then NOT empty, the lookup
                 * runs, which is how we know the truncation happened rather than the array
                 * being read as empty. */
                memset(sa.SymName, 'A', CFE_MISSION_MAX_PATH_LEN);
                sa.Offset = 0x10;
                ra        = 0xDEAD;
                sv[0]     = MM_ResolveSymAddr(&sa, &ra);
                printf("mmu_resolve_nul %ld %lu len=%lu last=%u\n", (long)sv[0],
                       (unsigned long)ra,
                       (unsigned long)OS_strnlen(sa.SymName, CFE_MISSION_MAX_PATH_LEN),
                       (unsigned)sa.SymName[CFE_MISSION_MAX_PATH_LEN - 1]);
            }

            /* --- MM_ComputeCRCFromFile. 450 BYTES, WHICH IS THREE READS of the 200-byte
             * buffer: 200, 200 and 50. One read would not prove the loop folds the previous CRC
             * in, and a file that divided evenly would not prove the SHORT last read is handled
             * -- CFE_ES_CalculateCRC is called with ByteCntr, not with the buffer size. */
            for (k = 0; k < 450; k++)
            {
                fs_data[k] = (unsigned char)((k * 7 + 3) & 0xFF);
            }
            fs_len     = 450;
            fs_noexist = 0;
            OS_OpenCreate(&fd, "/ram/mm.crc", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            crc = 0xA5A5A5A5;
            printf("mmu_crc rc=%ld crc=0x%08lx pos=%ld\n",
                   (long)MM_ComputeCRCFromFile(fd, &crc, MM_INTERNAL_LOAD_FILE_CRC_TYPE),
                   (unsigned long)crc, fs_pos);
            /* AN EMPTY FILE IS NOT AN ERROR: the first read returns 0, the loop never folds
             * anything in, and *CrcPtr is written with the initial 0. The poison is what says
             * the write happened at all. */
            fs_len = 0;
            OS_OpenCreate(&fd, "/ram/mm.crc", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            crc = 0xA5A5A5A5;
            printf("mmu_crc_empty rc=%ld crc=0x%08lx\n",
                   (long)MM_ComputeCRCFromFile(fd, &crc, MM_INTERNAL_LOAD_FILE_CRC_TYPE),
                   (unsigned long)crc);
            /* AND A READ ERROR MUST NOT TOUCH *CrcPtr, which is the only branch in this
             * function that does not write it -- so the poison has to still be there. This is
             * the first exercise in the port to make OS_read FAIL; the knob defaults to zero
             * and no existing line can see it. */
            fs_len     = 450;
            OS_OpenCreate(&fd, "/ram/mm.crc", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            crc        = 0xA5A5A5A5;
            fs_read_rc = OS_ERROR;
            printf("mmu_crc_err rc=%ld crc=0x%08lx\n",
                   (long)MM_ComputeCRCFromFile(fd, &crc, MM_INTERNAL_LOAD_FILE_CRC_TYPE),
                   (unsigned long)crc);
            fs_read_rc = 0;
        }

        /* --- mm_mem8.c -- THE FIRST SOURCE IN THE PORT THAT WRITES MEMORY -----------------
         * Three functions, one shape: a segment loop that moves up to 200 bytes, then calls
         * MM_SegmentBreak so something else can run. The simulated window is 256 bytes, so 250
         * is TWO segments -- 200 and 50 -- which is the smallest size that exercises both the
         * short last segment and the break between them.
         *
         * MM_PSP_READ_ERR_EID IS NOT DRIVEN HERE AND THAT IS DELIBERATE. Its text prints
         * `Tgt=%p`, which is `&ioBuffer8[i]` -- a REAL POINTER into MM_AppData.DumpBuffer, not
         * an address the ground supplied. Every other address in MM's events is a constant that
         * came from a command and is the same number on both halves; this one is wherever the
         * linker put MM_AppData. See the note at the top of Kernel/Cfs/mm/mm_mem8.HC. */
        {
            cpuaddr                 A8 = MD_SIM_WINDOW_BASE;
            MM_FillMemCmd_t         fc;
            MM_LoadDumpFileHeader_t fh;
            osal_id_t               fd8;
            CFE_ES_PerfData_t      *P8 = &CFE_ES_Global.ResetDataPtr->Perf;
            long                    w0, p0;
            int                     k8;
            int32                   st8;

            /* --- MM_FillMem8. THE PATTERN IS TRUNCATED TO ONE BYTE and housekeeping reports
             * the TRUNCATED value, so 0xAABBCCDD must come back as 0xDD -- the app telling the
             * operator what it actually wrote rather than what they asked for.
             *
             * md_sim_writes IS THE WITNESS THAT THE LOOP RAN. MM computes BytesProcessed from
             * its own segment arithmetic and never from the stores, so a fill that stored
             * nothing would report 250 anyway. [250] is the neighbour: the fill must stop. */
            md_sim_fill();
            memset(&fc, 0, sizeof(fc));
            fc.Payload.NumOfBytes  = 250;
            fc.Payload.FillPattern = 0xAABBCCDD;
            memset(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
            w0  = md_sim_writes;
            p0  = P8->MetaData.DataCount;
            st8 = MM_FillMem8(A8, &fc);
            printf("mm8_fill st=%ld writes=%ld perf=%ld m0=%02X m199=%02X m200=%02X m249=%02X "
                   "m250=%02X\n",
                   (long)st8, md_sim_writes - w0, (long)(P8->MetaData.DataCount - p0),
                   md_sim_mem[0], md_sim_mem[199], md_sim_mem[200], md_sim_mem[249],
                   md_sim_mem[250]);
            printf("mm8_fill_hk la=%u mt=%u addr=%lu dv=0x%08x bp=%u fnZ=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned char)MM_AppData.HkTlm.Payload.FileName[0]);

            /* A STORE THAT FAILS PART WAY THROUGH, at offset 100. The event prints the address
             * it stopped at; the loop breaks; BytesProcessed never reaches 250, so the SHORT
             * arm turns the status into CFE_PSP_ERROR and HOUSEKEEPING IS LEFT ALONE -- which
             * is why the two HK fields below must still read the previous fill's values. */
            md_sim_fill();
            md_sim_wfail_at = 100;
            w0              = md_sim_writes;
            st8             = MM_FillMem8(A8, &fc);
            md_sim_wfail_at = -1;
            printf("mm8_fill_err st=%ld writes=%ld m99=%02X m100=%02X bp=%u dv=0x%08x\n",
                   (long)st8, md_sim_writes - w0, md_sim_mem[99], md_sim_mem[100],
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue);

            /* --- MM_LoadMem8FromFile. The file is 250 bytes of a pattern that is NOT what
             * md_sim_fill leaves behind, so the window's contents after the load say the bytes
             * came from the file rather than from anywhere else.
             *
             * THE FILENAME GOES THROUGH strncpy, WHICH ZERO-FILLS. The destination is poisoned
             * with 'Z' first and byte 20 is printed: a MemCpy would leave the 'Z' there. */
            md_sim_fill();
            for (k8 = 0; k8 < 250; k8++)
            {
                fs_data[k8] = (unsigned char)(0x80 + k8);
            }
            fs_len     = 250;
            fs_noexist = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fd8, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            memset(&fh, 0, sizeof(fh));
            fh.NumOfBytes = 250;
            memset(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
            w0  = md_sim_writes;
            p0  = P8->MetaData.DataCount;
            st8 = MM_LoadMem8FromFile(fd8, "/ram/mm8.ld", &fh, A8);
            printf("mm8_load st=%ld writes=%ld perf=%ld m0=%02X m199=%02X m200=%02X m249=%02X "
                   "m250=%02X\n",
                   (long)st8, md_sim_writes - w0, (long)(P8->MetaData.DataCount - p0),
                   md_sim_mem[0], md_sim_mem[199], md_sim_mem[200], md_sim_mem[249],
                   md_sim_mem[250]);
            printf("mm8_load_hk la=%u mt=%u addr=%lu bp=%u fn=[%s] fn20=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   MM_AppData.HkTlm.Payload.FileName,
                   (unsigned char)MM_AppData.HkTlm.Payload.FileName[20]);

            /* A FILE THAT RUNS OUT. 100 bytes against a header claiming 250: the first read
             * asks for 200 and gets 100, which is a SHORT READ and not an end of file, so
             * MM_OS_READ_ERR_EID fires with both the count it got and the count it wanted. */
            md_sim_fill();
            fs_len = 100;
            OS_OpenCreate(&fd8, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            w0  = md_sim_writes;
            st8 = MM_LoadMem8FromFile(fd8, "/ram/mm8.ld", &fh, A8);
            printf("mm8_load_short st=%ld writes=%ld m0=%02X bp=%u\n", (long)st8,
                   md_sim_writes - w0, md_sim_mem[0],
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);

            /* A STORE THAT FAILS DURING A LOAD -- the same branch as the fill's, reached from
             * the other caller, and the one that proves the load's error arm is its own code.
             * It also leaves the window PART written, which the fill's error case cannot show
             * because a fill writes the same byte everywhere. */
            md_sim_fill();
            fs_len = 250;
            OS_OpenCreate(&fd8, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            md_sim_wfail_at = 10;
            w0              = md_sim_writes;
            st8             = MM_LoadMem8FromFile(fd8, "/ram/mm8.ld", &fh, A8);
            md_sim_wfail_at = -1;
            printf("mm8_load_wfail st=%ld writes=%ld m9=%02X m10=%02X\n", (long)st8,
                   md_sim_writes - w0, md_sim_mem[9], md_sim_mem[10]);

            /* --- MM_DumpMem8ToFile. The address comes from the FILE HEADER here, not from a
             * parameter -- NASA's own asymmetry with the load above, kept. */
            md_sim_fill();
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fd8, "/ram/mm8.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            memset(&fh, 0, sizeof(fh));
            fh.NumOfBytes        = 250;
            fh.SymAddress.Offset = CFE_ES_MEMADDRESS_C(A8);
            memset(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
            p0  = P8->MetaData.DataCount;
            st8 = MM_DumpMem8ToFile(fd8, "/ram/mm8.dp", &fh);
            printf("mm8_dump st=%ld perf=%ld len=%ld d0=%02X d199=%02X d200=%02X d249=%02X\n",
                   (long)st8, (long)(P8->MetaData.DataCount - p0), fs_len, fs_data[0],
                   fs_data[199], fs_data[200], fs_data[249]);
            printf("mm8_dump_hk la=%u mt=%u addr=%lu bp=%u fn=[%s] fn20=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   MM_AppData.HkTlm.Payload.FileName,
                   (unsigned char)MM_AppData.HkTlm.Payload.FileName[20]);

            /* A FILE THAT WILL NOT TAKE IT ALL. 100 bytes of room against 250 to write: the
             * FIRST write asks for 200 and places 100, so MM_OS_WRITE_EXP_ERR_EID fires and
             * HOUSEKEEPING IS NOT UPDATED -- this function tests the STATUS rather than the
             * byte count, the opposite of the load, so the two HK fields below still hold the
             * dump above's values. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = 100;
            OS_OpenCreate(&fd8, "/ram/mm8.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            st8        = MM_DumpMem8ToFile(fd8, "/ram/mm8.dp", &fh);
            fs_wr_left = -1;
            printf("mm8_dump_short st=%ld len=%ld bp=%u\n", (long)st8, fs_len,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);

            /* --- THE LOAD'S BytesRemaining IS int32 AND THE DUMP'S IS uint32, which is NASA's
             * own inconsistency and is NOT an observable one anywhere above -- so here is the
             * input that makes it observable. A header claiming 0xFFFFFFFF bytes:
             *
             *   the LOAD reads it into an int32, so BytesRemaining is -1, `BytesRemaining <
             *   MM_INTERNAL_MAX_LOAD_DATA_SEG` is TRUE on a signed comparison, and SegmentSize
             *   becomes (size_t)-1. The event then reports `Expected = 4294967295`.
             *
             *   the DUMP reads it into a uint32, 0xFFFFFFFF is NOT less than 200, and the
             *   segment stays the full 200. Its event reports `Expected = 200`.
             *
             * Two numbers in two events, and they are the only thing in the transcript that
             * says the two declarations differ. Making the load's unsigned -- which is what a
             * translator "tidying up" would do -- changes the first to 200.
             *
             * THE DUMP IS FORCED TO FAIL ON THE **WRITE**, with no room in the file at all,
             * rather than being allowed to run off the end of the 256-byte window: running off
             * it reaches MM_PSP_READ_ERR_EID, whose text carries an uncomparable pointer. */
            md_sim_fill();
            fs_len     = 250;
            fs_wr_left = -1;
            OS_OpenCreate(&fd8, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            memset(&fh, 0, sizeof(fh));
            fh.NumOfBytes        = 0xFFFFFFFF;
            fh.SymAddress.Offset = CFE_ES_MEMADDRESS_C(A8);
            w0                   = md_sim_writes;
            st8                  = MM_LoadMem8FromFile(fd8, "/ram/mm8.ld", &fh, A8);
            printf("mm8_load_signed st=%ld writes=%ld\n", (long)st8, md_sim_writes - w0);
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = 0;
            OS_OpenCreate(&fd8, "/ram/mm8.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            st8        = MM_DumpMem8ToFile(fd8, "/ram/mm8.dp", &fh);
            fs_wr_left = -1;
            printf("mm8_dump_unsigned st=%ld len=%ld\n", (long)st8, fs_len);

        }

        /* --- mm_mem16.c and mm_mem32.c -- THE WIDTH TWINS --------------------------------
         * These two are near-copies of mm_mem8.c, so this block does NOT repeat mem8's cases.
         * It drives the FOUR THINGS THAT DIFFER, because that is the entire argument for NASA
         * keeping three files instead of one parameterised loop:
         *
         *   1. THE LOOPS COUNT ELEMENTS, NOT BYTES. A 200-byte segment is 200 stores in mem8,
         *      100 in mem16 and 50 in mem32 -- and md_sim_writes is the only thing that can say
         *      so, because every byte count MM reports comes from its own segment arithmetic.
         *   2. THE FILL ROUNDS THE LENGTH DOWN, with a per-width event id and a per-width
         *      modulus, and then REPORTS AN ERROR ANYWAY -- the housekeeping guard compares
         *      BytesProcessed against the COMMANDED NumOfBytes, which the rounding has just
         *      made unreachable. This is also the input that makes mem8's two "swap the guard"
         *      no-op mutations into real ones here.
         *   3. THE PATTERN IS TRUNCATED TO THE WIDTH, and housekeeping reports the TRUNCATED
         *      value -- 0xCCDD from mem16, the whole 0xAABBCCDD from mem32, which needs no
         *      truncation at all. The window's bytes say which end went first.
         *   4. ONE ERROR, THREE RENDERINGS. The load's write-error event prints the PSP's status
         *      as `0x%08X` in mem8 and mem16 and as `%d` in mem32 -- and mem16 OVERWRITES the
         *      status with CFE_PSP_ERROR before printing it, so the three print 0xFFFFFFEB,
         *      0xFFFFFFFF and -21 for the same failure. A translator who harmonised the three
         *      files would lose all of it, and nothing but these three events would notice. */
        {
            cpuaddr                 AW = MD_SIM_WINDOW_BASE;
            MM_FillMemCmd_t         fcw;
            MM_LoadDumpFileHeader_t fhw;
            osal_id_t               fdw;
            long                    ww, rr;
            int                     kw;
            int32                   stw;

            memset(&fcw, 0, sizeof(fcw));
            fcw.Payload.FillPattern = 0xAABBCCDD;

            /* ===== MEM16 ===== */
            md_sim_fill();
            fcw.Payload.NumOfBytes = 250;
            ww                     = md_sim_writes;
            stw                    = MM_FillMem16(AW, &fcw);
            printf("mm16_fill st=%ld writes=%ld m0=%02X m1=%02X m248=%02X m249=%02X m250=%02X\n",
                   (long)stw, md_sim_writes - ww, md_sim_mem[0], md_sim_mem[1], md_sim_mem[248],
                   md_sim_mem[249], md_sim_mem[250]);
            printf("mm16_fill_hk la=%u mt=%u dv=0x%08x bp=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);
            /* AN ODD LENGTH: warns, rounds 251 down to 250, fills it, and STILL FAILS. The two
             * HK fields below must therefore still read the 250-byte fill above's. */
            md_sim_fill();
            fcw.Payload.NumOfBytes = 251;
            ww                     = md_sim_writes;
            stw                    = MM_FillMem16(AW, &fcw);
            printf("mm16_fill_odd st=%ld writes=%ld bp=%u dv=0x%08x\n", (long)stw,
                   md_sim_writes - ww, (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue);

            /* REFILL THE FILE BEFORE EVERY LOAD. The dumps above write INTO fs_data, and
             * what they write is md_sim_fill's own pattern -- so a load that read the stale
             * file would place bytes INDISTINGUISHABLE from the window's existing contents, and
             * "m0=40" would be satisfied equally by the load working and by it not running at
             * all. It was written that way first and the mem32 lines said 0x40 where they
             * should have said 0x80. */
            for (kw = 0; kw < 250; kw++)
            {
                fs_data[kw] = (unsigned char)(0x80 + kw);
            }
            md_sim_fill();
            fs_len     = 250;
            fs_noexist = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fdw, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            memset(&fhw, 0, sizeof(fhw));
            fhw.NumOfBytes        = 250;
            fhw.SymAddress.Offset = CFE_ES_MEMADDRESS_C(AW);
            ww                    = md_sim_writes;
            stw                   = MM_LoadMem16FromFile(fdw, "/ram/mmw.ld", &fhw, AW);
            printf("mm16_load st=%ld writes=%ld m0=%02X m1=%02X m248=%02X m249=%02X\n",
                   (long)stw, md_sim_writes - ww, md_sim_mem[0], md_sim_mem[1], md_sim_mem[248],
                   md_sim_mem[249]);
            /* THE FIRST OF THE THREE RENDERINGS. Offset 20 is 2-aligned, so the eleventh store
             * is the one that fails; the event prints 0xFFFFFFFF rather than the PSP's own
             * 0xFFFFFFEB, because mem16 overwrites the status before reporting it. */
            /* REFILL THE FILE BEFORE EVERY LOAD. The dumps above write INTO fs_data, and
             * what they write is md_sim_fill's own pattern -- so a load that read the stale
             * file would place bytes INDISTINGUISHABLE from the window's existing contents, and
             * "m0=40" would be satisfied equally by the load working and by it not running at
             * all. It was written that way first and the mem32 lines said 0x40 where they
             * should have said 0x80. */
            for (kw = 0; kw < 250; kw++)
            {
                fs_data[kw] = (unsigned char)(0x80 + kw);
            }
            md_sim_fill();
            fs_len = 250;
            OS_OpenCreate(&fdw, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            md_sim_wfail_at = 20;
            ww              = md_sim_writes;
            stw             = MM_LoadMem16FromFile(fdw, "/ram/mmw.ld", &fhw, AW);
            md_sim_wfail_at = -1;
            printf("mm16_load_wfail st=%ld writes=%ld m18=%02X m20=%02X\n", (long)stw,
                   md_sim_writes - ww, md_sim_mem[18], md_sim_mem[20]);

            md_sim_fill();
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fdw, "/ram/mmw.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            rr  = md_sim_reads;
            stw = MM_DumpMem16ToFile(fdw, "/ram/mmw.dp", &fhw);
            printf("mm16_dump st=%ld reads=%ld len=%ld d0=%02X d1=%02X d249=%02X\n", (long)stw,
                   md_sim_reads - rr, fs_len, fs_data[0], fs_data[1], fs_data[249]);

            /* ===== MEM32. 248 is the aligned length; 250 is not. ===== */
            md_sim_fill();
            fcw.Payload.NumOfBytes = 248;
            ww                     = md_sim_writes;
            stw                    = MM_FillMem32(AW, &fcw);
            printf("mm32_fill st=%ld writes=%ld m0=%02X m1=%02X m2=%02X m3=%02X m247=%02X "
                   "m248=%02X\n",
                   (long)stw, md_sim_writes - ww, md_sim_mem[0], md_sim_mem[1], md_sim_mem[2],
                   md_sim_mem[3], md_sim_mem[247], md_sim_mem[248]);
            /* AND THE PATTERN IS NOT TRUNCATED AT ALL HERE, which is the one of the three
             * widths where the commanded value and the reported value agree. */
            printf("mm32_fill_hk la=%u mt=%u dv=0x%08x bp=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);
            md_sim_fill();
            fcw.Payload.NumOfBytes = 250;
            ww                     = md_sim_writes;
            stw                    = MM_FillMem32(AW, &fcw);
            printf("mm32_fill_unaligned st=%ld writes=%ld bp=%u\n", (long)stw,
                   md_sim_writes - ww, (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);

            /* REFILL THE FILE BEFORE EVERY LOAD. The dumps above write INTO fs_data, and
             * what they write is md_sim_fill's own pattern -- so a load that read the stale
             * file would place bytes INDISTINGUISHABLE from the window's existing contents, and
             * "m0=40" would be satisfied equally by the load working and by it not running at
             * all. It was written that way first and the mem32 lines said 0x40 where they
             * should have said 0x80. */
            for (kw = 0; kw < 250; kw++)
            {
                fs_data[kw] = (unsigned char)(0x80 + kw);
            }
            md_sim_fill();
            fs_len                = 248;
            fhw.NumOfBytes        = 248;
            fhw.SymAddress.Offset = CFE_ES_MEMADDRESS_C(AW);
            OS_OpenCreate(&fdw, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            ww  = md_sim_writes;
            stw = MM_LoadMem32FromFile(fdw, "/ram/mmw.ld", &fhw, AW);
            printf("mm32_load st=%ld writes=%ld m0=%02X m3=%02X m244=%02X m247=%02X\n",
                   (long)stw, md_sim_writes - ww, md_sim_mem[0], md_sim_mem[3], md_sim_mem[244],
                   md_sim_mem[247]);
            /* THE THIRD RENDERING: "RC=%d" with no overwrite, so the PSP's -21 reaches the
             * ground as a negative decimal. Offset 20 is 4-aligned, so the sixth store fails. */
            /* REFILL THE FILE BEFORE EVERY LOAD. The dumps above write INTO fs_data, and
             * what they write is md_sim_fill's own pattern -- so a load that read the stale
             * file would place bytes INDISTINGUISHABLE from the window's existing contents, and
             * "m0=40" would be satisfied equally by the load working and by it not running at
             * all. It was written that way first and the mem32 lines said 0x40 where they
             * should have said 0x80. */
            for (kw = 0; kw < 250; kw++)
            {
                fs_data[kw] = (unsigned char)(0x80 + kw);
            }
            md_sim_fill();
            fs_len = 248;
            OS_OpenCreate(&fdw, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            md_sim_wfail_at = 20;
            ww              = md_sim_writes;
            stw             = MM_LoadMem32FromFile(fdw, "/ram/mmw.ld", &fhw, AW);
            md_sim_wfail_at = -1;
            printf("mm32_load_wfail st=%ld writes=%ld m16=%02X m20=%02X\n", (long)stw,
                   md_sim_writes - ww, md_sim_mem[16], md_sim_mem[20]);

            md_sim_fill();
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fdw, "/ram/mmw.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            rr  = md_sim_reads;
            stw = MM_DumpMem32ToFile(fdw, "/ram/mmw.dp", &fhw);
            printf("mm32_dump st=%ld reads=%ld len=%ld d0=%02X d3=%02X d247=%02X\n", (long)stw,
                   md_sim_reads - rr, fs_len, fs_data[0], fs_data[3], fs_data[247]);
        }

        /* --- mm_dump.c -- the four ways MM gets memory OUT -------------------------------
         * MM_PeekMem reaches memory through the PSP, so it uses the SIMULATED WINDOW and its
         * two events print only the address the ground supplied -- both fully comparable.
         *
         * MM_DumpMemToFile AND MM_FillDumpInEventBuffer'S RAM/EEPROM ARM DO NOT. They
         * `memcpy` from the address, so a literal window address would be a wild pointer, and
         * they are exercised against a REAL driver-owned array instead. The consequence is that
         * MM_DumpMemToFile's housekeeping Address is a real pointer and CANNOT BE PRINTED --
         * so it is asserted by COMPARISON: `addr_ok` is whether the field equals the array's
         * own address, which is true on both halves and still fails if the field is set from
         * the wrong place.
         *
         * MM_FillDumpInEventBuffer's THREE ERROR ARMS ARE NOT DRIVEN. Each prints `Tgt=%p`, the
         * caller's buffer, for the reason mm_mem8's read error is undrivable. Their four
         * SUCCESS paths are, including the RAM and EEPROM pair that SHARE a case body -- which
         * is the one thing in this file that depends on HolyC's switch falling through like C's.
         * Measured before the translation was written, with both an empty label and a
         * non-empty case without a break. */
        {
            MM_PeekCmd_t            pk;
            MM_DumpInEventCmd_t     de;
            MM_LoadDumpFileHeader_t fhd;
            CFE_FS_Header_t         cfh;
            osal_id_t               fdd;
            long                    rr;
            int                     kd;
            int32                   std_;

            for (kd = 0; kd < 250; kd++)
            {
                mmd_src[kd] = (unsigned char)(0x10 + kd);
            }
            md_sim_fill();

            /* --- MM_PeekMem, the three widths. The data comes out of the simulated window, so
             * every byte in the three events is 0x40 + offset and the ENDIANNESS is part of the
             * comparison: a 32-bit peek at base+4 must read 0x47464544 and not 0x44454647. */
            memset(&pk, 0, sizeof(pk));
            pk.Payload.MemType  = MM_MemType_RAM;
            pk.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
            std_                = MM_PeekMem(&pk, MD_SIM_WINDOW_BASE);
            printf("mmd_peek8 st=%ld la=%u mt=%u bp=%u dv=0x%08x\n", (long)std_,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue);
            pk.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
            std_                = MM_PeekMem(&pk, MD_SIM_WINDOW_BASE + 2);
            printf("mmd_peek16 st=%ld bp=%u dv=0x%08x addr=%lu\n", (long)std_,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address);
            pk.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
            std_                = MM_PeekMem(&pk, MD_SIM_WINDOW_BASE + 4);
            printf("mmd_peek32 st=%ld bp=%u dv=0x%08x\n", (long)std_,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue);
            /* OUTSIDE THE WINDOW. Housekeeping must keep the 32-bit peek's values, because the
             * failure path writes none of it. */
            std_ = MM_PeekMem(&pk, MD_SIM_WINDOW_BASE + 300);
            printf("mmd_peek_bad st=%ld bp=%u dv=0x%08x\n", (long)std_,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue);
            /* A WIDTH NO ARM RECOGNISES. PSP_Status is still the value it was INITIALISED to --
             * CFE_PSP_ERROR_NOT_IMPLEMENTED, -27 -- and DataSize is still 0, so the event reads
             * `MemType=MEM0`. It is the one status in MM that means "no branch ran". NASA's own
             * comment says a bad DataSize is caught by MM_VerifyPeekPokeParams and this cannot
             * happen; calling MM_PeekMem directly is how a translation of the arm that NASA
             * says is unreachable gets checked at all. */
            pk.Payload.DataSize = 7;
            std_                = MM_PeekMem(&pk, MD_SIM_WINDOW_BASE);
            printf("mmd_peek_nowidth st=%ld\n", (long)std_);

            /* --- MM_DumpMemToFile, the GENERIC path: a real array, 250 bytes, two segments. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            fs_noexist = 0;
            OS_OpenCreate(&fdd, "/ram/mmd.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            memset(&fhd, 0, sizeof(fhd));
            fhd.NumOfBytes        = 250;
            fhd.MemType           = MM_MemType_EEPROM;
            fhd.SymAddress.Offset = CFE_ES_MEMADDRESS_C(mmd_src);
            memset(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
            std_ = MM_DumpMemToFile(fdd, "/ram/mmd.dp", &fhd);
            printf("mmd_dump st=%ld len=%ld d0=%02X d199=%02X d200=%02X d249=%02X\n", (long)std_,
                   fs_len, fs_data[0], fs_data[199], fs_data[200], fs_data[249]);
            /* `addr_ok` INSTEAD OF `addr`: the field holds a real pointer, so its VALUE cannot
             * cross the two halves -- but whether it equals the array's address can. */
            printf("mmd_dump_hk la=%u mt=%u bp=%u addr_ok=%d fn=[%s] fn20=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (int)(MM_AppData.HkTlm.Payload.Address == CFE_ES_MEMADDRESS_C(mmd_src)),
                   MM_AppData.HkTlm.Payload.FileName,
                   (unsigned char)MM_AppData.HkTlm.Payload.FileName[20]);
            /* A SHORT WRITE. Note the event prints `RC = %d` -- a SIGNED decimal, where
             * mm_mem8's twin prints `0x%08X` -- so a 100-byte write reads `RC = 100`. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = 100;
            OS_OpenCreate(&fdd, "/ram/mmd.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            std_       = MM_DumpMemToFile(fdd, "/ram/mmd.dp", &fhd);
            fs_wr_left = -1;
            printf("mmd_dump_short st=%ld len=%ld bp=%u\n", (long)std_, fs_len,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);

            /* --- MM_WriteFileHeaders. 64 bytes of cFE header then 88 of MM's, and the MM
             * header is MEMSET HERE BY THE DRIVER: its last byte is tail padding, so NASA
             * writes one byte of whatever was on the caller's stack into every dump file. The
             * zero at offset 151 below is therefore evidence about THIS DRIVER and not about
             * the translation -- stated because a reader would otherwise take it for NASA's. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fdd, "/ram/mmd.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            memset(&cfh, 0, sizeof(cfh));
            cfh.SubType = 0x4D4D5354;
            strncpy(cfh.Description, "MM dump", sizeof(cfh.Description));
            memset(&fhd, 0, sizeof(fhd));
            fhd.NumOfBytes        = 250;
            fhd.Crc               = 0x1234;
            fhd.MemType           = MM_MemType_MEM16;
            fhd.SymAddress.Offset = CFE_ES_MEMADDRESS_C(0x00100000);
            std_                  = MM_WriteFileHeaders("/ram/mmd.hd", fdd, &cfh, &fhd);
            printf("mmd_hdrs st=%ld len=%ld mmoff=%02X%02X%02X nbytes=%u crc=%u mt=%u "
                   "pad151=%u\n",
                   (long)std_, fs_len, fs_data[64], fs_data[65], fs_data[66],
                   (unsigned)fs_data[64 + 72], (unsigned)fs_data[64 + 76],
                   (unsigned)fs_data[64 + 80], (unsigned)fs_data[151]);
            /* THE cFE HEADER'S WRITE COMES UP SHORT. Both error arms of this function replace
             * the status with OS_ERR_INVALID_SIZE BEFORE printing it, so the event says -40 and
             * not what actually happened -- a failed write and a short write are
             * indistinguishable to the ground. NASA's own choice. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = 10;
            OS_OpenCreate(&fdd, "/ram/mmd.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            std_ = MM_WriteFileHeaders("/ram/mmd.hd", fdd, &cfh, &fhd);
            printf("mmd_hdrs_short1 st=%ld len=%ld\n", (long)std_, fs_len);
            /* AND NOW THE cFE HEADER FITS BUT MM'S DOES NOT, which is the other arm -- the one
             * that only runs because the first one passed. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = 64 + 10;
            OS_OpenCreate(&fdd, "/ram/mmd.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            std_       = MM_WriteFileHeaders("/ram/mmd.hd", fdd, &cfh, &fhd);
            fs_wr_left = -1;
            printf("mmd_hdrs_short2 st=%ld len=%ld\n", (long)std_, fs_len);

            /* --- MM_FillDumpInEventBuffer, all four success arms. The buffer is 16 bytes and
             * NASA clears only the first MM_INTERNAL_MAX_DUMP_INEVENT_BYTES (15) of it, so
             * [15] is a poison byte that must survive -- and [8..14] must be ZERO after an
             * 8-byte request, which is what says the clear happened at all.
             *
             * RAM AND EEPROM SHARE ONE CASE BODY. Driving both is the only thing that says
             * HolyC's switch falls through: if an empty `case` label did not reach the next
             * one, the RAM arm would do nothing and return CFE_PSP_ERROR. */
            memset(&de, 0, sizeof(de));
            de.Payload.NumOfBytes = 8;
            /* Filled at use rather than initialised, so the HolyC half can be the same shape:
             * it has no aggregate initialiser. */
            mmd_mts[0] = MM_MemType_RAM;
            mmd_mts[1] = MM_MemType_EEPROM;
            mmd_mts[2] = MM_MemType_MEM32;
            mmd_mts[3] = MM_MemType_MEM16;
            for (kd = 0; kd < 4; kd++)
            {
                cpuaddr src;
                memset(mmd_evbuf, 0xEE, sizeof(mmd_evbuf));
                de.Payload.MemType = (MM_MemType_Enum_t)mmd_mts[kd];
                /* RAM and EEPROM copy from a real pointer; the two width arms go through the
                 * PSP and so take a window address. */
                src = (cpuaddr)MD_SIM_WINDOW_BASE;
                if (kd < 2)
                {
                    src = (cpuaddr)mmd_src;
                }
                rr   = md_sim_reads;
                std_ = MM_FillDumpInEventBuffer(src, &de, mmd_evbuf);
                printf("mmd_ev mt=%u st=%ld reads=%ld b0=%02X b1=%02X b7=%02X b8=%02X "
                       "b14=%02X b15=%02X\n",
                       (unsigned)mmd_mts[kd], (long)std_, md_sim_reads - rr, mmd_evbuf[0],
                       mmd_evbuf[1], mmd_evbuf[7], mmd_evbuf[8], mmd_evbuf[14], mmd_evbuf[15]);
            }
            memset(mmd_evbuf, 0xEE, sizeof(mmd_evbuf));
            de.Payload.MemType = MM_MemType_MEM8;
            rr                 = md_sim_reads;
            std_               = MM_FillDumpInEventBuffer(MD_SIM_WINDOW_BASE, &de, mmd_evbuf);
            printf("mmd_ev mt=%u st=%ld reads=%ld b0=%02X b1=%02X b7=%02X b8=%02X b14=%02X "
                   "b15=%02X\n",
                   (unsigned)MM_MemType_MEM8, (long)std_, md_sim_reads - rr, mmd_evbuf[0],
                   mmd_evbuf[1], mmd_evbuf[7], mmd_evbuf[8], mmd_evbuf[14], mmd_evbuf[15]);
            /* AND A MEMORY TYPE NO ARM MATCHES: NASA's default is empty and says it cannot
             * happen, so PSP_Status is still the CFE_PSP_ERROR it was initialised to -- but the
             * BUFFER IS STILL CLEARED, because the memset runs before the switch. Both halves
             * of that. */
            memset(mmd_evbuf, 0xEE, sizeof(mmd_evbuf));
            de.Payload.MemType = MM_MemType_NOMEMTYPE;
            std_               = MM_FillDumpInEventBuffer(MD_SIM_WINDOW_BASE, &de, mmd_evbuf);
            printf("mmd_ev_nomt st=%ld b0=%02X b14=%02X b15=%02X\n", (long)std_, mmd_evbuf[0],
                   mmd_evbuf[14], mmd_evbuf[15]);
        }

        /* --- mm_load.c -- the six ways MM gets data IN ------------------------------------
         * EEPROM IS A SEPARATE DEVICE AND SO A SECOND SIMULATED REGION. A RAM poke goes through
         * CFE_PSP_MemWrite* into MD_SIM_WINDOW; an EEPROM poke goes through
         * CFE_PSP_EepromWrite* into MM_EEP_WINDOW, 0x00200000 and far away on purpose -- an
         * address meant for one and sent to the other must be REFUSED, not quietly work, and
         * the line below that pokes EEPROM at the RAM window's base is what says so.
         *
         * AND MM_FillMem HAS AN UPSTREAM DEFECT THAT THIS BLOCK PRINTS. NASA's scratch-segment
         * loop runs MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(uint32) = 50 times through a BYTE
         * pointer, so a 200-byte segment gets the pattern in its first fifty bytes and keeps
         * whatever MM_AppData.FillBuffer held in the other 150. Kept verbatim -- see the long
         * note at the top of Kernel/Cfs/mm/mm_load.HC -- and the four bytes printed below are
         * the boundary: 0 and 49 carry the pattern, 50 and 199 do not. */
        {
            MM_PokeCmd_t            pkc;
            MM_FillMemCmd_t         flc;
            MM_LoadDumpFileHeader_t fhl;
            CFE_FS_Header_t         cfl;
            osal_id_t               fdl;
            long                    we, p0;
            int                     kl;
            int32                   stl;
            CFE_ES_PerfData_t      *PL = &CFE_ES_Global.ResetDataPtr->Perf;

            memset(&pkc, 0, sizeof(pkc));
            pkc.Payload.MemType = MM_MemType_RAM;
            pkc.Payload.Data    = 0xAABBCCDD;

            /* --- MM_PokeMem, the three widths into the RAM window. The window's own bytes say
             * which end went first, and the event prints 0x%08X at every width -- which is the
             * asymmetry with the EEPROM path below. */
            md_sim_fill();
            pkc.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
            stl                  = MM_PokeMem(&pkc, MD_SIM_WINDOW_BASE + 8);
            /* PER-WIDTH, NOT JUST THE LAST ONE. The three byte counts were printed once after
             * all three pokes, which reads only the 32-bit arm's -- so a mutation that made the
             * 16-bit arm report ONE byte was INVISIBLE. Captured per call now. */
            mml_bp[0]            = (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed;
            mml_dv[0]            = (unsigned)MM_AppData.HkTlm.Payload.DataValue;
            pkc.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
            stl += MM_PokeMem(&pkc, MD_SIM_WINDOW_BASE + 16);
            mml_bp[1]            = (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed;
            mml_dv[1]            = (unsigned)MM_AppData.HkTlm.Payload.DataValue;
            pkc.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
            stl += MM_PokeMem(&pkc, MD_SIM_WINDOW_BASE + 24);
            mml_bp[2] = (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed;
            mml_dv[2] = (unsigned)MM_AppData.HkTlm.Payload.DataValue;
            printf("mml_poke_bp %u,%u,%u dv %u,%u,%u\n", mml_bp[0], mml_bp[1], mml_bp[2],
                   mml_dv[0], mml_dv[1], mml_dv[2]);
            printf("mml_poke st=%ld m8=%02X m16=%02X%02X m32=%02X%02X%02X%02X\n", (long)stl,
                   md_sim_mem[8], md_sim_mem[17], md_sim_mem[16], md_sim_mem[27], md_sim_mem[26],
                   md_sim_mem[25], md_sim_mem[24]);
            printf("mml_poke_hk la=%u mt=%u bp=%u dv=0x%08x addr=%lu\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address);
            /* OUTSIDE THE WINDOW, and a width no arm recognises. The second returns -27 with
             * `MemType=MEM0` -- BytesProcessed and DataSize are set BEFORE the write in this
             * function, which is why the first one's event can print `MemType=MEM32` where
             * MM_PeekMem's failure prints the size it never got to use. */
            stl = MM_PokeMem(&pkc, MD_SIM_WINDOW_BASE + 300);
            printf("mml_poke_bad st=%ld\n", (long)stl);
            pkc.Payload.DataSize = 7;
            stl                  = MM_PokeMem(&pkc, MD_SIM_WINDOW_BASE);
            printf("mml_poke_nowidth st=%ld\n", (long)stl);

            /* --- MM_PokeEeprom, the three widths into the OTHER region. Two performance-log
             * entries per call -- the RAM poke has none -- and the success event prints the data
             * AT THE COMMANDED WIDTH, so the same 0xAABBCCDD reads 0xDD, 0xCCDD and 0xAABBCCDD
             * across the three. */
            memset(mm_eep_mem, 0, sizeof(mm_eep_mem));
            pkc.Payload.MemType  = MM_MemType_EEPROM;
            pkc.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
            we                   = mm_eep_writes;
            p0                   = PL->MetaData.DataCount;
            stl                  = MM_PokeEeprom(&pkc, MM_EEP_WINDOW_BASE + 8);
            mml_bp[0]            = (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed;
            pkc.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
            stl += MM_PokeEeprom(&pkc, MM_EEP_WINDOW_BASE + 16);
            mml_bp[1]            = (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed;
            pkc.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
            stl += MM_PokeEeprom(&pkc, MM_EEP_WINDOW_BASE + 24);
            mml_bp[2] = (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed;
            printf("mml_poke_eep_bp %u,%u,%u\n", mml_bp[0], mml_bp[1], mml_bp[2]);
            printf("mml_poke_eep st=%ld writes=%ld perf=%ld e8=%02X e16=%02X%02X "
                   "e32=%02X%02X%02X%02X\n",
                   (long)stl, mm_eep_writes - we, (long)(PL->MetaData.DataCount - p0),
                   mm_eep_mem[8], mm_eep_mem[17], mm_eep_mem[16], mm_eep_mem[27], mm_eep_mem[26],
                   mm_eep_mem[25], mm_eep_mem[24]);
            printf("mml_poke_eep_hk la=%u mt=%u bp=%u dv=0x%08x\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue);
            /* THE TWO REGIONS ARE SEPARATE, which is the whole reason EEPROM got its own
             * window: an EEPROM poke aimed at the RAM window's base must be REFUSED, and the
             * RAM window's byte there must be untouched. A shared array would have made this
             * succeed and nothing else in the port would have noticed. */
            md_sim_fill();
            we                   = mm_eep_writes;
            pkc.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
            stl                  = MM_PokeEeprom(&pkc, MD_SIM_WINDOW_BASE + 8);
            printf("mml_poke_eep_wrongregion st=%ld writes=%ld ram8=%02X\n", (long)stl,
                   mm_eep_writes - we, md_sim_mem[8]);
            /* AND HOUSEKEEPING AFTER A FAILED POKE, which nothing read before -- so a mutation
             * that updated it on the error path was INVISIBLE. The address must still be the
             * 32-bit EEPROM poke's, 0x200018, and the byte count still 4. */
            printf("mml_poke_eep_failhk la=%u mt=%u bp=%u dv=0x%08x addr=%lu\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address);
            /* And the other two widths' error ids, which are three DIFFERENT events for one
             * failure -- the RAM poke has one. */
            pkc.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
            stl                  = MM_PokeEeprom(&pkc, MD_SIM_WINDOW_BASE + 8);
            pkc.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
            stl += MM_PokeEeprom(&pkc, MD_SIM_WINDOW_BASE + 8);
            printf("mml_poke_eep_err st=%ld\n", (long)stl);

            /* --- MM_LoadMemFromFile, generic, into the real array. THE PERFORMANCE STAMPS ARE
             * CONDITIONAL ON THE FILE HEADER'S MEMORY TYPE -- the only marker in MM taken only
             * sometimes -- so the same call gives perf=2 for EEPROM and perf=0 for RAM, with
             * the segment break's own pair on top of both. */
            for (kl = 0; kl < 250; kl++)
            {
                fs_data[kl] = (unsigned char)(0x80 + kl);
            }
            memset(mmd_src, 0xBB, sizeof(mmd_src));
            fs_len     = 250;
            fs_noexist = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fdl, "/ram/mml.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            memset(&fhl, 0, sizeof(fhl));
            fhl.NumOfBytes        = 250;
            fhl.MemType           = MM_MemType_EEPROM;
            fhl.SymAddress.Offset = CFE_ES_MEMADDRESS_C(mmd_src);
            memset(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
            p0  = PL->MetaData.DataCount;
            stl = MM_LoadMemFromFile(fdl, "/ram/mml.ld", &fhl, (cpuaddr)mmd_src);
            printf("mml_load_eep st=%ld perf=%ld s0=%02X s199=%02X s200=%02X s249=%02X\n",
                   (long)stl, (long)(PL->MetaData.DataCount - p0), mmd_src[0], mmd_src[199],
                   mmd_src[200], mmd_src[249]);
            printf("mml_load_hk la=%u mt=%u bp=%u addr_ok=%d fn=[%s] fn20=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (int)(MM_AppData.HkTlm.Payload.Address == CFE_ES_MEMADDRESS_C(mmd_src)),
                   MM_AppData.HkTlm.Payload.FileName,
                   (unsigned char)MM_AppData.HkTlm.Payload.FileName[20]);
            memset(mmd_src, 0xBB, sizeof(mmd_src));
            fs_len      = 250;
            fhl.MemType = MM_MemType_RAM;
            OS_OpenCreate(&fdl, "/ram/mml.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            p0  = PL->MetaData.DataCount;
            stl = MM_LoadMemFromFile(fdl, "/ram/mml.ld", &fhl, (cpuaddr)mmd_src);
            printf("mml_load_ram st=%ld perf=%ld mt=%u s0=%02X\n", (long)stl,
                   (long)(PL->MetaData.DataCount - p0),
                   (unsigned)MM_AppData.HkTlm.Payload.MemType, mmd_src[0]);
            /* A SHORT FILE. Note this function's event prints `RC = 0x%08X` where
             * MM_DumpMemToFile's prints `RC = %d` -- two sources, two renderings, again. */
            memset(mmd_src, 0xBB, sizeof(mmd_src));
            fs_len = 100;
            OS_OpenCreate(&fdl, "/ram/mml.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            stl = MM_LoadMemFromFile(fdl, "/ram/mml.ld", &fhl, (cpuaddr)mmd_src);
            printf("mml_load_short st=%ld s0=%02X bp=%u\n", (long)stl, mmd_src[0],
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);

            /* --- MM_VerifyLoadFileSize. The expected size is the header's claim PLUS BOTH
             * HEADERS: 250 + 64 + 88 = 402. This is the first thing in the port to READ the
             * stat buffer rather than only OS_stat's return code. */
            fhl.NumOfBytes = 250;
            es_stat_rc     = OS_SUCCESS;
            es_stat_size   = 402;
            stl            = MM_VerifyLoadFileSize("/ram/mml.ld", &fhl);
            printf("mml_vsize_ok st=%ld\n", (long)stl);
            es_stat_size = 401;
            stl          = MM_VerifyLoadFileSize("/ram/mml.ld", &fhl);
            printf("mml_vsize_wrong st=%ld\n", (long)stl);
            es_stat_rc = OS_ERROR;
            stl        = MM_VerifyLoadFileSize("/ram/mml.ld", &fhl);
            printf("mml_vsize_statfail st=%ld\n", (long)stl);
            es_stat_rc   = OS_SUCCESS;
            es_stat_size = 0;

            /* --- MM_ReadFileHeaders, AS A ROUND TRIP THROUGH MM_WriteFileHeaders. Writing the
             * pair and reading it back is the only test that says the two agree about the
             * layout -- each on its own would pass against a wrong offset. */
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            OS_OpenCreate(&fdl, "/ram/mml.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                          OS_WRITE_ONLY);
            memset(&cfl, 0, sizeof(cfl));
            cfl.SubType = 0x4D4D5354;
            memset(&fhl, 0, sizeof(fhl));
            fhl.NumOfBytes        = 1234;
            fhl.Crc               = 0x55AA;
            fhl.MemType           = MM_MemType_MEM8;
            fhl.SymAddress.Offset = CFE_ES_MEMADDRESS_C(0x00100040);
            strncpy(fhl.SymAddress.SymName, "RT", CFE_MISSION_MAX_PATH_LEN);
            stl = MM_WriteFileHeaders("/ram/mml.hd", fdl, &cfl, &fhl);
            memset(&cfl, 0, sizeof(cfl));
            memset(&fhl, 0, sizeof(fhl));
            OS_OpenCreate(&fdl, "/ram/mml.hd", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            stl = MM_ReadFileHeaders("/ram/mml.hd", fdl, &cfl, &fhl);
            printf("mml_rt st=%ld sub=0x%08x nbytes=%u crc=0x%04x mt=%u off=%lu sym=[%s]\n",
                   (long)stl, (unsigned)cfl.SubType, (unsigned)fhl.NumOfBytes,
                   (unsigned)fhl.Crc, (unsigned)fhl.MemType,
                   (unsigned long)fhl.SymAddress.Offset, fhl.SymAddress.SymName);
            /* THE TWO SHORT ARMS. Unlike the writer, this one sends the event BEFORE replacing
             * the status, so the ground sees what CFE_FS_ReadHeader really returned. */
            fs_len = 10;
            OS_OpenCreate(&fdl, "/ram/mml.hd", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            stl = MM_ReadFileHeaders("/ram/mml.hd", fdl, &cfl, &fhl);
            printf("mml_rt_short1 st=%ld\n", (long)stl);
            fs_len = 64 + 10;
            OS_OpenCreate(&fdl, "/ram/mml.hd", OS_FILE_FLAG_NONE, OS_READ_ONLY);
            stl = MM_ReadFileHeaders("/ram/mml.hd", fdl, &cfl, &fhl);
            printf("mml_rt_short2 st=%ld\n", (long)stl);

            /* --- MM_FillMem, AND THE UPSTREAM DEFECT. 200 bytes into an array poisoned with
             * 0xBB. Bytes 0 and 49 must carry the pattern's LOW BYTE; bytes 50 and 199 must
             * carry whatever MM_AppData.FillBuffer held -- which is zero the first time, since
             * it is in BSS and nothing has touched it. The 0xBB is gone either way, because the
             * memcpy covers the whole segment; it is the CONTENTS that say only a quarter of
             * the segment was ever filled. */
            memset(mmd_src, 0xBB, sizeof(mmd_src));
            memset(&flc, 0, sizeof(flc));
            flc.Payload.NumOfBytes  = 200;
            flc.Payload.FillPattern = 0xAABBCCDD;
            flc.Payload.MemType     = MM_MemType_RAM;
            p0                      = PL->MetaData.DataCount;
            MM_FillMem((cpuaddr)mmd_src, &flc);
            printf("mml_fill perf=%ld s0=%02X s49=%02X s50=%02X s199=%02X s200=%02X\n",
                   (long)(PL->MetaData.DataCount - p0), mmd_src[0], mmd_src[49], mmd_src[50],
                   mmd_src[199], mmd_src[200]);
            printf("mml_fill_hk la=%u mt=%u bp=%u dv=0x%08x addr_ok=%d\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (int)(MM_AppData.HkTlm.Payload.Address == CFE_ES_MEMADDRESS_C(mmd_src)));
            /* 250 BYTES IS TWO SEGMENTS, so the segment break fires once -- perf goes to 2 for
             * a RAM fill, and to 4 for an EEPROM one because this function's own stamps are
             * conditional on the memory type the same way the load's are. */
            memset(mmd_src, 0xBB, sizeof(mmd_src));
            flc.Payload.NumOfBytes = 250;
            p0                     = PL->MetaData.DataCount;
            MM_FillMem((cpuaddr)mmd_src, &flc);
            printf("mml_fill_2seg perf=%ld bp=%u s200=%02X s249=%02X\n",
                   (long)(PL->MetaData.DataCount - p0),
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed, mmd_src[200],
                   mmd_src[249]);
            memset(mmd_src, 0xBB, sizeof(mmd_src));
            flc.Payload.MemType = MM_MemType_EEPROM;
            p0                  = PL->MetaData.DataCount;
            MM_FillMem((cpuaddr)mmd_src, &flc);
            printf("mml_fill_eep perf=%ld mt=%u\n", (long)(PL->MetaData.DataCount - p0),
                   (unsigned)MM_AppData.HkTlm.Payload.MemType);
        }

        /* --- mm_cmds.c -- MM'S FOURTEEN GROUND COMMANDS --------------------------------------
         * THE MEMORY TYPE DECIDES WHETHER A COMMAND IS COMPARABLE AT ALL, and that is the
         * design of this whole block. Five of the handlers print the resolved address in their
         * SUCCESS event:
         *
         *   with MemType = MEM8/MEM16/MEM32 the work goes through CFE_PSP_Mem{Read,Write}*, so
         *   the address is a literal window constant and the event is the same text on both
         *   halves. Every success path below is driven that way.
         *
         *   with MemType = RAM or EEPROM the work is a `memcpy` from or to the address, so it
         *   has to be real memory -- a different number on each half -- and the event cannot be
         *   compared. Those paths were driven through mm_dump.c and mm_load.c directly, where
         *   the housekeeping address is asserted by COMPARISON instead.
         *
         * ONE SUCCESS PATH IS OUTSIDE THE DIFFERENTIAL ENTIRELY: MM_LoadMemWIDCmd. Its memory
         * type is HARD-CODED to RAM -- an EEPROM programming cycle cannot be done with
         * interrupts off -- and it ends in `memcpy((void *)DestAddress, ...)`. So the address is
         * necessarily real, and the event that announces the load prints it. Its three ERROR
         * paths are driven; its success path is not, and nothing here pretends otherwise. */
        {
            union
            {
                MM_SendHkCmd_t          Hk;
                MM_NoopCmd_t            Noop;
                MM_ResetCountersCmd_t   Reset;
                MM_LookupSymCmd_t       Lookup;
                MM_SymTblToFileCmd_t    SymTbl;
                MM_EepromWriteEnaCmd_t  Ena;
                MM_EepromWriteDisCmd_t  Dis;
                MM_PokeCmd_t            Poke;
                MM_PeekCmd_t            Peek;
                MM_LoadMemWIDCmd_t      Wid;
                MM_LoadMemFromFileCmd_t LdFile;
                MM_DumpMemToFileCmd_t   DmpFile;
                MM_FillMemCmd_t         Fill;
                MM_DumpInEventCmd_t     DmpEv;
            } c;
            int  kc;
            long sb0;

            /* THE HK PACKET NEEDS ITS MsgId, which is md_app.c's job and mm_app.c's after it.
             * Without it CFE_SB_TransmitMsg refuses with `Send Err:Invalid MsgId(0x0)` -- MD hit
             * that for real twice, and it is the thing that makes a send OBSERVABLE. */
            CFE_MSG_Init(CFE_MSG_PTR(MM_AppData.HkTlm.TelemetryHeader),
                         CFE_SB_ValueToMsgId(MM_HK_TLM_MID), sizeof(MM_HkTlm_t));

            /* --- MM_SendHkCmd. It must NOT move the command counter -- housekeeping arrives
             * once a second and counting it would swamp the number an operator reads. */
            MM_AppData.HkTlm.Payload.CommandCounter      = 11;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 22;
            memset(&c, 0, sizeof(c));
            printf("mmc_hk st=%ld cc=%u ec=%u\n", (long)MM_SendHkCmd(&c.Hk),
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* --- MM_NoopCmd and MM_ResetCountersCmd. */
            printf("mmc_noop st=%ld cc=%u la=%u\n", (long)MM_NoopCmd(&c.Noop),
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction);
            printf("mmc_reset st=%ld cc=%u ec=%u la=%u\n", (long)MM_ResetCountersCmd(&c.Reset),
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction);

            /* --- MM_LookupSymCmd, all three outcomes. The address in the event is the driver's
             * md_sym_addr, a constant, so this is the one command whose address is comparable
             * whatever the memory type -- it never touches memory at all. */
            memset(&c, 0, sizeof(c));
            MM_LookupSymCmd(&c.Lookup);
            printf("mmc_lookup_nul ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            strcpy(c.Lookup.Payload.SymName, "MM_PROBE");
            md_sym_rc   = OS_SUCCESS;
            md_sym_addr = 0x00100020;
            MM_LookupSymCmd(&c.Lookup);
            printf("mmc_lookup_ok cc=%u la=%u addr=%lu\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned long)MM_AppData.HkTlm.Payload.Address);
            md_sym_rc = OS_ERROR;
            MM_LookupSymCmd(&c.Lookup);
            printf("mmc_lookup_fail ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            md_sym_rc = OS_SUCCESS;

            /* --- MM_SymTblToFileCmd, all three outcomes. The size limit the stub records is
             * MM_INTERNAL_MAX_DUMP_FILE_DATA_SYMTBL, which no other line in MM reads. */
            memset(&c, 0, sizeof(c));
            MM_SymTblToFileCmd(&c.SymTbl);
            printf("mmc_symtbl_nul ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            strcpy(c.SymTbl.Payload.FileName, "/ram/sym.dmp");
            memset(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
            mm_symdump_rc = OS_SUCCESS;
            MM_SymTblToFileCmd(&c.SymTbl);
            printf("mmc_symtbl_ok cc=%u la=%u limit=%ld fn=[%s] fn20=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction, mm_symdump_limit,
                   MM_AppData.HkTlm.Payload.FileName,
                   (unsigned char)MM_AppData.HkTlm.Payload.FileName[20]);
            mm_symdump_rc = OS_ERROR;
            MM_SymTblToFileCmd(&c.SymTbl);
            printf("mmc_symtbl_fail ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            mm_symdump_rc = OS_SUCCESS;

            /* --- the two EEPROM bank commands, both outcomes each. The bank number reaches the
             * event, and mm_eep_last_bank says the PSP was really asked for THAT bank. */
            memset(&c, 0, sizeof(c));
            c.Ena.Payload.Bank = 3;
            mm_eep_lock_rc     = CFE_PSP_SUCCESS;
            MM_EepromWriteEnaCmd(&c.Ena);
            printf("mmc_eepena cc=%u la=%u mt=%u bank=%u locks=%ld\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType, (unsigned)mm_eep_last_bank,
                   mm_eep_locks);
            c.Dis.Payload.Bank = 4;
            MM_EepromWriteDisCmd(&c.Dis);
            printf("mmc_eepdis cc=%u la=%u bank=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction, (unsigned)mm_eep_last_bank);
            mm_eep_lock_rc = CFE_PSP_ERROR;
            MM_EepromWriteEnaCmd(&c.Ena);
            MM_EepromWriteDisCmd(&c.Dis);
            printf("mmc_eep_fail ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            mm_eep_lock_rc = CFE_PSP_SUCCESS;

            /* --- MM_PokeCmd. The RAM arm and the EEPROM arm are two different workers chosen by
             * the memory type, which is the one branch in this handler. Both addresses are
             * window constants because both go through the PSP. */
            md_sim_fill();
            memset(&c, 0, sizeof(c));
            c.Poke.Payload.MemType  = MM_MemType_RAM;
            c.Poke.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
            c.Poke.Payload.Data     = 0x11223344;
            c.Poke.Payload.DestSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE + 32);
            MM_PokeCmd(&c.Poke);
            printf("mmc_poke_ram cc=%u m32=%02X%02X%02X%02X\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter, md_sim_mem[35],
                   md_sim_mem[34], md_sim_mem[33], md_sim_mem[32]);
            memset(mm_eep_mem, 0, sizeof(mm_eep_mem));
            c.Poke.Payload.MemType = MM_MemType_EEPROM;
            c.Poke.Payload.DestSymAddress.Offset = CFE_ES_MEMADDRESS_C(MM_EEP_WINDOW_BASE + 32);
            MM_PokeCmd(&c.Poke);
            printf("mmc_poke_eep cc=%u e32=%02X%02X%02X%02X\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter, mm_eep_mem[35],
                   mm_eep_mem[34], mm_eep_mem[33], mm_eep_mem[32]);
            /* A POKE THE WORKER REFUSES, which is a THIRD error arm and not the same as the
             * two below: the verifier passes (this driver's MemValidateRange accepts any
             * address) and CFE_PSP_MemWrite32 then rejects it, so the failure comes back from
             * MM_PokeMem and lands in the INNER else. Without this case a mutation that counted
             * a failed poke as a success was INVISIBLE -- every other poke here either works or
             * never reaches the worker. */
            MM_AppData.HkTlm.Payload.CommandCounter      = 0;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            c.Poke.Payload.MemType = MM_MemType_RAM;
            c.Poke.Payload.DestSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE + 300);
            MM_PokeCmd(&c.Poke);
            printf("mmc_poke_wfail cc=%u ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            c.Poke.Payload.DestSymAddress.Offset = CFE_ES_MEMADDRESS_C(MM_EEP_WINDOW_BASE + 32);
            c.Poke.Payload.MemType               = MM_MemType_EEPROM;

            /* A WIDTH THE VERIFIER REFUSES, and then an UNRESOLVABLE SYMBOL -- the two error
             * arms. The second prints the LOCAL COPY of the name, which MM_ResolveSymAddr has
             * NUL-terminated; MM_PeekCmd's twin prints the message's own field instead. */
            c.Poke.Payload.DataSize = 7;
            MM_PokeCmd(&c.Poke);
            printf("mmc_poke_badsize ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            c.Poke.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
            strcpy(c.Poke.Payload.DestSymAddress.SymName, "NOSUCH");
            md_sym_rc = OS_ERROR;
            MM_PokeCmd(&c.Poke);
            printf("mmc_poke_badsym ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* --- MM_PeekCmd, success and its own symbol error. */
            memset(&c, 0, sizeof(c));
            c.Peek.Payload.MemType  = MM_MemType_MEM16;
            c.Peek.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
            c.Peek.Payload.SrcSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE + 40);
            md_sym_rc                           = OS_SUCCESS;
            MM_PeekCmd(&c.Peek);
            printf("mmc_peek cc=%u dv=0x%08x bp=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.DataValue,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);
            strcpy(c.Peek.Payload.SrcSymAddress.SymName, "NOSUCH");
            md_sym_rc = OS_ERROR;
            MM_PeekCmd(&c.Peek);
            printf("mmc_peek_badsym ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            md_sym_rc = OS_SUCCESS;

            /* --- MM_LoadMemWIDCmd, THE THREE ERROR ARMS. See the note at the top of this block
             * for why the success path is not here: it is hard-coded to RAM and ends in a memcpy
             * to the resolved address, which the event then prints. */
            memset(&c, 0, sizeof(c));
            c.Wid.Payload.NumOfBytes = 8;
            for (kc = 0; kc < 8; kc++)
            {
                c.Wid.Payload.DataArray[kc] = (unsigned char)(0x30 + kc);
            }
            c.Wid.Payload.DestSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE);
            c.Wid.Payload.Crc                   = 0; /* deliberately wrong */
            MM_LoadMemWIDCmd(&c.Wid);
            printf("mmc_wid_badcrc ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            /* A LENGTH ABOVE MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA, which is the WID-specific
             * limit the verifier applies -- 200. */
            c.Wid.Payload.NumOfBytes = 201;
            MM_LoadMemWIDCmd(&c.Wid);
            printf("mmc_wid_badlen ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            c.Wid.Payload.NumOfBytes = 8;
            strcpy(c.Wid.Payload.DestSymAddress.SymName, "NOSUCH");
            md_sym_rc = OS_ERROR;
            MM_LoadMemWIDCmd(&c.Wid);
            printf("mmc_wid_badsym ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            md_sym_rc = OS_SUCCESS;

            /* --- MM_FillMemCmd. MEM8 for the comparable success path, then THE SECOND UPSTREAM
             * DEFECT: a MEM16 fill of an ODD length. mm_mem16.c rounds the length down, warns,
             * and returns an error -- and this handler's `else` on that error moves the SUCCESS
             * counter and sends no event. So the two counters below are the defect. */
            md_sim_fill();
            memset(&c, 0, sizeof(c));
            c.Fill.Payload.MemType     = MM_MemType_MEM8;
            c.Fill.Payload.NumOfBytes  = 16;
            c.Fill.Payload.FillPattern = 0x5A5A5A5A;
            c.Fill.Payload.DestSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE + 64);
            sb0                                  = MM_AppData.HkTlm.Payload.CommandCounter;
            MM_FillMemCmd(&c.Fill);
            printf("mmc_fill8 cc=%ld m64=%02X m79=%02X m80=%02X\n",
                   (long)MM_AppData.HkTlm.Payload.CommandCounter - sb0, md_sim_mem[64],
                   md_sim_mem[79], md_sim_mem[80]);
            md_sim_fill();
            c.Fill.Payload.MemType    = MM_MemType_MEM16;
            c.Fill.Payload.NumOfBytes = 15;
            MM_AppData.HkTlm.Payload.CommandCounter      = 0;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_FillMemCmd(&c.Fill);
            printf("mmc_fill16_odd cc=%u ec=%u m64=%02X m77=%02X m78=%02X\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter, md_sim_mem[64],
                   md_sim_mem[77], md_sim_mem[78]);
            /* And the verifier's own refusal: a length of zero. */
            c.Fill.Payload.NumOfBytes = 0;
            MM_FillMemCmd(&c.Fill);
            printf("mmc_fill_zero cc=%u ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            /* THE DEFECT, AND THE INPUT THAT ACTUALLY REACHES IT. The first attempt used an
             * ODD MEM16 length, on the theory that mm_mem16's rounding would fail the fill --
             * but MM_VerifyLoadDumpParams checks the SIZE's alignment too, so that is refused
             * one level earlier and counted correctly. What reaches the `else` is a PSP WRITE
             * FAILURE: MM_FillMem8 returns CFE_PSP_ERROR when a store is refused, and this
             * handler's else then moves the SUCCESS counter and sends NO EVENT. So the two
             * numbers below are MM reporting a half-finished fill as a command that worked. */
            md_sim_fill();
            c.Fill.Payload.MemType    = MM_MemType_MEM8;
            c.Fill.Payload.NumOfBytes = 16;
            md_sim_wfail_at           = 70;
            MM_AppData.HkTlm.Payload.CommandCounter      = 0;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_FillMemCmd(&c.Fill);
            md_sim_wfail_at = -1;
            printf("mmc_fill_wfail cc=%u ec=%u m69=%02X m70=%02X\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter, md_sim_mem[69],
                   md_sim_mem[70]);

            /* --- MM_DumpMemToFileCmd then MM_LoadMemFromFileCmd, AS A ROUND TRIP. MEM8, so
             * every address is a window constant and both success events are comparable. The
             * dump writes the headers, the data, SEEKS BACK, computes the CRC over what it
             * wrote and REWRITES the headers -- and the load then verifies that same CRC. If
             * either side of that disagreed about the file layout the load would fail, which is
             * why one test covers both. */
            md_sim_fill();
            fs_len     = 0;
            fs_pos     = 0;
            fs_wr_left = -1;
            fs_noexist = 0;
            memset(&c, 0, sizeof(c));
            c.DmpFile.Payload.MemType    = MM_MemType_MEM8;
            c.DmpFile.Payload.NumOfBytes = 32;
            c.DmpFile.Payload.SrcSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE);
            strcpy(c.DmpFile.Payload.FileName, "/ram/rt.dmp");
            MM_AppData.HkTlm.Payload.CommandCounter      = 0;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_DumpMemToFileCmd(&c.DmpFile);
            printf("mmc_dmpfile cc=%u ec=%u len=%ld la=%u bp=%u crc=%02X%02X\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter, fs_len,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed, fs_data[64 + 77],
                   fs_data[64 + 76]);
            /* NOW LOAD IT BACK. The window is refilled with a different pattern first, so the
             * bytes that arrive say they came from the file. */
            for (kc = 0; kc < MD_SIM_WINDOW_SIZE; kc++)
            {
                md_sim_mem[kc] = 0xE0;
            }
            es_stat_rc   = OS_SUCCESS;
            es_stat_size = fs_len;
            memset(&c, 0, sizeof(c));
            strcpy(c.LdFile.Payload.FileName, "/ram/rt.dmp");
            MM_AppData.HkTlm.Payload.CommandCounter      = 0;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_LoadMemFromFileCmd(&c.LdFile);
            printf("mmc_ldfile cc=%u ec=%u la=%u bp=%u m0=%02X m31=%02X m32=%02X\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed, md_sim_mem[0],
                   md_sim_mem[31], md_sim_mem[32]);
            /* AND THE LOAD'S OWN REFUSALS: a file that will not open, and one whose CRC is
             * wrong. The second is the deepest error arm in MM -- seven checks in. */
            fs_noexist = 1;
            MM_LoadMemFromFileCmd(&c.LdFile);
            fs_noexist = 0;
            printf("mmc_ldfile_noopen ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            fs_data[64 + 76] ^= 0xFF; /* corrupt the stored CRC */
            MM_LoadMemFromFileCmd(&c.LdFile);
            fs_data[64 + 76] ^= 0xFF;
            printf("mmc_ldfile_badcrc ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* --- MM_DumpInEventCmd. THE EVENT TEXT IS THE PAYLOAD: a 13-character header, five
             * characters per byte, and a tail with the address -- all built by repeated
             * CFE_SB_MessageStringGet into one 122-byte buffer. Eight bytes is 13 + 40 + 30 = 83
             * characters, comfortably inside; it is the one command where the formatter, the
             * string-get bound and the dump buffer are all in the same line. */
            md_sim_fill();
            memset(&c, 0, sizeof(c));
            c.DmpEv.Payload.MemType    = MM_MemType_MEM8;
            c.DmpEv.Payload.NumOfBytes = 8;
            c.DmpEv.Payload.SrcSymAddress.Offset = CFE_ES_MEMADDRESS_C(MD_SIM_WINDOW_BASE + 4);
            MM_AppData.HkTlm.Payload.CommandCounter = 0;
            MM_DumpInEventCmd(&c.DmpEv);
            printf("mmc_dmpev cc=%u la=%u mt=%u bp=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.BytesProcessed);
            /* FIFTEEN BYTES IS THE MAXIMUM, and 16 is one past it -- the verifier's EVENT limit,
             * which is the narrowest in MM and the reason the constant exists. */
            c.DmpEv.Payload.NumOfBytes = 15;
            MM_DumpInEventCmd(&c.DmpEv);
            c.DmpEv.Payload.NumOfBytes                   = 16;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_DumpInEventCmd(&c.DmpEv);
            printf("mmc_dmpev_lim ec=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
        }

        /* --- mm_dispatch.c and mm_app.c -- MM'S FRONT DOOR AND ITS RUN LOOP ----------------
         * The last two sources. ACYCLIC, unlike MD's pair: mm_app.c calls MM_TaskPipe and
         * mm_dispatch.c calls only mm_cmds.c and mm_utils.c, because MM_SendHkCmd lives in
         * mm_cmds.c rather than in the app. So the include order alone resolves them.
         *
         * MM_AppMain IS CALLED AFTER THE PIPE IT NEEDS IS ALREADY TAKEN, which is MD's lesson
         * applied rather than re-derived: the loop treats CFE_SB_TIME_OUT as "no action", so on
         * a real pipe with MM_INTERNAL_SB_TIMEOUT of 1000 ms nothing would ever end it. An
         * AppInit that FAILS sets APP_ERROR, and CFE_ES_RunLoop's first test -- on the caller's
         * own RunStatus, before any record lookup -- skips the loop entirely. Calling
         * MM_AppInit directly first takes MM_CMD_PIPE, so AppMain's CreatePipe refuses the
         * duplicate.
         *
         * AND THE APP MUST BE A **CORE** APP FOR ExitApp TO RETURN. For a CORE app with
         * APP_ERROR, ExitApp REFUSES and logs `Cannot Exit CORE Application` -- that syslog
         * line is the witness that ExitApp was reached, because a zero exit count is also what
         * "never called" looks like. */
        {
            MM_LoadMemWIDCmd_t b; /* the largest MM command, 288 bytes: the buffer */
            CFE_SB_MsgId_t     mid;
            int32              sta;
            int                ka;
            long               xa;
            bool               oka;

            /* --- MM_AppInit, the success path. Five cFE calls and nothing else: MM registers
             * no tables and uses no CDS, which NASA says in four comments of its own. The HK
             * MsgId is read back OUT of the header, because CFE_MSG_Init is the only thing
             * that puts it there. */
            memset(&MM_AppData, 0xCC, sizeof(MM_AppData));
            MM_AppData.HkTlm.Payload.CommandCounter      = 99;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 99;
            CFE_ES_Global.SystemState      = CFE_ES_SystemState_CORE_READY;
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
            es_set_ctx(1);
            sta = MM_AppInit();
            mid = CFE_SB_INVALID_MSG_ID;
            CFE_MSG_GetMsgId(CFE_MSG_PTR(MM_AppData.HkTlm.TelemetryHeader), &mid);
            printf("mma_init st=%ld run=%lu pipe=%d hkmid=0x%04x cc=%u ec=%u la=%u mt=%u\n",
                   (long)sta, (unsigned long)MM_AppData.RunStatus,
                   (int)CFE_RESOURCEID_TEST_DEFINED(MM_AppData.CmdPipe),
                   (unsigned)CFE_SB_MsgIdToValue(mid),
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType);

            /* --- MM_AppMain. The pipe name is taken, so AppInit's CreatePipe refuses and the
             * loop never runs. Three things to read: the pipe event, APP_ERROR in RunStatus,
             * and ExitApp's refusal in the syslog. */
            xa = es_taskexits;
            MM_AppMain();
            printf("mma_appmain exits=%ld run=%lu\n", es_taskexits - xa,
                   (unsigned long)MM_AppData.RunStatus);

            /* --- MM_VerifyCmdLength, both ways. It counts the bad command ITSELF, which is why
             * no handler does -- a length failure never reaches one. */
            memset(&b, 0, sizeof(b));
            CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(MM_CMD_MID),
                         sizeof(MM_NoopCmd_t));
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            /* THE CALL IS HOISTED OUT OF THE PRINT, and it has to be: the bad-length call EMITS
             * AN EVENT, and C evaluates every printf argument before printing anything -- so on
             * this half the event lands BEFORE the line, while a HolyC S()/D() chain prints as
             * it goes and would put the event in the MIDDLE of it. Third time this has bitten
             * this driver. */
            oka = MM_VerifyCmdLength(CFE_MSG_PTR(b.CommandHeader), sizeof(MM_NoopCmd_t));
            printf("mma_len ok=%d ec=%u\n", (int)oka,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            oka = MM_VerifyCmdLength(CFE_MSG_PTR(b.CommandHeader), 999);
            printf("mma_len_bad ok=%d ec=%u\n", (int)oka,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* --- MM_ProcessGroundCommand, ALL THIRTEEN CODES plus one that is not a code. The
             * sizes come from `sizeof` rather than being written out, because the switch's
             * expected length IS a sizeof and a hand-copied number would be a second opinion
             * about the layout.
             *
             * Each command is sent with ZERO payload, so the ones that act on memory are
             * refused by their own validator -- and none of those refusals prints an address,
             * which is what makes thirteen commands in one loop comparable at all. The counters
             * are the witness: MM_ProcessGroundCommand returns void. */
            mma_cc[0]  = MM_NOOP_CC;               mma_sz[0]  = sizeof(MM_NoopCmd_t);
            mma_cc[1]  = MM_RESET_COUNTERS_CC;     mma_sz[1]  = sizeof(MM_ResetCountersCmd_t);
            mma_cc[2]  = MM_PEEK_CC;               mma_sz[2]  = sizeof(MM_PeekCmd_t);
            mma_cc[3]  = MM_POKE_CC;               mma_sz[3]  = sizeof(MM_PokeCmd_t);
            mma_cc[4]  = MM_LOAD_MEM_WID_CC;       mma_sz[4]  = sizeof(MM_LoadMemWIDCmd_t);
            mma_cc[5]  = MM_LOAD_MEM_FROM_FILE_CC; mma_sz[5]  = sizeof(MM_LoadMemFromFileCmd_t);
            mma_cc[6]  = MM_DUMP_MEM_TO_FILE_CC;   mma_sz[6]  = sizeof(MM_DumpMemToFileCmd_t);
            mma_cc[7]  = MM_DUMP_IN_EVENT_CC;      mma_sz[7]  = sizeof(MM_DumpInEventCmd_t);
            mma_cc[8]  = MM_FILL_MEM_CC;           mma_sz[8]  = sizeof(MM_FillMemCmd_t);
            mma_cc[9]  = MM_LOOKUP_SYM_CC;         mma_sz[9]  = sizeof(MM_LookupSymCmd_t);
            mma_cc[10] = MM_SYM_TBL_TO_FILE_CC;    mma_sz[10] = sizeof(MM_SymTblToFileCmd_t);
            mma_cc[11] = MM_EEPROM_WRITE_ENA_CC;   mma_sz[11] = sizeof(MM_EepromWriteEnaCmd_t);
            mma_cc[12] = MM_EEPROM_WRITE_DIS_CC;   mma_sz[12] = sizeof(MM_EepromWriteDisCmd_t);
            /* The load-from-file command opens a file; make the open FAIL so the branch it takes
             * is the one event rather than whatever fs_data happens to hold. */
            fs_noexist     = 1;
            mm_eep_lock_rc = CFE_PSP_SUCCESS;
            for (ka = 0; ka < 13; ka++)
            {
                memset(&b, 0, sizeof(b));
                CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(MM_CMD_MID),
                             mma_sz[ka]);
                CFE_MSG_SetFcnCode(CFE_MSG_PTR(b.CommandHeader), mma_cc[ka]);
                MM_AppData.HkTlm.Payload.CommandCounter      = 0;
                MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
                MM_ProcessGroundCommand((CFE_SB_Buffer_t *)&b);
                printf("mma_cmd cc=%d len=%u ok=%u err=%u la=%u\n", (int)mma_cc[ka],
                       (unsigned)mma_sz[ka],
                       (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                       (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter,
                       (unsigned)MM_AppData.HkTlm.Payload.LastAction);
            }
            fs_noexist = 0;
            /* A CODE THAT IS NOT A CODE. */
            memset(&b, 0, sizeof(b));
            CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(MM_CMD_MID),
                         sizeof(MM_NoopCmd_t));
            CFE_MSG_SetFcnCode(CFE_MSG_PTR(b.CommandHeader), 99);
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_ProcessGroundCommand((CFE_SB_Buffer_t *)&b);
            printf("mma_cmd_badcc err=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* MM_ResetHk RUNS BEFORE THE CODE IS EVEN LOOKED AT, so a command whose LENGTH is
             * wrong -- which no handler ever sees -- still clears the last action. The 7 below
             * must be gone and the counter must have moved. */
            MM_AppData.HkTlm.Payload.LastAction          = MM_LastAction_FILL;
            MM_AppData.HkTlm.Payload.MemType             = MM_MemType_MEM32;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            memset(&b, 0, sizeof(b));
            CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(MM_CMD_MID), 7);
            CFE_MSG_SetFcnCode(CFE_MSG_PTR(b.CommandHeader), MM_NOOP_CC);
            MM_ProcessGroundCommand((CFE_SB_Buffer_t *)&b);
            printf("mma_resethk_first la=%u mt=%u err=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.LastAction,
                   (unsigned)MM_AppData.HkTlm.Payload.MemType,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

            /* --- MM_TaskPipe, all three routes. The MsgId cache is filled by the FIRST call;
             * with it unfilled every route falls through to the unknown-id arm, which is what
             * makes the cache load-bearing rather than an optimisation. */
            memset(&b, 0, sizeof(b));
            CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(MM_CMD_MID),
                         sizeof(MM_NoopCmd_t));
            CFE_MSG_SetFcnCode(CFE_MSG_PTR(b.CommandHeader), MM_NOOP_CC);
            MM_AppData.HkTlm.Payload.CommandCounter      = 0;
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_TaskPipe((CFE_SB_Buffer_t *)&b);
            printf("mma_pipe_cmd ok=%u err=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            /* THE HK ROUTE. MM_SendHkCmd does not move the counter, so the witness is the
             * transmit -- the "No subscribers for MsgId 0x887" line below this one. */
            memset(&b, 0, sizeof(b));
            CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(MM_SEND_HK_MID),
                         sizeof(MM_SendHkCmd_t));
            MM_AppData.HkTlm.Payload.CommandCounter = 44;
            MM_TaskPipe((CFE_SB_Buffer_t *)&b);
            printf("mma_pipe_hk ok=%u err=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandCounter,
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);
            memset(&b, 0, sizeof(b));
            CFE_MSG_Init(CFE_MSG_PTR(b.CommandHeader), CFE_SB_ValueToMsgId(0x1899),
                         sizeof(MM_NoopCmd_t));
            MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
            MM_TaskPipe((CFE_SB_Buffer_t *)&b);
            printf("mma_pipe_badmid err=%u\n",
                   (unsigned)MM_AppData.HkTlm.Payload.CommandErrorCounter);

        cs_block_utils();

            /* PUT THE APP TYPE BACK, which MD's block does and this one did not. Nothing after
             * it today but tim_objtab, so both halves agreed and the transcript was green --
             * but the NEXT app's exercise goes in this same place and would inherit a CORE app
             * and a CORE_READY system state. "An EXTERNAL app's ExitApp does not return" is the
             * hang that cost MD three steps to find; leaving the flag set is how the next
             * person finds it again. Changes no output, which is the point. */
            CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
            CFE_ES_Global.SystemState      = CFE_ES_SystemState_OPERATIONAL;
        }

        printf("tim_objtab %s %d %d %d %lu %lu\n", CFE_TIME_ModuleEntry.Name,
               (int)(CFE_TIME_ModuleEntry.EarlyInit == NULL),
               (int)(CFE_TIME_ModuleEntry.TaskMain == NULL),
               (int)(CFE_TIME_ModuleEntry.AppCleanupCb == NULL),
               (unsigned long)CFE_TIME_ModuleEntry.Priority,
               (unsigned long)CFE_TIME_ModuleEntry.StackSize);
    }
    return 0;
}




