# Verification: properties, fuzzing, and proofs about the parts that deserve them

A plan for QuickCheck-style property testing, fuzzing, and Hoare-style reasoning (weakest
precondition / strongest postcondition) in this port. Written 2026-09-19.

The argument for doing this here rather than adding more example tests: **this repo already has
an oracle for almost everything.** GNU `as` says what an instruction encodes to. QEMU says what
it does. The 244-entry catalog says what it means. A second implementation of the same thing
exists in half the cases (host assembler vs guest assembler, host compiler vs guest compiler,
rv64 vs the rv32 lifter). Property testing is cheap when you have an oracle; that is the whole
reason to start there rather than with proofs.

---

## 0. What already works this way

Worth naming, because the plan is mostly "more of this, generated":

- `run_asm_gnu_diff.sh` — differential against GNU `as`: 220 match, 13 must-reject, **120
  generated**. This is already property testing; it just has a small, fixed generator.
- `run_exec_oracles.sh` / `run_rv32_oracles.sh` — 88 and 62 cases comparing execution against
  expected results, with the rv32 side checking the lifter against the rv64 meaning.
- The byte-identical gates: rv64 output unchanged when the rv32 backend changes; the newline
  rule off leaves the compiler byte-identical; the same program with and without semicolons
  compiles to identical bytes. These are *equivalence properties* already, just with one input.

---

## 1. Property testing (QuickCheck style)

### 1.1 Generate instructions from the catalog, not by hand

`rv_asm_doc_raw` has 244 entries with an operand template (`addi rd, rs, imm`), an encoding
class, and a documented immediate range (`-2048..2047`). That is a generator specification
already written down. A generator that reads the catalog and emits random well-typed operands
gives, for free:

- **P1 (encoding agreement):** for every catalog entry and 1000 random operand vectors, the guest
  assembler and GNU `as` produce identical bytes. Extends `asm-gnu-diff`'s 120 generated cases to
  the whole catalog, and makes a new instruction testable the moment it is documented.
- **P2 (round trip):** `disassemble(assemble(x)) == x` modulo whitespace, for every generated
  instruction. The `t` command already does this round trip by hand at run time; as a property it
  covers the whole catalog.
- **P3 (the catalog is honest):** every template in the catalog assembles. This already caught
  `fmv.d.x` — documented, and rejected by the assembler — but only because a human typed it.

### 1.2 Make the documentation the oracle

The catalog's `semantics` field is a machine-readable sentence: `rd = rs1 + sext(imm12)`,
`if (rs1 == rs2) pc += sext(imm)`. Parsing that subset into a reference interpreter turns every
documented instruction into an executable specification, and then:

- **P4 (execution agreement):** for random register states and random operands, the value
  `AsmStep` produces equals what the catalog's semantics predict. The stepper already has the
  register file, the private stack and a changed-register report — the harness exists, it needs a
  model to compare against.

This is the highest-value item in the plan. It is also the one that pays a second dividend: a
semantics sentence that cannot be parsed is a documentation bug, and a semantics that disagrees
with the hardware is either a doc bug or a CPU bug, and both are worth knowing.

### 1.3 Properties of the renderer and the layout

The diffing renderer has a real invariant and a model already written (the escape-stream replay
in the smokes):

- **P5 (incremental equals full):** for any sequence of documents rendered into a tile, the
  screen after incremental updates equals the screen after a full repaint of the last one. This
  is exactly the class of bug that made panes "look frozen", and a generated version would have
  caught the stale-shadow case without a person noticing it.
- **P6 (the layout fits):** for any terminal size in 20..60 rows by 60..200 columns, no pane
  overlaps another, nothing is written into the gutter, and every block that is shown is shown
  whole. The ranked-block code has four branches and they are currently checked at two sizes.

### 1.4 Properties of the compiler front end

- **P7 (the newline rule is a no-op on semicolon-terminated code):** generate small programs,
  compile with and without `HOLYC_NL_SEMI=1`, require identical bytes. The current test does this
  for one program; generating them is what would let the rule be turned on by default with
  confidence.
- **P8 (semicolon stripping is invertible):** generate a program, strip the semicolons the rule
  is meant to supply, compile both, require identical bytes. This is P7's converse and is the
  actual claim the rule makes.

---

## 2. Fuzzing

Ordered by how cheap the harness is.

### 2.1 The host compiler, coverage-guided

`host/` is plain C with a `main` that takes a file. That is an afl++/libFuzzer target as it
stands. Properties: never crash, never hang, and report errors rather than assert. Seed the
corpus with the `.HC` tree — several thousand real files — and it will explore the lexer and the
preprocessor hard. **This is the single cheapest thing on this page.**

### 2.2 The line editor and the escape parser

`RVLineEd` now parses CSI sequences with parameters, reads resize reports, and pushes back bytes
it did not want. Feed it random byte streams, including malformed escapes and partial sequences
split across reads. Property: it always terminates, never emits an unbalanced escape, and always
returns to a prompt. The soft-RX queue makes this drivable from the smoke harness without QEMU.

### 2.3 The guest assembler, negatively

Random text, random near-miss instructions (a good mnemonic with the wrong operand shape, an
immediate one past its range). Property: rejected with an error, never assembled to something
else, and never a trap. `asm-gnu-diff` has 13 hand-written negative cases; a generator would find
the ones nobody thought of.

### 2.4 Structure walkers

The page-table walker and the PMP decoder read attacker-shaped data: random PTE arrays, random
`pmpcfg` bytes, loops and self-referencing tables. Property: always terminates, never reads
outside the table it was given. `PgAt` already takes the root as an argument, which is exactly
what makes it fuzzable without paging turned on.

---

## 3. Weakest precondition / strongest postcondition

Proofs are worth it where the code is small, total, and load-bearing. Three places qualify.

### 3.1 The rv32 lifter — the strongest case

Each rv64 word becomes a fixed rv32 sequence, and the lifter's invariant is already written down:
expansion size depends only on the opcode, never on the operands. Model each rv64 instruction and
its rv32 expansion as SMT formulas over 64-bit and 32-bit bitvectors, then ask a solver whether
the expansion's strongest postcondition implies the original's, for all inputs. Z3 from Python,
one rule at a time, no proof assistant needed.

This is where a subtle bug hides longest: the oracles cover 62 cases, and the space is every
register value.

### 3.2 The asm REPL's wrapper

`AsmStep` wraps one instruction in a load/store of the register context. The claim is: after the
wrapper, the context holds exactly what the instruction would have left, and nothing outside the
context changed. That is a Hoare triple over a straight-line sequence with no branches — the
weakest precondition is mechanical.

It would have caught both wrapper bugs this month by construction: `t6` clobbered before it was
saved, and `sp` recorded 16 bytes low because the wrapper had already pushed.

### 3.3 Bit arithmetic with a spec

NAPOT decoding, PTE field extraction, satp mode decoding, the fcsr fields. Each is a handful of
shifts and masks with a specification in the privileged ISA manual. Extract them, state the
postcondition (`base + size == next region's base`, `size is a power of two ≥ 8`, `the decoded
range contains exactly the addresses the hardware would match`), and check with a solver over all
inputs rather than the one example a test would use.

---

## 4. Order, and what each step buys

| Step | Buys | Cost |
|---|---|---|
| 2.1 fuzz the host compiler | crashes and hangs in the thing every build depends on | an afternoon |
| 1.1 catalog-driven generator + P1/P2/P3 | every documented instruction tested against `as`, and the catalog kept honest | a day |
| 1.3 P5/P6 renderer and layout | the "pane looks frozen" class, permanently | a day |
| 1.2 semantics as an oracle (P4) | execution checked against the documentation, and the documentation checked against the hardware | two days |
| 3.1 lifter equivalence in Z3 | the rv32 backend, over all register values instead of 62 cases | two days |
| 2.2–2.4 fuzz the editor, assembler, walkers | robustness against the input a person actually types by accident | a day each |
| 3.2 wrapper triple | the stepper's correctness, by construction | a day |

A note on cost: every item above pays for itself per case, and the case count is what makes it
worth doing. Under QEMU each image parks in `wfi` and waits out its own timeout, so the loop is
slow enough that "a thousand cases per instruction" stays theoretical. [HOSTED_JIT.md](HOSTED_JIT.md)
is the project that changes that arithmetic, and §1.1-§1.3 are its H4.

**Start with 2.1 and 1.1.** They need no new theory, they reuse oracles that already exist, and
they will find things this week. The proofs in §3 are worth doing, but they are worth doing
*after* the generators, because a generator that disagrees with a proof usually means the model
is wrong — and it is much easier to debug a model when you have concrete counterexamples.

## 5. The thing to be careful about

Verification scaffolding rots faster than the code it checks, because it fails in ways nobody
wants to debug on a Friday. Two rules that keep it alive:

- **Every generator is seeded and reproducible.** A property failure must print the seed and the
  exact case, and that case must be addable to the fixed corpus in one line. A flaky property test
  gets disabled, and a disabled test is worse than no test.
- **Properties run in CI at a small count and on demand at a large one.** A thousand cases per
  instruction is a nightly job; ten is a pull-request gate.
