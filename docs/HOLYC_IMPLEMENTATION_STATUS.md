# HolyC Implementation Status

## Execution-verified status (2026-08-24)

The sections below this one describe what *parses/compiles*; `make compliance` cannot see whether
the generated code is right (it now fails on parse errors instead of silently truncating). This
table is what actually **runs correctly** on the RISC-V guest — the bare-metal HolyC REPL over the
UART (`make repl-holyc-smoke`; the legacy C-guest `repl-smoke` is retired) and the AOT exec harness
(`tests/exec/`, CI loads via emulator) — from probing each feature end to end.

| Runs correctly | Missing / known wrong |
|---|---|
| **Real TempleOS demos on the bare-metal REPL and under the AOT harness** (the REPL smoke feeds the files and checks their output): `Demo/Print.HC`, `Demo/NullCase.HC`, `Demo/SubSwitch.HC` (exact `Zero [One] Two …` output), `Demo/RadixSort.HC` (sorts correctly), `Demo/Exceptions.HC`, `Demo/GlblVars.HC` (aggregate initializers, `D()` dumps, `tS`) | `Demo/Carry.HC` (x86 carry flag), `Demo/Define.HC` (`DefineLoad` API), `Demo/MagicPairs.HC` (F64 math library, job queues), DolDoc/graphics/file demos |
| Top level is program level (REPL and AOT): functions, `class`/`union` (incl. `class X {…} a, *b[N];`, self-referential members), `enum`, globals with any initializer incl. **aggregates** (`T a[] = {…}`, `Cls c[] = {{…},{…}}`, strings into `U8` arrays, runtime expressions), `#define` (parameterized, nested, inside parentheses, TABs), `#ifjit`/`#ifaot`/`#exe`, statements — compiled as a frame of their own, so `switch`/`try`/block locals work there too | local (non-static) aggregate initializers |
| `if/else` ladders, ternary, `while`, `do…while`, `for`, `goto`/labels (backward `goto` pops `try` handlers), `switch` incl. `case a...b`, `case:` (auto-increment), fallthrough, `default`, **`sub_switch` `start:`/`end:` blocks** | forward `goto` out of a `try` does not pop the handler |
| **HolyC operator precedence** (Compiler/CInit.HC `binary_ops`): `` ` ``/`<<`/`>>` bind tightest, then `* / %`, then `& ^ |`, then `+ -`, then `< >`, then `== !=`, then `&& ^^ ||` — differs from C (bitwise binds tighter than `+`), so `m&15 +'0'` is `(m&15)+'0'` (the kernel's %X hex path relies on this) | |
| `&&`/`||` (correct even mid-expression, e.g. `x + (a && b) + y` — the short-circuit no longer drops the accumulated operand), `!`, `++`/`--`, all compound assignments, chained `a = b = 3`, unary `-`/`~`, shifts, comparisons; unsigned `/ % < <= > >= >>` when an operand is unsigned | class member functions (not HolyC; `c073`/`p028` are xfail) |
| **F64** through aggregates and pointers: array elements (`a[i]`), struct members (`s.x`), pointer derefs (`*p`) all keep their F64 type; `&x` is a pointer type (not F64). literals (incl. `.5`), `+ - * / %`, compares, unary `-`, I64↔F64 promotion in mixed expressions / assignment / `return`, casts, `Print("%f")`, F64-returning runtime calls (`tS`) | |
| casts: `(U8)`/`(U16)`/`(U32)` mask, `(I8)`/`(I16)`/`(I32)` sign-extend, pointer casts; **F64↔I64 casts relabel the bits** (HolyC: "to typecast int or F64, use ToI64()/ToF64()" — `0x7FF0000000000000(F64)` is inf, `i(F64)` reads i as a double); `ToI64()`, `ToF64()`, `ToBool()` convert | |
| locals, params (own scope), globals (also in expressions with other globals), `static` locals (init-once), typed sub-word loads/stores; arrays (local, global, N-dimensional) decay to their address as values | |
| **AOT data section**: globals and statics work in `holyc-riscv` output (laid out after code+strings, addressed PC-relative) | |
| pointers (`&x`, `*p`, `p[i]`, **pointer arithmetic scaled by element size** — `p+1`/`p++`/`p-q` for `I64*` step by 8, like C), pointee-sized typed elements, **typed class members** (`U8` fields, pointer members `*p->a`, array members `s.name[i]`, `StrCpy(s.name, …)`), `s.x` / `p->x` / `a[i].m` / `a[i].p->m` chains | |
| string literals (PC-relative), char literals (`'AB'` packs; `'ab\n';` statements call `PutChars`), adjacent literals, `"fmt", args;` ≡ `Print(...)`; predefined `NULL TRUE FALSE ON OFF I64_MAX …` | |
| **Runtime, shared by REPL and AOT** (`bootstrap/holy_rt.h`): `Print` (`%d %u %x %X %s %c %p %P %f %n %%`, width/precision, `,` flag, `h<n>`/`h*` repeat), `PutS`, `PutChars`, `MAlloc`/`CAlloc`/`Free`, `StrLen`/`StrCpy`/`StrCmp`/`StrCat`/`StrNew`, `MemCpy`/`MemSet`/`MemCmp`/`MemSetI64`, `AbsI64`/`MaxI64`/`MinI64`, `ToUpper`/`ToLower`, `RandU16`/`RandI64`/`Seed`, `YorN` (answers no), `tS`, `D()` hex dump; `MAlloc`/`Free` with a free list | |
| **AOT calls the runtime too**: externs go through import slots in the data section; the blob ends with a name directory that the exec harness resolves at load (`holy_resolve_imports`) | |
| calls: `Fn(args)`, HolyC `Fn;`, `&Fn`, function pointers, default arguments (trailing and omitted `f(,2)`), same-input define+call, recursion, >8 args; declared-but-undefined or too-few-arguments calls are compile errors | |
| `try`/`catch`/`throw` across calls and nested tries; `Fs->except_ch`, `Fs->catch_except`, `Fs->except_callers[]` exist (`class CTask` + `Fs` are built in) | |
| AOT: entry chunk sets `Fs`, runs the top-level statements (or calls `main()` when there are none); last value → `ORACLE`; parse errors fail the build; REPL errors report the token and line | |
| **2026-08-25 (both REPL and AOT, `tests/exec/cases/e_varargs…e_no_paren_call`)**: chained relations `2<=r<=36`, `switch [x]`, const-expression `case`s (`case -1:`, `case 'a':`), `0b/0o/0d` literals, `∞`, `1e300`, `'$$'`, `$$` as the current address, string literals with `\0` and adjacent-literal concatenation (also across macros), DolDoc `$…$` inside strings, postfix casts `x(U8)` / `"…"(U8 *)[i]` / `(&x)(U8 *)[0]`, `offset(Class.member)`, `>>= <<= %=`, `lock`, `no_warn`, `PUSHFD CLI STI POPFD PAUSE HLT INT` statements, varargs `argc`/`argv`, `(*fp)(args)`, function-pointer values are code addresses (global and local initializers, AOT too), `Fn;` calls when every parameter has a default, `;` between parameters, unnamed parameters, F64 runtime math (`Pow` via `` a`b ``, `Sqrt Exp Ln Floor Ceil Round Sign …`) with I64→F64 argument conversion from the callee's parameter types; **`Kernel/Kernel_RV.PRJ` compiles with 0 errors** (`make coverage`) | DolDoc commands are printed raw on the UART; the compiled kernel's Print reaches its keyboard/screen device layer (PutS), which needs phase-2 device init |
| **pointer depth** (`T **p`, `argv[i][j]`), **large stack frames** (lui/add beyond ±2 KB), frame-slot markers at `-(1<<40)` (no collision on big frames), **import self-resolution** (forward-referenced defs filled by the entry chunk; unresolved imports named at load), ~90 kernel runtime intrinsics (Bt/Que/port-IO/registers/Hash/StrMatch), `HOLYC_MAP` fault-address map, **conditional-branch relaxation** (branches beyond the ±4 KB B-type range jump over a `jal` — the bug that faulted the kernel's 900-line StrPrintJoin); the kernel's StrPrintJoin, QSort (recursion + fn-pointer comparator), Str2I64/StrPrintHex/Str*/Sqrt and the **%f float formatter** (StrPrintJoin("%.4f",3.25)="3.2500", given a populated pow10_I64 table — the test fills it; kernel boot-init is phase 2) all execute correctly (tests/exec/cases/e_kernel_*.hc). An F64-element array decays to its address (an integer), so it must not be typed F64 — else passing it as a vararg mangles the pointer to 0; the kernel's own **PutS drives the UART** via KeyDevAdd + the native keydev walk (register a UART put_s, clear Fs->display_flags/kbd.scan_code); this needed a codegen fix — an earlier call followed by an indirect call of different arity (a direct `add3(1,2,3)` then `(*fp)(7)`, or PutS's `(*put_s)(st)`/`(*put_key)(ch,0)`) had the indirect call's arg count clobber the earlier call's already-emitted IC (SetCallArgCnt now stamps only the tail call IC) | a portable RISC-V boot init `RVKernelInit()` (Kernel/KBootRV.HC) now populates the runtime tables (pow10_I64, rev_bits_table, set_bits_table) and wires the UART console, so a kernel program gets a working environment — `make kernel-boot-smoke` prints %f floats + kernel bit tables via the kernel's own Print over UART; a cooperative scheduler (RVSpawn/RVYield/RVTaskExit on the RVTaskSwitch context-switch primitive — save/restore callee-saved regs+sp+ra) round-robins tasks on RISC-V (`make kernel-sched-smoke`: two tasks interleave A0 B0 A1 B1 …); a PREEMPTIVE scheduler (timer-driven full-context switch) with critical sections (RVCritEnter/Leave), cooperative RVSpawn/RVYield, and RVSleep; RISC-V traps + CLINT timer + PLIC interrupt-driven UART input; capped by kernel_monitor_demo.hc — an interactive monitor where a preemptive background counter runs (lock-protected) while interrupt-delivered commands are handled (`make kernel-monitor-smoke`). persistent storage via a virtio-blk driver (RVBlkInit/RVBlkRead/RVBlkWrite over legacy virtio-mmio — read a disk sector, write one back, verified to persist in the image via `make kernel-blk-smoke`). a simple filesystem on the block device (superblock + directory in sector 0, bump-allocated file data) — format/create/read/list in pure HolyC over RVBlkRead/RVBlkWrite, with files that survive a reboot (`make kernel-fs-smoke` runs the demo twice on one image: create then read back). an interactive SHELL (kernel_shell_demo.hc) composing it all — reads command lines over the UART receive interrupt, runs a preemptive background clock task, and stores files on virtio-blk via the filesystem (ls / cat / write / uptime), `make kernel-shell-smoke`. Still phase 2: the kernel's own CTask/Sched integration, RedSea/richer FS, and x86/hardware boot (CPUId, IDE) |
| **2026-08-25, later**: call-site default expressions (`=gr.dc`, `=2.75`, `=-π`), `reg RSI` declarator hints, `sizeof(Class.member)`, unbraced/nested array initializers, `^^`, `π`, `F64_MAX` bit patterns, casts on literals reinterpret, `(*p)(T)`, `->reg`, `format "…"` member meta-data, prototypes without `;`, F64 results of user functions typed at call sites (`K()==2.5`); **`Compiler/Compiler.PRJ` and `Adam/MakeAdam_RV.PRJ` compile with 0 errors** | |

## Overview

This is a comprehensive status report of what's implemented and what's missing in the TempleOS RISC-V HolyC compiler.

### Automated compile checks

- `make compliance` — curated TempleOS `.HC` tree (expected XFAILs marked in the script) plus **52** HolyC-style parity files under `tests/holyc/compliance/parity/`; last green run: all required cases pass.
- `make ci` — **`make compliance`**, **`make fmt-test`**, then **`make qemu-integration`** (UART oracles, TempleOS smoke, kernel smokes including phase3/plat, REPL regression). Matches [GitHub Actions](../.github/workflows/ci.yml). Needs RISC-V toolchain, `qemu-system-riscv64`, and Python 3. See [CI.md](CI.md), [../AGENTS.md](../AGENTS.md).
- `make compliance-exec` — runs `run_holyc_compliance.sh --suite all --exec`: all manifest compile checks again, then embedded **`make exec-oracle`** path. Does **not** run **`make templeos-smoke`** (use **`make ci`** for full CI parity).

---

## ✅ FULLY IMPLEMENTED

### Core Compiler Infrastructure
- **Lexer** (`host/lexer.c`): Complete tokenization
  - Identifiers, keywords, numbers
  - All operators (arithmetic, bitwise, logical, comparison)
  - String literals
  - Character literals
  - Comments (`#` line comments)
  - Multi-character operators (`==`, `!=`, `&&`, `||`, `++`, `--`, etc.)

- **Parser** (`host/parser.c`): Complete AST/IC generation
  - Expression parsing with proper precedence
  - Function definitions and declarations
  - Variable declarations
  - Statement parsing
  - Block parsing with symbol table scoping

- **Code Generator** (`host/compiler.c`): RISC-V assembly emission
  - All basic instructions (addi, ld, sd, jal, jalr, etc.)
  - Stack frame management
  - Register allocation (a0-a7, s0-s11, t0-t6)
  - Function prologues and epilogues
  - Label resolution in multi-pass compilation

- **Hash Table** (`host/hash_table.c`): Symbol management
  - Function storage and lookup
  - Type storage
  - Persistent across REPL inputs

### Data Types
- **Integer Types**: `I8`, `I16`, `I32`, `I64`
- **Unsigned Types**: `U8`, `U16`, `U32`, `U64`
- **Floating Point**: `F64` (declared, not fully tested)
- **Boolean**: `Bool` (implemented as I64)
- **Void**: `U0` (no return type)

### Operators
**Arithmetic** ✅
- `+`, `-`, `*`, `/`, `%` (modulo)
- `-` (unary minus) ✅ FULLY IMPLEMENTED
- `++`, `--` (pre/post increment/decrement) ✅ FULLY IMPLEMENTED

**Bitwise** ✅ ALL IMPLEMENTED
- `&`, `|`, `^`, `~`, `<<`, `>>` ✅ ALL FULLY IMPLEMENTED
- `~` (bitwise complement) ✅ FULLY IMPLEMENTED
- `&`, `|`, `^` (bitwise operations) ✅ FULLY IMPLEMENTED
- `&=`, `|=`, `^=` ✅ FULLY IMPLEMENTED

**Logical** ✅
- `&&`, `||`, `!` ✅ FULLY IMPLEMENTED with short-circuit evaluation
- `!` (logical NOT) ✅ FULLY IMPLEMENTED

**Comparison** ✅
- `==`, `!=`, `<`, `>`, `<=`, `>=`

**Assignment** ✅ ALL IMPLEMENTED
- `=` ✅
- `+=`, `-=`, `*=`, `/=` ✅ FULLY IMPLEMENTED
- `&=`, `|=`, `^=` ✅ FULLY IMPLEMENTED

### Control Flow
**Conditionals** ✅
- `if`, `else`
- Nested if/else

**Loops** ✅ ALL IMPLEMENTED
- `while` loops with break/continue
- `for` loops with:
  - Init expressions
  - Condition expressions
  - Increment expressions ✅ FIXED
  - Body statements
- `do-while` loops with break/continue ✅ IMPLEMENTED
- `break` (jump to end of loop)
- `continue` (jump to loop increment/start)

**Unconditional Jumps** ✅
- `return` (with or without value)
- `goto` (labels)
- Switch/case with proper jump handling ✅

**Exception Handling** (parsed, not tested)
- `try/catch`
- `throw`

### Functions
**Function Definitions** ✅
- Return types
- Function names
- Parameters (up to 10+ parameters tested)
- Bodies with multiple statements
- Local variables
- **Forward declarations** ✅ NEWLY ADDED
  - Syntax: `I64 Fibonacci(I64 n);`
  - Adds function signature to hash table without body
  - Can be followed by full definition later

**Function Calls** ✅
- Direct calls: `func()`
- Parameter passing (0-7 in registers, 8+ on stack)
- Return values
- Nested function calls
- Function calls in expressions

**Parameter Passing** ✅
- Parameters 0-7: Registers a0-a7
- Parameters 8+: Stack above caller's frame
- Return value: Register a0
- Proper stack frame management

**RISC-V Calling Convention** ✅
- Callee-saved: ra, s0, s1-s11
- Caller-saved: a0-a7, t0-t6
- Stack alignment (16-byte minimum)
- Frame pointer (s0)

### Variables
**Local Variables** ✅
- Declarations with initialization
- Multiple locals per function
- Locals in nested scopes
- Stack-based storage with proper offsets

**Global Variables** (parsed, not fully tested)
- Global declarations
- Global access

**Parameters** ✅
- Parameter declarations
- Parameter access in body
- Correct stack offsets

### Expressions
**Basic Expressions** ✅
- Integer literals
- Variable references
- Function calls
- Operator precedence
- `sizeof` works for primitive types, struct/enum types, and local/global identifiers

**Complex Expressions** ✅
- Nested expressions
- Multi-operator expressions
- Parenthesized expressions

### Memory Operations
**Pointers** ✅
- Pointer declarations
- Pointer dereferencing (`*`)
- Address-of (`&`)

**Arrays** (parsed, not fully tested)
- Array declarations
- Array subscripting `[]`
- Multi-dimensional arrays (syntax parsed)

### REPL Features
**Interactive Environment** ✅
- The product REPL is **HolyC**, not C: `bootstrap/hc_repl/` + `bootstrap/seed/*.hc`
  (`make hc-repl` → `build/repl-holyc.elf`; gates `make repl-holyc-smoke` /
  `repl-holyc-regression`). See [REPL.md](REPL.md).
- The legacy C guest (`worry_dream_repl.c`) and its `bootstrap/repl.elf` link path were
  **deleted**; `make repl-smoke` / `repl-regression` now error out and point at the HolyC
  targets. The other early C prototypes (`simple_repl.c`, `templeos_debugger.c`,
  `stepping_debugger.c`) survive only under `bootstrap/archive/` and are not built.
- Persistent hash table across inputs
- Multiple function definitions
- Multiple function calls

### Debugging
**Disassembler** — HolyC `bootstrap/seed/disasm.hc`: `U()` disassembles, `D()` dumps memory,
`Dr()` dumps registers, with instruction formatting and hex addresses. **Caveat:** `disasm.hc`
is a seed, not AOT-included in the thin product image, so `U` / `Uf` are a known wiring gap
there ([DEBUGGER.md](DEBUGGER.md)).

**Stepping Debugger** — HolyC REPL surface; see [DEBUGGER.md](DEBUGGER.md) for what is
actually wired today. The `stepping_debugger.c` prototype that once backed this section is
archived and not built.

### RISC-V Backend
**Instruction Set** ✅
- Base integer instructions (RV64I)
- M extension (multiplication/division)
- Proper instruction encoding
- Sign extension for immediates
- Jump/call instruction generation

**Memory Model** ✅
- 64-bit addresses
- Little-endian byte order
- Stack grows downward
- Proper alignment (8-byte for 64-bit values)

**Code Generation** ✅
- AOT (Ahead-Of-Time) compilation
- Executable machine code output
- Proper prologue/epilogue
- Call site code generation
- Return handling

---

## ⚠️ PARTIALLY IMPLEMENTED / NOT TESTED

### Classes & Objects
- Status: Class definitions parsed, member access not tested
- Missing: Member function calls, inheritance, virtual functions

### Arrays
- Status: Syntax parsed, operations not fully tested
- Missing: Bounds checking, initialization, multi-dimensional access

### String Operations
- Status: String literals parsed
- Missing: String manipulation functions, concatenation

### Floating Point
- Status: F64 type declared
- Missing: Floating point arithmetic, comparisons

### Exception Handling
- Status: Try/catch/throw syntax parsed
- Missing: Exception propagation, handler execution

### Switch Statements (FIXED)
- Status: Fully implemented with cascading comparisons
- Supports multiple case labels
- Supports default case
- Proper break handling
- Jump table optimization possible

### Function Pointers
- Status: Parser supports `I64 (*fn)(I64, I64)` declarators, local/static/global storage, and indirect calls
- Missing: Variadic signature metadata, pointer-to-member semantics, richer type checking

### Global Variables
- Status: Parsed but not tested
- Missing: Proper global initialization, access across compilation units

### Preprocessor
- Status: Basic `#define` (simple and parameterized) expansion, `#if 0/1`, `#ifdef`/`#ifndef`, `#else`, `#endif`, `#include` with relative path resolution
- Recent: `#undef` removes macros and frees parameter lists; redeclarations replace the previous definition; `#include` loads files relative to the including source or CWD
- Missing: Nested conditional stacks beyond simple skipping, token pasting edge cases, angle-bracket system include search paths

### Structs/Unions/Enums
- Status: Structs/unions parsed with member access; enums generate integer constants
- Enum type names are registered as I64 aliases and can be used directly in variable declarations
- Anonymous and inline `enum { ... }` definitions allowed in local and global contexts
- Missing: Alignment/packing controls, using enum types as distinct type names

---

## ❌ NOT IMPLEMENTED

This section is about the **language surface**. OS subsystems (graphics, audio, file I/O,
input, scheduling) are **not** compiler gaps — they ship as HolyC drivers in `Kernel/` and
`Adam/`; see the "OS subsystems" table below and [DRIVERS.md](DRIVERS.md) /
[PLATFORM.md](../templeos-riscv/PLATFORM.md) for their real status.

### Advanced Object-Oriented Features
- Virtual functions
- Method overloading
- Operator overloading
- Templates/generics

(Not HolyC features either — TempleOS has none of these. Listed only so nobody expects them.)

### Memory Management
- `new` / `delete` operators
- Garbage collection
- Smart pointers

(`MAlloc`/`CAlloc`/`Free` are the HolyC model and are implemented.)

---

## OS subsystems (not compiler gaps)

| Subsystem | Shipped today | Still missing |
|---|---|---|
| **Graphics** | 32-bpp linear FB (`Kernel/RVFb.HC`) over QEMU **ramfb** + board **simplefb** bind; thin `Gr*`/CDC (`Kernel/RVGr.HC`), sprites (`Kernel/RVSprite.HC`), text_base WinMgr (`Kernel/RVWinMgr.HC`). Gates: `kernel-fb-smoke`, `kernel-gr-smoke`, `kernel-cdc-smoke`, `kernel-win-smoke`, `kernel-win-interactive` | 3D; 8-bit VGA `GrBitMap`; full Adam DolDoc / mouse grab; virtio-gpu and SoC DRM/KMS (out of scope — [BOARD_FB.md](../templeos-riscv/BOARD_FB.md)) |
| **Audio** | virtio-snd driver (`Kernel/Drv/VirtioSnd.HC`) + Adam sound surface (`Adam/ASnd_RV.HC`); gate `kernel-virtio-snd-smoke` | Music/`PlaySong` scores, mixer, real board codecs |
| **File I/O** | virtio-blk (`Kernel/BlkDev/DskVirtioRV.HC`) + virtio-blk-PCI fallback; **RedSea** (`Kernel/BlkDev/RVRedSeaRaw.HC`, `kernel-redsea-smoke`); **9P2000.L** client (`Kernel/Drv/Virtio9p.HC`, `Kernel/BlkDev/FileSys9P_RV.HC`, `kernel-virtio-9p-smoke`); `DskFile`/`DskDir` port; REPL memfs + `DumpFile`/`FsChanges` export | FAT write-back, full VFS mount glue, guest-as-9p-server |
| **Keyboard / mouse** | virtio-input poll + ABS map + PLIC ACK (`Kernel/Drv/VirtioInput.HC`, `kernel-virtio-input-smoke`); UART RX via PLIC IRQ; `KeyDevAdd` keydev walk | Live key-inject CI gate, wider `KEY_*` glyph coverage, PS/2 |
| **Concurrency** | Cooperative `RVSpawn`/`RVYield` + **preemptive** timer-driven switch, `RVSleep`, critical sections (`RVCritEnter`/`Leave`), HolyC `lock`, CTask integration; A-ext `LR/SC` + AMO from `asm{}`. Gates: `kernel-sched-smoke`, `kernel-preempt-smoke`, `kernel-crit-smoke`, `kernel-ctask-*-smoke` | SMP beyond the mailbox bring-up (`kernel-smp-smoke` is optional, not default CI) |
| **Networking** | virtio-net TX/RX, mmio + PCI (`Kernel/Drv/VirtioNet.HC`, `kernel-virtio-net-smoke`); SiFive GEM on `sifive_u` | **TCP/IP stack and sockets** — genuinely absent; live SLIRP RX gate |
| **System calls** | TempleOS model: no user/kernel split, so there is nothing to syscall *into*. Traps/CLINT/PLIC, `Fault`/`CrashMon`, task spawn/exit are the equivalents | S-mode/U-mode separation, SBI, IPC, signals — deliberately not on the roadmap |

---

## Test Coverage

### ✅ Working Tests
- Basic arithmetic: `42`, `10+20*2`
- Modulo: `17 % 5`
- Functions with 0-10 parameters
- Control flow: `if/else`, `while`, `for`
- Local variables
- Function calls
- Return values
- Nested calls
- Complex expressions
- Factorial function
- GCD algorithm (iterative)
- While loop summation

### ❌ Failing / fragile (execution or REPL)
- **Complex array operations:** Parsed and partially covered by compliance; edge cases remain.

---

## Known Issues

Ordered gap-fill work lives in [GAPS.md](GAPS.md); language-surface holes are listed in the
sections above. Items historically tracked here are resolved:

| Was | Now |
|---|---|
| **Recursion Bug** — self-calls hang because `exe_addr` isn't set before compiling the body | **Fixed.** Recursion executes under the AOT exec harness (`Demo/RadixSort.HC`, the kernel's QSort with a fn-pointer comparator, `tests/exec/cases/e_kernel_*.hc`) |
| **9th Parameter** — offset bug for the 9th parameter | **Fixed.** >8 args pass on the stack above the caller's frame and round-trip correctly |
| **For Loop Increment** — increment placed before the body | **Fixed** |
| **Missing Braces** — function-call parsing dropped braces | **Fixed** |
| **Terminal Corruption** during stress runs | Belonged to the deleted C guest. The HolyC REPL's UART path has software XON/XOFF + an IRQ-drained soft queue ([UART.md](UART.md)); flow-control behaviour is gated by `repl-holyc-regression` and the PTY smokes |

---

## Recent Additions

The bottom of this file used to carry a hand-maintained "Latest Commits" log of early
operator/codegen work (bitwise, compound assignment, unary, `&&`/`||` short circuit,
shifts, `++`/`--`). It had drifted years out of date and was truncated mid-sentence, so it
is gone: all of it is long since implemented and covered by the execution-verified table at
the top of this file, and `git log host/` is the accurate history.

For what changed recently, use `git log` plus the oracle suites
([tests/compiler/README.md](../tests/compiler/README.md), [tests/README.md](../tests/README.md)).
