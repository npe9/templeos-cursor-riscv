#!/bin/bash
# Console/VT multiplexing gate: guest soft VTs (console.hc) + framed channels
# (frame.hc, G22) + host demux (tools/uart_mux.py).
#
# Nothing exercised uart_mux.py before this, and it carried two silent data-loss bugs:
#   1. a literal '~' (0x7E) in console text was read as frame SYNC, and every failed
#      frame DROPPED its buffer — the REPL boot banner contains one ("~10000000 Hz"),
#      so every session lost everything after it;
#   2. soft VT banners were scanned one byte at a time against a multi-byte regex, so
#      --vt-split never split anything.
# Both were invisible: the tool exited 0 and wrote plausible-looking files. So this
# gate asserts BYTE PARITY against a plain `cat` first — that is the check that would
# have caught #1 immediately — and then that sessions actually separate.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/repl-holyc.elf"
MUX="$ROOT/tools/uart_mux.py"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
PY="${PYTHON:-python3}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP mux smoke — missing $QEMU" >&2; exit 0; }
command -v "$PY"   >/dev/null 2>&1 || { echo "SKIP mux smoke — missing $PY" >&2; exit 0; }
[ -f "$ELF" ] || { echo "SKIP mux smoke — no $ELF (make hc-repl)" >&2; exit 0; }

"$PY" "$MUX" --selftest >/dev/null 2>&1 || { echo "FAIL mux smoke — uart_mux selftest" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/outA" "$T/outB"

# Two runs, because the right invariant differs.
#
# Run A — framing OFF. The demuxer must be byte-for-byte transparent: it is only
# passing console text through. This is the check that catches the false-SYNC bug,
# and it is only meaningful because the boot banner contains a bare '~'.
SCRIPT_A='VtCapture(1);
Vt(1);
"vt1: answer=%d\n",6*7;
Vt(2);
"vt2: marker\n";
Vt(0);
Quit;
'
# Run B — framing ON. Byte parity no longer holds by design: framed packets are
# consumed by the demuxer rather than echoed. Assert the framed features instead.
SCRIPT_B='UartMuxOn();
LogInfo("mux","ch3 marker");
VtCapture(1);
Vt(1);
"vt1: answer=%d\n",6*7;
Vt(2);
"vt2: marker\n";
VtPane(1,2);
Vt(0);
Quit;
'
run_guest() { printf '%s' "$1" | $TIMEOUT 90 "$QEMU" -M virt -bios none -kernel "$ELF" -nographic 2>&1; }

fail=0
say() { echo "FAIL mux smoke — $1" >&2; fail=1; }

# ---- Run A: transparency + soft-banner VT split (no framing) ----
# Capture ONCE and replay the same bytes through the demuxer. Comparing two separate
# QEMU runs is flaky: the banner prints an uptime tick count whose digit-length varies,
# which showed up as a 1-byte diff and would have been read as data loss.
run_guest "$SCRIPT_A" > "$T/plain.txt"
"$PY" "$MUX" -o "$T/outA" --vt-split --console-stdout \
  < "$T/plain.txt" > "$T/muxedA.txt" 2>"$T/statusA.txt"

grep -q '~' "$T/plain.txt" || say "no bare '~' in guest output — the false-SYNC case is untested"
a=$(wc -c < "$T/plain.txt" | tr -d ' ')
b=$(wc -c < "$T/muxedA.txt" | tr -d ' ')
if [ "$a" != "$b" ]; then
  say "demux is not transparent with framing off: plain=${a}B muxed=${b}B"
fi
# Soft banners alone must still split sessions.
grep -q "vt1: answer=42" "$T/outA/vt1" 2>/dev/null || say "soft-banner split: vt1 missing its output"
grep -q "vt2: marker"    "$T/outA/vt2" 2>/dev/null || say "soft-banner split: vt2 missing its output"
grep -q "vt2: marker"    "$T/outA/vt1" 2>/dev/null && say "soft-banner split: vt2 leaked into vt1"

# ---- Run B: framed channels + pane layout ----
run_guest "$SCRIPT_B" > "$T/plainB.txt"
"$PY" "$MUX" -o "$T/outB" --vt-split --vt-panes \
  < "$T/plainB.txt" > /dev/null 2>"$T/statusB.txt"

grep -q "unknown fun UartMuxOn" "$T/plainB.txt" 2>/dev/null \
  && say "UartMuxOn not registered (JitAdd in bootstrap/hc_repl/repl.hc)"
frames=$(sed -n 's/.*frames=\([0-9]*\).*/\1/p' "$T/statusB.txt" | tail -1)
if [ -z "$frames" ] || [ "$frames" -le 0 ] 2>/dev/null; then
  say "no framed packets decoded (frames=${frames:-?})"
fi
sw=$(sed -n 's/.*vt_sw=\([0-9]*\).*/\1/p' "$T/statusB.txt" | tail -1)
# 3 distinct switches (0->1, 1->2, 2->0). Framed notify AND soft banner both fire per
# switch, so anything above 3 means they are being double-counted.
[ "$sw" = "3" ] || say "expected vt_sw=3, got ${sw:-?} (framed + banner double-count?)"
grep -q "pane=1|2" "$T/statusB.txt" || say "VtPane(1,2) not received over ch0"
# ch3: LogInfo must reach the framed log channel. This used to be dead — frame.hc
# "redefined" log.hc's LogMuxEmit, but in one AOT translation unit the call site binds
# to the definition in scope, so the framed emitter was never reached. It now goes
# through g_log_mux_hook, and this is what proves it.
grep -q "ch3 marker" "$T/outB/log" 2>/dev/null || say "LogInfo did not reach framed ch3"
grep -q "VT panes: 1 | 2" "$T/outB/vt_panes.txt" 2>/dev/null || say "--vt-panes did not render"

if [ "$fail" -ne 0 ]; then
  echo "---- status A (framing off) ----" >&2; cat "$T/statusA.txt" >&2
  echo "---- status B (framing on) ----" >&2; cat "$T/statusB.txt" >&2
  exit 1
fi
sed -n 's/^uart_mux: \(vt_cur.*\)/  A \1/p' "$T/statusA.txt"
sed -n 's/^uart_mux: \(vt_cur.*\)/  B \1/p' "$T/statusB.txt"
echo "Mux smoke: OK (no byte loss; soft VT split; framed ch0+ch3; panes)"
exit 0
