"""RISC-V RV64I encoding oracle — mirrors host/parser.c TryAssembleRiscV emit helpers."""

from __future__ import annotations

# ABI names indexed by x register number (matches host/parser.c RvRegNum).
REG_ABI = (
    "zero",  # x0
    "ra",    # x1
    "sp",    # x2
    "gp",    # x3
    "tp",    # x4
    "t0",    # x5
    "t1",    # x6
    "t2",    # x7
    "s0",    # x8 (fp alias)
    "s1",    # x9
    "a0",    # x10
    "a1",
    "a2",
    "a3",
    "a4",
    "a5",
    "a6",
    "a7",
    "s2",    # x18
    "s3",
    "s4",
    "s5",
    "s6",
    "s7",
    "s8",
    "s9",
    "s10",
    "s11",
    "t3",    # x28
    "t4",
    "t5",
    "t6",
)


def reg_name(n: int, rng=None) -> str:
    """Return a register token; optionally mix xN vs ABI via rng."""
    n &= 31
    if rng is not None and rng.random() < 0.25:
        return f"x{n}"
    if n == 8 and rng is not None and rng.random() < 0.5:
        return "fp"
    return REG_ABI[n]


def word_hex(w: int) -> str:
    return f"{w & 0xFFFFFFFF:08x}"


def rv_r(f7: int, f3: int, rd: int, rs1: int, rs2: int) -> int:
    return 0x33 | (rd << 7) | (f3 << 12) | (rs1 << 15) | (rs2 << 20) | (f7 << 25)


def rv_i(f3: int, rd: int, rs1: int, imm: int) -> int:
    return 0x13 | (rd << 7) | (f3 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20)


def rv_shift(f3: int, hi6: int, rd: int, rs1: int, sh: int) -> int:
    return 0x13 | (rd << 7) | (f3 << 12) | (rs1 << 15) | ((sh & 0x3F) << 20) | (hi6 << 26)


def rv_load(f3: int, rd: int, imm: int, rs1: int) -> int:
    return 0x03 | (rd << 7) | (f3 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20)


def rv_store(f3: int, rs2: int, imm: int, rs1: int) -> int:
    return (
        0x23
        | ((imm & 0x1F) << 7)
        | (f3 << 12)
        | (rs1 << 15)
        | (rs2 << 20)
        | (((imm >> 5) & 0x7F) << 25)
    )


def rv_br(f3: int, rs1: int, rs2: int, off: int) -> int:
    return (
        0x63
        | (((off >> 11) & 1) << 7)
        | (((off >> 1) & 0xF) << 8)
        | (f3 << 12)
        | (rs1 << 15)
        | (rs2 << 20)
        | (((off >> 5) & 0x3F) << 25)
        | (((off >> 12) & 1) << 31)
    )


def rv_j(rd: int, off: int) -> int:
    return (
        0x6F
        | (rd << 7)
        | (((off >> 12) & 0xFF) << 12)
        | (((off >> 11) & 1) << 20)
        | (((off >> 1) & 0x3FF) << 21)
        | (((off >> 20) & 1) << 31)
    )


def rv_jalr(rd: int, rs1: int, imm: int) -> int:
    return 0x67 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20)


def rv_u(opc: int, rd: int, imm20: int) -> int:
    return opc | (rd << 7) | ((imm20 & 0xFFFFF) << 12)


def encode_mnemonic(mn: str, rd=0, rs1=0, rs2=0, imm=0, boff=0) -> int:
    """Encode one assembled mnemonic (post-parse internal form)."""
    m = mn.lower()
    if m == "ret":
        return rv_jalr(0, 1, 0)
    if m == "nop":
        return rv_i(0, 0, 0, 0)
    if m == "mret":
        return 0x30200073
    if m == "sret":
        return 0x10200073
    if m == "ecall":
        return 0x00000073
    if m == "ebreak":
        return 0x00100073
    if m == "wfi":
        return 0x10500073
    if m == "fencei":
        return 0x0000100F
    if m == "mv":
        return rv_i(0, rd, rs1, 0)
    if m == "not":
        return rv_i(4, rd, rs1, -1)
    if m == "neg":
        return rv_r(0x20, 0, rd, 0, rs1)
    if m == "li":
        return rv_i(0, rd, 0, imm)
    if m == "j":
        return rv_j(0, boff)
    if m == "beqz":
        return rv_br(0, rs1, 0, boff)
    if m == "bnez":
        return rv_br(1, rs1, 0, boff)
    if m == "beq":
        return rv_br(0, rs1, rs2, boff)
    if m == "bne":
        return rv_br(1, rs1, rs2, boff)
    if m == "blt":
        return rv_br(4, rs1, rs2, boff)
    if m == "bge":
        return rv_br(5, rs1, rs2, boff)
    if m == "bltu":
        return rv_br(6, rs1, rs2, boff)
    if m == "bgeu":
        return rv_br(7, rs1, rs2, boff)
    loads = {
        "ld": 3,
        "lw": 2,
        "lwu": 6,
        "lh": 1,
        "lhu": 5,
        "lb": 0,
        "lbu": 4,
    }
    if m in loads:
        return rv_load(loads[m], rd, imm, rs1)
    stores = {"sd": 3, "sw": 2, "sh": 1, "sb": 0}
    if m in stores:
        return rv_store(stores[m], rs2, imm, rs1)
    if m == "jalr":
        return rv_jalr(rd, rs1, imm)
    if m == "addi":
        return rv_i(0, rd, rs1, imm)
    if m == "andi":
        return rv_i(7, rd, rs1, imm)
    if m == "ori":
        return rv_i(6, rd, rs1, imm)
    if m == "xori":
        return rv_i(4, rd, rs1, imm)
    if m == "slti":
        return rv_i(2, rd, rs1, imm)
    if m == "slli":
        return rv_shift(1, 0, rd, rs1, imm)
    if m == "srli":
        return rv_shift(5, 0, rd, rs1, imm)
    if m == "srai":
        return rv_shift(5, 0x10, rd, rs1, imm)
    rmap = {
        "add": (0, 0),
        "sub": (0x20, 0),
        "and": (0, 7),
        "or": (0, 6),
        "xor": (0, 4),
        "sll": (0, 1),
        "srl": (0, 5),
        "sra": (0x20, 5),
        "slt": (0, 2),
        "sltu": (0, 3),
        "mul": (1, 0),
        "div": (1, 4),
        "rem": (1, 6),
        "divu": (1, 5),
        "remu": (1, 7),
    }
    if m in rmap:
        f7, f3 = rmap[m]
        return rv_r(f7, f3, rd, rs1, rs2)
    if m == "lui":
        return rv_u(0x37, rd, imm)
    if m == "auipc":
        return rv_u(0x17, rd, imm)
    raise KeyError(mn)
