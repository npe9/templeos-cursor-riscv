// Differential oracle, HolyC side: drives the 1:1 translation of NASA cFE's CCSDS primary header
// accessors and prints the same transcript as tests/cfs/oracle_ccsdspri.c does against the
// unmodified C. The gate diffs the two. Standalone on purpose -- no kernel includes -- so the
// only thing under test is the translation and the compiler.
#include "/Kernel/Cfs/cfe/cfe_msg_ccsdspri.HC"
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

I64 main()
{
  CFE_MSG_Message msg;
  U16 ver, apid, seq;
  I64 type, segf, size;
  Bool hassec;
  I64 i;
  U8 *p = &msg;
  for (i = 0; i < sizeof(CFE_MSG_Message); i++)
    p[i] = 0;
  Dump("zero", &msg);

  Rc("setver  ", CFE_MSG_SetHeaderVersion(&msg, 1));
  Dump("afterver", &msg);
  S("getver   rc=");
  D(CFE_MSG_GetHeaderVersion(&msg, &ver));
  S(" v=");
  D(ver);
  S("\n");

  Rc("settype ", CFE_MSG_SetType(&msg, CFE_MSG_Type_Cmd));
  Dump("aftertype", &msg);
  S("gettype  rc=");
  D(CFE_MSG_GetType(&msg, &type));
  S(" t=");
  D(type);
  S("\n");

  Rc("setapid ", CFE_MSG_SetApId(&msg, 0x1AB));
  Dump("afterapid", &msg);
  S("getapid  rc=");
  D(CFE_MSG_GetApId(&msg, &apid));
  S(" a=");
  D(apid);
  S("\n");

  Rc("setsec  ", CFE_MSG_SetHasSecondaryHeader(&msg, TRUE));
  S("getsec   rc=");
  D(CFE_MSG_GetHasSecondaryHeader(&msg, &hassec));
  S(" s=");
  D(hassec);
  S("\n");
  Dump("aftersec", &msg);

  Rc("setseg  ", CFE_MSG_SetSegmentationFlag(&msg, CFE_MSG_SegFlag_Unsegmented));
  S("getseg   rc=");
  D(CFE_MSG_GetSegmentationFlag(&msg, &segf));
  S(" g=");
  D(segf);
  S("\n");

  Rc("setseq  ", CFE_MSG_SetSequenceCount(&msg, 0x2345));
  S("getseq   rc=");
  D(CFE_MSG_GetSequenceCount(&msg, &seq));
  S(" q=");
  D(seq);
  S("\n");
  Dump("afterseq", &msg);

  Rc("setsize ", CFE_MSG_SetSize(&msg, 0x100));
  S("getsize  rc=");
  D(CFE_MSG_GetSize(&msg, &size));
  S(" z=");
  D(size);
  S("\n");
  Dump("aftersize", &msg);

  Rc("badver  ", CFE_MSG_SetHeaderVersion(&msg, 0xFF));
  Rc("badapid ", CFE_MSG_SetApId(&msg, 0xFFFF));
  Rc("badnull ", CFE_MSG_GetType(NULL, &type));
  Rc("badsize ", CFE_MSG_SetSize(&msg, 0));
  Dump("final", &msg);
  return 0;
}
