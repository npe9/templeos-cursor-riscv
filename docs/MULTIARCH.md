# Multi-architecture port plan

**Status: planning only** for every ISA except the current **RV64 / LP64**
baseline. No `ARCH_ARM*`, `ARCH_PPC*`, non-RV host emit, or multi-arch CI jobs
exist yet. Do not treat milestones as started until success criteria land in CI
or an explicit smoke Makefile target.

This is the living plan for ports **beyond** the RISC-V board matrix in
[PLATFORM.md](../templeos-riscv/PLATFORM.md). RV32 has its own detailed plan —
[RV32.md](../templeos-riscv/RV32.md) — and remains the **first** non-RV64 ISA.

| Related | Role |
|---------|------|
| [../templeos-riscv/PLATFORM.md](../templeos-riscv/PLATFORM.md) | RV boards + CI emulator targets (product language) |
| [../templeos-riscv/RV32.md](../templeos-riscv/RV32.md) | RV32 / ILP32 deep plan (first port after RV64) |
| [../templeos-riscv/KCONFIG.md](../templeos-riscv/KCONFIG.md) | Kconfig tutorial (today: RV machines) |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Host / REPL / Kernel / Cmp map |
| [LAYOUT.md](LAYOUT.md) | `host/` · `bootstrap/` · `tos/` · TempleOS trees |
| [README.md](README.md) | Doc index |
| [RISCV_PORT_PLAN.md](RISCV_PORT_PLAN.md) | Historical RV64 / self-host notes |

**Product story:** TempleOS / HolyC on **boards** via Kconfig + HolyC drivers
(`Kernel/Drv/`). Emulator `-M` names are CI harness profiles — not the OS
definition. Prefer `MEM_*` / `CONFIG_*` / board language in Help and Man.

**CI honesty:** Port targets are **not** equal CI. Default `make ci` /
`qemu-integration` stay **RV64 virt** (and existing RV board smokes). Other
ISAs get optional / `continue-on-error` jobs only after their P0 UART hello is
green locally. Exhaustive QEMU machine inventories are **tentative** — never
a promise of smoke coverage.

**As-of snapshot (refresh when the RV64 baseline moves):** host compiler is
`holyc-riscv` under `host/`; interactive REPL is `bootstrap/` + `seed/`; guest
path is `Compiler/Compiler_RV.PRJ` + `make kernel-phase3-smoke`; platform
drivers are HolyC under `Kernel/Drv/`; CI default board profile is **virt** via
`make kernel-plat-smoke`. Formatter: `make fmt` / `fmt-check` / `fmt-test`.

---

## 1. Goals / non-goals

### Goals (ordered)

Bring up HolyC AOT + a thin Kernel slice on a **small set** of well-supported
emulator maps (and later real boards), reusing shared ARCH / codegen / driver
patterns — not a Linux-style “every `-M` in CI” matrix.

### Non-goals (near term)

- Equal CI smoke for every QEMU machine on every ISA.
- Full TempleOS / Adam / DolDoc / graphics parity on non-RV64.
- Binary compatibility across ISAs (or across XLEN within RISC-V).
- Growing `bootstrap/hc_repl/jit.hc` for new arches (same freeze as RV64).
- Inventing a second C libc-shaped **guest runtime** per ISA (see §2).
- Dual-maintaining a second copy of `host/parser.c` / `host/compiler.c`.
- Renaming the host binary away from `holyc-riscv` as a port blocker (naming
  debt — see §8; default target remains RV64).
- Reimplementing TempleOS **x86** as a peer product track (see §8).
- Other ISAs not listed in §3 (MIPS, LoongArch, s390x, …) — **explicit
  non-goals** until this plan revises them in.

---

## 2. HolyC-only runtime / C-hook kill list

**Mandate (every ISA):** keep eliminating old C hooks. There should be **no
runtime other than the HolyC that is being built by the compiler** (guest
`Compiler_RV` / `ExePutS` / `Cmp` — or that ISA’s guest Cmp). Do **not** grow
`bootstrap/hc_repl/jit.hc`. Host slots, `RuntimeRegister`, and C UART-drain
funptrs are **transitional bootstrap only** — not a product runtime to port.

ISA ports must **not** invent a new C runtime. Destination is HolyC Cmp +
HolyC drivers under `Kernel/Drv/` (and arch siblings). ARM/PPC/… follow the
same rule as RV64.

### Goal

Callable OS APIs = HolyC seeds / guest Cmp output. **Zero** `RuntimeRegister`
into `HTT_FUN` for TempleOS APIs. Interactive compile on the guest =
`ExePutS` / guest `Cmp`, not a host-registered C funptr table.

### What remains C (honest — bootstrap only)

`bootstrap/worry_dream_repl.c` — which held readline, IRQ drain into a shared RX ring,
the host compile slot, fmt / editor repair hatches, and the `0x87001xxx` publish
pointers — is **deleted** (`080f729`). Its HolyC replacements live in `bootstrap/seed/`
and `bootstrap/hc_repl/`.

What is still C is **bootstrap, not destination**: the host `holyc-riscv` AOT compiler
under `host/`, the fmt/editor/sym bridges it backs (see
[REGRESSION.md](../tests/REGRESSION.md)), and `templeos-riscv/`'s loader glue.

Do **not** treat any of these as APIs to reimplement in C on a new arch.

### C REPL audit (concrete leftovers)

As-of the C-hook audit taken before `worry_dream_repl.c` was deleted (the slot addresses
still describe what the seed pokes today):

- [x] **`ErrGo`:** HolyC `ErrGo` in `seed/sym.hc` reads published err metadata
  slots (`HC_SLOT_ERR_*` @ `0x87001158..170`); **zero** `RuntimeRegister`.
- [x] **Unused host slots:** stopped publishing `MEMFS` / `CWD` /
  `TERM_PROBE` / `TERM_ROWS` / `TERM_COLS` / `TERM_FLAGS`.
- [x] **`HolyRtSeedOwned`:** deleted (unused).
- **Real leftover mass:** `HostSlotsInstall` + C helpers (compile slot, UART
  ring, fmt, hash, srcmap, editor repair hatches) — not a `RuntimeRegister`
  table.
- **Boot** is still per-seed `Run` (`repl_boot_blob` embed is unused for boot).
- **`holy_rt`** = AOT / oracle helpers — **not** REPL OS APIs.

### Kill order (prioritized)

| # | Kill | Notes |
|---|------|-------|
| 1 | UART drain / get → HolyC MMIO | In progress / `uart.hc` (and board `Kernel/Drv/*`) |
| 2 | `ErrGo` → slot metadata + HolyC | **done** — HolyC `ErrGo` + `HC_SLOT_ERR_*`; no `RuntimeRegister` |
| 3 | Unused host slots / `HolyRtSeedOwned` | **done** — dropped unused publishes; deleted `HolyRtSeedOwned` |
| 4 | `Run` / `HcCompile` prefer `ExePutS` | When `Compiler_RV` (or arch Cmp) is linked; boot still per-seed `Run` today |
| 5 | Move RX ring / hash / srcmap ownership into HolyC | Out of C bootstrap (`HostSlotsInstall` mass) |
| 6 | Delete host compile slot | When guest Cmp owns the REPL loop |
| 7 | Retire `holy_rt` as REPL OS surface | Keep as AOT/oracle only — not TempleOS APIs |

### Non-goal

Deleting the **`host/` C compiler** (AOT front-end). That is the **bootstrap
compiler**, not the guest runtime. Multi-arch still means one host binary +
backend trait — not a second guest libc. `holy_rt` stays in that AOT/oracle
role; do not grow it into REPL OS APIs.

### Per-arch rule

New ARM / PPC / … ports inherit this kill list. P0–P3 land HolyC drivers +
guest Cmp; they do **not** grow a parallel C runtime or expand `jit.hc`.
Details for the RV baseline: [ARCHITECTURE.md](ARCHITECTURE.md),
[REPL.md](REPL.md), [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md).

---

## 3. Port order

Finish and keep green the **RV64** baseline first. Then:

| Order | Target | First harness map (CI language) | Status |
|-------|--------|----------------------------------|--------|
| 0 | **RV64** (LP64) | `qemu-system-riscv64 -M virt` (+ sifive_u smokes) | **Active** — product + CI default |
| 1 | **RV32** (ILP32 + wide `I64`) | `qemu-system-riscv32 -M virt` | **Planning** — [RV32.md](../templeos-riscv/RV32.md) |
| 2 | **AArch64** | `qemu-system-aarch64 -M virt` | **Planning** |
| 3 | **ARM32** | `qemu-system-arm -M virt` (or documented board map) | **Planning** |
| 4 | **PPC64 LE** | `qemu-system-ppc64 -M pseries` *or* `-M ppce500` (pick one in P0) | **Planning** |
| 5 | **PPC32** | `qemu-system-ppc` + documented `-M` | **Planning** |
| — | Exhaustive QEMU `-M` inventory | All other machines per ISA | **Tentative only** — no CI promise |

Do **not** skip ahead to ARM/PPC emit while RV32 P0–P2 are still open, unless
an explicit request isolates shared scaffolding (Kconfig `choice ARCH`,
backend trait stubs) with **no** default-CI breakage.

---

## 4. Per-ISA phases (P0–P4)

Same phase shape for every new ISA. RV32’s concrete criteria live in
[RV32.md](../templeos-riscv/RV32.md); other ISAs copy the philosophy, not the
RISC-V MMIO addresses.

| Phase | Name | Intent |
|-------|------|--------|
| **P0** | UART hello | Tiny AOT HolyC prints a fixed string over the board UART on the **first** harness map for that ISA. |
| **P1** | Host Cmp subset | Host emit covers the trusted exec-oracle / REPL integer subset (calls, pointers, loops; soft wide types as needed). |
| **P2** | Thin kernel | Reduced Kernel boots, traps, and returns from a timer/UART path — enough RAM; not full Adam. |
| **P3** | Guest Cmp | Guest compiler produces native code for `ExePutS` / `Cmp` (mirror RV64 phase3 — [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md)). |
| **P4** | Optional Adam / Win | Text-base WinMgr / FB only if P2–P3 are boring; never a P0 goal. |

**Gates (all non-RV64):**

1. RV64 `make ci` (or compliance + fmt + plat + phase3 slice) green on the
   branch you branch from.
2. No half-wired `ARCH_*` in the default `virt` / `qemu-integration` path.
3. P0 harness map frozen in this doc (or the ISA-specific doc) before emit PRs.
4. Guest dual-emit (P3) waits until that ISA’s P2 smoke is green **and** RV64
   phase3 stays green.
5. Implementation starts only when **explicitly requested** — this file is the
   plan, not a license to open megadiffs.

---

## 5. Shared work (cross-ISA)

Land these once, then specialize per ISA — prefer **one host binary, multiple
backends**, not forked parser trees.

| Area | Direction |
|------|-----------|
| **ARCH Kconfig** | Top-level `choice ARCH` (`ARCH_RISCV64` default; later `ARCH_RISCV32`, `ARCH_AARCH64`, …). Board/platform symbols depend on ARCH. Emit into `Kernel/*AutoConf.HH` (name may stay `RVAutoConf` until a rename is worth the churn). |
| **Codegen backend trait** | Small target object / `holyc_target.h`: pointer width, endian, ABI name, insn emitters. Gate call sites in `host/compiler*.c` — do not fork `parser.c`. |
| **ABI tables** | Calling convention, stack align, soft `I64`/`F64` on 32-bit, struct layout rules — freeze per ISA in P0. |
| **HolyC drivers** | UART / IRQ / timer under `Kernel/Drv/` with ARCH/board selects — same pattern as today’s `RVUart*` / `RVTimer` / PLIC. Prefer HolyC stubs over new C drivers. **No** new C guest runtime (§2). |
| **Trap / context** | Parameterized trap frames and boot entry; do not half-port “UART only” with an RV64-shaped frame. |
| **Harness `qemu-args`** | Extend `make -C templeos-riscv qemu-args` (or arch sibling) so smokes print suggested argv; keep emulator strings out of Man topics. |
| **Arch-named BIN artifacts** | `*.rv64.bin` / `Compiler_RV.BIN` today; new arches get explicit names — never `Load` a foreign ISA blob. |

---

## 6. Forgotten pitfalls

Recurring traps when leaving RV64. Call these out in ISA-specific P0 notes
rather than rediscovering them mid-PR.

| Pitfall | Why it hurts |
|---------|----------------|
| **Endianness** | TempleOS/x86 and current RV are LE; PPC defaults and some ARM board firmware stories mix BE/LE — pick LE first where QEMU allows, document BE as separate. |
| **Firmware** | `-bios none` vs OpenSBI / U-Boot / EDK2 / SLOF (pseries). Harness must document the boot story; bare ELF load is not universal. |
| **Exception models** | RISC-V `mtvec`/`mret` ≠ AArch64 EL1/EL2 ≠ ARM32 modes ≠ PPC interrupts / SIGs. Trap frames are ISA-specific. |
| **Atomics** | RV A-ext AMOs vs ARM LSE / LDREX vs PPC `lwarx`/`stwcx.`. HolyC `lock` / `LXchg*` need per-ISA lowers. |
| **Soft `I64` / `F64` on 32-bit** | HolyC stays `I64`-centric; ILP32/AAPCS32 need pairs or libcalls (same lesson as RV32). |
| **`asm{}` dialect** | Host and guest assemblers today speak RISC-V. New ISAs need dialect gates or reject foreign mnemonics early. |
| **Linker / load address** | Today’s `0x80000000` virt map is RV-shaped; ARM/PPC virt maps differ — new `link_*.ld` per first harness. |
| **Toolchains** | Optional `objdump` / gcc wrappers for verify (`aarch64-linux-gnu-*`, `powerpc64le-*`, …) — document apt/brew names; do not require them for P0 if raw blob + QEMU suffices. |
| **CI cost** | Extra `qemu-system-*` packages and jobs blow runner time — optional jobs only; never block RV64. |
| **Naming `holyc-riscv`** | Historical; multi-arch does not require an immediate rename. Default target stays RV64; `--target` (or env) selects others. |
| **TempleOS x86 reimplements** | Upstream x86 TempleOS remains reference under `tos/` — not a peer ARCH track in this plan. |
| **C guest runtime / `RuntimeRegister`** | Bootstrap only on RV64; do not port or enlarge — §2 kill list. |
| **Other ISAs** | Anything not in §3 is an explicit non-goal until listed here. |

---

## 7. QEMU: primary targets vs inventory

Emulators are the **CI harness**. Primary rows are the intended first smoke map
per ISA. Inventory rows are typical `-M help` names — **tentative**, no equal
CI.

Refresh machine strings against the QEMU version you actually ship in CI when
implementation starts.

### RISC-V

| Role | Machine / note |
|------|----------------|
| **Primary (RV64)** | `virt` — CI default; 16550 / CLINT / PLIC map — [PLATFORM.md](../templeos-riscv/PLATFORM.md) |
| **Primary (RV32)** | `virt` under `qemu-system-riscv32` — [RV32.md](../templeos-riscv/RV32.md) |
| Board smokes | `sifive_u` (HolyC); others tentative |
| Inventory (tentative) | `sifive_e`, `spike`, `opentitan`, `shakti_c`, `microchip-icicle-kit`, `xiangshan-*`, `amd-microblaze-v-generic`, … — see PLATFORM table |

### ARM / AArch64

| Role | Machine / note |
|------|----------------|
| **Primary (AArch64)** | `qemu-system-aarch64 -M virt` (GICv2/v3 + pl011 UART — freeze details in P0) |
| **Primary (ARM32)** | `qemu-system-arm -M virt` when available; else a documented versatile / virt-like map |
| Inventory (tentative) | `virt`, `raspi*`, `vexpress-*`, `virt` variants, board-specific models — **not** equal CI |

### PowerPC

| Role | Machine / note |
|------|----------------|
| **Primary (PPC64 LE)** | Prefer one of: `pseries` (SLOF / firmware story) **or** `ppce500` — **choose in P0 and freeze**; do not dual-track both in CI |
| **Primary (PPC32)** | Documented `-M` under `qemu-system-ppc` after PPC64 LE P0 shape exists |
| Inventory (tentative) | `pseries`, `ppce500`, `mac99`, `g3beige`, bamboo / e500 variants — **tentative only** |

Harness rule: `make … qemu-args` (or arch sibling) prints suggested argv; Man /
Help speak board + `MEM_*`, not “we are QEMU.”

---

## 8. Naming, x86, and other non-goals

| Topic | Stance |
|-------|--------|
| **`holyc-riscv` binary name** | Keep for now; multi-arch via `--target` / `HOLYC_ARCH`. Rename is cosmetic debt, not a port gate. |
| **Artifact names** | Arch-qualified BINs and smoke targets (`kernel-*-aarch64-smoke`, …). |
| **TempleOS x86** | Reference tree in `tos/`; [TOS_X86_PARITY.md](../templeos-riscv/TOS_X86_PARITY.md) maps subsystems for the **RV** port. No `ARCH_X86` product track here. |
| **Guest runtime** | HolyC only (§2); host `holyc-riscv` stays as bootstrap AOT, not a C OS API layer |
| **ISAs not in §3** | Explicit non-goals until this document lists them. |

---

## 9. Decision summary

| Decision | Choice |
|----------|--------|
| Product language | Boards / Kconfig / HolyC drivers; QEMU = harness |
| Guest runtime | HolyC Cmp + HolyC drivers only — kill C hooks (§2); no per-ISA C libc |
| CI default | **RV64 virt** until an ISA’s P0 is trusted |
| First non-RV64 ISA | **RV32 virt** ([RV32.md](../templeos-riscv/RV32.md)) |
| Then | AArch64 virt → ARM32 → PPC64 LE → PPC32 |
| Exhaustive `-M` lists | Tentative inventory only |
| Host compiler | One binary, backend trait; no parser fork (bootstrap AOT — not guest runtime) |
| Guest Cmp | Per-ISA after that ISA’s P2; keep RV64 phase3 green |
| Adam / Win on new ISA | Optional P4 only |
| Implementation | **On request** — plan first, small PRs later |

---

## 10. Suggested first patches (when implementation is requested)

Cross-cutting (optional, before or with RV32):

1. Docs only — this file + index links (this landing).
2. Stub `choice ARCH` in Kconfig with **only** `ARCH_RISCV64` selected in
   default defconfigs (no behavior change).
3. `holyc_target` stub fields (XLEN / arch enum) defaulting to RV64.

Then follow [RV32.md](../templeos-riscv/RV32.md) §10 for the first real port.
Do not land ARM/PPC emit in the same series.
