#!/usr/bin/env python3
"""Property-based assembler semantics tests (host TryAssembleRiscV vs riscv_oracle).

Generates random valid RV64I (+ M) instruction patterns, assembles via holyc-riscv
--asm-dump, and compares encodings to the Python oracle. Also checks that out-of-range
immediates are rejected and replays positive.jsonl goldens through the oracle.
"""

from __future__ import annotations

import json
import os
import random
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Optional, Sequence, Tuple

from riscv_oracle import REG_ABI, encode_mnemonic, reg_name, word_hex

ROOT = Path(__file__).resolve().parents[2]
CASES_DIR = Path(__file__).resolve().parent / "cases"
POSITIVE = CASES_DIR / "positive.jsonl"


@dataclass
class PropCase:
    name: str
    insns: List[str]
    expect: List[str]
    expect_fail: bool = False


def wrap_hc(insns: Sequence[str]) -> str:
    lines = ["asm {", "  T::"]
    for ln in insns:
        lines.append("    " + ln)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def batch_hc(cases: Sequence[PropCase]) -> str:
    return "\n".join(wrap_hc(c.insns) for c in cases)


def host_dump_batch(
    bin_path: Path, cases: Sequence[PropCase], tmp: Path
) -> Tuple[int, List[List[str]], str]:
    hc = tmp / "batch.hc"
    hc.write_text(batch_hc(cases))
    r = subprocess.run(
        [str(bin_path), "--asm-dump", str(hc)], capture_output=True, text=True
    )
    words = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    if r.returncode != 0:
        return r.returncode, [], (r.stderr or "").strip()
    # Split flat word list by expected lengths per case.
    chunks: List[List[str]] = []
    i = 0
    for c in cases:
        n = len(c.expect)
        chunks.append(words[i : i + n])
        i += n
    if i != len(words):
        return 1, chunks, f"word count mismatch: got {len(words)}, expected {sum(len(c.expect) for c in cases)}"
    return 0, chunks, ""


def host_dump_one(bin_path: Path, insns: Sequence[str], tmp: Path) -> Tuple[int, List[str], str]:
    c = PropCase("one", list(insns), [])
    rc, chunks, err = host_dump_batch(bin_path, [c], tmp)
    return rc, chunks[0] if chunks else [], err


# --- generators (RV64I core + M extension) ---------------------------------

SIMM12 = range(-2048, 2048)
SHAMT = range(0, 64)
UIMM20_POS = range(0, 0x100000)  # 0..0xFFFFF
UIMM20_NEG = range(-0x80000, 0)  # sign-extended 20-bit negatives


def _i_arith(rng: random.Random, mn: str) -> PropCase:
    rd, rs1 = rng.randint(0, 31), rng.randint(0, 31)
    imm = rng.choice(list(SIMM12))
    r1, r2 = reg_name(rd, rng), reg_name(rs1, rng)
    insns = [f"{mn} {r1}, {r2}, {imm}"]
    w = word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1, imm=imm))
    return PropCase(f"{mn}", insns, [w])


def _shift(rng: random.Random, mn: str, hi6: int) -> PropCase:
    rd, rs1 = rng.randint(0, 31), rng.randint(0, 31)
    sh = rng.choice(list(SHAMT))
    r1, r2 = reg_name(rd, rng), reg_name(rs1, rng)
    insns = [f"{mn} {r1}, {r2}, {sh}"]
    from riscv_oracle import rv_shift

    f3 = {"slli": 1, "srli": 5, "srai": 5}[mn]
    w = word_hex(rv_shift(f3, hi6, rd, rs1, sh))
    return PropCase(mn, insns, [w])


def _rtype(rng: random.Random, mn: str) -> PropCase:
    rd, rs1, rs2 = rng.randint(0, 31), rng.randint(0, 31), rng.randint(0, 31)
    insns = [
        f"{mn} {reg_name(rd, rng)}, {reg_name(rs1, rng)}, {reg_name(rs2, rng)}"
    ]
    w = word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1, rs2=rs2))
    return PropCase(mn, insns, [w])


def _load(rng: random.Random, mn: str) -> PropCase:
    rd, rs1 = rng.randint(0, 31), rng.randint(0, 31)
    imm = rng.choice(list(SIMM12))
    insns = [f"{mn} {reg_name(rd, rng)}, {imm}({reg_name(rs1, rng)})"]
    w = word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1, imm=imm))
    return PropCase(mn, insns, [w])


def _store(rng: random.Random, mn: str) -> PropCase:
    rs2, rs1 = rng.randint(0, 31), rng.randint(0, 31)
    imm = rng.choice(list(SIMM12))
    insns = [f"{mn} {reg_name(rs2, rng)}, {imm}({reg_name(rs1, rng)})"]
    w = word_hex(encode_mnemonic(mn, rs2=rs2, rs1=rs1, imm=imm))
    return PropCase(mn, insns, [w])


def _u_type(rng: random.Random, mn: str) -> PropCase:
    rd = rng.randint(0, 31)
    imm = rng.choice(list(UIMM20_POS) if rng.random() < 0.85 else list(UIMM20_NEG))
    insns = [f"{mn} {reg_name(rd, rng)}, {imm if imm >= 0 else imm}"]
    w = word_hex(encode_mnemonic(mn, rd=rd, imm=imm))
    return PropCase(mn, insns, [w])


def _jalr(rng: random.Random) -> PropCase:
    if rng.random() < 0.3:
        rs1 = rng.randint(0, 31)
        insns = [f"jalr {reg_name(rs1, rng)}"]
        w = word_hex(encode_mnemonic("jalr", rd=1, rs1=rs1, imm=0))
        return PropCase("jalr_short", insns, [w])
    rd, rs1 = rng.randint(0, 31), rng.randint(0, 31)
    imm = rng.choice(list(SIMM12))
    insns = [f"jalr {reg_name(rd, rng)}, {imm}({reg_name(rs1, rng)})"]
    w = word_hex(encode_mnemonic("jalr", rd=rd, rs1=rs1, imm=imm))
    return PropCase("jalr", insns, [w])


def _branch(rng: random.Random, mn: str, rs2_reg: bool) -> PropCase:
    rs1 = rng.randint(0, 31)
    rs2 = rng.randint(0, 31) if rs2_reg else 0
    fwd = rng.random() < 0.5
    if rs2_reg:
        op = f"{mn} {reg_name(rs1, rng)}, {reg_name(rs2, rng)}, L"
    else:
        op = f"{mn} {reg_name(rs1, rng)}, L"
    if fwd:
        insns = [op, "nop", "L:", "nop"]
        boff = 8  # branch at i=0, label.idx=2 → (2-0)*4
    else:
        insns = ["L:", "nop", op]
        boff = -4  # label.idx=0, branch at i=1 → (0-1)*4
    w0 = word_hex(encode_mnemonic(mn, rs1=rs1, rs2=rs2, boff=boff))
    if fwd:
        expect = [w0, "00000013", "00000013"]
    else:
        expect = ["00000013", w0]
    return PropCase(f"{mn}_{'fwd' if fwd else 'back'}", insns, expect)


def _jump(rng: random.Random) -> PropCase:
    fwd = rng.random() < 0.5
    if fwd:
        insns = ["j L", "nop", "L:", "nop"]
        boff = 8
        expect = [word_hex(encode_mnemonic("j", boff=boff)), "00000013", "00000013"]
    else:
        insns = ["L:", "nop", "j L"]
        boff = -4  # label.idx=0, j at i=1
        expect = ["00000013", word_hex(encode_mnemonic("j", boff=boff))]
    return PropCase(f"j_{'fwd' if fwd else 'back'}", insns, expect)


def _li_narrow(rng: random.Random) -> PropCase:
    rd = rng.randint(0, 31)
    imm = rng.choice(list(SIMM12))
    insns = [f"li {reg_name(rd, rng)}, {imm}"]
    w = word_hex(encode_mnemonic("li", rd=rd, imm=imm))
    return PropCase("li_narrow", insns, [w])


def _pseudo(rng: random.Random, mn: str) -> PropCase:
    rd, rs1 = rng.randint(0, 31), rng.randint(0, 31)
    insns = [f"{mn} {reg_name(rd, rng)}, {reg_name(rs1, rng)}"]
    w = word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1))
    return PropCase(mn, insns, [w])


def _zero(rng: random.Random) -> PropCase:
    insns = ["addi zero, zero, 0"]
    return PropCase("zero_alias", insns, ["00000013"])


GENERATORS: List[Tuple[str, Callable[[random.Random], PropCase]]] = [
    ("addi", lambda r: _i_arith(r, "addi")),
    ("andi", lambda r: _i_arith(r, "andi")),
    ("ori", lambda r: _i_arith(r, "ori")),
    ("xori", lambda r: _i_arith(r, "xori")),
    ("slti", lambda r: _i_arith(r, "slti")),
    ("slli", lambda r: _shift(r, "slli", 0)),
    ("srli", lambda r: _shift(r, "srli", 0)),
    ("srai", lambda r: _shift(r, "srai", 0x10)),
    ("add", lambda r: _rtype(r, "add")),
    ("sub", lambda r: _rtype(r, "sub")),
    ("and", lambda r: _rtype(r, "and")),
    ("or", lambda r: _rtype(r, "or")),
    ("xor", lambda r: _rtype(r, "xor")),
    ("sll", lambda r: _rtype(r, "sll")),
    ("srl", lambda r: _rtype(r, "srl")),
    ("sra", lambda r: _rtype(r, "sra")),
    ("slt", lambda r: _rtype(r, "slt")),
    ("sltu", lambda r: _rtype(r, "sltu")),
    ("mul", lambda r: _rtype(r, "mul")),
    ("div", lambda r: _rtype(r, "div")),
    ("rem", lambda r: _rtype(r, "rem")),
    ("divu", lambda r: _rtype(r, "divu")),
    ("remu", lambda r: _rtype(r, "remu")),
    ("ld", lambda r: _load(r, "ld")),
    ("lw", lambda r: _load(r, "lw")),
    ("lwu", lambda r: _load(r, "lwu")),
    ("lh", lambda r: _load(r, "lh")),
    ("lhu", lambda r: _load(r, "lhu")),
    ("lb", lambda r: _load(r, "lb")),
    ("lbu", lambda r: _load(r, "lbu")),
    ("sd", lambda r: _store(r, "sd")),
    ("sw", lambda r: _store(r, "sw")),
    ("sh", lambda r: _store(r, "sh")),
    ("sb", lambda r: _store(r, "sb")),
    ("lui", lambda r: _u_type(r, "lui")),
    ("auipc", lambda r: _u_type(r, "auipc")),
    ("jalr", _jalr),
    ("beq", lambda r: _branch(r, "beq", True)),
    ("bne", lambda r: _branch(r, "bne", True)),
    ("blt", lambda r: _branch(r, "blt", True)),
    ("bge", lambda r: _branch(r, "bge", True)),
    ("bltu", lambda r: _branch(r, "bltu", True)),
    ("bgeu", lambda r: _branch(r, "bgeu", True)),
    ("beqz", lambda r: _branch(r, "beqz", False)),
    ("bnez", lambda r: _branch(r, "bnez", False)),
    ("j", _jump),
    ("li_narrow", _li_narrow),
    ("mv", lambda r: _pseudo(r, "mv")),
    ("not", lambda r: _pseudo(r, "not")),
    ("neg", lambda r: _pseudo(r, "neg")),
    ("zero", _zero),
]


def gen_reject_cases(rng: random.Random) -> List[PropCase]:
    """Out-of-range immediates — host must fail assembly."""
    r1, r2 = reg_name(10, rng), reg_name(11, rng)
    base = reg_name(8, rng)
    cases = [
        PropCase("reject_addi_hi", [f"addi {r1}, {r2}, 2048"], [], True),
        PropCase("reject_addi_lo", [f"addi {r1}, {r2}, -2049"], [], True),
        PropCase("reject_ld_hi", [f"ld {r1}, 2048({base})"], [], True),
        PropCase("reject_ld_lo", [f"ld {r1}, -2049({base})"], [], True),
        PropCase("reject_slli", [f"slli {r1}, {r2}, 64"], [], True),
        PropCase("reject_lui_addr", [f"lui {r1}, 0x81397000"], [], True),
        PropCase("reject_jal_bare", ["jal L"], [], True),
    ]
    rng.shuffle(cases)
    return cases


def replay_positive_oracle() -> Tuple[int, int]:
    """Every positive.jsonl golden must match riscv_oracle re-encode where applicable."""
    if not POSITIVE.is_file():
        return 0, 0
    skip_prefixes = (
        "li_a0_2048",
        "li_a0_m2049",
        "li_a0_wide",
        "li_a0_hi",
        "semi_sep",
        "faddd",
        "fmv",
        "rdtime",
        "sfence",
        "lr_",
        "sc_",
        "amo",
        "csr",
        "fence",
        "ecall",
        "ebreak",
        "mret",
        "sret",
        "wfi",
        "nop",
        "ret",
        "regs_",
        "fp_",
        "zero_alias",
    )
    ok = skip = 0
    with open(POSITIVE) as f:
        for line in f:
            if not line.strip():
                continue
            case = json.loads(line)
            name = case["name"]
            if any(name.startswith(p) or p in name for p in skip_prefixes):
                skip += 1
                continue
            # Single-insn oracle replay only (branches/jumps use label layout — covered by generators).
            if len(case["insns"]) != 1:
                skip += 1
                continue
            insn = case["insns"][0]
            # Skip if not in our oracle surface (CSRs, A-ext, float, …).
            tok = insn.split()[0].lower()
            try:
                # Minimal parse for oracle — only handles simple single-insn forms tested here.
                words = _oracle_from_asm_line(insn)
            except (KeyError, ValueError, IndexError):
                skip += 1
                continue
            if words != case["words"]:
                print(
                    f"FAIL oracle replay {name}: oracle {words} != golden {case['words']}",
                    file=sys.stderr,
                )
                return ok, 1
            ok += 1
    return ok, 0


def _parse_reg(s: str) -> int:
    s = s.strip().lower()
    if s in ("fp", "s0"):
        return 8
    if s.startswith("x"):
        return int(s[1:])
    for i, n in enumerate(REG_ABI):
        if n == s:
            return i
    raise ValueError(s)


def _oracle_from_asm_line(insn: str) -> List[str]:
    """Best-effort single-line decode → oracle words (RV64I/M subset)."""
    parts = [p.strip() for p in insn.replace("(", " ( ").replace(")", " ) ").split()]
    mn = parts[0].lower()
    if mn in ("mv", "not", "neg"):
        rd, rs1 = _parse_reg(parts[1].rstrip(",")), _parse_reg(parts[2])
        return [word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1))]
    if mn in ("addi", "andi", "ori", "xori", "slti"):
        rd, rs1, imm = _parse_reg(parts[1].rstrip(",")), _parse_reg(parts[2].rstrip(",")), int(parts[3])
        return [word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1, imm=imm))]
    if mn in ("slli", "srli", "srai"):
        rd, rs1, sh = _parse_reg(parts[1].rstrip(",")), _parse_reg(parts[2].rstrip(",")), int(parts[3])
        from riscv_oracle import rv_shift

        f3, hi6 = {"slli": (1, 0), "srli": (5, 0), "srai": (5, 0x10)}[mn]
        return [word_hex(rv_shift(f3, hi6, rd, rs1, sh))]
    if mn in ("add", "sub", "and", "or", "xor", "sll", "srl", "sra", "slt", "sltu", "mul", "div", "rem", "divu", "remu"):
        rd, rs1, rs2 = _parse_reg(parts[1].rstrip(",")), _parse_reg(parts[2].rstrip(",")), _parse_reg(parts[3])
        return [word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1, rs2=rs2))]
    if mn in ("ld", "lw", "lwu", "lh", "lhu", "lb", "lbu"):
        rd = _parse_reg(parts[1].rstrip(","))
        imm = int(parts[2])
        rs1 = _parse_reg(parts[4].rstrip(")"))
        return [word_hex(encode_mnemonic(mn, rd=rd, rs1=rs1, imm=imm))]
    if mn in ("sd", "sw", "sh", "sb"):
        rs2 = _parse_reg(parts[1].rstrip(","))
        imm = int(parts[2])
        rs1 = _parse_reg(parts[4].rstrip(")"))
        return [word_hex(encode_mnemonic(mn, rs2=rs2, rs1=rs1, imm=imm))]
    if mn in ("lui", "auipc"):
        rd, imm = _parse_reg(parts[1].rstrip(",")), int(parts[2], 0)
        return [word_hex(encode_mnemonic(mn, rd=rd, imm=imm))]
    if mn == "li":
        rd, imm = _parse_reg(parts[1].rstrip(",")), int(parts[2], 0)
        return [word_hex(encode_mnemonic("li", rd=rd, imm=imm))]
    if mn == "jalr":
        if len(parts) == 2:
            rs1 = _parse_reg(parts[1])
            return [word_hex(encode_mnemonic("jalr", rd=1, rs1=rs1, imm=0))]
        rd = _parse_reg(parts[1].rstrip(","))
        imm = int(parts[2])
        rs1 = _parse_reg(parts[4].rstrip(")"))
        return [word_hex(encode_mnemonic("jalr", rd=rd, rs1=rs1, imm=imm))]
    raise KeyError(mn)


def run_encode_props(
    bin_path: Path, rng: random.Random, trials: int, batch: int, tmp: Path
) -> Tuple[int, int]:
    fail = 0
    ok = 0
    for start in range(0, trials, batch):
        chunk: List[PropCase] = []
        for _ in range(min(batch, trials - start)):
            tag, gen = rng.choice(GENERATORS)
            c = gen(rng)
            c.name = f"prop_{start + len(chunk)}_{tag}"
            chunk.append(c)
        rc, got_chunks, err = host_dump_batch(bin_path, chunk, tmp)
        if rc != 0:
            print(f"FAIL batch rc={rc}: {err}", file=sys.stderr)
            fail += len(chunk)
            continue
        for c, got in zip(chunk, got_chunks):
            if got != c.expect:
                print(
                    f"FAIL {c.name}: host {got} != oracle {c.expect}\n  insns: {c.insns}",
                    file=sys.stderr,
                )
                fail += 1
            else:
                ok += 1
    return ok, fail


def run_reject_props(bin_path: Path, rng: random.Random, trials: int, tmp: Path) -> Tuple[int, int]:
    pool = gen_reject_cases(rng)
    fail = ok = 0
    for i in range(trials):
        c = pool[i % len(pool)]
        rc, words, err = host_dump_one(bin_path, c.insns, tmp)
        if rc == 0 and words:
            print(f"FAIL reject {c.name}: expected failure, got {words}", file=sys.stderr)
            fail += 1
        elif rc == 0:
            print(f"FAIL reject {c.name}: expected failure, rc=0 empty", file=sys.stderr)
            fail += 1
        else:
            ok += 1
    return ok, fail


def main() -> int:
    seed = int(os.environ.get("ASM_PROP_SEED", "42"))
    trials = int(os.environ.get("ASM_PROP_TRIALS", "400"))
    reject_trials = int(os.environ.get("ASM_PROP_REJECT", "28"))
    batch = int(os.environ.get("ASM_PROP_BATCH", "40"))
    bin_path = Path(os.environ.get("HOLYC_BIN", ROOT / "holyc-riscv"))

    if not bin_path.is_file():
        print(f"error: missing {bin_path} (run make holyc-riscv)", file=sys.stderr)
        return 1

    rng = random.Random(seed)
    tmp = Path(tempfile.mkdtemp(prefix="holyc_asm_prop_"))

    print(
        f"asm-prop: seed={seed} encode_trials={trials} reject={reject_trials} batch={batch}"
    )

    rep_ok, rep_fail = replay_positive_oracle()
    print(f"  oracle replay: {rep_ok} single-insn goldens checked")

    enc_ok, enc_fail = run_encode_props(bin_path, rng, trials, batch, tmp)
    rej_ok, rej_fail = run_reject_props(bin_path, rng, reject_trials, tmp)

    total_fail = rep_fail + enc_fail + rej_fail
    print(
        f"✓ asm-prop: encode {enc_ok}/{trials}, reject {rej_ok}/{reject_trials}, "
        f"oracle replay {rep_ok} (failures {total_fail})"
    )
    if total_fail:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
