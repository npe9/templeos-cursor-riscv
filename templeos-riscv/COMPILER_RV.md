# RISC-V TempleOS compiler & graphics-boot plan

Repo map: [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). REPL users: [../docs/REPL.md](../docs/REPL.md). Platform Kconfig: [KCONFIG.md](KCONFIG.md). Doc index: [../docs/README.md](../docs/README.md).

**Intent:** RISC-V is the CPU target (boards via Kconfig); the **system shape** stays TempleOS — CmpCtrl/Lex/Prs → IC → Opt → emit, load Compiler, StartOS/Adam, WinMgr on FB. Interactive compile on the guest = **`ExePutS` / `COCCompile` / guest `Cmp`**, not `jit.hc`. Do **not** grow `bootstrap/hc_repl/jit.hc` as a parallel language. There should be **no runtime other than the HolyC built by the compiler** — host slots / `RuntimeRegister` / C UART-drain funptrs are transitional bootstrap only ([MULTIARCH.md](../docs/MULTIARCH.md) §2). CI smokes load ELF images on an emulator harness — that is not the product ([PLATFORM.md](PLATFORM.md)).

## Architectural mandate (read this first)

| | Today (honest) | Desired end state |
|--|----------------|-------------------|
| **Who builds the boot/runtime image?** | Mostly **host `holyc-riscv` (C)** AOT of `kernel_*_demo.hc` + link of host-packed `Compiler.BIN` | **HolyC `Compiler_RV` / guest `Cmp` / `ExePutS`** builds Kernel seeds, Adam, and the runtime that **actually boots** |
| **Host C role** | Baseline producer of phase3/kernel ELF + Compiler blob | **Bootstrap seed only** (or eliminated) — after a known-good tree is stable enough to commit |
| **Callable OS APIs** | Some still via `RuntimeRegister` / C slots in `worry_dream_repl.c` | HolyC seeds / guest Cmp output only — **zero** `RuntimeRegister` into `HTT_FUN` for TempleOS APIs |
| **Success definition** | ~~Forever host-AOT the demo `.hc`~~ | Boot path **Loads/runs HolyC-built** modules; host AOT is transitional |

**Policy:** after a known-good tree is committed (do **not** commit unless the user asks), the boot path must prefer HolyC-built runtime. This doc’s **P3** is that baseline flip — not “more host AOT demos.” Kill order for remaining C REPL hooks: [MULTIARCH.md](../docs/MULTIARCH.md) §2 (UART→HolyC MMIO, ErrGo, ExePutS over host slot, retire `holy_rt` register path). **Non-goal:** deleting the `host/` C AOT compiler — that is bootstrap, not the guest runtime.

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
| In-image ExePutS | `kernel_exepubs_demo.hc` / `kernel_exepubs_fundef.hc` | Expr + fun-def → 42 (same stmt or split ExePutS) |
| Guest Cmp MakeOS | `RVPhase3MakeOS` | **Cmp→Tiny.BIN export→Load→Call → 42** (no hand TOSB) |
| Guest Runtime seed | `RVPhase3GuestRuntime` | **Cmp→Seed/Svc/Kern/Kernel/StartOS/AdamCore.BIN**; StartOS **Loads** them; arg + `F()+imm` proven |
| Phase3 ELF itself | host AOT of thin demo; RedSea virtio img ships `Compiler.BIN` + probe `Kernel.BIN` | **Still host-built** scaffold; ELF `.compiler_bin` @`0x81000000` optional (`PHASE3_LINK_COMPILER_BIN=1`); live Cmp is **heap Load** of RedSea Compiler seed (G9 reloc); Kernel seed FileFind+Load before Cmp |
| Temp bridge | `bootstrap/hc_repl` + `jit.hc` | **Stop expanding** |

## Run gates

```bash
make holyc-riscv
make kernel-exepubs-smoke          # ExePutS expr → 42
make kernel-exepubs-fundef-smoke   # ExePutS fun-def → 42 (if present)
make kernel-phase3-smoke           # Load Compiler.BIN + MakeOS Cmp + Runtime Cmp + StartOS
```

Console (UART) phase3 expects (among others): `MakeOS OK`, `Runtime OK (…call+imm…)`, `Kern.BIN OK (arg+call+add→42)`, `RedSea Kernel.BIN seed FileFind+Load OK (KernelProbe=42)`, `StartOS Load AdamCore.BIN OK (guest Cmp FileWrite STR_CONST)`, `StartOS Load StartOS/Seed/Svc/Kern.BIN OK`, `StartOS Load Kernel.BIN OK (RedSea Kernel.BIN preferred over Mac phase3.elf scaffold)`, `StartOS subset OK (guest BINs AdamCore+…+Kernel)`, `done (compiler + StartOS)`. AdamCore: guest Cmp→Load→Call `FileWrite` multi-STR via `RVHCCall` plants READY/CORE — **hard required** (no linked MakeAdam fallback). Soft P6 (not required): `P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Menu_RV, LITE.TXT)` after staging Menu_RV on A:.

## Gap-fill plan (ordered)

| Phase | Goal | Success criteria | Status |
|-------|------|------------------|--------|
| **P0** | Fun-def `ExePutS` + OptPass789A stable | `ExePutS` fun → 42 (incl. split def/call); no OptPass size thrash | **Done** |
| **P1** | Guest `Cmp` BIN has real `HTT_FUN\|HTF_EXPORT` IE; MakeOS without hand TOSB | UART `MakeOS OK (Cmp→BIN→Load→Call MakeOSProbe=42)`; no `hand TOSB` | **Done** (`AOTGlblsResolve` + `CmpStoreU32` patch-table; `LoadU32` discipline) |
| **P2** | Guest-built **runtime modules** that boot/StartOS **require** (grow toward Kernel/Compiler on A:) | `Runtime OK` (#include+multi-fun); StartOS **Loads** Seed/Svc/Kern + StartOS.BIN; `SEED.OK`/`SVC.OK`/`KERN.OK`/`STARTOS.OK` | **Done** (intermediate) — multi-fun/`#include` Cmp; four guest BINs on A: |
| **P3** | **HolyC-compiled runtime is the boot baseline** | Tiny C/asm (or last host seed) only loads RedSea `Kernel.BIN` / runtime built by guest Cmp; phase3 success ≠ “host AOT’d the whole demo” | **In progress** — intermediate gate below; residual host AOT listed |
| **P4** | MakeAdam / DolDoc / WinMgrTask toward real StartOS | `DocTermNew` / `Spawn(WinMgrTask)` on FB | **Partial** — DocTerm Put/Display/Border + `WinMgrTask`/`RVWinMgrSpawn` on RVWinMgr; full DolDoc entries / ODE still open |

### P2 fix notes (multi-fun / `#include` Cmp)

Root cause: AOT `IC_CALL` used heap `buf` as PC when computing jal offsets (`OptPass_RV`), so the call site loaded a **module-relative** `exe_addr` as an absolute VA → hang on Call (and nested `#include` multi-fun looked like a Cmp hang). Fix: AOT call rip = `aotc->rip + local_rip` (same as x86 `OptPass789A`). Also emit real `IC_CALL_EXTERN`/`IMPORT` JAL placeholders + RV J-type patch in `AOTGlblsResolve`.

**Guest Cmp arg/call hardening (this pass):** root causes for hang/wrong Call on `F()+imm` / `F(a)`:

1. **`IC_ADD_CONST`/`IC_SUB_CONST`** used `arg2` (cleared to `MDF_NULL` by OptPass3) instead of `ic_data` — match x86 `ICAddSubEctImm`.
2. **`IC_CALL_START`/`IC_CALL_END`** were no-ops; now Push/Pop STK_TMP + mov return from `a0` like x86 OptPass789A.
3. **`ICMov` IMM→STK** — OptPass4 turns `IC_IMM` into `IC_MOV` with `res=STK` for arg pushes; dest-STK must `RVPush` (was a silent no-op).
4. **`IC_ENTER`** must load positive `reg_offsets` (arg slots) into assigned regs; without that, reg-allocated params read as 0.

Proven in phase3: Seed `RuntimeSeedVal+27`, Kern `KernBase+KernScale(9)` with `KernScale`=`n+n+n` → 42.

**AdamCore / CALL_IMPORT → host HolyC:** Guest eval-SP is junk (`SP>>28==0`); FP stays valid. Veneer `_RV_HC_CALL` saves guest `ra` at `FP-2040` (not `s11` — host HolyC clobbers s-regs), sets `SP=FP-2048`, `JR T1`. **Arg marshalling:** OptPass6 `ICF_PUSH_RES` `res.type=` fix; abs64 callee+veneer slots (`IC_BODY_SIZE=0x83`); `RVAArgReg()` for a-reg ids (avoid `RV_REG_A0+n` U8 mis-encode). CALL_IMPORT remats PUSH_RES as IMM/MOV+IMM/`la` STR; if IC emitted **RTL** (IMM/size before STRs, as in `FileWrite(path,buf,size)`), **reverse-assign** into `a0..`; else left-to-right. After `_RV_HC_CALL`, rebuild `SP=FP-(frame+ENTER locals+call push+args)` so `ADD_RSP`/`CALL_END`/`LEAVE` match a non-veneer call (Count→store then multi-STR FileWrite). **CALL_START** rebuilds `SP=FP-frame-ENTER_locals` **only when `cc->htc.fun` is set** (mid-function). Top-level ExePutS expression JIT has no ENTER — host `Call()`’s `s0` is not a HolyC FP; unconditional `SP=FP-16` corrupted the return stack and hung on `MakeOSProbe` after fun-def. **Proven:** guest→asm `RVRet42`; 0-arg HolyC; `RVHCAdd1(40)=41`; `DirMk` 1-STR; **`FileWrite` multi-STR**; **`make kernel-exepubs-fundef-smoke`** (split `ExePutS` def then call → 42).

**ICAdd / ICLea multi-use (fixed):** `n+n+n` on a reg-allocated arg: OptPass4 folds `n+n` to SIB `IC_LEA`; emitting `add rd,rs,rs` into the live arg GPR destroyed `n` for the third term (symptom: `KernScale(9)`→9, `KernBase+…`→24). Fix in `ICLea`: when SIB `base==index` and dest aliases that reg, accumulate in `a0`/`t2` and retarget left-assoc consumer `arg1`.

### P0 ExePutS fun-def / call (fixed)

Hang after `ExePutS("I64 MakeOSProbe(){return 42;}")` then `ExePutS("MakeOSProbe;")` (and same-stmt combined fundef): **not** Cmp/resolve — def completed (`ExePutS after fun def`); hang on **Call** of expression JIT. Root cause: `IC_CALL_START` always emitted `SP=FP-frame` (even with `htc.fun==NULL`). Fix above. Gates: `make kernel-exepubs-smoke`, `make kernel-exepubs-fundef-smoke`.

### P1 fix notes (export IE)

Host AOT of `Cmp` used `*ptr(U32 *)++`, which advances by **8** on RV (pointer width), not 4 — same class of bug as `LoadU32` in `KLoad.HC`. Patch-table type byte was correct (`et0=16` = `IET_REL32_EXPORT`) but the name was skipped/corrupt → Load found no export. Fix: `CmpStoreU32`/`CmpStoreI64` (MemCpy + +4/+8) in `Compiler/CMain.HC`; `AOTGlblsResolve` always emits `IET_REL32_EXPORT` with `tmpf` from the export hash.

### P0 fix notes (OptPass / fun-def)

- Forward labels at `INVALID_PTR`: fixed-size short jmp/branch placeholders until `IC_LABEL`.
- `ICU*` bounds vs `IC_BODY_SIZE`; ENTER/LEAVE frame sign; `OptLabelFwd` cycle guard.
- `PrsStmt` `goto sm_done`, RVLi/LUI, `ICCall` `ra` save/restore, label/jmp rip (earlier).
- `IC_CALL_START` FP→SP rebuild gated on `cc->htc.fun` so top-level ExePutS Call keeps host SP (see “P0 ExePutS fun-def / call” above).

### Host parser note

Unlabeled x86 `asm{}` soft-skips on **host** AOT (Kernel PCIBIOS/PageTables). Bare-metal REPL still hard-errors failed unlabeled inline asm (REPL `s2` / `a7` regression).

**REPL imm subtract (no `subi`):** RISC-V has no standard `subi`; use `addi` with a negative immediate:

```
asm { li a7, 20 addi a7,a7,-4 }; Regs
```

`sub` is R-type only (`sub rd,rs1,rs2`). Writing `sub a7,a7,4` or `subi …` is a **clear hard error** pointing at `addi` / `sub rd,rs1,rs2`. ABI names `a0`–`a7`, `s0`–`s11`, … are supported. System ops `sret`/`mret`/`ecall`/`ebreak`/CSR assemble (encode-only labeled forms are safe; executing `sret` in M-mode may trap).

| Path | Asm | Role |
|------|-----|------|
| Host `holyc-riscv` / `host/parser.c` `TryAssembleRiscV` | drives `repl.elf` today | unlabeled inline → `IC_RAW_RV`; semantics gate: `make asm-stress` ([tests/asm/](../tests/asm/README.md)) |
| Guest `Compiler/Asm_RV.HC` (`CMP_RV_ASM`) | `Compiler_RV.PRJ` / ExePutS | destination language compiler |
| `bootstrap/hc_repl/jit.hc` | — | **do not grow** as parallel language |

## Boot image without host AOT as baseline (P3 detail)

**Today (P3 intermediate gate):** phase3 **success path runs primarily from guest BINs**. After host-seeded Compiler is up, guest `Cmp` builds and StartOS **Loads**:

| Guest BIN | Role | Probe |
|-----------|------|-------|
| `A:/MakeOS/Tiny.BIN` | MakeOS closed loop | `MakeOSProbe=42` |
| `A:/Runtime/Seed.BIN` | multi-`#include` + `F()+imm` | `RuntimeSeedInit=42` |
| `A:/Runtime/Svc.BIN` | runtime service surface | `RuntimeSvcProbe=42` |
| `A:/Runtime/Kern.BIN` | arg call + `n+n+n` | `KernInit=42` (`KernBase+KernScale(9)`) |
| `A:/Kernel/Kernel.BIN` | Boot.DD-shaped **probe** on RedSea seed (`KernelProbe=42`, `KernelEntry=0x4B45`); host `pack_tosb` of `tests/exec/cases/kernel_bin_probe.hc` | **Not** full `Kernel_RV` — preferred over Mac phase3 ELF as the Kernel.BIN *path*; real Kernel.BIN boot still residual |
| `A:/Adam/StartOS.BIN` | StartOS body | `StartOSProbe=1` |
| `A:/Adam/AdamCore.BIN` | MakeAdam bring-up (guest Cmp) | **Required** — guest `FileWrite` multi-STR via `RVHCCall` plants `READY.TXT`+`CORE.TXT`; phase3 fails hard if Cmp/Load/Call/READY soft-fails |

Console proof: `RedSea Kernel.BIN seed FileFind+Load OK` … `Kern.BIN OK (arg+call+add→42)` … `StartOS Load Kern.BIN OK` … `StartOS Load Kernel.BIN OK (RedSea Kernel.BIN preferred…)` … `StartOS subset OK (guest BINs …+Kernel)`.

**Residual host AOT (inventory — each piece until removable):**

| Residual | Why still host | Removable when |
|----------|----------------|----------------|
| phase3 ELF scaffolding (`kernel_phase3_demo.hc` → `build/exec/phase3.elf`) | Boot glue: `RVKMain` / RedSea / `Load` / Cmp orchestration; **no** in-image `Compiler_RV_Body` (G9) | Shrink toward thin loader only (`kernel_thin_loader_demo.hc` → `thin_loader.elf` already proves mount+Load+`KernelEntry`); retire when `Kernel.BIN` owns traps/heap/UART/RedSea |
| `build/Compiler.BIN` via `pack_tosb` → RedSea virtio img | Host still packs seed; smoke stages `build/exec/phase3_redsea.img` (`tools/mk_redsea_seed_img.py`) with `A:/Compiler/Compiler.BIN`; live path is heap `Load` (PC-rel = relocatable) | Guest Cmp rebuilds Compiler TOSB (drop host `pack_tosb` seed) |
| `build/Kernel.BIN` via `pack_tosb` → RedSea virtio img | Host packs **probe** (`KernelProbe→42`, `KernelEntry→0x4B45`); early FileFind+Load+handoff before Cmp; Runtime prefers RedSea seed; `make kernel-thin-loader-smoke` proves loader→BIN Call | Guest Cmp (or host pack of real `Kernel_RV`) TOSB that owns traps/heap/RedSea; thin loader jumps and **does not return** to Mac scaffold |
| ELF `.compiler_bin` @ `0x81000000` | **Optional** last-resort (`PHASE3_LINK_COMPILER_BIN=1`); default smoke omits `compiler_full.o` | Keep only as recovery if RedSea seed missing |
| Host `holyc-riscv` AOT of RVPhase3 staging strings | Tiny Runtime/MakeOS/Menu_RV extract sources written to A: then guest-Cmp’d — staging still lives in host-built ELF text | Sources live on RedSea/9P (or guest-built Kernel plants them) |
| Win split-AOT `char_bmp_*` wire (`RVCmpWireCharBmps` / `RVCmpPatchCharBmps`) | Loaded Compiler.BIN zero-fills bitmaps; Lex needs kernel copies | **Do not regress** — stays until Compiler seed shares live kernel globals |

**G9 shrink this pass:** live Cmp is **heap `Load` of RedSea `A:/Compiler/Compiler.BIN`** from virtio seed img (relocatable PC-rel; plants `RELOC.TXT`). Default phase3 ELF has **empty/absent** `.compiler_bin` (no Mac pack bytes at `0x81000000`). **Also:** host-packed probe `A:/Kernel/Kernel.BIN` on the same RedSea img; `RVPhase3ProbeSeedKernel` FileFind+Load+Call **KernelProbe+KernelEntry** before Cmp; Runtime prefers that seed (guest Cmp Kernel rebuild = fallback only). **Thin loader milestone:** `kernel_thin_loader_demo.hc` → `build/exec/thin_loader.elf` (`make kernel-thin-loader-smoke`) mounts virtio, Loads RedSea `Kernel.BIN`, CallExports `KernelEntry` (0x4B45) — no Cmp/StartOS. Loader ELF still embeds full `Kernel_RV.PRJ` (not tiny yet); handoff into probe BIN is proven. `RVKMain` prefers `RVMountVirtioDisk` then RAM fallback. Earlier: dropped Body + HostBinEmbed + Menu U8[] embeds. Soft P6 stages Menu_RV_Guest via `RVAdamLiteMenuSrc`.

**Must stay host-built (document):** `holyc-riscv` + `pack_tosb` + `mk_redsea_seed_img.py` producing Compiler + Kernel **probe** seeds until guest Cmp rebuilds them; phase3 ELF Cmp/StartOS scaffolding until `Kernel.BIN` is bootable `Kernel_RV` (or thin loader stops returning after handoff into a real core); win split-AOT `char_bmp_*` wire — do not regress.

**Honest blocker to drop phase3.elf:** RedSea `Kernel.BIN` must become a bootable `Kernel_RV` (traps, heap, UART, RedSea/virtio, `Load`) that the thin loader can jump into **without** Mac AOT of Cmp/StartOS. Landed: probe staging + FileFind/Load + **thin loader ELF handoff to `KernelEntry`**. Still residual: probe ≠ kernel; thin loader ELF still hosts full `Kernel_RV` for mount/Load; phase3.elf still required for Cmp/StartOS product path.

**P6 soft (not DoD):** guest Cmp→Load→Call `AdamLite.BIN` (nested `#include Menu_RV` → `Menu_RV_Guest` → menu_n=8). Call must run **before** flat Menu Load (dup `RVMenu*` exports hung Call). Guest `FileWrite` inside that BIN still hangs under loaded Cmp — phase3 plants `LITE.TXT` after Call. Gaps: FileWrite-in-Lite / local U8* / rich `Menu_RV.HC` CMenu — [GAPS.md](../docs/GAPS.md) § MakeAdam_RV.

**Dropped this pass:** linked `MakeAdam_RV_Core.HC` from `kernel_phase3_demo.hc` — phase3 Adam markers are guest AdamCore only. (`MakeAdam_RV_Core` remains for `StartOS_RV.HC` / win demos that plant HOME.DD/WALLPAPER.)

**P3 target:** guest `Cmp` of Kernel/runtime (and eventually Compiler) to TOSB on RedSea; boot loader `Load`s those BINs. Host `holyc-riscv` limited to producing the first Compiler seed if needed. Do not redefine success as perpetual host AOT of larger demos.

## StartOS / MakeAdam (RV)

- `Adam/MakeAdam_RV_Core.HC` + `Adam/StartOS_RV.HC` — Adam home markers + HOME.DD/WALLPAPER for DocTerm path; **not** linked into phase3 demo (guest AdamCore plants READY/CORE there).
- `Kernel/RVWinMgr.HC` — DocTerm-lite (`DocTermNew`, `RVDocHomeOpen`, Doc-lite `$FG,`/`$TX,`).
- `Kernel/RVTextBase.HC` — `TextChar` / `TextPrint` on WinMgr text_base.
- Full `MakeAdam.HC` / DolDoc Put/Display/Border / `Spawn(WinMgrTask)` still open (P4 remainder).

## `hc_repl` / C-hook policy

- Bootstrap/demo of Mac-AOT HolyC with zero C guest runtime only.
- **Do not** add language surface to `jit.hc`.
- Destination: kernel + `Compiler_RV` + `ExePutS` / guest `Cmp`, same as x86 TempleOS.
- Align with the multi-arch C-hook kill list ([MULTIARCH.md](../docs/MULTIARCH.md) §2): no second C libc-shaped runtime on RV or any new ISA.

## Non-goals

- Greenfield OS that only reuses HolyC names.
- Forever-maintained second HolyC in `jit.hc`.
- **Forever host-AOT of the demo `.hc` as the definition of done.**
- Growing `RuntimeRegister` / host compile slots as the long-term REPL API surface.
- Deleting the `host/` C **compiler** (bootstrap AOT) — distinct from killing the C **guest runtime**.
- Shipping x86 `OptPass789A` / `BackA.HC` inside the RISC-V guest image.

## Host codegen quality (pointer)

Expression-stack emit + **safe** Tier-1 peephole live in **`host/compiler.c`**
(`RVU32`: same-reg push/pop cancel + push-abandon) plus **`ICF_ASSIGN_ZERO`**
for `*p=0` → `sd zero`. Do **not** re-enable push→`mv` across regs (broke
`Print`/`PjPutHex`). if/else BB tail merge not re-landed. Call policy
(`auipc+jalr` vs import `ld+jalr`; no distance-`jal`), insn counts, and open
gaps: **[host/README.md](../host/README.md)**. Guest `RVLi` in `BackLib_RV.HC`
shares the U32/`bit31` zero-extend rule with host `EmitLoadImm64`; guest does
not yet mirror host Tier-1 / assign-zero.
