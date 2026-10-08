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

// Exactly two upper-case hex digits, matching the oracle's "%02X". Used to dump dwell bytes,
// where the POINT is to see the bytes that were NOT written: a store that is too wide shows up
// as a missing poison byte, and only a fixed-width unsigned rendering makes that readable.
U0 H2(I64 v)
{
  U8 two[3];
  U8 *hx = "0123456789ABCDEF";
  two[0] = hx[(v >> 4) & 15];
  two[1] = hx[v & 15];
  two[2] = 0;
  S(two);
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
I64 fs_noexist;
// make a READ-ONLY open fail: the file is not there
// fs_wr_left is the number of bytes the file will still accept, not a per-call cap. A per-call
// cap of 64 looked like it would make a record write fail and did not: the header write is 64
// and every record is 10, so each individual write still fit and the run reported COMPLETE.
I64 fs_wr_left;
// < 0 = unlimited
I64 fs_mut_create, fs_mut_take, fs_mut_give;
// Steer the three mutex calls; see the note in the C half. Without these, cfe_fs_priv.c's
// three syslog lines are unreachable -- including the only one that formats three arguments.
I64 fs_mut_create_rc, fs_mut_take_rc, fs_mut_give_rc;
// `fs_noexist` SAYS "THE FILE IS NOT THERE", WHICH `fs_open_fail` COULD NOT. This stub had one
// knob for both ideas, and cfe_tbl_dump.c is the first code in the port whose behaviour turns on
// the difference: CFE_TBL_WriteSnapshotToFile opens the dump file READ-ONLY purely to decide
// between CFE_TBL_OVERWRITE_DUMP_INF_EID and CFE_TBL_WRITE_DUMP_INF_EID, and then opens it for
// WRITING. With one knob the read-only open always succeeded, so the file always "existed" and
// the first-write event id was UNREACHABLE -- a branch no transcript could enter. Keyed on
// access_mode so it cannot affect any existing line: every other caller of this stub writes.
I32 OS_OpenCreate(U32 *filedes, U8 *path, I32 flags, I32 access_mode)
{
  if (fs_open_fail)
    return -1;
  // OS_ERROR
  if (fs_noexist && access_mode == OS_READ_ONLY)
    return -1;
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

// MAKE OS_read FAIL. mm_utils.c's MM_ComputeCRCFromFile has a branch that runs only on a
// NEGATIVE return -- it hands the error back INSTEAD of writing the caller's CRC -- and nothing
// in the port had ever made a read fail, so that branch was unreachable. Defaults to 0, which is
// "no change", so no existing transcript line can see it.
I32 fs_read_rc;

I32 OS_read(U32 filedes, U8 *buffer, I64 nbytes)
{
  I64 n = nbytes;
  if (fs_read_rc != 0)
    return fs_read_rc;
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
// A DISTINCT ID PER CREATE, and the reason is CFE_TBL_EarlyInit. It creates TWO mutexes and
// stores them in two different fields of CFE_TBL_Global; while this stub handed back the same
// id for both, a translation that wrote the registry mutex into WorkBufMutex -- or stored one
// twice -- produced exactly the transcript a correct one does. The ids start well above
// ES_SHARED_MUTEX_ID (0x1E5), which the startup sequence plants directly rather than creating,
// so nothing that keys on that constant is affected.
I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options)
{
  ++fs_mut_create;
  *sem_id = 0x3000 + fs_mut_create;
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

// THE SIZE OS_stat REPORTS, which arrived with MM: mm_load.c's MM_VerifyLoadFileSize is the
// first thing in the port to READ the stat buffer rather than only the return code, and it
// compares the size against the file header's claim plus both headers. The stub ignored
// `filestats` entirely before, which would have made every size check pass on a zero.
I64 es_stat_size;

I32 OS_stat(U8 *path, os_fstat_t *filestats)
{
  ++es_stats;
  if (filestats != NULL)
    filestats->FileSize = es_stat_size;
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
// WHERE A MODULE'S CODE SEGMENT IS, and how big. The defaults are the fixed values this driver
// has always reported -- set in main(), because HolyC zeroes globals -- so every existing
// esa_appinfo_addr line is unchanged. CS's app checksum CRCs these bytes, and 0x11110000 is not
// memory either half may read; CS's exercise points them at a driver-owned buffer and puts them
// back.
U64 es_modinfo_code_addr; // cpuaddr
I64 es_modinfo_code_size;
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
    module_prop->addr.code_address = es_modinfo_code_addr;
    module_prop->addr.code_size = es_modinfo_code_size;
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

// THE OS KERNEL'S TEXT SEGMENT -- the sibling of CFE_PSP_GetCFETextSegmentInfo above, and the one
// new simulated PSP function CS needs. On flight hardware it reports where the operating system's
// code was linked; here it reports a FIXED, SHORT STRING for exactly the reason its sibling does,
// written out again because it is the reason that matters: CS CRCs these bytes directly, so
// pointing a checksum at real kernel text would make the number depend on the COMPILER -- and a
// host process and a QEMU guest do not share one.
//
// NASA'S OWN PSP RETURNS CFE_PSP_ERROR_NOT_IMPLEMENTED on several platforms, which is why
// CS_InitSegments has a whole arm for it, and es_kernelseg_rc is how that arm is driven.
I64 es_kernelseg;
I32 es_kernelseg_rc;

I32 CFE_PSP_GetKernelTextSegmentInfo(U64 *PtrToKernelSegment, U32 *SizeOfKernelSegment)
{
  ++es_kernelseg;
  *PtrToKernelSegment = "OSkernel";
  *SizeOfKernelSegment = 8;
  return es_kernelseg_rc;
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
#include "/Kernel/Cfs/cfe/cfe_tbl_loadbuff.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_regrec.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_valresult.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_passthru_codec.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_transaction.HC"
// Backing memory for the load buffers the tbl exercise hands out, plus the four event ids it
// walks. File scope because of limit 22 and because HolyC has no file-scope aggregate
// initialiser; the C half keeps them at file scope too so the two read the same.
U8 tbl_probe_mem[64];
U8 tbl_probe_mem2[64];
U16 tbl_actv_ids[4];
U16 tbl_val_ids[5];
CFE_TBL_TxnEventContext_t tbl_txctx;
// a validation callback that exists only to be non-NULL: what SetupValidationRequest branches
// on is whether the pointer is set, never what it does.
// A STEERABLE VALIDATION CALLBACK. It began as a pointer that exists only to be non-NULL --
// CFE_TBL_SetupValidationRequest branches on whether it is set, never on what it does -- and
// `tbl_val_rc` was added for cfe_tbl_load.c, where WHAT IT RETURNS decides between three
// outcomes: zero is a pass, a NEGATIVE value raises CFE_TBL_VALIDATION_ERR_EID and zeroes the
// buffer, and a POSITIVE value raises a DIFFERENT event (CFE_TBL_LOAD_VAL_ERR_EID) and becomes
// CFE_STATUS_VALIDATION_FAILURE. Without the knob, two of those three are unreachable.
I32 tbl_val_rc;
I32 TblValStub(U8 *TblPtr)
{
  no_warn TblPtr;
  return tbl_val_rc;
}
// --- FOUR STAND-INS FOR THE loadbuff+regrec PAIR -------------------------------------------
// Named by tools/cfs/module_deps.py --cuts: two from cfe_tbl_internal.c and two from
// cfe_tbl_transaction.c, both still inside tbl's call cycle.
//
// THE FIRST TWO STAND-INS ARE GONE: CFE_TBL_ForeachAccessDescriptor and
// CFE_TBL_AcquireGlobalLoadBuff both live in cfe_tbl_internal.c, gated below, so the real
// ones are compiled in now. The `tbl_foreach_visits` counter went with them -- a witness that
// only a stub could keep -- and what replaces it is in the exercise: the list walk is now
// observed through NASA's own CFE_TBL_CountAccessDescHelper.
// CFE_TBL_TxnAddEvent and CFE_TBL_SendTransactionEvents WERE STAND-INS HERE and are real now
// -- they live in cfe_tbl_transaction.c, gated above. Their deletion is the whole reason the
// `tbl_actvsend`/`tbl_vrsend` assertions changed shape: they counted a stub, and what arrives
// instead is the event text itself, which is strictly better. Recorded trap: the witness moves
// when the stub goes.
//
// ALL FOUR cfe_tbl_registry.c STAND-INS ARE GONE -- CFE_TBL_TxnFindRegByName, the counted
// lock pair, and CFE_TBL_TxnRemoveAccessLink. The source is gated below, so the counted lock
// now delegates to the REAL CFE_TBL_LockRegistry (which this driver's mutex still counts, so
// the transcript witnesses every take and give), and RemoveAccessLink does the list surgery
// it only pretended to do. `tbl_removelink_calls` went with it -- a counter is all a stub can
// witness -- and what replaces it is the effect: a table whose last accessor leaves is
// returned to the pool, which the exercise reads from the registry record itself.
#include "/Kernel/Cfs/cfe/cfe_tbl_accdesc.HC"
// --- cfe_tbl_internal.c ---------------------------------------------------------
// Four unrelated concerns in one file: startup, the shared memory pool, the access-descriptor
// list, and the critical-table CDS. It goes HERE, after cfe_tbl_accdesc.HC, because that is
// the point at which all but one of its seventy-two external calls are already defined.
#include "/Kernel/Cfs/cfe/cfe_tbl_internal.HC"
// --- cfe_tbl_registry.c ---------------------------------------------------------
// The eleven transaction steps that reach into CFE_TBL_Global.Registry. It goes directly
// after internal.c because it calls six of that source's functions -- the counted lock pair
// delegates to CFE_TBL_LockRegistry/UnlockRegistry, and RemoveAccessLink needs
// HandleListRemoveLink, DiscardWorkingBuffer and DeallocateAllBuffers. Gating it needs no new
// stand-ins at all: of its 43 external calls, 37 were already translated and the other 6 are
// id macros that collapse onto CFE_ResourceId_IsDefined / _Equal / the identity.
#include "/Kernel/Cfs/cfe/cfe_tbl_registry.HC"
// --- cfe_tbl_task.c -------------------------------------------------------------
// The app entry point, its five-step initialisation, and the data init that seeds all five
// resource-id spaces. It goes after registry.c because CFE_TBL_InitData is the function the
// rest of tbl's allocators depend on, and because CFE_TBL_TaskMain is the last of the three
// object-table hooks.
#include "/Kernel/Cfs/cfe/cfe_tbl_task.HC"
// --- cfe_tbl_dump.c -------------------------------------------------------------
// The three-phase dump: allocate a control block, snapshot the buffer, and write the file from
// the background task. It goes last of the tbl sources gated so far because it calls into
// internal.c (AcquireGlobalLoadBuff, SendNotificationMsg), the codec, dumpctl, regrec,
// loadbuff and the transaction -- all of which are above it. Zero stand-ins.
#include "/Kernel/Cfs/cfe/cfe_tbl_dump.HC"
// --- cfe_tbl_load.c -------------------------------------------------------------
// The most guarded operation in Table Services: open, std header, table header, loadability,
// content, metadata -- and every step can refuse. It goes after dump.c because both share the
// CombinedFileHdr_t type and the codec, and because CFE_TBL_LoadFinish calls
// CFE_TBL_UpdateInternal from internal.c. Zero stand-ins.
#include "/Kernel/Cfs/cfe/cfe_tbl_load.HC"
// --- cfe_tbl_api.c --------------------------------------------------------------
// THE PUBLIC API. Nineteen functions an application actually calls, every one of them a
// transaction whose first line carries the access check. It goes last of tbl's sources because
// it calls into all of them -- internal, registry, accdesc, loadbuff, regrec, dump and load.
// Zero stand-ins.
#include "/Kernel/Cfs/cfe/cfe_tbl_api.HC"
// --- cfe_tbl_task_cmds.c --------------------------------------------------------
// THE GROUND COMMANDS: ten handlers plus the housekeeping packer, the registry packer and the
// two background-dump callbacks. Last of tbl's sources because it calls into every other one,
// including the public API's own helpers. Zero stand-ins.
#include "/Kernel/Cfs/cfe/cfe_tbl_task_cmds.HC"
// CFE_TBL_EarlyInit, CFE_TBL_CleanUpApp AND CFE_TBL_TaskMain WERE STUBS HERE. All three are
// real now, so every hook cfe_tbl_objtab.c names is the function it claims to be -- the first
// module whose object table is complete.
//
// AND THE LAST STAND-IN IS GONE TOO: CFE_TBL_TaskPipe lives in cfe_tbl_dispatch.c, gated
// below, so tbl has NO stand-ins left anywhere in this driver. `tbl_taskpipe_calls` went with
// it -- a counter is all a stub can witness -- and what replaces it is the dispatcher's own
// three-way error plus the handlers it actually calls.
//
// --- cfe_tbl_dispatch.c ---------------------------------------------------------
// The command dispatcher: a twelve-row table of function pointers, a three-way error, and the
// length check that means no handler ever sees a message of the wrong size. It goes here, after
// cfe_tbl_task_cmds.HC, because its table names all ten handlers.
#include "/Kernel/Cfs/cfe/cfe_tbl_dispatch.HC"
#include "/Kernel/Cfs/cfe/cfe_tbl_objtab.HC"

// --- MD, THE FIRST cFS APP ------------------------------------------------------------------
// An app sees cFE only through the public API, so MD comes last: everything it calls is
// already above it. module_deps.py --fresh says MD is fully acyclic in this configuration and
// names md_utils.c as the leaf, so it is gated first and needs no stand-ins.
//
// OS_SymbolLookup IS A SEAM HERE, not a translation -- see the stub below and the matching one
// in the oracle. This driver's scope is cFE, and the cFE translation sees OSAL only through
// its API; osapi-module.c is translated and gated by run_osal_xlat_smoke.sh.
#include "/Kernel/Cfs/md/md_msg.HC"
#include "/Kernel/Cfs/md/md_global.HC"
// CFE_PSP_INVALID_MEM_ADDR is NASA's CFE_PSP_STATUS_C(-21), from vendor/PSP's cfe_psp_error.h.
// It is used only by the exercise below -- no translated function mentions it -- so it is a
// driver constant, defined where the driver's other PSP stubs are.
#define CFE_PSP_INVALID_MEM_ADDR -21
// THE SIMULATED DWELL WINDOW. The hardware MD needs and this port does not have, supplied
// through the PSP exactly as the other 22 CFE_PSP_* functions are, and mirroring the oracle's
// copy line for line. See the long note on the C side for why it is a WINDOW of literal
// addresses rather than a real buffer's address: NASA's own event text prints a resolved
// cpuaddr with %08X, and a host pointer can never match a guest one.
//
// ADDITIVE: CFE_PSP_MemValidateRange keeps its settable return code untouched, because ES's and
// TBL's pool paths already drive it and the existing transcript lines are the control.
//
// The bytes are assembled explicitly, little end first, rather than by casting the buffer --
// MD_GetDwellData copies the low NumBytes of the value into the dwell packet, so the packet's
// contents depend on that choice.
#define MD_SIM_WINDOW_BASE 0x00100000
#define MD_SIM_WINDOW_SIZE 256
U8 md_sim_mem[MD_SIM_WINDOW_SIZE];
I64 md_sim_reads;
I64 md_sim_i;

U0 md_sim_fill()
{
  for (md_sim_i = 0; md_sim_i < MD_SIM_WINDOW_SIZE; md_sim_i++) {
    md_sim_mem[md_sim_i] = 0x40 + md_sim_i; // ascending and distinguishable
  }
}

Bool md_sim_in(U64 a, I64 width)
{
  return a >= MD_SIM_WINDOW_BASE && (a - MD_SIM_WINDOW_BASE) + width <= MD_SIM_WINDOW_SIZE;
}

I32 CFE_PSP_MemRead8(U64 MemoryAddress, U8 *ByteValue)
{
  ++md_sim_reads;
  if (!md_sim_in(MemoryAddress, 1))
    return CFE_PSP_INVALID_MEM_ADDR;
  *ByteValue = md_sim_mem[MemoryAddress - MD_SIM_WINDOW_BASE];
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_MemRead16(U64 MemoryAddress, U16 *uint16Value)
{
  I64 o = MemoryAddress - MD_SIM_WINDOW_BASE;
  ++md_sim_reads;
  if (!md_sim_in(MemoryAddress, 2))
    return CFE_PSP_INVALID_MEM_ADDR;
  *uint16Value = md_sim_mem[o] | (md_sim_mem[o + 1] << 8);
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_MemRead32(U64 MemoryAddress, U32 *uint32Value)
{
  I64 o = MemoryAddress - MD_SIM_WINDOW_BASE;
  ++md_sim_reads;
  if (!md_sim_in(MemoryAddress, 4))
    return CFE_PSP_INVALID_MEM_ADDR;
  *uint32Value = md_sim_mem[o] | (md_sim_mem[o + 1] << 8) | (md_sim_mem[o + 2] << 16) |
                 (md_sim_mem[o + 3] << 24);
  return CFE_PSP_SUCCESS;
}

// --- THE WRITE HALF OF THE SAME WINDOW, which arrived with MM ---------------------------------
// MD only ever READ memory. MM pokes it, fills it and loads it from a file, so the simulated
// window gains three stores -- same base, same size, same bytes. The name stays MD_SIM_* because
// it is literally the same simulated hardware, and renaming it would touch MD's lines for
// nothing.
//
// md_sim_writes COUNTS STORES, and it is the witness that distinguishes "the fill loop ran" from
// "the fill loop returned success": MM's fill writes one byte at a time and reports a byte count
// it computes from the segment arithmetic, not from the stores, so a loop that never stored would
// still report the right number.
//
// md_sim_wfail_at MAKES ONE STORE FAIL, by offset, which is the only way into MM's
// MM_PSP_WRITE_ERR_EID branch -- and that branch stops the segment loop mid-way, which is also
// the only way to reach the short-load arm that turns a partial write into CFE_PSP_ERROR. -1
// means "never", so no existing line can see it.
I64 md_sim_writes;
I64 md_sim_wfail_at = -1;

Bool md_sim_wfail(U64 a)
{
  return md_sim_wfail_at >= 0 && (a - MD_SIM_WINDOW_BASE)(I64) == md_sim_wfail_at;
}

I32 CFE_PSP_MemWrite8(U64 MemoryAddress, U8 ByteValue)
{
  ++md_sim_writes;
  if (!md_sim_in(MemoryAddress, 1) || md_sim_wfail(MemoryAddress))
    return CFE_PSP_INVALID_MEM_ADDR;
  md_sim_mem[MemoryAddress - MD_SIM_WINDOW_BASE] = ByteValue;
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_MemWrite16(U64 MemoryAddress, U16 uint16Value)
{
  I64 o = MemoryAddress - MD_SIM_WINDOW_BASE;
  ++md_sim_writes;
  if (!md_sim_in(MemoryAddress, 2) || md_sim_wfail(MemoryAddress))
    return CFE_PSP_INVALID_MEM_ADDR;
  md_sim_mem[o] = uint16Value & 0xFF;
  md_sim_mem[o + 1] = (uint16Value >> 8) & 0xFF;
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_MemWrite32(U64 MemoryAddress, U32 uint32Value)
{
  I64 o = MemoryAddress - MD_SIM_WINDOW_BASE;
  ++md_sim_writes;
  if (!md_sim_in(MemoryAddress, 4) || md_sim_wfail(MemoryAddress))
    return CFE_PSP_INVALID_MEM_ADDR;
  md_sim_mem[o] = uint32Value & 0xFF;
  md_sim_mem[o + 1] = (uint32Value >> 8) & 0xFF;
  md_sim_mem[o + 2] = (uint32Value >> 16) & 0xFF;
  md_sim_mem[o + 3] = (uint32Value >> 24) & 0xFF;
  return CFE_PSP_SUCCESS;
}


// --- A SECOND SIMULATED REGION: EEPROM -------------------------------------------------------
// MM pokes EEPROM through CFE_PSP_EepromWrite*, not CFE_PSP_MemWrite*, because on real hardware
// the two are different devices: EEPROM has to be unlocked, programmed and waited on, which is
// why MM wraps only the EEPROM paths in performance-log stamps. So it gets its own window rather
// than sharing the RAM one -- a shared array would let a poke to EEPROM be satisfied by the RAM
// path and nothing would notice.
//
// Its base is deliberately FAR from MD_SIM_WINDOW_BASE so that an address meant for one and sent
// to the other falls outside and is refused rather than quietly working.
#define MM_EEP_WINDOW_BASE 0x00200000
#define MM_EEP_WINDOW_SIZE 256
U8 mm_eep_mem[MM_EEP_WINDOW_SIZE];
I64 mm_eep_writes;
I64 mm_eep_wfail_at = -1;

Bool mm_eep_in(U64 a, I64 width)
{
  return a >= MM_EEP_WINDOW_BASE && (a - MM_EEP_WINDOW_BASE)(I64) + width <= MM_EEP_WINDOW_SIZE;
}

Bool mm_eep_wfail(U64 a)
{
  return mm_eep_wfail_at >= 0 && (a - MM_EEP_WINDOW_BASE)(I64) == mm_eep_wfail_at;
}

I32 CFE_PSP_EepromWrite8(U64 MemoryAddress, U8 ByteValue)
{
  ++mm_eep_writes;
  if (!mm_eep_in(MemoryAddress, 1) || mm_eep_wfail(MemoryAddress))
    return CFE_PSP_INVALID_MEM_ADDR;
  mm_eep_mem[MemoryAddress - MM_EEP_WINDOW_BASE] = ByteValue;
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_EepromWrite16(U64 MemoryAddress, U16 uint16Value)
{
  I64 o = MemoryAddress - MM_EEP_WINDOW_BASE;
  ++mm_eep_writes;
  if (!mm_eep_in(MemoryAddress, 2) || mm_eep_wfail(MemoryAddress))
    return CFE_PSP_INVALID_MEM_ADDR;
  mm_eep_mem[o] = uint16Value & 0xFF;
  mm_eep_mem[o + 1] = (uint16Value >> 8) & 0xFF;
  return CFE_PSP_SUCCESS;
}

I32 CFE_PSP_EepromWrite32(U64 MemoryAddress, U32 uint32Value)
{
  I64 o = MemoryAddress - MM_EEP_WINDOW_BASE;
  ++mm_eep_writes;
  if (!mm_eep_in(MemoryAddress, 4) || mm_eep_wfail(MemoryAddress))
    return CFE_PSP_INVALID_MEM_ADDR;
  mm_eep_mem[o] = uint32Value & 0xFF;
  mm_eep_mem[o + 1] = (uint32Value >> 8) & 0xFF;
  mm_eep_mem[o + 2] = (uint32Value >> 16) & 0xFF;
  mm_eep_mem[o + 3] = (uint32Value >> 24) & 0xFF;
  return CFE_PSP_SUCCESS;
}


// --- THE EEPROM BANK LOCK ---------------------------------------------------------------------
// On real hardware CFE_PSP_EepromWriteEnable drives a write-protect line and the bank number
// selects which part. Nothing in MM reads a bank's state back, so unlike the EepromWrite* trio
// these need no simulated region -- only a settable return code and a count, which is what makes
// mm_cmds.c's two commands drivable at all.
I64 mm_eep_locks;
I32 mm_eep_lock_rc = CFE_PSP_SUCCESS;
U32 mm_eep_last_bank;

I32 CFE_PSP_EepromWriteEnable(U32 Bank)
{
  ++mm_eep_locks;
  mm_eep_last_bank = Bank;
  return mm_eep_lock_rc;
}

I32 CFE_PSP_EepromWriteDisable(U32 Bank)
{
  ++mm_eep_locks;
  mm_eep_last_bank = Bank;
  return mm_eep_lock_rc;
}

// OS_SymbolTableDump writes the loader's whole symbol table to a file. There is no loader and no
// symbol table in this port -- OS_SymbolLookup is already a driver stub -- so this records the
// request and returns a settable code. The SIZE LIMIT is part of the record because it is
// MM_INTERNAL_MAX_DUMP_FILE_DATA_SYMTBL, a constant no other line in MM reads.
I64 mm_symdumps;
I32 mm_symdump_rc = OS_SUCCESS;
I64 mm_symdump_limit;

I32 OS_SymbolTableDump(U8 *filename, I64 size_limit)
{
  ++mm_symdumps;
  mm_symdump_limit = size_limit;
  S("os_symdump ");
  S(filename);
  S(" limit=");
  D(mm_symdump_limit);
  S(" rc=");
  D(mm_symdump_rc);
  S("\n");
  return mm_symdump_rc;
}

I32 md_sym_rc;
U64 md_sym_addr;
I32 OS_SymbolLookup(U64 *SymbolAddress, U8 *SymbolName)
{
  if (md_sym_rc == OS_SUCCESS)
    *SymbolAddress = md_sym_addr;
  return md_sym_rc;
}
#include "/Kernel/Cfs/md/md_utils.HC"
#include "/Kernel/Cfs/md/md_dwell_pkt.HC"
#include "/Kernel/Cfs/md/md_dwell_tbl.HC"
#include "/Kernel/Cfs/md/md_cmds.HC"
// md_app.HC and md_dispatch.HC are a CYCLE and go in together: MD_AppMain calls MD_TaskPipe
// from the second, and the second's switch calls MD_SendHkCmd from the first. md_app.HC comes
// first and forward-declares MD_TaskPipe, which is one declaration instead of three.
#include "/Kernel/Cfs/md/md_app.HC"
#include "/Kernel/Cfs/md/md_dispatch.HC"
// MEMORY MANAGER, the second app. Its four files are ACYCLIC in this order: the event
// ids, then the message and config vocabulary, then the global, then the leaf whose
// functions every other MM source calls.
#include "/Kernel/Cfs/mm/mm_eventids.HC"
#include "/Kernel/Cfs/mm/mm_perfids.HC"
#include "/Kernel/Cfs/mm/mm_msg.HC"
#include "/Kernel/Cfs/mm/mm_global.HC"
#include "/Kernel/Cfs/mm/mm_utils.HC"
#include "/Kernel/Cfs/mm/mm_mem8.HC"
#include "/Kernel/Cfs/mm/mm_mem16.HC"
#include "/Kernel/Cfs/mm/mm_mem32.HC"
#include "/Kernel/Cfs/mm/mm_dump.HC"
#include "/Kernel/Cfs/mm/mm_load.HC"
#include "/Kernel/Cfs/mm/mm_cmds.HC"
#include "/Kernel/Cfs/mm/mm_dispatch.HC"
#include "/Kernel/Cfs/mm/mm_app.HC"
// CHECKSUM, the third app. Its vocabulary first: the event ids, the one performance id, the
// message/config/table-entry types, then the global -- which here also carries
// CS_TableWrapper_t, because CS_AppData_t embeds an array of six of them.
#include "/Kernel/Cfs/cs/cs_eventids.HC"
#include "/Kernel/Cfs/cs/cs_perfids.HC"
#include "/Kernel/Cfs/cs/cs_msg.HC"
#include "/Kernel/Cfs/cs/cs_global.HC"
// CS's three middle sources, which are a CYCLE and go in together -- cs_utils calls
// CS_ComputeEepromMemory, CS_ComputeTables and CS_ComputeApp in the second and
// CS_HandleTableUpdate in the third, and all three call back into the first. cs_utils.HC
// forward-declares those four, which is four declarations instead of a stand-in.
#include "/Kernel/Cfs/cs/cs_utils.HC"
#include "/Kernel/Cfs/cs/cs_compute.HC"
#include "/Kernel/Cfs/cs/cs_table_processing.HC"
// And cs_init.HC, step 2: it depends on the three above (seven functions out of
// cs_table_processing and one out of cs_utils) and the seven-source group depends on IT.
#include "/Kernel/Cfs/cs/cs_init.HC"
// CS's seven-source group, step 3. The order is: the five command files (which call into
// cs_utils, cs_compute, cs_table_processing and cs_app), then cs_app.HC, then cs_dispatch.HC.
// cs_app.HC forward-declares CS_AppPipe and cs_dispatch.HC forward-declares all 42 handlers, which
// is the two edges that close the cycle -- docs/CFS_PLAN.md measured that the other forty are a
// dispatcher calling its own handlers, a tree.
#include "/Kernel/Cfs/cs/cs_cmds.HC"
#include "/Kernel/Cfs/cs/cs_eeprom_cmds.HC"
#include "/Kernel/Cfs/cs/cs_memory_cmds.HC"
#include "/Kernel/Cfs/cs/cs_table_cmds.HC"
#include "/Kernel/Cfs/cs/cs_app_cmds.HC"
#include "/Kernel/Cfs/cs/cs_app.HC"
#include "/Kernel/Cfs/cs/cs_dispatch.HC"

// ===================== CS, THE THIRD cFS APP -- STEP 1'S STATE =====================
//
// CS reads memory DIRECTLY -- CFE_ES_CalculateCRC takes a raw pointer -- so every address the
// exercise hands it points into one of the two buffers below, filled by cs_fill_sources() with
// the same arithmetic on both halves. A CRC over equal bytes is equal wherever the bytes live;
// what cannot cross is PRINTING an address, so every pointer-valued assertion below is a
// COMPARISON against the pointer this driver handed over.
//
// THE SIX WRAPPERS ARE HAND-BUILT because CS_InitAllTables is cs_init.c -- step 2. cs_setup()
// mirrors NASA's TABLE_INITIALIZERS field for field, with these eight arrays standing in for the
// buffers table services will allocate once step 2 arrives. Both halves set the same eleven
// fields in the same order: a wrapper setup that drifted would produce a transcript diff that
// has nothing to do with CS.
//
// AND MaxBytesPerCycle IS SET HERE, which is not a detail. cs_app.c sets it (step 3); at zero
// CS_DoChecksumChunk clamps every cycle to zero bytes, CurrOffset never advances,
// CS_IsChecksumComplete is never true -- and the three recompute child tasks' `while
// (!DoneWithEntry)` does not terminate. That is a QEMU timeout that looks exactly like a codegen
// bug. It is deliberately set SMALLER than either buffer, so the chunking and the resume-from-
// ByteOffset path are what the transcript sees rather than a single-shot CRC.
#define CS_EX_BUDGET 64

U8 cs_src_a[200];
U8 cs_src_b[120];

CS_Def_EepromMemory_Table_Entry_t cs_def_eep[CS_MAX_NUM_EEPROM_TABLE_ENTRIES];
CS_Res_EepromMemory_Table_Entry_t cs_res_eep[CS_MAX_NUM_EEPROM_TABLE_ENTRIES];
CS_Def_EepromMemory_Table_Entry_t cs_def_mem[CS_MAX_NUM_MEMORY_TABLE_ENTRIES];
CS_Res_EepromMemory_Table_Entry_t cs_res_mem[CS_MAX_NUM_MEMORY_TABLE_ENTRIES];
CS_Def_Tables_Table_Entry_t cs_def_tbl[CS_MAX_NUM_TABLES_TABLE_ENTRIES];
CS_Res_Tables_Table_Entry_t cs_res_tbl[CS_MAX_NUM_TABLES_TABLE_ENTRIES];
CS_Def_App_Table_Entry_t cs_def_app[CS_MAX_NUM_APP_TABLE_ENTRIES];
CS_Res_App_Table_Entry_t cs_res_app[CS_MAX_NUM_APP_TABLE_ENTRIES];

U0 cs_fill_sources()
{
  I64 i;
  for (i = 0; i < 200; ++i) {
    cs_src_a[i] = i * 7 + 3;
  }
  for (i = 0; i < 120; ++i) {
    cs_src_b[i] = i * 11 + 5;
  }
}

U0 cs_setup()
{
  CS_TableWrapper_t *tw;
  I64 i;

  MemSet(&CS_AppData, 0, sizeof(CS_AppData_t));
  MemSet(cs_def_eep, 0, sizeof(CS_Def_EepromMemory_Table_Entry_t) * CS_MAX_NUM_EEPROM_TABLE_ENTRIES);
  MemSet(cs_res_eep, 0, sizeof(CS_Res_EepromMemory_Table_Entry_t) * CS_MAX_NUM_EEPROM_TABLE_ENTRIES);
  MemSet(cs_def_mem, 0, sizeof(CS_Def_EepromMemory_Table_Entry_t) * CS_MAX_NUM_MEMORY_TABLE_ENTRIES);
  MemSet(cs_res_mem, 0, sizeof(CS_Res_EepromMemory_Table_Entry_t) * CS_MAX_NUM_MEMORY_TABLE_ENTRIES);
  MemSet(cs_def_tbl, 0, sizeof(CS_Def_Tables_Table_Entry_t) * CS_MAX_NUM_TABLES_TABLE_ENTRIES);
  MemSet(cs_res_tbl, 0, sizeof(CS_Res_Tables_Table_Entry_t) * CS_MAX_NUM_TABLES_TABLE_ENTRIES);
  MemSet(cs_def_app, 0, sizeof(CS_Def_App_Table_Entry_t) * CS_MAX_NUM_APP_TABLE_ENTRIES);
  MemSet(cs_res_app, 0, sizeof(CS_Res_App_Table_Entry_t) * CS_MAX_NUM_APP_TABLE_ENTRIES);

  CS_AppData.MaxBytesPerCycle = CS_EX_BUDGET;

  // THE EIGHT TABLE HANDLES ARE EXPLICITLY INVALID, which NASA's initialiser does not do -- it
  // leaves them zero, and CS_RegisterResultTable/CS_RegisterDefinitionTable fill them in. That
  // is step 2. Zero IS A VALID cFE TABLE HANDLE (cfe_tbl_internal.HC:110 records why
  // CFE_TBL_BAD_TABLE_HANDLE is -1 and not 0), and MD has already registered tables by the time
  // this runs -- so a wrapper left at zero would make CS_SetDefEntryState's CFE_TBL_Modified
  // mark one of MD's dwell tables as changed. -1 makes it fail predictably instead, and the
  // failure is the behaviour step 1 can honestly exercise.
  for (i = 0; i < CS_NUM_TABLES; ++i) {
    CS_AppData.Tbl[i].DefHandle = CFE_TBL_BAD_TABLE_HANDLE;
    CS_AppData.Tbl[i].ResHandle = CFE_TBL_BAD_TABLE_HANDLE;
  }

  tw = &CS_AppData.Tbl[CS_ChecksumType_CFECORE];
  tw->BaselineValue = &CS_AppData.HkPacket.Payload.CfeCoreBaseline;
  tw->ResEntrySize = sizeof(CS_Res_EepromMemory_Table_Entry_t);
  tw->ResAddr = &CS_AppData.CfeCoreCodeSeg;
  tw->NumEntries = 1;

  tw = &CS_AppData.Tbl[CS_ChecksumType_OSCORE];
  tw->BaselineValue = &CS_AppData.HkPacket.Payload.OSBaseline;
  tw->ResEntrySize = sizeof(CS_Res_EepromMemory_Table_Entry_t);
  tw->ResAddr = &CS_AppData.OSCodeSeg;
  tw->NumEntries = 1;

  tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
  tw->DefTableName = CS_DEF_EEPROM_TABLE_NAME;
  tw->ResTableName = CS_RESULTS_EEPROM_TABLE_NAME;
  tw->GlobalState = &CS_AppData.HkPacket.Payload.EepromCSState;
  tw->NumEntries = CS_MAX_NUM_EEPROM_TABLE_ENTRIES;
  tw->DefEntrySize = sizeof(CS_Def_EepromMemory_Table_Entry_t);
  tw->ResEntrySize = sizeof(CS_Res_EepromMemory_Table_Entry_t);
  tw->DefStateOffset = 8; // offsetof(CS_Def_EepromMemory_Table_Entry_t, State)
  tw->UpdateHandler = &CS_ProcessNewEepromMemoryDefinitionTable;
  tw->DefaultDefinitionPtr = CS_AppData.DefaultEepromDefTable;
  tw->DefAddr = cs_def_eep;
  tw->ResAddr = cs_res_eep;

  tw = &CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE];
  tw->DefTableName = CS_DEF_MEMORY_TABLE_NAME;
  tw->ResTableName = CS_RESULTS_MEMORY_TABLE_NAME;
  tw->GlobalState = &CS_AppData.HkPacket.Payload.MemoryCSState;
  tw->NumEntries = CS_MAX_NUM_MEMORY_TABLE_ENTRIES;
  tw->DefEntrySize = sizeof(CS_Def_EepromMemory_Table_Entry_t);
  tw->ResEntrySize = sizeof(CS_Res_EepromMemory_Table_Entry_t);
  tw->DefStateOffset = 8; // offsetof(CS_Def_EepromMemory_Table_Entry_t, State)
  tw->UpdateHandler = &CS_ProcessNewEepromMemoryDefinitionTable;
  tw->DefaultDefinitionPtr = CS_AppData.DefaultMemoryDefTable;
  tw->DefAddr = cs_def_mem;
  tw->ResAddr = cs_res_mem;

  tw = &CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE];
  tw->DefTableName = CS_DEF_TABLES_TABLE_NAME;
  tw->ResTableName = CS_RESULTS_TABLES_TABLE_NAME;
  tw->GlobalState = &CS_AppData.HkPacket.Payload.TablesCSState;
  tw->NumEntries = CS_MAX_NUM_TABLES_TABLE_ENTRIES;
  tw->DefEntrySize = sizeof(CS_Def_Tables_Table_Entry_t);
  tw->ResEntrySize = sizeof(CS_Res_Tables_Table_Entry_t);
  tw->DefStateOffset = 0; // offsetof(CS_Def_Tables_Table_Entry_t, State)
  tw->UpdateHandler = &CS_ProcessNewTablesDefinitionTable;
  tw->DefaultDefinitionPtr = CS_AppData.DefaultTablesDefTable;
  tw->DefAddr = cs_def_tbl;
  tw->ResAddr = cs_res_tbl;

  tw = &CS_AppData.Tbl[CS_ChecksumType_APP_TABLE];
  tw->DefTableName = CS_DEF_APP_TABLE_NAME;
  tw->ResTableName = CS_RESULTS_APP_TABLE_NAME;
  tw->GlobalState = &CS_AppData.HkPacket.Payload.AppCSState;
  tw->NumEntries = CS_MAX_NUM_APP_TABLE_ENTRIES;
  tw->DefEntrySize = sizeof(CS_Def_App_Table_Entry_t);
  tw->ResEntrySize = sizeof(CS_Res_App_Table_Entry_t);
  tw->DefStateOffset = 0; // offsetof(CS_Def_App_Table_Entry_t, State)
  tw->UpdateHandler = &CS_ProcessNewAppDefinitionTable;
  tw->DefaultDefinitionPtr = CS_AppData.DefaultAppDefTable;
  tw->DefAddr = cs_def_app;
  tw->ResAddr = cs_res_app;

  // AND THE FOUR UpdateHandler MEMBERS ARE REPORTED NON-NULL, which is not padding. Each is a
  // file-scope reference to a function, and that is exactly what limit #22 turns into ZERO when
  // some other function's frame grows -- a limit this session has already hit once. Here the
  // symptom would NOT be mepc=0: CS_CallTableUpdateHandler guards with `if (tw->UpdateHandler)`,
  // so a zeroed member makes it quietly do nothing, the results tables never fill, and the
  // transcript differs somewhere downstream with no hint why. One line turns that into a named
  // failure at the place it happened.
  S("cs_setup handlers=");
  D(CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE].UpdateHandler != NULL);
  D(CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE].UpdateHandler != NULL);
  D(CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE].UpdateHandler != NULL);
  D(CS_AppData.Tbl[CS_ChecksumType_APP_TABLE].UpdateHandler != NULL);
  S("\n");
}



// mm_dispatch and mm_app's exercise state. mma_b is the BUFFER: a CFE_SB_Buffer is only an
// 8-byte alignment union, so a command is built in the LARGEST of the fourteen command types --
// MM_LoadMemWIDCmd_t, 288 bytes -- and its address passed as the buffer. `&BufPtr->Msg` is at
// offset 0 either way, which is what makes that substitution exact rather than convenient.
MM_LoadMemWIDCmd_t mma_b;
CFE_SB_MsgId mma_mid;
I32 mma_st;
I64 mma_k, mma_x0;
Bool mma_ok;
I64 mma_cc[13];
I64 mma_sz[13];
// MM'S COMMAND BUFFER. The C half writes this as an ANONYMOUS UNION LOCAL -- a buffer the size
// of the command being BUILT is not the size a handler READS -- and HolyC needs it named and at
// file scope.
union MM_AnyCmd_t
{
  MM_SendHkCmd_t Hk;
  MM_NoopCmd_t Noop;
  MM_ResetCountersCmd_t Reset;
  MM_LookupSymCmd_t Lookup;
  MM_SymTblToFileCmd_t SymTbl;
  MM_EepromWriteEnaCmd_t Ena;
  MM_EepromWriteDisCmd_t Dis;
  MM_PokeCmd_t Poke;
  MM_PeekCmd_t Peek;
  MM_LoadMemWIDCmd_t Wid;
  MM_LoadMemFromFileCmd_t LdFile;
  MM_DumpMemToFileCmd_t DmpFile;
  MM_FillMemCmd_t Fill;
  MM_DumpInEventCmd_t DmpEv;
};
MM_AnyCmd_t mmc_c;
I64 mmc_k, mmc_cc0;
I32 mmc_st;
// mm_load's exercise state.
I64 mml_k, mml_w, mml_p0;
I32 mml_st;
U32 mml_fd;
MM_PokeCmd_t mml_pk;
MM_FillMemCmd_t mml_fc;
MM_LoadDumpFileHeader_t mml_fh;
CFE_FS_Header_t mml_cf;
CFE_ES_PerfData_t *mml_perf;
// THE TWO BUFFERS MM'S GENERIC PATHS ACTUALLY DEREFERENCE. mm_dump.c's MM_DumpMemToFile and
// MM_FillDumpInEventBuffer's RAM/EEPROM arm MemCpy from the address they are given rather than
// going through CFE_PSP_MemRead*, so the simulated window of literal addresses does not work for
// them -- they need real memory. File scope on both halves (limit 22), and the same shape, so the
// two can be filled identically.
//
// mmd_evbuf IS SIXTEEN BYTES AND NASA CLEARS FIFTEEN. The sixteenth is a poison byte: it says
// MM_INTERNAL_MAX_DUMP_INEVENT_BYTES is the bound the clear used, which is the kind of constant a
// translation can get wrong without any other line noticing.
U8 mmd_src[250];
U8 mmd_evbuf[16];
U8 mmd_mts[4];
// Per-width captures for mm_load's poke exercises -- see the note at their use.
I64 mml_bp[3];
I64 mml_dv[3];
I64 mmd_k, mmd_r;
I32 mmd_st;
U32 mmd_fd;
U64 mmd_src_addr;
MM_PeekCmd_t mmd_pk;
MM_DumpInEventCmd_t mmd_de;
MM_LoadDumpFileHeader_t mmd_fh;
CFE_FS_Header_t mmd_cfh;
// mm_mem16 and mm_mem32's exercise state.
U64 mmw_A;
I64 mmw_k, mmw_w, mmw_r;
I32 mmw_st;
U32 mmw_fd;
MM_FillMemCmd_t mmw_fc;
MM_LoadDumpFileHeader_t mmw_fh;
// mm_mem8's exercise state, at file scope for the same reason as MM's above.
U64 mm8_A;
I64 mm8_k;
I32 mm8_st;
U32 mm8_fd;
I64 mm8_w0, mm8_p0;
MM_FillMemCmd_t mm8_fc;
MM_LoadDumpFileHeader_t mm8_fh;
CFE_ES_PerfData_t *mm8_perf;
// MM's exercise state, at FILE SCOPE for the reason docs/HOLYC_STRUCT_LIMITS.md #22 records --
// growing this function's total frame makes an unrelated file-scope read return zero -- and
// because HolyC has no aggregate initialiser, so the width list is filled at use.
U64 mmu_A;
I64 mmu_mt, mmu_vt, mmu_k, mmu_t;
I32 mmu_sv[8];
U32 mmu_crc;
U32 mmu_fd;
I64 mmu_before;
U64 mmu_ra;
I64 mmu_widths[3];
MM_SymAddr_t mmu_sa;
CFE_ES_StartPerfDataCmd_t mmu_spc;
CFE_ES_PerfData_t *mmu_perf;
// File scope, not locals: docs/HOLYC_STRUCT_LIMITS.md #22 -- growing a big function's TOTAL
// frame makes an unrelated file-scope read return zero -- and HolyC has no aggregate
// initialiser, so the mask list is filled at use.
U16 md_masks[5];
MD_SymAddr_t md_sa;
// The exercise's own scalars, also at file scope and for the same reason: #22 measured that
// FOUR added scalars in a big function's frame were enough to make a file-scope read return 0.
I64 md_mi;
I64 md_k;
// md_dwell_pkt's exercise. File scope for the reason above, and the two width lists because
// HolyC has no aggregate initialiser.
U16 md_widths[3];
U16 md_badw[4];
MD_DwellPacketControl_t *md_T;
MD_DwellPkt_t *md_P;
I64 md_n;
I64 md_i;
I64 md_r0;
I64 md_st;
I64 md_msz;
I64 md_sends0;
// md_dwell_tbl's exercise. md_load is 2,040 bytes and md_e 80; both at file scope for the
// reason above (limit #22), and because HolyC has no aggregate initialiser.
MD_DwellTableLoad_t md_load;
// The dispatcher's command buffer. A CFE_SB_Buffer is only an 8-byte alignment union, so a
// command is built in the LARGEST of the six command types -- MD_JamDwellCmd_t, 88 bytes --
// and its address passed as the buffer; &BufPtr->Msg is at offset 0 either way.
MD_JamDwellCmd_t md_dcmd;
U8 md_ccs[6];
I64 md_szs[6];
I64 md_i2;
MD_TableLoadEntry_t md_e;
U16 md_ac;
U16 md_sz;
U32 md_rate;
U16 md_bad;
MD_SymAddr_t md_na;
MD_DwellTableLoad_t *md_rb;
CFE_TBL_RegistryRec_t *md_rr;
// md_cmds' command messages, at FILE SCOPE for the reason the rest of this block is (limit
// #22): MD_JamDwellCmd_t is 88 bytes and MD_SetSignatureCmd_t 44.
MD_NoopCmd_t md_np;
MD_ResetCountersCmd_t md_rc;
MD_StartDwellCmd_t md_sd;
MD_StopDwellCmd_t md_pd;
MD_JamDwellCmd_t md_jd;
MD_SetSignatureCmd_t md_sg;
I64 md_used;
MD_SendHkCmd_t md_hk;
MD_HkTlm_t *md_hp;
CFE_SB_MsgId md_mid;
I64 md_x0;
CFE_ES_MemPoolRecord_t *md_pr;
I64 md_freed;
I64 md_get;
I64 md_k2;
I64 md_before;
U64 md_ra;
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
// --- cfe_tbl_loadbuff.c + cfe_tbl_regrec.c -------------------------------------------
// The pair, gated together because they are mutually recursive: regrec asks "which buffer is
// this id" on every load and only loadbuff knows, while loadbuff asks regrec for the record
// that owns a buffer.
//
// THE SERIAL ENCODING FIRST. One flat numbering over every buffer in the system -- four
// shared, then two per table -- recovered with a modulo and a comparison. Then the three
// buffer questions a registry record can answer, and finally the one branch that is the
// reason ForeachAccessDescriptor had to be written faithfully rather than as a counter: a
// load REFUSED because another application still holds the buffer it wants.
// --- cfe_tbl_valresult.c -------------------------------------------------------------
// Validation is a REQUEST, not a call: the app owns the validation function, so Table Services
// records the ask in one of ten blocks and the app answers it later from its own task. The two
// paths that matter are the one where there IS a validation function (block goes PENDING, the
// app will answer) and the one where there is not -- where the block is still allocated, goes
// straight to PERFORMED, the buffer is marked valid on the spot, and the only thing
// distinguishing "checked" from "nobody checked" is an INFORMATION event.
// --- cfe_tbl_passthru_codec.c --------------------------------------------------------
// The codec that does nothing, which is the point: without EDS a table file is a raw image of
// the table's memory, so encode and decode are a copy. What it really does is BYTE ORDER -- a
// cFE table file header is big endian on the wire so a file written on one processor loads on
// another -- plus one overflow check that is easy to read as a duplicate.
// --- cfe_tbl_transaction.c -----------------------------------------------------------
// WHO IS ALLOWED TO DO THIS. Every public CFE_TBL_* call runs inside a transaction that
// resolves the caller and the table, takes the registry lock, and collects events to send
// after releasing it. The access model is four bits and one comparison, and that comparison is
// the most important line in the module:
//
//     if ((AccessAllowed & AllowedContext) != AllowedContext)
//
// -- EVERY required bit must be present, not any. Table Services sets all of them.
U0 TblTransactionExercise()
{
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_AccessDescriptor_t *ad;
  CFE_TBL_TxnState_t txn;
  U32 self;
  I64 rc;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B30;
  CFE_ES_GetAppID(&self);
  // TxnInit: with a context check it resolves the caller; without, it does not look.
  MemSet(&txn, 0xA5, sizeof(CFE_TBL_TxnState_t));
  S("tbl_txinit ctx rc=");
  D(CFE_TBL_TxnInit(&txn, TRUE));
  S(" app=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_TxnAppId(&txn)));
  MemSet(&txn, 0xA5, sizeof(CFE_TBL_TxnState_t));
  S(" noctx rc=");
  D(CFE_TBL_TxnInit(&txn, FALSE));
  S(" app=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_TxnAppId(&txn)));
  S(" lock=");
  D(txn.RegLockCount);
  S("\n");
  // THE NAME IS REFUSED WHILE THE REGISTRY IS LOCKED, and the refusal is a literal that NASA
  // intends to appear in logs as a bug report: "if this is seen in a log, it is a bug in the
  // caller that should be fixed".
  CFE_TBL_TxnInit(&txn, TRUE);
  txn.RegLockCount = 1;
  S("tbl_txname locked=");
  S(CFE_TBL_TxnAppNameCaller(&txn));
  txn.RegLockCount = 0;
  S(" unlocked=");
  S(CFE_TBL_TxnAppNameCaller(&txn));
  S(" cached=");
  S(CFE_TBL_TxnAppNameCaller(&txn));
  S("\n");
  // START FROM NAME: found, and not found (which reports and unlocks).
  rr = &CFE_TBL_Global.Registry[2];
  CFE_TBL_InitRegistryRecord(rr);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 2));
  StrNCpy(rr->Config.Name, "CFE_TBL.Txn", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  rr->OwnerAppId = self;
  rc = CFE_TBL_TxnStartFromName(&txn, "CFE_TBL.Txn", CFE_TBL_TxnContext_UNDEFINED);
  S("tbl_txname_ok rc=");
  D(rc);
  S(" regid=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_TxnRegId(&txn)));
  S(" lock=");
  D(txn.RegLockCount);
  S("\n");
  CFE_TBL_TxnFinish(&txn);
  S("tbl_txfinish lock=");
  D(txn.RegLockCount);
  S("\n");
  rc = CFE_TBL_TxnStartFromName(&txn, "CFE_TBL.Nope", CFE_TBL_TxnContext_UNDEFINED);
  S("tbl_txname_miss rc=0x");
  Hx8(rc);
  S(" lock=");
  D(txn.RegLockCount);
  S(" events=");
  D(CFE_TBL_TxnGetEventCount(&txn));
  S(" id=");
  D(txn.PendingEvents[0].EventId);
  S("\n");
  // START FROM HANDLE. An undefined handle is refused BEFORE the registry is locked -- the
  // comment says why: "this avoids locking the registry for lookups that will certainly fail".
  rc = CFE_TBL_TxnStartFromHandle(&txn, CFE_TBL_HANDLEID_UNDEFINED, CFE_TBL_TxnContext_UNDEFINED);
  S("tbl_txh_undef rc=0x");
  Hx8(rc);
  S(" lock=");
  D(txn.RegLockCount);
  S("\n");
  // a good descriptor owned by us, pointing at a good record owned by us
  ad = &CFE_TBL_Global.Handles[9];
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9));
  ad->AppId = self;
  ad->RegIndex = CFE_TBL_RegRecGetID(rr);
  // ASKING FOR A CONTEXT IS WHAT MAKES THE CALLER BE RESOLVED AT ALL, and that is worth
  // pinning because it surprised me. TxnInit only calls CFE_ES_GetAppID when AllowedContext
  // != UNDEFINED, so a transaction started with UNDEFINED keeps AppId zero -- and a zero
  // AppId then compares EQUAL to an unset CFE_TBL_Global.TableTaskAppId, which grants
  // TABLE_SERVICES. So UNDEFINED means "no context required" and incidentally yields ctx=1
  // rather than the ctx=0 one might expect. Both cases are below.
  rc = CFE_TBL_TxnStartFromHandle(&txn, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9), CFE_TBL_TxnContext_UNDEFINED);
  S("tbl_txh_nocheck rc=");
  D(rc);
  S(" ctx=");
  D(txn.CallContext);
  S(" app=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_TxnAppId(&txn)));
  S("\n");
  CFE_TBL_TxnFinish(&txn);
  // ...and with a real requirement, the caller IS resolved, and because we are both the
  // descriptor's owner and the table's owner we get OWNER_APP|ACCESSOR_APP = 6.
  rc = CFE_TBL_TxnStartFromHandle(&txn, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9), CFE_TBL_TxnContext_ACCESSOR_APP);
  S("tbl_txh_ok rc=");
  D(rc);
  S(" ctx=");
  D(txn.CallContext);
  S(" lock=");
  D(txn.RegLockCount);
  S(" regid=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_TxnRegId(&txn)));
  S("\n");
  // FindAccessDescriptorForSelf walks the table's list looking for OUR descriptor.
  rr->AccessList.Next = CFE_TBL_AccDescGetHandle(ad);
  txn.AccDescPtr = NULL;
  S("tbl_txself rc=");
  D(CFE_TBL_FindAccessDescriptorForSelf(&txn));
  S(" found=");
  D(txn.AccDescPtr == ad);
  S(" handle=");
  D(CFE_TBL_TxnHandleAsULong(&txn));
  S("\n");
  // and with the descriptor owned by somebody else, it finds nothing
  ad->AppId = CFE_ResourceId_FromInteger(0xBEEF);
  txn.AccDescPtr = NULL;
  rc = CFE_TBL_FindAccessDescriptorForSelf(&txn);
  S("tbl_txself_other rc=0x");
  Hx8(rc);
  S(" found=");
  D(txn.AccDescPtr != NULL);
  S("\n");
  ad->AppId = self;
  CFE_TBL_TxnFinish(&txn);
  // ACCESS DENIED: require a context bit the caller does not have. We own the table, so demand
  // TABLE_SERVICES, which only tbl itself gets.
  rc = CFE_TBL_TxnStartFromHandle(&txn, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9), CFE_TBL_TxnContext_TABLE_SERVICES);
  S("tbl_txh_denied rc=0x");
  Hx8(rc);
  S(" events=");
  D(CFE_TBL_TxnGetEventCount(&txn));
  S(" id=");
  D(txn.PendingEvents[0].EventId);
  S(" data2=");
  D(txn.PendingEvents[0].EventData2);
  S(" lock=");
  D(txn.RegLockCount);
  S("\n");
  // AND AS TABLE SERVICES ITSELF every requirement passes, because AccessAllowed gets every
  // bit set.
  CFE_TBL_Global.TableTaskAppId = self;
  rc = CFE_TBL_TxnStartFromHandle(&txn, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9), CFE_TBL_TxnContext_ALL);
  S("tbl_txh_root rc=");
  D(rc);
  S(" ctx=");
  D(txn.CallContext);
  S("\n");
  CFE_TBL_TxnFinish(&txn);
  CFE_TBL_Global.TableTaskAppId = CFE_ES_APPID_UNDEFINED;
  // A STALE DESCRIPTOR: the handle is good but the record it names is free.
  ad->RegIndex = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 77);
  rc = CFE_TBL_TxnStartFromHandle(&txn, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9), CFE_TBL_TxnContext_UNDEFINED);
  S("tbl_txh_stale rc=0x");
  Hx8(rc);
  S(" lock=");
  D(txn.RegLockCount);
  S("\n");
  ad->RegIndex = CFE_TBL_RegRecGetID(rr);
  // THE NOTIFICATION LADDER: never loaded, then updated, then plain success.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  txn.AccDescPtr = ad;
  CFE_TBL_RegRecClearLoadInProgress(rr);
  rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
  S("tbl_txnotify never=0x");
  Hx8(CFE_TBL_TxnGetNextNotification(&txn));
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 8), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  ad->Updated = TRUE;
  S(" updated=0x");
  Hx8(CFE_TBL_TxnGetNextNotification(&txn));
  ad->Updated = FALSE;
  S(" plain=");
  D(CFE_TBL_TxnGetNextNotification(&txn));
  S("\n");
  // EVENT OVERFLOW: NumPendingEvents counts PAST the limit so the overrun is evident, and
  // ProcessEvents clamps back before walking.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  for (rc = 0; rc < CFE_TBL_MAX_EVENTS_PER_TXN + 3; rc++)
    CFE_TBL_TxnAddEvent(&txn, CFE_TBL_ACTIVATE_ERR_EID, 0, rc);
  S("tbl_txoverflow count=");
  D(CFE_TBL_TxnGetEventCount(&txn));
  S(" limit=");
  D(CFE_TBL_MAX_EVENTS_PER_TXN);
  S("\n");
  CFE_EVS_Global.EVS_EventBurstMax = 0;
  // the context must be filled: the helper renders it with %s and a NULL there is undefined
  // behaviour, not a blank.
  tbl_txctx.Operation = "Overflow";
  tbl_txctx.CallerName = "TXN_APP";
  tbl_txctx.TableName = CFE_TBL_RegRecGetName(rr);
  rc = CFE_TBL_TxnProcessEvents(&txn, &CFE_TBL_SendActivationEventHelper, &tbl_txctx);
  S("tbl_txclear processed=");
  D(rc);
  CFE_TBL_TxnClearEvents(&txn);
  S(" after=");
  D(CFE_TBL_TxnGetEventCount(&txn));
  S("\n");
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}
// tbl_mkfile lives with the cfe_tbl_load.c block below, which is where it belongs; this
// exercise needs it to build the table file its Load call reads.
U0 tbl_mkfile(U8 *tblname, U32 offset, U32 numbytes, I64 datasize, U32 contenttype, U16 subtype, U8 fill);
// --- cfe_tbl_api.c -------------------------------------------------------------
// THE PUBLIC API, AND THE RIGHT WAY TO EXERCISE IT IS A LIFECYCLE. Nineteen functions, and what
// matters is not each one alone but that an application can register a table, share it, load
// it, validate it, manage it, read it and give it back -- with every step going through the
// real transaction machinery, the real registry, the real buffers and the real events.
//
// So the order below is an app's order, not the file's: Register, Share, GetAddress(es), Load,
// Validate, GetStatus/Manage, Update, GetInfo, Modified, NotifyByMessage, DumpToBuffer,
// Unregister -- with the argument-check refusals folded in where they belong.
//
// TWO APP IDS ARE IN PLAY. es_set_ctx(1) is "CFE_EVS" and es_set_ctx(2) is "OTHER_APP"; the
// transaction's access check is the whole point of this file, so the OWNER and the NON-OWNER are
// both driven.
U0 TblApiExercise()
{
  I16 h1, h2, hbad;
  I16 handles[2];
  CFE_TBL_Info_t info;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_AccessDescriptor_t *ad1;
  CFE_TBL_AccessDescriptor_t *ad2;
  U8 *addr;
  U8 **addrs[2];
  U8 *a0;
  U8 *a1;
  I32 st;
  // THE SETUP IS THE REAL STARTUP SEQUENCE, which is both more faithful and less work than
  // hand-building CFE_TBL_Global. CFE_TBL_EarlyInit creates the two mutexes, the 512 KiB pool
  // and the four shared load buffers; CFE_TBL_InitData seeds all five resource-id spaces and
  // the three packet headers. Between them that is exactly what the object table and
  // CFE_TBL_TaskInit do at boot, and both are gated code.
  //
  // THE FIRST DRAFT HAND-BUILT IT AND EVERY ASSERTION BELOW CASCADED INTO A FAILURE. It memset
  // the global and called CFE_ES_PoolCreate directly, which returned without a usable handle --
  // `CFE_ES_GetPoolBuf: Err:Bad handle(0x00000000)` -- so CFE_TBL_SetupTableBuffers failed, so
  // Register failed, so all nineteen functions answered CFE_TBL_ERR_INVALID_HANDLE and the
  // whole block was one repeated number. The tell was `tbl_apireg rc=-1006632959 handle=-1`: a
  // handle of -1 is CFE_TBL_BAD_TABLE_HANDLE, so nothing had been registered at all.
  es_set_ctx(1);
  CFE_TBL_EarlyInit();
  CFE_TBL_InitData();
  CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
  // --- THE HANDLE/ID CONVERSION, FIRST, BECAUSE I GOT IT WRONG --------------------------
  //
  // CFE_TBL_Handle_t is an int16 in this configuration and CFE_TBL_BAD_TABLE_HANDLE is **-1**,
  // not zero -- so handle 0 is a PERFECTLY GOOD handle and -1 is the only invalid one. The
  // first draft of the translation wrote CFE_TBL_HANDLE_IS_VALID as a test against zero
  // (CFE_TBL_HandleID_IsDefined), which would have made CFE_TBL_HandleToID(0) answer UNDEFINED.
  // check_constants caught the constant; nothing could catch the macro body, because a macro
  // body is neither a value nor a signature. These three lines are what now catch it.
  S("tbl_handleid zero=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_HandleToID(0)));
  S(" base=");
  D(CFE_TBL_HANDLE_BASE);
  S(" bad=");
  D(!CFE_ResourceId_IsDefined(CFE_TBL_HandleToID(CFE_TBL_BAD_TABLE_HANDLE)));
  S("\n");
  S("tbl_handleid roundtrip=");
  D(CFE_TBL_HandleFromID(CFE_TBL_HandleToID(7)) == 7);
  S(" fromundef=");
  D(CFE_TBL_HandleFromID(CFE_TBL_HANDLEID_UNDEFINED) == CFE_TBL_BAD_TABLE_HANDLE);
  S("\n");
  // --- THE NULL-ARGUMENT REFUSALS, which return before any transaction starts ----------
  S("tbl_apinull reg1=");
  D(CFE_TBL_Register(NULL, "X", 32, 0, NULL));
  S(" reg2=");
  D(CFE_TBL_Register(&h1, NULL, 32, 0, NULL));
  S(" share1=");
  D(CFE_TBL_Share(NULL, "X"));
  S(" share2=");
  D(CFE_TBL_Share(&h1, NULL));
  S("\n");
  S("tbl_apinull load=");
  D(CFE_TBL_Load(0, CFE_TBL_SRC_ADDRESS, NULL));
  S(" getaddr=");
  D(CFE_TBL_GetAddress(NULL, 0));
  S(" getaddrs1=");
  D(CFE_TBL_GetAddresses(NULL, 1, handles));
  S(" getaddrs2=");
  D(CFE_TBL_GetAddresses(addrs, 1, NULL));
  S(" reladdrs=");
  D(CFE_TBL_ReleaseAddresses(1, NULL));
  S(" info1=");
  D(CFE_TBL_GetInfo(NULL, "X"));
  S("\n");
  // --- REGISTER, as CFE_EVS ------------------------------------------------------------
  es_set_ctx(1);
  tbl_val_rc = CFE_SUCCESS;
  st = CFE_TBL_Register(&h1, "Api", 32, CFE_TBL_OPT_DEFAULT, &TblValStub);
  S("tbl_apireg rc=");
  D(st);
  S(" handle=");
  D(h1);
  S(" id=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_HandleToID(h1)));
  S("\n");
  // AND THE DUPLICATE, which is a WARNING and hands back the SAME handle -- the one path in the
  // registry that is a supported no-op rather than an error.
  st = CFE_TBL_Register(&h2, "Api", 32, CFE_TBL_OPT_DEFAULT, &TblValStub);
  S("tbl_apireg dup=");
  D(st);
  S(" same=");
  D(h2 == h1);
  S("\n");
  // --- SHARE, as OTHER_APP, which is what CFE_TBL_TxnContext_OTHER_APP is for ----------
  es_set_ctx(2);
  st = CFE_TBL_Share(&h2, "CFE_EVS.Api");
  S("tbl_apishare rc=");
  D(st);
  S(" different=");
  D(h2 != h1);
  S(" users=");
  if (CFE_TBL_GetInfo(&info, "CFE_EVS.Api") == CFE_SUCCESS)
    D(info.NumUsers);
  else
    D(0);
  S("\n");
  st = CFE_TBL_Share(&hbad, "NO.SUCH");
  S("tbl_apishare missing=");
  D(st);
  S(" bad=");
  D(hbad == CFE_TBL_BAD_TABLE_HANDLE);
  S("\n");
  // RESOLVE THE RECORD AND THE TWO DESCRIPTORS, rather than assuming where they landed.
  // THE FIRST DRAFT HARD-CODED Registry[0], Handles[0] and Handles[1] and SEVEN assertions below
  // read the wrong objects: `tbl_apival status=0` where a pending validation was planted,
  // `tbl_apimanage updated=0`, `tbl_apinotify enabled=0` right after a call that returned
  // CFE_SUCCESS, `tbl_apimod own=0 other=0`. Each was a plausible-looking zero.
  // CFE_TBL_InitData seeds LastRegId to the BASE, so the allocator does not start at index 0 --
  // which is exactly the kind of thing a hand-built global hides and the real startup path does
  // not.
  rr = CFE_TBL_LocateRegRecByName("CFE_EVS.Api");
  ad1 = CFE_TBL_LocateAccDescByHandle(CFE_TBL_HandleToID(h1));
  ad2 = CFE_TBL_LocateAccDescByHandle(CFE_TBL_HandleToID(h2));
  S("tbl_apiresolve rr=");
  D(rr != NULL);
  S(" ad1=");
  D(ad1 != NULL);
  S(" ad2=");
  D(ad2 != NULL);
  S(" distinct=");
  D(ad1 != ad2);
  S("\n");
  // --- LOAD, FROM A FILE, as the OWNER ------------------------------------------------
  // FROM A FILE AND NOT FROM AN ADDRESS, deliberately: CFE_TBL_TxnLoadFromSourceAddr writes
  // "Addr 0x%08lX" of the caller's pointer into DataSource, and CFE_TBL_GetInfo reports
  // DataSource as LastFileLoaded -- so an address load put `last=Addr 0x102F99610` into the
  // transcript, an arm64 value the RISC-V half cannot match. A file load makes the same field a
  // filename, which also leaves the modified marker below readable.
  //
  // A non-owner is refused first: CFE_TBL_TxnContext_OWNER_APP is what Load requires, and
  // OTHER_APP holds only an accessor descriptor.
  tbl_mkfile("CFE_EVS.Api", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x7E);
  st = CFE_TBL_Load(h2, CFE_TBL_SRC_FILE, "/ram/load.tbl");
  S("tbl_apiload notowner=");
  D(st);
  S("\n");
  es_set_ctx(1);
  st = CFE_TBL_Load(h1, CFE_TBL_SRC_FILE, "/ram/load.tbl");
  S("tbl_apiload rc=");
  D(st);
  S("\n");
  // --- GetAddress / ReleaseAddress ----------------------------------------------------
  addr = NULL;
  st = CFE_TBL_GetAddress(&addr, h1);
  S("tbl_apiaddr rc=");
  D(st);
  S(" nonnull=");
  D(addr != NULL);
  S(" first=");
  if (addr == NULL)
    Hx2b(0);
  else
    Hx2b(addr[0]);
  S("\n");
  st = CFE_TBL_ReleaseAddress(h1);
  S("tbl_apiaddr release=");
  D(st);
  S("\n");
  // AND THE PLURAL FORMS. Two handles, one good and one that was never registered: the first
  // non-success is KEPT and the loop keeps going, so `rc` is the bad one's status while the good
  // one's address still comes back.
  handles[0] = h1;
  handles[1] = 0x7FFF;
  a0 = NULL;
  a1 = NULL;
  addrs[0] = &a0;
  addrs[1] = &a1;
  st = CFE_TBL_GetAddresses(addrs, 2, handles);
  S("tbl_apiaddrs rc=");
  D(st);
  S(" good=");
  D(a0 != NULL);
  S(" bad=");
  D(a1 == NULL);
  S("\n");
  st = CFE_TBL_ReleaseAddresses(2, handles);
  S("tbl_apiaddrs release=");
  D(st);
  S("\n");
  // --- VALIDATE, GetStatus, Manage ----------------------------------------------------
  // With nothing pending, Validate says so and GetStatus says CFE_SUCCESS.
  st = CFE_TBL_Validate(h1);
  S("tbl_apival nopending=");
  D(st);
  st = CFE_TBL_GetStatus(h1);
  S(" status=");
  D(st);
  S("\n");
  // Now plant a validation request and run it twice, on the two buffer selections -- and WHAT
  // THEY REACH IS DIFFERENT, which is not what the first draft's comment claimed.
  //
  // INACTIVE means the load-in-progress buffer, and there is no load in progress, so
  // CFE_TBL_GetLoadInProgressBuffer answers NULL and CFE_TBL_Validate takes its "no buffer, it
  // cannot be valid" arm: `result=-1` WITHOUT the validation function ever being called. ACTIVE
  // finds the real buffer and does call it, which is why `failed` reports the -3 the stub was
  // told to return. Two distinct arms, one of which never reaches the callback.
  //
  // In both cases the result goes into the validation-result BLOCK, not the return value --
  // `performed=0` means "the validation was carried out", not "the table is valid", which is
  // NASA's own distinction and the reason CFE_TBL_Manage loops on it.
  CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0], CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
  CFE_TBL_Global.ValidationResults[0].BufferSelect = CFE_TBL_BufferSelect_INACTIVE;
  rr->PendingValId = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE);
  S("tbl_apival status=");
  D(CFE_TBL_GetStatus(h1));
  S("\n");
  tbl_val_rc = CFE_SUCCESS;
  st = CFE_TBL_Validate(h1);
  S("tbl_apival performed=");
  D(st);
  S(" result=");
  D(CFE_TBL_Global.ValidationResults[0].Result);
  S(" state=");
  D(CFE_TBL_Global.ValidationResults[0].State);
  S("\n");
  // a FAILING validator takes the other event and leaves a non-zero result
  CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0], CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
  CFE_TBL_Global.ValidationResults[0].BufferSelect = CFE_TBL_BufferSelect_ACTIVE;
  rr->PendingValId = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE);
  tbl_val_rc = -3;
  st = CFE_TBL_Validate(h1);
  S("tbl_apival failed=");
  D(st);
  S(" result=");
  D(CFE_TBL_Global.ValidationResults[0].Result);
  S("\n");
  tbl_val_rc = CFE_SUCCESS;
  // --- MANAGE, which is the loop over GetStatus ---------------------------------------
  // Nothing pending: one pass, CFE_SUCCESS.
  st = CFE_TBL_Manage(h1);
  S("tbl_apimanage idle=");
  D(st);
  S("\n");
  // An UPDATE pending: Manage updates and reports CFE_TBL_INFO_UPDATED, which is the code a
  // caller watches for to know its table changed underneath it.
  rr->Buffers[0].IsValid = TRUE;
  rr->Buffers[0].ActivateReq = TRUE;
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  st = CFE_TBL_Manage(h1);
  S("tbl_apimanage updated=");
  D(st);
  S("\n");
  // --- UPDATE on its own, and the no-op case ------------------------------------------
  st = CFE_TBL_Update(h1);
  S("tbl_apiupdate nothing=");
  D(st);
  S("\n");
  // --- GetInfo, which is the one function that fills a struct for the caller -----------
  MemSet(&info, 0xA5, sizeof(CFE_TBL_Info_t));
  st = CFE_TBL_GetInfo(&info, "CFE_EVS.Api");
  S("tbl_apiinfo rc=");
  D(st);
  S(" size=");
  D(info.Size);
  S(" users=");
  D(info.NumUsers);
  S(" loaded=");
  D(info.TableLoadedOnce);
  S(" dbl=");
  D(info.DoubleBuffered);
  S(" dmp=");
  D(info.DumpOnly);
  S(" usr=");
  D(info.UserDefAddr);
  S(" crit=");
  D(info.Critical);
  S(" crc=");
  D(info.Crc != 0);
  S(" last=");
  S(info.LastFileLoaded);
  S("\n");
  st = CFE_TBL_GetInfo(&info, "NO.SUCH");
  S("tbl_apiinfo missing=");
  D(st);
  S("\n");
  // --- MODIFIED, which marks the table and notifies the OTHER holders -----------------
  // h2 belongs to OTHER_APP, so calling Modified as CFE_EVS must set OTHER_APP's Updated flag
  // and NOT its own -- that is what CFE_TBL_NotifyOtherAppHelper is for.
  ad1->Updated = FALSE;
  ad2->Updated = FALSE;
  st = CFE_TBL_Modified(h1);
  S("tbl_apimod rc=");
  D(st);
  S(" own=");
  D(ad1->Updated);
  S(" other=");
  D(ad2->Updated);
  S("\n");
  // and the name now carries the modified marker
  CFE_TBL_GetInfo(&info, "CFE_EVS.Api");
  S("tbl_apimod marked=");
  S(info.LastFileLoaded);
  S("\n");
  // --- NOTIFY BY MESSAGE: owner only --------------------------------------------------
  st = CFE_TBL_NotifyByMessage(h1, CFE_SB_ValueToMsgId(0x1888), 3, 0x1234);
  S("tbl_apinotify owner=");
  D(st);
  S(" enabled=");
  D(rr->Notify.Enabled);
  S(" mid=");
  Hx4(CFE_SB_MsgIdToValue(rr->Notify.MsgId));
  S(" fcn=");
  D(rr->Notify.FcnCode);
  S(" param=");
  Hx4(rr->Notify.Param);
  S("\n");
  es_set_ctx(2);
  st = CFE_TBL_NotifyByMessage(h2, CFE_SB_ValueToMsgId(0x1888), 3, 0x1234);
  S("tbl_apinotify notowner=");
  D(st);
  S("\n");
  es_set_ctx(1);
  // --- DUMP TO BUFFER, both answers ---------------------------------------------------
  // With no dump pending at all, NO_DUMP_PENDING and nothing is logged. With a STALE id -- one
  // that is valid but matches no block -- the same status comes back, the id is CLEARED, and a
  // syslog line says it was dropped. The `cleared` field is the difference.
  st = CFE_TBL_DumpToBuffer(h1);
  S("tbl_apidump none=");
  D(st);
  S("\n");
  rr->DumpControlId = CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + 1);
  st = CFE_TBL_DumpToBuffer(h1);
  S("tbl_apidump stale=");
  D(st);
  S(" cleared=");
  D(!CFE_TBL_DUMPCTRLID_IS_VALID(rr->DumpControlId));
  S("\n");
  // --- UNREGISTER, and the handle is dead afterwards ----------------------------------
  st = CFE_TBL_Unregister(h1);
  S("tbl_apiunreg rc=");
  D(st);
  S("\n");
  // EACH CALL INTO A LOCAL FIRST. Both of these emit a syslog line, and C evaluates every
  // printf argument before printing any of them while this half prints incrementally -- so as
  // arguments they put their log lines on opposite sides of the label. Fourth and fifth instance
  // of this trap in the project; it is always worth writing out.
  st = CFE_TBL_Unregister(h1);
  S("tbl_apiunreg again=");
  D(st);
  st = CFE_TBL_GetStatus(h1);
  S(" status=");
  D(st);
  S("\n");
  es_ctx_init();
}
// --- cfe_tbl_load.c -------------------------------------------------------------
// SIXTEEN FUNCTIONS, AND A LOAD IS THE MOST GUARDED OPERATION IN TABLE SERVICES. The exercise
// follows the file path in order, because every step can refuse and the interesting thing about
// each one is WHICH refusal it produces.
//
// THE FILE IS BUILT EXPLICITLY, NOT ROUND-TRIPPED THROUGH A DUMP, and that is not a style
// choice. CFE_TBL_WriteSnapshotToFile leaves Tbl.Reserved and Tbl.Offset as uninitialised stack
// -- see the note at tbl_dmphdr and in docs/CFS_PLAN.md -- and CFE_TBL_ReadHeaders reads Offset
// to decide where the data lands. A dump-then-load exercise would therefore be NONDETERMINISTIC
// between the two halves and would present as a load.c translation bug. So tbl_mkfile below
// sets all four table-header fields itself.
U0 tbl_mkfile(U8 *tblname, U32 offset, U32 numbytes, I64 datasize, U32 contenttype, U16 subtype, U8 fill)
{
  CFE_TBL_CombinedFileHdr_t hdr;
  CFE_TBL_TxnState_t txn;
  U32 fd;
  I64 k;
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  // THE WHOLE header, unlike NASA's partial memset -- this is driver code and may be
  // deterministic where the code under test is not.
  MemSet(&hdr, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  CFE_FS_InitHeader(&hdr.Std, "Table Load Image", subtype);
  hdr.Std.ContentType = contenttype;
  hdr.Std.TimeSeconds = 0x11223344;
  hdr.Std.TimeSubSeconds = 0x55667788;
  hdr.Tbl.Reserved = 0;
  hdr.Tbl.Offset = offset;
  hdr.Tbl.NumBytes = numbytes;
  StrNCpy(hdr.Tbl.TableName, tblname, CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  fs_len = 0;
  fs_pos = 0;
  fs_wr_left = -1;
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
  CFE_TBL_WriteHeaders(&txn, fd, &hdr);
  for (k = 0; k < datasize; k++)
    tbl_probe_mem2[k] = fill + k;
  OS_write(fd, tbl_probe_mem2, datasize);
  OS_close(fd);
  // THE CONTENT TYPE HAS TO BE POKED INTO THE FILE, not set in the struct. CFE_FS_WriteHeader
  // writes CFE_FS_FILE_CONTENT_ID itself, overwriting whatever the caller put there -- the
  // first draft set hdr.Std.ContentType and the badcontent case came back SUCCESS with
  // ct=63464531, which is "cFE1" in ASCII. It is the first four bytes of the file, big-endian.
  // (SubType survives, which is why that case needs no poke; and TimeSeconds does NOT survive
  // either -- WriteHeader stamps the current time -- which is why tbl_rdhdr reports the clock's
  // value and not the one tbl_mkfile asked for.)
  if (contenttype != CFE_FS_FILE_CONTENT_ID) {
    fs_data[0] = (contenttype >> 24) & 0xFF;
    fs_data[1] = (contenttype >> 16) & 0xFF;
    fs_data[2] = (contenttype >> 8) & 0xFF;
    fs_data[3] = contenttype & 0xFF;
  }
  fs_pos = 0;
}

U0 TblLoadExercise()
{
  CFE_TBL_TxnState_t txn;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_CombinedFileHdr_t hdr;
  CFE_TBL_LoadBuff_t *lb;
  U32 fd;
  I32 st;
  I64 k;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B60;
  CFE_TBL_Global.WorkBufMutex = 0x7B61;
  CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
  CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + CFE_TBL_TOTAL_LOAD_BUFFS - 1);
  // --- WHAT THIS EXERCISE CANNOT REACH, AND WHY, said before the parts it can -----------
  //
  // CFE_TBL_ValidateTableHeaderId CANNOT BE CALLED FROM THE C HALF. Like
  // CFE_TBL_HandleListGetSafeLink in cfe_tbl_internal.c, it is a non-static definition with NO
  // DECLARATION IN ANY HEADER, so the oracle cannot name it. (check_coverage and
  // check_signatures both compare it; only the body is unexercised.)
  //
  // And it would not help much if it could: both accept lists are EMPTY in this configuration
  // -- cfe_platformcfg_tables.HC says so at its top, CFE_PLATFORM_TBL_VALID_SCID and _PRID have
  // a count of zero -- so the function always returns true and CFE_TBL_ReadHeaders'
  // CFE_TBL_ERR_BAD_SPACECRAFT_ID and CFE_TBL_ERR_BAD_PROCESSOR_ID arms are UNREACHABLE. That is
  // a configuration fact, the same kind the coverage gate already records for the nine functions
  // a verified #if excludes, not a gap someone forgot to fill. A mission that configures a list
  // is the thing that would reach them.
  //
  // --- THE REGISTRY RECORD every step below works against -----------------------------
  // Registry[11]'s own buffer pair is serial 4 + 2*11 = 26 and 27.
  rr = &CFE_TBL_Global.Registry[11];
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 11));
  StrNCpy(rr->Config.Name, "LD_APP.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  rr->Config.Size = 32;
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  CFE_TBL_HandleLinkInit(&rr->AccessList);
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 26), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_LoadBuffSetAllocatedBlock(&rr->Buffers[0], tbl_probe_mem, sizeof(tbl_probe_mem));
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    CFE_TBL_LoadBuffSetAllocatedBlock(&CFE_TBL_Global.LoadBuffs[k], tbl_probe_mem, sizeof(tbl_probe_mem));
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  // --- CFE_TBL_ReadHeaders, four answers ----------------------------------------------
  // A SHORT FILE first: no std header at all.
  fs_len = 0;
  fs_pos = 0;
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  MemSet(&hdr, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
  S("tbl_rdhdr nostd=");
  D(st);
  S("\n");
  OS_close(fd);
  // WRONG CONTENT ID
  tbl_mkfile("LD_APP.Tbl", 0, 32, 32, 0xBADF00D, CFE_FS_SubType_TBL_IMG, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  MemSet(&hdr, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
  S("tbl_rdhdr badcontent=");
  D(st);
  S(" ct=");
  Hx4(hdr.Std.ContentType >> 16);
  Hx4(hdr.Std.ContentType);
  S("\n");
  OS_close(fd);
  // WRONG SUBTYPE
  tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, 99, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  MemSet(&hdr, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
  S("tbl_rdhdr badsubtype=");
  D(st);
  S(" sub=");
  D(hdr.Std.SubType);
  S("\n");
  OS_close(fd);
  // AND A GOOD ONE: the whole header comes back, and the four table fields are exactly what
  // tbl_mkfile wrote -- which is the point of building it explicitly.
  tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  MemSet(&hdr, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  st = CFE_TBL_ReadHeaders(&txn, fd, &hdr);
  S("tbl_rdhdr ok=");
  D(st);
  S(" name=");
  S(hdr.Tbl.TableName);
  S(" n=");
  D(hdr.Tbl.NumBytes);
  S(" off=");
  D(hdr.Tbl.Offset);
  S(" resv=");
  D(hdr.Tbl.Reserved);
  S(" secs=");
  Hx4(hdr.Std.TimeSeconds >> 16);
  Hx4(hdr.Std.TimeSeconds);
  S("\n");
  // --- CFE_TBL_ValidateFileIsLoadable, five answers -----------------------------------
  txn.RegRecPtr = NULL;
  st = CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl);
  S("tbl_loadable notbl=");
  D(st);
  S("\n");
  txn.RegRecPtr = rr;
  StrNCpy(hdr.Tbl.TableName, "OTHER.Tbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  st = CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl);
  S("tbl_loadable wrongname=");
  D(st);
  S("\n");
  StrNCpy(hdr.Tbl.TableName, "LD_APP.Tbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  hdr.Tbl.NumBytes = 0;
  st = CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl);
  S("tbl_loadable zerolen=");
  D(st);
  S("\n");
  hdr.Tbl.NumBytes = 16;
  hdr.Tbl.Offset = 8;
  st = CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl);
  S("tbl_loadable partial=");
  D(st);
  S("\n");
  // a partial load IS allowed once the table has been loaded before
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  st = CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl);
  S("tbl_loadable partialok=");
  D(st);
  S("\n");
  rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
  hdr.Tbl.Offset = 0;
  hdr.Tbl.NumBytes = 32;
  st = CFE_TBL_ValidateFileIsLoadable(&txn, &hdr.Tbl);
  S("tbl_loadable ok=");
  D(st);
  S("\n");
  // --- CFE_TBL_ValidateLoadRequest, the five arms -------------------------------------
  // Into locals: each refusal queues an event, and they are all sent at the end.
  txn.RegRecPtr = NULL;
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
  S("tbl_ldreq notbl=");
  D(st);
  S("\n");
  txn.RegRecPtr = rr;
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
  S("tbl_ldreq inprogress=");
  D(st);
  S("\n");
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadRequest(&txn, 99);
  S("tbl_ldreq badsrc=");
  D(st);
  S("\n");
  // A DUMP-ONLY TABLE CAN BE LOADED EXACTLY ONCE AND ONLY FROM AN ADDRESS. Not user-defined is
  // refused; user-defined but already loaded is refused; user-defined, unloaded, from a FILE is
  // refused; user-defined, unloaded, from an ADDRESS is allowed. The first two report the SAME
  // status from two different preconditions, which is NASA's code and not a duplicate assertion.
  rr->Config.DumpOnly = TRUE;
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_ADDRESS);
  S("tbl_ldreq dmp_notuser=");
  D(st);
  S("\n");
  rr->Config.UserDefAddr = TRUE;
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_ADDRESS);
  S("tbl_ldreq dmp_loaded=");
  D(st);
  S("\n");
  rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
  S("tbl_ldreq dmp_fromfile=");
  D(st);
  S("\n");
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_ADDRESS);
  S("tbl_ldreq dmp_fromaddr=");
  D(st);
  S(" lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr));
  S("\n");
  rr->Config.DumpOnly = FALSE;
  rr->Config.UserDefAddr = FALSE;
  // and the ordinary success, which RESERVES a working buffer as its whole side effect
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
  S("tbl_ldreq ok=");
  D(st);
  S(" lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr));
  S("\n");
  // THE EVENT LIST HOLDS EIGHT AND THIS GROUP QUEUED MORE, which is why it is flushed here
  // instead of at the end of the block. A negative control found this: changing the event id in
  // CFE_TBL_ValidateLoadInProgress's positive arm left the transcript IDENTICAL, because by the
  // time that code ran the transaction had long overflowed and CFE_TBL_TxnAddEvent was dropping
  // everything. A real mutation that still passes means the driver never reaches it.
  //
  // `queued=` is NASA's own overflow witness: the counter "always increments ... to make it
  // evident if there was an overflow", and until now nothing read it. Above 8 means events were
  // lost.
  S("tbl_ldreq queued=");
  D(txn.NumPendingEvents);
  S(" overflow=");
  D(txn.NumPendingEvents > CFE_TBL_MAX_EVENTS_PER_TXN);
  S("\n");
  StrNCpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
  CFE_TBL_SendTableLoadEvents(&txn);
  txn.NumPendingEvents = 0;
  // --- CFE_TBL_LoadContentFromFile, four answers --------------------------------------
  // TOO LARGE: a 32-byte buffer cannot take 32 bytes at offset 40.
  tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  OS_lseek(fd, 116, 0);
  st = CFE_TBL_LoadContentFromFile(&txn, fd, 40, 32);
  S("tbl_ldcontent toobig=");
  D(st);
  S("\n");
  OS_close(fd);
  // SHORT: the header claims 32 bytes but only 8 follow.
  tbl_mkfile("LD_APP.Tbl", 0, 32, 8, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  OS_lseek(fd, 116, 0);
  st = CFE_TBL_LoadContentFromFile(&txn, fd, 0, 32);
  S("tbl_ldcontent short=");
  D(st);
  S("\n");
  OS_close(fd);
  // TOO MUCH DATA: the header claims 32 and 40 follow. This is the one-byte read past the end,
  // and nothing else in the function would catch it.
  tbl_mkfile("LD_APP.Tbl", 0, 32, 40, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  OS_lseek(fd, 116, 0);
  st = CFE_TBL_LoadContentFromFile(&txn, fd, 0, 32);
  S("tbl_ldcontent extradata=");
  D(st);
  S("\n");
  OS_close(fd);
  // AND EXACTLY RIGHT. first/last are the proof the DATA arrived, not just the status.
  tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x40);
  OS_OpenCreate(&fd, "/ram/load.tbl", OS_FILE_FLAG_NONE, OS_READ_ONLY);
  OS_lseek(fd, 116, 0);
  st = CFE_TBL_LoadContentFromFile(&txn, fd, 0, 32);
  OS_close(fd);
  lb = CFE_TBL_GetLoadInProgressBuffer(rr);
  S("tbl_ldcontent ok=");
  D(st);
  S(" size=");
  if (lb == NULL)
    D(0);
  else
    D(CFE_TBL_LoadBuffGetContentSize(lb));
  S(" first=");
  if (lb == NULL)
    Hx2b(0);
  else
    Hx2b(CFE_TBL_LoadBuffGetReadPointer(lb)[0]);
  S(" last=");
  if (lb == NULL)
    Hx2b(0);
  else
    Hx2b(CFE_TBL_LoadBuffGetReadPointer(lb)[31]);
  S("\n");
  // flush again before the validation group, same reason
  S("tbl_ldcontent queued=");
  D(txn.NumPendingEvents);
  S("\n");
  CFE_TBL_SendTableLoadFileEvents(&txn, "/ram/load.tbl", &hdr);
  txn.NumPendingEvents = 0;
  // --- CFE_TBL_SetMetaDataFromFileHeader ----------------------------------------------
  // The file time comes from the STD header, the CRC is recomputed, and IsValid is seeded from
  // whether a validation function exists -- a table with no validator is valid on arrival, one
  // with a validator is not until the validator says so.
  hdr.Std.TimeSeconds = 0x11223344;
  hdr.Std.TimeSubSeconds = 0x55667788;
  rr->Config.ValidationFuncPtr = NULL;
  CFE_TBL_SetMetaDataFromFileHeader(&txn, "/ram/load.tbl", &hdr.Std);
  S("tbl_ldmeta src=");
  S(lb->DataSource);
  S(" secs=");
  Hx4(lb->FileTime.Seconds >> 16);
  Hx4(lb->FileTime.Seconds);
  S(" subs=");
  Hx4(lb->FileTime.Subseconds >> 16);
  Hx4(lb->FileTime.Subseconds);
  S(" valid=");
  D(lb->IsValid);
  S(" actreq=");
  D(lb->ActivateReq);
  S(" crc=");
  D(lb->Crc != 0);
  S("\n");
  rr->Config.ValidationFuncPtr = &TblValStub;
  CFE_TBL_SetMetaDataFromFileHeader(&txn, "/ram/load.tbl", &hdr.Std);
  S("tbl_ldmeta withfunc valid=");
  D(lb->IsValid);
  S("\n");
  // --- CFE_TBL_ValidateLoadInProgress, four answers -----------------------------------
  // No validator is assumed success; a validator returning 0 succeeds; a POSITIVE return and a
  // NEGATIVE one raise DIFFERENT event ids, which NASA's own comment calls historical and
  // unexplained.
  rr->Config.ValidationFuncPtr = NULL;
  st = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
  S("tbl_ldval nofunc=");
  D(st);
  S(" valid=");
  D(lb->IsValid);
  S(" actreq=");
  D(lb->ActivateReq);
  S("\n");
  rr->Config.ValidationFuncPtr = &TblValStub;
  tbl_val_rc = CFE_SUCCESS;
  st = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
  S("tbl_ldval pass=");
  D(st);
  S(" valid=");
  D(lb->IsValid);
  S("\n");
  tbl_val_rc = 7;
  st = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
  S("tbl_ldval positive=");
  D(st);
  S(" valid=");
  D(lb->IsValid);
  S("\n");
  tbl_val_rc = -9;
  st = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
  S("tbl_ldval negative=");
  D(st);
  S(" valid=");
  D(lb->IsValid);
  S(" cleared=");
  D(CFE_TBL_LoadBuffGetReadPointer(lb)[0] == 0);
  S("\n");
  tbl_val_rc = CFE_SUCCESS;
  rr->Config.ValidationFuncPtr = NULL;
  // and the no-buffer arm
  CFE_TBL_RegRecClearLoadInProgress(rr);
  st = CFE_TBL_ValidateLoadInProgress(&txn, CFE_SUCCESS);
  S("tbl_ldval nobuf=");
  D(st);
  S("\n");
  // --- SEND WHAT THE VALIDATION GROUP QUEUED ------------------------------------------
  // Only that group is pending now, so these lines are the two validation event ids --
  // CFE_TBL_LOAD_VAL_ERR_EID for a POSITIVE return and CFE_TBL_VALIDATION_ERR_EID for a negative
  // one -- plus the second of each pair, because the positive arm sets Status to
  // CFE_STATUS_VALIDATION_FAILURE, which is NEGATIVE, so it falls into the negative arm too and
  // queues BOTH. That cascade is NASA's and is the reason a single-id mutation is only visible
  // once the list is not overflowing.
  //
  // The FILE helper handles what needs the header in its text and FALLS THROUGH to the basic one
  // for the rest, so this one call renders events from both switches. The asymmetry is the
  // design -- a non-file load can never raise a file event.
  S("tbl_ldval queued=");
  D(txn.NumPendingEvents);
  S("\n");
  StrNCpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
  CFE_TBL_SendTableLoadFileEvents(&txn, "/ram/load.tbl", &hdr);
  // AND THE BASIC-ONLY PATH, which cannot render a file event at all.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  StrNCpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
  CFE_TBL_TxnAddEvent(&txn, CFE_TBL_LOAD_IN_PROGRESS_ERR_EID, CFE_TBL_ERR_LOAD_IN_PROGRESS, 0);
  CFE_TBL_TxnAddEvent(&txn, CFE_TBL_FILE_LOADED_INF_EID, 0, 0);
  CFE_TBL_SendTableLoadEvents(&txn);
  // --- CFE_TBL_TxnLoadFromFile, the whole path ----------------------------------------
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  StrNCpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
  fs_open_fail = 1;
  st = CFE_TBL_TxnLoadFromFile(&txn, "/ram/load.tbl");
  S("tbl_ldfile noopen=");
  D(st);
  S("\n");
  fs_open_fail = 0;
  tbl_mkfile("LD_APP.Tbl", 0, 32, 32, CFE_FS_FILE_CONTENT_ID, CFE_FS_SubType_TBL_IMG, 0x90);
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  StrNCpy(txn.AppNameBuffer, "LD_APP", CFE_MISSION_MAX_API_LEN - 1);
  CFE_TBL_RegRecClearLoadInProgress(rr);
  CFE_TBL_ValidateLoadRequest(&txn, CFE_TBL_SRC_FILE);
  st = CFE_TBL_TxnLoadFromFile(&txn, "/ram/load.tbl");
  lb = CFE_TBL_GetLoadInProgressBuffer(rr);
  S("tbl_ldfile ok=");
  D(st);
  S(" first=");
  if (lb == NULL)
    Hx2b(0);
  else
    Hx2b(CFE_TBL_LoadBuffGetReadPointer(lb)[0]);
  S(" src=");
  if (lb == NULL)
    S("?");
  else
    S(lb->DataSource);
  S(" secs=");
  if (lb == NULL) {
    Hx4(0);
    Hx4(0);
  } else {
    Hx4(lb->FileTime.Seconds >> 16);
    Hx4(lb->FileTime.Seconds);
  }
  S("\n");
  // --- CFE_TBL_TxnLoadFromSourceAddr, both shapes -------------------------------------
  // A NORMAL table COPIES the caller's memory; a DUMP-ONLY table keeps the caller's POINTER,
  // which is what makes a user-defined-address dump-only table possible at all. `alloc=0` below
  // is how CFE_TBL_LoadBuffIsAllocated tells the two apart.
  MemSet(tbl_probe_mem2, 0xE1, sizeof(tbl_probe_mem2));
  rr->Config.DumpOnly = FALSE;
  st = CFE_TBL_TxnLoadFromSourceAddr(&txn, tbl_probe_mem2);
  // `addrpfx` rather than the string: CFE_TBL_TxnLoadFromSourceAddr formats the caller's
  // POINTER into DataSource, so only the fixed prefix can be compared between the halves.
  S("tbl_ldaddr copy=");
  D(st);
  S(" first=");
  Hx2b(CFE_TBL_LoadBuffGetReadPointer(lb)[0]);
  S(" isext=");
  D(CFE_TBL_LoadBuffGetReadPointer(lb) == tbl_probe_mem2);
  S(" addrpfx=");
  D(StrNCmp(lb->DataSource, "Addr 0x", 7) == 0);
  S("\n");
  rr->Config.DumpOnly = TRUE;
  st = CFE_TBL_TxnLoadFromSourceAddr(&txn, tbl_probe_mem2);
  S("tbl_ldaddr external=");
  D(st);
  S(" isext=");
  D(CFE_TBL_LoadBuffGetReadPointer(lb) == tbl_probe_mem2);
  S(" alloc=");
  D(CFE_TBL_LoadBuffIsAllocated(lb));
  S("\n");
  rr->Config.DumpOnly = FALSE;
  CFE_TBL_LoadBuffSetAllocatedBlock(lb, tbl_probe_mem, sizeof(tbl_probe_mem));
  // AND THE DataSource MUST BE PUT BACK TO A FIXED STRING. CFE_TBL_TxnLoadFromSourceAddr wrote
  // "Addr 0x%08lX" of the caller's POINTER into it, and CFE_TBL_LoadFinish's success event
  // prints the last file loaded -- so the transcript grew a line reading
  // `Successfully loaded 'LD_APP.Tbl' from 'Addr 0x10458D610'`, an arm64 address that the RISC-V
  // half has no way to match. The `addrpfx` field above exists for the same reason. A pointer
  // value in a differential transcript is always a defect in the exercise.
  StrNCpy(lb->DataSource, "/ram/load.tbl", OS_MAX_PATH_LEN - 1);
  // --- CFE_TBL_LoadFinish, three answers, and CFE_TBL_AbortLoad -----------------------
  // A FAILING status DISCARDS the working buffer and nothing else happens.
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  st = CFE_TBL_LoadFinish(&txn, CFE_TBL_ERR_ACCESS);
  S("tbl_ldfinish failed=");
  D(st);
  S(" lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr));
  S("\n");
  // THE FIRST SUCCESS IS A **DEBUG** EVENT, every later one INFORMATION -- NASA's reason is that
  // every table in the system loads once at startup and INFORMATION would flood the log at the
  // worst possible moment.
  //
  // AND THE WAY THAT SHOWS IN THE TRANSCRIPT IS AN ABSENCE: this driver's EVS filters DEBUG, so
  // the FIRST load produces NO event line and the second produces
  // `35: Successfully loaded ...`. One line for two calls is the assertion. The status is 0 both
  // times and cannot tell them apart.
  rr->Status.ActiveBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  rr->Buffers[0].IsValid = TRUE;
  rr->Buffers[0].ActivateReq = TRUE;
  st = CFE_TBL_LoadFinish(&txn, CFE_SUCCESS);
  S("tbl_ldfinish first=");
  D(st);
  S(" loaded=");
  D(CFE_TBL_RegRecIsTableLoaded(rr));
  S(" last=");
  D(CFE_ResourceId_Equal(CFE_TBL_Global.LastTblUpdated, CFE_TBL_RegRecGetID(rr)));
  S("\n");
  // and again, now that the table HAS been loaded once
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  rr->Buffers[0].IsValid = TRUE;
  rr->Buffers[0].ActivateReq = TRUE;
  st = CFE_TBL_LoadFinish(&txn, CFE_SUCCESS);
  S("tbl_ldfinish again=");
  D(st);
  S("\n");
  // AND THE ABORT, which is the only function here that sends its event directly rather than
  // queueing it on the transaction.
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  CFE_TBL_AbortLoad(rr);
  S("tbl_ldabort lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr));
  S("\n");
}
// --- cfe_tbl_dump.c -------------------------------------------------------------
// A DUMP IS THREE PHASES SEPARATED IN TIME, and the exercise follows them in order because
// each one's output is the next one's input:
//
//   1. ALLOCATE   a dump control block, recording WHICH buffer is to be dumped
//   2. SNAPSHOT   copy that buffer into a shared load buffer and stamp the time
//   3. WRITE      the background task writes the snapshot to a file and frees both
//
// The split exists so a dump never blocks the caller on file I/O, and so a DUMP-ONLY table's
// snapshot happens when its OWNER says so rather than when the command arrives. Phase 2
// therefore has two shapes, and both are driven below.
U0 TblDumpExercise()
{
  CFE_TBL_TxnState_t txn;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_DumpControl_t *dc;
  U32 dcid;
  I32 st;
  I64 k;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B50;
  CFE_TBL_Global.WorkBufMutex = 0x7B51;
  CFE_TBL_Global.LastDumpCtrlBlockId = CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - 1);
  CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + CFE_TBL_TOTAL_LOAD_BUFFS - 1);
  CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
  // Registry[9]'s own buffer pair is serial 4 + 2*9 = 22 and 23.
  rr = &CFE_TBL_Global.Registry[9];
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 9));
  StrNCpy(rr->Config.Name, "DMP_APP.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  rr->Config.Size = 32;
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  CFE_TBL_HandleLinkInit(&rr->AccessList);
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 22), CFE_TBL_RegRecGetID(rr));
  MemSet(tbl_probe_mem, 0xC3, sizeof(tbl_probe_mem));
  CFE_TBL_LoadBuffSetAllocatedBlock(&rr->Buffers[0], tbl_probe_mem, sizeof(tbl_probe_mem));
  rr->Buffers[0].ContentSize = 32;
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  // --- PHASE 1: ALLOCATE, and the four ways it answers -------------------------------
  // Into locals first: three of the four arms add a deferred event, and the events are sent at
  // the end of this block rather than per call -- which is the whole point of the transaction's
  // event list.
  txn.RegRecPtr = NULL;
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
  S("tbl_dmpalloc notbl=");
  D(st);
  S(" undef=");
  D(!CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
  S("\n");
  txn.RegRecPtr = rr;
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, 99);
  S("tbl_dmpalloc badsel=");
  D(st);
  S(" undef=");
  D(!CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
  S("\n");
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
  dc = CFE_TBL_LocateDumpCtrlByID(dcid);
  S("tbl_dmpalloc ok=");
  D(st);
  S(" valid=");
  D(CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
  S(" used=");
  D(dc != NULL && CFE_TBL_DumpCtrlBlockIsUsed(dc));
  S(" src=");
  D(dc != NULL && CFE_ResourceId_Equal(dc->SourceBuffId, CFE_TBL_LoadBufferGetID(&rr->Buffers[0])));
  S(" name=");
  if (dc == NULL)
    S("?");
  else
    S(dc->TableName);
  S("\n");
  // a dump is pending on this table now, so the next request on it is refused
  rr->DumpControlId = dcid;
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
  S("tbl_dmpalloc pending=");
  D(st);
  S("\n");
  rr->DumpControlId = CFE_TBL_DUMPCTRLID_UNDEFINED;
  // EXHAUSTION: every block used, so the allocator has nowhere to put the next one
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    CFE_TBL_DumpCtrlBlockSetUsed(&CFE_TBL_Global.DumpControlBlocks[k], CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + k));
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
  S("tbl_dmpalloc toomany=");
  D(st);
  S(" undef=");
  D(!CFE_TBL_DUMPCTRLID_IS_VALID(dcid));
  S("\n");
  // SEND WHAT THE FOUR CALLS QUEUED. Three events come out of five queued, and the two that do
  // not are the point: CFE_TBL_SendDumpEventHelper's switch has no case for
  // CFE_TBL_NO_SUCH_TABLE_ERR_EID, so it leaves EventString empty, returns FALSE, and declines
  // to own that event. That is the mechanism which lets each operation register its own helper.
  CFE_TBL_SendTableDumpEvents(&txn, "/ram/dump.tbl", CFE_TBL_RegRecGetName(rr));
  // AND THE TWO DEFAULTS, which only show with a fresh transaction carrying one event. NASA
  // refuses to leave either field blank: NULL becomes "[none]" and "[unknown]".
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  CFE_TBL_TxnAddEvent(&txn, CFE_TBL_DUMP_PENDING_ERR_EID, CFE_TBL_INFO_DUMP_PENDING, 0);
  CFE_TBL_SendTableDumpEvents(&txn, NULL, NULL);
  // --- PHASE 2: SNAPSHOT, both shapes --------------------------------------------------
  // Reset the blocks the exhaustion test above filled, and give the shared load buffers real
  // memory so AcquireGlobalLoadBuff has something to hand out.
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++) {
    CFE_TBL_DumpCtrlBlockSetFree(&CFE_TBL_Global.DumpControlBlocks[k]);
    CFE_TBL_LoadBuffSetAllocatedBlock(&CFE_TBL_Global.LoadBuffs[k], tbl_probe_mem2, sizeof(tbl_probe_mem2));
  }
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
  // A NORMAL TABLE SNAPSHOTS IMMEDIATELY: Prepare calls ExecuteDumpSnapshot itself, so the
  // state comes back PERFORMED and the source id is CLEARED -- the dump no longer refers to the
  // table's buffer, it owns a copy. `first=c3` is the proof the DATA moved, not just the state.
  st = CFE_TBL_PrepareDumpSnapshotBuffer(&txn, dcid, "/ram/dump.tbl");
  dc = CFE_TBL_LocateDumpCtrlByID(dcid);
  S("tbl_dmpprep normal=");
  D(st);
  S(" state=");
  D(dc->State);
  S(" srccleared=");
  D(!CFE_TBL_LOADBUFFID_IS_VALID(dc->SourceBuffId));
  S(" buf=");
  D(dc->DumpBufferPtr != NULL);
  S(" enc=");
  D(dc->EncodeStatus);
  S(" first=");
  if (dc->DumpBufferPtr == NULL)
    Hx2b(0);
  else
    Hx2b(CFE_TBL_LoadBuffGetReadPointer(dc->DumpBufferPtr)[0]);
  S("\n");
  // A DUMP-ONLY TABLE DOES NOT: the state is PENDING and the REGISTRY RECORD remembers the
  // block, because the snapshot has to wait for the owner to call CFE_TBL_Modified.
  CFE_TBL_DumpCtrlBlockSetFree(dc);
  rr->Config.DumpOnly = TRUE;
  st = CFE_TBL_AllocateDumpCtrlBlock(&txn, &dcid, CFE_TBL_BufferSelect_ACTIVE);
  st = CFE_TBL_PrepareDumpSnapshotBuffer(&txn, dcid, "/ram/dump.tbl");
  dc = CFE_TBL_LocateDumpCtrlByID(dcid);
  S("tbl_dmpprep dumponly=");
  D(st);
  S(" state=");
  D(dc->State);
  S(" remembered=");
  D(CFE_ResourceId_Equal(rr->DumpControlId, dcid));
  S("\n");
  rr->Config.DumpOnly = FALSE;
  rr->DumpControlId = CFE_TBL_DUMPCTRLID_UNDEFINED;
  // AND THE NO-BUFFER ARM, which is why AcquireGlobalLoadBuff's NULL return matters: mark every
  // shared buffer used and there is nothing to snapshot into.
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    CFE_TBL_LoadBuffSetUsed(&CFE_TBL_Global.LoadBuffs[k], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + k), CFE_TBL_RegRecGetID(rr));
  st = CFE_TBL_PrepareDumpSnapshotBuffer(&txn, dcid, "/ram/dump.tbl");
  S("tbl_dmpprep nobuf=");
  D(st);
  S("\n");
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++)
    CFE_TBL_LoadBuffSetFree(&CFE_TBL_Global.LoadBuffs[k]);
  // AND THE SNAPSHOT ON ITS OWN, with a source id that does not match anything.
  dc = &CFE_TBL_Global.DumpControlBlocks[0];
  dc->SourceBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + CFE_TBL_TOTAL_LOAD_BUFFS);
  st = CFE_TBL_ExecuteDumpSnapshot(dc);
  S("tbl_dmpsnap badsrc=");
  D(st);
  S("\n");
  // --- PHASE 3: WRITE, five outcomes --------------------------------------------------
  // Set the block up as the background task expects to find it: used, PERFORMED, with a dump
  // buffer holding the snapshot.
  MemSet(dc, 0, sizeof(CFE_TBL_DumpControl_t));
  CFE_TBL_DumpCtrlBlockSetUsed(dc, CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE));
  dc->State = CFE_TBL_DUMP_PERFORMED;
  dc->EncodeStatus = CFE_SUCCESS;
  dc->DumpBufferPtr = &CFE_TBL_Global.LoadBuffs[0];
  CFE_TBL_LoadBuffSetAllocatedBlock(dc->DumpBufferPtr, tbl_probe_mem2, sizeof(tbl_probe_mem2));
  dc->DumpBufferPtr->ContentSize = 32;
  StrNCpy(dc->DumpBufferPtr->DataSource, "/ram/dump.tbl", OS_MAX_PATH_LEN - 1);
  StrNCpy(dc->TableName, "DMP_APP.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  // THE FILE ALREADY EXISTS, which is the only thing the read-only open at the top of
  // WriteSnapshotToFile is for: it picks OVERWRITE_DUMP over WRITE_DUMP.
  fs_len = 0;
  fs_pos = 0;
  fs_wr_left = -1;
  st = CFE_TBL_WriteSnapshotToFile(dc);
  S("tbl_dmpwrite overwrite=");
  D(st);
  S(" bytes=");
  D(fs_len);
  S(" last=");
  S(CFE_TBL_Global.HkPacket.Payload.LastFileDumped);
  S("\n");
  // WHAT THE TABLE HEADER ACTUALLY CONTAINS, and the two fields deliberately NOT printed.
  //
  // The table header starts at byte 64, after CFE_FS_Header_t, and is
  // Reserved/Offset/NumBytes/TableName -- big-endian, because CFE_TBL_EncodeHeadersToFile
  // byte-swaps it on a little-endian host to keep the cFE file standard. So NumBytes is at 72
  // and reads 00000020 for this 32-byte table.
  //
  // Reserved (64..67) AND Offset (68..71) ARE NOT ASSERTED, BECAUSE THEY ARE GARBAGE. NASA's
  // `memset(&FileHeader, 0, sizeof(CFE_TBL_File_Hdr_t))` clears 52 bytes from the FRONT of a
  // CombinedFileHdr_t, which is entirely inside Std -- none of it reaches Tbl -- and nothing
  // assigns those two fields afterwards. They go into the file as whatever was on the stack. A
  // probe printed them and the two halves disagreed on the first run:
  //
  //     C   tbl_dmphdr resv=00000001 off=8d30a184
  //     HC  tbl_dmphdr resv=00000000 off=00000000
  //
  // That is upstream behaviour, not a translation defect, and it matters for what comes next:
  // CFE_TBL_ReadHeaders reads Offset and CFE_TBL_LoadFromFile decides where the data lands from
  // it. So a load.c exercise must build its header EXPLICITLY rather than round-tripping one
  // through a dump, or it will diff for a reason two sources away.
  S("tbl_dmphdr numbytes=");
  Hx2b(fs_data[72]);
  Hx2b(fs_data[73]);
  Hx2b(fs_data[74]);
  Hx2b(fs_data[75]);
  S(" name=");
  S(&fs_data[76]);
  S("\n");
  // THE FILE DOES NOT EXIST YET -- and this branch was unreachable until the stub learned to
  // say so; see the note on fs_noexist at OS_OpenCreate.
  fs_noexist = 1;
  fs_len = 0;
  fs_pos = 0;
  st = CFE_TBL_WriteSnapshotToFile(dc);
  S("tbl_dmpwrite first=");
  D(st);
  S(" bytes=");
  D(fs_len);
  S("\n");
  fs_noexist = 0;
  // THE CREATE FAILS
  fs_open_fail = 1;
  st = CFE_TBL_WriteSnapshotToFile(dc);
  S("tbl_dmpwrite nocreate=");
  D(st);
  S("\n");
  fs_open_fail = 0;
  // THE THREE WRITES ARE 64 + 52 + 32 BYTES, and each budget below stops one of them. The
  // numbers are not guessed: a full successful dump reports bytes=148 above, and the image is
  // 32, so the two headers are 116 and CFE_FS_Header_t is 64.
  //
  // A FIRST DRAFT USED 150 FOR THE IMAGE CASE and the write SUCCEEDED -- the line read
  // `shortimg=0 bytes=148`, byte-identical to the overwrite line above it, which is the
  // two-assertions-agreeing tell. The middle case, a cFE header that goes out and a TABLE
  // header that does not, was not in that draft at all, so CFE_TBL_WRITE_TBL_HDR_ERR_EID had no
  // way to appear.
  fs_wr_left = 130;
  // both headers out (116), image truncated to 14
  fs_len = 0;
  fs_pos = 0;
  st = CFE_TBL_WriteSnapshotToFile(dc);
  S("tbl_dmpwrite shortimg=");
  D(st);
  S(" bytes=");
  D(fs_len);
  S("\n");
  fs_wr_left = 80;
  // cFE header out (64), table header truncated to 16
  fs_len = 0;
  fs_pos = 0;
  st = CFE_TBL_WriteSnapshotToFile(dc);
  S("tbl_dmpwrite shorttblhdr=");
  D(st);
  S(" bytes=");
  D(fs_len);
  S("\n");
  fs_wr_left = 10;
  // not even the cFE header
  fs_len = 0;
  fs_pos = 0;
  st = CFE_TBL_WriteSnapshotToFile(dc);
  S("tbl_dmpwrite shorthdr=");
  D(st);
  S(" bytes=");
  D(fs_len);
  S("\n");
  fs_wr_left = -1;
  // --- AND THE BACKGROUND SWEEP, which is phase 3's only real caller ------------------
  // Two blocks: one with a good snapshot, which gets written, and one whose encode FAILED, which
  // gets an event instead. Both must be freed either way -- that is the whole reason NASA's
  // comment says to "just accept the error and move on to eventually free the dump ctrl buffer".
  MemSet(&CFE_TBL_Global.DumpControlBlocks, 0, sizeof(CFE_TBL_DumpControl_t) * CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS);
  for (k = 0; k < 2; k++) {
    dc = &CFE_TBL_Global.DumpControlBlocks[k];
    CFE_TBL_DumpCtrlBlockSetUsed(dc, CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + k));
    dc->State = CFE_TBL_DUMP_PERFORMED;
    if (k == 0)
      dc->EncodeStatus = CFE_SUCCESS;
    else
      dc->EncodeStatus = CFE_TBL_ERR_ACCESS;
    dc->DumpBufferPtr = &CFE_TBL_Global.LoadBuffs[k];
    CFE_TBL_LoadBuffSetUsed(dc->DumpBufferPtr, CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + k), CFE_TBL_RegRecGetID(rr));
    CFE_TBL_LoadBuffSetAllocatedBlock(dc->DumpBufferPtr, tbl_probe_mem2, sizeof(tbl_probe_mem2));
    dc->DumpBufferPtr->ContentSize = 32;
    StrNCpy(dc->DumpBufferPtr->DataSource, "/ram/bg.tbl", OS_MAX_PATH_LEN - 1);
    StrNCpy(dc->TableName, "DMP_APP.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  }
  // a third block is PENDING, not PERFORMED, and must be left completely alone
  dc = &CFE_TBL_Global.DumpControlBlocks[2];
  CFE_TBL_DumpCtrlBlockSetUsed(dc, CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + 2));
  dc->State = CFE_TBL_DUMP_PENDING;
  fs_len = 0;
  fs_pos = 0;
  CFE_TBL_TableDumpExecuteBackground();
  S("tbl_dmpbg free0=");
  D(!CFE_TBL_DumpCtrlBlockIsUsed(&CFE_TBL_Global.DumpControlBlocks[0]));
  S(" free1=");
  D(!CFE_TBL_DumpCtrlBlockIsUsed(&CFE_TBL_Global.DumpControlBlocks[1]));
  S(" pendingkept=");
  D(CFE_TBL_DumpCtrlBlockIsUsed(&CFE_TBL_Global.DumpControlBlocks[2]));
  S(" buf0free=");
  D(!CFE_TBL_LoadBuffIsUsed(&CFE_TBL_Global.LoadBuffs[0]));
  S(" buf1free=");
  D(!CFE_TBL_LoadBuffIsUsed(&CFE_TBL_Global.LoadBuffs[1]));
  S(" bytes=");
  D(fs_len);
  S("\n");
}
// --- cfe_tbl_task_cmds.c and cfe_tbl_dispatch.c ---------------------------------
// THE GROUND COMMANDS, DRIVEN AS MESSAGES. Everything above this point called tbl's functions
// directly; these go in through CFE_TBL_TaskPipe the way an uplinked packet does, so the
// dispatcher's table, its length check and its three-way error are all under test at once.
//
// THE LENGTH SWEEP IS THE STRONGEST ASSERTION ABOUT THE TABLE. Sending every command code at a
// size no command has makes each row report its own ExpectedLength in the event text -- so one
// loop pins all ten rows' sizeof, and a handler wired to the wrong payload type shows up as a
// different number rather than as silence.
//
// AND EVERY HANDLER RETURNS CFE_SUCCESS, so the only observable is the COUNTERS and the events.
// CFE_TBL_TranslateCmdProcRet is the convention: a failed command is an incremented error
// counter, not a failed return.
//
// NASA'S ANONYMOUS LOCAL UNION IS NAMED HERE, as every other one in this port has had to be.
union TblCmdUnion
{
  CFE_SB_Buffer Buf;
  CFE_TBL_NoopCmd_t Noop;
  CFE_TBL_LoadCmd_t Load;
  CFE_TBL_DumpCmd_t Dump;
  CFE_TBL_ValidateCmd_t Validate;
  CFE_TBL_ActivateCmd_t Activate;
  CFE_TBL_DumpRegistryCmd_t DumpReg;
  CFE_TBL_SendRegistryCmd_t SendReg;
  CFE_TBL_DeleteCDSCmd_t DelCDS;
  CFE_TBL_AbortLoadCmd_t Abort;
};

U0 TblCmdExercise()
{
  TblCmdUnion cmd;
  CFE_TBL_RegistryRec_t *rr;
  I16 h1;
  U8 *buf;
  I64 bufsz;
  Bool eof;
  I64 k;
  I64 regidx;
  I64 txmark;
  // The real startup sequence again, then one registered table to command at.
  es_set_ctx(1);
  CFE_TBL_EarlyInit();
  CFE_TBL_InitData();
  CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
  tbl_val_rc = CFE_SUCCESS;
  CFE_TBL_Register(&h1, "Cmd", 32, CFE_TBL_OPT_DEFAULT, &TblValStub);
  rr = CFE_TBL_LocateRegRecByName("CFE_EVS.Cmd");
  // The INDEX the long way round -- HolyC scales pointer arithmetic by the pointee, so both
  // halves divide an explicit byte difference. Printed because three assertions below depend on
  // it and it is NOT zero: CFE_TBL_InitData seeds LastRegId to the BASE.
  regidx = ((U8 *)rr - (U8 *)CFE_TBL_Global.Registry) / sizeof(CFE_TBL_RegistryRec_t);
  S("tbl_cmdsetup reg=");
  D(h1);
  S(" rr=");
  D(rr != NULL);
  S(" idx=");
  D(regidx);
  S("\n");
  // --- THE THREE-WAY ERROR ------------------------------------------------------------
  MemSet(&cmd, 0, sizeof(TblCmdUnion));
  CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_NoopCmd_t));
  // UNKNOWN MESSAGE ID: the event fires and the error counter does NOT move, which is the
  // asymmetry worth pinning -- a message that was never ours should not count against us.
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(0x1FFF));
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_pipe badmid cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // BAD COMMAND CODE on the right id: this one DOES count.
  CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, 99);
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_pipe badcc cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // --- THE LENGTH SWEEP, which pins every row's ExpectedLength ------------------------
  // A size no tbl command has. The smallest payload here is the 40-byte table name, so a bare
  // header plus one byte cannot collide -- and if it ever did, the command would RUN instead of
  // erroring and the count below would drop.
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_NoopCmd_t) + 1);
  for (k = 0; k <= 9; k++) {
    CFE_MSG_SetFcnCode(&cmd.Buf.Msg, k);
    CFE_TBL_TaskPipe(&cmd.Buf);
  }
  // BOTH COUNTERS STAY AT ZERO AND THAT IS CORRECT: the wrong-length arm raises its event and
  // deliberately does NOT count, because a handler that never ran cannot have counted anything.
  // So this line asserts almost nothing on its own -- THE ASSERTION IS THE TEN `EVS 52` LINES
  // ABOVE IT, each naming a different `Expected =`, which is what pins all ten rows' sizeof. A
  // handler wired to the wrong payload type changes a number there.
  S("tbl_pipe alllen cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // --- NOOP AND RESET, the two counter conventions ------------------------------------
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_NoopCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_NOOP_CC);
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd noop cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // RESET IS THE ONLY DONT_INC_CTR HANDLER: it zeroes the counters and must not then leave one
  // at 1. Both come back 0, which is the whole assertion.
  CFE_TBL_Global.CommandCounter = 7;
  CFE_TBL_Global.CommandErrorCounter = 3;
  CFE_TBL_Global.ValidationCounter = 5;
  CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_ResetCountersCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_RESET_COUNTERS_CC);
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd reset cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S(" val=");
  D(CFE_TBL_Global.ValidationCounter);
  S("\n");
  // --- THE HOUSEKEEPING REQUEST, which is a MSG_MSGTYPE row (no command code) ---------
  // It packs the HK payload, transmits it, and -- the part worth knowing -- is the only caller
  // of CFE_TBL_TableDumpExecuteBackground in flight code.
  CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_SEND_HK_MID));
  CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_SendHkCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, 0);
  // sb_tx_reset/sb_tx_since are helpers the C half has and this one does not, so the mark is
  // taken inline from the same counter: a transmit with no subscribers bumps it, which is what
  // makes it a transmit witness in this driver.
  txmark = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd hk tx=");
  D(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - txmark);
  S(" tables=");
  D(CFE_TBL_Global.HkPacket.Payload.NumTables);
  S(" pending=");
  D(CFE_TBL_Global.HkPacket.Payload.NumLoadPending);
  S(" freebufs=");
  D(CFE_TBL_Global.HkPacket.Payload.NumFreeSharedBufs);
  S("\n");
  // --- CFE_TBL_GetHkData's VALIDATION HARVEST -----------------------------------------
  // A completed validation result is reported ONCE and then freed, so the counters move and the
  // block is released. A failing result bumps FailedValCounter instead.
  CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0], CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
  CFE_TBL_Global.ValidationResults[0].State = CFE_TBL_VALIDATION_PERFORMED;
  CFE_TBL_Global.ValidationResults[0].Result = 0;
  CFE_TBL_Global.ValidationResults[0].CrcOfTable = 0xABCD;
  CFE_TBL_Global.ValidationResults[0].BufferSelect = CFE_TBL_BufferSelect_ACTIVE;
  StrNCpy(CFE_TBL_Global.ValidationResults[0].TableName, "CFE_EVS.Cmd", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.SuccessValCounter = 0;
  CFE_TBL_Global.FailedValCounter = 0;
  CFE_TBL_Global.ValidationCounter = 0;
  CFE_TBL_GetHkData();
  S("tbl_hk valpass crc=");
  Hx4(CFE_TBL_Global.HkPacket.Payload.LastValCrc);
  S(" succ=");
  D(CFE_TBL_Global.SuccessValCounter);
  S(" fail=");
  D(CFE_TBL_Global.FailedValCounter);
  S(" valcnt=");
  D(CFE_TBL_Global.ValidationCounter);
  S(" active=");
  D(CFE_TBL_Global.HkPacket.Payload.ActiveBuffer);
  S(" name=");
  S(CFE_TBL_Global.HkPacket.Payload.LastValTableName);
  S(" freed=");
  D(!CFE_TBL_ValidationResultIsUsed(&CFE_TBL_Global.ValidationResults[0]));
  S("\n");
  // and a FAILING one takes the other counter
  CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[0], CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE));
  CFE_TBL_Global.ValidationResults[0].State = CFE_TBL_VALIDATION_PERFORMED;
  CFE_TBL_Global.ValidationResults[0].Result = -5;
  CFE_TBL_GetHkData();
  S("tbl_hk valfail succ=");
  D(CFE_TBL_Global.SuccessValCounter);
  S(" fail=");
  D(CFE_TBL_Global.FailedValCounter);
  S(" status=");
  D(CFE_TBL_Global.HkPacket.Payload.LastValStatus);
  S("\n");
  // --- SEND REGISTRY: the command only sets a flag; HK does the packing ----------------
  MemSet(&cmd, 0, sizeof(TblCmdUnion));
  CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_SendRegistryCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_SEND_REGISTRY_CC);
  StrNCpy(cmd.SendReg.Payload.TableName, "CFE_EVS.Cmd", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd sendreg cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S(" armed=");
  D(CFE_TBL_REGID_IS_VALID(CFE_TBL_Global.HkTlmTblRegId));
  S("\n");
  // the NEXT housekeeping request packs it, sends it and CLEARS the id so it goes once
  CFE_MSG_SetMsgId(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_SEND_HK_MID));
  CFE_MSG_SetSize(&cmd.Buf.Msg, sizeof(CFE_TBL_SendHkCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, 0);
  txmark = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd regtlm tx=");
  D(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - txmark);
  S(" cleared=");
  D(!CFE_TBL_REGID_IS_VALID(CFE_TBL_Global.HkTlmTblRegId));
  S(" size=");
  D(CFE_TBL_Global.TblRegPacket.Payload.Size);
  S(" name=");
  S(CFE_TBL_Global.TblRegPacket.Payload.Name);
  S(" owner=");
  S(CFE_TBL_Global.TblRegPacket.Payload.OwnerAppName);
  S("\n");
  // and a name that is not there is refused
  MemSet(&cmd, 0, sizeof(TblCmdUnion));
  CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_SendRegistryCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_SEND_REGISTRY_CC);
  StrNCpy(cmd.SendReg.Payload.TableName, "NO.SUCH", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd sendreg_missing ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // --- ABORT LOAD, and the DUMP-ONLY exclusion that is NOT defensive ------------------
  MemSet(&cmd, 0, sizeof(TblCmdUnion));
  CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_AbortLoadCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_ABORT_LOAD_CC);
  StrNCpy(cmd.Abort.Payload.TableName, "CFE_EVS.Cmd", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  // no load in progress: refused
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_RegRecClearLoadInProgress(rr);
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd abort_noload cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // a load in progress on a DUMP-ONLY table is also refused -- NextBufferId holds the DUMP
  // buffer there, so aborting would abort a dump.
  //
  // A REAL BUFFER ID, resolved from the record's own index. The first draft passed
  // CFE_TBL_LoadBufferGetID(&rr->Buffers[0]) straight back, and after EarlyInit that buffer has
  // no id -- so IsLoadInProgress stayed FALSE, the dump-only arm was never entered, and
  // `abort_dumponly` reported the "No load started" refusal while `lip=0` quietly agreed with
  // it. Registry[k]'s own pair is serial 4 + 2k.
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 4 + 2 * regidx), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[0]));
  rr->Config.DumpOnly = TRUE;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd abort_dumponly cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S(" lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr));
  S("\n");
  // and a real load IS aborted
  rr->Config.DumpOnly = FALSE;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd abort_ok cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr));
  S("\n");
  // a name that is not there
  StrNCpy(cmd.Abort.Payload.TableName, "NO.SUCH", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd abort_missing ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // --- DELETE CDS: three arms, and the first is the interlock -------------------------
  // All three report ec=1 -- one error each -- and what distinguishes them is the EVENT, not
  // the counter. The three EVS lines above each of these are the assertion.
  MemSet(&cmd, 0, sizeof(TblCmdUnion));
  CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_DeleteCDSCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_DELETE_CDS_CC);
  // STILL REGISTERED: refused, because a registered table means its owner is still running and
  // the CDS is the only copy of a critical table's contents.
  StrNCpy(cmd.DelCDS.Payload.TableName, "CFE_EVS.Cmd", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd delcds_registered ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // NOT IN THE CRITICAL REGISTRY either: a different refusal
  StrNCpy(cmd.DelCDS.Payload.TableName, "GONE.Tbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd delcds_notcrit ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // IN the critical registry but with no CDS of that name
  StrNCpy(CFE_TBL_Global.CritReg[3].Name, "GONE.Tbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd delcds_nocds ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // --- THE REGISTRY DUMP: a background job, and its getter ----------------------------
  // The COMMAND only queues a request.
  MemSet(&cmd, 0, sizeof(TblCmdUnion));
  CFE_MSG_Init(&cmd.Buf.Msg, CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID), sizeof(CFE_TBL_DumpRegistryCmd_t));
  CFE_MSG_SetFcnCode(&cmd.Buf.Msg, CFE_TBL_DUMP_REGISTRY_CC);
  StrNCpy(cmd.DumpReg.Payload.DumpFilename, "/ram/reg.log", CFE_MISSION_MAX_PATH_LEN - 1);
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd dumpreg cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S(" pending=");
  D(CFE_FS_BackgroundFileDumpIsPending(&CFE_TBL_Global.RegDumpState.FileWrite));
  S(" existed=");
  D(CFE_TBL_Global.RegDumpState.FileExisted);
  S(" file=");
  S(CFE_TBL_Global.RegDumpState.FileWrite.FileName);
  S("\n");
  // A SECOND REQUEST WHILE ONE IS PENDING IS SILENTLY DROPPED -- no event, and the error
  // counter still moves because CmdProcRet was never changed from its pessimistic default.
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_TaskPipe(&cmd.Buf);
  S("tbl_cmd dumpreg_again cc=");
  D(CFE_TBL_Global.CommandCounter);
  S(" ec=");
  D(CFE_TBL_Global.CommandErrorCounter);
  S("\n");
  // THE GETTER, called the way the background writer calls it, ON THE RECORD THAT EXISTS --
  // resolved rather than assumed. The first draft asked for record 0 and got an EMPTY slot --
  // CFE_TBL_InitData seeds LastRegId to the BASE, so the allocator does not start at index 0 --
  // which printed `sz=0 name=` and then made the unowned case below read a name left over from
  // a different record.
  buf = NULL;
  bufsz = 0;
  eof = CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, regidx, &buf, &bufsz);
  S("tbl_reggetter used eof=");
  D(eof);
  S(" sz=");
  D(bufsz);
  S(" name=");
  S(CFE_TBL_Global.RegDumpState.DumpRecord.Name);
  S(" owner=");
  S(CFE_TBL_Global.RegDumpState.DumpRecord.OwnerAppName);
  S(" users=");
  D(CFE_TBL_Global.RegDumpState.DumpRecord.NumUsers);
  S("\n");
  // AN EMPTY SLOT writes nothing and does NOT end the job -- the return value means "last
  // record", never "wrote something", which is how a sparse registry dumps without holes.
  buf = NULL;
  bufsz = 1;
  eof = CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, regidx + 1, &buf, &bufsz);
  S("tbl_reggetter empty eof=");
  D(eof);
  S(" sz=");
  D(bufsz);
  S(" null=");
  D(buf == NULL);
  S("\n");
  eof = CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1, &buf, &bufsz);
  S("tbl_reggetter last eof=");
  D(eof);
  S("\n");
  // AN UNOWNED entry reports "--UNOWNED--" rather than asking ES for a name it has not got
  rr->OwnerAppId = CFE_TBL_NOT_OWNED;
  CFE_TBL_DumpRegistryGetter(&CFE_TBL_Global.RegDumpState, regidx, &buf, &bufsz);
  S("tbl_reggetter unowned owner=");
  S(CFE_TBL_Global.RegDumpState.DumpRecord.OwnerAppName);
  S("\n");
  // THE EVENT HANDLER's four cases plus the default it ignores. It runs in the ES background
  // task, which is why it uses SendEventWithAppID -- in that context the "current app" is ES and
  // the event would otherwise be misattributed.
  StrNCpy(CFE_TBL_Global.RegDumpState.FileWrite.FileName, "/ram/reg.log", OS_MAX_PATH_LEN - 1);
  CFE_TBL_Global.RegDumpState.FileExisted = FALSE;
  CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_COMPLETE, CFE_SUCCESS, 7, 0, 128);
  CFE_TBL_Global.RegDumpState.FileExisted = TRUE;
  CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_COMPLETE, CFE_SUCCESS, 7, 0, 128);
  CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR, -1, 3, 0, 0);
  CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR, -2, 0, 0, 0);
  CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_CREATE_ERROR, -3, 0, 0, 0);
  // the default arm: an event the switch does not name produces NOTHING, which is the absence
  // the next line asserts by being the only output
  CFE_TBL_DumpRegistryEventHandler(&CFE_TBL_Global.RegDumpState, CFE_FS_FileWriteEvent_MAX, 0, 0, 0, 0);
  S("tbl_regevents done\n");
  es_ctx_init();
}
// --- cfe_tbl_task.c -------------------------------------------------------------
// THREE FUNCTIONS, AND THE OBJECT TABLE IS FINALLY HONEST. cfe_tbl_objtab.c names
// CFE_TBL_EarlyInit, CFE_TBL_TaskMain and CFE_TBL_CleanUpApp; two of the three now run in this
// transcript and the third has a real body. The objtab exercise's claim -- three distinct
// non-NULL addresses -- was true of three stubs too.
//
// POISON-FIRST WORKS HERE, unlike CFE_TBL_EarlyInit. CFE_TBL_InitData does NOT zero the global;
// it writes eight specific places in it. So filling those places with a recognisable value
// first turns every assertion below from "it is zero" (which a memset would also give) into
// "it CHANGED to the right thing".
U0 TblTaskExercise()
{
  CFE_SB_MsgId mid_hk, mid_reg, mid_notify;
  I64 x0;
  // --- CFE_TBL_InitData, with the five id spaces poisoned first ------------------------
  CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(0xBAD01);
  CFE_TBL_Global.LastValidationResultId = CFE_ResourceId_FromInteger(0xBAD02);
  CFE_TBL_Global.LastDumpCtrlBlockId = CFE_ResourceId_FromInteger(0xBAD03);
  CFE_TBL_Global.LastRegId = CFE_ResourceId_FromInteger(0xBAD04);
  CFE_TBL_Global.LastHandle = CFE_ResourceId_FromInteger(0xBAD05);
  CFE_TBL_Global.TableTaskAppId = CFE_ResourceId_FromInteger(0xBAD06);
  MemSet(&CFE_TBL_Global.HkPacket, 0x5A, sizeof(CFE_TBL_HousekeepingTlm_t));
  MemSet(&CFE_TBL_Global.TblRegPacket, 0x5A, sizeof(CFE_TBL_TableRegistryTlm_t));
  MemSet(&CFE_TBL_Global.NotifyMsg, 0x5A, sizeof(CFE_TBL_NotifyCmd_t));
  CFE_TBL_InitData();
  S("tbl_initdata lb=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastLoadBuffId) == CFE_TBL_LOADBUFFID_BASE);
  S(" vr=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastValidationResultId) == CFE_TBL_VALRESULTID_BASE);
  S(" dc=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastDumpCtrlBlockId) == CFE_TBL_DUMPCTRLID_BASE);
  S(" reg=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastRegId) == CFE_TBL_REGID_BASE);
  S(" hnd=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_Global.LastHandle) == CFE_TBL_HANDLE_BASE);
  S(" app=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_Global.TableTaskAppId));
  S("\n");
  // THE THIRD HEADER IS INITIALISED TO AN INVALID MSG ID ON PURPOSE -- NASA's comment says
  // "Message ID is set when sent, so OK as 0 here". So `notify=0` is the right answer and is
  // not a failure to initialise: the 0x5A poison above is what makes that readable.
  CFE_MSG_GetMsgId(&CFE_TBL_Global.HkPacket.TelemetryHeader.Msg, &mid_hk);
  CFE_MSG_GetMsgId(&CFE_TBL_Global.TblRegPacket.TelemetryHeader.Msg, &mid_reg);
  CFE_MSG_GetMsgId(&CFE_TBL_Global.NotifyMsg.CommandHeader.Msg, &mid_notify);
  S("tbl_initdata hk=0x");
  Hx4(CFE_SB_MsgIdToValue(mid_hk));
  S(" reg=0x");
  Hx4(CFE_SB_MsgIdToValue(mid_reg));
  S(" notify=0x");
  Hx4(CFE_SB_MsgIdToValue(mid_notify));
  S("\n");
  // --- CFE_TBL_TaskInit AND CFE_TBL_TaskMain, both paths ------------------------------
  // TaskInit IS NOT CALLED DIRECTLY, and that is a deliberate retreat. SB and EVS are both
  // 100% gated, so CFE_EVS_Register, CFE_SB_CreatePipe and the two CFE_SB_Subscribe calls are
  // real code -- a pipe really is created and two real subscriptions are made. But the pipe
  // NAME is a process-wide resource, so a direct call leaves TBL_CMD_PIPE taken and every
  // later TaskMain fails at CreatePipe.
  //
  // THE OBVIOUS FIX DOES NOT WORK AND THE REASON IS WORTH RECORDING. Calling
  // CFE_SB_DeletePipe on the pipe TaskInit made SEGFAULTS the C reference, in
  // CFE_SB_GetDestPtr reading address 0x809 -- which is a MsgId being walked as a pointer.
  // The same CFE_SB_DeletePipe works earlier in this transcript (see api_del), so something
  // about the route state TaskInit's two subscriptions leave behind is different. Not chased
  // here, and NOT diagnosed: recorded as an observation so the next person does not spend the
  // afternoon this cost. It also means the first draft's claim -- that the crash came from the
  // POWER ON RESET below -- was wrong; moving the reset last did not help, and the lldb
  // backtrace is what settled it.
  //
  // So TaskMain creates the pipe itself, both times, and the two runs take the two paths.
  CFE_ES_Global.SystemState = CFE_ES_SystemState_CORE_READY;
  CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
  // FIRST RUN: TBL_CMD_PIPE is free, so TaskMain's TaskInit runs all five steps -- the
  // "cFE TBL Initialized" event above this line is the fifth. Then the loop exits when
  // CFE_SB_ReceiveBuffer fails, because OS_QueueGet returns OS_QUEUE_EMPTY on an empty pipe:
  // one pass, `Error reading cmd pipe`, one CFE_ES_ExitApp(CORE_APP_RUNTIME_ERROR).
  // taskpipe=0 because there was no message to dispatch.
  // `cmds=` REPLACED `taskpipe=`, and it is weaker. The old field counted calls inside the
  // DRIVER's own CFE_TBL_TaskPipe; the real dispatcher is gated now, so what can be observed is
  // its EFFECT -- the two command counters it moves. Neither run dispatches anything, so both
  // read 0, which is the same thing the old field said and no more. Kept because it is the real
  // state rather than a stub's, and because the SYSLOG lines are what actually separate the two
  // paths; see the note below.
  CFE_TBL_Global.CmdPipe = CFE_SB_INVALID_PIPE;
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  x0 = es_taskexits;
  CFE_TBL_TaskMain();
  S("tbl_taskmain_loop exits=");
  D(es_taskexits - x0);
  S(" cmds=");
  D(CFE_TBL_Global.CommandCounter + CFE_TBL_Global.CommandErrorCounter);
  S(" pipe=");
  D(CFE_ResourceId_IsDefined(CFE_TBL_Global.CmdPipe));
  S(" req=");
  D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
  S("\n");
  // SECOND RUN: the name is taken now, so TaskInit fails at CreatePipe, TaskMain takes the
  // `Application Init Failed` branch and calls CFE_ES_ExitApp(CORE_APP_INIT_ERROR) -- which
  // drives the real CFE_ES_ResetCFE and a POWER ON RESET, `psp_restart 2` in the transcript.
  // It goes LAST in the block for that reason.
  //
  // TWO ExitApp CALLS COME OUT OF ONE TaskMain here, and that is NASA's code behaving exactly
  // as written. CFE_ES_ExitApp "will not return" in flight; in this driver it does, so control
  // falls past the `if`, the loop is never entered because Status is already an error, and the
  // bottom CFE_ES_ExitApp(CORE_APP_RUNTIME_ERROR) runs too. The driver IS the "except under
  // unit test" case NASA's own comment names.
  //
  // AND THE TWO PRINTF LINES ARE IDENTICAL, which is worth stating rather than leaving for
  // someone to notice. `exits=1 taskpipe=0 req=9` both times: es_taskexits counts OS_TaskExit,
  // and the extra ExitApp in this run does a PROCESSOR RESET instead of reaching OS_TaskExit,
  // so the count does not move. (A third draft claimed `exits=2` here; the transcript says
  // otherwise.) What separates the two paths is the SYSLOG, which is compared just as
  // strictly: `Error reading cmd pipe` and one ExitApp line above against `Application Init
  // Failed`, a POWER ON RESET and three ExitApp lines here. The printf fields are the weaker
  // half of this assertion and are kept only because they say both runs TERMINATED and neither
  // dispatched a message.
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  x0 = es_taskexits;
  CFE_TBL_TaskMain();
  S("tbl_taskmain_initfail exits=");
  D(es_taskexits - x0);
  S(" cmds=");
  D(CFE_TBL_Global.CommandCounter + CFE_TBL_Global.CommandErrorCounter);
  S(" req=");
  D(CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest);
  S("\n");
  CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
  CFE_ES_Global.SystemState = CFE_ES_SystemState_UNDEFINED;
}
// --- cfe_tbl_internal.c: CFE_TBL_EarlyInit -------------------------------------
// THE OBJECT TABLE'S FIRST HOOK, and until this block it was only an ADDRESS. cfe_tbl_objtab.c
// has held &CFE_TBL_EarlyInit since it was gated, and all the objtab exercise asserts is that
// the three function pointers are distinct and non-NULL -- which passed just as well when
// EarlyInit was a two-line stub. check_in_blob says it has an address; nothing said it runs.
//
// IT IS CHEAP NOW BECAUSE ES IS 100% GATED. CFE_ES_PoolCreate, CFE_ES_RegisterCDSEx,
// CFE_ES_RestoreFromCDS and CFE_ES_CopyToCDS are all real code in this driver, so the 512 KiB
// partition really is carved up and the critical-table registry really does go into the CDS.
// The only thing standing in is OS_MutSemCreate, which the driver counts -- and counting is
// exactly the right stand-in for it, because what EarlyInit does with a mutex is create it and
// store the id.
U32 tbl_early_pool1;
U32 tbl_early_pool2;
U0 TblEarlyInitExercise()
{
  I32 st;
  I64 c0;
  I64 k, allocated, distinct;
  // WHAT THIS BLOCK CANNOT ASSERT, said first because the first draft asserted it anyway.
  // CFE_RESOURCEID_UNDEFINED is 0 in this configuration and the SIMPLE resourceid mode makes
  // every wrapper the identity -- so `HkTlmTblRegId is undefined`, `all 128 registry records
  // are free`, `all 32 critical slots hold the BAD handle` and `the deepest access list is
  // detached` ALL READ THE SAME whether EarlyInit ran or not, because its own memset produces
  // them. The usual fix -- poison the memory first, as cfe_tbl_regrec.c's own comment
  // describes -- is unavailable here precisely because EarlyInit begins by zeroing the whole
  // 592 KiB global itself. Six fields were cut from this exercise for that reason.
  //
  // So what is left is everything NON-zero that EarlyInit produces: two mutex ids, a pool
  // handle, four shared load buffers of the right size at four DIFFERENT addresses, a CDS
  // handle -- and the one thing that genuinely distinguishes the recovery branch, below.
  //
  // FIRST RUN: nothing in the CDS under this name yet, so RegisterCDSEx succeeds and the
  // else-branch saves the initial registry with CopyToCDS.
  c0 = fs_mut_create;
  st = CFE_TBL_EarlyInit();
  allocated = 0;
  distinct = 1;
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; k++) {
    if (CFE_TBL_LoadBuffIsAllocated(&CFE_TBL_Global.LoadBuffs[k]) && CFE_TBL_Global.LoadBuffs[k].AllocationSize == CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE)
      ++allocated;
    if (k > 0 && CFE_TBL_LoadBuffGetReadPointer(&CFE_TBL_Global.LoadBuffs[k]) == CFE_TBL_LoadBuffGetReadPointer(&CFE_TBL_Global.LoadBuffs[k - 1]))
      distinct = 0;
  }
  tbl_early_pool1 = CFE_TBL_Global.Buf.PoolHdl;
  // creates=3 is NOT a mistake: EarlyInit makes two, and CFE_ES_PoolCreate makes the pool's own
  // mutex. The third one is the witness that the pool was really created rather than its handle
  // merely being set. And reg/wrk differ, which is what the per-create id above is for -- see
  // the note on OS_MutSemCreate.
  S("tbl_early rc=");
  D(st);
  S(" creates=");
  D(fs_mut_create - c0);
  S(" reg=");
  D(CFE_TBL_Global.RegistryMutex);
  S(" wrk=");
  D(CFE_TBL_Global.WorkBufMutex);
  S(" pool=");
  D(CFE_ResourceId_IsDefined(CFE_TBL_Global.Buf.PoolHdl));
  S(" bufs=");
  D(allocated);
  S(" distinct=");
  D(distinct);
  S("\n");
  // THE RECOVERY BRANCH, WITNESSED. Both CDS paths return CFE_SUCCESS -- NASA's words,
  // "failure to support critical tables is not a good enough reason to exit the cFE on start
  // up" -- so the return value cannot tell them apart and the first draft printed two nearly
  // identical lines while claiming they took different paths.
  //
  // What distinguishes them is CONTENT. Write a recognisable handle into the critical registry
  // and push it to the CDS; the next EarlyInit finds the entry already there, takes the
  // CFE_ES_CDS_ALREADY_EXISTS arm, and RestoreFromCDS brings that handle back AFTER the loop
  // that set every slot to the BAD handle. So `crit5=0x5151` is proof the restore happened, and
  // `critbad=31` is proof it overwrote the loop's work rather than being merged with it.
  CFE_TBL_Global.CritReg[5].CDSHandle = CFE_ResourceId_FromInteger(0x5151);
  CFE_ES_CopyToCDS(CFE_TBL_Global.CritRegHandle, CFE_TBL_Global.CritReg);
  c0 = fs_mut_create;
  st = CFE_TBL_EarlyInit();
  allocated = 0;
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES; k++)
    if (CFE_ResourceId_Equal(CFE_TBL_Global.CritReg[k].CDSHandle, CFE_ES_CDS_BAD_HANDLE))
      ++allocated;
  tbl_early_pool2 = CFE_TBL_Global.Buf.PoolHdl;
  S("tbl_early recovered rc=");
  D(st);
  S(" creates=");
  D(fs_mut_create - c0);
  S(" crit5=0x");
  Hx4(CFE_ResourceId_ToInteger(CFE_TBL_Global.CritReg[5].CDSHandle));
  S(" critbad=");
  D(allocated);
  S("\n");
  // THIRD RUN: the mutex refuses, which is the ONE failure EarlyInit does not survive -- it
  // returns before the pool is ever created. Both mutex calls are on that path, so a count of
  // ONE create is the witness that it stopped at the first, and pool=0 that it never got as far
  // as CFE_ES_PoolCreate.
  fs_mut_create_rc = -1;
  c0 = fs_mut_create;
  st = CFE_TBL_EarlyInit();
  S("tbl_early nomutex rc=");
  D(st);
  S(" creates=");
  D(fs_mut_create - c0);
  S(" pool=");
  D(CFE_ResourceId_IsDefined(CFE_TBL_Global.Buf.PoolHdl));
  S("\n");
  fs_mut_create_rc = OS_SUCCESS;
  // AND HAND THE POOL RECORDS BACK, which this block has to do because
  // CFE_PLATFORM_ES_MAX_MEMORY_POOLS IS **TEN** and the two successful EarlyInits above each
  // took one. Without this, the next exercise to call CFE_ES_PoolCreate gets nothing:
  // TblApiExercise did, and every one of its nineteen assertions came back
  // CFE_TBL_ERR_INVALID_HANDLE because SetupTableBuffers could not allocate -- one repeated
  // number for a whole block, with `CFE_ES_GetPoolBuf: Err:Bad handle(0x00000000)` the only
  // clue. A FIXED-SIZE RESOURCE TABLE SHARED BETWEEN EXERCISES has to be given back.
  //
  // The deletes come last so they cannot disturb the measurements above, and the status is
  // printed rather than discarded -- `pooldel=0 0` being zeros is what says the records are
  // actually free again.
  S("tbl_early pooldel=");
  D(CFE_ES_PoolDelete(tbl_early_pool1));
  S(" ");
  D(CFE_ES_PoolDelete(tbl_early_pool2));
  S("\n");
}
// --- cfe_tbl_registry.c ---------------------------------------------------------
// SIX OF THE ELEVEN STEPS, the ones nothing else reaches. TxnLockRegistry, TxnUnlockRegistry,
// TxnRemoveAccessLink and TxnFindRegByName are already driven -- by tbl_adtxn's take/give
// counts, by tbl_adrel_owner/other, and by tbl_findreg through CFE_TBL_FindTableInRegistry.
//
// Each step is given its own setup rather than being chained, because a chain would make one
// wrong answer cascade into five unreadable ones.
U0 TblRegistryExercise()
{
  CFE_TBL_TxnState_t txn;
  CFE_TBL_TableConfig_t cfg;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_AccessDescriptor_t *ad;
  CFE_TBL_LoadBuff_t *lb;
  U8 *tp;
  I32 st;
  I64 k;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B40;
  // THE FOUR VALIDATORS IN ORDER, and the order is load-bearing: options are decoded before
  // the size is checked, because the size limit depends on the double-buffered flag that
  // ValidateTableOptions writes into this same config object.
  //
  // Each call into a local first -- three of the four arms emit a syslog line.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  StrNCpy(txn.AppNameBuffer, "REG_APP", CFE_MISSION_MAX_API_LEN - 1);
  MemSet(&cfg, 0, sizeof(CFE_TBL_TableConfig_t));
  st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "", 0, 64, NULL);
  S("tbl_cfg badname=");
  D(st);
  S("\n");
  MemSet(&cfg, 0, sizeof(CFE_TBL_TableConfig_t));
  st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "Tbl", 0x0003, 64, NULL);
  S("tbl_cfg badopt=");
  D(st);
  S("\n");
  MemSet(&cfg, 0, sizeof(CFE_TBL_TableConfig_t));
  st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "Tbl", 0x0000, 0, NULL);
  S("tbl_cfg badsize=");
  D(st);
  S("\n");
  MemSet(&cfg, 0, sizeof(CFE_TBL_TableConfig_t));
  st = CFE_TBL_TxnCheckConfig(&txn, &cfg, "Tbl", 0x0001, 2048, &TblValStub);
  S("tbl_cfg good=");
  D(st);
  S(" name=");
  S(cfg.Name);
  S(" size=");
  D(cfg.Size);
  S(" dbl=");
  D(cfg.DoubleBuffered);
  S(" fn=");
  D(cfg.ValidationFuncPtr != NULL);
  S("\n");
  // FOUR PENDING STATES, AND ONLY ONE IS EVER REPORTED. The tests run validation, then update,
  // then dump -- so a table with a pending validation AND a pending dump answers
  // VALIDATION_PENDING and the caller hears about the dump next time round. The last line sets
  // BOTH to prove the priority rather than assuming it.
  //
  // THE BUFFER IDS HAVE TO BE REAL, and the serials are not free to choose. Four shared buffers
  // come first, so Registry[k]'s own pair is serial 4 + 2k -- Registry[4] is 12 and 13. A
  // zeroed buffer has an UNDEFINED id, CFE_TBL_LoadBufferGetID hands that straight back, and
  // the first draft of this block set LoadInProgress to UNDEFINED: the update arm was never
  // entered and `tbl_status update` printed the DUMP value, identical to the line above it.
  // Two assertions reading the same number is the tell.
  rr = &CFE_TBL_Global.Registry[4];
  MemSet(rr, 0, sizeof(CFE_TBL_RegistryRec_t));
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 4));
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  st = CFE_TBL_TxnGetTableStatus(&txn);
  S("tbl_status clean=");
  D(st);
  S("\n");
  rr->DumpControlId = CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE + 1);
  st = CFE_TBL_TxnGetTableStatus(&txn);
  S("tbl_status dump=");
  D(st);
  S("\n");
  // AND IT HAS TO BE Buffers[0], SERIAL 12, FOR A SINGLE-BUFFERED TABLE. The first fix put
  // serial 13 into Buffers[1] -- the right serial for that slot -- and the arm STILL was not
  // entered, because CFE_TBL_LocateLoadBufferByID forces `Idx = 0` when the parent table is
  // not double-buffered. So serial 13 resolves to Buffers[0], whose id is undefined, IsMatch
  // fails, and nothing is pending. A buffer id must agree with the table's SHAPE, not just
  // with the slot it was written into.
  lb = &rr->Buffers[0];
  CFE_TBL_LoadBuffSetUsed(lb, CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 12), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(lb));
  lb->IsValid = TRUE;
  lb->ActivateReq = TRUE;
  st = CFE_TBL_TxnGetTableStatus(&txn);
  S("tbl_status update=");
  D(st);
  S("\n");
  rr->PendingValId = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 1);
  st = CFE_TBL_TxnGetTableStatus(&txn);
  S("tbl_status valfirst=");
  D(st);
  S("\n");
  // ALLOCATION, and the lock count is the thing worth watching: Allocate takes the registry
  // itself, so lockcnt must be back to zero on return.
  //
  // LastRegId HAS TO NAME A REAL ID FIRST. CFE_TBL_GetNextRegId searches forward from it, and
  // a zeroed global means it searches forward from the undefined id and finds nothing -- so the
  // FIRST allocation came back ERR_REGISTRY_FULL, the same value as the exhaustion case below,
  // and the pair asserted nothing. Seeding it with the LAST id wraps the search to index 0.
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B40;
  CFE_TBL_Global.LastRegId = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1);
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  st = CFE_TBL_TxnAllocateRegistryEntry(&txn);
  S("tbl_alloc rc=");
  D(st);
  S(" id=");
  D(CFE_TBL_TxnRegIdAsULong(&txn));
  S(" nonnull=");
  D(txn.RegRecPtr != NULL);
  S(" used=");
  D(txn.RegRecPtr != NULL && CFE_TBL_RegRecIsUsed(txn.RegRecPtr));
  S(" lockcnt=");
  D(txn.RegLockCount);
  S("\n");
  // EXHAUSTION. Every slot marked used, so the next allocation must refuse AND must leave the
  // transaction's own fields cleared rather than half-filled.
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_NUM_TABLES; k++)
    CFE_TBL_RegRecSetUsed(&CFE_TBL_Global.Registry[k], CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + k));
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  st = CFE_TBL_TxnAllocateRegistryEntry(&txn);
  S("tbl_alloc full=");
  D(st);
  S(" null=");
  D(txn.RegRecPtr == NULL);
  S(" undef=");
  D(!CFE_TBL_REGID_IS_VALID(txn.RegId));
  S("\n");
  // THE THREE WAYS A DUPLICATE REGISTRATION ENDS, plus the not-a-duplicate path that falls
  // through to allocation. Re-registering YOUR OWN table at the SAME size is a supported no-op
  // that returns a WARNING, which is the only path here that is not an error.
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B40;
  CFE_TBL_Global.LastRegId = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1);
  CFE_TBL_Global.LastHandle = CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + CFE_PLATFORM_TBL_MAX_NUM_HANDLES - 1);
  rr = &CFE_TBL_Global.Registry[6];
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 6));
  StrNCpy(rr->Config.Name, "REG_APP.Dup", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  rr->Config.Size = 512;
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.AppId = CFE_ResourceId_FromInteger(0x1111);
  st = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.Dup", 1024);
  S("tbl_dup diffsize=");
  D(st);
  S("\n");
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.AppId = CFE_ResourceId_FromInteger(0x2222);
  st = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.Dup", 512);
  S("tbl_dup notowned=");
  D(st);
  S("\n");
  // the accepted path needs an access descriptor this app already holds, because
  // CFE_TBL_FindAccessDescriptorForSelf is what turns "same table, same size" into a warning
  // rather than an error
  ad = &CFE_TBL_Global.Handles[9];
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 9));
  ad->AppId = CFE_ResourceId_FromInteger(0x1111);
  ad->RegIndex = CFE_TBL_RegRecGetID(rr);
  CFE_TBL_HandleListInsertLink(rr, ad);
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.AppId = CFE_ResourceId_FromInteger(0x1111);
  st = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.Dup", 512);
  S("tbl_dup warn=");
  D(st);
  S(" handle=");
  D(CFE_TBL_TxnHandleAsULong(&txn));
  S("\n");
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.AppId = CFE_ResourceId_FromInteger(0x1111);
  st = CFE_TBL_TxnCheckDuplicateRegistration(&txn, "REG_APP.New", 512);
  S("tbl_dup fresh=");
  D(st);
  S(" allocated=");
  D(txn.RegRecPtr != NULL);
  S("\n");
  // CONNECTING A DESCRIPTOR, and the three answers for Updated. A loaded load/dump table says
  // updated; a loaded DUMP-ONLY table does not (there is nothing for an accessor to be notified
  // about); and a record whose id no longer matches the transaction is not linked at all -- that
  // arm is not dead code, it is the re-allocated-under-us case.
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B40;
  rr = &CFE_TBL_Global.Registry[7];
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 7));
  CFE_TBL_HandleLinkInit(&rr->AccessList);
  // "loaded" means ActiveBufferId IS DEFINED, so the buffer needs its id before it can be made
  // active -- Registry[7]'s pair is serial 4 + 2*7 = 18 and 19. Without this the table reads
  // never-loaded and `upd=0` below passes while testing the wrong branch.
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 18), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  ad = &CFE_TBL_Global.Handles[11];
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 11));
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.AccDescPtr = ad;
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  txn.AppId = CFE_ResourceId_FromInteger(0x3333);
  CFE_TBL_TxnConnectAccessDescriptor(&txn);
  S("tbl_connect upd=");
  D(ad->Updated);
  S(" linked=");
  D(CFE_TBL_LocateAccDescByHandle(rr->AccessList.Next) == ad);
  S(" app=");
  D(CFE_ResourceId_ToInteger(ad->AppId));
  S(" lockcnt=");
  D(txn.RegLockCount);
  S("\n");
  rr->Config.DumpOnly = TRUE;
  CFE_TBL_HandleLinkInit(&rr->AccessList);
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 11));
  CFE_TBL_TxnConnectAccessDescriptor(&txn);
  S("tbl_connect dumponly upd=");
  D(ad->Updated);
  S(" linked=");
  D(CFE_TBL_LocateAccDescByHandle(rr->AccessList.Next) == ad);
  S("\n");
  rr->Config.DumpOnly = FALSE;
  CFE_TBL_HandleLinkInit(&rr->AccessList);
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 11));
  txn.RegId = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 99);
  CFE_TBL_TxnConnectAccessDescriptor(&txn);
  S("tbl_connect mismatch upd=");
  D(ad->Updated);
  S(" linked=");
  D(CFE_TBL_LocateAccDescByHandle(rr->AccessList.Next) == ad);
  S("\n");
  // AND THE POINTER ITSELF. Three answers, and the third is the one the whole lock scheme
  // exists for: handing the caller the ACTIVE buffer's address while recording in the
  // descriptor WHICH blob is being read, so nothing overwrites it until the address is
  // released. Into locals first -- the unowned arm emits a syslog line.
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B40;
  rr = &CFE_TBL_Global.Registry[8];
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 8));
  ad = &CFE_TBL_Global.Handles[12];
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 12));
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.AccDescPtr = ad;
  txn.RegRecPtr = rr;
  txn.RegId = CFE_TBL_RegRecGetID(rr);
  txn.Handle = CFE_TBL_AccDescGetHandle(ad);
  tp = 1;
  st = CFE_TBL_TxnGetTableAddress(&txn, &tp);
  S("tbl_addr unowned=");
  D(st);
  S(" null=");
  D(tp == NULL);
  S("\n");
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x4444);
  tp = 1;
  st = CFE_TBL_TxnGetTableAddress(&txn, &tp);
  S("tbl_addr neverloaded=");
  D(st);
  S(" null=");
  D(tp == NULL);
  S("\n");
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 20), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_LoadBuffSetAllocatedBlock(&rr->Buffers[0], tbl_probe_mem, sizeof(tbl_probe_mem));
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  ad->Updated = TRUE;
  tp = NULL;
  st = CFE_TBL_TxnGetTableAddress(&txn, &tp);
  S("tbl_addr loaded=");
  D(st);
  S(" isbuf0=");
  D(tp == tbl_probe_mem);
  S(" locked=");
  D(ad->LockFlag);
  S(" bufmatch=");
  D(CFE_ResourceId_Equal(ad->BufferIndex, CFE_TBL_LoadBufferGetID(&rr->Buffers[0])));
  S(" updcleared=");
  D(!ad->Updated);
  S("\n");
}
// --- cfe_tbl_internal.c ---------------------------------------------------------
// FOUR UNRELATED CONCERNS, and this exercise takes them in the order they are cheapest to
// observe: the three validators that decide whether a registration is legal at all, the name
// marker, the doubly-linked access list, and the validation-request handoff.
//
// CFE_TBL_HandleListGetSafeLink, GetNext and GetPrev CANNOT BE CALLED FROM THE C HALF. The
// last two are `static inline` INSIDE cfe_tbl_internal.c and the first has no declaration in
// any header -- so the oracle reaches the safe-link trick only through InsertLink, RemoveLink
// and ForeachAccessDescriptor, and this half does the same even though its own translation
// has them at file scope. Both ends of the list are still covered, because removing the FRONT
// element and removing the LAST one are exactly the two cases the head-node pointer exists to
// erase.
//
// (Note for the gates: those three are source-file static inlines, not header inlines, so
// check_header_inlines does not look at them. check_coverage always did -- and
// check_signatures did NOT, until this commit: its return-type pattern allowed two words
// before the name, and `static inline CFE_TBL_AccessDescriptor_t *` is three, so GetNext and
// GetPrev were never compared to NASA's. 30 of 32 was the number, and it printed as a pass.)
// The chain printer. It follows Next from the head using the gated
// CFE_TBL_LocateAccDescByHandle, which answers NULL for the undefined id and so terminates the
// walk; the bound of 8 is there so a mistake in the list surgery prints a wrong answer instead
// of hanging. The count beside it comes from NASA's own
// ForeachAccessDescriptor/CountAccessDescHelper pair, so the two walks check each other.
U0 tbl_chain(CFE_TBL_RegistryRec_t *rr, U8 *tag)
{
  CFE_TBL_AccessDescriptor_t *p;
  CFE_TBL_HandleLink_t *lnk;
  U32 descs;
  I64 guard;
  S(tag);
  S(" head=");
  D(CFE_ResourceId_ToInteger(rr->AccessList.Next));
  S(" chain=");
  lnk = &rr->AccessList;
  for (guard = 0; guard < 8; guard++) {
    p = CFE_TBL_LocateAccDescByHandle(lnk->Next);
    if (p == NULL)
      break;
    D(CFE_ResourceId_ToInteger(CFE_TBL_AccDescGetHandle(p)));
    S(",");
    lnk = &p->Link;
  }
  descs = 0;
  CFE_TBL_ForeachAccessDescriptor(rr, &CFE_TBL_CountAccessDescHelper, &descs);
  S(" n=");
  D(descs);
  S("\n");
}

U0 TblInternalExercise()
{
  CFE_TBL_TableConfig_t cfg;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_AccessDescriptor_t *adp[3];
  CFE_TBL_CritRegRec_t *crp;
  CFE_TBL_ValidationResult_t *vrp;
  U32 vid;
  U32 found;
  U16 opts[9];
  U8 nbuf[20];
  U8 longname[CFE_MISSION_TBL_MAX_NAME_LENGTH + 4];
  I64 k;
  I32 st;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.RegistryMutex = 0x7B30;
  // THE NINE OPTION WORDS THAT COVER EVERY BRANCH. Filled one at a time rather than with an
  // initialiser list because HolyC has no aggregate initialiser and the two halves are kept
  // reading the same. 0x6 is the interesting one: USR_DEF_ADDR INCLUDES the dump-only bit, so
  // asking for a user-defined address implies dump-only -- which means the
  // `else if (UserDefAddr)` arm can only be reached by 0x4, a caller who set the user-defined
  // mask bit WITHOUT the dump-only bit. That word is in the table for exactly that reason.
  //   0x0  single, load/dump, not user-def, not critical    accepted
  //   0x1  double-buffered                                   accepted
  //   0x2  dump-only                                         accepted
  //   0x3  dump-only AND double                              REFUSED
  //   0x4  user-def mask without dump-only                    REFUSED, and only reachable so
  //   0x6  USR_DEF_ADDR proper: user-def and dump-only        accepted
  //   0x8  critical                                          accepted
  //   0x9  critical and double                               accepted
  //   0xA  critical and dump-only                            REFUSED
  opts[0] = 0x0000;
  opts[1] = 0x0001;
  opts[2] = 0x0002;
  opts[3] = 0x0003;
  opts[4] = 0x0004;
  opts[5] = 0x0006;
  opts[6] = 0x0008;
  opts[7] = 0x0009;
  opts[8] = 0x000A;
  for (k = 0; k < 9; k++) {
    MemSet(&cfg, 0, sizeof(cfg));
    st = CFE_TBL_ValidateTableOptions(&cfg, opts[k]);
    S("tbl_opt ");
    Hx4(opts[k]);
    S(" dbl=");
    D(cfg.DoubleBuffered);
    S(" dmp=");
    D(cfg.DumpOnly);
    S(" usr=");
    D(cfg.UserDefAddr);
    S(" crit=");
    D(cfg.Critical);
    S(" st=");
    D(st);
    S("\n");
  }
  // SIZE, and the limit that depends on a flag the caller set in the SAME config object. Both
  // platform limits are 16384 in this configuration, so the single/double distinction cannot
  // be seen in the numbers -- what is still worth asserting is that Size is written on success
  // and left alone on failure.
  MemSet(&cfg, 0, sizeof(cfg));
  st = CFE_TBL_ValidateTableSize(&cfg, 0);
  S("tbl_size zero=");
  D(st);
  S(" sz=");
  D(cfg.Size);
  S("\n");
  st = CFE_TBL_ValidateTableSize(&cfg, CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE);
  S("tbl_size limit=");
  D(st);
  S(" sz=");
  D(cfg.Size);
  S("\n");
  st = CFE_TBL_ValidateTableSize(&cfg, CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE + 1);
  S("tbl_size over=");
  D(st);
  S(" sz=");
  D(cfg.Size);
  S("\n");
  cfg.DoubleBuffered = TRUE;
  st = CFE_TBL_ValidateTableSize(&cfg, CFE_PLATFORM_TBL_MAX_DBL_TABLE_SIZE);
  S("tbl_size dbllimit=");
  D(st);
  S(" sz=");
  D(cfg.Size);
  S("\n");
  // THE NAME, which is both too-long and empty in one test: MemChr over MAX_NAME_LENGTH
  // finding no NUL means the name does not terminate within the limit. A name of exactly 16
  // characters is already too long for that reason -- the NUL sits at index 16.
  MemSet(&cfg, 0, sizeof(cfg));
  st = CFE_TBL_ValidateTableName(&cfg, "", "APP");
  S("tbl_name empty=");
  D(st);
  S("\n");
  MemSet(longname, 'X', sizeof(longname));
  longname[CFE_MISSION_TBL_MAX_NAME_LENGTH] = '\0';
  st = CFE_TBL_ValidateTableName(&cfg, longname, "APP");
  S("tbl_name exactly16=");
  D(st);
  S("\n");
  longname[CFE_MISSION_TBL_MAX_NAME_LENGTH - 1] = '\0';
  st = CFE_TBL_ValidateTableName(&cfg, longname, "APP");
  S("tbl_name fifteen=");
  D(st);
  S(" full=");
  S(cfg.Name);
  S("\n");
  st = CFE_TBL_ValidateTableName(&cfg, "Tbl", "APP");
  S("tbl_name good=");
  D(st);
  S(" full=");
  S(cfg.Name);
  S("\n");
  // and the truncation arm: 15 + 1 + 15 + 1 fits 40, so the app name has to be long enough to
  // push the joined name past CFE_TBL_MAX_FULL_NAME_LEN by itself
  st = CFE_TBL_ValidateTableName(&cfg, longname, "AN_APPLICATION_WITH_A_VERY_LONG_NAME");
  S("tbl_name trunc=");
  D(st);
  S(" full=");
  S(cfg.Name);
  S("\n");
  // THE MODIFIED MARKER, both arms. The second name leaves no room for three more characters,
  // so the marker overwrites the tail rather than being dropped.
  MemSet(nbuf, 0, sizeof(nbuf));
  StrCpy(nbuf, "APP.Tbl");
  CFE_TBL_MarkNameAsModified(nbuf, sizeof(nbuf));
  S("tbl_mark short=");
  S(nbuf);
  S("\n");
  MemSet(nbuf, 'Y', sizeof(nbuf));
  nbuf[sizeof(nbuf) - 1] = '\0';
  CFE_TBL_MarkNameAsModified(nbuf, sizeof(nbuf));
  S("tbl_mark maximal=");
  S(nbuf);
  S(" len=");
  D(StrLen(nbuf));
  S("\n");
  // THE ACCESS LIST. Three descriptors, each inserted at the front, so the chain comes out
  // reversed -- and then the three removals take the MIDDLE, the FRONT and the LAST element,
  // which is every case the head-node trick exists to flatten.
  rr = &CFE_TBL_Global.Registry[3];
  CFE_TBL_HandleLinkInit(&rr->AccessList);
  for (k = 0; k < 3; k++) {
    adp[k] = &CFE_TBL_Global.Handles[10 + k];
    CFE_TBL_InitAccessDescriptor(adp[k]);
    CFE_TBL_AccDescSetUsed(adp[k], CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 10 + k));
  }
  tbl_chain(rr, "tbl_list empty");
  for (k = 0; k < 3; k++)
    CFE_TBL_HandleListInsertLink(rr, adp[k]);
  tbl_chain(rr, "tbl_list three");
  // READ `attached=0 1 1` CAREFULLY -- it is not a mistake and not a bug to fix. The first
  // descriptor inserted is the LAST in the chain, so its Next is undefined, and
  // CFE_TBL_HandleLinkIsAttached tests Next ALONE. So the tail of a non-empty list reports
  // itself detached, which is narrower than what cfe_tbl_handlelink.h promises of it ("true if
  // the passed-in link is attached to another list node, indicating it is part of a list").
  // The translation keeps NASA's one-line body; this transcript line is what pins the
  // behaviour so a later "tidy-up" of either half shows up as a diff.
  S("tbl_list attached=");
  D(CFE_TBL_HandleLinkIsAttached(&adp[0]->Link));
  S(" ");
  D(CFE_TBL_HandleLinkIsAttached(&adp[1]->Link));
  S(" ");
  D(CFE_TBL_HandleLinkIsAttached(&adp[2]->Link));
  S("\n");
  CFE_TBL_HandleListRemoveLink(rr, adp[1]);
  tbl_chain(rr, "tbl_list -middle");
  S("tbl_list midattached=");
  D(CFE_TBL_HandleLinkIsAttached(&adp[1]->Link));
  S("\n");
  CFE_TBL_HandleListRemoveLink(rr, adp[2]);
  tbl_chain(rr, "tbl_list -front");
  CFE_TBL_HandleListRemoveLink(rr, adp[0]);
  tbl_chain(rr, "tbl_list -last");
  // AND THE WALK THAT MARKS, which is the only reason the list exists: one table updated,
  // every app holding a handle to it told so. Two descriptors are back on the list and a third
  // is deliberately left OFF it, so the count is a claim about the list and not about the
  // handle array.
  CFE_TBL_HandleListInsertLink(rr, adp[0]);
  CFE_TBL_HandleListInsertLink(rr, adp[1]);
  adp[0]->Updated = FALSE;
  adp[1]->Updated = FALSE;
  adp[2]->Updated = FALSE;
  CFE_TBL_NotifyTblUsersOfUpdate(rr);
  S("tbl_notify upd=");
  D(adp[0]->Updated);
  S(" ");
  D(adp[1]->Updated);
  S(" off=");
  D(adp[2]->Updated);
  S("\n");
  // THE VALIDATION-REQUEST HANDOFF, which is a flag and an id in one word. Three cases: an
  // undefined id is left ALONE (NASA's comment: "only write to the global if it was set to a
  // value"), a live id is consumed and returns its block, and a stale id -- one whose block is
  // no longer used -- is consumed and returns NULL.
  vid = CFE_TBL_VALRESULTID_UNDEFINED;
  vrp = CFE_TBL_CheckValidationRequest(&vid);
  S("tbl_valreq undef null=");
  D(vrp == NULL);
  S(" left=");
  D(!CFE_TBL_VALRESULTID_IS_VALID(vid));
  S("\n");
  CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[2], CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 2));
  vid = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 2);
  vrp = CFE_TBL_CheckValidationRequest(&vid);
  S("tbl_valreq live isblk2=");
  D(vrp == &CFE_TBL_Global.ValidationResults[2]);
  S(" cleared=");
  D(!CFE_TBL_VALRESULTID_IS_VALID(vid));
  S("\n");
  vid = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + 3);
  vrp = CFE_TBL_CheckValidationRequest(&vid);
  S("tbl_valreq stale null=");
  D(vrp == NULL);
  S(" cleared=");
  D(!CFE_TBL_VALRESULTID_IS_VALID(vid));
  S("\n");
  // THE CRITICAL-TABLE REGISTRY LOOKUP, and the second call is the one the code actually leans
  // on: searching for CFE_ES_CDS_BAD_HANDLE is how a FREE entry is found, because a free entry
  // is one whose handle is the bad one.
  //
  // THE INDEX THE LONG WAY ROUND. `crp - CFE_TBL_Global.CritReg` is the idiomatic C, but HolyC
  // scales pointer arithmetic by the pointee and the two halves are kept reading the same, so
  // both divide an explicit byte difference.
  CFE_TBL_Global.CritReg[5].CDSHandle = CFE_ResourceId_FromInteger(0x5151);
  CFE_TBL_FindCriticalTblInfo(&crp, CFE_ResourceId_FromInteger(0x5151));
  S("tbl_crit found=");
  D(crp != NULL);
  S(" idx=");
  if (crp == NULL)
    D(-1);
  else
    D (((U8 *)crp - (U8 *)CFE_TBL_Global.CritReg) / sizeof(CFE_TBL_CritRegRec_t));
  S("\n");
  CFE_TBL_FindCriticalTblInfo(&crp, CFE_ES_CDS_BAD_HANDLE);
  S("tbl_crit free=");
  D(crp != NULL);
  S(" idx=");
  if (crp == NULL)
    D(-1);
  else
    D (((U8 *)crp - (U8 *)CFE_TBL_Global.CritReg) / sizeof(CFE_TBL_CritRegRec_t));
  S("\n");
  CFE_TBL_Global.CritReg[0].CDSHandle = CFE_ResourceId_FromInteger(0x1111);
  CFE_TBL_FindCriticalTblInfo(&crp, CFE_ResourceId_FromInteger(0x9999));
  S("tbl_crit absent=");
  D(crp == NULL);
  S("\n");
  // THE REGISTRY LOCK PAIR, which is NOT the counted one the transaction uses -- it is the
  // bare take/give, and its whole content is turning an OSAL status into a cFE one. The
  // driver's mutex returns what fs_mut_take_rc says, which is how the failure arm is reached
  // without a real mutex.
  //
  // EACH CALL INTO A LOCAL FIRST, because the two halves print incrementally and C does not
  // even specify the order among printf arguments.
  st = CFE_TBL_LockRegistry();
  S("tbl_reglock ok=");
  D(st);
  st = CFE_TBL_UnlockRegistry();
  S(" unlock=");
  D(st);
  S("\n");
  fs_mut_take_rc = -1;
  fs_mut_give_rc = -1;
  st = CFE_TBL_LockRegistry();
  S("tbl_reglock failtake=");
  D(st);
  st = CFE_TBL_UnlockRegistry();
  S(" failgive=");
  D(st);
  S("\n");
  fs_mut_take_rc = OS_SUCCESS;
  fs_mut_give_rc = OS_SUCCESS;
  // THE NAME LOOKUP, through a whole transaction. Into a local first: the miss emits an event.
  found = CFE_TBL_FindTableInRegistry("NO.SUCH");
  S("tbl_findreg miss=");
  D(!CFE_TBL_REGID_IS_VALID(found));
  S("\n");
  StrNCpy(rr->Config.Name, "APP.Found", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
  found = CFE_TBL_FindTableInRegistry("APP.Found");
  S("tbl_findreg hit=");
  D(CFE_TBL_REGID_IS_VALID(found));
  S(" id=");
  D(CFE_ResourceId_ToInteger(found));
  S("\n");
}

U0 TblCodecExercise()
{
  CFE_TBL_File_Hdr_t hdr;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_TxnState_t txn;
  U32 w;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  // the swap itself, and that it is its own inverse
  w = 0x01020304;
  CFE_TBL_ByteSwapUint32(&w);
  S("tbl_cdswap once=");
  Hx8(w);
  CFE_TBL_ByteSwapUint32(&w);
  S(" twice=");
  Hx8(w);
  S("\n");
  // THREE FIELDS SWAP, THE NAME DOES NOT -- which is why the header can be read as a struct
  // at all.
  MemSet(&hdr, 0, sizeof(CFE_TBL_File_Hdr_t));
  hdr.Reserved = 0x11223344;
  hdr.Offset = 0x0000002A;
  hdr.NumBytes = 0x000000FF;
  StrNCpy(hdr.TableName, "CFE_TBL.Cdc", CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  CFE_TBL_ByteSwapTblHeader(&hdr);
  S("tbl_cdhdr res=");
  Hx8(hdr.Reserved);
  S(" off=");
  Hx8(hdr.Offset);
  S(" num=");
  Hx8(hdr.NumBytes);
  S(" name=");
  S(hdr.TableName);
  S("\n");
  CFE_TBL_ByteSwapTblHeader(&hdr);
  S("tbl_cdhdr_back res=");
  Hx8(hdr.Reserved);
  S(" off=");
  Hx8(hdr.Offset);
  S(" num=");
  Hx8(hdr.NumBytes);
  S("\n");
  // THE SIZE CHECK, and the overflow case the first test exists for: Offset and NumBytes are
  // both 32-bit and come from a file, so their sum can WRAP -- a wrapped sum is smaller than
  // Offset and would otherwise pass the size test and then be used as a length.
  rr = &CFE_TBL_Global.Registry[3];
  CFE_TBL_InitRegistryRecord(rr);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
  rr->Config.Size = 256;
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  MemSet(&hdr, 0, sizeof(CFE_TBL_File_Hdr_t));
  hdr.Offset = 0;
  hdr.NumBytes = 256;
  S("tbl_cdsize exact=");
  D(CFE_TBL_ValidateCodecLoadSize(&txn, &hdr));
  hdr.NumBytes = 257;
  S(" over=0x");
  Hx8(CFE_TBL_ValidateCodecLoadSize(&txn, &hdr));
  hdr.Offset = 0xFFFFFFF0;
  hdr.NumBytes = 0x20;
  // sum wraps to 0x10, which is < Offset and < Size
  S(" wrap=0x");
  Hx8(CFE_TBL_ValidateCodecLoadSize(&txn, &hdr));
  S(" events=");
  D(txn.NumPendingEvents);
  S("\n");
  // PARTIAL versus SHORT, which are different warnings for different reasons
  MemSet(&hdr, 0, sizeof(CFE_TBL_File_Hdr_t));
  hdr.Offset = 0;
  hdr.NumBytes = 256;
  S("tbl_cdfinal full=");
  D(CFE_TBL_CodecGetFinalStatus(&txn, &hdr));
  hdr.NumBytes = 128;
  S(" short=0x");
  Hx8(CFE_TBL_CodecGetFinalStatus(&txn, &hdr));
  hdr.Offset = 16;
  hdr.NumBytes = 256;
  S(" partial=0x");
  Hx8(CFE_TBL_CodecGetFinalStatus(&txn, &hdr));
  S("\n");
  // the empty seam members, which still have to return the right thing
  S("tbl_cdseam cfg=");
  D(CFE_TBL_ValidateCodecConfig(&rr->Config));
  S(" acquire_null=");
  D(CFE_TBL_AcquireCodecBuffer(rr) == NULL);
  S("\n");
  CFE_TBL_ReleaseCodecBuffer(&rr->Buffers[0]);
  // ENCODE AND DECODE ARE A COPY, and both skip it when source and destination are the same
  // buffer -- the case a dump of an already-resident table hits.
  rr->Buffers[0].BufferPtr = tbl_probe_mem;
  rr->Buffers[0].AllocationSize = 64;
  rr->Buffers[1].BufferPtr = tbl_probe_mem2;
  rr->Buffers[1].AllocationSize = 64;
  MemSet(tbl_probe_mem, 0x5E, 64);
  MemSet(tbl_probe_mem2, 0, 64);
  CFE_TBL_LoadBuffSetContentSize(&rr->Buffers[0], 12);
  S("tbl_cdcopy enc=");
  D(CFE_TBL_EncodeOutputData(&txn, &rr->Buffers[0], &rr->Buffers[1]));
  S(" dst=");
  Hx2b(tbl_probe_mem2[0]);
  S(" len=");
  D(CFE_TBL_LoadBuffGetContentSize(&rr->Buffers[1]));
  MemSet(tbl_probe_mem2, 0, 64);
  CFE_TBL_LoadBuffSetContentSize(&rr->Buffers[1], 0);
  S(" dec=");
  D(CFE_TBL_DecodeInputData(&txn, &rr->Buffers[0], &rr->Buffers[1]));
  S(" dst=");
  Hx2b(tbl_probe_mem2[0]);
  S(" len=");
  D(CFE_TBL_LoadBuffGetContentSize(&rr->Buffers[1]));
  S(" same=");
  D(CFE_TBL_EncodeOutputData(&txn, &rr->Buffers[0], &rr->Buffers[0]));
  S("\n");
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

U0 TblValResultExercise()
{
  CFE_TBL_ValidationResult_t *vr;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_TxnState_t txn;
  CFE_TBL_TxnEventContext_t evctx;
  U32 nid, idx;
  I64 k, sent;
  I64 before;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_ES_GetAppID(&CFE_TBL_Global.TableTaskAppId);
  CFE_EVS_Global.EVS_EventBurstMax = 0;
  // THE ID SPACE HAS TO BE OPENED FIRST, the same line CFE_TBL_EarlyInit runs and the same
  // trap ES's exercises hit four times: CFE_TBL_Global is zeroed, 0 is not a valid resource
  // id, so CFE_ResourceId_FindNext starting there walks off the table and returns UNDEFINED
  // with all ten blocks free. The first draft of this exercise then dereferenced the NULL that
  // LocateValidationResultByID correctly returned.
  CFE_TBL_Global.LastValidationResultId = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1);
  // the id space: first, last, one past (which WRAPS -- ToIndex is a modulo), undefined
  S("tbl_vridx first=");
  D(CFE_TBL_ValidationResultId_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE), &idx));
  S("/");
  D(idx);
  S(" last=");
  D(CFE_TBL_ValidationResultId_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS - 1), &idx));
  S("/");
  D(idx);
  S(" past=");
  D(CFE_TBL_ValidationResultId_ToIndex(CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS), &idx));
  S("/");
  D(idx);
  S(" undef=");
  D(CFE_TBL_ValidationResultId_ToIndex(CFE_TBL_VALRESULTID_UNDEFINED, &idx));
  S("\n");
  // the allocator primitives
  nid = CFE_TBL_GetNextValResultBlock();
  vr = CFE_TBL_LocateValidationResultByID(nid);
  S("tbl_vralloc self=");
  D(vr == &CFE_TBL_Global.ValidationResults[0]);
  S(" used=");
  // guarded the way NASA's own CheckValidationResultSlotUsed guards it: a NULL here means the
  // id was out of range, and IsUsed would dereference it.
  D(vr != NULL && CFE_TBL_ValidationResultIsUsed(vr));
  S(" slotused=");
  D(CFE_TBL_CheckValidationResultSlotUsed(CFE_ResourceId_FromInteger(0)));
  S("\n");
  CFE_TBL_ValidationResultSetUsed(vr, nid);
  vr->State = CFE_TBL_VALIDATION_PERFORMED;
  S("tbl_vrused used=");
  D(CFE_TBL_ValidationResultIsUsed(vr));
  S(" id=");
  D(CFE_ResourceId_ToInteger(CFE_TBL_ValidationResultGetId(vr)));
  S(" match=");
  D(CFE_TBL_ValidationResultIsMatch(vr, nid));
  S("\n");
  CFE_TBL_ValidationResultSetFree(vr);
  S("tbl_vrfree used=");
  D(CFE_TBL_ValidationResultIsUsed(vr));
  S(" state=");
  D(vr->State);
  S("\n");
  // A TABLE WITH A VALIDATION FUNCTION: the block goes PENDING and the app owes an answer.
  rr = &CFE_TBL_Global.Registry[4];
  CFE_TBL_InitRegistryRecord(rr);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 4));
  StrNCpy(rr->Config.Name, "CFE_TBL.Val", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  rr->Config.ValidationFuncPtr = &TblValStub;
  rr->Buffers[0].BufferPtr = tbl_probe_mem;
  rr->Buffers[0].AllocationSize = 64;
  rr->Buffers[0].Crc = 0xFEEDFACE;
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 12), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  vr = CFE_TBL_TxnSetupValidationRequest(&txn, CFE_TBL_BufferSelect_ACTIVE);
  S("tbl_vrpending nonnull=");
  D(vr != NULL);
  S(" state=");
  if (vr == NULL)
    D(-1);
  else
    D(vr->State);
  S(" crc=");
  if (vr == NULL)
    Hx8(0);
  else
    Hx8(vr->CrcOfTable);
  S(" name=");
  if (vr != NULL)
    S(vr->TableName);
  S(" sel=");
  if (vr == NULL)
    D(0);
  else
    D(vr->BufferSelect);
  S(" events=");
  D(txn.NumPendingEvents);
  S(" reqs=");
  D(CFE_TBL_Global.NumValRequests);
  S("\n");
  // ASKING AGAIN WHILE ONE IS PENDING is refused, and the event carries the pending id.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  vr = CFE_TBL_TxnCheckValidationRequest(&txn);
  S("tbl_vrinprog nonnull=");
  D(vr != NULL);
  S(" events=");
  D(txn.NumPendingEvents);
  S(" id=");
  D(txn.PendingEvents[0].EventId);
  S(" data2=");
  D(txn.PendingEvents[0].EventData2);
  S("\n");
  // NO VALIDATION FUNCTION: allocated anyway, straight to PERFORMED, buffer marked valid.
  rr->Config.ValidationFuncPtr = NULL;
  rr->PendingValId = CFE_TBL_VALRESULTID_UNDEFINED;
  rr->Buffers[0].IsValid = FALSE;
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  vr = CFE_TBL_TxnSetupValidationRequest(&txn, CFE_TBL_BufferSelect_ACTIVE);
  S("tbl_vrassumed nonnull=");
  D(vr != NULL);
  S(" state=");
  if (vr == NULL)
    D(-1);
  else
    D(vr->State);
  S(" bufvalid=");
  D(rr->Buffers[0].IsValid);
  S(" events=");
  D(txn.NumPendingEvents);
  S(" id=");
  D(txn.PendingEvents[0].EventId);
  S(" reqs=");
  D(CFE_TBL_Global.NumValRequests);
  S("\n");
  // AN ILLEGAL BUFFER SELECTOR never reaches a block at all.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  vr = CFE_TBL_TxnSetupValidationRequest(&txn, 99);
  S("tbl_vrbadsel null=");
  D(vr == NULL);
  S(" events=");
  D(txn.NumPendingEvents);
  S(" id=");
  D(txn.PendingEvents[0].EventId);
  S(" data2=");
  D(txn.PendingEvents[0].EventData2);
  S("\n");
  // ALL TEN TAKEN, so the eleventh request has nowhere to put the answer.
  for (k = 0; k < CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS; k++)
    CFE_TBL_ValidationResultSetUsed(&CFE_TBL_Global.ValidationResults[k], CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE + k));
  rr->Config.ValidationFuncPtr = &TblValStub;
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  txn.RegRecPtr = rr;
  vr = CFE_TBL_TxnSetupValidationRequest(&txn, CFE_TBL_BufferSelect_ACTIVE);
  S("tbl_vrfull null=");
  D(vr == NULL);
  S(" events=");
  D(txn.NumPendingEvents);
  S(" id=");
  D(txn.PendingEvents[0].EventId);
  S("\n");
  // AND THE FOUR EVENT STRINGS, which are the only output this file produces. Two of them
  // carry a formatted number, and CFE_TBL_ASSUMED_VALID_INF_EID is the one that is
  // INFORMATION rather than ERROR -- visible in the EVS line's type field.
  tbl_val_ids[0] = CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID;
  tbl_val_ids[1] = CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID;
  tbl_val_ids[2] = CFE_TBL_ASSUMED_VALID_INF_EID;
  tbl_val_ids[3] = CFE_TBL_VALIDATION_IN_PROGRESS_ERR_EID;
  tbl_val_ids[4] = 998;
  MemSet(&evctx, 0, sizeof(CFE_TBL_TxnEventContext_t));
  evctx.Operation = "Validate";
  evctx.CallerName = "PROBE_APP";
  evctx.TableName = "CFE_TBL.Val";
  for (k = 0; k < 5; k++) {
    CFE_TBL_TxnEvent_t ev;
    MemSet(&ev, 0, sizeof(CFE_TBL_TxnEvent_t));
    ev.EventId = tbl_val_ids[k];
    ev.EventData2 = 0x1234ABCD;
    sent = CFE_TBL_SendValidationEventHelper(&ev, &evctx);
    S("tbl_vrevt id=");
    D(tbl_val_ids[k]);
    S(" sent=");
    D(sent);
    S("\n");
  }
  // THE WITNESS MOVED when CFE_TBL_SendTransactionEvents stopped being a stand-in. It used to
  // be a counter; the real one assembles the context, walks the pending events in the order
  // they were added, renders each through the helper, and CLEARS the list. So what says it ran
  // is the event text plus NumPendingEvents going to zero -- and the caller name comes from
  // the transaction, which is what proves the context assembly.
  CFE_TBL_TxnAddEvent(&txn, CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID, 0, 0);
  CFE_TBL_TxnAddEvent(&txn, CFE_TBL_ASSUMED_VALID_INF_EID, 0, 0);
  txn.RegRecPtr = rr;
  StrNCpy(txn.AppNameBuffer, "TXN_APP", CFE_MISSION_MAX_API_LEN - 1);
  before = CFE_TBL_TxnGetEventCount(&txn);
  CFE_TBL_SendValidationEvents(&txn);
  S("tbl_vrsend before=");
  D(before);
  S(" after=");
  D(CFE_TBL_TxnGetEventCount(&txn));
  S("\n");
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

U0 TblLoadBuffRegRecExercise()
{
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_AccessDescriptor_t *ad;
  CFE_TBL_LoadBuff_t *lb;
  U32 nid, cat, idx, serial;
  U32 descs;
  I64 k;
  I64 stale_before, stale_got, stale_after;
  I64 before;
  CFE_TBL_TxnState_t txn2;
  CFE_TBL_TxnEventContext_t evctx;
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  CFE_TBL_Global.WorkBufMutex = 0x7B20;
  // DECOMPOSE over the category boundary: 0..3 are shared, 4 onward are table 0's pair.
  for (k = 0; k < 8; k++) {
    CFE_TBL_LoadBuffSerialDecompose(k, &cat, &idx);
    S("tbl_lbdec s=");
    D(k);
    S(" cat=");
    D(cat);
    S(" idx=");
    D(idx);
    S("\n");
  }
  // COMPOSE IS NOT THE INVERSE: it rounds UP to the next serial in the asked-for category.
  for (k = 0; k < 3; k++) {
    serial = k;
    CFE_TBL_LoadBuffSerialCompose(&serial, 0, 1);
    S("tbl_lbcomp in=");
    D(k);
    S(" cat=0 idx=1 out=");
    D(serial);
    S("\n");
    serial = k;
    CFE_TBL_LoadBuffSerialCompose(&serial, 2, 0);
    S("tbl_lbcomp in=");
    D(k);
    S(" cat=2 idx=0 out=");
    D(serial);
    S("\n");
  }
  // LOCATE: a shared id lands in CFE_TBL_Global.LoadBuffs, a local id in the table's own
  // pair -- and a SINGLE-buffered table always uses local index 0 whichever is asked for.
  rr = &CFE_TBL_Global.Registry[1];
  rr->Config.DoubleBuffered = TRUE;
  S("tbl_lbloc shared0=");
  D(CFE_TBL_LocateLoadBufferByID(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE)) == &CFE_TBL_Global.LoadBuffs[0]);
  S(" shared3=");
  D(CFE_TBL_LocateLoadBufferByID(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 3)) == &CFE_TBL_Global.LoadBuffs[3]);
  S("\n");
  // table 1's pair is category 2, i.e. serial 4 + 1*2 = 6 and 7
  S("tbl_lbloc dbl0=");
  D(CFE_TBL_LocateLoadBufferByID(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6)) == &rr->Buffers[0]);
  S(" dbl1=");
  D(CFE_TBL_LocateLoadBufferByID(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 7)) == &rr->Buffers[1]);
  S("\n");
  rr->Config.DoubleBuffered = FALSE;
  S("tbl_lbloc sgl_collapses=");
  D(CFE_TBL_LocateLoadBufferByID(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 7)) == &rr->Buffers[0]);
  S("\n");
  // THE HISTORICAL TELEMETRY INDEX: shared buffers report 0..3, a double-buffered table's own
  // pair reports -3 and -2, and anything unrecognised is -1.
  S("tbl_lbtlm sh0=");
  D(CFE_TBL_LoadBuffIdToTlmIndex(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE)));
  S(" sh3=");
  D(CFE_TBL_LoadBuffIdToTlmIndex(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 3)));
  S(" loc0=");
  D(CFE_TBL_LoadBuffIdToTlmIndex(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6)));
  S(" loc1=");
  D(CFE_TBL_LoadBuffIdToTlmIndex(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 7)));
  S("\n");
  S("tbl_lbkind sh_isshared=");
  D(CFE_TBL_LoadBuffIsShared(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE)));
  S(" loc_isshared=");
  D(CFE_TBL_LoadBuffIsShared(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6)));
  S(" loc_isprivate1=");
  D(CFE_TBL_LoadBuffIsPrivate(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6), CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 1)));
  S(" loc_isprivate0=");
  D(CFE_TBL_LoadBuffIsPrivate(CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 6), CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE)));
  S("\n");
  // INIT SETS FOUR FIELDS EXPLICITLY, and in THIS configuration all four are zero anyway
  // (CFE_RESOURCEID_UNDEFINED is 0 and the SIMPLE resourceid mode makes every wrapper the
  // identity). The record is filled with 0x5A first, so what this asserts is that Init ran at
  // all -- and `lip` and `attached` are the two that would differ regardless.
  rr = &CFE_TBL_Global.Registry[2];
  MemSet(rr, 0x5A, sizeof(CFE_TBL_RegistryRec_t));
  CFE_TBL_InitRegistryRecord(rr);
  S("tbl_rrinit owner=");
  D(CFE_ResourceId_ToInteger(rr->OwnerAppId));
  S(" val=");
  D(CFE_ResourceId_ToInteger(rr->PendingValId));
  S(" cds=");
  D(CFE_ResourceId_ToInteger(rr->CDSHandle));
  S(" dump=");
  D(CFE_ResourceId_ToInteger(rr->DumpControlId));
  S(" lip=");
  D(CFE_TBL_RegRecIsLoadInProgress(rr) != 0);
  S(" attached=");
  D(CFE_TBL_HandleLinkIsAttached(&rr->AccessList));
  S("\n");
  // name and id lookup
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 2));
  StrNCpy(rr->Config.Name, "CFE_TBL.Probe", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  S("tbl_rrfind byname=");
  D(CFE_TBL_LocateRegRecByName("CFE_TBL.Probe") == rr);
  S(" bymiss=");
  D(CFE_TBL_LocateRegRecByName("CFE_TBL.Nope") == NULL);
  S(" byid=");
  D(CFE_TBL_LocateRegRecByID(CFE_TBL_RegRecGetID(rr)) == rr);
  S(" used=");
  D(CFE_TBL_RegRecIsUsed(rr));
  S(" name=");
  S(CFE_TBL_RegRecGetName(rr));
  S("\n");
  // THE BRANCH THIS WHOLE PAIR WAS SEQUENCED FOR. A double-buffered table wants its other
  // buffer for a new load. If another application still holds that buffer -- it called
  // CFE_TBL_GetAddress and has not released it, so LockFlag is set -- the load must be
  // REFUSED and the holder named. Reaching this needs a real walk of the access-descriptor
  // list, which is why CFE_TBL_ForeachAccessDescriptor is faithful in the driver and not a
  // counter: a walk of zero descriptors makes the refusal unreachable and the assertion
  // below would pass while testing nothing.
  rr = &CFE_TBL_Global.Registry[0];
  CFE_TBL_InitRegistryRecord(rr);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE));
  rr->Config.DoubleBuffered = TRUE;
  // active is local idx 0 (serial 4), so the next local buffer is idx 1 (serial 5)
  rr->Status.ActiveBufferId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 4);
  nid = CFE_TBL_GetNextLocalBufferId(rr);
  lb = CFE_TBL_LocateLoadBufferByID(nid);
  S("tbl_nextlocal id=");
  D(CFE_ResourceId_ToInteger(nid));
  S(" isbuf1=");
  D(lb == &rr->Buffers[1]);
  S("\n");
  // mark it used by someone else so the exclusive check has to run
  // A DIFFERENT ID THAT NAMES THE SAME BLOB. 260 serials cover every buffer once, so
  // serial+260 decomposes to the same place -- which is precisely the case NASA's helper
  // comment calls out: "check if it refers to this memory blob (even if the ID is different)".
  // Using an unrelated id instead would land on another table's buffer and the locked-buffer
  // branch would never fire, which is how the first draft of this exercise passed while
  // testing nothing.
  CFE_TBL_LoadBuffSetUsed(lb, CFE_ResourceId_FromInteger(CFE_ResourceId_ToInteger(nid) + 260), CFE_TBL_RegRecGetID(rr));
  // attach ONE access descriptor holding that buffer, locked
  ad = &CFE_TBL_Global.Handles[7];
  CFE_TBL_InitAccessDescriptor(ad);
  CFE_TBL_AccDescSetUsed(ad, CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE + 7));
  ad->AppId = CFE_ResourceId_FromInteger(0xABCD);
  ad->BufferIndex = CFE_TBL_LoadBufferGetID(lb);
  ad->LockFlag = TRUE;
  rr->AccessList.Next = CFE_TBL_AccDescGetHandle(ad);
  // into a local first, to match the C half: this call emits the syslog line naming the
  // holder -- see the note at tbl_stalelip.
  // WHAT `descs` REPLACED, AND WHAT IT DOES NOT. This line used to report a counter the
  // DRIVER kept inside its own copy of CFE_TBL_ForeachAccessDescriptor, and `visits=1` here
  // against `visits=0` at tbl_lockedclaim below was an assertion about CONTROL FLOW INSIDE
  // CFE_TBL_GetInactiveBufferExclusive -- one path walked the list, the other returned before
  // it. `descs` cannot tell those apart: it counts the list AFTER the call and reads 1 at both
  // sites. So this is a trade, not an upgrade. What is gained is real -- ForeachAccessDescriptor
  // and CountAccessDescHelper had never been called by anything -- and what is lost went with
  // the stub, because a counter inside gated code is not something a driver may add.
  //
  // Third occurrence of the recorded trap: the witness moves when the stub goes, and the
  // replacement is rarely the same shape.
  descs = 0;
  stale_got = CFE_TBL_GetInactiveBufferExclusive(rr) == NULL;
  CFE_TBL_ForeachAccessDescriptor(rr, &CFE_TBL_CountAccessDescHelper, &descs);
  S("tbl_lockedrefuse null=");
  D(stale_got);
  S(" descs=");
  D(descs);
  S("\n");
  // release the lock and the SAME call now claims the buffer for this table
  ad->LockFlag = FALSE;
  descs = 0;
  lb = CFE_TBL_GetInactiveBufferExclusive(rr);
  CFE_TBL_ForeachAccessDescriptor(rr, &CFE_TBL_CountAccessDescHelper, &descs);
  S("tbl_lockedclaim nonnull=");
  D(lb != NULL);
  S(" descs=");
  D(descs);
  S(" owner=");
  if (lb == NULL)
    D(0);
  else
    D(CFE_ResourceId_ToInteger(lb->OwnerRegId));
  S("\n");
  // THE STALE LOAD-IN-PROGRESS RECOVERY. A NextBufferId that no longer matches its buffer is
  // cleared rather than trusted, and the table is reported.
  // EACH VALUE INTO A LOCAL FIRST, to match the C half: the middle call emits a syslog line,
  // and C evaluates printf's arguments before printing any of them while this side prints
  // incrementally, so an inline call puts that line on opposite sides of this one.
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 2));
  stale_before = CFE_TBL_RegRecIsLoadInProgress(rr) != 0;
  stale_got = CFE_TBL_GetLoadInProgressBuffer(rr) != NULL;
  stale_after = CFE_TBL_RegRecIsLoadInProgress(rr) != 0;
  S("tbl_stalelip before=");
  D(stale_before);
  S(" got=");
  D(stale_got);
  S(" after=");
  D(stale_after);
  S("\n");
  // the three buffer questions, now that one is active
  S("tbl_buf3 active=");
  D(CFE_TBL_GetActiveBuffer(rr) == &rr->Buffers[0]);
  S(" lip=");
  D(CFE_TBL_GetLoadInProgressBuffer(rr) == NULL);
  S(" inactive=");
  D(CFE_TBL_GetInactiveBuffer(rr) != NULL);
  S(" loaded=");
  D(CFE_TBL_RegRecIsTableLoaded(rr));
  S("\n");
  // selected-buffer dispatch, including the default that returns NULL
  S("tbl_bufsel act=");
  D(CFE_TBL_GetSelectedBuffer(rr, CFE_TBL_BufferSelect_ACTIVE) == CFE_TBL_GetActiveBuffer(rr));
  S(" inact=");
  D(CFE_TBL_GetSelectedBuffer(rr, CFE_TBL_BufferSelect_INACTIVE) == CFE_TBL_GetInactiveBuffer(rr));
  S(" bogus=");
  D(CFE_TBL_GetSelectedBuffer(rr, 99) == NULL);
  S("\n");
  // modified flag and load info
  CFE_TBL_RegRecResetLoadInfo(rr, "/cf/probe.tbl", CFE_TIME_GetTime());
  S("tbl_loadinfo file=");
  S(CFE_TBL_RegRecGetLastFileLoaded(rr));
  S(" modified=");
  D(CFE_TBL_RegRecIsModified(rr));
  S("\n");
  CFE_TBL_RegRecSetModifiedFlag(rr);
  S("tbl_modified ");
  D(CFE_TBL_RegRecIsModified(rr));
  S("\n");
  // pending activation needs BOTH validated and requested
  lb = CFE_TBL_LocateLoadBufferByID(CFE_TBL_RegRecGetLoadInProgress(rr));
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[1]));
  lb = &rr->Buffers[1];
  lb->IsValid = FALSE;
  lb->ActivateReq = TRUE;
  S("tbl_pending novalid=");
  D(CFE_TBL_RegRecIsPendingActivation(rr));
  lb->IsValid = TRUE;
  S(" both=");
  D(CFE_TBL_RegRecIsPendingActivation(rr));
  lb->ActivateReq = FALSE;
  S(" noreq=");
  D(CFE_TBL_RegRecIsPendingActivation(rr));
  S("\n");
  // THE TWO FUNCTIONS THAT COMPOSE ALL OF THE ABOVE, which nothing had reached yet.
  //
  // PrepareNewLoadBuff picks the buffer for a new load: a double-buffered table gets its own
  // other buffer (exclusively, so the walk above runs), a single-buffered one borrows from the
  // shared pool. Either way the ACTIVE contents are copied forward first, because a file may
  // contain only part of a table, and the result is marked unvalidated.
  rr = &CFE_TBL_Global.Registry[5];
  CFE_TBL_InitRegistryRecord(rr);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 5));
  rr->Config.DoubleBuffered = TRUE;
  rr->Buffers[0].BufferPtr = tbl_probe_mem;
  rr->Buffers[0].AllocationSize = 64;
  rr->Buffers[1].BufferPtr = tbl_probe_mem2;
  rr->Buffers[1].AllocationSize = 64;
  MemSet(tbl_probe_mem, 0xC3, 64);
  CFE_TBL_LoadBuffSetContentSize(&rr->Buffers[0], 8);
  rr->Buffers[0].IsValid = TRUE;
  // A TABLE'S OWN BUFFERS NEED THEIR OWN IDS, or SetActiveBuffer stores a zero and
  // GetActiveBuffer resolves it to NULL -- faithful (an unset id IS undefined) but it means
  // nothing is copied forward and the assertion below reads `copied=0`, passing while testing
  // the wrong path. Registry[5] is category 6, so its pair is serial 4+5*2 = 14 and 15.
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[0], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 14), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_LoadBuffSetUsed(&rr->Buffers[1], CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 15), CFE_TBL_RegRecGetID(rr));
  CFE_TBL_SetActiveBuffer(rr, &rr->Buffers[0]);
  lb = CFE_TBL_PrepareNewLoadBuff(rr);
  S("tbl_prepdbl isbuf1=");
  D(lb == &rr->Buffers[1]);
  S(" copied=");
  if (lb == NULL)
    D(-1);
  else
    D(CFE_TBL_LoadBuffGetContentSize(lb));
  S(" first=");
  if (lb == NULL)
    Hx2b(0);
  else
    Hx2b(CFE_TBL_LoadBuffGetReadPointer(lb)[0]);
  S(" valid=");
  if (lb == NULL)
    D(-1);
  else
    D(lb->IsValid);
  S(" actreq=");
  if (lb == NULL)
    D(-1);
  else
    D(lb->ActivateReq);
  S("\n");
  // the single-buffered path, which goes through the shared pool via AcquireGlobalLoadBuff
  rr = &CFE_TBL_Global.Registry[6];
  CFE_TBL_InitRegistryRecord(rr);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 6));
  rr->Config.DoubleBuffered = FALSE;
  CFE_TBL_Global.LoadBuffs[0].BufferPtr = tbl_probe_mem2;
  CFE_TBL_Global.LoadBuffs[0].AllocationSize = 64;
  CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + 3);
  lb = CFE_TBL_PrepareNewLoadBuff(rr);
  S("tbl_prepsgl shared=");
  if (lb == NULL)
    D(-1);
  else
    D(CFE_TBL_LoadBuffIsShared(CFE_TBL_LoadBufferGetID(lb)));
  S(" isbuf0=");
  D(lb == &CFE_TBL_Global.LoadBuffs[0]);
  S(" owner=");
  if (lb == NULL)
    D(0);
  else
    D(CFE_ResourceId_ToInteger(lb->OwnerRegId));
  S(" valid=");
  if (lb == NULL)
    D(-1);
  else
    D(lb->IsValid);
  S("\n");
  // TxnSetupActivationRequest: three refusals and one success, each with its own event.
  MemSet(&txn2, 0, sizeof(CFE_TBL_TxnState_t));
  txn2.RegRecPtr = &CFE_TBL_Global.Registry[5];
  rr = txn2.RegRecPtr;
  rr->Config.DumpOnly = TRUE;
  S("tbl_actv dumponly null=");
  D(CFE_TBL_TxnSetupActivationRequest(&txn2) == NULL);
  S(" events=");
  D(txn2.NumPendingEvents);
  S(" id=");
  D(txn2.PendingEvents[0].EventId);
  S("\n");
  rr->Config.DumpOnly = FALSE;
  MemSet(&txn2, 0, sizeof(CFE_TBL_TxnState_t));
  txn2.RegRecPtr = rr;
  CFE_TBL_RegRecClearLoadInProgress(rr);
  S("tbl_actv nobuf null=");
  D(CFE_TBL_TxnSetupActivationRequest(&txn2) == NULL);
  S(" events=");
  D(txn2.NumPendingEvents);
  S(" id=");
  D(txn2.PendingEvents[0].EventId);
  S("\n");
  MemSet(&txn2, 0, sizeof(CFE_TBL_TxnState_t));
  txn2.RegRecPtr = rr;
  CFE_TBL_RegRecSetLoadInProgress(rr, CFE_TBL_LoadBufferGetID(&rr->Buffers[1]));
  rr->Buffers[1].IsValid = FALSE;
  S("tbl_actv unvalidated null=");
  D(CFE_TBL_TxnSetupActivationRequest(&txn2) == NULL);
  S(" events=");
  D(txn2.NumPendingEvents);
  S(" id=");
  D(txn2.PendingEvents[0].EventId);
  S("\n");
  MemSet(&txn2, 0, sizeof(CFE_TBL_TxnState_t));
  txn2.RegRecPtr = rr;
  rr->Buffers[1].IsValid = TRUE;
  lb = CFE_TBL_TxnSetupActivationRequest(&txn2);
  S("tbl_actv ok nonnull=");
  D(lb != NULL);
  S(" events=");
  D(txn2.NumPendingEvents);
  S(" actreq=");
  if (lb == NULL)
    D(-1);
  else
    D(lb->ActivateReq);
  S("\n");
  // AND THE EVENT TEXT, which IS the comparison surface -- the only thing that compares the
  // three strings this file formats. The helper is called directly, as NASA's own unit tests
  // do: it is not static, and the dispatcher that would reach it lives in
  // cfe_tbl_transaction.c, which is still inside the cycle. An event id it does not know
  // returns false, which is how the dispatcher passes an event to the next helper.
  // AND THE EVENT NEEDS A REGISTERED APP, or EVS refuses it and the three strings this file
  // formats are never emitted -- `sent=1` would still be printed, because that is the
  // HELPER's return value, not EVS's. The first version of this exercise asserted exactly
  // that and compared nothing.
  CFE_ES_GetAppID(&CFE_TBL_Global.TableTaskAppId);
  CFE_EVS_Global.EVS_EventBurstMax = 0;
  // filled at run time, not in the declaration: HolyC has no file-scope aggregate initialiser.
  tbl_actv_ids[0] = CFE_TBL_ACTIVATE_DUMP_ONLY_ERR_EID;
  tbl_actv_ids[1] = CFE_TBL_ACTIVATE_ERR_EID;
  tbl_actv_ids[2] = CFE_TBL_UNVALIDATED_ERR_EID;
  tbl_actv_ids[3] = 999;
  MemSet(&evctx, 0, sizeof(CFE_TBL_TxnEventContext_t));
  evctx.Operation = "Activate";
  evctx.CallerName = "PROBE_APP";
  evctx.TableName = "CFE_TBL.Probe";
  for (k = 0; k < 4; k++) {
    CFE_TBL_TxnEvent_t ev;
    MemSet(&ev, 0, sizeof(CFE_TBL_TxnEvent_t));
    ev.EventId = tbl_actv_ids[k];
    // into a local first, to match the C half -- this call EMITS the event. Third time; see
    // the note at tbl_stalelip.
    stale_got = CFE_TBL_SendActivationEventHelper(&ev, &evctx);
    S("tbl_actvevt id=");
    D(tbl_actv_ids[k]);
    S(" sent=");
    D(stale_got);
    S("\n");
  }
  // and the wrapper, which only counts here because SendTransactionEvents is a stand-in
  // same, for the activation helper -- and with NO registry record on the transaction, so the
  // context's TableName falls back to the literal "[unknown]" rather than being left blank.
  // That fallback is one line in SendTransactionEvents and is visible in the text.
  MemSet(&txn2, 0, sizeof(CFE_TBL_TxnState_t));
  CFE_TBL_TxnAddEvent(&txn2, CFE_TBL_ACTIVATE_ERR_EID, 0, 0);
  StrNCpy(txn2.AppNameBuffer, "TXN_APP", CFE_MISSION_MAX_API_LEN - 1);
  before = CFE_TBL_TxnGetEventCount(&txn2);
  CFE_TBL_SendActivationEvents(&txn2);
  S("tbl_actvsend before=");
  D(before);
  S(" after=");
  D(CFE_TBL_TxnGetEventCount(&txn2));
  S("\n");
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
}

U0 TblAccDescExercise()
{
  CFE_TBL_AccessDescriptor_t *ad;
  CFE_TBL_RegistryRec_t *rr;
  CFE_TBL_TxnState_t txn;
  U32 nid, idx;
  I64 k, t0, g0;
  I64 before;
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
  // cfe_tbl_regrec.c IS gated now, so CFE_TBL_InitRegistryRecord is available -- the MemSet
  // stays because this exercise wants a record with NO buffers and NO access links, which is
  // what a zeroed one is; InitRegistryRecord would fill in defaults this test then has to undo.
  rr = &CFE_TBL_Global.Registry[3];
  MemSet(rr, 0, sizeof(CFE_TBL_RegistryRec_t));
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  // WHAT `regused` REPLACED, AND WHY IT IS SET FIRST. This line used to report a counter
  // inside the driver's own CFE_TBL_TxnRemoveAccessLink. That stand-in is gone, so what is
  // witnessed now is the real function's EFFECT: an unowned table with no remaining access
  // links is returned to the pool by CFE_TBL_RegRecSetFree. The record is marked USED here on
  // purpose -- a zeroed record already reads free, so asserting `regused=0` against a record
  // that was never used is the vacuous-zero shape this transcript has been caught by before.
  // `before=1` is in the line so the reader can see it was not.
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
  before = CFE_TBL_RegRecIsUsed(rr);
  txn.AppId = rr->OwnerAppId;
  txn.RegRecPtr = rr;
  CFE_TBL_TxnReleaseAccDesc(&txn);
  S("tbl_adrel_owner owner=");
  D(CFE_ResourceId_ToInteger(rr->OwnerAppId));
  S(" freed=");
  D(!CFE_TBL_AccDescIsUsed(txn.AccDescPtr));
  S(" before=");
  D(before);
  S(" regused=");
  D(CFE_TBL_RegRecIsUsed(rr));
  S("\n");
  // RELEASE BY A NON-OWNER must leave the table owned -- but it still FREES the descriptor,
  // and `freed=1` below is correct, not a bug. CFE_TBL_AccDescSetFree is outside the
  // ownership `if`: giving back your own handle always gives it back, and only the un-owning
  // of the TABLE is conditional. A reader checking "a non-owner should change nothing" would
  // misread that line.
  MemSet(&txn, 0, sizeof(CFE_TBL_TxnState_t));
  CFE_TBL_TxnAllocateAccDesc(&txn);
  CFE_TBL_RegRecSetUsed(rr, CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE + 3));
  rr->OwnerAppId = CFE_ResourceId_FromInteger(0x1111);
  txn.AppId = CFE_ResourceId_FromInteger(0x2222);
  txn.RegRecPtr = rr;
  CFE_TBL_TxnReleaseAccDesc(&txn);
  // and `regused=1` here is the other half of the same claim: the table is still OWNED, so
  // RemoveAccessLink's two-part test fails on the first part and the record stays.
  S("tbl_adrel_other owner=");
  D(CFE_ResourceId_ToInteger(rr->OwnerAppId));
  S(" freed=");
  D(!CFE_TBL_AccDescIsUsed(txn.AccDescPtr));
  S(" regused=");
  D(CFE_TBL_RegRecIsUsed(rr));
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
Bool es_pool_exhausted;
// AND DO NOT USE IT TO FAIL SB'S POOL CREATE. CFE_SB_InitBuffers' failure message prints
// `gave adr 0x%lx` -- the partition's address -- so that line cannot be compared across a host
// process and a QEMU guest. It is out of the transcript because the pool SUCCEEDS, not because
// it is unreachable. Same rule as CFE_SB_CreatePipe's argument-check branch.
// EXHAUST/RESTORE IS A PAIR, AND A `restore` WITH NO `exhaust` IN EFFECT MUST DO NOTHING.
//
// THIS FIXED A CRASH THAT HAD BEEN BLAMED ON NASA -- see the C half's copy of this comment for the
// measurements. In short: ten exhaust sites, sixteen restore sites, so six restores ran with no
// exhaust in effect and each wrote a STALE saved tail into a bump allocator that had moved on. One
// of them rewound SB's pool to EMPTY while twenty-one destination descriptors were linked into
// live routes, so those blocks were handed out twice and the second owner wrote over the first. A
// route's destination node ended up with `Next` = 0x809, which is EVS's long-event MsgId.
// CFE_SB_DeletePipe was blamed because it is the only function that walks every route.
U0 es_pool_exhaust(U32 Handle)
{
  CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(Handle);
  if (r != NULL && !es_pool_exhausted) {
    es_pool_saved_tail = r->Pool.TailPosition;
    r->Pool.TailPosition = r->Pool.PoolMaxOffset;
    es_pool_exhausted = TRUE;
  }
}

U0 es_pool_restore(U32 Handle)
{
  CFE_ES_MemPoolRecord_t *r = CFE_ES_LocateMemPoolRecordByID(Handle);
  if (r != NULL && es_pool_exhausted) {
    r->Pool.TailPosition = es_pool_saved_tail;
    es_pool_exhausted = FALSE;
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

// evs_delays COUNTS CALLS, where evs_delay_ms SUMS MILLISECONDS, and MM is why both exist:
// MM_SegmentBreak delays for MM_INTERNAL_PROCESSOR_CYCLE, which is 0 in this configuration, so
// the millisecond total is a zero against a zero and asserts nothing at all.
I64 evs_delays;

I32 OS_TaskDelay(U32 millisecond)
{
  ++evs_delays;
  evs_delay_ms += millisecond;
  return OS_SUCCESS;
}

// OS_strnlen IS NASA'S OWN BODY, not a stub standing in for one. OSAL is not gated in THIS
// driver -- every OS_* here is a simulation -- but this function touches no operating system at
// all, and mm_utils.c's MM_ResolveSymAddr decides between "the offset IS the address" and "look
// the symbol up" on its answer. A simulation would be this port inventing that decision. The
// gated translation lives in Kernel/Cfs/osal/osapi_common.HC and the OSAL differential gate is
// what compares it; this is the same body, written as a scan because HolyC has no memchr.
I64 OS_strnlen(U8 *s, I64 maxlen)
{
  I64 i = 0;
  while (i < maxlen && s[i])
    i++;
  return i;
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
// CS_SbInit hard-codes its pipe name, and the simulated OS_QueueCreate rejects a duplicate the way
// NASA's OSAL does -- so an exercise that needs CreatePipe to succeed TWICE has to free the name in
// between. This frees only the NAME, leaving the cFE pipe record registered, because the thing under
// test is CS_SbInit's arms and not SB's bookkeeping.
U0 sb_forget_queue_name(U8 *name)
{
  I64 i;
  for (i = 1; i < SBQ_MAX; i++) {
    if (sbq[i].Created && !StrCmp(sbq[i].Name, name)) {
      sbq[i].Name[0] = '\0';
    }
  }
}

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
// ======================= CS, step 1 of three: cs_utils.c ======================
//
// The twenty-six functions of CS's utility layer, in NASA's own order. Nothing here needs table
// services or a child task; those are the two blocks after it.
//
// ITS OWN FUNCTION, ON BOTH HALVES, and only this half needs it to be: written as a block inside
// main() this section grew that frame enough to make a FILE-SCOPE `&function` initialiser read as
// zero, and the transcript died 1,900 lines earlier at `cp->Algorithm(...)` in the crc section
// with `TRAP mcause=0x1 (insn-fault) mepc=0x0`. That is the open limit recorded in
// docs/HOLYC_STRUCT_LIMITS.md as a stack frame zeroing a global, third sighting, and the measured
// fix is exactly this: a called function gets its own frame and costs main() nothing. The
// diagnosis was cheap only because the shape was already written down -- a section JUST added,
// plus a trap at mepc=0 somewhere else, plus a function POINTER at the fault site.
U0 cs_block_utils()
{
    CS_TableWrapper_t *tw;
    CS_Res_EepromMemory_Table_Entry_t *re;
    CS_Def_EepromMemory_Table_Entry_t *de;
    CS_Res_Tables_Table_Entry_t *rt;
    CS_Def_Tables_Table_Entry_t *dt;
    CS_Res_App_Table_Entry_t *ra;
    CS_Def_App_Table_Entry_t *da;
    U16 st;
    Bool csb;
    I64 k;

    cs_fill_sources();
    cs_setup();

    // --- CS_CheckGenericNameMatch, and the two wrappers over it. The NULL-safety is the whole
    // point: four of the six wrappers have no DefTableName at all, so
    // CS_CheckDefTableNameMatch(name, CS_ChecksumType_CFECORE) asks whether a name matches
    // NULL. strcmp would fault.
    S("csu_namematch ");
    D(CS_CheckGenericNameMatch(NULL, NULL));
    S(" ");
    D(CS_CheckGenericNameMatch(NULL, "DefEepromTbl"));
    S(" ");
    D(CS_CheckGenericNameMatch("DefEepromTbl", "DefEepromTbl"));
    S(" ");
    D(CS_CheckGenericNameMatch("DefEepromTbl", "DefMemoryTbl"));
    S("\n");
    S("csu_tblnamematch d=");
    D(CS_CheckDefTableNameMatch("DefEepromTbl", CS_ChecksumType_EEPROM_TABLE));
    D(CS_CheckDefTableNameMatch("ResEepromTbl", CS_ChecksumType_EEPROM_TABLE));
    D(CS_CheckDefTableNameMatch("DefEepromTbl", CS_ChecksumType_CFECORE));
    S(" r=");
    D(CS_CheckResTableNameMatch("ResEepromTbl", CS_ChecksumType_EEPROM_TABLE));
    D(CS_CheckResTableNameMatch("DefEepromTbl", CS_ChecksumType_EEPROM_TABLE));
    D(CS_CheckResTableNameMatch("ResEepromTbl", CS_ChecksumType_OSCORE));
    S("\n");

    // --- CS_GetDefEntryAddr and CS_GetResEntryAddr. The answers are POINTERS, so every line is
    // a comparison against the array this driver handed the wrapper -- see the note on cs_src_a
    // above. The fourth column is the one that matters: index 16 is one past the end of a
    // 16-entry table and must be NULL, because that NULL return is the ONLY terminator eleven
    // `while (true)` loops in cs_utils.c have.
    tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
    S("csu_entryaddr def=");
    D(CS_GetDefEntryAddr(tw, 0) == &cs_def_eep[0]);
    D(CS_GetDefEntryAddr(tw, 1) == &cs_def_eep[1]);
    D(CS_GetDefEntryAddr(tw, 15) == &cs_def_eep[15]);
    D(CS_GetDefEntryAddr(tw, 16) == NULL);
    S(" res=");
    D(CS_GetResEntryAddr(tw, 0) == &cs_res_eep[0]);
    D(CS_GetResEntryAddr(tw, 1) == &cs_res_eep[1]);
    D(CS_GetResEntryAddr(tw, 15) == &cs_res_eep[15]);
    D(CS_GetResEntryAddr(tw, 16) == NULL);
    S(" codeseg=");
    // The cFE core wrapper has NO definition table -- DefAddr is NULL -- and ONE results
    // entry, which is CS_AppData.CfeCoreCodeSeg itself.
    D(CS_GetDefEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_CFECORE], 0) == NULL);
    D(CS_GetResEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_CFECORE], 1) == NULL);
    S("\n");
    // AND THE ODD-SIZED TABLES, whose stride is 42 and 22 rather than a multiple of 8 -- the
    // arithmetic tests/exec/cases/e_tbl_wrapper_idiom.hc measures in isolation, here through
    // the generic indexer every CS loop goes through.
    S("csu_oddstride tbl=");
    D(CS_GetTablesDefEntry(1) == &cs_def_tbl[1]);
    D(CS_GetTablesDefEntry(23) == &cs_def_tbl[23]);
    S(" app=");
    D(CS_GetAppDefEntry(1) == &cs_def_app[1]);
    D(CS_GetAppDefEntry(23) == &cs_def_app[23]);
    S("\n");

    // --- CS_StateValid, and the four states. ENABLED and DISABLED are commandable; EMPTY and
    // UNDEFINED are not, and that distinction is what makes CS_SetGenericEntryState refuse
    // twice.
    S("csu_statevalid ");
    D(CS_StateValid(CS_ChecksumState_EMPTY));
    D(CS_StateValid(CS_ChecksumState_ENABLED));
    D(CS_StateValid(CS_ChecksumState_DISABLED));
    D(CS_StateValid(CS_ChecksumState_UNDEFINED));
    S("\n");

    // --- CS_SetGenericEntryState, the generic poke. The THREE refusals and the one write, and
    // each line prints what the entry's State is AFTERWARDS -- a return value saying "I
    // refused" is not evidence that nothing was written.
    de = &cs_def_eep[3];
    de->State = CS_ChecksumState_EMPTY;
    st = CS_SetGenericEntryState(de, 8, CS_ChecksumState_ENABLED);
    S("csu_setgeneric from_empty prev=");
    D(st);
    S(" now=");
    D(de->State);
    S("\n");
    de->State = CS_ChecksumState_ENABLED;
    st = CS_SetGenericEntryState(de, 8, CS_ChecksumState_DISABLED);
    S("csu_setgeneric enabled_to_disabled prev=");
    D(st);
    S(" now=");
    D(de->State);
    S("\n");
    st = CS_SetGenericEntryState(de, 8, CS_ChecksumState_EMPTY);
    S("csu_setgeneric to_empty prev=");
    D(st);
    S(" now=");
    D(de->State);
    S("\n");
    // AN OFFSET OTHER THAN ZERO IS THE REASON DefStateOffset EXISTS. The tables and app
    // entries keep State at offset 0 and the EEPROM/Memory entry keeps it at 8; this is the
    // same function reaching both.
    dt = &cs_def_tbl[2];
    dt->State = CS_ChecksumState_DISABLED;
    st = CS_SetGenericEntryState(dt, 0, CS_ChecksumState_ENABLED);
    S("csu_setgeneric tbl_off0 prev=");
    D(st);
    S(" now=");
    D(dt->State);
    S("\n");

    // --- CS_SetDefEntryState, which is the above PLUS two side effects, and they only happen
    // when the state actually MOVED. ResTblPtr is aimed at a results entry with work in
    // progress; a real move clears it, a no-op move leaves it.
    tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
    tw->ResTblPtr = &cs_res_tbl[5];
    cs_res_tbl[5].ByteOffset = 40;
    cs_res_tbl[5].TempChecksumValue = 0x1234;
    cs_res_tbl[5].ComputedYet = TRUE;
    de = &cs_def_eep[4];
    de->State = CS_ChecksumState_ENABLED;
    st = CS_SetDefEntryState(tw, de, CS_ChecksumState_DISABLED);
    S("csu_setdef moved prev=");
    D(st);
    S(" now=");
    D(de->State);
    S(" off=");
    D(cs_res_tbl[5].ByteOffset);
    S(" temp=");
    D(cs_res_tbl[5].TempChecksumValue);
    S(" yet=");
    D(cs_res_tbl[5].ComputedYet);
    S("\n");
    cs_res_tbl[5].ByteOffset = 40;
    st = CS_SetDefEntryState(tw, de, CS_ChecksumState_DISABLED);
    S("csu_setdef same prev=");
    D(st);
    S(" now=");
    D(de->State);
    S(" off=");
    D(cs_res_tbl[5].ByteOffset);
    S("\n");
    // AND WITH NO ResTblPtr AT ALL, which is the state five of the six wrappers are in until a
    // tables table names one of CS's own tables. CS_ResetTablesTblResultEntry is NULL-safe for
    // exactly this.
    tw->ResTblPtr = NULL;
    de->State = CS_ChecksumState_DISABLED;
    st = CS_SetDefEntryState(tw, de, CS_ChecksumState_ENABLED);
    S("csu_setdef noresptr prev=");
    D(st);
    S(" now=");
    D(de->State);
    S("\n");

    // --- CS_GetTableTypeAsString, all six plus the default. The default arm is unreachable
    // through CS's own code because every caller passes &CS_AppData.Tbl[n]; CS_GetTableId is a
    // pointer SUBTRACTION, so a wrapper one past the end lands there rather than indexing off a
    // jump table.
    S("csu_typestr");
    for (k = 0; k < CS_NUM_TABLES; ++k) {
      S(" ");
      S(CS_GetTableTypeAsString(&CS_AppData.Tbl[k]));
    }
    S(" ");
    // `CS_AppData.Tbl + CS_NUM_TABLES`, NOT `&CS_AppData.Tbl[0] + CS_NUM_TABLES`. The second
    // spelling was the first draft and it produced the only transcript diff this whole block had:
    // adding an integer to `&array[i]` scales by EIGHT rather than by the element size, so
    // 6 * 8 = 48 bytes is still inside a 112-byte element 0, CS_GetTableId answered 0, and the
    // line read "cFE Core" where NASA's C read "Undef". A second surface of the limit
    // docs/HOLYC_STRUCT_LIMITS.md #4 records, pinned by
    // tests/exec/cases/e_amp_index_plus_int.hc.
    S(CS_GetTableTypeAsString(CS_AppData.Tbl + CS_NUM_TABLES));
    S("\n");
    // CS_GetTableId and CS_CheckTableId, the two halves of the pointer arithmetic.
    S("csu_tableid ");
    D(CS_GetTableId(&CS_AppData.Tbl[0]));
    S(" ");
    D(CS_GetTableId(&CS_AppData.Tbl[5]));
    S(" ");
    D(CS_CheckTableId(&CS_AppData.Tbl[4], CS_ChecksumType_TABLES_TABLE));
    S(" ");
    D(CS_CheckTableId(&CS_AppData.Tbl[4], CS_ChecksumType_APP_TABLE));
    S("\n");

    // --- THE SIX Zero*TempValues. Poison every entry first, so a function that cleared nothing
    // and a function that cleared everything are distinguishable -- and print the LAST entry as
    // well as the first, because a loop that stopped after one would otherwise look right.
    for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k) {
      cs_res_eep[k].TempChecksumValue = 0xAA00 + k;
      cs_res_eep[k].ByteOffset = 0xBB00 + k;
      cs_res_mem[k].TempChecksumValue = 0xCC00 + k;
      cs_res_mem[k].ByteOffset = 0xDD00 + k;
    }
    for (k = 0; k < CS_MAX_NUM_TABLES_TABLE_ENTRIES; ++k) {
      cs_res_tbl[k].TempChecksumValue = 0xEE00 + k;
      cs_res_tbl[k].ByteOffset = 0xFF00 + k;
      cs_res_app[k].TempChecksumValue = 0x1100 + k;
      cs_res_app[k].ByteOffset = 0x2200 + k;
    }
    CS_AppData.CfeCoreCodeSeg.TempChecksumValue = 0x3300;
    CS_AppData.CfeCoreCodeSeg.ByteOffset = 0x4400;
    CS_AppData.OSCodeSeg.TempChecksumValue = 0x5500;
    CS_AppData.OSCodeSeg.ByteOffset = 0x6600;
    CS_ZeroEepromTempValues();
    CS_ZeroMemoryTempValues();
    CS_ZeroTablesTempValues();
    CS_ZeroAppTempValues();
    CS_ZeroCfeCoreTempValues();
    CS_ZeroOSTempValues();
    S("csu_zerotemp eep=");
    D(cs_res_eep[0].TempChecksumValue);
    S(",");
    D(cs_res_eep[0].ByteOffset);
    S(",");
    D(cs_res_eep[15].TempChecksumValue);
    S(",");
    D(cs_res_eep[15].ByteOffset);
    S(" mem=");
    D(cs_res_mem[15].TempChecksumValue);
    S(",");
    D(cs_res_mem[15].ByteOffset);
    S(" tbl=");
    D(cs_res_tbl[23].TempChecksumValue);
    S(",");
    D(cs_res_tbl[23].ByteOffset);
    S(" app=");
    D(cs_res_app[23].TempChecksumValue);
    S(",");
    D(cs_res_app[23].ByteOffset);
    S(" seg=");
    D(CS_AppData.CfeCoreCodeSeg.TempChecksumValue);
    S(",");
    D(CS_AppData.CfeCoreCodeSeg.ByteOffset);
    S(",");
    D(CS_AppData.OSCodeSeg.TempChecksumValue);
    S(",");
    D(CS_AppData.OSCodeSeg.ByteOffset);
    S("\n");

    // --- CS_InitializeDefaultTables, the cold-boot fallback. Poisoned first, and the two NAME
    // tables are checked at Name[0] AND Name[1]: NASA clears only the first byte, so a
    // translation that cleared the whole name would pass a weaker check and fail this one.
    for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k) {
      CS_AppData.DefaultEepromDefTable[k].State = CS_ChecksumState_ENABLED;
      CS_AppData.DefaultEepromDefTable[k].NumBytesToChecksum = 99;
      CS_AppData.DefaultEepromDefTable[k].StartAddress = 0x1000;
      CS_AppData.DefaultMemoryDefTable[k].State = CS_ChecksumState_ENABLED;
      CS_AppData.DefaultMemoryDefTable[k].NumBytesToChecksum = 98;
      CS_AppData.DefaultMemoryDefTable[k].StartAddress = 0x2000;
    }
    for (k = 0; k < CS_MAX_NUM_TABLES_TABLE_ENTRIES; ++k) {
      CS_AppData.DefaultTablesDefTable[k].State = CS_ChecksumState_ENABLED;
      CS_AppData.DefaultTablesDefTable[k].Name[0] = 'Z';
      CS_AppData.DefaultTablesDefTable[k].Name[1] = 'Y';
      CS_AppData.DefaultAppDefTable[k].State = CS_ChecksumState_ENABLED;
      CS_AppData.DefaultAppDefTable[k].Name[0] = 'W';
      CS_AppData.DefaultAppDefTable[k].Name[1] = 'V';
    }
    CS_InitializeDefaultTables();
    S("csu_initdefault eep=");
    D(CS_AppData.DefaultEepromDefTable[15].State);
    S(",");
    D(CS_AppData.DefaultEepromDefTable[15].NumBytesToChecksum);
    S(",");
    D(CS_AppData.DefaultEepromDefTable[15].StartAddress);
    S(" mem=");
    D(CS_AppData.DefaultMemoryDefTable[15].State);
    S(",");
    D(CS_AppData.DefaultMemoryDefTable[15].NumBytesToChecksum);
    S(",");
    D(CS_AppData.DefaultMemoryDefTable[15].StartAddress);
    S(" tbl=");
    D(CS_AppData.DefaultTablesDefTable[23].State);
    S(",");
    D(CS_AppData.DefaultTablesDefTable[23].Name[0]);
    S(",");
    D(CS_AppData.DefaultTablesDefTable[23].Name[1]);
    S(" app=");
    D(CS_AppData.DefaultAppDefTable[23].State);
    S(",");
    D(CS_AppData.DefaultAppDefTable[23].Name[0]);
    S(",");
    D(CS_AppData.DefaultAppDefTable[23].Name[1]);
    S("\n");

    // --- CS_GoToNextTable, seven calls from table 0. The seventh is the wrap, and the
    // PassCounter increment on it is the ONLY place in CS that counter moves.
    CS_AppData.HkPacket.Payload.CurrentCSTable = 0;
    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 9;
    CS_AppData.HkPacket.Payload.PassCounter = 0;
    S("csu_gotonext");
    for (k = 0; k < 7; ++k) {
      CS_GoToNextTable();
      S(" ");
      D(CS_AppData.HkPacket.Payload.CurrentCSTable);
      S("/");
      D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
      S("/");
      D(CS_AppData.HkPacket.Payload.PassCounter);
    }
    S("\n");

    // --- THE FOUR BY-NAME LOOKUPS, and their asymmetry. The two RESULTS lookups accept
    // anything that is not EMPTY; the two DEFINITION lookups require CS_StateValid. So an
    // UNDEFINED entry -- CS looked and could not find what was named -- is findable in the
    // results table and NOT in the definition table, which is what lets "report its baseline"
    // answer while "enable it" refuses. Four columns per line: a hit, a miss, the UNDEFINED
    // case, and an EMPTY entry whose name still matches.
    StrNCpy(cs_res_tbl[2].Name, "CS.ResTablesTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_res_tbl[2].State = CS_ChecksumState_ENABLED;
    StrNCpy(cs_res_tbl[3].Name, "CS.Undef", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_res_tbl[3].State = CS_ChecksumState_UNDEFINED;
    StrNCpy(cs_res_tbl[4].Name, "CS.Empty", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_res_tbl[4].State = CS_ChecksumState_EMPTY;
    rt = NULL;
    S("csu_restbl_byname hit=");
    D(CS_GetTableResTblEntryByName(&rt, "CS.ResTablesTbl"));
    S("@");
    D(rt == &cs_res_tbl[2]);
    rt = NULL;
    S(" miss=");
    D(CS_GetTableResTblEntryByName(&rt, "CS.Nope"));
    S(" undef=");
    D(CS_GetTableResTblEntryByName(&rt, "CS.Undef"));
    S(" empty=");
    D(CS_GetTableResTblEntryByName(&rt, "CS.Empty"));
    S("\n");

    StrNCpy(cs_def_tbl[6].Name, "CS.DefTablesTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_def_tbl[6].State = CS_ChecksumState_DISABLED;
    StrNCpy(cs_def_tbl[7].Name, "CS.Undef", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_def_tbl[7].State = CS_ChecksumState_UNDEFINED;
    dt = NULL;
    S("csu_deftbl_byname hit=");
    D(CS_GetTableDefTblEntryByName(&dt, "CS.DefTablesTbl"));
    S("@");
    D(dt == &cs_def_tbl[6]);
    dt = NULL;
    S(" miss=");
    D(CS_GetTableDefTblEntryByName(&dt, "CS.Nope"));
    S(" undef=");
    D(CS_GetTableDefTblEntryByName(&dt, "CS.Undef"));
    S("\n");

    StrNCpy(cs_res_app[1].Name, "CS", CFE_MISSION_MAX_API_LEN);
    cs_res_app[1].State = CS_ChecksumState_ENABLED;
    ra = NULL;
    S("csu_resapp_byname hit=");
    D(CS_GetAppResTblEntryByName(&ra, "CS"));
    S("@");
    D(ra == &cs_res_app[1]);
    ra = NULL;
    S(" miss=");
    D(CS_GetAppResTblEntryByName(&ra, "NOPE"));
    S("\n");

    StrNCpy(cs_def_app[8].Name, "TO_LAB_APP", CFE_MISSION_MAX_API_LEN);
    cs_def_app[8].State = CS_ChecksumState_ENABLED;
    da = NULL;
    S("csu_defapp_byname hit=");
    D(CS_GetAppDefTblEntryByName(&da, "TO_LAB_APP"));
    S("@");
    D(da == &cs_def_app[8]);
    da = NULL;
    S(" miss=");
    D(CS_GetAppDefTblEntryByName(&da, "NOPE"));
    S("\n");

    // --- THE FOUR CS_FindEnabled*. They advance CurrentEntryInTable as a SIDE EFFECT, which is
    // how a cycle resumes where the last one stopped -- so each line prints the counter as well
    // as which entry came back. The second call on each is the exhausted case: NULL, with the
    // counter parked at the table bound.
    for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k) {
      cs_res_eep[k].State = CS_ChecksumState_DISABLED;
    }
    cs_res_eep[5].State = CS_ChecksumState_ENABLED;
    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
    re = CS_FindEnabledEepromEntry();
    S("csu_findeep at=");
    D(re == &cs_res_eep[5]);
    S(" cur=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 6;
    re = CS_FindEnabledEepromEntry();
    S(" exhausted=");
    D(re == NULL);
    S(" cur=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    S("\n");

    cs_res_mem[0].State = CS_ChecksumState_ENABLED;
    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
    re = CS_FindEnabledMemoryEntry();
    S("csu_findmem at=");
    D(re == &cs_res_mem[0]);
    S(" cur=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    S("\n");

    cs_res_tbl[2].State = CS_ChecksumState_ENABLED;
    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
    rt = CS_FindEnabledTablesEntry();
    S("csu_findtbl at=");
    D(rt == &cs_res_tbl[2]);
    S(" cur=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    S("\n");

    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
    ra = CS_FindEnabledAppEntry();
    S("csu_findapp at=");
    D(ra == &cs_res_app[1]);
    S(" cur=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    S("\n");

    // --- CS_ResetTablesTblResultEntry, both arms. The NULL one is not decoration: five of the
    // six wrappers have no ResTblPtr until a tables table names a CS table.
    cs_res_tbl[9].ByteOffset = 7;
    cs_res_tbl[9].TempChecksumValue = 8;
    cs_res_tbl[9].ComputedYet = TRUE;
    CS_ResetTablesTblResultEntry(&cs_res_tbl[9]);
    CS_ResetTablesTblResultEntry(NULL);
    S("csu_resetres off=");
    D(cs_res_tbl[9].ByteOffset);
    S(" temp=");
    D(cs_res_tbl[9].TempChecksumValue);
    S(" yet=");
    D(cs_res_tbl[9].ComputedYet);
    S("\n");

    // --- CS_CheckRecomputeOneshot, the guard every command handler calls first. It increments
    // the error counter ITSELF, which is why a handler that forgets to return would count one
    // failure twice -- so the counter is printed, not just the answer.
    //
    // THE CALL IS HOISTED OUT OF THE PRINT, both halves, and this is the FOURTH time that trap
    // has been hit in this port: C evaluates every argument before printing anything, so an
    // argument that SENDS AN EVENT emits its line first, while HolyC's S()/D() pair prints the
    // label and then the event lands mid-line. Reading CommandErrorCounter in the same call
    // would be worse again -- the order of evaluation against the call that increments it is
    // unspecified in C.
    CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
    CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
    CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
    csb = CS_CheckRecomputeOneshot();
    S("csu_recompguard idle=");
    D(csb);
    S(" err=");
    D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
    S("\n");
    CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
    csb = CS_CheckRecomputeOneshot();
    S("csu_recompguard recomp=");
    D(csb);
    S(" err=");
    D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
    S("\n");
    CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
    CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
    csb = CS_CheckRecomputeOneshot();
    S("csu_recompguard oneshot=");
    D(csb);
    S(" err=");
    D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
    S("\n");
    CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
}

// ===================== CS, step 1 of three: cs_compute.c =====================
//
// The chunking engine, two of the three typed wrappers over it, and the four background walks
// that use them. CS_ComputeTables goes in the cs_table_processing block with the rest of the
// table-services path, and so do ALL FOUR CHILD TASKS -- a first draft of this header claimed
// three of them were here and none was, which is the kind of comment a reader believes.
//
// NOTHING CALLS CS_DoChecksumChunk, CS_IsChecksumComplete OR CS_CheckOrUpdateReference DIRECTLY,
// and that is deliberate rather than a gap. All three take a CS_LocalChecksumState_t, which NASA
// declares inside cs_compute.c and no header exports; reaching them would mean re-declaring a
// private type here and keeping the copy in step with NASA's. Every arm of all three is reachable
// through CS_ComputeEepromMemory, which is also how CS itself reaches them:
//
//   the clamp to MaxBytesPerCycle        a 200-byte region on a 64-byte budget: four cycles
//   the "start again at beginning" arm   a region whose SIZE SHRANK below ByteOffset
//   reference not yet computed           the first pass to completion records the baseline
//   reference matches                    the second pass over unchanged bytes
//   reference differs                    one byte poked, and the miscompare is CS_ERROR
//
// EVERY CHECKSUM IS PRINTED IN DECIMAL, not hex, and only because the HolyC half's print helpers
// are S() and D() plus a two-digit H2(). A four- and an eight-digit zero-padded hex helper would
// be two more pieces of driver to keep identical on both sides for no gain -- a CRC compares the
// same either way.
//
// AND THE BYTES ARE cs_src_a AND cs_src_b, not a literal address. See the note on them above:
// CFE_ES_CalculateCRC takes a raw pointer, so this is the one block where the two halves have to
// be reading identical memory rather than merely agreeing about a number.
U0 cs_block_compute()
{
 CS_Res_EepromMemory_Table_Entry_t *re;
 CS_Res_App_Table_Entry_t *ra;
 U32 cv;
 Bool done;
 I32 rc;
 I64 k;
 Bool csb;

  cs_fill_sources();
  cs_setup();

  // --- CS_ComputeEepromMemory, a 200-byte region on a 64-byte budget. Four calls: 64, 128,
  // 192, 200. Each line prints the status, the done flag, the resume offset, the running
  // partial and the baseline -- because "it returned CFE_SUCCESS" says nothing about whether
  // the position advanced.
  re = &cs_res_eep[0];
  re->State = CS_ChecksumState_ENABLED;
  re->StartAddress = cs_src_a;
  re->NumBytesToChecksum = 200;
  for (k = 0; k < 4; ++k) {
    cv = 0;
    done = FALSE;
    rc = CS_ComputeEepromMemory(re, &cv, &done);
    S("csc_eep[");
    D(k);
    S("] rc=");
    D(rc);
    S(" done=");
    D(done);
    S(" off=");
    D(re->ByteOffset);
    S(" temp=");
    D(re->TempChecksumValue);
    S(" cv=");
    D(cv);
    S(" cmp=");
    D(re->ComparisonValue);
    S(" yet=");
    D(re->ComputedYet);
    S("\n");
  }
  // THE ADDRESS IS WRITTEN BACK EVERY CYCLE, unchanged -- a no-op here and NOT one in
  // CS_ComputeTables, which shares the export block's shape. Asserted as a comparison.
  S("csc_eep_addr same=");
  D(re->StartAddress == cs_src_a);
  S(" size=");
  D(re->NumBytesToChecksum);
  S("\n");

  // --- A SECOND COMPLETE PASS over unchanged bytes: the reference MATCHES. Four more calls,
  // and only the last one can compare, because only a complete pass reaches
  // CS_CheckOrUpdateReference's body.
  for (k = 0; k < 4; ++k) {
    cv = 0;
    done = FALSE;
    rc = CS_ComputeEepromMemory(re, &cv, &done);
  }
  S("csc_eep_match rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" cv=");
  D(cv);
  S(" cmp=");
  D(re->ComparisonValue);
  S("\n");

  // --- ONE BYTE POKED, and the third pass MISCOMPARES. This is the whole purpose of CS.
  cs_src_a[100] ^= 0xFF;
  for (k = 0; k < 4; ++k) {
    cv = 0;
    done = FALSE;
    rc = CS_ComputeEepromMemory(re, &cv, &done);
  }
  S("csc_eep_miscompare rc=");
  D(rc);
  S(" cv=");
  D(cv);
  S(" cmp=");
  D(re->ComparisonValue);
  S("\n");
  cs_src_a[100] ^= 0xFF;

  // --- THE SIZE SHRINKS BELOW ByteOffset, which is the only way to reach
  // CS_DoChecksumChunk's "start again at beginning" arm -- and the reason
  // CS_IsChecksumComplete is written `>=` rather than `==`. Left mid-walk at 64, then told the
  // region is 32 bytes: the next cycle restarts from zero AND completes, so the baseline is
  // replaced rather than compared.
  re->ByteOffset = 0;
  re->TempChecksumValue = 0;
  re->ComputedYet = FALSE;
  cv = 0;
  done = FALSE;
  CS_ComputeEepromMemory(re, &cv, &done);
  S("csc_eep_midwalk off=");
  D(re->ByteOffset);
  S(" done=");
  D(done);
  S("\n");
  re->NumBytesToChecksum = 32;
  cv = 0;
  done = FALSE;
  rc = CS_ComputeEepromMemory(re, &cv, &done);
  S("csc_eep_shrunk rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" off=");
  D(re->ByteOffset);
  S(" cv=");
  D(cv);
  S(" cmp=");
  D(re->ComparisonValue);
  S("\n");

  // --- A ZERO-LENGTH REGION. NumBytesThisCycle is zero, CFE_ES_CalculateCRC returns the input
  // CRC unchanged, and the entry is COMPLETE after one cycle rather than looping -- which is
  // what keeps an empty table entry from wedging the background walk.
  re = &cs_res_eep[1];
  re->State = CS_ChecksumState_ENABLED;
  re->StartAddress = cs_src_a;
  re->NumBytesToChecksum = 0;
  cv = 0;
  done = FALSE;
  rc = CS_ComputeEepromMemory(re, &cv, &done);
  S("csc_eep_empty rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" off=");
  D(re->ByteOffset);
  S(" cv=");
  D(cv);
  S(" yet=");
  D(re->ComputedYet);
  S("\n");

  // --- CS_ComputeApp, the RESUME path: a results entry that already has an address and a size
  // never calls CS_RefreshAppSizeAndAddr. 120 bytes on a 64-byte budget, so two cycles.
  ra = &cs_res_app[0];
  ra->State = CS_ChecksumState_ENABLED;
  ra->StartAddress = cs_src_b;
  ra->NumBytesToChecksum = 120;
  StrNCpy(ra->Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  for (k = 0; k < 2; ++k) {
    cv = 0;
    done = FALSE;
    rc = CS_ComputeApp(ra, &cv, &done);
    S("csc_app[");
    D(k);
    S("] rc=");
    D(rc);
    S(" done=");
    D(done);
    S(" off=");
    D(ra->ByteOffset);
    S(" cv=");
    D(cv);
    S(" cmp=");
    D(ra->ComparisonValue);
    S("\n");
  }

  // --- CS_ComputeApp, the LOOKUP path: StartAddress zero sends it through
  // CS_RefreshAppSizeAndAddr, which asks ES for the module's code segment. The driver's
  // simulated OS_ModuleInfo reports a FIXED 0x11110000 by default -- not memory either half may
  // read -- so it is pointed at cs_src_b for the duration and put back.
  es_modinfo_code_addr = cs_src_b;
  es_modinfo_code_size = 64;
  ra = &cs_res_app[2];
  ra->State = CS_ChecksumState_ENABLED;
  ra->StartAddress = 0;
  ra->NumBytesToChecksum = 0;
  StrNCpy(ra->Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  cv = 0;
  done = FALSE;
  rc = CS_ComputeApp(ra, &cv, &done);
  S("csc_app_lookup rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" at=");
  D(ra->StartAddress == cs_src_b);
  S(" size=");
  D(ra->NumBytesToChecksum);
  S(" cv=");
  D(cv);
  S("\n");

  // THE PLATFORM ARM: OS_ModuleInfo succeeds and clears its own `valid` flag, so
  // AddressesAreValid is FALSE, CS sends a DEBUG event and returns CS_ERROR -- which
  // CS_RefreshAppSizeAndAddr then turns into CS_ERR_NOT_FOUND. Nothing is wrong; the platform
  // simply cannot say where the code is.
  es_modinfo_valid = 0;
  ra = &cs_res_app[3];
  ra->State = CS_ChecksumState_ENABLED;
  ra->StartAddress = 0;
  ra->NumBytesToChecksum = 0;
  StrNCpy(ra->Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  cv = 0;
  done = FALSE;
  rc = CS_ComputeApp(ra, &cv, &done);
  S("csc_app_notvalid rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" addr=");
  D(ra->StartAddress == 0);
  S("\n");
  es_modinfo_valid = 1;

  // A NAME THAT IS A LIBRARY AND NOT AN APP. CS tries the app table, gets
  // CFE_ES_ERR_NAME_NOT_FOUND, and tries the LIBRARY table -- which is how a mission checksums
  // code that has no task of its own.
  //
  // THIS LINE EXISTS BECAUSE A MUTATION FOUND IT MISSING. Deleting the library fallback outright
  // left the transcript unchanged: the two names driven here were a real APP (so the fallback was
  // never reached) and a name that is neither (so it ran and failed, same answer). The branch the
  // fallback exists for was asserted only by implication.
  // THE BLOCK REGISTERS ITS OWN LIBRARY RECORD and frees it again, which is the second half of
  // this finding. The first attempt named "ESLIB" -- the library the ES resource block creates --
  // and came back CS_ERR_NOT_FOUND anyway, because that block FREES its three records when it is
  // done (`rs_freed app=1 lib=1 ctr=1`). Borrowing another block's fixture is the shape recorded
  // as shared-fixture resource exhaustion, one step along: not "the table is full" but "the thing
  // I was pointing at is gone". So this owns its fixture.
  {
    CFE_ES_LibRecord_t *lrp = &CFE_ES_Global.LibTable[2];

    CFE_ES_LibRecordSetUsed(lrp, ES_LIBID(2));
    StrNCpy(lrp->LibName, "CSLIB", OS_MAX_API_NAME - 1);

    ra = &cs_res_app[6];
    ra->State = CS_ChecksumState_ENABLED;
    ra->StartAddress = 0;
    ra->NumBytesToChecksum = 0;
    StrNCpy(ra->Name, "CSLIB", CFE_MISSION_MAX_API_LEN);
    cv = 0;
    done = FALSE;
    rc = CS_ComputeApp(ra, &cv, &done);
    S("csc_app_library rc=");
    D(rc);
    S(" done=");
    D(done);
    S(" at=");
    D(ra->StartAddress == cs_src_b);
    S(" size=");
    D(ra->NumBytesToChecksum);
    S(" cv=");
    D(cv);
    S("\n");

    CFE_ES_LibRecordSetFree(lrp);
  }

  // AND A NAME THAT IS NEITHER AN APP NOR A LIBRARY: both lookups fail and CS gives up.
  ra = &cs_res_app[4];
  ra->State = CS_ChecksumState_ENABLED;
  ra->StartAddress = 0;
  ra->NumBytesToChecksum = 0;
  StrNCpy(ra->Name, "NO_SUCH_APP", CFE_MISSION_MAX_API_LEN);
  cv = 0;
  done = FALSE;
  rc = CS_ComputeApp(ra, &cv, &done);
  S("csc_app_missing rc=");
  D(rc);
  S(" done=");
  D(done);
  S("\n");
  es_modinfo_code_addr = 0x11110000;
  es_modinfo_code_size = 0x1000;

  // --- THE FOUR BACKGROUND WALKS THAT USE THIS ENGINE. cFE core and OS have ONE entry and no
  // table; EEPROM has a table AND a running total; Memory has a table and NO total, which is
  // NASA's asymmetry. Each returns whether the cycle's budget is spent.
  cs_setup();
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_ENABLED;
  CS_AppData.CfeCoreCodeSeg.State = CS_ChecksumState_ENABLED;
  CS_AppData.CfeCoreCodeSeg.StartAddress = cs_src_a;
  CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum = 64;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_CFECORE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundCfeCore();
  S("csc_bg_cfecore spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" cur=");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" base=");
  D(CS_AppData.HkPacket.Payload.CfeCoreBaseline);
  S("\n");
  // THE MISCOMPARE ARM: poke a byte and walk it again. The second walk re-reads the same 64
  // bytes, finds a different CRC and counts an error.
  CS_AppData.CfeCoreCodeSeg.ByteOffset = 0;
  cs_src_a[10] ^= 0xFF;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_CFECORE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundCfeCore();
  S("csc_bg_cfecore_bad spent=");
  D(csb);
  S(" err=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSErrCounter);
  S("\n");
  cs_src_a[10] ^= 0xFF;
  // AND THE TWO SKIP ARMS: the results entry disabled, and the whole type disabled. Both just
  // advance to the next table, and the witness is CurrentCSTable moving with no event.
  CS_AppData.CfeCoreCodeSeg.State = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_CFECORE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundCfeCore();
  S("csc_bg_cfecore_entryoff spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("\n");
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_CFECORE;
  csb = CS_BackgroundCfeCore();
  S("csc_bg_cfecore_typeoff spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("\n");

  CS_AppData.HkPacket.Payload.OSCSState = CS_ChecksumState_ENABLED;
  CS_AppData.OSCodeSeg.State = CS_ChecksumState_ENABLED;
  CS_AppData.OSCodeSeg.StartAddress = cs_src_b;
  CS_AppData.OSCodeSeg.NumBytesToChecksum = 32;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_OSCORE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundOS();
  S("csc_bg_os spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" base=");
  D(CS_AppData.HkPacket.Payload.OSBaseline);
  S("\n");

  // EEPROM: two enabled entries in a sixteen-entry table, each 32 bytes, so the walk needs
  // three cycles to reach the end -- and the THIRD is where EepromBaseline is summed from every
  // entry's ComparisonValue. An unsigned 32-bit sum, so it wraps; it is a change detector, not
  // a checksum of anything.
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  cs_res_eep[0].State = CS_ChecksumState_ENABLED;
  cs_res_eep[0].StartAddress = cs_src_a;
  cs_res_eep[0].NumBytesToChecksum = 32;
  cs_res_eep[4].State = CS_ChecksumState_ENABLED;
  cs_res_eep[4].StartAddress = cs_src_b;
  cs_res_eep[4].NumBytesToChecksum = 32;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_EEPROM_TABLE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  for (k = 0; k < 3; ++k) {
    csb = CS_BackgroundEeprom();
    S("csc_bg_eep[");
    D(k);
    S("] spent=");
    D(csb);
    S(" tbl=");
    D(CS_AppData.HkPacket.Payload.CurrentCSTable);
    S(" cur=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    S(" base=");
    D(CS_AppData.HkPacket.Payload.EepromBaseline);
    S("\n");
  }
  S("csc_bg_eep_sum cmp0=");
  D(cs_res_eep[0].ComparisonValue);
  S(" cmp4=");
  D(cs_res_eep[4].ComparisonValue);
  S(" base=");
  D(CS_AppData.HkPacket.Payload.EepromBaseline);
  S("\n");

  // MEMORY: the same shape with NO running total, which is the asymmetry. MemoryBaseline does
  // not exist in housekeeping, so the witness is that the walk completes and nothing else
  // moves.
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_ENABLED;
  cs_res_mem[2].State = CS_ChecksumState_ENABLED;
  cs_res_mem[2].StartAddress = cs_src_b;
  cs_res_mem[2].NumBytesToChecksum = 16;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_MEMORY_TABLE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundMemory();
  S("csc_bg_mem spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" cur=");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" cmp=");
  D(cs_res_mem[2].ComparisonValue);
  S("\n");
  csb = CS_BackgroundMemory();
  S("csc_bg_mem_end spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("\n");
  // AND THE TYPE DISABLED, which is the one arm the two table walks share with the code
  // segments: ResultsEntry is left NULL and the walk advances with no compute at all.
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_MEMORY_TABLE;
  csb = CS_BackgroundMemory();
  S("csc_bg_mem_off spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("\n");
}


// ================ CS, step 1 of three: cs_table_processing.c ================
//
// The four validation callbacks, the three update handlers, the name splitter, the routine-update
// sweep and the four child tasks. Everything here that needs cFE TABLE SERVICES is driven on its
// FAILURE path, which is the honest half this block can reach: CS's own tables are not registered
// until cs_init.c runs, and that is step 2. The failure paths are not filler -- "the table CS was
// told to watch is not registered any more" is what CS does for a living.
//
// THE VALIDATION ACCUMULATOR IS DRIVEN THROUGH ITS COUNTS AND THROUGH THE FIRST-ERROR RULE. A
// table with several bad entries must produce ONE error event and a summary saying how many --
// so each callback is run twice, once clean and once with two defects, and the summary line is
// the witness for both the counting and the suppression.
U0 cs_block_tblproc()
{
  CS_TableWrapper_t *tw;
  I32 rc;
  U8 appbuf[OS_MAX_API_NAME];
  U8 tblbuf[CFE_MISSION_TBL_MAX_NAME_LENGTH];
  Bool csb;
  I64 k;

  cs_fill_sources();
  cs_setup();

  // --- CS_ValidateEepromChecksumDefinitionTable. A clean table first: sixteen EMPTY entries,
  // so good=0, bad=0, unused=16 and CFE_SUCCESS.
  rc = CS_ValidateEepromChecksumDefinitionTable(cs_def_eep);
  S("cst_val_eep_clean rc=");
  D(rc);
  S("\n");
  // THEN TWO DEFECTS AND A GOOD ENTRY. Entry 1 is ENABLED with a valid range; entry 3 has a
  // state of 7, which is neither EMPTY nor commandable; entry 5 is ENABLED over a range the
  // simulated PSP refuses. Only the FIRST error gets an event, and the summary says bad=2.
  cs_def_eep[1].State = CS_ChecksumState_ENABLED;
  cs_def_eep[1].StartAddress = cs_src_a;
  cs_def_eep[1].NumBytesToChecksum = 32;
  cs_def_eep[3].State = 7;
  cs_def_eep[5].State = CS_ChecksumState_ENABLED;
  cs_def_eep[5].StartAddress = cs_src_b;
  cs_def_eep[5].NumBytesToChecksum = 16;
  rc = CS_ValidateEepromChecksumDefinitionTable(cs_def_eep);
  S("cst_val_eep_bad rc=");
  D(rc);
  S("\n");
  // AND THE MEM_RANGE ARM, which is the one error kind only the two address tables can produce.
  // es_psp_validate_rc is the driver's knob on CFE_PSP_MemValidateRange; the event prints the
  // status through CS's own ErrorMessage buffer, so this also drives StrPrintN into it.
  cs_def_eep[3].State = CS_ChecksumState_EMPTY;
  es_psp_validate_rc = -1;
  rc = CS_ValidateEepromChecksumDefinitionTable(cs_def_eep);
  S("cst_val_eep_range rc=");
  D(rc);
  S("\n");
  es_psp_validate_rc = CFE_PSP_SUCCESS;

  // --- The memory table: the same code with CFE_PSP_MEM_ANY and its own three event ids.
  cs_def_mem[2].State = CS_ChecksumState_DISABLED;
  cs_def_mem[2].StartAddress = cs_src_a;
  cs_def_mem[2].NumBytesToChecksum = 8;
  rc = CS_ValidateMemoryChecksumDefinitionTable(cs_def_mem);
  S("cst_val_mem rc=");
  D(rc);
  S("\n");

  // --- The tables table, which validates FIVE of the six error kinds. One good entry, one
  // UNTERMINATED name, one ENABLED entry with an empty name, one EMPTY entry that still has a
  // name, and one DUPLICATE of the good one. Five defects, one event, bad=4.
  StrNCpy(cs_def_tbl[0].Name, "CS.DefEepromTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  cs_def_tbl[0].State = CS_ChecksumState_ENABLED;
  rc = CS_ValidateTablesChecksumDefinitionTable(cs_def_tbl);
  S("cst_val_tbl_clean rc=");
  D(rc);
  S("\n");
  MemSet(cs_def_tbl[1].Name, 'A', CFE_MISSION_TBL_MAX_FULL_NAME_LEN); // no NUL anywhere
  cs_def_tbl[1].State = CS_ChecksumState_ENABLED;
  cs_def_tbl[2].State = CS_ChecksumState_ENABLED;
  cs_def_tbl[2].Name[0]  = '\0';
  cs_def_tbl[3].State = CS_ChecksumState_EMPTY;
  StrNCpy(cs_def_tbl[3].Name, "CS.Leftover", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  StrNCpy(cs_def_tbl[4].Name, "CS.DefEepromTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  cs_def_tbl[4].State = CS_ChecksumState_ENABLED;
  rc = CS_ValidateTablesChecksumDefinitionTable(cs_def_tbl);
  S("cst_val_tbl_bad rc=");
  D(rc);
  S("\n");
  // THE DUPLICATE ON ITS OWN, so its event is the FIRST error and therefore the one sent. The
  // position in the message comes from CS's ErrorMessage buffer and names the EARLIER entry,
  // which is the one a ground operator has to go and look at.
  MemSet(cs_def_tbl, 0, sizeof(CS_Def_Tables_Table_Entry_t) * CS_MAX_NUM_TABLES_TABLE_ENTRIES);
  StrNCpy(cs_def_tbl[2].Name, "CS.DefAppTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  cs_def_tbl[2].State = CS_ChecksumState_ENABLED;
  StrNCpy(cs_def_tbl[9].Name, "CS.DefAppTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  cs_def_tbl[9].State = CS_ChecksumState_DISABLED;
  rc = CS_ValidateTablesChecksumDefinitionTable(cs_def_tbl);
  S("cst_val_tbl_dup rc=");
  D(rc);
  S("\n");

  // --- The app table, the same five kinds over a 20-byte name.
  MemSet(cs_def_app, 0, sizeof(CS_Def_App_Table_Entry_t) * CS_MAX_NUM_APP_TABLE_ENTRIES);
  StrNCpy(cs_def_app[0].Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  cs_def_app[0].State = CS_ChecksumState_ENABLED;
  rc = CS_ValidateAppChecksumDefinitionTable(cs_def_app);
  S("cst_val_app_clean rc=");
  D(rc);
  S("\n");
  MemSet(cs_def_app[1].Name, 'B', CFE_MISSION_MAX_API_LEN);
  cs_def_app[1].State = CS_ChecksumState_ENABLED;
  rc = CS_ValidateAppChecksumDefinitionTable(cs_def_app);
  S("cst_val_app_longname rc=");
  D(rc);
  S("\n");
  MemSet(cs_def_app[1].Name, '0', CFE_MISSION_MAX_API_LEN);
  cs_def_app[1].State = CS_ChecksumState_EMPTY;

  // --- CS_ExtractNames, the "Owner.Table" splitter. Four shapes: a normal full name, no
  // separator at all (the whole string is a table name and the owner is empty), an owner longer
  // than the buffer, and a table name longer than the buffer. The two truncating cases are why
  // the function takes sizes at all.
  MemSet(cs_def_tbl, 0, sizeof(CS_Def_Tables_Table_Entry_t) * CS_MAX_NUM_TABLES_TABLE_ENTRIES);
  StrNCpy(cs_def_tbl[0].Name, "CS.DefEepromTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  CS_ExtractNames(&cs_def_tbl[0], appbuf, OS_MAX_API_NAME, tblbuf, CFE_MISSION_TBL_MAX_NAME_LENGTH);
  S("cst_extract app=[");
  S(appbuf);
  S("] tbl=[");
  S(tblbuf);
  S("]\n");
  StrNCpy(cs_def_tbl[0].Name, "NoSeparatorHere", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  CS_ExtractNames(&cs_def_tbl[0], appbuf, OS_MAX_API_NAME, tblbuf, CFE_MISSION_TBL_MAX_NAME_LENGTH);
  S("cst_extract_nosep app=[");
  S(appbuf);
  S("] tbl=[");
  S(tblbuf);
  S("]\n");
  StrNCpy(cs_def_tbl[0].Name, "AnAppNameLongerThanTwenty.T", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  CS_ExtractNames(&cs_def_tbl[0], appbuf, OS_MAX_API_NAME, tblbuf, CFE_MISSION_TBL_MAX_NAME_LENGTH);
  S("cst_extract_longapp app=[");
  S(appbuf);
  S("] tbl=[");
  S(tblbuf);
  S("]\n");
  StrNCpy(cs_def_tbl[0].Name, "A.ATableNameLongerThanSixteen", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  CS_ExtractNames(&cs_def_tbl[0], appbuf, OS_MAX_API_NAME, tblbuf, CFE_MISSION_TBL_MAX_NAME_LENGTH);
  S("cst_extract_longtbl app=[");
  S(appbuf);
  S("] tbl=[");
  S(tblbuf);
  S("]\n");

  // --- CS_ProcessNewEepromMemoryDefinitionTable, through CS_CallTableUpdateHandler so the
  // indirect call is part of the exercise rather than bypassed. The results entries are POISONED
  // first: the memset inside the handler is the whole safety property -- a ground table load
  // that REMOVES a region must stop CS checksumming it -- and a handler that copied without
  // wiping would leave the old address in the slots the new table leaves empty.
  cs_setup();
  for (k = 0; k < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; ++k) {
    cs_res_eep[k].State = CS_ChecksumState_ENABLED;
    cs_res_eep[k].StartAddress = 0xDEAD0000 + k;
    cs_res_eep[k].NumBytesToChecksum = 777;
    cs_res_eep[k].ComparisonValue = 888;
  }
  cs_def_eep[1].State = CS_ChecksumState_ENABLED;
  cs_def_eep[1].StartAddress = cs_src_a;
  cs_def_eep[1].NumBytesToChecksum = 32;
  cs_def_eep[7].State = CS_ChecksumState_DISABLED;
  cs_def_eep[7].StartAddress = cs_src_b;
  cs_def_eep[7].NumBytesToChecksum = 16;
  tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
  CS_CallTableUpdateHandler(tw);
  S("cst_proc_eep kept1=");
  D(cs_res_eep[1].StartAddress == cs_src_a);
  S(",");
  D(cs_res_eep[1].NumBytesToChecksum);
  S(",");
  D(cs_res_eep[1].State);
  S(" wiped0=");
  D(cs_res_eep[0].StartAddress);
  S(",");
  D(cs_res_eep[0].NumBytesToChecksum);
  S(",");
  D(cs_res_eep[0].State);
  S(" wiped15=");
  D(cs_res_eep[15].ComparisonValue);
  S(",");
  D(cs_res_eep[15].State);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S("\n");
  // AND THE GLOBAL STATE IS RESTORED, not left disabled -- the handler turns checksumming off
  // while it swaps the table out and puts the previous value back. Driven from DISABLED so a
  // handler that hard-coded ENABLED would be caught.
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_DISABLED;
  CS_CallTableUpdateHandler(tw);
  S("cst_proc_eep_restore state=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S("\n");
  // THE NO-ENTRIES EVENT: a definition table with nothing commandable in it.
  MemSet(cs_def_eep, 0, sizeof(CS_Def_EepromMemory_Table_Entry_t) * CS_MAX_NUM_EEPROM_TABLE_ENTRIES);
  CS_CallTableUpdateHandler(tw);
  S("cst_proc_eep_empty res0=");
  D(cs_res_eep[0].State);
  S("\n");

  // --- CS_ProcessNewAppDefinitionTable. It copies only the state and the NAME -- no address
  // and no size, because an app's code address is looked up every time -- which is the
  // asymmetry against the EEPROM handler above, and the reason both are checked for what they
  // do NOT write.
  for (k = 0; k < CS_MAX_NUM_APP_TABLE_ENTRIES; ++k) {
    cs_res_app[k].State = CS_ChecksumState_ENABLED;
    cs_res_app[k].StartAddress = 0xBEEF0000 + k;
  }
  MemSet(cs_def_app, 0, sizeof(CS_Def_App_Table_Entry_t) * CS_MAX_NUM_APP_TABLE_ENTRIES);
  StrNCpy(cs_def_app[3].Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  cs_def_app[3].State = CS_ChecksumState_ENABLED;
  tw = &CS_AppData.Tbl[CS_ChecksumType_APP_TABLE];
  CS_CallTableUpdateHandler(tw);
  S("cst_proc_app name3=[");
  S(cs_res_app[3].Name);
  S("] state3=");
  D(cs_res_app[3].State);
  S(" addr3=");
  D(cs_res_app[3].StartAddress);
  S(" state0=");
  D(cs_res_app[0].State);
  S(" addr0=");
  D(cs_res_app[0].StartAddress);
  S(" app_state=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S("\n");

  // --- CS_ProcessNewTablesDefinitionTable. The one handler that can aim a WRAPPER at a results
  // entry: if the new tables table names one of CS's own eight tables, that wrapper's ResTblPtr
  // points at the matching results entry, so CS_SetDefEntryState can later invalidate the
  // checksum of the very table it just modified. All six are cleared to NULL first, so a table
  // dropped from the new definition stops being tracked.
  //
  // THE OWNER NAME HAS TO MATCH CS'S APP NAME for that to happen, and this driver's app context
  // is not called "CS" -- so the match is driven by asking ES for the name it WILL compare
  // against and building the entry from that. A hard-coded "CS." would make this block assert
  // that the driver is called CS rather than that the handler compares the right things.
  {
    U32 aid = CFE_ES_APPID_UNDEFINED;
    U8 myname[OS_MAX_API_NAME];
    U8 full[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];

    CFE_ES_GetAppID(&aid);
    CFE_ES_GetAppName(myname, aid, OS_MAX_API_NAME);
    StrPrintN(full, CFE_MISSION_TBL_MAX_FULL_NAME_LEN, "%s.%s", myname, CS_DEF_EEPROM_TABLE_NAME);

    for (k = 0; k < CS_MAX_NUM_TABLES_TABLE_ENTRIES; ++k) {
      cs_res_tbl[k].State = CS_ChecksumState_ENABLED;
      cs_res_tbl[k].StartAddress = 0xFEED0000 + k;
    }
    MemSet(cs_def_tbl, 0, sizeof(CS_Def_Tables_Table_Entry_t) * CS_MAX_NUM_TABLES_TABLE_ENTRIES);
    StrNCpy(cs_def_tbl[6].Name, full, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_def_tbl[6].State = CS_ChecksumState_ENABLED;
    StrNCpy(cs_def_tbl[8].Name, "SomeoneElse.TheirTbl", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_def_tbl[8].State = CS_ChecksumState_DISABLED;
    // AND A RESULTS TABLE OF CS'S OWN, which is the OTHER name match in that inner loop and which
    // a mutation found unasserted: deleting the CS_CheckResTableNameMatch branch outright changed
    // nothing, because the two names here were a DEFINITION table of CS's and somebody else's
    // table. The two branches differ in a way worth pinning rather than assuming -- the DEF match
    // aims the wrapper's ResTblPtr at the entry, the RES match does NOT, it only takes the handle
    // and claims ownership.
    StrPrintN(full, CFE_MISSION_TBL_MAX_FULL_NAME_LEN, "%s.%s", myname,
              CS_RESULTS_EEPROM_TABLE_NAME);
    StrNCpy(cs_def_tbl[10].Name, full, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    cs_def_tbl[10].State = CS_ChecksumState_ENABLED;
    tw = &CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE];
    CS_CallTableUpdateHandler(tw);
    S("cst_proc_tbl name6=[");
    S(cs_res_tbl[6].Name);
    S("] owner6=");
    D(cs_res_tbl[6].IsCSOwner);
    S(" state6=");
    D(cs_res_tbl[6].State);
    S(" name8=[");
    S(cs_res_tbl[8].Name);
    S("] owner8=");
    D(cs_res_tbl[8].IsCSOwner);
    S("\n");
    S("cst_proc_tbl_res name10=[");
    S(cs_res_tbl[10].Name);
    S("] owner10=");
    D(cs_res_tbl[10].IsCSOwner);
    S(" state10=");
    D(cs_res_tbl[10].State);
    S("\n");
    // THE WRAPPER THE NAME POINTED AT now has a ResTblPtr, and the other five do not -- and NONE
    // of them points at entry 10, because a RESULTS-name match does not set it.
    S("cst_proc_tbl_resptr eep=");
    D(CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE].ResTblPtr == &cs_res_tbl[6]);
    S(" mem=");
    D(CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE].ResTblPtr == NULL);
    S(" tbl=");
    D(CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE].ResTblPtr == NULL);
    S(" app=");
    D(CS_AppData.Tbl[CS_ChecksumType_APP_TABLE].ResTblPtr == NULL);
    S(" core=");
    D(CS_AppData.Tbl[CS_ChecksumType_CFECORE].ResTblPtr == NULL);
    S(" os=");
    D(CS_AppData.Tbl[CS_ChecksumType_OSCORE].ResTblPtr == NULL);
    S("\n");
    for (k = 0; k < CS_NUM_TABLES; ++k) {
      if (CS_AppData.Tbl[k].ResTblPtr == &cs_res_tbl[10]) {
        S("cst_proc_tbl_res_BADPTR ");
        D(k);
        S("\n");
      }
    }
    S("cst_proc_tbl_res_noptr 1\n");
    // AND A TABLE DROPPED FROM THE NEW DEFINITION STOPS BEING TRACKED: run the handler again
    // over an empty definition and the pointer goes back to NULL.
    MemSet(cs_def_tbl, 0, sizeof(CS_Def_Tables_Table_Entry_t) * CS_MAX_NUM_TABLES_TABLE_ENTRIES);
    CS_CallTableUpdateHandler(tw);
    S("cst_proc_tbl_dropped eep=");
    D(CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE].ResTblPtr == NULL);
    S("\n");
  }

  // --- CS_CallTableUpdateHandler's NULL arm, which four of the six wrappers are in. It must do
  // nothing and not fault; the witness is that the cFE core wrapper's results entry is
  // untouched.
  CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum = 4242;
  CS_CallTableUpdateHandler(&CS_AppData.Tbl[CS_ChecksumType_CFECORE]);
  S("cst_nullhandler size=");
  D(CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum);
  S("\n");

  // --- CS_ComputeTables AND CS_BackgroundTables on the "not registered" path, which is what CS
  // does when a table it was told to watch is gone. CFE_TBL_GetInfo cannot find the name, so
  // CS_RefreshTableSize answers CS_ERR_NOT_FOUND, CS_ComputeTables logs its own event and
  // returns the generic error, and CS_BackgroundTables turns that into "skipping" and advances.
  // Note the SECOND memset in CS_ComputeTables is what keeps this from leaking a table address
  // per failed cycle, so the exported size is asserted back to zero.
  cs_setup();
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;
  cs_res_tbl[0].State = CS_ChecksumState_ENABLED;
  cs_res_tbl[0].NumBytesToChecksum = 0;
  cs_res_tbl[0].TblHandleID = CFE_TBL_HANDLEID_UNDEFINED;
  StrNCpy(cs_res_tbl[0].Name, "GONE.TBL", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_TABLES_TABLE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundTables();
  S("cst_bg_tbl spent=");
  D(csb);
  S(" cur=");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" size=");
  D(cs_res_tbl[0].NumBytesToChecksum);
  S(" err=");
  D(CS_AppData.HkPacket.Payload.TablesCSErrCounter);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("\n");
  // AND THE TYPE DISABLED, the arm all four table walks share.
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_TABLES_TABLE;
  csb = CS_BackgroundTables();
  S("cst_bg_tbl_off spent=");
  D(csb);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("\n");

  // --- CS_BackgroundApp, the sixth walk. Its CS_ERR_NOT_FOUND arm is the app equivalent: a
  // name that is neither an app nor a library is "skipping", not an error to retry.
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_ENABLED;
  cs_res_app[0].State = CS_ChecksumState_ENABLED;
  cs_res_app[0].StartAddress = 0;
  cs_res_app[0].NumBytesToChecksum = 0;
  StrNCpy(cs_res_app[0].Name, "NO_SUCH_APP", CFE_MISSION_MAX_API_LEN);
  CS_AppData.HkPacket.Payload.CurrentCSTable = CS_ChecksumType_APP_TABLE;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  csb = CS_BackgroundApp();
  S("cst_bg_app spent=");
  D(csb);
  S(" cur=");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" err=");
  D(CS_AppData.HkPacket.Payload.AppCSErrCounter);
  S("\n");

  // --- CS_HandleRoutineTableUpdates, which sweeps all six wrappers once per cycle. The two code
  // segments have DefEntrySize zero and are SKIPPED -- that is what keeps them out of the
  // "table update failed" event, and the zeroes in cs_utils.c's EventIdMap are load-bearing for
  // the same reason. The other four have invalid handles here, so CS_HandleTableUpdate's error
  // arm fires: four events and four global states turned off.
  cs_setup();
  rc = CS_HandleRoutineTableUpdates();
  S("cst_routine rc=");
  D(rc);
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S("\n");
  // AND THE CHILD-TASK EXCLUSION: with a recompute in progress and no one-shot, the table the
  // child task owns is skipped and the other three are not. The witness is that the owned
  // table's state is NOT turned off.
  cs_setup();
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  CS_AppData.ChildTaskTable = CS_ChecksumType_MEMORY_TABLE;
  rc = CS_HandleRoutineTableUpdates();
  S("cst_routine_child rc=");
  D(rc);
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
}


// =============== CS, step 1 of three: the four child tasks ===============
//
// A ground-commanded recompute cannot run inside a cycle -- it has to finish the whole entry --
// so it runs out of line, looping with OS_TaskDelay between chunks. All four tasks are called
// HERE from the main task's context, which has two consequences worth naming rather than hiding:
//
//   OS_TaskDelay IS SIMULATED. It counts calls and sums milliseconds and does not sleep, so a
//   four-chunk recompute costs nothing. evs_delays is the witness that the loop iterated.
//
//   CFE_ES_ExitChildTask TAKES ITS `else` ARM, because this is a main task. It syslogs "Cannot
//   Call from a cFE App Main Task" and RETURNS -- which is exactly why the four tasks can be
//   driven at all, and the four syslog lines in the transcript below are that, not a defect.
//
// THE SHAPE ALL THREE RECOMPUTE TASKS SHARE is: disable the results entry so the background walk
// cannot touch it, clear its partial state so the next pass starts from zero, disable the matching
// DEFINITION entry too, loop until done, restore both. Each is checked for the RESTORE, because a
// task that left an entry disabled would silently stop CS watching it.
U0 cs_block_child()
{
  I64 d0;
  I64 k;
  U32 cv;
  Bool done;
  U8 cs_port_saved;
  U16 cs_sent_before;

  cs_fill_sources();
  cs_setup();

  // --- CS_RecomputeEepromMemoryChildTask. The definition entry is matched by ADDRESS, not by
  // index -- `ResultsEntry->StartAddress == DefEntry->StartAddress` -- because the two tables
  // can disagree after a ground load, and disabling the wrong definition entry would silently
  // stop checksumming a region nobody asked about. Driven both ways.
  CS_AppData.ChildTaskTable = CS_ChecksumType_EEPROM_TABLE;
  CS_AppData.ChildTaskEntryID = 2;
  CS_AppData.RecomputeEepromMemoryEntryPtr = &cs_res_eep[2];
  cs_res_eep[2].State = CS_ChecksumState_ENABLED;
  cs_res_eep[2].StartAddress = cs_src_a;
  cs_res_eep[2].NumBytesToChecksum = 200;
  cs_res_eep[2].ByteOffset = 40;
  cs_res_eep[2].TempChecksumValue = 0x9999;
  cs_res_eep[2].ComputedYet = TRUE;
  cs_res_eep[2].ComparisonValue = 0x1111;
  cs_def_eep[2].State = CS_ChecksumState_ENABLED;
  cs_def_eep[2].StartAddress = cs_src_a;
  cs_def_eep[2].NumBytesToChecksum = 200;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  d0 = evs_delays;
  CS_RecomputeEepromMemoryChildTask();
  S("csh_recomp_eep state=");
  D(cs_res_eep[2].State);
  S(" def=");
  D(cs_def_eep[2].State);
  S(" off=");
  D(cs_res_eep[2].ByteOffset);
  S(" cmp=");
  D(cs_res_eep[2].ComparisonValue);
  S(" base=");
  D(CS_AppData.HkPacket.Payload.EepromBaseline);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");
  // THE ADDRESSES DISAGREE: the definition entry is left ALONE and nothing is restored to it,
  // which is what the `else { DefEntry = NULL; }` arm is for. Driven from DISABLED so that a
  // task which touched it anyway would show up as an ENABLED definition entry.
  cs_setup();
  CS_AppData.ChildTaskTable = CS_ChecksumType_MEMORY_TABLE;
  CS_AppData.ChildTaskEntryID = 1;
  CS_AppData.RecomputeEepromMemoryEntryPtr = &cs_res_mem[1];
  cs_res_mem[1].State = CS_ChecksumState_DISABLED;
  cs_res_mem[1].StartAddress = cs_src_a;
  cs_res_mem[1].NumBytesToChecksum = 64;
  cs_def_mem[1].State = CS_ChecksumState_DISABLED;
  cs_def_mem[1].StartAddress = cs_src_b; // a DIFFERENT region
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  d0 = evs_delays;
  CS_RecomputeEepromMemoryChildTask();
  S("csh_recomp_mem state=");
  D(cs_res_mem[1].State);
  S(" def=");
  D(cs_def_mem[1].State);
  S(" base=");
  D(CS_AppData.HkPacket.Payload.OSBaseline);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");
  // AND A WRAPPER WITH NO BaselineValue AT ALL -- the two table types have none, only the three
  // code-segment-and-EEPROM baselines exist in housekeeping -- so `if (tw->BaselineValue)` is
  // the guard that makes the memory recompute above write nothing. Asserted by the line before
  // this one reading OSBaseline, which must still be zero.

  // --- CS_RecomputeAppChildTask. The definition entry is matched BY NAME here, through
  // CS_GetAppDefTblEntryByName, which is a different mechanism from the address match above.
  cs_setup();
  CS_AppData.RecomputeAppEntryPtr = &cs_res_app[4];
  cs_res_app[4].State = CS_ChecksumState_ENABLED;
  cs_res_app[4].StartAddress = cs_src_b;
  cs_res_app[4].NumBytesToChecksum = 120;
  cs_res_app[4].ByteOffset = 64;
  cs_res_app[4].ComputedYet = TRUE;
  cs_res_app[4].ComparisonValue = 0x2222;
  StrNCpy(cs_res_app[4].Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  cs_def_app[7].State = CS_ChecksumState_ENABLED;
  StrNCpy(cs_def_app[7].Name, "CFE_EVS", CFE_MISSION_MAX_API_LEN);
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  d0 = evs_delays;
  CS_RecomputeAppChildTask();
  S("csh_recomp_app state=");
  D(cs_res_app[4].State);
  S(" def=");
  D(cs_def_app[7].State);
  S(" off=");
  D(cs_res_app[4].ByteOffset);
  S(" cmp=");
  D(cs_res_app[4].ComparisonValue);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");
  // THE NOT-FOUND ARM: an entry whose name is no app and no library. CS_ComputeApp answers
  // CS_ERR_NOT_FOUND, the loop BREAKS rather than spinning, and the task reports a failure
  // instead of a new baseline. Note the entry's state is still restored.
  cs_setup();
  CS_AppData.RecomputeAppEntryPtr = &cs_res_app[5];
  cs_res_app[5].State = CS_ChecksumState_ENABLED;
  cs_res_app[5].StartAddress = 0;
  cs_res_app[5].NumBytesToChecksum = 0;
  StrNCpy(cs_res_app[5].Name, "NO_SUCH_APP", CFE_MISSION_MAX_API_LEN);
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  d0 = evs_delays;
  CS_RecomputeAppChildTask();
  S("csh_recomp_app_missing state=");
  D(cs_res_app[5].State);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");

  // --- CS_RecomputeTablesChildTask, on the only path step 1 can reach: the table is not
  // registered, so CS_ComputeTables answers CS_ERR_NOT_FOUND and the loop breaks on the first
  // iteration. The ORDER is what this line is really for -- this task sends its event BEFORE
  // restoring the entry's state where the app task restores first and then sends, and the two
  // are otherwise line-for-line twins.
  cs_setup();
  CS_AppData.RecomputeTablesEntryPtr = &cs_res_tbl[3];
  cs_res_tbl[3].State = CS_ChecksumState_ENABLED;
  cs_res_tbl[3].TblHandleID = CFE_TBL_HANDLEID_UNDEFINED;
  StrNCpy(cs_res_tbl[3].Name, "GONE.TBL", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  cs_def_tbl[3].State = CS_ChecksumState_ENABLED;
  StrNCpy(cs_def_tbl[3].Name, "GONE.TBL", CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  d0 = evs_delays;
  CS_RecomputeTablesChildTask();
  S("csh_recomp_tbl state=");
  D(cs_res_tbl[3].State);
  S(" def=");
  D(cs_def_tbl[3].State);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");

  // --- CS_OneShotChildTask, the only checksum in CS with no table entry at all: the ground
  // names an address, a size and a budget. 200 bytes at 64 per cycle is four iterations, and the
  // answer must equal what the background walk computes for the same bytes -- so the same region
  // is run through CS_ComputeEepromMemory afterwards and the two are COMPARED. That equality is
  // the real assertion here; a one-shot that disagreed with the table path would be useless.
  //
  // ITS FINISH EVENT PRINTS THE ADDRESS -- "OneShot checksum on Address: 0x%08X" -- and a host
  // process and a QEMU guest never agree about one, so this is the fourth kind of event in this
  // port that cannot cross the differential. MM's answer was to leave such events undriven. The
  // better answer, used here, is to CLOSE THE EVS OUTPUT PORT for the duration: the event is
  // still built, filtered, counted and transmitted -- so every line of EVS_SendEvent runs -- and
  // only the human-readable copy is not printed. EVS_TlmPkt.Payload.MessageSendCounter is the
  // witness, and it reads TWO, which is worth accounting for rather than waving at: the counter
  // increments exactly once per event in EVS_GenerateEventTelemetry, and the second event is the
  // one the FIRST one provokes -- transmitting it finds no subscriber for the long-event MsgId,
  // and SB reports that with an event of its own. So closing the port suppresses BOTH port lines,
  // not just the one with the address in it. A first draft of this comment claimed the
  // "No subscribers" line still printed because it came from SB; it does not, and the transcript
  // says so where csh_oneshot_sent lands.
  cs_setup();
  CS_AppData.HkPacket.Payload.LastOneShotAddress = cs_src_a;
  CS_AppData.HkPacket.Payload.LastOneShotSize = 200;
  CS_AppData.HkPacket.Payload.LastOneShotMaxBytesPerCycle = 64;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  d0 = evs_delays;
  cs_port_saved = CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort;
  cs_sent_before = CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter;
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = 0;
  CS_OneShotChildTask();
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = cs_port_saved;
  S("csh_oneshot_sent ");
  D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter - cs_sent_before);
  S("\n");
  S("csh_oneshot cks=");
  D(CS_AppData.HkPacket.Payload.LastOneShotChecksum);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S(" task=");
  D(CS_AppData.ChildTaskID);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");
  cs_res_eep[6].State = CS_ChecksumState_ENABLED;
  cs_res_eep[6].StartAddress = cs_src_a;
  cs_res_eep[6].NumBytesToChecksum = 200;
  for (k = 0; k < 4; ++k) {
    cv = 0;
    done = FALSE;
    CS_ComputeEepromMemory(&cs_res_eep[6], &cv, &done);
  }
  S("csh_oneshot_agrees ");
  D(CS_AppData.HkPacket.Payload.LastOneShotChecksum == cs_res_eep[6].ComparisonValue);
  S("\n");
  // A ZERO SIZE: the loop body never runs, the checksum stays zero, and the task still finishes.
  // This is the arm that would hang if MaxBytesPerCycle were the thing left at zero instead --
  // see the note on CS_EX_BUDGET above.
  CS_AppData.HkPacket.Payload.LastOneShotSize = 0;
  CS_AppData.HkPacket.Payload.LastOneShotChecksum = 0x4444;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  d0 = evs_delays;
  cs_port_saved = CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort;
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = 0;
  CS_OneShotChildTask();
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = cs_port_saved;
  S("csh_oneshot_zero cks=");
  D(CS_AppData.HkPacket.Payload.LastOneShotChecksum);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S(" cycles=");
  D(evs_delays - d0);
  S("\n");
}


// ===================== CS, step 2 of three: cs_init.c =====================
//
// Three functions, and the one that matters is CS_InitAllTables: it is where the six wrappers come
// from. Step 1's exercise had to hand-build all six because nothing else fills one in; this block
// builds them NASA'S way, through cFE table services, and then re-reaches the six functions step 1
// could not -- CS_RegisterResultTable, CS_RegisterDefinitionTable, CS_TableInit,
// CS_GetTableAddr, CS_ReleaseTableAddr and CS_RefreshTableHandleAndAddress -- because all six need
// a table of CS's own to exist.
//
// CS_InitializeDefaultTables RUNS FIRST, and that order is the whole point of the
// "generated table init order" shape. The definition table FILES do not exist in this driver, so
// CS_RegisterDefinitionTable falls back to CFE_TBL_Load(CFE_TBL_SRC_ADDRESS,
// tw->DefaultDefinitionPtr) -- and those four default tables are a RUNTIME FILL here where NASA's
// C has them zero-initialised by the loader. A reader that ran before the fill would load whatever
// the BSS held, with no diagnostic. cs_app.c is what calls it in NASA's flow; this block does it
// explicitly and says so.
U0 cs_block_init()
{
  I32 rc;
  CS_TableWrapper_t *tw;
  U32 cv;
  Bool done;
  I64 k;
  U8 *expect;

  cs_fill_sources();
  cs_setup();

  // --- HEADROOM FIRST, and this line exists because of a shape this port has already paid for:
  // ONE PROCESS runs every exercise, so cFE's fixed-size tables are shared with MD, MM, TA and
  // everything else that ran before. This block creates FIVE pipes (CS_SbInit is called five times
  // and two of those succeed) and registers EIGHT tables, and if either pool is full the failure
  // appears as a registration error inside CS and looks exactly like CS's bug. So the headroom is
  // printed BEFORE anything is taken, and again after, on both halves. A diff here names the
  // cause; without it the next person bisects a registration failure.
  {
    I64 used = 0;
    I64 i;
    for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_TABLES; ++i) {
      // CFE_TBL_RegRecIsUsed, not a peek at a Name field -- the registry record has no `Name`
      // member, the name lives in its Config, and NASA's own accessor is what the rest of tbl asks
      // with. Guessing the field was a compile error here and would have been a silent wrong
      // answer on the C side.
      if (CFE_TBL_RegRecIsUsed(&CFE_TBL_Global.Registry[i])) {
        ++used;
      }
    }
    S("csi_headroom_before pipes=");
    D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
    S("/");
    D(CFE_PLATFORM_SB_MAX_PIPES);
    S(" tables=");
    D(used);
    S("/");
    D(CFE_PLATFORM_TBL_MAX_NUM_TABLES);
    S("\n");
  }

  // --- CS_InitSegments, both segments and both arms of each. The simulated PSP reports a FIXED
  // short string for each -- see the note on CFE_PSP_GetKernelTextSegmentInfo -- so the ADDRESS
  // is asserted as a comparison and the SIZE as a value.
  CS_InitSegments();
  S("csi_seg cfe=");
  D(CS_AppData.CfeCoreCodeSeg.State);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum);
  S(" os=");
  D(CS_AppData.OSCodeSeg.State);
  S("/");
  D(CS_AppData.OSCodeSeg.NumBytesToChecksum);
  S("\n");
  // AND THE TWO SEGMENTS ARE IMMEDIATELY CHECKSUMMABLE, which is the only thing that makes the
  // addresses worth reporting at all. Four bytes of "cFEtext" is one cycle.
  cv = 0;
  done = FALSE;
  rc = CS_ComputeEepromMemory(&CS_AppData.CfeCoreCodeSeg, &cv, &done);
  S("csi_seg_crc rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" cv=");
  D(cv);
  S("\n");
  // AND THE OS SEGMENT'S OWN CRC, which is what makes the two ADDRESSES asserted rather than just
  // the two sizes. A mutation that pointed the OS segment at the cFE one was a NO-OP while this
  // line was missing: the sizes differ (7 against 8) so NumBytesToChecksum looked right, and
  // nothing read the bytes. "cFEtext" read 8 long and "OSkernel" read 8 long are different bytes,
  // so the two CRCs are different numbers.
  cv = 0;
  done = FALSE;
  rc = CS_ComputeEepromMemory(&CS_AppData.OSCodeSeg, &cv, &done);
  S("csi_seg_crc_os rc=");
  D(rc);
  S(" done=");
  D(done);
  S(" cv=");
  D(cv);
  S("\n");

  // THE PSP REFUSING: NASA's own PSP answers CFE_PSP_ERROR_NOT_IMPLEMENTED on several platforms,
  // which is why each segment has a whole arm for it. All seven fields are written -- a failure
  // ZEROES the entry rather than leaving it alone, which is what keeps CS from checksumming
  // whatever the BSS held. Driven from an ENABLED entry with a real address, so an arm that
  // only set State would be caught.
  es_textseg_rc = CFE_PSP_ERROR_NOT_IMPLEMENTED;
  es_kernelseg_rc = CFE_PSP_ERROR_NOT_IMPLEMENTED;
  CS_InitSegments();
  S("csi_seg_refused cfe=");
  D(CS_AppData.CfeCoreCodeSeg.State);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.StartAddress);
  S(" os=");
  D(CS_AppData.OSCodeSeg.State);
  S("/");
  D(CS_AppData.OSCodeSeg.NumBytesToChecksum);
  S("/");
  D(CS_AppData.OSCodeSeg.StartAddress);
  S("\n");
  es_textseg_rc = CFE_PSP_SUCCESS;
  es_kernelseg_rc = CFE_PSP_SUCCESS;

  // --- CS_SbInit, and THE ORDER OF THESE FOUR CALLS IS THE WHOLE DESIGN. CS_SbInit hard-codes
  // CS_CMD_PIPE_NAME, and the simulated OS_QueueCreate rejects a duplicate name the way NASA's OSAL
  // does -- so the FIRST call that gets as far as creating a pipe consumes the only name CS has, and
  // every later call fails at CreatePipe before reaching a subscribe.
  //
  // A FIRST DRAFT RAN THEM success / taken / qfail / subfail AND THE LAST THREE WERE THE SAME ARM:
  // all four printed 0xCA000005, CFE_SB_PIPE_CR_ERR, and the comment claimed the fourth "reaches the
  // SECOND of CS_SbInit's five arms". It did not. Three identical status codes with four different
  // labels is the shape to distrust.
  //
  // So: the injected CreatePipe failure first (no name consumed), then the pool-exhausted subscribe
  // failure (which DOES create the pipe), then the name freed by hand so the nominal path can run,
  // then the duplicate.
  sb_queuecreate_rc = OS_ERROR;
  rc = CS_SbInit();
  S("csi_sb_qfail rc=");
  D(rc);
  S("\n");
  sb_queuecreate_rc = OS_SUCCESS;

  // THE HOUSEKEEPING SUBSCRIBE FAILING. CFE_SB_Subscribe allocates a destination descriptor from
  // SB's memory pool, so exhausting the pool is the fault injector, and the pipe is created before
  // the first subscribe -- which is why this has to come before the nominal call rather than after.
  //
  // THE OTHER TWO SUBSCRIBE ARMS ARE NOT DRIVEN, and saying so is better than implying it: reaching
  // "housekeeping succeeded and the background cycle failed" needs the pool to have room for exactly
  // one descriptor and "both succeeded and commands failed" for exactly two, which is a white-box
  // count of SB's allocator rather than a property of CS.
  es_pool_exhaust(CFE_SB_Global.Mem.PoolHdl);
  rc = CS_SbInit();
  es_pool_restore(CFE_SB_Global.Mem.PoolHdl);
  S("csi_sb_subfail rc=");
  D(rc);
  S("\n");

  // FREE THE SIMULATED QUEUE NAME so the nominal path can create its pipe. White-box on purpose,
  // and THE REASON RECORDED HERE WAS WRONG: it said CFE_SB_DeletePipe "is the one function in
  // NASA's SB this port has an undiagnosed segfault in". That crash is diagnosed and fixed, and it
  // was never NASA's -- es_pool_restore was rewinding SB's bump allocator over live memory, so
  // destination descriptors were handed out twice and a route's `Next` ended up holding a MsgId.
  // See the comment on es_pool_exhaust. With the allocator fixed, DeletePipe returns CFE_SUCCESS
  // for every one of the nine live pipes.
  //
  // The helper stays for now, and that is a choice rather than a necessity: swapping it for
  // CFE_SB_DeletePipe would exercise NASA's code instead of poking a driver table, but it also
  // frees the cFE pipe RECORD and so moves csi_headroom_after. Worth doing on its own, not folded
  // into the commit that fixed the allocator. The record is corrected; the shortcut is labelled.
  sb_forget_queue_name(CS_CMD_PIPE_NAME);

  // THE NOMINAL PATH: a pipe and three subscriptions.
  //
  // AND THE THREE SUBSCRIPTIONS ARE READ BACK, which they were not: a mutation that replaced the
  // background-cycle CFE_SB_Subscribe with `Result = CFE_SUCCESS` was a NO-OP, because nothing here
  // asked SB what CS was listening to. CFE_SB_GetDestPtr on each MsgId's route answers whether CS's
  // pipe is a destination -- the question the subscribe exists to settle.
  //
  // THE HOUSEKEEPING PACKET'S SIZE IS READ BACK FOR THE SAME REASON. CFE_MSG_Init is told
  // sizeof(CS_HkPacket_t); replacing that with sizeof(CS_HkPacket_Payload_t) was also a NO-OP.
  // 80 against 64, and the number on the wire is what a ground system decodes.
  rc = CS_SbInit();
  S("csi_sb rc=");
  D(rc);
  S(" pipe=");
  D(CFE_ResourceId_IsDefined(CS_AppData.CmdPipe));
  S("\n");
  {
    I64 hksz = 0;

    CFE_MSG_GetSize(&CS_AppData.HkPacket.TelemetryHeader.Msg, &hksz);
    S("csi_sb_hksize ");
    D(hksz);
    S("\n");
    S("csi_sb_subs cmd=");
    D(CFE_SB_GetDestPtr(CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(CS_CMD_MID)),
                        CS_AppData.CmdPipe) != NULL);
    S(" hk=");
    D(CFE_SB_GetDestPtr(CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(CS_SEND_HK_MID)),
                        CS_AppData.CmdPipe) != NULL);
    S(" bg=");
    D(CFE_SB_GetDestPtr(CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(CS_BACKGROUND_CYCLE_MID)),
                        CS_AppData.CmdPipe) != NULL);
    S(" other=");
    D(CFE_SB_GetDestPtr(CFE_SBR_GetRouteId(CFE_SB_ValueToMsgId(CS_HK_TLM_MID)),
                        CS_AppData.CmdPipe) != NULL);
    S("\n");
  }

  // AND THE DUPLICATE, which needs no fault injector at all -- just the name CS has now used.
  rc = CS_SbInit();
  S("csi_sb_taken rc=");
  D(rc);
  S("\n");

  // --- CS_InitAllTables, NASA'S way. The four default tables are filled FIRST (see the header
  // above), then all six types go through CS_TableInit: the two code segments have a NULL
  // filename and return success having done nothing, and the four real ones register a results
  // table, register a definition table, fail to load the file, fall back to the default in
  // memory, get an address and call their update handler.
  cs_setup();
  CS_InitializeDefaultTables();
  rc = CS_InitAllTables();
  S("csi_tables rc=");
  D(rc);
  S("\n");
  for (k = 0; k < CS_NUM_TABLES; ++k) {
    tw = &CS_AppData.Tbl[k];
    S("csi_tbl[");
    D(k);
    S("] ");
    S(CS_GetTableTypeAsString(tw));
    S(" def=");
    D(CFE_TBL_HANDLE_IS_VALID(tw->DefHandle));
    S(" res=");
    D(CFE_TBL_HANDLE_IS_VALID(tw->ResHandle));
    S(" defaddr=");
    D(tw->DefAddr != NULL);
    S(" resaddr=");
    D(tw->ResAddr != NULL);
    S(" n=");
    D(tw->NumEntries);
    S("\n");
    // THE FOUR DESCRIPTOR FIELDS, which is what CS_InitAllTables is FOR and which nothing read: two
    // mutations -- the TABLES type given DefStateOffset 8 instead of 0, and the EEPROM type given
    // the MEMORY default table -- were both NO-OPS. The sizes and the offset are what the generic
    // byte arithmetic in cs_utils.c indexes with, and DefaultDefinitionPtr is a POINTER, so it is
    // asserted as a comparison against the array it must name.
    expect = NULL;
    if (k == CS_ChecksumType_EEPROM_TABLE)
      expect = CS_AppData.DefaultEepromDefTable;
    else if (k == CS_ChecksumType_MEMORY_TABLE)
      expect = CS_AppData.DefaultMemoryDefTable;
    else if (k == CS_ChecksumType_TABLES_TABLE)
      expect = CS_AppData.DefaultTablesDefTable;
    else if (k == CS_ChecksumType_APP_TABLE)
      expect = CS_AppData.DefaultAppDefTable;
    S("csi_tbl_desc[");
    D(k);
    S("] defsz=");
    D(tw->DefEntrySize);
    S(" ressz=");
    D(tw->ResEntrySize);
    S(" off=");
    D(tw->DefStateOffset);
    S(" dflt=");
    D(tw->DefaultDefinitionPtr == expect);
    S("\n");
  }
  // LOADED FROM MEMORY MEANS DISABLED. The file was missing, so each of the four tables came up
  // from CS's own zeroed default -- and CS_RegisterDefinitionTable turns its global state OFF for
  // exactly that case, so CS does not come up claiming to watch things it was never told about.
  // The two code segments have no global state at all and are untouched.
  S("csi_tbl_states eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S("\n");
  // AND THE RESULTS TABLES ARE REAL cFE BUFFERS NOW, not driver arrays: the update handlers ran
  // over them during registration, so every entry is EMPTY and zero. Read at both ends.
  // EACH POINTER IS HOISTED INTO A LOCAL, both halves, and this cost a trap to learn.
  // `CS_GetEepromResEntry(0)->State` is the `fn(args)->member` shape that
  // docs/HOLYC_STRUCT_LIMITS.md #17 records -- and #17 says the compiler RESOLVES THE ARROW
  // AGAINST THE FIRST ARGUMENT'S CLASS AND REFUSES. With an INTEGER first argument there is no
  // class to resolve against, and it does not refuse: it compiles and loads through zero.
  // `load-fault mepc=... mtval=0x0` right after this line printed `csi_tbl_res eep0=`. So the limit
  // has a SILENT form, which tests/exec/cases/e_call_arrow_int_arg.hc now pins.
  {
    CS_Res_EepromMemory_Table_Entry_t *re0 = CS_GetEepromResEntry(0);
    CS_Res_EepromMemory_Table_Entry_t *re15 = CS_GetEepromResEntry(15);
    CS_Res_App_Table_Entry_t *ra0 = CS_GetAppResEntry(0);
    CS_Res_App_Table_Entry_t *ra23 = CS_GetAppResEntry(23);

    S("csi_tbl_res eep0=");
    D(re0->State);
    S(" eep15=");
    D(re15->State);
    S(" app0=");
    D(ra0->State);
    S(" app23=");
    D(ra23->State);
    S("\n");
  }

  // --- AND NOW THE SIX FUNCTIONS STEP 1 COULD NOT REACH. CS_HandleTableUpdate on a registered
  // pair releases both addresses, manages both tables and re-acquires both -- so
  // CS_GetTableAddr runs for real. Nothing has been loaded since registration, so the second
  // GetAddress does NOT answer CFE_TBL_INFO_UPDATED and the update handler is not called again,
  // which is the arm that distinguishes "managed" from "updated".
  rc = CS_HandleTableUpdate(&CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE]);
  S("csi_update rc=");
  D(rc);
  S(" defaddr=");
  D(CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE].DefAddr != NULL);
  S(" resaddr=");
  D(CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE].ResAddr != NULL);
  S("\n");
  // AND NOW THE ARM A MUTATION PROVED UNREACHABLE IN STEP 1. Batch one deleted
  // CS_HandleTableUpdate's `if (Result == CFE_TBL_INFO_UPDATED)` and the transcript did not move,
  // which is correct and was worth knowing: with no table loaded, the second CFE_TBL_GetAddress
  // answers plain CFE_SUCCESS and the update handler is never called again. Loading the definition
  // table from memory makes table services report the change, so this reaches the one branch in CS
  // that calls an update handler OUTSIDE registration -- and, for the tables type, the loop that
  // hands back every shared handle the old results table held.
  rc = CFE_TBL_Load(CS_GetDefHandle(CS_ChecksumType_EEPROM_TABLE), CFE_TBL_SRC_ADDRESS,
                    CS_AppData.DefaultEepromDefTable);
  S("csi_reload rc=");
  D(rc);
  S("\n");
  rc = CS_HandleTableUpdate(&CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE]);
  S("csi_update_after_load rc=");
  D(rc);
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S("\n");
  rc = CFE_TBL_Load(CS_GetDefHandle(CS_ChecksumType_TABLES_TABLE), CFE_TBL_SRC_ADDRESS,
                    CS_AppData.DefaultTablesDefTable);
  rc = CS_HandleTableUpdate(&CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE]);
  {
    // Hoisted for the same reason as csi_tbl_res above -- `fn(int)->member` loads through zero in
    // this compiler rather than refusing.
    CS_Res_Tables_Table_Entry_t *rt0 = CS_GetTablesResEntry(0);

    S("csi_update_tables rc=");
    D(rc);
    S(" res0=");
    D(rt0->State);
    S("\n");
  }

  // CS_ComputeTables ON A REAL TABLE, which is the only path through CS_GetTableAddr,
  // CS_ReleaseTableAddr and CS_RefreshTableHandleAndAddress. The table named is one of CS's OWN
  // -- its EEPROM definition table -- so the name resolves, CFE_TBL_Share hands back a handle,
  // the address is acquired, 256 bytes are CRC'd and the address is released again in the same
  // cycle. The budget is 64, so it takes four.
  //
  // AND THE RULE, BEFORE SOMEONE ADDS THE OBVIOUS NEXT LINE: CS may checksum its own DEFINITION
  // tables here and must never checksum its own RESULTS tables. A definition table is all zeros
  // after the fall-back-to-memory load, so the bytes agree between a host process and a QEMU
  // guest. A results table holds CS_Res_*_Table_Entry_t.StartAddress -- REAL POINTERS -- so the
  // moment any entry has a live address, a CRC over that buffer diverges and reads as a checksum
  // bug three steps from its cause. Naming CS_RESULTS_EEPROM_TABLE_NAME here is the shape to
  // refuse.
  {
    U32 aid = CFE_ES_APPID_UNDEFINED;
    U8 myname[OS_MAX_API_NAME];
    CS_Res_Tables_Table_Entry_t *rt;

    CFE_ES_GetAppID(&aid);
    CFE_ES_GetAppName(myname, aid, OS_MAX_API_NAME);

    rt = CS_GetTablesResEntry(0);
    MemSet(rt, 0, sizeof(CS_Res_Tables_Table_Entry_t));
    rt->State = CS_ChecksumState_ENABLED;
    rt->TblHandleID = CFE_TBL_HANDLEID_UNDEFINED;
    StrPrintN(rt->Name, CFE_MISSION_TBL_MAX_FULL_NAME_LEN, "%s.%s", myname, CS_DEF_EEPROM_TABLE_NAME);
    for (k = 0; k < 4; ++k) {
      cv = 0;
      done = FALSE;
      rc = CS_ComputeTables(rt, &cv, &done);
      S("csi_ctbl[");
      D(k);
      S("] rc=");
      D(rc);
      S(" done=");
      D(done);
      S(" off=");
      D(rt->ByteOffset);
      S(" size=");
      D(rt->NumBytesToChecksum);
      S(" cv=");
      D(cv);
      S(" cmp=");
      D(rt->ComparisonValue);
      S("\n");
    }
    // THE ADDRESS IS RELEASED EVERY CYCLE AND RE-ACQUIRED, so the exported StartAddress is
    // whatever table services last handed over -- non-zero, and the SAME across cycles, which
    // is the property that lets the resume test in CS_ComputeTables work at all.
    S("csi_ctbl_addr nonzero=");
    D(rt->StartAddress != 0);
    S(" handle=");
    D(rt->TblHandleID != CFE_TBL_HANDLEID_UNDEFINED);
    S("\n");
  }

  // --- A CS_InitAllTables THAT FAILS, LAST, because it leaves every wrapper in a failed state. Two
  // mutations proved this arm unreached -- "report an error for a type with no event id" and "do not
  // disable a type whose init failed" were both NO-OPS, because every table init had succeeded.
  // Running it a second time is what fails, and the reason is NOT a knob of this driver's: the eight
  // table names are already registered and the fall-back load answers CFE_TBL_ERR_LOAD_IN_PROGRESS,
  // 0xCC000012. A first draft tried to force it by exhausting TBL's memory pool, printed `rc=0`, and
  // claimed in a comment that the four types had failed. They had not. The pool-exhaust line is gone
  // and this says what actually fails and why.
  //
  // THE WITNESS IS FOUR EVENTS AND NO MORE: 116, 117, 118, 119 -- one per real type -- and SILENCE
  // for the cFE core and OS types, which is what the zeroes in cs_init.c's event-id map are for.
  //
  // AND IT TAKES TWO CALLS, which is the part that had to be measured rather than reasoned. A draft
  // put ONE call here, moved it to the end "so it cannot leave the wrappers broken", and it came
  // back rc=0: the second CS_InitAllTables SUCCEEDS. What fails is the THIRD, because the second
  // leaves a CFE_TBL_Load pending on each single-buffer table -- CS never calls CFE_TBL_Manage, so
  // nothing completes it -- and the next load answers CFE_TBL_ERR_LOAD_IN_PROGRESS. So the first of
  // these two lines is a success and the second is the failure, and both are printed because a
  // reader cannot otherwise tell which call the events belong to.
  CS_InitializeDefaultTables();
  rc = CS_InitAllTables();
  S("csi_tables_reinit rc=");
  D(rc);
  S("\n");
  // THE FOUR STATES ARE FORCED *ENABLED* FIRST, and this line is the whole reason mutation 9 means
  // anything. Deleting the `*tw->GlobalState = CS_ChecksumState_DISABLED` from CS_InitAllTables'
  // failure arm was a NO-OP: by this point every state was ALREADY disabled -- the first init loaded
  // each table from memory, which disables it -- so writing DISABLED again changed nothing. The
  // assertion was reading a value that was there for another reason. Poison-first, which is the rule
  // this project keeps relearning.
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_ENABLED;
  rc = CS_InitAllTables();
  S("csi_tables_fail rc=");
  D(rc);
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S("\n");

  // AND THE HEADROOM AFTER, so the cost of this block is a number rather than an assumption.
  {
    I64 used = 0;
    I64 i;
    for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_TABLES; ++i) {
      // CFE_TBL_RegRecIsUsed, not a peek at a Name field -- the registry record has no `Name`
      // member, the name lives in its Config, and NASA's own accessor is what the rest of tbl asks
      // with. Guessing the field was a compile error here and would have been a silent wrong
      // answer on the C side.
      if (CFE_TBL_RegRecIsUsed(&CFE_TBL_Global.Registry[i])) {
        ++used;
      }
    }
    S("csi_headroom_after pipes=");
    D(CFE_SB_Global.StatTlmMsg.Payload.PipesInUse);
    S("/");
    D(CFE_PLATFORM_SB_MAX_PIPES);
    S(" tables=");
    D(used);
    S("/");
    D(CFE_PLATFORM_TBL_MAX_NUM_TABLES);
    S("\n");
  }
}

// ===================== CS, step 3 of three: five command files, the dispatcher, the app ========
//
// 2,924 lines and 49 functions, gated in one commit because CS_AppPipe and CS_UpdateCDS close a
// seven-source cycle. This is their exercise, and it is SEVEN BLOCKS rather than one for a reason
// that is now measured rather than feared: docs/HOLYC_STRUCT_LIMITS.md #22 says a function whose
// TOTAL frame grows past some threshold makes a file-scope `&function` initialiser read as ZERO
// hundreds of lines away, and step 1's first draft hit it by writing one block inline in main().
// One block per NASA source keeps every frame small, and makes a bisect name a file.
//
// THE SEVEN BLOCKS RUN **AFTER** cs_block_init, AND NONE OF THEM MAY DEPEND ON WHAT IT LEFT.
// cs_block_init deliberately ENDS with a CS_InitAllTables that FAILED -- that is the only way to
// reach cs_init.c's error arms -- so every wrapper it leaves behind is in a failed state. Each
// block below therefore starts from cs_setup(), the hand-built wrappers over driver arrays, which
// is what step 1's four blocks used and is deterministic. The rule recorded for step 2 said
// cs_block_init must stay LAST because a later cs_setup() orphans its eight registered cFE
// tables; that remains true and is now harmless, because nothing after it reads them. The eight
// registrations still cost eight of 64 table slots, which csi_headroom_after counts.
//
// AND THE STICKY FLAGS ARE THE VACUITY HAZARD IN THIS WHOLE STEP. RecomputeInProgress and
// OneShotInProgress are what every busy-path arm needs set -- and CS_CheckRecomputeOneshot reads
// them, so a flag left TRUE makes DOZENS of later handlers take their refuse path, BOTH HALVES
// AGREE, and the transcript grows while asserting nothing. Worse, this driver's OS_TaskCreate
// never calls the entry function, so a SUCCESSFUL recompute command leaves RecomputeInProgress
// TRUE with no child to clear it. So every line below that can set a flag PRINTS BOTH FLAGS, and
// the blocks reset through cs_setup() between groups rather than trusting them to be clear.
//
// CS_NUM_DATA_STORE_STATES IS A `#define` INSIDE cs_app.c, not a header, so neither oracle can
// include it -- the same reason it briefly appeared in check_constants' "names NASA does not
// define" bucket until cs_app.c joined CSRC_DEFS. Written out here with its own name, and the
// VALUE is gated: check_constants compares the translation's CS_NUM_DATA_STORE_STATES against
// NASA's cs_app.c, so a drift fails there rather than silently resizing this buffer.
#define CS_EX_CDS_STATES 6

U0 cs_block_cmds()
{
  CS_RecomputeBaselineTableCmd_t cb; // the largest CS command, used as the buffer -- see csd
  CS_OneShotCmd_t osc;
  CS_Res_EepromMemory_Table_Entry_t *seg;
  I64 d0;
  I64 k;

  cs_fill_sources();
  cs_setup();

  // --- CS_NoopCmd. The version is four #defines from cs_version.h, which was the one CS header
  // nothing had needed until this file asked for CS_MAJOR_VERSION and the compile failed.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_NoopCmd(&cb);
  S("cscm_noop cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");

  // --- CS_ResetCountersCmd. ALL NINE COUNTERS ARE POISONED FIRST and the two baselines are
  // poisoned with them: the assertion is not only that nine counters are zero, it is that the
  // reset did NOT touch what CS has MEASURED. A reset that cleared the baselines would lose the
  // reference every future comparison is against, and with the baselines left at zero both
  // halves would agree about nothing.
  //
  // AND CommandCounter IS ZERO AFTERWARDS, NOT ONE. Every other CS command increments it; this
  // one has just zeroed it and does not. NASA's, deliberate, and the kind of asymmetry a
  // transcript is the only honest record of.
  CS_AppData.HkPacket.Payload.CommandCounter = 11;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 12;
  CS_AppData.HkPacket.Payload.EepromCSErrCounter = 13;
  CS_AppData.HkPacket.Payload.MemoryCSErrCounter = 14;
  CS_AppData.HkPacket.Payload.TablesCSErrCounter = 15;
  CS_AppData.HkPacket.Payload.AppCSErrCounter = 16;
  CS_AppData.HkPacket.Payload.CfeCoreCSErrCounter = 17;
  CS_AppData.HkPacket.Payload.OSCSErrCounter = 18;
  CS_AppData.HkPacket.Payload.PassCounter = 19;
  CS_AppData.HkPacket.Payload.CfeCoreBaseline = 0xAAAA;
  CS_AppData.HkPacket.Payload.OSBaseline = 0xBBBB;
  CS_ResetCountersCmd(&cb);
  S("cscm_reset cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSErrCounter);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSErrCounter);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSErrCounter);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSErrCounter);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSErrCounter);
  S(" os=");
  D(CS_AppData.HkPacket.Payload.OSCSErrCounter);
  S(" pass=");
  D(CS_AppData.HkPacket.Payload.PassCounter);
  S(" base_cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreBaseline);
  S(" base_os=");
  D(CS_AppData.HkPacket.Payload.OSBaseline);
  S("\n");

  // --- CS_EnableAllCSCmd and CS_DisableAllCSCmd, and THE SIX Zero*TempValues CALLS ARE THE POINT
  // OF THE DISABLE. A partial checksum left behind would be RESUMED when the ground re-enabled,
  // giving a baseline computed half before and half after whatever the ground was doing in
  // between. So six partial states are poisoned first -- a temp value and a non-zero byte offset
  // in each of the four tables and both code segments -- and all twelve numbers are read back.
  // The ENABLE twin zeroes NOTHING, which is the asymmetry, and it is asserted by poisoning again
  // and showing the twelve survive.
  CS_AppData.CfeCoreCodeSeg.TempChecksumValue = 0x1111;
  CS_AppData.CfeCoreCodeSeg.ByteOffset = 8;
  CS_AppData.OSCodeSeg.TempChecksumValue = 0x2222;
  CS_AppData.OSCodeSeg.ByteOffset = 16;
  cs_res_eep[0].TempChecksumValue = 0x3333;
  cs_res_eep[0].ByteOffset = 24;
  cs_res_mem[0].TempChecksumValue = 0x4444;
  cs_res_mem[0].ByteOffset = 32;
  cs_res_tbl[0].TempChecksumValue = 0x5555;
  cs_res_tbl[0].ByteOffset = 40;
  cs_res_app[0].TempChecksumValue = 0x6666;
  cs_res_app[0].ByteOffset = 48;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_DisableAllCSCmd(&cb);
  S("cscm_disall st=");
  D(CS_AppData.HkPacket.Payload.ChecksumState);
  S(" cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" cfe=");
  D(CS_AppData.CfeCoreCodeSeg.TempChecksumValue);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.ByteOffset);
  S(" os=");
  D(CS_AppData.OSCodeSeg.TempChecksumValue);
  S("/");
  D(CS_AppData.OSCodeSeg.ByteOffset);
  S(" eep=");
  D(cs_res_eep[0].TempChecksumValue);
  S("/");
  D(cs_res_eep[0].ByteOffset);
  S(" mem=");
  D(cs_res_mem[0].TempChecksumValue);
  S("/");
  D(cs_res_mem[0].ByteOffset);
  S(" tbl=");
  D(cs_res_tbl[0].TempChecksumValue);
  S("/");
  D(cs_res_tbl[0].ByteOffset);
  S(" app=");
  D(cs_res_app[0].TempChecksumValue);
  S("/");
  D(cs_res_app[0].ByteOffset);
  S("\n");
  CS_AppData.CfeCoreCodeSeg.TempChecksumValue = 0x1111;
  CS_AppData.CfeCoreCodeSeg.ByteOffset = 8;
  cs_res_app[0].TempChecksumValue = 0x6666;
  cs_res_app[0].ByteOffset = 48;
  CS_EnableAllCSCmd(&cb);
  S("cscm_enall st=");
  D(CS_AppData.HkPacket.Payload.ChecksumState);
  S(" cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" cfe=");
  D(CS_AppData.CfeCoreCodeSeg.TempChecksumValue);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.ByteOffset);
  S(" app=");
  D(cs_res_app[0].TempChecksumValue);
  S("/");
  D(cs_res_app[0].ByteOffset);
  S("\n");

  // --- THE FOUR PER-TYPE ENABLE/DISABLE COMMANDS, AND THEIR CDS WRITES.
  //
  // These four are the first commands in CS that PERSIST. CS_UpdateCDS is one of the two
  // functions closing the seven-source cycle, and it is SILENT when there is no store -- so a
  // draft that ran these with CS_AppData.DataStoreHandle at zero would exercise the enable/
  // disable and not one line of the CDS, and nothing in the output would say so. A real CDS is
  // registered here first, and es_cds_writes is the witness that each command wrote one.
  //
  // AND THE CDS IS SIX BYTES IN NASA'S OWN ORDER -- eeprom, memory, APP, TABLES, os, cfecore --
  // which is NOT the order of the checksum-type enum. The buffer is read back raw after the four
  // commands so the ORDER is asserted and not just the count: a swap of slots 2 and 3 would
  // restore the app state into the tables state on the next power-on and no counter would move.
  //
  // AND es_cds_reset() IS *NOT* CALLED HERE, which a first draft did and it made this whole group
  // vacuous: that helper clears CFE_ES_Global.CDSIsAvailable, so CFE_ES_RegisterCDS answered
  // CFE_ES_NOT_IMPLEMENTED (0xC400FFFF), the handle stayed undefined, every CS_UpdateCDS below was
  // SILENT -- which is its documented behaviour with no store -- and the transcript read
  // `writes=0`, `rc=0xC4000001` and six bytes of 0xEE poison. Green, and about nothing. The ES
  // block has already brought the CDS up; this registers inside it.
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  S("cscm_cds_reg rc=");
  D(CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_EX_CDS_STATES, "CSCMDS"));
  S("\n");
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  d0 = es_cds_writes;
  CS_EnableCfeCoreCmd(&cb);
  CS_EnableOSCmd(&cb);
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_DISABLED;
  CS_UpdateCDS();
  S("cscm_cds_write cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" writes=");
  D(es_cds_writes - d0);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSState);
  S(" os=");
  D(CS_AppData.HkPacket.Payload.OSCSState);
  S("\n");
  {
    U8 back[CS_EX_CDS_STATES];
    MemSet(back, 0xEE, CS_EX_CDS_STATES);
    S("cscm_cds_read rc=");
    D(CFE_ES_RestoreFromCDS(back, CS_AppData.DataStoreHandle));
    for (k = 0; k < CS_EX_CDS_STATES; ++k) {
      S(" ");
      D(back[k]);
    }
    S("\n");
  }
  // THE DISABLE TWINS, which also zero that type's partial state where the enable does not.
  CS_AppData.CfeCoreCodeSeg.TempChecksumValue = 0x7777;
  CS_AppData.OSCodeSeg.TempChecksumValue = 0x8888;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_DisableCfeCoreCmd(&cb);
  CS_DisableOSCmd(&cb);
  S("cscm_dis_seg cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSState);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.TempChecksumValue);
  S(" os=");
  D(CS_AppData.HkPacket.Payload.OSCSState);
  S("/");
  D(CS_AppData.OSCodeSeg.TempChecksumValue);
  S("\n");
  // AND A CDS WRITE THAT FAILS, which is the arm that gives up on the store for good: the handle
  // is set to CFE_ES_CDS_BAD_HANDLE so every later command is silent. The witness is that the NEXT
  // command writes NOTHING, which no counter would show without the second call.
  es_cds_write_rc = CFE_PSP_ERROR;
  CS_EnableCfeCoreCmd(&cb);
  es_cds_write_rc = CFE_PSP_SUCCESS;
  d0 = es_cds_writes;
  CS_EnableOSCmd(&cb);
  S("cscm_cds_broken defined=");
  D(CFE_ResourceId_IsDefined(CS_AppData.DataStoreHandle));
  S(" writes_after=");
  D(es_cds_writes - d0);
  S("\n");

  // --- CS_ReportBaselineCfeCoreCmd and the OS twin, BOTH ARMS EACH. `ComputedYet` is the whole
  // command: a baseline that has not been measured is not zero, it is ABSENT, and the two are
  // different events. A ground display reading the number alone could not tell them apart.
  seg = CS_GetCfeCoreCodeSegResTable();
  seg->ComputedYet = FALSE;
  seg->ComparisonValue = 0x1234;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_ReportBaselineCfeCoreCmd(&cb);
  seg->ComputedYet = TRUE;
  CS_ReportBaselineCfeCoreCmd(&cb);
  seg = CS_GetOSCodeSegResTable();
  seg->ComputedYet = FALSE;
  seg->ComparisonValue = 0x5678;
  CS_ReportBaselineOSCmd(&cb);
  seg->ComputedYet = TRUE;
  CS_ReportBaselineOSCmd(&cb);
  S("cscm_report cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");

  // --- CS_RecomputeBaselineCfeCoreCmd and the OS twin, ALL THREE ARMS EACH.
  //
  // THE FLAG IS SET BEFORE THE TASK IS CREATED and cleared again if the create fails, which is the
  // only safe order and is therefore the thing to assert: after a FAILED create the flag must be
  // FALSE, or a recompute that never started would lock out every later one. Both flags are
  // printed on every line for the reason in this block's header.
  cs_setup();
  es_taskcreate_rc = OS_SUCCESS;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_RecomputeBaselineCfeCoreCmd(&cb);
  S("cscm_recomp_cfe cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S(" type=");
  D(CS_AppData.ChildTaskTable);
  S(" ent=");
  D(CS_AppData.ChildTaskEntryID);
  S(" ptr=");
  D(CS_AppData.RecomputeEepromMemoryEntryPtr == &CS_AppData.CfeCoreCodeSeg);
  S("\n");
  // THE BUSY ARM, which is now reachable without touching a flag by hand: the call above left
  // RecomputeInProgress TRUE because this driver's OS_TaskCreate never runs the child.
  CS_RecomputeBaselineCfeCoreCmd(&cb);
  S("cscm_recomp_cfe_busy cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  // THE CREATE-FAILED ARM, and THE KNOB IS es_taskcreate_rc. A first draft used es_starttask_rc,
  // which is a leftover from when CFE_ES_StartAppTask was a stub -- its source is gated now and
  // the real one runs, so that variable is read by nothing and the command SUCCEEDED: cc moved to
  // 2 and the comment claiming a failed create was false. The real failure point is OS_TaskCreate,
  // whose return this driver owns; the status CS prints is then whatever CFE_ES_StartAppTask maps
  // it to, which is the same number on both halves.
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  es_taskcreate_rc = OS_ERROR;
  CS_RecomputeBaselineCfeCoreCmd(&cb);
  S("cscm_recomp_cfe_fail cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;
  // AND THE OS TWIN, line for line with a different type, task name and three event ids. The
  // ONE-SHOT flag is what blocks it here rather than the recompute flag, which is the half of the
  // guard the cFE-core lines above did not reach.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_RecomputeBaselineOSCmd(&cb);
  S("cscm_recomp_os cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" type=");
  D(CS_AppData.ChildTaskTable);
  S(" ptr=");
  D(CS_AppData.RecomputeEepromMemoryEntryPtr == &CS_AppData.OSCodeSeg);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  CS_RecomputeBaselineOSCmd(&cb);
  S("cscm_recomp_os_busy ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S("\n");
  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  es_taskcreate_rc = OS_ERROR;
  CS_RecomputeBaselineOSCmd(&cb);
  S("cscm_recomp_os_fail ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;

  // --- CS_OneShotCmd, ALL FOUR ARMS, and the ADDRESS IS A FIXED CONSTANT rather than a real
  // pointer. The started event prints "address: 0x%08X" -- so a cs_src_a(U64) would put a host
  // pointer in the transcript and nothing would ever match. MD_SIM_WINDOW_BASE is a compile-time
  // number both halves agree about, and CFE_PSP_MemValidateRange in this driver answers
  // es_psp_validate_rc regardless of the address, so the number does not have to be backed by
  // anything: the child task that would read it is never run here.
  //
  // AND A ZERO MaxBytesPerCycle MEANS "USE THE PLATFORM DEFAULT", which is the substitution that
  // keeps CS_OneShotChildTask's loop bounded at all -- a zero reaching it would never terminate.
  // Driven both ways, and the stored value is read back, because the substitution is invisible in
  // a counter.
  cs_setup();
  MemSet(&osc, 0, sizeof(CS_OneShotCmd_t));
  osc.Payload.Address = MD_SIM_WINDOW_BASE;
  osc.Payload.Size = 32;
  osc.Payload.MaxBytesPerCycle = 0;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  es_psp_validate_rc = -17;
  CS_OneShotCmd(&osc);
  S("cscm_oneshot_badrange cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S("\n");
  es_psp_validate_rc = CFE_PSP_SUCCESS;
  es_taskcreate_rc = OS_ERROR;
  CS_OneShotCmd(&osc);
  S("cscm_oneshot_createfail ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;
  CS_OneShotCmd(&osc);
  S("cscm_oneshot cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S(" addr=");
  D(CS_AppData.HkPacket.Payload.LastOneShotAddress == MD_SIM_WINDOW_BASE);
  S(" size=");
  D(CS_AppData.HkPacket.Payload.LastOneShotSize);
  S(" budget=");
  D(CS_AppData.HkPacket.Payload.LastOneShotMaxBytesPerCycle);
  S(" cks=");
  D(CS_AppData.HkPacket.Payload.LastOneShotChecksum);
  S(" task=");
  D(CFE_ResourceId_IsDefined(CS_AppData.ChildTaskID));
  S("\n");
  // THE BUSY ARM, left set by the successful call above.
  CS_OneShotCmd(&osc);
  S("cscm_oneshot_busy ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- CS_CancelOneShotCmd, ALL THREE ARMS, in the order that needs no hand-set flag for the
  // first two: a one-shot is in progress right now from the lines above, so the SUCCESS arm goes
  // first, and the second call finds nothing active.
  //
  // THE GUARD IS `Recompute == FALSE && OneShot == TRUE`, so it REFUSES while a RECOMPUTE owns the
  // child task even though that is also a child task -- there is one ChildTaskID and deleting it
  // from here would kill a recompute nobody asked to cancel. That third arm is the last two lines,
  // and it is the one a reader would assume is the same as "no one-shot".
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  d0 = es_taskdeletes;
  CS_CancelOneShotCmd(&cb);
  S("cscm_cancel cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S(" dels=");
  D(es_taskdeletes - d0);
  S(" task=");
  D(CFE_ResourceId_IsDefined(CS_AppData.ChildTaskID));
  S("\n");
  CS_CancelOneShotCmd(&cb);
  S("cscm_cancel_none ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  CS_CancelOneShotCmd(&cb);
  S("cscm_cancel_recomp ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S("\n");

  // --- CS_BackgroundCheckCycleCmd, FOUR ARMS.
  //
  // (a) checksumming DISABLED app-wide: the whole body is skipped and nothing moves.
  // (b) ENABLED with a recompute in progress: one event and no walk.
  // (c) the real walk, from CurrentCSTable 0, over a table set with one enabled entry each.
  // (d) the `default:` RECOVERY arm -- a CurrentCSTable outside 0..5, which only a corrupted
  //     housekeeping packet produces. It rewinds to zero and counts a pass, and is one of only two
  //     places in CS that touch PassCounter.
  //
  // THE `EndOfList` TEST LOOKS WRONG AND IS NOT: it is set when CurrentCSTable reaches
  // CS_NUM_TABLES - 1 and tested at the TOP of the next iteration, so the last type still runs
  // once. CurrentCSTable and CurrentEntryInTable after each call are what say which types the walk
  // actually visited.
  cs_setup();
  CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.CurrentCSTable = 3;
  CS_AppData.HkPacket.Payload.PassCounter = 5;
  CS_BackgroundCheckCycleCmd(&cb);
  S("cscm_bkgnd_off tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" pass=");
  D(CS_AppData.HkPacket.Payload.PassCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  CS_BackgroundCheckCycleCmd(&cb);
  S("cscm_bkgnd_busy tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" pass=");
  D(CS_AppData.HkPacket.Payload.PassCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  // (c) THE WALK. Every type is ENABLED and given something to checksum, so each background
  // function does work rather than falling straight through -- a cycle over six empty tables would
  // return after six no-ops and look identical to a cycle that worked.
  CS_AppData.CfeCoreCodeSeg.State = CS_ChecksumState_ENABLED;
  CS_AppData.CfeCoreCodeSeg.StartAddress = cs_src_a(U64);
  CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum = 32;
  CS_AppData.OSCodeSeg.State = CS_ChecksumState_ENABLED;
  CS_AppData.OSCodeSeg.StartAddress = cs_src_b(U64);
  CS_AppData.OSCodeSeg.NumBytesToChecksum = 24;
  cs_res_eep[0].State = CS_ChecksumState_ENABLED;
  cs_res_eep[0].StartAddress = cs_src_a(U64);
  cs_res_eep[0].NumBytesToChecksum = 16;
  cs_res_mem[0].State = CS_ChecksumState_ENABLED;
  cs_res_mem[0].StartAddress = cs_src_b(U64);
  cs_res_mem[0].NumBytesToChecksum = 16;
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.OSCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.CurrentCSTable = 0;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  CS_AppData.HkPacket.Payload.PassCounter = 0;
  for (k = 0; k < 8; ++k) {
    CS_BackgroundCheckCycleCmd(&cb);
    S("cscm_bkgnd[");
    D(k);
    S("] tbl=");
    D(CS_AppData.HkPacket.Payload.CurrentCSTable);
    S(" ent=");
    D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    S(" pass=");
    D(CS_AppData.HkPacket.Payload.PassCounter);
    S(" cfe=");
    D(CS_AppData.CfeCoreCodeSeg.ByteOffset);
    S("/");
    D(CS_AppData.CfeCoreCodeSeg.ComparisonValue);
    S(" os=");
    D(CS_AppData.OSCodeSeg.ByteOffset);
    S("/");
    D(CS_AppData.OSCodeSeg.ComparisonValue);
    S(" eep=");
    D(cs_res_eep[0].ComparisonValue);
    S("\n");
  }
  // (d) THE RECOVERY ARM.
  CS_AppData.HkPacket.Payload.CurrentCSTable = 99;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 77;
  CS_AppData.HkPacket.Payload.PassCounter = 0;
  CS_BackgroundCheckCycleCmd(&cb);
  S("cscm_bkgnd_bad tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" ent=");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" pass=");
  D(CS_AppData.HkPacket.Payload.PassCounter);
  S("\n");

  // --- CS_SendHkCmd, which does TWO things: transmits the packet and SWEEPS the six wrappers for
  // ground table loads. The sweep is here as well as in CS_AppMain's timeout arm, so a busy pipe
  // that never times out still picks up a new table.
  //
  // THE PACKET HAS TO BE INITIALISED FIRST or CFE_SB_TransmitMsg refuses a zero MsgId and the
  // sweep is all that runs -- which would pass, and would be half an exercise. CFE_MSG_Init is
  // what CS_SbInit does; doing it here keeps this block independent of that one.
  //
  // NoSubscribersCounter IS THE WITNESS. Nothing subscribes to CS_HK_TLM_MID in this driver, so a
  // successful transmit shows up as SB reporting no subscriber -- which is a real send that went
  // nowhere, not a refused one. A refused send does not move it.
  cs_setup();
  CFE_MSG_Init(&CS_AppData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CS_HK_TLM_MID),
               sizeof(CS_HkPacket_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 42;
  d0 = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
  CS_SendHkCmd(&cb);
  S("cscm_hk nosub=");
  D(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - d0);
  S(" cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
}

// --- cs_eeprom_cmds.c, seven commands, and the file that carries two of CS's four upstream
// defects. The address in every event here is a FIXED NUMBER rather than a pointer into cs_src_a:
// CS_GetEntryIDEepromCmd prints "Found Address 0x%08X", and no host process and QEMU guest ever
// agree about a real one. Nothing in this block reads the bytes at those addresses, so they do not
// have to be backed by anything.
#define CS_EX_EEP_ADDR 0x00300000

U0 cs_block_eeprom_cmds()
{
  CS_RecomputeBaselineTableCmd_t cb;
  CS_ReportBaselineEntryIDEepromCmd_t ec;
  CS_GetEntryIDEepromCmd_t gc;
  I64 d0;

  cs_fill_sources();
  cs_setup();
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_EX_CDS_STATES, "CSEEP");

  // --- CS_DisableEepromCmd and CS_EnableEepromCmd. THE GUARD IS THE FIRST THING EACH DOES, and a
  // refused command moves the ERROR counter from inside CS_CheckRecomputeOneshot rather than from
  // the handler -- so the handler's own counter must NOT move, which is what makes cc=0 on the
  // refused line an assertion rather than an absence.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  CS_DisableEepromCmd(&cb);
  S("csec_dis_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S("\n");
  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  cs_res_eep[2].TempChecksumValue = 0x9999;
  cs_res_eep[2].ByteOffset = 12;
  d0 = es_cds_writes;
  CS_DisableEepromCmd(&cb);
  S("csec_dis cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" temp=");
  D(cs_res_eep[2].TempChecksumValue);
  S(" off=");
  D(cs_res_eep[2].ByteOffset);
  S(" writes=");
  D(es_cds_writes - d0);
  S("\n");
  cs_res_eep[2].TempChecksumValue = 0x9999;
  cs_res_eep[2].ByteOffset = 12;
  CS_EnableEepromCmd(&cb);
  S("csec_en cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" temp=");
  D(cs_res_eep[2].TempChecksumValue);
  S(" off=");
  D(cs_res_eep[2].ByteOffset);
  S("\n");

  // --- CS_ReportBaselineEntryIDEepromCmd, AND THIS IS WHERE UPSTREAM DEFECT #13 IS WITNESSED.
  //
  // The command writes `ResultsEntry->State = CS_ChecksumState_ENABLED` inside the valid arm. So
  // the state is printed BEFORE and AFTER: a DISABLED entry asked for its baseline comes back
  // ENABLED, and the background walk resumes over a region the ground switched off. The Memory
  // twin does not have the line and csmc_report below prints the same pair unchanged, which is
  // what makes this a DIFFERENCE and not a convention.
  //
  // Three arms: an id past the end of the table (NULL, so State becomes UNDEFINED and
  // CS_StateValid refuses it), a DISABLED entry with no baseline yet, and an ENABLED entry with
  // one.
  MemSet(&ec, 0, sizeof(CS_ReportBaselineEntryIDEepromCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  ec.Payload.EntryID = CS_MAX_NUM_EEPROM_TABLE_ENTRIES;
  CS_ReportBaselineEntryIDEepromCmd(&ec);
  S("csec_report_badid cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  cs_res_eep[4].State = CS_ChecksumState_DISABLED;
  cs_res_eep[4].ComputedYet = FALSE;
  cs_res_eep[4].ComparisonValue = 0x1357;
  ec.Payload.EntryID = 4;
  S("csec_report_before state=");
  D(cs_res_eep[4].State);
  S("\n");
  CS_ReportBaselineEntryIDEepromCmd(&ec);
  S("csec_report_nobase cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state_after=");
  D(cs_res_eep[4].State);
  S("\n");
  cs_res_eep[4].ComputedYet = TRUE;
  CS_ReportBaselineEntryIDEepromCmd(&ec);
  S("csec_report cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");

  // --- CS_RecomputeBaselineEepromCmd, AND THE BUSY ARM IS UPSTREAM DEFECT #14.
  //
  // `EntryID = CmdPtr->Payload.EntryID` is INSIDE the `if`, and the busy event in the `else`
  // prints EntryID -- so it always says 0 whatever the ground commanded. THE COMMANDED ID HERE IS
  // 7, AND THE EVENT IN THE TRANSCRIPT SAYS "Entry ID 0". That event text is directly comparable,
  // because the declaration initialises EntryID to zero: it is a wrong value, not an
  // uninitialised one, which is exactly what separates this defect from #15 two files later.
  //
  // The busy arm goes FIRST so the commanded id is unambiguous, and the flag is set by hand here
  // rather than inherited -- the success call below is what leaves it set for good.
  cs_setup();
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  ec.Payload.EntryID = 7;
  CS_RecomputeBaselineEepromCmd(&ec);
  S("csec_recomp_busy ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  // An id past the end: the inner arm, which reports the real id because it is inside the if.
  ec.Payload.EntryID = CS_MAX_NUM_EEPROM_TABLE_ENTRIES + 3;
  CS_RecomputeBaselineEepromCmd(&ec);
  S("csec_recomp_badid ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  // The create failing, and then succeeding. ChildTaskEntryID is the witness that the command's id
  // reached the child-task variables at all -- the event on the busy path cannot show it.
  cs_res_eep[9].State = CS_ChecksumState_ENABLED;
  ec.Payload.EntryID = 9;
  es_taskcreate_rc = OS_ERROR;
  CS_RecomputeBaselineEepromCmd(&ec);
  S("csec_recomp_fail ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_RecomputeBaselineEepromCmd(&ec);
  S("csec_recomp cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" type=");
  D(CS_AppData.ChildTaskTable);
  S(" ent=");
  D(CS_AppData.ChildTaskEntryID);
  S(" ptr=");
  D(CS_AppData.RecomputeEepromMemoryEntryPtr == &cs_res_eep[9]);
  S("\n");

  // --- CS_EnableEntryIDEepromCmd and CS_DisableEntryIDEepromCmd, FOUR ARMS EACH.
  //
  // BOTH WRITE **TWO** TABLES, and the definition write can fail quietly: CS_SetDefEntryState
  // returns the PREVIOUS state, and a previous state that is not commandable means the definition
  // entry is EMPTY -- so the results entry changes and the definition entry does not, and the
  // mismatch survives only until the next ground table load. That is the DEBUG event, and it is
  // driven: entry 5's definition entry is left EMPTY on purpose while entry 3's is DISABLED. Both
  // definition states are printed, so "wrote the results entry and not the definition entry" is
  // visible rather than implied.
  //
  // AND THE DISABLE CLEARS THE PARTIAL CHECKSUM WHERE THE ENABLE DOES NOT, the same asymmetry as
  // every other disable in CS. Poisoned before each so the difference is a number.
  cs_setup();
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  ec.Payload.EntryID = 3;
  CS_EnableEntryIDEepromCmd(&ec);
  CS_DisableEntryIDEepromCmd(&ec);
  S("csec_entry_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  ec.Payload.EntryID = CS_MAX_NUM_EEPROM_TABLE_ENTRIES + 1;
  CS_EnableEntryIDEepromCmd(&ec);
  CS_DisableEntryIDEepromCmd(&ec);
  S("csec_entry_badid ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  cs_res_eep[3].State = CS_ChecksumState_DISABLED;
  cs_res_eep[3].TempChecksumValue = 0x2468;
  cs_res_eep[3].ByteOffset = 20;
  cs_def_eep[3].State = CS_ChecksumState_DISABLED;
  cs_res_eep[5].State = CS_ChecksumState_DISABLED;
  cs_def_eep[5].State = CS_ChecksumState_EMPTY;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  ec.Payload.EntryID = 3;
  CS_EnableEntryIDEepromCmd(&ec);
  S("csec_en_entry cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_eep[3].State);
  S(" def=");
  D(cs_def_eep[3].State);
  S(" temp=");
  D(cs_res_eep[3].TempChecksumValue);
  S(" off=");
  D(cs_res_eep[3].ByteOffset);
  S("\n");
  CS_DisableEntryIDEepromCmd(&ec);
  S("csec_dis_entry cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_eep[3].State);
  S(" def=");
  D(cs_def_eep[3].State);
  S(" temp=");
  D(cs_res_eep[3].TempChecksumValue);
  S(" off=");
  D(cs_res_eep[3].ByteOffset);
  S("\n");
  // THE DEFINITION ENTRY THAT IS EMPTY: the results entry moves, the definition entry does not,
  // and a DEBUG event says so.
  ec.Payload.EntryID = 5;
  CS_EnableEntryIDEepromCmd(&ec);
  S("csec_en_entry_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_eep[5].State);
  S(" def=");
  D(cs_def_eep[5].State);
  S("\n");
  CS_DisableEntryIDEepromCmd(&ec);
  S("csec_dis_entry_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_eep[5].State);
  S(" def=");
  D(cs_def_eep[5].State);
  S("\n");

  // --- CS_GetEntryIDEepromCmd. THE LOOP DOES NOT STOP AT THE FIRST MATCH: it walks the whole
  // table and sends an event for EVERY entry whose range contains the address, so overlapping
  // definition entries all report. That is NASA's and it is the right answer -- an operator asking
  // "who is watching this byte" wants all of them -- so the exercise makes entries 1 and 6 OVERLAP
  // and the transcript carries TWO found events for one command. A version that broke out of the
  // loop would print one, and the command counter would be identical.
  cs_setup();
  cs_res_eep[1].State = CS_ChecksumState_ENABLED;
  cs_res_eep[1].StartAddress = CS_EX_EEP_ADDR;
  cs_res_eep[1].NumBytesToChecksum = 0x100;
  cs_res_eep[6].State = CS_ChecksumState_DISABLED;
  cs_res_eep[6].StartAddress = CS_EX_EEP_ADDR + 0x40;
  cs_res_eep[6].NumBytesToChecksum = 0x80;
  // AND AN **EMPTY** ENTRY WHOSE RANGE ALSO CONTAINS THE ADDRESS, which must NOT report: the
  // `State != CS_ChecksumState_EMPTY` test is the first of the three conditions and nothing else
  // in this block would notice if it were dropped.
  cs_res_eep[8].State = CS_ChecksumState_EMPTY;
  cs_res_eep[8].StartAddress = CS_EX_EEP_ADDR;
  cs_res_eep[8].NumBytesToChecksum = 0x100;
  MemSet(&gc, 0, sizeof(CS_GetEntryIDEepromCmd_t));
  gc.Payload.Address = CS_EX_EEP_ADDR + 0x50;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_GetEntryIDEepromCmd(&gc);
  S("csec_getid cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
  // ONE PAST THE END OF ENTRY 1, which is the half-open test: StartAddress + NumBytes is NOT
  // inside the entry. An `<=` there would report entry 1 and this line would still say cc=2.
  gc.Payload.Address = CS_EX_EEP_ADDR + 0x100;
  CS_GetEntryIDEepromCmd(&gc);
  S("csec_getid_notfound cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
}

// --- cs_memory_cmds.c, seven commands, AND THIS BLOCK IS GENERATED FROM THE EEPROM ONE ABOVE BY
// THE SAME NAME MAP THAT GENERATED cs_memory_cmds.HC FROM cs_eeprom_cmds.HC. That is the point
// rather than a shortcut: the two NASA sources are line-for-line twins, so their two exercises must
// differ in EXACTLY the places upstream differs and nowhere else. Three places, each marked:
//
//   #13  the report command does NOT re-enable the entry here -- csmc_report_nobase prints
//        state_after=2 where csec_report_nobase printed 1.
//   #14  EntryID is assigned OUTSIDE the `if`, so the child-task-busy event reports the REAL
//        commanded id (7) where the EEPROM twin's said 0.
//   #16  the create-failed event says "ES_CreateChildTask returned:" with the CFE_ prefix DROPPED,
//        and with two spaces before the status. Both are in the transcript verbatim.
//
// Everything else about this block -- the fixed addresses, the half-open range test, the empty
// definition entry -- is explained once, at the EEPROM block above.
#define CS_EX_MEM_ADDR 0x00400000

U0 cs_block_memory_cmds()
{
  CS_RecomputeBaselineTableCmd_t cb;
  CS_ReportBaselineEntryIDMemoryCmd_t ec;
  CS_GetEntryIDMemoryCmd_t gc;
  I64 d0;

  cs_fill_sources();
  cs_setup();
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_EX_CDS_STATES, "CSMEM");

  // --- CS_DisableMemoryCmd and CS_EnableMemoryCmd. THE GUARD IS THE FIRST THING EACH DOES, and a
  // refused command moves the ERROR counter from inside CS_CheckRecomputeOneshot rather than from
  // the handler -- so the handler's own counter must NOT move, which is what makes cc=0 on the
  // refused line an assertion rather than an absence.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  CS_DisableMemoryCmd(&cb);
  S("csmc_dis_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S("\n");
  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  cs_res_mem[2].TempChecksumValue = 0x9999;
  cs_res_mem[2].ByteOffset = 12;
  d0 = es_cds_writes;
  CS_DisableMemoryCmd(&cb);
  S("csmc_dis cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" temp=");
  D(cs_res_mem[2].TempChecksumValue);
  S(" off=");
  D(cs_res_mem[2].ByteOffset);
  S(" writes=");
  D(es_cds_writes - d0);
  S("\n");
  cs_res_mem[2].TempChecksumValue = 0x9999;
  cs_res_mem[2].ByteOffset = 12;
  CS_EnableMemoryCmd(&cb);
  S("csmc_en cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" temp=");
  D(cs_res_mem[2].TempChecksumValue);
  S(" off=");
  D(cs_res_mem[2].ByteOffset);
  S("\n");

  // --- CS_ReportBaselineEntryIDMemoryCmd. UPSTREAM DIFFERENCE #13, AND THIS IS THE HALF THAT
  // MAKES IT A DEFECT RATHER THAN A CONVENTION: the same three lines as the EEPROM twin, and NO
  // `ResultsEntry->State = CS_ChecksumState_ENABLED`. So csmc_report_nobase prints state_after=2
  // -- the entry is still DISABLED -- where csec_report_nobase printed 1.
  //
  // Two lines of transcript, one number apart, in two functions that are otherwise identical. That
  // pair is the evidence; a note in a document asserting it would not be.
  MemSet(&ec, 0, sizeof(CS_ReportBaselineEntryIDMemoryCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  ec.Payload.EntryID = CS_MAX_NUM_MEMORY_TABLE_ENTRIES;
  CS_ReportBaselineEntryIDMemoryCmd(&ec);
  S("csmc_report_badid cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  cs_res_mem[4].State = CS_ChecksumState_DISABLED;
  cs_res_mem[4].ComputedYet = FALSE;
  cs_res_mem[4].ComparisonValue = 0x1357;
  ec.Payload.EntryID = 4;
  S("csmc_report_before state=");
  D(cs_res_mem[4].State);
  S("\n");
  CS_ReportBaselineEntryIDMemoryCmd(&ec);
  S("csmc_report_nobase cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state_after=");
  D(cs_res_mem[4].State);
  S("\n");
  cs_res_mem[4].ComputedYet = TRUE;
  CS_ReportBaselineEntryIDMemoryCmd(&ec);
  S("csmc_report cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");

  // --- CS_RecomputeBaselineMemoryCmd. UPSTREAM DIFFERENCE #14, the other half of the same pair:
  // `EntryID = CmdPtr->Payload.EntryID` is OUTSIDE the `if` here, so the busy event reports the id
  // the ground actually sent. SAME COMMANDED ID AS THE EEPROM BLOCK -- 7 -- and the transcript says
  // "Memory Entry ID 7 failed: child task in use" where the EEPROM one said "EEPROM Entry ID 0".
  //
  // AND UPSTREAM DIFFERENCE #16 IS IN THE create-failed LINE BELOW: this file's event text is
  // "ES_CreateChildTask returned:  0x%08X" -- no CFE_ prefix, and two spaces. A ground decoder
  // keyed on the other six child-task failure texts misses this one. Kept verbatim, and in the
  // transcript to be read.
  cs_setup();
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  ec.Payload.EntryID = 7;
  CS_RecomputeBaselineMemoryCmd(&ec);
  S("csmc_recomp_busy ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  // An id past the end: the inner arm, which reports the real id because it is inside the if.
  ec.Payload.EntryID = CS_MAX_NUM_MEMORY_TABLE_ENTRIES + 3;
  CS_RecomputeBaselineMemoryCmd(&ec);
  S("csmc_recomp_badid ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  // The create failing, and then succeeding. ChildTaskEntryID is the witness that the command's id
  // reached the child-task variables at all -- the event on the busy path cannot show it.
  cs_res_mem[9].State = CS_ChecksumState_ENABLED;
  ec.Payload.EntryID = 9;
  es_taskcreate_rc = OS_ERROR;
  CS_RecomputeBaselineMemoryCmd(&ec);
  S("csmc_recomp_fail ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_RecomputeBaselineMemoryCmd(&ec);
  S("csmc_recomp cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" type=");
  D(CS_AppData.ChildTaskTable);
  S(" ent=");
  D(CS_AppData.ChildTaskEntryID);
  S(" ptr=");
  D(CS_AppData.RecomputeEepromMemoryEntryPtr == &cs_res_mem[9]);
  S("\n");

  // --- CS_EnableEntryIDMemoryCmd and CS_DisableEntryIDMemoryCmd, FOUR ARMS EACH.
  //
  // BOTH WRITE **TWO** TABLES, and the definition write can fail quietly: CS_SetDefEntryState
  // returns the PREVIOUS state, and a previous state that is not commandable means the definition
  // entry is EMPTY -- so the results entry changes and the definition entry does not, and the
  // mismatch survives only until the next ground table load. That is the DEBUG event, and it is
  // driven: entry 5's definition entry is left EMPTY on purpose while entry 3's is DISABLED. Both
  // definition states are printed, so "wrote the results entry and not the definition entry" is
  // visible rather than implied.
  //
  // AND THE DISABLE CLEARS THE PARTIAL CHECKSUM WHERE THE ENABLE DOES NOT, the same asymmetry as
  // every other disable in CS. Poisoned before each so the difference is a number.
  cs_setup();
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  ec.Payload.EntryID = 3;
  CS_EnableEntryIDMemoryCmd(&ec);
  CS_DisableEntryIDMemoryCmd(&ec);
  S("csmc_entry_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  ec.Payload.EntryID = CS_MAX_NUM_MEMORY_TABLE_ENTRIES + 1;
  CS_EnableEntryIDMemoryCmd(&ec);
  CS_DisableEntryIDMemoryCmd(&ec);
  S("csmc_entry_badid ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  cs_res_mem[3].State = CS_ChecksumState_DISABLED;
  cs_res_mem[3].TempChecksumValue = 0x2468;
  cs_res_mem[3].ByteOffset = 20;
  cs_def_mem[3].State = CS_ChecksumState_DISABLED;
  cs_res_mem[5].State = CS_ChecksumState_DISABLED;
  cs_def_mem[5].State = CS_ChecksumState_EMPTY;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  ec.Payload.EntryID = 3;
  CS_EnableEntryIDMemoryCmd(&ec);
  S("csmc_en_entry cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_mem[3].State);
  S(" def=");
  D(cs_def_mem[3].State);
  S(" temp=");
  D(cs_res_mem[3].TempChecksumValue);
  S(" off=");
  D(cs_res_mem[3].ByteOffset);
  S("\n");
  CS_DisableEntryIDMemoryCmd(&ec);
  S("csmc_dis_entry cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_mem[3].State);
  S(" def=");
  D(cs_def_mem[3].State);
  S(" temp=");
  D(cs_res_mem[3].TempChecksumValue);
  S(" off=");
  D(cs_res_mem[3].ByteOffset);
  S("\n");
  // THE DEFINITION ENTRY THAT IS EMPTY: the results entry moves, the definition entry does not,
  // and a DEBUG event says so.
  ec.Payload.EntryID = 5;
  CS_EnableEntryIDMemoryCmd(&ec);
  S("csmc_en_entry_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_mem[5].State);
  S(" def=");
  D(cs_def_mem[5].State);
  S("\n");
  CS_DisableEntryIDMemoryCmd(&ec);
  S("csmc_dis_entry_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_mem[5].State);
  S(" def=");
  D(cs_def_mem[5].State);
  S("\n");

  // --- CS_GetEntryIDMemoryCmd. THE LOOP DOES NOT STOP AT THE FIRST MATCH: it walks the whole
  // table and sends an event for EVERY entry whose range contains the address, so overlapping
  // definition entries all report. That is NASA's and it is the right answer -- an operator asking
  // "who is watching this byte" wants all of them -- so the exercise makes entries 1 and 6 OVERLAP
  // and the transcript carries TWO found events for one command. A version that broke out of the
  // loop would print one, and the command counter would be identical.
  cs_setup();
  cs_res_mem[1].State = CS_ChecksumState_ENABLED;
  cs_res_mem[1].StartAddress = CS_EX_MEM_ADDR;
  cs_res_mem[1].NumBytesToChecksum = 0x100;
  cs_res_mem[6].State = CS_ChecksumState_DISABLED;
  cs_res_mem[6].StartAddress = CS_EX_MEM_ADDR + 0x40;
  cs_res_mem[6].NumBytesToChecksum = 0x80;
  // AND AN **EMPTY** ENTRY WHOSE RANGE ALSO CONTAINS THE ADDRESS, which must NOT report: the
  // `State != CS_ChecksumState_EMPTY` test is the first of the three conditions and nothing else
  // in this block would notice if it were dropped.
  cs_res_mem[8].State = CS_ChecksumState_EMPTY;
  cs_res_mem[8].StartAddress = CS_EX_MEM_ADDR;
  cs_res_mem[8].NumBytesToChecksum = 0x100;
  MemSet(&gc, 0, sizeof(CS_GetEntryIDMemoryCmd_t));
  gc.Payload.Address = CS_EX_MEM_ADDR + 0x50;
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_GetEntryIDMemoryCmd(&gc);
  S("csmc_getid cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
  // ONE PAST THE END OF ENTRY 1, which is the half-open test: StartAddress + NumBytes is NOT
  // inside the entry. An `<=` there would report entry 1 and this line would still say cc=2.
  gc.Payload.Address = CS_EX_MEM_ADDR + 0x100;
  CS_GetEntryIDMemoryCmd(&gc);
  S("csmc_getid_notfound cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
}

// --- cs_table_cmds.c, six commands, and THE FILE WHERE AN EVENT CANNOT CROSS THE DIFFERENTIAL.
//
// CS_RecomputeBaselineTableCmd's child-task-busy event prints `Name`, and the StrNCpy that fills
// Name is INSIDE the `if` -- so on that path the event carries up to 40 bytes of whatever the frame
// held, with no guarantee of a terminator inside the array (upstream note #15). A host process's
// stack and a QEMU guest's hold different rubbish, so that event is the fourth kind in this port
// that cannot be compared: it joins the one that prints a real pointer.
//
// SO IT IS DRIVEN WITH THE EVS OUTPUT PORT CLOSED, which is the technique CS_OneShotChildTask
// established. The event is still built, filtered, counted and transmitted -- every line of
// CFE_EVS_SendEvent runs -- and only the human-readable copy is not printed.
// EVS_TlmPkt.Payload.MessageSendCounter is the witness. Leaving the arm undriven, which is what MM
// did with its uncomparable events, would leave the defect unproven as well as unexercised.
U0 cs_block_table_cmds()
{
  CS_RecomputeBaselineTableCmd_t tc;
  CS_Res_Tables_Table_Entry_t *rt;
  U8 port_saved;
  U16 sent_before;
  I64 d0;

  // EVERY LENGTH HERE IS THE CONSTANT, NOT A sizeof. Both are 40 -- CFE_TBL_MAX_FULL_NAME_LEN,
  // CFE_MISSION_TBL_MAX_FULL_NAME_LEN and CS_Res_Tables_Table_Entry_t.Name all agree -- and the
  // constant is what this half can spell: docs/HOLYC_STRUCT_LIMITS.md #16 records that `sizeof`
  // through a `->` fails here, and writing the two halves differently in a place where a length is
  // the thing under test is how a difference becomes invisible.
  cs_fill_sources();
  cs_setup();
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_EX_CDS_STATES, "CSTBL");

  // THREE NAMED RESULTS ENTRIES, and the names are what every command in this file looks up. Entry
  // 0 has a matching DEFINITION entry; entry 1 does NOT, which is the DEBUG arm; entry 2 is EMPTY
  // with a name, which must never match -- CS_GetTableResTblEntryByName tests `State != EMPTY`
  // BEFORE the name compare, and nothing else here reads that test.
  StrNCpy(cs_res_tbl[0].Name, "CS.EepromTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  cs_res_tbl[0].State = CS_ChecksumState_DISABLED;
  StrNCpy(cs_def_tbl[0].Name, "CS.EepromTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  cs_def_tbl[0].State = CS_ChecksumState_DISABLED;
  StrNCpy(cs_res_tbl[1].Name, "CS.Orphan", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  cs_res_tbl[1].State = CS_ChecksumState_DISABLED;
  StrNCpy(cs_res_tbl[2].Name, "CS.EmptyOne", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  cs_res_tbl[2].State = CS_ChecksumState_EMPTY;

  // --- CS_DisableTablesCmd and CS_EnableTablesCmd, the whole-table pair. Same shape as the EEPROM
  // pair: a refused command, then the disable zeroing the partial state and writing the CDS, then
  // the enable zeroing nothing.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  CS_DisableTablesCmd(&tc);
  S("cstc_dis_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  cs_res_tbl[0].TempChecksumValue = 0xABCD;
  cs_res_tbl[0].ByteOffset = 36;
  d0 = es_cds_writes;
  CS_DisableTablesCmd(&tc);
  S("cstc_dis cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" temp=");
  D(cs_res_tbl[0].TempChecksumValue);
  S(" off=");
  D(cs_res_tbl[0].ByteOffset);
  S(" writes=");
  D(es_cds_writes - d0);
  S("\n");
  cs_res_tbl[0].TempChecksumValue = 0xABCD;
  cs_res_tbl[0].ByteOffset = 36;
  CS_EnableTablesCmd(&tc);
  S("cstc_en cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" temp=");
  D(cs_res_tbl[0].TempChecksumValue);
  S(" off=");
  D(cs_res_tbl[0].ByteOffset);
  S("\n");

  // --- CS_ReportBaselineTableCmd, FOUR LOOKUPS.
  //
  // AND THE UNTERMINATED NAME IS THE ONE WORTH THE SETUP. The command's Name field may fill all 40
  // bytes with no NUL, which is why NASA copies with strncpy(..., len - 1) and then writes the
  // terminator by hand. So one call passes a Name field filled to the brim with 'Z' and no
  // terminator: a handler that copied the whole 40 bytes, or that trusted the command's own field,
  // would read past it. The event text is then 39 'Z's, which is comparable and is in the
  // transcript.
  //
  // The other three: the entry with no baseline yet, the same entry with one, and a name that
  // matches nothing.
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  StrNCpy(tc.Payload.Name, "CS.EepromTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  cs_res_tbl[0].ComputedYet = FALSE;
  cs_res_tbl[0].ComparisonValue = 0x2BAD;
  CS_ReportBaselineTableCmd(&tc);
  S("cstc_report_nobase cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
  cs_res_tbl[0].ComputedYet = TRUE;
  CS_ReportBaselineTableCmd(&tc);
  S("cstc_report cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
  MemSet(tc.Payload.Name, 'Z', CFE_TBL_MAX_FULL_NAME_LEN);
  CS_ReportBaselineTableCmd(&tc);
  S("cstc_report_unterm ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  StrNCpy(tc.Payload.Name, "CS.EmptyOne", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CS_ReportBaselineTableCmd(&tc);
  S("cstc_report_empty ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- CS_EnableNameTableCmd and CS_DisableNameTableCmd, FOUR ARMS EACH.
  //
  // THE DEFINITION ENTRY IS OPTIONAL HERE, which is the difference from the EEPROM pair: a table CS
  // is watching need NOT be in the definition table at all -- it can have arrived from a results
  // table that outlived a definition load -- so a missing definition entry is a DEBUG event and the
  // command still SUCCEEDS. Entry 0 has one and entry 1 does not, and both definition states are
  // printed so "wrote the results entry and not the definition entry" is a number rather than a
  // claim.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  StrNCpy(tc.Payload.Name, "CS.EepromTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CS_EnableNameTableCmd(&tc);
  CS_DisableNameTableCmd(&tc);
  S("cstc_name_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  cs_res_tbl[0].TempChecksumValue = 0x1357;
  cs_res_tbl[0].ByteOffset = 28;
  CS_EnableNameTableCmd(&tc);
  S("cstc_en_name cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_tbl[0].State);
  S(" def=");
  D(cs_def_tbl[0].State);
  S(" temp=");
  D(cs_res_tbl[0].TempChecksumValue);
  S(" off=");
  D(cs_res_tbl[0].ByteOffset);
  S("\n");
  CS_DisableNameTableCmd(&tc);
  S("cstc_dis_name cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_tbl[0].State);
  S(" def=");
  D(cs_def_tbl[0].State);
  S(" temp=");
  D(cs_res_tbl[0].TempChecksumValue);
  S(" off=");
  D(cs_res_tbl[0].ByteOffset);
  S("\n");
  StrNCpy(tc.Payload.Name, "CS.Orphan", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CS_EnableNameTableCmd(&tc);
  S("cstc_en_name_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_tbl[1].State);
  S("\n");
  CS_DisableNameTableCmd(&tc);
  S("cstc_dis_name_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_tbl[1].State);
  S("\n");
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  StrNCpy(tc.Payload.Name, "CS.NoSuchTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CS_EnableNameTableCmd(&tc);
  CS_DisableNameTableCmd(&tc);
  S("cstc_name_unknown ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- CS_RecomputeBaselineTableCmd. THE NAMED ARMS FIRST, ALL COMPARABLE, AND THE UNCOMPARABLE
  // ONE LAST BEHIND A CLOSED PORT.
  //
  // (a) a name that matches nothing -- Name HAS been copied, so this event is comparable.
  // (b) the create failing.
  // (c) the create succeeding; ChildTaskTable and RecomputeTablesEntryPtr are the witnesses that
  //     the command's own entry reached the child-task variables.
  // (d) the busy arm, UPSTREAM DEFECT #15: Name is never written on that path. Port closed,
  //     MessageSendCounter is the witness, restored immediately after.
  //
  // THE COUNTER READS TWO, and that is accounted for rather than waved at: it increments once per
  // event in EVS_GenerateEventTelemetry, and the second event is the one the FIRST provokes --
  // transmitting it finds no subscriber for the long-event MsgId and SB reports that with an event
  // of its own. So closing the port suppresses BOTH port lines. The same arithmetic
  // csh_oneshot_sent records, and the same arithmetic a first draft of that comment got wrong.
  cs_setup();
  StrNCpy(cs_res_tbl[0].Name, "CS.EepromTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  cs_res_tbl[0].State = CS_ChecksumState_ENABLED;
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  StrNCpy(tc.Payload.Name, "CS.NoSuchTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  CS_RecomputeBaselineTableCmd(&tc);
  S("cstc_recomp_unknown ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  StrNCpy(tc.Payload.Name, "CS.EepromTbl", CFE_TBL_MAX_FULL_NAME_LEN - 1);
  es_taskcreate_rc = OS_ERROR;
  CS_RecomputeBaselineTableCmd(&tc);
  S("cstc_recomp_fail ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;
  CS_RecomputeBaselineTableCmd(&tc);
  rt = CS_GetTablesResEntry(0);
  S("cstc_recomp cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" type=");
  D(CS_AppData.ChildTaskTable);
  S(" ptr=");
  D(CS_AppData.RecomputeTablesEntryPtr == rt);
  S("\n");
  // (d) THE BUSY ARM, behind a closed port.
  port_saved = CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort;
  sent_before = CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter;
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = 0;
  CS_RecomputeBaselineTableCmd(&tc);
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = port_saved;
  S("cstc_recomp_busy ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" sent=");
  D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter - sent_before);
  S("\n");
}

// --- cs_app_cmds.c, six commands, GENERATED FROM THE TABLE BLOCK ABOVE -- AND THIS TWIN PAIR HAS
// NO UPSTREAM DIFFERENCES AT ALL, which was measured rather than assumed.
//
// NASA's cs_table_cmds.c and cs_app_cmds.c, diffed against each other with the type words
// normalised to one token, differ in WHITESPACE AND COMMENTS ONLY: a column of padding, four
// header-banner widths, and three "command verification variables" comments present in one file
// and not the other. Not one statement. So this block is a pure name map of the one above, with no
// markers -- where the eeprom/memory pair needed three.
//
// That is worth stating because it cuts the other way too: finding nothing is only evidence if the
// same method found something elsewhere. The same normalised diff over the eeprom/memory pair
// returned five lines, and all five are real (notes #13, #14 and #16). Here it returns none.
//
// ONE THING DOES DIFFER, and it is not upstream: the names are APP names, so every length is
// OS_MAX_API_NAME (20) rather than CFE_TBL_MAX_FULL_NAME_LEN (40). The unterminated-name event
// therefore carries 19 'Z's here and 39 there.
//
// CS_RecomputeBaselineAppCmd's child-task-busy event prints `Name` with the StrNCpy that fills it
// INSIDE the `if` -- upstream note #15, the other half of the pair cs_table_cmds carries -- so it
// is driven the same way, with the EVS output port closed and MessageSendCounter as the witness.
U0 cs_block_app_cmds()
{
  CS_RecomputeBaselineAppCmd_t tc;
  CS_Res_App_Table_Entry_t *rt;
  U8 port_saved;
  U16 sent_before;
  I64 d0;

  // EVERY LENGTH HERE IS THE CONSTANT, NOT A sizeof. All three are 20 -- OS_MAX_API_NAME,
  // CFE_MISSION_MAX_API_LEN and CS_Res_App_Table_Entry_t.Name agree -- and the
  // constant is what this half can spell: docs/HOLYC_STRUCT_LIMITS.md #16 records that `sizeof`
  // through a `->` fails here, and writing the two halves differently in a place where a length is
  // the thing under test is how a difference becomes invisible.
  cs_fill_sources();
  cs_setup();
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_EX_CDS_STATES, "CSAPP");

  // THREE NAMED RESULTS ENTRIES, and the names are what every command in this file looks up. Entry
  // 0 has a matching DEFINITION entry; entry 1 does NOT, which is the DEBUG arm; entry 2 is EMPTY
  // with a name, which must never match -- CS_GetAppResTblEntryByName tests `State != EMPTY`
  // BEFORE the name compare, and nothing else here reads that test.
  StrNCpy(cs_res_app[0].Name, "CS_APP_ONE", OS_MAX_API_NAME - 1);
  cs_res_app[0].State = CS_ChecksumState_DISABLED;
  StrNCpy(cs_def_app[0].Name, "CS_APP_ONE", OS_MAX_API_NAME - 1);
  cs_def_app[0].State = CS_ChecksumState_DISABLED;
  StrNCpy(cs_res_app[1].Name, "CS_ORPHAN", OS_MAX_API_NAME - 1);
  cs_res_app[1].State = CS_ChecksumState_DISABLED;
  StrNCpy(cs_res_app[2].Name, "CS_EMPTY", OS_MAX_API_NAME - 1);
  cs_res_app[2].State = CS_ChecksumState_EMPTY;

  // --- CS_DisableAppsCmd and CS_EnableAppsCmd, the whole-app pair. Same shape as the EEPROM
  // pair: a refused command, then the disable zeroing the partial state and writing the CDS, then
  // the enable zeroing nothing.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;
  CS_DisableAppsCmd(&tc);
  S("csac_dis_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S("\n");
  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  cs_res_app[0].TempChecksumValue = 0xABCD;
  cs_res_app[0].ByteOffset = 36;
  d0 = es_cds_writes;
  CS_DisableAppsCmd(&tc);
  S("csac_dis cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S(" temp=");
  D(cs_res_app[0].TempChecksumValue);
  S(" off=");
  D(cs_res_app[0].ByteOffset);
  S(" writes=");
  D(es_cds_writes - d0);
  S("\n");
  cs_res_app[0].TempChecksumValue = 0xABCD;
  cs_res_app[0].ByteOffset = 36;
  CS_EnableAppsCmd(&tc);
  S("csac_en cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" state=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S(" temp=");
  D(cs_res_app[0].TempChecksumValue);
  S(" off=");
  D(cs_res_app[0].ByteOffset);
  S("\n");

  // --- CS_ReportBaselineAppCmd, FOUR LOOKUPS.
  //
  // AND THE UNTERMINATED NAME IS THE ONE WORTH THE SETUP. The command's Name field may fill all 20
  // bytes with no NUL, which is why NASA copies with strncpy(..., len - 1) and then writes the
  // terminator by hand. So one call passes a Name field filled to the brim with 'Z' and no
  // terminator: a handler that copied the whole 20 bytes, or that trusted the command's own field,
  // would read past it. The event text is then 19 'Z's, which is comparable and is in the
  // transcript.
  //
  // The other three: the entry with no baseline yet, the same entry with one, and a name that
  // matches nothing.
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineAppCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  StrNCpy(tc.Payload.Name, "CS_APP_ONE", OS_MAX_API_NAME - 1);
  cs_res_app[0].ComputedYet = FALSE;
  cs_res_app[0].ComparisonValue = 0x2BAD;
  CS_ReportBaselineAppCmd(&tc);
  S("csac_report_nobase cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
  cs_res_app[0].ComputedYet = TRUE;
  CS_ReportBaselineAppCmd(&tc);
  S("csac_report cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");
  MemSet(tc.Payload.Name, 'Z', OS_MAX_API_NAME);
  CS_ReportBaselineAppCmd(&tc);
  S("csac_report_unterm ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineAppCmd_t));
  StrNCpy(tc.Payload.Name, "CS_EMPTY", OS_MAX_API_NAME - 1);
  CS_ReportBaselineAppCmd(&tc);
  S("csac_report_empty ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- CS_EnableNameAppCmd and CS_DisableNameAppCmd, FOUR ARMS EACH.
  //
  // THE DEFINITION ENTRY IS OPTIONAL HERE, which is the difference from the EEPROM pair: a app CS
  // is watching need NOT be in the definition app at all -- it can have arrived from a results
  // app that outlived a definition load -- so a missing definition entry is a DEBUG event and the
  // command still SUCCEEDS. Entry 0 has one and entry 1 does not, and both definition states are
  // printed so "wrote the results entry and not the definition entry" is a number rather than a
  // claim.
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineAppCmd_t));
  StrNCpy(tc.Payload.Name, "CS_APP_ONE", OS_MAX_API_NAME - 1);
  CS_EnableNameAppCmd(&tc);
  CS_DisableNameAppCmd(&tc);
  S("csac_name_refused cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  cs_res_app[0].TempChecksumValue = 0x1357;
  cs_res_app[0].ByteOffset = 28;
  CS_EnableNameAppCmd(&tc);
  S("csac_en_name cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_app[0].State);
  S(" def=");
  D(cs_def_app[0].State);
  S(" temp=");
  D(cs_res_app[0].TempChecksumValue);
  S(" off=");
  D(cs_res_app[0].ByteOffset);
  S("\n");
  CS_DisableNameAppCmd(&tc);
  S("csac_dis_name cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_app[0].State);
  S(" def=");
  D(cs_def_app[0].State);
  S(" temp=");
  D(cs_res_app[0].TempChecksumValue);
  S(" off=");
  D(cs_res_app[0].ByteOffset);
  S("\n");
  StrNCpy(tc.Payload.Name, "CS_ORPHAN", OS_MAX_API_NAME - 1);
  CS_EnableNameAppCmd(&tc);
  S("csac_en_name_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_app[1].State);
  S("\n");
  CS_DisableNameAppCmd(&tc);
  S("csac_dis_name_nodef cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" res=");
  D(cs_res_app[1].State);
  S("\n");
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineAppCmd_t));
  StrNCpy(tc.Payload.Name, "CS_NOSUCH", OS_MAX_API_NAME - 1);
  CS_EnableNameAppCmd(&tc);
  CS_DisableNameAppCmd(&tc);
  S("csac_name_unknown ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- CS_RecomputeBaselineAppCmd. THE NAMED ARMS FIRST, ALL COMPARABLE, AND THE UNCOMPARABLE
  // ONE LAST BEHIND A CLOSED PORT.
  //
  // (a) a name that matches nothing -- Name HAS been copied, so this event is comparable.
  // (b) the create failing.
  // (c) the create succeeding; ChildTaskTable and RecomputeAppEntryPtr are the witnesses that
  //     the command's own entry reached the child-task variables.
  // (d) the busy arm, UPSTREAM DEFECT #15: Name is never written on that path. Port closed,
  //     MessageSendCounter is the witness, restored immediately after.
  //
  // THE COUNTER READS TWO, and that is accounted for rather than waved at: it increments once per
  // event in EVS_GenerateEventTelemetry, and the second event is the one the FIRST provokes --
  // transmitting it finds no subscriber for the long-event MsgId and SB reports that with an event
  // of its own. So closing the port suppresses BOTH port lines. The same arithmetic
  // csh_oneshot_sent records, and the same arithmetic a first draft of that comment got wrong.
  cs_setup();
  StrNCpy(cs_res_app[0].Name, "CS_APP_ONE", OS_MAX_API_NAME - 1);
  cs_res_app[0].State = CS_ChecksumState_ENABLED;
  MemSet(&tc, 0, sizeof(CS_RecomputeBaselineAppCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  StrNCpy(tc.Payload.Name, "CS_NOSUCH", OS_MAX_API_NAME - 1);
  CS_RecomputeBaselineAppCmd(&tc);
  S("csac_recomp_unknown ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  StrNCpy(tc.Payload.Name, "CS_APP_ONE", OS_MAX_API_NAME - 1);
  es_taskcreate_rc = OS_ERROR;
  CS_RecomputeBaselineAppCmd(&tc);
  S("csac_recomp_fail ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S("\n");
  es_taskcreate_rc = OS_SUCCESS;
  CS_RecomputeBaselineAppCmd(&tc);
  rt = CS_GetAppResEntry(0);
  S("csac_recomp cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" type=");
  D(CS_AppData.ChildTaskTable);
  S(" ptr=");
  D(CS_AppData.RecomputeAppEntryPtr == rt);
  S("\n");
  // (d) THE BUSY ARM, behind a closed port.
  port_saved = CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort;
  sent_before = CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter;
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = 0;
  CS_RecomputeBaselineAppCmd(&tc);
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = port_saved;
  S("csac_recomp_busy ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S(" sent=");
  D(CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter - sent_before);
  S("\n");
}

// --- cs_dispatch.c: the length check, the forty-case switch, and the pipe router -------------
//
// CS HAS MORE COMMANDS THAN MD AND MM PUT TOGETHER -- 40 against 7 and 10 -- and the point of this
// block is that all forty go through CS_AppPipe rather than being called directly. Direct calls are
// what the five blocks above do, and they leave CS_ProcessCmd, CS_VerifyCmdLength and the forty
// switch arms UNRUN while check_coverage stays green, because that gate is blind to execution.
//
// A CFE_SB_Buffer IS ONLY AN 8-BYTE ALIGNMENT UNION, so a command is built in a
// CS_RecomputeBaselineTableCmd_t -- the largest of the forty-three at 48 bytes -- and its address
// passed as the buffer. `&BufPtr->Msg` is at offset 0 either way, which is what makes that
// substitution exact rather than convenient. MD's block established it.
//
// EACH COMMAND IS SENT WITH **ITS OWN** CORRECT LENGTH, from a table generated out of NASA's own
// switch rather than written by hand: a bare command header is 8 bytes, an EntryID command is 12
// and a name command is 48, so the length check is per-case and a single length would make
// thirty-nine of the forty take the error arm and look routed.
//
// AND THE TWO FLAGS ARE CLEARED AFTER EVERY DISPATCH. Four of these forty set RecomputeInProgress
// or OneShotInProgress and this driver's OS_TaskCreate never runs the child that would clear them
// -- so without this, every command after the first recompute would take
// CS_CheckRecomputeOneshot's refuse path, both halves would agree, and thirty-odd lines would
// assert nothing. The flags are PRINTED before they are cleared, so the four that set one are
// visible as themselves.
//
// CS_VerifyCmdLength IS A PUBLIC FUNCTION WITH NO DECLARATION ANYWHERE in NASA's CS -- upstream
// note #17, the second instance of the shape #3 records for OS_ConsoleWrite. cs_dispatch.h declares
// its two neighbours and not it. This half reaches it because cs_dispatch.HC is #included, so no
// prototype is needed here; the C oracle writes its own and says so.
U0 cs_block_dispatch()
{
  CS_RecomputeBaselineTableCmd_t cb;
  U16 ccs[40];
  I64 szs[40];
  I64 i;
  I64 ok;

  cs_fill_sources();
  cs_setup();
  CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_ENABLED;
  CFE_MSG_Init(&CS_AppData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CS_HK_TLM_MID),
               sizeof(CS_HkPacket_t));

  ccs[0] = CS_NOOP_CC;
  ccs[1] = CS_RESET_COUNTERS_CC;
  ccs[2] = CS_ONE_SHOT_CC;
  ccs[3] = CS_CANCEL_ONE_SHOT_CC;
  ccs[4] = CS_ENABLE_ALL_CS_CC;
  ccs[5] = CS_DISABLE_ALL_CS_CC;
  ccs[6] = CS_ENABLE_CFE_CORE_CC;
  ccs[7] = CS_DISABLE_CFE_CORE_CC;
  ccs[8] = CS_REPORT_BASELINE_CFE_CORE_CC;
  ccs[9] = CS_RECOMPUTE_BASELINE_CFE_CORE_CC;
  ccs[10] = CS_ENABLE_OS_CC;
  ccs[11] = CS_DISABLE_OS_CC;
  ccs[12] = CS_REPORT_BASELINE_OS_CC;
  ccs[13] = CS_RECOMPUTE_BASELINE_OS_CC;
  ccs[14] = CS_ENABLE_EEPROM_CC;
  ccs[15] = CS_DISABLE_EEPROM_CC;
  ccs[16] = CS_REPORT_BASELINE_ENTRY_ID_EEPROM_CC;
  ccs[17] = CS_RECOMPUTE_BASELINE_EEPROM_CC;
  ccs[18] = CS_ENABLE_ENTRY_ID_EEPROM_CC;
  ccs[19] = CS_DISABLE_ENTRY_ID_EEPROM_CC;
  ccs[20] = CS_GET_ENTRY_ID_EEPROM_CC;
  ccs[21] = CS_ENABLE_MEMORY_CC;
  ccs[22] = CS_DISABLE_MEMORY_CC;
  ccs[23] = CS_REPORT_BASELINE_ENTRY_ID_MEMORY_CC;
  ccs[24] = CS_RECOMPUTE_BASELINE_MEMORY_CC;
  ccs[25] = CS_ENABLE_ENTRY_ID_MEMORY_CC;
  ccs[26] = CS_DISABLE_ENTRY_ID_MEMORY_CC;
  ccs[27] = CS_GET_ENTRY_ID_MEMORY_CC;
  ccs[28] = CS_ENABLE_TABLES_CC;
  ccs[29] = CS_DISABLE_TABLES_CC;
  ccs[30] = CS_REPORT_BASELINE_TABLE_CC;
  ccs[31] = CS_RECOMPUTE_BASELINE_TABLE_CC;
  ccs[32] = CS_ENABLE_NAME_TABLE_CC;
  ccs[33] = CS_DISABLE_NAME_TABLE_CC;
  ccs[34] = CS_ENABLE_APPS_CC;
  ccs[35] = CS_DISABLE_APPS_CC;
  ccs[36] = CS_REPORT_BASELINE_APP_CC;
  ccs[37] = CS_RECOMPUTE_BASELINE_APP_CC;
  ccs[38] = CS_ENABLE_NAME_APP_CC;
  ccs[39] = CS_DISABLE_NAME_APP_CC;
  szs[0] = sizeof(CS_NoopCmd_t);
  szs[1] = sizeof(CS_ResetCountersCmd_t);
  szs[2] = sizeof(CS_OneShotCmd_t);
  szs[3] = sizeof(CS_CancelOneShotCmd_t);
  szs[4] = sizeof(CS_EnableAllCSCmd_t);
  szs[5] = sizeof(CS_DisableAllCSCmd_t);
  szs[6] = sizeof(CS_EnableCfeCoreCmd_t);
  szs[7] = sizeof(CS_DisableCfeCoreCmd_t);
  szs[8] = sizeof(CS_ReportBaselineCfeCoreCmd_t);
  szs[9] = sizeof(CS_RecomputeBaselineCfeCoreCmd_t);
  szs[10] = sizeof(CS_EnableOSCmd_t);
  szs[11] = sizeof(CS_DisableOSCmd_t);
  szs[12] = sizeof(CS_ReportBaselineOSCmd_t);
  szs[13] = sizeof(CS_RecomputeBaselineOSCmd_t);
  szs[14] = sizeof(CS_EnableEepromCmd_t);
  szs[15] = sizeof(CS_DisableEepromCmd_t);
  szs[16] = sizeof(CS_ReportBaselineEntryIDEepromCmd_t);
  szs[17] = sizeof(CS_RecomputeBaselineEepromCmd_t);
  szs[18] = sizeof(CS_EnableEntryIDEepromCmd_t);
  szs[19] = sizeof(CS_DisableEntryIDEepromCmd_t);
  szs[20] = sizeof(CS_GetEntryIDEepromCmd_t);
  szs[21] = sizeof(CS_EnableMemoryCmd_t);
  szs[22] = sizeof(CS_DisableMemoryCmd_t);
  szs[23] = sizeof(CS_ReportBaselineEntryIDMemoryCmd_t);
  szs[24] = sizeof(CS_RecomputeBaselineMemoryCmd_t);
  szs[25] = sizeof(CS_EnableEntryIDMemoryCmd_t);
  szs[26] = sizeof(CS_DisableEntryIDMemoryCmd_t);
  szs[27] = sizeof(CS_GetEntryIDMemoryCmd_t);
  szs[28] = sizeof(CS_EnableTablesCmd_t);
  szs[29] = sizeof(CS_DisableTablesCmd_t);
  szs[30] = sizeof(CS_ReportBaselineTableCmd_t);
  szs[31] = sizeof(CS_RecomputeBaselineTableCmd_t);
  szs[32] = sizeof(CS_EnableNameTableCmd_t);
  szs[33] = sizeof(CS_DisableNameTableCmd_t);
  szs[34] = sizeof(CS_EnableAppsCmd_t);
  szs[35] = sizeof(CS_DisableAppsCmd_t);
  szs[36] = sizeof(CS_ReportBaselineAppCmd_t);
  szs[37] = sizeof(CS_RecomputeBaselineAppCmd_t);
  szs[38] = sizeof(CS_EnableNameAppCmd_t);
  szs[39] = sizeof(CS_DisableNameAppCmd_t);

  // --- CS_VerifyCmdLength BOTH WAYS. The mismatch arm raises an event AND increments the error
  // counter, and the function returns a bool -- so the counter is what separates the two, and the
  // event text carries the MsgId, the command code, the actual length and the expected one, all
  // four of which it looks up ONLY when the length is wrong.
  MemSet(&cb, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(CS_CMD_MID), sizeof(CS_NoopCmd_t));
  CFE_MSG_SetFcnCode(&cb.CommandHeader.Msg, CS_NOOP_CC);
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  ok = CS_VerifyCmdLength(&cb.CommandHeader.Msg, sizeof(CS_NoopCmd_t));
  S("csd_len ok=");
  D(ok);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");
  ok = CS_VerifyCmdLength(&cb.CommandHeader.Msg, sizeof(CS_NoopCmd_t) + 1);
  S("csd_len bad=");
  D(ok);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- ALL FORTY COMMAND CODES THROUGH CS_AppPipe, each with its own length. The counters after
  // each dispatch say which arm was taken: a routing error moves the wrong one or neither.
  for (i = 0; i < 40; ++i) {
    MemSet(&cb, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
    CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(CS_CMD_MID), szs[i]);
    CFE_MSG_SetFcnCode(&cb.CommandHeader.Msg, ccs[i]);
    CS_AppData.HkPacket.Payload.CommandCounter = 0;
    CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
    CS_AppPipe(&cb);
    S("csd_cc");
    D(ccs[i]);
    S(" len=");
    D(szs[i]);
    S(" cc=");
    D(CS_AppData.HkPacket.Payload.CommandCounter);
    S(" ec=");
    D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
    S(" prog=");
    D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
    S(" one=");
    D(CS_AppData.HkPacket.Payload.OneShotInProgress);
    S("\n");
    CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
    CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  }

  // --- A WRONG LENGTH ON A COMMAND THAT HAS A PAYLOAD, through the switch. The arm is reached for
  // every one of the forty; one is enough to show the switch consults the length BEFORE calling the
  // handler, and the counter is what shows the handler did not run.
  MemSet(&cb, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(CS_CMD_MID), sizeof(CS_NoopCmd_t));
  CFE_MSG_SetFcnCode(&cb.CommandHeader.Msg, CS_ENABLE_ENTRY_ID_EEPROM_CC);
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppPipe(&cb);
  S("csd_badlen cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S(" ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- A COMMAND CODE NOTHING CLAIMS: the switch's `default:` arm.
  CFE_MSG_SetFcnCode(&cb.CommandHeader.Msg, 123);
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppPipe(&cb);
  S("csd_badcc ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- THE OTHER THREE ROUTES, which are CS_AppPipe's own if-chain rather than the switch.
  //
  // THE THREE MESSAGE IDS ARE CACHED IN STATIC LOCALS named CMD_MID, SEND_HK_MID and
  // BACKGROUND_CYCLE_MID, and CS IS THE SIXTH SET IN ONE TRANSLATION UNIT to use the first two --
  // cfe_es_dispatch, cfe_evs_dispatch, cfe_ta_dispatch, md_dispatch and mm_dispatch are the others.
  // For one commit all of them collided, because a HolyC static local became a global under its
  // bare name (docs/HOLYC_STRUCT_LIMITS.md #12, fixed). If that regressed, CS's cache would hold a
  // cFE module's id and these lines would route to the wrong handler. That is the check, not an
  // aside -- and it is why MD's dispatch is driven again at the END of this block.
  //
  // A HOUSEKEEPING REQUEST runs CS_SendHkCmd, so the witness is SB reporting no subscriber for the
  // packet it transmitted. A BACKGROUND CYCLE runs the walk, so the witness is CurrentCSTable
  // moving. An unknown id moves the error counter and nothing else.
  MemSet(&cb, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(CS_SEND_HK_MID),
               sizeof(CS_SendHkCmd_t));
  CS_AppData.HkPacket.Payload.CommandCounter = 55;
  i = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
  CS_AppPipe(&cb);
  S("csd_hk nosub=");
  D(CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - i);
  S(" cc=");
  D(CS_AppData.HkPacket.Payload.CommandCounter);
  S("\n");

  MemSet(&cb, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(CS_BACKGROUND_CYCLE_MID),
               sizeof(CS_BackgroundCheckCycleCmd_t));
  // AND CHECKSUMMING HAS TO BE TURNED BACK **ON** FIRST, which a first draft did not do and it made
  // this line vacuous: CS_DISABLE_ALL_CS_CC is one of the forty dispatched above, so ChecksumState
  // was DISABLED by the time the route was tested. The cycle then skipped its whole body, printed
  // `tbl=0 ent=0` -- which is also what "the route went nowhere" looks like -- and both halves
  // agreed. A route witness that reads the same when the route works and when it does not is not a
  // witness.
  CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_ENABLED;
  CS_AppData.CfeCoreCodeSeg.State = CS_ChecksumState_ENABLED;
  CS_AppData.CfeCoreCodeSeg.StartAddress = cs_src_a(U64);
  CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum = 16;
  CS_AppData.HkPacket.Payload.CurrentCSTable = 0;
  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
  CS_AppPipe(&cb);
  S("csd_bkgnd tbl=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S(" ent=");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" cfe=");
  D(CS_AppData.CfeCoreCodeSeg.ComparisonValue);
  S("\n");

  // A HOUSEKEEPING REQUEST WITH THE WRONG LENGTH: the SEND_HK arm's own length check, which is not
  // the switch's.
  CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(CS_SEND_HK_MID),
               sizeof(CS_SendHkCmd_t) + 4);
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppPipe(&cb);
  S("csd_hk_badlen ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // AN UNKNOWN MESSAGE ID. 0x1898 is one no app in this tree subscribes to.
  MemSet(&cb, 0, sizeof(CS_RecomputeBaselineTableCmd_t));
  CFE_MSG_Init(&cb.CommandHeader.Msg, CFE_SB_ValueToMsgId(0x1898), sizeof(CS_NoopCmd_t));
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppPipe(&cb);
  S("csd_badmid ec=");
  D(CS_AppData.HkPacket.Payload.CommandErrorCounter);
  S("\n");

  // --- AND MD'S DISPATCHER AGAIN, AFTER CS'S HAS WARMED ITS CACHE. Three lines, and they are the
  // cross-app assertion a per-app exercise cannot make: if CMD_MID or SEND_HK_MID were globals
  // shared between the six dispatchers in this unit, CS's cache would now be sitting in MD's and a
  // NOOP would not reach MD_NoopCmd. MD's counter is the witness.
  {
    MD_NoopCmd_t mb;

    MemSet(&mb, 0, sizeof(MD_NoopCmd_t));
    CFE_MSG_Init(&mb.CmdHeader.Msg, CFE_SB_ValueToMsgId(MD_CMD_MID), sizeof(MD_NoopCmd_t));
    CFE_MSG_SetFcnCode(&mb.CmdHeader.Msg, MD_NOOP_CC);
    MD_AppData.CommandCounter = 0;
    MD_AppData.CommandErrorCounter = 0;
    MD_TaskPipe(&mb);
    S("csd_md_still_routes cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
  }
}

// --- cs_app.c: the startup chain, the CDS, and the main loop ---------------------------------
//
// THE LAST BLOCK, AND IT HAS TO BE LAST. It re-runs CFE_TBL_EarlyInit to clear the table registry
// so CS can register its OWN eight tables for real -- which pulls MD's, MM's and cs_block_init's
// tables out from under them. That is MD's lesson, paid for there: its app block moved earlier once
// and every editor in its command block answered CFE_TBL_ERR_NEVER_LOADED, a 54-line diff entirely
// self-inflicted. It also leaks one more pair of TBL pools, which is the sixth (docs/CFS_PLAN.md's
// shared-fixture note counts them).
//
// THE ORDER INSIDE THE BLOCK WAS WRONG, AND A MUTATION IS WHAT SAID SO. The first version ran the
// four hand-driven CDS arms FIRST and CS_AppInit afterwards -- so by the time AppInit ran a store
// existed under CS_CDS_NAME, CS_CreateRestoreStatesFromCDS took the ALREADY_EXISTS branch, and all
// six states came from the store. **Deleting CS_AppInit's six platform-configuration assignments
// was then a NO-OP.** The comment claimed "the config first and the CDS overrides it -- the ORDER
// is the whole feature" and the transcript could not tell that order from "the CDS only".
//
// So CS_AppInit now runs FIRST, on a COLD boot. The two directions of the feature are then two
// lines that differ:
//
//   csap_init_states  ... os=1 cfe=1   <- a cold boot: the PLATFORM CONFIGURATION, and the only
//                                         thing that writes it is CS_AppInit's own assignment
//   csap_cds_warm     ... os=2 cfe=2   <- a warm boot: the STORE, over a caller that had the
//                                         opposite in all six
//
// AND THE PATTERN THE WARM BOOT RESTORES IS WRITTEN THROUGH CS'S OWN WRITER, CS_UpdateCDS, onto the
// store CS_AppInit created -- not planted by hand. A cold boot writes the configuration, which is
// all 1s, and restoring all 1s over all 1s would assert nothing.
//
// THE REGISTRATION-FAILED ARM COMES LAST, because its lever -- es_cds_reset(), which clears
// CFE_ES_Global.CDSIsAvailable -- turns the store off for good.
U0 cs_block_app()
{
  I32 rc;
  I64 x0;
  U8 back[CS_EX_CDS_STATES];
  I64 k;

  cs_fill_sources();
  cs_setup();

  // --- (1) CS_AppMain WITH AN AppInit THAT **SUCCEEDS**, which is the only shape that reaches both
  // of the two termination events AND CS_AppInit's nine-link chain -- and it took three attempts to
  // find.
  //
  // THE CHAIN IS `if (Result == CFE_SUCCESS)` FOUR TIMES, not nesting: register for events, zero
  // the whole global, stand up the bus, fill the four default tables, take the poweron states from
  // the platform config, let the CDS override them, register the eight tables, read the two code
  // segments, set the app enabled. Everything it needs has to be free first: the table registry
  // (cleared), the pipe name (released), the context (app 1).
  //
  // AND THIS IS A **COLD** BOOT, which is the whole reason it comes first. Nothing has used
  // CS_CDS_NAME yet, so CS_CreateRestoreStatesFromCDS takes the fresh-store branch and COPIES THE
  // SIX STATES OUT instead of reading any in -- which makes CS_AppInit's own
  // platform-configuration assignments the ONLY source of those values, and therefore
  // mutable-and-caught. Run second, after a store exists, deleting all six of them is a NO-OP;
  // that is what the first version of this block did and what a mutation found.
  //
  // AND IT GETS **ONE** CFE_TBL_EarlyInit, WHICH IS WHY AppInit IS RUN FROM INSIDE AppMain RATHER
  // THAN BESIDE IT. A draft called CS_AppInit() directly for the success path and then wanted a
  // second successful one inside CS_AppMain for the clean-exit event -- which needs the registry
  // cleared again, and the second CFE_TBL_EarlyInit printed `No free MemPool slots available`,
  // allocated nothing, and every table registration answered 0xC4000001. The app terminated with
  // APP_ERROR and the "clean exit" line read run=3. Each EarlyInit leaks its two pools
  // (docs/CFS_PLAN.md's shared-fixture note counts them) and CFE_PLATFORM_ES_MAX_MEMORY_POOLS is
  // finite. So there is exactly one, and AppMain does the only successful init.
  //
  // THE LEVER FOR THE CLEAN EXIT is CFE_ES_RunLoop's SECOND test:
  // `if (AppRecPtr->ControlReq.AppControlRequest == CFE_ES_RunStatus_APP_RUN)`, and anything else
  // writes the control request INTO *RunStatus and returns false. AppInit sets RunStatus to APP_RUN
  // itself so it cannot be pre-set, but the app RECORD can. MD's block records that pre-setting
  // ControlReq "did NOT work", which is true there for a different reason: MD's AppInit was
  // failing, so APP_ERROR was written over the control request's value before RunLoop ever looked.
  //
  // THE APP MUST ALSO BE A **CORE** APP FOR CFE_ES_ExitApp TO RETURN, and exits=0 IS NOT THE
  // WITNESS: for a CORE app ExitApp REFUSES and logs `Cannot Exit CORE Application`. That syslog
  // line is what proves ExitApp was reached; a zero count is also what "never called" looks like.
  // MD's block paid for that too.
  es_set_ctx(1);
  CFE_TBL_EarlyInit();
  CFE_TBL_InitData();
  CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
  sb_forget_queue_name(CS_CMD_PIPE_NAME);
  CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
  CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_EXIT;
  x0 = es_taskexits;
  CS_AppMain();
  CFE_ES_Global.AppTable[1].ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
  S("csap_main_exit exits=");
  D(es_taskexits - x0);
  S(" run=");
  D(CS_AppData.RunStatus);
  S("\n");

  // AND NOW EVERYTHING CS_AppInit SET, read out of the global AppMain left behind.
  //
  // MaxBytesPerCycle IS THE ONE TO WATCH: AppInit sets it to CS_DEFAULT_BYTES_PER_CYCLE, 16384. At
  // zero every checksum cycle clamps to zero bytes, CurrOffset never advances, and the three
  // recompute child tasks' `while (!DoneWithEntry)` does not terminate -- a QEMU timeout that reads
  // as a codegen bug. Nothing else in this port's exercises reaches the line that sets it.
  S("csap_init pipe=");
  D(CFE_ResourceId_IsDefined(CS_AppData.CmdPipe));
  S(" cks=");
  D(CS_AppData.HkPacket.Payload.ChecksumState);
  S(" budget=");
  D(CS_AppData.MaxBytesPerCycle);
  S(" cur=");
  D(CS_AppData.HkPacket.Payload.CurrentCSTable);
  S("/");
  D(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
  S(" prog=");
  D(CS_AppData.HkPacket.Payload.RecomputeInProgress);
  S(" one=");
  D(CS_AppData.HkPacket.Payload.OneShotInProgress);
  S("\n");
  // THE SIX STATES, AND WHAT THEY PROVE ON A COLD BOOT. Every CS_*_POWERON_STATE and both
  // CS_*CHECKSUM_STATE constants are 1 (ENABLED), so the two CODE-SEGMENT states read 1 -- the
  // configured value, and the only thing that could have written it is the assignment in
  // CS_AppInit. The four TABLE states read 2, because CS_InitAllTables DISABLES each of them
  // afterwards when its table loads from memory rather than from a file; that is a SECOND writer,
  // and it is why the four cannot witness the configuration or the CDS. The pair `os=1 cfe=1` here
  // against `os=2 cfe=2` in csap_cds_warm below is the two directions of the same feature.
  S("csap_init_states eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" os=");
  D(CS_AppData.HkPacket.Payload.OSCSState);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSState);
  S("\n");
  // THE HANDLE **VALUES**, NOT CFE_TBL_HANDLE_IS_VALID, and this is the trap cs_setup's own comment
  // warns about: CFE_TBL_BAD_TABLE_HANDLE is -1 and ZERO IS A PERFECTLY GOOD HANDLE. CS_AppInit
  // memsets the whole global, so the two code-segment types -- which have a NULL definition
  // filename and register nothing -- come out of CS_TableInit with handles of 0, and a validity test
  // prints `11` for them exactly as it does for the four real ones. A first draft did precisely
  // that and read as six registered pairs. The values distinguish them: 0/0 for the two segments,
  // eight distinct small handles for the four tables.
  S("csap_init_tables");
  for (k = 0; k < CS_NUM_TABLES; ++k) {
    S(" ");
    D(CS_AppData.Tbl[k].DefHandle);
    S("/");
    D(CS_AppData.Tbl[k].ResHandle);
  }
  S("\n");
  S("csap_init_seg cfe=");
  D(CS_AppData.CfeCoreCodeSeg.State);
  S("/");
  D(CS_AppData.CfeCoreCodeSeg.NumBytesToChecksum);
  S(" os=");
  D(CS_AppData.OSCodeSeg.State);
  S("/");
  D(CS_AppData.OSCodeSeg.NumBytesToChecksum);
  S("\n");


  // --- (2) THE STORE CS_AppInit JUST CREATED, READ BACK RAW. Six bytes of the platform
  // configuration, written by CS_CreateRestoreStatesFromCDS's fresh-store branch, in NASA'S OWN
  // ORDER -- eeprom, memory, APP, TABLES, os, cfecore, which is NOT the order of the checksum-type
  // enum. Read raw so a swap of slots 2 and 3 is visible; it would restore the app state into the
  // tables state on the next power-on and no counter would move.
  //
  // NOTE THE FOUR TABLE STATES READ 1 HERE AND csap_init_states READS 2 for the same four. That is
  // not a contradiction: the CDS write happens inside CS_CreateRestoreStatesFromCDS, BEFORE
  // CS_InitAllTables disables each table that loaded from memory. The store holds what the
  // configuration said; the live states hold what the table loads did.
  MemSet(back, 0xEE, CS_EX_CDS_STATES);
  S("csap_cds_bytes rc=");
  D(CFE_ES_RestoreFromCDS(back, CS_AppData.DataStoreHandle));
  for (k = 0; k < CS_EX_CDS_STATES; ++k) {
    S(" ");
    D(back[k]);
  }
  S("\n");

  // --- (3) A PATTERN THE CONFIGURATION COULD NEVER PRODUCE, WRITTEN THROUGH CS_UpdateCDS. That is
  // CS's own writer and one of the two functions closing the seven-source cycle, so this both
  // plants the warm boot's input and exercises the writer on a healthy store.
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.OSCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_DISABLED;
  x0 = es_cds_writes;
  CS_UpdateCDS();
  MemSet(back, 0xEE, CS_EX_CDS_STATES);
  CFE_ES_RestoreFromCDS(back, CS_AppData.DataStoreHandle);
  S("csap_cds_plant writes=");
  D(es_cds_writes - x0);
  for (k = 0; k < CS_EX_CDS_STATES; ++k) {
    S(" ");
    D(back[k]);
  }
  S("\n");
  // --- (4) THE WARM BOOT. Same name, so RegisterCDS answers CFE_ES_CDS_ALREADY_EXISTS and the six
  // states are READ back over whatever the caller had. POISON FIRST: all six are set to the
  // OPPOSITE of what is in the store, so a restore that did nothing would be visible.
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_DISABLED;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.OSCSState = CS_ChecksumState_ENABLED;
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_ENABLED;
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  rc = CS_CreateRestoreStatesFromCDS();
  S("csap_cds_warm rc=");
  D(rc);
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" os=");
  D(CS_AppData.HkPacket.Payload.OSCSState);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSState);
  S("\n");

  // --- (5) THE RESTORE FAILING. A broken CDS is NOT fatal -- the handle is set to
  // CFE_ES_CDS_BAD_HANDLE so CS_UpdateCDS stops trying, the six states go back to the PLATFORM
  // CONFIGURATION, an event says so, and the function returns CFE_SUCCESS so CS_AppInit carries on.
  // All three of those are asserted: the return, the handle and the six states.
  es_cds_read_rc = CFE_PSP_ERROR;
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  rc = CS_CreateRestoreStatesFromCDS();
  es_cds_read_rc = CFE_PSP_SUCCESS;
  S("csap_cds_resfail rc=");
  D(rc);
  S(" defined=");
  D(CFE_ResourceId_IsDefined(CS_AppData.DataStoreHandle));
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" mem=");
  D(CS_AppData.HkPacket.Payload.MemoryCSState);
  S(" app=");
  D(CS_AppData.HkPacket.Payload.AppCSState);
  S(" tbl=");
  D(CS_AppData.HkPacket.Payload.TablesCSState);
  S(" os=");
  D(CS_AppData.HkPacket.Payload.OSCSState);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSState);
  S("\n");

  // --- (6) THE COPY FAILING ON A **FRESH** STORE, which is the other of the two error event ids.
  // It needs a name that has never been used, because the copy arm is only reached when RegisterCDS
  // SUCCEEDS -- so this one cannot use CS_CDS_NAME, and the registration is done by hand with a
  // different name before the write knob is set. The event id is what distinguishes this from arm
  // (5), and both are in the transcript.
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  S("csap_cds_cpy_reg rc=");
  D(CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_EX_CDS_STATES, "CS_CDS2"));
  S("\n");
  es_cds_write_rc = CFE_PSP_ERROR;
  CS_UpdateCDS();
  es_cds_write_rc = CFE_PSP_SUCCESS;
  S("csap_cds_updfail defined=");
  D(CFE_ResourceId_IsDefined(CS_AppData.DataStoreHandle));
  S("\n");

  // --- (7) CS_AppMain WITH AN AppInit THAT FAILS, which is the ERROR termination event and the
  // other half of the pair. The pipe name CS just used is taken, so CFE_SB_CreatePipe refuses the
  // duplicate, AppInit returns that status, AppMain sets APP_ERROR, and CFE_ES_RunLoop's FIRST test
  // -- on the caller's own RunStatus, before any record lookup -- skips the loop entirely. That is
  // what makes this callable at all: on a real pipe with CS_WAKEUP_TIMEOUT of 1000 ms the loop's
  // timeout arm is "no action" and nothing ends it.
  //
  // The ERROR event carries RunStatus AND the last Result; the INFORMATION event above carried
  // RunStatus alone. Both are in the transcript.
  x0 = es_taskexits;
  CS_AppMain();
  S("csap_main_err exits=");
  D(es_taskexits - x0);
  S(" run=");
  D(CS_AppData.RunStatus);
  S("\n");
  CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;

  // --- (8) CS_AppInit ON ITS OWN, FAILING AT CS_SbInit -- the second link of the chain. The whole
  // rest of the chain is skipped, which is what the zeroes assert, and RunStatus is APP_RUN rather
  // than APP_ERROR because setting APP_ERROR is CS_AppMain's job and not AppInit's.
  rc = CS_AppInit();
  S("csap_init_sbfail rc=");
  D(rc);
  S(" run=");
  D(CS_AppData.RunStatus);
  S(" budget=");
  D(CS_AppData.MaxBytesPerCycle);
  S(" cks=");
  D(CS_AppData.HkPacket.Payload.ChecksumState);
  S("\n");

  // --- (9) THE CDS REGISTRATION FAILING, LAST, because the lever is permanent. es_cds_reset clears
  // CFE_ES_Global.CDSIsAvailable, so CFE_ES_RegisterCDS answers CFE_ES_NOT_IMPLEMENTED and the
  // third of the three event ids fires. The six states go back to the platform configuration and
  // the return is still CFE_SUCCESS.
  es_cds_reset();
  CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
  CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;
  rc = CS_CreateRestoreStatesFromCDS();
  S("csap_cds_regfail rc=");
  D(rc);
  S(" defined=");
  D(CFE_ResourceId_IsDefined(CS_AppData.DataStoreHandle));
  S(" eep=");
  D(CS_AppData.HkPacket.Payload.EepromCSState);
  S(" cfe=");
  D(CS_AppData.HkPacket.Payload.CfeCoreCSState);
  S("\n");
  // AND CS_UpdateCDS IS NOW SILENT, which is the property that makes a broken CDS non-fatal
  // everywhere and not just in CS_AppInit: every enable/disable command still works and simply does
  // not persist. The witness is a write count that does not move.
  x0 = es_cds_writes;
  CS_UpdateCDS();
  S("csap_cds_silent writes=");
  D(es_cds_writes - x0);
  S("\n");
}

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
  es_modinfo_code_addr = 0x11110000;
  es_modinfo_code_size = 0x1000;
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
  // AND THE COMMAND HANDLER TABLE, for the same reason and with the same hazard: NASA's
  // CFE_TBL_CmdHandlerTbl is a `const` file-scope array with initialisers, HolyC has no
  // file-scope aggregate initialiser, so it is filled at runtime and the fill MUST RUN BEFORE
  // ANY DISPATCH. A reader that runs first sees a table of zeroes, whose first row has a NULL
  // MsgId, so the search loop terminates immediately and EVERY command is reported as an
  // unknown message id -- silently, with no gate able to tell.
  CFE_TBL_CmdHandlerTblInit();
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
    // --- md_utils.c (MD -- THE FIRST cFS APP) ------------------------------------
    // Nine functions. The bitmask reader, five validators, the two alignment checks and the
    // address resolver, plus the summariser that walks a dwell table.
    //
    // EVERY ADDRESS BELOW IS A LITERAL CONSTANT, and that is the whole reason this block can
    // exist. MD_ResolveSymAddr returns Offset verbatim when SymName is empty, so the numbers
    // the two halves print are the numbers written here -- not a host pointer on one side and
    // a guest pointer on the other. See docs/CFS_PLAN.md.
    md_masks[0] = 0x0001;
    md_masks[1] = 0x0002;
    md_masks[2] = 0x000A;
    md_masks[3] = 0xFFFF;
    md_masks[4] = 0x0000;
    // MD_TableIsInMask. TableId 1 is the branch that does NOT shift -- `if (TableId - 1)` is
    // false -- and it is the one an off-by-one would get wrong.
    for (md_mi = 0; md_mi < 5; md_mi++) {
      S("md_mask ");
      D(md_masks[md_mi]);
      S(" ");
      D(MD_TableIsInMask(1, md_masks[md_mi]));
      D(MD_TableIsInMask(2, md_masks[md_mi]));
      D(MD_TableIsInMask(3, md_masks[md_mi]));
      D(MD_TableIsInMask(4, md_masks[md_mi]));
      S("\n");
    }
    // the three range validators, each at both edges and one past each
    S("md_entryid ");
    D(MD_ValidEntryId(0));
    D(MD_ValidEntryId(1));
    D(MD_ValidEntryId(MD_INTERFACE_DWELL_TABLE_SIZE));
    D(MD_ValidEntryId(MD_INTERFACE_DWELL_TABLE_SIZE + 1));
    S("\nmd_tableid ");
    D(MD_ValidTableId(0));
    D(MD_ValidTableId(1));
    D(MD_ValidTableId(MD_INTERFACE_NUM_DWELL_TABLES));
    D(MD_ValidTableId(MD_INTERFACE_NUM_DWELL_TABLES + 1));
    S("\nmd_fieldlen ");
    D(MD_ValidFieldLength(0));
    D(MD_ValidFieldLength(1));
    D(MD_ValidFieldLength(2));
    D(MD_ValidFieldLength(3));
    D(MD_ValidFieldLength(4));
    D(MD_ValidFieldLength(5));
    // The alignment pair. BOTH ARMS MATTER: NASA checks the address and then the SIZE, so
    // (8,6) must be rejected on the size alone -- a translation that dropped the second branch
    // would still pass a test that only ever moved the address.
    S("\nmd_a32 ");
    D(MD_Verify32Aligned(8, 4));
    D(MD_Verify32Aligned(9, 4));
    D(MD_Verify32Aligned(8, 6));
    D(MD_Verify32Aligned(0, 0));
    S("\nmd_a16 ");
    D(MD_Verify16Aligned(8, 2));
    D(MD_Verify16Aligned(7, 2));
    D(MD_Verify16Aligned(8, 3));
    D(MD_Verify16Aligned(0, 0));
    S("\n");
    // MD_ValidAddrRange is a one-line wrapper over the PSP, so the only thing worth asserting
    // is that it passes the call through and reports both answers. The call COUNTER is the
    // part that says it was really called: a stub returning a constant would satisfy the two
    // booleans on its own.
    md_before = es_psp_validates;
    es_psp_validate_rc = CFE_PSP_SUCCESS;
    md_k = MD_ValidAddrRange(0x00100000, 4);
    es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
    // The second call has to be made BEFORE the line is printed: docs record four separate
    // bugs from printf evaluating an argument that itself emits or mutates.
    md_k2 = MD_ValidAddrRange(0x00100000, 4);
    S("md_addrrange ");
    D(md_k);
    D(md_k2);
    S(" calls=");
    D(es_psp_validates - md_before);
    S("\n");
    es_psp_validate_rc = CFE_PSP_SUCCESS;
    // MD_ResolveSymAddr, all three outcomes. The empty-SymName branch is the one the rest of
    // this port's MD exercises stand on.
    MemSet(&md_sa, 0, sizeof(MD_SymAddr_t));
    md_sa.Offset = 0x00100040;
    md_ra = 0xDEAD;
    md_k = MD_ResolveSymAddr(&md_sa, &md_ra);
    S("md_resolve_off ");
    D(md_k);
    S(" ");
    D(md_ra);
    S("\n");
    StrCpy(md_sa.SymName, "MD_SIM_WINDOW");
    md_sa.Offset = 0x20;
    md_sym_rc = OS_SUCCESS;
    md_sym_addr = 0x00100000;
    md_ra = 0xDEAD;
    md_k = MD_ResolveSymAddr(&md_sa, &md_ra);
    S("md_resolve_sym ");
    D(md_k);
    S(" ");
    D(md_ra);
    S("\n");
    // a lookup FAILURE must leave the caller's variable alone, which is a property of the
    // branch and not of the return value
    md_sym_rc = OS_ERROR;
    md_ra = 0xDEAD;
    md_k = MD_ResolveSymAddr(&md_sa, &md_ra);
    S("md_resolve_fail ");
    D(md_k);
    S(" ");
    D(md_ra);
    S("\n");
    md_sym_rc = OS_SUCCESS;
    // MD_UpdateDwellControlInfo, three shapes of table.
    //   0: three entries, then a TERMINATOR, then a non-null entry after it. NASA's own
    //      comment says entries may follow a terminator and will not be processed, so the 99
    //      below must not reach Rate.
    //   1: all 25 entries full -- the EntryIndex < MD_INTERFACE_DWELL_TABLE_SIZE bound, which
    //      is the other way out of the loop.
    //   2: terminator first, so all three totals are zero.
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    MD_AppData.MD_DwellTables[0].Entry[0].Length = 1;
    MD_AppData.MD_DwellTables[0].Entry[0].Delay = 10;
    MD_AppData.MD_DwellTables[0].Entry[1].Length = 2;
    MD_AppData.MD_DwellTables[0].Entry[1].Delay = 20;
    MD_AppData.MD_DwellTables[0].Entry[2].Length = 4;
    MD_AppData.MD_DwellTables[0].Entry[2].Delay = 30;
    MD_AppData.MD_DwellTables[0].Entry[4].Length = 2;
    MD_AppData.MD_DwellTables[0].Entry[4].Delay = 99;
    for (md_k = 0; md_k < MD_INTERFACE_DWELL_TABLE_SIZE; md_k++) {
      MD_AppData.MD_DwellTables[1].Entry[md_k].Length = 4;
      MD_AppData.MD_DwellTables[1].Entry[md_k].Delay = 1;
    }
    for (md_k = 0; md_k < 3; md_k++) {
      MD_UpdateDwellControlInfo(md_k);
      S("md_dwell_sum ");
      D(md_k);
      S(" ");
      D(MD_AppData.MD_DwellTables[md_k].AddrCount);
      S(" ");
      D(MD_AppData.MD_DwellTables[md_k].DataSize);
      S(" ");
      D(MD_AppData.MD_DwellTables[md_k].Rate);
      S("\n");
    }
    // and the neighbour: table 3 was never touched and must still be zero
    S("md_dwell_neigh ");
    D(MD_AppData.MD_DwellTables[3].AddrCount + MD_AppData.MD_DwellTables[3].DataSize +
      MD_AppData.MD_DwellTables[3].Rate);
    S("\n");
    // --- md_dwell_tbl.c -- WHERE MD MEETS TABLE SERVICES ----------------------------
    // The validation callback the ground's table load is checked by, the three functions under
    // it, and the copy into working state. (The three CFE_TBL_GetAddress editors come in the
    // next block.)
    //
    // ADDRESS VALIDITY HERE IS THE PSP STUB, NOT THE DWELL WINDOW. MD_ValidAddrRange calls
    // CFE_PSP_MemValidateRange, whose return code this driver owns, so "out of range" is set
    // rather than arranged -- the only way to reach MD_INVALID_ADDR_ERROR without also
    // changing the address NASA's event text prints.
    md_sim_fill();
    // EVERY CALL BELOW IS HOISTED INTO md_st FIRST, and that is not style. All five of these
    // functions EMIT EVS EVENTS; the C half's printf evaluates its arguments before printing
    // any of the format string while this half prints incrementally with S()/D(), so an inline
    // call puts the event text on opposite sides of its own status line and the two transcripts
    // differ in ORDER while agreeing in content. Measured as a 26-line diff.
    // (a) the NULL table. First branch, and the only one that returns early.
    md_st = MD_TableValidationFunc(NULL);
    S("mdt_null ");
    D(md_st);
    S("\n");
    // (b) an invalid Enabled flag. The flag is checked FIRST in the chain, so this holds even
    // with a bad signature underneath it -- which is what the second line asserts, and it is
    // the kind of ordering a reordered translation would lose.
    MemSet(&md_load, 0, sizeof(MD_DwellTableLoad_t));
    md_load.Enabled = 7;
    md_st = MD_TableValidationFunc(&md_load);
    S("mdt_enaflag ");
    D(md_st);
    S("\n");
    MemSet(md_load.Signature, 'x', MD_INTERFACE_SIGNATURE_FIELD_LENGTH); // no NUL anywhere
    md_st = MD_TableValidationFunc(&md_load);
    S("mdt_ena_beats_sig ");
    D(md_st);
    S("\n");
    // (c) a signature with no terminator in 32 bytes, with a VALID enable flag
    md_load.Enabled = MD_Dwell_States_DISABLED;
    md_st = MD_TableValidationFunc(&md_load);
    S("mdt_siglen ");
    D(md_st);
    S("\n");
    // (d) a valid table: three entries of 2 bytes in the simulated window, delays 1.
    // MD_ReadDwellTable's three outputs are asserted separately from the validation, because
    // NASA DISCARDS its return value at the call site -- the only thing that proves it ran is
    // the numbers it wrote.
    MemSet(&md_load, 0, sizeof(MD_DwellTableLoad_t));
    StrCpy(md_load.Signature, "SIG1");
    md_load.Enabled = MD_Dwell_States_ENABLED;
    for (md_i = 0; md_i < 3; md_i++) {
      md_load.Entry[md_i].Length = 2;
      md_load.Entry[md_i].Delay = 1;
      md_load.Entry[md_i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x20 + 2 * md_i;
    }
    md_ac = 0xFFFF;
    md_sz = 0xFFFF;
    md_rate = 0xFFFFFFFF;
    md_st = MD_ReadDwellTable(&md_load, &md_ac, &md_sz, &md_rate);
    S("mdt_read st=");
    D(md_st);
    S(" n=");
    D(md_ac);
    S(" size=");
    D(md_sz);
    S(" rate=");
    D(md_rate);
    // THE NEWLINE BELONGS TO THE PREVIOUS LINE, so it goes BEFORE the hoisted call. Written as
    // one S("\nmdt_valid ") it was a single call carrying mdt_read's terminator AND this line's
    // prefix, and hoisting the validation above it moved the terminator with it -- the event
    // then landed between `rate=3` and its own newline. A 4-line diff reading
    // `rate=3EVS Port1 ...` followed by a blank. Splitting the two is the whole fix.
    S("\n");
    md_st = MD_TableValidationFunc(&md_load);
    S("mdt_valid ");
    D(md_st);
    S("\n");
    // (e) ENABLED WITH A ZERO TOTAL RATE is the informational case NASA calls out: the load is
    // ACCEPTED and an event says it will never be processed. Status is success, so only the
    // event distinguishes it -- and md_dwell_pkt's md_zerorate line is the other half.
    for (md_i = 0; md_i < 3; md_i++) {
      md_load.Entry[md_i].Delay = 0;
    }
    md_st = MD_TableValidationFunc(&md_load);
    S("mdt_zerorate ");
    D(md_st);
    S("\n");
    for (md_i = 0; md_i < 3; md_i++) {
      md_load.Entry[md_i].Delay = 1;
    }
    // (f) MD_ValidTableEntry, one line per error class. The ORDER of NASA's checks is the thing
    // worth pinning: resolve, then range, then length, then alignment -- so a length of 3 at a
    // BAD address is INVALID_ADDR and the same length at a good one is INVALID_LEN. A
    // translation that reordered the chain would still return "an error" for both.
    MemSet(&md_e, 0, sizeof(MD_TableLoadEntry_t));
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_len0 ");
    D(md_st);
    S("\n");
    md_e.Length = 2;
    StrCpy(md_e.DwellAddress.SymName, "NO_SUCH_SYMBOL");
    md_sym_rc = OS_ERROR;
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_resolve ");
    D(md_st);
    S("\n");
    md_sym_rc = OS_SUCCESS;
    MemSet(&md_e, 0, sizeof(MD_TableLoadEntry_t));
    md_e.Length = 3;
    md_e.DwellAddress.Offset = MD_SIM_WINDOW_BASE;
    es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_range ");
    D(md_st);
    S("\n");
    es_psp_validate_rc = CFE_PSP_SUCCESS;
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_len3 ");
    D(md_st);
    S("\n");
    md_e.Length = 4;
    md_e.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 2; // 4-aligned? no
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_align4 ");
    D(md_st);
    S("\n");
    md_e.Length = 2;
    md_e.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 1; // 2-aligned? no
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_align2 ");
    D(md_st);
    S("\n");
    md_e.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 2;
    md_st = MD_ValidTableEntry(&md_e);
    S("mdt_entry_ok ");
    D(md_st);
    S("\n");
    // (g) MD_CheckTableEntries KEEPS COUNTING PAST THE FIRST ERROR, which is NASA's own comment
    // and the reason the informational event carries three totals. Entry 1 is given an
    // unresolvable symbol, so good=1 bad=1 and the walk still runs to the terminator at entry
    // 3. ErrorEntryArg must be the FIRST bad index, not the last.
    MemSet(&md_load, 0, sizeof(MD_DwellTableLoad_t));
    for (md_i = 0; md_i < 3; md_i++) {
      md_load.Entry[md_i].Length = 2;
      md_load.Entry[md_i].Delay = 1;
      md_load.Entry[md_i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x20 + 2 * md_i;
    }
    StrCpy(md_load.Entry[1].DwellAddress.SymName, "NO_SUCH_SYMBOL");
    StrCpy(md_load.Entry[2].DwellAddress.SymName, "ALSO_MISSING");
    md_sym_rc = OS_ERROR;
    md_bad = 0xFFFF;
    md_st = MD_CheckTableEntries(&md_load, &md_bad);
    S("mdt_check st=");
    D(md_st);
    S(" firstbad=");
    D(md_bad);
    S("\n");
    md_sym_rc = OS_SUCCESS;
    // (h) MD_CopyUpdatedTbl: the load structure into working state, with the addresses
    // RESOLVED. The entry past the terminator is copied too -- NASA's loop runs all 25 rows
    // regardless -- and the derived totals come from MD_UpdateDwellControlInfo at the end of
    // it, so this one line also asserts that call happened.
    MemSet(&md_load, 0, sizeof(MD_DwellTableLoad_t));
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    StrCpy(md_load.Signature, "COPY");
    md_load.Signature[6] = 0x7A; // past the NUL, so strncpy's zero-fill is visible
    md_load.Enabled = MD_Dwell_States_ENABLED;
    for (md_i = 0; md_i < 2; md_i++) {
      md_load.Entry[md_i].Length = 4;
      md_load.Entry[md_i].Delay = 3;
      md_load.Entry[md_i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 4 * md_i;
    }
    md_load.Entry[4].Length = 1; // past the terminator
    md_load.Entry[4].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x40;
    MD_CopyUpdatedTbl(&md_load, 1);
    S("mdt_copy ena=");
    D(MD_AppData.MD_DwellTables[1].Enabled);
    S(" n=");
    D(MD_AppData.MD_DwellTables[1].AddrCount);
    S(" size=");
    D(MD_AppData.MD_DwellTables[1].DataSize);
    S(" rate=");
    D(MD_AppData.MD_DwellTables[1].Rate);
    S(" a0=");
    D(MD_AppData.MD_DwellTables[1].Entry[0].ResolvedAddress);
    S(" a1=");
    D(MD_AppData.MD_DwellTables[1].Entry[1].ResolvedAddress);
    S(" a4=");
    D(MD_AppData.MD_DwellTables[1].Entry[4].ResolvedAddress);
    S(" sig=");
    for (md_i = 0; md_i < 8; md_i++) {
      H2(MD_AppData.MD_DwellTables[1].Signature[md_i]);
    }
    // and table 0 is untouched, which is what says TblIndex was honoured
    S(" neigh=");
    D(MD_AppData.MD_DwellTables[0].AddrCount + MD_AppData.MD_DwellTables[0].Rate);
    S("\n");

    // --- md_dwell_tbl.c, the three CFE_TBL_GetAddress editors -----------------------
    // These are what make MD an APP rather than a library: each asks Table Services for the
    // ground's buffer, edits it in place, tells tbl the buffer was modified, and releases it.
    // Nothing above this point has used tbl from the OUTSIDE -- every tbl assertion so far was
    // tbl's own code driven from inside its module -- so this is the first time the finished
    // tbl module is a dependency rather than a subject.
    //
    // GIVE BACK THE SLOTS THIS TRANSCRIPT LEAKED. The MemPool table is a FIXED-SIZE RESOURCE
    // SHARED BETWEEN EXERCISES and it is at TEN OF TEN here: CFE_TBL_EarlyInit runs six times
    // above and only one section returns its pool, so the rest are stale handles to one buffer.
    // Without this, EarlyInit fails with "No free MemPool slots available", every handle comes
    // back as CFE_TBL_BAD_TABLE_HANDLE and all six assertions collapse to one error code.
    //
    // DISCRIMINATED BY BASE ADDRESS, NOT BY SIZE: SB's buffer pool is ALSO 524,288 bytes, so a
    // size test would delete it and break the dwell transmit in the next block -- md_sent would
    // read 0 instead of 2. The COUNT is printed, not the addresses, because a cpuaddr cannot be
    // compared across a host process and a QEMU guest.
    md_freed = 0;
    for (md_i = 0; md_i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; md_i++) {
      md_pr = &CFE_ES_Global.MemPoolTable[md_i];
      if (CFE_ES_MemPoolRecordIsUsed(md_pr) &&
          md_pr->BaseAddr == &CFE_TBL_Global.Buf.Partition) {
        if (CFE_ES_PoolDelete(md_pr->PoolID) == CFE_SUCCESS) {
          md_freed++;
        }
      }
    }
    S("mdt_poolgc freed=");
    D(md_freed);
    S("\n");
    // THE SETUP IS THE REAL STARTUP SEQUENCE, the same one the tbl section uses. The
    // registration status is PRINTED rather than assumed: a handle of -1 is
    // CFE_TBL_BAD_TABLE_HANDLE, i.e. nothing registered at all.
    //
    // ONE DELIBERATE DIFFERENCE FROM md_app.c: NASA registers with OPT_DEFAULT | OPT_CRITICAL,
    // a table backed by the Critical Data Store. This registers plain OPT_DEFAULT, because the
    // three functions under test only take a handle and call GetAddress, and standing up the
    // CDS belongs to md_app.c's own exercise where CRITICAL is the thing being translated.
    es_set_ctx(1);
    CFE_TBL_EarlyInit();
    CFE_TBL_InitData();
    CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
    MemSet(MD_AppData.MD_TableHandle, 0, 2 * MD_INTERFACE_NUM_DWELL_TABLES);
    md_st = CFE_TBL_Register(&MD_AppData.MD_TableHandle[0], "DWELL_TABLE1",
                             sizeof(MD_DwellTableLoad_t), CFE_TBL_OPT_DEFAULT,
                             &MD_TableValidationFunc);
    S("mdt_reg st=");
    D(md_st);
    S(" h=");
    D(MD_AppData.MD_TableHandle[0]);
    S("\n");
    // AND THE TABLE HAS TO BE LOADED BEFORE IT CAN BE EDITED. A freshly registered table has no
    // data, so CFE_TBL_GetAddress answers CFE_TBL_ERR_NEVER_LOADED (0xCC000005) and all three
    // editors take their error arm -- correct cFE behaviour, and the first thing this block
    // measured. The ground loads and then edits, so the exercise does too.
    MemSet(&md_load, 0, sizeof(MD_DwellTableLoad_t));
    StrCpy(md_load.Signature, "LOADED");
    md_load.Enabled = MD_Dwell_States_DISABLED;
    for (md_i = 0; md_i < 3; md_i++) {
      md_load.Entry[md_i].Length = 2;
      md_load.Entry[md_i].Delay = 1;
      md_load.Entry[md_i].DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x20 + 2 * md_i;
    }
    md_st = CFE_TBL_Load(MD_AppData.MD_TableHandle[0], CFE_TBL_SRC_ADDRESS, &md_load);
    S("mdt_load ");
    D(md_st);
    S("\n");
    // THE REGISTRY RECORD, BY NAME. CFE_TBL_Modified's only comparable effect is
    // RegRecPtr->Status.IsModified -- TimeOfLastUpdate is a time -- and without reading it the
    // Modified call in all three editors is UNEXERCISED. Measured: deleting it from
    // MD_UpdateTableEnabledField left the transcript BYTE-IDENTICAL, because the readback reads
    // the same buffer the editor wrote and does not care whether tbl was told.
    //
    // By NAME, not by index: CFE_TBL_FindTableInRegistry returns a RESOURCE ID (it came back as
    // 0x1c0001, which indexes nothing), and the tbl section records hard-coded registry indices
    // as a mistake it already made seven times.
    md_rr = CFE_TBL_LocateRegRecByName("CFE_EVS.DWELL_TABLE1");
    S("mdt_regrec found=");
    D(md_rr != NULL);
    S(" name=");
    if (md_rr != NULL)
      S(CFE_TBL_RegRecGetName(md_rr));
    else
      S("?");
    S("\n");
    // (i) the ENABLED field. Written through the handle, then read back through a SECOND
    // GetAddress -- not from the pointer the editor used, which it released. IsModified is
    // CLEARED first, so reading it back asserts THIS call and not whatever ran before.
    if (md_rr != NULL)
      md_rr->Status.IsModified = FALSE;
    md_st = MD_UpdateTableEnabledField(0, MD_Dwell_States_ENABLED);
    md_rb = NULL;
    md_get = CFE_TBL_GetAddress(&md_rb, MD_AppData.MD_TableHandle[0]);
    S("mdt_upd_ena st=");
    D(md_st);
    S(" get=");
    D(md_get);
    S(" ena=");
    if (md_rb != NULL)
      D(md_rb->Enabled);
    else
      D(65535);
    S(" mod=");
    if (md_rr != NULL)
      D(md_rr->Status.IsModified);
    else
      D(-1);
    S("\n");
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
    // (j) one dwell entry. NASA takes MD_SymAddr_t BY VALUE and this half takes a POINTER --
    // docs/HOLYC_STRUCT_LIMITS.md #26, 72 bytes against an 8-byte limit. THE READBACK IS WHAT
    // MAKES THAT DEVIATION SAFE TO ASSERT: the whole 72 bytes have to arrive, and the symbol
    // name lives at offset 8 and beyond -- precisely what a by-value call here would lose.
    MemSet(&md_na, 0, sizeof(MD_SymAddr_t));
    md_na.Offset = MD_SIM_WINDOW_BASE + 0x30;
    StrCpy(md_na.SymName, "SYM_IN_ENTRY");
    if (md_rr != NULL)
      md_rr->Status.IsModified = FALSE;
    md_st = MD_UpdateTableDwellEntry(0, 2, 4, 9, &md_na);
    md_rb = NULL;
    md_get = CFE_TBL_GetAddress(&md_rb, MD_AppData.MD_TableHandle[0]);
    S("mdt_upd_dwell mod=");
    if (md_rr != NULL)
      D(md_rr->Status.IsModified);
    else
      D(-1);
    S(" st=");
    D(md_st);
    S(" get=");
    D(md_get);
    S(" len=");
    D(md_rb->Entry[2].Length);
    S(" dly=");
    D(md_rb->Entry[2].Delay);
    S(" off=");
    D(md_rb->Entry[2].DwellAddress.Offset);
    S(" sym=");
    S(md_rb->Entry[2].DwellAddress.SymName);
    S("\n");
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
    // (k) the signature, and the bytes PAST its terminator, for the same reason as
    // md_dwell_pkt's: strncpy zero-fills and a MemCpy would not. The buffer is poisoned first
    // so the zero-fill is observable -- the measured lesson from that block.
    md_rb = NULL;
    CFE_TBL_GetAddress(&md_rb, MD_AppData.MD_TableHandle[0]);
    if (md_rb != NULL)
      MemSet(md_rb->Signature, 0x5A, MD_INTERFACE_SIGNATURE_FIELD_LENGTH);
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
    if (md_rr != NULL)
      md_rr->Status.IsModified = FALSE;
    md_st = MD_UpdateTableSignature(0, "NEWSIG");
    md_rb = NULL;
    md_get = CFE_TBL_GetAddress(&md_rb, MD_AppData.MD_TableHandle[0]);
    S("mdt_upd_sig mod=");
    if (md_rr != NULL)
      D(md_rr->Status.IsModified);
    else
      D(-1);
    S(" st=");
    D(md_st);
    S(" get=");
    D(md_get);
    S(" sig=");
    for (md_i = 0; md_i < 10; md_i++) {
      H2(md_rb->Signature[md_i]);
    }
    S(" last=");
    D(md_rb->Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1]);
    S("\n");
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
    // (l) AND ALL THREE ON A BAD HANDLE, which is the error arm each of them has. -1 is
    // CFE_TBL_BAD_TABLE_HANDLE; GetAddress refuses it and each editor raises its OWN event id
    // and returns what GetAddress returned -- NOT CFE_SUCCESS, which the success arm sets
    // explicitly. Three different event ids for one shape of failure.
    MD_AppData.MD_TableHandle[3] = -1;
    md_st = MD_UpdateTableEnabledField(3, MD_Dwell_States_ENABLED);
    S("mdt_bad_ena ");
    D(md_st);
    S("\n");
    MemSet(&md_na, 0, sizeof(MD_SymAddr_t));
    md_st = MD_UpdateTableDwellEntry(3, 0, 1, 1, &md_na);
    S("mdt_bad_dwell ");
    D(md_st);
    S("\n");
    md_st = MD_UpdateTableSignature(3, "X");
    S("mdt_bad_sig ");
    D(md_st);
    S("\n");

    // --- md_cmds.c -- the six ground commands ---------------------------------------
    // THE TABLE FROM THE BLOCK ABOVE IS REUSED RATHER THAN RE-REGISTERED. Nothing between here
    // and there memsets CFE_TBL_Global, so MD_AppData.MD_TableHandle[0] is still a registered
    // and loaded CFE_EVS.DWELL_TABLE1 -- and re-running CFE_TBL_EarlyInit would take another
    // MemPool slot from a table that was at 10/10 before this transcript reclaimed two. The
    // occupancy is printed once as a TRIPWIRE.
    //
    // HANDLES 1..3 ARE DELIBERATELY NOT REGISTERED, which is what makes the partial failure
    // reachable: a mask of 0x0003 succeeds for table 1 and fails for table 2.
    //
    // EVERY CALL IS HOISTED. All six handlers emit EVS events.
    md_used = 0;
    for (md_i = 0; md_i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; md_i++) {
      if (CFE_ES_MemPoolRecordIsUsed(&CFE_ES_Global.MemPoolTable[md_i]))
        md_used++;
    }
    S("mdc_pools ");
    D(md_used);
    S("/");
    D(CFE_PLATFORM_ES_MAX_MEMORY_POOLS);
    S("\n");
    MemSet(&md_np, 0, sizeof(MD_NoopCmd_t));
    MemSet(&md_rc, 0, sizeof(MD_ResetCountersCmd_t));
    MemSet(&md_sd, 0, sizeof(MD_StartDwellCmd_t));
    MemSet(&md_pd, 0, sizeof(MD_StopDwellCmd_t));
    MemSet(&md_jd, 0, sizeof(MD_JamDwellCmd_t));
    MemSet(&md_sg, 0, sizeof(MD_SetSignatureCmd_t));
    MD_AppData.CommandCounter = 0;
    MD_AppData.CommandErrorCounter = 0;
    // (a) Noop and ResetCounters. The Noop event carries the VERSION, which is the only place
    // those four constants reach the transcript.
    md_st = MD_NoopCmd(&md_np);
    S("mdc_noop st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    MD_AppData.CommandErrorCounter = 9;
    md_st = MD_ResetCountersCmd(&md_rc);
    S("mdc_reset st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (b) START on the registered table alone: the nominal arm. Countdown of 1 is what makes
    // the next wakeup issue a packet, so all four control fields are asserted.
    md_sd.Payload.TableMask = 0x0001;
    md_st = MD_StartDwellCmd(&md_sd);
    S("mdc_start1 st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S(" ena=");
    D(MD_AppData.MD_DwellTables[0].Enabled);
    S(" cd=");
    D(MD_AppData.MD_DwellTables[0].Countdown);
    S(" cur=");
    D(MD_AppData.MD_DwellTables[0].CurrentEntry);
    S(" off=");
    D(MD_AppData.MD_DwellTables[0].PktOffset);
    S("\n");
    // (c) START on tables 1 AND 2: table 2 has no registered table, so the editor fails for it
    // and succeeds for table 1 -- "failed for 1 of 2 tables". The CONTROL STRUCTURE is still
    // updated for both, because NASA writes it before calling the editor; only the Table
    // Services copy is missed. That asymmetry is the point.
    md_sd.Payload.TableMask = 0x0003;
    md_st = MD_StartDwellCmd(&md_sd);
    S("mdc_start12 st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S(" ena2=");
    D(MD_AppData.MD_DwellTables[1].Enabled);
    S("\n");
    // (d) an EMPTY mask: no table in it at all
    md_sd.Payload.TableMask = 0x0000;
    md_st = MD_StartDwellCmd(&md_sd);
    S("mdc_startnone st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (e) STOP, both arms. Note Countdown goes to ZERO here where Start set it to 1.
    md_pd.Payload.TableMask = 0x0001;
    md_st = MD_StopDwellCmd(&md_pd);
    S("mdc_stop1 st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" ena=");
    D(MD_AppData.MD_DwellTables[0].Enabled);
    S(" cd=");
    D(MD_AppData.MD_DwellTables[0].Countdown);
    S("\n");
    md_pd.Payload.TableMask = 0x0000;
    md_st = MD_StopDwellCmd(&md_pd);
    S("mdc_stopnone st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (f) JAM argument checks, which are index bounds and so are checked FIRST.
    //
    // EACH LINE CARRIES THE ERROR COUNTER, AND IT HAS TO. MD_JamDwellCmd sets Status to
    // CFE_SUCCESS at the top and an argument rejection only clears AllInputsValid, so EVERY
    // line below returns st=0 -- exactly what a function that did nothing would return. The
    // counter is the signal; the status is not.
    md_jd.Payload.TableId = 0;
    md_jd.Payload.EntryId = 1;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_tbl0 st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_jd.Payload.TableId = MD_INTERFACE_NUM_DWELL_TABLES + 1;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_tblhi st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_jd.Payload.TableId = 1;
    md_jd.Payload.EntryId = 0;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_ent0 st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_jd.Payload.EntryId = MD_INTERFACE_DWELL_TABLE_SIZE + 1;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_enthi st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (g) A VALID JAM, then the derived totals.
    for (md_i = 0; md_i < 3; md_i++) {
      MD_AppData.MD_DwellTables[0].Entry[md_i].Length = 2;
      MD_AppData.MD_DwellTables[0].Entry[md_i].Delay = 2;
      MD_AppData.MD_DwellTables[0].Entry[md_i].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x20;
    }
    MD_UpdateDwellControlInfo(0);
    S("mdc_before n=");
    D(MD_AppData.MD_DwellTables[0].AddrCount);
    S(" size=");
    D(MD_AppData.MD_DwellTables[0].DataSize);
    S(" rate=");
    D(MD_AppData.MD_DwellTables[0].Rate);
    S("\n");
    md_jd.Payload.TableId = 1;
    md_jd.Payload.EntryId = 3;
    md_jd.Payload.FieldLength = 4;
    md_jd.Payload.DwellDelay = 7;
    md_jd.Payload.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x40; // 4-aligned
    md_jd.Payload.DwellAddress.SymName[0] = '\0';
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_ok st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" len=");
    D(MD_AppData.MD_DwellTables[0].Entry[2].Length);
    S(" dly=");
    D(MD_AppData.MD_DwellTables[0].Entry[2].Delay);
    S(" addr=");
    D(MD_AppData.MD_DwellTables[0].Entry[2].ResolvedAddress);
    S(" n=");
    D(MD_AppData.MD_DwellTables[0].AddrCount);
    S(" size=");
    D(MD_AppData.MD_DwellTables[0].DataSize);
    S(" rate=");
    D(MD_AppData.MD_DwellTables[0].Rate);
    S("\n");
    // and the Table Services copy got it too -- read back through the handle, as a STRING,
    // because the null-jam path hands MD_UpdateTableDwellEntry a partially initialised 72-byte
    // struct and the bytes past the NUL are stack garbage
    md_rb = NULL;
    md_get = CFE_TBL_GetAddress(&md_rb, MD_AppData.MD_TableHandle[0]);
    S("mdc_jam_tbl get=");
    D(md_get);
    S(" len=");
    D(md_rb->Entry[2].Length);
    S(" dly=");
    D(md_rb->Entry[2].Delay);
    S(" off=");
    D(md_rb->Entry[2].DwellAddress.Offset);
    S("\n");
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);
    // (h) A NULL JAM, AND THE SILENT CONSEQUENCE. MD_ValidFieldLength ACCEPTS 0, so a Jam with
    // FieldLength 0 is the "null out this entry" command -- the status is success either way.
    // Nulling entry 2 TERMINATES the table there, and MD_UpdateDwellControlInfo stops at the
    // first zero Length, so AddrCount, DataSize and Rate all drop even though two live entries
    // still follow it. Only the derived totals show that.
    md_jd.Payload.EntryId = 2;
    md_jd.Payload.FieldLength = 0;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_null st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" n=");
    D(MD_AppData.MD_DwellTables[0].AddrCount);
    S(" size=");
    D(MD_AppData.MD_DwellTables[0].DataSize);
    S(" rate=");
    D(MD_AppData.MD_DwellTables[0].Rate);
    // e2dly AND e2addr ARE NOT DECORATION. The null path zeroes Length, Delay and
    // ResolvedAddress, and the three derived totals can only see the Length: once an entry is
    // terminated, MD_UpdateDwellControlInfo stops there and NEVER READS its Delay. Measured --
    // deleting `DwellEntryPtr->Delay = 0;` left the transcript byte-identical.
    S(" e2len=");
    D(MD_AppData.MD_DwellTables[0].Entry[1].Length);
    S(" e2dly=");
    D(MD_AppData.MD_DwellTables[0].Entry[1].Delay);
    S(" e2addr=");
    D(MD_AppData.MD_DwellTables[0].Entry[1].ResolvedAddress);
    S(" e3len=");
    D(MD_AppData.MD_DwellTables[0].Entry[2].Length);
    S("\n");
    // (i) the JAM rejection paths, one per event. The address ones are why the dwell window is
    // a literal: NASA prints "address 0x%08X" from the resolved cpuaddr.
    md_jd.Payload.EntryId = 4;
    md_jd.Payload.FieldLength = 2;
    StrCpy(md_jd.Payload.DwellAddress.SymName, "NO_SUCH_SYMBOL");
    md_sym_rc = OS_ERROR;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_resolve st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_sym_rc = OS_SUCCESS;
    md_jd.Payload.DwellAddress.SymName[0] = '\0';
    md_jd.Payload.FieldLength = 3;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_len3 st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_jd.Payload.FieldLength = 2;
    es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_range st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    es_psp_validate_rc = CFE_PSP_SUCCESS;
    md_jd.Payload.FieldLength = 4;
    md_jd.Payload.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x42; // not 4-aligned
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_al4 st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_jd.Payload.FieldLength = 2;
    md_jd.Payload.DwellAddress.Offset = MD_SIM_WINDOW_BASE + 0x41; // not 2-aligned
    md_st = MD_JamDwellCmd(&md_jd);
    S("mdc_jam_al2 ");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (j) SET SIGNATURE: the length check comes FIRST, before the table id, so an unterminated
    // signature is rejected even with a bad table id underneath it.
    MemSet(md_sg.Payload.Signature, 'z', MD_INTERFACE_SIGNATURE_FIELD_LENGTH); // no NUL
    md_sg.Payload.TableId = 99;
    md_st = MD_SetSignatureCmd(&md_sg);
    S("mdc_sig_len st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    MemSet(md_sg.Payload.Signature, 0, MD_INTERFACE_SIGNATURE_FIELD_LENGTH);
    StrCpy(md_sg.Payload.Signature, "CMDSIG");
    md_sg.Payload.TableId = 99;
    md_st = MD_SetSignatureCmd(&md_sg);
    S("mdc_sig_tbl st=");
    D(md_st);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_sg.Payload.TableId = 1;
    md_st = MD_SetSignatureCmd(&md_sg);
    S("mdc_sig_ok st=");
    D(md_st);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" sig=");
    S(MD_AppData.MD_DwellTables[0].Signature);
    S("\n");
    // and the Table Services copy, which MD_UpdateTableSignature wrote
    md_rb = NULL;
    md_get = CFE_TBL_GetAddress(&md_rb, MD_AppData.MD_TableHandle[0]);
    S("mdc_sig_tblcopy get=");
    D(md_get);
    S(" sig=");
    S(md_rb->Signature);
    S("\n");
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[0]);

    // --- md_dwell_pkt.c -------------------------------------------------------------
    // The part of MD that actually reads memory. Four functions: the loop, the one read, the
    // send, and a three-line reset.
    //
    // THE DWELL BYTES ARE READ BACK WITH THEIR NEIGHBOURS. MD_GetDwellData's write is a 1-, 2-
    // or 4-byte store at a VARIABLE OFFSET, which is the exact shape of the two codegen bugs
    // in docs -- an 8-byte store emitted for a narrow one, and a wild store for a deep
    // variable index. Data[] is poisoned with 0xEE before each write and the bytes on BOTH
    // SIDES of the written region are printed, so a store that is too wide shows up as a
    // missing 0xEE rather than as a value that happens to look right.
    md_T = &MD_AppData.MD_DwellTables[0];
    md_P = &MD_AppData.MD_DwellPkt[0];
    md_widths[0] = 1;
    md_widths[1] = 2;
    md_widths[2] = 4;
    md_badw[0] = 1;
    md_badw[1] = 2;
    md_badw[2] = 4;
    md_badw[3] = 3;
    md_sim_fill();
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    MemSet(MD_AppData.MD_DwellPkt, 0, sizeof(MD_DwellPkt_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    // INITIALISE THE PACKET HEADER, because without it MD_SendDwellPkt's transmit is REJECTED
    // and the send path is not exercised at all. The first version of this block MemSet the
    // packet and never called CFE_MSG_Init, so every CFE_SB_TransmitMsg produced
    // `Send Err:Invalid MsgId(0x0)in msg` -- identical on both halves, so the transcript was
    // satisfied while the function under test did nothing. This is what md_app.c does.
    CFE_MSG_Init(&md_P->TelemetryHeader.Msg, CFE_SB_ValueToMsgId(MD_DWELL_PKT_MID_BASE),
                 sizeof(MD_DwellPkt_t));
    // (a) one write per width, each into a poisoned packet, neighbours printed
    for (md_n = 0; md_n < 3; md_n++) {
      MemSet(md_P->Payload.Data, 0xEE, MD_INTERFACE_DWELL_TABLE_SIZE * 4);
      md_T->Entry[0].Length = md_widths[md_n];
      md_T->Entry[0].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x10;
      md_T->PktOffset = 4;
      md_r0 = md_sim_reads;
      md_st = MD_GetDwellData(0, 0);
      S("md_get w=");
      D(md_widths[md_n]);
      S(" st=");
      D(md_st);
      S(" off=");
      D(md_T->PktOffset);
      S(" reads=");
      D(md_sim_reads - md_r0);
      S(" data=");
      for (md_i = 0; md_i < 10; md_i++) {
        H2(md_P->Payload.Data[md_i]);
      }
      S("\n");
    }
    // (b) the four error returns, and the fact that PktOffset advances ANYWAY -- NASA's
    // `TblPtr->PktOffset += NumBytes` sits OUTSIDE the success branch, so a failed read still
    // moves the write cursor. That is behaviour, not a bug, and it is invisible to a test that
    // only looks at the status.
    for (md_n = 0; md_n < 4; md_n++) {
      MemSet(md_P->Payload.Data, 0xEE, MD_INTERFACE_DWELL_TABLE_SIZE * 4);
      md_T->Entry[0].Length = md_badw[md_n];
      // widths 1,2,4 get an address OUTSIDE the window; width 3 is invalid itself
      if (md_badw[md_n] == 3)
        md_T->Entry[0].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x10;
      else
        md_T->Entry[0].ResolvedAddress = 0x900;
      md_T->PktOffset = 4;
      md_st = MD_GetDwellData(0, 0);
      S("md_get_err w=");
      D(md_badw[md_n]);
      S(" st=");
      D(md_st);
      S(" off=");
      D(md_T->PktOffset);
      S(" untouched=");
      D(md_P->Payload.Data[4] == 0xEE);
      S("\n");
    }
    // (c) MD_StartDwellStream, three lines and all three asserted
    md_T->Countdown = 99;
    md_T->CurrentEntry = 7;
    md_T->PktOffset = 33;
    MD_StartDwellStream(0);
    S("md_start ");
    D(md_T->Countdown);
    S(" ");
    D(md_T->CurrentEntry);
    S(" ");
    D(md_T->PktOffset);
    S("\n");
    // (d) THE LOOP. Three entries of two bytes each, one delay apiece, so Rate is 3 and each
    // wakeup collects exactly one entry; the third fills the packet and sends it. Printed
    // after every call, because the interesting part is the STATE MACHINE and not the packet.
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    MemSet(md_P->Payload.Data, 0xEE, MD_INTERFACE_DWELL_TABLE_SIZE * 4);
    for (md_i = 0; md_i < 3; md_i++) {
      md_T->Entry[md_i].Length = 2;
      md_T->Entry[md_i].Delay = 1;
      md_T->Entry[md_i].ResolvedAddress = MD_SIM_WINDOW_BASE + 0x20 + 2 * md_i;
    }
    MD_UpdateDwellControlInfo(0);
    md_T->Enabled = MD_Dwell_States_ENABLED;
    StrCpy(md_T->Signature, "DW0");
    // AND A BYTE AFTER THE TERMINATOR, because without it this test asserts nothing. Measured:
    // replacing NASA's strncpy with a plain MemCpy of the same length left the transcript
    // BYTE-IDENTICAL, because the source field had been MemSet to zero and a verbatim copy of
    // zeros is indistinguishable from a zero-fill. The control PASSED, which means the setup --
    // not the code -- was doing the work. With 0x7A sitting past the NUL, StrNCpy still
    // zero-fills the destination and a MemCpy carries the 0x7A across.
    md_T->Signature[5] = 0x7A;
    MD_StartDwellStream(0);
    // AND A WITNESS THAT THE PACKET WAS REALLY TRANSMITTED. MD_SendDwellPkt returns U0, so
    // nothing it does is observable from its own result; SB's NoSubscribersCounter is
    // incremented by CFE_SB_TransmitMsg on a VALID MsgId with no subscribers, which is exactly
    // this case -- and a send rejected for a bad MsgId does NOT increment it.
    md_sends0 = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
    for (md_n = 0; md_n < 3; md_n++) {
      md_st = MD_DwellLoop(NULL);
      S("md_loop ");
      D(md_n);
      S(" st=");
      D(md_st);
      S(" cur=");
      D(md_T->CurrentEntry);
      S(" off=");
      D(md_T->PktOffset);
      S(" cd=");
      D(md_T->Countdown);
      S("\n");
    }
    // the packet, read out of MD_AppData rather than off the bus: CFE_SB_TimeStampMsg puts a
    // TIME in the header, which cannot be compared, and the payload is what MD is responsible
    // for. CFE_MSG_PTR(x) is NASA's &x.Msg.
    // MASKED TO EIGHT BITS, because NoSubscribersCounter is a U8 and it stood at 254 when this
    // block was reached -- the unmasked difference printed 4294967042. A witness that wraps is
    // not a witness.
    S("md_sent ");
    D((CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - md_sends0) & 0xFF);
    S("\n");
    CFE_MSG_GetSize(&md_P->TelemetryHeader.Msg, &md_msz);
    S("md_pkt id=");
    D(md_P->Payload.TableId);
    S(" n=");
    D(md_P->Payload.AddrCount);
    S(" rate=");
    D(md_P->Payload.Rate);
    S(" bytes=");
    D(md_P->Payload.ByteCount);
    S(" size=");
    D(md_msz);
    S(" data=");
    for (md_i = 0; md_i < 10; md_i++) {
      H2(md_P->Payload.Data[md_i]);
    }
    // AND THE SIGNATURE PAST ITS TERMINATOR. NASA copies it with strncpy, which ZERO-FILLS the
    // rest of the field; a MemCpy would carry whatever followed the source string instead, and
    // only the bytes AFTER the NUL would show it.
    S(" sig=");
    for (md_i = 0; md_i < 6; md_i++) {
      H2(md_P->Payload.Signature[md_i]);
    }
    S(" last=");
    D(md_P->Payload.Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1]);
    S("\n");
    // (e) A ZERO-RATE TABLE IS NEVER PROCESSED, and that guard is load-bearing rather than
    // defensive: with every Delay zero, MD_DwellLoop's `while (Countdown == 0)` would reload
    // Countdown with a zero delay after sending and spin forever. The Rate > 0 test is the
    // only thing standing between this app and a hang.
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    for (md_i = 0; md_i < 3; md_i++) {
      md_T->Entry[md_i].Length = 1;
      md_T->Entry[md_i].Delay = 0;
      md_T->Entry[md_i].ResolvedAddress = MD_SIM_WINDOW_BASE;
    }
    MD_UpdateDwellControlInfo(0);
    md_T->Enabled = MD_Dwell_States_ENABLED;
    MD_StartDwellStream(0);
    md_r0 = md_sim_reads;
    md_st = MD_DwellLoop(NULL);
    S("md_zerorate st=");
    D(md_st);
    S(" rate=");
    D(md_T->Rate);
    S(" cd=");
    D(md_T->Countdown);
    S(" reads=");
    D(md_sim_reads - md_r0);
    S("\n");
    // (f) THE ALREADY-FULL BRANCH: CurrentEntry >= AddrCount on entry, which NASA reaches when
    // a table is shortened after data was written. It sends immediately and reloads Countdown
    // from the LAST entry's delay.
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    for (md_i = 0; md_i < 3; md_i++) {
      md_T->Entry[md_i].Length = 1;
      md_T->Entry[md_i].Delay = 5 + md_i;
      md_T->Entry[md_i].ResolvedAddress = MD_SIM_WINDOW_BASE;
    }
    MD_UpdateDwellControlInfo(0);
    md_T->Enabled = MD_Dwell_States_ENABLED;
    md_T->CurrentEntry = md_T->AddrCount;
    md_T->Countdown = 42;
    md_r0 = md_sim_reads;
    md_sends0 = CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter;
    md_st = MD_DwellLoop(NULL);
    // THE WITNESS READS 2 PER DWELL PACKET, AND THAT IS THE POINT OF PRINTING IT. The dwell
    // send finds no subscribers, which increments this counter and makes SB raise
    // CFE_SB_SEND_NO_SUBS_EID; EVS then TRANSMITS that event packet over SB
    // (cfe_evs_utils.c:498) on MsgId 0x809, which also has no subscribers, and the counter
    // moves again. Verified rather than assumed: 0x809 accounts for 113 of the 119
    // no-subscriber lines in this transcript. I first predicted 1 here, on the theory that
    // cfe_sb_priv.c's SEND_NO_SUBS REQUEST BIT made the event a per-route one-shot. It is not,
    // and the second witness is what said so.
    S("md_full st=");
    D(md_st);
    S(" cur=");
    D(md_T->CurrentEntry);
    S(" off=");
    D(md_T->PktOffset);
    S(" cd=");
    D(md_T->Countdown);
    S(" reads=");
    D(md_sim_reads - md_r0);
    S(" sent=");
    D((CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter - md_sends0) & 0xFF);
    S("\n");
    // --- md_app.c and md_dispatch.c -- MD's startup, loop and front door ------------
    // The last two sources, and a CYCLE: MD_AppMain calls MD_TaskPipe from the dispatcher and
    // the dispatcher's switch calls MD_SendHkCmd from the app. 775 lines that go in together.
    //
    // THIS BLOCK IS LAST AMONG THE MD BLOCKS ON PURPOSE: it re-runs CFE_TBL_EarlyInit to clear
    // the registry so MD can register its OWN four tables, and the md_cmds block depends on
    // the table the md_dwell_tbl block registered. Placed earlier it pulled that table out
    // from under md_cmds -- a 54-line diff that was entirely self-inflicted.
    //
    // MD_AppMain IS CALLED AFTER THE PIPE IT NEEDS IS TAKEN. Its loop treats CFE_SB_TIME_OUT
    // as "no action", so nothing ends it on a real pipe; an AppInit that FAILS sets APP_ERROR
    // and RunLoop's FIRST test -- on the caller's own RunStatus, before any record lookup --
    // skips the loop. Each init function is exercised on its success path directly and its
    // failure path through AppMain.
    md_freed = 0;
    for (md_i = 0; md_i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; md_i++) {
      md_pr = &CFE_ES_Global.MemPoolTable[md_i];
      if (CFE_ES_MemPoolRecordIsUsed(md_pr) &&
          md_pr->BaseAddr == &CFE_TBL_Global.Buf.Partition) {
        if (CFE_ES_PoolDelete(md_pr->PoolID) == CFE_SUCCESS)
          md_freed++;
      }
    }
    S("mda_poolgc freed=");
    D(md_freed);
    S("\n");
    es_set_ctx(1);
    CFE_TBL_EarlyInit();
    CFE_TBL_InitData();
    CFE_TBL_Global.TableTaskAppId = ES_CTX_APPID(1);
    md_used = 0;
    for (md_i = 0; md_i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; md_i++) {
      if (CFE_ES_MemPoolRecordIsUsed(&CFE_ES_Global.MemPoolTable[md_i]))
        md_used++;
    }
    S("mda_pools ");
    D(md_used);
    S("/");
    D(CFE_PLATFORM_ES_MAX_MEMORY_POOLS);
    S("\n");
    // (a) MD_InitControlStructures: four zeroed blocks with Countdown 1, which is what makes
    // the first wakeup collect rather than wait. The Signature is strncpy'd from "" over the
    // whole field, so a byte DEEP in it must be zero too -- poisoned with 0xCC first.
    MemSet(MD_AppData.MD_DwellTables, 0xCC,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    MD_InitControlStructures();
    S("mda_ctrl cd=");
    D(MD_AppData.MD_DwellTables[0].Countdown);
    S(",");
    D(MD_AppData.MD_DwellTables[1].Countdown);
    S(",");
    D(MD_AppData.MD_DwellTables[2].Countdown);
    S(",");
    D(MD_AppData.MD_DwellTables[3].Countdown);
    S(" ena=");
    D(MD_AppData.MD_DwellTables[0].Enabled);
    S(" sig0=");
    D(MD_AppData.MD_DwellTables[0].Signature[0]);
    S(" sig20=");
    D(MD_AppData.MD_DwellTables[0].Signature[20]);
    S(" n=");
    D(MD_AppData.MD_DwellTables[0].AddrCount);
    S("\n");
    // (b) MD_InitSoftwareBusServices, the success path. The HK packet's MsgId is read back OUT
    // of the header, because CFE_MSG_Init is the only thing that puts it there.
    MD_AppData.CmdPipe = CFE_SB_INVALID_PIPE;
    md_st = MD_InitSoftwareBusServices();
    md_mid = CFE_SB_InvalidMsgId();
    CFE_MSG_GetMsgId(&MD_AppData.HkPkt.TelemetryHeader.Msg, &md_mid);
    S("mda_sbs st=");
    D(md_st);
    S(" pipe=");
    D(CFE_ResourceId_IsDefined(MD_AppData.CmdPipe));
    S(" hkmid=0x");
    Hx4(CFE_SB_MsgIdToValue(md_mid));
    S("\n");
    // (c) MD_InitTableServices, four CRITICAL tables. The file /cf/md_dw01.tbl EXISTS on this
    // driver's RAM disk but is a dump of ANOTHER table left by an earlier section, so
    // CFE_TBL_Load answers CFE_TBL_ERR_FILE_FOR_WRONG_TABLE and NASA's loop stops at the
    // FIRST table -- one handle set, fourth name empty.
    MemSet(MD_AppData.MD_TableHandle, 0, 2 * MD_INTERFACE_NUM_DWELL_TABLES);
    md_st = MD_InitTableServices();
    S("mda_tbl st=");
    D(md_st);
    S(" h=");
    D(MD_AppData.MD_TableHandle[0]);
    S(",");
    D(MD_AppData.MD_TableHandle[1]);
    S(",");
    D(MD_AppData.MD_TableHandle[2]);
    S(",");
    D(MD_AppData.MD_TableHandle[3]);
    S(" names=");
    S(MD_AppData.MD_TableName[0]);
    S(",");
    S(MD_AppData.MD_TableName[3]);
    S("\n");
    // (d) MD_ManageDwellTable with nothing pending: the final else sets the flag. The point is
    // that it TERMINATES -- a translation that missed one of the four branches would HANG.
    S("mda_manage ");
    D(MD_ManageDwellTable(0));
    S("\n");
    // (e) MD_SendHkCmd: the control state projected into the packet. The enable MASK is the
    // field worth checking -- tables 1 and 3 enabled must give 0x0005 and not 0x0003.
    MD_AppData.CommandCounter = 11;
    MD_AppData.CommandErrorCounter = 22;
    MD_AppData.MD_DwellTables[0].Enabled = MD_Dwell_States_ENABLED;
    MD_AppData.MD_DwellTables[2].Enabled = MD_Dwell_States_ENABLED;
    MD_AppData.MD_DwellTables[0].AddrCount = 3;
    MD_AppData.MD_DwellTables[0].Rate = 9;
    MD_AppData.MD_DwellTables[0].DataSize = 6;
    MD_AppData.MD_DwellTables[0].PktOffset = 4;
    MD_AppData.MD_DwellTables[0].CurrentEntry = 2;
    MD_AppData.MD_DwellTables[0].Countdown = 5;
    MemSet(&md_hk, 0, sizeof(MD_SendHkCmd_t));
    md_st = MD_SendHkCmd(&md_hk);
    md_hp = &MD_AppData.HkPkt;
    S("mda_hk st=");
    D(md_st);
    S(" valid=");
    D(md_hp->Payload.ValidCmdCntr);
    S(" invalid=");
    D(md_hp->Payload.InvalidCmdCntr);
    S(" mask=0x");
    Hx4(md_hp->Payload.DwellEnabledMask);
    S(" n0=");
    D(md_hp->Payload.DwellTblAddrCount[0]);
    S(" rate0=");
    D(md_hp->Payload.NumWaitsPerPkt[0]);
    S(" off0=");
    D(md_hp->Payload.DwellPktOffset[0]);
    S(" bytes0=");
    D(md_hp->Payload.ByteCount[0]);
    S(" ent0=");
    D(md_hp->Payload.DwellTblEntry[0]);
    S(" cd0=");
    D(md_hp->Payload.Countdown[0]);
    S("\n");
    // (f) MD_AppMain. THE APP MUST BE A **CORE** APP FOR ExitApp TO RETURN: CFE_ES_ExitApp
    // calls OS_TaskExit for a CORE app and otherwise WAITS IN OS_TaskDelay to be deleted by
    // ES, which never happens in a single-process driver. A `sample` of the live process is
    // what named OS_TaskDelay after two wrong guesses.
    //
    // exits=0 IS NOT THE WITNESS: for a CORE app with APP_ERROR rather than one of the
    // CORE_APP_*_ERROR statuses, ExitApp REFUSES and logs `Cannot Exit CORE Application`, and
    // that syslog line is what proves it was reached. A zero count is also what "never
    // called" looks like.
    CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
    md_x0 = es_taskexits;
    MD_AppMain();
    CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
    S("mda_appmain exits=");
    D(es_taskexits - md_x0);
    S(" run=");
    D(MD_AppData.RunStatus);
    S(" cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // --- md_dispatch.c: the length check, the switch, and the pipe router ---------
    // THE COUNTERS ARE THE WITNESS, not the return values: MD_ProcessGroundCommand and
    // MD_TaskPipe both return U0, and MD_VerifyCmdLength's Bool says only whether the length
    // matched. What proves a command was ROUTED is which counter moved.
    md_ccs[0] = MD_NOOP_CC;
    md_szs[0] = sizeof(MD_NoopCmd_t);
    md_ccs[1] = MD_RESET_CNTRS_CC;
    md_szs[1] = sizeof(MD_ResetCountersCmd_t);
    md_ccs[2] = MD_START_DWELL_CC;
    md_szs[2] = sizeof(MD_StartDwellCmd_t);
    md_ccs[3] = MD_STOP_DWELL_CC;
    md_szs[3] = sizeof(MD_StopDwellCmd_t);
    md_ccs[4] = MD_JAM_DWELL_CC;
    md_szs[4] = sizeof(MD_JamDwellCmd_t);
    md_ccs[5] = MD_SET_SIGNATURE_CC;
    md_szs[5] = sizeof(MD_SetSignatureCmd_t);
    // (g) MD_VerifyCmdLength both ways. The mismatch arm raises an event AND increments the
    // error counter, so the counter is what separates them.
    MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
    CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(MD_CMD_MID), sizeof(MD_NoopCmd_t));
    MD_AppData.CommandErrorCounter = 0;
    md_i2 = MD_VerifyCmdLength(&md_dcmd.Header.Msg, sizeof(MD_NoopCmd_t));
    S("mdd_len ok=");
    D(md_i2);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    md_i2 = MD_VerifyCmdLength(&md_dcmd.Header.Msg, sizeof(MD_NoopCmd_t) + 1);
    S("mdd_len bad=");
    D(md_i2);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (h) every command code through the switch, each with ITS OWN correct length so
    // VerifyCmdLength passes and the handler actually runs. The counters after each dispatch
    // say which arm was taken: a routing error would move the wrong one or neither.
    for (md_i2 = 0; md_i2 < 6; md_i2++) {
      MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
      CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(MD_CMD_MID), md_szs[md_i2]);
      CFE_MSG_SetFcnCode(&md_dcmd.Header.Msg, md_ccs[md_i2]);
      // give Jam and SetSignature arguments that reach their success arm
      md_dcmd.Payload.TableId = 1;
      md_dcmd.Payload.EntryId = 1;
      md_dcmd.Payload.FieldLength = 0;
      MD_AppData.CommandCounter = 0;
      MD_AppData.CommandErrorCounter = 0;
      MD_ProcessGroundCommand(&md_dcmd);
      S("mdd_cc");
      D(md_ccs[md_i2]);
      S(" cc=");
      D(MD_AppData.CommandCounter);
      S(" ec=");
      D(MD_AppData.CommandErrorCounter);
      S("\n");
    }
    // (i) a command code nothing claims: the default arm
    MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
    CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(MD_CMD_MID), sizeof(MD_NoopCmd_t));
    CFE_MSG_SetFcnCode(&md_dcmd.Header.Msg, 99);
    MD_AppData.CommandErrorCounter = 0;
    MD_ProcessGroundCommand(&md_dcmd);
    S("mdd_badcc ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    // (j) THE PIPE ROUTER, all four branches. MD_TaskPipe caches the three message ids in
    // STATIC LOCALS on its first call -- named CMD_MID, SEND_HK_MID and WAKE_UP_MID, the same
    // names cfe_es_dispatch, cfe_evs_dispatch and cfe_ta_dispatch already use. Those three
    // COLLIDED once when a HolyC static local became a global under its bare name
    // (docs/HOLYC_STRUCT_LIMITS.md #12), and MD is the FOURTH user of them in one translation
    // unit. If that scoping regressed, MD's cache would hold a cFE module's id and these four
    // lines would route to the wrong handler. That is the check, not an aside.
    //
    // A WAKEUP runs the dwell loop, so md_sim_reads is its witness. A HK request runs
    // MD_SendHkCmd, so the packet's ValidCmdCntr is its witness. A ground command with NOOP
    // moves CommandCounter. An unknown id moves the error counter and nothing else.
    md_sim_fill();
    MemSet(MD_AppData.MD_DwellTables, 0,
           sizeof(MD_DwellPacketControl_t) * MD_INTERFACE_NUM_DWELL_TABLES);
    MD_AppData.MD_DwellTables[0].Enabled = MD_Dwell_States_ENABLED;
    MD_AppData.MD_DwellTables[0].Entry[0].Length = 2;
    MD_AppData.MD_DwellTables[0].Entry[0].Delay = 1;
    MD_AppData.MD_DwellTables[0].Entry[0].ResolvedAddress = MD_SIM_WINDOW_BASE;
    MD_UpdateDwellControlInfo(0);
    MD_AppData.MD_DwellTables[0].Countdown = 1;
    MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
    CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(MD_WAKEUP_MID), sizeof(MD_Wakeup_t));
    md_x0 = md_sim_reads;
    MD_TaskPipe(&md_dcmd);
    S("mdd_pipe_wakeup reads=");
    D(md_sim_reads - md_x0);
    S("\n");
    MD_AppData.CommandCounter = 77;
    MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
    CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(MD_SEND_HK_MID),
                 sizeof(MD_SendHkCmd_t));
    MD_TaskPipe(&md_dcmd);
    S("mdd_pipe_hk valid=");
    D(MD_AppData.HkPkt.Payload.ValidCmdCntr);
    S("\n");
    MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
    CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(MD_CMD_MID), sizeof(MD_NoopCmd_t));
    CFE_MSG_SetFcnCode(&md_dcmd.Header.Msg, MD_NOOP_CC);
    MD_AppData.CommandCounter = 0;
    MD_AppData.CommandErrorCounter = 0;
    MD_TaskPipe(&md_dcmd);
    S("mdd_pipe_cmd cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");
    MemSet(&md_dcmd, 0, sizeof(MD_JamDwellCmd_t));
    CFE_MSG_Init(&md_dcmd.Header.Msg, CFE_SB_ValueToMsgId(0x1899), sizeof(MD_NoopCmd_t));
    MD_AppData.CommandCounter = 0;
    MD_AppData.CommandErrorCounter = 0;
    MD_TaskPipe(&md_dcmd);
    S("mdd_pipe_badmid cc=");
    D(MD_AppData.CommandCounter);
    S(" ec=");
    D(MD_AppData.CommandErrorCounter);
    S("\n");

    // --- mm_utils.c (MM -- THE SECOND cFS APP) -----------------------------------------
    // Eight functions: the housekeeping reset, the segment break, the two parameter
    // validators, the two alignment checks, the address resolver and the file CRC.
    //
    // THE ADDRESSES ARE LITERAL CONSTANTS, for the reason recorded in docs/CFS_PLAN.md and at
    // the top of Kernel/Cfs/mm/mm_msg.HC: every event below renders the address, and a host
    // pointer and a guest pointer never agree. 0x00100000 is the base of the same simulated
    // window MD uses, and nothing here reads memory through it -- the PSP's range check is this
    // driver's own stub, so the address only has to be a NUMBER.
    //
    // AND THE RENDERING IS "%p", WHICH NO EARLIER GATED SOURCE USED. Six of these events print
    // "Addr = %p"; StrPrintN did not implement the conversion, and an unhandled one does not
    // consume its argument, so every argument after it would have shifted.
    // tools/cfs/check_formats.py is the static gate for that, and these lines are the dynamic
    // one. NO EXERCISE HERE PASSES ADDRESS ZERO THROUGH %p: C leaves the null rendering
    // implementation-defined and the two mainstream libcs disagree about it ("0x0" against
    // "(nil)"), which is a difference between HOSTS and not between halves.
    mmu_A = 0x00100000;
    mmu_perf = &CFE_ES_Global.ResetDataPtr->Perf;

    // --- MM_ResetHk. IT CLEARS WHAT THE LAST COMMAND REPORTED AND NOTHING ELSE, which is two
    // properties and not one: the six payload fields go to their cleared values, and the two
    // COUNTERS are untouched -- this runs at the start of every command, so a reset that
    // cleared the counters would erase MM's whole command history.
    //
    // FileName[1] IS IN THE LINE DELIBERATELY. NASA writes only FileName[0], making it an empty
    // C STRING rather than a cleared buffer, so the 'Y' must survive. A translation that
    // reached for MemSet would pass a test that only read [0].
    MM_AppData.HkTlm.Payload.CommandCounter = 11;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 22;
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_FILL;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM16;
    MM_AppData.HkTlm.Payload.Address = 0x00100040;
    MM_AppData.HkTlm.Payload.DataValue = 0xAABBCCDD;
    MM_AppData.HkTlm.Payload.BytesProcessed = 77;
    MM_AppData.HkTlm.Payload.FileName[0] = 'Z';
    MM_AppData.HkTlm.Payload.FileName[1] = 'Y';
    MM_ResetHk();
    S("mmu_resethk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S(" dv=");
    D(MM_AppData.HkTlm.Payload.DataValue);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" fn0=");
    D(MM_AppData.HkTlm.Payload.FileName[0]);
    S(" fn1=");
    D(MM_AppData.HkTlm.Payload.FileName[1]);
    S(" cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- MM_SegmentBreak. THREE WITNESSES AND NOT ONE DELAY, and the delay is the weakest of
    // them: MM_INTERNAL_PROCESSOR_CYCLE is 0 in this configuration, so summing the MILLISECONDS
    // would be a zero against a zero -- evs_delays counts CALLS for exactly that reason. The
    // two performance-log entries are the real assertion: 31 and 31 with the exit bit set,
    // which pins the marker AND says both stamps ran. Dropping PerfLogExit leaves a transcript
    // that still says "it delayed".
    //
    // THE FILTER MASK IS SET HERE AND NOT LEFT TO StartPerfDataCmd, which does not touch it:
    // only a POWER-ON reset initialises the mask, and the es block earlier in this file both
    // zeroes the whole Perf area and then drives CFE_ES_SetPerfFilterMaskCmd. The first run of
    // this block recorded NOTHING for exactly that reason -- a zero DataCount against a zero,
    // with no event to say why, because StartPerfDataCmd's own acknowledgement is a DEBUG event
    // and this configuration filters those out.
    CFE_ES_Global.BackgroundPerfDumpState.CurrentState = CFE_ES_PerfDumpState_IDLE;
    CFE_ES_Global.BackgroundPerfDumpState.PendingState = CFE_ES_PerfDumpState_IDLE;
    for (mmu_k = 0; mmu_k < CFE_ES_PERF_8BIT_WORDS_IN_MASK; mmu_k++) {
      mmu_perf->MetaData.FilterMask[mmu_k] = 0xFF;
      mmu_perf->MetaData.TriggerMask[mmu_k] = 0x00;
    }
    MemSet(&mmu_spc, 0, sizeof(CFE_ES_StartPerfDataCmd_t));
    mmu_spc.Payload.TriggerMode = CFE_ES_PerfTrigger_START;
    CFE_ES_StartPerfDataCmd(&mmu_spc);
    mmu_before = evs_delays;
    MM_SegmentBreak();
    S("mmu_segbreak n=");
    D(mmu_perf->MetaData.DataCount);
    S(" e0=0x");
    Hx8(mmu_perf->DataBuffer[0].Data);
    S(" e1=0x");
    Hx8(mmu_perf->DataBuffer[1].Data);
    S(" delays=");
    D(evs_delays - mmu_before);
    S("\n");

    // --- the alignment pair. BOTH ARMS MATTER, the same way MD's do: NASA checks the address
    // and then the SIZE, so (A, 6) must be rejected on the size alone.
    S("mmu_a32 ");
    D(MM_Verify32Aligned(mmu_A + 8, 4));
    D(MM_Verify32Aligned(mmu_A + 9, 4));
    D(MM_Verify32Aligned(mmu_A + 8, 6));
    D(MM_Verify32Aligned(mmu_A, 0));
    S("\n");
    S("mmu_a16 ");
    D(MM_Verify16Aligned(mmu_A + 8, 2));
    D(MM_Verify16Aligned(mmu_A + 7, 2));
    D(MM_Verify16Aligned(mmu_A + 8, 3));
    D(MM_Verify16Aligned(mmu_A, 0));
    S("\n");

    // --- MM_VerifyPeekPokeParams, as a grid: three legal widths against the five memory types
    // and one illegal type. THE STATUSES ARE COLLECTED BEFORE THEY ARE PRINTED, because the
    // calls EMIT EVENTS -- a print interleaved with the loop would be cut in half by the first
    // event and the line would not exist.
    //
    // The diagonal is the point: RAM and EEPROM take any legal width, while MEM8, MEM16 and
    // MEM32 take exactly one each. That is a property of the hardware behind the memory type
    // and not of the command, and it is six rejections that a translation dropping the
    // `else if (SizeInBytes != N)` arms would turn into six acceptances.
    mmu_widths[0] = MM_INTERNAL_BYTE_BIT_WIDTH;
    mmu_widths[1] = MM_INTERNAL_WORD_BIT_WIDTH;
    mmu_widths[2] = MM_INTERNAL_DWORD_BIT_WIDTH;
    for (mmu_k = 0; mmu_k < 3; mmu_k++) {
      for (mmu_mt = 0; mmu_mt < 6; mmu_mt++) {
        // 1..5 are the five real memory types; the sixth column is 9, which is not a type at
        // all. Written as an if rather than a ?: so the two halves read line for line.
        mmu_t = mmu_mt + 1;
        if (mmu_mt == 5) {
          mmu_t = 9;
        }
        mmu_sv[mmu_mt] = MM_VerifyPeekPokeParams(mmu_A, mmu_t, mmu_widths[mmu_k]);
      }
      S("mmu_pp w=");
      D(mmu_widths[mmu_k]);
      S(" ram=");
      D(mmu_sv[0]);
      S(" eep=");
      D(mmu_sv[1]);
      S(" m8=");
      D(mmu_sv[2]);
      S(" m16=");
      D(mmu_sv[3]);
      S(" m32=");
      D(mmu_sv[4]);
      S(" bad=");
      D(mmu_sv[5]);
      S("\n");
    }
    // An illegal WIDTH short-circuits before the memory type is looked at, so it is called once
    // rather than six times -- and 0xFFFFFFFF is the interesting value, because the event
    // renders it through NASA's (unsigned int) cast.
    mmu_sv[0] = MM_VerifyPeekPokeParams(mmu_A, MM_MemType_RAM, 7);
    mmu_sv[1] = MM_VerifyPeekPokeParams(mmu_A, MM_MemType_RAM, 0xFFFFFFFF);
    S("mmu_pp_badw ");
    D(mmu_sv[0]);
    S(" ");
    D(mmu_sv[1]);
    S("\n");

    // The misalignment arms, which the grid above cannot reach: it uses an 8-aligned address
    // throughout.
    mmu_sv[0] = MM_VerifyPeekPokeParams(mmu_A + 1, MM_MemType_RAM, MM_INTERNAL_WORD_BIT_WIDTH);
    mmu_sv[1] = MM_VerifyPeekPokeParams(mmu_A + 1, MM_MemType_RAM, MM_INTERNAL_DWORD_BIT_WIDTH);
    mmu_sv[2] = MM_VerifyPeekPokeParams(mmu_A + 2, MM_MemType_RAM, MM_INTERNAL_DWORD_BIT_WIDTH);
    S("mmu_pp_align ");
    D(mmu_sv[0]);
    S(" ");
    D(mmu_sv[1]);
    S(" ");
    D(mmu_sv[2]);
    S("\n");

    // THE CASE OF %p's HEX DIGITS, WHICH NOTHING ABOVE CAN SEE. Every address in this block is
    // 0x001000xx, so its digits are all 0-4 and rendering %p in UPPER case changed the
    // transcript NOT AT ALL -- driven, and the mutation was invisible. 0x00ABCDEF has every
    // letter digit and is odd, so the 16-bit alignment check rejects it and the event prints it.
    mmu_sv[0] = MM_VerifyPeekPokeParams(0x00ABCDEF, MM_MemType_RAM, MM_INTERNAL_WORD_BIT_WIDTH);
    S("mmu_pp_hexcase ");
    D(mmu_sv[0]);
    S("\n");

    // And the PSP refusing the range. The CALL COUNTER is what says the PSP was really asked:
    // both statuses below would be satisfied by a validator that never called it and returned
    // the stub's code from a local variable.
    mmu_before = es_psp_validates;
    es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
    mmu_sv[0] = MM_VerifyPeekPokeParams(mmu_A, MM_MemType_RAM, MM_INTERNAL_BYTE_BIT_WIDTH);
    mmu_sv[1] = MM_VerifyPeekPokeParams(mmu_A, MM_MemType_EEPROM, MM_INTERNAL_BYTE_BIT_WIDTH);
    es_psp_validate_rc = CFE_PSP_SUCCESS;
    S("mmu_pp_psp ");
    D(mmu_sv[0]);
    S(" ");
    D(mmu_sv[1]);
    S(" calls=");
    D(es_psp_validates - mmu_before);
    S("\n");

    // --- MM_VerifyLoadDumpParams, THE GRID. Seven memory types (0 and 6 are not types) against
    // six verification types (5 is not one), at a size of 16 bytes.
    //
    // WHY 16 AND NOT 4. It is above MM_INTERNAL_MAX_DUMP_INEVENT_BYTES, which is 15, and below
    // every other limit -- so DumpInEvent's column REJECTS while the other four accept, and the
    // grid distinguishes five different MaxSize values rather than agreeing on "small enough
    // for all of them". VerifyType 5 is refused before the switch runs and emits NOTHING, which
    // is the one cell with no event.
    for (mmu_mt = 0; mmu_mt < 7; mmu_mt++) {
      for (mmu_vt = 0; mmu_vt < 6; mmu_vt++) {
        mmu_sv[mmu_vt] = MM_VerifyLoadDumpParams(mmu_A, mmu_mt, 16, mmu_vt);
      }
      S("mmu_ldv mt=");
      D(mmu_mt);
      S(" dump=");
      D(mmu_sv[0]);
      S(" load=");
      D(mmu_sv[1]);
      S(" evt=");
      D(mmu_sv[2]);
      S(" fill=");
      D(mmu_sv[3]);
      S(" wid=");
      D(mmu_sv[4]);
      S(" bad=");
      D(mmu_sv[5]);
      S("\n");
    }

    // The size boundaries, one pair per limit the grid above could only prove was "bigger than
    // 16". Each pair is MaxSize and MaxSize+1, so it pins the number.
    mmu_sv[0] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_RAM, 1048576, MM_VERIFY_LOAD);
    mmu_sv[1] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_RAM, 1048577, MM_VERIFY_LOAD);
    mmu_sv[2] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_EEPROM, 131072, MM_VERIFY_LOAD);
    mmu_sv[3] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_EEPROM, 131073, MM_VERIFY_LOAD);
    S("mmu_ldv_lim ram=");
    D(mmu_sv[0]);
    S(",");
    D(mmu_sv[1]);
    S(" eep=");
    D(mmu_sv[2]);
    S(",");
    D(mmu_sv[3]);
    S("\n");
    mmu_sv[0] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_RAM, 15, MM_VERIFY_EVENT);
    mmu_sv[1] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_RAM, 200, MM_VERIFY_WID);
    mmu_sv[2] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_RAM, 201, MM_VERIFY_WID);
    // ZERO IS ITS OWN REJECTION, written as `(SizeInBytes == 0) ||` rather than falling out of
    // the comparison -- an unsigned 0 is not greater than any MaxSize.
    mmu_sv[3] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_RAM, 0, MM_VERIFY_DUMP);
    S("mmu_ldv_edge evt15=");
    D(mmu_sv[0]);
    S(" wid200=");
    D(mmu_sv[1]);
    S(" wid201=");
    D(mmu_sv[2]);
    S(" zero=");
    D(mmu_sv[3]);
    S("\n");

    // The alignment arms, and MEM8's ABSENCE of one. MEM32 and MEM16 check the address and the
    // size; MEM8 has no check at all, because every address is byte aligned -- so the last of
    // these five must be ACCEPTED, and it is the cell that says the three arms were not written
    // as one.
    mmu_sv[0] = MM_VerifyLoadDumpParams(mmu_A + 1, MM_MemType_MEM32, 4, MM_VERIFY_LOAD);
    mmu_sv[1] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_MEM32, 6, MM_VERIFY_LOAD);
    mmu_sv[2] = MM_VerifyLoadDumpParams(mmu_A + 1, MM_MemType_MEM16, 2, MM_VERIFY_LOAD);
    mmu_sv[3] = MM_VerifyLoadDumpParams(mmu_A, MM_MemType_MEM16, 3, MM_VERIFY_LOAD);
    mmu_sv[4] = MM_VerifyLoadDumpParams(mmu_A + 1, MM_MemType_MEM8, 3, MM_VERIFY_LOAD);
    S("mmu_ldv_align m32=");
    D(mmu_sv[0]);
    S(",");
    D(mmu_sv[1]);
    S(" m16=");
    D(mmu_sv[2]);
    S(",");
    D(mmu_sv[3]);
    S(" m8=");
    D(mmu_sv[4]);
    S("\n");

    // --- THE MEMORY TYPE'S NAME, which only the last event in the function prints. Five calls,
    // five strings, and nothing else in MM reads MemTypeStr -- so without these five the four
    // StrPrintN call sites could all write "MEM_RAM", or nothing at all, and every line above
    // would be unchanged.
    es_psp_validate_rc = CFE_PSP_INVALID_MEM_ADDR;
    for (mmu_mt = 1; mmu_mt <= 5; mmu_mt++) {
      mmu_sv[mmu_mt - 1] = MM_VerifyLoadDumpParams(mmu_A, mmu_mt, 4, MM_VERIFY_LOAD);
    }
    es_psp_validate_rc = CFE_PSP_SUCCESS;
    S("mmu_ldv_mtstr ");
    D(mmu_sv[0]);
    S(" ");
    D(mmu_sv[1]);
    S(" ");
    D(mmu_sv[2]);
    S(" ");
    D(mmu_sv[3]);
    S(" ");
    D(mmu_sv[4]);
    S("\n");

    // --- MM_ResolveSymAddr, all three outcomes, as MD's sibling does. The empty-name branch is
    // the one every MM exercise after this one stands on.
    MemSet(&mmu_sa, 0, sizeof(MM_SymAddr_t));
    mmu_sa.Offset = 0x00100040;
    mmu_ra = 0xDEAD;
    S("mmu_resolve_off ");
    D(MM_ResolveSymAddr(&mmu_sa, &mmu_ra));
    S(" ");
    D(mmu_ra);
    S("\n");
    StrCpy(mmu_sa.SymName, "MM_SIM_WINDOW");
    mmu_sa.Offset = 0x20;
    md_sym_rc = OS_SUCCESS;
    md_sym_addr = 0x00100000;
    mmu_ra = 0xDEAD;
    S("mmu_resolve_sym ");
    D(MM_ResolveSymAddr(&mmu_sa, &mmu_ra));
    S(" ");
    D(mmu_ra);
    S("\n");
    // A LOOKUP FAILURE LEAVES THE CALLER'S VARIABLE ALONE, which is a property of the branch and
    // not of the return value.
    md_sym_rc = OS_ERROR;
    mmu_ra = 0xDEAD;
    S("mmu_resolve_fail ");
    D(MM_ResolveSymAddr(&mmu_sa, &mmu_ra));
    S(" ");
    D(mmu_ra);
    S("\n");
    md_sym_rc = OS_SUCCESS;
    // THE NUL AT THE VERY END IS WRITTEN UNCONDITIONALLY, before anything looks at the name, and
    // that is a safety measure on a 64-byte array the ground filled. Filling all 64 bytes with
    // 'A' makes the last byte the only thing that can stop OS_strnlen at 63 -- and because the
    // name is then NOT empty, the lookup runs, which is how we know the truncation happened
    // rather than the array being read as empty.
    MemSet(mmu_sa.SymName, 'A', CFE_MISSION_MAX_PATH_LEN);
    mmu_sa.Offset = 0x10;
    mmu_ra = 0xDEAD;
    mmu_sv[0] = MM_ResolveSymAddr(&mmu_sa, &mmu_ra);
    S("mmu_resolve_nul ");
    D(mmu_sv[0]);
    S(" ");
    D(mmu_ra);
    S(" len=");
    D(OS_strnlen(mmu_sa.SymName, CFE_MISSION_MAX_PATH_LEN));
    S(" last=");
    D(mmu_sa.SymName[CFE_MISSION_MAX_PATH_LEN - 1]);
    S("\n");

    // --- MM_ComputeCRCFromFile. 450 BYTES, WHICH IS THREE READS of the 200-byte buffer: 200,
    // 200 and 50. One read would not prove the loop folds the previous CRC in, and a file that
    // divided evenly would not prove the SHORT last read is handled -- CFE_ES_CalculateCRC is
    // called with ByteCntr, not with the buffer size.
    for (mmu_k = 0; mmu_k < 450; mmu_k++) {
      fs_data[mmu_k] = (mmu_k * 7 + 3) & 0xFF;
    }
    fs_len = 450;
    fs_noexist = 0;
    OS_OpenCreate(&mmu_fd, "/ram/mm.crc", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mmu_crc = 0xA5A5A5A5;
    mmu_sv[0] = MM_ComputeCRCFromFile(mmu_fd, &mmu_crc, MM_INTERNAL_LOAD_FILE_CRC_TYPE);
    S("mmu_crc rc=");
    D(mmu_sv[0]);
    S(" crc=0x");
    Hx8(mmu_crc);
    S(" pos=");
    D(fs_pos);
    S("\n");
    // AN EMPTY FILE IS NOT AN ERROR: the first read returns 0, the loop never folds anything in,
    // and *CrcPtr is written with the initial 0. The poison is what says the write happened at
    // all.
    fs_len = 0;
    OS_OpenCreate(&mmu_fd, "/ram/mm.crc", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mmu_crc = 0xA5A5A5A5;
    mmu_sv[0] = MM_ComputeCRCFromFile(mmu_fd, &mmu_crc, MM_INTERNAL_LOAD_FILE_CRC_TYPE);
    S("mmu_crc_empty rc=");
    D(mmu_sv[0]);
    S(" crc=0x");
    Hx8(mmu_crc);
    S("\n");
    // AND A READ ERROR MUST NOT TOUCH *CrcPtr, which is the only branch in this function that
    // does not write it -- so the poison has to still be there. This is the first exercise in
    // the port to make OS_read FAIL; the knob defaults to zero and no existing line can see it.
    fs_len = 450;
    OS_OpenCreate(&mmu_fd, "/ram/mm.crc", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mmu_crc = 0xA5A5A5A5;
    fs_read_rc = OS_ERROR;
    mmu_sv[0] = MM_ComputeCRCFromFile(mmu_fd, &mmu_crc, MM_INTERNAL_LOAD_FILE_CRC_TYPE);
    S("mmu_crc_err rc=");
    D(mmu_sv[0]);
    S(" crc=0x");
    Hx8(mmu_crc);
    S("\n");
    fs_read_rc = 0;

    // --- mm_mem8.c -- THE FIRST SOURCE IN THE PORT THAT WRITES MEMORY -----------------------
    // Three functions, one shape: a segment loop that moves up to 200 bytes, then calls
    // MM_SegmentBreak so something else can run. The simulated window is 256 bytes, so 250 is
    // TWO segments -- 200 and 50 -- which is the smallest size that exercises both the short
    // last segment and the break between them.
    //
    // MM_PSP_READ_ERR_EID IS NOT DRIVEN HERE AND THAT IS DELIBERATE. Its text prints `Tgt=%p`,
    // which is `&ioBuffer8[i]` -- a REAL POINTER into MM_AppData.DumpBuffer, not an address the
    // ground supplied. Every other address in MM's events is a constant that came from a command
    // and is the same number on both halves; this one is wherever the linker put MM_AppData. See
    // the note at the top of Kernel/Cfs/mm/mm_mem8.HC.
    mm8_A = MD_SIM_WINDOW_BASE;
    mm8_perf = &CFE_ES_Global.ResetDataPtr->Perf;

    // --- MM_FillMem8. THE PATTERN IS TRUNCATED TO ONE BYTE and housekeeping reports the
    // TRUNCATED value, so 0xAABBCCDD must come back as 0xDD -- the app telling the operator what
    // it actually wrote rather than what they asked for.
    //
    // md_sim_writes IS THE WITNESS THAT THE LOOP RAN. MM computes BytesProcessed from its own
    // segment arithmetic and never from the stores, so a fill that stored nothing would report
    // 250 anyway. [250] is the neighbour: the fill must stop.
    md_sim_fill();
    MemSet(&mm8_fc, 0, sizeof(MM_FillMemCmd_t));
    mm8_fc.Payload.NumOfBytes = 250;
    mm8_fc.Payload.FillPattern = 0xAABBCCDD;
    MemSet(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
    mm8_w0 = md_sim_writes;
    mm8_p0 = mm8_perf->MetaData.DataCount;
    mm8_st = MM_FillMem8(mm8_A, &mm8_fc);
    S("mm8_fill st=");
    D(mm8_st);
    S(" writes=");
    D(md_sim_writes - mm8_w0);
    S(" perf=");
    D(mm8_perf->MetaData.DataCount - mm8_p0);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m199=");
    H2(md_sim_mem[199]);
    S(" m200=");
    H2(md_sim_mem[200]);
    S(" m249=");
    H2(md_sim_mem[249]);
    S(" m250=");
    H2(md_sim_mem[250]);
    S("\n");
    S("mm8_fill_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" fnZ=");
    D(MM_AppData.HkTlm.Payload.FileName[0]);
    S("\n");

    // A STORE THAT FAILS PART WAY THROUGH, at offset 100. The event prints the address it
    // stopped at; the loop breaks; BytesProcessed never reaches 250, so the SHORT arm turns the
    // status into CFE_PSP_ERROR and HOUSEKEEPING IS LEFT ALONE -- which is why the two HK fields
    // below must still read the previous fill's values.
    md_sim_fill();
    md_sim_wfail_at = 100;
    mm8_w0 = md_sim_writes;
    mm8_st = MM_FillMem8(mm8_A, &mm8_fc);
    md_sim_wfail_at = -1;
    S("mm8_fill_err st=");
    D(mm8_st);
    S(" writes=");
    D(md_sim_writes - mm8_w0);
    S(" m99=");
    H2(md_sim_mem[99]);
    S(" m100=");
    H2(md_sim_mem[100]);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S("\n");

    // --- MM_LoadMem8FromFile. The file is 250 bytes of a pattern that is NOT what md_sim_fill
    // leaves behind, so the window's contents after the load say the bytes came from the file
    // rather than from anywhere else.
    //
    // THE FILENAME GOES THROUGH strncpy, WHICH ZERO-FILLS. The destination is poisoned with 'Z'
    // first and byte 20 is printed: a MemCpy would leave the 'Z' there.
    md_sim_fill();
    for (mm8_k = 0; mm8_k < 250; mm8_k++) {
      fs_data[mm8_k] = (0x80 + mm8_k) & 0xFF;
    }
    fs_len = 250;
    fs_noexist = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    MemSet(&mm8_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mm8_fh.NumOfBytes = 250;
    MemSet(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
    mm8_w0 = md_sim_writes;
    mm8_p0 = mm8_perf->MetaData.DataCount;
    mm8_st = MM_LoadMem8FromFile(mm8_fd, "/ram/mm8.ld", &mm8_fh, mm8_A);
    S("mm8_load st=");
    D(mm8_st);
    S(" writes=");
    D(md_sim_writes - mm8_w0);
    S(" perf=");
    D(mm8_perf->MetaData.DataCount - mm8_p0);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m199=");
    H2(md_sim_mem[199]);
    S(" m200=");
    H2(md_sim_mem[200]);
    S(" m249=");
    H2(md_sim_mem[249]);
    S(" m250=");
    H2(md_sim_mem[250]);
    S("\n");
    S("mm8_load_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" fn=[");
    S(MM_AppData.HkTlm.Payload.FileName);
    S("] fn20=");
    D(MM_AppData.HkTlm.Payload.FileName[20]);
    S("\n");

    // A FILE THAT RUNS OUT. 100 bytes against a header claiming 250: the first read asks for 200
    // and gets 100, which is a SHORT READ and not an end of file, so MM_OS_READ_ERR_EID fires
    // with both the count it got and the count it wanted.
    md_sim_fill();
    fs_len = 100;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mm8_w0 = md_sim_writes;
    mm8_st = MM_LoadMem8FromFile(mm8_fd, "/ram/mm8.ld", &mm8_fh, mm8_A);
    S("mm8_load_short st=");
    D(mm8_st);
    S(" writes=");
    D(md_sim_writes - mm8_w0);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");

    // A STORE THAT FAILS DURING A LOAD -- the same branch as the fill's, reached from the other
    // caller, and the one that proves the load's error arm is its own code. It also leaves the
    // window PART written, which the fill's error case cannot show because a fill writes the
    // same byte everywhere.
    md_sim_fill();
    fs_len = 250;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    md_sim_wfail_at = 10;
    mm8_w0 = md_sim_writes;
    mm8_st = MM_LoadMem8FromFile(mm8_fd, "/ram/mm8.ld", &mm8_fh, mm8_A);
    md_sim_wfail_at = -1;
    S("mm8_load_wfail st=");
    D(mm8_st);
    S(" writes=");
    D(md_sim_writes - mm8_w0);
    S(" m9=");
    H2(md_sim_mem[9]);
    S(" m10=");
    H2(md_sim_mem[10]);
    S("\n");

    // --- MM_DumpMem8ToFile. The address comes from the FILE HEADER here, not from a parameter --
    // NASA's own asymmetry with the load above, kept.
    md_sim_fill();
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    MemSet(&mm8_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mm8_fh.NumOfBytes = 250;
    mm8_fh.SymAddress.Offset = mm8_A;
    MemSet(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
    mm8_p0 = mm8_perf->MetaData.DataCount;
    mm8_st = MM_DumpMem8ToFile(mm8_fd, "/ram/mm8.dp", &mm8_fh);
    S("mm8_dump st=");
    D(mm8_st);
    S(" perf=");
    D(mm8_perf->MetaData.DataCount - mm8_p0);
    S(" len=");
    D(fs_len);
    S(" d0=");
    H2(fs_data[0]);
    S(" d199=");
    H2(fs_data[199]);
    S(" d200=");
    H2(fs_data[200]);
    S(" d249=");
    H2(fs_data[249]);
    S("\n");
    S("mm8_dump_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" fn=[");
    S(MM_AppData.HkTlm.Payload.FileName);
    S("] fn20=");
    D(MM_AppData.HkTlm.Payload.FileName[20]);
    S("\n");

    // A FILE THAT WILL NOT TAKE IT ALL. 100 bytes of room against 250 to write: the FIRST write
    // asks for 200 and places 100, so MM_OS_WRITE_EXP_ERR_EID fires and HOUSEKEEPING IS NOT
    // UPDATED -- this function tests the STATUS rather than the byte count, the opposite of the
    // load, so the two HK fields below still hold the dump above's values.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = 100;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mm8_st = MM_DumpMem8ToFile(mm8_fd, "/ram/mm8.dp", &mm8_fh);
    fs_wr_left = -1;
    S("mm8_dump_short st=");
    D(mm8_st);
    S(" len=");
    D(fs_len);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");

    // --- THE LOAD'S BytesRemaining IS int32 AND THE DUMP'S IS uint32, which is NASA's own
    // inconsistency and is NOT an observable one anywhere above -- so here is the input that
    // makes it observable. A header claiming 0xFFFFFFFF bytes:
    //
    //   the LOAD reads it into an I32, so BytesRemaining is -1, `BytesRemaining <
    //   MM_INTERNAL_MAX_LOAD_DATA_SEG` is TRUE on a signed comparison, and SegmentSize becomes
    //   -1. The event then reports `Expected = 4294967295`.
    //
    //   the DUMP reads it into a U32, 0xFFFFFFFF is NOT less than 200, and the segment stays the
    //   full 200. Its event reports `Expected = 200`.
    //
    // Two numbers in two events, and they are the only thing in the transcript that says the two
    // declarations differ. Making the load's unsigned -- which is what a translator "tidying up"
    // would do -- changes the first to 200.
    //
    // THE DUMP IS FORCED TO FAIL ON THE **WRITE**, with no room in the file at all, rather than
    // being allowed to run off the end of the 256-byte window: running off it reaches
    // MM_PSP_READ_ERR_EID, whose text carries an uncomparable pointer.
    md_sim_fill();
    fs_len = 250;
    fs_wr_left = -1;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    MemSet(&mm8_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mm8_fh.NumOfBytes = 0xFFFFFFFF;
    mm8_fh.SymAddress.Offset = mm8_A;
    mm8_w0 = md_sim_writes;
    mm8_st = MM_LoadMem8FromFile(mm8_fd, "/ram/mm8.ld", &mm8_fh, mm8_A);
    S("mm8_load_signed st=");
    D(mm8_st);
    S(" writes=");
    D(md_sim_writes - mm8_w0);
    S("\n");
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = 0;
    OS_OpenCreate(&mm8_fd, "/ram/mm8.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mm8_st = MM_DumpMem8ToFile(mm8_fd, "/ram/mm8.dp", &mm8_fh);
    fs_wr_left = -1;
    S("mm8_dump_unsigned st=");
    D(mm8_st);
    S(" len=");
    D(fs_len);
    S("\n");


    // --- mm_mem16.c and mm_mem32.c -- THE WIDTH TWINS --------------------------------------
    // These two are near-copies of mm_mem8.c, so this block does NOT repeat mem8's cases. It
    // drives the FOUR THINGS THAT DIFFER, because that is the entire argument for NASA keeping
    // three files instead of one parameterised loop:
    //
    //   1. THE LOOPS COUNT ELEMENTS, NOT BYTES. A 200-byte segment is 200 stores in mem8, 100 in
    //      mem16 and 50 in mem32 -- and md_sim_writes is the only thing that can say so, because
    //      every byte count MM reports comes from its own segment arithmetic.
    //   2. THE FILL ROUNDS THE LENGTH DOWN, with a per-width event id and a per-width modulus,
    //      and then REPORTS AN ERROR ANYWAY -- the housekeeping guard compares BytesProcessed
    //      against the COMMANDED NumOfBytes, which the rounding has just made unreachable. This
    //      is also the input that makes mem8's two "swap the guard" no-op mutations into real
    //      ones here.
    //   3. THE PATTERN IS TRUNCATED TO THE WIDTH, and housekeeping reports the TRUNCATED value --
    //      0xCCDD from mem16, the whole 0xAABBCCDD from mem32, which needs no truncation at all.
    //      The window's bytes say which end went first.
    //   4. ONE ERROR, THREE RENDERINGS. The load's write-error event prints the PSP's status as
    //      `0x%08X` in mem8 and mem16 and as `%d` in mem32 -- and mem16 OVERWRITES the status
    //      with CFE_PSP_ERROR before printing it, so the three print 0xFFFFFFEB, 0xFFFFFFFF and
    //      -21 for the same failure. A translator who harmonised the three files would lose all
    //      of it, and nothing but these three events would notice.
    mmw_A = MD_SIM_WINDOW_BASE;
    MemSet(&mmw_fc, 0, sizeof(MM_FillMemCmd_t));
    mmw_fc.Payload.FillPattern = 0xAABBCCDD;

    // ===== MEM16 =====
    md_sim_fill();
    mmw_fc.Payload.NumOfBytes = 250;
    mmw_w = md_sim_writes;
    mmw_st = MM_FillMem16(mmw_A, &mmw_fc);
    S("mm16_fill st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m1=");
    H2(md_sim_mem[1]);
    S(" m248=");
    H2(md_sim_mem[248]);
    S(" m249=");
    H2(md_sim_mem[249]);
    S(" m250=");
    H2(md_sim_mem[250]);
    S("\n");
    S("mm16_fill_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");
    // AN ODD LENGTH: warns, rounds 251 down to 250, fills it, and STILL FAILS. The two HK fields
    // below must therefore still read the 250-byte fill above's.
    md_sim_fill();
    mmw_fc.Payload.NumOfBytes = 251;
    mmw_w = md_sim_writes;
    mmw_st = MM_FillMem16(mmw_A, &mmw_fc);
    S("mm16_fill_odd st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S("\n");

    // REFILL THE FILE BEFORE EVERY LOAD. The dumps below write INTO fs_data, and what they write
    // is md_sim_fill's own pattern -- so a load that read the stale file would place bytes
    // INDISTINGUISHABLE from the window's existing contents, and "m0=40" would be satisfied
    // equally by the load working and by it not running at all. It was written that way first
    // and the mem32 lines said 0x40 where they should have said 0x80.
    for (mmw_k = 0; mmw_k < 250; mmw_k++) {
      fs_data[mmw_k] = (0x80 + mmw_k) & 0xFF;
    }
    md_sim_fill();
    fs_len = 250;
    fs_noexist = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mmw_fd, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    MemSet(&mmw_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mmw_fh.NumOfBytes = 250;
    mmw_fh.SymAddress.Offset = mmw_A;
    mmw_w = md_sim_writes;
    mmw_st = MM_LoadMem16FromFile(mmw_fd, "/ram/mmw.ld", &mmw_fh, mmw_A);
    S("mm16_load st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m1=");
    H2(md_sim_mem[1]);
    S(" m248=");
    H2(md_sim_mem[248]);
    S(" m249=");
    H2(md_sim_mem[249]);
    S("\n");
    // THE FIRST OF THE THREE RENDERINGS. Offset 20 is 2-aligned, so the eleventh store is the
    // one that fails; the event prints 0xFFFFFFFF rather than the PSP's own 0xFFFFFFEB, because
    // mem16 overwrites the status before reporting it.
    for (mmw_k = 0; mmw_k < 250; mmw_k++) {
      fs_data[mmw_k] = (0x80 + mmw_k) & 0xFF;
    }
    md_sim_fill();
    fs_len = 250;
    OS_OpenCreate(&mmw_fd, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    md_sim_wfail_at = 20;
    mmw_w = md_sim_writes;
    mmw_st = MM_LoadMem16FromFile(mmw_fd, "/ram/mmw.ld", &mmw_fh, mmw_A);
    md_sim_wfail_at = -1;
    S("mm16_load_wfail st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" m18=");
    H2(md_sim_mem[18]);
    S(" m20=");
    H2(md_sim_mem[20]);
    S("\n");

    md_sim_fill();
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mmw_fd, "/ram/mmw.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mmw_r = md_sim_reads;
    mmw_st = MM_DumpMem16ToFile(mmw_fd, "/ram/mmw.dp", &mmw_fh);
    S("mm16_dump st=");
    D(mmw_st);
    S(" reads=");
    D(md_sim_reads - mmw_r);
    S(" len=");
    D(fs_len);
    S(" d0=");
    H2(fs_data[0]);
    S(" d1=");
    H2(fs_data[1]);
    S(" d249=");
    H2(fs_data[249]);
    S("\n");

    // ===== MEM32. 248 is the aligned length; 250 is not. =====
    md_sim_fill();
    mmw_fc.Payload.NumOfBytes = 248;
    mmw_w = md_sim_writes;
    mmw_st = MM_FillMem32(mmw_A, &mmw_fc);
    S("mm32_fill st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m1=");
    H2(md_sim_mem[1]);
    S(" m2=");
    H2(md_sim_mem[2]);
    S(" m3=");
    H2(md_sim_mem[3]);
    S(" m247=");
    H2(md_sim_mem[247]);
    S(" m248=");
    H2(md_sim_mem[248]);
    S("\n");
    // AND THE PATTERN IS NOT TRUNCATED AT ALL HERE, which is the one of the three widths where
    // the commanded value and the reported value agree.
    S("mm32_fill_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");
    md_sim_fill();
    mmw_fc.Payload.NumOfBytes = 250;
    mmw_w = md_sim_writes;
    mmw_st = MM_FillMem32(mmw_A, &mmw_fc);
    S("mm32_fill_unaligned st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");

    for (mmw_k = 0; mmw_k < 250; mmw_k++) {
      fs_data[mmw_k] = (0x80 + mmw_k) & 0xFF;
    }
    md_sim_fill();
    fs_len = 248;
    mmw_fh.NumOfBytes = 248;
    mmw_fh.SymAddress.Offset = mmw_A;
    OS_OpenCreate(&mmw_fd, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mmw_w = md_sim_writes;
    mmw_st = MM_LoadMem32FromFile(mmw_fd, "/ram/mmw.ld", &mmw_fh, mmw_A);
    S("mm32_load st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m3=");
    H2(md_sim_mem[3]);
    S(" m244=");
    H2(md_sim_mem[244]);
    S(" m247=");
    H2(md_sim_mem[247]);
    S("\n");
    // THE THIRD RENDERING: "RC=%d" with no overwrite, so the PSP's -21 reaches the ground as a
    // negative decimal. Offset 20 is 4-aligned, so the sixth store fails.
    for (mmw_k = 0; mmw_k < 250; mmw_k++) {
      fs_data[mmw_k] = (0x80 + mmw_k) & 0xFF;
    }
    md_sim_fill();
    fs_len = 248;
    OS_OpenCreate(&mmw_fd, "/ram/mmw.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    md_sim_wfail_at = 20;
    mmw_w = md_sim_writes;
    mmw_st = MM_LoadMem32FromFile(mmw_fd, "/ram/mmw.ld", &mmw_fh, mmw_A);
    md_sim_wfail_at = -1;
    S("mm32_load_wfail st=");
    D(mmw_st);
    S(" writes=");
    D(md_sim_writes - mmw_w);
    S(" m16=");
    H2(md_sim_mem[16]);
    S(" m20=");
    H2(md_sim_mem[20]);
    S("\n");

    md_sim_fill();
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mmw_fd, "/ram/mmw.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mmw_r = md_sim_reads;
    mmw_st = MM_DumpMem32ToFile(mmw_fd, "/ram/mmw.dp", &mmw_fh);
    S("mm32_dump st=");
    D(mmw_st);
    S(" reads=");
    D(md_sim_reads - mmw_r);
    S(" len=");
    D(fs_len);
    S(" d0=");
    H2(fs_data[0]);
    S(" d3=");
    H2(fs_data[3]);
    S(" d247=");
    H2(fs_data[247]);
    S("\n");

    // --- mm_dump.c -- the four ways MM gets memory OUT -------------------------------------
    // MM_PeekMem reaches memory through the PSP, so it uses the SIMULATED WINDOW and its two
    // events print only the address the ground supplied -- both fully comparable.
    //
    // MM_DumpMemToFile AND MM_FillDumpInEventBuffer'S RAM/EEPROM ARM DO NOT. They `memcpy` from
    // the address, so a literal window address would be a wild pointer, and they are exercised
    // against a REAL driver-owned array instead. The consequence is that MM_DumpMemToFile's
    // housekeeping Address is a real pointer and CANNOT BE PRINTED -- so it is asserted by
    // COMPARISON: `addr_ok` is whether the field equals the array's own address, which is true on
    // both halves and still fails if the field is set from the wrong place.
    //
    // MM_FillDumpInEventBuffer's THREE ERROR ARMS ARE NOT DRIVEN. Each prints `Tgt=%p`, the
    // caller's buffer, for the reason mm_mem8's read error is undrivable. Their four SUCCESS
    // paths are, including the RAM and EEPROM pair that SHARE a case body -- which is the one
    // thing in this file that depends on HolyC's switch falling through like C's. Measured before
    // the translation was written, with both an empty label and a non-empty case without a break.
    for (mmd_k = 0; mmd_k < 250; mmd_k++) {
      mmd_src[mmd_k] = (0x10 + mmd_k) & 0xFF;
    }
    md_sim_fill();

    // --- MM_PeekMem, the three widths. The data comes out of the simulated window, so every
    // byte in the three events is 0x40 + offset and the ENDIANNESS is part of the comparison: a
    // 32-bit peek at base+4 must read 0x47464544 and not 0x44454647.
    MemSet(&mmd_pk, 0, sizeof(MM_PeekCmd_t));
    mmd_pk.Payload.MemType = MM_MemType_RAM;
    mmd_pk.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
    mmd_st = MM_PeekMem(&mmd_pk, MD_SIM_WINDOW_BASE);
    S("mmd_peek8 st=");
    D(mmd_st);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S("\n");
    mmd_pk.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
    mmd_st = MM_PeekMem(&mmd_pk, MD_SIM_WINDOW_BASE + 2);
    S("mmd_peek16 st=");
    D(mmd_st);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S("\n");
    mmd_pk.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
    mmd_st = MM_PeekMem(&mmd_pk, MD_SIM_WINDOW_BASE + 4);
    S("mmd_peek32 st=");
    D(mmd_st);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S("\n");
    // OUTSIDE THE WINDOW. Housekeeping must keep the 32-bit peek's values, because the failure
    // path writes none of it.
    mmd_st = MM_PeekMem(&mmd_pk, MD_SIM_WINDOW_BASE + 300);
    S("mmd_peek_bad st=");
    D(mmd_st);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S("\n");
    // A WIDTH NO ARM RECOGNISES. PSP_Status is still the value it was INITIALISED to --
    // CFE_PSP_ERROR_NOT_IMPLEMENTED, -27 -- and DataSize is still 0, so the event reads
    // `MemType=MEM0`. It is the one status in MM that means "no branch ran". NASA's own comment
    // says a bad DataSize is caught by MM_VerifyPeekPokeParams and this cannot happen; calling
    // MM_PeekMem directly is how a translation of the arm that NASA says is unreachable gets
    // checked at all.
    mmd_pk.Payload.DataSize = 7;
    mmd_st = MM_PeekMem(&mmd_pk, MD_SIM_WINDOW_BASE);
    S("mmd_peek_nowidth st=");
    D(mmd_st);
    S("\n");

    // --- MM_DumpMemToFile, the GENERIC path: a real array, 250 bytes, two segments.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    fs_noexist = 0;
    OS_OpenCreate(&mmd_fd, "/ram/mmd.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    MemSet(&mmd_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mmd_fh.NumOfBytes = 250;
    mmd_fh.MemType = MM_MemType_EEPROM;
    mmd_fh.SymAddress.Offset = mmd_src(U64);
    MemSet(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
    mmd_st = MM_DumpMemToFile(mmd_fd, "/ram/mmd.dp", &mmd_fh);
    S("mmd_dump st=");
    D(mmd_st);
    S(" len=");
    D(fs_len);
    S(" d0=");
    H2(fs_data[0]);
    S(" d199=");
    H2(fs_data[199]);
    S(" d200=");
    H2(fs_data[200]);
    S(" d249=");
    H2(fs_data[249]);
    S("\n");
    // `addr_ok` INSTEAD OF `addr`: the field holds a real pointer, so its VALUE cannot cross the
    // two halves -- but whether it equals the array's address can.
    S("mmd_dump_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" addr_ok=");
    D(MM_AppData.HkTlm.Payload.Address == mmd_src(U64));
    S(" fn=[");
    S(MM_AppData.HkTlm.Payload.FileName);
    S("] fn20=");
    D(MM_AppData.HkTlm.Payload.FileName[20]);
    S("\n");
    // A SHORT WRITE. Note the event prints `RC = %d` -- a SIGNED decimal, where mm_mem8's twin
    // prints `0x%08X` -- so a 100-byte write reads `RC = 100`.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = 100;
    OS_OpenCreate(&mmd_fd, "/ram/mmd.dp", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mmd_st = MM_DumpMemToFile(mmd_fd, "/ram/mmd.dp", &mmd_fh);
    fs_wr_left = -1;
    S("mmd_dump_short st=");
    D(mmd_st);
    S(" len=");
    D(fs_len);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");

    // --- MM_WriteFileHeaders. 64 bytes of cFE header then 88 of MM's, and the MM header is
    // MEMSET HERE BY THE DRIVER: its last byte is tail padding, so NASA writes one byte of
    // whatever was on the caller's stack into every dump file. The zero at offset 151 below is
    // therefore evidence about THIS DRIVER and not about the translation -- stated because a
    // reader would otherwise take it for NASA's.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mmd_fd, "/ram/mmd.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    MemSet(&mmd_cfh, 0, sizeof(CFE_FS_Header_t));
    mmd_cfh.SubType = 0x4D4D5354;
    StrNCpy(mmd_cfh.Description, "MM dump", CFE_FS_HDR_DESC_MAX_LEN);
    MemSet(&mmd_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mmd_fh.NumOfBytes = 250;
    mmd_fh.Crc = 0x1234;
    mmd_fh.MemType = MM_MemType_MEM16;
    mmd_fh.SymAddress.Offset = 0x00100000;
    mmd_st = MM_WriteFileHeaders("/ram/mmd.hd", mmd_fd, &mmd_cfh, &mmd_fh);
    S("mmd_hdrs st=");
    D(mmd_st);
    S(" len=");
    D(fs_len);
    S(" mmoff=");
    H2(fs_data[64]);
    H2(fs_data[65]);
    H2(fs_data[66]);
    S(" nbytes=");
    D(fs_data[64 + 72]);
    S(" crc=");
    D(fs_data[64 + 76]);
    S(" mt=");
    D(fs_data[64 + 80]);
    S(" pad151=");
    D(fs_data[151]);
    S("\n");
    // THE cFE HEADER'S WRITE COMES UP SHORT. Both error arms of this function replace the status
    // with OS_ERR_INVALID_SIZE BEFORE printing it, so the event says -40 and not what actually
    // happened -- a failed write and a short write are indistinguishable to the ground. NASA's
    // own choice.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = 10;
    OS_OpenCreate(&mmd_fd, "/ram/mmd.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mmd_st = MM_WriteFileHeaders("/ram/mmd.hd", mmd_fd, &mmd_cfh, &mmd_fh);
    S("mmd_hdrs_short1 st=");
    D(mmd_st);
    S(" len=");
    D(fs_len);
    S("\n");
    // AND NOW THE cFE HEADER FITS BUT MM'S DOES NOT, which is the other arm -- the one that only
    // runs because the first one passed.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = 64 + 10;
    OS_OpenCreate(&mmd_fd, "/ram/mmd.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    mmd_st = MM_WriteFileHeaders("/ram/mmd.hd", mmd_fd, &mmd_cfh, &mmd_fh);
    fs_wr_left = -1;
    S("mmd_hdrs_short2 st=");
    D(mmd_st);
    S(" len=");
    D(fs_len);
    S("\n");

    // --- MM_FillDumpInEventBuffer, all four success arms. The buffer is 16 bytes and NASA clears
    // only the first MM_INTERNAL_MAX_DUMP_INEVENT_BYTES (15) of it, so [15] is a poison byte that
    // must survive -- and [8..14] must be ZERO after an 8-byte request, which is what says the
    // clear happened at all.
    //
    // RAM AND EEPROM SHARE ONE CASE BODY. Driving both is the only thing that says HolyC's switch
    // falls through: if an empty `case` label did not reach the next one, the RAM arm would do
    // nothing and return CFE_PSP_ERROR.
    MemSet(&mmd_de, 0, sizeof(MM_DumpInEventCmd_t));
    mmd_de.Payload.NumOfBytes = 8;
    // Filled at use rather than initialised: HolyC has no aggregate initialiser, and the C half
    // is written the same way so the two read alike.
    mmd_mts[0] = MM_MemType_RAM;
    mmd_mts[1] = MM_MemType_EEPROM;
    mmd_mts[2] = MM_MemType_MEM32;
    mmd_mts[3] = MM_MemType_MEM16;
    for (mmd_k = 0; mmd_k < 4; mmd_k++) {
      MemSet(mmd_evbuf, 0xEE, 16);
      mmd_de.Payload.MemType = mmd_mts[mmd_k];
      // RAM and EEPROM copy from a real pointer; the two width arms go through the PSP and so
      // take a window address.
      mmd_src_addr = MD_SIM_WINDOW_BASE;
      if (mmd_k < 2) {
        mmd_src_addr = mmd_src(U64);
      }
      mmd_r = md_sim_reads;
      mmd_st = MM_FillDumpInEventBuffer(mmd_src_addr, &mmd_de, mmd_evbuf);
      S("mmd_ev mt=");
      D(mmd_mts[mmd_k]);
      S(" st=");
      D(mmd_st);
      S(" reads=");
      D(md_sim_reads - mmd_r);
      S(" b0=");
      H2(mmd_evbuf[0]);
      S(" b1=");
      H2(mmd_evbuf[1]);
      S(" b7=");
      H2(mmd_evbuf[7]);
      S(" b8=");
      H2(mmd_evbuf[8]);
      S(" b14=");
      H2(mmd_evbuf[14]);
      S(" b15=");
      H2(mmd_evbuf[15]);
      S("\n");
    }
    MemSet(mmd_evbuf, 0xEE, 16);
    mmd_de.Payload.MemType = MM_MemType_MEM8;
    mmd_r = md_sim_reads;
    mmd_st = MM_FillDumpInEventBuffer(MD_SIM_WINDOW_BASE, &mmd_de, mmd_evbuf);
    S("mmd_ev mt=");
    D(MM_MemType_MEM8);
    S(" st=");
    D(mmd_st);
    S(" reads=");
    D(md_sim_reads - mmd_r);
    S(" b0=");
    H2(mmd_evbuf[0]);
    S(" b1=");
    H2(mmd_evbuf[1]);
    S(" b7=");
    H2(mmd_evbuf[7]);
    S(" b8=");
    H2(mmd_evbuf[8]);
    S(" b14=");
    H2(mmd_evbuf[14]);
    S(" b15=");
    H2(mmd_evbuf[15]);
    S("\n");
    // AND A MEMORY TYPE NO ARM MATCHES: NASA's default is empty and says it cannot happen, so
    // PSP_Status is still the CFE_PSP_ERROR it was initialised to -- but the BUFFER IS STILL
    // CLEARED, because the MemSet runs before the switch. Both halves of that.
    MemSet(mmd_evbuf, 0xEE, 16);
    mmd_de.Payload.MemType = MM_MemType_NOMEMTYPE;
    mmd_st = MM_FillDumpInEventBuffer(MD_SIM_WINDOW_BASE, &mmd_de, mmd_evbuf);
    S("mmd_ev_nomt st=");
    D(mmd_st);
    S(" b0=");
    H2(mmd_evbuf[0]);
    S(" b14=");
    H2(mmd_evbuf[14]);
    S(" b15=");
    H2(mmd_evbuf[15]);
    S("\n");

    // --- mm_load.c -- the six ways MM gets data IN ------------------------------------------
    // EEPROM IS A SEPARATE DEVICE AND SO A SECOND SIMULATED REGION. A RAM poke goes through
    // CFE_PSP_MemWrite* into MD_SIM_WINDOW; an EEPROM poke goes through CFE_PSP_EepromWrite*
    // into MM_EEP_WINDOW, 0x00200000 and far away on purpose -- an address meant for one and
    // sent to the other must be REFUSED, not quietly work, and the line below that pokes EEPROM
    // at the RAM window's base is what says so.
    //
    // AND MM_FillMem HAS AN UPSTREAM DEFECT THAT THIS BLOCK PRINTS. NASA's scratch-segment loop
    // runs MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(uint32) = 50 times through a BYTE pointer, so
    // a 200-byte segment gets the pattern in its first fifty bytes and keeps whatever
    // MM_AppData.FillBuffer held in the other 150. Kept verbatim -- see the long note at the top
    // of Kernel/Cfs/mm/mm_load.HC -- and the four bytes printed below are the boundary: 0 and 49
    // carry the pattern, 50 and 199 do not.
    mml_perf = &CFE_ES_Global.ResetDataPtr->Perf;
    MemSet(&mml_pk, 0, sizeof(MM_PokeCmd_t));
    mml_pk.Payload.MemType = MM_MemType_RAM;
    mml_pk.Payload.Data = 0xAABBCCDD;

    // --- MM_PokeMem, the three widths into the RAM window. The window's own bytes say which end
    // went first, and the event prints 0x%08X at every width -- which is the asymmetry with the
    // EEPROM path below.
    md_sim_fill();
    mml_pk.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
    mml_st = MM_PokeMem(&mml_pk, MD_SIM_WINDOW_BASE + 8);
    // PER-WIDTH, NOT JUST THE LAST ONE. The three byte counts were printed once after all three
    // pokes, which reads only the 32-bit arm's -- so a mutation that made the 16-bit arm report
    // ONE byte was INVISIBLE. Captured per call now.
    mml_bp[0] = MM_AppData.HkTlm.Payload.BytesProcessed;
    mml_dv[0] = MM_AppData.HkTlm.Payload.DataValue;
    mml_pk.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
    mml_st += MM_PokeMem(&mml_pk, MD_SIM_WINDOW_BASE + 16);
    mml_bp[1] = MM_AppData.HkTlm.Payload.BytesProcessed;
    mml_dv[1] = MM_AppData.HkTlm.Payload.DataValue;
    mml_pk.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
    mml_st += MM_PokeMem(&mml_pk, MD_SIM_WINDOW_BASE + 24);
    mml_bp[2] = MM_AppData.HkTlm.Payload.BytesProcessed;
    mml_dv[2] = MM_AppData.HkTlm.Payload.DataValue;
    S("mml_poke_bp ");
    D(mml_bp[0]);
    S(",");
    D(mml_bp[1]);
    S(",");
    D(mml_bp[2]);
    S(" dv ");
    D(mml_dv[0]);
    S(",");
    D(mml_dv[1]);
    S(",");
    D(mml_dv[2]);
    S("\n");
    S("mml_poke st=");
    D(mml_st);
    S(" m8=");
    H2(md_sim_mem[8]);
    S(" m16=");
    H2(md_sim_mem[17]);
    H2(md_sim_mem[16]);
    S(" m32=");
    H2(md_sim_mem[27]);
    H2(md_sim_mem[26]);
    H2(md_sim_mem[25]);
    H2(md_sim_mem[24]);
    S("\n");
    S("mml_poke_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S("\n");
    // OUTSIDE THE WINDOW, and a width no arm recognises. The second returns -27 with
    // `MemType=MEM0` -- BytesProcessed and DataSize are set BEFORE the write in this function,
    // which is why the first one's event can print `MemType=MEM32` where MM_PeekMem's failure
    // prints the size it never got to use.
    mml_st = MM_PokeMem(&mml_pk, MD_SIM_WINDOW_BASE + 300);
    S("mml_poke_bad st=");
    D(mml_st);
    S("\n");
    mml_pk.Payload.DataSize = 7;
    mml_st = MM_PokeMem(&mml_pk, MD_SIM_WINDOW_BASE);
    S("mml_poke_nowidth st=");
    D(mml_st);
    S("\n");

    // --- MM_PokeEeprom, the three widths into the OTHER region. Two performance-log entries per
    // call -- the RAM poke has none -- and the success event prints the data AT THE COMMANDED
    // WIDTH, so the same 0xAABBCCDD reads 0xDD, 0xCCDD and 0xAABBCCDD across the three.
    MemSet(mm_eep_mem, 0, MM_EEP_WINDOW_SIZE);
    mml_pk.Payload.MemType = MM_MemType_EEPROM;
    mml_pk.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
    mml_w = mm_eep_writes;
    mml_p0 = mml_perf->MetaData.DataCount;
    mml_st = MM_PokeEeprom(&mml_pk, MM_EEP_WINDOW_BASE + 8);
    mml_bp[0] = MM_AppData.HkTlm.Payload.BytesProcessed;
    mml_pk.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
    mml_st += MM_PokeEeprom(&mml_pk, MM_EEP_WINDOW_BASE + 16);
    mml_bp[1] = MM_AppData.HkTlm.Payload.BytesProcessed;
    mml_pk.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
    mml_st += MM_PokeEeprom(&mml_pk, MM_EEP_WINDOW_BASE + 24);
    mml_bp[2] = MM_AppData.HkTlm.Payload.BytesProcessed;
    S("mml_poke_eep_bp ");
    D(mml_bp[0]);
    S(",");
    D(mml_bp[1]);
    S(",");
    D(mml_bp[2]);
    S("\n");
    S("mml_poke_eep st=");
    D(mml_st);
    S(" writes=");
    D(mm_eep_writes - mml_w);
    S(" perf=");
    D(mml_perf->MetaData.DataCount - mml_p0);
    S(" e8=");
    H2(mm_eep_mem[8]);
    S(" e16=");
    H2(mm_eep_mem[17]);
    H2(mm_eep_mem[16]);
    S(" e32=");
    H2(mm_eep_mem[27]);
    H2(mm_eep_mem[26]);
    H2(mm_eep_mem[25]);
    H2(mm_eep_mem[24]);
    S("\n");
    S("mml_poke_eep_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S("\n");
    // THE TWO REGIONS ARE SEPARATE, which is the whole reason EEPROM got its own window: an
    // EEPROM poke aimed at the RAM window's base must be REFUSED, and the RAM window's byte
    // there must be untouched. A shared array would have made this succeed and nothing else in
    // the port would have noticed.
    md_sim_fill();
    mml_w = mm_eep_writes;
    mml_pk.Payload.DataSize = MM_INTERNAL_BYTE_BIT_WIDTH;
    mml_st = MM_PokeEeprom(&mml_pk, MD_SIM_WINDOW_BASE + 8);
    S("mml_poke_eep_wrongregion st=");
    D(mml_st);
    S(" writes=");
    D(mm_eep_writes - mml_w);
    S(" ram8=");
    H2(md_sim_mem[8]);
    S("\n");
    // AND HOUSEKEEPING AFTER A FAILED POKE, which nothing read before -- so a mutation that
    // updated it on the error path was INVISIBLE. The address must still be the 32-bit EEPROM
    // poke's, 0x200018, and the byte count still 4.
    S("mml_poke_eep_failhk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S("\n");
    // And the other two widths' error ids, which are three DIFFERENT events for one failure --
    // the RAM poke has one.
    mml_pk.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
    mml_st = MM_PokeEeprom(&mml_pk, MD_SIM_WINDOW_BASE + 8);
    mml_pk.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
    mml_st += MM_PokeEeprom(&mml_pk, MD_SIM_WINDOW_BASE + 8);
    S("mml_poke_eep_err st=");
    D(mml_st);
    S("\n");

    // --- MM_LoadMemFromFile, generic, into the real array. THE PERFORMANCE STAMPS ARE
    // CONDITIONAL ON THE FILE HEADER'S MEMORY TYPE -- the only marker in MM taken only sometimes
    // -- so the same call gives perf=2 for EEPROM and perf=0 for RAM, with the segment break's
    // own pair on top of both.
    for (mml_k = 0; mml_k < 250; mml_k++) {
      fs_data[mml_k] = (0x80 + mml_k) & 0xFF;
    }
    MemSet(mmd_src, 0xBB, 250);
    fs_len = 250;
    fs_noexist = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mml_fd, "/ram/mml.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    MemSet(&mml_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mml_fh.NumOfBytes = 250;
    mml_fh.MemType = MM_MemType_EEPROM;
    mml_fh.SymAddress.Offset = mmd_src(U64);
    MemSet(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
    mml_p0 = mml_perf->MetaData.DataCount;
    mml_st = MM_LoadMemFromFile(mml_fd, "/ram/mml.ld", &mml_fh, mmd_src(U64));
    S("mml_load_eep st=");
    D(mml_st);
    S(" perf=");
    D(mml_perf->MetaData.DataCount - mml_p0);
    S(" s0=");
    H2(mmd_src[0]);
    S(" s199=");
    H2(mmd_src[199]);
    S(" s200=");
    H2(mmd_src[200]);
    S(" s249=");
    H2(mmd_src[249]);
    S("\n");
    S("mml_load_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" addr_ok=");
    D(MM_AppData.HkTlm.Payload.Address == mmd_src(U64));
    S(" fn=[");
    S(MM_AppData.HkTlm.Payload.FileName);
    S("] fn20=");
    D(MM_AppData.HkTlm.Payload.FileName[20]);
    S("\n");
    MemSet(mmd_src, 0xBB, 250);
    fs_len = 250;
    mml_fh.MemType = MM_MemType_RAM;
    OS_OpenCreate(&mml_fd, "/ram/mml.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mml_p0 = mml_perf->MetaData.DataCount;
    mml_st = MM_LoadMemFromFile(mml_fd, "/ram/mml.ld", &mml_fh, mmd_src(U64));
    S("mml_load_ram st=");
    D(mml_st);
    S(" perf=");
    D(mml_perf->MetaData.DataCount - mml_p0);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" s0=");
    H2(mmd_src[0]);
    S("\n");
    // A SHORT FILE. Note this function's event prints `RC = 0x%08X` where MM_DumpMemToFile's
    // prints `RC = %d` -- two sources, two renderings, again.
    MemSet(mmd_src, 0xBB, 250);
    fs_len = 100;
    OS_OpenCreate(&mml_fd, "/ram/mml.ld", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mml_st = MM_LoadMemFromFile(mml_fd, "/ram/mml.ld", &mml_fh, mmd_src(U64));
    S("mml_load_short st=");
    D(mml_st);
    S(" s0=");
    H2(mmd_src[0]);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");

    // --- MM_VerifyLoadFileSize. The expected size is the header's claim PLUS BOTH HEADERS:
    // 250 + 64 + 88 = 402. This is the first thing in the port to READ the stat buffer rather
    // than only OS_stat's return code.
    mml_fh.NumOfBytes = 250;
    es_stat_rc = OS_SUCCESS;
    es_stat_size = 402;
    mml_st = MM_VerifyLoadFileSize("/ram/mml.ld", &mml_fh);
    S("mml_vsize_ok st=");
    D(mml_st);
    S("\n");
    es_stat_size = 401;
    mml_st = MM_VerifyLoadFileSize("/ram/mml.ld", &mml_fh);
    S("mml_vsize_wrong st=");
    D(mml_st);
    S("\n");
    es_stat_rc = OS_ERROR;
    mml_st = MM_VerifyLoadFileSize("/ram/mml.ld", &mml_fh);
    S("mml_vsize_statfail st=");
    D(mml_st);
    S("\n");
    es_stat_rc = OS_SUCCESS;
    es_stat_size = 0;

    // --- MM_ReadFileHeaders, AS A ROUND TRIP THROUGH MM_WriteFileHeaders. Writing the pair and
    // reading it back is the only test that says the two agree about the layout -- each on its
    // own would pass against a wrong offset.
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    OS_OpenCreate(&mml_fd, "/ram/mml.hd", OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                  OS_WRITE_ONLY);
    MemSet(&mml_cf, 0, sizeof(CFE_FS_Header_t));
    mml_cf.SubType = 0x4D4D5354;
    MemSet(&mml_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    mml_fh.NumOfBytes = 1234;
    mml_fh.Crc = 0x55AA;
    mml_fh.MemType = MM_MemType_MEM8;
    mml_fh.SymAddress.Offset = 0x00100040;
    StrNCpy(mml_fh.SymAddress.SymName, "RT", CFE_MISSION_MAX_PATH_LEN);
    mml_st = MM_WriteFileHeaders("/ram/mml.hd", mml_fd, &mml_cf, &mml_fh);
    MemSet(&mml_cf, 0, sizeof(CFE_FS_Header_t));
    MemSet(&mml_fh, 0, sizeof(MM_LoadDumpFileHeader_t));
    OS_OpenCreate(&mml_fd, "/ram/mml.hd", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mml_st = MM_ReadFileHeaders("/ram/mml.hd", mml_fd, &mml_cf, &mml_fh);
    S("mml_rt st=");
    D(mml_st);
    S(" sub=0x");
    Hx8(mml_cf.SubType);
    S(" nbytes=");
    D(mml_fh.NumOfBytes);
    S(" crc=0x");
    Hx4(mml_fh.Crc);
    S(" mt=");
    D(mml_fh.MemType);
    S(" off=");
    D(mml_fh.SymAddress.Offset);
    S(" sym=[");
    S(mml_fh.SymAddress.SymName);
    S("]\n");
    // THE TWO SHORT ARMS. Unlike the writer, this one sends the event BEFORE replacing the
    // status, so the ground sees what CFE_FS_ReadHeader really returned.
    fs_len = 10;
    OS_OpenCreate(&mml_fd, "/ram/mml.hd", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mml_st = MM_ReadFileHeaders("/ram/mml.hd", mml_fd, &mml_cf, &mml_fh);
    S("mml_rt_short1 st=");
    D(mml_st);
    S("\n");
    fs_len = 64 + 10;
    OS_OpenCreate(&mml_fd, "/ram/mml.hd", OS_FILE_FLAG_NONE, OS_READ_ONLY);
    mml_st = MM_ReadFileHeaders("/ram/mml.hd", mml_fd, &mml_cf, &mml_fh);
    S("mml_rt_short2 st=");
    D(mml_st);
    S("\n");

    // --- MM_FillMem, AND THE UPSTREAM DEFECT. 200 bytes into an array poisoned with 0xBB.
    // Bytes 0 and 49 must carry the pattern's LOW BYTE; bytes 50 and 199 must carry whatever
    // MM_AppData.FillBuffer held -- which is zero the first time, since it is in BSS and nothing
    // has touched it. The 0xBB is gone either way, because the MemCpy covers the whole segment;
    // it is the CONTENTS that say only a quarter of the segment was ever filled.
    MemSet(mmd_src, 0xBB, 250);
    MemSet(&mml_fc, 0, sizeof(MM_FillMemCmd_t));
    mml_fc.Payload.NumOfBytes = 200;
    mml_fc.Payload.FillPattern = 0xAABBCCDD;
    mml_fc.Payload.MemType = MM_MemType_RAM;
    mml_p0 = mml_perf->MetaData.DataCount;
    MM_FillMem(mmd_src(U64), &mml_fc);
    S("mml_fill perf=");
    D(mml_perf->MetaData.DataCount - mml_p0);
    S(" s0=");
    H2(mmd_src[0]);
    S(" s49=");
    H2(mmd_src[49]);
    S(" s50=");
    H2(mmd_src[50]);
    S(" s199=");
    H2(mmd_src[199]);
    S(" s200=");
    H2(mmd_src[200]);
    S("\n");
    S("mml_fill_hk la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" addr_ok=");
    D(MM_AppData.HkTlm.Payload.Address == mmd_src(U64));
    S("\n");
    // 250 BYTES IS TWO SEGMENTS, so the segment break fires once -- perf goes to 2 for a RAM
    // fill, and to 4 for an EEPROM one because this function's own stamps are conditional on the
    // memory type the same way the load's are.
    MemSet(mmd_src, 0xBB, 250);
    mml_fc.Payload.NumOfBytes = 250;
    mml_p0 = mml_perf->MetaData.DataCount;
    MM_FillMem(mmd_src(U64), &mml_fc);
    S("mml_fill_2seg perf=");
    D(mml_perf->MetaData.DataCount - mml_p0);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" s200=");
    H2(mmd_src[200]);
    S(" s249=");
    H2(mmd_src[249]);
    S("\n");
    MemSet(mmd_src, 0xBB, 250);
    mml_fc.Payload.MemType = MM_MemType_EEPROM;
    mml_p0 = mml_perf->MetaData.DataCount;
    MM_FillMem(mmd_src(U64), &mml_fc);
    S("mml_fill_eep perf=");
    D(mml_perf->MetaData.DataCount - mml_p0);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S("\n");

    // --- mm_cmds.c -- MM'S FOURTEEN GROUND COMMANDS ----------------------------------------
    // THE MEMORY TYPE DECIDES WHETHER A COMMAND IS COMPARABLE AT ALL, and that is the design of
    // this whole block. Five of the handlers print the resolved address in their SUCCESS event:
    //
    //   with MemType = MEM8/MEM16/MEM32 the work goes through CFE_PSP_Mem{Read,Write}*, so the
    //   address is a literal window constant and the event is the same text on both halves.
    //   Every success path below is driven that way.
    //
    //   with MemType = RAM or EEPROM the work is a `memcpy` from or to the address, so it has to
    //   be real memory -- a different number on each half -- and the event cannot be compared.
    //   Those paths were driven through mm_dump.c and mm_load.c directly, where the housekeeping
    //   address is asserted by COMPARISON instead.
    //
    // ONE SUCCESS PATH IS OUTSIDE THE DIFFERENTIAL ENTIRELY: MM_LoadMemWIDCmd. Its memory type
    // is HARD-CODED to RAM -- an EEPROM programming cycle cannot be done with interrupts off --
    // and it ends in `memcpy((void *)DestAddress, ...)`. So the address is necessarily real, and
    // the event that announces the load prints it. Its three ERROR paths are driven; its success
    // path is not, and nothing here pretends otherwise.
    //
    // THE HK PACKET NEEDS ITS MsgId, which is md_app.c's job and mm_app.c's after it. Without it
    // CFE_SB_TransmitMsg refuses with `Send Err:Invalid MsgId(0x0)` -- MD hit that for real
    // twice, and it is the thing that makes a send OBSERVABLE.
    CFE_MSG_Init(&MM_AppData.HkTlm.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(MM_HK_TLM_MID),
                 sizeof(MM_HkTlm_t));

    // --- MM_SendHkCmd. It must NOT move the command counter -- housekeeping arrives once a
    // second and counting it would swamp the number an operator reads.
    MM_AppData.HkTlm.Payload.CommandCounter = 11;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 22;
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_st = MM_SendHkCmd(&mmc_c.Hk);
    S("mmc_hk st=");
    D(mmc_st);
    S(" cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- MM_NoopCmd and MM_ResetCountersCmd.
    mmc_st = MM_NoopCmd(&mmc_c.Noop);
    S("mmc_noop st=");
    D(mmc_st);
    S(" cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S("\n");
    mmc_st = MM_ResetCountersCmd(&mmc_c.Reset);
    S("mmc_reset st=");
    D(mmc_st);
    S(" cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S("\n");

    // --- MM_LookupSymCmd, all three outcomes. The address in the event is the driver's
    // md_sym_addr, a constant, so this is the one command whose address is comparable whatever
    // the memory type -- it never touches memory at all.
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    MM_LookupSymCmd(&mmc_c.Lookup);
    S("mmc_lookup_nul ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    StrCpy(mmc_c.Lookup.Payload.SymName, "MM_PROBE");
    md_sym_rc = OS_SUCCESS;
    md_sym_addr = 0x00100020;
    MM_LookupSymCmd(&mmc_c.Lookup);
    S("mmc_lookup_ok cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" addr=");
    D(MM_AppData.HkTlm.Payload.Address);
    S("\n");
    md_sym_rc = OS_ERROR;
    MM_LookupSymCmd(&mmc_c.Lookup);
    S("mmc_lookup_fail ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    md_sym_rc = OS_SUCCESS;

    // --- MM_SymTblToFileCmd, all three outcomes. The size limit the stub records is
    // MM_INTERNAL_MAX_DUMP_FILE_DATA_SYMTBL, which no other line in MM reads.
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    MM_SymTblToFileCmd(&mmc_c.SymTbl);
    S("mmc_symtbl_nul ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    StrCpy(mmc_c.SymTbl.Payload.FileName, "/ram/sym.dmp");
    MemSet(MM_AppData.HkTlm.Payload.FileName, 'Z', CFE_MISSION_MAX_PATH_LEN);
    mm_symdump_rc = OS_SUCCESS;
    MM_SymTblToFileCmd(&mmc_c.SymTbl);
    S("mmc_symtbl_ok cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" limit=");
    D(mm_symdump_limit);
    S(" fn=[");
    S(MM_AppData.HkTlm.Payload.FileName);
    S("] fn20=");
    D(MM_AppData.HkTlm.Payload.FileName[20]);
    S("\n");
    mm_symdump_rc = OS_ERROR;
    MM_SymTblToFileCmd(&mmc_c.SymTbl);
    S("mmc_symtbl_fail ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    mm_symdump_rc = OS_SUCCESS;

    // --- the two EEPROM bank commands, both outcomes each. The bank number reaches the event,
    // and mm_eep_last_bank says the PSP was really asked for THAT bank.
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.Ena.Payload.Bank = 3;
    mm_eep_lock_rc = CFE_PSP_SUCCESS;
    MM_EepromWriteEnaCmd(&mmc_c.Ena);
    S("mmc_eepena cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bank=");
    D(mm_eep_last_bank);
    S(" locks=");
    D(mm_eep_locks);
    S("\n");
    mmc_c.Dis.Payload.Bank = 4;
    MM_EepromWriteDisCmd(&mmc_c.Dis);
    S("mmc_eepdis cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" bank=");
    D(mm_eep_last_bank);
    S("\n");
    mm_eep_lock_rc = CFE_PSP_ERROR;
    MM_EepromWriteEnaCmd(&mmc_c.Ena);
    MM_EepromWriteDisCmd(&mmc_c.Dis);
    S("mmc_eep_fail ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    mm_eep_lock_rc = CFE_PSP_SUCCESS;

    // --- MM_PokeCmd. The RAM arm and the EEPROM arm are two different workers chosen by the
    // memory type, which is the one branch in this handler. Both addresses are window constants
    // because both go through the PSP.
    md_sim_fill();
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.Poke.Payload.MemType = MM_MemType_RAM;
    mmc_c.Poke.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
    mmc_c.Poke.Payload.Data = 0x11223344;
    mmc_c.Poke.Payload.DestSymAddress.Offset = MD_SIM_WINDOW_BASE + 32;
    MM_PokeCmd(&mmc_c.Poke);
    S("mmc_poke_ram cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" m32=");
    H2(md_sim_mem[35]);
    H2(md_sim_mem[34]);
    H2(md_sim_mem[33]);
    H2(md_sim_mem[32]);
    S("\n");
    MemSet(mm_eep_mem, 0, MM_EEP_WINDOW_SIZE);
    mmc_c.Poke.Payload.MemType = MM_MemType_EEPROM;
    mmc_c.Poke.Payload.DestSymAddress.Offset = MM_EEP_WINDOW_BASE + 32;
    MM_PokeCmd(&mmc_c.Poke);
    S("mmc_poke_eep cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" e32=");
    H2(mm_eep_mem[35]);
    H2(mm_eep_mem[34]);
    H2(mm_eep_mem[33]);
    H2(mm_eep_mem[32]);
    S("\n");
    // A POKE THE WORKER REFUSES, which is a THIRD error arm and not the same as the two below:
    // the verifier passes (this driver's MemValidateRange accepts any address) and
    // CFE_PSP_MemWrite32 then rejects it, so the failure comes back from MM_PokeMem and lands in
    // the INNER else. Without this case a mutation that counted a failed poke as a success was
    // INVISIBLE -- every other poke here either works or never reaches the worker.
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    mmc_c.Poke.Payload.MemType = MM_MemType_RAM;
    mmc_c.Poke.Payload.DestSymAddress.Offset = MD_SIM_WINDOW_BASE + 300;
    MM_PokeCmd(&mmc_c.Poke);
    S("mmc_poke_wfail cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    mmc_c.Poke.Payload.DestSymAddress.Offset = MM_EEP_WINDOW_BASE + 32;
    mmc_c.Poke.Payload.MemType = MM_MemType_EEPROM;

    // A WIDTH THE VERIFIER REFUSES, and then an UNRESOLVABLE SYMBOL -- the two error arms. The
    // second prints the LOCAL COPY of the name, which MM_ResolveSymAddr has NUL-terminated;
    // MM_PeekCmd's twin prints the message's own field instead.
    mmc_c.Poke.Payload.DataSize = 7;
    MM_PokeCmd(&mmc_c.Poke);
    S("mmc_poke_badsize ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    mmc_c.Poke.Payload.DataSize = MM_INTERNAL_DWORD_BIT_WIDTH;
    StrCpy(mmc_c.Poke.Payload.DestSymAddress.SymName, "NOSUCH");
    md_sym_rc = OS_ERROR;
    MM_PokeCmd(&mmc_c.Poke);
    S("mmc_poke_badsym ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- MM_PeekCmd, success and its own symbol error.
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.Peek.Payload.MemType = MM_MemType_MEM16;
    mmc_c.Peek.Payload.DataSize = MM_INTERNAL_WORD_BIT_WIDTH;
    mmc_c.Peek.Payload.SrcSymAddress.Offset = MD_SIM_WINDOW_BASE + 40;
    md_sym_rc = OS_SUCCESS;
    MM_PeekCmd(&mmc_c.Peek);
    S("mmc_peek cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" dv=0x");
    Hx8(MM_AppData.HkTlm.Payload.DataValue);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");
    StrCpy(mmc_c.Peek.Payload.SrcSymAddress.SymName, "NOSUCH");
    md_sym_rc = OS_ERROR;
    MM_PeekCmd(&mmc_c.Peek);
    S("mmc_peek_badsym ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    md_sym_rc = OS_SUCCESS;

    // --- MM_LoadMemWIDCmd, THE THREE ERROR ARMS. See the note at the top of this block for why
    // the success path is not here: it is hard-coded to RAM and ends in a memcpy to the resolved
    // address, which the event then prints.
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.Wid.Payload.NumOfBytes = 8;
    for (mmc_k = 0; mmc_k < 8; mmc_k++) {
      mmc_c.Wid.Payload.DataArray[mmc_k] = (0x30 + mmc_k) & 0xFF;
    }
    mmc_c.Wid.Payload.DestSymAddress.Offset = MD_SIM_WINDOW_BASE;
    mmc_c.Wid.Payload.Crc = 0; /* deliberately wrong */
    MM_LoadMemWIDCmd(&mmc_c.Wid);
    S("mmc_wid_badcrc ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    // A LENGTH ABOVE MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA, which is the WID-specific limit the
    // verifier applies -- 200.
    mmc_c.Wid.Payload.NumOfBytes = 201;
    MM_LoadMemWIDCmd(&mmc_c.Wid);
    S("mmc_wid_badlen ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    mmc_c.Wid.Payload.NumOfBytes = 8;
    StrCpy(mmc_c.Wid.Payload.DestSymAddress.SymName, "NOSUCH");
    md_sym_rc = OS_ERROR;
    MM_LoadMemWIDCmd(&mmc_c.Wid);
    S("mmc_wid_badsym ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    md_sym_rc = OS_SUCCESS;

    // --- MM_FillMemCmd. MEM8 for the comparable success path, then THE SECOND UPSTREAM DEFECT.
    md_sim_fill();
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.Fill.Payload.MemType = MM_MemType_MEM8;
    mmc_c.Fill.Payload.NumOfBytes = 16;
    mmc_c.Fill.Payload.FillPattern = 0x5A5A5A5A;
    mmc_c.Fill.Payload.DestSymAddress.Offset = MD_SIM_WINDOW_BASE + 64;
    mmc_cc0 = MM_AppData.HkTlm.Payload.CommandCounter;
    MM_FillMemCmd(&mmc_c.Fill);
    S("mmc_fill8 cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter - mmc_cc0);
    S(" m64=");
    H2(md_sim_mem[64]);
    S(" m79=");
    H2(md_sim_mem[79]);
    S(" m80=");
    H2(md_sim_mem[80]);
    S("\n");
    md_sim_fill();
    mmc_c.Fill.Payload.MemType = MM_MemType_MEM16;
    mmc_c.Fill.Payload.NumOfBytes = 15;
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_FillMemCmd(&mmc_c.Fill);
    S("mmc_fill16_odd cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S(" m64=");
    H2(md_sim_mem[64]);
    S(" m77=");
    H2(md_sim_mem[77]);
    S(" m78=");
    H2(md_sim_mem[78]);
    S("\n");
    // And the verifier's own refusal: a length of zero.
    mmc_c.Fill.Payload.NumOfBytes = 0;
    MM_FillMemCmd(&mmc_c.Fill);
    S("mmc_fill_zero cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    // THE DEFECT, AND THE INPUT THAT ACTUALLY REACHES IT. The first attempt used an ODD MEM16
    // length, on the theory that mm_mem16's rounding would fail the fill -- but
    // MM_VerifyLoadDumpParams checks the SIZE's alignment too, so that is refused one level
    // earlier and counted correctly. What reaches the `else` is a PSP WRITE FAILURE:
    // MM_FillMem8 returns CFE_PSP_ERROR when a store is refused, and this handler's else then
    // moves the SUCCESS counter and sends NO EVENT. So the two numbers below are MM reporting a
    // half-finished fill as a command that worked.
    md_sim_fill();
    mmc_c.Fill.Payload.MemType = MM_MemType_MEM8;
    mmc_c.Fill.Payload.NumOfBytes = 16;
    md_sim_wfail_at = 70;
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_FillMemCmd(&mmc_c.Fill);
    md_sim_wfail_at = -1;
    S("mmc_fill_wfail cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S(" m69=");
    H2(md_sim_mem[69]);
    S(" m70=");
    H2(md_sim_mem[70]);
    S("\n");

    // --- MM_DumpMemToFileCmd then MM_LoadMemFromFileCmd, AS A ROUND TRIP. MEM8, so every
    // address is a window constant and both success events are comparable. The dump writes the
    // headers, the data, SEEKS BACK, computes the CRC over what it wrote and REWRITES the headers
    // -- and the load then verifies that same CRC. If either side of that disagreed about the
    // file layout the load would fail, which is why one test covers both.
    md_sim_fill();
    fs_len = 0;
    fs_pos = 0;
    fs_wr_left = -1;
    fs_noexist = 0;
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.DmpFile.Payload.MemType = MM_MemType_MEM8;
    mmc_c.DmpFile.Payload.NumOfBytes = 32;
    mmc_c.DmpFile.Payload.SrcSymAddress.Offset = MD_SIM_WINDOW_BASE;
    StrCpy(mmc_c.DmpFile.Payload.FileName, "/ram/rt.dmp");
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_DumpMemToFileCmd(&mmc_c.DmpFile);
    S("mmc_dmpfile cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S(" len=");
    D(fs_len);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" crc=");
    H2(fs_data[64 + 77]);
    H2(fs_data[64 + 76]);
    S("\n");
    // NOW LOAD IT BACK. The window is refilled with a different pattern first, so the bytes that
    // arrive say they came from the file.
    for (mmc_k = 0; mmc_k < MD_SIM_WINDOW_SIZE; mmc_k++) {
      md_sim_mem[mmc_k] = 0xE0;
    }
    es_stat_rc = OS_SUCCESS;
    es_stat_size = fs_len;
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    StrCpy(mmc_c.LdFile.Payload.FileName, "/ram/rt.dmp");
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_LoadMemFromFileCmd(&mmc_c.LdFile);
    S("mmc_ldfile cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S(" m0=");
    H2(md_sim_mem[0]);
    S(" m31=");
    H2(md_sim_mem[31]);
    S(" m32=");
    H2(md_sim_mem[32]);
    S("\n");
    // AND THE LOAD'S OWN REFUSALS: a file that will not open, and one whose CRC is wrong. The
    // second is the deepest error arm in MM -- seven checks in.
    fs_noexist = 1;
    MM_LoadMemFromFileCmd(&mmc_c.LdFile);
    fs_noexist = 0;
    S("mmc_ldfile_noopen ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    fs_data[64 + 76] ^= 0xFF; // corrupt the stored CRC
    MM_LoadMemFromFileCmd(&mmc_c.LdFile);
    fs_data[64 + 76] ^= 0xFF;
    S("mmc_ldfile_badcrc ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- MM_DumpInEventCmd. THE EVENT TEXT IS THE PAYLOAD: a 13-character header, five
    // characters per byte, and a tail with the address -- all built by repeated
    // CFE_SB_MessageStringGet into one 122-byte buffer. Eight bytes is 13 + 40 + 30 = 83
    // characters, comfortably inside; it is the one command where the formatter, the string-get
    // bound and the dump buffer are all in the same line.
    md_sim_fill();
    MemSet(&mmc_c, 0, sizeof(MM_AnyCmd_t));
    mmc_c.DmpEv.Payload.MemType = MM_MemType_MEM8;
    mmc_c.DmpEv.Payload.NumOfBytes = 8;
    mmc_c.DmpEv.Payload.SrcSymAddress.Offset = MD_SIM_WINDOW_BASE + 4;
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_DumpInEventCmd(&mmc_c.DmpEv);
    S("mmc_dmpev cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" bp=");
    D(MM_AppData.HkTlm.Payload.BytesProcessed);
    S("\n");
    // FIFTEEN BYTES IS THE MAXIMUM, and 16 is one past it -- the verifier's EVENT limit, which is
    // the narrowest in MM and the reason the constant exists.
    mmc_c.DmpEv.Payload.NumOfBytes = 15;
    MM_DumpInEventCmd(&mmc_c.DmpEv);
    mmc_c.DmpEv.Payload.NumOfBytes = 16;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_DumpInEventCmd(&mmc_c.DmpEv);
    S("mmc_dmpev_lim ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- mm_dispatch.c and mm_app.c -- MM'S FRONT DOOR AND ITS RUN LOOP ---------------------
    // The last two sources. ACYCLIC, unlike MD's pair: mm_app.c calls MM_TaskPipe and
    // mm_dispatch.c calls only mm_cmds.c and mm_utils.c, because MM_SendHkCmd lives in mm_cmds.c
    // rather than in the app. So the include order alone resolves them.
    //
    // MM_AppMain IS CALLED AFTER THE PIPE IT NEEDS IS ALREADY TAKEN, which is MD's lesson applied
    // rather than re-derived: the loop treats CFE_SB_TIME_OUT as "no action", so on a real pipe
    // with MM_INTERNAL_SB_TIMEOUT of 1000 ms nothing would ever end it. An AppInit that FAILS
    // sets APP_ERROR, and CFE_ES_RunLoop's first test -- on the caller's own RunStatus, before
    // any record lookup -- skips the loop entirely. Calling MM_AppInit directly first takes
    // MM_CMD_PIPE, so AppMain's CreatePipe refuses the duplicate.
    //
    // AND THE APP MUST BE A **CORE** APP FOR ExitApp TO RETURN. For a CORE app with APP_ERROR,
    // ExitApp REFUSES and logs `Cannot Exit CORE Application` -- that syslog line is the witness
    // that ExitApp was reached, because a zero exit count is also what "never called" looks like.

    // --- MM_AppInit, the success path. Five cFE calls and nothing else: MM registers no tables
    // and uses no CDS, which NASA says in four comments of its own. The HK MsgId is read back
    // OUT of the header, because CFE_MSG_Init is the only thing that puts it there.
    MemSet(&MM_AppData, 0xCC, sizeof(MM_AppData_t));
    MM_AppData.HkTlm.Payload.CommandCounter = 99;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 99;
    CFE_ES_Global.SystemState = CFE_ES_SystemState_CORE_READY;
    CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_CORE;
    es_set_ctx(1);
    mma_st = MM_AppInit();
    mma_mid = CFE_SB_InvalidMsgId();
    CFE_MSG_GetMsgId(&MM_AppData.HkTlm.TelemetryHeader.Msg, &mma_mid);
    S("mma_init st=");
    D(mma_st);
    S(" run=");
    D(MM_AppData.RunStatus);
    S(" pipe=");
    // CFE_RESOURCEID_TEST_DEFINED is a C macro over CFE_ResourceId_IsDefined; this port has the
    // function and the macro collapses onto it (check_header_inlines records the three such
    // collapses).
    D(CFE_ResourceId_IsDefined(MM_AppData.CmdPipe));
    S(" hkmid=0x");
    Hx4(CFE_SB_MsgIdToValue(mma_mid));
    S(" cc=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S(" la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S("\n");

    // --- MM_AppMain. The pipe name is taken, so AppInit's CreatePipe refuses and the loop never
    // runs. Three things to read: the pipe event, APP_ERROR in RunStatus, and ExitApp's refusal
    // in the syslog.
    mma_x0 = es_taskexits;
    MM_AppMain();
    S("mma_appmain exits=");
    D(es_taskexits - mma_x0);
    S(" run=");
    D(MM_AppData.RunStatus);
    S("\n");

    // --- MM_VerifyCmdLength, both ways. It counts the bad command ITSELF, which is why no
    // handler does -- a length failure never reaches one.
    MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
    CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(MM_CMD_MID),
                 sizeof(MM_NoopCmd_t));
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    // THE CALL IS HOISTED OUT OF THE PRINT, and it has to be: the bad-length call EMITS AN
    // EVENT, and C evaluates every printf argument before printing anything -- so on that half
    // the event lands BEFORE the line. A HolyC S()/D() chain prints as it goes, which would put
    // the event in the MIDDLE of the line. Third time this has bitten this driver; see
    // docs/CFS_PLAN.md.
    mma_ok = MM_VerifyCmdLength(&mma_b.CommandHeader.Msg, sizeof(MM_NoopCmd_t));
    S("mma_len ok=");
    D(mma_ok);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    mma_ok = MM_VerifyCmdLength(&mma_b.CommandHeader.Msg, 999);
    S("mma_len_bad ok=");
    D(mma_ok);
    S(" ec=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- MM_ProcessGroundCommand, ALL THIRTEEN CODES plus one that is not a code. The sizes come
    // from `sizeof` rather than being written out, because the switch's expected length IS a
    // sizeof and a hand-copied number would be a second opinion about the layout.
    //
    // Each command is sent with ZERO payload, so the ones that act on memory are refused by their
    // own validator -- and none of those refusals prints an address, which is what makes thirteen
    // commands in one loop comparable at all. The counters are the witness:
    // MM_ProcessGroundCommand returns void.
    mma_cc[0] = MM_NOOP_CC;               mma_sz[0] = sizeof(MM_NoopCmd_t);
    mma_cc[1] = MM_RESET_COUNTERS_CC;     mma_sz[1] = sizeof(MM_ResetCountersCmd_t);
    mma_cc[2] = MM_PEEK_CC;               mma_sz[2] = sizeof(MM_PeekCmd_t);
    mma_cc[3] = MM_POKE_CC;               mma_sz[3] = sizeof(MM_PokeCmd_t);
    mma_cc[4] = MM_LOAD_MEM_WID_CC;       mma_sz[4] = sizeof(MM_LoadMemWIDCmd_t);
    mma_cc[5] = MM_LOAD_MEM_FROM_FILE_CC; mma_sz[5] = sizeof(MM_LoadMemFromFileCmd_t);
    mma_cc[6] = MM_DUMP_MEM_TO_FILE_CC;   mma_sz[6] = sizeof(MM_DumpMemToFileCmd_t);
    mma_cc[7] = MM_DUMP_IN_EVENT_CC;      mma_sz[7] = sizeof(MM_DumpInEventCmd_t);
    mma_cc[8] = MM_FILL_MEM_CC;           mma_sz[8] = sizeof(MM_FillMemCmd_t);
    mma_cc[9] = MM_LOOKUP_SYM_CC;         mma_sz[9] = sizeof(MM_LookupSymCmd_t);
    mma_cc[10] = MM_SYM_TBL_TO_FILE_CC;   mma_sz[10] = sizeof(MM_SymTblToFileCmd_t);
    mma_cc[11] = MM_EEPROM_WRITE_ENA_CC;  mma_sz[11] = sizeof(MM_EepromWriteEnaCmd_t);
    mma_cc[12] = MM_EEPROM_WRITE_DIS_CC;  mma_sz[12] = sizeof(MM_EepromWriteDisCmd_t);
    // The load-from-file command opens a file; make the open FAIL so the branch it takes is the
    // one event rather than whatever fs_data happens to hold.
    fs_noexist = 1;
    mm_eep_lock_rc = CFE_PSP_SUCCESS;
    for (mma_k = 0; mma_k < 13; mma_k++) {
      MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
      CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(MM_CMD_MID), mma_sz[mma_k]);
      CFE_MSG_SetFcnCode(&mma_b.CommandHeader.Msg, mma_cc[mma_k]);
      MM_AppData.HkTlm.Payload.CommandCounter = 0;
      MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
      MM_ProcessGroundCommand(&mma_b);
      S("mma_cmd cc=");
      D(mma_cc[mma_k]);
      S(" len=");
      D(mma_sz[mma_k]);
      S(" ok=");
      D(MM_AppData.HkTlm.Payload.CommandCounter);
      S(" err=");
      D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
      S(" la=");
      D(MM_AppData.HkTlm.Payload.LastAction);
      S("\n");
    }
    fs_noexist = 0;
    // A CODE THAT IS NOT A CODE.
    MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
    CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(MM_CMD_MID),
                 sizeof(MM_NoopCmd_t));
    CFE_MSG_SetFcnCode(&mma_b.CommandHeader.Msg, 99);
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_ProcessGroundCommand(&mma_b);
    S("mma_cmd_badcc err=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // MM_ResetHk RUNS BEFORE THE CODE IS EVEN LOOKED AT, so a command whose LENGTH is wrong --
    // which no handler ever sees -- still clears the last action. The 7 below must be gone and
    // the counter must have moved.
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_FILL;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM32;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
    CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(MM_CMD_MID), 7);
    CFE_MSG_SetFcnCode(&mma_b.CommandHeader.Msg, MM_NOOP_CC);
    MM_ProcessGroundCommand(&mma_b);
    S("mma_resethk_first la=");
    D(MM_AppData.HkTlm.Payload.LastAction);
    S(" mt=");
    D(MM_AppData.HkTlm.Payload.MemType);
    S(" err=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    // --- MM_TaskPipe, all three routes. The MsgId cache is filled by the FIRST call; with it
    // unfilled every route falls through to the unknown-id arm, which is what makes the cache
    // load-bearing rather than an optimisation.
    MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
    CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(MM_CMD_MID),
                 sizeof(MM_NoopCmd_t));
    CFE_MSG_SetFcnCode(&mma_b.CommandHeader.Msg, MM_NOOP_CC);
    MM_AppData.HkTlm.Payload.CommandCounter = 0;
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_TaskPipe(&mma_b);
    S("mma_pipe_cmd ok=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" err=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    // THE HK ROUTE. MM_SendHkCmd does not move the counter, so the witness is the transmit --
    // the "No subscribers for MsgId 0x887" line below this one.
    MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
    CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(MM_SEND_HK_MID),
                 sizeof(MM_SendHkCmd_t));
    MM_AppData.HkTlm.Payload.CommandCounter = 44;
    MM_TaskPipe(&mma_b);
    S("mma_pipe_hk ok=");
    D(MM_AppData.HkTlm.Payload.CommandCounter);
    S(" err=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");
    MemSet(&mma_b, 0, sizeof(MM_LoadMemWIDCmd_t));
    CFE_MSG_Init(&mma_b.CommandHeader.Msg, CFE_SB_ValueToMsgId(0x1899), sizeof(MM_NoopCmd_t));
    MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;
    MM_TaskPipe(&mma_b);
    S("mma_pipe_badmid err=");
    D(MM_AppData.HkTlm.Payload.CommandErrorCounter);
    S("\n");

    cs_block_utils();
    cs_block_compute();
    cs_block_tblproc();
    cs_block_child();
    cs_block_init();
    cs_block_cmds();
    cs_block_eeprom_cmds();
    cs_block_memory_cmds();
    cs_block_table_cmds();
    cs_block_app_cmds();
    cs_block_dispatch();
    cs_block_app();

    // PUT THE APP TYPE BACK, which MD's block does and this one did not. Nothing after it today
    // but tim_objtab, so both halves agreed and the transcript was green -- but the NEXT app's
    // exercise goes in this same place and would inherit a CORE app and a CORE_READY system
    // state. "An EXTERNAL app's ExitApp does not return" is the hang that cost MD three steps to
    // find; leaving the flag set is how the next person finds it again. Changes no output, which
    // is the point.
    CFE_ES_Global.AppTable[1].Type = CFE_ES_AppType_EXTERNAL;
    CFE_ES_Global.SystemState = CFE_ES_SystemState_OPERATIONAL;

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
