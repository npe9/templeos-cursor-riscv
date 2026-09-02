# Assembler semantics stress (`make asm-stress`) and property tests (`make asm-prop`)

Host `TryAssembleRiscV` (`host/parser.c`) encoding oracle — not a tutorial, not “parses OK.”

## Run

```bash
make          # build holyc-riscv
make asm-stress   # curated golden vectors (+ optional gas cross-check)
make asm-prop     # property-based random RV64I vs Python oracle
make asm-gnu-diff # HolyC --asm-dump vs GNU gas (immediates/pseudos focus)
make stress       # asm-stress + asm-prop + asm-gnu-diff + compiler-stress + compiler-prop
```

Requires `python3`. Optional gas cross-check when `riscv64-unknown-elf-as` / `objdump` are on `PATH` (CI qemu-integration image has them). Without gas, goldens alone still gate; `asm-gnu-diff` skips gas compares gracefully.

### GNU differential (`make asm-gnu-diff`)

Compares instruction words from `holyc-riscv --asm-dump` against `riscv64-unknown-elf-as` (or `riscv64-linux-gnu-as`). Focus: immediates, pseudos, branch offsets, and rejection policy.

| Env var | Default | Meaning |
|---------|---------|---------|
| `ASM_GNU_DIFF_SEED` | `42` | PRNG seed for generated cases |
| `ASM_GNU_DIFF_GEN` | `120` | Random imm/pseudo/branch trials vs gas |
| `ASM_GNU_DIFF_BATCH` | `30` | Cases per host `--asm-dump` batch |
| `ASM_GNU_DIFF_POSITIVE` | `1` | Replay `positive.jsonl` (skip `"gas": false`) |
| `RISCV_AS` / `RISCV_OBJDUMP` | auto-detect | Override GNU toolchain paths |
| `ASM_STRESS_GAS_MARCH` | `rv64ima_zicsr_zifencei` | `-march=` for gas (no RVC) |

**Case modes** (`cases/gnu_diff.jsonl`):

| Mode | Meaning |
|------|---------|
| `match` | Host and gas must assemble; `IC_RAW_RV` words must match exactly |
| `both_reject` | Host must fail; gas must also fail (OOR simm12, shamt, …) |
| `holyc_reject` | Host must fail; gas may accept (unsupported pseudos: `seqz`, `snez`, `jr`, bare `jal`; or gas-only syntax) |
| `host_only` | Skip gas (documented encoding divergence, e.g. wide `li`) |

**Label / immediate translation for gas:**

- HolyC `L:` → gas local labels `1:` / `1f` / `1b` (same as asm-stress).
- Signed U-type (`lui a0, -1`) → gas `lui a0, 0xFFFFF` (encoding identical).
- Wide `li` outside ±2047: HolyC `lui`+`addi` (+ optional 32-bit shifts); gas uses `addiw` sequence — `"host_only"` / `"gas": false`.

**Generated cases** reuse asm-prop generators for I/S/U/B/J types, narrow `li`, pseudos (`mv`, `not`, `neg`), branches/jumps, and `jalr`.

### Property tests (`make asm-prop`)

Randomly generates valid RV64I (+ M) instruction patterns with legal immediates and register operands, assembles via `holyc-riscv --asm-dump`, and compares each `IC_RAW_RV` word to a Python reference encoder (`tests/asm/riscv_oracle.py`) that mirrors `host/parser.c` emit helpers.

| Env var | Default | Meaning |
|---------|---------|---------|
| `ASM_PROP_SEED` | `42` | PRNG seed (reproducible runs) |
| `ASM_PROP_TRIALS` | `400` | Random encode trials |
| `ASM_PROP_REJECT` | `28` | Out-of-range immediate reject trials |
| `ASM_PROP_BATCH` | `40` | Cases per host `--asm-dump` invocation |

Properties checked:

- **Encode**: host word == oracle for random valid forms (I/R/S/U/B/J types, pseudos, branches/jumps with local labels).
- **Reject**: `addi`/`ld`/… OOR simm12, `slli` shamt 64, full-address `lui`, bare `jal` → assemble failure.
- **Oracle replay**: single-insn `positive.jsonl` goldens re-encoded through the oracle (sanity that reference matches committed vectors).

Not covered by asm-prop (see `GAPS.md` / asm-stress goldens): RVC, `%hi`/`%lo`, wide `li` expansion, CSR/A-ext/float, guest `Compiler/Asm_RV.HC`.

## Layout

| Path | Role |
|------|------|
| `cases/positive.jsonl` | Dozens of encodings: `insns` + golden `words` (8 hex digits, LE word as printed by `--asm-dump`) |
| `cases/negative.jsonl` | Must fail cleanly (compile error or soft-skip → no `IC_RAW_RV`) |
| `cases/gnu_diff.jsonl` | Curated imm/pseudo/branch/reject cases for GNU differential |
| `riscv_oracle.py` | Python RV64I/M encode reference (mirrors host emit) |
| `gas_util.py` | Shared gas detect, `--asm-dump`, objdump word extract |
| `run_asm_prop.py` | Property generator + harness |
| `run_asm_gnu_diff.py` | HolyC vs GNU gas differential harness |
| `GAPS.md` | Unsupported / known soft spots |
| `../scripts/run_asm_stress.sh` | Curated-case harness |
| `../scripts/run_asm_prop.sh` | Property-test wrapper |
| `../scripts/run_asm_gnu_diff.sh` | GNU differential wrapper |

## How asm-stress works

1. Each positive case is wrapped as:

   ```holyc
   asm {
     T::
       <insns…>
   }
   ```

2. `holyc-riscv --asm-dump` walks the IC stream and prints each `IC_RAW_RV` word (bypasses AOT peephole that would drop `nop` / `mv rd,rd`).

3. Words must match the committed golden. If gas is present and the case is not `"gas": false`, the same insn(s) are assembled with `-march=rv64ima_zicsr_zifencei` (no RVC) and compared to the host dump.

**asm-stress gaps vs asm-gnu-diff:** stress replays committed goldens (107/112 gas-checked; 5 wide-`li`/semi cases skipped). It does not systematically sweep imm edges, generated pseudos, or document `holyc_reject` vs `both_reject` policy. Use `make asm-gnu-diff` for gas-focused imm/pseudo coverage.

## Adding a case

1. Prefer a gas-checked encoding (`riscv64-unknown-elf-as -march=rv64ima_zicsr_zifencei`).
2. Append one JSON object per line to `positive.jsonl` (`name`, `insns`, `words`; optional `gas` string override or `false`).
3. For imm/pseudo/branch focus, also add to `gnu_diff.jsonl` with appropriate `mode`.
4. Re-run `make asm-stress` and `make asm-gnu-diff`.

Negative: add to `negative.jsonl` with `name`, `insns`, `why`.

## CI

- `make asm-stress` is part of **`make ci`** and the GitHub **compile-compliance** job (host-fast; gas optional there).
- **`make asm-gnu-diff`** runs in **compile-compliance** when GNU gas is installed; skips gas compares gracefully otherwise.
- **qemu-integration** also runs `make asm-stress` so the gas cross-check runs on the RISC-V toolchain image.
- `make asm-prop` runs under **`make stress`** locally; in CI via compile-compliance.

Tutorials A01–A06 remain separate; this suite is the merge gate for assembler semantics.

Companion: [`../compiler/`](../compiler/README.md) (`make compiler-stress`) for HolyC→RISC-V execute-oracle semantics. Umbrella: `make stress`.
