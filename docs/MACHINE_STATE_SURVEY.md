# Showing all the machine: a survey of RISC-V architectural state

What a debugger would have to capture and display to show *everything* the hardware holds, what
this port captures today, and what each missing piece costs. Written 2026-09-18 while building
the register sidebar (`Kernel/RVRegPane.HC`, `Kernel/RVAsmReplUi.HC`).

The short version: **the registers are covered, the CSRs are half-covered and drift, and the
float state is a lie after a fault.** Three of the items below are bugs rather than gaps.

**Status, same day:** items 1, 2, 3, 4, 5 (kernel image), 7 and 10 of §4 are done — the decoders are one shared
file, the freeze carries ten more CSRs, fcsr is read and decoded, satp is decoded in both images,
the privilege the trap came from is displayed, and the kernel image's trap now freezes f0..f31
and fcsr so the pane shows the faulting float state rather than the last stepped one. What is
left is §4 items 6 and 11 and the seed image's half of 5: a paged pane, a generic CSR reader,
and float freezing in the seed trap path.

PMP turned out not to need the illegal-instruction probe after all: whether the hart has those
CSRs is a build-time fact about the board, so CONFIG_HAS_PMP answers it and a build without it
says so rather than faulting.

One more found while wiring this up: **a planted pub delivers only its first argument.** The
rest arrive as zero, declared defaults or not, so `PgAt(root, va, levels)` cannot be called from
the REPL — `PtWalk` exists to make that call in one. It affects every multi-argument pub in the
image (`Dm`, `D`, `Da`, `Lk` is fine at one), and it is the next thing to fix if the REPL is to
grow a real API.

---

## 1. The state, and where a value can come from

There are only three sources in this port, and they disagree about what is true.

| Source | What it holds | Address |
|---|---|---|
| **Fault freeze** | x0..x31 at the moment of the trap, plus 4 CSRs | `0x87000400` canonical, `0x87000100` legacy 22-slot |
| **Stepper context** | x0..x31 and f0..f31 as the asm REPL left them | `0x87000400` (shared!), `0x87000800` |
| **Live CSR read** | whatever the CSR says *now*, not when you stopped | `Csr("name")`, `RVWinCsrr*` |

The freeze and the stepper context are **the same array** — deliberately, so `_A0` means one
thing whether you got there by faulting or by stepping (`Kernel/RVRegPane.HC:9`). The float file
is not shared with anything, which is where the lie comes from (§3.1).

| State | Captured at a fault | In the stepper | Readable live | Displayed |
|---|---|---|---|---|
| x0..x31 | yes | yes | — | yes |
| pc | yes (as mepc) | no | — | yes |
| f0..f31 | **no** | yes | — | yes, **but see §3.1** |
| fcsr / frm / fflags | no | no | yes | `Csr("fcsr")`, decoded |
| mcause, mepc, mtval, mstatus | yes | no | yes | yes, raw |
| mtvec, mie, mip, misa, mscratch, mhartid, satp, medeleg, mideleg, mcounteren | yes (slots 22..31) | no | yes | `Machine()` frozen + decoded; 4 of them in the pane |
| cycle, time, instret | no | no | yes | `Uptime()` |
| mcycle, minstret | no | no | yes | `Csr("mcycle")` |
| mvendorid, marchid, mimpid | no | no | only via `CPUId` | no |
| PMP (`pmpcfg*`, `pmpaddr*`) | no | no | yes, when CONFIG_HAS_PMP | `Pmp()`, decoded incl. NAPOT ranges |
| Page tables | via satp in the freeze | — | yes | `Pg(va)` walks and prints every PTE; `Pt` dumps the root |
| Current privilege mode | as mstatus.MPP | — | — | `Dbg`/`Machine`: "trap came from M" |
| PLIC pending/threshold/priority | no | no | yes | `Plic()` |
| CLINT mtime/mtimecmp | — | — | yes (MMIO) | no |
| hpmcounter3..31 | no | no | no | no |
| Vector state (vtype/vl/vstart) | no | no | no | no (extension not implemented) |

## 2. Why "read any CSR" is the hard one

A CSR number is an **immediate in the instruction encoding**. There is no `csrr rd, rs` — so a
runtime reader cannot be a loop over a number. Everything in the tree is therefore an if-chain
over hand-written stubs: 24 of them in the kernel image (`Kernel/RVWinSerial.HC:43`, reached by
`Csr(name)` at `Kernel/RVExplore.HC:451`), 27 in the seed image (`bootstrap/seed/csr.hc:363`,
`CSRGet` at :646, which returns 0 for anything it does not know). About 4000 CSR numbers are
unreachable.

Three ways out, in increasing order of what they buy:

1. **Generate the switch.** A table of the ~60 CSRs that exist on this hardware, one `csrr` each,
   generated rather than hand-written so it cannot drift. Bounded, boring, and enough for any
   view a person reads.
2. **Assemble one at runtime.** Write `csrr a0, <n>; ret` into a scratch page and call it — the
   asm REPL already does exactly this for any line you type, and a test does it directly
   (`tests/exec/cases/kernel_bin_probe.hc:892`). Reaches all 4096, needs an illegal-instruction
   probe to tell "reads as zero" from "does not exist".
3. **Neither, for the stopped context.** A CSR read *now* is not the value you stopped at. The
   only honest way to show the machine as it was is to widen the freeze (§3.2).

## 3. The three bugs

### 3.1 The float block is stale after a fault — misleading, shipped today

`Kernel/RVRegPane.HC` reads f0..f31 from `0x87000800`, which is the **asm stepper's** register
file (`Compiler/RVAsmRepl.HC:23`). No trap path writes it: neither trap vector contains a single
`fsd` (`bootstrap/seed/trap.hc`, `bootstrap/holy_rt.h` — zero hits). So after a fault the pane
shows 32 float registers that belong to whatever you last stepped, presented identically to the
integer registers, which are real. Of everything in this survey this is the one to fix first,
because it is the only item that is *wrong* rather than *absent*.

Fixed: the C runtime's publisher now saves f0..f31 to `0x87000E00` and fcsr beside them, guarded
on mstatus.FS — with FS=Off an `fsd` is an illegal instruction, so saving unconditionally would
fault inside the trap handler, which is a loop rather than a message. A flag at `0x87000F00`
says the block belongs to a trap, and the pane reads whichever file is current and names it in
the heading. The seed image's trap publisher still saves no float state, so there the label is
the whole fix.

### 3.2 Only four CSRs are frozen — FIXED, ten more now

`mcause`, `mepc`, `mtval`, `mstatus` (slots 18-21, `bootstrap/seed/debug.hc:21`). Everything else
— mtvec, mie, mip, satp, mscratch — is read live, so it can drift between the fault and the
moment you look at it. Widening the freeze is ~15 `csrr`+`sd` pairs in each of the two trap
vectors plus a bigger frame; the float half is 32 `fsd` and needs mstatus.FS handled, since
saving FP state in a trap when FS is Off would itself trap.

Done for the integer half: both publishers now freeze mtvec, mie, mip, misa, mscratch, mhartid,
satp, mcounteren, medeleg and mideleg into slots 22..31 — which is exactly the room between
mstatus and the live-`Bt` scratch at `0x87000200`, so that is where the list stops. `Machine()`
reads them back and decodes them. The float half is still open (§4 item 5).

### 3.3 The catalog documents what the assembler rejects

`AsmDoc("fmvdx")` prints the template `fmv.d.x fd, rs`, but the guest assembler only accepted the
dot-free `fmvdx` — typing what the documentation told you to type raised "Unsupported RISC-V asm
mnemonic". Fixed here by accepting both spellings (`Compiler/Asm_RV.HC`). The same class of drift
is worth a test: every template in the catalog should assemble.

Two more, found in passing, both in the **seed** image and not on the kernel path:

- `RegsDumpHc` spills 10 CSRs to `0x87000400`..`0x448` (`bootstrap/seed/csr.hc:1556`: `lui t6,
  0x10E00; slli t6,t6,3` is `0x87000000`, then `sd t5, 0x400(t6)`) — which is `TRAP_SNAP_X`
  slots x0..x9. Typing `Regs;` after a fault corrupts the low ten registers of the freeze that
  `_X0.._X9` and `DbgX` read back.
- `TrapFaultDump` prints frame slot 0 as `ra` (`bootstrap/seed/trap.hc:535`), but `TrapCtxSave`
  puts x1 at offset 8 and never writes slot 0. The `ra =` line is uninitialised stack.

## 4. What it would take

Ordered by value per unit of work. Items 1-3 are worth doing regardless of how far the display
goes; 4-6 are the display itself.

| # | Work | Touches | Size | State |
|---|---|---|---|---|
| 1 | Stop the float block lying: tag each block with where its values came from | `RVRegPane.HC` | small | **done** — labelled "(as last stepped)" |
| 2 | `fcsr` read + frm/fflags decode — the only float state with no reader at all | a stub per image, one decoder | small | **done** — `Csr("fcsr")`, `CsrDecodeFcsr` |
| 3 | One copy of the decoders instead of two forks | new shared file, both images | medium | **done** — `bootstrap/seed/csr_decode.hc` |
| 4 | Widen the freeze: 10 more CSRs at trap | both trap publishers | medium | **done** — slots 22..31, `Machine()` reads them |
| 5 | Float registers in the freeze (32 `fsd`, mstatus.FS aware) | trap publishers | medium | **done for the C runtime** (`HOLY_TRAP_SNAP_F`); the seed image's publisher still saves none |
| 6 | Paged/tabbed pane: registers, float, CSRs, decoded mstatus — 32+32+60 values do not fit a screen at any size | `RVRegPane.HC`, `RVAsmReplUi.HC` | medium | open (ranked blocks are the stopgap) |
| 7 | satp decode (mode/ASID/PPN) in the kernel image; it existed only in the seed datasheet | `RVExplore.HC` | small | **done** |
| 8 | PLIC state reader (pending/threshold/priority — never claim) | `RVExplore.HC` | medium | **done** — `Plic()` |
| 9 | PMP registers — optional CSRs, so a build option | `RVWinSerial.HC`, `RVExplore.HC` | medium | **done** — `Pmp()` behind CONFIG_HAS_PMP |
| 12 | Page tables: satp decoded but never followed | `RVExplore.HC` | medium | **done** — `Pg`, `PgAt`, `Pt`, `PtWalk` |
| 10 | Privilege mode as a displayed value (mstatus.MPP at a trap) | `RVDbgView.HC` | small | **done** — `Dbg` and `Machine` say "trap came from M" |
| 11 | A generic CSR-by-number reader (§2) — still if-chains, ~4000 numbers unreachable | both images | medium | open |

Note on 6: the sidebar already ranks blocks by the rows available (registers and machine state
always, float next, memory last) because 32 registers plus 32 float registers plus the CSRs is
about 70 rows and no terminal has that. Adding CSRs makes paging unavoidable rather than optional.

## 5. The thing that made this harder than it looked — now fixed

*(Resolved: the pure value decoders live in `bootstrap/seed/csr_decode.hc`, concatenated into the
seed blob by `gen_boot_blob.py`, `#include`d by `bootstrap/hc_repl/repl.hc` for that image and by
`Kernel/RVExplore.HC` for the kernel image. Three manifests, one file — and missing any one of
them turns every decoder call into an unresolved import, which is a fault loop, not a link error.
The kernel's smaller fork is gone.)*

The decoders used to exist **twice**, in two images that cannot call each other:
`bootstrap/seed/csr.hc` has the richer set (mstatus with every field, misa, mie/mip, mtvec, mcause
names, mtval keyed off the cause) and a genuinely table-driven datasheet
(`bootstrap/seed/datasheet/ds_csr.hc`, including the only satp decode in the tree). The kernel
image has a smaller fork in `Kernel/RVExplore.HC`. `Kernel/RVWinSerial.HC:556` says outright that
the seed's `csr.hc` is not linked into the kernel image. Anything written for the debugger view
has to be written in the kernel image or made shareable first — and "make it shareable" is
probably the honest prerequisite for items 3, 4 and 7.
