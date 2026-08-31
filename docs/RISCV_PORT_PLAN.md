# TempleOS on RISC-V — port plan

> **Historical.** Prefer [ARCHITECTURE.md](ARCHITECTURE.md), [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md), and [../templeos-riscv/COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) for current status.

Goal: TempleOS running on QEMU `virt` (RISC-V 64): boot → kernel → HolyC compiler → Adam/Home →
an interactive HolyC shell over the UART (graphics later via virtio-gpu). This plan is written
against measurements from this repo; it is executed phase by phase and updated as numbers move.

## Where we are (2026-08-25)

- `holyc-riscv` (C, host) compiles HolyC to RISC-V and the bare-metal REPL (`bootstrap/repl.elf`)
  compiles and runs HolyC over the UART. Language coverage is execution-verified
  (`HOLYC_IMPLEMENTATION_STATUS.md`); six `Demo/*.HC` files run unmodified.
- Project-mode compile of the kernel (`Kernel/Kernel.PRJ` with the `.HH` headers): stops at the
  first construct family it does not know. `make coverage` reports the tally.
- Standalone compile of every `.HC` (515 files): 18 compile — meaningless alone, because
  TempleOS builds are projects (`Kernel.PRJ`, `Adam/MakeAdam.HC`, `Compiler/Compiler.PRJ`).
- `templeos-riscv/` has a C kernel scaffold (S-mode traps, UART, virtio-blk, RedSea read, a
  compiler slot and a `TosApi` table); `Compiler/*_RV.HC` is a started RISC-V backend for the
  self-hosted compiler.

## What "the rest of TempleOS" is, honestly

TempleOS is x86-64 to the bone: the boot path (`KStart16/32/64`), interrupts/`MultiProc`,
scheduler context switch, paging (`Mem/*`), and drivers (VGA text/graphics, PS/2, ATA/PCI BIOS)
are x86 assembly and hardware. The compiler's backend (`Compiler/Back*.HC`, `Asm*.HC`) is an x86
assembler/JIT. None of that is "compiled to RISC-V"; it is re-implemented. What *is* portable is
most of the language-level code: `Str*`, `KMath*`, `KDate`, `KHash*`, `Compress`, `QSort`, the
DolDoc engine, and Adam's HolyC applications — once the compiler accepts kernel-style HolyC and a
kernel provides the API surface they call.

## Phases

### Phase 0 — runtime completeness for demos (done / in progress)
Print formats, strings, F64, try/catch, Fs, aggregate initializers, sub_switch, MAlloc/Free,
`tS`, `D()`. Remaining: F64 math library (Sqrt/Pow/Ln/Exp/Floor/Ceil/trig), UART input
(`GetChar`/`GetStr`/real `YorN`), `DefineLoad`/`DefineMatch` API.

### Phase 1 — language coverage as a project build (the compiler work)
Drive `make coverage` (project-mode compiles of Kernel, Adam, Compiler with all-errors tally)
toward zero *parse* errors. Known construct families, in order of volume:
1. Declarations: `public`/`extern`/`_extern`/`_intern`/`import`/`_import` qualifiers,
   `extern class X;` forward declarations, `extern` functions become runtime imports (resolved
   by name at load; unresolved imports print a diagnostic instead of crashing).
2. Function attributes: `interrupt`, `haserrcode`, `argpop`, `noreg`/`reg`, `no_warn`; varargs
   (`...`, `argc`/`argv`); `lastclass`; `offset(Class.member)`; `sizeof` on members.
3. `asm { … }` blocks: parsed and skipped with a warning (x86 code cannot run on RISC-V; the
   kernel's asm gets rewritten in phase 2).
4. Whatever the tally says next (`#define` bodies with code, `class` edge cases, `lock {}`,
   `switch [ ]` nobound, `#if` expressions, `#include` of `.Z` names, string escapes).
Exit criterion: `Kernel/Kernel.PRJ`, `Adam/MakeAdam.HC` and `Compiler/Compiler.PRJ` parse with
0 errors (asm blocks skipped), and every portable file executes under the exec harness.

**Status 2026-08-25:** `Kernel/Kernel_RV.PRJ` (Kernel.PRJ minus the x86 files) compiles with
**0 errors** to a 1.09 MB blob (17 asm blocks skipped). `Kernel/KStartRV.HC` stands in for
KStart16/32/64 + KInts/MultiProc/FunSeg: the boot-data asm labels as one-element arrays and the
scan-code tables, plus same-signature stubs for the functions those files define — this is the
list phase 2 has to implement. Constructs added for it: chained relations (`2<=r<=36`), `switch [x]`,
const-expression `case`s, `0b/0o/0d`, `∞`, `1e300`, `'$$'`/`$$` (current address, `IC_PC`),
NUL-carrying and adjacent string literals, DolDoc commands inside strings, postfix casts
(`"…"(U8 *)[i]`, `(&x)(U8 *)`), `offset()`, the x86 bare statements (`PUSHFD CLI STI POPFD` →
`mstatus.MIE`; `HLT` → `wfi`; `INT n` → `ebreak`; `CLD/MOV_RAX_CR2/…` skipped), `lock`, `no_warn`,
varargs with hidden `argc`/`argv` (caller builds the array), `(*fp)(args)`, function-pointer
values as code addresses (PC-relative in AOT), no-paren calls when defaults allow it, implicit
imports for functions used before declaration (AOT), the F64 math runtime (`Pow` for `` a`b ``,
`Sqrt Exp Ln Log2 Log10 Floor Ceil Round Trunc Sin Cos Tan ATan Abs Sign`) with F64-typed
runtime parameters, `Fs`/`Gs` intrinsics, `;` parameter separators, unnamed parameters, `µs`.
**Status 2026-08-25, later:** `Compiler/Compiler.PRJ` and `Adam/MakeAdam_RV.PRJ` (Adam compiled on
top of the kernel project, as TempleOS does against the live kernel; a few compile-time
`DefinePrint` values are `#define`d in the PRJ prelude) also parse with **0 errors**. Added for
them: default arguments as call-site expressions (`CDC *dc=gr.dc`, `F64 w=2.75`, `=-π`; the
default's source text is re-lexed at each call with the current token held pending), `reg`/`noreg`
declarator hints (`I64 reg RSI *dst`), `sizeof(Class.member)`/`sizeof(var.member)`, unbraced
array initializers, nested `{}` for array members, `^^`, `π`, `F64_MAX` as bit patterns
(`0x7FEF…(F64)`: a cast on a literal reinterprets), postfix casts in constant expressions,
bare x86 instructions in HolyC code skipped (`MOV U64 [RSI],R13`), `$IB…$` sprite data as NULL,
`::/` include paths, `#help_index "…"\` continuations, prototypes without `;`, class member
`format "…"` meta-data, labels ending a block, keyword member names (`->reg`), `(*p)(T)` casts vs
`(*fp)(args)` calls, and a function's return type recorded for call sites (`K()==2.5` on F64).
Phase 1's exit criterion is met for parsing. Execution work done toward phase 2: the AOT blob of
`Kernel/Kernel_RV.PRJ` links and its entry chunk runs into the kernel's own `StrPrintJoin`
(1000+ instructions deep) before faulting — an execution bug still under investigation, not a
parse issue. Infrastructure added for running real kernel code: (1) **pointer depth** on symbols/
globals/members/expressions so `*p`/`p[i]`/`argv[i][j]` on `T **`/`T ***` load a pointer, not the
base type; (2) **large frames** — `EmitAddImm` uses lui/add for frame sizes beyond the 12-bit addi
range (StrPrintJoin's frame is ~3 KB with `tmp_buf[]`); (3) **frame-slot markers relocated** to
`-(1<<40)-pos` (`HOLY_LOCAL_MARKER`) so a patched offset can never collide with a marker — the old
`-(10000+pos)` scheme mis-patched large frames; (4) **import self-resolution**: a function used
before its definition (extern-in-header, body later) has its call rewritten to an import slot and
the slot filled by the entry chunk (PC-relative), so forward references don't jump to 0; the loader
directory skips self-resolved slots and names any still-unresolved import at load; (5) ~90 kernel
**runtime intrinsics** (bit tests, queues, port I/O no-ops, register/flag/rdtime accessors, hash
tables, string match) in `bootstrap/holy_rt.h`; (6) `HOLYC_MAP=file` writes a function/data symbol
map for translating fault addresses. The StrPrintJoin execution fault was a **conditional-branch range bug**: `IC_BR_ZERO`/`IC_BR_NOT_ZERO`
emitted a 13-bit B-type `beq/bne` with no range check, so in a function whose then/else block
exceeds ±4 KB (StrPrintJoin's `%` handler) the offset overflowed and the branch landed at a wrapped
address. Fixed with branch relaxation (`EmitCondBranch`): in-range uses beq/bne, out-of-range uses
the inverse short branch over a `jal` (±1 MB). The kernel's own 900-line StrPrintJoin now executes
correctly and formats `"n=1337."` byte-for-byte into a buffer (`tests/exec/cases/e_kernel_strprint.hc`,
an exec oracle running real kernel code). Two more fixes made that work: (a) `ModU64(&q,d)` is a
by-pointer divide (updates `*q`, returns the remainder) — the runtime had it by value, so the
`%d` digit loop never terminated and overran the buffer; (b) the AOT entry chunk now runs the
top-level statements (globals' initializers, `#exe`) **and then calls `main()`** when one is defined
(it used to be either/or, so a kernel-linked `main()` never ran). `IC_JMP` got the same range
relaxation as the conditional branches. The kernel's own **`PutS` now drives the UART**: registering a UART `put_s` sink via the kernel's `KeyDevAdd` and clearing `Fs->display_flags`/`kbd.scan_code`, the kernel's `PutS` (`KeyDev.HC`) walks `keydev.put_key_head` and dispatches to it (`make kernel-puts-smoke`). Unblocking this device-dispatch path took a codegen fix — two indirect calls through fn-pointer members of different arity in one if/else (`PutS`'s `put_s`/`put_key`) had the second's arg count overwrite the first's already-emitted `CALL_INDIRECT`; `SetCallArgCnt` now stamps only the tail call IC. Full boot-time device/task init is still phase-2.

**Verified running kernel functions** (exec oracles that `#include Kernel/Kernel_RV.PRJ`):
`StrPrintJoin` (formatting, all specifiers — including `%f`, once `pow10_I64` is populated), `QSort` (recursion + fn-pointer comparator),
`Str2I64`, `StrPrintHex`, `StrCpy/StrLen/StrCmp`, `Sqrt`, the hash table (`HashTableNew/HashAdd/
HashFind/StrNew`), and the heap (`MAlloc/MSize/Free`). Codegen bugs these flushed out (all fixed):
eval-stack depth across branches (`&&`/`||`/`?:` mid-expression), pointer arithmetic scaling
(`p+n`, `p++`/`p--`, `p-q`), and `ModU64` by-pointer. Known remaining: `ArcCompressBuf` (Compress.HC)
corrupts a data-section import slot mid-run (bit-packing overrun, under investigation); the console
device layer. Still open: the UART runtime stripping DolDoc
`$…$` from printed strings; `PUSHFD/POPFD` keeping flags on the machine stack; the phase-2 kernel.

### Phase 2 — a RISC-V TempleOS kernel (the OS work)
Grow `templeos-riscv/` into a kernel that provides TempleOS's kernel API on QEMU `virt`, reusing
the portable kernel sources and rewriting the x86 parts:
1. Boot/traps/timer/SBI in RISC-V assembly + HolyC (`KStart*` replacement); `Fs` as a register
   (`tp`) instead of the x86 FS segment.
2. Memory: flat identity map; `MAlloc`/`Free` heaps from `Mem/MAllocFree.HC` on a simple page
   allocator (`Mem/MemPag.HC` rewritten).
3. Tasks/scheduler: `KTask.HC`/`Sched.HC` with a RISC-V context switch; `Spawn`, `Yield`,
   `Sleep`, exceptions integrated with the `try/catch` handler stack.
4. Devices: UART text console standing in for VGA text (`DCFill`/`TextRect` → an ANSI
   renderer), UART keyboard, virtio-blk + RedSea (`BlkDev/*`, scaffold exists), timer.
5. Load `Compiler.BIN` (phase 3) and run `StartOS.HC`.
Exit criterion: `Kernel.PRJ` (RISC-V edition) boots on `-M virt`, prints through
`StrPrint`/`Print` from the real kernel sources, `Spawn`s a task, reads a RedSea image.

### Phase 3 — self-hosting compiler
`Compiler/*.HC` with the `_RV` backend files compiled by `holyc-riscv`, then compiling itself on
the target (JIT). Needs phase 1 (it uses the whole language), phase 2 (kernel API), and the
RISC-V backend completed (`BackA_RV`…`BackLib_RV`, a RISC-V `AsmInit`/assembler, `OptPass_RV`).
Exit criterion: `Test_RV.HC` passes when compiled by the target-resident compiler.

### Phase 4 — Adam, Home, Apps
`StartOS.HC` → `MakeAdam` → DolDoc terminal on the UART → apps. Graphics via virtio-gpu once the
text path is solid.

## Working method
- Every step lands with a check in CI (`make ci`): exec oracles, REPL smoke (incl. demo files),
  compliance manifests, and the coverage tally (which may only go down).
- Measure first, then fix the biggest bucket.
