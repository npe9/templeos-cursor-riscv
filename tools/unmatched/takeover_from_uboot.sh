#!/bin/bash
# Wait for the U-Boot prompt in the user's screen (feeding Enter to stop autoboot), then take over
# hart 1 straight from the prompt — no `go` — and capture the console.
SPID="${UNMATCHED_SCREEN_PID:?pid of the screen session on the console port}"; S="${UNMATCHED_SCRATCH:-/tmp/unmatched}"; mkdir -p "$S"
cd /Users/npe/src/templeos-cursor-riscv
# Clear the visible window first so stale boot text from a previous run cannot trigger us; the
# detector then requires fresh boot text to appear before it will accept a prompt.
screen -S $SPID -X clear; sleep 0.3
seen_boot=0
for i in $(seq 1 600); do
  screen -S $SPID -X stuff $'\r'; sleep 0.3
  if [ $((i % 6)) -eq 0 ]; then
    screen -S $SPID -X hardcopy $S/win.txt; sleep 0.1
    grep -qE "OpenSBI|U-Boot 20|Hit any key" $S/win.txt && seen_boot=1
    last=$(grep -vE '^\s*$' $S/win.txt | tail -1)
    if [ "$seen_boot" = 1 ] && [ "$last" = "=>" ]; then echo "U-Boot prompt after reset at ~$((i*3/10))s"; break; fi
  fi
done
[ "$seen_boot" = 1 ] || { echo "no reset seen in 3 min"; exit 1; }
# SPL reuses 0x80200000 as the FIT load address every boot, so the payload must be re-poked after
# each reset (learned by taking over into leftover image bytes).
while IFS= read -r l; do screen -S $SPID -X stuff "$l"$'\r'; sleep 0.25; done < "${UNMATCHED_MW:-tools/unmatched/hello_mw.txt}"; sleep 1
screen -S $SPID -X stuff $'md.l 0x80200000 2\r'; sleep 1.5
screen -S $SPID -X hardcopy $S/win.txt; mdl=$(grep -A1 "^=> md.l" $S/win.txt | tail -1); echo "$mdl"
echo "$mdl" | grep -q 100102b7 || { echo "payload NOT in DDR — aborting before takeover"; exit 1; }
(timeout 120 openocd -f tests/openocd/hifive_unmatched_hart1.cfg -c "init" > $S/oocd_arm.log 2>&1 &); sleep 4
python3 tools/unmatched/dmi_takeover.py 0x80200000; rc=$?
pkill -f "openocd -f tests/openocd/hifive_unmatched_hart1.cfg -c init" 2>/dev/null; sleep 2
screen -S $SPID -X hardcopy -h $S/ub_arm.txt; sleep 1
echo "=== console after takeover (rc=$rc):"; grep -vE '^\s*$' $S/ub_arm.txt | tail -6 | cut -c1-100
echo ARMDONE
