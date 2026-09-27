#!/bin/bash
# Hands-free cold reset of the HiFive Unmatched over JTAG: dmcontrol.ndmreset.
#
# Measured 2026-09-26: writing ndmreset takes the debug module down with the rest of the chip, so
# the SAME OpenOCD session can never read back or release it (every DMI op times out and the board
# sits silent, held in reset). A FRESH session can: three blind writes of dmcontrol=dmactive read
# back as 0x1, dmstatus is sane again, and the console shows SPL -> U-Boot from the mask ROM. So this
# is two sessions: assert (blind), kill, release (verified). ~15 s to the U-Boot prompt.
cd "$(dirname "$0")/../.."
CFG=tests/openocd/hifive_unmatched_hart1.cfg; S="${UNMATCHED_SCRATCH:-/tmp/unmatched}"; mkdir -p "$S"
pkill -f "openocd -f $CFG" 2>/dev/null; sleep 1
dmi() { timeout 40 python3 -u - "$@" <<'PY'
import socket,sys
s=socket.create_connection(("127.0.0.1",6666),timeout=8)
def tcl(c):
    s.sendall(c.encode()+b"\x1a"); buf=b""
    while not buf.endswith(b"\x1a"):
        d=s.recv(4096)
        if not d: raise SystemExit("closed")
        buf+=d
    return buf[:-1].decode(errors="replace").strip()
mode=sys.argv[1]
try:
    if mode=="assert":
        for _ in range(3): tcl("riscv dmi_write 0x10 0x3")   # dmactive|ndmreset, blind: nothing answers after this
        print("ndmreset asserted (blind)")
    else:
        for _ in range(3): tcl("riscv dmi_write 0x10 0x1")
        dc=tcl("riscv dmi_read 0x10"); ds=tcl("riscv dmi_read 0x11"); print("released: dmcontrol=%s dmstatus=%s"%(dc,ds))
        sys.exit(0 if dc.lower()=="0x1" else 1)
except Exception as e: print("dmi:",e); sys.exit(1)
PY
}
(timeout 30 openocd -f $CFG -c init > $S/oocd_rst_a.log 2>&1 &); sleep 5; dmi assert
pkill -f "openocd -f $CFG"; sleep 2
(timeout 30 openocd -f $CFG -c init > $S/oocd_rst_b.log 2>&1 &); sleep 5; dmi release; rc=$?
pkill -f "openocd -f $CFG"; sleep 1
[ $rc = 0 ] && echo "reset: released; expect SPL on the console within ~5 s" || { echo "reset: release NOT confirmed (rc=$rc) — the board may be held in reset; rerun"; exit 1; }
