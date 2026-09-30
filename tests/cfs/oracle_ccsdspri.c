/* Differential-oracle driver for NASA cFE's CCSDS primary header accessors.
 *
 * Links the UNMODIFIED vendor/cFE/modules/msg/fsw/src/cfe_msg_ccsdspri.c and prints a transcript
 * of every accessor. The HolyC translation prints the same transcript, and the two must match
 * byte for byte -- which is the only way to tell a translation bug from a compiler bug, since
 * both look identical from the outside. */
#include <stdio.h>
#include "cfe_msg.h"
#include "cfe_sb.h"
#include "target_objtab.h"
#include "cfe_resourceid.h"
#include "cfe_resourceid_basevalue.h"

/* cfe_msg_objtab.c defines this and no header declares it -- the generated cfe_es_objtab.c is
 * what normally refers to it, by name, from the build system. */
extern const Target_ObjectTable_t CFE_MSG_ModuleEntry;
extern const Target_ObjectTable_t CFE_RESOURCEID_ModuleEntry;

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

    /* --- cfe_msg_objtab.c ------------------------------------------------------------- */
    /* One registration entry, no task. ES walks the collected table at every lifecycle phase,
     * so a port that skips these has modules that exist and never start. */
    printf("objtab %s %d %d %d %lu %lu\n", CFE_MSG_ModuleEntry.Name,
           (int)(CFE_MSG_ModuleEntry.EarlyInit == NULL), (int)(CFE_MSG_ModuleEntry.TaskMain == NULL),
           (int)(CFE_MSG_ModuleEntry.AppCleanupCb == NULL),
           (unsigned long)CFE_MSG_ModuleEntry.Priority, (unsigned long)CFE_MSG_ModuleEntry.StackSize);
    return 0;
}
