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
  return 0;
}
