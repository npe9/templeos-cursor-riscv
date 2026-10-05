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
#include "/Kernel/Cfs/cfe/cfe_time_tone.HC"
#include "/Kernel/Cfs/cfe/cfe_time_task.HC"
#include "/Kernel/Cfs/cfe/cfe_time_dispatch.HC"
#include "/Kernel/Cfs/cfe/cfe_time_objtab.HC"
// cfe_es_msg.HC before SB, because cfe_sb_task.c sizes a pool block with
// sizeof(CFE_ES_RestartCmd_t) -- NASA's own `#include "cfe_es_msg.h"` in that file.
#include "/Kernel/Cfs/cfe/cfe_es_global.HC"
#include "/Kernel/Cfs/cfe/cfe_es_msg.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_global.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_buf.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_init.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_priv.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_api.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_task.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_dispatch.HC"
#include "/Kernel/Cfs/cfe/cfe_sb_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_es_crc.HC"
#include "/Kernel/Cfs/cfe/cfe_es_generic_pool.HC"
#include "/Kernel/Cfs/cfe/cfe_es_syslog.HC"
#include "/Kernel/Cfs/cfe/cfe_es_mempool.HC"
#include "/Kernel/Cfs/cfe/cfe_es_resource.HC"
#include "/Kernel/Cfs/cfe/cfe_es_api.HC"
#include "/Kernel/Cfs/osal/osapi_heap_decl.HC"
#include "/Kernel/Cfs/osal/osapi_module_decl.HC"
#include "/Kernel/Cfs/osal/osapi_filesys_decl.HC"
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
// CFE_ES_WriteToSysLog: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
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
I64 fs_mut_create, fs_mut_take, fs_mut_give;
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
  // A READ-ONLY OPEN MUST NOT TRUNCATE, which this stub used to do unconditionally -- it never
  // mattered until cfe_es_startupscript.c became the first thing in the port to OPEN A FILE AND
  // READ IT. Every other caller writes, so resetting the length was indistinguishable from
  // correct. The startup script is staged into fs_data before the call and would have been
  // erased by it.
  if (access_mode != OS_READ_ONLY)
    fs_len = 0;
  fs_pos = 0;
  return OS_SUCCESS;
}
// Declared early because three of the OSAL delete stubs that call it are defined above it --
// they belong with the subsystems whose witnesses they carry, not with the object table.
U0 es_obj_mark(U32 object_id);
I32 OS_close(U32 filedes)
{
  fs_fd = 0;
  es_obj_mark(filedes);
  // also an OSAL object a dying task may own -- see es_obj_mark
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
// ES's shared-data lock, counted. See the note beside the removed stub pair further down: the
// real CFE_ES_LockSharedData takes CFE_ES_Global.SharedDataMutex, so the witness for "how many
// times did ES lock" has to live here, in the mutex stub, and has to tell ES's mutex apart from
// the FS and pool mutexes that come through the same stub.
#define ES_SHARED_MUTEX_ID 0x1E5
// ES's three BASED id spaces. Up here with the mutex id rather than beside es_ctx_init below,
// because the ES stubs that hand back ids are defined before it.
#define ES_CTX_APPID(slot) (CFE_ES_APPID_BASE + (slot))
#define ES_LIBID(slot)     (CFE_ES_LIBID_BASE + (slot))
#define ES_CTRID(slot)     (CFE_ES_COUNTID_BASE + (slot))
I64 es_lock_takes, es_lock_gives;
I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options)
{
  ++fs_mut_create;
  *sem_id = 3;
  return fs_mut_create_rc;
}

I32 OS_MutSemTake(U32 sem_id)
{
  if (sem_id == ES_SHARED_MUTEX_ID) {
    ++es_lock_takes;
  }
  ++fs_mut_take;
  return fs_mut_take_rc;
}

I32 OS_MutSemGive(U32 sem_id)
{
  if (sem_id == ES_SHARED_MUTEX_ID) {
    ++es_lock_gives;
  }
  ++fs_mut_give;
  return fs_mut_give_rc;
}
// Who the caller is USED TO BE THIS VARIABLE. cfe_es_api.c is gated, so CFE_ES_GetAppID is
// real and answers from the ES tables -- see es_set_ctx and es_ctx_init below, which is where
// the three paths through CFE_EVS_SendEvent (a registered app, an unregistered one, an id out
// of range) are selected now.
// CFE_ES_GetAppID: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_ES_BackgroundWakeup: STUB REMOVED -- its source is gated, the real one runs.
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
// Two lowercase hex digits, zero padded, to match the C oracle's %02x. SB's pipe-options
// events print the byte that way.
U0 Hx2b(I64 v)
{
  U8 *hx = "0123456789abcdef";
  U8 one[2];
  I64 i;
  one[1] = 0;
  for (i = 4; i >= 0; i -= 4) {
    one[0] = hx[(v >> i) & 15];
    S(one);
  }
}
// A CONSTANT IN THE DRIVER IS A CONSTANT WITH NO GATE BEHIND IT. check_constants.py reads
// Kernel/Cfs/**.HC and nothing else, so the four names this exercise needs
// (CFE_SB_INVALID_PIPE, CFE_ES_APPID_BASE and the two offsets under them) live in
// cfe_sb_api.HC beside the code that defines the rest of SB's public surface, where they are
// compared against NASA's. The fifth, CFE_SB_INVALID_MSG_ID, is NOT a constant here at all:
// cfe_sb_msgid.HC already spells it as CFE_SB_InvalidMsgId(), because the C is a compound
// literal of a class type, and a second spelling would be free to drift from the first.
U32 sb_api_idx;
// THE COMMAND BUFFER MUST BE THE SIZE OF THE LARGEST COMMAND, not of the one being built. The
// first version of the SB task exercise declared this as a bare CFE_SB_EnableRouteCmd_t -- 20
// bytes -- and the three file commands' handlers read CmdPtr->Filename, 64 bytes at offset 8,
// so 52 bytes of it came from whatever was next on the stack. The C half declares a union of
// every command type (72 bytes, CFE_SB_WriteRoutingInfoCmd_t being the largest) and memsets the
// whole thing, so it read 64 zeroes and took the default-filename path.
//
// AND THE TRANSCRIPT AGREED ANYWAY, which is the part worth recording: the garbage happened to
// have a zero first byte, so both sides took the same branch and printed the same file name.
// Exactly the failure mode check_padding exists for -- both sides read the field they wrote --
// except here one side was not reading its own memory at all.
// ES's STATE is defined in cfe_es_global.HC (beside its type); what the driver supplies is the
// RESET AREA it points at. The system log and its three indices live in memory that survives a
// processor reset, not in CFE_ES_Global, so nothing can be logged until ResetDataPtr is aimed.
CFE_ES_ResetData_t es_reset_area;
// cfe_es_api.c and cfe_es_task.c are not gated, so three of their functions are stubs on BOTH
// halves -- the same temporary arrangement CFE_SB_SendSubscriptionReport had until
// cfe_sb_task.c landed, and it goes away the same way.
//
// The lock pair is a COUNTER rather than a no-op on purpose: the syslog's whole design is about
// which reads happen inside it (the first block) and which deliberately do not (every block
// after), and a transcript that cannot see the difference could not tell a correct dump from
// one that held the lock for the entire file.
// THE LOCK PAIR IS REAL NOW: cfe_es_api.c is gated, and CFE_ES_LockSharedData takes
// OS_MutSemTake(CFE_ES_Global.SharedDataMutex) for real. The counters above did not go away
// with the stub -- they MOVED into the mutex stub, which bumps them only for ES's own mutex id.
// That keeps the syslog-dump probe measuring the thing it was written to measure (exactly one
// take/give pair however many blocks get written) and now measures it through NASA's code
// instead of through a stub that could not get it wrong.
//
// ES_SHARED_MUTEX_ID is the id the startup sequence plants in CFE_ES_Global.SharedDataMutex. It
// has to be distinct from the FS and pool mutexes, which share the same stub, or the counters
// would pick up their traffic too.
// CFE_ES_FileWriteByteCntErr: STUB REMOVED -- cfe_es_task.c is gated, the real one runs and
// raises CFE_ES_FILEWRITE_ERR_EID instead of printing. es_bytecnt_errs went with it; what
// counts a short write now is the event in the transcript.
// ---- what cfe_es_api.c calls and nothing gated defines ---------------------------------------
// cfe_es_cds.c, cfe_es_cds_mempool.c, cfe_es_apps.c and cfe_es_erlog.c are all untranslated, so
// nineteen of their functions are stubs here and in the C half, written to match. This is the
// arrangement CFE_SB_SendSubscriptionReport had until cfe_sb_task.c landed, and it comes apart
// the same way: each stub disappears from BOTH halves on the commit that gates its source.
//
// CFE_ES_Global.CDSIsAvailable IS ZERO in this driver and stays that way, which is why the CDS
// stubs can be this thin: CFE_ES_RegisterCDS, CFE_ES_GetCDSBlockIDByName and
// CFE_ES_GetCDSBlockName all return CFE_ES_NOT_IMPLEMENTED before they reach the registry, and
// the exercise checks that they do.
I64 es_cds_locks, es_cds_unlocks, es_starttasks, es_restarts;
I64 es_stats;
I32 es_stat_rc;
// what OS_stat says: Restart/Reload branch on it
I32 es_starttask_rc;
I64 es_taskdeletes, es_taskexits;
I32 es_taskdelete_rc;
// CFE_ES_WriteToERLog: STUB REMOVED -- its source is gated, the real one runs.
// NASA's CFE_PSP_Restart does not return. This one does, because the code AFTER it in
// CFE_ES_ResetCFE is part of what the transcript compares -- the "CFE_PSP_Restart returned"
// syslog line and the CFE_ES_NOT_IMPLEMENTED that follows exist for exactly this case.
U0 CFE_PSP_Restart(U32 ResetType)
{
  ++es_restarts;
  S("psp_restart ");
  D(ResetType);
  S("\n");
}

I32 OS_stat(U8 *path, os_fstat_t *filestats)
{
  ++es_stats;
  S("os_stat ");
  S(path);
  S(" rc=");
  D(es_stat_rc);
  S("\n");
  return es_stat_rc;
}

I32 OS_TaskDelete(U32 task_id)
{
  ++es_taskdeletes;
  S("os_taskdelete ");
  D(task_id);
  S(" rc=");
  D(es_taskdelete_rc);
  S("\n");
  return es_taskdelete_rc;
}
// NASA's OS_TaskExit does not return either, and the same reasoning applies: CFE_ES_ExitApp and
// CFE_ES_ExitChildTask both have a `return` after it with NASA's own comment saying the code is
// reached "except under unit test". This driver IS that case.
U0 OS_TaskExit()
{
  ++es_taskexits;
  S("os_taskexit\n");
}
// THE DRIVER'S OSAL IDS ARE BARE 1-BASED INTEGERS, so index = id - 1 and osal id 1 lands on
// table slot 0 -- which is the convention the resource-table probe already assumed when it
// marked TaskTable[0] used for CFE_ES_TaskId_FromOSAL(1). The real OSAL strips type bits and
// takes a modulus; that belongs to the OSAL translation and its own gate, not to this one.
I32 OS_ObjectIdToArrayIndex(U32 idtype, U32 object_id, U32 *ArrayIndex)
{
  if (object_id == 0 || object_id > OS_MAX_TASKS) {
    return OS_ERROR;
  }
  *ArrayIndex = object_id - 1;
  return OS_SUCCESS;
}
// ---- WHAT cfe_es_start.c NEEDS: THE VOLATILE DISK AND TWO MORE PIECES OF BOARD --------------
//
// THE RAM DISK IS SIMULATED, not recorded, for the same reason the CDS is: the interesting code
// is the part that decides whether to format it. A power-on reset calls OS_mkfs, a processor
// reset calls OS_initfs and falls back to OS_mkfs, and a processor reset whose disk is over
// CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED full unmounts, removes, re-makes and re-mounts it.
// Tracking "does a volume exist" and "is it mounted" in two flags is enough to drive all of
// that, and the block counts are steerable so the percentage is a knob.
//
// It is NOT a file system. Nothing is stored; OS_mkfs says a volume now exists and OS_mount says
// it is reachable. cFE never writes to the RAM disk through these -- it writes through
// OS_OpenCreate, which this driver simulates separately.
// This block sits ABOVE the include of cfe_es_start.HC, which is where the constant is named,
// so it is guarded here too -- one definition per name, whichever comes first.
#ifndef CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE
#define CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE 512
#endif
I64 es_vol_exists;
// a volume has been made (mkfs or initfs succeeded)
I64 es_vol_mounted;
I64 es_mkfs_calls, es_initfs_calls, es_mount_calls, es_unmount_calls, es_rmfs_calls;
I32 es_mkfs_rc;
I32 es_initfs_rc;
I32 es_mount_rc;
I32 es_unmount_rc;
I32 es_rmfs_rc;
I32 es_statvol_rc;
// The free-space check is `(blocks_free * 100) / total_blocks`, so these two ARE the percentage.
// total_blocks of 0 takes the error arm, because the division would be by zero.
I64 es_vol_total_blocks;
I64 es_vol_blocks_free;
I32 OS_mkfs(U8 *address, U8 *devname, U8 *volname, I64 blocksize, I64 numblocks)
{
  ++es_mkfs_calls;
  S("os_mkfs ");
  S(devname);
  S(" ");
  S(volname);
  S(" bs=");
  D(blocksize);
  S(" n=");
  D(numblocks);
  S(" rc=");
  D(es_mkfs_rc);
  S("\n");
  if (es_mkfs_rc == OS_SUCCESS) {
    es_vol_exists = 1;
  }
  return es_mkfs_rc;
}

I32 OS_initfs(U8 *address, U8 *devname, U8 *volname, I64 blocksize, I64 numblocks)
{
  ++es_initfs_calls;
  S("os_initfs ");
  S(devname);
  S(" ");
  S(volname);
  S(" rc=");
  D(es_initfs_rc);
  S("\n");
  if (es_initfs_rc == OS_SUCCESS) {
    es_vol_exists = 1;
  }
  return es_initfs_rc;
}

I32 OS_mount(U8 *devname, U8 *mountpoint)
{
  ++es_mount_calls;
  S("os_mount ");
  S(devname);
  S(" -> ");
  S(mountpoint);
  S(" rc=");
  D(es_mount_rc);
  S("\n");
  if (es_mount_rc == OS_SUCCESS) {
    es_vol_mounted = 1;
  }
  return es_mount_rc;
}

I32 OS_unmount(U8 *mountpoint)
{
  ++es_unmount_calls;
  S("os_unmount ");
  S(mountpoint);
  S(" rc=");
  D(es_unmount_rc);
  S("\n");
  if (es_unmount_rc == OS_SUCCESS) {
    es_vol_mounted = 0;
  }
  return es_unmount_rc;
}

I32 OS_rmfs(U8 *devname)
{
  ++es_rmfs_calls;
  S("os_rmfs ");
  S(devname);
  S(" rc=");
  D(es_rmfs_rc);
  S("\n");
  if (es_rmfs_rc == OS_SUCCESS) {
    es_vol_exists = 0;
  }
  return es_rmfs_rc;
}

I32 OS_FileSysStatVolume(U8 *name, OS_statvfs_t *statbuf)
{
  S("os_statvol ");
  S(name);
  S(" rc=");
  D(es_statvol_rc);
  S("\n");
  statbuf->block_size = CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE;
  statbuf->total_blocks = es_vol_total_blocks;
  statbuf->blocks_free = es_vol_blocks_free;
  return es_statvol_rc;
}
// CFE_PSP_AttachExceptions installs the trap vectors -- NASA's own comment at the call site is
// "Install exception Handlers ( Placeholder )", so it is a placeholder upstream too. And
// CFE_PSP_GetVolatileDiskMem hands back the RAM the volatile file system is built in: this
// returns a real buffer, because OS_mkfs is handed the address and a NULL would be a different
// test than the one intended.
// ---- A REAL CORE OBJECT TABLE, for CFE_ES_CreateObjects --------------------------------------
// CFE_CORE_MODULE_OBJTAB is empty in this configuration -- element 0 is its own NULL terminator
// -- so both phases of CreateObjects would walk nothing. These two entries are what make them
// run: one library-only module (an EarlyInit and no TaskMain, so phase 2 skips it) and one with
// a TaskMain, which takes a real app-table slot as a CORE app.
//
// The TaskMain is never CALLED -- this driver's OS_TaskCreate does not run entry points, for the
// reason recorded there -- so it only has to be a valid address.
I64 es_core_early_calls, es_core_taskmain_calls;
I32 es_core_early_rc;
I32 es_core_early_init()
{
  ++es_core_early_calls;
  S("es_core_earlyinit rc=");
  D(es_core_early_rc);
  S("\n");
  return es_core_early_rc;
}

U0 es_core_taskmain()
{
  ++es_core_taskmain_calls;
}
Target_ObjectTable es_core_entry_lib = {"COREL", &es_core_early_init, NULL, NULL, 0, 0};
Target_ObjectTable es_core_entry_task = {"CORET", &es_core_early_init, &es_core_taskmain, NULL, 70, 4096};
// CFE_ES_Main memsets the whole global, so the driver's planted state is saved around it.
CFE_ES_Global_t es_global_save;
I64 es_attachexc;
U8 es_ramdisk_mem[4096];
I32 es_voldiskmem_rc;
U0 CFE_PSP_AttachExceptions()
{
  ++es_attachexc;
  S("psp_attachexc\n");
}

I32 CFE_PSP_GetVolatileDiskMem(U64 *PtrToVolDisk, U32 *SizeOfVolDisk)
{
  *PtrToVolDisk = es_ramdisk_mem;
  *SizeOfVolDisk = 4096;
  return es_voldiskmem_rc;
}
// ---- WHAT cfe_es_apps.c NEEDS FROM OSAL, which this driver does not compile -----------------
// OSAL has its own differential driver (run_osal_xlat_smoke.sh) and its own transcript; here its
// public API is stubbed, the same way CFE_PSP_* is. Every one of these stands in for a real OS
// service and will still be a stub when every line of cFE is translated.
//
// THE OBJECT TABLE IS THE INTERESTING ONE. CFE_ES_CleanupTaskResources cannot be reached at all
// without it: the real OS_ForEachObject walks the OS's own records and hands every object whose
// creator is a given task to a callback, which is how a dead task's queues, semaphores, timers
// and open files get released when nothing recorded that it made them. There is no OS here, so
// the objects are a table of (id, type, deleted) and OS_ForEachObject walks that. It is enough
// to drive all eight arms of the callback's switch, the per-type error codes, and -- by
// refusing a delete -- the "number of found objects is not trending downward" guard.
#ifndef OS_OBJECT_TYPE_UNDEFINED
#define OS_OBJECT_TYPE_UNDEFINED 0x00
#endif
// OS_OBJECT_TYPE_OS_DIR is a kind cfe_es_apps.c's cleanup callback does NOT handle, which is the
// point: its default arm must count the object neither as found nor as a failure. The
// translation names the eight it does handle; this is the ninth, named here only to drive that
// arm, and tools/cfs/check_constants.py compares it against NASA's enumerator either way.
#ifndef OS_OBJECT_TYPE_OS_DIR
#define OS_OBJECT_TYPE_OS_DIR 0x07
#endif
#define ES_OBJS_MAX 8
U32 es_obj_id[ES_OBJS_MAX];
U32 es_obj_type[ES_OBJS_MAX];
I64 es_obj_gone[ES_OBJS_MAX];
I64 es_objs_n;
I32 es_objdel_rc;
I64 es_foreach_calls;
U0 es_obj_add(U32 id, U32 type)
{
  es_obj_id[es_objs_n] = id;
  es_obj_type[es_objs_n] = type;
  es_obj_gone[es_objs_n] = 0;
  ++es_objs_n;
}

U0 es_objs_clear()
{
  es_objs_n = 0;
  es_objdel_rc = OS_SUCCESS;
}
// Marks the object gone. FOUR OF THE SIX DELETE ENTRY POINTS ALREADY EXISTED in this driver --
// OS_close for the file simulation, OS_BinSemDelete for the background task, OS_QueueDelete for
// SB's pipe queues and OS_MutSemDelete for ES's mempool -- each with witnesses an existing probe
// reads. So they are not replaced; they call this, and keep their own return value. Only the two
// that did not exist carry the refusal knob.
//
// OS_QueueDelete DELIBERATELY DOES NOT MARK. Its own body returns OS_ERR_INVALID_ID for an id
// that is not one of SB's created queues, which an object-table id never is -- and that is the
// CFE_ES_QUEUE_DELETE_ERR arm of the cleanup callback, reached for free and honestly.
U0 es_obj_mark(U32 object_id)
{
  I64 i;
  for (i = 0; i < es_objs_n; ++i) {
    if (es_obj_id[i] == object_id) {
      es_obj_gone[i] = 1;
    }
  }
}

U0 OS_ForEachObject(U32 creator_id, U0 (*callback_ptr)(U32, U8 *), U8 *callback_arg)
{
  I64 i;
  ++es_foreach_calls;
  S("os_foreach creator=");
  D(creator_id);
  S(" n=");
  D(es_objs_n);
  S("\n");
  for (i = 0; i < es_objs_n; ++i) {
    if (!es_obj_gone[i]) {
      (*callback_ptr)(es_obj_id[i], callback_arg);
    }
  }
}

U32 OS_IdentifyObject(U32 object_id)
{
  I64 i;
  for (i = 0; i < es_objs_n; ++i) {
    if (es_obj_id[i] == object_id) {
      return es_obj_type[i];
    }
  }
  return OS_OBJECT_TYPE_UNDEFINED;
}

I32 OS_CountSemDelete(U32 sem_id)
{
  I32 rc = es_objdel_rc;
  S("os_countsemdelete ");
  D(sem_id);
  S(" rc=");
  D(rc);
  S("\n");
  if (rc != OS_SUCCESS) {
    return rc;
  }
  es_obj_mark(sem_id);
  return OS_SUCCESS;
}

I32 OS_TimerDelete(U32 timer_id)
{
  I32 rc = es_objdel_rc;
  S("os_timerdelete ");
  D(timer_id);
  S(" rc=");
  D(rc);
  S("\n");
  if (rc != OS_SUCCESS) {
    return rc;
  }
  es_obj_mark(timer_id);
  return OS_SUCCESS;
}
// THE LOADER, which is the one real piece of hardware-adjacent machinery cFE cannot do without
// and which this port has no equivalent of yet: there is no dlopen here and no ELF loader in the
// guest. So a load succeeds or fails on command and hands back a made-up module id, and a symbol
// lookup hands back a made-up address. Both are steerable because CFE_ES_LoadModule's three
// failure paths -- load failed, symbol missing, unload-after-failure failed -- are the bulk of
// what it does.
I64 es_modloads, es_modunloads, es_modlookups, es_modinfos;
I32 es_modload_rc;
I32 es_modunload_rc;
I32 es_modlookup_rc;
I32 es_modinfo_rc;
U32 es_modinfo_valid;
I32 OS_ModuleLoad(U32 *module_id, U8 *module_name, U8 *filename, U32 flags)
{
  ++es_modloads;
  S("os_moduleload ");
  S(module_name);
  S(" ");
  S(filename);
  S(" flags=");
  D(flags);
  S(" rc=");
  D(es_modload_rc);
  S("\n");
  if (es_modload_rc == OS_SUCCESS) {
    *module_id = 0x6660 + es_modloads;
  }
  return es_modload_rc;
}

I32 OS_ModuleUnload(U32 module_id)
{
  ++es_modunloads;
  S("os_moduleunload ");
  D(module_id);
  S(" rc=");
  D(es_modunload_rc);
  S("\n");
  return es_modunload_rc;
}
// THE LIBRARY ENTRY POINT IS ACTUALLY CALLED, unlike an app's, so it has to be a real function.
// CFE_ES_LoadLibrary invokes the init symbol inline with the library's own id -- that is what
// makes a library a library -- while an app's entry point goes into a task record whose task
// this driver never runs. So the lookup hands back es_lib_init when a test asks for it and an
// uncallable constant otherwise.
I64 es_lib_inits;
I32 es_lib_init_rc;
U32 es_lib_init_id;
I32 es_lib_init(U32 LibId)
{
  ++es_lib_inits;
  es_lib_init_id = LibId;
  S("es_lib_init id=");
  D(es_lib_init_id);
  S(" rc=");
  D(es_lib_init_rc);
  S("\n");
  return es_lib_init_rc;
}
U64 es_modlookup_addr;
I32 OS_ModuleSymbolLookup(U32 module_id, U64 *symbol_address, U8 *symbol_name)
{
  ++es_modlookups;
  S("os_modulesymlookup ");
  S(symbol_name);
  S(" rc=");
  D(es_modlookup_rc);
  S("\n");
  if (es_modlookup_rc == OS_SUCCESS) {
    // A FIXED, FAKE ENTRY POINT by default. It must never be CALLED -- and it is not: the main
    // task entry goes into a task record this driver's OS_TaskCreate never runs. The library
    // entry point IS called, so the library test points this at es_lib_init.
    *symbol_address = es_modlookup_addr;
  }
  return es_modlookup_rc;
}

I32 OS_ModuleInfo(U32 module_id, OS_module_prop_t *module_prop)
{
  ++es_modinfos;
  S("os_moduleinfo ");
  D(module_id);
  S(" rc=");
  D(es_modinfo_rc);
  S("\n");
  if (es_modinfo_rc == OS_SUCCESS) {
    module_prop->addr.valid = es_modinfo_valid;
    module_prop->addr.code_address = 0x11110000;
    module_prop->addr.code_size = 0x1000;
    module_prop->addr.data_address = 0x22220000;
    module_prop->addr.data_size = 0x2000;
    module_prop->addr.bss_address = 0x33330000;
    module_prop->addr.bss_size = 0x3000;
  }
  return es_modinfo_rc;
}
// OS_TaskCreate: the entry function is NEVER CALLED, which is the whole reason this driver can
// run ES's app lifecycle in one thread. CFE_ES_StartAppTask passes CFE_ES_TaskEntryPoint, and
// that function polls for a task record under the lock -- running it here would deadlock on the
// shared-data mutex this same thread already holds. The task id it hands back is real enough for
// the record ES then writes.
I64 es_taskcreates;
I32 es_taskcreate_rc;
// THE ID HAS TO RESOLVE, which it did not have to before. The old CFE_ES_StartAppTask stub
// handed back 0x7770+n on purpose -- documented as "the id it returns does not resolve" -- and
// the real one LOCATES the task record for the id OSAL gives it and writes to it without a NULL
// check, because NASA's comment there is "As this is a newly-created task, this shouldn't fail."
// An id of 0, or one past OS_MAX_TASKS, makes CFE_ES_LocateTaskRecordByID return NULL and the
// MemSet that follows is a wild store. So this allocates real ids: 1-based, index = id - 1, with
// 1 reserved for the calling task (es_os_taskid).
U32 es_taskcreate_next;
I32 OS_TaskCreate(U32 *task_id, U8 *task_name, U0 (*function_pointer)(), U32 *stack_pointer, I64 stack_size, U32 priority, U32 flags)
{
  ++es_taskcreates;
  S("os_taskcreate ");
  S(task_name);
  S(" stack=");
  D(stack_size);
  S(" prio=");
  D(priority);
  S(" flags=");
  D(flags);
  S(" rc=");
  D(es_taskcreate_rc);
  S("\n");
  if (es_taskcreate_rc == OS_SUCCESS) {
    if (es_taskcreate_next > OS_MAX_TASKS) {
      es_taskcreate_next = 2;
    }
    *task_id = es_taskcreate_next;
    ++es_taskcreate_next;
  }
  return es_taskcreate_rc;
}
// CFE_PSP_SetDefaultExceptionEnvironment installs the trap handlers a new task runs under. It is
// the BOARD, like the rest of the PSP exception interface.
I64 es_setexcenv;
U0 CFE_PSP_SetDefaultExceptionEnvironment()
{
  ++es_setexcenv;
}
// CFE_ES_LockUserAppRecord: STUB REMOVED -- its source is gated, the real one runs. The copy
// that lived here was NASA's own body, kept byte for byte in behaviour precisely so that this
// swap would not move the transcript. It did not.
// CFE_ES_StartAppTask: STUB REMOVED -- its source is gated, the real one runs. It now makes a
// real task RECORD, so CFE_ES_DeleteChildTask on the id it returns no longer takes the "Task ID
// is not active" branch -- which is a transcript change the exercise had to account for.
// THE CDS GROUP: STUBS REMOVED -- cfe_es_cds.c and cfe_es_cds_mempool.c are gated, the real
// ones run. All nine of them went at once: FormCDSName, LocateCDSBlockRecordByID and ByName,
// RegisterCDSEx, LockCDS, UnlockCDS, CDSBlockWrite, CDSBlockRead and DeleteCDS. They recorded
// and refused, so the three public CDS entry points returned CFE_ES_NOT_IMPLEMENTED and the
// exercise asserted that CDSIsAvailable was 0. It is 1 now.
//
// ---- THE SIMULATED CRITICAL DATA STORE -------------------------------------------------------
//
// A CDS is non-volatile memory the processor CANNOT LOAD FROM: on a real spacecraft it is
// battery-backed RAM or an EEPROM region, reached only through CFE_PSP_ReadFromCDS and
// WriteToCDS, and its whole purpose is to still be there after a processor reset. There is no
// such device here, so it is a byte array -- and that is better than a recording stub in a way
// worth stating: THE REBUILD PATH BECOMES TESTABLE. Clearing CFE_ES_Global.CDSVars while leaving
// es_cds_store alone is exactly what a processor reset looks like to cFE, so the exercise can
// boot the CDS, write blocks, "reset", and watch CFE_ES_RebuildCDS find the registry and the
// allocator recover the blocks from the descriptors that survived. Against a stub none of that
// code could run at all.
//
// The size is small on purpose: 64 KiB is over the 36,884-byte minimum (a 36,876-byte header
// holding 512 registry entries, plus an 8-byte trailer) with room for a handful of blocks, so
// the "too small" refusal is one knob away and a full pool is reachable.
// `CFE_PSP_STATUS_C(-1)` -- the PSP's own generic failure, which the simulated store returns
// for an out-of-range offset the same way a real one would.
#ifndef CFE_PSP_ERROR
#define CFE_PSP_ERROR -1
#endif
#define ES_CDS_STORE_SIZE 65536
U8 es_cds_store[ES_CDS_STORE_SIZE];
U32 es_cds_size;
I64 es_cds_reads, es_cds_writes;
// Steerable, because every CDS function has a PSP-failure arm and nothing else can reach it.
I32 es_cds_getsize_rc;
I32 es_cds_read_rc;
I32 es_cds_write_rc;
// An offset past which writes fail, so a failure can be aimed at one step of a multi-step
// operation -- clearing the store, or writing the end signature -- rather than all of them.
U32 es_cds_write_fail_at;
I32 CFE_PSP_GetCDSSize(U32 *SizeOfCDS)
{
  *SizeOfCDS = es_cds_size;
  return es_cds_getsize_rc;
}

I32 CFE_PSP_WriteToCDS(U8 *PtrToDataToWrite, U32 CDSOffset, U32 NumBytes)
{
  ++es_cds_writes;
  if (es_cds_write_rc != CFE_PSP_SUCCESS) {
    return es_cds_write_rc;
  }
  if (CDSOffset >= es_cds_write_fail_at) {
    return CFE_PSP_ERROR;
  }
  // A real PSP bounds-checks against the device; so does this, and a refusal here is the same
  // CFE_PSP_ERROR an out-of-range offset would get on hardware.
  if (CDSOffset + NumBytes > ES_CDS_STORE_SIZE) {
    return CFE_PSP_ERROR;
  }
  MemCpy(&es_cds_store[CDSOffset], PtrToDataToWrite, NumBytes);
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_ReadFromCDS(U8 *PtrToDataFromRead, U32 CDSOffset, U32 NumBytes)
{
  ++es_cds_reads;
  if (es_cds_read_rc != CFE_PSP_SUCCESS) {
    return es_cds_read_rc;
  }
  if (CDSOffset + NumBytes > ES_CDS_STORE_SIZE) {
    return CFE_PSP_ERROR;
  }
  MemCpy(PtrToDataFromRead, &es_cds_store[CDSOffset], NumBytes);
  return CFE_PSP_SUCCESS;
}
// A PROCESSOR RESET, as cFE experiences one: the RAM copy of the CDS state is gone and the store
// is not. Everything CFE_ES_CDS_EarlyInit rebuilds comes back out of es_cds_store.
// EXACTLY EIGHT BYTES, because a CDS signature is not NUL terminated: `_CDSEnd_` occupies the
// last eight bytes of the store with nothing after it, so printing it as a string would run off
// the end of the array. The C half has no %.8s worth using either, which is the other reason
// this is a helper on both sides rather than a format.
U0 es_sig8(U8 *p)
{
  I64 i;
  for (i = 0; i < 8; i++) {
    Ch(p[i]);
  }
}
// THE EXERCISE'S BUFFERS LIVE HERE, NOT ON THE STACK, and that is a measured requirement
// rather than a preference: three local arrays (two 64-byte and one 64-byte name) declared in a
// nested block of the ES exercise function made `&CFE_ES_ComputeCRC_Algo_16_ARC` -- a function
// address in a FILE-SCOPE INITIALISER in cfe_es_crc.HC, read 500 lines earlier in the same run
// -- come back as 0, and the call through it trapped with mepc=0. Removing the three arrays and
// changing nothing else fixed it. The function's frame is already very large; this is the same
// family as the recorded deep-frame codegen bugs, and the smallest honest workaround is to not
// grow the frame. docs/HOLYC_STRUCT_LIMITS.md records it.
U8 es_cdsbuf[64];
U8 es_cdsback[64];
U8 es_cdsnm[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN];
U0 es_cds_reset()
{
  MemSet(&CFE_ES_Global.CDSVars, 0, sizeof(CFE_ES_CDS_Instance_t));
  CFE_ES_Global.CDSIsAvailable = FALSE;
}
// CFE_ES_CopyModuleBasicInfo / CopyModuleStatusInfo / CopyModuleAddressInfo: STUBS REMOVED --
// their source is gated, the real ones run. These three printed a line each and filled in NO
// fields, so AppInfo's EntryPoint, FileName, StartAddress and the six module addresses were
// whatever the callers' MemSet left. Three transcript lines go; the fields they were standing in
// for arrive, and the exercise reads them.
// ---- what cfe_es_task.c calls and nothing gated defines -------------------------------------
// The apps/CDS/perf/background/dispatch set again, plus the PSP and OSAL version calls. Each
// goes away from BOTH halves on the commit that gates its source.
I64 es_cdsdeletes, es_taskpipes, es_textseg;
I32 es_bkginit_rc, es_cdsdelete_rc;
I32 es_textseg_rc;
I64 es_perf_remaining;
I32 es_heap_rc;
// CFE_ES_AppCreate: STUB REMOVED -- its source is gated, the real one runs.
// CFE_ES_CleanUpApp: STUB REMOVED -- its source is gated, the real one runs. It lasted exactly
// one commit: cfe_es_appctrl.c was gated before cfe_es_apps.c, so this stub existed only to let
// the control-request path reach an end.
// CFE_ES_BackgroundInit: STUB REMOVED -- its source is gated, the real one runs.
// CFE_ES_DeleteCDS: STUB REMOVED -- cfe_es_cds.c is gated, the real one runs.
// CFE_ES_GetPerfLogDumpRemaining: STUB REMOVED -- its source is gated, the real one runs.
// CFE_ES_TaskPipe: STUB REMOVED -- its source is gated, the real one runs.
// The ER log's two background-writer callbacks. They are never CALLED here -- the FS
// background writer is what calls them -- but their ADDRESSES go into the state object, and
// the transcript prints whether each is NULL.
// CFE_ES_BackgroundERLogFileDataGetter: STUB REMOVED -- its source is gated, the real one runs.
// CFE_ES_BackgroundERLogFileEventHandler: STUB REMOVED -- its source is gated, the real one runs.
I32 CFE_PSP_GetCFETextSegmentInfo(U64 *PtrToCFESegment, U32 *SizeOfCFESegment)
{
  ++es_textseg;
  // A FIXED, SMALL SEGMENT, so the CRC in housekeeping is a number both halves compute from
  // the same bytes. Pointing it at real code would make the checksum depend on the COMPILER,
  // which is the one thing this comparison must not do.
  *PtrToCFESegment = "cFEtext";
  *SizeOfCFESegment = 7;
  return es_textseg_rc;
}

U0 CFE_PSP_GetVersionNumber(U8 *VersionNumbers)
{
  VersionNumbers[0] = 1;
  VersionNumbers[1] = 6;
  VersionNumbers[2] = 0;
  VersionNumbers[3] = 0;
}

U8 *CFE_PSP_GetVersionString()
{
  return "1.6.0-psp";
}

U0 OS_GetVersionNumber(U8 *VersionNumbers)
{
  VersionNumbers[0] = 6;
  VersionNumbers[1] = 1;
  VersionNumbers[2] = 0;
  VersionNumbers[3] = 0;
}

U8 *OS_GetVersionString()
{
  return "6.1.0-osal";
}
// The heap, which only CFE_ES_SendHkCmd asks about. Steerable so the else branch -- three
// zeroes in housekeeping rather than a missing packet -- is reachable.
I32 OS_HeapGetInfo(OS_heap_prop_t *heap_prop)
{
  heap_prop->free_bytes = 100000;
  heap_prop->free_blocks = 25;
  heap_prop->largest_free_block = 40000;
  return es_heap_rc;
}
// ---- what cfe_es_erlog.c, cfe_es_backgroundtask.c and cfe_es_objtab.c call -----------------
// The last three ES stubs from the apps/CDS/perf set, plus the PSP's exception interface --
// which is the BOARD, and will still be a stub when every line of cFE is translated.
I64 es_perfdumps, es_cdsearly;
I32 es_cdsearly_rc;
I64 es_exc_count;
// what CFE_PSP_Exception_GetCount reports
I32 es_exc_summary_rc;
U32 es_exc_taskid;
// 0 = "a system exception, not a task's"
I32 es_exc_ctxsize;
// <0 means "no context available"
// CFE_ES_RunAppTableScan: STUB REMOVED -- its source is gated, the real one runs.
// CFE_ES_RunPerfLogDump: STUB REMOVED -- its source is gated, the real one runs.
// CFE_ES_CDS_EarlyInit: STUB REMOVED -- cfe_es_cds.c is gated, the real one runs. It is the
// EarlyInit slot of ES's own module-table entry, which NASA spends on the CDS because the store
// has to exist before any app can register with it.
U32 CFE_PSP_Exception_GetCount()
{
  return es_exc_count;
}

I32 CFE_PSP_Exception_GetSummary(U32 *ContextLogId, U32 *TaskId, U8 *ReasonBuf, U32 ReasonSize)
{
  *ContextLogId = 77;
  *TaskId = es_exc_taskid;
  StrNCpy(ReasonBuf, "simulated exception", ReasonSize - 1);
  ReasonBuf[ReasonSize - 1] = 0;
  return es_exc_summary_rc;
}

I32 CFE_PSP_Exception_CopyContext(U32 ContextLogId, U8 *ContextBuf, U32 ContextSize)
{
  if (es_exc_ctxsize > 0) {
    MemSet(ContextBuf, 0xC7, es_exc_ctxsize);
  }
  return es_exc_ctxsize;
}
// ---- the PSP's TIMEBASE, which cfe_es_perf.c is built around -------------------------------
// A performance log entry IS a hardware timestamp, so these will still be stubs when every
// line of cFE is translated. es_perf_tb advances by one per read, which makes the timestamps in
// a dumped log a predictable sequence rather than a wall clock -- the transcript compares them.
U32 es_perf_tb;
U32 CFE_PSP_GetTimerTicksPerSecond()
{
  return 1000000;
}

U32 CFE_PSP_GetTimerLow32Rollover()
{
  return 1000000;
}

U0 CFE_PSP_Get_Timebase(U32 *Tbu, U32 *Tbl)
{
  ++es_perf_tb;
  *Tbu = 0;
  *Tbl = es_perf_tb;
}
// cfe_es_task.HC GOES HERE, NOT WITH THE OTHER INCLUDES AT THE TOP, and the reason is a HolyC
// rule rather than a preference: CFE_ES_WriteERLogCmd takes the ADDRESS of
// CFE_ES_BackgroundERLogFileDataGetter and CFE_ES_BackgroundERLogFileEventHandler, and a
// forward DECLARATION is not enough for that -- the definitions have to have been seen. Both
// are stubs in this file (cfe_es_erlog.c is not gated), so the include follows them.
// ERLOG BEFORE TASK: cfe_es_task.c's CFE_ES_WriteERLogCmd takes the ADDRESS of two functions
// cfe_es_erlog.c defines, and in HolyC an address-of needs the definition to have been seen --
// a forward declaration is not enough. A plain CALL is fine either way, which is why
// CFE_ES_TaskInit can call CFE_ES_BackgroundInit from the file before it.
#include "/Kernel/Cfs/cfe/cfe_es_erlog.HC"
#include "/Kernel/Cfs/cfe/cfe_es_task.HC"
#include "/Kernel/Cfs/cfe/cfe_es_perf.HC"
#include "/Kernel/Cfs/cfe/cfe_es_dispatch.HC"
#include "/Kernel/Cfs/cfe/cfe_es_apps.HC"
#include "/Kernel/Cfs/cfe/cfe_es_cds.HC"
#include "/Kernel/Cfs/cfe/cfe_es_cds_mempool.HC"
#include "/Kernel/Cfs/cfe/cfe_es_startupscript.HC"
#include "/Kernel/Cfs/cfe/cfe_es_start.HC"
#include "/Kernel/Cfs/cfe/cfe_es_appctrl.HC"
#include "/Kernel/Cfs/cfe/cfe_es_backgroundtask.HC"
#include "/Kernel/Cfs/cfe/cfe_es_objtab.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_msg.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_global.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_handlelink.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_dumpctl.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_transaction_decl.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_loadbuff_decl.HC"
// THREE STAND-INS FROM cfe_tbl_registry.c, which is inside tbl's eight-source call cycle.
// tools/cfs/module_deps.py --cuts prices cfe_tbl_accdesc.c at exactly these three. The lock
// pair is a COUNTED lock -- the count is what makes it re-entrant within one transaction --
// and it delegates to the driver's OS_MutSemTake/Give, which count, so the transcript
// witnesses every take and give the real code performs.
U0 CFE_TBL_TxnLockRegistry(CFE_TBL_TxnState_t *Txn)
{
  if (Txn->RegLockCount == 0)
    OS_MutSemTake(CFE_TBL_Global.RegistryMutex);
  ++Txn->RegLockCount;
}

U0 CFE_TBL_TxnUnlockRegistry(CFE_TBL_TxnState_t *Txn)
{
  if (Txn->RegLockCount > 0) {
    --Txn->RegLockCount;
    if (Txn->RegLockCount == 0)
      OS_MutSemGive(CFE_TBL_Global.RegistryMutex);
  }
}
// The real one unlinks the descriptor from its table's list. Standing in for it as a no-op
// that COUNTS is deliberate: the list surgery belongs to cfe_tbl_registry.c and writing it
// here would be upstream logic where no gate compares it against NASA. What the exercise can
// still assert is that ReleaseAccDesc CALLS it exactly once, which the counter shows.
I64 tbl_removelink_calls;
I32 CFE_TBL_TxnRemoveAccessLink(CFE_TBL_TxnState_t *Txn)
{
  no_warn Txn;
  ++tbl_removelink_calls;
  return CFE_SUCCESS;
}
#include "/Kernel/Cfs/cfe/cfe_tbl_accdesc.HC"
// cfe_tbl_internal.c, cfe_tbl_task.c and cfe_tbl_api.c are three of the EIGHT sources that
// tools/cfs/module_deps.py shows must be gated together, so these three are stubs on both
// halves -- exactly the arrangement the other six objtabs have had. They exist so that
// CFE_TBL_ModuleEntry has three distinct non-NULL addresses to hold, which is the only
// property the object table exercise asserts about them.
I32 CFE_TBL_EarlyInit()
{
  return CFE_SUCCESS;
}

U0 CFE_TBL_TaskMain()
{
}

I32 CFE_TBL_CleanUpApp(U32 AppId)
{
  no_warn AppId;
  return CFE_SUCCESS;
}
#include "/Kernel/Cfs/cfe/cfe_tbl_objtab.HC"
// --- cfe_tbl_dumpctl.c ----------------------------------------------------------
// The dump-only rendezvous: four blocks, a resource-id allocator over them, and the five
// header accessors that are the allocator's primitives. The whole id scheme is exercised
// here once, because tbl repeats it in five id spaces and the other four are the same code
// with a different base.
//
// THIS SECTION IS ITS OWN FUNCTION, and that is not style either. Limit 22: every local added
// to main() spends from one frame budget, and exceeding it makes a file-scope `&function`
// initialiser elsewhere in the unit read as 0 -- it cost this driver the crc section's
// `cp->Algorithm(...)`, 775 lines away, on the commit that added these very locals. A called
// function gets its OWN frame, so a section written this way costs main() nothing and needs no
// file-scope globals standing in for its locals. Every tbl section from here is written so.
// --- cfe_tbl_accdesc.c ---------------------------------------------------------------
// The per-app handle: 256 access descriptors, a resource-id allocator over them, and the two
// transaction entry points that hand one out and give it back.
//
// The interesting assertions are the two that are not about the allocator at all. First, a
// transaction TAKES AND RELEASES the registry lock exactly once around the allocation, which
// the driver's counting mutex witnesses. Second, releasing a descriptor only clears the
// table's OwnerAppId IF THE CALLER OWNS IT -- a non-owner may hold a handle to a shared table
// and releasing theirs must not un-own it for everyone.
U0 TblAccDescExercise()
{
  CFE_TBL_AccessDescriptor_t *ad;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_TxnState_t txn;
  U32 nid, idx;
  I64 k, t0, g0;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B10;
  CFE_TBL_Global.LastHandle = CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES - 1);
  // ToIndex DOES NOT BOUNDS CHECK, and that is the thing to know about every resource id in
  // cFS. Its last line is `*Idx = Serial % TableSize` -- a MODULO. The only rejection is a
  // serial above CFE_RESOURCEID_MAX. So one past the last handle WRAPS to index 0 and reports
  // success, and what actually establishes that a record is the one you asked for is
  // CFE_TBL_AccDescIsMatch comparing the id STORED IN the record. An id check that only called
  // ToIndex would read a live neighbour and believe it.
  S("tbl_adidx first=");
  D(CFE_TBL_Handle_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE), &idx));
  S("/");
  D(idx);
  S(" last=");
  D(CFE_TBL_Handle_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES - 1), &idx));
  S("/");
  D(idx);
  S(" past=");
  D(CFE_TBL_Handle_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES), &idx));
  S("/");
  D(idx);
  S(" undef=");
  D(CFE_TBL_Handle_ToIndex(CFE_TBL_HANDLEID_UNDEFINED, &idx));
  S("\n");
  ad = CFE_TBL_LocateAccDescByHandle(CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 5));
  S("tbl_adloc self=");
  D(ad == &CFE_TBL_Global.Handles[5]);
  S(" used=");
  D(CFE_TBL_AccDescIsUsed(ad));
  S(" null=");
  D(CFE_TBL_LocateAccDescByHandle(CFE_TBL_HANDLEID_UNDEFINED) == NULL);
  S(" slotused=");
  D(CFE_TBL_CheckAccessDescriptorSlotUsed(CFE_ResourceId_FromInteger(0)));
  S("\n");
  // init, mark used, read back, match, free -- the allocator primitives
  nid = CFE_TBL_GetNextTableHandle();
  ad = CFE_TBL_LocateAccDescByHandle(nid);
  MemSet(ad, 0xEE, sizeof(CFE_TBL_AccessDescriptor_t));
  CFE_TBL_InitAccessDescriptor(ad);
  S("tbl_adinit id=");
  D(CFE_ResourceId_ToInteger(nid));
  S(" zeroed=");
  D(ad->LockFlag == FALSE && ad->AppId == 0);
  S(" linkdetached=");
  D(!CFE_TBL_HandleLinkIsAttached(&ad->Link));
  S("\n");
  CFE_TBL_AccDescSetUsed(ad, nid);
  S("tbl_adused used=");
  D(CFE_TBL_AccDescIsUsed(ad));
  S(" back=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_AccDescGetHandle(ad)));
  S(" match=");
  D(CFE_TBL_AccDescIsMatch(ad, nid));
  S("\n");
  ad->AppId = CFE_ResourceId_FromInteger(0x4321);
  CFE_TBL_AccDescSetFree(ad);
  S("tbl_adfree used=");
  D(CFE_TBL_AccDescIsUsed(ad));
  S(" appid=");
  D(CFE_ResourceId_ToInteger(ad->AppId));
  S("\n");
  // A WHOLE TRANSACTION, and the lock is the thing being watched.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  t0 = fs_mut_take;
  g0 = fs_mut_give;
  S("tbl_adtxn rc=");
  D(CFE_TBL_TxnAllocateAccDesc(&txn));
  S(" handle=");
  D(CFE_TBL_TxnHandleAsULong(&txn));
  S(" nonnull=");
  D(txn.AccDescPtr != NULL);
  S(" used=");
  D(txn.AccDescPtr != NULL && CFE_TBL_AccDescIsUsed(txn.AccDescPtr));
  S(" takes=");
  D(fs_mut_take - t0);
  S(" gives=");
  D(fs_mut_give - g0);
  S(" lockcnt=");
  D(txn.RegLockCount);
  S("\n");
  // RELEASE BY THE OWNER clears the table's owner; RemoveAccessLink is called once.
  // cfe_tbl_regrec.c is not gated, so the record is zeroed directly rather than through
  // CFE_TBL_InitRegistryRecord -- the only field this exercise reads is OwnerAppId.
  rr = &CFE_TBL_Global.Registry[3];
  MemSet(rr, 0, sizeof(CFE_TBL_RegistryRec_t));
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  txn.AppId = rr->OwnerAppId;
  txn.RegRecPtr = rr;
  tbl_removelink_calls = 0;
  CFE_TBL_TxnReleaseAccDesc(&txn);
  S("tbl_adrel_owner owner=");
  D(CFE_ResourceId_ToInteger(rr->OwnerAppId));
  S(" freed=");
  D(!CFE_TBL_AccDescIsUsed(txn.AccDescPtr));
  S(" unlinks=");
  D(tbl_removelink_calls);
  S("\n");
  // RELEASE BY A NON-OWNER must leave the table owned.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  CFE_TBL_TxnAllocateAccDesc(&txn);
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  txn.AppId = CFE_ResourceId_FromInteger(0x2222);
  txn.RegRecPtr = rr;
  tbl_removelink_calls = 0;
  CFE_TBL_TxnReleaseAccDesc(&txn);
  S("tbl_adrel_other owner=");
  D(CFE_ResourceId_ToInteger(rr->OwnerAppId));
  S(" freed=");
  D(!CFE_TBL_AccDescIsUsed(txn.AccDescPtr));
  S(" unlinks=");
  D(tbl_removelink_calls);
  S("\n");
  // EXHAUSTION. All 256 marked used, so the next transaction must refuse and must leave the
  // transaction's own fields cleared rather than half-filled.
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_NUM_HANDLES; k++)
    CFE_TBL_AccDescSetUsed(&CFE_TBL_Global.Handles[k], CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + k));
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  t0 = fs_mut_take;
  g0 = fs_mut_give;
  S("tbl_adfull rc=0x");
  Hx8(CFE_TBL_TxnAllocateAccDesc(&txn));
  S(" null=");
  D(txn.AccDescPtr == NULL);
  S(" handle=");
  D(CFE_TBL_TxnHandleAsULong(&txn));
  S(" takes=");
  D(fs_mut_take - t0);
  S(" gives=");
  D(fs_mut_give - g0);
  S("\n");
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

U0 TblDumpCtlExercise()
{
  CFE_TBL_DumpControl_t *bp;
  U32 nid, idx;
  I64 k;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.LastDumpCtrlBlockId = CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1);
  // ToIndex: the first slot, the last slot, one past the end, and an undefined id
  S("tbl_dcidx first=");
  D(CFE_TBL_DumpCtrlId_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE), &idx));
  S("/");
  D(idx);
  S(" last=");
  D(CFE_TBL_DumpCtrlId_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1), &idx));
  S("/");
  D(idx);
  S(" past=");
  D(CFE_TBL_DumpCtrlId_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS), &idx));
  S(" undef=");
  D(CFE_TBL_DumpCtrlId_ToIndex(CFE_TBL_DUMPCTRLID_UNDEFINED, &idx));
  S("\n");
  // Locate: every slot resolves to its own address, and a bad id gives NULL
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++) {
    bp = CFE_TBL_LocateDumpCtrlByID(CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + k));
    S("tbl_dcloc k=");
    D(k);
    S(" self=");
    D(bp == &CFE_TBL_Global.DumpControlBlocks[k]);
    S(" used=");
    D(bp != NULL && CFE_TBL_DumpCtrlBlockIsUsed(bp));
    S("\n");
  }
  S("tbl_dcloc_bad null=");
  D(CFE_TBL_LocateDumpCtrlByID(CFE_TBL_DUMPCTRLID_UNDEFINED) == NULL);
  S(" slotused=");
  D(CFE_TBL_CheckDumpCtrlSlotUsed(CFE_ResourceId_FromInteger(0)));
  S("\n");
  // THE ALLOCATOR. Four blocks, so the fifth request must come back UNDEFINED --
  // exhaustion is the path that matters, because a dump request that silently reused a
  // block would overwrite another table's pending snapshot.
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS + 1; k++) {
    nid = CFE_TBL_GetNextDumpCtrlBlock();
    bp = CFE_TBL_LocateDumpCtrlByID(nid);
    S("tbl_dcnext k=");
    D(k);
    S(" id=");
    D(CFE_ResourceId_ToInteger(nid));
    S(" got=");
    D(bp != NULL);
    if (bp != NULL) {
      CFE_TBL_DumpCtrlBlockSetUsed(bp, nid);
      CFE_TBL_Global.LastDumpCtrlBlockId = nid;
      S(" used=");
      D(CFE_TBL_DumpCtrlBlockIsUsed(bp));
      S(" id_back=");
      D(CFE_ResourceId_ToInteger(CFE_TBL_DumpCtrlBlockGetId(bp)));
      S(" match=");
      D(CFE_TBL_DumpCtrlBlockIsMatch(bp, nid));
    }
    S("\n");
  }
  // and freeing one puts BOTH fields back, which is what lets it be reallocated
  bp = &CFE_TBL_Global.DumpControlBlocks[2];
  bp->State = CFE_TBL_DUMP_PERFORMED;
  CFE_TBL_DumpCtrlBlockSetFree(bp);
  S("tbl_dcfree used=");
  D(CFE_TBL_DumpCtrlBlockIsUsed(bp));
  S(" state=");
  D(bp->State);
  S(" match=");
  D(CFE_TBL_DumpCtrlBlockIsMatch(bp, CFE_TBL_DUMPCTRLID_UNDEFINED));
  S(" next=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_GetNextDumpCtrlBlock()));
  S("\n");
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}
// THE SIMULATED MEMORY POOL IS GONE from both halves of this driver. CFE_ES_PoolCreateEx,
// CFE_ES_GetPoolBuf and CFE_ES_PutPoolBuf were a hand-written bump allocator here;
// cfe_es_mempool.HC and cfe_es_generic_pool.HC are gated now, so every allocation in the
// transcript goes through NASA's real pool -- real buckets, a real free stack that recycles,
// real check patterns, and the resource-id table in CFE_ES_Global.
//
// Two OSAL/PSP calls are still stubs. OS_MutSemCreate is ALREADY stubbed elsewhere in this file
// and the pool's mutex uses that one.
I64 es_mutsem_deletes;
I64 es_psp_validates;
I32 es_psp_validate_rc;
I32 OS_MutSemDelete(U32 sem_id)
{
  ++es_mutsem_deletes;
  es_obj_mark(sem_id);
  return OS_SUCCESS;
}

I32 CFE_PSP_MemValidateRange(U64 Address, I64 Size, U32 MemoryType)
{
  ++es_psp_validates;
  return es_psp_validate_rc;
}
// Fill a pool so the next allocation cannot fit, and put it back. White-box on purpose: there
// is no API for "make the next GetPoolBuf fail", and a 512 KiB pool cannot be exhausted a block
// at a time inside a transcript. It replaces the old sb_getpool_rc injector.
//
// BOTH ARE NULL-SAFE, and that is not defensive padding: several of the sites that used to set
// sb_getpool_rc back to CFE_SUCCESS run BEFORE SB's EarlyInit, where there is no pool and the
// handle resolves to nothing. The old stub ignored its handle entirely so those lines were
// no-ops; with the real pool they are lookups that can fail.
I64 es_pool_saved_tail;
// AND DO NOT USE IT TO FAIL SB'S POOL CREATE. CFE_SB_InitBuffers' failure message prints
// `gave adr 0x%lx` -- the partition's address -- so that line cannot be compared across a host
// process and a QEMU guest. It is out of the transcript because the pool SUCCEEDS, not because
// it is unreachable. Same rule as CFE_SB_CreatePipe's argument-check branch.
U0 es_pool_exhaust(U32 Handle)
{
  CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(Handle);
  // The TailPosition test makes a second exhaust a no-op. There are ten call sites and
  // es_pool_saved_tail is ONE variable: without it, exhaust-exhaust-restore saves PoolMaxOffset
  // as the "real" tail and leaves the pool permanently full.
  if (r != NULL && r->Pool.TailPosition != r->Pool.PoolMaxOffset) {
    es_pool_saved_tail = r->Pool.TailPosition;
    r->Pool.TailPosition = r->Pool.PoolMaxOffset;
  }
}

U0 es_pool_restore(U32 Handle)
{
  CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(Handle);
  if (r != NULL) {
    r->Pool.TailPosition = es_pool_saved_tail;
  }
}
// THE THREE COUNTERS THE TRANSCRIPT USED TO PRINT, now read out of NASA'S OWN POOL instead of
// out of my stub's locals. AllocationCount is the pool's record of every block it has ever
// handed out, and the per-bucket ReleaseCount is its record of every one given back -- the same
// numbers CFE_ES_GetMemPoolStats reports to the ground. es_pool_puts sums ReleaseCount across
// the buckets because there is no aggregate: a free is recorded against the bucket the block
// came from, which is also how NumFree is derived (ReleaseCount - RecycleCount).
I64 es_pool_creates()
{
  if (CFE_ES_ValidateHandle(CFE_SB_Global.Mem.PoolHdl))
    return 1;
  return 0;
}

I64 es_pool_gets()
{
  CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(CFE_SB_Global.Mem.PoolHdl);
  if (r == NULL)
    return 0;
  return r->Pool.AllocationCount;
}

I64 es_pool_puts()
{
  CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(CFE_SB_Global.Mem.PoolHdl);
  I64 n = 0;
  U16 i;
  if (r != NULL) {
    for (i = 0; i < r->Pool.NumBuckets; ++i)
      n += r->Pool.Buckets[i].ReleaseCount;
  }
  return n;
}
// THE GENERIC POOL'S STORAGE AND ITS ACCESSORS. cfe_es_generic_pool.HC never dereferences the
// pool -- it addresses everything by OFFSET and goes through these two function pointers, so
// that a pool can live somewhere that is not memory-mapped (a CDS in battery-backed RAM is the
// case NASA has in mind). For an ordinary memory-mapped pool Retrieve just adds the offset to a
// base and Commit does nothing, which is what cfe_es_mempool.c's Direct pair does and what
// these reproduce. They live in the DRIVER rather than the translation because mempool.c is
// not gated yet.
//
// 2048 bytes is chosen to make the pool-full path reachable: the largest bucket is 256, so a
// handful of allocations exhausts it.
U8 es_pool_mem[2048];
I32 es_pool_retrieve(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t **BdPtr)
{
  *BdPtr = &es_pool_mem[Offset];
  return CFE_SUCCESS;
}

I32 es_pool_commit(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t *BdPtr)
{
  return CFE_SUCCESS;
}
// "123456789" -- the CRC-16/ARC check value for this exact input is 0xBB3D, stated in NASA's
// comment on the CFE_ES_CrcType_16_ARC enumerator. Using the documented vector means the
// transcript agreeing is evidence about the ALGORITHM and not just about two copies of a table.
U8 *CRC_PROBE = "123456789";
// A message LONGER THAN HALF THE LOG, for the truncation and wrap paths. 4100 bytes: the
// per-message cap is CFE_PLATFORM_ES_SYSTEM_LOG_SIZE/2 = 4096, so this is just over it and
// exercises the cap rather than merely approaching it. At file scope because the guest's stack
// is not the place for it.
U8 es_big_msg[4101];
// ES'S COMMAND BUFFER, for the same reason CFE_SB_AnyCmd_t below exists: a buffer the size of
// the command being BUILT is not the size a handler READS. The C half writes this as an
// anonymous union local; HolyC needs it named.
// THE PERF COMMANDS' OWN BUFFER, with CFE_SB_Buffer first so the dispatcher can be handed a
// message. Separate from CFE_ES_AnyCmd_t below only because the perf probe needs the buffer
// member and the est_ probe does not.
union CFE_ES_AnyPerfCmd_t
{
  CFE_SB_Buffer Buf;
  CFE_ES_NoopCmd_t Noop;
  CFE_ES_StartPerfDataCmd_t StartPerf;
  CFE_ES_StopPerfDataCmd_t StopPerf;
  CFE_ES_SetPerfFilterMaskCmd_t FiltMask;
  CFE_ES_SetPerfTriggerMaskCmd_t TrigMask;
};

union CFE_ES_AnyCmd_t
{
  CFE_ES_NoopCmd_t Noop;
  CFE_ES_ResetCountersCmd_t ResetCtrs;
  CFE_ES_RestartCmd_t Restart;
  CFE_ES_SendHkCmd_t Hk;
  CFE_ES_StartAppCmd_t StartApp;
  CFE_ES_StopAppCmd_t StopApp;
  CFE_ES_RestartAppCmd_t RestartApp;
  CFE_ES_ReloadAppCmd_t ReloadApp;
  CFE_ES_QueryOneCmd_t QueryOne;
  CFE_ES_QueryAllCmd_t QueryAll;
  CFE_ES_QueryAllTasksCmd_t QueryAllTasks;
  CFE_ES_ClearSysLogCmd_t ClearSysLog;
  CFE_ES_OverWriteSysLogCmd_t OverWriteSysLog;
  CFE_ES_WriteSysLogCmd_t WriteSysLog;
  CFE_ES_ClearERLogCmd_t ClearERLog;
  CFE_ES_WriteERLogCmd_t WriteERLog;
  CFE_ES_ResetPRCountCmd_t ResetPRCount;
  CFE_ES_SetMaxPRCountCmd_t SetMaxPRCount;
  CFE_ES_DeleteCDSCmd_t DeleteCDS;
  CFE_ES_SendMemPoolStatsCmd_t MemPoolStats;
  CFE_ES_DumpCDSRegistryCmd_t DumpCDSReg;
};

union CFE_SB_AnyCmd_t
{
  CFE_SB_Buffer Buf;
  CFE_SB_NoopCmd_t Noop;
  CFE_SB_ResetCountersCmd_t Reset;
  CFE_SB_SendSbStatsCmd_t Stats;
  CFE_SB_EnableRouteCmd_t Route;
  CFE_SB_WriteRoutingInfoCmd_t WrFile;
  CFE_SB_SendPrevSubsCmd_t PrevSubs;
  CFE_SB_EnableSubReportingCmd_t SubRpt;
  CFE_SB_SendHkCmd_t Hk;
};

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
// One character, for a %c. S() takes a NUL-terminated string, so a single byte needs a
// two-byte buffer of its own.
U0 Ch(I64 c)
{
  U8 one[2];
  one[0] = c;
  one[1] = 0;
  S(one);
}

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
// CFE_ES_AppID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_ES_GetAppIDByName: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_ES_GetAppName: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
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
I64 ta_evs_register_rc;
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
// THESE TWO ARE MACROS IN NASA'S cfe_es.h, not functions:
//     #define CFE_ES_PerfLogEntry(id) (CFE_ES_PerfLogAdd(id, 0))
//     #define CFE_ES_PerfLogExit(id)  (CFE_ES_PerfLogAdd(id, 1))
// and CFE_ES_PerfLogAdd is real now (cfe_es_perf.c is gated), so they are FORWARDERS rather
// than stubs -- the C half's macros reach the same function.
//
// THEY ARE FUNCTIONS HERE AND NOT MACROS, and the reason is include order: SB, EVS, TIME and
// TA all call them, and all four are included BEFORE cfe_es_perf.HC, so a macro defined there
// would not be in scope at their call sites. A function resolves at link time either way.
U0 CFE_ES_PerfLogEntry(U32 Marker)
{
  CFE_ES_PerfLogAdd(Marker, 0);
}

U0 CFE_ES_PerfLogExit(U32 Marker)
{
  CFE_ES_PerfLogAdd(Marker, 1);
}
// CFE_ES_ExitApp: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_ES_WaitForSystemState: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
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
// CFE_ES_GetResetType: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
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
// CFE_TIME_Tone1HzISR used to be stubbed here, because cfe_time_tone.c was not gated and
// CFE_TIME_ExternalTone's whole body is a call to it. It is gated now, so the REAL one runs --
// and the stub had to go on both sides at once, which is the shape every one of these removals
// has had: the stub is what the gate was measuring until the translation arrived.
// CFE_ES_IncrementTaskCounter: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// The simulated OS's semaphores, child tasks and timebase, for CFE_TIME_TaskInit. Every value
// TaskInit branches on is a variable here, so the gate can walk the failure paths as well as the
// happy one -- TaskInit has five of them and each returns a different status.
//
// time_sem_take_budget is a BUDGET, not a constant, and that is the whole reason the two 1Hz
// child tasks are drivable at all: CFE_TIME_Tone1HzTask and CFE_TIME_Local1HzTask are
// `while (TRUE)` loops that exit only when OS_BinSemTake fails, so NASA's own loop termination is
// what ends them. A stub that always succeeded would hang the oracle.
I64 time_sems_created;
I64 time_sem_gives;
I64 time_sem_takes;
I64 time_childtasks;
I64 time_tb_lookups;
I64 time_timer_adds;
I64 time_timer_sets;
I64 time_synch_calls;
I32 time_binsem_rc;
I32 time_childtask_rc;
I32 time_tb_rc;
I32 time_timeradd_rc;
I32 time_timerset_rc;
I64 time_sem_take_budget;
// OS_SUCCESS reaches this file through cfe_fs_priv.HC; OS_ERROR does not, because nothing
// translated so far needed it. osapi_errors.HC defines it as -1 and is NOT included here -- this
// gate is deliberately standalone -- so the one value is spelled out, and check_constants.py
// compares it against NASA's own header like every other number in the translation.
#ifndef OS_ERROR
#define OS_ERROR -1
#endif
I32 OS_BinSemCreate(U32 *sem_id, U8 *sem_name, U32 sem_initial_value, U32 options)
{
  ++time_sems_created;
  *sem_id = 0x3330 + time_sems_created;
  return time_binsem_rc;
}

I32 OS_BinSemGive(U32 sem_id)
{
  ++time_sem_gives;
  return OS_SUCCESS;
}

I32 OS_BinSemTake(U32 sem_id)
{
  ++time_sem_takes;
  if (time_sem_take_budget <= 0)
    return OS_ERROR;
  --time_sem_take_budget;
  return OS_SUCCESS;
}
// THE BACKGROUND TASK'S DELAY, and its only way out. CFE_ES_BackgroundTask loops forever on
// OS_BinSemTimedWait and breaks only on a status that is neither OS_SUCCESS nor OS_SEM_TIMEOUT
// -- so a budget, exactly like time_sem_take_budget above, is what makes the task drivable at
// all. es_bg_waits counts the passes; es_bg_wait_budget bounds them.
I64 es_bg_waits, es_bg_deletes;
I64 es_bg_wait_budget;
I32 OS_BinSemTimedWait(U32 sem_id, U32 msecs)
{
  ++es_bg_waits;
  if (es_bg_wait_budget <= 0) {
    return OS_ERROR;
  }
  --es_bg_wait_budget;
  return OS_SEM_TIMEOUT;
}

I32 OS_BinSemDelete(U32 sem_id)
{
  ++es_bg_deletes;
  es_obj_mark(sem_id);
  return OS_SUCCESS;
}
// CFE_ES_CreateChildTask: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_SB_SubscribeLocal was stubbed here. It is real now (cfe_sb_api.HC), and TIME is the only
// caller. time_sub_local counted the calls; SB counts the successful ones in
// StatTlmMsg.Payload.SubscriptionsInUse, which is what the transcript reports instead. A LOCAL
// which is what the transcript reports.
// Defaults to FAILING, which is NASA's documented expectation and not a shortcut: the comment on
// CFE_TIME_TaskInit_Setup1HzTimer says a PSP that did not set up a timebase returns
// OS_ERR_NAME_NOT_FOUND and the lookup failure is deliberately NOT reported. The gate drives both
// answers.
I32 OS_TimeBaseGetIdByName(U32 *timebase_id, U8 *timebase_name)
{
  ++time_tb_lookups;
  *timebase_id = 0x5551;
  return time_tb_rc;
}

I32 OS_TimerAdd(U32 *timer_id, U8 *timer_name, U32 timebase_id, U0 (*callback_ptr)(), U8 *callback_arg)
{
  ++time_timer_adds;
  *timer_id = 0x6661;
  return time_timeradd_rc;
}

I32 OS_TimerSet(U32 timer_id, U32 start_time, U32 interval_time)
{
  ++time_timer_sets;
  return time_timerset_rc;
}
// SB's PIPE QUEUES, simulated. One queue of one entry per pipe is enough for the transaction
// machinery: what cfe_sb_priv.c does is decide WHICH pipes to write to and how to undo the
// accounting when a write fails, so the queue only has to be able to succeed, be full, and be
// empty on demand.
#define SBQ_MAX 32
class SbQueue
{
  U8 Data[64];
  I64 Size;
  Bool Full;
  Bool Created;
  U8 Name[32];
};
SbQueue sbq[SBQ_MAX];
I64 sb_qputs, sb_qgets;
I32 sb_queueput_rc;
// set to OS_QUEUE_FULL to force the undo path
I32 sb_queueget_rc;
// CREATE, DELETE AND LOOKUP, and these three are why CFE_SB_CreatePipe no longer needs a stub.
// The pipe table, the name check and the "reserved" slot in cfe_sb_api.HC are all real now;
// what is simulated is only the OS queue underneath them.
//
// sb_queuecreate_rc IS THE FAULT INJECTOR THAT ta_pipe_rc USED TO BE, and it is a better one.
// The stub returned whatever number the test asked for; this returns an OSAL error and lets
// CFE_SB_CreatePipe decide, so the transcript now shows CFE_SB_PIPE_CR_ERR (0xca000005) coming
// out of the translation of OS_ERROR -- and the three DIFFERENT events it raises for
// OS_ERR_NAME_TAKEN, OS_ERR_NO_FREE_IDS and everything else became reachable at the same time.
I64 sb_qcreates, sb_qdeletes;
I32 sb_queuecreate_rc;
I64 sb_next_qid;
// 0 is OS_OBJECT_ID_UNDEFINED, so ids start at 1; set in main
I32 OS_QueueCreate(U32 *queue_id, U8 *queue_name, I64 queue_depth, I64 data_size, U32 flags)
{
  I64 i;
  ++sb_qcreates;
  if (sb_queuecreate_rc != OS_SUCCESS)
    return sb_queuecreate_rc;
  // the name check NASA's OSAL does, because CFE_SB_CreatePipe has a distinct event for it
  for (i = 1; i < sb_next_qid && i < SBQ_MAX; i++) {
    if (sbq[i].Created && !StrCmp(sbq[i].Name, queue_name))
      return OS_ERR_NAME_TAKEN;
  }
  if (sb_next_qid >= SBQ_MAX)
    return OS_ERR_NO_FREE_IDS;
  i = sb_next_qid++;
  sbq[i].Created = TRUE;
  sbq[i].Full = FALSE;
  StrPrintN(sbq[i].Name, 32, "%s", queue_name);
  *queue_id = i;
  return OS_SUCCESS;
}

I32 OS_QueueDelete(U32 queue_id)
{
  I64 i = queue_id;
  ++sb_qdeletes;
  if (i >= SBQ_MAX || !sbq[i].Created)
    return OS_ERR_INVALID_ID;
  // The id is NOT returned to the pool: a reused id would make a stale pipe descriptor look
  // valid, which is the one thing a queue simulation must not do to a lifetime test.
  sbq[i].Created = FALSE;
  sbq[i].Full = FALSE;
  sbq[i].Name[0] = 0;
  return OS_SUCCESS;
}
// RESETTING THE BUS IS NOT ENOUGH TO RESET THE QUEUES. CFE_SB_EarlyInit clears CFE_SB_Global,
// but the OS queue NAMES live in OSAL, not in SB -- so a second CFE_SB_AppInit after an
// EarlyInit came back CFE_SB_PIPE_CR_ERR with OS_ERR_NAME_TAKEN, because SB_CMD_PIPE was still
// registered from the first one. That is correct behaviour on both sides and it made the
// exercise meaningless, so this is the analogue of restarting OSAL too.
U0 sbq_reset()
{
  MemSet(sbq, 0, sizeof(SbQueue) * SBQ_MAX);
  sb_next_qid = 1;
}

I32 OS_QueueGetIdByName(U32 *queue_id, U8 *queue_name)
{
  I64 i;
  for (i = 1; i < sb_next_qid && i < SBQ_MAX; i++) {
    if (sbq[i].Created && !StrCmp(sbq[i].Name, queue_name)) {
      *queue_id = i;
      return OS_SUCCESS;
    }
  }
  return OS_ERR_NAME_NOT_FOUND;
}

I32 OS_QueuePut(U32 queue_id, U8 *data, I64 size, I32 timeout)
{
  I64 i = queue_id;
  ++sb_qputs;
  if (sb_queueput_rc != OS_SUCCESS)
    return sb_queueput_rc;
  if (i >= SBQ_MAX || size > 64)
    return OS_ERROR;
  MemCpy(sbq[i].Data, data, size);
  sbq[i].Size = size;
  sbq[i].Full = TRUE;
  return OS_SUCCESS;
}

I32 OS_QueueGet(U32 queue_id, U8 *data, I64 size, I64 *size_copied, I32 timeout)
{
  I64 i = queue_id;
  ++sb_qgets;
  if (sb_queueget_rc != OS_SUCCESS) {
    *size_copied = 0;
    return sb_queueget_rc;
  }
  if (i >= SBQ_MAX || !sbq[i].Full) {
    *size_copied = 0;
    return OS_QUEUE_EMPTY;
  }
  MemCpy(data, sbq[i].Data, sbq[i].Size);
  *size_copied = sbq[i].Size;
  sbq[i].Full = FALSE;
  return OS_SUCCESS;
}
// ES's task identity. One task, one app, and the names differ so CFE_SB_GetAppTskName takes its
// "app.task" branch rather than the "they are the same" one.
I64 sb_taskinfo_calls;
I32 sb_taskinfo_rc;
// CFE_ES_GetTaskID: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// THE OTHER TWO INDEX CONVERSIONS, and all four of them are STUBS MORE PERMISSIVE THAN THE REAL
// THING -- a debt this file has paid before. The real CFE_ES_LibID_ToIndex and
// CFE_ES_CounterID_ToIndex (cfe_es_api.c, not gated yet) subtract CFE_ES_LIBID_BASE and
// CFE_ES_COUNTID_BASE; these take a small id AS the index, the way the AppID stub does. When
// api.c lands, every site here that passes a bare 1 or 2 stops resolving -- the same break
// CFE_SB_PipeId_ToIndex caused when IT stopped being `id & 0xFF`.
// CFE_ES_LibID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_ES_CounterID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// OSAL's id arithmetic, which is the IDENTITY for the SIMPLE osal_id variant this port builds:
// an osal_id_t IS its integer. cfe_es_resource.HC's XOR with CFE_RESOURCEID_MARK is what makes
// an ES task id and its OSAL id differ, not these.
U32 OS_ObjectIdFromInteger(U64 Value)
{
  return Value;
}

U64 OS_ObjectIdToInteger(U32 object_id)
{
  return object_id;
}
// The running task's OSAL id. CFE_ES_GetTaskRecordByContext XORs it into an ES task id, so the
// value here decides which ES task record "the calling task" resolves to.
U32 es_os_taskid;
U32 OS_TaskGetId()
{
  return es_os_taskid;
}
// ---- THE DRIVER'S ES CONTEXT -----------------------------------------------------------------
// "Who is calling" USED TO BE A VARIABLE and is now two table entries. While cfe_es_api.c was
// stubbed, CFE_ES_GetAppID returned `ta_getappid` and a test changed the caller by assigning to
// it. The real one walks OS_TaskGetId -> task record -> its AppId -> app record, so the caller
// is whatever the ES tables say, and es_set_ctx is what moves it.
//
// THE IDS ARE PROPERLY BASED, which is the break this file predicted twice in writing. The old
// *_ToIndex stubs took a bare 1 or 2 AS the index; the real CFE_ES_AppID_ToIndex subtracts
// CFE_ES_APPID_BASE first, so every id here is BASE + slot and `1` is simply out of range.
// Exactly what CFE_SB_PipeId_ToIndex did when it stopped being `id & 0xFF`.
//
// App slot 1 is "CFE_EVS" and slot 2 is "OTHER_APP" -- the same two names the removed
// CFE_ES_GetAppIDByName stub answered for, so the EVS probes keep asking what they asked
// before and now get the answer out of NASA's own name lookup.
#define ES_CTX_TASK_SLOT   0
// osal id es_os_taskid == 1 maps to task table index 0
U0 es_app_slot(U32 slot, U8 *name, U32 type, U32 state)
{
  CFE_ES_AppRecord_t *arp = &CFE_ES_Global.AppTable[slot];
  // THE ID GOES THROUGH A LOCAL, and it has to. Passing ES_CTX_APPID(slot) straight into
  // CFE_ES_AppRecordSetUsed, whose first parameter is a pointer, folds the `OS_OBJECT_TYPE_USER
  // + 1` inside CFE_ES_APPID_BASE as `+ 1*sizeof(CFE_ES_AppRecord_t *pointee)` and plants every
  // app at base 0xC80000 instead of 0x110000 -- silently. docs/HOLYC_STRUCT_LIMITS.md #20,
  // pinned by tests/exec/cases/e_call_arg_const_scaled.hc. The C half has no such problem, so
  // this is the one line in the driver where the two halves are written differently on purpose.
  U32 id = ES_CTX_APPID(slot);
  MemSet(arp, 0, sizeof(CFE_ES_AppRecord_t));
  CFE_ES_AppRecordSetUsed(arp, id);
  StrNCpy(arp->AppName, name, OS_MAX_API_NAME - 1);
  arp->Type = type;
  arp->AppState = state;
  arp->MainTaskId = CFE_ES_TaskId_FromOSAL(es_os_taskid);
  arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
  StrNCpy(arp->StartParams.BasicInfo.FileName, "/cf/es_app.so", OS_MAX_PATH_LEN - 1);
}
// The CALLING app. Only the task record's AppId moves, so the app records themselves stay
// exactly as the startup sequence left them -- a test that changes the caller is not also
// silently changing that app's name, type or state.
U0 es_set_ctx(U32 slot)
{
  CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT].AppId = ES_CTX_APPID(slot);
}

U0 es_ctx_init()
{
  CFE_ES_TaskRecord_t *trp = &CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT];
  es_app_slot(1, "CFE_EVS", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
  es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
  MemSet(trp, 0, sizeof(CFE_ES_TaskRecord_t));
  CFE_ES_TaskRecordSetUsed(trp, CFE_ES_TaskId_FromOSAL(es_os_taskid));
  StrNCpy(trp->TaskName, "SBTESTTASK", OS_MAX_API_NAME - 1);
  trp->StartParams.StackSize = 4096;
  trp->StartParams.Priority = 55;
  CFE_ES_Global.RegisteredTasks = 1;
  CFE_ES_Global.RegisteredExternalApps = 2;
  es_set_ctx(1);
}
// CFE_ES_TaskID_ToIndex: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_ES_GetTaskInfo: STUB REMOVED -- cfe_es_api.c is gated, the real one runs.
// CFE_SB_PipeId_ToIndex, CFE_SB_DeletePipeWithAppId and CFE_SB_GetPipeName were stubbed here
// while cfe_sb_api.c was untranslated. All three are real now. Removing the PipeId_ToIndex stub
// is a change of behaviour on BOTH sides at once -- it was `PipeID & 0xFF` and the real one
// goes through CFE_ResourceId_ToIndex against CFE_SB_PIPEID_BASE.
//
// CFE_SB_SendSubscriptionReport is a NEW stub, not a leftover: it lives in cfe_sb_task.c, which
// is not gated yet, and CFE_SB_SubscribeFull calls it on every successful GLOBAL subscribe. It
// also does the counting ta_subscribes used to do.
// CFE_SB_SendSubscriptionReport WAS stubbed here, and the previous commit's note said it would
// stop being one when cfe_sb_task.c landed. It has. The stub counted calls; the real one does
// nothing at all unless SubscriptionReporting is enabled, so there is no call count worth
// reporting -- both prints below use SB's own SubscriptionsInUse instead.
// OS_ObjectIdEqual is a `static inline` in osapi-idmap.h, so the C half gets it from the header
// and links nothing; HolyC has no inline, so the driver supplies it. CFE_SB_GetPipeIdByName is
// the caller -- it scans the pipe table comparing each descriptor's queue id against the one
// OSAL returned for the name. The blob import trailer is what said this was missing; the
// transcript would have printed "[unresolved import]" eventually, and check_coverage could not
// see it at all.
Bool OS_ObjectIdEqual(U32 object_id1, U32 object_id2)
{
  return object_id1 == object_id2;
}
// OSAL's time arithmetic that the TIMED timeout mode uses. OS_TimeAdd and
// OS_TimeFromTotalMilliseconds are in osapi-clock; reproduced here for the reason the other
// OSAL reproductions in this file record -- a tick is 100 ns.
OS_time_t OS_TimeFromTotalMilliseconds(I64 ms)
{
  OS_time_t t;
  t.ticks = ms * (OS_TIME_TICKS_PER_SECOND / 1000);
  return t;
}

OS_time_t OS_TimeAdd(OS_time_t t1, OS_time_t t2)
{
  OS_time_t t;
  t.ticks = t1.ticks + t2.ticks;
  return t;
}
// OS_MutSemCreate is ALREADY stubbed above, for FS, and SB's EarlyInit uses that one: it counts
// into fs_mut_create and its result is fs_mut_create_rc. One stub per OSAL call in this file.
// A registered 1Hz synchronisation callback. CFE_TIME_NotifyTimeSynchApps walks the registry and
// calls through a function POINTER, which is the one thing in TIME that cannot be checked by
// reading a counter afterwards unless the callback itself bumps one.
I32 TimeSynchProbe()
{
  ++time_synch_calls;
  return CFE_SUCCESS;
}
// CFE_SB_CreatePipe, CFE_SB_Subscribe, CFE_SB_ReceiveBuffer and CFE_SB_TransmitMsg were the
// four stubs every other module in this file was driven through: config, fs, ta, evs and time
// all reach the bus by one of them. They are gone. Those paths now run SB's real argument
// checking, real pipe table, real route lookup and real transaction machinery, on both sides.
//
// WHAT THE THREE COUNTERS BECAME, because each had to move to something the real code does:
//   ta_pipe_created -> sb_qcreates, counted in the simulated OS_QueueCreate.
//   ta_subscribes   -> SB's own StatTlmMsg.Payload.SubscriptionsInUse.
//   ta_transmits    -> the delta in CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter, which
//                      is SB's own count of a message sent to a message id nobody subscribed
//                      to. Every housekeeping packet in this driver is exactly that, so the
//                      number is the same one the stub reported -- but it is now SB's.
// sb_tx_reset() BEFORE EVERY sb_tx_since() IS MANDATORY. The difference is unsigned, so a
// sb_tx_since() with no preceding reset reports a large positive number rather than an
// obviously-wrong zero.
U32 sb_tx_mark;
U0 sb_tx_reset()
{
  sb_tx_mark = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
}

I64 sb_tx_since()
{
  return CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - sb_tx_mark;
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
  // sb_next_qid is 1 because 0 is OS_OBJECT_ID_UNDEFINED; HolyC zeroes globals, so it is set
  // here rather than at the declaration. es_os_taskid is the same case -- the C half gives it
  // an initialiser at its declaration and HolyC cannot, and the two halves agreeing anyway
  // would have meant only that nothing reads it yet. The ES record-by-context probe below does.
  sb_next_qid = 1;
  es_os_taskid = 1;
  // Two more of the same case, both new with cfe_es_apps.c. es_taskcreate_next is 2 because 1 is
  // the calling task's osal id, and an id that does not resolve is now a wild store rather than
  // a harmless number -- see OS_TaskCreate above. es_modinfo_valid is 1 so
  // CFE_ES_CopyModuleAddressInfo's nominal arm is the default and the exercise steers the other.
  es_taskcreate_next = 2;
  es_modinfo_valid = 1;
  es_modlookup_addr = 0xE0000000;
  // The simulated CDS: its size, and the offset past which writes fail. HolyC zeroes globals
  // and CFE_PSP_SUCCESS is 0, so the three PSP statuses need no explicit default.
  es_cds_size = ES_CDS_STORE_SIZE;
  es_cds_write_fail_at = 0xFFFFFFFF;
  // The simulated volatile disk: 90 of 100 blocks free, so the free-space check passes by
  // default and the reformat path is one knob away. The six OS_* statuses default to
  // OS_SUCCESS, which is 0, so HolyC's zeroed globals already say that.
  es_vol_total_blocks = 100;
  es_vol_blocks_free = 90;
  // THE BUS HAS TO EXIST BEFORE ANYTHING SUBSCRIBES TO IT, and before cfe_sb_api was gated it
  // did not have to: CFE_SB_CreatePipe and CFE_SB_Subscribe were stubs that answered without
  // reading CFE_SB_Global. They are real now, and CFE_SB_Global starts zeroed -- LastPipeId of
  // 0 is not a valid resource id, so CFE_ResourceId_FindNext walks off the table and the very
  // first CFE_TA_TaskInit came back CFE_SB_MAX_PIPES_MET with 64 pipes free. CFE_SB_EarlyInit
  // is what sets LastPipeId to CFE_SB_PIPEID_BASE - 1 and stands up the memory pool the
  // destination blocks come from. cFE's own startup calls it first too; the SB section below
  // calls it again, deliberately, to exercise it.
  // ES'S RESET AREA HAS TO BE AIMED BEFORE ANYTHING CAN LOG, and that became load-bearing the
  // moment cfe_es_mempool.c was gated: the real pool calls CFE_ES_WriteToSysLog on every
  // failure path, the syslog writes into CFE_ES_Global.ResetDataPtr->SystemLog, and a NULL
  // there is a dereference of 0 rather than a dropped message. cFE does this in
  // CFE_ES_SetupResetVariables during startup; the syslog section below re-clears it.
  MemSet(&es_reset_area, 0, sizeof(CFE_ES_ResetData_t));
  CFE_ES_Global.ResetDataPtr = &es_reset_area;
  CFE_ES_Global.ResetDataPtr->SystemLogMode = CFE_ES_LogMode_DISCARD;
  // AND THE POOL-ID SPACE HAS TO BE OPENED, for the same reason and with the same symptom as
  // SB's LastPipeId: CFE_ES_Global is zeroed, 0 is not a valid resource id, so
  // CFE_ResourceId_FindNext walks off the table and CFE_ES_PoolCreateEx reports "no free
  // MemPool slots" with all ten free. cfe_es_start.c:178 does exactly this line. The symptom was
  // CFE_SB_GetBufferFromPool returning NULL and the driver dereferencing it -- a hundred lines
  // after SB's EarlyInit had quietly failed.
  CFE_ES_Global.LastMemPoolId = CFE_ES_POOLID_BASE;
  // AND THE OTHER THREE ID SPACES, for exactly the same reason and with the same symptom:
  // CFE_ES_RegisterGenCounter came back CFE_ES_NO_RESOURCE_IDS_AVAILABLE with every slot free,
  // because CFE_ResourceId_FindNext starting from 0 walks off the table. These are
  // cfe_es_start.c:175-177, the three lines next to the pool one already here.
  CFE_ES_Global.LastAppId = CFE_ES_APPID_BASE;
  CFE_ES_Global.LastLibId = CFE_ES_LIBID_BASE;
  CFE_ES_Global.LastCounterId = CFE_ES_COUNTID_BASE;
  // AND ES'S OWN TABLES, because cfe_es_api.c is gated and "who is calling" now comes out of
  // them rather than out of a stub. The mutex id goes in first: the real CFE_ES_LockSharedData
  // takes CFE_ES_Global.SharedDataMutex, and the id is what lets the OS_MutSemTake stub count
  // ES's locks apart from the FS and pool ones.
  CFE_ES_Global.SharedDataMutex = ES_SHARED_MUTEX_ID;
  es_ctx_init();
  // AND EVS'S LOG POINTER, for the same reason the reset area had to be aimed above: with a
  // real CFE_ES_GetAppID the caller is now a REGISTERED app, so events raised by the fs, ta and
  // sb sections actually reach EVS_AddLog instead of being refused for an out-of-range app id
  // -- and EVS_AddLog dereferences CFE_EVS_Global.EVS_LogPtr with no NULL check.
  // CFE_EVS_EarlyInit is what does this in cFE; the EVS section below calls it again and
  // re-points it at the same storage.
  MemSet(&evs_log_storage, 0, sizeof(CFE_EVS_Log_t));
  CFE_EVS_Global.EVS_LogPtr = &evs_log_storage;
  CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_EVS_LogMode_OVERWRITE;
  // AND THE CONFIG SERVICE BEFORE THE BUS, which is cFE's own startup order -- ES, then config,
  // then everything else. It did not matter while CFE_ES_PoolCreateEx was a stub that ignored
  // its block-size arguments; with the real pool, CFE_SB_InitBuffers reads SB's block sizes out
  // of the config registry (CFE_CONFIGID_PLATFORM_SB_MEM_BLOCK_SIZE) and an empty registry means
  // ZERO block sizes, which CFE_ES_GenPoolInitialize correctly refuses. The config section
  // below calls it again and checks what it returns.
  // ...and CFE_TargetConfigInit BEFORE THAT, which is the one call this half needs and the C
  // half does not. GLOBAL_CONFIGDATA and the module-version table are STATIC INITIALISERS in
  // the generated C; here they are filled at runtime, so CFE_Config_Init run before them sees
  // a NULL ModuleVersionList and registers five fewer entries. That showed up as
  // "cfg_iter 18 of 34" against NASA's 23 -- a five-entry difference in the config registry
  // that nothing had ever counted, because until now no CFE_Config_Init ran before cfg_iter.
  // THE TWO RUNTIME INITS THE C HALF DOES NOT NEED, both for the same reason: the generated C
  // declares these tables as STATIC INITIALISERS and HolyC fills them at runtime, so anything
  // that reads them has to run after. CFE_Config_Init reads BOTH -- the module-version list
  // through CFE_Config_SetupModuleVersions, and the platform block-size arrays through
  // CFE_Config_SetupPlatformConfigInfo.
  //
  // Getting the order wrong does not fail loudly. It registered five fewer config entries
  // ("cfg_iter 18 of 34" against NASA's 23) and handed CFE_SB_InitBuffers an EMPTY block-size
  // array, so SB's pool came back CFE_ES_ERR_MEM_BLOCK_SIZE and every allocation in the run
  // failed -- reported once, at the top of the transcript, and then as absent telemetry
  // hundreds of lines later.
  CFE_TargetConfigInit();
  CFE_PlatformConfigTablesInit();
  CFE_Config_Init();
  CFE_SB_EarlyInit();
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
    // The head is stored and returned, never inspected -- BY cfe_sbr. It is very much
    // inspected by cfe_sb_priv.HC, and this probe used to leave the sentinel in place:
    // harmless while CFE_SB_TransmitMsg was a stub, and a crash the moment cfe_sb_api was
    // gated and the real one walked the route, three thousand lines away from here.
    CFE_SBR_SetDestListHeadPtr(rid2, NULL);
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
    // THE WAKEUP WITNESS IS THE SEMAPHORE NOW. CFE_ES_BackgroundWakeup was a stub that bumped
    // fs_wakeups; cfe_es_backgroundtask.c is gated, so the real one gives
    // CFE_ES_Global.BackgroundTask.WorkSem and time_sem_gives is what counts that.
    D(time_sem_gives);
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
    sb_queuecreate_rc = OS_SUCCESS;
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
    ta_cores = 1;
    irc = CFE_TA_TaskInit();
    S("ta_init rc=");
    D(irc);
    S(" pipes=");
    D(sb_qcreates);
    S(" subs=");
    D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
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
    // The create failure is now an OSAL error, and CFE_SB_CreatePipe turns it into
    // CFE_SB_PIPE_CR_ERR -- NASA's code deciding, where a stub used to return -78.
    sb_queuecreate_rc = OS_ERROR;
    irc = CFE_TA_TaskInit();
    S("ta_init_pipefail rc=");
    D(irc);
    S("\n");
    sb_queuecreate_rc = OS_SUCCESS;
    // And the subscribe failure is the destination block allocation failing, which is the one
    // real way CFE_SB_SubscribeFull fails for a caller who owns a valid pipe:
    // CFE_SB_DEST_BLK_ERR_EID and CFE_SB_BUF_ALOC_ERR.
    es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
    irc = CFE_TA_TaskInit();
    S("ta_init_subfail rc=");
    D(irc);
    S("\n");
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
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
    sb_tx_reset();
    crc = CFE_TA_ReportHousekeepingCmd(NULL);
    S("ta_hk rc=");
    D(crc);
    S(" tx=");
    D(sb_tx_since());
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
    // PROPERLY BASED IDS. These were a bare 1 and 2 while the *_ToIndex functions were stubs
    // that took a small id AS the index. The real CFE_ES_AppID_ToIndex subtracts
    // CFE_ES_APPID_BASE, so a bare 1 is out of range and EVS_GetAppDataByID returns NULL --
    // which this probe then dereferenced. The ids now match what es_ctx_init planted.
    U32 evsid = ES_CTX_APPID(1);
    U32 othrid = ES_CTX_APPID(2);
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
    sb_tx_reset();
    evs_printf_lines = 0;
    // --- CFE_EVS_Register -----------------------------------------------------------
    // The caller is whatever CFE_ES_GetAppID says, which this driver points at app 1.
    es_set_ctx(1);
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
    es_set_ctx(2);
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
    es_set_ctx(1);
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
    es_set_ctx(2);
    rc = CFE_EVS_ResetFilter(10);
    S("evs_resetf_unreg rc=");
    D(rc);
    S("\n");
    rc = CFE_EVS_ResetAllFilters();
    S("evs_resetall_unreg rc=");
    D(rc);
    S("\n");
    es_set_ctx(1);
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
    es_set_ctx(1);
    CFE_EVS_ResetAllFilters();
    CFE_EVS_Global.EVS_EventBurstMax = 0;
    CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = CFE_EVS_PORT1_BIT;
    ta_cores = 1;
    ta_evs_register_rc = CFE_SUCCESS;
    sb_queuecreate_rc = OS_SUCCESS;
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
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
    es_set_ctx(1);
    sb_queuecreate_rc = OS_SUCCESS;
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
    rc = CFE_EVS_TaskInit();
    S("evt_init rc=");
    D(rc);
    S(" appid=");
    D(CFE_ResourceId_ToInteger(CFE_EVS_Global.EVS_AppID));
    S("\n");
    sb_queuecreate_rc = OS_ERROR;
    rc = CFE_EVS_TaskInit();
    S("evt_init_pipefail rc=");
    D(rc);
    S("\n");
    sb_queuecreate_rc = OS_SUCCESS;
    es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
    rc = CFE_EVS_TaskInit();
    S("evt_init_subfail rc=");
    D(rc);
    S("\n");
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
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
    sb_tx_reset();
    rc = CFE_EVS_SendHkCmd(&evt_c.Buf);
    S("evt_hk rc=");
    D(rc);
    S(" tx=");
    D(sb_tx_since());
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
  // --- cfe_time_task.c, cfe_time_tone.c, cfe_time_dispatch.c, cfe_time_objtab.c ---------
  //
  // TIME AS A TASK, and before this block the module was only ever reached SIDEWAYS: EVS and TA
  // housekeeping call CFE_SB_TimeStampMsg, which calls CFE_TIME_GetTime, and CFE_TIME_Print
  // rendered the timestamps. So cfe_time_api.c and cfe_time_utils.c were gated for coverage,
  // signatures, constants and byte layout while the transcript exercised a handful of their
  // functions. The three sources below are the module's own behaviour, and they are the ones
  // where getting it wrong does not look like a crash.
  //
  // THE LOCAL CLOCK IS A VARIABLE IN THIS FILE (evs_psp_ns, read by CFE_PSP_GetTime), so every
  // number here is determined. That matters more for TIME than anywhere else in this gate: tone
  // validation is a COMPARISON of two latched clock values against a window, so a wall-clock
  // would make the answers un-pinnable.
  
  {
    CFE_TIME_ReferenceState_t *rs;
    U8 tcbuf[256];
    CFE_SB_Buffer *tb = tcbuf;
    CFE_TIME_SetLeapSecondsCmd_t *c_leaps = tcbuf;
    CFE_TIME_SetMETCmd_t *c_met = tcbuf;
    CFE_TIME_SetStateCmd_t *c_state = tcbuf;
    CFE_TIME_AddOneHzAdjustmentCmd_t *c_1hz = tcbuf;
    CFE_TIME_SetSourceCmd_t *c_source = tcbuf;
    CFE_TIME_SetSignalCmd_t *c_signal = tcbuf;
    CFE_TIME_AddDelayCmd_t *c_delay = tcbuf;
    time_binsem_rc = OS_SUCCESS;
    time_childtask_rc = CFE_SUCCESS;
    time_tb_rc = OS_ERROR;
    time_timeradd_rc = OS_SUCCESS;
    time_timerset_rc = OS_SUCCESS;
    // --- cfe_time_task.c: EarlyInit is CFE_TIME_InitData ------------------------------
    Rc("tim_earlyinit", CFE_TIME_EarlyInit());
    rs = CFE_TIME_GetReferenceState();
    S("tim_init src=");
    D(CFE_TIME_Global.ClockSource);
    S(" sig=");
    D(CFE_TIME_Global.ClockSignal);
    S(" fly=");
    D(CFE_TIME_Global.ServerFlyState);
    S(" vmet=");
    D(CFE_TIME_Global.VirtualMET);
    S(" minel=");
    D(CFE_TIME_Global.MinElapsed);
    S(" maxel=");
    D(CFE_TIME_Global.MaxElapsed);
    S("\n");
    S("tim_init2 maxlocal=");
    D(CFE_TIME_Global.MaxLocalClock.Seconds);
    S(".");
    D(CFE_TIME_Global.MaxLocalClock.Subseconds);
    S(" over=");
    D(CFE_TIME_Global.ToneOverLimit);
    S(" under=");
    D(CFE_TIME_Global.ToneUnderLimit);
    S(" setstate=");
    D(rs->ClockSetState);
    S(" flystate=");
    D(rs->ClockFlyState);
    S("\n");
    // --- cfe_time_task.c: TaskInit, and its five failure paths ------------------------
    // Each of the five is reached by making exactly one stub fail, and each returns a DIFFERENT
    // status -- which is the property worth pinning, because a TaskInit that returned
    // CFE_SUCCESS from a failed semaphore create would start two child tasks that pend on
    // nothing. The statuses print as SIGNED DECIMAL for the reason the C half records.
    time_binsem_rc = OS_ERROR;
    // THE CALL FIRST, THEN THE LABEL. printf evaluates its arguments before it emits anything,
    // so the C half's syslog lines come out ahead of the tim_ line; `S("label"); D(f())` emits
    // the label and then runs f, which drops f's own output into the middle of this line. That
    // is what the first version of this block did, and the diff showed the syslog text spliced
    // in after `rc=`. Every call below is hoisted for the same reason.
    rc32 = CFE_TIME_TaskInit();
    S("tim_init_semfail rc=");
    D(rc32);
    S(" sems=");
    D(time_sems_created);
    S("\n");
    time_binsem_rc = OS_SUCCESS;
    time_childtask_rc = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    rc32 = CFE_TIME_TaskInit();
    S("tim_init_taskfail rc=");
    D(rc32);
    S(" tasks=");
    D(time_childtasks);
    S("\n");
    time_childtask_rc = CFE_SUCCESS;
    sb_queuecreate_rc = OS_ERROR;
    rc32 = CFE_TIME_TaskInit();
    S("tim_init_pipefail rc=");
    D(rc32);
    S("\n");
    sb_queuecreate_rc = OS_SUCCESS;
    es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
    rc32 = CFE_TIME_TaskInit();
    S("tim_init_subfail rc=");
    D(rc32);
    S(" subs=");
    D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
    S("\n");
    es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
    rc32 = CFE_TIME_TaskInit();
    S("tim_init rc=");
    D(rc32);
    S(" sems=");
    D(time_sems_created);
    S(" tasks=");
    D(time_childtasks);
    S(" subs=");
    D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
    S(" tb=");
    D(time_tb_lookups);
    S(" timers=");
    D(time_timer_adds);
    S("\n");
    // ...and again with a timebase present, which is the only way OS_TimerAdd/OS_TimerSet are
    // reached at all.
    time_tb_rc = OS_SUCCESS;
    rc32 = CFE_TIME_TaskInit();
    S("tim_init_tb rc=");
    D(rc32);
    S(" adds=");
    D(time_timer_adds);
    S(" sets=");
    D(time_timer_sets);
    S("\n");
    time_timerset_rc = OS_ERROR;
    rc32 = CFE_TIME_TaskInit();
    S("tim_init_tbsetfail rc=");
    D(rc32);
    S(" sets=");
    D(time_timer_sets);
    S("\n");
    time_timerset_rc = OS_SUCCESS;
    time_tb_rc = OS_ERROR;
    // --- cfe_time_tone.c: the 1Hz tone interrupt -------------------------------------
    // A tone is VALID when it lands about one second after the previous one, and the window is
    // ToneUnderLimit..ToneOverLimit in subseconds. Three tones: one that establishes the
    // previous latch, one a clean second later, and one only half a second later.
    //
    // ONE SECOND IS 10,000,000 TICKS, not 1,000,000,000: OS_TIME_TICKS_PER_SECOND is 1e7 because
    // a tick is 100 ns. The first draft stepped by 1e9 and every tone came back INVALID with the
    // window never reached, which looked like a translation bug and was an arithmetic one in the
    // DRIVER. Everything here also stays under MaxLocalClock, 27 seconds, because past that the
    // local clock rolls over and TimeSinceTone stops meaning what the names say.
    evs_psp_ns = 10000000;
    CFE_TIME_Tone1HzISR();
    S("tim_tone1 int=");
    D(CFE_TIME_Global.ToneIntCounter);
    S(" err=");
    D(CFE_TIME_Global.ToneIntErrorCounter);
    S(" vmet=");
    D(CFE_TIME_Global.VirtualMET);
    S(" good=");
    D(CFE_TIME_Global.IsToneGood);
    S("\n");
    evs_psp_ns += 10000000;
    CFE_TIME_Tone1HzISR();
    S("tim_tone2 int=");
    D(CFE_TIME_Global.ToneIntCounter);
    S(" err=");
    D(CFE_TIME_Global.ToneIntErrorCounter);
    S(" vmet=");
    D(CFE_TIME_Global.VirtualMET);
    S(" good=");
    D(CFE_TIME_Global.IsToneGood);
    S(" gives=");
    D(time_sem_gives);
    S("\n");
    evs_psp_ns += 5000000;
    CFE_TIME_Tone1HzISR();
    S("tim_tone_early int=");
    D(CFE_TIME_Global.ToneIntCounter);
    S(" err=");
    D(CFE_TIME_Global.ToneIntErrorCounter);
    S(" vmet=");
    D(CFE_TIME_Global.VirtualMET);
    S(" good=");
    D(CFE_TIME_Global.IsToneGood);
    S("\n");
    // --- cfe_time_tone.c: ToneSend builds the "time at the tone" packet --------------
    CFE_TIME_ToneSend();
    S("tim_tonesend internal=");
    D(CFE_TIME_Global.InternalCount);
    S(" met=");
    D(CFE_TIME_Global.ToneDataCmd.Payload.AtToneMET.Seconds);
    S(".");
    D(CFE_TIME_Global.ToneDataCmd.Payload.AtToneMET.Subseconds);
    S(" stcf=");
    D(CFE_TIME_Global.ToneDataCmd.Payload.AtToneSTCF.Seconds);
    S(".");
    D(CFE_TIME_Global.ToneDataCmd.Payload.AtToneSTCF.Subseconds);
    S(" leaps=");
    D(CFE_TIME_Global.ToneDataCmd.Payload.AtToneLeapSeconds);
    S(" state=");
    D(CFE_TIME_Global.ToneDataCmd.Payload.AtToneState);
    S("\n");
    // --- cfe_time_tone.c: ToneData, ToneVerify and the DUPLICATE REJECTION ------------
    // The second call passes the IDENTICAL pair, and NASA's two function-static PrevTime1 /
    // PrevTime2 are what notice. That is the only place in TIME whose correctness depends on a
    // static local keeping its value between calls, so the match counter not moving on the
    // second call is what says the statics work (tests/exec/cases/e_static_local_class_zero.hc
    // gates the compiler property itself).
    CFE_TIME_ToneData(&CFE_TIME_Global.ToneDataCmd.Payload);
    S("tim_tonedata data=");
    D(CFE_TIME_Global.ToneDataCounter);
    S(" match=");
    D(CFE_TIME_Global.ToneMatchCounter);
    S(" matcherr=");
    D(CFE_TIME_Global.ToneMatchErrorCounter);
    S(" pend=");
    D(CFE_TIME_Global.PendingMET.Seconds);
    S(".");
    D(CFE_TIME_Global.PendingMET.Subseconds);
    S(" pstate=");
    D(CFE_TIME_Global.PendingState);
    S("\n");
    CFE_TIME_ToneData(&CFE_TIME_Global.ToneDataCmd.Payload);
    S("tim_tonedup data=");
    D(CFE_TIME_Global.ToneDataCounter);
    S(" match=");
    D(CFE_TIME_Global.ToneMatchCounter);
    S(" matcherr=");
    D(CFE_TIME_Global.ToneMatchErrorCounter);
    S("\n");
    CFE_TIME_ToneSignal();
    S("tim_tonesig sig=");
    D(CFE_TIME_Global.ToneSignalCounter);
    S("\n");
    // --- cfe_time_tone.c: the local 1Hz ISR and the two child-task loops --------------
    CFE_TIME_Local1HzISR();
    S("tim_local1hz lint=");
    D(CFE_TIME_Global.LocalIntCounter);
    S(" gives=");
    D(time_sem_gives);
    S("\n");
    time_sem_take_budget = 2;
    CFE_TIME_Tone1HzTask();
    S("tim_tonetask tasks=");
    D(CFE_TIME_Global.ToneTaskCounter);
    S(" takes=");
    D(time_sem_takes);
    S("\n");
    time_sem_take_budget = 2;
    CFE_TIME_Local1HzTask();
    S("tim_localtask tasks=");
    D(CFE_TIME_Global.LocalTaskCounter);
    S(" takes=");
    D(time_sem_takes);
    S(" autofly=");
    D(CFE_TIME_Global.AutoStartFly);
    S("\n");
    // --- cfe_time_tone.c: Local1HzStateMachine enters FLYWHEEL -----------------------
    // CFE_PLATFORM_TIME_CFG_START_FLY is 2 seconds since the last tone, so the clock jumps three
    // seconds forward and the state machine has to notice by itself.
    evs_psp_ns += 30000000;
    CFE_TIME_Local1HzStateMachine();
    rs = CFE_TIME_GetReferenceState();
    S("tim_fly fly=");
    D(rs->ClockFlyState);
    S(" autofly=");
    D(CFE_TIME_Global.AutoStartFly);
    S(" serverfly=");
    D(CFE_TIME_Global.ServerFlyState);
    S("\n");
    // ...and LATCH_FLY (8 s) rolls the time-at-tone forward while flywheeling.
    evs_psp_ns += 90000000;
    CFE_TIME_Local1HzStateMachine();
    rs = CFE_TIME_GetReferenceState();
    S("tim_fly_latch met=");
    D(rs->AtToneMET.Seconds);
    S(".");
    D(rs->AtToneMET.Subseconds);
    S(" latch=");
    D(rs->AtToneLatch.Seconds);
    S(".");
    D(rs->AtToneLatch.Subseconds);
    S("\n");
    // --- cfe_time_tone.c: NotifyTimeSynchApps calls through a function pointer --------
    CFE_TIME_Global.SynchCallback[0].Ptr = &TimeSynchProbe;
    CFE_TIME_Global.IsToneGood = FALSE;
    CFE_TIME_NotifyTimeSynchApps();
    S("tim_synch_badtone calls=");
    D(time_synch_calls);
    S("\n");
    CFE_TIME_Global.IsToneGood = TRUE;
    CFE_TIME_NotifyTimeSynchApps();
    S("tim_synch calls=");
    D(time_synch_calls);
    S("\n");
    CFE_TIME_Global.SynchCallback[0].Ptr = NULL;
    // --- cfe_time_dispatch.c: the GROUND COMMANDS ------------------------------------
    // Two levels of routing, and the counters are what tell them apart: an unrecognised MESSAGE
    // ID is an event and nothing else, while an unrecognised COMMAND CODE and a wrong LENGTH
    // both bump CommandErrorCounter.
    CFE_TIME_Global.CommandCounter = 0;
    CFE_TIME_Global.CommandErrorCounter = 0;
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_NoopCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_NOOP_CC);
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_noop ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    // a recognised code with the WRONG length
    CFE_MSG_SetSize(&tb->Msg, sizeof(CFE_TIME_NoopCmd_t) + 4);
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_badlen ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    // an unrecognised command code
    CFE_MSG_SetSize(&tb->Msg, sizeof(CFE_TIME_NoopCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, 99);
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_badcc ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    // an unrecognised MESSAGE id: an event, and NEITHER counter moves
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(0x18FF), sizeof(CFE_TIME_NoopCmd_t));
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_badmid ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    // the four non-ground message ids this task subscribes to
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_SEND_HK_MID), sizeof(CFE_TIME_SendHkCmd_t));
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_hk ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S(" transmits=");
    D(sb_tx_since());
    S("\n");
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_TONE_CMD_MID), sizeof(CFE_TIME_ToneSignalCmd_t));
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_tonesig sig=");
    D(CFE_TIME_Global.ToneSignalCounter);
    S("\n");
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_SEND_CMD_MID), sizeof(CFE_TIME_FakeToneCmd_t));
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_tonesend internal=");
    D(CFE_TIME_Global.InternalCount);
    S("\n");
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_ONEHZ_CMD_MID), sizeof(CFE_TIME_OneHzCmd_t));
    CFE_TIME_TaskPipe(tb);
    S("tim_cmd_onehz lint=");
    D(CFE_TIME_Global.LocalIntCounter);
    S(" int=");
    D(CFE_TIME_Global.ToneIntCounter);
    S(" err=");
    D(CFE_TIME_Global.ToneIntErrorCounter);
    S("\n");
    // --- cfe_time_task.c: the SERVER commands this build really executes --------------
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_SetLeapSecondsCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_SET_LEAP_SECONDS_CC);
    c_leaps->Payload.LeapSeconds = 37;
    CFE_TIME_TaskPipe(tb);
    rs = CFE_TIME_GetReferenceState();
    S("tim_setleaps ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" leaps=");
    D(rs->AtToneLeapSeconds);
    S("\n");
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_SetMETCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_SET_MET_CC);
    c_met->Payload.Seconds = 1000;
    c_met->Payload.MicroSeconds = 500000;
    CFE_TIME_TaskPipe(tb);
    rs = CFE_TIME_GetReferenceState();
    S("tim_setmet ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" met=");
    D(rs->AtToneMET.Seconds);
    S(".");
    D(rs->AtToneMET.Subseconds);
    S("\n");
    // and the rejected form: a microseconds value that is not microseconds
    c_met->Payload.MicroSeconds = 1000000;
    CFE_TIME_TaskPipe(tb);
    S("tim_setmet_bad ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_SetStateCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_SET_STATE_CC);
    c_state->Payload.ClockState = CFE_TIME_ClockState_VALID;
    CFE_TIME_TaskPipe(tb);
    rs = CFE_TIME_GetReferenceState();
    S("tim_setstate ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" setstate=");
    D(rs->ClockSetState);
    S("\n");
    c_state->Payload.ClockState = 99;
    CFE_TIME_TaskPipe(tb);
    S("tim_setstate_bad err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_AddOneHzAdjustmentCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_ADD_ONE_HZ_ADJUSTMENT_CC);
    c_1hz->Payload.Seconds = 1;
    c_1hz->Payload.Subseconds = 0x20000000;
    CFE_TIME_TaskPipe(tb);
    S("tim_add1hz ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" adj=");
    D(CFE_TIME_Global.OneHzAdjust.Seconds);
    S(".");
    D(CFE_TIME_Global.OneHzAdjust.Subseconds);
    S(" dir=");
    D(CFE_TIME_Global.OneHzDirection);
    S("\n");
    // the 1Hz adjustment is APPLIED by the state machine, not by the command
    CFE_TIME_Local1HzStateMachine();
    rs = CFE_TIME_GetReferenceState();
    S("tim_1hz_applied stcf=");
    D(rs->AtToneSTCF.Seconds);
    S(".");
    D(rs->AtToneSTCF.Subseconds);
    S("\n");
    CFE_TIME_Global.OneHzAdjust.Seconds = 0;
    CFE_TIME_Global.OneHzAdjust.Subseconds = 0;
    // --- cfe_time_task.c: the four commands this CONFIGURATION disables ---------------
    // SetSource and SetSignal need CFE_PLATFORM_TIME_CFG_SOURCE / _SIGNAL, and the two delay
    // commands need _CLIENT. All three are 0 here, so the branch that runs is NASA's "invalid
    // without ..." one -- which still COUNTS the command and reports it. That branch is the one
    // this build exercises, and it is easy to mistake for unimplemented.
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_SetSourceCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_SET_SOURCE_CC);
    c_source->Payload.TimeSource = CFE_TIME_SourceSelect_EXTERNAL;
    CFE_TIME_TaskPipe(tb);
    S("tim_setsource_cfg ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    c_source->Payload.TimeSource = 99;
    CFE_TIME_TaskPipe(tb);
    S("tim_setsource_bad err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_SetSignalCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_SET_SIGNAL_CC);
    c_signal->Payload.ToneSource = CFE_TIME_ToneSignalSelect_REDUNDANT;
    CFE_TIME_TaskPipe(tb);
    S("tim_setsignal_cfg err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_AddDelayCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_ADD_DELAY_CC);
    c_delay->Payload.Seconds = 0;
    c_delay->Payload.MicroSeconds = 1000;
    CFE_TIME_TaskPipe(tb);
    S("tim_adddelay_cfg err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    c_delay->Payload.MicroSeconds = 1000000;
    CFE_TIME_TaskPipe(tb);
    S("tim_adddelay_bad err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S("\n");
    // --- cfe_time_task.c: diagnostics and ResetCounters ------------------------------
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_SendDiagnosticCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_SEND_DIAGNOSTIC_CC);
    CFE_TIME_TaskPipe(tb);
    S("tim_diag ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" atmet=");
    D(CFE_TIME_Global.DiagPacket.Payload.AtToneMET.Seconds);
    S(".");
    D(CFE_TIME_Global.DiagPacket.Payload.AtToneMET.Subseconds);
    S(" leaps=");
    D(CFE_TIME_Global.DiagPacket.Payload.AtToneLeapSeconds);
    S(" state=");
    D(CFE_TIME_Global.DiagPacket.Payload.ClockStateAPI);
    S("\n");
    MemSet(tcbuf, 0, sizeof(tcbuf));
    CFE_MSG_Init(&tb->Msg, CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), sizeof(CFE_TIME_ResetCountersCmd_t));
    CFE_MSG_SetFcnCode(&tb->Msg, CFE_TIME_RESET_COUNTERS_CC);
    CFE_TIME_TaskPipe(tb);
    S("tim_reset ok=");
    D(CFE_TIME_Global.CommandCounter);
    S(" err=");
    D(CFE_TIME_Global.CommandErrorCounter);
    S(" tone=");
    D(CFE_TIME_Global.ToneMatchCounter);
    S(" toneerr=");
    D(CFE_TIME_Global.ToneMatchErrorCounter);
    S(" int=");
    D(CFE_TIME_Global.ToneIntCounter);
    S(" internal=");
    D(CFE_TIME_Global.InternalCount);
    S("\n");
    // --- cfe_sb_init.c and cfe_sb_buf.c: SB's BUFFER LIFETIME --------------------------
    //
    // The whole of cfe_sb_buf.c is one invariant: a buffer is freed when the LAST reference to it
    // goes away. A message transmitted to three subscribed pipes is ONE buffer with UseCount 3,
    // and the third release is what returns it to the pool. The pool on this side is a real bump
    // allocator for that reason -- a stub handing back one address would make the accounting
    // agree with itself and prove nothing.
    //
    // The tracking list is a circular doubly-linked list whose EMPTY state points at itself,
    // which is what removes every null check from Add and Remove. The identity comparisons below
    // are how that is observable: "is this node its own next" is the empty test.
    
    {
      CFE_SB_BufferD_t *b1;
      CFE_SB_BufferD_t *b2;
      CFE_SB_DestinationD_t *d1;
      CFE_SB_MsgId sbmid = CFE_SB_InvalidMsgId;
      I64 sbsz = 0;
      es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
      // THE CALL FIRST, THEN THE LABEL -- printf evaluates its arguments before it emits
      // anything, and `S("label"); D(f())` does not. cfe_time_task's block records what that
      // cost the first time.
      rc32 = CFE_SB_EarlyInit();
      S("sb_earlyinit rc=");
      D(rc32);
      S(" pools=");
      D(es_pool_creates());
      S(" gets=");
      D(es_pool_gets());
      S(" subrep=");
      D(CFE_SB_Global.SubscriptionReporting);
      S("\n");
      S("sb_init_lists intransit_self=");
      D(CFE_SB_Global.InTransitList.Next == &CFE_SB_Global.InTransitList && CFE_SB_Global.InTransitList.Prev == &CFE_SB_Global.InTransitList);
      S(" zerocopy_self=");
      D(CFE_SB_Global.ZeroCopyList.Next == &CFE_SB_Global.ZeroCopyList && CFE_SB_Global.ZeroCopyList.Prev == &CFE_SB_Global.ZeroCopyList);
      S("\n");
      S("sb_init_pipe lastpipe=0x");
      Hx8(CFE_ResourceId_ToInteger(CFE_SB_Global.LastPipeId));
      S("\n");
      CFE_MSG_GetMsgId(&CFE_SB_Global.StatTlmMsg.TelemetryHeader.Msg, &sbmid);
      CFE_MSG_GetSize(&CFE_SB_Global.StatTlmMsg.TelemetryHeader.Msg, &sbsz);
      S("sb_init_stats mid=0x");
      Hx8(CFE_SB_MsgIdToValue(sbmid));
      S(" size=");
      D(sbsz);
      S("\n");
      // The two failure paths, each by failing exactly one call. The mutex one returns
      // CFE_STATUS_EXTERNAL_RESOURCE_FAIL rather than OSAL's own code, which is the thing worth
      // pinning: EarlyInit translates OSAL failures into cFE ones.
      fs_mut_create_rc = OS_ERROR;
      rc32 = CFE_SB_EarlyInit();
      S("sb_earlyinit_mutexfail rc=");
      D(rc32);
      S("\n");
      fs_mut_create_rc = OS_SUCCESS;
      // THE POOL-CREATE FAILURE PATH IS NOT DRIVEN, and the reason is a real limit on this
      // whole method rather than a gap in the driver. NASA's own diagnostic is
      //   CFE_ES_WriteToSysLog("%s: PoolCreate failed for SB Buffers, gave adr 0x%lx,...")
      // and that %lx is the PARTITION'S ADDRESS. This gate compares a transcript from NASA's C
      // on the host against this code under QEMU, in a different address space, so a line
      // carrying a pointer cannot agree however correct both sides are -- and NASA's C is
      // compiled UNMODIFIED, so the format is not ours to change. The mutex path above is driven
      // because its diagnostic carries only an integer. docs/CFS_PLAN.md records the constraint.
      //
      // AND THIS CALL IS LOAD-BEARING. The mutex-failure run above returns EARLY, before
      // CFE_SB_InitBuffers -- so it leaves the global MEMSET AND ABANDONED, with both
      // tracking-list heads NULL rather than pointing at themselves, and the next
      // CFE_SB_TrackingListAdd dereferences NULL.
      CFE_SB_EarlyInit();
      // A buffer. AllocatedSize is the request PLUS the descriptor header, which is what
      // CFE_SB_BUFFERD_CONTENT_OFFSET is for, and this side spells that number out because HolyC
      // has no offsetof -- so these two numbers agreeing is the check that the spelled-out 56 is
      // right. It was 48 for one run, and this line is what said so.
      b1 = CFE_SB_GetBufferFromPool(100);
      S("sb_getbuf nonnull=");
      D(b1 != NULL);
      S(" use=");
      D(b1->UseCount);
      S(" alloc=");
      D(b1->AllocatedSize);
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S(" peak=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PeakSBBuffersInUse);
      S(" mem=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
      S("\n");
      S("sb_getbuf_link singleton=");
      D(b1->Link.Next == &b1->Link && b1->Link.Prev == &b1->Link);
      S("\n");
      // The tracking list, observed by identity rather than by a count.
      CFE_SB_TrackingListAdd(&CFE_SB_Global.InTransitList, &b1->Link);
      S("sb_listadd head_next_b1=");
      D(CFE_SB_Global.InTransitList.Next == &b1->Link);
      S(" b1_next_head=");
      D(b1->Link.Next == &CFE_SB_Global.InTransitList);
      S(" b1_prev_head=");
      D(b1->Link.Prev == &CFE_SB_Global.InTransitList);
      S("\n");
      b2 = CFE_SB_GetBufferFromPool(200);
      CFE_SB_TrackingListAdd(&CFE_SB_Global.InTransitList, &b2->Link);
      S("sb_listadd2 head_prev_b2=");
      D(CFE_SB_Global.InTransitList.Prev == &b2->Link);
      S(" b1_next_b2=");
      D(b1->Link.Next == &b2->Link);
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S(" mem=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
      S("\n");
      CFE_SB_TrackingListRemove(&b1->Link);
      S("sb_listremove head_next_b2=");
      D(CFE_SB_Global.InTransitList.Next == &b2->Link);
      S(" b1_singleton=");
      D(b1->Link.Next == &b1->Link && b1->Link.Prev == &b1->Link);
      S("\n");
      // THREE REFERENCES, THREE RELEASES, and the pool sees exactly one free -- on the third. b2
      // is still on the in-transit list, so the free path also has to take it off, which is why
      // ReturnBufferToPool calls TrackingListRemove unconditionally.
      CFE_SB_IncrBufUseCnt(b2);
      CFE_SB_IncrBufUseCnt(b2);
      S("sb_use3 use=");
      D(b2->UseCount);
      S(" puts=");
      D(es_pool_puts());
      S("\n");
      CFE_SB_DecrBufUseCnt(b2);
      S("sb_use2 use=");
      D(b2->UseCount);
      S(" puts=");
      D(es_pool_puts());
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S("\n");
      CFE_SB_DecrBufUseCnt(b2);
      S("sb_use1 use=");
      D(b2->UseCount);
      S(" puts=");
      D(es_pool_puts());
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S("\n");
      CFE_SB_DecrBufUseCnt(b2);
      S("sb_use0 puts=");
      D(es_pool_puts());
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S(" mem=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
      S(" head_self=");
      D(CFE_SB_Global.InTransitList.Next == &CFE_SB_Global.InTransitList);
      S("\n");
      // The 0x7FFF ceiling: NASA leaves the top bit of a uint16 alone, so a count that has run
      // away stops climbing instead of wrapping to zero and freeing a live buffer.
      b1->UseCount = 0x7FFE;
      CFE_SB_IncrBufUseCnt(b1);
      S("sb_use_below use=");
      D(b1->UseCount);
      S("\n");
      CFE_SB_IncrBufUseCnt(b1);
      S("sb_use_ceiling use=");
      D(b1->UseCount);
      S("\n");
      // ...and a decrement at zero does nothing, rather than wrapping to 0xFFFF
      b1->UseCount = 0;
      CFE_SB_DecrBufUseCnt(b1);
      S("sb_use_floor use=");
      D(b1->UseCount);
      S(" puts=");
      D(es_pool_puts());
      S("\n");
      // Destination blocks. MemInUse follows the POOL's returned size, not the requested one,
      // because a real pool rounds up to a block size.
      d1 = CFE_SB_GetDestinationBlk();
      S("sb_getdest nonnull=");
      D(d1 != NULL);
      S(" mem=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
      S("\n");
      rc32 = CFE_SB_PutDestinationBlk(d1);
      S("sb_putdest rc=");
      D(rc32);
      S(" mem=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MemInUse);
      S("\n");
      rc32 = CFE_SB_PutDestinationBlk(NULL);
      S("sb_putdest_null rc=");
      D(rc32);
      S("\n");
      // And the allocation failure path: a null back, and NO counter moved.
      es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
      b2 = CFE_SB_GetBufferFromPool(100);
      S("sb_getbuf_fail null=");
      D(b2 == NULL);
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S("\n");
      d1 = CFE_SB_GetDestinationBlk();
      // EXHAUSTING THE TAIL IS NOT THE SAME AS AN EMPTY POOL. A 156-byte buffer request fails:
      // no 156-byte block is on the free stack and there is no room to create one. A 32-byte
      // DESTINATION request SUCCEEDS, because sb_putdest above returned a 32-byte block and the
      // real pool RECYCLES it. The simulated bump allocator would have returned NULL for both.
      // This was called sb_getdest_fail and asserted a failure that stopped happening the
      // moment NASA's pool was gated.
      S("sb_getdest_recycled null=");
      D(d1 == NULL);
      S("\n");
      es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
    }
    // --- cfe_sb_priv.c: the pipe table, the destination list, the recursion guard ------
    //
    // Everything here is reachable WITHOUT a pipe existing, which is the half of cfe_sb_priv.c
    // that does not depend on cfe_sb_api.c. The transaction EXECUTION paths need real pipes and
    // queues and come with api.c.
    
    {
      CFE_SB_PipeD_t *pd;
      CFE_SB_DestinationD_t d1;
      CFE_SB_DestinationD_t d2;
      CFE_SB_DestinationD_t d3;
      CFE_SBR_RouteId rid;
      CFE_SB_TransmitTxn_State_t ttxn;
      CFE_SB_ReceiveTxn_State_t rtxn;
      CFE_SB_MessageTxn_State_t *txn;
      U8 tskname[OS_MAX_API_NAME * 2];
      I64 v1, v2;
      v1 = CFE_SB_ValidateMsgId(CFE_SB_ValueToMsgId(CFE_SB_CMD_MID));
      v2 = CFE_SB_ValidateMsgId(CFE_SB_InvalidMsgId);
      S("sbp_validmsgid ok=");
      D(v1);
      S(" bad=");
      D(v2);
      S("\n");
      // The pipe table: locate in range, locate out of range, and the used/free flag.
      //
      // THE ID HAS TO CARRY THE BASE NOW. This probe used to pass a bare 3, which worked
      // because CFE_SB_PipeId_ToIndex was stubbed here as `id & 0xFF`. The real one
      // (cfe_sb_api.HC) subtracts CFE_SB_PIPEID_BASE and range-checks, so a bare 3 is not a
      // pipe id at all: Locate returned NULL and the next line wrote through it. A stub that
      // is more permissive than the thing it stands in for does not fail when it is replaced
      // -- it moves the failure to the caller.
      pd = CFE_SB_LocatePipeDescByID(CFE_SB_PIPEID_BASE + 3);
      S("sbp_locate inrange=");
      D(pd != NULL);
      S(" used=");
      D(pd != NULL && CFE_SB_PipeDescIsUsed(pd));
      S(" outofrange=");
      D(CFE_SB_LocatePipeDescByID(3) == NULL);
      S("\n");
      CFE_SB_PipeDescSetUsed(pd, 0x1234);
      S("sbp_setused used=");
      D(CFE_SB_PipeDescIsUsed(pd));
      S(" id=0x");
      Hx8(CFE_SB_PipeDescGetID(pd));
      S(" match=");
      D(CFE_SB_PipeDescIsMatch(pd, 0x1234));
      S("\n");
      S("sbp_slotused=");
      D(CFE_SB_CheckPipeDescSlotUsed(CFE_SB_PIPEID_BASE + 3));
      S("\n");
      CFE_SB_PipeDescSetFree(pd);
      S("sbp_setfree used=");
      D(CFE_SB_PipeDescIsUsed(pd));
      S(" nullmatch=");
      D(CFE_SB_PipeDescIsMatch(NULL, 3));
      S("\n");
      // THE RECURSION GUARD: granted once, denied while held, granted again after finish. A
      // negative bit is always granted -- that is how the receive-side events opt out.
      v1 = CFE_SB_RequestToSendEvent(1, 3);
      v2 = CFE_SB_RequestToSendEvent(1, 3);
      S("sbp_guard a=");
      D(v1);
      S(" b=");
      D(v2);
      CFE_SB_FinishSendEvent(1, 3);
      v1 = CFE_SB_RequestToSendEvent(1, 3);
      v2 = CFE_SB_RequestToSendEvent(1, -1);
      S(" c=");
      D(v1);
      S(" neg=");
      D(v2);
      S("\n");
      CFE_SB_FinishSendEvent(1, 3);
      // The app.task name, both branches.
      S("sbp_tskname ");
      S(CFE_SB_GetAppTskName(1, tskname));
      S("\n");
      sb_taskinfo_rc = CFE_ES_ERR_RESOURCEID_NOT_VALID;
      S("sbp_tskname_bad ");
      S(CFE_SB_GetAppTskName(1, tskname));
      S("\n");
      sb_taskinfo_rc = CFE_SUCCESS;
      // THE DESTINATION LIST. Three nodes, inserted at the FRONT each time, then removed from
      // the middle, the end and finally as the only one -- the four branches of
      // CFE_SB_RemoveDestNode, which is the function whose pointer surgery a count cannot check.
      rid = CFE_SBR_AddRoute(CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), NULL);
      MemSet(&d1, 0, sizeof(CFE_SB_DestinationD_t));
      MemSet(&d2, 0, sizeof(CFE_SB_DestinationD_t));
      MemSet(&d3, 0, sizeof(CFE_SB_DestinationD_t));
      d1.PipeId = 11;
      d2.PipeId = 12;
      d3.PipeId = 13;
      CFE_SB_AddDestNode(rid, &d1);
      CFE_SB_AddDestNode(rid, &d2);
      CFE_SB_AddDestNode(rid, &d3);
      S("sbp_destadd head_d3=");
      D(CFE_SBR_GetDestListHeadPtr(rid) == &d3);
      S(" d3_next_d2=");
      D(d3.Next == &d2);
      S(" d1_next_null=");
      D(d1.Next == NULL);
      S("\n");
      S("sbp_destfind d2=");
      D(CFE_SB_GetDestPtr(rid, d2.PipeId) == &d2);
      S(" miss=");
      D(CFE_SB_GetDestPtr(rid, 99) == NULL);
      S("\n");
      CFE_SB_RemoveDestNode(rid, &d2);
      // middle
      S("sbp_destrm_mid d3_next_d1=");
      D(d3.Next == &d1);
      S(" d1_prev_d3=");
      D(d1.Prev == &d3);
      S(" d2_clear=");
      D(d2.Next == NULL && d2.Prev == NULL);
      S("\n");
      CFE_SB_RemoveDestNode(rid, &d1);
      // last
      S("sbp_destrm_last d3_next_null=");
      D(d3.Next == NULL);
      S(" head_d3=");
      D(CFE_SBR_GetDestListHeadPtr(rid) == &d3);
      S("\n");
      CFE_SB_RemoveDestNode(rid, &d3);
      // only
      S("sbp_destrm_only head_null=");
      D(CFE_SBR_GetDestListHeadPtr(rid) == NULL);
      S("\n");
      // THE TRANSACTION SETTERS. First writer wins, independently, for the event and the status.
      txn = CFE_SB_TransmitTxn_Init(&ttxn, &ttxn);
      S("sbp_txn_init ok=");
      D(CFE_SB_MessageTxn_IsOK(txn));
      S(" transmit=");
      D(txn->IsTransmit);
      S(" maxpipes=");
      D(txn->MaxPipes);
      S(" status=");
      D(CFE_SB_MessageTxn_GetStatus(txn));
      S("\n");
      CFE_SB_MessageTxn_SetContentSize(txn, 100);
      S("sbp_txn_size ok=");
      D(CFE_SB_MessageTxn_IsOK(txn));
      S(" size=");
      D(CFE_SB_MessageTxn_GetContentSize(txn));
      S("\n");
      CFE_SB_MessageTxn_SetRoutingMsgId(txn, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID));
      S("sbp_txn_mid ok=");
      D(CFE_SB_MessageTxn_IsOK(txn));
      S(" mid=0x");
      Hx8(CFE_SB_MsgIdToValue(CFE_SB_MessageTxn_GetRoutingMsgId(txn)));
      S("\n");
      // too big, then an invalid id: the FIRST failure keeps both fields
      CFE_SB_MessageTxn_SetContentSize(txn, CFE_MISSION_SB_MAX_SB_MSG_SIZE + 1);
      S("sbp_txn_toobig ok=");
      D(CFE_SB_MessageTxn_IsOK(txn));
      S(" evt=");
      D(txn->TransactionEventId);
      S(" status=");
      D(CFE_SB_MessageTxn_GetStatus(txn));
      S(" size=");
      D(CFE_SB_MessageTxn_GetContentSize(txn));
      S("\n");
      CFE_SB_MessageTxn_SetRoutingMsgId(txn, CFE_SB_InvalidMsgId);
      S("sbp_txn_firstwins evt=");
      D(txn->TransactionEventId);
      S(" status=");
      D(CFE_SB_MessageTxn_GetStatus(txn));
      S("\n");
      // The timeout modes, including the rejected one.
      txn = CFE_SB_ReceiveTxn_Init(&rtxn, &rtxn);
      CFE_SB_MessageTxn_SetTimeout(txn, CFE_SB_POLL);
      v1 = CFE_SB_MessageTxn_GetOsTimeout(txn);
      S("sbp_timeout poll=");
      D(txn->TimeoutMode);
      S(" os=");
      D(v1);
      CFE_SB_MessageTxn_SetTimeout(txn, CFE_SB_PEND_FOREVER);
      v1 = CFE_SB_MessageTxn_GetOsTimeout(txn);
      S(" pend=");
      D(txn->TimeoutMode);
      S(" os=");
      D(v1);
      CFE_SB_MessageTxn_SetTimeout(txn, -99);
      S(" bad_evt=");
      D(txn->TransactionEventId);
      S(" status=");
      D(CFE_SB_MessageTxn_GetStatus(txn));
      S("\n");
      // A NULL reference pointer is rejected, with a DIFFERENT event per direction.
      txn = CFE_SB_TransmitTxn_Init(&ttxn, NULL);
      S("sbp_null_tx evt=");
      D(txn->TransactionEventId);
      S(" status=");
      D(CFE_SB_MessageTxn_GetStatus(txn));
      S("\n");
      txn = CFE_SB_ReceiveTxn_Init(&rtxn, NULL);
      S("sbp_null_rx evt=");
      D(txn->TransactionEventId);
      S(" status=");
      D(CFE_SB_MessageTxn_GetStatus(txn));
      S(" endpoint=");
      D(txn->IsEndpoint);
      S("\n");
      CFE_SB_MessageTxn_SetEndpoint(txn, TRUE);
      S("sbp_endpoint=");
      D(txn->IsEndpoint);
      S("\n");
      // The subscribe counters: six event ids mean "failed", one means "duplicate".
      CFE_SB_Global.HKTlmMsg.Payload.SubscribeErrorCounter = 0;
      CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter = 0;
      CFE_SB_IncrementSubscribeCounters(CFE_SB_SUB_INV_PIPE_EID);
      CFE_SB_IncrementSubscribeCounters(CFE_SB_MAX_DESTS_MET_EID);
      CFE_SB_IncrementSubscribeCounters(CFE_SB_DUP_SUBSCRIP_EID);
      CFE_SB_IncrementSubscribeCounters(CFE_SB_INIT_EID);
      // not an error
      S("sbp_subcnt err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.SubscribeErrorCounter);
      S(" dup=");
      D(CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter);
      S("\n");
    }
    // --- cfe_sb_api.c: the PUBLIC bus ------------------------------------------------
    //
    // Everything above drove SB through another module. This drives it directly, and it starts
    // from a clean bus because the sections above left pipes, routes and subscriptions behind
    // -- CFE_SB_EarlyInit is the reset, and running it here means the numbers below are about
    // these calls and not about how many times EVS was initialised.
    //
    // WHAT IS NOT DRIVEN, and why: every path through CFE_SB_CreatePipe's argument check raises
    // an event that prints `ptr=0x%lx`, the address of the caller's own variable. A host
    // process and a QEMU guest put that variable in different places, so NONE of the four
    // bad-argument cases can be compared -- not just the NULL one.
    
    {
      U32 pipe1, pipe2, found;
      CFE_SB_Buffer *zbuf;
      CFE_SB_Buffer *rcvd;
      CFE_SB_Qos_t qos;
      U8 pname[OS_MAX_API_NAME];
      U8 opts;
      CFE_MSG_Message tmsg;
      I32 arc;
      CFE_SB_EarlyInit();
      sb_queuecreate_rc = OS_SUCCESS;
      es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
      MemSet(&qos, 0, sizeof(CFE_SB_Qos_t));
      arc = CFE_SB_CreatePipe(&pipe1, 4, "APIPIPE1");
      S("api_create1 rc=");
      D(arc);
      S(" pipes=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
      S("\n");
      arc = CFE_SB_CreatePipe(&pipe2, 4, "APIPIPE2");
      S("api_create2 rc=");
      D(arc);
      S(" pipes=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
      S(" peak=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PeakPipesInUse);
      S("\n");
      // the same name twice: OS_ERR_NAME_TAKEN, which has its own event
      arc = CFE_SB_CreatePipe(&found, 4, "APIPIPE1");
      S("api_create_taken rc=");
      D(arc);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CreatePipeErrorCounter);
      S("\n");
      // the name comes back, and the id can be found from it
      arc = CFE_SB_GetPipeName(pname, sizeof(pname), pipe1);
      S("api_name rc=");
      D(arc);
      S(" name=");
      S(pname);
      S("\n");
      arc = CFE_SB_GetPipeIdByName(&found, "APIPIPE2");
      S("api_byname rc=");
      D(arc);
      S(" same=");
      D(found == pipe2);
      S("\n");
      arc = CFE_SB_GetPipeIdByName(&found, "NOSUCHPIPE");
      S("api_byname_bad rc=");
      D(arc);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.GetPipeIdByNameErrorCounter);
      S("\n");
      // options round-trip, then the two refusals
      arc = CFE_SB_SetPipeOpts(pipe1, CFE_SB_PIPEOPTS_IGNOREMINE);
      S("api_setopts rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_GetPipeOpts(pipe1, &opts);
      S("api_getopts rc=");
      D(arc);
      S(" opts=0x");
      Hx2b(opts);
      S("\n");
      arc = CFE_SB_GetPipeOpts(pipe1, NULL);
      S("api_getopts_null rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_SetPipeOpts(CFE_SB_INVALID_PIPE, 0);
      S("api_setopts_bad rc=");
      D(arc);
      S(" errs=");
      D(CFE_SB_Global.HKTlmMsg.Payload.PipeOptsErrorCounter);
      S("\n");
      CFE_SB_SetPipeOpts(pipe1, 0);
      // subscriptions: the three public forms, then a duplicate
      arc = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0931), pipe1);
      S("api_sub rc=");
      D(arc);
      S(" subs=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
      S("\n");
      arc = CFE_SB_SubscribeEx(CFE_SB_ValueToMsgId(0x0931), pipe2, qos, 4);
      S("api_subex rc=");
      D(arc);
      S(" subs=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
      S("\n");
      arc = CFE_SB_SubscribeLocal(CFE_SB_ValueToMsgId(0x0932), pipe1, 4);
      S("api_sublocal rc=");
      D(arc);
      S(" subs=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
      S("\n");
      arc = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0931), pipe1);
      S("api_sub_dup rc=");
      D(arc);
      S(" dup=");
      D(CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter);
      S("\n");
      arc = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0931), CFE_SB_INVALID_PIPE);
      S("api_sub_badpipe rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_Subscribe(CFE_SB_InvalidMsgId, pipe1);
      S("api_sub_badmid rc=");
      D(arc);
      S("\n");
      // a zero-copy buffer: take one, release it, and ask for an impossible one
      zbuf = CFE_SB_AllocateMessageBuffer(64);
      S("api_alloc got=");
      D(zbuf != NULL);
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S("\n");
      arc = CFE_SB_ReleaseMessageBuffer(zbuf);
      S("api_release rc=");
      D(arc);
      S(" inuse=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse);
      S("\n");
      arc = CFE_SB_ReleaseMessageBuffer(NULL);
      S("api_release_null rc=");
      D(arc);
      S("\n");
      // HOISTED, not inlined into the D(). The oversize path writes a SYSLOG LINE, and C
      // evaluates printf's arguments before printf writes anything while S()/D() write as they
      // go -- inlining the call put the syslog line in the middle of "api_alloc_huge got=".
      // This is the argument-order trap the driver notes record; it is the only kind of
      // difference that is purely about how the two halves print.
      zbuf = CFE_SB_AllocateMessageBuffer(CFE_MISSION_SB_MAX_SB_MSG_SIZE + 1);
      S("api_alloc_huge got=");
      D(zbuf != NULL);
      S("\n");
      // THE ROUND TRIP, and this is the one the four stubs made impossible: transmit a message
      // to a message id two pipes subscribed to, then receive it on each.
      MemSet(&tmsg, 0, sizeof(CFE_MSG_Message));
      CFE_MSG_Init(&tmsg, CFE_SB_ValueToMsgId(0x0931), sizeof(CFE_MSG_Message));
      arc = CFE_SB_TransmitMsg(&tmsg, TRUE);
      S("api_tx rc=");
      D(arc);
      S(" nosubs=");
      D(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter);
      S("\n");
      rcvd = NULL;
      arc = CFE_SB_ReceiveBuffer(&rcvd, pipe1, OS_CHECK);
      S("api_rx1 rc=");
      D(arc);
      S(" got=");
      D(rcvd != NULL);
      S("\n");
      rcvd = NULL;
      arc = CFE_SB_ReceiveBuffer(&rcvd, pipe2, OS_CHECK);
      S("api_rx2 rc=");
      D(arc);
      S(" got=");
      D(rcvd != NULL);
      S("\n");
      rcvd = NULL;
      arc = CFE_SB_ReceiveBuffer(&rcvd, pipe1, OS_CHECK);
      S("api_rx_empty rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_ReceiveBuffer(&rcvd, CFE_SB_INVALID_PIPE, OS_CHECK);
      S("api_rx_badpipe rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_ReceiveBuffer(NULL, pipe1, OS_CHECK);
      S("api_rx_nullptr rc=");
      D(arc);
      S("\n");
      // unsubscribe: the real one, one with no subscription, and the two refusals
      arc = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(0x0931), pipe1);
      S("api_unsub rc=");
      D(arc);
      S(" subs=");
      D(CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse);
      S("\n");
      arc = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(0x0931), pipe1);
      S("api_unsub_none rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(0x0931), CFE_SB_INVALID_PIPE);
      S("api_unsub_badpipe rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_Unsubscribe(CFE_SB_InvalidMsgId, pipe1);
      S("api_unsub_badmid rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_UnsubscribeLocal(CFE_SB_ValueToMsgId(0x0932), pipe1);
      S("api_unsublocal rc=");
      D(arc);
      S("\n");
      // delete: the owner can, a different app cannot, and a bad id cannot
      arc = CFE_SB_DeletePipeWithAppId(pipe1, CFE_ES_APPID_BASE + 42);
      S("api_del_notowner rc=");
      D(arc);
      S("\n");
      arc = CFE_SB_DeletePipe(pipe1);
      S("api_del rc=");
      D(arc);
      S(" pipes=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
      S(" queues_deleted=");
      D(sb_qdeletes);
      S("\n");
      arc = CFE_SB_DeletePipe(pipe1);
      S("api_del_again rc=");
      D(arc);
      S(" errs=");
      D(CFE_SB_Global.HKTlmMsg.Payload.DeletePipeErrorCounter);
      S("\n");
      arc = CFE_SB_DeletePipe(pipe2);
      S("api_del2 rc=");
      D(arc);
      S(" pipes=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
      S("\n");
      arc = CFE_SB_PipeId_ToIndex(CFE_SB_INVALID_PIPE, &sb_api_idx);
      S("api_toindex rc=");
      D(arc);
      S("\n");
    }
    // --- cfe_sb_task.c and cfe_sb_dispatch.c: SB AS AN APPLICATION ------------------
    //
    // The bus commanding itself. Everything above called SB as a library; this builds command
    // packets and pushes them through the dispatcher, which is the path a ground command
    // actually takes.
    //
    // CFE_SB_TaskMain is NOT driven, and cannot be: its loop pends forever on
    // CFE_SB_ReceiveBuffer and ends in CFE_ES_ExitApp. Every function it calls IS driven,
    // individually -- AppInit here, ProcessCmdPipePkt through the packets below.
    
    {
      CFE_SB_AnyCmd_t sc;
      U32 tpipe;
      CFE_SB_Qos_t tqos;
      U8 *gbuf;
      I64 gsize;
      Bool geof;
      I64 cc;
      I32 trc;
      MemSet(&tqos, 0, sizeof(CFE_SB_Qos_t));
      sbq_reset();
      CFE_SB_EarlyInit();
      sb_queuecreate_rc = OS_SUCCESS;
      es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
      es_set_ctx(1);
      // --- CFE_SB_AppInit: the success path and three of its eight failure returns -
      //
      // AppInit has EIGHT `return Status` points. Three are driven: the create-pipe failure
      // twice over (once by OS_ERR_NAME_TAKEN, once by OS_ERROR -- the same return, two
      // different OSAL causes) and the subscribe failure by way of the memory pool. The
      // CFE_EVS_Register, PutPoolBuf and init-event returns are NOT taken, because the driver
      // has no way to make the real EVS or the real pool fail at just those points. Said
      // plainly rather than counted as four.
      trc = CFE_SB_AppInit();
      S("sbt_init rc=");
      D(trc);
      S(" pipes=");
      D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
      S("\n");
      // ALL FOUR FILTER PAIRS, because nothing else can see them: the
      // CFE_PLATFORM_SB_FILTERED_EVENTn macros expand to other macro names, so
      // check_constants.py files every one under "not a literal and so NOT compared". The C
      // half fills these with NASA's real macros; a wrong name here diverges at this line and
      // nowhere else.
      S("sbt_init_filters ");
      for (cc = 0; cc < 4; cc++) {
        if (cc)
          S(" ");
        D(CFE_SB_Global.EventFilters[cc].EventID);
        S("/0x");
        Hx4(CFE_SB_Global.EventFilters[cc].Mask);
      }
      S("\n");
      // the fixed fields AppInit populates, which nothing else sets
      S("sbt_init_fixed maxids=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MaxMsgIdsAllowed);
      S(" maxpipes=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MaxPipesAllowed);
      S(" maxmem=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MaxMemAllowed);
      S(" maxdepth=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MaxPipeDepthAllowed);
      S(" maxsubs=");
      D(CFE_SB_Global.StatTlmMsg.Payload.MaxSubscriptionsAllowed);
      S("\n");
      // the create-pipe failure: the name is already taken by the pipe just made
      trc = CFE_SB_AppInit();
      S("sbt_init_again rc=");
      D(trc);
      S("\n");
      sbq_reset();
      CFE_SB_EarlyInit();
      sb_queuecreate_rc = OS_ERROR;
      trc = CFE_SB_AppInit();
      S("sbt_init_pipefail rc=");
      D(trc);
      S("\n");
      sb_queuecreate_rc = OS_SUCCESS;
      sbq_reset();
      CFE_SB_EarlyInit();
      es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
      trc = CFE_SB_AppInit();
      S("sbt_init_poolfail rc=");
      D(trc);
      S("\n");
      es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
      // A clean bus with one real pipe and one subscription, for the commands below.
      sbq_reset();
      CFE_SB_EarlyInit();
      trc = CFE_SB_AppInit();
      S("sbt_setup rc=");
      D(trc);
      S("\n");
      CFE_SB_CreatePipe(&tpipe, 4, "SBTPIPE");
      CFE_SB_Subscribe(CFE_SB_ValueToMsgId(0x0941), tpipe);
      // --- the counters, and the only two functions that touch them ----------------
      CFE_SB_Global.HKTlmMsg.Payload.CommandCounter = 11;
      CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter = 22;
      CFE_SB_IncrCmdCtr(CFE_SUCCESS);
      CFE_SB_IncrCmdCtr(CFE_SB_BAD_ARGUMENT);
      S("sbt_incr ok=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandCounter);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      CFE_SB_ResetCounters();
      S("sbt_reset ok=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandCounter);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S(" nosub=");
      D(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter);
      S(" dup=");
      D(CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter);
      S(" send=");
      D(CFE_SB_Global.HKTlmMsg.Payload.MsgSendErrorCounter);
      S(" recv=");
      D(CFE_SB_Global.HKTlmMsg.Payload.MsgReceiveErrorCounter);
      S(" int=");
      D(CFE_SB_Global.HKTlmMsg.Payload.InternalErrorCounter);
      S("\n");
      // --- the dispatcher: every ground command code, in order ---------------------
      for (cc = 0; cc <= 11; cc++) {
        MemSet(&sc, 0, sizeof(CFE_SB_AnyCmd_t));
        CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), sizeof(CFE_SB_NoopCmd_t));
        CFE_MSG_SetFcnCode(&sc.Buf.Msg, cc);
        // the three file commands and the two route commands carry a payload, so their length
        // differs; set it per code so only the UNKNOWN codes 6 and 12 reach the bad-code branch
        // rather than the bad-length one
        switch (cc) {
          case CFE_SB_ENABLE_ROUTE_CC :
          case CFE_SB_DISABLE_ROUTE_CC :
          CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_EnableRouteCmd_t));
          sc.Route.Payload.MsgId = CFE_SB_ValueToMsgId(0x0941);
          sc.Route.Payload.Pipe = tpipe;
          break;
          case CFE_SB_WRITE_ROUTING_INFO_CC :
          case CFE_SB_WRITE_PIPE_INFO_CC :
          case CFE_SB_WRITE_MAP_INFO_CC :
          CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_WriteRoutingInfoCmd_t));
          break;
          default:
          break;
        }
        CFE_SB_ProcessCmdPipePkt(&sc.Buf);
        S("sbt_cmd[");
        D(cc);
        S("] ok=");
        D(CFE_SB_Global.HKTlmMsg.Payload.CommandCounter);
        S(" err=");
        D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
        S("\n");
      }
      // a code no branch knows, and one with the wrong length
      MemSet(&sc, 0, sizeof(CFE_SB_AnyCmd_t));
      CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), sizeof(CFE_SB_NoopCmd_t));
      CFE_MSG_SetFcnCode(&sc.Buf.Msg, 99);
      CFE_SB_ProcessCmdPipePkt(&sc.Buf);
      S("sbt_cmd_badcode err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      CFE_MSG_SetFcnCode(&sc.Buf.Msg, CFE_SB_NOOP_CC);
      CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_NoopCmd_t) + 4);
      CFE_SB_ProcessCmdPipePkt(&sc.Buf);
      S("sbt_cmd_badlen err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      // the housekeeping request, which has no function code at all
      MemSet(&sc, 0, sizeof(CFE_SB_AnyCmd_t));
      CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_SEND_HK_MID), sizeof(CFE_SB_SendHkCmd_t));
      sb_tx_reset();
      CFE_SB_ProcessCmdPipePkt(&sc.Buf);
      S("sbt_hk tx=");
      D(sb_tx_since());
      S(" meminuse=");
      D(CFE_SB_Global.HKTlmMsg.Payload.MemInUse);
      S(" unmarked=");
      D(CFE_SB_Global.HKTlmMsg.Payload.UnmarkedMem);
      S(" pool=");
      D(CFE_SB_Global.HKTlmMsg.Payload.MemPoolHandle);
      S("\n");
      // --- the subscription-report control mid, and its three codes ----------------
      for (cc = 9; cc <= 12; cc++) {
        MemSet(&sc, 0, sizeof(CFE_SB_AnyCmd_t));
        CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_SUB_RPT_CTRL_MID), sizeof(CFE_SB_EnableSubReportingCmd_t));
        CFE_MSG_SetFcnCode(&sc.Buf.Msg, cc);
        if (cc == CFE_SB_SEND_PREV_SUBS_CC) {
          CFE_MSG_SetSize(&sc.Buf.Msg, sizeof(CFE_SB_SendPrevSubsCmd_t));
        }
        CFE_SB_ProcessCmdPipePkt(&sc.Buf);
        S("sbt_subrpt[");
        D(cc);
        S("] report=");
        D(CFE_SB_Global.SubscriptionReporting);
        S(" err=");
        D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
        S(" seg=");
        D(CFE_SB_Global.PrevSubMsg.Payload.PktSegment);
        S(" entries=");
        D(CFE_SB_Global.PrevSubMsg.Payload.Entries);
        S("\n");
      }
      // a message id SB does not route to itself
      MemSet(&sc, 0, sizeof(CFE_SB_AnyCmd_t));
      CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(0x09FF), sizeof(CFE_SB_NoopCmd_t));
      CFE_SB_ProcessCmdPipePkt(&sc.Buf);
      S("sbt_badmid err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      // --- the subscription report itself, with reporting ENABLED ------------------
      CFE_SB_SetSubscriptionReporting(CFE_SB_ENABLE);
      trc = CFE_SB_SendSubscriptionReport(CFE_SB_ValueToMsgId(0x0941), tpipe, tqos);
      S("sbt_subrpt_on rc=");
      D(trc);
      S(" state=");
      D(CFE_SB_Global.SubscriptionReporting);
      S("\n");
      CFE_SB_SetSubscriptionReporting(CFE_SB_DISABLE);
      trc = CFE_SB_SendSubscriptionReport(CFE_SB_ValueToMsgId(0x0941), tpipe, tqos);
      S("sbt_subrpt_off rc=");
      D(trc);
      S("\n");
      // --- the route commands' two refusals, which the loop above did not reach ----
      MemSet(&sc, 0, sizeof(CFE_SB_AnyCmd_t));
      CFE_MSG_Init(&sc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), sizeof(CFE_SB_EnableRouteCmd_t));
      CFE_MSG_SetFcnCode(&sc.Buf.Msg, CFE_SB_ENABLE_ROUTE_CC);
      sc.Route.Payload.MsgId = CFE_SB_InvalidMsgId;
      sc.Route.Payload.Pipe = tpipe;
      trc = CFE_SB_EnableRouteCmd(&sc.Route);
      S("sbt_enrt_badmid rc=");
      D(trc);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      sc.Route.Payload.MsgId = CFE_SB_ValueToMsgId(0x09AB);
      // valid, but unsubscribed
      trc = CFE_SB_EnableRouteCmd(&sc.Route);
      S("sbt_enrt_noroute rc=");
      D(trc);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      trc = CFE_SB_DisableRouteCmd(&sc.Route);
      S("sbt_dsrt_noroute rc=");
      D(trc);
      S(" err=");
      D(CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter);
      S("\n");
      // --- the three data getters, called the way the file writer calls them -------
      gbuf = NULL;
      gsize = 0;
      geof = CFE_SB_WriteRouteInfoDataGetter(&CFE_SB_Global.BackgroundFile, 0, &gbuf, &gsize);
      S("sbt_getroute eof=");
      D(geof);
      S(" size=");
      D(gsize);
      S(" dests=");
      D(CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.NumDestinations);
      S("\n");
      S("sbt_getroute_e0 msgid=0x");
      Hx4(CFE_SB_MsgIdToValue(CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].MsgId));
      S(" state=");
      D(CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].State);
      S(" app=");
      S(CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].AppName);
      S(" pipe=");
      S(CFE_SB_Global.BackgroundFile.Buffer.RouteInfo.DestEntries[0].PipeName);
      S("\n");
      // RecordNum IS the pipe-table index, so probing slot 0 proved nothing: whichever slot
      // CFE_SB_AppInit's command pipe landed in is the one with data in it. Ask.
      CFE_SB_PipeId_ToIndex(CFE_SB_Global.CmdPipe, &sb_api_idx);
      gbuf = NULL;
      gsize = 0;
      geof = CFE_SB_WritePipeInfoDataGetter(&CFE_SB_Global.BackgroundFile, sb_api_idx, &gbuf, &gsize);
      S("sbt_getpipe eof=");
      D(geof);
      S(" size=");
      D(gsize);
      S(" used=");
      D(gbuf != NULL);
      S(" depth=");
      D(CFE_SB_Global.BackgroundFile.Buffer.PipeInfo.CurrentQueueDepth);
      S("/");
      D(CFE_SB_Global.BackgroundFile.Buffer.PipeInfo.MaxQueueDepth);
      S(" app=");
      S(CFE_SB_Global.BackgroundFile.Buffer.PipeInfo.AppName);
      S("\n");
      // and an UNUSED slot, which is still a record but writes nothing
      gbuf = NULL;
      gsize = 0;
      geof = CFE_SB_WritePipeInfoDataGetter(&CFE_SB_Global.BackgroundFile, CFE_PLATFORM_SB_MAX_PIPES - 2, &gbuf, &gsize);
      S("sbt_getpipe_free eof=");
      D(geof);
      S(" size=");
      D(gsize);
      S(" used=");
      D(gbuf != NULL);
      S("\n");
      gbuf = NULL;
      gsize = 0;
      geof = CFE_SB_WritePipeInfoDataGetter(&CFE_SB_Global.BackgroundFile, CFE_PLATFORM_SB_MAX_PIPES - 1, &gbuf, &gsize);
      S("sbt_getpipe_last eof=");
      D(geof);
      S(" size=");
      D(gsize);
      S("\n");
      gbuf = NULL;
      gsize = 0;
      geof = CFE_SB_WriteMsgMapInfoDataGetter(&CFE_SB_Global.BackgroundFile, 0, &gbuf, &gsize);
      S("sbt_getmap eof=");
      D(geof);
      S(" size=");
      D(gsize);
      S(" idx=");
      D(CFE_SB_Global.BackgroundFile.Buffer.MsgMapInfo.Index);
      S("\n");
      // --- the background event handler, every event it knows and one it does not --
      StrPrintN(CFE_SB_Global.BackgroundFile.FileWrite.FileName, CFE_MISSION_MAX_PATH_LEN, "/ram/sbt.dat");
      CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile, CFE_FS_FileWriteEvent_COMPLETE, 0, 7, 0, 123);
      CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile, CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR, -5, 0, 64, 0);
      CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile, CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR, -6, 1, 32, 0);
      CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile, CFE_FS_FileWriteEvent_CREATE_ERROR, -7, 0, 0, 0);
      CFE_SB_BackgroundFileEventHandler(&CFE_SB_Global.BackgroundFile, CFE_FS_FileWriteEvent_UNDEFINED, 0, 0, 0, 0);
      S("sbt_bgevents done\n");
      // --- cfe_sb_objtab.c ---------------------------------------------------------
      S("sbt_objtab ");
      S(CFE_SB_ModuleEntry.Name);
      S(" ");
      D(CFE_SB_ModuleEntry.EarlyInit == NULL);
      S(" ");
      D(CFE_SB_ModuleEntry.TaskMain == NULL);
      S(" ");
      D(CFE_SB_ModuleEntry.AppCleanupCb == NULL);
      S(" ");
      D(CFE_SB_ModuleEntry.Priority);
      S(" ");
      D(CFE_SB_ModuleEntry.StackSize);
      S("\n");
    }
    // --- cfe_es_generic_pool.c and cfe_es_crc.c: THE REAL ALLOCATOR -----------------
    //
    // Every CFE_ES_GetPoolBuf in the transcript above goes to a hand-written bump allocator
    // further up this file, because NASA's real pool lives in ES and ES was not translated.
    // This drives the real one directly -- the generic layer, which holds all of the
    // allocation logic; cfe_es_mempool.c is the thin wrapper that adds a resource id and a
    // mutex, and it needs CFE_ES_Global, which is the next commit.
    
    {
      CFE_ES_GenPoolRecord_t pool;
      I64 blocksizes[4];
      I64 off1, off2, off3, off4, sz;
      CFE_ES_BlockStats_t bstat;
      CFE_ES_GenPoolBucket_t *bp1;
      CFE_ES_GenPoolBucket_t *bp4;
      CFE_ES_ComputeCRC_Params_t *cp;
      I64 freesz, totalsz;
      U16 nbuckets;
      U32 alloccnt, errcnt;
      I32 st;
      I64 k;
      MemSet(es_pool_mem, 0, 2048);
      // UNSORTED ON PURPOSE: GenPoolInitialize bubble-sorts them, and the order it ends up
      // with is what decides every bucket id.
      blocksizes[0] = 128;
      blocksizes[1] = 32;
      blocksizes[2] = 256;
      blocksizes[3] = 64;
      st = CFE_ES_GenPoolInitialize(&pool, 0, 2048, 8, 4, blocksizes, &es_pool_retrieve, &es_pool_commit);
      S("gp_init rc=");
      D(st);
      S(" buckets=");
      D(pool.NumBuckets);
      S(" sorted=");
      D(pool.Buckets[0].BlockSize);
      S("/");
      D(pool.Buckets[1].BlockSize);
      S("/");
      D(pool.Buckets[2].BlockSize);
      S("/");
      D(pool.Buckets[3].BlockSize);
      S(" align=");
      D(pool.AlignMask);
      S("\n");
      S("gp_valid=");
      D(CFE_ES_GenPoolValidateState(&pool));
      S("\n");
      // THE BUCKET ID IS INVERTED: the LARGEST bucket is 1 and "nothing fits" is 0.
      S("gp_bucket 1=");
      D(CFE_ES_GenPoolFindBucket(&pool, 1));
      S(" 32=");
      D(CFE_ES_GenPoolFindBucket(&pool, 32));
      S(" 33=");
      D(CFE_ES_GenPoolFindBucket(&pool, 33));
      S(" 256=");
      D(CFE_ES_GenPoolFindBucket(&pool, 256));
      S(" 257=");
      D(CFE_ES_GenPoolFindBucket(&pool, 257));
      S("\n");
      // HOISTED, and not for style: `fn(args)->member` does not compile. HolyC resolves the
      // `->` against the type of the call's FIRST ARGUMENT rather than its return type, so
      // `CFE_ES_GenPoolGetBucketState(&pool, 1)->BlockSize` was refused with "No member
      // 'BlockSize' in class 'CFE_ES_GenPoolRecord_t'". It REFUSES rather than miscompiling,
      // which is the right outcome -- docs/HOLYC_STRUCT_LIMITS.md #17 and
      // tests/holyc/refused/call_arrow_member.hc.
      bp1 = CFE_ES_GenPoolGetBucketState(&pool, 1);
      bp4 = CFE_ES_GenPoolGetBucketState(&pool, 4);
      S("gp_state 0=");
      D(CFE_ES_GenPoolGetBucketState(&pool, 0) == NULL);
      S(" 1=");
      D(bp1->BlockSize);
      S(" 4=");
      D(bp4->BlockSize);
      S(" 5=");
      D(CFE_ES_GenPoolGetBucketState(&pool, 5) == NULL);
      S("\n");
      // three allocations, two of them from the same bucket
      st = CFE_ES_GenPoolGetBlock(&pool, &off1, 20);
      S("gp_get20 rc=");
      D(st);
      S(" off=");
      D(off1);
      S(" tail=");
      D(pool.TailPosition);
      S("\n");
      st = CFE_ES_GenPoolGetBlock(&pool, &off2, 30);
      S("gp_get30 rc=");
      D(st);
      S(" off=");
      D(off2);
      S(" tail=");
      D(pool.TailPosition);
      S("\n");
      st = CFE_ES_GenPoolGetBlock(&pool, &off3, 200);
      S("gp_get200 rc=");
      D(st);
      S(" off=");
      D(off3);
      S(" tail=");
      D(pool.TailPosition);
      S("\n");
      st = CFE_ES_GenPoolGetBlockSize(&pool, &sz, off1);
      S("gp_size1 rc=");
      D(st);
      S(" sz=");
      D(sz);
      S("\n");
      st = CFE_ES_GenPoolGetBlockSize(&pool, &sz, off3);
      S("gp_size3 rc=");
      D(st);
      S(" sz=");
      D(sz);
      S("\n");
      // too big for any bucket, and a size query outside the pool
      st = CFE_ES_GenPoolGetBlock(&pool, &off4, 1000);
      S("gp_get_huge rc=");
      D(st);
      S("\n");
      st = CFE_ES_GenPoolGetBlockSize(&pool, &sz, 0);
      S("gp_size_oob rc=");
      D(st);
      S("\n");
      st = CFE_ES_GenPoolGetBlockSize(&pool, &sz, pool.TailPosition + 8);
      S("gp_size_past rc=");
      D(st);
      S("\n");
      // RECYCLING: free the 20-byte block and ask for another that fits the same bucket. The
      // offset must come back IDENTICAL -- that is the whole point of the free stack, and a
      // pool that created a new block instead would still "work".
      st = CFE_ES_GenPoolPutBlock(&pool, &sz, off1);
      S("gp_put1 rc=");
      D(st);
      S(" sz=");
      D(sz);
      S("\n");
      st = CFE_ES_GenPoolGetBlock(&pool, &off4, 25);
      S("gp_recycle rc=");
      D(st);
      S(" same=");
      D(off4 == off1);
      S(" tail_unchanged=");
      D(pool.TailPosition == off3 + 256);
      S("\n");
      // The block is LIVE again after the recycle, so freeing it once more is legitimate --
      // the first version of this probe called that a double free and reported errs=0 as if
      // the counter were broken. The free AFTER it is the real double free: the descriptor
      // already says DEALLOCATED, so the bucket id derived from it is out of range,
      // GetBucketState returns NULL, and the pool counts a validation error.
      st = CFE_ES_GenPoolPutBlock(&pool, &sz, off1);
      S("gp_put_recycled rc=");
      D(st);
      S(" errs=");
      D(pool.ValidationErrorCount);
      S("\n");
      st = CFE_ES_GenPoolPutBlock(&pool, &sz, off1);
      S("gp_double_free rc=");
      D(st);
      S(" errs=");
      D(pool.ValidationErrorCount);
      S("\n");
      CFE_ES_GenPoolGetUsage(&pool, &freesz, &totalsz);
      S("gp_usage free=");
      D(freesz);
      S(" total=");
      D(totalsz);
      S("\n");
      CFE_ES_GenPoolGetCounts(&pool, &nbuckets, &alloccnt, &errcnt);
      S("gp_counts buckets=");
      D(nbuckets);
      S(" alloc=");
      D(alloccnt);
      S(" errs=");
      D(errcnt);
      S("\n");
      for (k = 0; k <= 5; k++) {
        MemSet(&bstat, 0, sizeof(CFE_ES_BlockStats_t));
        CFE_ES_GenPoolGetBucketUsage(&pool, k, &bstat);
        S("gp_bucketuse[");
        D(k);
        S("] size=");
        D(bstat.BlockSize);
        S(" created=");
        D(bstat.NumCreated);
        S(" free=");
        D(bstat.NumFree);
        S("\n");
      }
      // MinSize is pure arithmetic over the list: smallest block plus a descriptor
      S("gp_minsize n4=");
      D(CFE_ES_GenPoolCalcMinSize(4, blocksizes, 10));
      S(" n0=");
      D(CFE_ES_GenPoolCalcMinSize(0, blocksizes, 10));
      S("\n");
      // REBUILD: the descriptors are still in the storage, the record is not. A FRESH record
      // over the same memory with the same block sizes recovers the state from the check
      // patterns alone -- which is what a CDS does after a reboot. Done before the
      // argument-check failures below, because those overwrite the record.
      CFE_ES_GenPoolInitialize(&pool, 0, 2048, 8, 4, blocksizes, &es_pool_retrieve, &es_pool_commit);
      st = CFE_ES_GenPoolRebuild(&pool);
      S("gp_rebuild rc=");
      D(st);
      S(" tail=");
      D(pool.TailPosition);
      S(" alloc=");
      D(pool.AllocationCount);
      S("\n");
      CFE_ES_GenPoolGetBucketUsage(&pool, 4, &bstat);
      S("gp_rebuild_b4 created=");
      D(bstat.NumCreated);
      S(" free=");
      D(bstat.NumFree);
      S("\n");
      // the three failure returns in Initialize
      st = CFE_ES_GenPoolInitialize(&pool, 0, 2048, 8, 0, blocksizes, &es_pool_retrieve, &es_pool_commit);
      S("gp_init_nobuckets rc=");
      D(st);
      S("\n");
      st = CFE_ES_GenPoolInitialize(&pool, 0, 2048, 6, 4, blocksizes, &es_pool_retrieve, &es_pool_commit);
      S("gp_init_badalign rc=");
      D(st);
      S("\n");
      blocksizes[1] = 0;
      st = CFE_ES_GenPoolInitialize(&pool, 0, 2048, 8, 4, blocksizes, &es_pool_retrieve, &es_pool_commit);
      S("gp_init_zerosize rc=");
      D(st);
      S("\n");
      blocksizes[1] = 32;
      // --- cfe_es_crc.c -----------------------------------------------------------
      S("crc_none rc=");
      D(CFE_ES_ComputeCRC_Algo_NONE(CRC_PROBE, 9, 0));
      S("\n");
      // CRC-16/ARC of "123456789" is 0xBB3D -- the check value in NASA's own comment on the
      // enumerator, which is why this input and not another.
      S("crc_arc rc=0x");
      Hx4(CFE_ES_ComputeCRC_Algo_16_ARC(CRC_PROBE, 9, 0));
      S("\n");
      S("crc_arc_seeded rc=0x");
      Hx4(CFE_ES_ComputeCRC_Algo_16_ARC(CRC_PROBE, 9, 1));
      S("\n");
      S("crc_arc_empty rc=0x");
      Hx4(CFE_ES_ComputeCRC_Algo_16_ARC(CRC_PROBE, 0, 7));
      S("\n");
      // GetParams: NONE has a NULL algorithm in the table ON PURPOSE, so it falls through to
      // the catch-all; an out-of-range type does too. Both come back non-NULL with a usable
      // algorithm, which is the contract.
      for (k = 0; k <= 2; k++) {
        S("crc_params[");
        D(k);
        S("] null=");
        D(CFE_ES_ComputeCRC_GetParams(k) == NULL);
        S(" algo_none=");
        cp = CFE_ES_ComputeCRC_GetParams(k);
        D(cp->Algorithm == &CFE_ES_ComputeCRC_Algo_NONE);
        S("\n");
      }
      cp = CFE_ES_ComputeCRC_GetParams(CFE_ES_CrcType_16_ARC);
      S("crc_params_arc result=0x");
      Hx4(cp->Algorithm(CRC_PROBE, 9, 0));
      S("\n");
    }
    // --- cfe_es_resource.c: HOW ES FINDS A RECORD ------------------------------------
    //
    // Four tables -- apps, libraries, tasks, counters -- and three ways into each: by ID, by
    // NAME, and BY CALLING CONTEXT. The third is what every cFS call that says "the calling
    // application" is built on, and it is the one that cannot be checked by reading a counter:
    // it asks OSAL which task is running, maps that to an ES task record, and reads the app id
    // out of it.
    //
    // THE TABLES ARE POPULATED BY HAND HERE because cfe_es_apps.c is not gated -- there is no
    // CFE_ES_AppCreate to call. The accessors used to write them are the same ones the lookups
    // use to read, which is a weakness worth naming: a SetUsed/IsUsed pair that agreed on the
    // wrong field would pass. check_padding is what rules that out -- it measures AppId at
    // offset 0 against NASA's compiler.
    
    {
      CFE_ES_AppRecord_t *arp;
      CFE_ES_LibRecord_t *lrp;
      CFE_ES_TaskRecord_t *trp;
      CFE_ES_GenCounterRecord_t *crp;
      // EVERY BASED ID GOES THROUGH A LOCAL. ES_CTX_APPID and friends expand to an expression
      // containing `OS_OBJECT_TYPE_USER + 1`, and passing that expression directly to a
      // function whose first parameter is a pointer folds the `+ 1` as `+ 1*pointee_size` --
      // silently, with no diagnostic. docs/HOLYC_STRUCT_LIMITS.md #20, pinned by
      // tests/exec/cases/e_call_arg_const_scaled.hc. Hoisting is limit 17's workaround too.
      U32 aid2 = ES_CTX_APPID(2);
      U32 aid5 = ES_CTX_APPID(5);
      U32 aid999 = ES_CTX_APPID(999);
      U32 lid1 = ES_LIBID(1);
      U32 lid5 = ES_LIBID(5);
      U32 cid3 = ES_CTRID(3);
      U32 cid0 = ES_CTRID(0);
      MemSet(CFE_ES_Global.AppTable, 0, sizeof(CFE_ES_AppRecord_t) * CFE_PLATFORM_ES_MAX_APPLICATIONS);
      MemSet(CFE_ES_Global.LibTable, 0, sizeof(CFE_ES_LibRecord_t) * CFE_PLATFORM_ES_MAX_LIBRARIES);
      MemSet(CFE_ES_Global.TaskTable, 0, sizeof(CFE_ES_TaskRecord_t) * OS_MAX_TASKS);
      MemSet(CFE_ES_Global.CounterTable, 0, sizeof(CFE_ES_GenCounterRecord_t) * CFE_PLATFORM_ES_MAX_GEN_COUNTERS);
      // App 2 named "ESPROBE", library 1 named "ESLIB", counter 3 named "ESCTR".
      // THE IDS ARE PROPERLY BASED NOW. They were bare small integers while the four
      // *_ToIndex functions were stubs that took them AS the index; cfe_es_api.c is gated, so
      // the real ones subtract CFE_ES_APPID_BASE, CFE_ES_LIBID_BASE and CFE_ES_COUNTID_BASE
      // and a bare 2 does not resolve. That break was recorded in advance beside the stubs,
      // and it arrived: this probe handed NULL to CFE_ES_AppRecordIsUsed and faulted.
      // "slot 5" and "slot 999" keep their meaning -- a free slot and one past the table --
      // because the base is added to both.
      arp = &CFE_ES_Global.AppTable[2];
      CFE_ES_AppRecordSetUsed(arp, aid2);
      StrNCpy(arp->AppName, "ESPROBE", OS_MAX_API_NAME - 1);
      lrp = &CFE_ES_Global.LibTable[1];
      CFE_ES_LibRecordSetUsed(lrp, lid1);
      StrNCpy(lrp->LibName, "ESLIB", OS_MAX_API_NAME - 1);
      crp = &CFE_ES_Global.CounterTable[3];
      CFE_ES_CounterRecordSetUsed(crp, cid3);
      StrNCpy(crp->CounterName, "ESCTR", OS_MAX_API_NAME - 1);
      // BY NAME: a hit, a miss, and the record's own id read back.
      S("rs_appbyname found=");
      D(CFE_ES_LocateAppRecordByName("ESPROBE") != NULL);
      S(" id=");
      D(CFE_ES_AppRecordGetID(CFE_ES_LocateAppRecordByName("ESPROBE")));
      S(" name=");
      S(CFE_ES_AppRecordGetName(CFE_ES_LocateAppRecordByName("ESPROBE")));
      S("\n");
      S("rs_appbyname_miss null=");
      D(CFE_ES_LocateAppRecordByName("NOSUCHAPP") == NULL);
      S("\n");
      S("rs_libbyname found=");
      D(CFE_ES_LocateLibRecordByName("ESLIB") != NULL);
      S(" name=");
      S(CFE_ES_LibRecordGetName(CFE_ES_LocateLibRecordByName("ESLIB")));
      S("\n");
      S("rs_libbyname_miss null=");
      D(CFE_ES_LocateLibRecordByName("NOSUCHLIB") == NULL);
      S("\n");
      S("rs_ctrbyname found=");
      D(CFE_ES_LocateCounterRecordByName("ESCTR") != NULL);
      S(" name=");
      S(CFE_ES_CounterRecordGetName(CFE_ES_LocateCounterRecordByName("ESCTR")));
      S("\n");
      S("rs_ctrbyname_miss null=");
      D(CFE_ES_LocateCounterRecordByName("NOSUCHCTR") == NULL);
      S("\n");
      // AN UNUSED SLOT IS NOT A NAME MATCH even when the bytes happen to be right. Slot 4 gets
      // the name without the id, so IsUsed is false and the scan must skip it.
      StrNCpy(CFE_ES_Global.AppTable[4].AppName, "ESGHOST", OS_MAX_API_NAME - 1);
      S("rs_ghost null=");
      D(CFE_ES_LocateAppRecordByName("ESGHOST") == NULL);
      S("\n");
      // BY ID: in range, out of range, and the match test that confirms it.
      arp = CFE_ES_LocateAppRecordByID(aid2);
      S("rs_appbyid nonnull=");
      D(arp != NULL);
      S(" match=");
      D(CFE_ES_AppRecordIsMatch(arp, aid2));
      S(" used=");
      D(CFE_ES_AppRecordIsUsed(arp));
      S("\n");
      S("rs_appbyid_oor null=");
      D(CFE_ES_LocateAppRecordByID(aid999) == NULL);
      S("\n");
      S("rs_match_null=");
      D(CFE_ES_AppRecordIsMatch(NULL, aid2));
      S("\n");
      lrp = CFE_ES_LocateLibRecordByID(lid1);
      S("rs_libbyid nonnull=");
      D(lrp != NULL);
      S(" match=");
      D(CFE_ES_LibRecordIsMatch(lrp, lid1));
      S("\n");
      crp = CFE_ES_LocateCounterRecordByID(cid3);
      S("rs_ctrbyid nonnull=");
      D(crp != NULL);
      S(" match=");
      D(CFE_ES_CounterRecordIsMatch(crp, cid3));
      S("\n");
      // WHAT THIS DOES AND DOES NOT CHECK, because the first version of this comment claimed
      // more than the numbers support. CFE_RESOURCEID_MARK is 0 in the SIMPLE resourceid variant
      // this port builds -- it is 0x02000000 only under EDS -- so the XOR is a NO-OP here and a
      // round trip cannot distinguish "XOR with 0" from "no XOR at all".
      //
      // It is still not vacuous: `id7=7` pins the round trip's PLUMBING -- that both
      // conversions exist and are inverses. The CONSTANT itself is owned by check_constants.py,
      // which was shown to fail on a MARK of 0x02000000 before the transcript even runs, and
      // that is the stronger guard of the two.
      S("rs_osal_rt id7=");
      D(CFE_ES_TaskId_ToOSAL(7));
      S(" back=");
      D(CFE_ES_TaskId_FromOSAL(CFE_ES_TaskId_ToOSAL(7)));
      S("\n");
      // BY CONTEXT. es_os_taskid is what OS_TaskGetId reports, and the task record it lands on
      // has to be marked used AND carry the app id, or the two-hop lookup returns NULL at the
      // first or the second step. Both failures are driven.
      trp = &CFE_ES_Global.TaskTable[0];
      CFE_ES_TaskRecordSetUsed(trp, CFE_ES_TaskId_FromOSAL(1));
      StrNCpy(trp->TaskName, "ESTASK", OS_MAX_API_NAME - 1);
      trp->AppId = aid2;
      S("rs_ctx_task nonnull=");
      D(CFE_ES_GetTaskRecordByContext() != NULL);
      S(" name=");
      S(CFE_ES_TaskRecordGetName(&CFE_ES_Global.TaskTable[0]));
      S("\n");
      S("rs_ctx_app nonnull=");
      D(CFE_ES_GetAppRecordByContext() != NULL);
      S(" name=");
      S(CFE_ES_AppRecordGetName(&CFE_ES_Global.AppTable[2]));
      S("\n");
      // step 2 fails: the task's app id points at a free slot
      trp->AppId = aid5;
      S("rs_ctx_app_noapp null=");
      D(CFE_ES_GetAppRecordByContext() == NULL);
      S("\n");
      // step 1 fails: the task record is free
      CFE_ES_TaskRecordSetFree(trp);
      S("rs_ctx_task_free null=");
      D(CFE_ES_GetTaskRecordByContext() == NULL);
      S(" app_null=");
      D(CFE_ES_GetAppRecordByContext() == NULL);
      S("\n");
      // THE FOUR SLOT-USED PREDICATES FAIL SAFE BY SAYING "TAKEN". An out-of-range id gives
      // NULL, and claiming the slot is in use is what makes CFE_ResourceId_FindNext move on
      // rather than hand it out -- so the answer for a bad id is TRUE, which reads backwards
      // until you know why.
      S("rs_slot app2=");
      D(CFE_ES_CheckAppIdSlotUsed(aid2));
      S(" app5=");
      D(CFE_ES_CheckAppIdSlotUsed(aid5));
      S(" appoor=");
      D(CFE_ES_CheckAppIdSlotUsed(aid999));
      S("\n");
      S("rs_slot lib1=");
      D(CFE_ES_CheckLibIdSlotUsed(lid1));
      S(" lib5=");
      D(CFE_ES_CheckLibIdSlotUsed(lid5));
      S(" ctr3=");
      D(CFE_ES_CheckCounterIdSlotUsed(cid3));
      S(" ctr0=");
      D(CFE_ES_CheckCounterIdSlotUsed(cid0));
      S("\n");
      // SetFree really frees: the same lookups that found these must stop finding them.
      CFE_ES_AppRecordSetFree(&CFE_ES_Global.AppTable[2]);
      CFE_ES_LibRecordSetFree(&CFE_ES_Global.LibTable[1]);
      CFE_ES_CounterRecordSetFree(&CFE_ES_Global.CounterTable[3]);
      S("rs_freed app=");
      D(CFE_ES_LocateAppRecordByName("ESPROBE") == NULL);
      S(" lib=");
      D(CFE_ES_LocateLibRecordByName("ESLIB") == NULL);
      S(" ctr=");
      D(CFE_ES_LocateCounterRecordByName("ESCTR") == NULL);
      S("\n");
      // AND PUT THE DRIVER'S CONTEXT BACK. This block memset all four ES tables and then
      // freed the records it made, including TaskTable[0] -- which is the task record
      // CFE_ES_GetAppID walks to answer "who is calling". Everything after this point that
      // asks ES who it is would get CFE_ES_ERR_RESOURCEID_NOT_VALID, silently, and the
      // transcript would still match because both halves would be equally wrong.
      es_ctx_init();
    }
    // --- cfe_es_api.c: ES'S PUBLIC API ------------------------------------------------
    //
    // Forty-six functions, and what they have in common is that almost none of them DO
    // anything: Restart, Reload and Delete set a control request and return, because an app
    // cannot be torn down from inside the caller's context -- the caller might BE the app. So
    // what this block checks is the DECISIONS: which id is accepted, which lock is held while
    // the decision is made, and what the syslog says when it is refused.
    //
    // Every id here is properly based. While the four *_ToIndex functions were stubs that took
    // a small integer AS the index, a bare 1 worked; the real ones subtract a base.
    
    {
      U32 aid;
      U32 lid;
      U32 tid;
      U32 cid;
      CFE_ES_AppInfo_t ainfo;
      CFE_ES_TaskInfo_t tinfo;
      U8 sstr[CFE_STATUS_STRING_LENGTH];
      U8 nbuf[OS_MAX_API_NAME];
      U32 idx;
      U32 cnt;
      U32 runstatus;
      I32 rc;
      U32 aid9 = ES_CTX_APPID(9);
      U32 lid9 = ES_LIBID(9);
      U32 lid2 = ES_LIBID(2);
      U32 cid2 = ES_CTRID(2);
      // --- the reset type, straight out of the reset area -------------------------
      CFE_ES_Global.ResetDataPtr->ResetVars.ResetType = CFE_PSP_RST_TYPE_PROCESSOR;
      CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype = 7;
      idx = 0;
      rc = CFE_ES_GetResetType(&idx);
      S("esa_resettype type=");
      D(rc);
      S(" sub=");
      D(idx);
      S("\n");
      rc = CFE_ES_GetResetType(NULL);
      S("esa_resettype_null type=");
      D(rc);
      S("\n");
      // --- identity, by name and by context ---------------------------------------
      rc = CFE_ES_GetAppIDByName(&aid, "CFE_EVS");
      S("esa_appidbyname rc=");
      D(rc);
      S(" id=");
      D(aid);
      S("\n");
      rc = CFE_ES_GetAppIDByName(&aid, "NOSUCHAPP");
      S("esa_appidbyname_miss rc=");
      D(rc);
      S(" id=");
      D(aid);
      S("\n");
      rc = CFE_ES_GetAppIDByName(NULL, "CFE_EVS");
      S("esa_appidbyname_null rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetLibIDByName(&lid, "NOSUCHLIB");
      S("esa_libidbyname_miss rc=");
      D(rc);
      S(" id=");
      D(lid);
      S("\n");
      rc = CFE_ES_GetAppID(&aid);
      S("esa_appid rc=");
      D(rc);
      S(" id=");
      D(aid);
      S("\n");
      rc = CFE_ES_GetTaskID(&tid);
      S("esa_taskid rc=");
      D(rc);
      S(" id=");
      D(tid);
      S("\n");
      // --- names, and the buffer-length edge --------------------------------------
      rc = CFE_ES_GetAppName(nbuf, aid, OS_MAX_API_NAME);
      S("esa_appname rc=");
      D(rc);
      S(" name=");
      S(nbuf);
      S("\n");
      rc = CFE_ES_GetAppName(nbuf, aid, 0);
      S("esa_appname_zero rc=");
      D(rc);
      S("\n");
      // A SHORT BUFFER TRUNCATES AND DOES NOT FAIL: StrNCpy of BufferLength-1 then a
      // terminator, so four bytes of "CFE_EVS" come back as "CFE".
      nbuf[4] = 'Z';
      rc = CFE_ES_GetAppName(nbuf, aid, 4);
      S("esa_appname_short rc=");
      D(rc);
      S(" name=");
      S(nbuf);
      S(" tail=");
      D(nbuf[4]);
      S("\n");
      rc = CFE_ES_GetAppName(nbuf, aid9, OS_MAX_API_NAME);
      S("esa_appname_badid rc=");
      D(rc);
      S(" first=");
      D(nbuf[0]);
      S("\n");
      rc = CFE_ES_GetLibName(nbuf, lid9, OS_MAX_API_NAME);
      S("esa_libname_badid rc=");
      D(rc);
      S("\n");
      // --- the info packets --------------------------------------------------------
      // THE MODULE FIELDS ARRIVE NOW. CFE_ES_CopyModuleBasicInfo, CopyModuleStatusInfo and
      // CopyModuleAddressInfo were stubs that printed a line and filled in nothing, so this
      // probe asserted only what ES itself writes. cfe_es_apps.c is gated, so the entry point,
      // the file name, the init symbol's address and the six module address ranges are real --
      // the three lines those stubs printed are replaced by the fields they were standing in
      // for, which is strictly more than they were worth.
      rc = CFE_ES_GetAppInfo(&ainfo, aid);
      S("esa_appinfo rc=");
      D(rc);
      S(" type=");
      D(ainfo.Type);
      S(" name=");
      S(ainfo.Name);
      S(" main=");
      D(ainfo.MainTaskId);
      S(" kids=");
      D(ainfo.NumOfChildTasks);
      S(" stack=");
      D(ainfo.StackSize);
      S(" prio=");
      D(ainfo.Priority);
      S("\n");
      S("esa_appinfo_mod entry=");
      S(ainfo.EntryPoint);
      S(" file=");
      S(ainfo.FileName);
      S(" start=");
      Hx8(ainfo.StartAddress);
      S(" valid=");
      D(ainfo.AddressesAreValid);
      S("\n");
      S("esa_appinfo_addr code=");
      Hx8(ainfo.CodeAddress);
      S("/");
      Hx8(ainfo.CodeSize);
      S(" data=");
      Hx8(ainfo.DataAddress);
      S("/");
      Hx8(ainfo.DataSize);
      S(" bss=");
      Hx8(ainfo.BSSAddress);
      S("/");
      Hx8(ainfo.BSSSize);
      S("\n");
      // OS_ModuleInfo failing, and succeeding with its own `valid` flag clear: the only two ways
      // AddressesAreValid comes back false. The six addresses are written either way, from a
      // ModuleInfo this driver zeroed first -- so a failure yields zeroes rather than stale
      // values, which is the property worth asserting.
      es_modinfo_rc = OS_ERROR;
      CFE_ES_GetAppInfo(&ainfo, aid);
      S("esa_appinfo_infofail valid=");
      D(ainfo.AddressesAreValid);
      S(" code=");
      Hx8(ainfo.CodeAddress);
      S("\n");
      es_modinfo_rc = OS_SUCCESS;
      es_modinfo_valid = 0;
      CFE_ES_GetAppInfo(&ainfo, aid);
      S("esa_appinfo_notvalid valid=");
      D(ainfo.AddressesAreValid);
      S(" code=");
      Hx8(ainfo.CodeAddress);
      S("\n");
      es_modinfo_valid = 1;
      rc = CFE_ES_GetAppInfo(NULL, aid);
      S("esa_appinfo_null rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetAppInfo(&ainfo, aid9);
      S("esa_appinfo_badid rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetModuleInfo(&ainfo, aid);
      S("esa_moduleinfo_app rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetModuleInfo(&ainfo, 0x990000);
      S("esa_moduleinfo_bad rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetTaskInfo(&tinfo, tid);
      S("esa_taskinfo rc=");
      D(rc);
      S(" task=");
      S(tinfo.TaskName);
      S(" app=");
      S(tinfo.AppName);
      S(" exec=");
      D(tinfo.ExecutionCounter);
      S(" stack=");
      D(tinfo.StackSize);
      S(" prio=");
      D(tinfo.Priority);
      S("\n");
      // --- the four index conversions, and the base that makes them refuse ---------
      idx = 0xFFFF;
      rc = CFE_ES_AppID_ToIndex(aid, &idx);
      S("esa_toidx app rc=");
      D(rc);
      S(" idx=");
      D(idx);
      S("\n");
      rc = CFE_ES_AppID_ToIndex(1, &idx);
      S("esa_toidx app_bare rc=");
      D(rc);
      S("\n");
      idx = 0xFFFF;
      rc = CFE_ES_LibID_ToIndex(lid2, &idx);
      S("esa_toidx lib rc=");
      D(rc);
      S(" idx=");
      D(idx);
      S("\n");
      idx = 0xFFFF;
      rc = CFE_ES_TaskID_ToIndex(tid, &idx);
      S("esa_toidx task rc=");
      D(rc);
      S(" idx=");
      D(idx);
      S("\n");
      rc = CFE_ES_TaskID_ToIndex(CFE_ES_TASKID_UNDEFINED, &idx);
      S("esa_toidx task_undef rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_TaskID_ToIndex(tid, NULL);
      S("esa_toidx task_nullidx rc=");
      D(rc);
      S("\n");
      idx = 0xFFFF;
      rc = CFE_ES_CounterID_ToIndex(cid2, &idx);
      S("esa_toidx ctr rc=");
      D(rc);
      S(" idx=");
      D(idx);
      S("\n");
      // --- the run loop and the execution counter ----------------------------------
      // RunLoop bumps the CALLING TASK's counter outside the lock, sets the app state to
      // RUNNING if it is below it, and returns false the moment the control request is
      // anything but APP_RUN.
      CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_EARLY_INIT;
      runstatus = CFE_ES_RunStatus_APP_RUN;
      rc = CFE_ES_RunLoop(&runstatus);
      S("esa_runloop first=");
      D(rc);
      S(" state=");
      D(CFE_ES_Global.AppTable[1].AppState);
      S(" exec=");
      D(CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT].ExecutionCounter);
      S("\n");
      rc = CFE_ES_RunLoop(NULL);
      S("esa_runloop null=");
      D(rc);
      S("\n");
      runstatus = CFE_ES_RunStatus_APP_EXIT;
      rc = CFE_ES_RunLoop(&runstatus);
      S("esa_runloop_exitreq=");
      D(rc);
      S("\n");
      // The control request wins over the caller's status, and is handed back through it
      CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
      runstatus = CFE_ES_RunStatus_APP_RUN;
      rc = CFE_ES_RunLoop(&runstatus);
      S("esa_runloop_ctlreq=");
      D(rc);
      S(" out=");
      D(runstatus);
      S("\n");
      CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      CFE_ES_IncrementTaskCounter();
      S("esa_exec exec=");
      D(CFE_ES_Global.TaskTable[ES_CTX_TASK_SLOT].ExecutionCounter);
      S("\n");
      // --- waiting for a system state -----------------------------------------------
      // Already satisfied: returns at once and still moves the caller's app state.
      CFE_ES_Global.SystemState = CFE_ES_SystemState_OPERATIONAL;
      CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_EARLY_INIT;
      rc = CFE_ES_WaitForSystemState(CFE_ES_SystemState_APPS_INIT, 0);
      S("esa_wait_met rc=");
      D(rc);
      S(" state=");
      D(CFE_ES_Global.AppTable[1].AppState);
      S("\n");
      // Not satisfied, and the timeout is the only thing that ends it.
      evs_delay_ms = 0;
      rc = CFE_ES_WaitForSystemState(CFE_ES_SystemState_SHUTDOWN, 120);
      S("esa_wait_timeout rc=");
      D(rc);
      S(" delay=");
      D(evs_delay_ms);
      S("\n");
      // --- restart, reload and delete: a control request, nothing more --------------
      // BACK TO RUNNING FIRST. CFE_ES_WaitForSystemState above left the app at LATE_INIT, and
      // CFE_ES_LockUserAppRecord refuses anything that is not RUNNING -- which is a real
      // refusal, driven deliberately a few lines further down, so it must not be the
      // accidental state here.
      CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_RUNNING;
      es_stat_rc = OS_SUCCESS;
      rc = CFE_ES_RestartApp(aid);
      S("esa_restart rc=");
      D(rc);
      S(" req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S("\n");
      CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      es_stat_rc = OS_ERROR;
      rc = CFE_ES_RestartApp(aid);
      S("esa_restart_nofile rc=");
      D(rc);
      S(" req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S("\n");
      es_stat_rc = OS_SUCCESS;
      rc = CFE_ES_ReloadApp(aid, "/cf/new_app.so");
      S("esa_reload rc=");
      D(rc);
      S(" req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S(" file=");
      S(CFE_ES_Global.AppTable[1].StartParams.BasicInfo.FileName);
      S("\n");
      CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      rc = CFE_ES_ReloadApp(aid, NULL);
      S("esa_reload_nullname rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_DeleteApp(aid);
      S("esa_delete rc=");
      D(rc);
      S(" req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S("\n");
      CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      // THE THREE REFUSALS, each from CFE_ES_LockUserAppRecord and each with its own log line:
      // a bad id, a CORE app, and an app that is not running.
      rc = CFE_ES_RestartApp(aid9);
      S("esa_restart_badid rc=");
      D(rc);
      S("\n");
      CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
      rc = CFE_ES_RestartApp(aid);
      S("esa_restart_core rc=");
      D(rc);
      S("\n");
      CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
      CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_EARLY_INIT;
      rc = CFE_ES_RestartApp(aid);
      S("esa_restart_notrunning rc=");
      D(rc);
      S("\n");
      CFE_ES_Global.AppTable[1].AppState = CFE_ES_AppState_RUNNING;
      // --- child tasks ---------------------------------------------------------------
      // CFE_ES_StartAppTask is a stub that hands back an id without making a RECORD, so the
      // delete below takes the "Task ID is not active" branch -- driven on purpose rather than
      // pretended away.
      es_starttask_rc = CFE_SUCCESS;
      rc = CFE_ES_CreateChildTask(&tid, "KID", &CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0);
      S("esa_child rc=");
      D(rc);
      S(" id=");
      D(tid);
      S("\n");
      rc = CFE_ES_CreateChildTask(NULL, "KID", &CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0);
      S("esa_child_nullid rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CreateChildTask(NULL, NULL, &CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0);
      S("esa_child_nullboth rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CreateChildTask(&tid, NULL, &CFE_ES_ProcessAsyncEvent, NULL, 2048, 70, 0);
      S("esa_child_nullname rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CreateChildTask(&tid, "KID", NULL, NULL, 2048, 70, 0);
      S("esa_child_nullfn rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_DeleteChildTask(tid);
      S("esa_child_del_inactive rc=");
      D(rc);
      S("\n");
      // The main task cannot be deleted as a child: the scan finds it in the app table.
      rc = CFE_ES_DeleteChildTask(CFE_ES_TaskId_FromOSAL(es_os_taskid));
      S("esa_child_del_main rc=");
      D(rc);
      S("\n");
      // And ExitChildTask from the MAIN task is refused for the same reason.
      es_taskexits = 0;
      CFE_ES_ExitChildTask();
      S("esa_child_exit_main exits=");
      D(es_taskexits);
      S("\n");
      // --- the generic counters --------------------------------------------------------
      rc = CFE_ES_RegisterGenCounter(&cid, "ESAPICTR");
      S("esa_ctr_reg rc=");
      D(rc);
      S(" id=");
      D(cid);
      S("\n");
      rc = CFE_ES_RegisterGenCounter(&cid, "ESAPICTR");
      S("esa_ctr_dup rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_RegisterGenCounter(&cid, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
      S("esa_ctr_longname rc=");
      D(rc);
      S("\n");
      CFE_ES_GetGenCounterIDByName(&cid, "ESAPICTR");
      CFE_ES_IncrementGenCounter(cid);
      CFE_ES_IncrementGenCounter(cid);
      cnt = 0;
      rc = CFE_ES_GetGenCount(cid, &cnt);
      S("esa_ctr_get rc=");
      D(rc);
      S(" n=");
      D(cnt);
      S("\n");
      rc = CFE_ES_SetGenCount(cid, 41);
      S("esa_ctr_set rc=");
      D(rc);
      S("\n");
      CFE_ES_GetGenCount(cid, &cnt);
      S("esa_ctr_after n=");
      D(cnt);
      S("\n");
      rc = CFE_ES_GetGenCounterName(nbuf, cid, OS_MAX_API_NAME);
      S("esa_ctr_name rc=");
      D(rc);
      S(" name=");
      S(nbuf);
      S("\n");
      rc = CFE_ES_GetGenCounterIDByName(&cid, "NOSUCHCTR");
      S("esa_ctr_byname_miss rc=");
      D(rc);
      S("\n");
      CFE_ES_GetGenCounterIDByName(&cid, "ESAPICTR");
      rc = CFE_ES_DeleteGenCounter(cid);
      S("esa_ctr_del rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_DeleteGenCounter(cid);
      S("esa_ctr_del_again rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_IncrementGenCounter(cid);
      S("esa_ctr_incr_gone rc=");
      D(rc);
      S("\n");
      // --- the CDS group, all of it refused because CDSIsAvailable is 0 ----------------
      rc = CFE_ES_RegisterCDS(&idx, 64, "CDSNAME");
      S("esa_cds_reg rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_RegisterCDS(NULL, 64, "CDSNAME");
      S("esa_cds_reg_null rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetCDSBlockIDByName(&idx, "CDSNAME");
      S("esa_cds_byname rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_GetCDSBlockName(nbuf, CFE_ES_CDS_BAD_HANDLE, OS_MAX_API_NAME);
      S("esa_cds_name rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CopyToCDS(CFE_ES_CDS_BAD_HANDLE, NULL);
      S("esa_cds_copy_null rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_RestoreFromCDS(NULL, CFE_ES_CDS_BAD_HANDLE);
      S("esa_cds_restore_null rc=");
      D(rc);
      S("\n");
      // --- the CRC, and the status string ----------------------------------------------
      rc = CFE_ES_CalculateCRC("123456789", 9, 0, CFE_ES_CrcType_16_ARC);
      S("esa_crc rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CalculateCRC(NULL, 9, 0x1234, CFE_ES_CrcType_16_ARC);
      S("esa_crc_null rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CalculateCRC("123456789", 0, 0x1234, CFE_ES_CrcType_16_ARC);
      S("esa_crc_zerolen rc=");
      D(rc);
      S("\n");
      S("esa_status str=");
      S(CFE_ES_StatusToString(CFE_ES_FILE_IO_ERR, sstr));
      S("\n");
      rc = CFE_ES_StatusToString(0, NULL) == NULL;
      S("esa_status_null isnull=");
      D(rc);
      S("\n");
      // --- ProcessAsyncEvent is one line: wake the background task ---------------------
      // Same move: the real CFE_ES_BackgroundWakeup gives the background semaphore.
      time_sem_gives = 0;
      CFE_ES_ProcessAsyncEvent();
      S("esa_async gives=");
      D(time_sem_gives);
      S("\n");
      // --- ResetCFE, which does not return on real hardware ---------------------------
      // CFE_PSP_Restart is a stub that returns, so the code AFTER it runs -- the "returned"
      // syslog line and CFE_ES_NOT_IMPLEMENTED -- which is the only way this function's tail
      // is reachable at all.
      // AND THE ER LOG WITNESS IS THE LOG. es_erlog_writes counted a stub; cfe_es_erlog.c is
      // gated, so what says an entry was made is ERLogEntries, which
      // CFE_ES_WriteToERLogWithContext increments -- a stronger statement, because it says the
      // entry LANDED rather than that a function was called.
      es_restarts = 0;
      CFE_ES_Global.ResetDataPtr->ERLogEntries = 0;
      rc = CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_PROCESSOR);
      S("esa_reset_proc rc=");
      D(rc);
      S(" restarts=");
      D(es_restarts);
      S(" erlog=");
      D(CFE_ES_Global.ResetDataPtr->ERLogEntries);
      S("\n");
      rc = CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_POWERON);
      S("esa_reset_power rc=");
      D(rc);
      S(" restarts=");
      D(es_restarts);
      S("\n");
      rc = CFE_ES_ResetCFE(99);
      S("esa_reset_bad rc=");
      D(rc);
      S(" restarts=");
      D(es_restarts);
      S("\n");
      // --- ExitApp, on the one path that comes back ------------------------------------
      // An EXTERNAL app spins forever and a CORE app with an init or runtime error does not
      // return either, so the only reachable path is a CORE app with some other status: it
      // logs "Cannot Exit CORE Application" and falls through to the unlock.
      CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
      CFE_ES_ExitApp(CFE_ES_RunStatus_APP_EXIT);
      S("esa_exitapp_core req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S("\n");
      CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      // An out-of-range status is DOWNGRADED to APP_ERROR with a log line, not refused
      CFE_ES_ExitApp(CFE_ES_RunStatus_MAX + 5);
      S("esa_exitapp_badstatus req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S("\n");
      CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
      // Leave ES exactly as it was found, or every probe after this inherits it.
      es_ctx_init();
      CFE_ES_Global.SystemState = CFE_ES_SystemState_UNDEFINED;
    }
    // --- cfe_es_task.c: ES'S TASK AND ITS GROUND COMMANDS ---------------------------
    //
    // Twenty-eight functions, and almost all of them end the same way: a counter moves and an
    // event goes out. So what this block compares is mostly EVENT TEXT, which is the strongest
    // thing in this transcript -- it is the packet payload, formatted by the translation and
    // compared character for character.
    //
    // EVERY HANDLER RETURNS CFE_SUCCESS. What distinguishes a command that worked from one
    // that was refused is which of the two counters moved, so the counters are printed around
    // each group rather than the return value being trusted.
    
    {
      // THE BUFFER IS A UNION OF EVERY COMMAND, not of the one being built, which is the
      // lesson cfe_sb_task.c's exercise paid for: a 20-byte buffer where a handler read 72
      // agreed with the C anyway, because the garbage happened to start with a zero.
      CFE_ES_AnyCmd_t escmd;
      U32 cdsh;
      // for the CDS probes, which register real blocks now
      I32 rc;
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      // --- the two trivial ones, and what they do to the counters -----------------
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      rc = CFE_ES_NoopCmd(&escmd.Noop);
      S("est_noop rc=");
      D(rc);
      S(" cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // ResetCounters does NOT count itself -- zeroing and then incrementing would report 1,
      // which is not what "reset" means.
      rc = CFE_ES_ResetCountersCmd(&escmd.ResetCtrs);
      S("est_resetctrs rc=");
      D(rc);
      S(" cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // --- restart: the refusal, then the one that does not come back -------------
      escmd.Restart.Payload.RestartType = 99;
      rc = CFE_ES_RestartCmd(&escmd.Restart);
      S("est_restart_bad rc=");
      D(rc);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      es_restarts = 0;
      escmd.Restart.Payload.RestartType = CFE_PSP_RST_TYPE_PROCESSOR;
      rc = CFE_ES_RestartCmd(&escmd.Restart);
      S("est_restart_ok rc=");
      D(rc);
      S(" restarts=");
      D(es_restarts);
      S(" cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S("\n");
      // --- housekeeping, the widest packet in the module --------------------------
      CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount = 3;
      CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = 7;
      CFE_ES_Global.ResetDataPtr->ResetVars.BootSource = 2;
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.State = 1;
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.Mode = 1;
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.TriggerCount = 11;
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.TriggerMask[0] = 0x81;
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask[1] = 0x42;
      es_perf_remaining = 9;
      es_heap_rc = OS_SUCCESS;
      sb_tx_reset();
      rc = CFE_ES_SendHkCmd(&escmd.Hk);
      S("est_hk rc=");
      D(rc);
      S(" tx=");
      D(sb_tx_since());
      S("\n");
      S("est_hk_p1 cc=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.CommandErrorCounter);
      S(" logbytes=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.SysLogBytesUsed);
      S(" logsize=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.SysLogSize);
      S(" entries=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.SysLogEntries);
      S(" mode=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.SysLogMode);
      S("\n");
      S("est_hk_p2 apps=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredCoreApps);
      S("/");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredExternalApps);
      S(" tasks=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredTasks);
      S(" libs=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredLibs);
      S(" rst=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.ResetType);
      S("/");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.ResetSubtype);
      S(" pr=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.ProcessorResets);
      S("/");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.MaxProcessorResets);
      S(" boot=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.BootSource);
      S("\n");
      S("est_hk_p3 perf=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.PerfState);
      S("/");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.PerfMode);
      S(" trig=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerCount);
      S(" towrite=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.PerfDataToWrite);
      S(" tmask0=");
      Hx2b(CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerMask[0]);
      S(" fmask1=");
      Hx2b(CFE_ES_Global.TaskData.HkPacket.Payload.PerfFilterMask[1]);
      S("\n");
      S("est_hk_p4 heapfree=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.HeapBytesFree);
      S(" blocks=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.HeapBlocksFree);
      S(" largest=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.HeapMaxBlockSize);
      S("\n");
      // A heap the OSAL cannot report gives three zeroes, not a missing packet.
      es_heap_rc = OS_ERROR;
      CFE_ES_SendHkCmd(&escmd.Hk);
      S("est_hk_noheap free=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.HeapBytesFree);
      S(" blocks=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.HeapBlocksFree);
      S(" largest=");
      D(CFE_ES_Global.TaskData.HkPacket.Payload.HeapMaxBlockSize);
      S("\n");
      es_heap_rc = OS_SUCCESS;
      // --- StartApp: five refusals and the success --------------------------------
      // THE EVENT TEXT IS THE COMPARISON for each of the six, and the counters below are the
      // second witness: a change that moved a branch without changing its wording would show
      // up there and nowhere else.
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      StrNCpy(escmd.StartApp.Payload.Application, "NEWAPP", CFE_MISSION_MAX_API_LEN - 1);
      StrNCpy(escmd.StartApp.Payload.AppEntryPoint, "NEWAPP_Main", CFE_MISSION_MAX_API_LEN - 1);
      StrNCpy(escmd.StartApp.Payload.AppFileName, "newapp", CFE_MISSION_MAX_PATH_LEN - 1);
      escmd.StartApp.Payload.StackSize = 0;
      // means "use the default"
      escmd.StartApp.Payload.Priority = 80;
      escmd.StartApp.Payload.ExceptionAction = CFE_ES_ExceptionAction_RESTART_APP;
      // CFE_ES_AppCreate IS REAL NOW, so a creation failure has to be made to happen rather than
      // returned: the module load is what fails. That also means the success path below now
      // runs the whole lifecycle -- OS_ModuleLoad, a symbol lookup, a task record -- and the
      // app really does end up in the app table, which is why the counters at the end of this
      // block moved.
      rc = CFE_ES_StartAppCmd(&escmd.StartApp);
      S("est_startapp rc=");
      D(rc);
      S("\n");
      es_modload_rc = OS_ERROR;
      rc = CFE_ES_StartAppCmd(&escmd.StartApp);
      S("est_startapp_createfail rc=");
      D(rc);
      S("\n");
      es_modload_rc = OS_SUCCESS;
      escmd.StartApp.Payload.Priority = 255 + 1;
      // > OS_MAX_PRIORITY, but the field is u16
      rc = CFE_ES_StartAppCmd(&escmd.StartApp);
      S("est_startapp_prio rc=");
      D(rc);
      S("\n");
      escmd.StartApp.Payload.Priority = 80;
      escmd.StartApp.Payload.ExceptionAction = 9;
      rc = CFE_ES_StartAppCmd(&escmd.StartApp);
      S("est_startapp_exc rc=");
      D(rc);
      S("\n");
      escmd.StartApp.Payload.ExceptionAction = CFE_ES_ExceptionAction_RESTART_APP;
      escmd.StartApp.Payload.AppEntryPoint[0] = 0;
      rc = CFE_ES_StartAppCmd(&escmd.StartApp);
      S("est_startapp_noentry rc=");
      D(rc);
      S("\n");
      StrNCpy(escmd.StartApp.Payload.AppEntryPoint, "NEWAPP_Main", CFE_MISSION_MAX_API_LEN - 1);
      escmd.StartApp.Payload.Application[0] = 0;
      rc = CFE_ES_StartAppCmd(&escmd.StartApp);
      S("est_startapp_noname rc=");
      D(rc);
      S("\n");
      S("est_startapp_ctrs cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S(" loads=");
      D(es_modloads);
      S("\n");
      // --- stop, restart and reload, by NAME this time ----------------------------
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      StrNCpy(escmd.StopApp.Payload.Application, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
      rc = CFE_ES_StopAppCmd(&escmd.StopApp);
      S("est_stopapp rc=");
      D(rc);
      S("\n");
      CFE_ES_Global.AppTable[2].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      StrNCpy(escmd.StopApp.Payload.Application, "NOSUCHAPP", CFE_MISSION_MAX_API_LEN - 1);
      rc = CFE_ES_StopAppCmd(&escmd.StopApp);
      S("est_stopapp_miss rc=");
      D(rc);
      S("\n");
      StrNCpy(escmd.RestartApp.Payload.Application, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
      es_stat_rc = OS_SUCCESS;
      rc = CFE_ES_RestartAppCmd(&escmd.RestartApp);
      S("est_restartapp rc=");
      D(rc);
      S("\n");
      CFE_ES_Global.AppTable[2].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      es_stat_rc = OS_ERROR;
      rc = CFE_ES_RestartAppCmd(&escmd.RestartApp);
      S("est_restartapp_nofile rc=");
      D(rc);
      S("\n");
      es_stat_rc = OS_SUCCESS;
      StrNCpy(escmd.RestartApp.Payload.Application, "NOSUCHAPP", CFE_MISSION_MAX_API_LEN - 1);
      rc = CFE_ES_RestartAppCmd(&escmd.RestartApp);
      S("est_restartapp_miss rc=");
      D(rc);
      S("\n");
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      StrNCpy(escmd.ReloadApp.Payload.Application, "OTHER_APP", CFE_MISSION_MAX_API_LEN - 1);
      StrNCpy(escmd.ReloadApp.Payload.AppFileName, "other_v2", CFE_MISSION_MAX_PATH_LEN - 1);
      rc = CFE_ES_ReloadAppCmd(&escmd.ReloadApp);
      S("est_reloadapp rc=");
      D(rc);
      S(" file=");
      S(CFE_ES_Global.AppTable[2].StartParams.BasicInfo.FileName);
      S("\n");
      CFE_ES_Global.AppTable[2].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      StrNCpy(escmd.ReloadApp.Payload.Application, "NOSUCHAPP", CFE_MISSION_MAX_API_LEN - 1);
      rc = CFE_ES_ReloadAppCmd(&escmd.ReloadApp);
      S("est_reloadapp_miss rc=");
      D(rc);
      S("\n");
      S("est_appctl_ctrs cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // --- the three queries ------------------------------------------------------
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      StrNCpy(escmd.QueryOne.Payload.Application, "CFE_EVS", CFE_MISSION_MAX_API_LEN - 1);
      sb_tx_reset();
      rc = CFE_ES_QueryOneCmd(&escmd.QueryOne);
      S("est_queryone rc=");
      D(rc);
      S(" tx=");
      D(sb_tx_since());
      S(" name=");
      S(CFE_ES_Global.TaskData.OneAppPacket.Payload.AppInfo.Name);
      S("\n");
      StrNCpy(escmd.QueryOne.Payload.Application, "NOSUCHAPP", CFE_MISSION_MAX_API_LEN - 1);
      rc = CFE_ES_QueryOneCmd(&escmd.QueryOne);
      S("est_queryone_miss rc=");
      D(rc);
      S("\n");
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      fs_len = 0;
      fs_pos = 0;
      rc = CFE_ES_QueryAllCmd(&escmd.QueryAll);
      S("est_queryall rc=");
      D(rc);
      S(" len=");
      D(fs_len);
      S("\n");
      fs_open_fail = 1;
      rc = CFE_ES_QueryAllCmd(&escmd.QueryAll);
      S("est_queryall_nocreate rc=");
      D(rc);
      S("\n");
      fs_open_fail = 0;
      fs_len = 0;
      fs_pos = 0;
      rc = CFE_ES_QueryAllTasksCmd(&escmd.QueryAllTasks);
      S("est_queryalltasks rc=");
      D(rc);
      S(" len=");
      D(fs_len);
      S("\n");
      fs_open_fail = 1;
      rc = CFE_ES_QueryAllTasksCmd(&escmd.QueryAllTasks);
      S("est_queryalltasks_nocreate rc=");
      D(rc);
      S("\n");
      fs_open_fail = 0;
      // --- the system log and the ER log ------------------------------------------
      CFE_ES_WriteToSysLog("a line to clear\n");
      rc = CFE_ES_ClearSysLogCmd(&escmd.ClearSysLog);
      S("est_clearsyslog rc=");
      D(rc);
      S(" entries=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
      S("\n");
      escmd.OverWriteSysLog.Payload.Mode = CFE_ES_LogMode_DISCARD;
      rc = CFE_ES_OverWriteSysLogCmd(&escmd.OverWriteSysLog);
      S("est_overwrite rc=");
      D(rc);
      S(" mode=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogMode);
      S("\n");
      escmd.OverWriteSysLog.Payload.Mode = 99;
      rc = CFE_ES_OverWriteSysLogCmd(&escmd.OverWriteSysLog);
      S("est_overwrite_bad rc=");
      D(rc);
      S(" mode=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogMode);
      S("\n");
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      fs_len = 0;
      fs_pos = 0;
      rc = CFE_ES_WriteSysLogCmd(&escmd.WriteSysLog);
      S("est_writesyslog rc=");
      D(rc);
      S(" len=");
      D(fs_len);
      S("\n");
      CFE_ES_Global.ResetDataPtr->ERLogIndex = 5;
      CFE_ES_Global.ResetDataPtr->ERLogEntries = 5;
      rc = CFE_ES_ClearERLogCmd(&escmd.ClearERLog);
      S("est_clearerlog rc=");
      D(rc);
      S(" idx=");
      D(CFE_ES_Global.ResetDataPtr->ERLogIndex);
      S(" entries=");
      D(CFE_ES_Global.ResetDataPtr->ERLogEntries);
      S("\n");
      // THE RETURN VALUE SAYS NOTHING HERE and that is worth stating once: every handler in
      // this file returns CFE_SUCCESS whatever happens, because the return goes to the
      // dispatcher, which only cares that the handler ran. The witnesses are the two counters
      // and the event. The FS background queue is four deep and the FS section above has
      // already used it, so whether the request is ACCEPTED depends on what that left behind
      // -- which is why the queue is drained first.
      MemSet(&CFE_ES_Global.BackgroundERLogDumpState, 0, sizeof(CFE_ES_BackgroundLogDumpGlobal_t));
      MemSet(&CFE_FS_Global.FileDump, 0, sizeof(CFE_FS_BackgroundFileDumpState_t));
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      CFE_ES_WriteERLogCmd(&escmd.WriteERLog);
      S("est_writeerlog cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S(" pending=");
      D(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.IsPending);
      S(" sub=");
      D(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.FileSubType);
      S(" getdata=");
      D(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.GetData != NULL);
      S(" onevent=");
      D(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.OnEvent != NULL);
      S(" file=");
      S(CFE_ES_Global.BackgroundERLogDumpState.FileWrite.FileName);
      S("\n");
      // And asking again while it is pending is a DISTINCT error with its own event.
      CFE_ES_WriteERLogCmd(&escmd.WriteERLog);
      S("est_writeerlog_again cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // --- the processor reset counts ---------------------------------------------
      rc = CFE_ES_ResetPRCountCmd(&escmd.ResetPRCount);
      S("est_resetpr rc=");
      D(rc);
      S(" count=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount);
      S("\n");
      escmd.SetMaxPRCount.Payload.MaxPRCount = 12;
      rc = CFE_ES_SetMaxPRCountCmd(&escmd.SetMaxPRCount);
      S("est_setmaxpr rc=");
      D(rc);
      S(" max=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount);
      S("\n");
      // --- the CDS, whose four refusals each have their own event ------------------
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      // THE FOUR REFUSALS ARE REAL NOW. Until cfe_es_cds.c was gated these five probes steered
      // es_cdsdelete_rc on a stub, so all five asserted the same thing: that the command handler
      // turns whatever CFE_ES_DeleteCDS returns into the right event and counter. That is worth
      // one probe, not five. Each refusal below is now produced by setting up the CDS so the real
      // function has to reach it.
      //
      // The CDS has to exist first, which also means these probes run against the real store:
      // CFE_ES_CDS_EarlyInit wipes it, writes the signatures, creates the pool and writes an
      // empty registry.
      rc = CFE_ES_CDS_EarlyInit();
      S("est_cds_init rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S("\n");
      // A block owned by an app that is not registered -- "APP" is not in the app table, which
      // is the condition CFE_ES_DeleteCDS inverts: a FAILED lookup means the owner is gone and
      // the block may go.
      rc = CFE_ES_RegisterCDSEx(&cdsh, 64, "APP.TBL", FALSE);
      S("est_cds_reg rc=");
      D(rc);
      S("\n");
      StrNCpy(escmd.DeleteCDS.Payload.CdsName, "APP.TBL", CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
      rc = CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS);
      S("est_deletecds rc=");
      D(rc);
      S("\n");
      // Registered as a CRITICAL TABLE, so an ES command may not delete it: the Table flag and
      // the caller's claim about who it is have to agree.
      rc = CFE_ES_RegisterCDSEx(&cdsh, 64, "APP.TBL", TRUE);
      S("est_cds_reg_tbl rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS);
      S("est_deletecds_tbl rc=");
      D(rc);
      S("\n");
      // Owned by an app that IS registered. "CFE_EVS" is app slot 1, and the owner name is
      // whatever precedes the dot.
      rc = CFE_ES_RegisterCDSEx(&cdsh, 64, "CFE_EVS.TBL", FALSE);
      S("est_cds_reg_active rc=");
      D(rc);
      S("\n");
      StrNCpy(escmd.DeleteCDS.Payload.CdsName, "CFE_EVS.TBL", CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
      rc = CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS);
      S("est_deletecds_active rc=");
      D(rc);
      S("\n");
      // No such name in the registry.
      StrNCpy(escmd.DeleteCDS.Payload.CdsName, "NO.SUCH", CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
      rc = CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS);
      S("est_deletecds_miss rc=");
      D(rc);
      S("\n");
      // A store that refuses the registry write-back, which is the last step of a delete that
      // otherwise succeeded -- the block is freed and the registry is not updated, so the error
      // comes out of CFE_ES_UpdateCDSRegistry and the log line is written after the CDS lock is
      // released.
      rc = CFE_ES_RegisterCDSEx(&cdsh, 64, "OTHER.TBL", FALSE);
      S("est_cds_reg_err rc=");
      D(rc);
      S("\n");
      StrNCpy(escmd.DeleteCDS.Payload.CdsName, "OTHER.TBL", CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
      es_cds_write_rc = CFE_PSP_ERROR;
      rc = CFE_ES_DeleteCDSCmd(&escmd.DeleteCDS);
      S("est_deletecds_err rc=");
      D(rc);
      S("\n");
      es_cds_write_rc = CFE_PSP_SUCCESS;
      S("est_deletecds_ctrs cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // The registry dump walks a registry that is empty here, which is the case the
      // pre-loaded OsStatus makes report SUCCESS.
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      fs_len = 0;
      fs_pos = 0;
      rc = CFE_ES_DumpCDSRegistryCmd(&escmd.DumpCDSReg);
      S("est_dumpcdsreg rc=");
      D(rc);
      S(" len=");
      D(fs_len);
      S("\n");
      fs_open_fail = 1;
      rc = CFE_ES_DumpCDSRegistryCmd(&escmd.DumpCDSReg);
      S("est_dumpcdsreg_nocreate rc=");
      D(rc);
      S("\n");
      fs_open_fail = 0;
      // --- the memory pool statistics ---------------------------------------------
      MemSet(&escmd, 0, sizeof(CFE_ES_AnyCmd_t));
      escmd.MemPoolStats.Payload.PoolHandle = CFE_SB_Global.Mem.PoolHdl;
      sb_tx_reset();
      rc = CFE_ES_SendMemPoolStatsCmd(&escmd.MemPoolStats);
      S("est_mempoolstats rc=");
      D(rc);
      S(" tx=");
      D(sb_tx_since());
      S(" handle=");
      D(CFE_ES_Global.TaskData.MemStatsPacket.Payload.PoolHandle);
      S(" size=");
      D(CFE_ES_Global.TaskData.MemStatsPacket.Payload.PoolStats.PoolSize);
      S("\n");
      escmd.MemPoolStats.Payload.PoolHandle = ES_CTX_APPID(9);
      rc = CFE_ES_SendMemPoolStatsCmd(&escmd.MemPoolStats);
      S("est_mempoolstats_bad rc=");
      D(rc);
      S("\n");
      // --- the short-write reporter, now a real event -----------------------------
      CFE_ES_FileWriteByteCntErr("/ram/x.log", 64, -7);
      // --- CFE_ES_TaskMain, which DOES come back ----------------------------------
      // The loop exits when CFE_SB_ReceiveBuffer fails, and OS_QueueGet returns OS_QUEUE_EMPTY
      // on an empty pipe -- so one pass, then CFE_ES_ExitApp. The caller must be a CORE app
      // for that to return: an EXTERNAL one spins forever in `while (1) OS_TaskDelay(500)`.
      // SystemState is set to CORE_READY first so the WaitForSystemState before the loop does
      // not spend 30,000 ms of simulated delay.
      CFE_ES_Global.SystemState = CFE_ES_SystemState_CORE_READY;
      CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
      es_taskpipes = 0;
      // CFE_ES_BackgroundInit is real now, so what says it ran is the semaphore it creates --
      // time_sems_created -- not a counter in a stub that no longer exists.
      time_sems_created = 0;
      es_taskexits = 0;
      evs_delay_ms = 0;
      sb_queuecreate_rc = OS_SUCCESS;
      es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
      CFE_ES_TaskMain();
      S("est_taskmain pipes=");
      D(es_taskpipes);
      S(" bgsem=");
      D(time_sems_created);
      S(" exits=");
      D(es_taskexits);
      S(" delay=");
      D(evs_delay_ms);
      S(" req=");
      D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
      S("\n");
      CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
      // Leave ES as it was found.
      es_ctx_init();
      CFE_ES_Global.SystemState = CFE_ES_SystemState_UNDEFINED;
    }
    // --- cfe_es_perf.c and cfe_es_dispatch.c -----------------------------------------
    //
    // The performance log is the only part of ES that writes a file through a STATE MACHINE
    // rather than in one call, so the interesting thing to drive is the machine: eleven states,
    // a work credit that bounds how many run per pass, and a mutex held from LOCK_DATA to
    // UNLOCK_DATA.
    //
    // AND THE DISPATCHER IS THE FIRST TIME ES'S COMMANDS ARRIVE AS MESSAGES. Everything in the
    // est_ block above called a handler directly; these go in through CFE_ES_TaskPipe with a
    // message id, a function code and a length, which is the only path a real ground command
    // takes.
    
    {
      CFE_ES_AnyPerfCmd_t pc;
      CFE_ES_PerfData_t *Perf = &CFE_ES_Global.ResetDataPtr->Perf;
      CFE_ES_PerfDumpGlobal_t *PDump = &CFE_ES_Global.BackgroundPerfDumpState;
      I64 k;
      I32 rc;
      MemSet(&pc, 0, sizeof(CFE_ES_AnyPerfCmd_t));
      MemSet(PDump, 0, sizeof(CFE_ES_PerfDumpGlobal_t));
      // --- SetupPerfVariables: a POWER-ON reset initialises, a processor reset does not
      MemSet(Perf, 0, sizeof(CFE_ES_PerfData_t));
      CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
      S("esp_setup_por ver=");
      D(Perf->MetaData.Version);
      S(" endian=");
      D(Perf->MetaData.Endian);
      S(" ticks=");
      D(Perf->MetaData.TimerTicksPerSecond);
      S(" roll=");
      D(Perf->MetaData.TimerLow32Rollover);
      S(" state=");
      D(Perf->MetaData.State);
      S(" mode=");
      D(Perf->MetaData.Mode);
      S(" masksz=");
      D(Perf->MetaData.FilterTriggerMaskSize);
      S("\n");
      S("esp_setup_por_masks filt0=");
      Hx2b(Perf->MetaData.FilterMask[0]);
      S(" filt15=");
      Hx2b(Perf->MetaData.FilterMask[15]);
      S(" trig0=");
      Hx2b(Perf->MetaData.TriggerMask[0]);
      S("\n");
      // A processor reset touches ONE field -- the log survives, which is the point.
      Perf->MetaData.Version = 7;
      Perf->MetaData.TriggerCount = 99;
      CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_PROCESSOR);
      S("esp_setup_pr ver=");
      D(Perf->MetaData.Version);
      S(" trig=");
      D(Perf->MetaData.TriggerCount);
      S(" state=");
      D(Perf->MetaData.State);
      S("\n");
      CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
      // --- the capture path, through CFE_ES_PerfLogAdd ----------------------------
      // THE PERF LOG'S LOCK IS A MUTEX, not a binary semaphore, so the witness for "did it
      // take the lock" is fs_mut_take -- what OS_MutSemTake counts. Reading time_sem_takes
      // here would have been a zero against a zero.
      fs_mut_take = 0;
      CFE_ES_PerfLogAdd(3, 0);
      S("esp_add_idle count=");
      D(Perf->MetaData.DataCount);
      S(" takes=");
      D(fs_mut_take);
      S("\n");
      // Armed, with an all-ones filter mask and an all-zero trigger mask: entries are recorded
      // and nothing triggers, so DataCount climbs and State stays WAITING.
      pc.StartPerf.Payload.TriggerMode = CFE_ES_PerfTrigger_START;
      CFE_ES_StartPerfDataCmd(&pc.StartPerf);
      es_perf_tb = 0;
      CFE_ES_PerfLogAdd(3, 0);
      CFE_ES_PerfLogAdd(3, 1);
      CFE_ES_PerfLogAdd(4, 0);
      S("esp_add_armed count=");
      D(Perf->MetaData.DataCount);
      S(" end=");
      D(Perf->MetaData.DataEnd);
      S(" start=");
      D(Perf->MetaData.DataStart);
      S(" state=");
      D(Perf->MetaData.State);
      S("\n");
      // THE ENTRY WORD CARRIES THE MARKER AND THE EXIT BIT, which is the one piece of
      // bit-packing in the module: marker | (EntryExit << 31).
      S("esp_entries e0=");
      Hx8(Perf->DataBuffer[0].Data);
      S(" t0=");
      D(Perf->DataBuffer[0].TimerLower32);
      S(" e1=");
      Hx8(Perf->DataBuffer[1].Data);
      S(" t1=");
      D(Perf->DataBuffer[1].TimerLower32);
      S("\n");
      // A FILTERED marker is dropped before the lock.
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask[0] = 0x00;
      fs_mut_take = 0;
      CFE_ES_PerfLogAdd(3, 0);
      S("esp_add_filtered count=");
      D(Perf->MetaData.DataCount);
      S(" takes=");
      D(fs_mut_take);
      S("\n");
      CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask[0] = 0xFF;
      // AN OUT-OF-RANGE MARKER COMPLAINS ONCE, then is latched silent -- the second call
      // produces no syslog line at all, which is the behaviour worth pinning.
      CFE_ES_PerfLogAdd(CFE_MISSION_ES_PERF_MAX_IDS, 0);
      CFE_ES_PerfLogAdd(CFE_MISSION_ES_PERF_MAX_IDS + 5, 0);
      S("esp_add_badmarker reported=");
      D(Perf->MetaData.InvalidMarkerReported);
      S(" count=");
      D(Perf->MetaData.DataCount);
      S("\n");
      Perf->MetaData.InvalidMarkerReported = FALSE;
      // THE TRIGGER, in END mode: the first triggering marker stops the capture.
      CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
      pc.StartPerf.Payload.TriggerMode = CFE_ES_PerfTrigger_END;
      CFE_ES_StartPerfDataCmd(&pc.StartPerf);
      Perf->MetaData.TriggerMask[0] = 0x10;
      // marker 4 triggers
      CFE_ES_PerfLogAdd(3, 0);
      S("esp_trig_pre state=");
      D(Perf->MetaData.State);
      S(" trigs=");
      D(Perf->MetaData.TriggerCount);
      S("\n");
      CFE_ES_PerfLogAdd(4, 0);
      S("esp_trig_end state=");
      D(Perf->MetaData.State);
      S(" trigs=");
      D(Perf->MetaData.TriggerCount);
      S(" count=");
      D(Perf->MetaData.DataCount);
      S("\n");
      // --- the two mask commands, in range and out -------------------------------
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      pc.FiltMask.Payload.FilterMaskNum = 2;
      pc.FiltMask.Payload.FilterMask = 0x5A;
      CFE_ES_SetPerfFilterMaskCmd(&pc.FiltMask);
      pc.FiltMask.Payload.FilterMaskNum = CFE_ES_PERF_8BIT_WORDS_IN_MASK;
      CFE_ES_SetPerfFilterMaskCmd(&pc.FiltMask);
      pc.TrigMask.Payload.TriggerMaskNum = 3;
      pc.TrigMask.Payload.TriggerMask = 0xA5;
      CFE_ES_SetPerfTriggerMaskCmd(&pc.TrigMask);
      pc.TrigMask.Payload.TriggerMaskNum = 99;
      CFE_ES_SetPerfTriggerMaskCmd(&pc.TrigMask);
      S("esp_masks filt2=");
      Hx2b(Perf->MetaData.FilterMask[2]);
      S(" trig3=");
      Hx2b(Perf->MetaData.TriggerMask[3]);
      S(" cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // --- Start and Stop, and the "write in progress" refusal -------------------
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      pc.StartPerf.Payload.TriggerMode = 99;
      // > END
      CFE_ES_StartPerfDataCmd(&pc.StartPerf);
      pc.StartPerf.Payload.TriggerMode = CFE_ES_PerfTrigger_CENTER;
      CFE_ES_StartPerfDataCmd(&pc.StartPerf);
      S("esp_start mode=");
      D(Perf->MetaData.Mode);
      S(" state=");
      D(Perf->MetaData.State);
      S(" cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // PendingState non-IDLE is what "a write is in progress" means to both commands.
      PDump->PendingState = CFE_ES_PerfDumpState_INIT;
      CFE_ES_StartPerfDataCmd(&pc.StartPerf);
      CFE_ES_StopPerfDataCmd(&pc.StopPerf);
      S("esp_busy cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      PDump->PendingState = CFE_ES_PerfDumpState_IDLE;
      // --- THE DUMP, one state at a time -------------------------------------------
      // Stop queues it; then each RunPerfLogDump call is given exactly enough credit to
      // advance, and the state is printed after each so the machine's path is in the
      // transcript rather than only its result.
      MemSet(PDump, 0, sizeof(CFE_ES_PerfDumpGlobal_t));
      Perf->MetaData.DataCount = 3;
      Perf->MetaData.DataStart = 0;
      fs_len = 0;
      fs_pos = 0;
      fs_mut_take = 0;
      fs_mut_give = 0;
      // THE UNION BITES HERE and it is worth the comment: StartPerfCmd's TriggerMode is a
      // uint32 at payload offset 0 and StopPerfCmd's DataFileName is a char[64] at the same
      // offset, so setting the trigger mode above left a one-byte control character as the
      // filename -- and the dump went to "/ram/\001" rather than to the default. Both halves
      // agreed, because both had the same garbage.
      MemSet(&pc, 0, sizeof(CFE_ES_AnyPerfCmd_t));
      CFE_ES_StopPerfDataCmd(&pc.StopPerf);
      S("esp_stop pending=");
      D(PDump->PendingState);
      S(" file=");
      S(PDump->DataFileName);
      S(" cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S("\n");
      // ElapsedTime 0 earns no credit, so the machine does not move at all.
      S("esp_dump_nocredit active=");
      D(CFE_ES_RunPerfLogDump(0, PDump));
      S(" cur=");
      D(PDump->CurrentState);
      S("\n");
      for (k = 0; k < 8; k++) {
        S("esp_dump[");
        D(k);
        S("] active=");
        D(CFE_ES_RunPerfLogDump(1, PDump));
        S(" cur=");
        D(PDump->CurrentState);
        S(" pend=");
        D(PDump->PendingState);
        S(" ctr=");
        D(PDump->StateCounter);
        S(" pos=");
        D(PDump->DataPos);
        S(" size=");
        D(PDump->FileSize);
        S("\n");
      }
      // takes/gives are the PERF mutex, held from LOCK_DATA to UNLOCK_DATA -- several states
      // apart, which is the thing NASA flags at CFE_ES_PerfLogAdd.
      S("esp_dump_done len=");
      D(fs_len);
      S(" takes=");
      D(fs_mut_take);
      S(" gives=");
      D(fs_mut_give);
      S(" remaining=");
      D(CFE_ES_GetPerfLogDumpRemaining());
      S("\n");
      // And a dump whose file will not open goes straight back to IDLE.
      MemSet(PDump, 0, sizeof(CFE_ES_PerfDumpGlobal_t));
      fs_open_fail = 1;
      CFE_ES_StopPerfDataCmd(&pc.StopPerf);
      CFE_ES_RunPerfLogDump(1000, PDump);
      S("esp_dump_nocreate cur=");
      D(PDump->CurrentState);
      S("\n");
      fs_open_fail = 0;
      MemSet(PDump, 0, sizeof(CFE_ES_PerfDumpGlobal_t));
      // --- the dispatcher: a length check, twenty-four codes and three message ids --
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      MemSet(&pc, 0, sizeof(CFE_ES_AnyPerfCmd_t));
      CFE_MSG_Init(&pc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_ES_CMD_MID), sizeof(CFE_ES_NoopCmd_t));
      // A GOOD length, then a bad one: the bad one never reaches a handler.
      CFE_MSG_SetFcnCode(&pc.Buf.Msg, CFE_ES_NOOP_CC);
      CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t));
      CFE_ES_ProcessGroundCmd(&pc.Buf);
      CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t) + 4);
      CFE_ES_ProcessGroundCmd(&pc.Buf);
      S("esp_len cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // An unknown code, which is the dispatcher's own event.
      CFE_MSG_SetFcnCode(&pc.Buf.Msg, 99);
      CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t));
      CFE_ES_ProcessGroundCmd(&pc.Buf);
      S("esp_badcc ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // EVERY CODE WITH A DELIBERATELY WRONG LENGTH. What this pins is the TABLE -- that each
      // code maps to the type the handler expects -- and it does it without running twenty-four
      // handlers, because the length check fires first and names the expected size in its
      // event. A code mapped to the wrong type shows up as a different "Expected =" number.
      //
      // NINE BYTES, NOT ONE. A size of 1 is below the CCSDS header minimum and CFE_MSG_SetSize
      // refuses it, leaving the previous size in place -- which was sizeof(CFE_ES_NoopCmd_t),
      // so the six no-argument commands PASSED the length check and ran, and the error count
      // came out 20 instead of 25.
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t) + 1);
      for (k = 0; k <= 24; k++) {
        CFE_MSG_SetFcnCode(&pc.Buf.Msg, k);
        CFE_ES_ProcessGroundCmd(&pc.Buf);
      }
      S("esp_alllen ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // TaskPipe: the housekeeping id, the command id, and one that is neither.
      CFE_ES_Global.TaskData.CommandCounter = 0;
      CFE_ES_Global.TaskData.CommandErrorCounter = 0;
      CFE_MSG_SetFcnCode(&pc.Buf.Msg, CFE_ES_NOOP_CC);
      CFE_MSG_SetSize(&pc.Buf.Msg, sizeof(CFE_ES_NoopCmd_t));
      CFE_MSG_SetMsgId(&pc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_ES_SEND_HK_MID));
      sb_tx_reset();
      CFE_ES_TaskPipe(&pc.Buf);
      S("esp_pipe_hk tx=");
      D(sb_tx_since());
      S("\n");
      CFE_MSG_SetMsgId(&pc.Buf.Msg, CFE_SB_ValueToMsgId(CFE_ES_CMD_MID));
      CFE_ES_TaskPipe(&pc.Buf);
      CFE_MSG_SetMsgId(&pc.Buf.Msg, CFE_SB_ValueToMsgId(0x1FFF));
      CFE_ES_TaskPipe(&pc.Buf);
      S("esp_pipe cc=");
      D(CFE_ES_Global.TaskData.CommandCounter);
      S(" ec=");
      D(CFE_ES_Global.TaskData.CommandErrorCounter);
      S("\n");
      // Leave the perf log idle, or the next probe's PerfLogAdd calls start recording.
      CFE_ES_SetupPerfVariables(CFE_PSP_RST_TYPE_POWERON);
      MemSet(PDump, 0, sizeof(CFE_ES_PerfDumpGlobal_t));
    }
    // --- cfe_es_startupscript.c: HOW A SPACECRAFT DECIDES WHAT TO RUN ---------------
    //
    // Eight comma-separated fields terminated by a semicolon, and this is the only thing between
    // a text file and the set of applications a flight computer boots with. The parser is
    // deliberately forgiving and every allowance is a decision about what a half-written script
    // does to a vehicle, so each one is driven here.
    //
    // The script is staged into the simulated file system and read back through
    // OS_OpenCreate/OS_read -- which is what made the read-only open stop truncating.
    
    {
      U8 *tok[CFE_ES_STARTSCRIPT_MAX_TOKENS_PER_LINE + 1];
      I32 rc;
      es_objs_clear();
      es_modload_rc = OS_SUCCESS;
      // --- CFE_ES_ParseFileEntry: the two entry types and every refusal ----------
      // A CFE_APP line. The priority, stack size and exception action come out of the text
      // through StrToUL, which is why "0x40" and "16384" both work.
      tok[0] = "CFE_APP";
      tok[1] = "/cf/sch.so";
      tok[2] = "SCH_AppMain";
      tok[3] = "SCH";
      tok[4] = "0x40";
      tok[5] = "16384";
      tok[6] = "0x0";
      tok[7] = "0";
      rc = CFE_ES_ParseFileEntry(tok, 8);
      S("ess_app rc=");
      D(rc);
      S("\n");
      // A priority over OS_MAX_TASK_PRIORITY is CLAMPED, not refused -- and an exception action
      // over RESTART_APP becomes PROC_RESTART, so a typo makes the spacecraft MORE willing to
      // reset itself. Both show up in the os_moduleload/os_taskcreate lines.
      tok[3] = "SCH2";
      tok[4] = "999";
      tok[7] = "7";
      rc = CFE_ES_ParseFileEntry(tok, 8);
      S("ess_app_clamped rc=");
      D(rc);
      S("\n");
      // A CFE_LIB line reads only four of the eight fields, and the entry symbol is CALLED --
      // which is what makes it a library.
      tok[0] = "CFE_LIB";
      tok[1] = "/cf/cfs_lib.so";
      tok[2] = "CFS_LibInit";
      tok[3] = "CFS_LIB";
      es_modlookup_addr = &es_lib_init;
      rc = CFE_ES_ParseFileEntry(tok, 8);
      S("ess_lib rc=");
      D(rc);
      S("\n");
      es_modlookup_addr = 0xE0000000;
      // An unknown entry type is CFE_ES_ERR_APP_CREATE, not a parse error.
      tok[0] = "CFE_WAT";
      rc = CFE_ES_ParseFileEntry(tok, 8);
      S("ess_badtype rc=");
      D(rc);
      S("\n");
      // Too few fields.
      tok[0] = "CFE_APP";
      rc = CFE_ES_ParseFileEntry(tok, 7);
      S("ess_short rc=");
      D(rc);
      S("\n");
      // A file name the FS layer refuses.
      tok[1] = "";
      rc = CFE_ES_ParseFileEntry(tok, 8);
      S("ess_badname rc=");
      D(rc);
      S("\n");
      // CFE_ES_ReadStartupLine and CFE_ES_OpenStartupScript are `static` in NASA's .c, so
      // neither half can call them directly -- they are driven through CFE_ES_StartApplications
      // below, where the scripts are written with the whitespace and the token shapes that prove
      // the tokenisation: isgraph decides what is part of a token, so the spaces and the newline
      // are dropped and the ',' and ';' are the only delimiters. The ParseFileEntry log lines
      // show what came out.
      // --- CFE_ES_StartApplications, end to end ---------------------------------
      // A power-on reset reads the nonvolatile script only; a processor reset tries the volatile
      // copy first. Both go through the same simulated file.
      fs_open_fail = 0;
      MemCpy(fs_data, "CFE_LIB, /cf/a.so, A_Init, A, 0, 0, 0x0, 0;\n!", 45);
      fs_len = 45;
      es_modlookup_addr = &es_lib_init;
      S("ess_start_poweron\n");
      CFE_ES_StartApplications(CFE_PSP_RST_TYPE_POWERON, "/cf/cfe_es_startup.scr");
      MemCpy(fs_data, "CFE_LIB, /cf/c.so, C_Init, C, 0, 0, 0x0, 0;\n!", 45);
      fs_len = 45;
      S("ess_start_proc\n");
      CFE_ES_StartApplications(CFE_PSP_RST_TYPE_PROCESSOR, "/cf/cfe_es_startup.scr");
      es_modlookup_addr = 0xE0000000;
      // A MALFORMED LINE IS LOGGED AND SKIPPED, never fatal, and the detector is that both
      // buffers are one larger than the maximum: filling one IS overrunning it. This line has
      // nine fields.
      MemCpy(fs_data, "A,B,C,D,E,F,G,H,I;\n!", 21);
      fs_len = 21;
      S("ess_start_toomany\n");
      CFE_ES_StartApplications(CFE_PSP_RST_TYPE_POWERON, "/cf/cfe_es_startup.scr");
      // A script that will not open at all: two log lines and no parsing.
      fs_open_fail = 1;
      S("ess_start_noopen\n");
      CFE_ES_StartApplications(CFE_PSP_RST_TYPE_PROCESSOR, "/cf/cfe_es_startup.scr");
      fs_open_fail = 0;
      fs_len = 0;
      fs_pos = 0;
    }
    // --- cfe_es_start.c: THE BOOT SEQUENCE ------------------------------------------
    //
    // cFE's main(). Five states in order, and the only failure mode in the whole file is a panic
    // -- five of its eight functions call CFE_PSP_Panic after a half-second delay "to allow the
    // message to be read".
    //
    // EVERYTHING HERE RUNS AGAINST A SAVED AND RESTORED GLOBAL. CFE_ES_Main's first act is to
    // MemSet CFE_ES_Global, which would destroy every record this driver planted, so the boot is
    // driven last and the state is put back afterwards.
    
    {
      I32 rc;
      // --- CFE_ES_SetupResetVariables: how a reset loop is detected --------------
      // A power-on reset records the subtype and zeroes the counters. Three subtypes get three
      // different log lines and ER log entries.
      S("esb_reset_cycle\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_POWER_CYCLE, 1);
      S("esb_reset_cycle_v count=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount);
      S(" max=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount);
      S(" type=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ResetType);
      S(" sub=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype);
      S(" boot=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.BootSource);
      S("\n");
      S("esb_reset_hwcmd\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND, 2);
      S("esb_reset_other\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, 99, 3);
      // A PROCESSOR RESET THAT ES DID NOT CAUSE increments the counter. Under the maximum it is
      // logged as a processor reset; the watchdog and hw-command subtypes get different text.
      CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = FALSE;
      S("esb_reset_proc_wd\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_HW_WATCHDOG, 1);
      S("esb_reset_proc_wd_v count=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount);
      S(" sub=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype);
      S("\n");
      CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = FALSE;
      S("esb_reset_proc_hw\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND, 1);
      // OVER THE MAXIMUM, THE NEXT ONE IS ESCALATED TO A POWER-ON RESET -- which wipes the reset
      // area, so the loop is broken by losing state deliberately. The ER log entry is written
      // first, knowing it will not survive: "it's good to have the entry just in case something
      // fails".
      CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = FALSE;
      CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = 1;
      S("esb_reset_max_wd\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_HW_WATCHDOG, 1);
      CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = FALSE;
      CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = 1;
      CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount = 5;
      S("esb_reset_max_hw\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND, 1);
      // A reset ES DID cause was already logged on the way down, so this only updates the
      // variables -- no ER log entry, no counter change.
      CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = TRUE;
      S("esb_reset_commanded\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_PROCESSOR, 42, 1);
      S("esb_reset_commanded_v sub=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype);
      S(" caused=");
      D(CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset);
      S("\n");
      // The reset area being unavailable or too small: both panic, and both return here because
      // CFE_PSP_Panic is a stub that does.
      evs_resetarea_rc = CFE_PSP_ERROR;
      S("esb_reset_noarea\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, 1, 1);
      evs_resetarea_rc = CFE_PSP_SUCCESS;
      evs_resetarea_size = 16;
      S("esb_reset_small\n");
      CFE_ES_SetupResetVariables(CFE_PSP_RST_TYPE_POWERON, 1, 1);
      evs_resetarea_size = sizeof(CFE_ES_ResetData_t);
      // --- CFE_ES_InitializeFileSystems: format or re-attach ---------------------
      // A power-on reset FORMATS; a processor reset RE-ATTACHES and falls back to formatting.
      // That difference is the volatile disk's whole purpose.
      S("esb_fs_poweron\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
      S("esb_fs_poweron_v exists=");
      D(es_vol_exists);
      S(" mounted=");
      D(es_vol_mounted);
      S("\n");
      S("esb_fs_proc\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      // A failed re-attach falls back to a format, with its own log line.
      es_initfs_rc = OS_ERROR;
      S("esb_fs_initfail\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      es_initfs_rc = OS_SUCCESS;
      // THE DISK TOO FULL: unmount, remove, re-make, re-mount. 10 of 100 blocks free is under
      // the 30 percent reserve.
      es_vol_blocks_free = 10;
      S("esb_fs_full\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      es_vol_blocks_free = 90;
      // And every failure arm: the memory, the format, the mount, the stat, and each step of the
      // reformat.
      es_voldiskmem_rc = CFE_PSP_ERROR;
      S("esb_fs_nomem\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
      es_voldiskmem_rc = CFE_PSP_SUCCESS;
      es_mkfs_rc = OS_ERROR;
      S("esb_fs_mkfsfail\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
      es_mkfs_rc = OS_SUCCESS;
      es_mount_rc = OS_ERROR;
      S("esb_fs_mountfail\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_POWERON);
      es_mount_rc = OS_SUCCESS;
      es_statvol_rc = OS_ERROR;
      S("esb_fs_statfail\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      es_statvol_rc = OS_SUCCESS;
      // total_blocks of zero takes the same arm, because the division would be by zero.
      es_vol_total_blocks = 0;
      S("esb_fs_zeroblocks\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      es_vol_total_blocks = 100;
      // The reformat's four steps, each refused in turn.
      es_vol_blocks_free = 10;
      es_unmount_rc = OS_ERROR;
      S("esb_fs_unmountfail\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      es_unmount_rc = OS_SUCCESS;
      es_rmfs_rc = OS_ERROR;
      S("esb_fs_rmfsfail\n");
      CFE_ES_InitializeFileSystems(CFE_PSP_RST_TYPE_PROCESSOR);
      es_rmfs_rc = OS_SUCCESS;
      es_vol_blocks_free = 90;
      // CFE_ES_MainTaskSyncDelay is effectively static -- its definition has no `static` but a
      // prior forward declaration does, and in C the first declaration's linkage wins -- so its
      // two arms are driven through CFE_ES_CreateObjects and CFE_ES_Main below. The timeout arm
      // is the one that matters, and CreateObjects reaches it whenever a core app's task does not
      // come up RUNNING, which in this driver is always: OS_TaskCreate does not run entry points.
      // --- CFE_ES_CreateObjects, with a REAL core object table -------------------
      // THE ENTRIES GO INTO THE TABLE, NOT OVER THE POINTER. GLOBAL_CONFIGDATA is `const` in the
      // C half and lives in .rodata, so writing its CoreObjectTable field through a cast is a
      // SIGBUS -- which is how this was found. CFE_CORE_MODULE_OBJTAB is a separate object,
      // emitted writable with spare slots by tools/cfs/gen_target_config.py precisely so the
      // driver can do this, and GLOBAL_CONFIGDATA already points at it.
      CFE_CORE_MODULE_OBJTAB[0] = &es_core_entry_lib;
      CFE_CORE_MODULE_OBJTAB[1] = &es_core_entry_task;
      CFE_CORE_MODULE_OBJTAB[2] = NULL;
      S("esb_createobj\n");
      CFE_ES_CreateObjects();
      S("esb_createobj_v coreapps=");
      D(CFE_ES_Global.RegisteredCoreApps);
      S(" early=");
      D(es_core_early_calls);
      S(" tasks=");
      D(es_taskcreates);
      S("\n");
      // An EarlyInit that fails panics -- and returns, because the panic is a stub.
      es_core_early_rc = -5;
      S("esb_createobj_earlyfail\n");
      CFE_ES_CreateObjects();
      es_core_early_rc = CFE_SUCCESS;
      // And a task that cannot be created: the reserved slot is wiped rather than left claimed.
      es_taskcreate_rc = OS_ERROR;
      S("esb_createobj_taskfail\n");
      CFE_ES_CreateObjects();
      es_taskcreate_rc = OS_SUCCESS;
      CFE_CORE_MODULE_OBJTAB[0] = NULL;
      // --- CFE_ES_Main: THE WHOLE BOOT -------------------------------------------
      // Last, because its first act is to MemSet CFE_ES_Global. Everything above is saved and
      // restored around it. The five state transitions are in the log, in order, and the startup
      // script runs for real.
      MemCpy(&es_global_save, &CFE_ES_Global, sizeof(CFE_ES_Global_t));
      MemCpy(fs_data, "CFE_LIB, /cf/a.so, A_Init, A, 0, 0, 0x0, 0;\n!", 45);
      fs_len = 45;
      es_modlookup_addr = &es_lib_init;
      S("esb_main\n");
      CFE_ES_Main(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_POWER_CYCLE, 1, "/cf/cfe_es_startup.scr");
      S("esb_main_v state=");
      D(CFE_ES_Global.SystemState);
      S(" coreapps=");
      D(CFE_ES_Global.RegisteredCoreApps);
      S(" lastapp=");
      D(CFE_ES_Global.LastAppId);
      S("\n");
      // The shared-data mutex failing is the one failure that stops the boot before anything can
      // be logged -- so it reports through OS_printf and panics.
      fs_mut_create_rc = OS_ERROR;
      S("esb_main_nomutex\n");
      CFE_ES_Main(CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_POWER_CYCLE, 1, "/cf/cfe_es_startup.scr");
      fs_mut_create_rc = OS_SUCCESS;
      MemCpy(&CFE_ES_Global, &es_global_save, sizeof(CFE_ES_Global_t));
      es_modlookup_addr = 0xE0000000;
      fs_len = 0;
      fs_pos = 0;
      es_ctx_init();
    }
    // --- cfe_es_cds.c and cfe_es_cds_mempool.c: THE CRITICAL DATA STORE --------------
    //
    // The one piece of memory on a spacecraft that is expected to still be there after the
    // processor resets. It is not memory mapped -- NASA's comment at the cache is "Because CDS
    // memory is not memory mapped, this serves as temporary holding location for data being
    // actively accessed" -- so every byte in or out is a PSP call and everything funnels through
    // one 72-byte staging buffer.
    //
    // THE RESET IS WHY THE STORE IS SIMULATED RATHER THAN STUBBED. es_cds_reset wipes
    // CFE_ES_Global.CDSVars and leaves es_cds_store alone, which is exactly what cFE experiences
    // across a processor reset -- so the recovery path can actually run: the signatures are
    // found, the registry is read back, and CFE_ES_GenPoolRebuild recovers the allocator from the
    // block descriptors that survived in the store. A recording stub cannot reach any of that
    // code.
    //
    // The ES task block above already initialised the CDS and used it for the four delete
    // refusals. This drives what a command cannot reach.
    
    {
      U32 h1;
      U32 h2;
      CFE_ES_CDS_RegRec_t *rr;
      U32 idx;
      I32 rc;
      I64 reqd;
      I64 k;
      U32 badh = 0x990000;
      U32 oneh = 1;
      // THESE THREE ARE FILE-SCOPE BUFFERS, NOT LOCALS, and that is a measured requirement:
      // 168 bytes of stack arrays here made `&CFE_ES_ComputeCRC_Algo_16_ARC` -- a function
      // address in a file-scope initialiser read 500 lines earlier in this same function --
      // come back as 0, and the call through it trapped with mepc=0.
      // docs/HOLYC_STRUCT_LIMITS.md #22, with the 64-vs-128-byte threshold measured.
      U8 *cdsbuf = es_cdsbuf;
      U8 *cdsback = es_cdsback;
      U8 *nm = es_cdsnm;
      // --- the sizes, before anything is written ---------------------------------
      reqd = CFE_ES_CDSReqdMinSize(1);
      S("esd_minsize one=");
      D(reqd);
      S(" entries=");
      D(CFE_ES_CDSReqdMinSize(CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES));
      S("\n");
      // --- EarlyInit's refusals --------------------------------------------------
      // The mutex failing is the first thing that can go wrong, and the only one that stops it
      // before the store is even sized.
      fs_mut_create_rc = OS_ERROR;
      es_cds_reset();
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_init_mutexfail rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S("\n");
      fs_mut_create_rc = OS_SUCCESS;
      // The PSP refusing to say how big it is.
      es_cds_getsize_rc = CFE_PSP_ERROR;
      es_cds_reset();
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_init_sizefail rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S("\n");
      es_cds_getsize_rc = CFE_PSP_SUCCESS;
      // A STORE TOO SMALL IS REPORTED AND THEN IGNORED: Status stays CFE_SUCCESS and the CDS is
      // simply unavailable, so a spacecraft with a broken CDS still boots. The minimum is 36,884
      // bytes of layout plus a pool big enough for 512 blocks.
      es_cds_size = 1024;
      es_cds_reset();
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_init_toosmall rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S("\n");
      es_cds_size = ES_CDS_STORE_SIZE;
      // --- a first boot: no signatures, so wipe and build ------------------------
      MemSet(es_cds_store, 0xAA, ES_CDS_STORE_SIZE);
      es_cds_reset();
      es_cds_reads = 0;
      es_cds_writes = 0;
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_firstboot rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S(" total=");
      D(CFE_ES_Global.CDSVars.TotalSize);
      S(" data=");
      D(CFE_ES_Global.CDSVars.DataSize);
      S("\n");
      // The signatures are in the store now, at each end, and the entry count is at offset 8 --
      // which is what makes the next boot a recovery rather than a wipe.
      S("esd_sig begin=[");
      es_sig8(&es_cds_store[0]);
      S("] end=[");
      es_sig8(&es_cds_store[ES_CDS_STORE_SIZE - 8]);
      S("] regsize=");
      D (*((&es_cds_store[CDS_REG_SIZE_OFFSET])(U32 *)));
      S("\n");
      // --- register, write, read back --------------------------------------------
      rc = CFE_ES_RegisterCDSEx(&h1, 64, "CDSAPP.ONE", FALSE);
      S("esd_reg rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDSHandle_ToIndex(h1, &idx);
      S("esd_reg_idx rc=");
      D(rc);
      S(" idx=");
      D(idx);
      S("\n");
      rr = CFE_ES_LocateCDSBlockRecordByID(h1);
      S("esd_reg_rec name=");
      S(rr->Name);
      S(" size=");
      D(rr->BlockSize);
      S(" usersize=");
      D(CFE_ES_CDSBlockRecordGetUserSize(rr));
      S(" tbl=");
      D(rr->Table);
      S(" used=");
      D(CFE_ES_CDSBlockRecordIsUsed(rr));
      S("\n");
      for (k = 0; k < 64; ++k) {
        cdsbuf[k] = 0x40 + k;
      }
      rc = CFE_ES_CDSBlockWrite(h1, cdsbuf);
      S("esd_write rc=");
      D(rc);
      S("\n");
      MemSet(cdsback, 0, 64);
      rc = CFE_ES_CDSBlockRead(cdsback, h1);
      S("esd_read rc=");
      D(rc);
      S(" match=");
      D(MemCmp(cdsbuf, cdsback, 64) == 0);
      S(" first=");
      Hxb(cdsback[0]);
      S(" last=");
      Hxb(cdsback[63]);
      S("\n");
      // --- THE RESET, and the recovery -------------------------------------------
      // Everything in RAM is gone; the store is not. The signatures validate, the registry is
      // read back, and the pool is rebuilt from the descriptors in the store -- so the handle
      // from before the reset still reads its data.
      es_cds_reset();
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_reboot rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S("\n");
      rr = CFE_ES_LocateCDSBlockRecordByID(h1);
      S("esd_reboot_rec name=");
      S(rr->Name);
      S(" used=");
      D(CFE_ES_CDSBlockRecordIsUsed(rr));
      S(" size=");
      D(rr->BlockSize);
      S("\n");
      MemSet(cdsback, 0, 64);
      rc = CFE_ES_CDSBlockRead(cdsback, h1);
      S("esd_reboot_read rc=");
      D(rc);
      S(" match=");
      D(MemCmp(cdsbuf, cdsback, 64) == 0);
      S("\n");
      // AND THE NAME STILL FINDS IT, which is how an app that restarts gets its own store back:
      // re-registering the same name at the same size returns the alt-success code
      // CFE_ES_CDS_ALREADY_EXISTS -- not an error, high bit clear -- and the same handle.
      rc = CFE_ES_RegisterCDSEx(&h2, 64, "CDSAPP.ONE", FALSE);
      S("esd_rereg rc=");
      D(rc);
      S(" same=");
      D(h1 == h2);
      S("\n");
      // A DIFFERENT SIZE IS A REALLOCATION, and NASA says the alt-success code is deliberately
      // NOT returned for it: the old block is freed and a new one taken, so the data is gone
      // even though the name and the handle are the same.
      rc = CFE_ES_RegisterCDSEx(&h2, 128, "CDSAPP.ONE", FALSE);
      rr = CFE_ES_LocateCDSBlockRecordByID(h2);
      S("esd_rereg_resize rc=");
      D(rc);
      S(" same=");
      D(h1 == h2);
      S(" size=");
      D(rr->BlockSize);
      S("\n");
      // --- THE CRC IS THE ANSWER TO "DID THIS SURVIVE INTACT" --------------------
      // Corrupt one byte of the user data in the store, behind the CDS's back, and the read
      // refuses. Nothing repairs it, because nothing can.
      rc = CFE_ES_CDSBlockWrite(h2, cdsbuf);
      S("esd_write2 rc=");
      D(rc);
      S("\n");
      rr = CFE_ES_LocateCDSBlockRecordByID(h2);
      es_cds_store[rr->BlockOffset + 4] ^= 0xFF;
      rc = CFE_ES_CDSBlockRead(cdsback, h2);
      S("esd_read_corrupt rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDSBlockWrite(h2, cdsbuf);
      S("esd_write3 rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDSBlockRead(cdsback, h2);
      S("esd_read_ok rc=");
      D(rc);
      S("\n");
      // --- the refusals a caller can provoke -------------------------------------
      rc = CFE_ES_RegisterCDSEx(&h2, 0, "X.Y", FALSE);
      S("esd_reg_zero rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_RegisterCDSEx(&h2, 1073741824, "X.Y", FALSE);
      S("esd_reg_huge rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDSBlockWrite(badh, cdsbuf);
      S("esd_write_badh rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDSBlockRead(cdsback, badh);
      S("esd_read_badh rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDSHandle_ToIndex(oneh, &idx);
      S("esd_toidx_bad rc=");
      D(rc);
      S("\n");
      S("esd_locate_bad null=");
      D(CFE_ES_LocateCDSBlockRecordByID(oneh) == NULL);
      S("\n");
      S("esd_byname_miss null=");
      D(CFE_ES_LocateCDSBlockRecordByName("NOPE.NOPE") == NULL);
      S("\n");
      // --- the cache's own bounds -------------------------------------------------
      // Every fetch, flush and preload refuses zero and anything over the union's 72 bytes. It
      // is the only bound checking the CDS has, because the store is reached by call and not by
      // pointer -- there is no fault to catch.
      rc = CFE_ES_CDS_CacheFetch(&CFE_ES_Global.CDSVars.Cache, 0, 0);
      S("esd_cache_zero rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDS_CacheFetch(&CFE_ES_Global.CDSVars.Cache, 0, 1024);
      S("esd_cache_big rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_CDS_CachePreload(&CFE_ES_Global.CDSVars.Cache, cdsbuf, 0, 1024);
      S("esd_cache_preload_big rc=");
      D(rc);
      S("\n");
      CFE_ES_Global.CDSVars.Cache.Size = 0;
      rc = CFE_ES_CDS_CacheFlush(&CFE_ES_Global.CDSVars.Cache);
      S("esd_cache_flush_zero rc=");
      D(rc);
      S("\n");
      // --- a store that reads back wrong -----------------------------------------
      // An unreadable store: the first signature fetch fails, which is not "invalid" but a PSP
      // error, and it is reported as itself.
      es_cds_read_rc = CFE_PSP_ERROR;
      rc = CFE_ES_ValidateCDS();
      S("esd_validate_readfail rc=");
      D(rc);
      S("\n");
      es_cds_read_rc = CFE_PSP_SUCCESS;
      // A wrong END signature, with the beginning intact -- the case a store that was grown or
      // truncated would hit.
      es_cds_store[ES_CDS_STORE_SIZE - 1] = 'X';
      rc = CFE_ES_ValidateCDS();
      S("esd_validate_endbad rc=");
      D(rc);
      S("\n");
      // An entry count from a differently-configured build. The registry that follows would be
      // the wrong size, so this is CFE_ES_CDS_INVALID -- wipe and start again, not an attempt to
      // convert.
      *((&es_cds_store[CDS_REG_SIZE_OFFSET])(U32 *)) = 7;
      rc = CFE_ES_RebuildCDS();
      S("esd_rebuild_wrongcount rc=");
      D(rc);
      S("\n");
      // And a store whose registry cannot be read at all.
      *((&es_cds_store[CDS_REG_SIZE_OFFSET])(U32 *)) = CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES;
      es_cds_read_rc = CFE_PSP_ERROR;
      rc = CFE_ES_RebuildCDS();
      S("esd_rebuild_readfail rc=");
      D(rc);
      S("\n");
      es_cds_read_rc = CFE_PSP_SUCCESS;
      // --- a store that will not take a write ------------------------------------
      // The wipe fails on its first flush.
      es_cds_write_rc = CFE_PSP_ERROR;
      rc = CFE_ES_ClearCDS();
      S("esd_clear_fail rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_InitCDSSignatures();
      S("esd_sig_fail rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_InitCDSRegistry();
      S("esd_initreg_fail rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_UpdateCDSRegistry();
      S("esd_updatereg_fail rc=");
      D(rc);
      S("\n");
      es_cds_write_rc = CFE_PSP_SUCCESS;
      // THE END SIGNATURE FAILING WITH THE BEGINNING WRITTEN, which is the one partial state the
      // store can be left in -- and it is safe, because the next boot validates the beginning,
      // fails on the end, and wipes.
      es_cds_write_fail_at = ES_CDS_STORE_SIZE - 8;
      rc = CFE_ES_InitCDSSignatures();
      S("esd_sig_endfail rc=");
      D(rc);
      S("\n");
      es_cds_write_fail_at = 0xFFFFFFFF;
      // --- the pool, filled until it refuses --------------------------------------
      // A 64 KiB store leaves about 28 KiB of pool after the 36,884-byte layout, so a few
      // hundred small blocks exhaust it -- and CFE_ES_RegisterCDS_AllocateBlock's refusal is the
      // allocator's, not the registry's.
      MemSet(es_cds_store, 0, ES_CDS_STORE_SIZE);
      es_cds_reset();
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_pool_init rc=");
      D(rc);
      S("\n");
      rc = CFE_SUCCESS;
      k = 0;
      while (rc == CFE_SUCCESS && k < 600) {
        StrPrintN(nm, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN, "FILL.%03d", k);
        rc = CFE_ES_RegisterCDSEx(&h2, 64, nm, FALSE);
        ++k;
      }
      S("esd_pool_full after=");
      D(k);
      S(" rc=");
      D(rc);
      S("\n");
      // Leave the CDS in a clean, available state for anything after this.
      MemSet(es_cds_store, 0, ES_CDS_STORE_SIZE);
      es_cds_reset();
      rc = CFE_ES_CDS_EarlyInit();
      S("esd_final rc=");
      D(rc);
      S(" avail=");
      D(CFE_ES_Global.CDSIsAvailable);
      S("\n");
    }
    // --- cfe_es_apps.c: THE APP LIFECYCLE ---------------------------------------------
    //
    // Loading a module, looking up its entry symbol, starting its task, and taking all of that
    // apart again. Six stubs went away from both halves of this driver on the commit that gated
    // this source -- CFE_ES_LockUserAppRecord, StartAppTask, AppCreate, CleanUpApp and the three
    // CopyModule*Info -- and every probe above that steered one of them now steers an OSAL call
    // instead, which is the honest place for the knob.
    //
    // WHAT IS WORTH DRIVING DIRECTLY is what the paths above cannot reach: LoadModule's four
    // outcomes, the whole of LoadLibrary (nothing else in cFE loads a library), and
    // CleanupTaskResources against the object table -- eight object kinds, an unknown kind, a
    // delete that refuses, and the trend guard that stops the sweep looping forever.
    
    {
      CFE_ES_ModuleLoadParams_t mlp;
      CFE_ES_ModuleLoadStatus_t mls;
      CFE_ES_AppStartParams_t sparams;
      U32 lid;
      U32 aid2;
      U8 nbuf[OS_MAX_API_NAME];
      U32 k;
      I32 rc;
      // EVERY ID GOES THROUGH A LOCAL, and docs/HOLYC_STRUCT_LIMITS.md #20 is why: a constant
      // `A + B` written straight into a call whose parameter is a pointer gets the addition
      // scaled by the pointee's size, silently. es_app_slot carries the same note.
      U32 a2 = ES_CTX_APPID(2);
      U32 l2 = ES_LIBID(2);
      U32 tbase = CFE_ES_TASKID_BASE;
      U32 lbase = CFE_ES_LIBID_BASE;
      U32 tmpid;
      es_objs_clear();
      MemSet(&mlp, 0, sizeof(CFE_ES_ModuleLoadParams_t));
      MemSet(&mls, 0, sizeof(CFE_ES_ModuleLoadStatus_t));
      MemSet(&sparams, 0, sizeof(CFE_ES_AppStartParams_t));
      // --- CFE_ES_LoadModule -----------------------------------------------------
      //
      // AN EMPTY FILE NAME IS NOT AN ERROR: a core app, or a library already linked in, has
      // nothing to load, so the module id stays undefined and the call succeeds.
      rc = CFE_ES_LoadModule(a2, "NOFILE", &mlp, &mls);
      S("esm_load_nofile rc=");
      D(rc);
      S(" mod=");
      D(mls.ModuleId);
      S("\n");
      // The flags differ by resource kind, and that is the whole switch: an APP keeps its
      // symbols LOCAL so the module stays unloadable, a LIBRARY exposes them GLOBALLY -- which
      // is zero, OSAL's default, so the library arm's OR is a no-op.
      StrNCpy(mlp.FileName, "/cf/thing.so", OS_MAX_PATH_LEN - 1);
      rc = CFE_ES_LoadModule(a2, "THING", &mlp, &mls);
      S("esm_load_app rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_LoadModule(l2, "THING", &mlp, &mls);
      S("esm_load_lib rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_LoadModule(0x990000, "THING", &mlp, &mls);
      S("esm_load_other rc=");
      D(rc);
      S("\n");
      // The load itself failing.
      es_modload_rc = OS_ERROR;
      rc = CFE_ES_LoadModule(a2, "THING", &mlp, &mls);
      S("esm_load_fail rc=");
      D(rc);
      S("\n");
      es_modload_rc = OS_SUCCESS;
      // An entry symbol, found and not found. THE UNLOAD AFTER A FAILED LOOKUP is the part
      // worth seeing: a bad entry symbol must not leak the module it loaded.
      StrNCpy(mlp.InitSymbolName, "THING_Main", OS_MAX_API_NAME - 1);
      rc = CFE_ES_LoadModule(a2, "THING", &mlp, &mls);
      S("esm_load_sym rc=");
      D(rc);
      S(" addr=");
      Hx8(mls.InitSymbolAddress);
      S("\n");
      es_modlookup_rc = OS_ERROR;
      rc = CFE_ES_LoadModule(a2, "THING", &mlp, &mls);
      S("esm_load_symfail rc=");
      D(rc);
      S(" unloads=");
      D(es_modunloads);
      S("\n");
      // And the unload after that failure ALSO failing, which NASA can only report: "There's
      // not much we can do except notify."
      es_modunload_rc = OS_ERROR;
      rc = CFE_ES_LoadModule(a2, "THING", &mlp, &mls);
      S("esm_load_symfail_unloadfail rc=");
      D(rc);
      S("\n");
      es_modunload_rc = OS_SUCCESS;
      es_modlookup_rc = OS_SUCCESS;
      // The literal string "NULL" means "no entry symbol", which is how a startup-script line
      // says so -- no lookup happens at all.
      StrNCpy(mlp.InitSymbolName, "NULL", OS_MAX_API_NAME - 1);
      rc = CFE_ES_LoadModule(a2, "THING", &mlp, &mls);
      S("esm_load_nullsym rc=");
      D(rc);
      S(" lookups=");
      D(es_modlookups);
      S("\n");
      // --- CFE_ES_LoadLibrary ----------------------------------------------------
      //
      // The same reserved-slot protocol as AppCreate, and three real differences: no task, the
      // entry symbol is called ONCE inline with the library's own id, and a duplicate name
      // reports the EXISTING library's id rather than UNDEFINED.
      MemSet(&mlp, 0, sizeof(CFE_ES_ModuleLoadParams_t));
      StrNCpy(mlp.FileName, "/cf/libthing.so", OS_MAX_PATH_LEN - 1);
      StrNCpy(mlp.InitSymbolName, "LIBTHING_Init", OS_MAX_API_NAME - 1);
      CFE_ES_Global.LastLibId = lbase;
      es_modlookup_addr = &es_lib_init;
      rc = CFE_ES_LoadLibrary(&lid, "LIBTHING", &mlp);
      S("esl_lib rc=");
      D(rc);
      S(" id=");
      D(lid);
      S(" libs=");
      D(CFE_ES_Global.RegisteredLibs);
      S("\n");
      // A duplicate library name hands back the id of the one already loaded -- the only path
      // in either loader where a failure returns a usable id.
      rc = CFE_ES_LoadLibrary(&lid, "LIBTHING", &mlp);
      S("esl_lib_dup rc=");
      D(rc);
      S(" id=");
      D(lid);
      S("\n");
      // And one namespace with apps: a library may not take an app's name.
      rc = CFE_ES_LoadLibrary(&lid, "CFE_EVS", &mlp);
      S("esl_lib_appname rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_LoadLibrary(&lid, NULL, &mlp);
      S("esl_lib_nullname rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_LoadLibrary(&lid, "X", NULL);
      S("esl_lib_nullparams rc=");
      D(rc);
      S("\n");
      // A name with no terminator inside the record's width, checked with MemChr rather than a
      // length -- StrLen on a caller's buffer is what runs off the end.
      MemSet(nbuf, 'L', OS_MAX_API_NAME);
      rc = CFE_ES_LoadLibrary(&lid, nbuf, &mlp);
      S("esl_lib_longname rc=");
      D(rc);
      S("\n");
      // The load failing, and the init function returning an error. Both leave the slot free
      // again, and the id comes back UNDEFINED.
      es_modload_rc = OS_ERROR;
      rc = CFE_ES_LoadLibrary(&lid, "LIBTWO", &mlp);
      S("esl_lib_loadfail rc=");
      D(rc);
      S(" id=");
      D(lid);
      S("\n");
      es_modload_rc = OS_SUCCESS;
      es_lib_init_rc = -77;
      rc = CFE_ES_LoadLibrary(&lid, "LIBTWO", &mlp);
      S("esl_lib_initfail rc=");
      D(rc);
      S(" id=");
      D(lid);
      S(" libs=");
      D(CFE_ES_Global.RegisteredLibs);
      S("\n");
      es_lib_init_rc = CFE_SUCCESS;
      // Every slot taken.
      for (k = 0; k < CFE_PLATFORM_ES_MAX_LIBRARIES; ++k) {
        tmpid = lbase + k;
        CFE_ES_LibRecordSetUsed(&CFE_ES_Global.LibTable[k], tmpid);
      }
      rc = CFE_ES_LoadLibrary(&lid, "LIBFULL", &mlp);
      S("esl_lib_nofree rc=");
      D(rc);
      S("\n");
      MemSet(CFE_ES_Global.LibTable, 0, CFE_PLATFORM_ES_MAX_LIBRARIES *sizeof(CFE_ES_LibRecord_t));
      CFE_ES_Global.RegisteredLibs = 0;
      es_modlookup_addr = 0xE0000000;
      // --- CFE_ES_CleanupTaskResources, against the object table -------------------
      //
      // This is the only place a dead task's resources can be reclaimed from, because nothing
      // recorded that it made them: OS_ForEachObject hands over every object whose creator it
      // was, and the callback asks OS_IdentifyObject what each one is. All eight kinds, in one
      // sweep.
      es_objs_clear();
      es_obj_add(0x7001, OS_OBJECT_TYPE_OS_BINSEM);
      es_obj_add(0x7002, OS_OBJECT_TYPE_OS_COUNTSEM);
      es_obj_add(0x7003, OS_OBJECT_TYPE_OS_MUTEX);
      es_obj_add(0x7004, OS_OBJECT_TYPE_OS_TIMECB);
      es_obj_add(0x7005, OS_OBJECT_TYPE_OS_STREAM);
      tmpid = tbase + 5;
      rc = CFE_ES_CleanupTaskResources(tmpid);
      S("esm_cleanup_sweep rc=");
      D(rc);
      S(" foreach=");
      D(es_foreach_calls);
      S("\n");
      // AN UNKNOWN KIND IS NOT COUNTED AT ALL -- not as found, not as a failure -- which is
      // what keeps the trend guard from being confused by a type OSAL grows later.
      es_objs_clear();
      es_obj_add(0x7010, OS_OBJECT_TYPE_OS_DIR);
      tmpid = tbase + 6;
      rc = CFE_ES_CleanupTaskResources(tmpid);
      S("esm_cleanup_unknown rc=");
      D(rc);
      S("\n");
      // A QUEUE object: OS_QueueDelete's own body refuses an id that is not one of SB's created
      // queues, so this is the CFE_ES_QUEUE_DELETE_ERR arm -- and the object is never marked
      // gone, so it is also the "found objects are not trending downward" guard that stops the
      // sweep.
      es_objs_clear();
      es_obj_add(0x7020, OS_OBJECT_TYPE_OS_QUEUE);
      tmpid = tbase + 7;
      rc = CFE_ES_CleanupTaskResources(tmpid);
      S("esm_cleanup_stuck rc=");
      D(rc);
      S("\n");
      // A delete that refuses outright, on a type whose error code is its own.
      es_objs_clear();
      es_obj_add(0x7030, OS_OBJECT_TYPE_OS_TIMECB);
      es_objdel_rc = OS_ERROR;
      tmpid = tbase + 8;
      rc = CFE_ES_CleanupTaskResources(tmpid);
      S("esm_cleanup_refused rc=");
      D(rc);
      S("\n");
      es_objdel_rc = OS_SUCCESS;
      // NO OBJECTS AT ALL, and the task delete failing -- which is the one way
      // CFE_ES_TASK_DELETE_ERR comes out. A self-exited task reports OS_ERR_INVALID_ID instead
      // and that is NOT an error: NASA's comment is "there is nothing else needed to do".
      es_objs_clear();
      es_taskdelete_rc = OS_ERROR;
      tmpid = tbase + 9;
      rc = CFE_ES_CleanupTaskResources(tmpid);
      S("esm_cleanup_taskfail rc=");
      D(rc);
      S("\n");
      es_taskdelete_rc = OS_ERR_INVALID_ID;
      rc = CFE_ES_CleanupTaskResources(tmpid);
      S("esm_cleanup_selfexited rc=");
      D(rc);
      S("\n");
      es_taskdelete_rc = OS_SUCCESS;
      // --- CFE_ES_AppCreate's refusals, which the ground command cannot reach ------
      rc = CFE_ES_AppCreate(&aid2, NULL, &sparams);
      S("esm_create_nullname rc=");
      D(rc);
      S("\n");
      rc = CFE_ES_AppCreate(&aid2, "X", NULL);
      S("esm_create_nullparams rc=");
      D(rc);
      S("\n");
      MemSet(nbuf, 'A', OS_MAX_API_NAME);
      rc = CFE_ES_AppCreate(&aid2, nbuf, &sparams);
      S("esm_create_longname rc=");
      D(rc);
      S("\n");
      es_ctx_init();
      es_objs_clear();
    }
    // --- cfe_es_appctrl.c: CARRYING OUT A CONTROL REQUEST -----------------------------
    //
    // cfe_es_api.c's RestartApp, ReloadApp and DeleteApp only STORE a request in the app
    // record -- the block above already asserted that, and that the app keeps running. This
    // is the other half: the four functions the background task runs later to actually delete
    // the app, maybe start it again, and say what happened.
    //
    // THE EVENT IS THE ASSERTION. One event comes out of each request, chosen from a ten-row
    // table indexed by RUN STATUS, and NASA writes that table with DESIGNATED initialisers --
    // most rows set two of five fields and leave the rest zero, and every branch in _Finish
    // tests one of those fields against zero. HolyC has no designated initialisers, so the
    // translation writes all five fields of all ten rows positionally. A row written one
    // field off still compiles, still passes every structural gate, and sends the wrong
    // event. Nothing but this comparison would notice.
    //
    // So every row is driven, including the two reserved ones and an out-of-range request,
    // and the three branches inside a row -- cleanup failed, startup failed, nominal -- are
    // driven separately on the rows that have them.
    
    {
      CFE_ES_AppRecord_t *arp = &CFE_ES_Global.AppTable[2];
      CFE_ES_AppTableScanState_t *sst = &CFE_ES_Global.BackgroundAppScanState;
      U32 a2 = ES_CTX_APPID(2);
      U32 a9 = ES_CTX_APPID(9);
      U32 a4 = ES_CTX_APPID(4);
      CFE_ES_AppStartParams_t sp;
      U8 nm[OS_MAX_API_NAME];
      U32 req;
      U32 burst;
      Bool r;
      es_ctx_init();
      es_objs_clear();
      // THE SQUELCH HAS TO COME OFF OR THIS BLOCK ASSERTS NOTHING. EVS's per-app token bucket
      // ran dry during the ES task block above -- "44: Events squelched, AppName = CFE_EVS" is
      // in the transcript -- and every event after that is dropped silently. This block's
      // entire assertion is WHICH EVENT came out, so it was written, run, and produced thirty
      // lines of path markers with no events at all. Zeroing EVS_EventBurstMax is what the EVS
      // block does for the same reason and short-circuits EVS_CheckAndIncrementSquelchTokens.
      // Restored at the end.
      burst = CFE_EVS_Global.EVS_EventBurstMax;
      CFE_EVS_Global.EVS_EventBurstMax = 0;
      // --- _Start: THE SNAPSHOT TAKEN UNDER THE LOCK --------------------------------
      //
      // NASA's reason for the copy is that the caller is about to delete the record it just
      // read: "This way it becomes private and can be accessed without concerns about other
      // threads/tasks, even after the global data records are eventually cleared."
      //
      // AND THE COPY IS THE SECOND LIVE SITE OF docs/HOLYC_STRUCT_LIMITS.md #21. NASA writes
      // `*RestartParamPtr = AppRecPtr->StartParams;` -- a 344-byte struct copy through a bare
      // pointer, which in HolyC moves eight bytes and leaves the rest at whatever the
      // destination held. The entry point, stack size, priority and exception action below are
      // all past that eighth byte, so a translation that wrote the assignment would restart
      // the app with a zero stack and no entry symbol. Each is printed.
      StrNCpy(arp->StartParams.BasicInfo.InitSymbolName, "OTHER_AppMain", OS_MAX_API_NAME - 1);
      arp->StartParams.MainTaskInfo.StackSize = 8192;
      arp->StartParams.MainTaskInfo.Priority = 77;
      arp->StartParams.ExceptionAction = CFE_ES_ExceptionAction_PROC_RESTART;
      arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RESTART;
      MemSet(&sp, 0, sizeof(CFE_ES_AppStartParams_t));
      MemSet(nm, 0, OS_MAX_API_NAME);
      req = CFE_ES_ProcessControlRequest_Start(a2, nm, OS_MAX_API_NAME, &sp);
      S("esc_start req=");
      D(req);
      S(" name=");
      S(nm);
      S(" file=");
      S(sp.BasicInfo.FileName);
      S(" entry=");
      S(sp.BasicInfo.InitSymbolName);
      S(" stack=");
      D(sp.MainTaskInfo.StackSize);
      S(" prio=");
      D(sp.MainTaskInfo.Priority);
      S(" exc=");
      D(sp.ExceptionAction);
      S("\n");
      // A request that is not a restart or a reload does NOT copy the parameters. The buffer
      // is zeroed first, so an unconditional copy would show up here.
      arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
      MemSet(&sp, 0, sizeof(CFE_ES_AppStartParams_t));
      MemSet(nm, 0, OS_MAX_API_NAME);
      req = CFE_ES_ProcessControlRequest_Start(a2, nm, OS_MAX_API_NAME, &sp);
      S("esc_start_nocopy req=");
      D(req);
      S(" name=");
      S(nm);
      S(" file=[");
      S(sp.BasicInfo.FileName);
      S("] stack=");
      D(sp.MainTaskInfo.StackSize);
      S("\n");
      // No record matches, so the snapshot is never taken and the request stays 0 -- which is
      // CFE_ES_RunStatus_UNDEFINED, the table row with no name. That is how a stale app id
      // turns into the "[Req0]" event below rather than a wild read.
      MemSet(nm, 0, OS_MAX_API_NAME);
      req = CFE_ES_ProcessControlRequest_Start(a9, nm, OS_MAX_API_NAME, &sp);
      S("esc_start_nomatch req=");
      D(req);
      S(" name=[");
      S(nm);
      S("]\n");
      // --- _Finish: ALL TEN ROWS, PLUS ONE PAST THE END ----------------------------
      //
      // The nominal case for each row: no cleanup error, no startup error, no new app id.
      // Rows 0, 8 and 9 have an ErrorEventID set and so send that instead; row 1 ("Run") has
      // NOTHING set, which is NASA's //jphfix, and sends no event at all.
      for (req = 0; req <= CFE_ES_RunStatus_MAX; ++req) {
        S("esc_fin req=");
        D(req);
        S("\n");
        CFE_ES_ProcessControlRequest_Finish(req, "OTHER_APP", CFE_SUCCESS, CFE_SUCCESS, CFE_ES_APPID_UNDEFINED);
      }
      // A new app id is appended to the nominal text, and only when it is defined.
      S("esc_fin_newid\n");
      CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_RELOAD, "OTHER_APP", CFE_SUCCESS, CFE_SUCCESS, a4);
      // Cleanup failed, on a row that HAS a CleanupErrEventID.
      S("esc_fin_cleanuperr\n");
      CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_DELETE, "OTHER_APP", CFE_SUCCESS, CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_ES_APPID_UNDEFINED);
      // Cleanup failed on a row that has NO CleanupErrEventID -- "Exception" -- so the failure
      // is swallowed and the nominal event goes out. NASA's note: "The CleanupStatus is a
      // dont-care when CleanupErrEventID is not set."
      S("esc_fin_cleanuperr_dontcare\n");
      CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_EXCEPTION, "OTHER_APP", CFE_SUCCESS, CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_ES_APPID_UNDEFINED);
      // Startup failed, on a row that has a StartupErrEventID.
      S("esc_fin_startuperr\n");
      CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_RESTART, "OTHER_APP", CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_SUCCESS, CFE_ES_APPID_UNDEFINED);
      // BOTH failed. Cleanup wins, because its branch is tested first.
      S("esc_fin_botherr\n");
      CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_SYS_RELOAD, "OTHER_APP", CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_ES_APPID_UNDEFINED);
      // A startup failure on a row with no StartupErrEventID -- "Exit" -- is a dont-care the
      // same way, and the nominal event goes out.
      S("esc_fin_startuperr_dontcare\n");
      CFE_ES_ProcessControlRequest_Finish(CFE_ES_RunStatus_APP_EXIT, "OTHER_APP", CFE_ES_ERR_RESOURCEID_NOT_VALID, CFE_SUCCESS, CFE_ES_APPID_UNDEFINED);
      // --- ProcessControlRequest: END TO END ---------------------------------------
      //
      // Snapshot, CleanUpApp, maybe AppCreate, event. Each of the seven live requests, and the
      // app record is re-planted each time because the real CleanUpApp would have cleared it --
      // the stub does not, which is exactly why the loop has to.
      for (req = CFE_ES_RunStatus_APP_RUN; req <= CFE_ES_RunStatus_SYS_DELETE; ++req) {
        // THE WHOLE TABLE IS CLEARED, not just slot 2, and the reason is a residue the stub
        // never produced: a successful restart really does create a NEW app record now, named
        // OTHER_APP, in whatever slot was free. Re-planting slot 2 on the next pass then left
        // TWO records with that name, so the following AppCreate reported a duplicate and the
        // reload success path stopped being exercised.
        MemSet(CFE_ES_Global.AppTable, 0, CFE_PLATFORM_ES_MAX_APPLICATIONS *sizeof(CFE_ES_AppRecord_t));
        es_app_slot(1, "CFE_EVS", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
        es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
        StrNCpy(arp->StartParams.BasicInfo.InitSymbolName, "OTHER_AppMain", OS_MAX_API_NAME - 1);
        arp->StartParams.MainTaskInfo.StackSize = 8192;
        arp->StartParams.MainTaskInfo.Priority = 77;
        arp->ControlReq.AppControlRequest = req;
        S("esc_pcr req=");
        D(req);
        S("\n");
        CFE_ES_ProcessControlRequest(a2);
      }
      // Cleanup failing does NOT stop the restart, which is the behaviour NASA argues for at
      // length: a stale task id is a minor inconsistency in the old record and should not cost
      // the operator the new app. So AppCreate still runs.
      // THE FAILURE IS REAL NOW RATHER THAN A RETURN CODE. Until cfe_es_apps.c was gated this
      // was `es_cleanup_rc = ...` on a stub; the real CFE_ES_CleanUpApp returns
      // CFE_ES_APP_CLEANUP_ERR only when its FailCount is non-zero, so something has to
      // actually fail to be reclaimed. An OSAL object of QUEUE type owned by the app's main
      // task does it: the cleanup callback calls OS_QueueDelete, whose own body refuses an id
      // that is not one of SB's created queues, and the error propagates
      // CFE_ES_QUEUE_DELETE_ERR out through CleanupTaskResources and FreeTasks.
      es_objs_clear();
      es_obj_add(es_os_taskid, OS_OBJECT_TYPE_OS_QUEUE);
      es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
      arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RESTART;
      S("esc_pcr_cleanupfail\n");
      CFE_ES_ProcessControlRequest(a2);
      // And AppCreate failing.
      es_objs_clear();
      es_modload_rc = CFE_ES_ERR_RESOURCEID_NOT_VALID;
      es_app_slot(2, "OTHER_APP", CFE_ES_AppType_EXTERNAL, CFE_ES_AppState_RUNNING);
      arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RELOAD;
      S("esc_pcr_createfail\n");
      CFE_ES_ProcessControlRequest(a2);
      es_modload_rc = OS_SUCCESS;
      // A stale app id: no snapshot, request 0, the unnamed row, "[Req0]".
      S("esc_pcr_stale\n");
      CFE_ES_ProcessControlRequest(a9);
      // --- RunAppTableScan: WHAT MAKES A STORED REQUEST HAPPEN ---------------------
      //
      // A RUNNING app is not killed, it is ASKED. An app with a pending request moves to
      // WAITING and is given APP_KILL_TIMEOUT scan periods; only when that runs out does the
      // request get carried out. That window is the app's chance to exit cleanly through
      // CFE_ES_ExitApp.
      es_ctx_init();
      es_objs_clear();
      MemSet(sst, 0, sizeof(CFE_ES_AppTableScanState_t));
      // Not due: no pending changes, the command counter has not moved, and the timer has time
      // left. The timer is decremented and nothing is scanned.
      sst->LastScanCommandCount = CFE_ES_Global.TaskData.CommandCounter;
      sst->BackgroundScanTimer = 1000;
      r = CFE_ES_RunAppTableScan(10, sst);
      S("esc_scan_notdue r=");
      D(r);
      S(" timer=");
      D(sst->BackgroundScanTimer);
      S(" pend=");
      D(sst->PendingAppStateChanges);
      S("\n");
      // The command counter moving makes a scan due IMMEDIATELY, which is how a ground command
      // that stores a request is acted on at once rather than up to a second later. Nothing is
      // pending, so the scan finds nothing and the timer is reloaded.
      ++CFE_ES_Global.TaskData.CommandCounter;
      r = CFE_ES_RunAppTableScan(10, sst);
      S("esc_scan_cmdcount r=");
      D(r);
      S(" timer=");
      D(sst->BackgroundScanTimer);
      S(" pend=");
      D(sst->PendingAppStateChanges);
      S(" last=");
      D(sst->LastScanCommandCount);
      S("\n");
      // A pending request on a RUNNING app: it moves to WAITING and gets the timeout. Note it
      // is NOT counted as a pending state change on this pass -- the branch that counts runs
      // only for apps already past RUNNING -- so the scan still returns false and the next pass
      // is a normal timed one.
      arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
      sst->BackgroundScanTimer = 0;
      r = CFE_ES_RunAppTableScan(0, sst);
      S("esc_scan_ask r=");
      D(r);
      S(" state=");
      D(arp->AppState);
      S(" timer=");
      D(arp->ControlReq.AppTimerMsec);
      S(" pend=");
      D(sst->PendingAppStateChanges);
      S("\n");
      // Now it is WAITING, so each scan counts it and winds its timer down. One tick short of
      // the end, nothing happens except the countdown -- and the scan returns TRUE, which is
      // what makes the background task come back sooner.
      sst->BackgroundScanTimer = 0;
      r = CFE_ES_RunAppTableScan(4000, sst);
      S("esc_scan_wait r=");
      D(r);
      S(" state=");
      D(arp->AppState);
      S(" timer=");
      D(arp->ControlReq.AppTimerMsec);
      S(" pend=");
      D(sst->PendingAppStateChanges);
      S("\n");
      // The timer reaches zero, the app id goes on the timeout list, and the request is carried
      // out AFTER the lock is released -- NASA: "This avoids needing to access the global
      // records outside of the lock." The es_cleanupapp line and the Stop event below are that
      // deletion.
      sst->BackgroundScanTimer = 0;
      S("esc_scan_fire\n");
      r = CFE_ES_RunAppTableScan(4000, sst);
      S("esc_scan_fired r=");
      D(r);
      S(" used=");
      D(CFE_ES_AppRecordIsUsed(arp));
      S(" pend=");
      D(sst->PendingAppStateChanges);
      S("\n");
      // A CORE app is skipped entirely, however it is set up: NASA's loop tests
      // Type == EXTERNAL. So a pending request on a core app is never carried out.
      es_app_slot(2, "CORE_APP", CFE_ES_AppType_CORE, CFE_ES_AppState_WAITING);
      arp->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
      arp->ControlReq.AppTimerMsec = 0;
      sst->BackgroundScanTimer = 0;
      r = CFE_ES_RunAppTableScan(0, sst);
      S("esc_scan_core r=");
      D(r);
      S(" state=");
      D(arp->AppState);
      S(" pend=");
      D(sst->PendingAppStateChanges);
      S("\n");
      // Leave ES, and EVS's squelch, as the rest of the file expects to find them.
      CFE_EVS_Global.EVS_EventBurstMax = burst;
      es_ctx_init();
      MemSet(sst, 0, sizeof(CFE_ES_AppTableScanState_t));
    }
    // --- cfe_es_syslog.c: THE SYSTEM LOG ---------------------------------------------
    //
    // CFE_ES_WriteToSysLog appears in every module's error path and has been a six-line
    // recording stub in this file since EVS. The real thing is an 8 KiB RING BUFFER IN THE
    // RESET AREA, and its output IS the comparison: every "syslog ..." line already in the
    // transcript above goes through a stub, and these go through NASA's formatter, its
    // timestamp, its whitespace strip and its wrap logic.
    //
    // The reset area has to be aimed first -- the log lives there, not in CFE_ES_Global --
    // which is the one thing a caller must do before any of this works.
    
    {
      CFE_ES_SysLogReadBuffer_t rdbuf;
      I64 k;
      I32 src;
      MemSet(&es_reset_area, 0, sizeof(CFE_ES_ResetData_t));
      CFE_ES_Global.ResetDataPtr = &es_reset_area;
      CFE_ES_Global.ResetDataPtr->SystemLogMode = CFE_ES_LogMode_DISCARD;
      CFE_ES_SysLogClear_Unsync();
      S("sl_clear w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S(" e=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEndIdx);
      S(" n=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
      S("\n");
      // THE APPEND PATH, directly -- no timestamp, no formatting, just the ring. The copy is
      // MessageLen-1 bytes and the last byte is forced to a newline, so a string that ends in
      // one is unchanged and one that does not gets its last character REPLACED. Both are
      // below, and the second is the surprising one.
      src = CFE_ES_SysLogAppend_Unsync("first\n");
      S("sl_app1 rc=");
      D(src);
      S(" w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S(" n=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
      S("\n");
      src = CFE_ES_SysLogAppend_Unsync("no-newline");
      S("sl_app2 rc=");
      D(src);
      S(" w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S("\n");
      S("sl_bytes");
      for (k = 0; k < 17; k++) {
        S(" ");
        Hxb(CFE_ES_Global.ResetDataPtr->SystemLog[k]);
      }
      S("\n");
      // an empty message is not logged at all, and does not count
      src = CFE_ES_SysLogAppend_Unsync("");
      S("sl_empty rc=");
      D(src);
      S(" w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S(" n=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
      S("\n");
      // THE FORMATTER. This is the one whose output the transcript is really comparing: NASA's
      // timestamp, then the format, then ALL trailing whitespace stripped and exactly one
      // newline added -- whether or not the caller supplied one.
      src = CFE_ES_SysLogWrite_Unsync("plain %d %s\n", 42, "txt");
      S("sl_write rc=");
      D(src);
      S("\n");
      src = CFE_ES_SysLogWrite_Unsync("no newline %u", 7);
      S("sl_write_nonl rc=");
      D(src);
      S("\n");
      src = CFE_ES_SysLogWrite_Unsync("trailing   \t\n\n");
      S("sl_write_ws rc=");
      D(src);
      S("\n");
      // MODE: the two valid values and one that is not. DISCARD is the default, which is the
      // opposite of what a ring buffer usually does -- the FIRST messages after a fault are
      // the ones that explain it.
      src = CFE_ES_SysLogSetMode(CFE_ES_LogMode_OVERWRITE);
      S("sl_mode_ov rc=");
      D(src);
      S(" m=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogMode);
      S("\n");
      src = CFE_ES_SysLogSetMode(CFE_ES_LogMode_DISCARD);
      S("sl_mode_di rc=");
      D(src);
      S(" m=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogMode);
      S("\n");
      src = CFE_ES_SysLogSetMode(99);
      S("sl_mode_bad rc=");
      D(src);
      S(" m=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogMode);
      S("\n");
      // A SINGLE MESSAGE MAY NOT EXCEED HALF THE LOG, and that check comes before any wrap
      // logic -- so it reports TRUNCATED and still logs 4096 bytes.
      MemSet(es_big_msg, 'A', 4100);
      es_big_msg[4100] = 0;
      CFE_ES_SysLogClear_Unsync();
      src = CFE_ES_SysLogAppend_Unsync(es_big_msg);
      S("sl_huge rc=");
      D(src);
      S(" w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S("\n");
      // READ BACK: start a read, then pull blocks. The log has not wrapped, so this is NOT a
      // fragment and no tag is prepended.
      CFE_ES_SysLogReadStart_Unsync(&rdbuf);
      S("sl_rdstart frag=");
      D(rdbuf.IsFragment);
      S(" left=");
      D(rdbuf.SizeLeft);
      S(" last=");
      D(rdbuf.LastOffset);
      S(" end=");
      D(rdbuf.EndIdx);
      S("\n");
      CFE_ES_SysLogReadData(&rdbuf);
      S("sl_rd1 block=");
      D(rdbuf.BlockSize);
      S(" left=");
      D(rdbuf.SizeLeft);
      S(" first=");
      Ch(rdbuf.Data[0]);
      S("\n");
      CFE_ES_SysLogReadData(&rdbuf);
      S("sl_rd2 block=");
      D(rdbuf.BlockSize);
      S(" left=");
      D(rdbuf.SizeLeft);
      S("\n");
      // THE WRAP, and the FRAGMENT TAG it produces. In OVERWRITE mode a message that will not
      // fit resets WriteIdx to 0 and records the old tail in EndIdx -- so a reader starting at
      // WriteIdx is now mid-message, IsFragment is true, and CFE_ES_SysLogReadData prepends
      // the literal "<<FRAGMENT>> ". That string is in the dump file, which is why it is
      // checked here character for character.
      CFE_ES_SysLogClear_Unsync();
      CFE_ES_SysLogSetMode(CFE_ES_LogMode_OVERWRITE);
      for (k = 0; k < 3; k++)
        CFE_ES_SysLogAppend_Unsync(es_big_msg);
      S("sl_wrapped w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S(" e=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEndIdx);
      S(" n=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogEntryNum);
      S("\n");
      CFE_ES_SysLogReadStart_Unsync(&rdbuf);
      S("sl_frag_start frag=");
      D(rdbuf.IsFragment);
      S(" left=");
      D(rdbuf.SizeLeft);
      S(" last=");
      D(rdbuf.LastOffset);
      S(" end=");
      D(rdbuf.EndIdx);
      S("\n");
      CFE_ES_SysLogReadData(&rdbuf);
      S("sl_frag_tag ");
      for (k = 0; k < 13; k++)
        Ch(rdbuf.Data[k]);
      S("| block=");
      D(rdbuf.BlockSize);
      S(" frag=");
      D(rdbuf.IsFragment);
      S("\n");
      // DISCARD at the very end of the buffer: too little room even for a timestamp, so the
      // whole message goes and the return is FULL rather than TRUNCATED.
      CFE_ES_SysLogClear_Unsync();
      CFE_ES_SysLogSetMode(CFE_ES_LogMode_DISCARD);
      CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE - 4;
      src = CFE_ES_SysLogAppend_Unsync("too late\n");
      S("sl_full rc=");
      D(src);
      S("\n");
      CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE - 64;
      src = CFE_ES_SysLogAppend_Unsync(es_big_msg);
      S("sl_trunc rc=");
      D(src);
      S(" w=");
      D(CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx);
      S("\n");
      // THE DUMP, to the simulated filesystem, and the lock counters with it: exactly ONE
      // take/give pair however many blocks get written, because NASA locks only for the first
      // read and says at length why.
      CFE_ES_SysLogClear_Unsync();
      CFE_ES_SysLogSetMode(CFE_ES_LogMode_DISCARD);
      CFE_ES_SysLogWrite_Unsync("dumped entry %d\n", 1);
      CFE_ES_Global.TaskData.HkPacket.Payload.SysLogEntries = CFE_ES_Global.ResetDataPtr->SystemLogEntryNum;
      es_lock_takes = 0;
      es_lock_gives = 0;
      fs_len = 0;
      fs_pos = 0;
      src = CFE_ES_SysLogDump("/ram/syslog.dat");
      S("sl_dump rc=");
      D(src);
      S(" takes=");
      D(es_lock_takes);
      S(" gives=");
      D(es_lock_gives);
      S(" len=");
      D(fs_len);
      S("\n");
      // and the two failure paths: a create that fails, and a write that fails
      fs_open_fail = 1;
      src = CFE_ES_SysLogDump("/ram/syslog.dat");
      S("sl_dump_nocreate rc=");
      D(src);
      S("\n");
      fs_open_fail = 0;
      fs_len = 0;
      fs_pos = 0;
      fs_wr_left = 8;
      // THE WITNESS MOVED. es_bytecnt_errs counted a stub; CFE_ES_FileWriteByteCntErr is real
      // now (cfe_es_task.c) and raises CFE_ES_FILEWRITE_ERR_EID instead, so what says the
      // short-write path fired is the event -- which is in the transcript above this line --
      // and the count of EVS output lines it produced.
      evs_printf_lines = 0;
      src = CFE_ES_SysLogDump("/ram/syslog.dat");
      S("sl_dump_wrfail rc=");
      D(src);
      S(" evs=");
      D(evs_printf_lines);
      S("\n");
      fs_wr_left = -1;
    }
    // --- cfe_tbl_handlelink.c -------------------------------------------------------
    // The first of table services' fifteen sources to be gated, and the only one that never
    // touches CFE_TBL_Global: two functions over a two-field list node. The node is filled with
    // 0xAB first, because CFE_TBL_HandleLinkInit's whole job is to write BOTH fields and a
    // zeroed node would not tell them apart from an untouched one.
    
    {
      CFE_TBL_HandleLink_t link;
      CFE_TBL_RegistryRec_t *deep;
      MemSet(&link, 0xAB, sizeof(CFE_TBL_HandleLink_t));
      CFE_TBL_HandleLinkInit(&link);
      S("tbl_linkinit prev=");
      D(CFE_ResourceId_ToInteger(link.Prev));
      S(" next=");
      D(CFE_ResourceId_ToInteger(link.Next));
      S(" attached=");
      D(CFE_TBL_HandleLinkIsAttached(&link));
      S("\n");
      link.Next = CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 3);
      S("tbl_linkattach next=");
      D(CFE_ResourceId_ToInteger(link.Next));
      S(" attached=");
      D(CFE_TBL_HandleLinkIsAttached(&link));
      S("\n");
      // PREV ALONE IS NOT ATTACHMENT. CFE_TBL_HandleLinkIsAttached reads only Next, which is
      // the asymmetry that makes the list walkable in one direction from any node and is easy
      // to get wrong by symmetry when translating.
      CFE_TBL_HandleLinkInit(&link);
      link.Prev = CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 4);
      S("tbl_linkprevonly prev=");
      D(CFE_ResourceId_ToInteger(link.Prev));
      S(" attached=");
      D(CFE_TBL_HandleLinkIsAttached(&link));
      S("\n");
      // AND THROUGH THE DEEPEST REGISTRY RECORD, 61 KB into the global: this is where a table's
      // access list actually lives, and `Registry[MAX - 1]` is the address form that resolved
      // 117 KB before the object until the subscript fix.
      deep = &CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1];
      MemSet(&deep->AccessList, 0xCD, sizeof(CFE_TBL_HandleLink_t));
      CFE_TBL_HandleLinkInit(&deep->AccessList);
      S("tbl_linkdeep attached=");
      D(CFE_TBL_HandleLinkIsAttached(&deep->AccessList));
      S(" off=");
      D ((U8 *) & deep->AccessList - (U8 *) & CFE_TBL_Global);
      S("\n");
    }
    TblDumpCtlExercise();
    TblAccDescExercise();
    // --- tbl: CFE_TBL_Global IS 592,056 BYTES AND EVERY OFFSET IN IT HAS TO BE REACHABLE
    // ------------------------------------------------------------------------------------
    // This is not a translation of anything. It is the test that has to pass BEFORE the 7,780
    // lines of table services are worth translating, because all of them reach through this one
    // object and the deepest member sits at offset 591,736.
    //
    // A RISC-V load or store carries a 12-bit signed immediate, so anything past 2,047 bytes
    // from the base register needs the address built up first -- and this port has a recorded
    // codegen bug of exactly that shape (an indexed store into a large local array emitted a
    // wild store at deep offsets). It was fixed for LOCALS and has never been exercised at
    // 590 KB on a global. If it is wrong here, every table function built on top writes to the
    // wrong place and the transcript blames the function.
    //
    // So: the offsets are printed as pointer differences, which is the COMPILER'S OWN
    // arithmetic, and then a sentinel is written and read back through each one. The C half
    // computes the same differences from the same header, so a mismatch here is a codegen
    // failure and not a layout disagreement -- check_padding already settled layout.
    S("tbl_off reg=");
    D ((U8 *) & CFE_TBL_Global.Registry[0] - (U8 *) & CFE_TBL_Global);
    S(" crit=");
    D ((U8 *) & CFE_TBL_Global.CritReg[0] - (U8 *) & CFE_TBL_Global);
    S(" buf=");
    D ((U8 *) & CFE_TBL_Global.Buf - (U8 *) & CFE_TBL_Global);
    S(" val=");
    D ((U8 *) & CFE_TBL_Global.ValidationResults[0] - (U8 *) & CFE_TBL_Global);
    S(" dmp=");
    D ((U8 *) & CFE_TBL_Global.DumpControlBlocks[0] - (U8 *) & CFE_TBL_Global);
    S(" rds=");
    D ((U8 *) & CFE_TBL_Global.RegDumpState - (U8 *) & CFE_TBL_Global);
    S(" last=");
    D ((U8 *) & CFE_TBL_Global.LastDumpCtrlBlockId - (U8 *) & CFE_TBL_Global);
    S(" whole=");
    D(sizeof(CFE_TBL_Global));
    S("\n");
    // the LAST element of every array, which is the deepest reach in each case
    S("tbl_off_end reg=");
    D ((U8 *) & CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1] - (U8 *) & CFE_TBL_Global);
    S(" crit=");
    D ((U8 *) & CFE_TBL_Global.CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES - 1] - (U8 *) & CFE_TBL_Global);
    S(" val=");
    D ((U8 *) & CFE_TBL_Global.ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1] - (U8 *) & CFE_TBL_Global);
    S(" dmp=");
    D ((U8 *) & CFE_TBL_Global.DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1] - (U8 *) & CFE_TBL_Global);
    S(" pool=");
    D ((U8 *) & CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 1] - (U8 *) & CFE_TBL_Global);
    S("\n");
    // AND NOW WRITE THROUGH EVERY ONE OF THEM AND READ IT BACK. A store that lands at the wrong
    // offset shows up two ways: the value read back is wrong, or a NEIGHBOUR changed. Both are
    // checked -- the neighbour sum is over the members that follow the ones written, and it has
    // to stay zero.
    MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    CFE_TBL_Global.Registry[0].RegId = 0x11111111;
    CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1].RegId = 0x22222222;
    CFE_TBL_Global.CritReg[0].CDSHandle = 0x33333333;
    CFE_TBL_Global.CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES - 1].CDSHandle = 0x44444444;
    CFE_TBL_Global.Buf.Partition.Data[0] = 0x55;
    CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 1] = 0x66;
    CFE_TBL_Global.ValidationResults[0].CrcOfTable = 0x77777777;
    CFE_TBL_Global.ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1].CrcOfTable = 0x88888888;
    CFE_TBL_Global.DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1].TableName[0] = 'Z';
    CFE_TBL_Global.RegDumpState.FileExisted = TRUE;
    CFE_TBL_Global.LastHandle = CFE_ResourceId_FromInteger(0x99999999);
    CFE_TBL_Global.LastDumpCtrlBlockId = CFE_ResourceId_FromInteger(0xAAAAAAAA);
    S("tbl_deep ");
    Hx8(CFE_TBL_Global.Registry[0].RegId);
    S(" ");
    Hx8(CFE_TBL_Global.Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1].RegId);
    S(" ");
    Hx8(CFE_TBL_Global.CritReg[0].CDSHandle);
    S(" ");
    Hx8(CFE_TBL_Global.CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES - 1].CDSHandle);
    S(" ");
    Hx2b(CFE_TBL_Global.Buf.Partition.Data[0]);
    S(" ");
    Hx2b(CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 1]);
    S(" ");
    Hx8(CFE_TBL_Global.ValidationResults[0].CrcOfTable);
    S(" ");
    Hx8(CFE_TBL_Global.ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1].CrcOfTable);
    S(" ");
    
    {
      U8 one[2];
      one[0] = CFE_TBL_Global.DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1].TableName[0];
      one[1] = 0;
      S(one);
    }
    S(" ");
    D(CFE_TBL_Global.RegDumpState.FileExisted);
    S(" ");
    Hx8(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastHandle));
    S(" ");
    Hx8(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastDumpCtrlBlockId));
    S("\n");
    // the neighbours: every one of these is adjacent to something written above and must still
    // be zero. Registry[1] follows Registry[0], CritReg[1] follows CritReg[0],
    // ValidationResults[1] follows ValidationResults[0], and LastRegId, LastLoadBuffId and
    // LastValidationResultId sit between LastHandle and LastDumpCtrlBlockId.
    S("tbl_neigh ");
    D(CFE_TBL_Global.Registry[1].RegId + CFE_TBL_Global.CritReg[1].CDSHandle + CFE_TBL_Global.ValidationResults[1].CrcOfTable + CFE_ResourceId_ToInteger(CFE_TBL_Global.LastRegId) + CFE_ResourceId_ToInteger(CFE_TBL_Global.LastLoadBuffId) + CFE_ResourceId_ToInteger(CFE_TBL_Global.LastValidationResultId) + CFE_TBL_Global.Buf.Partition.Data[1] + CFE_TBL_Global.Buf.Partition.Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES - 2]);
    S("\n");
    MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
    // --- cfe_time_objtab.c ------------------------------------------------------------
    // --- cfe_tbl_objtab.c ----------------------------------------------------------
    // tbl's entry in the core module object table: the whole contract between a core service
    // and cFE's startup, which walks the table twice -- EarlyInit for every module, then
    // TaskMain for every module. TBL is the ORDINARY shape, with all three hooks present; ES
    // is the one that is odd, having no Cleanup.
    S("tbl_objtab ");
    S(CFE_TBL_ModuleEntry.Name);
    S(" ");
    D(CFE_TBL_ModuleEntry.EarlyInit == NULL);
    S(" ");
    D(CFE_TBL_ModuleEntry.TaskMain == NULL);
    S(" ");
    D(CFE_TBL_ModuleEntry.AppCleanupCb == NULL);
    S(" ");
    D(CFE_TBL_ModuleEntry.Priority);
    S(" ");
    D(CFE_TBL_ModuleEntry.StackSize);
    S("\n");
    // and the three are DISTINCT addresses, which is what a positional initialiser can
    // silently get wrong where a designated one cannot
    S("tbl_objtab_distinct ");
    D(CFE_TBL_ModuleEntry.EarlyInit != CFE_TBL_ModuleEntry.TaskMain && CFE_TBL_ModuleEntry.TaskMain != CFE_TBL_ModuleEntry.AppCleanupCb);
    S("\n");
    S("tim_objtab ");
    S(CFE_TIME_ModuleEntry.Name);
    S(" ");
    D(CFE_TIME_ModuleEntry.EarlyInit == NULL);
    S(" ");
    D(CFE_TIME_ModuleEntry.TaskMain == NULL);
    S(" ");
    D(CFE_TIME_ModuleEntry.AppCleanupCb == NULL);
    S(" ");
    D(CFE_TIME_ModuleEntry.Priority);
    S(" ");
    D(CFE_TIME_ModuleEntry.StackSize);
    S("\n");
  }
  return 0;
}
