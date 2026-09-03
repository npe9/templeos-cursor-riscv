#!/usr/bin/env python3
"""P0 closed loop: RV64I OP-IMM I-type model vs riscv_oracle.rv_i (+ extracted C RvI).

Exit 0: model (and C, if built) match the oracle on the checked domain.
Exit 1: mismatch (or --expect-fail did not see a failure).

Modes:
  (default)     Exhaustive f3×rd×rs1×imm12 equivalence; compile+check C RvI.
  --seed-bug    Rebuild C with -DRV_I_SEED_BUG and require a mismatch (fail demo).
  --expect-fail Invert: succeed only if a mismatch is found (used by seed-bug).
"""

from __future__ import annotations

import argparse
import ctypes
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
ORACLE_PATH = REPO / "tests" / "asm" / "riscv_oracle.py"
RV_I_C = HERE / "rv_i.c"
MODEL_PATH = HERE / "rv_i_model.py"


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _build_lib(out_dir: Path, seed_bug: bool) -> Path:
    lib = out_dir / ("rv_i_bug.so" if seed_bug else "rv_i.so")
    cmd = [
        os.environ.get("CC", "cc"),
        "-shared",
        "-fPIC",
        "-O0",
        "-o",
        str(lib),
        str(RV_I_C),
    ]
    if seed_bug:
        cmd.insert(-1, "-DRV_I_SEED_BUG")
    subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return lib


def _load_c_rvi(lib_path: Path):
    lib = ctypes.CDLL(str(lib_path))
    lib.RvI.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lib.RvI.restype = ctypes.c_uint32
    return lib.RvI


def _iter_domain(exhaustive_imm: bool):
    """Yield (f3, rd, rs1, imm) covering the legal encode domain."""
    for f3 in range(8):
        for rd in range(32):
            for rs1 in range(32):
                if exhaustive_imm:
                    for imm in range(4096):
                        yield f3, rd, rs1, imm
                        # also signed form that masks to same bits
                        if imm >= 2048:
                            yield f3, rd, rs1, imm - 4096
                else:
                    # Dense edges + stride (fast default; full with --exhaustive)
                    edges = (
                        list(range(-2048, -2040))
                        + list(range(-16, 17))
                        + list(range(2040, 2048))
                        + [0, 1, -1, 0x7FF, -2048, 0x800, 0xFFF, -4095]
                    )
                    for imm in edges:
                        yield f3, rd, rs1, imm
                    for imm in range(-2048, 2048, 17):
                        yield f3, rd, rs1, imm


def check(
    *,
    seed_bug: bool,
    expect_fail: bool,
    exhaustive: bool,
    build_dir: Path | None,
) -> int:
    oracle = _load_module(ORACLE_PATH, "riscv_oracle")
    model = _load_module(MODEL_PATH, "rv_i_model")

    out = build_dir or Path(tempfile.mkdtemp(prefix="verify_p0_rv_i_"))
    out.mkdir(parents=True, exist_ok=True)
    lib_path = _build_lib(out, seed_bug=seed_bug)
    c_rvi = _load_c_rvi(lib_path)

    mismatches = []
    n = 0
    for f3, rd, rs1, imm in _iter_domain(exhaustive):
        n += 1
        want = oracle.rv_i(f3, rd, rs1, imm) & 0xFFFFFFFF
        got_m = model.encode_op_imm_i(f3, rd, rs1, imm) & 0xFFFFFFFF
        got_c = int(c_rvi(f3, rd, rs1, imm)) & 0xFFFFFFFF

        if got_m != want:
            mismatches.append(("model", f3, rd, rs1, imm, want, got_m))
        if got_c != want:
            mismatches.append(("c", f3, rd, rs1, imm, want, got_c))
        if mismatches and len(mismatches) >= 8:
            break

        # Round-trip only when C/model match OP-IMM (skip under seed-bug)
        if not seed_bug and got_m == want:
            f3d, rdd, rs1d, immd = model.decode_op_imm_i(got_m)
            if (f3d, rdd, rs1d, immd) != (f3 & 7, rd & 31, rs1 & 31, imm & 0xFFF):
                mismatches.append(("decode", f3, rd, rs1, imm, want, got_m))
                break

    tag = "SEED-BUG" if seed_bug else "OK-PATH"
    if expect_fail:
        if mismatches:
            m = mismatches[0]
            print(
                f"PASS ({tag}): checker caught mismatch "
                f"{m[0]} f3={m[1]} rd={m[2]} rs1={m[3]} imm={m[4]} "
                f"oracle=0x{m[5]:08x} got=0x{m[6]:08x}  (n≈{n})"
            )
            return 0
        print(f"FAIL ({tag}): expected a mismatch but model/C matched oracle (n={n})")
        return 1

    if mismatches:
        print(f"FAIL ({tag}): {len(mismatches)} mismatch(es) after {n} trials")
        for m in mismatches[:5]:
            print(
                f"  {m[0]}: f3={m[1]} rd={m[2]} rs1={m[3]} imm={m[4]} "
                f"oracle=0x{m[5]:08x} got=0x{m[6]:08x}"
            )
        return 1

    print(
        f"PASS ({tag}): model + C RvI ≡ riscv_oracle.rv_i "
        f"({n} vectors; exhaustive_imm={exhaustive})"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--seed-bug",
        action="store_true",
        help="Compile C with wrong opcode; require mismatch (--expect-fail implied)",
    )
    ap.add_argument(
        "--expect-fail",
        action="store_true",
        help="Succeed only if a model/C vs oracle mismatch is found",
    )
    ap.add_argument(
        "--exhaustive",
        action="store_true",
        help="Full 12-bit imm domain (slower; ~8*32*32*4096)",
    )
    ap.add_argument(
        "--build-dir",
        type=Path,
        default=None,
        help="Directory for compiled .so (default: temp or build/verify/p0_rv_i)",
    )
    args = ap.parse_args(argv)
    expect_fail = args.expect_fail or args.seed_bug
    build = args.build_dir
    if build is None:
        build = REPO / "build" / "verify" / "p0_rv_i"
    return check(
        seed_bug=args.seed_bug,
        expect_fail=expect_fail,
        exhaustive=args.exhaustive,
        build_dir=build,
    )


if __name__ == "__main__":
    sys.exit(main())
