// Differential oracle, HolyC side: drives the 1:1 translation of NASA cFE's CCSDS primary header
// accessors and prints the same transcript as tests/cfs/oracle_ccsdspri.c does against the
// unmodified C. The gate diffs the two. Standalone on purpose -- no kernel includes -- so the
// only thing under test is the translation and the compiler.
#include "/Kernel/Cfs/cfe/cfe_msg_msgid_v1.HC"
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
    D(((CFE_RESOURCEID_MAX + 1) & CFE_RESOURCEID_MAX) == 0);
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
    D(CFE_ResourceId_ToInteger(CFE_ResourceId_FindNext(
        CFE_ResourceId_FromInteger(base + CFE_RESOURCEID_MAX - 1), 4, &rid_in_use)));
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
    Hx2("topic_glob c=", CFE_SB_GlobalCmdTopicIdToMsgId(5), " t=",
        CFE_SB_GlobalTlmTopicIdToMsgId(5));
    Hx2("topic_locl c=", CFE_SB_LocalCmdTopicIdToMsgId(5), " t=",
        CFE_SB_LocalTlmTopicIdToMsgId(5));
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
    D((1024 & (1024 - 1)) == 0);
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
  return 0;
}
