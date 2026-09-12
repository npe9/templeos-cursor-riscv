# Operate-through / recovery playbook

Circumvention and recovery for a **running** RISC-V TempleOS / HolyC guest
(UART REPL, bootloader+REPL, board serial). Prefer HolyC / `MEM_*` language;
QEMU lines are the usual harness, not the product.

Related:

| Doc | Role |
|-----|------|
| [FILE_EXPORT.md](FILE_EXPORT.md) | Guest → host: `DumpFile` / `DumpChanges` / ZMODEM |
| [MEMFS_LOG.md](MEMFS_LOG.md) | Memfs journal / epochs (`FsChanges`, `FsSnap`, `FsCheckpoint`) |
| [SELF_HOST.md](SELF_HOST.md) | Guest rebuild / zero guest C; when to trust Mac AOT again |
| [PLATFORM.md](../templeos-riscv/PLATFORM.md) | Board ports + which `-M` / plat.elf to boot |
| [DRIVERS.md](DRIVERS.md) | UART / timer / PLIC / virtio survey when HW looks dead |
| [REPL.md](REPL.md) | Interactive UART REPL entry / honesty |
| [BAREMETAL.md](BAREMETAL.md) | Flash / bootloader / OpenOCD when the image never boots |
| [DEBUGGER.md](DEBUGGER.md) | UART dig-down: Regs / Bp / StkRep; watch/step WIP; gdb+OpenOCD in [BAREMETAL.md](BAREMETAL.md) |

Host pin of last-good ELFs: [build/known-good/README.md](../build/known-good/README.md).

---

## Decision tree (fast)

| Symptom | First move |
|---------|------------|
| Guest still prints `>` | **Operate through** — export, then soft recover |
| UART garbage / no prompt | Board / driver / wrong `-M` — [PLATFORM.md](../templeos-riscv/PLATFORM.md), [DRIVERS.md](DRIVERS.md) |
| Compile / eval broken but prompt lives | `SafeMode;` → export → `Reset;` |
| Memfs polluted / seeds edited badly | Export dirty set → `Recover;` (soft) or power-cycle for pristine seeds |
| Suspected bad rebuild on host | `make known-good-check` vs pinned hashes |
| Kernel plat smoke / no REPL | Rebuild `plat.elf`; pin known-good; see PLATFORM matrix |

---

## Operate through (UART still alive)

Do **not** power-cycle until session work is off the guest.

1. **See dirty set** (full UART REPL with journal):
   ```holyc
   FsChanges;
   FsLog(16);
   ```
   Quiet spill is hidden by default; `FsChanges(-1, 1);` includes it
   (`FS_CH_ALL`). Design: [MEMFS_LOG.md](MEMFS_LOG.md).
2. **Export**:
   ```holyc
   DumpChanges;              // UART framed batch
   // or
   ZmodemSendChanges;        // needs host rz / tools/uart_recv_zmodem.py
   DumpFile("Home/foo.hc");  // single file
   ```
   Recipes: [FILE_EXPORT.md](FILE_EXPORT.md).
3. **Pin a session epoch** before more risk:
   ```holyc
   FsCheckpoint("pre-fix");
   // FsSnap;  // alias: reseal boot-style baseline (clears journal)
   ```
4. **Soft stack clean** (keeps memfs):
   ```holyc
   SafeMode;   // checkpoint + ops banner
   Reset;      // re-enter Boot — not a chip power cycle
   ```
5. **Soft memfs clean** (after export):
   ```holyc
   FsReplay;   // optional: verify journal vs tree
   Recover;    // drop non-snap + RECOVER reseal (P6)
   ```

`Help;` advertises export and soft reset. Prefer `Man("SafeMode");` /
`Man("Recover");` on the full seed path.

---

## SafeMode vs Recover vs Reset

| Call | What it does today | When |
|------|--------------------|------|
| **`SafeMode;`** | UART-only recovery banner; `FsCheckpoint("safemode")` (or `FsSnap` if journal not ready). **Does not** wipe memfs or touch WinMgr (REPL has none). | Prompt lives; want a named pin + reminder to export |
| **`Reset;`** | Soft Boot re-entry (`trap.hc`) | Clear stack / interrupt state; keep files |
| **`HardReset;`** | MEM_TEST finisher RESET `0x7777` | Sim/board reset only when you mean it |
| **`Quit;` / `Exit;`** | MEM_TEST finisher PASS `0x5555` | End QEMU virt session (host exit 0) |
| **`Fail;`** | MEM_TEST finisher FAIL `0x10003333` | End QEMU with non-zero host exit |
| **`Recover;`** / **`FsRecover;`** | Drop slots not in snap table; `FsEpochSealNamed(id,"RECOVER")`. Clears journal. **Does not** reinstall pristine seed bytes from the host blob. | After export, when you want a clean dirty-set without power-cycle |
| **`FsReplay;`** | Verify journal vs tree (OK/MISS/DRIFT); no body rewrite | Forensics before/after Recover |

Soft **Recover** is MEMFS_LOG **P6**. Pristine seed reinstall still needs power-cycle /
rebuild image (boot reseals `FS_EPOCH_BOOT`). Typical path:

1. `FsChanges;` / `DumpChanges;` or `ZmodemSendChanges;`
2. Optional `FsReplay;`
3. `Recover;` (or `FsRecover;`) — session files gone; new RECOVER epoch
4. `SafeMode;` then `Reset;` if the eval loop is wedged
5. Host: `make known-good-pin` after green smoke when pinning ELFs

Do **not** rewrite `fs.hc` journal ownership for Recover — it calls
`FsDropNonSnap` + `FsEpochSealNamed` (same seal path as boot).

---

## Host-side: last-good ELF pins

When CI or a local smoke is green, record hashes so a later “everything CRASH”
bisect has a fallback:

```bash
make known-good-pin          # hash repl + plat ELFs → build/known-good/
make known-good-check        # compare current ELFs to pins
```

Details: [build/known-good/README.md](../build/known-good/README.md).

Stale `repl.elf` after `host/holyc_compiler.h` / `bootstrap/holy_rt*.h` edits often
looks like universal hang — rebuild, then re-pin if the new image is trusted.

Host AOT progress (watch long `make kernel-win-rebuild` builds): stderr lines prefixed
`holyc:` when stderr is a TTY — `HOLYC_PROGRESS=1` forces on, `HOLYC_QUIET=1` off.

### Compiler diagnostic env vars

All off by default, all stderr-only, none affect codegen (verified byte-identical
blobs with `HOLYC_WARN_ALIGN` on vs off).

| Var | What it prints | Use it when |
|---|---|---|
| `HOLYC_MAP=<file>` | `offset name` per function in the unit | Turning a faulting PC into a function name. The blob is `objcopy -I binary`'d in and has **no ELF symbols**, so this is the only way — see the TRAP line in [CI.md](CI.md) |
| `HOLYC_DUMP_CLASS=<C>` | that class's whole member table (offset, size, type) | `offset: unknown member`, or any "is the layout what I think it is" question |
| `HOLYC_WARN_ALIGN=1` | `[align] C.m off=44 size=8 (off % 8 == 4)` for every 2/4/8-byte member at a non-multiple offset | Porting to a core that traps misaligned access. HolyC packs with no padding — correct on x86, and the RV backend emits a real full-width `ld`/`sd` at whatever offset results. Survey: [../tests/scratch/align_survey.md](../tests/scratch/align_survey.md) |
| `HOLYC_ALL_ERRORS=1` | every parse error, not just the first | A compile fails and the first error is a cascade victim |
| `HOLYC_TRACE=1` | `ParseFunction` failure sites | A function silently fails to parse |

### Incremental win AOT (compile + link)

`make kernel-win-interactive` / `kernel-win-run` no longer re-parse/optimize the whole
Kernel+Compiler include graph on every leaf edit. Units under `build/aot/win/`:

| Artifact | Source | Role |
|----------|--------|------|
| `compiler.bin` (+ `.map` / `.d`) | `tests/exec/aot/win_compiler.PRJ` | Compiler_RV + RVExePubs |
| `kernel.bin` (+ `.map` / `.d`) | `tests/exec/aot/win_kernel.hc` | Kernel_RV + main (no Body) — **shared by both ELFs** |
| `flag_i.bin` / `flag_hold.bin` | `tests/exec/aot/win_flag_{i,hold}.hc` | `RVWinHoldFlag()` → 0 / 1 (~1 KB) |
| `win_*.blob.bin` | `holyc-riscv --link` | Cross-patch HOFYIMP1 imports @ `0x80800000` |
| `build/exec/win_*.elf` | objcopy + `link_exepubs.ld` | QEMU kernel |

Touch a Compiler `.HC` → only `compiler` unit + link. Touch Kernel/main → only
`kernel` + relink. No-op when deps unchanged (~instant).

#### One shared Kernel unit for win_i + win_hold

`win_i` and `win_hold` differ by a single runtime bool: headless (typing/wrap stress
then `RVWinMgrRun(64)`) vs interactive hold (`RVWinMgrRun(0)`; ESC / serial `q` quits).
They used to be two `#define RV_WIN_HOLD`-flavoured compiles of the same include graph,
so one Kernel leaf edit cost **two** full ~20s unit compiles.

Now the bool is a HOFYIMP1 cross-unit call to `RVWinHoldFlag()`, defined in a ~1 KB
per-variant flag unit chosen at `--link` time (`RV_WIN_HOLD_UNIT` in
`kernel_win_interactive.hc` selects this path; plain `RV_WIN_HOLD` still works for the
script's monolithic fallback). The flag unit is linked **last** so `kernel` and
`compiler` land at identical VMAs in both blobs — `win_i.blob.bin` and
`win_hold.blob.bin` are byte-identical apart from one immediate byte.

A Kernel leaf edit is therefore one compile plus two ~0.3s relinks, not two compiles.

#### Compiler identity stamp (`build/aot/.compiler-stamp`)

Units depend on **what `holyc-riscv` is**, not when it was last linked. `-g` links embed
a fresh `LC_UUID`/debug stamp, so a rebuilt-but-identical compiler gets a new mtime —
which used to invalidate every unit (~80s full remake) after any `host/*.c` touch,
branch switch, or `make ci`. The stamp holds a hash of `COMPILER_SOURCES` +
`COMPILER_HEADERS` + `holy_rt_names.h` + `CFLAGS`, and its mtime moves **only** when
that hash changes; unit rules depend on the stamp. Touch `host/lexer.c` without changing
it → compiler relinks (~3s), HolyC units are kept.

Two consequences: the stamp recipe re-runs (hash only) on every `make`, so `make -n`
pessimistically shows all units rebuilding — trust a real build. And a toolchain swap
with no source change won't invalidate units; that's what `kernel-win-rebuild` is for.

Force a clean full rebuild:

```bash
make kernel-win-rebuild   # rm ELFs + build/aot/win; recompile all units
# or: rm -rf build/aot/win && make build/exec/win_i.elf
```

CLI: `holyc-riscv file.hc -o out.bin [--deps out.d] [--map out.map]` and
`holyc-riscv --link -o out.bin [--base 0x80800000] a.bin b.bin…` (sibling `.map` required).

Remaining gaps toward TempleOS Cmp/Load multi-TU: shared `Fs`/`cmp` still need
`RVAotLibSync` / `RVCmpWireAsmHash` at boot; per-`.HC` objects (not per-PRJ) not yet.

---

## Board / image won’t boot

1. Confirm defconfig / `-M` match ([PLATFORM.md](../templeos-riscv/PLATFORM.md)).
2. UART base / IRQ: [DRIVERS.md](DRIVERS.md), `Man("UART");` `Man("CLINT");` on a working REPL.
3. Bare flash / OpenOCD: [BAREMETAL.md](BAREMETAL.md).
4. Product HolyC path vs legacy C guest: [SELF_HOST.md](SELF_HOST.md) —
   prefer `build/repl-holyc.elf` / bootloader-repl; use legacy `bootstrap/repl.elf`
   when you need ZMODEM / `FsChanges` / `DumpChanges` ([FILE_EXPORT.md](FILE_EXPORT.md) matrix).

---

## Dig-down when eval is sick but UART works

```holyc
Regs; Reg("mstatus"); Bits("mstatus");
MemMap; MemMapDrvFind("uart");
pc; U(pc-16);          // last trap PC
Man("Reset"); Man("SafeMode");
```

No dedicated debugger doc yet; host gdb against OpenOCD is the silicon path
([BAREMETAL.md](BAREMETAL.md)).

---

## Non-goals

- Growing `jit.hc` / new C guest recovery APIs
- WinMgr / FB “safe desktop” — this playbook is **UART-first**
- Owning MEMFS_LOG P2–P5 journal work (already shipped; use the APIs)
- Committing `build/known-good/*.sha256` by default (local pins; README only in tree)
