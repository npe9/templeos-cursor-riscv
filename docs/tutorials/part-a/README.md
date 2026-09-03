# Part A — RISC-V ISA labs (executable)

Prereq for Parts B/C. Each lesson is a HolyC file: `Run("A01_RV64I.hc");`

**Workflow:** `Run` → demos PASS / Ex FAIL → `Src` fill `Ex1…ExN` → `Run` until PASS.

| # | Lesson | Ex | You will |
|---|--------|----|----------|
| 1 | [`A01_RV64I.hc`](../../../bootstrap/seed/tutorials/A01_RV64I.hc) | 7 | `li` / `addi` / `add`; no `subi`; imm range |
| 2 | [`A02_RegsABI.hc`](../../../bootstrap/seed/tutorials/A02_RegsABI.hc) | 7 | `a*` / `s*` / caller vs callee; `Regs` |
| 3 | [`A03_LoadStore.hc`](../../../bootstrap/seed/tutorials/A03_LoadStore.hc) | 8 | LE peek; sign/zero ext; `MEM_*` |
| 4 | [`A04_Branches.hc`](../../../bootstrap/seed/tutorials/A04_Branches.hc) | 8 | HolyC control + `Uf`; signed vs unsigned |
| 5 | [`A05_CSRTraps.hc`](../../../bootstrap/seed/tutorials/A05_CSRTraps.hc) | 8 | `GetMStatus` / CLINT; no TrapInit at load |
| 6 | [`A06_AsmHolyC.hc`](../../../bootstrap/seed/tutorials/A06_AsmHolyC.hc) | 8 | unlabeled `asm{}`; sequences; `FnAddr` |
| 7 | [`A07_MemMapMan.hc`](../../../bootstrap/seed/tutorials/A07_MemMapMan.hc) | 8 | MemMap → driver → Man dig-down |
| 8 | [`A08_REPLDrills.hc`](../../../bootstrap/seed/tutorials/A08_REPLDrills.hc) | 8 | capstone: bits + map + symbols |

Start: [../getting-started.md](../getting-started.md) · Index: [../README.md](../README.md)
