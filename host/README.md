# Host HolyC → RISC-V compiler

C sources for the host AOT compiler that builds **`holyc-riscv`** (repo-root
binary via top-level `make`). All compiler source is **committed in this directory**;
the native `./holyc-riscv` binary is a local build artifact (gitignored). There is no
external HolyC install step — only host `gcc` + `make`.

| File | Role |
|------|------|
| `lexer.c` | Tokenization / `#include` |
| `parser.c` | AST / intermediate code |
| `compiler.c` | RISC-V emit + Tier-1 peephole / O1 / Tier-2 IC opts |
| `holyc_fmt.c` | `--fmt` / HolyFmtSrc (canonical gofmt-style formatter; `make fmt` / `make fmt-check`) |
| `hash_table.c` | Symbol table |
| `compiler_helper.c` | StrPrintF etc. for lexer |
| `main_stub.c` | CLI entry (`HOLYC_STANDALONE`) |

Headers: `holyc_compiler.h`, `holyc_fmt.h`, `hash_table.h`, `holy_api.h`.

Runtime name table used for AOT imports: `../bootstrap/holy_rt_names.h`
(included as `"bootstrap/holy_rt_names.h"` with `-I.` from the repo root).

Do **not** confuse this with the guest HolyC compiler under `Compiler/`
(`Compiler_RV.PRJ`). Layout map: [docs/LAYOUT.md](../docs/LAYOUT.md).

## Codegen quality

Emit is still an expression-stack machine (`addi sp,-8; sd; …; ld; addi sp,+8` per
operand). Correctness first; efficiency is layered on the existing opt story
(`HOLYC_NO_OPT` / `HOLYC_NO_TIER2` / `HOLYC_NO_PROMOTE` / `HOLYC_O1_MODE` — see
`AGENTS.md`), not a second optimizer.

### Tier-1 (in `RVU32`, whenever `cc->optimize`)

| Pattern | Rewrite |
|---------|---------|
| push rX; pop rX | nop |
| push rX; `addi sp,+8` (abandon / `IC_EVAL_DROP`) | nop |
| (no) push rX; pop rY → `mv` | **disabled** — miscompiled indexed stores (`PjPutHex` / Print) |

### Tier-2 IC (default; `HOLYC_NO_TIER2=1` bisect)

| Pattern | Rewrite | Bisect |
|---------|---------|--------|
| `EQU_EQU`…`LESS_EQU` + `BR_ZERO`/`BR_NOT_ZERO` | `IC_BR_EQU_*` + optional `ICF_CMP_IMM` | (in Tier-2) |
| `\|\|` / `&&` bool 0/1 + following `BR_*` | Elide when every edge is `IC_BR_EQU…` (JMP retarget) | `HOLYC_NO_BOOL_ELIDE=1` |
| `IMM k` + `BR_ZERO`/`BR_NOT_ZERO` | Const fold / dead else | (in Tier-2) |
| Identical if/else straight arms | Keep one arm; `EVAL_DROP` condition | `HOLYC_NO_TAIL_MERGE=1` |
| `CALL` (arity 0) + `END_EXP` + `JMP L` ×N | Share one call+jmp; others `JMP` share | `HOLYC_NO_CALL_TAIL=1` |
| Code after `JMP` before next `LABEL` | DCE (no other IR entries) | `HOLYC_NO_DEAD_JMP=1` |

Guest `getenv` is always NULL (`worry_dream_repl.c`), so host-only env gates do **not**
affect REPL seed compiles — defaults must be safe for vim.

Bool-elision root cause (vim `VCmd` illegal insn): OR elision turned an outer AND's
`BR_ZERO→F` into `JMP F`, then AND elision deleted `F` without retargeting that `JMP`.
Fixed via `IcRetargetLabel` including `IC_JMP`. Stats are O(n) per elision (was O(n²)
per BR candidate and hung the boot-blob AOT).

### `ICF_ASSIGN_ZERO`

`IMM 0` before pointer `IC_ASSIGN` skips dead `li`/push; emit is **`sd zero,0(<addr>)`**
with no useless `addi t0,a0,0` (addr in `a0`, promoted `sN`, or `t0` if stack-popped).

### Before / after — CR/LF `if (x=='\r'\|\|x=='\n')`

Condition core of `U0 F(I64 x){ if (x=='\r'\|\|x=='\n') X(); else Y(); }`
(first load of `x` through the `j` that selects else), excluding calls:

| Build | Cond insns | Shape |
|-------|----------:|-------|
| Pre-Tier-2 / `HOLYC_NO_OPT` | **~35–40** | push/pop/`sub`/`seqz` per `==`, then IMM 0/1, then `beqz` |
| O1 + cmp→branch only | **~16–20** | `ld; li t1,13; beq` ×2, still bool 0/1 + `beqz` |
| + bool elision (**default**) | **~7** | `ld; li; beq` ×2; `j .else` |

Default after:

```text
  ld   a0, -8(s0)
  li   t1, 13
  beq  a0, t1, .true
  ld   a0, -8(s0)
  li   t1, 10
  beq  a0, t1, .true
  j    .else
.true:
  … then …
.else:
  … else …
```

Oracle: `tests/compiler/cases/c_crlf_or.hc` in `make compiler-stress`
(requires `beq` to 13/10, no `seqz`/`sub`/`beqz`, core ≤12).

### Calls: `auipc+jalr` vs import slot vs host abs

| Kind | Encoding | Why |
|------|----------|-----|
| Same-unit defined callee | `auipc`+`jalr` (2 words) | Fixed size so multi-pass label sizing converges |
| Import / undefined prototype / host RT slot | `ld` from slot + `jalr` | Loader fill / TempleOS-style redefinition |
| Host absolute `exe_addr` (no data layout) | `lui`/`addi`/(U32 `slli`/`srli`)/`ld`/`jalr` | Slot pointer in host VA |
| In-range `jal` fast path | **not used** | Desyncs sizing vs emit near ±1 MiB edge |

Mutable HTT_FUN slots **must** stay load-per-call if the callee can be redefined between
calls. Same-unit direct calls already avoid the 6-insn host path. Repeated
`VClrCnt(); continue;` style tails share one CALL via `IcOptCallJmpTailMerge` instead of
re-emitting the call sequence N times. Do **not** cross-reg push→`mv` (broke `PjPutHex`).

### Before / after — `*p = 0`

| Build | Store path |
|-------|------------|
| Older assign-zero | `mv t0,s1; sd zero,0(t0)` / `addi t0,a0,0; sd zero,0(t0)` |
| Now | **`sd zero,0(s1)`** or **`sd zero,0(a0)`** |

Still open (honest gaps):

| Gap | Why it stays |
|-----|----------------|
| Value-based `a \|\| b` elision | Only BrCmp edges elide; plain vars keep bool 0/1 |
| CSE reload of `x` in `a\|\|b` | Second `ld a0,x` not reused |
| Hoist repeated import-slot `ld` in a BB | Unsafe if redefinition between calls; same-unit already direct |
| Partial shared tails | Identical if/else arms + arity-0 CALL+JMP only |
| Non-zero `*p=v` stack bounce | Zero-only `ICF_ASSIGN_ZERO` |
| Unsigned / F64 compare→branch | Signed `EQU`…`LESS_EQU` only |
| push→`mv` across regs | Off — broke `PjPutHex` indexed `sb` |
| TOS register cache | Eval stack still memory |

Guest `Compiler/BackLib_RV.HC` `RVLi` matches the same U32 zext rule.
Host Tier-1 / Tier-2 / `ICF_ASSIGN_ZERO` are **not** mirrored in guest `OptPass_RV` yet.
