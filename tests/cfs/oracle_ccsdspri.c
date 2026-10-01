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
#include "cfe_ta_task.h"
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
extern const Target_ObjectTable_t CFE_CONFIG_ModuleEntry;
extern const Target_ObjectTable_t CFE_TA_ModuleEntry;
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
int32 CFE_ES_WriteToSysLog(const char *SpecStringPtr, ...)
{
    (void)SpecStringPtr;
    printf("syslog\n");
    return 0;
}

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
CFE_TIME_SysTime_t CFE_TIME_GetTime(void)
{
    CFE_TIME_SysTime_t t;
    t.Seconds    = 0x20304050;
    t.Subseconds = 0x60708090;
    return t;
}

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
static unsigned char fs_data[256];
static long          fs_len;           /* bytes written so far */
static long          fs_pos;           /* current position */
static unsigned int  fs_fd;            /* 0 is OS_OBJECT_ID_UNDEFINED */
static int           fs_open_fail;     /* make OS_OpenCreate fail */
/* fs_wr_left is the number of bytes the file will still accept, not a per-call cap. A per-call
 * cap of 64 looked like it would make a record write fail and did not: the header write is 64
 * and every record is 10, so each individual write still fit and the run reported COMPLETE. */
static long          fs_wr_left;       /* < 0 = unlimited */
static int           fs_mut_create, fs_mut_take, fs_mut_give, fs_wakeups;

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

int32 OS_MutSemCreate(osal_id_t *sem_id, const char *sem_name, uint32 options)
{
    (void)sem_name; (void)options;
    ++fs_mut_create;
    *sem_id = 3;
    return OS_SUCCESS;
}

int32 OS_MutSemTake(osal_id_t sem_id)
{
    (void)sem_id;
    ++fs_mut_take;
    return OS_SUCCESS;
}

int32 OS_MutSemGive(osal_id_t sem_id)
{
    (void)sem_id;
    ++fs_mut_give;
    return OS_SUCCESS;
}

int32 CFE_ES_GetAppID(CFE_ES_AppId_t *AppIdPtr)
{
    *AppIdPtr = CFE_ES_APPID_C(CFE_ResourceId_FromInteger(0x4321));
    return CFE_SUCCESS;
}

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
 * CFE_EVS_SendEvent is variadic in the C and takes a plain string in the translation. The
 * transcript therefore compares the event ID and the TYPE and leaves the WORDING out -- the same
 * split CFE_ES_WriteToSysLog has, for the same reason: the id is what a ground system acts on. */
static int      ta_evs_count;
static int      ta_perf_depth;
static int      ta_pipe_created, ta_subscribes, ta_transmits;
static int      ta_evs_register_rc, ta_pipe_rc, ta_subscribe_rc, ta_getappid_rc, ta_msginit_rc;
static int      ta_cores;            /* what OS_TaskAffinityCoresConfigured reports */
static int      ta_getid_rc, ta_setaff_rc, ta_getaff_rc;
static unsigned char ta_os_mask;     /* the one byte the simulated OS stores per task */

CFE_Status_t CFE_EVS_Register(const void *Filters, uint16 NumFilteredEvents,
                              CFE_EVS_EventFilter_Enum_t FilterScheme)
{
    (void)Filters; (void)NumFilteredEvents; (void)FilterScheme;
    return ta_evs_register_rc;
}

int32 CFE_EVS_SendEvent(uint16 EventID, uint16 EventType, const char *Spec, ...)
{
    (void)Spec;
    ++ta_evs_count;
    printf("evs eid=%u type=%u\n", (unsigned)EventID, (unsigned)EventType);
    return CFE_SUCCESS;
}

void  CFE_ES_PerfLogAdd(uint32 Marker, uint32 EntryExit) { (void)Marker; (void)EntryExit; }
void  CFE_ES_ExitApp(uint32 ExitStatus) { printf("es_exitapp %lu\n", (unsigned long)ExitStatus); }
int32 CFE_ES_WaitForSystemState(uint32 MinSystemState, uint32 TimeOutMilliseconds)
{
    (void)MinSystemState; (void)TimeOutMilliseconds;
    return CFE_SUCCESS;
}
void CFE_ES_IncrementTaskCounter(void) {}

int32 CFE_SB_CreatePipe(CFE_SB_PipeId_t *PipeIdPtr, uint16 Depth, const char *PipeName)
{
    (void)Depth; (void)PipeName;
    ++ta_pipe_created;
    *PipeIdPtr = CFE_SB_PIPEID_C(CFE_ResourceId_FromInteger(0x1111));
    return ta_pipe_rc;
}

int32 CFE_SB_Subscribe(CFE_SB_MsgId_t MsgId, CFE_SB_PipeId_t PipeId)
{
    (void)MsgId; (void)PipeId;
    ++ta_subscribes;
    return ta_subscribe_rc;
}

/* Never reached by the transcript -- CFE_TA_TaskMain is the only caller and it is not driven
 * (it pends forever and ends in CFE_ES_ExitApp). It has to EXIST because the C side links
 * cfe_ta_task.c, which is the same reason the HolyC side declares it. */
CFE_Status_t CFE_SB_ReceiveBuffer(CFE_SB_Buffer_t **BufPtr, CFE_SB_PipeId_t PipeId,
                                  int32 TimeOut)
{
    (void)BufPtr; (void)PipeId; (void)TimeOut;
    return CFE_SUCCESS;
}

/* NOT stubbed: CFE_SB_TimeStampMsg is in cfe_sb_util.c, which this gate already translates, so
 * the housekeeping path runs the real one -- through CFE_TIME_GetTime and CFE_MSG_SetMsgTime,
 * both translated as well. Three translated modules composing, which is new here. */
CFE_Status_t CFE_SB_TransmitMsg(const CFE_MSG_Message_t *MsgPtr, bool IsOrigination)
{
    (void)MsgPtr; (void)IsOrigination;
    ++ta_transmits;
    return CFE_SUCCESS;
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

        /* The destination list head is stored and returned, never inspected. */
        CFE_SBR_SetDestListHeadPtr(rid2, (CFE_SB_DestinationD_t *)0x1234);
        printf("sbr_dest %d %d\n", (int)(CFE_SBR_GetDestListHeadPtr(rid2) == (void *)0x1234),
               (int)(CFE_SBR_GetDestListHeadPtr(CFE_SBR_INVALID_ROUTE_ID) == NULL));

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
    ta_pipe_rc         = CFE_SUCCESS;
    ta_subscribe_rc    = CFE_SUCCESS;
    ta_cores           = 1;
    printf("ta_init rc=%ld pipes=%d subs=%d\n", (long)CFE_TA_TaskInit(), ta_pipe_created,
           ta_subscribes);
    printf("ta_init_diag cores=%u max=%u app=%lu\n", CFE_TA_Global.CFE_TA_DiagInfo.CoresConfigured,
           CFE_TA_Global.CFE_TA_DiagInfo.TACoresMax,
           (unsigned long)CFE_RESOURCEID_TO_ULONG(CFE_TA_Global.TA_AppID));

    ta_evs_register_rc = -77;
    printf("ta_init_evsfail rc=%ld\n", (long)CFE_TA_TaskInit());
    ta_evs_register_rc = CFE_SUCCESS;
    ta_pipe_rc = -78;
    printf("ta_init_pipefail rc=%ld\n", (long)CFE_TA_TaskInit());
    ta_pipe_rc = CFE_SUCCESS;
    ta_subscribe_rc = -79;
    printf("ta_init_subfail rc=%ld\n", (long)CFE_TA_TaskInit());
    ta_subscribe_rc = CFE_SUCCESS;

    /* --- the simple commands -------------------------------------------------------------- */
    printf("ta_noop rc=%ld\n", (long)CFE_TA_NoopCmd(NULL));
    CFE_TA_Global.CommandCounter      = 7;
    CFE_TA_Global.CommandErrorCounter = 8;
    CFE_TA_Global.StartupCounter      = 9;
    CFE_TA_Global.StartupErrorCounter = 10;
    printf("ta_hk rc=%ld tx=%d pay=%u/%u/%u/%u\n", (long)CFE_TA_ReportHousekeepingCmd(NULL),
           ta_transmits, CFE_TA_Global.TA_TlmPkt.Payload.CommandCounter,
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
    return 0;
}



