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

> **`make compliance` measures via `HOLYC_PRINT_SIZE=1`.** The runner checks that a
> construct actually emitted code by parsing `Code size:` from compiler stdout, but
> `-o <file>` puts the compiler in quiet mode and suppresses that line. Without the env
> var every case reads as size 0 and fails — which is how it sat, silently, from
> `080f729` until it was found. Do not "simplify" this to `wc -c` on the output blob:
> that includes the import table, so every case would clear the minimum and the check
> would pass vacuously. See [../tests/scratch/compliance_size0_note.md](../tests/scratch/compliance_size0_note.md).

**Full local gate:** `make ci` (= compliance + fmt-test + fmt-check + asm-stress + asm-prop + qemu-integration). Shellcheck/syntax are separate locally (`make lint-sh` / `make syntax-sh`).

Semantics stress only: `make stress` (= `asm-stress` + `asm-prop` + `compiler-stress` + `compiler-prop`). See [tests/asm/](../tests/asm/README.md) and [tests/compiler/](../tests/compiler/README.md).

`fmt-check` enforces `holyc-riscv --fmt` on port-owned roots listed in [`tests/scripts/holyc_fmt_paths.sh`](../tests/scripts/holyc_fmt_paths.sh) (gofmt-style). See [CONTRIBUTING.md](CONTRIBUTING.md).

## Reading a failed `kernel-*-smoke`: the TRAP line

Every `tests/exec` case links `tests/exec/harness/crt0.S`, which installs a trap vector
before the blob runs. A fatal fault therefore **reports and halts** rather than hanging:

```
TRAP mcause=0x...05 (load-fault) mepc=0x0000000080800178 mtval=0x8 blob+0x0000000000000178
TRAP halted
```

Take `blob+0x...` and look it up in `HOLYC_MAP` output —
`HOLYC_MAP=/tmp/x.map ./holyc-riscv <case>.hc -o /tmp/blob.bin` writes `offset name` per
function. The blob is `objcopy -I binary`'d in and has no ELF symbols, so this map is the
only way to turn a faulting PC into a function name; gdb gives a bare `pc` and no
backtrace.

A hang with **no** TRAP line is a genuine loop, not a fault. Before this vector existed
the two were indistinguishable, and `kernel-cdc-smoke` / `kernel-span-smoke` sat red for
a while while never actually executing.

The handler is a floor: `bootstrap/holy_rt.h` installs its own vector
(`RVTrapInit` / `RVPreemptInit` / `RVTrapDiag` / `RVPreemptReal`) and wins once guest
code runs. It halts rather than powering off, so a trapped case still runs out its
`timeout` — the output arrives, the wall-clock does not improve.

## What `qemu-integration` covers

Exec oracles, TempleOS C-image smoke, the long `kernel-*-smoke` list (print → virtio → FB/Gr/Win → ExePutS → **phase3**), **`kernel-plat-smoke`**, then **Track A** ([SELF_HOST.md](SELF_HOST.md)):

| Path | Targets | CI status |
|------|---------|-----------|
| **HolyC guest Cmp (A2/A3)** | `kernel-repl-exepubs-smoke` / `repl-cmp-smoke` → `build/repl-cmp.elf` | **Required** |
| **HolyC memfs bridge** | `repl-holyc-smoke`, `repl-holyc-regression`, `bootloader-smoke` | **Required** |
| **Retired legacy C guest** | `repl-smoke`, `repl-regression` | **Retired** — the C guest is deleted; both targets now print an error and redirect |

Also **`repl-9p-smoke`**, **`gdb-uart-smoke`**, **`term-probe-pty`**, **`repl-uart-echo-pty`**, **`repl-uart-xon-pty`**, **`dump-changes-smoke`**. Begins with **`asm-stress`**, **`compiler-stress`**, and **`compiler-prop`**.

### WIP — smokes still wired to the deleted `bootstrap/repl.elf`

Honest blocker, **not** skip=OK. `make -C bootstrap -f Makefile.repl repl.elf` is now a hard
error, so anything that starts with it is red until it is retargeted at
`build/repl-holyc.elf` (`make hc-repl`). Every **required** row is now retargeted; what is
left is the G11-waived ZMODEM/trzsz pair.

| Script | Target | Required in `qemu-integration`? | State |
|---|---|---|---|
| `run_dump_changes_smoke.sh` | `dump-changes-smoke` | **yes** | **Fixed** — runs on `build/repl-holyc.elf`. The P5 fill loop is now wrapped in a function because the thin JIT rejects a top-level `for` (`JIT: unknown fun for`) |
| `run_repl_9p_smoke.sh` | `repl-9p-smoke` | **yes** | **Fixed** — runs on `build/repl-holyc.elf`. `seed/ninep.hc` is AOT-`#include`d by `hc_repl/repl.hc` (the thin JIT cannot compile a virtio driver), `Mount9p` / `NineExport` / `NinepSmoke` are `JitAdd`'d, and the source is memfs-embedded at `Lib/ninep.hc` for `Cat`/`Src`. The smoke calls `NinepSmoke();` instead of `Run("ninep.hc");` |
| `run_zmodem_export_smoke.sh` | `zmodem-smoke` | no (local) | **Red.** G11 waived the ZMODEM embed, so there is no guest to run it on — [SELF_HOST.md](SELF_HOST.md) |
| `run_trzsz_export_smoke.sh` | `trzsz-smoke` | no (local) | **Red**, same reason |
| `run_gdb_uart_smoke.sh` | `gdb-uart-smoke` | **yes** | **Fixed** — same shape: `seed/gdbstub.hc` is AOT-`#include`d, `GdbStub` / `GdbHelp` are `JitAdd`'d, source memfs-embedded at `Boot/gdbstub.hc`, and `tools/uart_gdb_proxy.py --qemu` points at `build/repl-holyc.elf`. Now in `qemu-integration` next to `repl-9p-smoke` (QEMU stage is ~0.2 s) |

### pty smokes and the thin JIT statement surface

Both scripts run `build/hc_repl.elf` and are **green**. They used to be red for two
different reasons, and the shape of the fix is worth keeping:

| Script | Target | Required in `qemu-integration`? | State |
|---|---|---|---|
| `run_repl_uart_echo_pty.sh` | `repl-uart-echo-pty` | **yes** | **Fixed.** Two bugs. (1) `while(1){}` → `JIT: unknown fun while`, so the busy eval never started; the smoke now calls `Spin(30)`, an AOT helper in `seed/sys.hc`, instead of asking the thin JIT for a toplevel loop. (2) `ExePutS` only calls `BreakArm` when `g_break_interactive` is set, and only `TrapInit` ever set it — which boot does not reach, so **Ctrl-C could not interrupt a running eval at all**. `ReplMain` now sets the flag at boot; `BreakArm` → `TrapInitOnce` still defers the mtvec swap to the first eval |
| `run_repl_uart_xon_pty.sh` | `repl-uart-xon-pty` | **yes** | **Fixed.** `UartXonXoff` / `UartPut` (plus `UartFcGet` / `UartRtsCts` / `UartRtsCtsGet`) are `JitAdd`'d in `repl.hc`, matching what [UART.md](UART.md) and [FLOW_CONTROL.md](FLOW_CONTROL.md) already promised. The blast loop lives in a prompt-defined `U0 XonBlast(){…}` — fun bodies have `for`, toplevel does not — and is paced, because unpaced QEMU emits 800 bytes in ~3 ms and the host XOFF never lands mid-stream |

Arming Break for every eval turns the UART/timer IRQs on for the rest of the session,
which surfaced a real duplicate-input bug: `hc_repl/uart.hc`'s `UartRxDrain` was missing
the `PUSHFD; CLI; … POPFD` window that `seed/uart.hc` already had, so the IRQ-side drain
and the polling drain could rewind the ring head and re-serve consumed bytes.

`repl-holyc-regression` used to *look* like it covered Ctrl-C and did not: its
`Interrupted` needle was satisfied by the earlier explicit `Break;`, and its
`for(__brk=0;;__brk++) {}` probe was rejected as `unknown fun for` so nothing ever spun.
It now feeds `Spin(20);`, waits for the eval to actually start, then sends `^C` on its own
— and asserts the **first** thing after the `Spin(20)` echo is `Interrupted`, not an `ans=`
(spin ran to completion) and not `unknown fun` (helper unregistered).

**Budget when you AOT-`#include` a seed:** boot `JitAdd`s come out of `jit_funs`
(`JIT_FUN_MAX` in `bootstrap/hc_repl/jit.hc`; the file itself is do-not-grow, but the
registration table and its diagnostics are fair game). Boot burns **234** of **384**
slots, leaving **150** for functions the session defines — the boot banner prints
`JIT: 234/384 fun slots used (150 free)` so you do not have to guess. Overrun is no longer
silent: `JitAdd` prints `JIT: fun table full (<name> dropped, JIT_FUN_MAX reached)` instead
of only returning `-1` and deferring the symptom to a later `JIT: unknown fun X`.
`JIT_FUN_MAX` went 256 → 384 to buy that headroom; the image is a flat blob, so each slot
is a real **56 B** of it (**+7,168 B** for the 128 extra). Publish only the documented
entry points; the rest of an AOT unit stays callable from AOT code and readable via
`Src`/`Cat`.

Already repaired in the same pass: `firmware-smoke` / `bios-smoke` now wrap the Kconfig
**plat** payload (`Makefile.firmware` defaults to `PAYLOAD=plat`; `PAYLOAD=repl` errors) and
assert `plat-smoke: PASS` instead of the deleted guest's REPL prompt.

**A3 Done:** honesty path is HolyC-only. Legacy dual-run and `zmodem-smoke` are
**not** required CI (G11 waived; DumpChanges covers export). The follow-up delete of
`worry_dream_repl.c` also landed (`080f729`) — [SELF_HOST.md](SELF_HOST.md),
[A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md).

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
