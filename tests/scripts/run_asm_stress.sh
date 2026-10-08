#!/usr/bin/env bash
# Assembler semantics stress: TryAssembleRiscV encodings vs goldens (+ optional gas oracle).
# See tests/asm/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${HOLYC_BIN:-$ROOT/holyc-riscv}"
CASES_DIR="$ROOT/tests/asm/cases"
POS="$CASES_DIR/positive.jsonl"
NEG="$CASES_DIR/negative.jsonl"
TMP="${TMPDIR:-/tmp}/holyc_asm_stress_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

GAS_AS="${RISCV_AS:-riscv64-unknown-elf-as}"
GAS_OBJDUMP="${RISCV_OBJDUMP:-riscv64-unknown-elf-objdump}"
GAS_MARCH="${ASM_STRESS_GAS_MARCH:-rv64ima_zicsr_zifencei}"
HAVE_GAS=0
if command -v "$GAS_AS" >/dev/null 2>&1 && command -v "$GAS_OBJDUMP" >/dev/null 2>&1; then
  HAVE_GAS=1
fi

if [[ ! -x "$BIN" ]]; then
  echo "Building holyc-riscv..." >&2
  make -C "$ROOT" holyc-riscv >/dev/null || {
    echo "error: missing $BIN (run make / make holyc-riscv)" >&2
    exit 1
  }
fi
if [[ ! -f "$POS" || ! -f "$NEG" ]]; then
  echo "error: missing case files under $CASES_DIR" >&2
  exit 1
fi

# Prefer python3 for JSONL; required offline (stdlib only).
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required for asm-stress" >&2
  exit 1
fi

export ROOT BIN TMP POS NEG HAVE_GAS GAS_AS GAS_OBJDUMP GAS_MARCH
python3 << 'PY'
import json, os, subprocess, sys, tempfile

ROOT = os.environ["ROOT"]
BIN = os.environ["BIN"]
TMP = os.environ["TMP"]
POS = os.environ["POS"]
NEG = os.environ["NEG"]
HAVE_GAS = os.environ["HAVE_GAS"] == "1"
GAS_AS = os.environ["GAS_AS"]
GAS_OBJDUMP = os.environ["GAS_OBJDUMP"]
GAS_MARCH = os.environ["GAS_MARCH"]

fail = 0
pos_ok = 0
neg_ok = 0
gas_ok = 0
gas_skip = 0


def wrap_hc(insns):
    lines = ["asm {", "  T::"]
    for ln in insns:
        lines.append("    " + ln)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def host_dump(insns):
    path = os.path.join(TMP, "case.hc")
    with open(path, "w") as f:
        f.write(wrap_hc(insns))
    r = subprocess.run([BIN, "--asm-dump", path], capture_output=True, text=True)
    words = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    return r.returncode, words, (r.stderr or "").strip()


def gas_dump(src: str, march: str):
    d = tempfile.mkdtemp(dir=TMP)
    s = os.path.join(d, "t.s")
    o = os.path.join(d, "t.o")
    with open(s, "w") as f:
        f.write(".text\n.globl _start\n_start:\n")
        for line in src.strip().splitlines():
            line = line.strip()
            if line:
                f.write("  " + line + "\n")
    r = subprocess.run([GAS_AS, f"-march={march}", s, "-o", o], capture_output=True, text=True)
    if r.returncode != 0:
        # Retry with D for float cases
        if "f" in src or "fa" in src or "ft" in src or "fs" in src:
            m2 = "rv64imafd_zicsr_zifencei"
            r = subprocess.run([GAS_AS, f"-march={m2}", s, "-o", o], capture_output=True, text=True)
            if r.returncode != 0:
                return None, r.stderr
        else:
            return None, r.stderr
    out = subprocess.check_output(
        [GAS_OBJDUMP, "-d", "-M", "no-aliases", o], text=True
    )
    words = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and ":" in parts[0]:
            hx = parts[1].strip().split()[0]
            if len(hx) == 8 and all(c in "0123456789abcdef" for c in hx):
                words.append(hx)
    return words, ""


def gas_src_from_case(case):
    g = case.get("gas", None)
    if g is False:
        return None
    if isinstance(g, str):
        return g
    # Derive: named label L: → 1: / 1f / 1b (forward refs only use 1f)
    insns = case["insns"]
    # If any backward ref to L after L: defined, use 1b for trailing branches to L
    out = []
    seen_L = False
    for ln in insns:
        if ln == "L:" or (ln.endswith(":") and ln[:-1].isalnum()):
            out.append("1:")
            seen_L = True
            continue
        s = ln
        if ", L" in s:
            s = s.replace(", L", ", 1b" if seen_L else ", 1f")
        if s.startswith("j L"):
            s = s.replace("j L", "j 1b" if seen_L else "j 1f", 1)
        out.append(s)
    return "\n".join(out)


with open(POS) as f:
    positives = [json.loads(l) for l in f if l.strip()]
with open(NEG) as f:
    negatives = [json.loads(l) for l in f if l.strip()]

print(f"asm-stress: {len(positives)} positive, {len(negatives)} negative"
      f" (gas={'yes' if HAVE_GAS else 'skip'})")

for case in positives:
    name = case["name"]
    expect = case["words"]
    rc, words, err = host_dump(case["insns"])
    if rc != 0:
        print(f"FAIL {name}: host --asm-dump rc={rc} {err}", file=sys.stderr)
        fail += 1
        continue
    if words != expect:
        print(f"FAIL {name}: host words {words} != golden {expect}", file=sys.stderr)
        fail += 1
        continue
    pos_ok += 1

    gsrc = gas_src_from_case(case)
    if not HAVE_GAS or gsrc is None:
        gas_skip += 1
    else:
        gw, gerr = gas_dump(gsrc, GAS_MARCH)
        if gw is None:
            print(f"FAIL {name}: gas assemble failed: {gerr}", file=sys.stderr)
            fail += 1
        elif gw != words:
            print(f"FAIL {name}: gas {gw} != host {words}", file=sys.stderr)
            fail += 1
        else:
            gas_ok += 1
    print(f"OK   {name}")

for case in negatives:
    name = case["name"]
    rc, words, err = host_dump(case["insns"])
    if rc == 0 and words:
        print(f"FAIL {name}: expected assemble failure, got {words}", file=sys.stderr)
        fail += 1
        continue
    if rc == 0:
        print(f"FAIL {name}: expected non-zero exit, got 0 with empty dump", file=sys.stderr)
        fail += 1
        continue
    neg_ok += 1
    print(f"OK   {name} (rejected rc={rc})")

print(
    f"✓ asm-stress: {pos_ok}/{len(positives)} positive, {neg_ok}/{len(negatives)} negative"
    f", gas-cross {gas_ok} (skipped {gas_skip})"
)
if fail:
    print(f"asm-stress: FAILED ({fail})", file=sys.stderr)
    sys.exit(1)
PY

# rv32 li regression: asm{} li expansion must not emit RV64 *W ops (illegal on
# rv32).  See tests/asm/rv32_li_test.py.
python3 "$ROOT/tests/asm/rv32_li_test.py"
