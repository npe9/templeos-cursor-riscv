# RISC-V TempleOS compiler & graphics-boot plan

Repo map: [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). REPL users: [../docs/REPL.md](../docs/REPL.md). Platform Kconfig: [KCONFIG.md](KCONFIG.md). Doc index: [../docs/README.md](../docs/README.md).

**Intent:** RISC-V is the CPU target (boards via Kconfig); the **system shape** stays TempleOS — CmpCtrl/Lex/Prs → IC → Opt → emit, load Compiler, StartOS/Adam, WinMgr on FB. Interactive compile on the guest = **`ExePutS` / `COCCompile` / guest `Cmp`**, not `jit.hc`. Do **not** grow `bootstrap/hc_repl/jit.hc` as a parallel language. CI smokes load ELF images on an emulator harness — that is not the product ([PLATFORM.md](PLATFORM.md)).

## Architectural mandate (read this first)

| | Today (honest) | Desired end state |
|--|----------------|-------------------|
| **Who builds the boot/runtime image?** | Mostly **host `holyc-riscv` (C)** AOT of `kernel_*_demo.hc` + link of host-packed `Compiler.BIN` | **HolyC `Compiler_RV` / guest `Cmp` / `ExePutS`** builds Kernel seeds, Adam, and the runtime that **actually boots** |
| **Host C role** | Baseline producer of phase3/kernel ELF + Compiler blob | **Bootstrap seed only** (or eliminated) — after a known-good tree is stable enough to commit |
| **Success definition** | ~~Forever host-AOT the demo `.hc`~~ | Boot path **Loads/runs HolyC-built** modules; host AOT is transitional |

**Policy:** after a known-good tree is committed (do **not** commit unless the user asks), the boot path must prefer HolyC-built runtime. This doc’s **P3** is that baseline flip — not “more host AOT demos.”

## North star (graphics boot)

Mirror `tos/Doc/Boot.DD` (`::/Doc/Boot.DD` at runtime):

1. Kernel up (traps, UART, heap, RedSea/virtio as today).
2. **Load `Compiler` (RV)** — guest-built or bootstrap-loaded — same role as `/Compiler/Compiler.BIN`.
3. **`ExeFile("StartOS")` / Adam** — symbol table, servers, then graphics.
4. **WinMgr + FB** — full path uses Adam/DolDoc on that FB.

## What already exists

| Piece | Location | Gap |
|-------|----------|-----|
| Lex/Prs/IC/OptPass012–6 | `Compiler/*.HC` | Shared |
| RV emit | `Back*_RV.HC`, `OptPass_RV.HC` | Wired via `Compiler_RV.PRJ` / Body |
| Host AOT Compiler_RV | `holyc-riscv Compiler/Compiler_RV.PRJ` → ~1.1MB | **Bootstrap** (`build/compiler_rv.blob.bin` → `Compiler.BIN`) |
| In-image ExePutS | `kernel_exepubs_demo.hc` | Expr + fun-def → 42 |
| Guest Cmp MakeOS | `RVPhase3MakeOS` | **Cmp→Tiny.BIN export→Load→Call → 42** (no hand TOSB) |
| Guest Runtime seed | `RVPhase3GuestRuntime` | **Cmp→Seed/Svc/Kern/StartOS/AdamCore.BIN**; StartOS **Loads** them; arg + `F()+imm` proven |
| Phase3 ELF itself | host AOT of demo + link | **Still host-built** — residual documented under P3 intermediate |
| Temp bridge | `bootstrap/hc_repl` + `jit.hc` | **Stop expanding** |

## Run gates

```bash
make holyc-riscv
make kernel-exepubs-smoke          # ExePutS expr → 42
make kernel-exepubs-fundef-smoke   # ExePutS fun-def → 42 (if present)
make kernel-phase3-smoke           # Load Compiler.BIN + MakeOS Cmp + Runtime Cmp + StartOS
```

Console (UART) phase3 expects (among others): `MakeOS OK`, `Runtime OK (…call+imm…)`, `Kern.BIN OK (arg+call+add→42)`, `StartOS Load StartOS/Seed/Svc/Kern.BIN OK`, `StartOS subset OK`, `done (compiler + StartOS)`. (AdamCore Cmp soft-fails → linked MakeAdam fallback.)

## Gap-fill plan (ordered)

| Phase | Goal | Success criteria | Status |
|-------|------|------------------|--------|
| **P0** | Fun-def `ExePutS` + OptPass789A stable | `ExePutS` fun → 42; no OptPass size thrash | **Done** |
| **P1** | Guest `Cmp` BIN has real `HTT_FUN\|HTF_EXPORT` IE; MakeOS without hand TOSB | UART `MakeOS OK (Cmp→BIN→Load→Call MakeOSProbe=42)`; no `hand TOSB` | **Done** (`AOTGlblsResolve` + `CmpStoreU32` patch-table; `LoadU32` discipline) |
| **P2** | Guest-built **runtime modules** that boot/StartOS **require** (grow toward Kernel/Compiler on A:) | `Runtime OK` (#include+multi-fun); StartOS **Loads** Seed/Svc/Kern + StartOS.BIN; `SEED.OK`/`SVC.OK`/`KERN.OK`/`STARTOS.OK` | **Done** (intermediate) — multi-fun/`#include` Cmp; four guest BINs on A: |
| **P3** | **HolyC-compiled runtime is the boot baseline** | Tiny C/asm (or last host seed) only loads RedSea `Kernel.BIN` / runtime built by guest Cmp; phase3 success ≠ “host AOT’d the whole demo” | **In progress** — intermediate gate below; residual host AOT listed |
| **P4** | MakeAdam / DolDoc / WinMgrTask toward real StartOS | `DocTermNew` / `Spawn(WinMgrTask)` on FB | Pending |

### P2 fix notes (multi-fun / `#include` Cmp)

Root cause: AOT `IC_CALL` used heap `buf` as PC when computing jal offsets (`OptPass_RV`), so the call site loaded a **module-relative** `exe_addr` as an absolute VA → hang on Call (and nested `#include` multi-fun looked like a Cmp hang). Fix: AOT call rip = `aotc->rip + local_rip` (same as x86 `OptPass789A`). Also emit real `IC_CALL_EXTERN`/`IMPORT` JAL placeholders + RV J-type patch in `AOTGlblsResolve`.

**Guest Cmp arg/call hardening (this pass):** root causes for hang/wrong Call on `F()+imm` / `F(a)`:

1. **`IC_ADD_CONST`/`IC_SUB_CONST`** used `arg2` (cleared to `MDF_NULL` by OptPass3) instead of `ic_data` — match x86 `ICAddSubEctImm`.
2. **`IC_CALL_START`/`IC_CALL_END`** were no-ops; now Push/Pop STK_TMP + mov return from `a0` like x86 OptPass789A.
3. **`ICMov` IMM→STK** — OptPass4 turns `IC_IMM` into `IC_MOV` with `res=STK` for arg pushes; dest-STK must `RVPush` (was a silent no-op).
4. **`IC_ENTER`** must load positive `reg_offsets` (arg slots) into assigned regs; without that, reg-allocated params read as 0.

Proven in phase3: Seed `RuntimeSeedVal+27`, Kern `KernBase+KernScale(9)` with `KernScale`=`3*n` → 42.

**Still soft:** `n+n+n` on a reg-allocated arg can clobber the reg (ADD into the same GPR); prefer `3*n` / spill until ICAdd preserves multi-use sources.

### P1 fix notes (export IE)

Host AOT of `Cmp` used `*ptr(U32 *)++`, which advances by **8** on RV (pointer width), not 4 — same class of bug as `LoadU32` in `KLoad.HC`. Patch-table type byte was correct (`et0=16` = `IET_REL32_EXPORT`) but the name was skipped/corrupt → Load found no export. Fix: `CmpStoreU32`/`CmpStoreI64` (MemCpy + +4/+8) in `Compiler/CMain.HC`; `AOTGlblsResolve` always emits `IET_REL32_EXPORT` with `tmpf` from the export hash.

### P0 fix notes (OptPass / fun-def)

- Forward labels at `INVALID_PTR`: fixed-size short jmp/branch placeholders until `IC_LABEL`.
- `ICU*` bounds vs `IC_BODY_SIZE`; ENTER/LEAVE frame sign; `OptLabelFwd` cycle guard.
- `PrsStmt` `goto sm_done`, RVLi/LUI, `ICCall` `ra` save/restore, label/jmp rip (earlier).

### Host parser note

Unlabeled x86 `asm{}` soft-skips on **host** AOT (Kernel PCIBIOS/PageTables). Bare-metal REPL still hard-errors failed unlabeled inline asm (REPL `s2` / `a7` regression).

**REPL imm subtract (no `subi`):** RISC-V has no standard `subi`; use `addi` with a negative immediate:

```
asm { li a7, 20 addi a7,a7,-4 }; Regs
```

`sub` is R-type only (`sub rd,rs1,rs2`). Writing `sub a7,a7,4` or `subi …` is a **clear hard error** pointing at `addi` / `sub rd,rs1,rs2`. ABI names `a0`–`a7`, `s0`–`s11`, … are supported. System ops `sret`/`mret`/`ecall`/`ebreak`/CSR assemble (encode-only labeled forms are safe; executing `sret` in M-mode may trap).

| Path | Asm | Role |
|------|-----|------|
| Host `holyc-riscv` / `host/parser.c` `TryAssembleRiscV` | drives `repl.elf` today | unlabeled inline → `IC_RAW_RV` |
| Guest `Compiler/Asm_RV.HC` (`CMP_RV_ASM`) | `Compiler_RV.PRJ` / ExePutS | destination language compiler |
| `bootstrap/hc_repl/jit.hc` | — | **do not grow** as parallel language |

## Boot image without host AOT as baseline (P3 detail)

**Today (P3 intermediate gate):** phase3 **success path runs primarily from guest BINs**. After host-seeded Compiler is up, guest `Cmp` builds and StartOS **Loads**:

| Guest BIN | Role | Probe |
|-----------|------|-------|
| `A:/MakeOS/Tiny.BIN` | MakeOS closed loop | `MakeOSProbe=42` |
| `A:/Runtime/Seed.BIN` | multi-`#include` + `F()+imm` | `RuntimeSeedInit=42` |
| `A:/Runtime/Svc.BIN` | runtime service surface | `RuntimeSvcProbe=42` |
| `A:/Runtime/Kern.BIN` | arg call + `F()+G(n)` | `KernInit=42` (`KernBase+KernScale(9)`) |
| `A:/Adam/StartOS.BIN` | StartOS body | `StartOSProbe=1` |
| `A:/Adam/AdamCore.BIN` | MakeAdam bring-up (guest Cmp) | **Soft** — Cmp of `FileWrite`/`DirMk` imports still fails; StartOS falls back to linked `MakeAdam_RV_Core` |

Console proof: `Kern.BIN OK (arg+call+add→42)` … `StartOS Load Kern.BIN OK` … `StartOS subset OK (guest BINs StartOS+Seed+Svc+Kern)`.

**Residual host AOT (evidence — still required this pass):**

| Residual | Why still host |
|----------|----------------|
| phase3 ELF (`kernel_phase3_demo.hc` → `build/exec/phase3.elf`) | Boot scaffolding + `RVKMain` / RedSea / in-image `Compiler_RV_Body` |
| `build/Compiler.BIN` via `pack_tosb` + link at `0x81000000` | Full guest Compiler seed (97 IMM_I64 imports); not yet self-hosted Cmp of Compiler |
| Linked `MakeAdam_RV_Core.HC` | Adam markers until guest AdamCore Cmp of FileWrite/DirMk imports works |
| Host `holyc-riscv` AOT of RVPhase3 staging strings | Sources written to A: then guest-Cmp’d — staging still lives in host-built ELF |

**P3 target:** guest `Cmp` of Kernel/runtime (and eventually Compiler) to TOSB on RedSea; boot loader `Load`s those BINs. Host `holyc-riscv` limited to producing the first Compiler seed if needed. Do not redefine success as perpetual host AOT of larger demos.

## StartOS / MakeAdam (RV)

- `Adam/MakeAdam_RV_Core.HC` + `Adam/StartOS_RV.HC` — Adam home / Doc-lite markers.
- `Kernel/RVTextBase.HC` — `TextChar` / `TextPrint` on WinMgr text_base.
- Full `MakeAdam.HC` / `DocTermNew` / `Spawn(WinMgrTask)` still open (P4).

## `hc_repl` policy

- Bootstrap/demo of Mac-AOT HolyC with zero C guest runtime only.
- **Do not** add language surface to `jit.hc`.
- Destination: kernel + `Compiler_RV` + `ExePutS` / guest `Cmp`, same as x86 TempleOS.

## Non-goals

- Greenfield OS that only reuses HolyC names.
- Forever-maintained second HolyC in `jit.hc`.
- **Forever host-AOT of the demo `.hc` as the definition of done.**
- Shipping x86 `OptPass789A` / `BackA.HC` inside the RISC-V guest image.
