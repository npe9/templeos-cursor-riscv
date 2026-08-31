# CI and local gates

How to run locally what GitHub Actions runs, and what is **not** in CI.

QEMU (and related emulator flags) appear here because this is the **test harness** —
not because TempleOS/RV is “a QEMU OS.” Product docs and REPL Help stay board / HolyC first.

## Jobs (`.github/workflows/ci.yml`)

| Job | What | Local mirror |
|-----|------|----------------|
| **syntax-sh** | `bash -n` on every `tests/scripts/*.sh` | `make syntax-sh` |
| **shellcheck** | ShellCheck on primary scripts | `make lint-sh` (needs `shellcheck`) |
| **compile-compliance** | Build `holyc-riscv`, `make compliance`, `make fmt-test`, `make fmt-check` | `make` && `make compliance` && `make fmt-test` && `make fmt-check` |
| **qemu-integration** | Needs the three jobs above; runs `make qemu-integration` | `make qemu-integration` |

**Full local gate:** `make ci` (= compliance + fmt-test + fmt-check + qemu-integration). Shellcheck/syntax are separate locally (`make lint-sh` / `make syntax-sh`).

`fmt-check` enforces `holyc-riscv --fmt` on port-owned roots listed in [`tests/scripts/holyc_fmt_paths.sh`](../tests/scripts/holyc_fmt_paths.sh) (gofmt-style). See [CONTRIBUTING.md](CONTRIBUTING.md).

## What `qemu-integration` covers

Exec oracles, TempleOS C-image smoke, the long `kernel-*-smoke` list (print → virtio → FB/Gr/Win → ExePutS → **phase3**), **`kernel-plat-smoke`** (default-board Kconfig UART/CLINT), **`hc-repl-smoke`**, **`repl-smoke`**, **`repl-regression`**, **`term-probe-pty`**.

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
| `kernel-plat-sifive-u-smoke` | Non-default machine; run when changing SiFive/Kconfig ports |
| Other `defconfig-*` boards | Tentative; image may not fit (see [PLATFORM.md](../templeos-riscv/PLATFORM.md)) |
| `make coverage` | Heavy all-errors project compile tally — useful locally |
| Interactive cocoa FB | Manual; CI uses headless display + UART hash |

## Doc-only pushes

`paths-ignore: **/*.md` — Markdown-only pushes/PRs **skip** CI. After doc-only changes that might affect scripts nested in docs… there are none; for a full run use **Actions → CI → Run workflow** (`workflow_dispatch`).

## Branch protection (optional)

Require all four: `syntax-sh`, `shellcheck`, `compile-compliance`, `qemu-integration`.
