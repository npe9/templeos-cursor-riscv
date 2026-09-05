# CI and local gates

How to run locally what GitHub Actions runs, and what is **not** in CI.

QEMU (and related emulator flags) appear here because this is the **test harness** —
not because TempleOS/RV is “a QEMU OS.” Product docs and REPL Help stay board / HolyC first.

## Jobs (`.github/workflows/ci.yml`)

| Job | What | Local mirror |
|-----|------|----------------|
| **syntax-sh** | `bash -n` on every `tests/scripts/*.sh` | `make syntax-sh` |
| **shellcheck** | ShellCheck on primary scripts | `make lint-sh` (needs `shellcheck`) |
| **compile-compliance** | Build `holyc-riscv`, `make compliance`, `make fmt-test`, `make fmt-check`, `make asm-stress`, `make asm-prop` | `make` && `make compliance` && `make fmt-test` && `make fmt-check` && `make asm-stress` && `make asm-prop` |
| **qemu-integration** | Needs the three jobs above; runs `make qemu-integration` (`asm-stress`, `compiler-stress`, `compiler-prop`, then kernel smokes) | `make qemu-integration` |

**Full local gate:** `make ci` (= compliance + fmt-test + fmt-check + asm-stress + asm-prop + qemu-integration). Shellcheck/syntax are separate locally (`make lint-sh` / `make syntax-sh`).

Semantics stress only: `make stress` (= `asm-stress` + `asm-prop` + `compiler-stress` + `compiler-prop`). See [tests/asm/](../tests/asm/README.md) and [tests/compiler/](../tests/compiler/README.md).

`fmt-check` enforces `holyc-riscv --fmt` on port-owned roots listed in [`tests/scripts/holyc_fmt_paths.sh`](../tests/scripts/holyc_fmt_paths.sh) (gofmt-style). See [CONTRIBUTING.md](CONTRIBUTING.md).

## What `qemu-integration` covers

Exec oracles, TempleOS C-image smoke, the long `kernel-*-smoke` list (print → virtio → FB/Gr/Win → ExePutS → **phase3**), **`kernel-plat-smoke`**, then **Track A** ([SELF_HOST.md](SELF_HOST.md)):

| Path | Targets | CI status |
|------|---------|-----------|
| **HolyC guest Cmp (A2/A3)** | `kernel-repl-exepubs-smoke` / `repl-cmp-smoke` → `build/repl-cmp.elf` | **Required** |
| **HolyC memfs bridge** | `repl-holyc-smoke`, `repl-holyc-regression`, `bootloader-smoke` | **Required** |
| **Deprecated legacy C guest** | `repl-smoke`, `repl-regression` | **Optional local only** (A3 Done; not in `qemu-integration`) |

Also **`repl-9p-smoke`**, **`term-probe-pty`**, **`repl-uart-echo-pty`**, **`repl-uart-xon-pty`**, **`dump-changes-smoke`**. Begins with **`asm-stress`**, **`compiler-stress`**, and **`compiler-prop`**.

**A3 Done:** honesty path is HolyC-only. Legacy dual-run and `zmodem-smoke` are
**not** required CI (G11 waived; DumpChanges covers export). Follow-up: delete
`worry_dream_repl.c` — [SELF_HOST.md](SELF_HOST.md), [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md).

CI’s default machine profile is **virt** (typical virt memory map). That is an emulator
target for automation — board ports are separate ([PLATFORM.md](../templeos-riscv/PLATFORM.md)).

See the full matrix: [../tests/README.md](../tests/README.md).

### Harness quit (emulator only)

When you run a smoke under `qemu-system-riscv64 -nographic`, the host monitor exit is
**Ctrl-A** then **X**. Guest soft re-entry is `Reset;` in the REPL — prefer that in
user-facing text; this key sequence is harness-only.

## Explicitly local / not CI (or optional)

| Target | Why |
|--------|-----|
| `repl-smoke` / `repl-regression` | Deprecated legacy C guest — A3 Done; scheduled delete |
| `zmodem-smoke` / `trzsz-smoke` | Legacy full-REPL export (G11 waived); product = DumpChanges + 9P |
| `kernel-plat-sifive-u-smoke` | Non-default machine; run when changing SiFive/Kconfig ports |
| Other `defconfig-*` boards | Tentative; image may not fit (see [PLATFORM.md](../templeos-riscv/PLATFORM.md)) |
| `make coverage` | Heavy all-errors project compile tally — useful locally |
| Interactive cocoa FB | Manual; CI uses headless display + UART hash |

## Doc-only pushes

`paths-ignore: **/*.md` — Markdown-only pushes/PRs **skip** CI. After doc-only changes that might affect scripts nested in docs… there are none; for a full run use **Actions → CI → Run workflow** (`workflow_dispatch`).

## Branch protection (optional)

Require all four: `syntax-sh`, `shellcheck`, `compile-compliance`, `qemu-integration`.
