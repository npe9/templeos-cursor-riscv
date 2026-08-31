# TempleOS x86 vs RISC-V kernel — apples-to-apples plan

This document maps **original x86 TempleOS** (in-repo `tos/Doc/*.DD`, `Kernel/*.HC`, Terry’s design) to what **`templeos-riscv/`** should implement for **the same roles**. Hardware differs; **subsystem jobs** should align.

## Status (this repo)

| Phase | State |
|-------|--------|
| **A** | **Done:** S-mode `stvec` + dedicated trap stack (`sscratch` swap), `rv_s_trap_fatal()` prints `scause` / `sepc` / `stval` on UART. See `kernel/boot.S`, `kernel/trap_entry.S`, `kernel/kernel.c`. |
| **B (start)** | **Done:** Linker region **`.compiler_blob` @ `0x80200000`**, 8-byte placeholder (`COMP` magic + `ret`). Kernel probes magic and calls stub at `+4`. **Next:** AOT `Compiler/Compiler_RV.PRJ` (RV Back*/OptPass789A) into that slot — see [`COMPILER_RV.md`](COMPILER_RV.md). |
| **C (start)** | **Done:** Same TosApi layout as above. **Guest:** `guest/kmain.hc` probes magic at **`0x80300000`** via **`(U32 *)`** and returns **42** on match; host **`holyc-riscv`** emits full AOT (buffer sizing, casts, unary `*` / **`IC_EVAL_DROP`**). See `guest/tosapi_probe.hc` for the same pattern. |
| **D (start)** | **Done:** **`tos_api_yield()`** bumps **`g_yield_count`** (no task switch). Kernel prints count after guest returns. |
| **E (start)** | **Started:** **virtio-mmio** (modern v2) + **PCI virtio-blk**; **RedSea** **`redsea_read_contiguous`**, root scan (all non-dir files). QEMU MMIO: **`-global virtio-mmio.force-legacy=off`**. Smoke: **`make redsea-smoke-img`**. |
| **F (start)** | **Started:** `Kernel/RVFb.HC` + `Kernel/RVGr.HC` + `Kernel/RVWinMgr.HC` — 32-bpp FB, thin Gr*/CDC, soft term, TempleOS-style text_base WinMgr. Board: `BOARD_FB.md`. Graphics boot still needs phase-3 **Compiler load + StartOS/Adam** on that FB ([`COMPILER_RV.md`](COMPILER_RV.md)). |

**QEMU `virt` with `-bios none -kernel`:** Bring-up assumes **supervisor mode** at ELF entry (matches `stvec` / `scause`). If a platform enters **M-mode** only, add `mtvec` + delegation or an M-mode trampoline.

---

## 1. Reference model: x86 TempleOS

| Area | x86 TempleOS |
|------|----------------|
| **Boot** | BIOS loads a tiny boot sector → loads **`/Kernel/Kernel.BIN.C`** (fits ~640K) → **16→32→64** → kernel pulls up the rest (`Doc/Boot.DD`). |
| **Early bring-up** | Kernel loads **`/Compiler/Compiler.BIN`**, runs **`/StartOS.HC`** (often `.Z`), compiles/loads Adam/Home into the **Adam task** (`tos/Doc/Boot.DD` on disk; `::/Doc/Boot.DD` at runtime). |
| **Privilege / memory** | **Ring 0 only**; **identity map** (VA = PA); paging present but effectively flat (`Doc/Strategy.DD`). |
| **Code model** | **No object files / linker** in normal workflow; **JIT** + whole-file compile; AOT for kernel/boot (`Doc/Strategy.DD`). |
| **CPU / IRQ** | x86_64; **IDT**; IRQs; disk often **polled ATA** (no IRQ) for compatibility (`Doc/Strategy.DD`). |
| **Tasks** | **`CTask`**, **cooperative** scheduler (`Yield`); register save/restore in **asm** (`Kernel/Sched.HC`). |
| **Memory** | Per-task **heap** + **symbol table**; helpers under `Kernel/Mem/*` (`Kernel/KGlbls.HC`). |
| **Storage** | **RedSea** (+ FAT/ISO); contiguous files; `Kernel/BlkDev/*`. |
| **Input** | **PS/2** keyboard/mouse preferred (`Doc/Strategy.DD`; `Kernel/SerialDev/*.HC`). |
| **Display** | **640×480 16-color** model; VGA/text fallback (`Doc/Strategy.DD`; `Kernel/Display.HC`). |
| **Multicore** | **Master/slave**, not symmetric SMP (`Doc/Strategy.DD`; `Kernel/MultiProc.HC`). |
| **Exceptions** | **`try`/`catch`** tied to kernel path (`Kernel/KExcept.HC`). |

**Current RISC-V tree:** C bootstrap under `templeos-riscv/` (traps, UART, guest/compiler slots) plus HolyC `Kernel/` (tasks, virtio/RedSea, FB/WinMgr) and guest `Compiler_RV` / phase3 Cmp path. Still not full x86 Adam/DolDoc/mouse — see status table above and [COMPILER_RV.md](COMPILER_RV.md). Architecture: [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).

---

## 2. Subsystem mapping (same job, different mechanism)

| x86 TempleOS | RISC-V counterpart | Parity meaning |
|--------------|-------------------|----------------|
| BIOS + boot sector + staged load | **OpenSBI / U-Boot / `-kernel` ELF** or M-mode loader from **virtio-blk** / **initrd** | Staged image load; 64-bit entry. QEMU `-bios none -kernel` skips BIOS; parity is **contract**, not real-mode. |
| **`Kernel.BIN.C` minimal core** | Minimal RV kernel: traps, RAM map, UART, optional timer | Smallest runnable core before compiler. |
| **Load `Compiler.BIN`** | Load **RV compiler blob** into **executable** memory; jump to entry | Kernel can compile source in-RAM. |
| **`StartOS.HC` / Adam** | HolyC (or fixed) init that fills **global symbol table** / spawns Adam analogue | Transition to “API symbols visible to all tasks.” |
| **Ring 0 + identity map** | **M-only or S-only**; identity or **1:1 Sv39** for used region | Task switch = **registers only** (no per-task page tables), matching `Sched.HC` assumptions. |
| **IDT / IRQ** | **mtvec/stvec**; **PLIC + CLINT** on `virt` | Timer, UART, virtio IRQ. |
| **Cooperative `CTask` + `Yield`** | Same **HolyC structures**; **RV64** context switch (**ra, sp, s0–s11**, fp if used) in asm | Same scheduling *model*. |
| **ATA polling** | **virtio-blk** polled (or IRQ + Yield) | Simple block path; avoid “IRQ disk matrix” early. |
| **RedSea / FAT** | Same **formats**, read via virtio-blk | Whole-file load, optional `.Z` compression policy. |
| **PS/2** | **UART** first; later **virtio-input** | Parity at **Kbd/Mouse API**, not wire-level PS/2. |
| **VGA 640×480** | **32-bpp linear FB** (`Kernel/RVFb.HC`) + thin **Gr*/CDC** (`Kernel/RVGr.HC`) + **text_base WinMgr** (`Kernel/RVWinMgr.HC`); QEMU **ramfb**, **simplefb** bind stub for boards (`BOARD_FB.md`) | One compositor model; no VGA ports. Full Adam DolDoc / mouse still pending. |
| **Master/slave cores** | **SBI HSM** or **IPI + WFI**; per-hart Seth queues | Explicit job handoff, not Linux SMP. |
| **`try`/`catch` / faults** | **Trap handler** + unwind / handler tables | RV encodes exceptions differently; semantics can still match HolyC. |

---

## 3. Phased implementation (mirror TempleOS bring-up)

| Phase | Goal | Matches TempleOS stage |
|-------|------|-------------------------|
| **A** | RV entry, stack, BSS, **trap vector**, UART **panic/diag**; document **identity map** in `link/*.ld` | 64-bit kernel alive; interrupts possible. |
| **B** | **Image layout** for **compiler blob**; loader copies to R/X; call into compiler entry | Kernel loads `Compiler.BIN` analogue (`Doc/Boot.DD`). |
| **C** | Minimal **StartOS/Adam**: register kernel API symbols for child tasks | Adam task symbol visibility (`Doc/Strategy.DD`). |
| **D** | **`CTask`**, **`Yield`**, round-robin; RV **asm** context switch | `Kernel/Sched.HC` model. |
| **E** | **virtio-blk** + **RedSea** read path | `Kernel/BlkDev/*` + `FileSysRedSea.HC` role. |
| **F** | **Display** + **input** backends behind TempleOS-style APIs | `Display.HC`, `KeyDev` / `Mouse.HC` roles. |
| **G** | **Second hart**: Seth loop, jobs, locks | `MultiProc.HC`. |
| **H** | **Traps ↔ HolyC `try`/`catch`** | `KExcept.HC`. |

**Next apples-to-apples milestone:** **Phase E** — one **virtio-blk** read path (polled), then **RedSea**-shaped superblock / directory parse (read-only), matching the **`Kernel/BlkDev/*`** + **`FileSysRedSea.HC`** role at minimal depth.

---

## 4. Non-goals (still “TempleOS-shaped”)

- **PC BIOS boot sectors** on RISC-V: replace with **SBI + ELF** (or small loader).
- **Port I/O ATA / PS/2**: keep **API**; use **virtio** (or UART) underneath.
- **In-kernel JIT**: same *role* as x86; implementation is **RV codegen**; host `holyc-riscv` is bootstrap until HolyC self-host on guest.

---

## 5. Repo pointers

- x86 docs: `tos/Doc/Boot.DD`, `tos/Doc/Strategy.DD`
- x86 kernel modules: `Kernel/*.HC`, especially `Sched.HC`, `KGlbls.HC`, `KExcept.HC`, `Mem/*`, `BlkDev/*`, `SerialDev/*`, `Display.HC`, `MultiProc.HC`
- RISC-V bring-up: `templeos-riscv/kernel/`, `templeos-riscv/link/`
- Host compiler (not part of OS tree): repo root `holyc-riscv`
