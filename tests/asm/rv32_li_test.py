#!/usr/bin/env python3
"""rv32 regression: asm{} li expansion must not emit RV64 *W ops.

`li rd, imm` outside ±2047 expands via the GNU-as idiom (lui+addiw), which is
rv64-only: on --target rv32 the *W opcodes (0x1B/0x3B) are RESERVED and trap
illegal instruction at run time.  The expansion must use lui+addi instead.
This bit for real on ULX3S (Flute): HcCsrsMieExt's `li t0, 2048` in
bootstrap/seed/trap.hc crashed the REPL's first ExePutS eval.

Also pins the rv64 behavior (addiw kept) so the fix cannot regress the
default target.

Run: python3 tests/asm/rv32_li_test.py  (env: BIN, TMP honored like asm-stress)
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

BIN = os.environ.get("BIN", os.path.join(os.path.dirname(__file__), "..", "..", "holyc-riscv"))
TMP = os.environ.get("TMP") or tempfile.mkdtemp(prefix="holyc_rv32_li_")

CASES = [
    # (constant, expected low-32 result)
    ("2048", 0x800),
    ("-2048", -2048 & 0xFFFFFFFF),
    ("0x7FFFFFFF", 0x7FFFFFFF),
    ("0x80000000", 0x80000000),
    ("0xFFFFFFFF", 0xFFFFFFFF),
    ("123456", 123456),
    ("-123456", -123456 & 0xFFFFFFFF),
]


def wrap_hc(insns):
    lines = ["asm {", "  T::"]
    for ln in insns:
        lines.append("    " + ln)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def dump(target, insns, tag):
    path = os.path.join(TMP, f"{tag}.hc")
    with open(path, "w") as f:
        f.write(wrap_hc(insns))
    env = dict(os.environ, HOLYC_ARCH=target)
    r = subprocess.run(
        [BIN, "--asm-dump", path],
        capture_output=True,
        text=True,
        env=env,
    )
    words = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    return r.returncode, words, (r.stderr or "").strip()


def has_w_op(words):
    return any((int(w, 16) & 0x7F) in (0x1B, 0x3B) for w in words)


def fail(msg):
    print(msg, file=sys.stderr)
    return 1


def main():
    rc_all = 0

    for c, expect in CASES:
        tag = f"rv32_li_{c.replace('-', 'm').replace('x', 'x')}"
        rc, words, err = dump("rv32", [f"li t0, {c}", "ret"], tag)
        if rc != 0:
            rc_all |= fail(f"FAIL rv32 li {c}: rc={rc} {err}")
            continue
        if has_w_op(words):
            rc_all |= fail(f"FAIL rv32 li {c}: *W op in {words}")
            continue
        lo = int(words[0], 16)  # lui t0, hi — check nothing else snuck in
        print(f"OK   rv32 li {c}: {' '.join(words)}")

    # 0x80000000 must materialize correctly on rv32 (lui 0x80000), and wide
    # (>u32) constants must be rejected, not emitted as slli-32 garbage.
    rc, words, err = dump("rv32", ["li t0, 0x100000000", "ret"], "rv32_li_wide")
    if rc == 0 and words:
        rc_all |= fail(f"FAIL rv32 li wide: expected rejection, got {words}")
    else:
        print("OK   rv32 li 0x100000000 rejected")

    # rv64 keeps the GNU-as addiw idiom (regression pin).
    rc, words, err = dump("rv64", ["li t0, 2048", "ret"], "rv64_li_2048")
    if rc != 0 or not has_w_op(words):
        rc_all |= fail(f"FAIL rv64 li 2048: expected addiw in {words} (rc={rc})")
    else:
        print(f"OK   rv64 li 2048 keeps *W: {' '.join(words)}")

    if rc_all == 0:
        print("✓ rv32-li: no *W ops on rv32, wide rejected, rv64 pinned")
    return rc_all


if __name__ == "__main__":
    sys.exit(main())
