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
    return 0;
}
