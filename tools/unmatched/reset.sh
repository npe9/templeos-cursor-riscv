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
        # Plausible dmstatus only (version 2, authenticated). This DM does NOT report havereset
        # after ndmreset (measured: three real resets read bits 18/19 clear, one read 0x0 while the
        # DM was still coming back), so the proof that a reset happened is the SPL banner on the
        # console, checked by the shell below when a screen pid is available.
        try: v=int(ds,16); ok=(v&0xf)==2 and (v>>7)&1
        except ValueError: ok=0
        sys.exit(0 if dc.lower()=="0x1" and ok else 1)
except Exception as e: print("dmi:",e); sys.exit(1)
PY
}
SPID="${UNMATCHED_SCREEN_PID:-}"
for attempt in 1 2 3; do
  [ -n "$SPID" ] && screen -S $SPID -X clear
  (timeout 30 openocd -f $CFG -c init > $S/oocd_rst_a.log 2>&1 &); sleep 5; dmi assert
  pkill -f "openocd -f $CFG"; sleep 2
  (timeout 30 openocd -f $CFG -c init > $S/oocd_rst_b.log 2>&1 &); sleep 5; dmi release; rc=$?
  pkill -f "openocd -f $CFG"; sleep 1
  if [ -n "$SPID" ]; then
    # The proof: the mask ROM -> SPL banner appears on a window cleared before the assert.
    for i in $(seq 1 12); do sleep 1; screen -S $SPID -X hardcopy $S/rst_win.txt; grep -q "U-Boot SPL" $S/rst_win.txt && { echo "reset: confirmed by SPL banner on attempt $attempt (${i}s)"; exit 0; }; done
    echo "reset: attempt $attempt — no SPL banner in 12 s (release rc=$rc) — asserting again"
  else
    [ $rc = 0 ] && { echo "reset: released (no console to confirm) on attempt $attempt"; exit 0; }
    echo "reset: attempt $attempt release not confirmed (rc=$rc) — asserting again"
  fi
done
echo "reset: NOT confirmed after 3 attempts — the board may be held in reset or the assert keeps getting lost"; exit 1
