# Tutorial curriculum (Software Foundations style)

Hands-on systems programming on this **RISC-V TempleOS / HolyC** port.
**Lessons are executable HolyC** — like Software Foundations (Pierce et al.)
`.v` files you compile, these are `.hc` files you `Run` in the UART REPL.

Markdown here is only the **TOC map + how to run**. Chapter content lives in:

`bootstrap/seed/tutorials/*.hc` → memfs `/Tutorials/` (`Cd("Tutorials"); Run("B02_DataRep.hc");`).
Bare `Run("B02_DataRep.hc");` still works (unique basename).

## How to run

```bash
make
make hc-repl
# load build/repl-holyc.elf on your board / harness
```

At the `>` prompt:

```holyc
Help;
Tutorial;          // or SF;
Run("A01_RV64I.hc");
// edit TODOs: Src("A01_RV64I");  or Vi
Run("A01_RV64I.hc");
```

Rebuild the REPL blob whenever you change seeds or tutorials.

## Student workflow (per chapter)

1. `Run("Lesson.hc");` — teaching comments print; **demos PASS**; `Fill_in` exercises may **FAIL**.
2. `Src("Lesson");` / `Vi` — implement `Ex1`…`ExN` stubs (warmup → apply → challenge).
3. `Run("Lesson.hc");` again — aim for all `PASS`.
4. Optional dig-down: `Uf("…");` `MemMap;` `Man("…");` `Regs;`
5. `Tutorial;` — pick the next file.

Each chapter has **≥ 7–8 graded exercises** with automated PASS/FAIL checks (plus at least one working demo).

## Curriculum order

| Part | Focus | Lessons | Ex / chapter |
|------|--------|---------|--------------|
| **[A — RISC-V ISA](part-a/README.md)** | RV64I, ABI, loads/stores, branches, CSR/traps, `asm{}`, MemMap/Man | `A01_…` … `A08_…` | 7–8 |
| **[B — CSAPP 3e](part-b/README.md)** | CSAPP chapters + B13 thread-lib + B14 Herlihy&Shavit | `B01_…` … `B14_…` | 8–10 |
| **[C — Beck 3e](part-c/README.md)** | One `.hc` lab per Beck chapter | `C01_…` … `C08_…` | 8 |

Progressive path: **A → B (through B14) → C**. Entry: `Tutorial;` / `SF;`.

## Exercise counts (summary)

| Lesson | Exercises | Lesson | Exercises |
|--------|-----------|--------|-----------|
| A01 | 7 | B01 | 8 |
| A02 | 7 | B02 | 8 |
| A03 | 8 | B03 | 8 |
| A04 | 8 | B04 | 8 |
| A05 | 8 | B05 | 8 |
| A06 | 8 | B06 | 8 |
| A07 | 8 | B07 | 8 |
| A08 | 8 | B08 | 8 |
| C01 | 8 | B09 | 8 |
| C02 | 8 | B10 | 8 |
| C03 | 8 | B11 | 8 |
| C04 | 8 | B12 | 8 |
| C05 | 8 | B13 | 10 |
| C06 | 8 | B14 | 10 |
| C07 | 8 | | |
| C08 | 8 | | |

**Total: 30 chapters, 242 graded exercises** (plus working demos per chapter).

## Book TOC sources (edition-clear)

### CSAPP 3e — *Computer Systems: A Programmer’s Perspective*, 3rd Edition
**Authors:** Randal E. Bryant, David R. O’Hallaron (Pearson / CMU 15-213).  
**Sources used for chapter titles:**

- Pearson product TOC: https://www.pearson.com/en-us/subject-catalog/p/computer-systems-a-programmers-perspective/P200000003479  
- CS:APP3e student site (chapter resource headings): https://csapp.cs.cmu.edu/3e/students.html  
- About / ISBN page: https://csapp.cs.cmu.edu/3e/about.html (ISBN-13 978-0134092669)

**Parts & chapters (official titles):**

| Part | Ch | Title |
|------|----|--------|
| I Program Structure and Execution | 1 | A Tour of Computer Systems |
| | 2 | Representing and Manipulating Information |
| | 3 | Machine-Level Representation of Programs |
| | 4 | Processor Architecture |
| | 5 | Optimizing Program Performance |
| | 6 | The Memory Hierarchy |
| II Running Programs on a System | 7 | Linking |
| | 8 | Exceptional Control Flow |
| | 9 | Virtual Memory |
| III Interaction and Communication Between Programs | 10 | System-Level I/O |
| | 11 | Network Programming |
| | 12 | Concurrent Programming |

### Herlihy & Shavit — *The Art of Multiprocessor Programming* (lab B14)

**Authors:** Maurice Herlihy, Nir Shavit (Morgan Kaufmann / Elsevier).  
**Lab:** [`B14_ArtOfMulticore.hc`](../../bootstrap/seed/tutorials/B14_ArtOfMulticore.hc) — themes from mutual exclusion, CAS consensus, spin locks, ABA, barriers; remapped to RV64 HolyC + `RVSmp`.  
**TOC sources:** Elsevier 2e shop page (ISBN 978-0-12-415950-1); companion materials at https://booksite.elsevier.com/9780123705914/

### Beck 3e — *System Software: An Introduction to Systems Programming*, 3rd Edition
**Author:** Leland L. Beck (Addison-Wesley / Pearson, ©1997; ISBN commonly 0-201-42300-6).  
**Sources used for chapter titles:**

- Course/slide decks citing Beck 3e chapter list (e.g. https://www.slideserve.com/aviva/system-programming )  
- Publisher/retail listings describing the eight-chapter organization (Amazon/Pearson reprints)

**Chapters (in order):**

| Ch | Title |
|----|--------|
| 1 | Background |
| 2 | Assemblers |
| 3 | Loaders and Linkers |
| 4 | Macro Processors |
| 5 | Compilers |
| 6 | Operating Systems |
| 7 | Other System Software |
| 8 | Software Engineering Issues |

These labs teach **themes** on **this stack** (HolyC, `holyc-riscv`, guest `Compiler_RV`, Kernel drivers). They are not textbook reprints.

## Master mapping: book chapter → lesson file

| Book | Ch | Title | Lesson (memfs / `Run`) | Source path |
|------|----|--------|-------------------------|-------------|
| — | A1 | RV64I base | `A01_RV64I.hc` | [tutorials/A01_RV64I.hc](../../bootstrap/seed/tutorials/A01_RV64I.hc) |
| — | A2 | Registers & ABI | `A02_RegsABI.hc` | [A02_RegsABI.hc](../../bootstrap/seed/tutorials/A02_RegsABI.hc) |
| — | A3 | Load / store | `A03_LoadStore.hc` | [A03_LoadStore.hc](../../bootstrap/seed/tutorials/A03_LoadStore.hc) |
| — | A4 | Branches & control | `A04_Branches.hc` | [A04_Branches.hc](../../bootstrap/seed/tutorials/A04_Branches.hc) |
| — | A5 | CSR & traps | `A05_CSRTraps.hc` | [A05_CSRTraps.hc](../../bootstrap/seed/tutorials/A05_CSRTraps.hc) |
| — | A6 | `asm{}` in HolyC | `A06_AsmHolyC.hc` | [A06_AsmHolyC.hc](../../bootstrap/seed/tutorials/A06_AsmHolyC.hc) |
| — | A7 | MemMap & Man | `A07_MemMapMan.hc` | [A07_MemMapMan.hc](../../bootstrap/seed/tutorials/A07_MemMapMan.hc) |
| — | A8 | REPL drills | `A08_REPLDrills.hc` | [A08_REPLDrills.hc](../../bootstrap/seed/tutorials/A08_REPLDrills.hc) |
| CSAPP | 1 | A Tour of Computer Systems | `B01_Tour.hc` | [B01_Tour.hc](../../bootstrap/seed/tutorials/B01_Tour.hc) |
| CSAPP | 2 | Representing and Manipulating Information | `B02_DataRep.hc` | [B02_DataRep.hc](../../bootstrap/seed/tutorials/B02_DataRep.hc) |
| CSAPP | 3 | Machine-Level Representation of Programs | `B03_Machine.hc` | [B03_Machine.hc](../../bootstrap/seed/tutorials/B03_Machine.hc) |
| CSAPP | 4 | Processor Architecture | `B04_Processor.hc` | [B04_Processor.hc](../../bootstrap/seed/tutorials/B04_Processor.hc) |
| CSAPP | 5 | Optimizing Program Performance | `B05_Optimize.hc` | [B05_Optimize.hc](../../bootstrap/seed/tutorials/B05_Optimize.hc) |
| CSAPP | 6 | The Memory Hierarchy | `B06_MemHierarchy.hc` | [B06_MemHierarchy.hc](../../bootstrap/seed/tutorials/B06_MemHierarchy.hc) |
| CSAPP | 7 | Linking | `B07_Linking.hc` | [B07_Linking.hc](../../bootstrap/seed/tutorials/B07_Linking.hc) |
| CSAPP | 8 | Exceptional Control Flow | `B08_ECF.hc` | [B08_ECF.hc](../../bootstrap/seed/tutorials/B08_ECF.hc) |
| CSAPP | 9 | Virtual Memory | `B09_VM.hc` | [B09_VM.hc](../../bootstrap/seed/tutorials/B09_VM.hc) |
| CSAPP | 10 | System-Level I/O | `B10_IO.hc` | [B10_IO.hc](../../bootstrap/seed/tutorials/B10_IO.hc) |
| CSAPP | 11 | Network Programming | `B11_Network.hc` | [B11_Network.hc](../../bootstrap/seed/tutorials/B11_Network.hc) |
| CSAPP | 12 | Concurrent Programming | `B12_Concurrent.hc` | [B12_Concurrent.hc](../../bootstrap/seed/tutorials/B12_Concurrent.hc) |
| lab | — | Write a threading library | `B13_ThreadLib.hc` | [B13_ThreadLib.hc](../../bootstrap/seed/tutorials/B13_ThreadLib.hc) |
| lab | — | Art of Multiprocessor Programming (Herlihy & Shavit) | `B14_ArtOfMulticore.hc` | [B14_ArtOfMulticore.hc](../../bootstrap/seed/tutorials/B14_ArtOfMulticore.hc) |
| Beck | 1 | Background | `C01_Background.hc` | [C01_Background.hc](../../bootstrap/seed/tutorials/C01_Background.hc) |
| Beck | 2 | Assemblers | `C02_Assemblers.hc` | [C02_Assemblers.hc](../../bootstrap/seed/tutorials/C02_Assemblers.hc) |
| Beck | 3 | Loaders and Linkers | `C03_LoadersLinkers.hc` | [C03_LoadersLinkers.hc](../../bootstrap/seed/tutorials/C03_LoadersLinkers.hc) |
| Beck | 4 | Macro Processors | `C04_MacroProcessors.hc` | [C04_MacroProcessors.hc](../../bootstrap/seed/tutorials/C04_MacroProcessors.hc) |
| Beck | 5 | Compilers | `C05_Compilers.hc` | [C05_Compilers.hc](../../bootstrap/seed/tutorials/C05_Compilers.hc) |
| Beck | 6 | Operating Systems | `C06_OperatingSystems.hc` | [C06_OperatingSystems.hc](../../bootstrap/seed/tutorials/C06_OperatingSystems.hc) |
| Beck | 7 | Other System Software | `C07_OtherSystemSoftware.hc` | [C07_OtherSystemSoftware.hc](../../bootstrap/seed/tutorials/C07_OtherSystemSoftware.hc) |
| Beck | 8 | Software Engineering Issues | `C08_SoftwareEngineering.hc` | [C08_SoftwareEngineering.hc](../../bootstrap/seed/tutorials/C08_SoftwareEngineering.hc) |

Index entry also: [tutorial.hc](../../bootstrap/seed/tutorial.hc) (`Tutorial;` / `SF;`).

## Related docs

| Doc | Why |
|-----|-----|
| [getting-started.md](getting-started.md) | First five minutes |
| [export-changes.md](export-changes.md) | Make changes and get them off the box — `FsChanges` / `DumpChanges` / JTAG journal |
| [../REPL.md](../REPL.md) | UART REPL, `asm{}`, Man, MemMap |
| [../ARCHITECTURE.md](../ARCHITECTURE.md) | Host / REPL / Kernel / guest Cmp |
| [../../templeos-riscv/PLATFORM.md](../../templeos-riscv/PLATFORM.md) | Boards + `MEM_*` |
| [../../templeos-riscv/COMPILER_RV.md](../../templeos-riscv/COMPILER_RV.md) | Guest compiler |
