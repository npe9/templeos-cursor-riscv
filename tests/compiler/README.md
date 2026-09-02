# Compiler codegen semantics stress (`make compiler-stress`) and property tests (`make compiler-prop`)

Host HolyC→RISC-V **semantic** gate (execute-oracle), plus negatives and soft insn-pattern checks.
Assembler encodings live under [`../asm/`](../asm/README.md) (`make asm-stress`, `make asm-prop`).

## Run

```bash
make
make compiler-stress          # curated UART oracles + negatives + patterns
make compiler-prop            # property-based opt-tier equivalence (QEMU)
make stress                   # asm-stress + asm-prop + compiler-stress + compiler-prop
```

Requires the same RISC-V + `qemu-system-riscv64` tools as `make exec-oracle`.
Optional: `STRESS_GUEST=1 make compiler-stress` also runs `kernel-exepubs-smoke` + `kernel-phase3-smoke`
(those already run in `make qemu-integration`).

## Layout

| Path | Role |
|------|------|
| `stress_oracle.tsv` | Curated subset of exec oracles (+ stress-only cases) |
| `cases/*.hc` | Stress programs (`*(I64*)=0`, abs VA clean/bit31, class field, string, funptr, if/loop) |
| `negative/*.hc` | Must fail to compile |
| `patterns.tsv` | Soft/hard disassembly pattern checks (e.g. forbid useless `slli;srli`) |
| `run_compiler_prop.py` | Property generator + opt-tier equivalence harness |
| `../scripts/run_compiler_stress.sh` | Curated-case harness |
| `../scripts/run_compiler_prop.sh` | Property-test wrapper |

## Property tests (`make compiler-prop`)

Randomly generates valid HolyC programs in a **safe subset** (arithmetic, bitwise ops, comparisons,
`if`/`else`, bounded `while`, small helper calls, local `I64` vars). Each program is compiled at
multiple host optimization tiers, linked with the exec oracle harness, run under QEMU virt, and must
produce the same `main()` return value (`ORACLE` UART line) on every tier.

### Optimization tiers compared

`holyc-riscv` has no `-O0`/`-O1` CLI; tiers are selected via environment variables (see `host/README.md`):

| Tier | Environment | Meaning |
|------|-------------|---------|
| `no_opt` | `HOLYC_NO_OPT=1` | All optimizations off (baseline) |
| `no_tier2` | `HOLYC_NO_TIER2=1` | Tier-1 peephole only (no IC Tier-2) |
| `no_promote` | `HOLYC_NO_PROMOTE=1` | Default minus I64 local promotion |
| `default` | *(none)* | Full default O1 mode 3 + Tier-2 |

Default comparison: **`no_opt` vs `default`**. Override with `COMPILER_PROP_TIERS` (comma-separated, ≥2 tiers).

| Env var | Default | Meaning |
|---------|---------|---------|
| `COMPILER_PROP_SEED` | `42` | PRNG seed |
| `COMPILER_PROP_TRIALS` | `60` | Random generated programs |
| `COMPILER_PROP_EXPR_DEPTH` | `4` | Max expression tree depth |
| `COMPILER_PROP_MAX_LOOP` | `8` | Max `while` iteration bound |
| `COMPILER_PROP_TIERS` | `no_opt,default` | Tiers to compare |

Properties checked:

- **Cross-tier semantic equivalence**: identical `ORACLE` hex across all selected tiers.
- **Compile/run parity**: all tiers compile or all fail; no crash on one tier only.
- **Replay**: curated exec/compiler stress sources re-run at every tier.

Not generated (known gaps / future work): pointers, classes, strings, floats, globals, arrays, asm,
indirect calls, chain comparisons, guest `Compiler_RV` codegen.

## CI

- `make compiler-stress` runs in **qemu-integration** (needs QEMU).
- `make stress` / `make ci` include assembler and compiler halves; `compiler-prop` runs under **`make stress`** locally (QEMU-bound; not yet in CI).

## Gaps

| Area | Status |
|------|--------|
| Guest `ExePutS` / `Compiler_RV` | Already smoked in `qemu-integration` (`kernel-exepubs-smoke`, `kernel-phase3-smoke`); optional via `STRESS_GUEST=1` |
| Useless `slli;srli` on clean lo | **Hard** in `patterns.tsv` via `c_abs_store_clean.hc` (`0x10000000`) |
| Bit31 U32 VA zext | **Expected** (`lui`+`slli`/`srli` 32) — see `c_abs_store_bit31.hc`; not a pattern fail |
| Store-zero → `sd zero` | `ICF_ASSIGN_ZERO` + hard check on `c_ptr_store_zero.hc` (no `mv t0,a0`); stack width oracle `c_i64_store_zero.hc` |
| CR/LF `\|\|` compare-branch | `c_crlf_or.hc` — `beq` to 13/10, core ≤12 insn, no `seqz` |
| Indexed `sb` safety | `c_idx_store_sb.hc` — must be `sb a0,0(t0)`, never `sb a0,0(a0)` |
| Full exec oracle set | Still run by `make exec-oracle`; this suite is a curated fast subset |
| Guest Asm_RV encoding parity | Not in this suite (host AOT only); see `tests/asm/GAPS.md` for asm |
| Opt-tier prop: pointers / MMIO / floats | Out of scope for generator; use curated `stress_oracle.tsv` cases |
| `HOLYC_O1_MODE=4` BB slot forwarding | Alias-unsafe; not in default tier set (opt-in bisect only) |
