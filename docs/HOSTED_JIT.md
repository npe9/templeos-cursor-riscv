# Hosted JIT: running the JIT as a Linux/macOS process

A later project. The JIT (`bootstrap/hc_repl/jit.hc`, HolyC-in-HolyC) only ever runs bare
metal today. This is the plan to also run it as an ordinary userspace process on Linux and
macOS, **so that it is forced through those systems' ABIs and APIs** rather than through a
machine we control completely.

Written 2026-09-21. Companion to [MULTIARCH.md](MULTIARCH.md), which covers retargeting the
AOT backend to other ISAs *bare metal*, and to [VERIFICATION_PLAN.md](VERIFICATION_PLAN.md),
which this makes dramatically cheaper to execute.

---

## 1. Why, in order of what it buys

### 1.1 It exercises ABIs and APIs nothing here currently touches

Bare metal is a machine with no opinions. Every hard question a real platform asks — who saves
which register, where varargs live, whether you may write to the page you are about to execute,
how you learn that a load faulted — is either answered by us or does not arise. A hosted JIT has
to answer them the way the platform says, and getting them wrong fails loudly.

The specific surfaces, each of which is a real thing this port has never had to get right:

- **Calling convention.** SysV AMD64 and AAPCS64, and Apple's arm64 is *not* AAPCS64 where it
  matters most to us: on Darwin arm64 variadic arguments are passed on the **stack**, not in
  registers. HolyC is unusually varargs-heavy — `Print`, `StrPrint`, `StrPrintJoin`, and the
  `"..."` string-statement lowering that had its own codegen bug this month. This is the single
  best reason to do it: our varargs handling would be checked against two conventions that
  disagree.
- **W^X.** macOS on Apple Silicon requires `MAP_JIT` plus `pthread_jit_write_protect_np()`
  toggling per thread, and the hardened runtime entitlement. Linux wants
  `mmap(PROT_READ|PROT_WRITE)` then `mprotect(PROT_READ|PROT_EXEC)`. Bare metal has neither, so
  the JIT currently writes and executes the same page with nothing in the way.
- **Instruction-cache coherency.** `fence.i` becomes `sys_icache_invalidate()` on Darwin and
  `__builtin___clear_cache()` on Linux. We already know this matters — the guest JIT has to
  issue `fence.i` after writing code, and `CsrNum` fences before calling the stub it just built.
- **Trap delivery.** `mtvec` and `mcause` become `SIGSEGV`/`SIGBUS`/`SIGILL`, `si_code`, and
  `ucontext_t`. The REPL's recover-to-the-prompt behaviour has to be rebuilt on `siglongjmp`,
  and the register freeze the debugger reads has to be filled from `uc_mcontext` instead of a
  trap frame. That is a genuinely useful second implementation of a thing we rely on.
- **Position independence.** `jit.hc` hardcodes `JIT_BASE 0x84000000` / `JIT_END 0x84F00000`.
  `mmap` gives an arbitrary address, so the hosted port cannot keep a fixed base. We already
  learned the underlying lesson once — the guest RV JIT runs from a `MAlloc` heap, so its jump
  tables must be PC-relative deltas rather than absolute pointers — and this turns that
  invariant into something a second platform enforces rather than something we remember.
- **The red zone.** SysV AMD64 has a 128-byte red zone below `sp`; AAPCS64 does not. The asm
  REPL's stepper keeps a private `asm_stack` and parks `sp`, `ra` and `s0` around each stepped
  instruction, which is exactly the code that a red zone would quietly invalidate.

### 1.2 It takes QEMU out of the inner loop

Every image in `tests/exec` parks in `wfi` after `main` returns and never powers off, so each
smoke waits out its own `timeout` — `kernel-span` alone burns 300 seconds of wall clock on a
**passing** run, and a full `qemu-integration` is roughly 100 minutes. A hosted JIT makes "run
this HolyC and tell me the answer" a millisecond operation.

That is what makes [VERIFICATION_PLAN.md](VERIFICATION_PLAN.md) affordable. Its §1.1
catalog-driven generator and §2.1 host-compiler fuzzing are both described there as cheap; they
are cheap *per case*, and the case count is what makes them valuable. A thousand generated cases
per instruction is a nightly job under QEMU and an interactive one hosted.

### 1.3 It gives the multi-arch seam a native referee

`host/holyc_target.h` is built for rv64/rv32 now, with `HOLYC_ARCH_AARCH64` a comment. An
AArch64 backend validated on *this machine* is checkable against the hardware itself rather than
against an emulator's model of it. Emulators are lenient in specific ways that matter to us —
QEMU permits misaligned access that real boards fault on, which `lh`'s own catalog entry already
warns about.

---

## 2. What this is not

`MULTIARCH.md` §1 lists "growing `bootstrap/hc_repl/jit.hc` for new arches" as a near-term
non-goal, and this project does not overturn that — it is deliberately scoped as a **second
host for the existing JIT**, not a second guest runtime and not a per-ISA fork of `jit.hc`.

Also not in scope: TempleOS-on-Linux as a product, Adam/DolDoc/graphics/windowing hosted, a
libc-shaped guest runtime, or binary compatibility between the hosted and bare-metal builds.

---

## 3. Staging

Mirrors the P0..P4 shape `MULTIARCH.md` uses for RV32, so the two plans read the same way.

### H0 — execute one page

`mmap` a page with the right platform incantation, write a handful of instructions that return
a constant, invalidate the i-cache, call it through a function pointer, check the value. No
HolyC yet. This is small and it is where every platform difference in §1.1 first bites; do it on
both platforms before writing anything else.

**Gate:** `make hosted-jit-h0` returns 42 on Linux x86-64, Linux arm64 and macOS arm64.

### H1 — the oracles, hosted

Point the existing execution oracles at the hosted JIT. `tests/exec/cases` already holds 88
oracle-checked cases with known answers, which is a conformance suite we do not have to write —
the same HolyC must produce the same value hosted as it does under QEMU.

**Gate:** all 88 agree between the rv64 path and the hosted path. Disagreement is the interesting
output: it is either an ABI bug in the new backend or a latent assumption in the old one.

### H2 — varargs and the calling convention

The §1.1 item most likely to find real bugs. Drive `Print`/`StrPrint`/`StrPrintJoin` and the
string-statement lowering across SysV, AAPCS64 and Darwin arm64, including the stack-varargs
difference.

**Gate:** a generated property — random argument vectors of mixed `I64`/`F64`/pointer/string
produce identical formatted output on every host and under QEMU.

### H3 — traps and the debugger

Signal handlers, `ucontext` register capture, recover-to-the-prompt. Fill the same freeze the
debugger already reads so `Regs`, `DbgX` and the register pane work unchanged.

**Gate:** a deliberate null dereference reports the faulting address and returns to the prompt,
on both platforms, and the pane shows the same registers it would under QEMU.

### H4 — the generators move in

Run VERIFICATION_PLAN §1.1–§1.3 at the case counts that were previously impractical.

---

## 4. Risks worth naming before starting

- **Two ways to be wrong about the ABI.** If the hosted backend and the checker share an
  assumption, they agree and are both wrong. The mitigation is that the oracle values in H1 come
  from the *existing* rv64 path, which was written against a different convention entirely.
- **macOS entitlements and code signing** can make `MAP_JIT` fail in ways that look like a
  codegen bug. Prove H0 on a bare `mmap` before trusting any later failure.
- **Scope creep toward a Linux port.** The moment it can run HolyC, it will be tempting to give
  it files, a console and threads. §2 is the boundary; a hosted run that needs more than
  stdin/stdout/exit has left the project.
- **A second build matrix.** Three host triples is already more CI than this repo runs today,
  and `qemu-integration` is 100 minutes. H0/H1 should be fast enough to run per-commit; anything
  slower belongs in the nightly job VERIFICATION_PLAN §5 already calls for.
