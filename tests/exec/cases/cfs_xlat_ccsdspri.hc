// Differential oracle, HolyC side: drives the 1:1 translation of NASA cFE's CCSDS primary header
// accessors and prints the same transcript as tests/cfs/oracle_ccsdspri.c does against the
// unmodified C. The gate diffs the two. Standalone on purpose -- no kernel includes -- so the
// only thing under test is the translation and the compiler.
#include "/Kernel/Cfs/cfe/cfe_msg_msgid_v1.HC"
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
// ToUpper and StrNCmp, the two kernel primitives cfe_config_init.HC reaches for. Both are
// REAL kernel primitives -- ToUpper is `_intern IC_TOUPPER` in KernelB.HH and StrNCmp is
// `_extern _STRNCMP` in StrA.HC -- and both are also names bootstrap/holy_rt_names.h knows,
// which means leaving them out of this standalone harness does not fail: they bind SILENTLY to
// the host C runtime and the gate reports identical lines while running C code. That is what
// the blob import trailer check exists for, and it is how this comment came to be written.
//
// Both are reproduced to match the runtime (bootstrap/holy_rt.h):
//   HolyToUpper   'a'..'z' shift by 32, everything else unchanged -- same as C's toupper
//   HolyStrNCmp   a BYTE DIFFERENCE, unlike StrCmp's +-1. cFE compares against zero, so the
//                 magnitude does not matter here, but the difference is reproduced anyway.
I64 ToUpper(I64 c)
{
  if (c >= 'a' && c <= 'z')
    return c - 32;
  return c;
}
// MemCmp is a kernel primitive (_extern _MEMCMP in KernelB.HH) and a runtime name, so leaving
// it out of this standalone harness binds it silently to the host C runtime -- the trailer
// check is what said so. Reproduced to match bootstrap/holy_rt.h's HolyMemCmp: a BYTE
// DIFFERENCE, and cFE compares it against zero.
I64 MemCmp(U8 *a, U8 *b, I64 n)
{
  I64 i;
  for (i = 0; i < n; i++) {
    if (a[i] != b[i])
      return a[i] - b[i];
  }
  return 0;
}

I64 StrNCmp(U8 *a, U8 *b, I64 n)
{
  I64 i;
  for (i = 0; i < n; i++) {
    if (a[i] != b[i])
      return a[i] - b[i];
    if (!a[i])
      return 0;
  }
  return 0;
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
#include "/Kernel/Cfs/cfe/cfe_msg_sechdr_fc.HC"
#include "/Kernel/Cfs/cfe/cfe_msg_sechdr_time.HC"
#include "/Kernel/Cfs/cfe/cfe_msg_sechdr_checksum.HC"
#include "/Kernel/Cfs/cfe/cfe_msg_init.HC"
#include "/Kernel/Cfs/cfe/cfe_msg_integrity.HC"
#include "/Kernel/Cfs/cfe/cfe_msg_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_resourceid.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_util.HC"
#include "/Kernel/Cfs/cfe/cfe_sbr_map_hash.HC"
#include "/Kernel/Cfs/cfe/cfe_sbr_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_config.HC"
#include "/Kernel/Cfs/cfe/cfe_target_config.HC"
#include "/Kernel/Cfs/cfe/cfe_platformcfg_tables.HC"
#include "/Kernel/Cfs/cfe/cfe_config_init.HC"
#include "/Kernel/Cfs/cfe/cfe_config_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_fs_priv.HC"
#include "/Kernel/Cfs/cfe/cfe_fs_api.HC"
#include "/Kernel/Cfs/cfe/cfe_fs_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_ta_task.HC"
#include "/Kernel/Cfs/cfe/cfe_ta_dispatch.HC"
#include "/Kernel/Cfs/cfe/cfe_ta_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_evs_global.HC"
#include "/Kernel/Cfs/cfe/cfe_evs_utils.HC"
#include "/Kernel/Cfs/cfe/cfe_evs_log.HC"
#include "/Kernel/Cfs/cfe/cfe_evs.HC"
#include "/Kernel/Cfs/cfe/cfe_evs_task.HC"
#include "/Kernel/Cfs/cfe/cfe_evs_dispatch.HC"
#include "/Kernel/Cfs/cfe/cfe_evs_objtab.HC"
// The time module. cfe_time_global.HC carries the types AND the object, cfe_time_utils.HC the
// reference ring, cfe_time_api.HC the public calls -- in that order, because api states that
// as its requirement rather than including its siblings (docs/HOLYC_STRUCT_LIMITS.md #13).
#include "/Kernel/Cfs/cfe/cfe_time_global.HC"
#include "/Kernel/Cfs/cfe/cfe_es_resetdata.HC"
#include "/Kernel/Cfs/cfe/cfe_time_utils.HC"
#include "/Kernel/Cfs/cfe/cfe_time_api.HC"
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

U0 Dump(U8 *tag, CFE_MSG_Message *m)
{
  S(tag);
  S(" ");
  D(m->CCSDS.Pri.StreamId[0]);
  S(" ");
  D(m->CCSDS.Pri.StreamId[1]);
  S(" ");
  D(m->CCSDS.Pri.Sequence[0]);
  S(" ");
  D(m->CCSDS.Pri.Sequence[1]);
  S(" ");
  D(m->CCSDS.Pri.Length[0]);
  S(" ");
  D(m->CCSDS.Pri.Length[1]);
  S("\n");
}

U0 Rc(U8 *label, I32 rc)
{
  S(label);
  S(" rc=");
  D(rc);
  S("\n");
}
// Same, for the lines that print a status AND an out-parameter. The status goes through an I32
// parameter for the reason above.
U0 Rcv(U8 *label, I32 rc, U8 *key, I64 v)
{
  S(label);
  S(" rc=");
  D(rc);
  S(" ");
  S(key);
  S("=");
  D(v);
  S("\n");
}
// The two symbols the translated units declare and leave to whoever links them. Same values as
// the C oracle's stubs, so the comparison stays about cFE and not about the platform.
U32 CFE_PSP_GetProcessorId()
{
  return 1;
}
// Formats, as NASA's does. It printed a bare "syslog" while the translation's call sites took a
// plain string; now that they pass NASA's arguments, the text is the thing worth comparing --
// a status code in a log line is the same kind of evidence as one in an event.
I32 CFE_ES_WriteToSysLog(U8 *Msg,...)
{
  U8 buf[200];
  StrPrintNV(buf, 200, Msg, argc, argv);
  S("syslog ");
  S(buf);
  return 0;
}
// The C declares this `static const uint32 ARR[3] = {11, 22, 33}` inside its block -- static,
// so not on the stack. File scope is the faithful HolyC equivalent.
U32 CFG_ARR[3];
// Counts entries CFE_Config_IterateAll visits.
I64 cfg_visits;
U0 cfg_count_cb(U8 *Arg, U32 Id, U8 *Name)
{
  cfg_visits++;
}
// Counts how many route ids ForEachRouteId hands back.
I64 sbr_visits;
U0 sbr_count_cb(CFE_SBR_RouteId RouteId, U8 *ArgPtr)
{
  sbr_visits++;
}
// Check functions for CFE_ResourceId_FindNext. "In use" is serial 6 or 7, chosen so the search
// has to step over two occupied slots and land on the third -- one occupied slot would pass even
// if the do-while ran once instead of looping.
Bool rid_in_use(U32 id)
{
  U32 serial = CFE_ResourceId_GetSerial(id);
  return serial == 6 || serial == 7;
}

Bool rid_all_in_use(U32 id)
{
  return TRUE;
}
// CFE_TIME_GetTime and CFE_TIME_Print are no longer stubbed: cfe_time_utils.c and
// cfe_time_api.c are gated, so the real ones run. Both were ALREADY inside the byte-identical
// comparison -- every "1980-001-00:00:44.52768" in the transcript is a timestamp CFE_TIME_Print
// rendered -- the stub just happened to agree with itself on both sides. Now the C half calls
// glibc's gmtime_r and strftime and this half calls the calendar conversion in cfe_time_api.HC.
// Six lowercase hex digits, to match the C oracle's %06lx.
U0 Hx6(I64 v)
{
  U8 *hx = "0123456789abcdef";
  U8 one[2];
  I64 i;
  one[1] = 0;
  for (i = 20; i >= 0; i -= 4) {
    one[0] = hx[(v >> i) & 15];
    S(one);
  }
}
// Four lowercase hex digits, twice on a line, to match the C oracle's %04lx.
U0 Hx4(I64 v)
{
  U8 *hx = "0123456789abcdef";
  U8 one[2];
  I64 i;
  one[1] = 0;
  for (i = 12; i >= 0; i -= 4) {
    one[0] = hx[(v >> i) & 15];
    S(one);
  }
}

U0 Hx2(U8 *l1, I64 v1, U8 *l2, I64 v2)
{
  S(l1);
  S("0x");
  Hx4(v1);
  S(l2);
  S("0x");
  Hx4(v2);
  S("\n");
}
// Two out-parameters on one line, for the time round trip.
U0 Rcv2(U8 *label, I32 rc, U8 *k1, I64 v1, U8 *k2, I64 v2)
{
  S(label);
  S(" rc=");
  D(rc);
  S(" ");
  S(k1);
  S("=");
  D(v1);
  S(" ");
  S(k2);
  S("=");
  D(v2);
  S("\n");
}
// =========================== cFE fs module ======================================================
// A SIMULATED FILE, identical on both sides of the oracle.
//
// fs is the first translated module that calls OSAL, and OSAL has a gate of its own (423
// transcript lines, its own stub backend). Linking the two together here would make this
// transcript depend on both at once and stop telling us which one moved. So both sides get the
// same tiny in-memory file instead, and this gate stays about fs.
//
// The injection flags exist because three of the five Meta->OnEvent call sites are error paths.
// A file that always succeeds would leave the function-pointer-member call -- the compiler
// feature this module needed -- exercised on two sites out of five by the transcript that is
// supposed to validate it. So the driver drives one create failure, one short header write and
// one short record write, and all four event codes appear below.
// 4096, matching the C half: at 256 the simulated file could not hold one CFE_TA_DiagInfo_t,
// so QueryAllTasksCmd's success branch was unreachable on both sides. See the note there.
U8 fs_data[4096];
I64 fs_len;
// bytes written so far
I64 fs_pos;
// current position
U32 fs_fd;
// 0 is OS_OBJECT_ID_UNDEFINED
I64 fs_open_fail;
// make OS_OpenCreate fail
// fs_wr_left is the number of bytes the file will still accept, not a per-call cap. A per-call
// cap of 64 looked like it would make a record write fail and did not: the header write is 64
// and every record is 10, so each individual write still fit and the run reported COMPLETE.
I64 fs_wr_left;
// < 0 = unlimited
I64 fs_mut_create, fs_mut_take, fs_mut_give, fs_wakeups;
// Steer the three mutex calls; see the note in the C half. Without these, cfe_fs_priv.c's
// three syslog lines are unreachable -- including the only one that formats three arguments.
I64 fs_mut_create_rc, fs_mut_take_rc, fs_mut_give_rc;
I32 OS_OpenCreate(U32 *filedes, U8 *path, I32 flags, I32 access_mode)
{
  if (fs_open_fail)
    return -1;
  // OS_ERROR
  fs_fd = 7;
  *filedes = 7;
  fs_len = 0;
  fs_pos = 0;
  return OS_SUCCESS;
}

I32 OS_close(U32 filedes)
{
  fs_fd = 0;
  return OS_SUCCESS;
}

I32 OS_read(U32 filedes, U8 *buffer, I64 nbytes)
{
  I64 n = nbytes;
  if (n > fs_len - fs_pos)
    n = fs_len - fs_pos;
  if (n < 0)
    n = 0;
  MemCpy(buffer, &fs_data[fs_pos], n);
  fs_pos += n;
  return n;
}

I32 OS_write(U32 filedes, U8 *buffer, I64 nbytes)
{
  I64 n = nbytes;
  if (fs_wr_left >= 0) {
    if (n > fs_wr_left)
      n = fs_wr_left;
    fs_wr_left -= n;
  }
  if (fs_pos + n > sizeof(fs_data))
    n = sizeof(fs_data) - fs_pos;
  MemCpy(&fs_data[fs_pos], buffer, n);
  fs_pos += n;
  if (fs_pos > fs_len)
    fs_len = fs_pos;
  return n;
}

I32 OS_lseek(U32 filedes, I64 offset, U32 whence)
{
  fs_pos = offset;
  return offset;
}

Bool OS_ObjectIdDefined(U32 object_id)
{
  return object_id != 0;
}

I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options)
{
  ++fs_mut_create;
  *sem_id = 3;
  return fs_mut_create_rc;
}

I32 OS_MutSemTake(U32 sem_id)
{
  ++fs_mut_take;
  return fs_mut_take_rc;
}

I32 OS_MutSemGive(U32 sem_id)
{
  ++fs_mut_give;
  return fs_mut_give_rc;
}
// Who the caller is. fs and ta only needed a fixed value; EVS branches on it -- an app that
// has registered, one that has not, and one whose id is out of range are three different paths
// through CFE_EVS_SendEvent -- so the driver steers it. 0x4321 keeps the fs and ta lines above
// exactly as they were.
I64 ta_getappid = 0x4321;
I32 CFE_ES_GetAppID(U32 *AppIdPtr)
{
  *AppIdPtr = ta_getappid;
  return CFE_SUCCESS;
}

U0 CFE_ES_BackgroundWakeup()
{
  ++fs_wakeups;
}

U32 CFE_PSP_GetSpacecraftId()
{
  return 0x5A5A;
}
// The requester's two callbacks. Three records of ten bytes, with record 1 deliberately EMPTY --
// NASA's loop keeps going on a zero-size record, for holes in a table, and a getter that never
// returns 0 would not exercise that.
U8 fs_rec[16];
I64 fs_events;
Bool fs_getdata(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize)
{
  I64 i;
  for (i = 0; i < 10; i++)
    fs_rec[i] = 0xA0 + RecordNum * 16 + i;
  *Buffer = fs_rec;
  if (RecordNum == 1)
    *BufSize = 0;
  else
    *BufSize = 10;
  return RecordNum >= 3;
}

U0 fs_onevent(U8 *Meta, I32 Event, I32 Status, U32 RecordNum, I64 BlockSize, I64 Position)
{
  ++fs_events;
  S("fs_event ev=");
  D(Event);
  S(" st=");
  D(Status);
  S(" rec=");
  D(RecordNum);
  S(" blk=");
  D(BlockSize);
  S(" pos=");
  D(Position);
  S("\n");
}
// Eight lowercase hex digits, to match the C oracle's %08lx.
U0 Hx8(I64 v)
{
  U8 *hx = "0123456789abcdef";
  U8 one[2];
  I64 i;
  one[1] = 0;
  for (i = 28; i >= 0; i -= 4) {
    one[0] = hx[(v >> i) & 15];
    S(one);
  }
}
// One byte as two lowercase hex digits, to match %02x.
U0 Hxb(I64 v)
{
  U8 *hx = "0123456789abcdef";
  U8 one[2];
  one[1] = 0;
  one[0] = hx[(v >> 4) & 15];
  S(one);
  one[0] = hx[v & 15];
  S(one);
}
// A string that may be NULL, printed the way C's %s with a ternary does it here.
U0 Sn(U8 *s)
{
  if (s == NULL)
    S("(null)");
  else
    S(s);
}
// The file's bytes, so the big-endian conversion in WriteHeader is in the transcript rather than
// merely implied by a return value.
U0 fs_dump(U8 *tag, I64 n)
{
  I64 i;
  S(tag);
  for (i = 0; i < n; i++) {
    S(" ");
    Hxb(fs_data[i]);
  }
  S("\n");
}

U0 fs_hdr(U8 *tag, CFE_FS_Header_t *h)
{
  S(tag);
  S(" ct=");
  Hx8(h->ContentType);
  S(" sub=");
  D(h->SubType);
  S(" len=");
  D(h->Length);
  S(" sc=");
  D(h->SpacecraftID);
  S(" pr=");
  D(h->ProcessorID);
  S(" app=");
  D(h->ApplicationID);
  S(" ts=");
  Hx8(h->TimeSeconds);
  S(" tss=");
  Hx8(h->TimeSubSeconds);
  S(" d=[");
  S(h->Description);
  S("]\n");
}

U0 fs_parse_out(U8 *tag, U8 *out, I32 rc)
{
  S(tag);
  S(" rc=");
  D(rc);
  S(" [");
  S(out);
  S("]\n");
}
// ---- what EVS needs from the layers it sits on -------------------------------------------
// Every one of these is deterministic on purpose: EVS times its squelch bucket off
// CFE_PSP_GetTime, so a real clock would make the transcript depend on how fast the host is.
//
// CFE_EVS_Global is NOT defined here: it lives in cfe_evs_global.HC with the rest of the
// declarations, because cfe_evs_task.c -- where NASA defines it -- is the one EVS source not
// translated yet. The C side of this oracle defines it in the driver for the same reason, and
// when that source is translated the definition moves there on both sides.
CFE_EVS_Log_t evs_log_storage;
// what CFE_PSP_GetTime reports, in ticks (= ns here)
I64 evs_psp_ns;
I64 evs_printf_lines;
#define CFE_ES_ERR_NAME_NOT_FOUND 0xC4000002(I32)
I32 CFE_ES_AppID_ToIndex(U32 AppID, U32 *Idx)
{
  // The real one strips the resource-type bits; with the SIMPLE variant the id IS the index
  // for the small values this driver uses, and anything at or past the table size is rejected
  // so EVS_GetAppDataByID's NULL branch stays reachable.
  if (AppID >= CFE_PLATFORM_ES_MAX_APPLICATIONS)
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  *Idx = AppID;
  return CFE_SUCCESS;
}

I32 CFE_ES_GetAppIDByName(U32 *AppIdPtr, U8 *AppName)
{
  if (StrCmp(AppName, "CFE_EVS") == 0) {
    *AppIdPtr = 1;
    return CFE_SUCCESS;
  }
  if (StrCmp(AppName, "OTHER_APP") == 0) {
    *AppIdPtr = 2;
    return CFE_SUCCESS;
  }
  return CFE_ES_ERR_NAME_NOT_FOUND;
}

I32 CFE_ES_GetAppName(U8 *AppName, U32 AppId, I64 BufferLength)
{
  if (AppId == 1)
    StrNCpy(AppName, "CFE_EVS", BufferLength - 1);
  else if (AppId == 2)
    StrNCpy(AppName, "OTHER_APP", BufferLength - 1);
  else
    StrPrintN(AppName, BufferLength, "APP%u", AppId);
  return CFE_SUCCESS;
}
// Lives in cfe_evs_task.c, the last of EVS's six sources and not translated yet.
U0 CFE_PSP_GetTime(OS_time_t *LocalTime)
{
  LocalTime->ticks = evs_psp_ns;
}
// OSAL's time arithmetic. Reproduced rather than included, for the reason cfe_evs_utils.HC
// records: osapi_clock.HC reaches OS_GetLocalTime_Impl and the error-name tables. These two
// are the whole of what EVS uses, and they are exact -- a tick is a nanosecond here.
OS_time_t OS_TimeSubtract(OS_time_t time1, OS_time_t time2)
{
  OS_time_t ostm;
  ostm.ticks = time1.ticks - time2.ticks;
  return ostm;
}

I64 OS_TimeGetTotalMilliseconds(OS_time_t tm)
{
  return tm.ticks / 1000000;
}

U0 OS_printf(U8 *String,...)
{
  U8 line[256];
  ++evs_printf_lines;
  StrPrintNV(line, sizeof(line), String, argc, argv);
  S(line);
}
// ---- cfe_config_init.c helpers -------------------------------------------------------------
// Two module lists and a key/value list, so FindTargetKeyValue, IsModuleInList, IsPspModule and
// FindStaticModName are exercised on data this driver controls rather than only on the generated
// target config. The NULL terminators are what the walks stop on.
CFE_ConfigName_t ci_core[3] = {{"CFE_ES"}, {"CFE_SB"}, {NULL}};
CFE_ConfigName_t ci_apps[2] = {{"ci_lab"}, {NULL}};
CFE_StaticModuleLoadEntry_t ci_psp[3] = {{"soft_timebase", NULL}, {"eeprom_direct", NULL}, {NULL, NULL}};
CFE_ConfigKeyValue_t ci_kv[4] = {{"CFE_ES", "1.2.3"}, {"ci_lab", "4.5.6"}, {"SOFT_TIMEBASE", "7.8.9"}, {NULL, NULL}};
U0 ci_str(U8 *tag, U8 *s)
{
  S(tag);
  S(" [");
  Sn(s);
  S("]\n");
}
// =========================== cFE ta module =====================================================
// A SIMULATED OS AND BUS, identical on both sides.
//
// TA is the first translated module that is an APP: a task, a command pipe, a housekeeping
// packet, and 17 event messages. SB, EVS and ES are not translated, so both sides get the same
// recording stubs; the affinity side is a small table this driver controls, so the three-way
// loop bound in CFE_TA_Cpu_Set and every branch of the two affinity commands can be driven.
//
// BOTH SPLITS ARE GONE. CFE_EVS_SendEvent and CFE_ES_WriteToSysLog each used to take a plain
// string here, with the event id and the branch compared and the wording left out. EVS is
// translated now and StrPrintNV formats, so both pass NASA's own arguments and the text they
// produce is inside the byte-identical comparison.
I64 ta_evs_count;
I64 ta_pipe_created, ta_subscribes, ta_transmits;
I64 ta_evs_register_rc, ta_pipe_rc, ta_subscribe_rc;
I64 ta_cores;
// what OS_TaskAffinityCoresConfigured reports
I64 ta_getid_rc, ta_setaff_rc, ta_getaff_rc;
U8 ta_os_mask;
// the one byte the simulated OS stores per task
// CFE_EVS_Register and CFE_EVS_SendEvent are NOT stubbed any more: cfe_evs.HC is included
// above, so ta's events go through the real thing -- registration, filtering, the squelch
// token bucket, the local log, the formatter and the two output ports. The `evs eid=N type=N`
// lines this driver used to print are gone, and what replaces them is EVS_OutputPort's real
// text through OS_printf.
U0 CFE_ES_PerfLogEntry(U32 Marker)
{
}

U0 CFE_ES_PerfLogExit(U32 Marker)
{
}

U0 CFE_ES_ExitApp(U32 ExitStatus)
{
  S("es_exitapp ");
  D(ExitStatus);
  S("\n");
}

I32 CFE_ES_WaitForSystemState(U32 MinSystemState, U32 TimeOutMilliseconds)
{
  return CFE_SUCCESS;
}
// --- the reset area, for CFE_EVS_EarlyInit ----------------------------------------------------
// EVS's early init asks the PSP for the reset area, checks its SIZE against the whole of
// CFE_ES_ResetData_t and panics if it is short, then takes the event log out of it. So the driver
// supplies a real one, and the three things EarlyInit can be told are all steerable: the PSP
// call's status, the size it reports, and the reset type.
CFE_ES_ResetData_t evs_reset_area;
I64 evs_resetarea_rc;
// what CFE_PSP_GetResetArea returns
I64 evs_resetarea_size;
// what it reports, 0 = the real sizeof
I64 evs_reset_type;
// what CFE_ES_GetResetType answers
I64 evs_panics, evs_delay_ms;
// what the panic and delay stubs recorded
I32 CFE_PSP_GetResetArea(U64 *PtrToResetArea, U32 *SizeOfResetArea)
{
  *PtrToResetArea = &evs_reset_area;
  if (evs_resetarea_size)
    *SizeOfResetArea = evs_resetarea_size;
  else
    *SizeOfResetArea = sizeof(CFE_ES_ResetData_t);
  return evs_resetarea_rc;
}

I32 CFE_ES_GetResetType(U32 *ResetSubtypePtr)
{
  return evs_reset_type;
}
// NASA's CFE_PSP_Panic does not return; this one does, because EarlyInit's code AFTER the panic
// is part of what the transcript compares -- it falls through to `return Status`.
U0 CFE_PSP_Panic(I32 ErrorCode)
{
  ++evs_panics;
  S("psp_panic ");
  D(ErrorCode);
  S("\n");
}

I32 OS_TaskDelay(U32 millisecond)
{
  evs_delay_ms += millisecond;
  return OS_SUCCESS;
}
// cfe_time_tone.c is not gated, and CFE_TIME_ExternalTone's whole body is a call to this.
I64 evs_tone_isrs;
U0 CFE_TIME_Tone1HzISR()
{
  ++evs_tone_isrs;
}

U0 CFE_ES_IncrementTaskCounter()
{
}

I32 CFE_SB_CreatePipe(U32 *PipeIdPtr, U16 Depth, U8 *PipeName)
{
  ++ta_pipe_created;
  *PipeIdPtr = 0x1111;
  return ta_pipe_rc;
}

I32 CFE_SB_Subscribe(U32 MsgId, U32 PipeId)
{
  ++ta_subscribes;
  return ta_subscribe_rc;
}
// Never reached by the transcript -- CFE_TA_TaskMain is the only caller and it is not driven
// (it pends forever and ends in CFE_ES_ExitApp). It has to EXIST because the translation
// declares it, and the blob import trailer is what would say so if it did not.
I32 CFE_SB_ReceiveBuffer(CFE_SB_Buffer **BufPtr, U32 PipeId, I32 TimeOut)
{
  return CFE_SUCCESS;
}
// NOT stubbed: CFE_SB_TimeStampMsg is in cfe_sb_util.HC, which this gate already translates, so
// the housekeeping path runs the real one -- through CFE_TIME_GetTime and CFE_MSG_SetMsgTime,
// both translated as well. Three translated modules composing, which is new here.
I32 CFE_SB_TransmitMsg(CFE_MSG_Message *MsgPtr, Bool IsOrigination)
{
  ++ta_transmits;
  return CFE_SUCCESS;
}
// The simulated OS's task table: one name, one id, one stored affinity byte. Everything the two
// affinity commands branch on is a variable here.
I32 OS_TaskGetIdByName(U32 *task_id, U8 *task_name)
{
  *task_id = 0x2222;
  return ta_getid_rc;
}

I32 OS_TaskAffinitySetAffinity(U32 task_id, OS_cpuset_t cpuset)
{
  if (ta_setaff_rc == OS_SUCCESS)
    ta_os_mask = cpuset.affinity_mask[0];
  return ta_setaff_rc;
}

I32 OS_TaskAffinityGetAffinity(U32 task_id, OS_cpuset_t *cpuset)
{
  OS_CPUSET_ZERO(cpuset);
  cpuset->affinity_mask[0] = ta_os_mask;
  return ta_getaff_rc;
}

U32 OS_TaskAffinityCoresConfigured()
{
  return ta_cores;
}

I32 OS_RegisterEventHandler(I32 (*handler)(I64, U32, U8 *))
{
  return OS_SUCCESS;
}

I32 OS_GetResourceName(U32 object_id, U8 *buffer, I64 buffer_size)
{
  StrNCpy(buffer, "STARTUP_TASK", buffer_size - 1);
  return OS_SUCCESS;
}
// One row of the live affinity table, so the branch each command took is visible as STATE and
// not only as an event id.
U0 ta_row(U8 *tag, I64 i)
{
  S(tag);
  S("[");
  D(i);
  S("] name=[");
  S(CFE_TA_CpuTaskAffinity[i].TaskName);
  S("] mask=");
  Hxb(CFE_TA_CpuTaskAffinity[i].CpuMask.affinity_mask[0]);
  S(" fromos=");
  Hxb(CFE_TA_CpuTaskAffinity[i].CpuFromOS.affinity_mask[0]);
  S(" type=");
  D(CFE_TA_CpuTaskAffinity[i].Type);
  S(" status=");
  D(CFE_TA_CpuTaskAffinity[i].Status);
  S("\n");
}

U0 ta_counters(U8 *tag)
{
  S(tag);
  S(" cc=");
  D(CFE_TA_Global.CommandCounter);
  S(" cec=");
  D(CFE_TA_Global.CommandErrorCounter);
  S(" sc=");
  D(CFE_TA_Global.StartupCounter);
  S(" sec=");
  D(CFE_TA_Global.StartupErrorCounter);
  S(" evs=");
  D(ta_evs_count);
  S("\n");
}
// The config-supplied affinity table and the SB buffer union the dispatch test needs, at file
// scope as the C's `static` ones are.
CFE_TA_CpuTaskAffinity_t ta_tbl[4];
union ta_sb_u
{
  CFE_SB_Buffer Buf;
  CFE_TA_SetTaskAffinityCmd_t Set;
  CFE_TA_QueryAllTasksCmd_t Query;
  U8 Bytes[128];
};
ta_sb_u ta_sb;
// The command buffer the EVS task block needs. A HolyC union is declared at file scope, as
// ta_sb_u above is.
union evt_c_u
{
  CFE_SB_Buffer Buf;
  CFE_EVS_EnablePortsCmd_t Ports;
  CFE_EVS_EnableAppEventTypeCmd_t AppType;
  CFE_EVS_SetFilterCmd_t Filter;
  CFE_EVS_ResetFilterCmd_t RstFilter;
  CFE_EVS_EnableAppEventsCmd_t AppEvt;
  CFE_EVS_SetEventFormatModeCmd_t Fmt;
  CFE_EVS_SetLogModeCmd_t LogMode;
  CFE_EVS_WriteAppDataFileCmd_t AppData;
  CFE_EVS_WriteLogDataFileCmd_t LogData;
  U8 Bytes[256];
};
evt_c_u evt_c;
// The five objects the queue-full case needs at file scope, as the C's `static` ones are.
CFE_FS_FileWriteMetaData_t fs_q[5];
I64 main()
{
  CFE_MSG_Message msg;
  U16 ver, apid, seq;
  I32 rc32;
  I64 type, segf, size;
  Bool hassec;
  I64 i;
  U8 *p = &msg;
  for (i = 0; i < sizeof(CFE_MSG_Message); i++)
    p[i] = 0;
  Dump("zero", &msg);
  Rc("setver  ", CFE_MSG_SetHeaderVersion(&msg, 1));
  Dump("afterver", &msg);
  rc32 = CFE_MSG_GetHeaderVersion(&msg, &ver);
  Rcv("getver  ", rc32, "v", ver);
  Rc("settype ", CFE_MSG_SetType(&msg, CFE_MSG_Type_Cmd));
  Dump("aftertype", &msg);
  rc32 = CFE_MSG_GetType(&msg, &type);
  Rcv("gettype ", rc32, "t", type);
  Rc("setapid ", CFE_MSG_SetApId(&msg, 0x1AB));
  Dump("afterapid", &msg);
  rc32 = CFE_MSG_GetApId(&msg, &apid);
  Rcv("getapid ", rc32, "a", apid);
  Rc("setsec  ", CFE_MSG_SetHasSecondaryHeader(&msg, TRUE));
  rc32 = CFE_MSG_GetHasSecondaryHeader(&msg, &hassec);
  Rcv("getsec  ", rc32, "s", hassec);
  Dump("aftersec", &msg);
  Rc("setseg  ", CFE_MSG_SetSegmentationFlag(&msg, CFE_MSG_SegFlag_Unsegmented));
  rc32 = CFE_MSG_GetSegmentationFlag(&msg, &segf);
  Rcv("getseg  ", rc32, "g", segf);
  Rc("setseq  ", CFE_MSG_SetSequenceCount(&msg, 0x2345));
  rc32 = CFE_MSG_GetSequenceCount(&msg, &seq);
  Rcv("getseq  ", rc32, "q", seq);
  Dump("afterseq", &msg);
  Rc("setsize ", CFE_MSG_SetSize(&msg, 0x100));
  rc32 = CFE_MSG_GetSize(&msg, &size);
  Rcv("getsize ", rc32, "z", size);
  Dump("aftersize", &msg);
  Rc("badver  ", CFE_MSG_SetHeaderVersion(&msg, 0xFF));
  Rc("badapid ", CFE_MSG_SetApId(&msg, 0xFFFF));
  Rc("badnull ", CFE_MSG_GetType(NULL, &type));
  Rc("badsize ", CFE_MSG_SetSize(&msg, 0));
  Dump("final", &msg);
  // --- cfe_msg_msgid_v1.c plus the SB opaque-id helpers -------------------------------
  // Every CFE_SB_ValueToMsgId result is hoisted into a local rather than passed inline. The
  // result is a class BY VALUE, and nested calls in a non-variadic argument list are a known
  // codegen hazard in this compiler (see the ptr-assign scaling fix). Hoisting costs nothing
  // and keeps the translation's correctness separate from that question.
  
  {
    CFE_SB_MsgId mid, t;
    I32 rc32;
    for (i = 0; i < sizeof(CFE_MSG_Message); i++)
      p[i] = 0;
    t = CFE_SB_ValueToMsgId(0x0801);
    Rc("setmid  ", CFE_MSG_SetMsgId(&msg, t));
    Dump("aftermid", &msg);
    rc32 = CFE_MSG_GetMsgId(&msg, &mid);
    Rcv("getmid  ", rc32, "m", CFE_SB_MsgIdToValue(mid));
    t = CFE_SB_ValueToMsgId(0);
    Rc("midzero ", CFE_MSG_SetMsgId(&msg, t));
    t = CFE_SB_ValueToMsgId(0x2000);
    Rc("midhigh ", CFE_MSG_SetMsgId(&msg, t));
    Rc("midnull ", CFE_MSG_GetMsgId(NULL, &mid));
    S("midvalid v=");
    t = CFE_SB_ValueToMsgId(0x1FFF);
    D(CFE_SB_IsValidMsgId(t));
    S(" z=");
    t = CFE_SB_ValueToMsgId(0);
    D(CFE_SB_IsValidMsgId(t));
    S(" h=");
    t = CFE_SB_ValueToMsgId(0x2000);
    D(CFE_SB_IsValidMsgId(t));
    S("\n");
    Dump("midfinal", &msg);
  }
  // --- cfe_msg_sechdr_fc.c -------------------------------------------------------------
  
  {
    CFE_MSG_CommandHeader cmd;
    U16 fc;
    I32 rc32;
    U8 *cp = &cmd;
    for (i = 0; i < sizeof(CFE_MSG_CommandHeader); i++)
      cp[i] = 0;
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
    CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, TRUE);
    Rc("setfc   ", CFE_MSG_SetFcnCode(&cmd.Msg, 0x12));
    rc32 = CFE_MSG_GetFcnCode(&cmd.Msg, &fc);
    Rcv("getfc   ", rc32, "f", fc);
    S("cmdhdr ");
    D(cmd.Msg.CCSDS.Pri.StreamId[0]);
    S(" ");
    D(cmd.Msg.CCSDS.Pri.StreamId[1]);
    S(" ");
    D(cmd.Msg.CCSDS.Pri.Sequence[0]);
    S(" ");
    D(cmd.Msg.CCSDS.Pri.Sequence[1]);
    S(" ");
    D(cmd.Msg.CCSDS.Pri.Length[0]);
    S(" ");
    D(cmd.Msg.CCSDS.Pri.Length[1]);
    S(" ");
    D(cmd.Sec.FunctionCode);
    S(" ");
    D(cmd.Sec.Checksum);
    S("\n");
    Rc("fcbig   ", CFE_MSG_SetFcnCode(&cmd.Msg, 0x80));
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Tlm);
    fc = 0x55;
    rc32 = CFE_MSG_GetFcnCode(&cmd.Msg, &fc);
    Rcv("fctlm   ", rc32, "f", fc);
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
    CFE_MSG_SetHeaderVersion(&cmd.Msg, 1);
    Rc("fcver   ", CFE_MSG_SetFcnCode(&cmd.Msg, 0x7F));
    Rc("fcnull  ", CFE_MSG_GetFcnCode(NULL, &fc));
  }
  // --- header sizes -------------------------------------------------------------------
  // A property, not a function under test: if HolyC laid a class out differently from C the
  // transcripts would diverge somewhere far from the cause. Pin it where the cause would be.
  S("sizes ");
  D(sizeof(CFE_MSG_Message));
  S(" ");
  D(sizeof(CFE_MSG_CommandHeader));
  S(" ");
  D(sizeof(CFE_MSG_TelemetryHeader));
  S("\n");
  // --- cfe_msg_sechdr_time.c ----------------------------------------------------------
  
  {
    CFE_MSG_TelemetryHeader tlm;
    CFE_TIME_SysTime t;
    U8 *q = &tlm;
    for (i = 0; i < sizeof(CFE_MSG_TelemetryHeader); i++)
      q[i] = 0;
    // POISON THE TRAILING BYTES -- see the C oracle for why. Briefly: Spare[] follows Time[],
    // so an over-read past Time[5] lands in zeros and comes out right by accident. The first
    // draft of this translation had that bug and this line is what would have caught it.
    tlm.Spare[0] = 0xEE;
    tlm.Spare[1] = 0xEE;
    tlm.Spare[2] = 0xEE;
    tlm.Spare[3] = 0xEE;
    CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Tlm);
    CFE_MSG_SetHasSecondaryHeader(&tlm.Msg, TRUE);
    t.Seconds = 0x12345678;
    t.Subseconds = 0x9ABCDEF0;
    rc32 = CFE_MSG_SetMsgTime(&tlm.Msg, t);
    Rc("settime ", rc32);
    S("timebytes ");
    D(tlm.Sec.Time[0]);
    S(" ");
    D(tlm.Sec.Time[1]);
    S(" ");
    D(tlm.Sec.Time[2]);
    S(" ");
    D(tlm.Sec.Time[3]);
    S(" ");
    D(tlm.Sec.Time[4]);
    S(" ");
    D(tlm.Sec.Time[5]);
    S("\n");
    // Lossy by construction: six header bytes hold a 32/16 split, so the low 16 bits of
    // Subseconds have nowhere to go. 0x9ABC0000 coming back is correct.
    t.Seconds = 0;
    t.Subseconds = 0;
    rc32 = CFE_MSG_GetMsgTime(&tlm.Msg, &t);
    Rcv2("gettime ", rc32, "s", t.Seconds, "u", t.Subseconds);
    CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Cmd);
    t.Seconds = 0x11111111;
    t.Subseconds = 0x22222222;
    rc32 = CFE_MSG_GetMsgTime(&tlm.Msg, &t);
    Rcv2("timecmd ", rc32, "s", t.Seconds, "u", t.Subseconds);
    rc32 = CFE_MSG_SetMsgTime(&tlm.Msg, t);
    Rc("timeset2", rc32);
    rc32 = CFE_MSG_GetMsgTime(NULL, &t);
    Rc("timenull", rc32);
    S("timespare ");
    D(tlm.Spare[0]);
    S(" ");
    D(tlm.Spare[1]);
    S(" ");
    D(tlm.Spare[2]);
    S(" ");
    D(tlm.Spare[3]);
    S("\n");
  }
  // --- cfe_msg_sechdr_checksum.c ------------------------------------------------------
  
  {
    CFE_MSG_CommandHeader cmd;
    Bool valid;
    U8 *q = &cmd;
    for (i = 0; i < sizeof(CFE_MSG_CommandHeader); i++)
      q[i] = 0;
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
    CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, TRUE);
    CFE_MSG_SetSize(&cmd.Msg, sizeof(CFE_MSG_CommandHeader));
    CFE_MSG_SetFcnCode(&cmd.Msg, 0x12);
    rc32 = CFE_MSG_GenerateChecksum(&cmd.Msg);
    Rcv("gencsum ", rc32, "c", cmd.Sec.Checksum);
    valid = FALSE;
    rc32 = CFE_MSG_ValidateChecksum(&cmd.Msg, &valid);
    Rcv("valcsum ", rc32, "v", valid);
    // Corrupt a byte the checksum covered. A gate that only ever sees the passing case would
    // not notice a checksum that always answers "valid".
    cmd.Sec.FunctionCode = 0x13;
    valid = TRUE;
    rc32 = CFE_MSG_ValidateChecksum(&cmd.Msg, &valid);
    Rcv("badcsum ", rc32, "v", valid);
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Tlm);
    rc32 = CFE_MSG_GenerateChecksum(&cmd.Msg);
    Rc("csumtlm ", rc32);
    rc32 = CFE_MSG_ValidateChecksum(NULL, &valid);
    Rc("csumnull", rc32);
  }
  // --- cfe_msg_init.c, cfe_msg_initdefaulthdr_pri.c, cfe_msg_msgid_shared.c -----------
  
  {
    U8 buf[32];
    CFE_MSG_Message *mp = buf(CFE_MSG_Message *);
    I64 mtype;
    for (i = 0; i < 32; i++)
      buf[i] = 0xEE;
    rc32 = CFE_MSG_Init(mp, CFE_SB_ValueToMsgId(0x1801), 32);
    Rc("init    ", rc32);
    Dump("afterinit", mp);
    // Init clears the WHOLE size it was given, not just the header -- byte 31 proves it.
    S("initclr  b8=");
    D(buf[8]);
    S(" b31=");
    D(buf[31]);
    S("\n");
    rc32 = CFE_MSG_GetSegmentationFlag(mp, &segf);
    Rcv("initseg ", rc32, "g", segf);
    // An invalid msgid is explicitly ALLOWED here -- the real one may be filled in later -- so
    // this succeeds where CFE_MSG_SetMsgId on the same value refuses.
    rc32 = CFE_MSG_Init(mp, CFE_SB_InvalidMsgId, 32);
    Rc("initinv ", rc32);
    Dump("afterinv", mp);
    // But a bad SIZE is refused, because the size always has to be real.
    rc32 = CFE_MSG_Init(mp, CFE_SB_ValueToMsgId(0x1801), 0);
    Rc("initsz  ", rc32);
    rc32 = CFE_MSG_Init(NULL, CFE_SB_ValueToMsgId(0x1801), 32);
    Rc("initnull", rc32);
    // GetTypeFromMsgId decodes via a throwaway message rather than by masking a bit.
    rc32 = CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x1801), &mtype);
    Rcv("typecmd ", rc32, "t", mtype);
    rc32 = CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x0801), &mtype);
    Rcv("typetlm ", rc32, "t", mtype);
    rc32 = CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x2000), &mtype);
    Rc("typebad ", rc32);
    rc32 = CFE_MSG_GetTypeFromMsgId(CFE_SB_ValueToMsgId(0x1801), NULL);
    Rc("typenull", rc32);
  }
  // --- cfe_msg_integrity.c ------------------------------------------------------------
  
  {
    CFE_MSG_TelemetryHeader tlm;
    CFE_MSG_CommandHeader cmd;
    Bool acc;
    U8 *q = &tlm;
    U8 *r = &cmd;
    // OriginationAction stamps a time AND a checksum and ignores both return values, because
    // exactly one can apply to any given packet. Telemetry comes back timestamped with the
    // checksum call having failed harmlessly; a command the other way round.
    for (i = 0; i < sizeof(CFE_MSG_TelemetryHeader); i++)
      q[i] = 0;
    CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Tlm);
    CFE_MSG_SetHasSecondaryHeader(&tlm.Msg, TRUE);
    CFE_MSG_SetSize(&tlm.Msg, sizeof(CFE_MSG_TelemetryHeader));
    acc = FALSE;
    rc32 = CFE_MSG_OriginationAction(&tlm.Msg, sizeof(CFE_MSG_TelemetryHeader), &acc);
    Rcv("origtlm ", rc32, "a", acc);
    S("origtime ");
    D(tlm.Sec.Time[0]);
    S(" ");
    D(tlm.Sec.Time[1]);
    S(" ");
    D(tlm.Sec.Time[2]);
    S(" ");
    D(tlm.Sec.Time[3]);
    S(" ");
    D(tlm.Sec.Time[4]);
    S(" ");
    D(tlm.Sec.Time[5]);
    S("\n");
    for (i = 0; i < sizeof(CFE_MSG_CommandHeader); i++)
      r[i] = 0;
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
    CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, TRUE);
    CFE_MSG_SetSize(&cmd.Msg, sizeof(CFE_MSG_CommandHeader));
    acc = FALSE;
    rc32 = CFE_MSG_OriginationAction(&cmd.Msg, sizeof(CFE_MSG_CommandHeader), &acc);
    Rcv("origcmd ", rc32, "a", acc);
    S("origcsum f=");
    D(cmd.Sec.FunctionCode);
    S(" c=");
    D(cmd.Sec.Checksum);
    S("\n");
    acc = FALSE;
    rc32 = CFE_MSG_VerificationAction(&cmd.Msg, sizeof(CFE_MSG_CommandHeader), &acc);
    Rcv("verify  ", rc32, "a", acc);
    rc32 = CFE_MSG_OriginationAction(NULL, 8, &acc);
    Rc("orignull", rc32);
    rc32 = CFE_MSG_VerificationAction(&cmd.Msg, 8, NULL);
    Rc("verinull", rc32);
  }
  // --- cfe_resourceid_api.c -----------------------------------------------------------
  
  {
    U32 rid;
    U32 idx;
    U32 base = CFE_RESOURCEID_MAKE_BASE(1);
    // The C has a CompileTimeAssert that MAX is one less than a power of two, because the same
    // constant is a numeric limit AND a bit mask. HolyC has no static assert, so the property
    // is checked here rather than being silently dropped in translation.
    S("ridmask ");
    D (((CFE_RESOURCEID_MAX + 1) & CFE_RESOURCEID_MAX) == 0);
    S("\n");
    S("ridbase ");
    D(base);
    S(" ");
    D(CFE_RESOURCEID_MAX);
    S("\n");
    rid = CFE_ResourceId_FromInteger(base + 5);
    S("ridsplit b=");
    D(CFE_ResourceId_GetBase(rid));
    S(" s=");
    D(CFE_ResourceId_GetSerial(rid));
    S(" i=");
    D(CFE_ResourceId_ToInteger(rid));
    S("\n");
    S("riddef d=");
    D(CFE_ResourceId_IsDefined(rid));
    S(" u=");
    D(CFE_ResourceId_IsDefined(CFE_RESOURCEID_UNDEFINED));
    S("\n");
    idx = 0xAAAA;
    rc32 = CFE_ResourceId_ToIndex(rid, base, 8, &idx);
    Rcv("ridx    ", rc32, "i", idx);
    // Id below BaseValue. ToInteger yields 64 bits, so the subtraction is 64-bit and the result
    // only lands back in range because it is stored into a U32 first.
    idx = 0xAAAA;
    rc32 = CFE_ResourceId_ToIndex(CFE_ResourceId_FromInteger(5), base, 8, &idx);
    Rcv("ridxlow ", rc32, "i", idx);
    // THE DISCRIMINATING CASE. 5 - 0xFFFFFFFF is 0xFFFFFFFF00000006 in 64 bits, far above
    // CFE_RESOURCEID_MAX and would be REJECTED -- but truncated to U32 it is 6, which is
    // accepted and indexes slot 6. Keep 64-bit width here and this line returns an error where
    // NASA's returns success. No other input in this transcript tells the two apart.
    idx = 0xAAAA;
    rc32 = CFE_ResourceId_ToIndex(CFE_ResourceId_FromInteger(5), 0xFFFFFFFF, 8, &idx);
    Rcv("ridxwrap", rc32, "i", idx);
    idx = 0xAAAA;
    rc32 = CFE_ResourceId_ToIndex(rid, base, 0, &idx);
    Rcv("ridxzero", rc32, "i", idx);
    rc32 = CFE_ResourceId_ToIndex(rid, base, 8, NULL);
    Rc("ridxnull", rc32);
    // FindNext walks the do-while: increment first, then test. Serials 6 and 7 are taken, so
    // starting at 5 must land on 8.
    S("ridnext  ");
    D(CFE_ResourceId_ToInteger(CFE_ResourceId_FindNext(rid, 8, &rid_in_use)));
    S("\n");
    // Everything taken: RemainingCount reaches zero, the increment yields UNDEFINED, and the
    // IsDefined check breaks the loop rather than spinning forever.
    S("ridfull  ");
    D(CFE_ResourceId_ToInteger(CFE_ResourceId_FindNext(rid, 8, &rid_all_in_use)));
    S("\n");
    // A serial at the top of its range wraps modulo the table size, not to zero.
    S("ridwrap  ");
    D(CFE_ResourceId_ToInteger(CFE_ResourceId_FindNext(CFE_ResourceId_FromInteger(base + CFE_RESOURCEID_MAX - 1), 4, &rid_in_use)));
    S("\n");
    S("ridnull  ");
    D(CFE_ResourceId_ToInteger(CFE_ResourceId_FindNextEx(rid, NULL, NULL, &rid_in_use)));
    S(" ");
    D(CFE_ResourceId_ToInteger(CFE_ResourceId_FindNextEx(rid, NULL, NULL, NULL)));
    S("\n");
    S("ridobj ");
    S(CFE_RESOURCEID_ModuleEntry.Name);
    S(" ");
    D(CFE_RESOURCEID_ModuleEntry.StackSize);
    S("\n");
  }
  // --- cfe_sb_msg_id_util.c and cfe_sb_util.c ------------------------------------------
  
  {
    CFE_MSG_CommandHeader cmd;
    CFE_MSG_TelemetryHeader tlm;
    U8 name[12];
    U8 shortbuf[4];
    U8 *qc = &cmd;
    U8 *qt = &tlm;
    I32 n;
    for (i = 0; i < sizeof(CFE_MSG_CommandHeader); i++)
      qc[i] = 0;
    for (i = 0; i < sizeof(CFE_MSG_TelemetryHeader); i++)
      qt[i] = 0;
    // MsgHdrSize answers from the packet's own two class bits, which is how a bus can ask where
    // a payload starts without being told what kind of message it holds.
    S("hdrsz_none ");
    D(CFE_SB_MsgHdrSize(&cmd.Msg));
    S("\n");
    CFE_MSG_SetHasSecondaryHeader(&cmd.Msg, TRUE);
    CFE_MSG_SetType(&cmd.Msg, CFE_MSG_Type_Cmd);
    CFE_MSG_SetHasSecondaryHeader(&tlm.Msg, TRUE);
    CFE_MSG_SetType(&tlm.Msg, CFE_MSG_Type_Tlm);
    S("hdrsz ");
    D(CFE_SB_MsgHdrSize(&cmd.Msg));
    S(" ");
    D(CFE_SB_MsgHdrSize(&tlm.Msg));
    S(" ");
    D(CFE_SB_MsgHdrSize(NULL));
    S("\n");
    CFE_MSG_SetSize(&tlm.Msg, sizeof(CFE_MSG_TelemetryHeader) + 8);
    S("userdata off=");
    D(CFE_SB_GetUserData(&tlm.Msg) - qt);
    S(" len=");
    D(CFE_SB_GetUserDataLength(&tlm.Msg));
    S("\n");
    CFE_SB_SetUserDataLength(&tlm.Msg, 20);
    S("setuserlen len=");
    D(CFE_SB_GetUserDataLength(&tlm.Msg));
    S("\n");
    // Over the mission maximum: refused, and the size is left alone.
    CFE_SB_SetUserDataLength(&tlm.Msg, 100000);
    S("setuserbig len=");
    D(CFE_SB_GetUserDataLength(&tlm.Msg));
    S("\n");
    // HOISTED, not inlined into the prints. GetUserData(NULL) logs through the ES stub, and C
    // evaluates a printf's arguments before printf emits anything -- so the C transcript has
    // "syslog" BEFORE this line and an inline HolyC version puts it in the middle of it.
    
    {
      Bool nulldata;
      I64 nulllen;
      nulldata = CFE_SB_GetUserData(NULL) == NULL;
      nulllen = CFE_SB_GetUserDataLength(NULL);
      S("userdatanull ");
      D(nulldata);
      S(" ");
      D(nulllen);
      S("\n");
    }
    CFE_SB_TimeStampMsg(&tlm.Msg);
    S("stamped ");
    D(tlm.Sec.Time[0]);
    S(" ");
    D(tlm.Sec.Time[1]);
    S(" ");
    D(tlm.Sec.Time[2]);
    S(" ");
    D(tlm.Sec.Time[3]);
    S(" ");
    D(tlm.Sec.Time[4]);
    S(" ");
    D(tlm.Sec.Time[5]);
    S("\n");
    // MessageStringSet ZERO-FILLS the remainder rather than merely terminating, so a short name
    // completely erases a longer one. MessageStringGet reserves one byte for the NUL and falls
    // back to the default when the source is empty.
    for (i = 0; i < 12; i++)
      name[i] = 'Z';
    n = CFE_SB_MessageStringSet(name, "ABCDE", 12, 5);
    S("strset n=");
    D(n);
    S(" b0=");
    D(name[0]);
    S(" b5=");
    D(name[5]);
    S(" b11=");
    D(name[11]);
    S("\n");
    n = CFE_SB_MessageStringGet(shortbuf, name, NULL, 4, 12);
    S("strget n=");
    D(n);
    S(" s=");
    S(shortbuf);
    S("\n");
    n = CFE_SB_MessageStringGet(shortbuf, "", "dflt", 4, 0);
    S("strdflt n=");
    D(n);
    S(" s=");
    S(shortbuf);
    S("\n");
    S("strbad ");
    D(CFE_SB_MessageStringGet(NULL, "x", NULL, 4, 1));
    S(" ");
    D(CFE_SB_MessageStringSet(NULL, "x", 4, 1));
    S("\n");
    // THE TOPIC-ID MAPPING, and the asymmetry in it -- see cfe_sb_msgid.HC. For instance 0 the
    // COMMAND function returns the GLOBAL TELEMETRY value, 0x0865 rather than 0x1865 for topic
    // 5, so the type bit of the returned stream id says telemetry. Pinned deliberately.
    Hx2("topic_cmd  i0=", CFE_SB_CmdTopicIdToMsgId(5, 0), " i1=", CFE_SB_CmdTopicIdToMsgId(5, 1));
    Hx2("topic_tlm  i0=", CFE_SB_TlmTopicIdToMsgId(5, 0), " i1=", CFE_SB_TlmTopicIdToMsgId(5, 1));
    Hx2("topic_glob c=", CFE_SB_GlobalCmdTopicIdToMsgId(5), " t=", CFE_SB_GlobalTlmTopicIdToMsgId(5));
    Hx2("topic_locl c=", CFE_SB_LocalCmdTopicIdToMsgId(5), " t=", CFE_SB_LocalTlmTopicIdToMsgId(5));
  }
  // --- cfe_sbr_map_hash.c and cfe_sbr_route_unsorted.c --------------------------------
  
  {
    CFE_SBR_RouteId rid, rid2;
    CFE_SBR_Throttle thr;
    U32 coll = 0xBEEF;
    I64 k;
    U16 ids[6];
    // The C has a #error if the map size is not a power of two, because the size doubles as the
    // wrap mask. HolyC's preprocessor has no #error, so the property is checked here rather
    // than quietly dropped in translation.
    S("sbr_pow2 ");
    D ((1024 & (1024 - 1)) == 0);
    S("\n");
    // THE HASH IS 32-BIT ARITHMETIC: each step multiplies by 0x45d9f3b and overflows, and the
    // wrap IS the algorithm. A spread on purpose -- 0x0001 hashes the same with and without the
    // wrap, so a transcript testing only that would be blind to a 64-bit translation.
    ids[0] = 0x0001;
    ids[1] = 0x0801;
    ids[2] = 0x1801;
    ids[3] = 0x0865;
    ids[4] = 0x1FFF;
    ids[5] = 0x0102;
    S("sbr_hash");
    for (k = 0; k < 6; k++) {
      S(" ");
      D(CFE_SBR_MsgIdHash(CFE_SB_ValueToMsgId(ids[k])));
    }
    S("\n");
    CFE_SBR_Init;
    rid = CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(0x0801));
    S("sbr_empty v=");
    D(CFE_SBR_IsValidRouteId(rid));
    S("\n");
    rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(0x0801), &coll);
    S("sbr_add   v=");
    D(CFE_SBR_IsValidRouteId(rid));
    S(" idx=");
    D(CFE_SBR_RouteIdToValue(rid));
    S(" coll=");
    D(coll);
    S("\n");
    rid2 = CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(0x0801));
    S("sbr_get   idx=");
    D(CFE_SBR_RouteIdToValue(rid2));
    S(" mid=");
    D(CFE_SB_MsgIdToValue(CFE_SBR_GetMsgId(rid2)));
    S("\n");
    rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(0x1801), &coll);
    S("sbr_add2  idx=");
    D(CFE_SBR_RouteIdToValue(rid));
    S(" coll=");
    D(coll);
    S("\n");
    coll = 0xBEEF;
    rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(0), &coll);
    S("sbr_addbad v=");
    D(CFE_SBR_IsValidRouteId(rid));
    S(" coll=");
    D(coll);
    S("\n");
    CFE_SBR_SetDestListHeadPtr(rid2, 0x1234);
    S("sbr_dest ");
    D(CFE_SBR_GetDestListHeadPtr(rid2) == 0x1234);
    S(" ");
    D(CFE_SBR_GetDestListHeadPtr(CFE_SBR_InvalidRouteId) == NULL);
    S("\n");
    for (k = 0; k < 3; k++)
      CFE_SBR_IncrementSequenceCounter(rid2);
    S("sbr_seq ");
    D(CFE_SBR_GetSequenceCounter(rid2));
    S("\n");
    S("sbr_seqbad ");
    D(CFE_SBR_GetSequenceCounter(CFE_SBR_InvalidRouteId));
    S("\n");
    sbr_visits = 0;
    CFE_SBR_ForEachRouteId(&sbr_count_cb, NULL, NULL);
    S("sbr_each ");
    D(sbr_visits);
    S("\n");
    sbr_visits = 0;
    thr.StartIndex = 0;
    thr.MaxLoop = 1;
    thr.NextIndex = 0xFFFF;
    CFE_SBR_ForEachRouteId(&sbr_count_cb, NULL, &thr);
    S("sbr_thr1 n=");
    D(sbr_visits);
    S(" next=");
    D(thr.NextIndex);
    S("\n");
    sbr_visits = 0;
    thr.StartIndex = 0;
    thr.MaxLoop = 99;
    thr.NextIndex = 0xFFFF;
    CFE_SBR_ForEachRouteId(&sbr_count_cb, NULL, &thr);
    S("sbr_thr2 n=");
    D(sbr_visits);
    S(" next=");
    D(thr.NextIndex);
    S("\n");
    S("sbr_obj ");
    S(CFE_SBR_ModuleEntry.Name);
    S("\n");
  }
  // --- cfe_config_{lookup,get,set,eds_disabled}.c -------------------------------------
  
  {
    U32 cid;
    CFE_Config_ArrayValue av, avget;
    U8 vbuf[64];
    // Init is not translated (it needs the build-generated GLOBAL_CONFIGDATA), so the one thing
    // it would have set is set here on both sides. Everything below is the real API driving the
    // real table.
    CFE_Config_Global.UnknownString = "UNKNOWN";
    cid = CFE_Config_GetIdByName("CORE_VERSION_MAJOR");
    S("cfg_id 0x");
    Hx6(cid);
    S(" ");
    S(CFE_Config_GetName(cid));
    S("\n");
    S("cfg_nosuch ");
    D(CFE_Config_GetIdByName("NOT_A_KEY"));
    S(" ");
    D(CFE_Config_GetIdByName(NULL));
    S("\n");
    // An id below the base underflows the unsigned offset and is refused by the same bounds
    // check that catches one above the top -- the CFE_ResourceId_ToIndex trick again.
    S("cfg_oob ");
    S(CFE_Config_GetName(CFE_ResourceId_FromInteger(1)));
    S("\n");
    CFE_Config_SetValue(cid, 7);
    S("cfg_val ");
    D(CFE_Config_GetValue(cid));
    S("\n");
    S("cfg_wrongtype ");
    D(CFE_Config_GetString(cid) == CFE_Config_Global.UnknownString);
    S(" ");
    D(CFE_Config_GetObjPointer(cid) == NULL);
    S("\n");
    CFE_Config_SetString(CFE_Config_GetIdByName("MISSION_NAME"), "benchtop");
    S("cfg_str ");
    S(CFE_Config_GetString(CFE_Config_GetIdByName("MISSION_NAME")));
    S("\n");
    S("cfg_strptr ");
    D(CFE_Config_GetObjPointer(CFE_Config_GetIdByName("MISSION_NAME")) != NULL);
    S("\n");
    CFG_ARR[0] = 11;
    CFG_ARR[1] = 22;
    CFG_ARR[2] = 33;
    av.NumElements = 3;
    // NOT ARR(U8 *). A HolyC cast on an lvalue relabels the storage, so that form re-reads
    // eight bytes AT the array instead of taking its address. An array name is already a
    // pointer here, so it needs no cast at all -- the same trap that cost this port a
    // translated timestamp earlier today.
    av.ElementPtr = CFG_ARR;
    CFE_Config_SetArrayValue(CFE_Config_GetIdByName("TA_AFFINITY_TABLE"), &av);
    // Out-parameter, not a return value -- see cfe_config.HC for why that one signature
    // deviates. The printed numbers are the same, which is what the transcript compares.
    CFE_Config_GetArrayValue(CFE_Config_GetIdByName("TA_AFFINITY_TABLE"), &avget);
    S("cfg_arr n=");
    D(avget.NumElements);
    S(" first=");
    D (*(avget.ElementPtr(U32 *)));
    S("\n");
    CFE_Config_GetArrayValue(cid, &avget);
    S("cfg_arrbad n=");
    D(avget.NumElements);
    S(" p=");
    D(avget.ElementPtr == NULL);
    S("\n");
    cfg_visits = 0;
    CFE_Config_IterateAll(NULL, &cfg_count_cb);
    S("cfg_iter ");
    D(cfg_visits);
    S(" of ");
    D(CFE_ConfigIdOffset_MAX);
    S("\n");
    // The version-string helpers, the only formatted output in the module. Mission revision 0
    // is an official release, 0xFF a development build, anything else a user customisation --
    // three different strings out of one uint8.
    CFE_Config_GetMissionRevString(vbuf, sizeof(vbuf), 0, "v7.0.0");
    S("cfg_rev0 ");
    S(vbuf);
    S("\n");
    CFE_Config_GetMissionRevString(vbuf, sizeof(vbuf), 0xFF, "v7.0.0");
    S("cfg_revff ");
    S(vbuf);
    S("\n");
    CFE_Config_GetMissionRevString(vbuf, sizeof(vbuf), 42, "v7.0.0");
    S("cfg_rev42 ");
    S(vbuf);
    S("\n");
    // Truncation, which is snprintf's contract and therefore this translation's.
    CFE_Config_GetMissionRevString(vbuf, 10, 42, "v7.0.0");
    S("cfg_trunc [");
    S(vbuf);
    S("]\n");
    CFE_Config_GetVersionString(vbuf, sizeof(vbuf), "cFE", "1.2.3", "Draco", "v7.0.0");
    S("cfg_ver ");
    S(vbuf);
    S("\n");
    S("cfg_eds ");
    S(CFE_Config_EdsState("cFE"));
    S("\n");
  }
  // --- cfe_msg_objtab.c ---------------------------------------------------------------
  // One registration entry, no task. ES walks the collected table at every lifecycle phase, so
  // a port that skips these has modules that exist and never start.
  S("objtab ");
  S(CFE_MSG_ModuleEntry.Name);
  S(" ");
  D(CFE_MSG_ModuleEntry.EarlyInit == NULL);
  S(" ");
  D(CFE_MSG_ModuleEntry.TaskMain == NULL);
  S(" ");
  D(CFE_MSG_ModuleEntry.AppCleanupCb == NULL);
  S(" ");
  D(CFE_MSG_ModuleEntry.Priority);
  S(" ");
  D(CFE_MSG_ModuleEntry.StackSize);
  S("\n");
  // cFE's target configuration. The C half is designated initialisers, which are in place
  // before main runs; HolyC has no initialised aggregates at file scope, so the same values are
  // written by a function that has to be CALLED. fs is the first module to read
  // GLOBAL_CFE_CONFIGDATA, which is why nothing missed this until now -- and the symptom was
  // five mount points reading (null) rather than any kind of error.
  CFE_TargetConfigInit();
  // --- cfe_fs: layout ------------------------------------------------------------------
  // sizeof and the offsets of every translated class, on both sides. check_padding.py already
  // compares these against the host C compiler, but that is a MODEL on the HolyC side; this
  // puts the really compiled layout under the byte-identical transcript, which is stronger.
  //
  // CFE_FS_ParseContext_t is deliberately absent: it lives inside cfe_fs_api.c, so the C driver
  // cannot see it and a hand-written literal there would compare nothing. check_padding.py
  // lifts that typedef out of the .c and measures it for real.
  
  {
    CFE_FS_FileWriteMetaData_t lm;
    CFE_FS_CurrentFileState_t lc;
    S("fs_lay hdr=");
    D(sizeof(CFE_FS_Header_t));
    S(" meta=");
    D(sizeof(CFE_FS_FileWriteMetaData_t));
    S(" ent=");
    D(sizeof(CFE_FS_BackgroundFileDumpEntry_t));
    S(" cur=");
    D(sizeof(CFE_FS_CurrentFileState_t));
    S(" dump=");
    D(sizeof(CFE_FS_BackgroundFileDumpState_t));
    S(" glob=");
    D(sizeof(CFE_FS_Global_t));
    S("\n");
    S("fs_off pend=");
    D ((U8 *) & lm.IsPending - (U8 *) & lm);
    S(" name=");
    D ((U8 *) & lm.FileName - (U8 *) & lm);
    S(" sub=");
    D ((U8 *) & lm.FileSubType - (U8 *) & lm);
    S(" desc=");
    D ((U8 *) & lm.Description - (U8 *) & lm);
    S(" get=");
    D ((U8 *) & lm.GetData - (U8 *) & lm);
    S(" ev=");
    D ((U8 *) & lm.OnEvent - (U8 *) & lm);
    S("\n");
    S("fs_off2 mut=");
    D ((U8 *) & CFE_FS_Global.SharedDataMutexId - (U8 *) & CFE_FS_Global);
    S(" fdump=");
    D ((U8 *) & CFE_FS_Global.FileDump - (U8 *) & CFE_FS_Global);
    S(" req=");
    D ((U8 *) & CFE_FS_Global.FileDump.RequestCount - (U8 *) & CFE_FS_Global.FileDump);
    S(" comp=");
    D ((U8 *) & CFE_FS_Global.FileDump.CompleteCount - (U8 *) & CFE_FS_Global.FileDump);
    S(" entries=");
    D ((U8 *) & CFE_FS_Global.FileDump.Entries - (U8 *) & CFE_FS_Global.FileDump);
    S(" curr=");
    D ((U8 *) & CFE_FS_Global.FileDump.Current - (U8 *) & CFE_FS_Global.FileDump);
    S(" fd=");
    D ((U8 *) & lc.Fd - (U8 *) & lc);
    S(" cred=");
    D ((U8 *) & lc.Credit - (U8 *) & lc);
    S(" recn=");
    D ((U8 *) & lc.RecordNum - (U8 *) & lc);
    S(" fsz=");
    D ((U8 *) & lc.FileSize - (U8 *) & lc);
    S("\n");
  }
  // --- cfe_fs_priv.c ------------------------------------------------------------------
  
  {
    I32 irc = CFE_FS_EarlyInit();
    // logs on failure; hoisted for the same reason as the rest
    S("fs_init rc=");
    D(irc);
  }
  S(" create=");
  D(fs_mut_create);
  S(" mut=");
  D(CFE_FS_Global.SharedDataMutexId);
  S("\n");
  CFE_FS_LockSharedData("drv");
  CFE_FS_UnlockSharedData("drv");
  S("fs_lock take=");
  D(fs_mut_take);
  S(" give=");
  D(fs_mut_give);
  S("\n");
  // the three failure paths, each of which logs: the creation, the take and the give
  
  {
    I32 nrc;
    fs_mut_create_rc = -11;
    nrc = CFE_FS_EarlyInit();
    S("fs_init_nomutex rc=");
    D(nrc);
    S("\n");
    fs_mut_create_rc = OS_SUCCESS;
    nrc = CFE_FS_EarlyInit();
    S("fs_init_again rc=");
    D(nrc);
    S("\n");
    fs_mut_take_rc = -12;
    CFE_FS_LockSharedData("take_fails");
    S("fs_lock_takefail done\n");
    fs_mut_take_rc = OS_SUCCESS;
    fs_mut_give_rc = -13;
    CFE_FS_UnlockSharedData("give_fails");
    S("fs_lock_givefail done\n");
    fs_mut_give_rc = OS_SUCCESS;
  }
  // --- cfe_fs_api.c: the default locations -------------------------------------------
  // Every category, including the two that have no mount point and the three that have no
  // extension -- those return NULL, and a translation that returned "" instead would pass a
  // test that only looked at the five real ones.
  
  {
    I64 cat;
    for (cat = 0; cat <= CFE_FS_FileCategory_MAX; cat++) {
      S("fs_cat ");
      D(cat);
      S(" mp=[");
      Sn(CFE_FS_GetDefaultMountPoint(cat));
      S("] ex=[");
      Sn(CFE_FS_GetDefaultExtension(cat));
      S("]\n");
    }
  }
  // --- the byte swappers --------------------------------------------------------------
  
  {
    U32 u = 0x11223344;
    CFE_FS_Header_t h;
    CFE_FS_ByteSwapUint32(&u);
    S("fs_swap32 ");
    Hx8(u);
    S("\n");
    MemSet(&h, 0, sizeof(CFE_FS_Header_t));
    h.ContentType = 0x01020304;
    h.SubType = 0x05060708;
    h.Length = 0x090a0b0c;
    h.SpacecraftID = 0x0d0e0f10;
    h.ProcessorID = 0x11121314;
    h.ApplicationID = 0x15161718;
    h.TimeSeconds = 0x191a1b1c;
    h.TimeSubSeconds = 0x1d1e1f20;
    CFE_FS_ByteSwapCFEHeader(&h);
    fs_hdr("fs_swaphdr", &h);
    CFE_FS_ByteSwapCFEHeader(&h);
    fs_hdr("fs_swapback", &h);
  }
  // --- InitHeader / WriteHeader / ReadHeader / SetTimestamp --------------------------
  
  {
    CFE_FS_Header_t h;
    CFE_FS_Header_t rb;
    I32 rc;
    CFE_TIME_SysTime ts;
    CFE_FS_InitHeader(NULL, "x", 1);
    // both NULL paths log and return
    CFE_FS_InitHeader(&h, NULL, 1);
    // A description LONGER than the field, so strncpy's no-terminator edge is in the
    // transcript: 31 chars plus the NUL the prior MemSet left.
    CFE_FS_InitHeader(&h, "0123456789abcdefghijklmnopqrstuvwxyz", CFE_FS_SubType_ES_SYSLOG);
    fs_hdr("fs_inithdr", &h);
    S("fs_wrhdr_null rc=");
    D(CFE_FS_WriteHeader(7, NULL));
    S("\n");
    S("fs_rdhdr_null rc=");
    D(CFE_FS_ReadHeader(NULL, 7));
    S("\n");
    fs_wr_left = -1;
    fs_fd = 7;
    fs_len = 0;
    fs_pos = 0;
    rc = CFE_FS_WriteHeader(7, &h);
    S("fs_wrhdr rc=");
    D(rc);
    S(" len=");
    D(fs_len);
    S("\n");
    // The header on DISK is big endian; the caller's copy is restored to native.
    fs_dump("fs_bytes", 32);
    fs_hdr("fs_after", &h);
    rc = CFE_FS_ReadHeader(&rb, 7);
    S("fs_rdhdr rc=");
    D(rc);
    S("\n");
    fs_hdr("fs_readback", &rb);
    // A short read: truncate the file so OS_read cannot deliver 64 bytes.
    fs_len = 20;
    S("fs_rdhdr_short rc=");
    D(CFE_FS_ReadHeader(&rb, 7));
    S("\n");
    // SetTimestamp seeks to the byte offset of TimeSeconds, which NASA computes from the struct
    // with two char * casts -- without them C scales by sizeof(uint32) and gets 6.
    fs_len = 64;
    fs_pos = 0;
    ts.Seconds = 0x01234567;
    ts.Subseconds = 0x89abcdef;
    rc = CFE_FS_SetTimestamp(7, ts);
    S("fs_setts rc=");
    D(rc);
    S(" pos=");
    D(fs_pos);
    S("\n");
    fs_dump("fs_tsbytes", 32);
    // And the failure path: a write budget of 4 makes it a short write.
    fs_wr_left = 4;
    rc = CFE_FS_SetTimestamp(7, ts);
    // logs, so it must run BEFORE the prefix is printed
    S("fs_setts_short rc=");
    D(rc);
    S("\n");
    fs_wr_left = -1;
  }
  // --- ParseInputFileNameEx ----------------------------------------------------------
  
  {
    U8 o[32];
    S("fs_parse_nullbuf rc=");
    D(CFE_FS_ParseInputFileNameEx(NULL, NULL, 32, 0, "x", "/cf", ".bin"));
    S("\n");
    S("fs_parse_zerosz rc=");
    D(CFE_FS_ParseInputFileNameEx(o, NULL, 0, 0, "x", "/cf", ".bin"));
    S("\n");
    // no input at all: NULL buffer AND NULL default, so the loop never runs
    fs_parse_out("fs_parse_noinput", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, NULL, "/cf", ".bin"));
    // bare name: default path and default extension both supplied
    fs_parse_out("fs_parse_bare", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log", "/cf", ".bin"));
    // name with its own extension: the default extension is not used
    fs_parse_out("fs_parse_ext", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log.txt", "/cf", ".bin"));
    // name with its own path: the default path is not used
    fs_parse_out("fs_parse_path", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/ram/log", "/cf", ".bin"));
    // duplicate separators, which the separator component collapses from both sides
    fs_parse_out("fs_parse_dup", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/ram//sub///log..txt", "/cf", ".bin"));
    // a multi-level path: the pathname component repeats until the LAST separator
    fs_parse_out("fs_parse_deep", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/a/b/c/log.txt", "/cf", ".bin"));
    // no default extension and none in the input: the parse ends early
    fs_parse_out("fs_parse_noext", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log", "/cf", NULL));
    // no default path and none in the input
    fs_parse_out("fs_parse_nopath", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "log", NULL, ".bin"));
    // an EMPTY filename: the status stays INVALID_PATH even though a path was produced
    fs_parse_out("fs_parse_empty", o, CFE_FS_ParseInputFileNameEx(o, NULL, sizeof(o), 0, "/ram/", "/cf", ".bin"));
    // too long for the output buffer: FNAME_TOO_LONG, and the result is still terminated
    fs_parse_out("fs_parse_long", o, CFE_FS_ParseInputFileNameEx(o, NULL, 12, 0, "/ram/averylongfilename.txt", "/cf", ".bin"));
    // the InputBuffer form, which is NOT null terminated: 10 bytes of a longer buffer
    fs_parse_out("fs_parse_buf", o, CFE_FS_ParseInputFileNameEx(o, "/ram/ab.cdEXTRA", sizeof(o), 10, "unused", "/cf", ".bin"));
    // an empty InputBuffer falls back to DefaultInput
    fs_parse_out("fs_parse_bufempty", o, CFE_FS_ParseInputFileNameEx(o, "", sizeof(o), 4, "fallback", "/cf", ".bin"));
    // the category wrapper, for every category
    
    {
      I64 cat;
      for (cat = 0; cat <= CFE_FS_FileCategory_MAX; cat++) {
        I32 rc2 = CFE_FS_ParseInputFileName(o, "nm", sizeof(o), cat);
        S("fs_parsecat ");
        D(cat);
        S(" rc=");
        D(rc2);
        S(" [");
        S(o);
        S("]\n");
      }
    }
  }
  // --- ExtractFilenameFromPath -------------------------------------------------------
  
  {
    U8 o[80];
    I32 rc;
    S("fs_xf_null rc=");
    D(CFE_FS_ExtractFilenameFromPath(NULL, o));
    S("\n");
    S("fs_xf_null2 rc=");
    D(CFE_FS_ExtractFilenameFromPath("/a/b", NULL));
    S("\n");
    o[0] = 0;
    rc = CFE_FS_ExtractFilenameFromPath("/cf/apps/ci_lab.so", o);
    fs_parse_out("fs_xf", o, rc);
    // no separator at all
    o[0] = 0;
    rc = CFE_FS_ExtractFilenameFromPath("bare.txt", o);
    fs_parse_out("fs_xf_bare", o, rc);
    // the ONLY separator is at index 0, so DirMarkIdx == 0 and NASA's test is > 0:
    // "/name" is rejected as INVALID_PATH rather than yielding "name"
    o[0] = 0;
    rc = CFE_FS_ExtractFilenameFromPath("/name", o);
    fs_parse_out("fs_xf_root", o, rc);
    // a trailing separator: an empty filename, which is still CFE_SUCCESS
    o[0] = 0;
    rc = CFE_FS_ExtractFilenameFromPath("/a/b/", o);
    fs_parse_out("fs_xf_trail", o, rc);
    // the tail is OS_MAX_PATH_LEN or longer: FNAME_TOO_LONG
    o[0] = 0;
    rc = CFE_FS_ExtractFilenameFromPath("/x/0123456789012345678901234567890123456789012345678901234567890123", o);
    fs_parse_out("fs_xf_long", o, rc);
  }
  // --- the background file dump queue ------------------------------------------------
  
  {
    CFE_FS_FileWriteMetaData_t m;
    CFE_FS_FileWriteMetaData_t m2;
    I64 i;
    I64 k;
    Bool more1;
    MemSet(&m, 0, sizeof(CFE_FS_FileWriteMetaData_t));
    S("fs_req_null rc=");
    D(CFE_FS_BackgroundFileDumpRequest(NULL));
    S("\n");
    S("fs_pend_null ");
    D(CFE_FS_BackgroundFileDumpIsPending(NULL));
    S("\n");
    // GetData and OnEvent must both be set, and they are checked together
    S("fs_req_nogetdata rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m));
    S("\n");
    m.GetData = &fs_getdata;
    S("fs_req_noonevent rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m));
    S("\n");
    m.OnEvent = &fs_onevent;
    // then a non-empty filename
    S("fs_req_noname rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m));
    S("\n");
    StrNCpy(m.FileName, "/ram/dump.bin", CFE_MISSION_MAX_PATH_LEN - 1);
    StrNCpy(m.Description, "a test dump", CFE_FS_HDR_DESC_MAX_LEN - 1);
    m.FileSubType = CFE_FS_SubType_ES_QUERYALL;
    S("fs_req rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m));
    S(" pend=");
    D(CFE_FS_BackgroundFileDumpIsPending(&m));
    S(" wake=");
    D(fs_wakeups);
    S("\n");
    // a second request for the SAME object is rejected while it is pending
    S("fs_req_again rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m));
    S("\n");
    // run it: open, header, three records with a hole, EOF, complete event
    fs_open_fail = 0;
    fs_wr_left = -1;
    fs_fd = 0;
    fs_len = 0;
    fs_pos = 0;
    fs_events = 0;
    for (i = 0; i < 4; i++) {
      // 8 ms of elapsed time is 80 bytes of credit: the 64-byte header plus two 10-byte
      // records overruns it, so the first call cannot reach EOF and the multi-call path is in
      // the transcript rather than assumed.
      Bool more = CFE_FS_RunBackgroundFileDump(8, NULL);
      S("fs_run");
      D(i);
      S(" more=");
      D(more);
      S(" fd=");
      D(CFE_FS_Global.FileDump.Current.Fd);
      S(" cred=");
      D(CFE_FS_Global.FileDump.Current.Credit);
      S(" rec=");
      D(CFE_FS_Global.FileDump.Current.RecordNum);
      S(" sz=");
      D(CFE_FS_Global.FileDump.Current.FileSize);
      S(" pend=");
      D(CFE_FS_BackgroundFileDumpIsPending(&m));
      S(" comp=");
      D(CFE_FS_Global.FileDump.CompleteCount);
      S("\n");
    }
    fs_dump("fs_filebytes", 32);
    S("fs_events ");
    D(fs_events);
    S("\n");
    // the CREATE failure path
    MemSet(&m2, 0, sizeof(CFE_FS_FileWriteMetaData_t));
    m2.GetData = &fs_getdata;
    m2.OnEvent = &fs_onevent;
    StrNCpy(m2.FileName, "/ram/nope.bin", CFE_MISSION_MAX_PATH_LEN - 1);
    StrNCpy(m2.Description, "create fails", CFE_FS_HDR_DESC_MAX_LEN - 1);
    S("fs_req2 rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m2));
    S("\n");
    fs_open_fail = 1;
    CFE_FS_Global.FileDump.Current.Credit = 0;
    more1 = CFE_FS_RunBackgroundFileDump(1000, NULL);
    // emits an event; hoisted
    S("fs_run_createfail more=");
    D(more1);
    S(" pend=");
    D(CFE_FS_BackgroundFileDumpIsPending(&m2));
    S(" comp=");
    D(CFE_FS_Global.FileDump.CompleteCount);
    S("\n");
    fs_open_fail = 0;
    // the HEADER WRITE failure path: a 4-byte budget makes WriteHeader return 4, not 64
    S("fs_req3 rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m2));
    S("\n");
    fs_wr_left = 4;
    CFE_FS_Global.FileDump.Current.Credit = 0;
    more1 = CFE_FS_RunBackgroundFileDump(1000, NULL);
    // emits an event; hoisted
    S("fs_run_hdrfail more=");
    D(more1);
    S(" pend=");
    D(CFE_FS_BackgroundFileDumpIsPending(&m2));
    S("\n");
    // the RECORD WRITE failure path: the header fits, a record does not
    S("fs_req4 rc=");
    D(CFE_FS_BackgroundFileDumpRequest(&m2));
    S("\n");
    fs_wr_left = 64;
    CFE_FS_Global.FileDump.Current.Credit = 0;
    more1 = CFE_FS_RunBackgroundFileDump(1000, NULL);
    // emits an event; hoisted
    S("fs_run_recfail more=");
    D(more1);
    S(" pend=");
    D(CFE_FS_BackgroundFileDumpIsPending(&m2));
    S("\n");
    fs_wr_left = -1;
    // nothing queued: the lock is taken, Curr stays NULL, and it returns false
    more1 = CFE_FS_RunBackgroundFileDump(1000, NULL);
    S("fs_run_idle more=");
    D(more1);
    S("\n");
    // the credit CAP: a huge elapsed time must not bank more than MAX_CREDIT
    CFE_FS_Global.FileDump.Current.Credit = 0;
    CFE_FS_RunBackgroundFileDump(100000, NULL);
    S("fs_credit_cap ");
    D(CFE_FS_Global.FileDump.Current.Credit);
    S("\n");
    // the queue FULL path. The check is RequestCount + 1 == CompleteCount + 4, so three
    // objects can be queued and the fourth is refused.
    for (k = 0; k < 5; k++) {
      MemSet(&fs_q[k], 0, sizeof(CFE_FS_FileWriteMetaData_t));
      fs_q[k].GetData = &fs_getdata;
      fs_q[k].OnEvent = &fs_onevent;
      fs_q[k].FileName[0] = 'q';
      fs_q[k].FileName[1] = '0' + k;
      S("fs_qfill");
      D(k);
      S(" rc=");
      D(CFE_FS_BackgroundFileDumpRequest(&fs_q[k]));
      S("\n");
    }
    S("fs_lockcount take=");
    D(fs_mut_take);
    S(" give=");
    D(fs_mut_give);
    S("\n");
  }
  // --- cfe_fs_objtab.c ---------------------------------------------------------------
  // The first registration entry here with a non-NULL hook: FS has no task but does have global
  // data, so EarlyInit is set and TaskMain is not.
  S("fs_objtab ");
  S(CFE_FS_ModuleEntry.Name);
  S(" ");
  D(CFE_FS_ModuleEntry.EarlyInit == NULL);
  S(" ");
  D(CFE_FS_ModuleEntry.TaskMain == NULL);
  S(" ");
  D(CFE_FS_ModuleEntry.AppCleanupCb == NULL);
  S(" ");
  D(CFE_FS_ModuleEntry.Priority);
  S(" ");
  D(CFE_FS_ModuleEntry.StackSize);
  S("\n");
  // --- cfe_config_init.c -------------------------------------------------------------
  // The last piece of the config module, and it was blocked on build output rather than on
  // translation: GLOBAL_CONFIGDATA, the CFE_CONFIGID_* id macros and
  // CFE_Config_SetupPlatformConfigInfo, which is declared in cfe_config_external.h and defined
  // nowhere in the tree. tools/cfs/gen_platform_config.py compiles and runs NASA's OWN
  // generator for the last one.
  
  {
    CFE_ConfigName_t *ci_set[2];
    I32 rc;
    CFE_Config_ArrayValue av;
    // the case-insensitive comparison, including the two ways it can be unequal
    S("ci_eq ");
    D(CFE_Config_StrCaseEq("CFE_ES", "cfe_es"));
    S(" ");
    D(CFE_Config_StrCaseEq("CFE_ES", "CFE_ES"));
    S(" ");
    D(CFE_Config_StrCaseEq("CFE_ES", "CFE_SB"));
    S(" ");
    D(CFE_Config_StrCaseEq("CFE", "CFE_ES"));
    // prefix: shorter first
    S(" ");
    D(CFE_Config_StrCaseEq("CFE_ES", "CFE"));
    // prefix: longer first
    S(" ");
    D(CFE_Config_StrCaseEq("", ""));
    S("\n");
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
    // the set walk: found in the FIRST list, found in the SECOND, and in neither
    ci_set[0] = ci_core;
    ci_set[1] = ci_apps;
    ci_str("ci_set_first", CFE_Config_FindStaticModName(ci_set, 2, "cfe_es"));
    ci_str("ci_set_second", CFE_Config_FindStaticModName(ci_set, 2, "CI_LAB"));
    ci_str("ci_set_none", CFE_Config_FindStaticModName(ci_set, 2, "nothing"));
    ci_str("ci_set_zerolen", CFE_Config_FindStaticModName(ci_set, 0, "cfe_es"));
    // The three platform arrays are file-scope data the C's generated code initialises
    // statically; HolyC has no initialised aggregates at file scope, so the generated
    // CFE_PlatformConfigTablesInit fills them and has to be CALLED before Init installs them.
    CFE_PlatformConfigTablesInit();
    // and the whole initialisation. Note this MEMSETS the registry, so it has to come after
    // the config get/set lines above.
    rc = CFE_Config_Init();
    S("ci_init rc=");
    D(rc);
    S("\n");
    ci_str("ci_mission", CFE_Config_GetString(CFE_CONFIGID_MISSION_NAME));
    ci_str("ci_missionver", CFE_Config_GetString(CFE_CONFIGID_MISSION_SRCVER));
    S("ci_ver ");
    D(CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_MAJOR));
    S(" ");
    D(CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_MINOR));
    S(" ");
    D(CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_REVISION));
    S(" ");
    D(CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_MISSION_REV));
    S(" ");
    D(CFE_Config_GetValue(CFE_CONFIGID_CORE_VERSION_BUILDNUM));
    S("\n");
    ci_str("ci_baseline", CFE_Config_GetString(CFE_CONFIGID_CORE_VERSION_BASELINE));
    // CFE_CONFIGID_CORE_VERSION_DESCRIPTION is DELIBERATELY NOT PRINTED. NASA builds the string
    // into a LOCAL array in CFE_Config_SetupBasicBuildInfo and hands it to
    // CFE_Config_SetString, which stores the POINTER and copies nothing -- so the id holds a
    // pointer into dead stack the moment that function returns. Measured on the C side before
    // it was removed: [cFE v7.0.1+de251(Draco) DEV BUILD, based on v7.0.1, EDS disa] where
    // "v7.0.1+dev1 " and "disabled" belonged. Printing it would put stack contents in a
    // transcript that has to match byte for byte between two different machines.
    // docs/CFS_UPSTREAM_NOTES.md #8. The formatter itself is covered by cfg_ver above.
    // What IS checked is that the id was set at all, i.e. that it is not the fallback:
    S("ci_desc_set ");
    D(CFE_Config_GetString(CFE_CONFIGID_CORE_VERSION_DESCRIPTION) != CFE_Config_Global.UnknownString);
    S("\n");
    ci_str("ci_date", CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_DATE));
    ci_str("ci_user", CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_USER));
    ci_str("ci_host", CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_HOST));
    // the MOD_SRCVER_* ids: set only for modules that are BOTH in the name table and in a
    // static module list, which is how SetupModuleVersions skips dynamically loaded ones
    ci_str("ci_mod_msg", CFE_Config_GetString(CFE_CONFIGID_MOD_SRCVER_MSG));
    ci_str("ci_mod_es", CFE_Config_GetString(CFE_CONFIGID_MOD_SRCVER_ES));
    // and the three platform arrays the generated code installs
    CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_MEM_BLOCK_SIZE, &av);
    S("ci_arr_es n=");
    D(av.NumElements);
    S(" first=");
    D ((av.ElementPtr)(I64 *)[0]);
    S(" last=");
    D ((av.ElementPtr)(I64 *)[av.NumElements - 1]);
    S("\n");
    CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_CDS_MEM_BLOCK_SIZE, &av);
    S("ci_arr_cds n=");
    D(av.NumElements);
    S(" first=");
    D ((av.ElementPtr)(I64 *)[0]);
    S(" last=");
    D ((av.ElementPtr)(I64 *)[av.NumElements - 1]);
    S("\n");
    CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_SB_MEM_BLOCK_SIZE, &av);
    S("ci_arr_sb n=");
    D(av.NumElements);
    S(" first=");
    D ((av.ElementPtr)(I64 *)[0]);
    S(" last=");
    D ((av.ElementPtr)(I64 *)[av.NumElements - 1]);
    S("\n");
  }
  // --- cfe_config_objtab.c ----------------------------------------------------------
  // CONFIG's EarlyInit runs FIRST of all modules: the registry has to exist before anything
  // else in the startup sequence can read a value out of it.
  S("ci_objtab ");
  S(CFE_CONFIG_ModuleEntry.Name);
  S(" ");
  D(CFE_CONFIG_ModuleEntry.EarlyInit == NULL);
  S(" ");
  D(CFE_CONFIG_ModuleEntry.TaskMain == NULL);
  S(" ");
  D(CFE_CONFIG_ModuleEntry.AppCleanupCb == NULL);
  S(" ");
  D(CFE_CONFIG_ModuleEntry.Priority);
  S(" ");
  D(CFE_CONFIG_ModuleEntry.StackSize);
  S("\n");
  // --- cfe_ta: layout -----------------------------------------------------------------
  
  {
    CFE_TA_CpuTaskAffinity_t la;
    CFE_TA_DiagInfo_t ld;
    S("ta_lay aff=");
    D(sizeof(CFE_TA_CpuTaskAffinity_t));
    S(" diag=");
    D(sizeof(CFE_TA_DiagInfo_t));
    S(" glob=");
    D(sizeof(CFE_TA_Global_t));
    S(" hk=");
    D(sizeof(CFE_TA_HousekeepingTlm_t));
    S(" setcmd=");
    D(sizeof(CFE_TA_SetTaskAffinityCmd_t));
    S(" cpuset=");
    D(sizeof(OS_cpuset_t));
    S("\n");
    S("ta_off name=");
    D ((U8 *) & la.TaskName - (U8 *) & la);
    S(" mask=");
    D ((U8 *) & la.CpuMask - (U8 *) & la);
    S(" fromos=");
    D ((U8 *) & la.CpuFromOS - (U8 *) & la);
    S(" type=");
    D ((U8 *) & la.Type - (U8 *) & la);
    S(" status=");
    D ((U8 *) & la.Status - (U8 *) & la);
    S(" | cores=");
    D ((U8 *) & ld.CoresConfigured - (U8 *) & ld);
    S(" arr=");
    D ((U8 *) & ld.CpuTaskAffinity - (U8 *) & ld);
    S("\n");
  }
  // --- CFE_TA_Cpu_Set -----------------------------------------------------------------
  // Driven DIRECTLY, because nothing else can see it: OS_CPUSET_ZERO and OS_CPUSET_SET are
  // macros in the C, so check_coverage never looks for them and check_signatures never
  // compares them. With OS_MAX_CPUS == 1 the loop runs at most once, so the three-way bound
  // is the whole of the behaviour and the mask byte is the whole of the output.
  
  {
    OS_cpuset_t cs;
    U8 mask[8];
    I64 k;
    for (k = 0; k < 8; k++)
      mask[k] = 0xFF;
    ta_cores = 1;
    CFE_TA_Cpu_Set(mask, &cs);
    S("ta_cpuset all1 cores=1 -> ");
    Hxb(cs.affinity_mask[0]);
    S("\n");
    mask[0] = 0x00;
    CFE_TA_Cpu_Set(mask, &cs);
    S("ta_cpuset bit0clr cores=1 -> ");
    Hxb(cs.affinity_mask[0]);
    S("\n");
    mask[0] = 0x01;
    CFE_TA_Cpu_Set(mask, &cs);
    S("ta_cpuset bit0set cores=1 -> ");
    Hxb(cs.affinity_mask[0]);
    S("\n");
    // CoresConfigured is the tightest of the three bounds: at 0 the loop never runs and the
    // mask stays zeroed however many bits the ground sent.
    ta_cores = 0;
    mask[0] = 0xFF;
    CFE_TA_Cpu_Set(mask, &cs);
    S("ta_cpuset all1 cores=0 -> ");
    Hxb(cs.affinity_mask[0]);
    S("\n");
    ta_cores = 1;
  }
  // --- CFE_TA_EarlyInit ----------------------------------------------------------------
  
  {
    I32 erc = CFE_TA_EarlyInit();
    S("ta_early rc=");
    D(erc);
    S("\n");
  }
  ta_row("ta_early_row", 0);
  // Now with a table, including the empty-string terminator that stops the copy early.
  
  {
    I32 erc;
    MemSet(ta_tbl, 0, sizeof(ta_tbl));
    StrNCpy(ta_tbl[0].TaskName, "CFE_ES", CFE_MISSION_MAX_API_LEN - 1);
    ta_tbl[0].Type = CFE_TA_Mask;
    ta_tbl[0].CpuMask.affinity_mask[0] = 0x01;
    StrNCpy(ta_tbl[1].TaskName, "CFE_SB", CFE_MISSION_MAX_API_LEN - 1);
    ta_tbl[1].Type = CFE_TA_OsDefault;
    // ta_tbl[2].TaskName is "" -- the terminator. ta_tbl[3] must NOT be copied.
    StrNCpy(ta_tbl[3].TaskName, "NEVER", CFE_MISSION_MAX_API_LEN - 1);
    CFE_Config_SetObjPointer(CFE_CONFIGID_TA_AFFINITY_TABLE, ta_tbl);
    erc = CFE_TA_EarlyInit();
    S("ta_early2 rc=");
    D(erc);
    S("\n");
    ta_row("ta_early2_row", 0);
    ta_row("ta_early2_row", 1);
    ta_row("ta_early2_row", 2);
    ta_row("ta_early2_row", 3);
  }
  // --- CFE_TA_TaskInit: the success path and all five failures -------------------------
  
  {
    I32 irc;
    ta_evs_register_rc = CFE_SUCCESS;
    ta_pipe_rc = CFE_SUCCESS;
    ta_subscribe_rc = CFE_SUCCESS;
    ta_cores = 1;
    irc = CFE_TA_TaskInit();
    S("ta_init rc=");
    D(irc);
    S(" pipes=");
    D(ta_pipe_created);
    S(" subs=");
    D(ta_subscribes);
    S("\n");
    S("ta_init_diag cores=");
    D(CFE_TA_Global.CFE_TA_DiagInfo.CoresConfigured);
    S(" max=");
    D(CFE_TA_Global.CFE_TA_DiagInfo.TACoresMax);
    S(" app=");
    D(CFE_TA_Global.TA_AppID);
    S("\n");
    ta_evs_register_rc = -77;
    irc = CFE_TA_TaskInit();
    S("ta_init_evsfail rc=");
    D(irc);
    S("\n");
    ta_evs_register_rc = CFE_SUCCESS;
    ta_pipe_rc = -78;
    irc = CFE_TA_TaskInit();
    S("ta_init_pipefail rc=");
    D(irc);
    S("\n");
    ta_pipe_rc = CFE_SUCCESS;
    ta_subscribe_rc = -79;
    irc = CFE_TA_TaskInit();
    S("ta_init_subfail rc=");
    D(irc);
    S("\n");
    ta_subscribe_rc = CFE_SUCCESS;
  }
  // --- the simple commands ---------------------------------------------------------------
  
  {
    I32 crc = CFE_TA_NoopCmd(NULL);
    S("ta_noop rc=");
    D(crc);
    S("\n");
    CFE_TA_Global.CommandCounter = 7;
    CFE_TA_Global.CommandErrorCounter = 8;
    CFE_TA_Global.StartupCounter = 9;
    CFE_TA_Global.StartupErrorCounter = 10;
    crc = CFE_TA_ReportHousekeepingCmd(NULL);
    S("ta_hk rc=");
    D(crc);
    S(" tx=");
    D(ta_transmits);
    S(" pay=");
    D(CFE_TA_Global.TA_TlmPkt.Payload.CommandCounter);
    S("/");
    D(CFE_TA_Global.TA_TlmPkt.Payload.CommandErrorCounter);
    S("/");
    D(CFE_TA_Global.TA_TlmPkt.Payload.StartupCounter);
    S("/");
    D(CFE_TA_Global.TA_TlmPkt.Payload.StartupErrorCounter);
    S("\n");
    // The reset command returns NO_COUNTER_INCREMENT, not SUCCESS -- deliberately, so the
    // dispatcher does not bump the counter it just cleared.
    crc = CFE_TA_ResetCountersCmd(NULL);
    S("ta_reset rc=");
    D(crc);
    S("\n");
  }
  ta_counters("ta_reset_after");
  // --- SetTaskAffinityCmd: every branch -----------------------------------------------
  
  {
    CFE_TA_SetTaskAffinityCmd_t cmd;
    I32 crc;
    MemSet(&cmd, 0, sizeof(CFE_TA_SetTaskAffinityCmd_t));
    StrNCpy(cmd.Payload.TaskName, "CFE_ES", CFE_MISSION_MAX_API_LEN - 1);
    cmd.Payload.AffinityMask[0] = 0x01;
    ta_getid_rc = OS_SUCCESS;
    ta_setaff_rc = OS_SUCCESS;
    ta_getaff_rc = OS_SUCCESS;
    ta_os_mask = 0;
    crc = CFE_TA_SetTaskAffinityCmd(&cmd);
    S("ta_set_ok rc=");
    D(crc);
    S("\n");
    ta_row("ta_set_ok_row", 0);
    // the OS refuses the set
    ta_setaff_rc = -5;
    crc = CFE_TA_SetTaskAffinityCmd(&cmd);
    S("ta_set_setfail rc=");
    D(crc);
    S("\n");
    ta_row("ta_set_setfail_row", 0);
    ta_setaff_rc = OS_SUCCESS;
    // the set works but the read-back does not
    ta_getaff_rc = -6;
    crc = CFE_TA_SetTaskAffinityCmd(&cmd);
    S("ta_set_getfail rc=");
    D(crc);
    S("\n");
    ta_row("ta_set_getfail_row", 0);
    ta_getaff_rc = OS_SUCCESS;
    // a task that is not in the list: the walk stops at the first empty name
    StrNCpy(cmd.Payload.TaskName, "NOT_THERE", CFE_MISSION_MAX_API_LEN - 1);
    crc = CFE_TA_SetTaskAffinityCmd(&cmd);
    S("ta_set_notfound rc=");
    D(crc);
    S("\n");
  }
  ta_counters("ta_set_after");
  // --- GetTaskAffinityCmd ---------------------------------------------------------------
  
  {
    CFE_TA_GetTaskAffinityCmd_t cmd;
    I32 crc;
    MemSet(&cmd, 0, sizeof(CFE_TA_GetTaskAffinityCmd_t));
    StrNCpy(cmd.Payload.TaskName, "CFE_ES", CFE_MISSION_MAX_API_LEN - 1);
    // no discrepancy: the OS reports what the table already holds
    ta_os_mask = CFE_TA_CpuTaskAffinity[0].CpuFromOS.affinity_mask[0];
    crc = CFE_TA_GetTaskAffinityCmd(&cmd);
    S("ta_get_same rc=");
    D(crc);
    S("\n");
    ta_row("ta_get_same_row", 0);
    // a discrepancy: the OS reports something else, and TA adopts it
    ta_os_mask = 0x01;
    CFE_TA_CpuTaskAffinity[0].CpuFromOS.affinity_mask[0] = 0x00;
    crc = CFE_TA_GetTaskAffinityCmd(&cmd);
    S("ta_get_diff rc=");
    D(crc);
    S("\n");
    ta_row("ta_get_diff_row", 0);
    ta_getaff_rc = -8;
    crc = CFE_TA_GetTaskAffinityCmd(&cmd);
    S("ta_get_fail rc=");
    D(crc);
    S("\n");
    ta_row("ta_get_fail_row", 0);
    ta_getaff_rc = OS_SUCCESS;
    StrNCpy(cmd.Payload.TaskName, "NOT_THERE", CFE_MISSION_MAX_API_LEN - 1);
    crc = CFE_TA_GetTaskAffinityCmd(&cmd);
    S("ta_get_notfound rc=");
    D(crc);
    S("\n");
  }
  ta_counters("ta_get_after");
  // --- SetStartupAffinity: the three Types, the add path, and a failed lookup -----------
  
  {
    I32 src;
    ta_getid_rc = OS_SUCCESS;
    ta_getaff_rc = OS_SUCCESS;
    ta_os_mask = 0x01;
    // CFE_ES is in the list with Type == CFE_TA_Mask after the set above
    src = CFE_TA_SetStartupAffinity("CFE_ES");
    S("ta_startup_mask rc=");
    D(src);
    S("\n");
    ta_row("ta_startup_mask_row", 0);
    // CFE_SB is in the list with Type == CFE_TA_OsDefault
    src = CFE_TA_SetStartupAffinity("CFE_SB");
    S("ta_startup_osdef rc=");
    D(src);
    S("\n");
    ta_row("ta_startup_osdef_row", 1);
    // a name not in the list is ADDED at the first empty slot
    src = CFE_TA_SetStartupAffinity("BRAND_NEW");
    S("ta_startup_add rc=");
    D(src);
    S("\n");
    ta_row("ta_startup_add_row", 2);
    // an invalid Type
    CFE_TA_CpuTaskAffinity[1].Type = 99;
    src = CFE_TA_SetStartupAffinity("CFE_SB");
    S("ta_startup_badtype rc=");
    D(src);
    S("\n");
    ta_row("ta_startup_badtype_row", 1);
    CFE_TA_CpuTaskAffinity[1].Type = CFE_TA_OsDefault;
    // the name lookup fails: the loop never runs at all
    ta_getid_rc = -9;
    src = CFE_TA_SetStartupAffinity("CFE_ES");
    S("ta_startup_noid rc=");
    D(src);
    S("\n");
    ta_getid_rc = OS_SUCCESS;
    // The two OS failures inside the loop. Each logs a line carrying the TASK NAME and the
    // STATUS, and neither was reachable before: the block above only ever had the OS succeed,
    // so the arguments in those two syslog calls were translated and never read.
    ta_getaff_rc = -21;
    src = CFE_TA_SetStartupAffinity("CFE_ES");
    S("ta_startup_getfail rc=");
    D(src);
    S("\n");
    ta_getaff_rc = OS_SUCCESS;
    ta_setaff_rc = -22;
    src = CFE_TA_SetStartupAffinity("CFE_ES");
    S("ta_startup_setfail rc=");
    D(src);
    S("\n");
    ta_setaff_rc = OS_SUCCESS;
    ta_counters("ta_startup_after");
    // and the OS event handler, which is the only caller of SetStartupAffinity in flight
    src = CFE_TA_OS_EventHandler(OS_EVENT_RESOURCE_ALLOCATED, 1, NULL);
    S("ta_evh_alloc rc=");
    D(src);
    S("\n");
    src = CFE_TA_OS_EventHandler(OS_EVENT_RESOURCE_CREATED, 1, NULL);
    S("ta_evh_created rc=");
    D(src);
    S("\n");
    src = CFE_TA_OS_EventHandler(OS_EVENT_RESOURCE_DELETED, 1, NULL);
    S("ta_evh_deleted rc=");
    D(src);
    S("\n");
    src = CFE_TA_OS_EventHandler(OS_EVENT_TASK_STARTUP, 1, NULL);
    S("ta_evh_startup rc=");
    D(src);
    S("\n");
    ta_row("ta_evh_startup_row", 3);
    ta_counters("ta_evh_after");
  }
  // --- QueryAllTasksCmd: through the TRANSLATED fs module and the simulated file --------
  
  {
    CFE_TA_QueryAllTasksCmd_t cmd;
    I32 qrc;
    MemSet(&cmd, 0, sizeof(CFE_TA_QueryAllTasksCmd_t));
    StrNCpy(cmd.Payload.FileName, "/ram/ta.log", CFE_MISSION_MAX_PATH_LEN - 1);
    fs_open_fail = 0;
    fs_wr_left = -1;
    fs_fd = 0;
    fs_len = 0;
    fs_pos = 0;
    qrc = CFE_TA_QueryAllTasksCmd(&cmd);
    S("ta_query rc=");
    D(qrc);
    S(" len=");
    D(fs_len);
    S("\n");
    fs_dump("ta_query_bytes", 16);
    ta_counters("ta_query_after");
    // the file cannot be created
    fs_open_fail = 1;
    qrc = CFE_TA_QueryAllTasksCmd(&cmd);
    S("ta_query_nocreate rc=");
    D(qrc);
    S("\n");
    fs_open_fail = 0;
    // the header write comes up short
    fs_wr_left = 4;
    qrc = CFE_TA_QueryAllTasksCmd(&cmd);
    S("ta_query_hdrfail rc=");
    D(qrc);
    S("\n");
    // the header fits and the diagnostic packet does not
    fs_wr_left = 64;
    qrc = CFE_TA_QueryAllTasksCmd(&cmd);
    S("ta_query_datafail rc=");
    D(qrc);
    S("\n");
    fs_wr_left = -1;
    ta_counters("ta_query_errs");
  }
  // --- cfe_ta_dispatch.c -----------------------------------------------------------------
  // The CONDITIONAL source: CMakeLists picks this one when EDS is off, which is this port.
  // CFE_TA_TaskMain calls CFE_TA_TaskPipe, so a port that translated only the two
  // unconditional sources would have a task whose message loop dispatches to nothing.
  
  {
    I64 cc;
    Bool vok;
    MemSet(&ta_sb, 0, sizeof(ta_sb_u));
    CFE_MSG_Init(&ta_sb.Set.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID), sizeof(CFE_TA_SetTaskAffinityCmd_t));
    // the length check, both ways
    // Hoisted: the failing one emits an event, and printf evaluates its arguments before the
    // format, so on the C side that event line comes FIRST.
    vok = CFE_TA_VerifyCmdLength(&ta_sb.Buf.Msg, sizeof(CFE_TA_SetTaskAffinityCmd_t));
    S("ta_len_ok ");
    D(vok);
    S("\n");
    vok = CFE_TA_VerifyCmdLength(&ta_sb.Buf.Msg, 9999);
    S("ta_len_bad ");
    D(vok);
    S("\n");
    // every command code, then one that does not exist
    for (cc = 0; cc <= 5; cc++) {
      CFE_MSG_SetFcnCode(&ta_sb.Buf.Msg, cc);
      // give each command the length IT expects, so the routing rather than the length check
      // is what the transcript shows
      switch (cc) {
        case CFE_TA_NOOP_CC :
        case CFE_TA_RESET_COUNTERS_CC :
        CFE_MSG_SetSize(&ta_sb.Buf.Msg, sizeof(CFE_TA_NoopCmd_t));
        break;
        case CFE_TA_QUERY_ALL_TASKS_CC :
        CFE_MSG_SetSize(&ta_sb.Buf.Msg, sizeof(CFE_TA_QueryAllTasksCmd_t));
        break;
        case CFE_TA_SET_TASK_AFFINITY_CC :
        CFE_MSG_SetSize(&ta_sb.Buf.Msg, sizeof(CFE_TA_SetTaskAffinityCmd_t));
        break;
        case CFE_TA_GET_TASK_AFFINITY_CC :
        CFE_MSG_SetSize(&ta_sb.Buf.Msg, sizeof(CFE_TA_GetTaskAffinityCmd_t));
        break;
        default:
        break;
      }
      S("ta_cc ");
      D(cc);
      S(":\n");
      CFE_TA_ProcessGroundCommand(&ta_sb.Buf, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID));
    }
    ta_counters("ta_cc_after");
    // TaskPipe: the housekeeping id, the command id, and one that is neither
    CFE_MSG_SetFcnCode(&ta_sb.Buf.Msg, CFE_TA_NOOP_CC);
    CFE_MSG_SetSize(&ta_sb.Buf.Msg, sizeof(CFE_TA_NoopCmd_t));
    CFE_MSG_SetMsgId(&ta_sb.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TA_SEND_HK_MID));
    S("ta_pipe_hk:\n");
    CFE_TA_TaskPipe(&ta_sb.Buf);
    CFE_MSG_SetMsgId(&ta_sb.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID));
    S("ta_pipe_cmd:\n");
    CFE_TA_TaskPipe(&ta_sb.Buf);
    CFE_MSG_SetMsgId(&ta_sb.Buf.Msg, CFE_SB_ValueToMsgId(0x1FFF));
    S("ta_pipe_unknown:\n");
    CFE_TA_TaskPipe(&ta_sb.Buf);
    ta_counters("ta_pipe_after");
  }
  // --- cfe_ta_objtab.c ---------------------------------------------------------------------
  // The first entry here with every field filled in: TA is an app, not a library.
  S("ta_objtab ");
  S(CFE_TA_ModuleEntry.Name);
  S(" ");
  D(CFE_TA_ModuleEntry.EarlyInit == NULL);
  S(" ");
  D(CFE_TA_ModuleEntry.TaskMain == NULL);
  S(" ");
  D(CFE_TA_ModuleEntry.AppCleanupCb == NULL);
  S(" ");
  D(CFE_TA_ModuleEntry.Priority);
  S(" ");
  D(CFE_TA_ModuleEntry.StackSize);
  S("\n");
  
  {
    I32 clr = CFE_TA_CleanUpApp(1);
    S("ta_cleanup rc=");
    D(clr);
    S("\n");
  }
  // --- cfe_evs: the real event service ------------------------------------------------
  // Three of EVS's six sources, and with them the CFE_EVS_SendEvent stub is gone: the ta
  // events above now go through registration, filtering, the squelch bucket, the local log
  // and the formatter, and come out of EVS_OutputPort as real text. That text is the
  // strongest thing in this transcript, because it is the packet payload: the first
  // formatted string in this translation that is INSIDE the byte-identical comparison.
  
  {
    CFE_EVS_BinFilter_t filters[3];
    EVS_AppData_t *adp;
    U32 evsid = 1;
    U32 othrid = 2;
    I64 k;
    I32 rc;
    // Stand EVS up the way cfe_evs_task.c would: the log in the reset area, the format and
    // port defaults, an unlimited squelch bucket, and EVS registered as app 1.
    MemSet(&CFE_EVS_Global, 0, sizeof(CFE_EVS_Global_t));
    MemSet(&evs_log_storage, 0, sizeof(CFE_EVS_Log_t));
    CFE_EVS_Global.EVS_LogPtr = &evs_log_storage;
    CFE_EVS_Global.EVS_AppID = evsid;
    CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode = CFE_EVS_MsgFormat_LONG;
    CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = CFE_EVS_PORT1_BIT;
    // squelch off for now; the burst budget gets its own block below
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_EVS_LogMode_OVERWRITE;
    evs_psp_ns = 0;
    ta_transmits = 0;
    evs_printf_lines = 0;
    // --- CFE_EVS_Register -----------------------------------------------------------
    // The caller is whatever CFE_ES_GetAppID says, which this driver points at app 1.
    ta_getappid = 1;
    rc = CFE_EVS_Register(NULL, 0, 99);
    S("evs_reg_badscheme rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_Register(NULL, 2, CFE_EVS_EventFilter_BINARY);
    S("evs_reg_nullfilters rc=");
    D(rc);
    S("\n");
    filters[0].EventID = 10;
    filters[0].Mask = 0x0001;
    filters[1].EventID = 20;
    filters[1].Mask = 0x0000;
    filters[2].EventID = 30;
    filters[2].Mask = 0xFFFF;
    rc = CFE_EVS_Register(filters, 3, CFE_EVS_EventFilter_BINARY);
    S("evs_reg rc=");
    D(rc);
    S("\n");
    adp = EVS_GetAppDataByID(evsid);
    S("evs_reg_state used=");
    D(EVS_AppDataIsUsed(adp));
    S(" active=");
    D(adp->ActiveFlag);
    S(" tokens=");
    D(adp->SquelchTokens);
    S(" mask=");
    D(EVS_EventArrayToBitMask(adp));
    S("\n");
    // The three supplied filters, then the first unused slot: NASA marks those FREE_SLOT
    // (-1), which in a uint16 EventID is 0xFFFF.
    for (k = 0; k < 4; k++) {
      S("evs_reg_filter[");
      D(k);
      S("] id=");
      D(adp->BinFilters[k].EventID);
      S(" mask=");
      Hx4(adp->BinFilters[k].Mask);
      S(" count=");
      D(adp->BinFilters[k].Count);
      S("\n");
    }
    // more filters than the table holds: truncated, with a syslog line
    rc = CFE_EVS_Register(filters, 99, CFE_EVS_EventFilter_BINARY);
    S("evs_reg_trunc rc=");
    D(rc);
    S("\n");
    // --- CFE_EVS_SendEvent, through the whole pipeline ------------------------------
    // Re-register with the three filters, then send. Every successful send prints the port
    // line, which carries the formatted text, the app name, the ids and the time.
    CFE_EVS_Register(filters, 3, CFE_EVS_EventFilter_BINARY);
    rc = CFE_EVS_SendEvent(1, CFE_EVS_EventType_INFORMATION, NULL);
    S("evs_send_nullspec rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_SendEvent(1, CFE_EVS_EventType_INFORMATION, "plain text");
    S("evs_send_plain rc=");
    D(rc);
    S("\n");
    // the conversions EVS's own call sites use
    rc = CFE_EVS_SendEvent(2, CFE_EVS_EventType_ERROR, "s=%s u=%u d=%d x=%08x", "name", 7, -3, 0xbeef);
    S("evs_send_fmt rc=");
    D(rc);
    S("\n");
    // a message LONGER than the 122-byte payload: truncated, and marked with '$'
    rc = CFE_EVS_SendEvent(3, CFE_EVS_EventType_INFORMATION, "%s%s%s%s%s%s%s%s%s%s%s%s%s", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789", "0123456789");
    S("evs_send_long rc=");
    D(rc);
    S("\n");
    S("evs_trunc_count ");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageTruncCounter);
    S("\n");
    // event 10 has mask 0x0001: the FIRST send gets through (count 0), the second is
    // filtered because Mask & Count is nonzero
    rc = CFE_EVS_SendEvent(10, CFE_EVS_EventType_INFORMATION, "filtered id pass 1");
    S("evs_filt_first rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_SendEvent(10, CFE_EVS_EventType_INFORMATION, "filtered id pass 2");
    S("evs_filt_second rc=");
    D(rc);
    S("\n");
    // mask 0 never filters; mask 0xFFFF filters everything after the first
    rc = CFE_EVS_SendEvent(20, CFE_EVS_EventType_INFORMATION, "mask zero");
    S("evs_filt_mask0 rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_SendEvent(30, CFE_EVS_EventType_INFORMATION, "mask all");
    S("evs_filt_maskall rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_SendEvent(30, CFE_EVS_EventType_INFORMATION, "mask all again");
    S("evs_filt_maskall2 rc=");
    D(rc);
    S("\n");
    // The type switch. This used to be a driver stub answering CFE_EVS_GetTypeEnable;
    // cfe_evs_task.c is translated now, so the real one runs and the switch is the app's own
    // EventTypesActive array -- reached through CFE_EVS_SetTypeEnable, which is also translated.
    CFE_EVS_SetTypeEnable(CFE_EVS_EventType_INFORMATION, FALSE);
    rc = CFE_EVS_SendEvent(4, CFE_EVS_EventType_INFORMATION, "type disabled");
    S("evs_typeoff rc=");
    D(rc);
    S("\n");
    CFE_EVS_SetTypeEnable(CFE_EVS_EventType_INFORMATION, TRUE);
    // the per-app active flag does the same, one level earlier
    adp = EVS_GetAppDataByID(evsid);
    adp->ActiveFlag = FALSE;
    rc = CFE_EVS_SendEvent(5, CFE_EVS_EventType_INFORMATION, "app inactive");
    S("evs_inactive rc=");
    D(rc);
    S("\n");
    adp->ActiveFlag = TRUE;
    S("evs_counters sent=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter);
    S(" app=");
    D(adp->EventCount);
    S("\n");
    // --- the "not registered" path --------------------------------------------------
    // App 2 has never registered, so its first event logs and counts, and its second is
    // silent -- EVS remembers it has already complained about that app.
    ta_getappid = 2;
    rc = CFE_EVS_SendEvent(6, CFE_EVS_EventType_ERROR, "from an unregistered app");
    S("evs_unreg1 rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_SendEvent(7, CFE_EVS_EventType_ERROR, "again");
    S("evs_unreg2 rc=");
    D(rc);
    S("\n");
    S("evs_unreg_count ");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.UnregisteredAppCounter);
    S("\n");
    ta_getappid = 1;
    // --- SendEventWithAppID and SendTimedEvent --------------------------------------
    rc = CFE_EVS_SendEventWithAppID(8, CFE_EVS_EventType_INFORMATION, 99, "bad id");
    S("evs_withid_bad rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_SendEventWithAppID(9, CFE_EVS_EventType_INFORMATION, evsid, "by app id");
    S("evs_withid rc=");
    D(rc);
    S("\n");
    
    {
      CFE_TIME_SysTime ts;
      ts.Seconds = 123;
      ts.Subseconds = 456;
      rc = CFE_EVS_SendTimedEvent(ts, 11, CFE_EVS_EventType_INFORMATION, "timed");
      S("evs_timed rc=");
      D(rc);
      S("\n");
    }
    // --- the squelch bucket ---------------------------------------------------------
    // With a burst budget the token count is what decides. Each event costs 1000 and the
    // clock does not move, so a burst of 3 drains to the floor and the next send is refused with
    // CFE_EVS_APP_SQUELCHED.
    //
    // EIGHT iterations, not five: at five the count never reached LOWER_THRESHOLD, so doubling
    // the floor left this transcript byte-identical. See the note in the C half.
    CFE_EVS_Global.EVS_EventBurstMax = 3;
    adp = EVS_GetAppDataByID(evsid);
    adp->SquelchTokens = 3000;
    adp->SquelchedCount = 0;
    adp->LastSquelchCreditableTime.ticks = 0;
    evs_psp_ns = 0;
    for (k = 0; k < 8; k++) {
      rc = CFE_EVS_SendEvent(40 + k, CFE_EVS_EventType_INFORMATION, "burst");
      S("evs_squelch");
      D(k);
      S(" rc=");
      D(rc);
      S(" tok=");
      D(adp->SquelchTokens);
      S(" cnt=");
      D(adp->SquelchedCount);
      S("\n");
    }
    // move the clock forward a second: 15 events/sec * 1000 ms = 15000 credits, capped at
    // EventBurstMax * 1000
    evs_psp_ns = 1000000000;
    rc = CFE_EVS_SendEvent(50, CFE_EVS_EventType_INFORMATION, "after a second");
    S("evs_squelch_credit rc=");
    D(rc);
    S(" tok=");
    D(adp->SquelchTokens);
    S("\n");
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    // --- ResetFilter / ResetAllFilters ----------------------------------------------
    adp = EVS_GetAppDataByID(evsid);
    rc = CFE_EVS_ResetFilter(10);
    S("evs_resetf_known rc=");
    D(rc);
    S(" count=");
    D(adp->BinFilters[0].Count);
    S("\n");
    rc = CFE_EVS_ResetFilter(999);
    S("evs_resetf_unknown rc=");
    D(rc);
    S("\n");
    adp->BinFilters[1].Count = 5;
    adp->BinFilters[2].Count = 6;
    rc = CFE_EVS_ResetAllFilters();
    S("evs_resetall rc=");
    D(rc);
    S(" c1=");
    D(adp->BinFilters[1].Count);
    S(" c2=");
    D(adp->BinFilters[2].Count);
    S("\n");
    // both reject an unregistered caller
    ta_getappid = 2;
    rc = CFE_EVS_ResetFilter(10);
    S("evs_resetf_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ResetAllFilters();
    S("evs_resetall_unreg rc=");
    D(rc);
    S("\n");
    ta_getappid = 1;
    // --- the helpers nothing else reaches -------------------------------------------
    
    {
      Bool b0, b1, b2;
      b0 = EVS_IsInvalidBitMask(0, 1);
      b1 = EVS_IsInvalidBitMask(0x10, 2);
      b2 = EVS_IsInvalidBitMask(0x5, 3);
      S("evs_bitmask bad0=");
      D(b0);
      S(" badbig=");
      D(b1);
      S(" ok=");
      D(b2);
      S("\n");
    }
    EVS_SetTypes(adp, 0x0, TRUE);
    S("evs_settypes none=");
    D(EVS_EventArrayToBitMask(adp));
    S("\n");
    EVS_SetTypes(adp, CFE_EVS_ALL_EVENT_TYPES_MASK, TRUE);
    S("evs_settypes all=");
    D(EVS_EventArrayToBitMask(adp));
    S("\n");
    EVS_SetTypes(adp, CFE_EVS_DEBUG_BIT | CFE_EVS_ERROR_BIT, FALSE);
    S("evs_settypes cleared=");
    D(EVS_EventArrayToBitMask(adp));
    S("\n");
    // the NULL guard
    EVS_SetTypes(NULL, 0xFF, TRUE);
    S("evs_settypes nullsafe=");
    D(EVS_EventArrayToBitMask(NULL));
    S("\n");
    S("evs_findid known=");
    D(EVS_FindEventID(20, adp->BinFilters) == &adp->BinFilters[1]);
    S(" unknown=");
    D(EVS_FindEventID(999, adp->BinFilters) == NULL);
    S("\n");
    // EVS_GetApplicationInfo by name, which is how the ground addresses an app
    
    {
      EVS_AppData_t *byname = NULL;
      rc = EVS_GetApplicationInfo(&byname, "CFE_EVS");
      S("evs_byname_ok rc=");
      D(rc);
      S(" match=");
      D(byname == EVS_GetAppDataByID(evsid));
      S("\n");
      rc = EVS_GetApplicationInfo(&byname, "OTHER_APP");
      S("evs_byname_unreg rc=");
      D(rc);
      S(" null=");
      D(byname == NULL);
      S("\n");
      rc = EVS_GetApplicationInfo(&byname, "NOPE");
      S("evs_byname_nosuch rc=");
      D(rc);
      S("\n");
    }
  }
  // --- cfe_evs_log.c --------------------------------------------------------------------
  
  {
    CFE_EVS_LongEventTlm_t entry;
    CFE_EVS_SetLogModeCmd_t modecmd;
    CFE_EVS_WriteLogDataFileCmd_t wrcmd;
    I64 k;
    I32 rc;
    EVS_ClearLog();
    S("evs_log_clear next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S(" count=");
    D(CFE_EVS_Global.EVS_LogPtr->LogCount);
    S(" full=");
    D(CFE_EVS_Global.EVS_LogPtr->LogFullFlag);
    S(" ovf=");
    D(CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter);
    S("\n");
    // fill past the end: 20 entries fill it, the 21st wraps in OVERWRITE mode
    MemSet(&entry, 0, sizeof(CFE_EVS_LongEventTlm_t));
    for (k = 0; k < 22; k++) {
      entry.Payload.PacketID.EventID = 100 + k;
      EVS_AddLog(&entry);
    }
    S("evs_log_wrap next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S(" count=");
    D(CFE_EVS_Global.EVS_LogPtr->LogCount);
    S(" full=");
    D(CFE_EVS_Global.EVS_LogPtr->LogFullFlag);
    S(" ovf=");
    D(CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter);
    S(" first=");
    D(CFE_EVS_Global.EVS_LogPtr->LogEntry[0].Payload.PacketID.EventID);
    S("\n");
    // DISCARD mode: the overflow counter still climbs but nothing is written
    CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_EVS_LogMode_DISCARD;
    entry.Payload.PacketID.EventID = 777;
    EVS_AddLog(&entry);
    S("evs_log_discard next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S(" ovf=");
    D(CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter);
    S(" at2=");
    D(CFE_EVS_Global.EVS_LogPtr->LogEntry[2].Payload.PacketID.EventID);
    S("\n");
    // SetLogModeCmd, both valid modes and one that is not
    MemSet(&modecmd, 0, sizeof(CFE_EVS_SetLogModeCmd_t));
    modecmd.Payload.LogMode = CFE_EVS_LogMode_OVERWRITE;
    rc = CFE_EVS_SetLogModeCmd(&modecmd);
    S("evs_setmode_ovr rc=");
    D(rc);
    S(" mode=");
    D(CFE_EVS_Global.EVS_LogPtr->LogMode);
    S("\n");
    modecmd.Payload.LogMode = CFE_EVS_LogMode_DISCARD;
    rc = CFE_EVS_SetLogModeCmd(&modecmd);
    S("evs_setmode_dis rc=");
    D(rc);
    S(" mode=");
    D(CFE_EVS_Global.EVS_LogPtr->LogMode);
    S("\n");
    modecmd.Payload.LogMode = 7;
    rc = CFE_EVS_SetLogModeCmd(&modecmd);
    S("evs_setmode_bad rc=");
    D(rc);
    S(" mode=");
    D(CFE_EVS_Global.EVS_LogPtr->LogMode);
    S("\n");
    modecmd.Payload.LogMode = CFE_EVS_LogMode_OVERWRITE;
    CFE_EVS_SetLogModeCmd(&modecmd);
    // WriteLogDataFileCmd, through the translated fs module and the simulated file
    MemSet(&wrcmd, 0, sizeof(CFE_EVS_WriteLogDataFileCmd_t));
    StrNCpy(wrcmd.Payload.LogFilename, "/ram/evs.log", CFE_MISSION_MAX_PATH_LEN - 1);
    fs_open_fail = 0;
    fs_wr_left = -1;
    fs_fd = 0;
    fs_len = 0;
    fs_pos = 0;
    rc = CFE_EVS_WriteLogDataFileCmd(&wrcmd);
    S("evs_wrlog rc=");
    D(rc);
    S(" len=");
    D(fs_len);
    S("\n");
    fs_dump("evs_wrlog_bytes", 16);
    fs_open_fail = 1;
    rc = CFE_EVS_WriteLogDataFileCmd(&wrcmd);
    S("evs_wrlog_nocreate rc=");
    D(rc);
    S("\n");
    fs_open_fail = 0;
    fs_wr_left = 4;
    rc = CFE_EVS_WriteLogDataFileCmd(&wrcmd);
    S("evs_wrlog_hdrfail rc=");
    D(rc);
    S("\n");
    fs_wr_left = 64;
    rc = CFE_EVS_WriteLogDataFileCmd(&wrcmd);
    S("evs_wrlog_datafail rc=");
    D(rc);
    S("\n");
    fs_wr_left = -1;
    S("evs_printf_lines ");
    D(evs_printf_lines);
    S("\n");
  }
  // --- TA's events, through the real EVS -------------------------------------------------
  // The TA block above ran with CFE_EVS_Global zeroed, so every event it sent was dropped before
  // it reached the formatter: the ids and the branch taken were compared, the WORDING was not.
  // Now EVS is standing and app 1 is registered, so running the same commands again puts TA's
  // twenty event strings -- the affinity masks, the file sizes, the status codes, the message
  // ids -- inside the byte-identical comparison. That is the half of the TA translation nothing
  // had checked, and the half where the arguments live.
  
  {
    CFE_TA_SetTaskAffinityCmd_t setcmd;
    CFE_TA_GetTaskAffinityCmd_t getcmd;
    CFE_TA_QueryAllTasksCmd_t wrcmd;
    I32 rc;
    Bool vok;
    // EVS is still registered as app 1 from the block above; make TA the caller of record and
    // clear the filters so nothing is suppressed.
    ta_getappid = 1;
    CFE_EVS_ResetAllFilters();
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = CFE_EVS_PORT1_BIT;
    ta_cores = 1;
    ta_evs_register_rc = CFE_SUCCESS;
    ta_pipe_rc = CFE_SUCCESS;
    ta_subscribe_rc = CFE_SUCCESS;
    rc = CFE_TA_TaskInit();
    S("tae_init rc=");
    D(rc);
    S("\n");
    rc = CFE_TA_NoopCmd(NULL);
    S("tae_noop rc=");
    D(rc);
    S("\n");
    rc = CFE_TA_ResetCountersCmd(NULL);
    S("tae_reset rc=");
    D(rc);
    S("\n");
    // QueryAllTasks: the success line carries the filename, the entry count and the file size,
    // and each failure line carries a status code in a different conversion.
    MemSet(&wrcmd, 0, sizeof(CFE_TA_QueryAllTasksCmd_t));
    StrNCpy(wrcmd.Payload.FileName, "/ram/tasks.dat", CFE_MISSION_MAX_PATH_LEN - 1);
    fs_open_fail = 0;
    fs_wr_left = -1;
    fs_fd = 0;
    fs_len = 0;
    fs_pos = 0;
    rc = CFE_TA_QueryAllTasksCmd(&wrcmd);
    S("tae_qall rc=");
    D(rc);
    S("\n");
    fs_open_fail = 1;
    rc = CFE_TA_QueryAllTasksCmd(&wrcmd);
    S("tae_qall_nocreate rc=");
    D(rc);
    S("\n");
    fs_open_fail = 0;
    fs_wr_left = 4;
    rc = CFE_TA_QueryAllTasksCmd(&wrcmd);
    S("tae_qall_hdrfail rc=");
    D(rc);
    S("\n");
    fs_wr_left = 64;
    rc = CFE_TA_QueryAllTasksCmd(&wrcmd);
    S("tae_qall_wrfail rc=");
    D(rc);
    S("\n");
    fs_wr_left = -1;
    // SetTaskAffinity: the success event prints the mask twice with "0x%016llX", which is the
    // only 64-bit conversion in the whole translation.
    MemSet(&setcmd, 0, sizeof(CFE_TA_SetTaskAffinityCmd_t));
    StrNCpy(setcmd.Payload.TaskName, "CFE_ES", OS_MAX_API_NAME - 1);
    setcmd.Payload.AffinityMask[0] = 0x01;
    ta_getid_rc = OS_SUCCESS;
    ta_setaff_rc = OS_SUCCESS;
    ta_getaff_rc = OS_SUCCESS;
    ta_os_mask = 0;
    rc = CFE_TA_SetTaskAffinityCmd(&setcmd);
    S("tae_set rc=");
    D(rc);
    S("\n");
    ta_setaff_rc = -5;
    rc = CFE_TA_SetTaskAffinityCmd(&setcmd);
    S("tae_set_setfail rc=");
    D(rc);
    S("\n");
    ta_setaff_rc = OS_SUCCESS;
    ta_getaff_rc = -6;
    rc = CFE_TA_SetTaskAffinityCmd(&setcmd);
    S("tae_set_getfail rc=");
    D(rc);
    S("\n");
    ta_getaff_rc = OS_SUCCESS;
    StrNCpy(setcmd.Payload.TaskName, "NO_SUCH", OS_MAX_API_NAME - 1);
    rc = CFE_TA_SetTaskAffinityCmd(&setcmd);
    S("tae_set_notfound rc=");
    D(rc);
    S("\n");
    // GetTaskAffinity: the discrepancy event takes no arguments, the success one takes three.
    MemSet(&getcmd, 0, sizeof(CFE_TA_GetTaskAffinityCmd_t));
    StrNCpy(getcmd.Payload.TaskName, "CFE_ES", OS_MAX_API_NAME - 1);
    rc = CFE_TA_GetTaskAffinityCmd(&getcmd);
    S("tae_get rc=");
    D(rc);
    S("\n");
    ta_os_mask = 0x02;
    rc = CFE_TA_GetTaskAffinityCmd(&getcmd);
    S("tae_get_diff rc=");
    D(rc);
    S("\n");
    ta_getaff_rc = -6;
    rc = CFE_TA_GetTaskAffinityCmd(&getcmd);
    S("tae_get_fail rc=");
    D(rc);
    S("\n");
    ta_getaff_rc = OS_SUCCESS;
    StrNCpy(getcmd.Payload.TaskName, "NO_SUCH", OS_MAX_API_NAME - 1);
    rc = CFE_TA_GetTaskAffinityCmd(&getcmd);
    S("tae_get_notfound rc=");
    D(rc);
    S("\n");
    // The dispatcher's three events: a bad length, a bad command code and a bad message id. Each
    // prints a message id with a different hex conversion -- %X, %08x and %08X -- and those three
    // spellings are exactly what the formatter had to learn.
    MemSet(&ta_sb, 0, sizeof(ta_sb_u));
    CFE_MSG_Init(&ta_sb.Set.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID), sizeof(CFE_TA_SetTaskAffinityCmd_t));
    CFE_MSG_SetFcnCode(&ta_sb.Buf.Msg, CFE_TA_NOOP_CC);
    vok = CFE_TA_VerifyCmdLength(&ta_sb.Buf.Msg, 9999);
    S("tae_len_bad ");
    D(vok);
    S("\n");
    CFE_MSG_SetFcnCode(&ta_sb.Buf.Msg, 0x7E);
    CFE_TA_ProcessGroundCommand(&ta_sb.Buf, CFE_SB_ValueToMsgId(CFE_TA_CMD_MID));
    S("tae_badcc done\n");
    CFE_MSG_Init(&ta_sb.Set.CommandHeader.Msg, CFE_SB_ValueToMsgId(0x1FFF), sizeof(CFE_TA_SetTaskAffinityCmd_t));
    CFE_TA_TaskPipe(&ta_sb.Buf);
    S("tae_badmid done\n");
    S("tae_counters cc=");
    D(CFE_TA_Global.CommandCounter);
    S(" cec=");
    D(CFE_TA_Global.CommandErrorCounter);
    S(" evs=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter);
    S(" printed=");
    D(evs_printf_lines);
    S("\n");
  }
  // --- cfe_evs_task.c and cfe_evs_dispatch.c: EVS AS A TASK -------------------------------
  // The other three sources, and with them the module is complete. EarlyInit takes the event log
  // out of the PSP reset area; TaskInit registers EVS and subscribes; twenty ground commands and
  // a dispatcher route them. Every one of those commands ends in an event, and most of them are
  // CFE_EVS_EventType_DEBUG -- which the DEFAULT type mask has OFF, so the first thing this
  // block does is what a ground operator does: enable DEBUG. That is also why the transcript
  // lost nine lines when cfe_evs_task.c arrived: the driver's old CFE_EVS_GetTypeEnable stub
  // answered "enabled" for every type, and the real one reads the app's own EventTypesActive.
  
  {
    CFE_EVS_BitMaskCmd_Payload_t *bm;
    CFE_EVS_AppNameCmd_Payload_t *an;
    CFE_EVS_AppNameBitMaskCmd_Payload_t *anbm;
    CFE_EVS_AppNameEventIDCmd_Payload_t *aneid;
    CFE_EVS_AppNameEventIDMaskCmd_Payload_t *aneidm;
    EVS_AppData_t *ap;
    I32 rc;
    Bool vok;
    I64 cc;
    // --- CFE_EVS_EarlyInit ------------------------------------------------------------
    // the PSP refuses
    evs_resetarea_rc = -31;
    rc = CFE_EVS_EarlyInit();
    S("evt_early_nopsp rc=");
    D(rc);
    S(" panics=");
    D(evs_panics);
    S(" delay=");
    D(evs_delay_ms);
    S("\n");
    evs_resetarea_rc = CFE_PSP_SUCCESS;
    // the area is there and is too small for CFE_ES_ResetData_t
    evs_resetarea_size = 64;
    rc = CFE_EVS_EarlyInit();
    S("evt_early_short rc=");
    D(rc);
    S(" panics=");
    D(evs_panics);
    S("\n");
    evs_resetarea_size = 0;
    // a power-on reset clears the log
    evs_reset_type = CFE_PSP_RST_TYPE_POWERON;
    MemSet(&evs_reset_area, 0, sizeof(CFE_ES_ResetData_t));
    rc = CFE_EVS_EarlyInit();
    S("evt_early_poweron rc=");
    D(rc);
    S("\n");
    S("evt_early_state fmt=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode);
    S(" port=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort);
    S(" logmode=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.LogMode);
    S(" logen=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.LogEnabled);
    S(" burst=");
    D(CFE_EVS_Global.EVS_EventBurstMax);
    S(" next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S(" count=");
    D(CFE_EVS_Global.EVS_LogPtr->LogCount);
    S("\n");
    // a processor reset with a GOOD log restores it; with a bad one clears it
    evs_reset_type = 1;
    CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_EVS_LogMode_OVERWRITE;
    CFE_EVS_Global.EVS_LogPtr->LogFullFlag = FALSE;
    CFE_EVS_Global.EVS_LogPtr->Next = 3;
    CFE_EVS_Global.EVS_LogPtr->LogCount = 3;
    rc = CFE_EVS_EarlyInit();
    S("evt_early_restore rc=");
    D(rc);
    S(" next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S("\n");
    CFE_EVS_Global.EVS_LogPtr->LogMode = 99;
    // neither OVERWRITE nor DISCARD
    rc = CFE_EVS_EarlyInit();
    S("evt_early_badlog rc=");
    D(rc);
    S(" next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S(" mode=");
    D(CFE_EVS_Global.EVS_LogPtr->LogMode);
    S("\n");
    // --- CFE_EVS_TaskInit -------------------------------------------------------------
    ta_getappid = 1;
    ta_pipe_rc = CFE_SUCCESS;
    ta_subscribe_rc = CFE_SUCCESS;
    rc = CFE_EVS_TaskInit();
    S("evt_init rc=");
    D(rc);
    S(" appid=");
    D(CFE_ResourceId_ToInteger(CFE_EVS_Global.EVS_AppID));
    S("\n");
    ta_pipe_rc = -41;
    rc = CFE_EVS_TaskInit();
    S("evt_init_pipefail rc=");
    D(rc);
    S("\n");
    ta_pipe_rc = CFE_SUCCESS;
    ta_subscribe_rc = -42;
    rc = CFE_EVS_TaskInit();
    S("evt_init_subfail rc=");
    D(rc);
    S("\n");
    ta_subscribe_rc = CFE_SUCCESS;
    rc = CFE_EVS_TaskInit();
    S("evt_init_again rc=");
    D(rc);
    S("\n");
    // --- enable DEBUG, so the twenty commands' events are visible --------------------
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    bm = &evt_c.Ports.Payload;
    bm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
    rc = CFE_EVS_EnableEventTypeCmd(&evt_c.Ports);
    S("evt_enatype rc=");
    D(rc);
    S("\n");
    bm->BitMask = 0x80;
    // out of range: only four bits are defined
    rc = CFE_EVS_EnableEventTypeCmd(&evt_c.Ports);
    S("evt_enatype_badmask rc=");
    D(rc);
    S("\n");
    // --- the simple commands ---------------------------------------------------------
    rc = CFE_EVS_NoopCmd(&evt_c.Buf);
    S("evt_noop rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ResetCountersCmd(&evt_c.Buf);
    S("evt_rstcnt rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ClearLogCmd(&evt_c.Buf);
    S("evt_clearlog rc=");
    D(rc);
    S(" next=");
    D(CFE_EVS_Global.EVS_LogPtr->Next);
    S("\n");
    // --- the ports and the format mode -----------------------------------------------
    bm->BitMask = CFE_EVS_PORT2_BIT;
    rc = CFE_EVS_EnablePortsCmd(&evt_c.Ports);
    S("evt_enaport rc=");
    D(rc);
    S(" port=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort);
    S("\n");
    rc = CFE_EVS_DisablePortsCmd(&evt_c.Ports);
    S("evt_disport rc=");
    D(rc);
    S(" port=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort);
    S("\n");
    bm->BitMask = 0x80;
    rc = CFE_EVS_EnablePortsCmd(&evt_c.Ports);
    S("evt_enaport_badmask rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_DisablePortsCmd(&evt_c.Ports);
    S("evt_disport_badmask rc=");
    D(rc);
    S("\n");
    bm->BitMask = CFE_EVS_DEBUG_BIT;
    rc = CFE_EVS_DisableEventTypeCmd(&evt_c.Ports);
    S("evt_distype rc=");
    D(rc);
    S("\n");
    bm->BitMask = 0x80;
    rc = CFE_EVS_DisableEventTypeCmd(&evt_c.Ports);
    S("evt_distype_badmask rc=");
    D(rc);
    S("\n");
    bm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
    CFE_EVS_EnableEventTypeCmd(&evt_c.Ports);
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    evt_c.Fmt.Payload.MsgFormat = CFE_EVS_MsgFormat_SHORT;
    rc = CFE_EVS_SetEventFormatModeCmd(&evt_c.Fmt);
    S("evt_fmt_short rc=");
    D(rc);
    S(" mode=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode);
    S("\n");
    evt_c.Fmt.Payload.MsgFormat = CFE_EVS_MsgFormat_LONG;
    rc = CFE_EVS_SetEventFormatModeCmd(&evt_c.Fmt);
    S("evt_fmt_long rc=");
    D(rc);
    S(" mode=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode);
    S("\n");
    evt_c.Fmt.Payload.MsgFormat = 9;
    rc = CFE_EVS_SetEventFormatModeCmd(&evt_c.Fmt);
    S("evt_fmt_bad rc=");
    D(rc);
    S("\n");
    // --- the per-app commands --------------------------------------------------------
    // Each of the eight takes an app NAME and runs the same four-way branch on what
    // EVS_GetApplicationInfo says: found, not registered, illegal id, no such app. The driver's
    // CFE_ES_GetAppIDByName answers for "CFE_EVS" and refuses everything else, so three of the
    // four are reachable by name alone.
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    anbm = &evt_c.AppType.Payload;
    StrNCpy(anbm->AppName, "CFE_EVS", CFE_MISSION_MAX_API_LEN - 1);
    anbm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
    rc = CFE_EVS_EnableAppEventTypeCmd(&evt_c.AppType);
    S("evt_enaapptype rc=");
    D(rc);
    S("\n");
    anbm->BitMask = CFE_EVS_DEBUG_BIT;
    rc = CFE_EVS_DisableAppEventTypeCmd(&evt_c.AppType);
    S("evt_disapptype rc=");
    D(rc);
    S("\n");
    anbm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
    CFE_EVS_EnableAppEventTypeCmd(&evt_c.AppType);
    anbm->BitMask = 0x80;
    rc = CFE_EVS_EnableAppEventTypeCmd(&evt_c.AppType);
    S("evt_enaapptype_badmask rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_DisableAppEventTypeCmd(&evt_c.AppType);
    S("evt_disapptype_badmask rc=");
    D(rc);
    S("\n");
    anbm->BitMask = CFE_EVS_ALL_EVENT_TYPES_MASK;
    StrNCpy(anbm->AppName, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
    rc = CFE_EVS_EnableAppEventTypeCmd(&evt_c.AppType);
    S("evt_enaapptype_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_DisableAppEventTypeCmd(&evt_c.AppType);
    S("evt_disapptype_unreg rc=");
    D(rc);
    S("\n");
    StrNCpy(anbm->AppName, "NOPE", CFE_MISSION_MAX_API_LEN - 1);
    rc = CFE_EVS_EnableAppEventTypeCmd(&evt_c.AppType);
    S("evt_enaapptype_nosuch rc=");
    D(rc);
    S("\n");
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    an = &evt_c.AppEvt.Payload;
    StrNCpy(an->AppName, "CFE_EVS", CFE_MISSION_MAX_API_LEN - 1);
    rc = CFE_EVS_DisableAppEventsCmd(&evt_c.AppEvt);
    ap = EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID);
    S("evt_disappevt rc=");
    D(rc);
    S(" active=");
    D(ap->ActiveFlag);
    S("\n");
    rc = CFE_EVS_EnableAppEventsCmd(&evt_c.AppEvt);
    ap = EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID);
    S("evt_enaappevt rc=");
    D(rc);
    S(" active=");
    D(ap->ActiveFlag);
    S("\n");
    rc = CFE_EVS_ResetAppCounterCmd(&evt_c.AppEvt);
    S("evt_rstappcnt rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ResetAllFiltersCmd(&evt_c.AppEvt);
    S("evt_rstallfilt rc=");
    D(rc);
    S("\n");
    StrNCpy(an->AppName, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
    rc = CFE_EVS_DisableAppEventsCmd(&evt_c.AppEvt);
    S("evt_disappevt_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_EnableAppEventsCmd(&evt_c.AppEvt);
    S("evt_enaappevt_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ResetAppCounterCmd(&evt_c.AppEvt);
    S("evt_rstappcnt_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ResetAllFiltersCmd(&evt_c.AppEvt);
    S("evt_rstallfilt_unreg rc=");
    D(rc);
    S("\n");
    // --- the filter commands ----------------------------------------------------------
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    aneidm = &evt_c.Filter.Payload;
    StrNCpy(aneidm->AppName, "CFE_EVS", CFE_MISSION_MAX_API_LEN - 1);
    aneidm->EventID = 77;
    aneidm->Mask = 0x00ff;
    rc = CFE_EVS_AddEventFilterCmd(&evt_c.Filter);
    S("evt_addfilt rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_AddEventFilterCmd(&evt_c.Filter);
    S("evt_addfilt_dup rc=");
    D(rc);
    S("\n");
    aneidm->Mask = 0x000f;
    rc = CFE_EVS_SetFilterCmd(&evt_c.Filter);
    S("evt_setfilt rc=");
    D(rc);
    S("\n");
    aneidm->EventID = 999;
    rc = CFE_EVS_SetFilterCmd(&evt_c.Filter);
    S("evt_setfilt_noevt rc=");
    D(rc);
    S("\n");
    StrNCpy(aneidm->AppName, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
    rc = CFE_EVS_SetFilterCmd(&evt_c.Filter);
    S("evt_setfilt_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_AddEventFilterCmd(&evt_c.Filter);
    S("evt_addfilt_unreg rc=");
    D(rc);
    S("\n");
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    aneid = &evt_c.RstFilter.Payload;
    StrNCpy(aneid->AppName, "CFE_EVS", CFE_MISSION_MAX_API_LEN - 1);
    aneid->EventID = 77;
    rc = CFE_EVS_ResetFilterCmd(&evt_c.RstFilter);
    S("evt_rstfilt rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_DeleteEventFilterCmd(&evt_c.RstFilter);
    S("evt_delfilt rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_DeleteEventFilterCmd(&evt_c.RstFilter);
    S("evt_delfilt_again rc=");
    D(rc);
    S("\n");
    aneid->EventID = 999;
    rc = CFE_EVS_ResetFilterCmd(&evt_c.RstFilter);
    S("evt_rstfilt_noevt rc=");
    D(rc);
    S("\n");
    StrNCpy(aneid->AppName, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
    rc = CFE_EVS_ResetFilterCmd(&evt_c.RstFilter);
    S("evt_rstfilt_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_DeleteEventFilterCmd(&evt_c.RstFilter);
    S("evt_delfilt_unreg rc=");
    D(rc);
    S("\n");
    // fill every slot, then ask for one more
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    aneidm = &evt_c.Filter.Payload;
    StrNCpy(aneidm->AppName, "CFE_EVS", CFE_MISSION_MAX_API_LEN - 1);
    for (cc = 0; cc < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS + 1; cc++) {
      aneidm->EventID = 200 + cc;
      rc = CFE_EVS_AddEventFilterCmd(&evt_c.Filter);
      S("evt_addfilt[");
      D(cc);
      S("] rc=");
      D(rc);
      S("\n");
    }
    // --- the two file commands, through the translated fs module ---------------------
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    StrNCpy(evt_c.AppData.Payload.AppDataFilename, "/ram/evs_app.dat", CFE_MISSION_MAX_PATH_LEN - 1);
    fs_open_fail = 0;
    fs_wr_left = -1;
    fs_fd = 0;
    fs_len = 0;
    fs_pos = 0;
    rc = CFE_EVS_WriteAppDataFileCmd(&evt_c.AppData);
    S("evt_wrapp rc=");
    D(rc);
    S(" len=");
    D(fs_len);
    S("\n");
    fs_dump("evt_wrapp_bytes", 16);
    fs_open_fail = 1;
    rc = CFE_EVS_WriteAppDataFileCmd(&evt_c.AppData);
    S("evt_wrapp_nocreate rc=");
    D(rc);
    S("\n");
    fs_open_fail = 0;
    fs_wr_left = 4;
    rc = CFE_EVS_WriteAppDataFileCmd(&evt_c.AppData);
    S("evt_wrapp_hdrfail rc=");
    D(rc);
    S("\n");
    fs_wr_left = 80;
    rc = CFE_EVS_WriteAppDataFileCmd(&evt_c.AppData);
    S("evt_wrapp_wrfail rc=");
    D(rc);
    S("\n");
    fs_wr_left = -1;
    // --- housekeeping: the packet EVS downlinks ------------------------------------
    ta_transmits = 0;
    rc = CFE_EVS_SendHkCmd(&evt_c.Buf);
    S("evt_hk rc=");
    D(rc);
    S(" tx=");
    D(ta_transmits);
    S("\n");
    S("evt_hk_app0 id=");
    D(CFE_ResourceId_ToInteger(CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppID));
    S(" en=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppEnableStatus);
    S(" sent=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppMessageSentCounter);
    S(" sq=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[0].AppMessageSquelchedCounter);
    S("\n");
    // entry 1 is the first UNUSED slot, and entries 2.. are what upstream note #10 is about:
    // the clear loop never advances, so they keep the previous cycle's contents.
    S("evt_hk_app1 id=");
    D(CFE_ResourceId_ToInteger(CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[1].AppID));
    S("  app2 id=");
    D(CFE_ResourceId_ToInteger(CFE_EVS_Global.EVS_TlmPkt.Payload.AppData[2].AppID));
    S("\n");
    // --- cfe_evs_dispatch.c ----------------------------------------------------------
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    CFE_MSG_Init(&evt_c.Ports.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID), sizeof(CFE_EVS_EnablePortsCmd_t));
    vok = CFE_EVS_VerifyCmdLength(&evt_c.Buf.Msg, sizeof(CFE_EVS_EnablePortsCmd_t));
    S("evt_len_ok ");
    D(vok);
    S("\n");
    vok = CFE_EVS_VerifyCmdLength(&evt_c.Buf.Msg, 4242);
    S("evt_len_bad ");
    D(vok);
    S("\n");
    for (cc = 0; cc <= 21; cc++) {
      CFE_MSG_SetFcnCode(&evt_c.Buf.Msg, cc);
      S("evt_cc ");
      D(cc);
      S(":\n");
      CFE_EVS_ProcessGroundCommand(&evt_c.Buf, CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID));
    }
    S("evt_cc_after cc=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.CommandCounter);
    S(" cec=");
    D(CFE_EVS_Global.EVS_TlmPkt.Payload.CommandErrorCounter);
    S("\n");
    // and the packet router: the housekeeping id, the command id, and one that is neither
    CFE_MSG_SetFcnCode(&evt_c.Buf.Msg, CFE_EVS_NOOP_CC);
    CFE_MSG_SetMsgId(&evt_c.Buf.Msg, CFE_SB_ValueToMsgId(CFE_EVS_SEND_HK_MID));
    S("evt_pipe_hk:\n");
    CFE_EVS_ProcessCommandPacket(&evt_c.Buf);
    CFE_MSG_SetMsgId(&evt_c.Buf.Msg, CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID));
    CFE_MSG_SetSize(&evt_c.Buf.Msg, sizeof(CFE_EVS_NoopCmd_t));
    S("evt_pipe_cmd:\n");
    CFE_EVS_ProcessCommandPacket(&evt_c.Buf);
    CFE_MSG_SetMsgId(&evt_c.Buf.Msg, CFE_SB_ValueToMsgId(0x1EEE));
    S("evt_pipe_unknown:\n");
    CFE_EVS_ProcessCommandPacket(&evt_c.Buf);
    // --- the log commands and CleanUpApp -------------------------------------------
    MemSet(&evt_c, 0, sizeof(evt_c_u));
    evt_c.LogMode.Payload.LogMode = CFE_EVS_LogMode_DISCARD;
    rc = CFE_EVS_SetLogModeCmd(&evt_c.LogMode);
    S("evt_setlogmode rc=");
    D(rc);
    S(" mode=");
    D(CFE_EVS_Global.EVS_LogPtr->LogMode);
    S("\n");
    rc = CFE_EVS_CleanUpApp(99);
    S("evt_cleanup_bad rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_CleanUpApp(1);
    ap = EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID);
    S("evt_cleanup rc=");
    D(rc);
    S(" used=");
    D(EVS_AppDataIsUsed(ap));
    S("\n");
    // --- cfe_evs_objtab.c ----------------------------------------------------------
    S("evt_objtab ");
    S(CFE_EVS_ModuleEntry.Name);
    S(" ");
    D(CFE_EVS_ModuleEntry.EarlyInit == NULL);
    S(" ");
    D(CFE_EVS_ModuleEntry.TaskMain == NULL);
    S(" ");
    D(CFE_EVS_ModuleEntry.AppCleanupCb == NULL);
    S(" ");
    D(CFE_EVS_ModuleEntry.Priority);
    S(" ");
    D(CFE_EVS_ModuleEntry.StackSize);
    S("\n");
  }
  return 0;
}
