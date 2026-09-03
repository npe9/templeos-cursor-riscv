# Verification environment (plan + P0)

**Status:** roadmap + **P0 closed loop** (optional). Frama-C / Dafny / Low★ are
*not* required for day-to-day work or `make ci`. Goal: a realistic path for
*proving or heavily verifying critical slices* of this RISC-V TempleOS / HolyC
tree — not “verify all of TempleOS.”

Audience: contributors who already ship HolyC guest + host C bootstrap
(`host/`, `bootstrap/`). Existing test oracles (`asm-prop`, `compiler-prop`,
exec/kernel smokes) stay the day-to-day correctness gate; formal work *extends*
them where a model pays for itself.

Related: [ARCHITECTURE.md](ARCHITECTURE.md), [LAYOUT.md](LAYOUT.md),
[MEMFS_LOG.md](MEMFS_LOG.md), [DEBUGGER.md](DEBUGGER.md), [CI.md](CI.md),
[tests/asm/](../tests/asm/README.md), [tests/compiler/](../tests/compiler/README.md),
[docs/spec/p0_rv_i.md](spec/p0_rv_i.md), [verify/](../verify/README.md).

---

## 1. Goals and non-goals

### Goals

| Goal | Example |
|------|---------|
| Prove or heavily check **small, high-blast-radius** slices | Host lexer/parser emit invariants; assembler encode; memfs journal epochs |
| Prefer **machine-checkable specs** next to code that already has oracles | ACSL on `host/`; Dafny models of `fs.hc` journal; optional CBMC on packers |
| Keep verification **optional / nightly** until a slice is stable | Do not block `make ci` on Frama/Dafny install |
| Align with product constraints | Guest HolyC is the product path; Mac `holyc-riscv` (C) is bootstrap; RISC-V codegen |

### Non-goals

- Full OS proof (sched, WinMgr, Adam, RedSea, virtio stack, …).
- Verifying guest HolyC *in* Frama-C (HolyC ≠ C; no ACSL story for `.HC`).
- Replacing `asm-prop` / gas differential / `compiler-prop` with a heavier stack
  before those oracles stop catching bugs.
- Crypto proofs (there is no TLS/disk crypto product surface worth the effort).
- End-to-end “TempleOS is correct” marketing claims.

Honest framing: **slice proofs + stronger oracles**, not seL4-for-TempleOS.

---

## 2. What exists today (research snapshot)

### Language / artifact split

| Layer | Language | Role |
|-------|----------|------|
| `host/` (`lexer.c`, `parser.c`, `compiler.c`, …) | **C** | Mac AOT bootstrap `holyc-riscv` — HolyC → RISC-V |
| `bootstrap/worry_dream_repl.c`, `holy_rt*.h`, `startup.s` | **C + asm** | Legacy UART REPL / slots (deprecated product path; still instructive for trap/regs snaps) |
| `bootstrap/seed/*.hc`, `hc_repl/`, `bootloader/boot.hc` | **HolyC** (+ `asm{}`) | Product REPL, memfs, ZMODEM, tutorials, HolyC boot head |
| `Kernel/`, `Compiler/`, `Adam/` | **HolyC** | Ported TempleOS trees; guest `Compiler_RV` is the language destination |
| `templeos-riscv/` | **C** loader + Kconfig | Board image / plat harness glue |
| Packers / oracles | **Python** | `pack_bootloader.py`, `gen_boot_blob.py`, `riscv_oracle.py`, prop harnesses |

Constraint reminder ([SELF_HOST.md](SELF_HOST.md)): day-to-day product work is **guest HolyC**; host C stays as the required AOT bootstrap. Formal work should therefore (a) harden the C bootstrap where Frama/CBMC apply, and (b) model HolyC algorithms in a separate language rather than pretending Frama reads `.HC`.

### Existing formal-adjacent / oracle gates

| Gate | What it checks | Limit |
|------|----------------|--------|
| `make asm-stress` / `asm-prop` / `asm-gnu-diff` | Host `TryAssembleRiscV` vs Python encode oracle + optional GNU gas | Not guest `Compiler/Asm_RV.HC`; RVC/CSR gaps documented |
| `make compiler-stress` / `compiler-prop` | Curated UART exec oracles; random opt-tier equivalence | Safe HolyC subset; not full language; guest Cmp only smoked |
| `make exec-oracle` / kernel `*-smoke` | End-to-end QEMU virt behavior | Observational, not a proof |
| `make dump-changes-smoke` / `zmodem-smoke` | Export / framing smoke | No journal epoch model check |
| Fmt goldens / compliance | Syntax / project compile surface | Not semantics |

**Implication:** verification should *reuse* oracle shapes (encode tables, epoch traces, snap layouts) rather than invent a parallel truth.

---

## 3. Tool choice matrix → recommended stack

| Tool | Fits this repo when… | Poor fit when… |
|------|----------------------|----------------|
| **Frama-C + ACSL** | Annotating / WP-proving **host C** (`lexer`, emit helpers, bounds on dump/pack C) | HolyC seeds / Kernel; large `parser.c` all at once |
| **Dafny** | Executable **models** of journal epochs, framing FSMs, trap-snap layout invariants; refine against Python/oracle traces | Wanting to ship Dafny as guest code |
| **Low★ / F★** | Long-term verified *low-level* C extract of a tiny critical kernel (e.g. journal ring, encode) | Near-term bootstrap; steep toolchain vs current Python/C oracles |
| **CBMC / ESBMC** | Bounded model-check of packers / framing C with concrete bounds | Deep inductive epoch proofs; HolyC |
| **Alive2** | Only if an LLVM backend appears | Current host emit is custom RISC-V, not LLVM IR |
| **riscv-formal / Sail** | Deepening ISA encode/decode beyond gas + `riscv_oracle.py` | Day-to-day CI (heavy); most bugs today are host↔gas, not ISA law |
| **Keep / grow prop oracles** | Always — cheapest semantic net | Treating them as “done” for journal / trap / bootloader |

### Recommended stack (this repo)

**P0–P2 primary:** Frama-C (ACSL) on narrowly sliced **host C**, plus **Dafny models** of HolyC-adjacent algorithms (memfs journal epochs, ZMODEM framing FSM, trap-snap memory map), checked against existing Python/QEMU oracles.

**Keep forever:** `asm-prop` + gas differential + `compiler-prop` as the RISC-V encode/codegen net — do not wait on Low★ to catch encode bugs.

**Optional later:** CBMC on `pack_bootloader.py`-adjacent C or extracted pack helpers; Sail/`riscv-formal` only if encode disputes outgrow gas; Low★/F★ only if a *tiny* critical slice is rewritten to verified C extract with a named owner and months of runway.

Rationale: Frama speaks the language of the bootstrap (`host/`); Dafny speaks the language of specs for guest HolyC without lying about ACSL-on-HolyC; existing prop tests already own the highest-churn RISC-V surface.

---

## 4. Verification targets (ranked)

High value × tractability for *this* tree. Rank is suggested attack order, not exclusivity.

| Rank | Target | Why | Tractability | Primary tool |
|------|--------|-----|--------------|--------------|
| **1** | Host assembler encode helpers (`parser.c` emit / `TryAssembleRiscV`) | Wrong words = silent wrong binaries; already has Python + gas oracles | High — small pure functions | Frama WP on emit helpers **or** Dafny/Python refine that mirrors `riscv_oracle.py`; grow `asm-prop` first |
| **2** | Host lexer / parser **safety** (bounds, no OOB on tokens/buffers) + selected IC invariants | Bootstrap crash / miscompile class; C is Frama-native | Medium — start with lexer + one emit path | Frama-C ACSL |
| **3** | Memfs journal **epoch semantics** (`fs.hc` ring, seal, checkpoint, wrap, dirty views) | Ops “session truth”; design already in [MEMFS_LOG.md](MEMFS_LOG.md) | Medium — model in Dafny; refine vs trace dumps | Dafny + smoke/oracle traces |
| **4** | Trap / debugger snapshot correctness (`MEM_TRAP_SNAP` / `MEM_REGS_SNAP`, restore-before-ret) | Dig-down honesty; layout is finite and documented in [DEBUGGER.md](DEBUGGER.md) | Medium — model layout + restore lemma; asm stubs stay oracle-tested | Dafny model + QEMU/oracle |
| **5** | Bootloader pack/load (`pack_bootloader.py` + `boot.hc` jump/copy) | Flash/reset path; small state machine | Medium–high — pure pack invariants + smoke | Dafny/Python properties + `bootloader-smoke` |
| 6 | Compiler IR / opt-tier **local** invariants (Tier-1 peephole “must not change observable”) | Complements `compiler-prop` | Lower — large IC surface | Dafny lemmas on tiny rewrites; keep prop tests |
| 7 | Crypto-free **framing safety** (Dump / ZMODEM length/CRC framing, no buffer overrun in C or modeled HolyC) | Export path; no crypto proof needed | Medium | CBMC or Frama on C; Dafny FSM for ZMODEM subset |
| 8 | Guest `Compiler/Asm_RV.HC` encode | Product long-term | Low near-term — no Frama; need model or host-oracle parity tests | Parity vs host/`riscv_oracle.py` first |

**Top five for contributors:** (1) assembler encode, (2) host lexer/parser safety, (3) memfs journal epochs, (4) trap/regs snap, (5) bootloader pack/load.

---

## 5. Architecture (where specs live)

```
docs/VERIFICATION.md          # this plan
docs/spec/p0_rv_i.md          # P0 note: RvI / OP-IMM vs oracle
verify/                       # optional machine-checked artifacts (not in make ci)
  README.md
  p0_rv_i/                    # thin Python model + extracted C RvI + run_p0.py
  frama/                      # (future) ACSL stubs / WP drivers for host/
  dafny/                      # (future) Journal.dfy, TrapSnap.dfy, …
  oracles/                    # (future) trace adapters
tests/asm/riscv_oracle.py     # EXISTING — remains source of encode truth for CI
```

### Principles

1. **HolyC is not in Frama.** Do not mass-translate `Kernel/` or `seed/` to C “so Frama can see it.” Verify **host C** with ACSL; verify **HolyC algorithms** via Dafny (or Python) **models** plus observational oracles.
2. **Ghost models vs extracted code.** Prefer *models* that state laws (epoch monotonicity, wrap ring capacity, snap restore) and check them against traces from the live HolyC/C implementation. Extracted verified C (Low★) is a later option for a single tiny module if ownership exists.
3. **One truth per surface.** Assembler: `riscv_oracle.py` + gas remain CI truth; any Frama/Dafny encode model must be generated from or differentially checked against that oracle — never a third competing encoder without a sync story.
4. **Specs next to ownership.** Epoch laws live conceptually with [MEMFS_LOG.md](MEMFS_LOG.md); snap layout with [DEBUGGER.md](DEBUGGER.md); encode with [tests/asm/](../tests/asm/README.md). Machine-checked files may live under `verify/` once introduced.
5. **No disturbance of product drivers.** Formal scaffolding must not rewrite UART/memfs/debugger agent paths except where a *named* verified slice is explicitly adopted.

---

## 6. Phased roadmap

### P0 — First experiment (exit: one closed loop) — **done**

| Item | Status |
|------|--------|
| Pick **one** pure host encode helper | **`RvI`** (`host/parser.c` OP-IMM I-type) — [docs/spec/p0_rv_i.md](spec/p0_rv_i.md) |
| (B) Python model ≡ `riscv_oracle.py` (+ extracted C twin) | `verify/p0_rv_i/` — no Frama/Dafny install |
| Loop: *spec → check → fail on seeded bug → fix* | `run_p0.py` pass path + `--seed-bug` (wrong opcode `0x33`) |
| **Not** in default `make ci` | Optional **`make verify-p0`** (python3 + `cc` only) |

**What P0 proves (strength: model-checked, not WP):** field-packing model and
extracted C `RvI` match `tests/asm/riscv_oracle.py::rv_i` on a dense (default) or
full imm12 (`--exhaustive`) domain; a seeded wrong opcode is rejected by the
same checker. Day-to-day encode gate remains `make asm-prop`.

### P1 — Host safety slice

- ACSL (Frama) on lexer tokenization bounds + one parser buffer discipline.
- Optional CBMC bounded check on the same slice.
- Exit: contracts hold on tip; documented gaps list; still optional CI.

### P2 — Memfs journal model

- Dafny model of epochs / seal / checkpoint / wrap / dirty-set views per [MEMFS_LOG.md](MEMFS_LOG.md).
- Trace adapter: dump journal from guest smoke → check model acceptance.
- Exit: model rejects a seeded wrap/epoch bug; `dump-changes-smoke` remains the product gate.

### P3 — Snap + bootloader

- Trap/regs snap layout lemmas (addresses, restore-before-ret, CSR-not-in-GPR-snap).
- Bootloader pack invariants (jump vs copy, length/base, no overlap).
- Exit: models + existing `bootloader-smoke` / debugger docs agree; optional nightly job.

### P4 — Opt / framing / guest parity (stretch)

- Tiny Tier-1 peephole lemmas aligned with `compiler-prop`.
- ZMODEM/Dump framing FSM + overflow freedom (model or CBMC).
- Host↔guest asm encode parity tests (not full guest proof).
- Exit: clear “verified surface” map in this doc; still not full OS.

---

## 7. CI sketch

| Phase | When it runs | Gate strength |
|-------|--------------|---------------|
| Today | `asm-prop` in compile-compliance; `compiler-prop` in local `stress` / qemu path as configured | Required for encode/codegen health |
| P0 | Manual / contributor laptop **`make verify-p0`** ([verify/p0_rv_i/](../verify/p0_rv_i/)) | Optional — not in `make ci` |
| After P1–P2 | **Nightly** or `workflow_dispatch` job `verification` (Frama + Dafny containers) | Non-blocking; failure → issue, not red tip CI |
| After P3+ if stable | Optional path filter: only when `host/**` or `verify/**` or journal specs change | Still not part of markdown-skip-sensitive default PR CI until flake-free |

Principles: no new required apt packages on the main PR path; pin tool versions in a future `verify/README.md`; keep QEMU smokes as behavioral truth for HolyC.

---

## 8. Risks

| Risk | Mitigation |
|------|------------|
| HolyC semantics undefined for Frama | Never claim ACSL-on-HolyC; use Dafny/Python models + oracles |
| Bitwidth / RV64 vs host `long` / Frama machdep | Fix a model machine (64-bit); align with `I64` / word size docs |
| Asm stubs and `asm{}` opaque to WP | Keep snap/boot as models + smokes; do not WP naked asm |
| Effort duplicates `asm-prop` | Prefer growing oracles first; formalize only when a lemma beats more random trials |
| Toolchain weight (Frama, Dafny, F★) | Optional nightly; document macOS reality (Linux CI image may be easier) |
| Scope creep to “verify Kernel” | Ranked targets + non-goals; reject PRs that expand without exit criteria |
| Divergent third encoder | Single oracle ownership (`riscv_oracle.py` or gas) |

---

## 9. Contributor checklist (when work starts)

1. Read this plan + the target’s product doc (MEMFS / DEBUGGER / asm README).
2. Prefer extending an existing oracle before adding a new tool.
3. If adding Frama/Dafny: put artifacts under `verify/`, keep `make ci` green without those tools.
4. Record what is *proved* vs *model-checked* vs *oracle-tested* — three different strengths.
5. Do not disturb debugger/fs/driver agent code paths except for an explicitly scoped verified slice.

---

## Appendix — quick glossary

| Term | Meaning here |
|------|----------------|
| **Oracle** | Executable reference (Python encode, QEMU `ORACLE` line, gas) |
| **Model** | Spec in Dafny/ACSL that may not be the shipped code |
| **Refine** | Show implementation / traces satisfy the model |
| **Slice** | Small subsystem chosen for verification, not the whole OS |
