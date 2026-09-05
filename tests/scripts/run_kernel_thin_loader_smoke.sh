#!/usr/bin/env bash
# Thin loader smoke (G9): RVKMain mounts virtio RedSea → Load Kernel.BIN → Call KernelEntry.
# No Cmp / MakeOS / StartOS. Milestone toward dropping Mac phase3.elf scaffold.
# See templeos-riscv/COMPILER_RV.md § P3 residual / thin loader.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_thin_loader_demo.hc"
EXPECT_FIND="RVThinLoader: FileFind OK; Load..."
EXPECT_LOAD="RVThinLoader: Load OK; Call KernelEntry (handoff)..."
EXPECT_HAND="RVThinLoader: handoff OK (KernelEntry=0x4B45, KernelProbe=42)."
EXPECT_INIT="RVThinLoader: InitLite OK (ENTRY.OK + HeapProbe=64 + InitLite=0x4B49)."
EXPECT_DONE="RVThinLoader: done (thin loader + RedSea Kernel.BIN)."

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT="gtimeout"
elif ! command -v timeout >/dev/null 2>&1; then
  echo "SKIP kernel-thin-loader smoke — missing timeout/gtimeout" >&2
  exit 0
fi

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-thin-loader smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv tools/pack_tosb >/dev/null

# Host-pack Kernel.BIN seed: KernelProbe + KernelEntry + InitLite (heap/FileWrite).
KERNEL_PROBE_SRC="$ROOT/tests/exec/cases/kernel_bin_probe.hc"
KERNEL_BLOB="$OUTDIR/kernel_bin_probe.blob.bin"
KERNEL_MAP="$OUTDIR/kernel_bin_probe.map"
mkdir -p "$OUTDIR"
if ! HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_MAP="$KERNEL_MAP" \
   "$COMPILER" "$KERNEL_PROBE_SRC" -o "$KERNEL_BLOB" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — Kernel.BIN probe compile" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$KERNEL_PROBE_SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
KP_OFF=$(awk '/ KernelProbe$/{print $1; exit}' "$KERNEL_MAP")
KE_OFF=$(awk '/ KernelEntry$/{print $1; exit}' "$KERNEL_MAP")
KI_OFF=$(awk '/ KernelInitLite$/{print $1; exit}' "$KERNEL_MAP")
KH_OFF=$(awk '/ KernelHeapProbe$/{print $1; exit}' "$KERNEL_MAP")
if [ -z "$KP_OFF" ] || [ -z "$KE_OFF" ] || [ -z "$KI_OFF" ] || [ -z "$KH_OFF" ]; then
  echo "FAIL kernel-thin-loader smoke — KernelProbe/Entry/InitLite/HeapProbe missing from map" >&2
  exit 1
fi
"$ROOT/tools/pack_tosb" -v \
  -e "KernelProbe:0x${KP_OFF}" -e "KernelEntry:0x${KE_OFF}" \
  -e "KernelInitLite:0x${KI_OFF}" -e "KernelHeapProbe:0x${KH_OFF}" \
  "$KERNEL_BLOB" "$ROOT/build/Kernel.BIN" >/dev/null \
  || { echo "FAIL kernel-thin-loader smoke — pack Kernel.BIN" >&2; exit 1; }

REDSEA_IMG="$OUTDIR/thin_loader_redsea.img"
python3 "$ROOT/tools/mk_redsea_seed_img.py" "$REDSEA_IMG" \
  "Kernel/Kernel.BIN=$ROOT/build/Kernel.BIN" \
  || { echo "FAIL kernel-thin-loader smoke — RedSea seed img" >&2; exit 1; }

if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-thin-loader smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-thin-loader smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-thin-loader smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -40 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o thin.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-thin-loader smoke — link error" >&2; exit 1; }

cp "$T/thin.elf" "$OUTDIR/thin_loader.elf"
cp "$REDSEA_IMG" "$T/thin_loader_redsea.img" \
  || { echo "FAIL kernel-thin-loader smoke — copy RedSea img" >&2; exit 1; }

THIN_TIMEOUT="${THIN_TIMEOUT:-60}"
out=""
out=$(LC_ALL=C $TIMEOUT "$THIN_TIMEOUT" "$QEMU" -M virt -m 256M -bios none -kernel "$T/thin.elf" -nographic \
  -drive file="$T/thin_loader_redsea.img",if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | LC_ALL=C tr -d '\r') || true
printf '%s\n' "$out" > /tmp/thin_loader_uart.txt || true

if printf '%s\n' "$out" | grep -qF "$EXPECT_FIND" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_LOAD" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_HAND" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_INIT" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_DONE"; then
  echo "Kernel-thin-loader smoke: OK (virtio RedSea Load + KernelEntry + InitLite)"
  exit 0
fi
echo "FAIL kernel-thin-loader smoke — expected handoff line not found:" >&2
echo "  want: $EXPECT_FIND / $EXPECT_LOAD / $EXPECT_HAND / $EXPECT_INIT / $EXPECT_DONE" >&2
printf '%s\n' "$out" | grep -E 'RVThin|RVKMain|Kernel|Load|FAIL|OK|Except|Error' | head -40 | LC_ALL=C sed 's/^/  /' >&2
exit 1
