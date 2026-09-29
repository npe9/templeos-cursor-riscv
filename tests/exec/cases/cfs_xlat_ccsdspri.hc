// Differential oracle, HolyC side: drives the 1:1 translation of NASA cFE's CCSDS primary header
// accessors and prints the same transcript as tests/cfs/oracle_ccsdspri.c does against the
// unmodified C. The gate diffs the two. Standalone on purpose -- no kernel includes -- so the
// only thing under test is the translation and the compiler.
#include "/Kernel/Cfs/cfe/cfe_msg_msgid_v1.HC"
#include "/Kernel/Cfs/cfe/cfe_msg_sechdr_fc.HC"
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
  return 0;
}
