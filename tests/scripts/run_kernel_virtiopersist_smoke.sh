#!/bin/bash
# Kernel-virtiopersist smoke: boot the kernel TWICE against the SAME virtio-blk disk image. The first
# boot formats the blank disk RedSea and writes PERSIST.TXT; the second boot mounts the now-formatted
# disk (RedSeaValidate -> RedSeaInit, not a reformat) and reads the file straight back. Passing the
# second boot's expected line proves data written by the kernel's own FS/driver survives a reboot on a
# real disk -- durable storage, and the mount-existing path.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_virtiopersist_demo.hc"
EXPECT1="first boot: wrote PERSIST.TXT"
EXPECT2="PERSISTED across reboot OK"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-virtiopersist smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-virtiopersist smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-virtiopersist smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# One blank disk image, shared by both boots (this is what makes it a persistence test).
python3 -c "open('$T/disk.img','wb').write(bytes(4096*512))" || { echo "FAIL kernel-virtiopersist smoke — mkdisk" >&2; exit 1; }

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtiopersist smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-virtiopersist smoke — link error" >&2; exit 1; }

boot() { $TIMEOUT 30 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
           -drive file="$T/disk.img",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | tr -d '\r'; }

out1="$(boot)"   # first boot: blank disk -> format + write
out2="$(boot)"   # second boot: same image -> mount existing + read back

if printf '%s\n' "$out1" | grep -qF "$EXPECT1" && printf '%s\n' "$out2" | grep -qF "$EXPECT2"; then
  echo "Kernel-virtiopersist smoke: OK"
  exit 0
fi
echo "FAIL kernel-virtiopersist smoke — persistence not observed:" >&2
echo "  boot1 want: $EXPECT1" >&2
echo "  boot2 want: $EXPECT2" >&2
printf 'boot1: %s\n' "$out1" | grep -v 'import unresolved' | head -4 | sed 's/^/  /' >&2
printf 'boot2: %s\n' "$out2" | grep -v 'import unresolved' | head -4 | sed 's/^/  /' >&2
exit 1
