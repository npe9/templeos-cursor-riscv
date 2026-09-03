# Part C — Beck 3e chapter labs (executable)

**Book:** Leland L. Beck, *System Software: An Introduction to Systems
Programming*, **3rd edition**. Chapter titles — see [../README.md](../README.md)
for sources.

Beck’s through-line: **system software is machine-dependent** — here the machine
is **RISC-V + TempleOS HolyC**, not SIC/XE.

**Workflow:** `Run("C0N_….hc");` → demos PASS → fill **8** `Ex1…Ex8` → `Run`
again until PASS.

| Ch | Beck title | `Run("…")` | Ex |
|----|------------|------------|----|
| 1 | Background | [`C01_Background.hc`](../../../bootstrap/seed/tutorials/C01_Background.hc) | 8 |
| 2 | Assemblers | [`C02_Assemblers.hc`](../../../bootstrap/seed/tutorials/C02_Assemblers.hc) | 8 |
| 3 | Loaders and Linkers | [`C03_LoadersLinkers.hc`](../../../bootstrap/seed/tutorials/C03_LoadersLinkers.hc) | 8 |
| 4 | Macro Processors | [`C04_MacroProcessors.hc`](../../../bootstrap/seed/tutorials/C04_MacroProcessors.hc) | 8 |
| 5 | Compilers | [`C05_Compilers.hc`](../../../bootstrap/seed/tutorials/C05_Compilers.hc) | 8 |
| 6 | Operating Systems | [`C06_OperatingSystems.hc`](../../../bootstrap/seed/tutorials/C06_OperatingSystems.hc) | 8 |
| 7 | Other System Software | [`C07_OtherSystemSoftware.hc`](../../../bootstrap/seed/tutorials/C07_OtherSystemSoftware.hc) | 8 |
| 8 | Software Engineering Issues | [`C08_SoftwareEngineering.hc`](../../../bootstrap/seed/tutorials/C08_SoftwareEngineering.hc) | 8 |

Prereq: [Part A](../part-a/README.md); Part B Ch.7–8 help for Load/traps.
