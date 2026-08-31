# Bare-metal HolyC REPL

Interactive HolyC on RISC-V (UART console). Language surface matches a source file: functions,
classes, globals, `#define`, statements. Statements compile and run immediately; the
result prints in hex unless you use `Print` / `"fmt", args;`.

Default seed MMIO (`MEM_*` in `csr.hc`) matches a typical **virt-style** memory map so CI
and local smokes share one profile. Other boards: Kconfig + `Kernel/Drv/*` —
[PLATFORM.md](../templeos-riscv/PLATFORM.md).

## Run

```bash
make                         # host holyc-riscv (needed by some seeds / fmt bridges)
make repl-blob               # rebuild boot runtime snapshot (after editing seed/*.hc)
cd bootstrap
make clean && make -f Makefile.repl
# → repl.elf — load on board or CI emulator (see tests/REGRESSION.md for automated gates)
```

Boot loads a **prebuilt HolyC snapshot** (`boot_blob_embed.h`, built by `make repl-blob` /
`bootstrap/gen_boot_blob.py`) via one `run_source` of the concatenated seeds — not
`Run("mem.hc")` per file. Individual `seed/*.hc` still land in memfs for live edit.
The generator AOT-validates the concat with `holyc-riscv` when available
(`bootstrap/boot_runtime.bin`).

Compile errors print as `file:line:col: error: …` (host `holyc-riscv` and the UART REPL).
`ErrGo;` opens the preferred editor on the last error site.

From repo root:

```bash
make repl-smoke              # automated UART cases
make repl-regression         # hard Src / Man / FnSize / editor / trap gate
```

See [tests/REGRESSION.md](../tests/REGRESSION.md) for what “PASS” must mean. Local emulator
invocation for the harness is documented in [CI.md](CI.md) only.

### Temporary Mac-AOT guest (`hc_repl`)

```bash
make hc-repl
make hc-repl-smoke
```

Bridge only — **do not** add language features to `bootstrap/hc_repl/jit.hc`. Destination:
guest `Compiler_RV` ([COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md)).

## Boot welcome and history

On start, `boot.hc` prints `[boot] HolyC primitives loaded…` then `Help;` — a short
capability overview (eval, editors, Man, MemMap/Regs, asm, timer, files, keys, soft
`Reset;`). Type `Help;` again anytime. To leave a session, use guest `Reset;` (re-enter boot)
or your platform’s normal halt/reset; do not treat host-emulator key sequences as product UI.

Readline history is **preloaded** (oldest→newest) so **Up** walks demos first:

`Help;` → `1+2*3;` → `Man("Clint");` → `Man("Print");` → `Src("Dir");` → `MemMap;` →
`Regs;` → `Dir;` → `Cat("boot.hc");` → asm/`Reg("a7")` → `Uf("Print");` → `Fmt("boot.hc");`

(Seed lives in C `hist_seed()` in `worry_dream_repl.c`; banner text in `bootstrap/seed/boot.hc`.)

## Everyday commands

| Action | Example |
|--------|---------|
| Define + call | `I64 Add(I64 a,I64 b){return a+b;}` then `Add(40,2);` → `0x2a` |
| Print | `"x=%d\n", 42;` |
| Edit source | `Src("Dir");` — opens default editor (Vi), `:w` / quit, then `Run` |
| Goto def | Vi: `gd` / `^]` / Enter on symbol; EditHoly: `^]` / `^G`. Pushes a buffer session (memfs spill, depth 4) and loads `SrcFile("Name")` in the same editor loop; `:q` / `^X` pops. Resolve: srcmap file → srcmap text spill → memfs / `Name.hc` → `DocFileFor` (Man topics). No full TempleOS hash `SrcLink` yet. |
| Man under cursor | Vi: `K` or `gM` → `Man(ident)` then press a key to redraw. EditHoly: `^K`. |
| Format file | `Fmt("file.hc");` — host `HolyFmtSrc` (same as `holyc-riscv --fmt`) |
| Help / symbols | `Help;` `Man("Print");` `Man("CLINT");` / `Man("Clint");` `SrcFile("Print");` |
| Debug | `MemMap;` `Regs;` `StkRep;` (host-slot backed on `repl.elf` — honest C, not hollow labels). MemMap last column = HolyC driver (`MemMapDrvFind("uart")`, `Man("MemMap")`) |

`Man("Name")` covers HolyC functions (doc blocks above definitions) and **topics/symbols** in
`bootstrap/seed/man_topics.hc` — hardware like **CLINT** / **PLIC**, `MEM_*` addresses, CSR
timer bits (`MTIE` / `MIE`). Lookup is case-insensitive where practical (`Clint` / `CLINT`).
Example: `Man("CLINT")` prints this board profile’s `mtime`/`mtimecmp` via `MEM_*` and the
`SetTrap` → `TrapInit` → `TimerArm` → `wfi` programming path.

Default editor is Kconfig **Editors** (`Vi` / `Edit` / `Ed`) → `bootstrap/seed/RVEditorSelected.hc`.
Override live: `editor=&EditHoly;` / `editor=&EdHoly;` / `editor=&Vi;`.

Host formatter from the Mac/Linux side:

```bash
./holyc-riscv --fmt [--stdout] file.hc…
make fmt-test
```

## Inline `asm{}` (RISC-V)

Unlabeled `asm{}` on the host/REPL path emits raw RV via `TryAssembleRiscV`. Notes:

- No `subi` — use `addi rd, rs, -imm`.
- `sub` is R-type only (`sub rd, rs1, rs2`).
- ABI names `a0`–`a7`, `s0`–`s11`, … work.
- Guest destination assembler is `Compiler/Asm_RV.HC` (`CMP_RV_ASM`).

```holyc
asm {
  li a7, 20
  addi a7, a7, -4
};
Regs;
```

More: [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) (asm section).

## Ctrl-C interrupt

| Context | Behavior |
|---------|----------|
| At `>` prompt | Clears the draft line, prints `^C` / `Interrupted`, stays at the prompt |
| During eval (busy `for(;;)`, …) | UART RX IRQ (PLIC #10 on the default virt-style map) sets a break flag; trapvec aborts the eval — `Interrupted` back to `>`, or `throw('Break')` into an active `try`/`catch` |
| `Break;` | HolyC helper: `throw('Break')` (same exception code) |

`TrapInit` enables 16550 RX IRQ + PLIC + `mie.MEIE`, so a normal `wfi` **does** wake on Ctrl-C. If you clear `mstatus.MIE` or `mie.MEIE` (or never call `TrapInit`), bare `wfi` will not see Ctrl-C until a timer or other IRQ wakes the CPU. Editors are not break-armed: `^C` is still a keystroke there.

## Honesty

- Legacy `repl.elf` still uses **host slots** (`0x87001xxx`) for compile/run, Callers, MemMap, Regs, traps, etc. Inventory: [REGRESSION.md](../tests/REGRESSION.md).
- Graphics / WinMgr are **not** this UART REPL — use `make kernel-fb-smoke` / `kernel-win-smoke` ([BOARD_FB.md](../templeos-riscv/BOARD_FB.md)).
- Full DolDoc / mouse / net are not implemented.

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md) — what execution smokes cover
- [../AGENTS.md](../AGENTS.md) — agent-oriented build notes
- [README.md](README.md) — documentation index
