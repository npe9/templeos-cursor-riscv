// Differential oracle, HolyC side: drives the 1:1 translation of OSAL's portable error module
// and prints the same transcript as tests/osal/oracle_osal.c does against the unmodified C.
// Standalone on purpose -- no kernel includes -- so the only things under test are the
// translation and the compiler.
#include "/Kernel/Cfs/osal/os_shared_errors.HC"
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

// The backend's error-name table, empty as a bare-metal target's is. It must be defined BEFORE
// the portable layer that walks it -- see os_shared_errors.HC for why include order does a
// linker's job here.
OS_ErrorTable_Entry OS_IMPL_ERROR_NAME_TABLE[1] = {{0, NULL}};

// Stands in for osapi-printf.c, which is part of the shared layer and not translated yet. The C
// oracle's stub prints the same fixed marker: what the transcript pins is which checks fire.
U0 OS_printf(U8 *fmt)
{
  S("bugcheck\n");
}

#include "/Kernel/Cfs/osal/osapi_errors.HC"
#include "/Kernel/Cfs/osal/osapi_version.HC"
#include "/Kernel/Cfs/osal/osapi_clock.HC"
#include "/Kernel/Cfs/osal/osapi_heap.HC"

// THE RECORDING STUB BACKEND, matching the C oracle's. A fixed, made-up clock and fixed heap
// numbers, so the transcript asserts the portable layer's validation and dispatch rather than
// anything about a real clock -- a real one would make the transcript unreproducible, which is
// the opposite of what a gate needs.
I64 stub_setlocal_calls;

I32 OS_GetMonotonicTime_Impl(OS_time_t *time_struct)
{
  time_struct->ticks = 1234500000; // 123.45 s at 100 ns per tick
  return OS_SUCCESS;
}

I32 OS_GetLocalTime_Impl(OS_time_t *time_struct)
{
  time_struct->ticks = 500000000; // 50 s
  return OS_SUCCESS;
}

I32 OS_SetLocalTime_Impl(OS_time_t *time_struct)
{
  ++stub_setlocal_calls;
  return OS_SUCCESS;
}

I32 OS_HeapGetInfo_Impl(OS_heap_prop_t *heap_prop)
{
  heap_prop->free_bytes = 4096;
  heap_prop->free_blocks = 7;
  heap_prop->largest_free_block = 2048;
  return OS_SUCCESS;
}

U0 Nm(U8 *label, I32 rc, U8 *nm)
{
  S(label);
  S(" rc=");
  D(rc);
  S(" [");
  S(nm);
  S("]\n");
}

I64 main()
{
  U8 nm[OS_ERROR_NAME_LENGTH];
  U8 st[OS_STATUS_STRING_LENGTH];
  I32 rc;
  // Hoisted, because the C evaluates printf's arguments before printf emits anything and the
  // NULL case LOGS -- inline, the marker would land in the middle of its own line.
  rc = OS_GetErrorName(OS_ERR_NAME_TAKEN, nm);
  Nm("known  ", rc, nm);
  rc = OS_GetErrorName(OS_FS_ERR_PATH_INVALID, nm);
  Nm("gap    ", rc, nm);
  rc = OS_GetErrorName(OS_SUCCESS, nm);
  Nm("first  ", rc, nm);
  rc = OS_GetErrorName(OS_ERR_INVALID_ARGUMENT, nm);
  Nm("last   ", rc, nm);
  rc = OS_GetErrorName(-999, nm);
  Nm("unknown", rc, nm);
  // OS_ERR_TRY_AGAIN exists in osapi-error.h and is deliberately NOT in the name table.
  rc = OS_GetErrorName(OS_ERR_TRY_AGAIN, nm);
  Nm("nottbl ", rc, nm);
  rc = OS_GetErrorName(OS_ERROR, NULL);
  S("null    rc=");
  D(rc);
  S("\n");
  S("status  [");
  S(OS_StatusToString(-42, st));
  S("]\n");
  S("status0 [");
  S(OS_StatusToString(0, st));
  S("]\n");
  S("statusn [");
  D(OS_StatusToString(-1, NULL) == NULL);
  S("]\n");
  // --- osapi-version.c ---------------------------------------------------------------
  {
    U8 vn[4];
    OS_GetVersionNumber(vn);
    S("ver     [");
    S(OS_GetVersionString);
    S("]\n");
    S("codename[");
    S(OS_GetVersionCodeName);
    S("]\n");
    S("vernum  ");
    D(vn[0]);
    S(".");
    D(vn[1]);
    S(".");
    D(vn[2]);
    S(".");
    D(vn[3]);
    S("\n");
    S("build   ");
    D(OS_GetBuildNumber);
    S("\n");
  }

  // --- osapi-clock.c -----------------------------------------------------------------
  {
    OS_time_t t, a, b, r;
    OS_heap_prop_t hp;
    I32 r1, r2, r3;
    t.ticks = 0;
    rc = OS_GetMonotonicTime(&t);
    S("mono    rc=");
    D(rc);
    S(" ticks=");
    D(t.ticks);
    S("\n");
    t.ticks = 0;
    rc = OS_GetLocalTime(&t);
    S("local   rc=");
    D(rc);
    S(" ticks=");
    D(t.ticks);
    S("\n");
    rc = OS_SetLocalTime(&t);
    S("setloc  rc=");
    D(rc);
    S(" n=");
    D(stub_setlocal_calls);
    S("\n");
    // Hoisted: all three log, and C evaluates every printf argument before printing anything,
    // so the three markers come BEFORE the line rather than inside it.
    r1 = OS_GetMonotonicTime(NULL);
    r2 = OS_GetLocalTime(NULL);
    r3 = OS_SetLocalTime(NULL);
    S("clknull ");
    D(r1);
    S(" ");
    D(r2);
    S(" ");
    D(r3);
    S("\n");
    // The three branches of FromRelativeMilliseconds: poll, a real delay measured from the stub
    // clock, and the indefinite-block sentinel.
    r = OS_TimeFromRelativeMilliseconds(OS_CHECK);
    S("rel0    ");
    D(r.ticks);
    S("\n");
    r = OS_TimeFromRelativeMilliseconds(100);
    S("rel100  ");
    D(r.ticks);
    S("\n");
    r = OS_TimeFromRelativeMilliseconds(-5);
    S("relneg  ");
    D(r.ticks);
    S("\n");
    t.ticks = 0;
    S("torel0  ");
    D(OS_TimeToRelativeMilliseconds(t));
    S("\n");
    t = OS_TimeMax;
    S("torelmx ");
    D(OS_TimeToRelativeMilliseconds(t));
    S("\n");
    t.ticks = 500000000 + 250 * OS_TIME_TICKS_PER_MSEC; // 250 ms past the stub clock
    S("torel250 ");
    D(OS_TimeToRelativeMilliseconds(t));
    S("\n");
    S("ticks   ");
    D(OS_TIME_TICKS_PER_MSEC);
    S(" ");
    D(OS_TIME_TICKS_PER_SECOND);
    S("\n");
    S("sign    ");
    D(OS_TimeGetSign(OS_TimeFromTotalMilliseconds(5)));
    S(" ");
    D(OS_TimeGetSign(OS_TimeFromTotalMilliseconds(0)));
    S(" ");
    D(OS_TimeGetSign(OS_TimeFromTotalMilliseconds(-5)));
    S("\n");
    a = OS_TimeFromTotalMilliseconds(3);
    b = OS_TimeFromTotalMilliseconds(4);
    r = OS_TimeAdd(a, b);
    S("addsub  ");
    D(r.ticks);
    S(" ");
    r = OS_TimeSubtract(a, b);
    D(r.ticks);
    S("\n");
    S("cmp     ");
    D(OS_TimeCompare(a, b));
    S(" ");
    D(OS_TimeEqual(a, a));
    S("\n");
    // --- osapi-heap.c ----------------------------------------------------------------
    hp.free_bytes = 0;
    rc = OS_HeapGetInfo(&hp);
    S("heap    rc=");
    D(rc);
    S(" ");
    D(hp.free_bytes);
    S(" ");
    D(hp.free_blocks);
    S(" ");
    D(hp.largest_free_block);
    S("\n");
    rc = OS_HeapGetInfo(NULL);
    S("heapnull ");
    D(rc);
    S("\n");
  }
  return 0;
}
