/* Differential-oracle driver for NASA cFE's CCSDS primary header accessors.
 *
 * Links the UNMODIFIED vendor/cFE/modules/msg/fsw/src/cfe_msg_ccsdspri.c and prints a transcript
 * of every accessor. The HolyC translation prints the same transcript, and the two must match
 * byte for byte -- which is the only way to tell a translation bug from a compiler bug, since
 * both look identical from the outside. */
#include <stdio.h>
#include "cfe_msg.h"
#include "cfe_sb.h"

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
    return 0;
}
