# P0 — RV64I OP-IMM `RvI` vs `riscv_oracle.py`

Closed-loop experiment from [docs/VERIFICATION.md](../../docs/VERIFICATION.md) §P0 /
[docs/spec/p0_rv_i.md](../../docs/spec/p0_rv_i.md).

## What is checked

| Artifact | Role |
|----------|------|
| `rv_i_model.py` | Independent field-packing model of OP-IMM I-type |
| `tests/asm/riscv_oracle.py::rv_i` | CI encode truth |
| `rv_i.c` | Extracted mirror of `host/parser.c` `RvI` |

No Frama-C / Dafny install. Needs `python3` + a C compiler (`cc` / `CC`).

## Run

```bash
make verify-p0
# or:
python3 verify/p0_rv_i/run_p0.py
python3 verify/p0_rv_i/run_p0.py --seed-bug   # expect mismatch (fail demo)
python3 verify/p0_rv_i/run_p0.py --exhaustive # full imm12 domain
```

Not part of `make ci`.
