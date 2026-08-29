#!/bin/bash
# Kernel-virtioshell smoke: the interactive TempleOS/RISC-V shell running on a REAL, PERSISTENT
# virtio-blk disk. Two sessions against the SAME disk image: session 1 (mkdir/write) creates a
# directory and a file through the shell, session 2 (dir/cat) reads them back -- files created in one
# shell session survive to the next. This ties the whole authentic stack together: boot, the scheduler
# running the shell as a real CTask, the kernel's own RedSea filesystem, and the native virtio-blk
# driver giving durable storage.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_virtioshell_demo.hc"
PROG="$ROOT/tests/exec/cases/prog_hello.hc"
EXPECT1="wrote HELLO.TXT"      # session 1 created the file
EXPECT2="hello world"          # session 2 read it back off the persisted disk

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-virtioshell smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-virtioshell smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-virtioshell smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

python3 -c "open('$T/disk.img','wb').write(bytes(4096*512))" || { echo "FAIL kernel-virtioshell smoke — mkdisk" >&2; exit 1; }

# The shell's `run` command needs a program blob; generate it (never committed, always matches the tree).
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$PROG" -o "$OUTDIR/prog.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtioshell smoke — program compile error" >&2; exit 1
fi
python3 - "$OUTDIR/prog.bin" "$OUTDIR/prog_arr.hc" <<'PYEOF'
import sys
d=open(sys.argv[1],"rb").read()
open(sys.argv[2],"w").write("U8 prog_blob[%d]={%s};\nI64 prog_blob_size=%d;\n"%(len(d),",".join(map(str,d)),len(d)))
PYEOF

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtioshell smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-virtioshell smoke — link error" >&2; exit 1; }

shell() { printf "$1" | $TIMEOUT 30 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
            -drive file="$T/disk.img",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 2>&1 | tr -d '\r'; }

out1="$(shell 'mkdir DOCS\nwrite HELLO.TXT hello world\ndir\nexit\n')"   # session 1: create
out2="$(shell 'dir\ncat HELLO.TXT\nexit\n')"                             # session 2: read back (same disk)

if printf '%s\n' "$out1" | grep -qF "$EXPECT1" && printf '%s\n' "$out2" | grep -qF "$EXPECT2"; then
  echo "Kernel-virtioshell smoke: OK"
  exit 0
fi
echo "FAIL kernel-virtioshell smoke — shell persistence not observed:" >&2
echo "  session1 want: $EXPECT1" >&2
echo "  session2 want: $EXPECT2" >&2
printf 's1: %s\n' "$out1" | grep -v 'import unresolved' | head -5 | sed 's/^/  /' >&2
printf 's2: %s\n' "$out2" | grep -v 'import unresolved' | head -5 | sed 's/^/  /' >&2
exit 1
