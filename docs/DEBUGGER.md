# Debugger (UART REPL / dig-down)

In-guest inspection on the RISC-V HolyC REPL: registers, traps, stack, breakpoints,
disasm. Soft dig-down is first-class here; **UART GDB RSP** (`GdbStub`) is a partial
host attach path. QEMU `-gdb` / OpenOCD remain for JTAG / ELF load — [BAREMETAL.md](BAREMETAL.md).

**Scope today:** legacy full UART REPL (`bootstrap/repl.elf` / `worry_dream_repl.c`
host slots) has the richest surface. Product `repl-holyc` shares HolyC seeds
(`debug.hc`, `trap.hc`, `disasm.hc`, …) but may print `host slot empty` for
`Regs` / `StkRep` / `Callers` until those move fully into HolyC.

Related: [REPL.md](REPL.md), [DATASHEET.md](DATASHEET.md), [FILE_EXPORT.md](FILE_EXPORT.md),
[BOARD_FB.md](../templeos-riscv/BOARD_FB.md), `Man("Regs")`, `RegHelp;`, `Sections;`
(section 5 = debug/runtime).

Seeds: `bootstrap/seed/debug.hc`, `crash.hc`, `hwdbg.hc`, `gdbstub.hc`, `trap.hc`, `csr.hc`, `disasm.hc`, `sym.hc`,
`callers.hc`. Kernel x86-style `Dbg` / `Panic` / `S` / `B` live in `Kernel/KDbg.HC`
(not wired as the UART REPL debugger).

---

## Capability matrix

Status is **as of the tree now** (implementation in flight). Update this table when
APIs land; prefer probing `debug.hc` / `worry_dream_repl.c` over guessing.

| Capability | Status | Invoke | Limits |
|------------|--------|--------|--------|
| **Regs / Reg / Dr** | **works** (legacy REPL) | `Regs;` `Reg("a7");` `Dr;` | Snap+**restore** at stub entry; not mid-expr freeze. `repl-holyc`: host slot empty until HolyC snap. |
| **CSR dig-down** | **works** | `Reg("mstatus");` `CsrExplain("mcause");` `GetMStatus;` `Bits("mie");` | Named subset in `csr.hc`; `CsrDecode*` prints set bitfields; datasheet via `Bits`/`DsDecode`. |
| **Trap freeze** | **works** | auto on fault/`ebreak`; `DbgReg(n);` `DbgRa;` `DbgSp;` `DbgFP;` `pc;` | Frame at `MEM_TRAP_SNAP` (`0x87000100`). Words 18..20 = mcause/mepc/mtval. |
| **TrapDump** | **works** | `TrapDump;` | Prints snap CSRs + a0..a3/ra/sp/fp then `Bt`. |
| **Fault dump + abort** | **partial** (product) | `CrashDump` + `crash>` when trap path runs; `CrashMon;` anytime | Auto on `Fault;` needs G2 `TrapInitOnce`/mtvec. Legacy: C `trapvec` brief dump. |
| **Crash monitor** | **works** (product) | `CrashMon;` `CrashHelp;` `Md`/`Mw`; boot `SetTrapFn(&CrashOnTrap)` | `crash>`: `md`/`da`/`mw`/`regs`/`bt`/`pc`/`dump`/`go`/`reboot`; aliases `pc`/`sp`/`fp`/`snap`. Seed `crash.hc`. FB twin: `RVWinSerial` + `RVCrashMon*`. |
| **Software breakpoints** | **works** | `Bp(&Fn);` `Bps;` `BpClr(addr);` `Cont;` | One-shot `ebreak`; max 16; refuses RVC; default dump+continue. `BpStop` aborts eval to `>`. |
| **Backtrace / stack walk** | **works** | `Bt;` `StkRep;` | HolyC `Bt` (trap freeze or live FP). Legacy `StkRep` host slot when present; else `Call(Bt)`. Caps ~16 frames. |
| **Callers (static xref)** | **works** (legacy) | `Callers("Print");` `WhoCalls;` `CallersGo;` | Scans JIT bodies; C builtins / fn-ptrs invisible. |
| **Symbolize PC** | **works** | `FunSegFind` / `SymName` / `SymBase`; used by `Da` / `Uf` / `Bt` | Nearest HTT_FUN below addr (+ size when known). |
| **Disasm at PC / name** | **works** | `U(pc-16);` `Uf("Print");` `UA(addr);` `Disasm("Print");` | After trap, `pc` / `_RIP` = last mepc. |
| **Hex / symbolic dump** | **works** | `D(a);` `Dm(a,n);` `Da(a,n);` | `Da` symbolizes I64 slots. |
| **MemMap** | **works** | `MemMap;` `MemMapFind("trap");` | Trap/regs snap rows; driver column. |
| **Ctrl-C / Break** | **works** | Ctrl-C during eval; `Break;` | `throw('Break')` / prompt; not a debug stop. |
| **Watchpoints** | **works** (soft) | `Watch(&x);` `WatchChk;` `Watchs;` `WatchClr;` `WatchBreak;` | Soft compare ≤8 bytes; checked in `DbgTrap` / `WatchChk`. Soft path never needs Sdtrig. `WatchBreak` aborts eval on hit. |
| **Single-step** | **works** (soft) | `Step;` `StepOver;` | Next-insn / ra one-shot `ebreak`. Sequential only (no branch follow); no `dcsr.step`. |
| **Interactive Dbg shell** | **partial** | `BpStop;` then re-call from `>` | No TempleOS `Dbg;` prompt. `BpStop` aborts to `>`; `Cont` documents re-invoke. |
| **Hardware triggers (guest)** | **partial** | `HwTrigProbe;` `HwWatch(&x);` `HwBreak(&F);` `HwClr;` `HwHelp;` | `hwdbg.hc`: M-mode `tselect`/`tdata*`/`tinfo` on QEMU virt (`tinfo≈0x44`). Action=breakpoint → `DbgTrap`. `dcsr.step` **not** guest-writable. |
| **Host gdbstub / OpenOCD** | **works** (virt gdbstub) | `make hwdbg-smoke`; OpenOCD on FE310 | QEMU `-S -gdb tcp::3333` + `riscv64-elf-gdb`: `break`/`stepi`/`hbreak`/CSR peek. Board JTAG: [BAREMETAL.md](BAREMETAL.md). |
| **UART GDB RSP (guest)** | **partial** | `GdbStub;` / `make gdb-uart-smoke` | Cooperative stub: `?`/`g`/`G`/`m`/`M`/`p`/`Z0`/`z0`/`q*`/`D`. Soft-step `s` arms `Step`; `c`→`S05` (no resume while attached). `GdbUseMux` ch2 flag; TX still raw. |

---

## Recipes (what works today)

### Registers after `asm{}` (same eval line)

```holyc
asm { li a7, 20; addi a7, a7, -4 }; Reg("a7");   // expect 16
Regs; asm { li s2, 1; li a7, 4; sub a7, a7, s2 }; Regs;
asm { li a7, 5 }; Regs; "post=%d\n", Reg("a7");  // restore keeps stub-entry a7
RegHelp; Man("Regs");
```

Caller-saved regs do **not** survive across REPL **line** boundaries.

### Register naming (`Reg` / `Regs`)

`Reg("name")` and `Regs` accept **case-insensitive** GPR aliases (see `csr.hc` / `Man("ABI")`):

| Form | Example | Resolves to |
|------|---------|-------------|
| Numeric | `x10`, `X2` | x10, x2 (sp) |
| ABI | `a0`, `sp`, `ra`, `t0`, `s0` | Standard psABI names |
| Synonym | `fp` | s0 (x08, frame pointer) |
| Constant | `REG_A0`, `reg_sp` | Same as ABI name after `REG_` |

Output format: `x10/a0 = 0x…` with a one-line role hint (`arg/ret`, `stack pointer`, …).
`Regs` lists x1..x31 the same way (x0/zero omitted — always 0).

```holyc
asm { li a0, 42 }; Reg("a0");    // x10/a0 = …
Reg("x10");                      // same GPR
Reg("fp");                       // x08/s0 (frame pointer)
Man("ABI"); Man("Reg"); RegHelp;
Run("A02_RegsABI.hc");           // tutorial lab
```

**Limits:** FPR names (`fa0`, `ft0`) work in `asm{}` Tab completion only — not `Reg("fa0")` yet.
CSR names (`mstatus`, `mepc`, …) are separate from GPR aliases. Live mid-prologue read
after `asm{}` on a **later** line is still stub-entry snap (same-line `asm{…}; Reg("a0")` required).

### Trap / breakpoint inspect

```holyc
I64 Add(I64 a, I64 b) { return a + b; }
Bp(&Add);
Add(11, 22);          // *** breakpoint @ … a0/a1 dump, then continues
Bps; BpClr(&Add);

Fault;                // product: CrashDump → crash> (md/mw/regs/bt/go)
// crash> regs
// crash> md 0x87000100 64
// crash> go            // abort eval → >
U(pc - 16);           // disasm around last trap PC (if disasm seeded)
"ra=%X sp=%X fp=%X\n", DbgRa, DbgSp, DbgFP;
Dm(MEM_TRAP_SNAP, 0x90);
CrashHelp; Man("CrashMon");
```

`INT 3;` / `asm { ebreak };` also raise cause 3 once `TrapInit` + a handler are set.
`Bp` installs `SetTrap("DbgTrap")` for you (overrides `CrashOnTrap` until you
`SetTrap("CrashOnTrap")` again).

### Backtrace

```holyc
Bt;                     // HolyC FP walk (trap freeze if pc+DbgFP valid, else live)
StkRep;                 // host-slot C walker on legacy REPL; else Call(Bt)
// On fault, trapvec already prints a stack: walk automatically.
Callers("Print");       // who calls Print (static JIT xref), not a live stack
```

### Soft watch / step

```holyc
I64 w;
Watch(&w); w = 7; WatchChk;     // *** watch hit
WatchBreak;                     // next DbgTrap watch hit aborts eval
Watchs; WatchClr(&w);

pc = FnAddr("Add"); Step;       // one-shot ebreak at next insn
StepOver;                       // one-shot at DbgRa / live ra
TrapDump; DbgHelp; Man("Debugger");
```

### Disasm / dump / symbols

```holyc
Uf("Print"); U(FnAddr("Print"), 8); UA(pc - 16);
Da(DbgSp, 8); Dm(MEM_HEAP, 64);
```

### Export a snap off the guest

```holyc
DumpMem(MEM_TRAP_SNAP, 0x100);   // host: tools/uart_recv_dump.py — FILE_EXPORT.md
```

---

## Regs: snap + restore (honest freeze points)

On legacy `repl.elf`, `regs_snap_stub` / `reg_one_stub` (`worry_dream_repl.c`):

1. Snapshot `x1..x31` → **`MEM_REGS_SNAP`** (`0x87000300`; `t6` via `sscratch`).
2. Print from the snap (C UART may smash live regs).
3. **Restore** GPRs from the snap before `ret` (`Reg` preserves C return in `a0`).

CSR lines are live `csrr` at print time. Each CSR line is followed by **set-field decode**
(`CsrDecodeMstatus`, `CsrDecodeMcause`, …) — only non-zero / interesting bits.
On-demand: `CsrExplain("mstatus");` or `Bits("mstatus");` (datasheet tables in `ds_csr.hc`).

| Need | Use |
|------|-----|
| Dig-down after `asm{}` on the **same** line | `Regs;` / `Reg("name");` |
| Values at last trap / `ebreak` | `MEM_TRAP_SNAP` / `DbgReg` / `Dbg*` helpers |
| Live mid-expression, no call boundary | **Not available** |

Snap is **stub entry** (after HolyC `Regs`/`Reg` prologue + `jalr` into the stub).
`ra` in the dump is the return into HolyC `Regs`/`Reg`, not the outer REPL caller.

---

## Trap frame layout (`MEM_TRAP_SNAP`)

Published by C `trapvec` / `TrapCtxSave` on every trap (see `debug.hc` `DBG_I_*`):

| Index | Name | Notes |
|-------|------|-------|
| 0 | ra | |
| 1..7 | t0..t6 | |
| 8..15 | a0..a7 | `Bp` dump uses these |
| 16 | sp | trapped SP |
| 17 | s0 / fp | frame pointer for stack walk |
| 18 | mcause | published by C `trapvec` / `DbgTrap` |
| 19 | mepc | freeze PC |
| 20 | mtval | |

Helpers: `DbgReg(n)`, `DbgRa`, `DbgSp`, `DbgFP`, `TrapDump`. Global `pc` (`_RIP`) = last mepc.

---

## Software breakpoints (`Bp`)

| API | Role |
|-----|------|
| `Bp(&Fn)` / `Bp(addr)` | Patch one 32-bit insn → `ebreak`; one-shot |
| `Bps` / `BpClr(addr)` | List / clear |
| `BpStop` / `BpGo` | Abort eval on hit vs dump+continue (default) |
| `Cont` | Documents resume: auto-continue, or re-call after `BpStop` |

On hit: `DbgTrap` restores insn, dumps args + `Bt`, returns `epc` to re-run (`BpGo`).
With `BpStop`, returns 0 → fault recover to `>` (no live resume context).

---

## Backtrace details (`Bt` / `StkRep`)

HolyC `Bt` (`debug.hc`) and legacy C `stk_rep` share the same frame rules:

- Prefer trap freeze: `pc` + `DbgFP` when both look like RAM.
- Else live `s0`/`ra` (`DbgLiveS0` / `DbgLiveRa`); `StkRep` starts at the caller.
- JIT: decode frame size from entry `addi sp,sp,-N`; saved `ra`/`s0` at `s0-N`.
- C builtins: gcc-style `ra` at `s0-8`, prev `s0` at `s0-16`.
- Symbolize each PC via nearest HTT_FUN; cap ~16 frames.

Legacy `StkRep` uses the host slot when present; otherwise `Call(FnAddr("Bt"))`.

---

## Watchpoints / single-step (soft)

### Watchpoints (soft — works)

`Watch(addr, len=8)` snapshots ≤8 bytes. `WatchChk` / `DbgTrap` compare; on change
print `*** watch hit` + `Bt`. `WatchBreak` aborts eval on hit; `WatchContinue` is
report-only. Soft path never needs Sdtrig — stores that never trap are invisible until
you `WatchChk` or hit another trap. Hardware twin: `HwWatch` ([below](#hardware-triggers--host-gdb)).

### Single-step (soft — works)

`Step(addr=pc)` / `StepOver` arm one-shot `ebreak` at next sequential insn / return
address. Not `dcsr.step`; branches are not followed. Do **not** pretend Kernel `S;` /
`G;` work on UART REPL until an RV port of `KDbg.HC`. Host twin: gdb `stepi`
(`make hwdbg-smoke`).

---

## Hardware triggers / host gdb

### Guest Sdtrig (`hwdbg.hc` — partial)

QEMU virt (`-cpu rv64`, `debug=on` default) exposes Trigger Module CSRs to M-mode:

| CSR | Addr | Notes |
|-----|------|-------|
| `tselect` | `0x7a0` | Trigger index (virt: 2 triggers) |
| `tdata1` | `0x7a1` | mcontrol / mcontrol6 |
| `tdata2` | `0x7a2` | Match address |
| `tinfo` | `0x7a4` | Type bitmask; virt often `0x44` (types 2 + 6) |

```holyc
HwTrigProbe;                 // expect match trigger present
I64 w; HwWatch(&w);          // mcontrol store|M → breakpoint on store
HwBreak(&Fn);                // execute match
HwTrigs; HwClr; HwHelp;
HwStep;                      // prints: use soft Step or host stepi
```

`HwWatch` / `HwBreak` program trigger 0 with action=breakpoint. Arm a trap handler
before expecting hits: `SetTrap("DbgTrap"); TrapInit;` (same as soft `Bp`).
`dcsr` / `dpc` are Debug-mode only — **not** writable from the guest on virt.

### Host gdbstub (works on virt)

```bash
make hwdbg-smoke
# or manually:
qemu-system-riscv64 -M virt -cpu rv64 -m 128M -nographic -bios none \
  -kernel bootstrap/repl.elf -S -gdb tcp:127.0.0.1:3333
riscv64-elf-gdb bootstrap/repl.elf \
  -ex 'target remote :3333' -ex 'break *_start' -ex 'continue' -ex 'stepi'
```

Scripted recipe: `tests/gdb/hwdbg_virt.gdb` (break / stepi / `hbreak` / mcontrol WARL).

### UART GDB RSP (guest stub — partial)

Board / UART-only path (no QEMU `-gdb`, no JTAG). Seed
`bootstrap/seed/gdbstub.hc` loads in early boot (after `hwdbg`); memfs
`Run("Boot/gdbstub.hc");` remains as a fallback:

```holyc
GdbStub;                  // takes UART until detach
// or: Run("Boot/gdbstub.hc"); GdbStub;
```

**Regs `g`/`G`:** inline asm snap into `MEM_REGS_SNAP` (same pattern as
HolyC `RegsSnapOnly` / repl-holyc — **no** hung `Hc*` snap calls). `G` writes
the snap (+ `g_gdb_pc`); cooperative stub does not restore live GPRs.

**Transport today:** raw UART with `$HC_GDB$` … `$HC_GDB_END$`
(`make gdb-uart-smoke`). Stub TX uses raw `UartPut` (not framed ch0). Mux ch2
is reserved (`GdbUseMux`); prefer raw attach until demux round-trips dbg.

```bash
# One-shot smoke (Python RSP client, no host gdb required):
make gdb-uart-smoke

# Interactive — after seal on guest:
#   Run("Boot/gdbstub.hc"); GdbStub;
python3 tools/uart_gdb_proxy.py --uart /dev/pts/N --listen 3334
riscv64-elf-gdb bootstrap/repl.elf \
  -ex 'set architecture riscv:rv64' \
  -ex 'target remote :3334' \
  -ex 'info registers' -ex 'x/4xb 0x80000000'

python3 tools/uart_gdb_proxy.py --qemu bootstrap/repl.elf
python3 tools/uart_gdb_proxy.py --selftest
```

| Packet | Behavior |
|--------|----------|
| `?` | `S05` (TRAP) |
| `g` / `G` / `p` | GPRs via inline snap → `MEM_REGS_SNAP` + PC (`mepc` or `ra`) |
| `m` / `M` | Read/write DRAM `0x80000000..0x88000000` (≤128 B) |
| `Z0` / `z0` | Soft software breakpoint — same `DbgActive` table as `Bp`/`BpClr` (silent; no UART chatter). `qSupported` advertises `swbreak+`. |
| `s` / `S` | **Soft-step:** arm one-shot ebreak at next insn after `g_gdb_pc` (`Step` semantics), then `S05`. Guest does **not** run while attached. |
| `c` / `C` | `S05` remain stopped (honest: cooperative stub cannot resume while attached). After `D`, use soft `Cont`/`Bp` or re-enter. |
| `qSupported` / `qAttached` / `qC` / thread info | `PacketSize=600;swbreak+;hwbreak-` + minimal OK replies |
| `D` / `k` | Detach; if any soft Bp left, `TrapInit` post-RSP; restore console |

**Not yet:** real continue into guest while attached, hardware `Z1`/`z1`, CSRs via
RSP, SMP threads, mux ch2 round-trip (`GdbUseMux` is intent-only). Prefer soft
`Bp`/`Step` after detach or host qemu-gdbstub for live stepi.

### OpenOCD / FE310 (board)

JTAG load + gdb on real silicon still follows [BAREMETAL.md](BAREMETAL.md)
(`gdb_port 3333`, `load`, `break`, `continue`). SiFive FE310: use the board's OpenOCD
cfg; guest `Hw*` CSRs only help if the hart implements a Trigger Module visible in
M-mode — prefer OpenOCD hardware breakpoints/watchpoints on silicon.

---

## vs gdb / OpenOCD

| Job | Prefer |
|-----|--------|
| Dig-down inside HolyC / JIT / memfs | This doc (`Regs`, `Bp`, `Uf`, `StkRep`) |
| GDB over UART (board, no JTAG) | `GdbStub;` + `tools/uart_gdb_proxy.py` (partial RSP) |
| HW break/watch on virt without patching text | `HwBreak` / `HwWatch`, or gdb `hbreak`/`watch` |
| Load ELF, flash, FE310 JTAG | [BAREMETAL.md](BAREMETAL.md) OpenOCD + `riscv64-*-gdb` |
| FB / WinMgr interactive | [BOARD_FB.md](../templeos-riscv/BOARD_FB.md) — UART HolyC ExePutS via `RVWinSerial` (`1+1;` → `ans=2`; `fault`→`crash>`) while FB is up |
| Pull snaps/files to host | [FILE_EXPORT.md](FILE_EXPORT.md) |

Archive `bootstrap/archive/stepping_debugger.c` and `tests/scratch/legacy/debugger.hc`
are **not** product — do not grow them.

---

## Image matrix

| Guest | Regs / StkRep / Callers | Bp / Disasm / CSR / Dm | Notes |
|-------|-------------------------|------------------------|-------|
| Legacy `repl.elf` | host slots | seed HolyC | Full dig-down; regression covers Regs restore + `Bp` smoke |
| `repl-holyc` / bootloader-repl | HolyC soft | seed HolyC in AOT blob | `CrashOnTrap` default; `#include` `crash.hc` / `hwdbg.hc` |
| Kernel plat / phase3 / win | `RVWinSerial` + `RVCrashMon*` (UART) | UART ExePutS REPL + dig-down meta | Dig-down `Regs`/`Reg("a0")` = soft GPR snap → `MEM_REGS_SNAP` (+ CSR). Dig-down `bt` = live FP/RA (code PCs `<0x87000000` only) with **static** sym map (no `HashFind`/`FunSeg`). Crash>`bt` = trap **mepc** only (no fp/ra freeze). Full product `CrashOnTrap`/`Bt` is `repl-holyc`. |

Smokes: `make dbg-smoke` (Regs/Bt/Bp/Watch), `make trap-smoke` (Fault/`crash>`/Break), `make hwdbg-smoke` (qemu-gdbstub + `HwTrigProbe`),
`make gdb-uart-smoke` (guest `GdbStub` RSP), `make repl-regression` (Regs restore + Bp),
`make repl-smoke` (Bp demo).

---

## Related

- [REPL.md](REPL.md) — interactive overview / Ctrl-C
- [OPS.md](OPS.md) — operate-through / recovery when UART still lives
- [DATASHEET.md](DATASHEET.md) — `DsDecode` / `Bits`
- [FILE_EXPORT.md](FILE_EXPORT.md) — `DumpMem` trap snaps
- [BAREMETAL.md](BAREMETAL.md) — OpenOCD / gdb
- [SELF_HOST.md](SELF_HOST.md) — product HolyC guest path
