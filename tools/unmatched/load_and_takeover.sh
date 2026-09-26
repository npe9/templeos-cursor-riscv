#!/bin/bash
# Reset -> U-Boot prompt -> loady the platform image -> crc32 -> JTAG takeover into M-mode -> capture.
SPID="${UNMATCHED_SCREEN_PID:?pid of the screen session on the console port}"; S="${UNMATCHED_SCRATCH:-/tmp/unmatched}"; mkdir -p "$S"
IMG="${1:?path to the flat binary to load at 0x80200000}"; SZ=$(printf '0x%x' $(wc -c < $IMG)); CRC=$(python3 -c "import zlib;print('%08x'%(zlib.crc32(open('$IMG','rb').read())&0xffffffff))")
cd /Users/npe/src/templeos-cursor-riscv
screen -S $SPID -X clear; sleep 0.3; seen_boot=0
for i in $(seq 1 600); do
  screen -S $SPID -X stuff $'\r'; sleep 0.3
  if [ $((i % 6)) -eq 0 ]; then screen -S $SPID -X hardcopy $S/win.txt; sleep 0.1
    grep -qE "OpenSBI|U-Boot 20|Hit any key" $S/win.txt && seen_boot=1
    [ "$seen_boot" = 1 ] && [ "$(grep -vE '^\s*$' $S/win.txt | tail -1)" = "=>" ] && { echo "U-Boot prompt at ~$((i*3/10))s"; break; }
  fi
done
[ "$seen_boot" = 1 ] || { echo "no reset seen in 3 min"; exit 1; }
screen -S $SPID -X stuff $'loady 0x80200000\r'; sleep 2
screen -S $SPID -X exec '!!' sz --ymodem -b $IMG
for i in $(seq 1 60); do sleep 3; screen -S $SPID -X hardcopy $S/win.txt; grep -qE "Total Size|abort|error" $S/win.txt && break; done
grep -E "Total Size" $S/win.txt | tail -1
screen -S $SPID -X stuff "crc32 0x80200000 $SZ"$'\r'; sleep 4; screen -S $SPID -X hardcopy $S/win.txt
got=$(grep -A1 "^=> crc32" $S/win.txt | tail -1 | awk '{print $NF}'); echo "crc32 ddr=$got file=$CRC"
[ "$got" = "$CRC" ] || { echo "CRC MISMATCH — not taking over"; exit 1; }
screen -S $SPID -X clear; sleep 0.3
(timeout 120 openocd -f tests/openocd/hifive_unmatched_hart1.cfg -c "init" > $S/oocd_plat2.log 2>&1 &); sleep 4
python3 tools/unmatched/dmi_takeover.py 0x80200000; rc=$?
pkill -f "openocd -f tests/openocd/hifive_unmatched_hart1.cfg -c init" 2>/dev/null; sleep 5
screen -S $SPID -X hardcopy $S/plat_clean.txt; sleep 0.5
echo "=== console, post-clear only (rc=$rc):"; tr -cd '\11\12\15\40-\176' < $S/plat_clean.txt | sed 's/^ *//' | grep -vE '^\s*$' | cut -c1-100
echo PLATDONE
