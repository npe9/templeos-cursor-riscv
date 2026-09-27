#!/bin/bash
# Reset -> U-Boot prompt -> tftp (or loady) the image -> crc32 -> JTAG takeover into M-mode -> capture.
SPID="${UNMATCHED_SCREEN_PID:?pid of the screen session on the console port}"; S="${UNMATCHED_SCRATCH:-/tmp/unmatched}"; mkdir -p "$S"
IMG="${1:?path to the flat binary to load at 0x80200000}"; SZ=$(printf '0x%x' $(wc -c < $IMG)); CRC=$(python3 -c "import zlib;print('%08x'%(zlib.crc32(open('$IMG','rb').read())&0xffffffff))")
cd /Users/npe/src/templeos-cursor-riscv
screen -S $SPID -X clear; sleep 0.3; seen_boot=0
# UNMATCHED_AUTO_RESET=1: cold-reset the board over JTAG first (tools/unmatched/reset.sh) instead of
# waiting for a hand on the button; the banner wait below then sees the fresh boot.
[ -n "$UNMATCHED_AUTO_RESET" ] && { UNMATCHED_SCRATCH="$S" tools/unmatched/reset.sh || exit 1; }
# UNMATCHED_NO_RESET=1: the board is already parked at a clean U-Boot prompt (nothing was run since
# the last boot), so do not make a human press reset just to see the banner again — the DDR image
# is rewritten by tftp anyway. Still verify that a prompt answers. NEVER a bare Enter here: hush
# REPEATS the last command on an empty line, and tftpboot is repeatable. Ctrl-U + `true` instead.
if [ -n "$UNMATCHED_NO_RESET" ]; then
  screen -S $SPID -X stuff $'\x15true\r'; sleep 1; screen -S $SPID -X hardcopy $S/win.txt
  [ "$(grep -vE '^\s*$' $S/win.txt | tail -1)" = "=>" ] && seen_boot=1 || { echo "UNMATCHED_NO_RESET set but no => prompt answers"; exit 1; }
fi
for i in $(seq 1 600); do
  [ "$seen_boot" = 1 ] && [ -n "$UNMATCHED_NO_RESET" ] && break
  screen -S $SPID -X stuff $'\r'; sleep 0.3
  if [ $((i % 6)) -eq 0 ]; then screen -S $SPID -X hardcopy $S/win.txt; sleep 0.1
    grep -qE "OpenSBI|U-Boot 20|Hit any key" $S/win.txt && seen_boot=1
    [ "$seen_boot" = 1 ] && [ "$(grep -vE '^\s*$' $S/win.txt | tail -1)" = "=>" ] && { echo "U-Boot prompt at ~$((i*3/10))s"; break; }
  fi
done
[ "$seen_boot" = 1 ] || { echo "no reset seen in 3 min"; exit 1; }
# Transport: UNMATCHED_XFER=tftp (default) or =ymodem (no network needed; ~50 s per 323 KB).
# tftp serves from the ROUTER by default: the image is scp'd to UNMATCHED_TFTP_SSH:UNMATCHED_TFTP_DIR
# (dnsmasq TFTP, wired to the board: 62.5 KiB/s measured) and the board is told to fetch it from
# UNMATCHED_SERVERIP. Set UNMATCHED_TFTP_SSH= (empty) to serve from the Mac's own tftpd instead
# (/private/tftpboot, UNMATCHED_SERVERIP=<Mac IP>) — 11.7 KiB/s when the Mac is on Wi-Fi, because
# TFTP is one block per round trip.
XFER="${UNMATCHED_XFER:-tftp}"
if [ "$XFER" = tftp ]; then
  NAME=$(basename "$IMG"); TSSH="${UNMATCHED_TFTP_SSH-root@192.168.8.1}"; TDIR="${UNMATCHED_TFTP_DIR:-/tmp/tftp}"
  if [ -n "$TSSH" ]; then
    SRV="${UNMATCHED_SERVERIP:-${TSSH#*@}}"
    scp -q -O "$IMG" "$TSSH:$TDIR/$NAME" || { echo "scp to $TSSH:$TDIR failed (is dnsmasq TFTP enabled there?)"; exit 1; }
    rsz=$(ssh -o BatchMode=yes "$TSSH" "wc -c < $TDIR/$NAME" | tr -d ' '); [ "$rsz" = "$(wc -c < $IMG | tr -d ' ')" ] || { echo "staged size $rsz != local"; exit 1; }
  else
    SRV="${UNMATCHED_SERVERIP:?Mac IP that runs tftpd}"
    [ -f "/private/tftpboot/$NAME" ] || { echo "/private/tftpboot/$NAME missing (cp it there first)"; exit 1; }
    cmp -s "$IMG" "/private/tftpboot/$NAME" || { echo "/private/tftpboot/$NAME differs from $IMG"; exit 1; }
  fi
  # `dhcp` OVERWRITES serverip with the DHCP server (the router), so a setenv before it is lost and
  # the request goes to the wrong host. Name the server inline instead: host:file is always honoured.
  screen -S $SPID -X stuff $'\x15true\r'; sleep 0.3; screen -S $SPID -X stuff $'setenv autoload no\r'; sleep 0.5
  screen -S $SPID -X stuff $'dhcp\r'; sleep 6
  screen -S $SPID -X stuff "tftpboot 0x80200000 $SRV:$NAME"$'\r'
  for i in $(seq 1 600); do sleep 2; screen -S $SPID -X hardcopy $S/win.txt; grep -qE "Bytes transferred|Retry count exceeded|TFTP error|not found" $S/win.txt && break; done
  grep -E "DHCP client bound|Bytes transferred|Retry count exceeded|TFTP error|not found" $S/win.txt | tail -3
  grep -q "Bytes transferred" $S/win.txt || { echo "tftp did not complete"; exit 1; }
else
  screen -S $SPID -X stuff $'loady 0x80200000\r'; sleep 2
  screen -S $SPID -X exec '!!' sz --ymodem -b $IMG
  for i in $(seq 1 60); do sleep 3; screen -S $SPID -X hardcopy $S/win.txt; grep -qE "Total Size|abort|error" $S/win.txt && break; done
  grep -E "Total Size" $S/win.txt | tail -1
fi
screen -S $SPID -X stuff "crc32 0x80200000 $SZ"$'\r'; sleep 4; screen -S $SPID -X hardcopy $S/win.txt
got=$(grep -A1 "^=> crc32" $S/win.txt | tail -1 | awk '{print $NF}'); echo "crc32 ddr=$got file=$CRC"
[ "$got" = "$CRC" ] || { echo "CRC MISMATCH — not taking over"; exit 1; }
# UNMATCHED_UBOOT_PRE: U-Boot commands to run after the image is in DDR and before the takeover,
# e.g. `mw.q 0x80740000 0 0xf18000` to zero DDR above the image (QEMU's RAM is zero for free; the
# board's is whatever the last boot left, and the kernel finds out the hard way).
if [ -n "$UNMATCHED_UBOOT_PRE" ]; then
  screen -S $SPID -X stuff "$UNMATCHED_UBOOT_PRE"$'\r'; sleep 3
  screen -S $SPID -X stuff $'\x15true\r'; sleep 1; screen -S $SPID -X hardcopy $S/win.txt
  [ "$(grep -vE '^\s*$' $S/win.txt | tail -1)" = "=>" ] || { echo "U-Boot did not come back from: $UNMATCHED_UBOOT_PRE"; exit 1; }
  echo "pre-cmd done: $UNMATCHED_UBOOT_PRE"
fi
screen -S $SPID -X clear; sleep 0.3
(timeout 120 openocd -f tests/openocd/hifive_unmatched_hart1.cfg -c "init" > $S/oocd_plat2.log 2>&1 &); sleep 4
python3 tools/unmatched/dmi_takeover.py 0x80200000; rc=$?
pkill -f "openocd -f tests/openocd/hifive_unmatched_hart1.cfg -c init" 2>/dev/null; sleep 5
screen -S $SPID -X hardcopy $S/plat_clean.txt; sleep 0.5
echo "=== console, post-clear only (rc=$rc):"; tr -cd '\11\12\15\40-\176' < $S/plat_clean.txt | sed 's/^ *//' | grep -vE '^\s*$' | cut -c1-100
echo PLATDONE
