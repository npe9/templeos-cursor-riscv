#!/usr/bin/env bash
# Scratch: feed a few lines to the HolyC AOT REPL and dump the log.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ELF="$ROOT/build/repl-holyc.elf"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=timeout
command -v timeout >/dev/null 2>&1 || TIMEOUT_CMD=gtimeout

log="${LOGOUT:-/tmp/asmprobe.log}"
: >"$log"
input=""
while IFS= read -r line; do input+="$line"$'\n'; done
input+=$'4919;\n'

fifo="$(mktemp -u)"
mkfifo "$fifo"
$TIMEOUT_CMD 180 stdbuf -oL -eL "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic \
  <"$fifo" >"$log" 2>&1 &
qpid=$!
(
  for ((boot = 0; boot < 600; boot++)); do
    if grep -qF 'Try: Dir;' "$log" 2>/dev/null; then break; fi
    kill -0 "$qpid" 2>/dev/null || exit 0
    sleep 0.5
  done
  printf '%s' "$input"
  while kill -0 "$qpid" 2>/dev/null; do sleep 0.05; done
) >"$fifo" &
feeder=$!
for ((t = 0; t < 1800; t++)); do
  if grep -q 'ans=0x0000000000001337' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
kill "$feeder" 2>/dev/null || true
wait "$feeder" 2>/dev/null || true
rm -f "$fifo"
sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" | tr -d '\r' >"${log}.clean"
mv "${log}.clean" "$log"
cat "$log"
