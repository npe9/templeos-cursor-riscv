// Differential oracle, HolyC side, for OSAL's console/printf module: drives the 1:1
// translation of osapi-printf.c and prints the same transcript as tests/osal/oracle_printf.c
// does against the unmodified C. See that file for why this is a SEPARATE, SCOPED gate: once
// osapi-printf.c is in the build, OS_printf is the real one and the main gate's fixed
// "bugcheck" marker stub cannot coexist with it. This driver never triggers a BUGCHECK.
// Standalone on purpose -- no kernel includes.
#include "/Kernel/Cfs/osal/os_shared_errors.HC"
// --- the four TempleOS primitives the KERNEL provides ------------------------------------------
// This harness is standalone by design -- no kernel is linked, because the only thing under test
// is the translation -- so MemSet, MemCpy, StrCmp and StrLen have to be supplied here. They are
// the kernel's, not C's, and the semantics are matched deliberately:
//
//   MemSet/MemCpy  RVMemSet(dst,dat,size) / RVMemCpy(dst,src,size) in Kernel/KCmpStubsRV.HC --
//                  C's argument order, returning dst.
//   StrCmp         _STRCMP in Kernel/StrA.HC:85 returns only -1, 0 or +1, NOT a byte
//                  difference. Reproduced exactly: if this returned a difference while the
//                  kernel returns +-1, the oracle would be validating behaviour that does not
//                  ship. Every cFS call site compares against zero, so the two agree there.
//   StrLen         RVStrLen.
//
// These names would otherwise resolve against the host C runtime (they are in
// bootstrap/holy_rt_names.h) and the blob's import trailer is what would catch that -- the gate
// asserts the trailer is empty for exactly this reason.
U8 *MemSet(U8 *dst, I64 dat, I64 size)
{
  I64 i = 0;
  while (i < size) {
    dst[i] = dat & 0xFF;
    i++;
  }
  return dst;
}

U8 *MemCpy(U8 *dst, U8 *src, I64 size)
{
  I64 i = 0;
  while (i < size) {
    dst[i] = src[i];
    i++;
  }
  return dst;
}

I64 StrLen(U8 *st)
{
  I64 n = 0;
  while (st[n])
    n++;
  return n;
}

I64 StrCmp(U8 *st1, U8 *st2)
{
  I64 i = 0;
  while (st2[i]) {
    if (st1[i] != st2[i]) {
      if (st2[i] > st1[i])
        return -1;
      return 1;
    }
    i++;
  }
  if (st1[i])
    return 1;
  return 0;
}
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
// OS_SharedGlobalVars, OS_NotifyEvent, OS_strnlen, OS_MAX_EVENT_HANDLER and
// OS_INIT_MAGIC_NUMBER all come from osapi_common.HC, which osapi_idmap.HC includes. An earlier
// draft of this file declared its own stand-ins for them, as the C oracle must, and they
// collided: HolyC has no separate compilation, so the include order already supplies them.
#include "/Kernel/Cfs/osal/osapi_errors.HC"
// The real backend calls osapi-idmap.c makes; no-ops, single-threaded transcript.
U0 OS_Lock_Global_Impl(U32 idtype)
{
}

U0 OS_Unlock_Global_Impl(U32 idtype)
{
}

U0 OS_WaitForStateChange_Impl(U32 idtype, U32 attempts)
{
}

U32 OS_TaskGetId_Impl()
{
  return 0x10001;
}

U32 OS_TaskGetId()
{
  return 0x10001;
}
#include "/Kernel/Cfs/osal/osapi_idmap.HC"
#include "/Kernel/Cfs/osal/os_shared_console.HC"
#include "/Kernel/Cfs/osal/osapi_printf.HC"
// --- the console backend ----------------------------------------------------------------------
// A real backend drains the ring from ReadPos to WritePos and pushes the bytes at the device.
// This one does the same, and can be told to STOP draining -- which is what a slow consumer
// looks like, and the only way to reach the ring-full path with a 17,300 byte buffer.
I64 stub_c_creates, stub_c_wakeups, stub_c_outputs, stub_c_drain, stub_c_drained;
U8 stub_c_last[64];
I32 OS_ConsoleCreate_Impl(OS_object_token_t *token)
{
  ++stub_c_creates;
  return OS_SUCCESS;
}

U0 OS_ConsoleWakeup_Impl(OS_object_token_t *token)
{
  ++stub_c_wakeups;
}

U0 OS_ConsoleOutput_Impl(OS_object_token_t *token)
{
  OS_console_internal_record_t *console;
  I64 n = 0;
  U8 ch;
  console = &OS_console_table[OS_ObjectIndexFromToken(token)];
  ++stub_c_outputs;
  if (!stub_c_drain)
    return;
  while (console->ReadPos != console->WritePos) {
    ch = console->BufBase[console->ReadPos];
    if (n < sizeof(stub_c_last) - 1)
      stub_c_last[n] = ch;
    ++n;
    ++stub_c_drained;
    ++console->ReadPos;
    if (console->ReadPos >= console->BufSize)
      console->ReadPos = 0;
  }
  if (n >= sizeof(stub_c_last))
    n = sizeof(stub_c_last) - 1;
  stub_c_last[n] = 0;
}

I64 main()
{
  OS_console_internal_record_t *c;
  U32 badid;
  I64 i, wp;
  I32 r;
  U8 big[400];
  stub_c_drain = 1;
  // OS_printf BEFORE init. GlobalState is not the magic number yet, so NASA routes the message
  // to OS_DEBUG -- a no-op unless OSAL_CONFIG_DEBUG_PRINTF is set, and it is not in this build.
  OS_printf("dropped before init\n");
  S("pre_init  outputs=");
  D(stub_c_outputs);
  S(" drained=");
  D(stub_c_drained);
  S("\n");
  OS_SharedGlobalVars.GlobalState = OS_INIT_MAGIC_NUMBER;
  OS_ObjectIdInit;
  r = OS_ConsoleAPI_Init;
  S("init      rc=");
  D(r);
  S(" creates=");
  D(stub_c_creates);
  S(" enabled=");
  D(OS_SharedGlobalVars.PrintfEnabled);
  S("\n");
  c = &OS_console_table[0];
  S("bufsize   ");
  D(c->BufSize);
  S(" async=");
  D(c->IsAsync);
  S(" name0=");
  D(c->device_name[0]);
  S("\n");
  // A formatted write. The BYTES are checked, not just the counters -- the point of routing
  // through the real ring buffer.
  OS_printf("hi %s %d %u\n", "there", -7, 42);
  S("write1    outputs=");
  D(stub_c_outputs);
  S(" drained=");
  D(stub_c_drained);
  S(" [");
  S(stub_c_last);
  S("]");
  S(" rd=");
  D(c->ReadPos);
  S(" wr=");
  D(c->WritePos);
  S(" ovf=");
  D(c->OverflowEvents);
  S("\n");
  // Disabled: PrintfEnabled gates at the top of OS_printf, so nothing reaches the ring.
  OS_printf_disable;
  OS_printf("must not appear\n");
  S("disabled  outputs=");
  D(stub_c_outputs);
  S(" drained=");
  D(stub_c_drained);
  S("\n");
  OS_printf_enable;
  OS_printf("back\n");
  S("enabled   outputs=");
  D(stub_c_outputs);
  S(" drained=");
  D(stub_c_drained);
  S(" [");
  S(stub_c_last);
  S("]\n");
  // A bad console id never reaches the ring.
  badid = 0x12345678;
  S("badid     rc=");
  D(OS_ConsoleWrite(badid, "x"));
  S("\n");
  // THE RING-FULL PATH. Stop draining, then write until a message does not fit. The property is
  // ALL-OR-NOTHING: on the failing write, OverflowEvents goes up and WritePos does NOT move, so
  // the ring holds whole messages only and never a truncated tail.
  //
  // 400, not 200: the ring is 17,300 bytes and each message is 71, so filling it takes about
  // 244 writes. At 200 the loop ran out FIRST and the overflow path was never reached.
  stub_c_drain = 0;
  i = 0;
  while (i < 400) {
    OS_printf("0123456789012345678901234567890123456789012345678901234567890123456789\n");
    if (c->OverflowEvents != 0)
      break;
    ++i;
  }
  S("fullat    i=");
  D(i);
  S(" ovf=");
  D(c->OverflowEvents);
  S("\n");
  wp = c->WritePos;
  OS_printf("0123456789012345678901234567890123456789012345678901234567890123456789\n");
  S("allornone wr_moved=");
  D(c->WritePos != wp);
  S(" ovf=");
  D(c->OverflowEvents);
  S("\n");
  // Drain it all, then confirm the ring is reusable and WRAPS: ReadPos and WritePos come back to
  // the same place only if the modular arithmetic in CopyOut is right.
  stub_c_drain = 1;
  OS_printf("drain\n");
  S("drained   rd_eq_wr=");
  D(c->ReadPos == c->WritePos);
  S(" total=");
  D(stub_c_drained);
  S("\n");
  OS_printf("after wrap %d\n", 99);
  S("postwrap  [");
  S(stub_c_last);
  S("] rd=");
  D(c->ReadPos);
  S(" wr=");
  D(c->WritePos);
  S("\n");
  // Truncation: OS_BUFFER_SIZE is 172, so a longer message is cut to 171 characters plus a NUL.
  // The count is what proves the cut, and it is NASA's constant doing it.
  MemSet(big, 'A', sizeof(big) - 1);
  big[sizeof(big) - 1] = 0;
  stub_c_drained = 0;
  OS_printf("%s", big);
  S("truncate  drained=");
  D(stub_c_drained);
  S("\n");
  S("done\n");
  return 0;
}
