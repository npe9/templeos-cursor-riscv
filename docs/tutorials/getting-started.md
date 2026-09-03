# Getting started (before Part A)

## Goal

Boot the bare-metal HolyC REPL, confirm Man/MemMap/`Tutorial` work.

## Build and load

```bash
make
make repl-blob
cd bootstrap && make clean && make -f Makefile.repl
```

Load `bootstrap/repl.elf` on the configured board profile. Details:
[../REPL.md](../REPL.md), [../../templeos-riscv/PLATFORM.md](../../templeos-riscv/PLATFORM.md).

## First five minutes

```holyc
Help;
Tutorial;
1+2*3;
Man("Print");
Man("CLINT");
MemMap;
Regs;
Run("A01_RV64I.hc");
```

## SF-style workflow

1. `Run("Lesson.hc");` — demos run and should **PASS**; `TODO` / `Fill_in`
   exercises (`Ex1`…`ExN`) may **FAIL** until you edit them.
2. `Src("Lesson");` or `Vi` — implement the stubs (warmup → apply → challenge).
3. `Run("Lesson.hc");` again — aim for every check to print `PASS`.
4. Dig-down as needed: `Uf("Name");` `MemMap;` `Man("Topic");` `Reg("a0");`
5. `Tutorial;` — pick the next file.

Each chapter ships **7–8 graded exercises** with automated harnesses. See
[README.md](README.md) for the full exercise-count table (~220 total).

Lessons live in memfs (from `bootstrap/seed/tutorials/`). After editing seeds on
the host: `make repl-blob` and rebuild `Makefile.repl`.

## Next

→ [Part A — RISC-V ISA](part-a/README.md) · [Curriculum index](README.md)
