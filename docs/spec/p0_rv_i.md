# Spec note — P0: RV64I OP-IMM `RvI`

**Status:** closed loop (optional `make verify-p0`).  
**Strength:** model-checked equivalence (exhaustive / dense domain), not a Frama WP proof.

## Choice

Prove/model **one** host encode helper: `RvI` in `host/parser.c` (OP-IMM I-type,
opcode `0x13`), used by `TryAssembleRiscV` for `addi` / `andi` / `ori` / …

```c
static U32 RvI(U32 f3, int rd, int rs1, int imm) {
  return 0x13u | (rd << 7) | (f3 << 12) | (rs1 << 15) | (((U32)imm & 0xFFF) << 20);
}
```

## Approach (tractable)

**Thin Python field model + differential vs `tests/asm/riscv_oracle.py::rv_i`**, plus
an extracted C twin (`verify/p0_rv_i/rv_i.c`) loaded via ctypes.

Rationale vs Frama/Dafny: zero new toolchain; reuses the existing CI oracle as the
single encode truth; still demonstrates *spec → check → seeded bug fails → fix*.

| Layer | Artifact |
|-------|----------|
| Spec / model | `verify/p0_rv_i/rv_i_model.py` (named ISA fields) |
| Oracle truth | `tests/asm/riscv_oracle.py::rv_i` |
| Implementation twin | `verify/p0_rv_i/rv_i.c` ≡ `host/parser.c` `RvI` |
| Harness | `verify/p0_rv_i/run_p0.py` |

## Laws checked

1. `encode_op_imm_i(f3,rd,rs1,imm) == rv_i(f3,rd,rs1,imm)` on the checked domain.
2. Extracted C `RvI` matches the same oracle words.
3. Decode round-trip recovers `(f3, rd, rs1, imm12)` when opcode is OP-IMM.
4. Seeded wrong opcode (`-DRV_I_SEED_BUG` → `0x33`) **must** mismatch the oracle.

## How to run

```bash
make verify-p0
# Pass path + intentional fail demo (both must succeed as a pair):
python3 verify/p0_rv_i/run_p0.py
python3 verify/p0_rv_i/run_p0.py --seed-bug
```

Optional full imm12 sweep: `python3 verify/p0_rv_i/run_p0.py --exhaustive`.

## Pass / fail demo

| Command | Expected |
|---------|----------|
| `run_p0.py` | `PASS (OK-PATH): model + C RvI ≡ riscv_oracle.rv_i …` |
| `run_p0.py --seed-bug` | `PASS (SEED-BUG): checker caught mismatch c …` (wrong opcode) |

If the seed-bug build accidentally matched the oracle, the harness exits 1
(`expected a mismatch`). Fix = remove `-DRV_I_SEED_BUG` / restore opcode `0x13`.

## Out of scope (P0)

Frama ACSL on live `parser.c`, guest `Compiler/Asm_RV.HC`, shifts (`RvShift`),
loads/stores, RVC.
