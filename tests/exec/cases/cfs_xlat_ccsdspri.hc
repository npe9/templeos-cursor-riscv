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
