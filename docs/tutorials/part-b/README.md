# Part B — CSAPP 3e chapter labs (executable)

**Book:** *Computer Systems: A Programmer’s Perspective*, **3rd ed.** (Bryant &
O’Hallaron). Chapter titles from Pearson / CS:APP3e TOC — see
[../README.md](../README.md) for source URLs.

Each chapter → one HolyC lab under `bootstrap/seed/tutorials/`. Remapped to
**HolyC + RV64 + this Kernel/REPL**, not x86-64 Linux.

**Workflow:** `Run("B0N_….hc");` → demos PASS → fill **8** `Ex1…Ex8` stubs →
`Run` again. Honest **GAP** notes appear where the port lacks full VM/sockets.

| Ch | CSAPP title | `Run("…")` | Ex |
|----|-------------|------------|----|
| 1 | A Tour of Computer Systems | [`B01_Tour.hc`](../../../bootstrap/seed/tutorials/B01_Tour.hc) | 8 |
| 2 | Representing and Manipulating Information | [`B02_DataRep.hc`](../../../bootstrap/seed/tutorials/B02_DataRep.hc) | 8 |
| 3 | Machine-Level Representation of Programs | [`B03_Machine.hc`](../../../bootstrap/seed/tutorials/B03_Machine.hc) | 8 |
| 4 | Processor Architecture | [`B04_Processor.hc`](../../../bootstrap/seed/tutorials/B04_Processor.hc) | 8 |
| 5 | Optimizing Program Performance | [`B05_Optimize.hc`](../../../bootstrap/seed/tutorials/B05_Optimize.hc) | 8 |
| 6 | The Memory Hierarchy | [`B06_MemHierarchy.hc`](../../../bootstrap/seed/tutorials/B06_MemHierarchy.hc) | 8 |
| 7 | Linking | [`B07_Linking.hc`](../../../bootstrap/seed/tutorials/B07_Linking.hc) | 8 |
| 8 | Exceptional Control Flow | [`B08_ECF.hc`](../../../bootstrap/seed/tutorials/B08_ECF.hc) | 8 |
| 9 | Virtual Memory | [`B09_VM.hc`](../../../bootstrap/seed/tutorials/B09_VM.hc) | 8 |
| 10 | System-Level I/O | [`B10_IO.hc`](../../../bootstrap/seed/tutorials/B10_IO.hc) | 8 |
| 11 | Network Programming | [`B11_Network.hc`](../../../bootstrap/seed/tutorials/B11_Network.hc) | 8 |
| 12 | Concurrent Programming | [`B12_Concurrent.hc`](../../../bootstrap/seed/tutorials/B12_Concurrent.hc) | 8 |
| — | **Lab:** Write a threading library | [`B13_ThreadLib.hc`](../../../bootstrap/seed/tutorials/B13_ThreadLib.hc) | 10 |
| — | **Lab:** Art of Multiprocessor Programming | [`B14_ArtOfMulticore.hc`](../../../bootstrap/seed/tutorials/B14_ArtOfMulticore.hc) | 10 |

Prereq: [Part A](../part-a/README.md). Path: **B12 → B13 → B14** then Part C. Entry: `Tutorial;`
