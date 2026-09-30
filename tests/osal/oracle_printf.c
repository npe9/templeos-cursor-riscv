/* Differential oracle for the OSAL console/printf module, osapi-printf.c.
 *
 * WHY THIS IS A SEPARATE GATE FROM oracle_osal.c, and not another section of it.
 *
 * The main OSAL gate stubs OS_printf, printing a fixed "bugcheck" marker, because OSAL's
 * BUGCHECK macro logs through it:
 *
 *     BUGREPORT("\n**BUG** %s():%d:check '%s' FAILED --> %s\n\n",
 *               __func__, __LINE__, #cond, #errcode)
 *
 * and HolyC has no __func__, no __LINE__ and no stringification. The translation keeps the check
 * and the return and does not reproduce the wording. That marker is load-bearing: it is what
 * distinguishes a BUGCHECK (which logs) from an ARGCHECK (which is silent) when both return a
 * code, and a negative control on exactly that distinction has fired before.
 *
 * Once osapi-printf.c is IN the build, OS_printf is NASA's real one and that stub cannot exist --
 * one definition per program. The C side would then emit the full **BUG** text where the HolyC
 * side emits nothing comparable, and every marker line would diverge for a reason that is about
 * the C preprocessor rather than about the translation.
 *
 * So this gate is SCOPED: it links osapi-printf.c and osapi-idmap.c and drives the console ring
 * buffer directly, and its driver never triggers a BUGCHECK. The main gate keeps its markers and
 * its stub. Neither gate pretends to cover what the other does.
 *
 * In particular this driver never calls OS_printf(NULL): BUGCHECK_VOID would call BUGREPORT,
 * which calls OS_printf, which is the very thing under test -- it would print the untranslatable
 * text and recurse into it.
 */
#include <stdio.h>
#include <string.h>
#include "osapi.h"
#include "os-shared-errors.h"
#include "os-shared-idmap.h"
#include "os-shared-common.h"
#include "os-shared-printf.h"
#include "os-shared-console.h"

/* OS_ConsoleWrite is defined in osapi-printf.c with external linkage, under a banner comment
 * that reads "PUBLIC API (application-callable functions)", and is declared in NO NASA header --
 * checked across the whole of src/os. So a caller has to write its own prototype, which is what
 * this is. Recorded in docs/CFS_UPSTREAM_NOTES.md; reproduced, not fixed. */
int32 OS_ConsoleWrite(osal_id_t console_id, const char *Str);

OS_SharedGlobalVars_t OS_SharedGlobalVars;

const OS_ErrorTable_Entry_t OS_IMPL_ERROR_NAME_TABLE[] = {{0, NULL}};

int32 OS_NotifyEvent(OS_Event_t event, osal_id_t object_id, void *data)
{
    return OS_SUCCESS;
}

size_t OS_strnlen(const char *s, size_t maxlen)
{
    const char *end = (const char *)memchr(s, 0, maxlen);
    if (end != NULL)
    {
        maxlen = end - s;
    }
    return maxlen;
}

void      OS_Lock_Global_Impl(osal_objtype_t idtype) {}
void      OS_Unlock_Global_Impl(osal_objtype_t idtype) {}
void      OS_WaitForStateChange_Impl(osal_objtype_t idtype, uint32 attempts) {}
osal_id_t OS_TaskGetId_Impl(void) { return OS_ObjectIdFromInteger(0x10001); }
osal_id_t OS_TaskGetId(void) { return OS_ObjectIdFromInteger(0x10001); }

/* --- the console backend ----------------------------------------------------------------------
 * A real backend drains the ring from ReadPos to WritePos and pushes the bytes at the device.
 * This one does the same, and can be told to STOP draining -- which is what a slow consumer
 * looks like, and the only way to reach the ring-full path with a 17,300 byte buffer.
 */
static int    stub_c_creates;
static int    stub_c_wakeups;
static int    stub_c_outputs;
static int    stub_c_drain = 1;
static long   stub_c_drained;      /* total bytes taken out of the ring */
static char   stub_c_last[64];     /* the tail of the last drain, so the BYTES are checked */

int32 OS_ConsoleCreate_Impl(const OS_object_token_t *token)
{
    ++stub_c_creates;
    return OS_SUCCESS;
}

void OS_ConsoleWakeup_Impl(const OS_object_token_t *token)
{
    ++stub_c_wakeups;
}

void OS_ConsoleOutput_Impl(const OS_object_token_t *token)
{
    OS_console_internal_record_t *console = OS_OBJECT_TABLE_GET(OS_console_table, *token);
    size_t                        n = 0;

    ++stub_c_outputs;
    if (!stub_c_drain)
    {
        return;
    }
    while (console->ReadPos != console->WritePos)
    {
        char ch = console->BufBase[console->ReadPos];
        if (n < sizeof(stub_c_last) - 1)
        {
            stub_c_last[n] = ch;
        }
        ++n;
        ++stub_c_drained;
        ++console->ReadPos;
        if (console->ReadPos >= console->BufSize)
        {
            console->ReadPos = 0;
        }
    }
    if (n >= sizeof(stub_c_last))
    {
        n = sizeof(stub_c_last) - 1;
    }
    stub_c_last[n] = 0;
}

static OS_console_internal_record_t *the_console(void)
{
    return &OS_console_table[0];
}

int main(void)
{
    OS_console_internal_record_t *c;
    osal_id_t                     badid;
    int                           i;

    /* OS_printf BEFORE init. GlobalState is not the magic number yet, so NASA routes the
     * message to OS_DEBUG -- a no-op unless OSAL_CONFIG_DEBUG_PRINTF is set, and it is not in
     * this build. Nothing is written and nothing is output. */
    OS_printf("dropped before init\n");
    printf("pre_init  outputs=%d drained=%ld\n", stub_c_outputs, stub_c_drained);

    OS_SharedGlobalVars.GlobalState = OS_INIT_MAGIC_NUMBER;
    OS_ObjectIdInit();
    printf("init      rc=%d creates=%d enabled=%d\n", (int)OS_ConsoleAPI_Init(), stub_c_creates,
           (int)OS_SharedGlobalVars.PrintfEnabled);
    c = the_console();
    printf("bufsize   %ld async=%d name0=%d\n", (long)c->BufSize, (int)c->IsAsync,
           (int)c->device_name[0]);

    /* A formatted write. The bytes are checked, not just the counters -- this is the whole
     * point of routing through the real ring buffer. */
    OS_printf("hi %s %d %u\n", "there", -7, 42u);
    printf("write1    outputs=%d drained=%ld [%s]", stub_c_outputs, stub_c_drained, stub_c_last);
    printf(" rd=%ld wr=%ld ovf=%lu\n", (long)c->ReadPos, (long)c->WritePos,
           (unsigned long)c->OverflowEvents);

    /* Disabled: PrintfEnabled gates at the top of OS_printf, so nothing reaches the ring. */
    OS_printf_disable();
    OS_printf("must not appear\n");
    printf("disabled  outputs=%d drained=%ld\n", stub_c_outputs, stub_c_drained);
    OS_printf_enable();
    OS_printf("back\n");
    printf("enabled   outputs=%d drained=%ld [%s]\n", stub_c_outputs, stub_c_drained,
           stub_c_last);

    /* A bad console id never reaches the ring. */
    badid = OS_ObjectIdFromInteger(0x12345678);
    printf("badid     rc=%d\n", (int)OS_ConsoleWrite(badid, "x"));

    /* THE RING-FULL PATH. Stop draining, then write until a message does not fit. The property
     * is ALL-OR-NOTHING: on the failing write, OverflowEvents goes up and WritePos does NOT
     * move, so the ring holds whole messages only and never a truncated tail.
     *
     * NASA enforces that twice over -- CopyOut does not update NextWritePos on the full path,
     * AND ConsoleWrite commits WritePos only on success -- so breaking either one alone leaves
     * this transcript unchanged. Breaking both does change it, which is how the coverage was
     * confirmed. */
    stub_c_drain = 0;
    /* 400, not 200: the ring is 17,300 bytes and each message is 71, so filling it takes about
     * 244 writes. At 200 the loop ran out FIRST and the overflow path was never reached -- the
     * transcript said ovf=0 and the all-or-nothing check below it was measuring nothing. A
     * control that cannot fire is worse than no control, so the bound is derived from the
     * buffer size rather than picked. */
    for (i = 0; i < 400; ++i)
    {
        OS_printf("0123456789012345678901234567890123456789012345678901234567890123456789\n");
        if (c->OverflowEvents != 0)
        {
            break;
        }
    }
    printf("fullat    i=%d ovf=%lu\n", i, (unsigned long)c->OverflowEvents);
    {
        size_t wp = c->WritePos;
        OS_printf("0123456789012345678901234567890123456789012345678901234567890123456789\n");
        printf("allornone wr_moved=%d ovf=%lu\n", (int)(c->WritePos != wp),
               (unsigned long)c->OverflowEvents);
    }

    /* Drain it all, then confirm the ring is reusable and WRAPS: ReadPos and WritePos come back
     * to the same place only if the modular arithmetic in CopyOut is right. */
    stub_c_drain = 1;
    OS_printf("drain\n");
    printf("drained   rd_eq_wr=%d total=%ld\n", (int)(c->ReadPos == c->WritePos), stub_c_drained);
    OS_printf("after wrap %d\n", 99);
    printf("postwrap  [%s] rd=%ld wr=%ld\n", stub_c_last, (long)c->ReadPos, (long)c->WritePos);

    /* Truncation: OS_BUFFER_SIZE is 172, so a longer message is cut to 171 characters plus a
     * NUL. The count is what proves the cut, and it is NASA's constant doing it. */
    {
        char big[400];
        memset(big, 'A', sizeof(big) - 1);
        big[sizeof(big) - 1] = 0;
        stub_c_drained = 0;
        OS_printf("%s", big);
        printf("truncate  drained=%ld\n", stub_c_drained);
    }
    printf("done\n");
    return 0;
}
