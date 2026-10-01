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

I32 CFE_ES_WriteToSysLog(U8 *Msg)
{
  S("syslog\n");
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
// cfe_msg_integrity.HC declares this and the harness supplies it -- the TIME module is not
// translated yet, and nothing under test depends on what the clock says. Same fixed values as
// the C oracle's stub.
CFE_TIME_SysTime CFE_TIME_GetTime()
{
  CFE_TIME_SysTime t;
  t.Seconds = 0x20304050;
  t.Subseconds = 0x60708090;
  return t;
}
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
U8 fs_data[256];
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
  return OS_SUCCESS;
}

I32 OS_MutSemTake(U32 sem_id)
{
  ++fs_mut_take;
  return OS_SUCCESS;
}

I32 OS_MutSemGive(U32 sem_id)
{
  ++fs_mut_give;
  return OS_SUCCESS;
}

I32 CFE_ES_GetAppID(U32 *AppIdPtr)
{
  *AppIdPtr = 0x4321;
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
  return 0;
}
