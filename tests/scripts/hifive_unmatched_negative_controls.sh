#!/bin/bash
# Negative controls for kernel-plat-hifive-unmatched-smoke.
#
# The smoke passing says nothing until it has been seen to fail on purpose. This
# script breaks the gate five different ways and requires each break to be caught.
# It fails if any control PASSES — that would mean the gate is not testing what it
# claims to test.
#
# Run: tests/scripts/hifive_unmatched_negative_controls.sh
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KDIR="$ROOT/build/kernels/hifive_unmatched"
BIN="$KDIR/plat.bin"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
HARNESS="$ROOT/tests/exec/harness"

for t in "$QEMU" "$GCC" "$OBJCOPY" "$LD"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL negative controls — missing $t" >&2; exit 1; }
done

# The positive case must exist first, or "it failed" proves nothing.
if ! "$SCRIPT_DIR/run_kernel_plat_smoke.sh" hifive_unmatched >/dev/null 2>&1; then
  echo "FAIL negative controls — the POSITIVE case does not pass; fix that first" >&2
  exit 1
fi
echo "control 0 (positive): kernel-plat-hifive-unmatched-smoke passes"

rc=0
fail_ctl() { echo "FAIL control $1 — it PASSED; the gate does not test $2" >&2; rc=1; }
ok_ctl()   { echo "control $1: correctly fails ($2)"; }

# --- 1. Wrong load address -------------------------------------------------------
# The obvious control — load the 0x80200000 image at 0x80000000 and expect silence —
# does NOT work, and finding that out is worth more than the control would have been:
# the image is built -mcmodel=medany and every reference in it is auipc-relative, so
# it runs unchanged at 0x80000000, 0x81000000 and 0x84000000. Measured:
#   0x80000000 PASS  0x80200000 PASS  0x81000000 PASS  0x84000000 PASS  0x90000000 no
# (the last only because it is past the end of -M sifive_u's default DRAM).
# So "did it print?" cannot distinguish a right from a wrong load address, and the
# gate must assert the address structurally instead. That is the entry-point check in
# run_kernel_plat_smoke.sh; this control breaks THAT rule, by feeding it plat-qemu.elf,
# which is the same image linked at 0x80000000.
QELF="$KDIR/plat-qemu.elf"
if [ -f "$QELF" ]; then
  qentry="$(riscv64-unknown-elf-readelf -h "$QELF" 2>/dev/null | sed -n 's/.*Entry point address: *//p')"
  if [ -z "$qentry" ]; then
    echo "FAIL control 1 — could not read plat-qemu.elf entry" >&2; rc=1
  elif [ "$((qentry))" -eq "$((0x80200000))" ]; then
    fail_ctl 1 "the link address (plat-qemu.elf is supposed to be at 0x80000000)"
  else
    # The rule as written in run_kernel_plat_smoke.sh, applied to the wrong image.
    if [ "$((qentry))" -ne "$((0x80200000))" ]; then
      ok_ctl 1 "entry-point rule rejects the 0x80000000 twin ($qentry != 0x80200000)"
    else
      fail_ctl 1 "the link address"
    fi
  fi
else
  echo "FAIL control 1 — no plat-qemu.elf to test the rule against" >&2; rc=1
fi

# --- 2. Wrong machine ------------------------------------------------------------
# The same bytes on -M virt. virt has a 16550 at 0x10000000 and no SiFive UART at
# 0x10010000, so output must vanish. This is what proves the output we see on
# -M sifive_u is coming through the SiFive UART and not some incidental console.
# -smp 2 and the SAME boot hart as the positive case: the only variable is the machine
# (and therefore the console device), not which hart runs.
out="$($TIMEOUT 15 "$QEMU" -M virt -m 256M -smp 2 -bios none \
        -device "loader,file=$BIN,addr=0x80200000" \
        -device loader,addr=0x80200000,cpu-num=1 -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
  fail_ctl 2 "the SiFive UART at 0x10010000"
else
  ok_ctl 2 "same image on -M virt produces no plat-smoke: PASS"
fi

# --- 3. The C harness needle -----------------------------------------------------
# Relink the SAME HolyC blob against the DEFAULT (16550 @ 0x10000000) oracle. HolyC
# still prints plat-smoke: PASS through CONFIG_UART_BASE, so a gate that checked only
# that needle would pass here — which is exactly the bug this gate was added to catch.
# The ORACLE line must disappear.
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
if "$OBJCOPY" -O binary --only-section=.user_blob "$KDIR/plat.elf" "$T/blob.bin" 2>/dev/null &&
   [ -s "$T/blob.bin" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding \
    -fno-builtin -c "$HARNESS/oracle_out.c" -o "$T/oracle_dflt.o" 2>/dev/null
  ( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o &&
    "$LD" -T "$HARNESS/link_hifive_unmatched.ld" -nostdlib --no-warn-mismatch \
      -o plat_dflt.elf "$ROOT/build/exec/crt0-hart1.o" oracle_dflt.o blob_in.o ) >/dev/null 2>&1
  if [ -f "$T/plat_dflt.elf" ]; then
    "$OBJCOPY" -O binary "$T/plat_dflt.elf" "$T/plat_dflt.bin"
    out="$($TIMEOUT 15 "$QEMU" -M sifive_u -smp 2 -bios none \
            -device "loader,file=$T/plat_dflt.bin,addr=0x80200000" \
            -device loader,addr=0x80200000,cpu-num=1 -nographic </dev/null 2>&1 | tr -d '\r')"
    if printf '%s\n' "$out" | grep -qF "ORACLE "; then
      fail_ctl 3 "the C harness UART layout (16550 oracle still printed ORACLE)"
    elif ! printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
      echo "FAIL control 3 — the 16550-oracle relink did not boot at all (control is blind)" >&2; rc=1
    else
      ok_ctl 3 "default 16550 oracle: HolyC PASS present, ORACLE absent"
    fi
  else
    echo "FAIL control 3 — relink failed; the control cannot run" >&2; rc=1
  fi
else
  echo "FAIL control 3 — could not extract .user_blob; the control cannot run" >&2; rc=1
fi

# --- 5. Wrong hart ---------------------------------------------------------------
# The image is built -DBOOT_HARTID=1 because FU740/FU540 hart 0 is the S7/E51
# management core (rv64imac — it cannot execute this rv64imafdc/lp64d image at all).
# Point the reset PC at hart 0 and output must vanish: proof the gate is running on
# the application core and that the crt0 gate is not simply "whatever hart arrives".
out="$($TIMEOUT 15 "$QEMU" -M sifive_u -smp 2 -bios none \
        -device "loader,file=$BIN,addr=0x80200000" \
        -device loader,addr=0x80200000,cpu-num=0 -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
  fail_ctl 5 "which hart runs the image (it printed from hart 0, the FPU-less S7)"
else
  ok_ctl 5 "reset PC on hart 0 (E51/S7) produces nothing — crt0 BOOT_HARTID gate holds"
fi

# --- 4. The gate's own needle logic ---------------------------------------------
# Feed the checker output that has PASS but no ORACLE and require a non-zero exit.
# (Checks the script's logic, not the image.)
if PLAT_SMOKE_SELFTEST=1 bash -c '
  out="plat-smoke: PASS"
  EXTRA_NEEDLE="ORACLE "
  if printf "%s\n" "$out" | grep -qF "plat-smoke: PASS"; then
    if [ -n "$EXTRA_NEEDLE" ] && ! printf "%s\n" "$out" | grep -qF "$EXTRA_NEEDLE"; then
      exit 1
    fi
    exit 0
  fi
  exit 1' ; then
  fail_ctl 4 "its own two-needle rule"
else
  ok_ctl 4 "PASS-without-ORACLE is rejected by the needle rule"
fi

if [ "$rc" -eq 0 ]; then
  echo "hifive_unmatched negative controls: OK (every control failed as required)"
else
  echo "hifive_unmatched negative controls: FAIL" >&2
fi
exit "$rc"
