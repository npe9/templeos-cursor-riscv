# Contributing

This repo ports **TempleOS / HolyC to RISC-V** for real boards (Kconfig, SiFive, …).
Automated smokes may use an emulator; that harness is not the product. Prefer board /
`MEM_*` / HolyC-driver language in docs and Help.

## Prerequisites

- Host C toolchain (`gcc`, `make`) — builds `holyc-riscv` from sources in `host/`
- Guest / CI tools: `riscv64-unknown-elf-gcc` (+ `ld`/`objcopy`), Python 3
- Optional for local integration smokes: `qemu-system-riscv64`
- Optional: `shellcheck` for `make lint-sh`

There is **no** separate HolyC compiler download, submodule, or install step. A clean
clone plus the tools above is enough for `make`, `make test`, and (with QEMU) `make ci`.

## Self-contained repository

| In git | Not in git (build locally) |
|--------|----------------------------|
| `host/*.c` / `host/*.h` — full host AOT compiler | `./holyc-riscv` — produced by `make` (gitignored; platform-specific) |
| `bootstrap/holy_rt*.h`, `seed/*.hc` — REPL runtime tables + seeds | `bootstrap/repl.elf`, `boot_blob_embed.h` — from `Makefile.repl` / `make repl-blob` |
| `tools/pack_tosb.c`, generators | `tools/pack_tosb` — built on demand by kernel smokes |

**Bootstrap path:** standard host `gcc` compiles `host/` → `./holyc-riscv`. That binary
AOT-compiles HolyC guests (kernel smokes, `repl-blob`, `hc_repl`). The bare-metal REPL
(`bootstrap/Makefile.repl`) also links `host/*.c` directly as a guest object — it does
**not** require a prebuilt `./holyc-riscv` to link `repl.elf`, though `make repl-blob`
uses the host binary for AOT validation when present.

**Do not commit** `./holyc-riscv`: macOS and Linux produce different native binaries. CI
and local workflows always build from `host/` (`make` or `make holyc-riscv`). Override only
for debugging: `HOLYC=/path/to/holyc-riscv` or `HOLYC_BIN=…` in test scripts.

## Build and test

```bash
make                         # holyc-riscv
make test                    # tiny AOT smoke + fmt-test
make fmt                     # rewrite HolyC under enforced roots (like gofmt)
make fmt-check               # fail if any enforced file differs (CI; like gofmt -l)
make ci                      # compliance + fmt-test + fmt-check + qemu-integration
make repl-regression         # hard Src/editor/trap gate (see tests/REGRESSION.md)
```

`make ci` mirrors GitHub Actions after the shellcheck/syntax jobs. Details: [CI.md](CI.md),
[../AGENTS.md](../AGENTS.md), [../tests/README.md](../tests/README.md).

Doc-only commits (`*.md` only) skip CI (`paths-ignore`); use **Actions → CI → Run workflow** if you need a full run.

## HolyC formatting (gofmt-style)

All HolyC under the **enforced roots** must match `holyc-riscv --fmt` (canonical AST formatter in `host/holyc_fmt.c`). Do not hand-fight indent/spacing — edit code, then `make fmt` or `./holyc-riscv --fmt file.hc`.

| Command | Role |
|---------|------|
| `make fmt` | Rewrite enforced roots in place |
| `make fmt-check` | List diffs / exit 1 if dirty (CI) |
| `make fmt-test` | Golden + idempotency fixtures in `tests/fmt/` |

**Path list (source of truth):** [`tests/scripts/holyc_fmt_paths.sh`](../tests/scripts/holyc_fmt_paths.sh) — currently `bootstrap/seed/`, `bootstrap/hc_repl/`, `Kernel/**/*RV*` + `Kernel/Drv/`, `Compiler/**/*RV*`, `Adam/*RV*` (HolyC), `tests/exec/cases/`, `tests/fmt/golden/`. Not required yet: unreformed x86 TempleOS corpus, `tests/scratch/`, intentionally ugly `tests/fmt/cases/`. Basename denylist covers syntax-stress and known non-idempotent mid-`//` fixtures. Expand the script when a tree is stably port-owned.

Cursor rule: [`.cursor/rules/holyc-fmt.mdc`](../.cursor/rules/holyc-fmt.mdc).

## Norms

- **No hollow stubs** that look green under loose greps. If a feature is a host-slot bridge or unfinished, say so; `make repl-regression` rejects stub `Src` / label-only MemMap/Regs. See [../tests/REGRESSION.md](../tests/REGRESSION.md).
- **Do not grow `bootstrap/hc_repl/jit.hc`** as a second language — destination is `Compiler/Compiler_RV.PRJ` + `ExePutS` / guest `Cmp` ([COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md)).
- **OS devices are HolyC** (`Kernel/Drv/*` + Kconfig). Do not add a parallel C multi-machine driver stack under `templeos-riscv/`.
- Prefer small, reviewable changes over mega-WIP that falsely greens local smokes.
- Do not commit unless asked (agents) / follow normal PR review for humans.
- User-facing Help / Man / README: RISC-V OS first; keep emulator key sequences out of product banners (harness notes belong in [CI.md](CI.md) if anywhere).

## Boards / Kconfig

```bash
make menuconfig
# or
make -C templeos-riscv defconfig-sifive_u
```

Tutorial: [../templeos-riscv/KCONFIG.md](../templeos-riscv/KCONFIG.md). Machine table: [PLATFORM.md](../templeos-riscv/PLATFORM.md). After non-default experiments, restore `make -C templeos-riscv defconfig` so CI-oriented builds see the default profile again.

## Architecture

[ARCHITECTURE.md](ARCHITECTURE.md) — host compiler, REPL, Kernel, guest Cmp, self-host honesty.
Tree map: [LAYOUT.md](LAYOUT.md). Doc index: [README.md](README.md).

## Remotes

This clone may use `origin` as a local path mirror; **`github`** is the GitHub remote. Prefer `git push github <branch>` if `origin` rejects pushes.
