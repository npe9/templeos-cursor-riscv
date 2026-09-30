/* Differential-oracle driver for the OSAL PORTABLE layer.
 *
 * Same shape as tests/cfs/oracle_ccsdspri.c: link NASA's unmodified sources, print a transcript,
 * and require the HolyC translation to print it byte for byte.
 *
 * WHAT MAKES THIS LAYER TESTABLE WITHOUT AN OS. src/os/shared/src makes zero direct OS calls --
 * no pthread, no sem, no open/read/write, no malloc. Its job is validation, id mapping and
 * dispatch to 128 OS_*_Impl functions a backend supplies. So a RECORDING STUB backend is enough
 * to exercise it, and the transcript then asserts the dispatch decisions, which is the layer's
 * whole contract. No tasks, no hardware, no scheduler. */
#include <stdio.h>
#include "osapi.h"
#include "os-shared-errors.h"
#include "osapi-version.h"
#include "os-shared-clock.h"
#include "os-shared-heap.h"

/* The backend's error-name table. A bare-metal target contributes no OS-specific errors, so
 * this is empty -- and empty is the interesting case, because it is the one that makes
 * OS_GetErrorName fall through both tables to its OS_UNKNOWN() path. */
const OS_ErrorTable_Entry_t OS_IMPL_ERROR_NAME_TABLE[] = {{0, NULL}};

/* OSAL's BUGCHECK macro logs through OS_printf before returning:
 *     BUGREPORT("\n**BUG** %s():%d:check '%s' FAILED --> %s\n\n", __func__, __LINE__, ...)
 * using __func__, __LINE__ and stringified macro arguments, none of which HolyC has. So the
 * translation keeps the CHECK and the RETURN and does not reproduce the wording, and this stub
 * prints a fixed marker on both sides. What the transcript then pins is WHICH CHECKS FIRE,
 * which is the behaviour; the message text is C preprocessor machinery.
 *
 * osapi-printf.c is itself part of the shared layer and will be translated later; until then
 * this stub stands in for it. */
void OS_printf(const char *fmt, ...)
{
    (void)fmt;
    printf("bugcheck\n");
}

/* THE RECORDING STUB BACKEND. This is what makes the portable layer testable with no OS: the
 * clock returns a fixed, made-up time and the heap fixed numbers, so the transcript below
 * asserts the layer's VALIDATION AND DISPATCH -- which argument checks fire, which _Impl gets
 * called, what it does with the result -- rather than anything about a real clock. A real clock
 * would make the transcript unreproducible, which is the opposite of what a gate needs. */
static int stub_setlocal_calls;

int32 OS_GetMonotonicTime_Impl(OS_time_t *time_struct)
{
    time_struct->ticks = 1234500000; /* 123.45 s at 100 ns per tick */
    return OS_SUCCESS;
}

int32 OS_GetLocalTime_Impl(OS_time_t *time_struct)
{
    time_struct->ticks = 500000000; /* 50 s */
    return OS_SUCCESS;
}

int32 OS_SetLocalTime_Impl(const OS_time_t *time_struct)
{
    ++stub_setlocal_calls;
    return OS_SUCCESS;
}

int32 OS_HeapGetInfo_Impl(OS_heap_prop_t *heap_prop)
{
    heap_prop->free_bytes         = 4096;
    heap_prop->free_blocks        = 7;
    heap_prop->largest_free_block = 2048;
    return OS_SUCCESS;
}

int main(void)
{
    os_err_name_t      nm;
    os_status_string_t st;

    /* A code near the front of the table, one past every gap in it (-20 to -27, -38 to -40,
     * -44 to -103), and one that is in neither table. The gaps matter: the lookup walks a list
     * rather than indexing, so a translation that "helpfully" indexed by value would pass the
     * first case and fail the second. */
    printf("known   rc=%d [%s]\n", (int)OS_GetErrorName(OS_ERR_NAME_TAKEN, &nm), nm);
    printf("gap     rc=%d [%s]\n", (int)OS_GetErrorName(OS_FS_ERR_PATH_INVALID, &nm), nm);
    printf("first   rc=%d [%s]\n", (int)OS_GetErrorName(OS_SUCCESS, &nm), nm);
    printf("last    rc=%d [%s]\n", (int)OS_GetErrorName(OS_ERR_INVALID_ARGUMENT, &nm), nm);
    printf("unknown rc=%d [%s]\n", (int)OS_GetErrorName(-999, &nm), nm);
    /* A code that EXISTS in osapi-error.h but is deliberately absent from the name table --
     * OS_ERR_TRY_AGAIN (-43) and OS_ERR_EMPTY_SET (-44) are not listed. Proving that is a
     * property of NASA's table, not an oversight in the translation. */
    printf("nottbl  rc=%d [%s]\n", (int)OS_GetErrorName(OS_ERR_TRY_AGAIN, &nm), nm);
    printf("null    rc=%d\n", (int)OS_GetErrorName(OS_ERROR, NULL));

    printf("status  [%s]\n", OS_StatusToString(-42, &st));
    printf("status0 [%s]\n", OS_StatusToString(0, &st));
    printf("statusn [%d]\n", (int)(OS_StatusToString(-1, NULL) == NULL));

    /* --- osapi-version.c ------------------------------------------------------------- */
    {
        uint8 vn[4];
        OS_GetVersionNumber(vn);
        printf("ver     [%s]\n", OS_GetVersionString());
        printf("codename[%s]\n", OS_GetVersionCodeName());
        printf("vernum  %d.%d.%d.%d\n", vn[0], vn[1], vn[2], vn[3]);
        printf("build   %lu\n", (unsigned long)OS_GetBuildNumber());
    }

    /* --- osapi-clock.c --------------------------------------------------------------- */
    {
        OS_time_t      t;
        OS_heap_prop_t hp;

        t.ticks = 0;
        printf("mono    rc=%d ticks=%ld\n", (int)OS_GetMonotonicTime(&t), (long)t.ticks);
        t.ticks = 0;
        printf("local   rc=%d ticks=%ld\n", (int)OS_GetLocalTime(&t), (long)t.ticks);
        printf("setloc  rc=%d n=%d\n", (int)OS_SetLocalTime(&t), stub_setlocal_calls);
        printf("clknull %d %d %d\n", (int)OS_GetMonotonicTime(NULL), (int)OS_GetLocalTime(NULL),
               (int)OS_SetLocalTime(NULL));

        /* The three branches of FromRelativeMilliseconds: poll, a real delay measured from the
         * stub clock, and the indefinite-block sentinel. */
        printf("rel0    %ld\n", (long)OS_TimeFromRelativeMilliseconds(OS_CHECK).ticks);
        printf("rel100  %ld\n", (long)OS_TimeFromRelativeMilliseconds(100).ticks);
        printf("relneg  %ld\n", (long)OS_TimeFromRelativeMilliseconds(-5).ticks);

        /* And back. A time in the past collapses to OS_CHECK; OS_TIME_MAX stays a block. */
        t.ticks = 0;
        printf("torel0  %d\n", (int)OS_TimeToRelativeMilliseconds(t));
        t = OS_TIME_MAX;
        printf("torelmx %d\n", (int)OS_TimeToRelativeMilliseconds(t));
        t.ticks = 500000000 + (250 * OS_TIME_TICKS_PER_MSEC); /* 250 ms past the stub clock */
        printf("torel250 %d\n", (int)OS_TimeToRelativeMilliseconds(t));

        /* The arithmetic helpers, which are where a tick-rate mistake would show. */
        printf("ticks   %d %d\n", (int)OS_TIME_TICKS_PER_MSEC, (int)OS_TIME_TICKS_PER_SECOND);
        printf("sign    %d %d %d\n", OS_TimeGetSign(OS_TimeFromTotalMilliseconds(5)),
               OS_TimeGetSign(OS_TimeFromTotalMilliseconds(0)),
               OS_TimeGetSign(OS_TimeFromTotalMilliseconds(-5)));
        printf("addsub  %ld %ld\n",
               (long)OS_TimeAdd(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(4)).ticks,
               (long)OS_TimeSubtract(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(4)).ticks);
        printf("cmp     %d %d\n", OS_TimeCompare(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(4)),
               (int)OS_TimeEqual(OS_TimeFromTotalMilliseconds(3), OS_TimeFromTotalMilliseconds(3)));

        /* --- osapi-heap.c ------------------------------------------------------------ */
        hp.free_bytes = 0;
        printf("heap    rc=%d %ld %ld %ld\n", (int)OS_HeapGetInfo(&hp), (long)hp.free_bytes,
               (long)hp.free_blocks, (long)hp.largest_free_block);
        printf("heapnull %d\n", (int)OS_HeapGetInfo(NULL));
    }
    return 0;
}
