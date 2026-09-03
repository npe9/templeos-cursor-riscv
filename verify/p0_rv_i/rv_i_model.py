"""Independent RV64I OP-IMM I-type encoder (field packing, not a copy of the oracle).

Mirrors RISC-V unprivileged ISA I-type layout for opcode OP-IMM (0x13):

  [31:20] imm[11:0] | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode

Equivalence target: tests/asm/riscv_oracle.py::rv_i and host/parser.c RvI.
"""

from __future__ import annotations

OP_IMM = 0b0010011  # 0x13


def encode_op_imm_i(funct3: int, rd: int, rs1: int, imm: int) -> int:
    """Build one OP-IMM I-type word from named fields."""
    opcode = OP_IMM
    f3 = funct3 & 0x7
    rd5 = rd & 0x1F
    rs1_5 = rs1 & 0x1F
    imm12 = imm & 0xFFF
    word = 0
    word |= opcode
    word |= rd5 << 7
    word |= f3 << 12
    word |= rs1_5 << 15
    word |= imm12 << 20
    return word & 0xFFFFFFFF


def decode_op_imm_i(word: int) -> tuple[int, int, int, int]:
    """Inverse field extract (sanity for round-trip checks)."""
    w = word & 0xFFFFFFFF
    opcode = w & 0x7F
    rd = (w >> 7) & 0x1F
    f3 = (w >> 12) & 0x7
    rs1 = (w >> 15) & 0x1F
    imm = (w >> 20) & 0xFFF
    if opcode != OP_IMM:
        raise ValueError(f"not OP-IMM: opcode=0x{opcode:x}")
    return f3, rd, rs1, imm
