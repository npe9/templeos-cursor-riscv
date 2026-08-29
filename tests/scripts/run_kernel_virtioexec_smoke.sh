#!/bin/bash
# Kernel-print smoke: compile a program that #includes the real TempleOS kernel (Kernel_RV.PRJ),
# formats a string with the kernel's own StrPrintJoin, and writes it to the QEMU virt UART. Then
# run it under qemu-system-riscv64 and check the expected line appears. This proves real kernel
# code (not just the front end) executes and produces output on RISC-V.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_virtioexec_demo.hc"
EXPECT="loaded program returned 55"
EXPECT2="loaded off the RedSea disk"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-virtioexec smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-virtioexec smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-virtioexec smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

python3 -c "open('$T/disk.img','wb').write(bytes(4096*512))" || { echo "FAIL kernel-virtioexec smoke — mkdisk" >&2; exit 1; }

# Compile the guest program to a position-independent blob and emit it as a HolyC byte array that the
# loader demo #includes (generated, never committed — always matches the compiler in the tree).
PROG="$ROOT/tests/exec/cases/prog_hello.hc"
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$PROG" -o "$OUTDIR/prog.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtioexec smoke — program compile error" >&2; exit 1
fi
python3 - "$OUTDIR/prog.bin" "$OUTDIR/prog_arr.hc" <<'PYEOF'
import sys
d=open(sys.argv[1],"rb").read()
open(sys.argv[2],"w").write("U8 prog_blob[%d]={%s};\nI64 prog_blob_size=%d;\n"%(len(d),",".join(map(str,d)),len(d)))
PYEOF

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtioexec smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-virtioexec smoke — link error" >&2; exit 1; }

out="$($TIMEOUT 30 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
        -drive file="$T/disk.img",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && printf '%s\n' "$out" | grep -qF "$EXPECT2"; then
  echo "Kernel-virtioexec smoke: OK"
  exit 0
fi
echo "FAIL kernel-virtioexec smoke — expected line not found:" >&2
echo "  want: $EXPECT" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -5 | sed 's/^/  got: /' >&2
exit 1
