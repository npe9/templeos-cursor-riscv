// Thin-only stubs for SerialDev symbols still referenced after MakeSerialDev is gated.
// SoftCall FifoSoft owns FifoU8/I64 in Kernel.BIN (→'SF'); Serial body empty here.
// InputFilterTask wall: Job servant spawn path — keep stub; do not SoftCall Serial yet.
#ifndef K_THIN_SERIAL_STUBS_HC
#define K_THIN_SERIAL_STUBS_HC
U0 InputFilterTask()
{
}
#endif
