# A3 / G7 flip — draft diff notes (DO NOT APPLY YET)

Scaffolding only. **Do not** merge these Makefile / CI edits until
`make a3-flip-check` prints **READY** and [SELF_HOST.md](SELF_HOST.md) G7 blockers
are green or waived. ZMODEM / Fmt / Demo are waived. **G2 trap/Ctrl-C session** is
Done (`make trap-smoke` hard-requires Fault→`*** FAULT` / crash>→go, Break, Zap/Ecall,
Ctrl-C; also holyc-regression needles). **G3 livedrv Done** via Home/`livedrv.hc`
`PutS` rewrite (`livedrv `/`LIVEDRV `) — not char-walk JIT. Man cover uses
`Man("Regs")` (not `Man("Reg")`). Bt honesty needle is **`Bt (trap freeze)`** after
Fault (live `Bt;` without freeze = UART stub — trap lane). `REMAINING_BLOCKERS` has
no livedrv. Still run the full check + `bootloader-smoke` before applying this draft.

G2 install note (product path): `TrapInit` must call `TrapBareMtvec` whenever
`TRAP_VEC_OFF≠0` — do **not** gate on `FnAddr("TrapBareMtvec")` (asm labels are
absent from the thin JIT table; that skip left mtvec=0 and hung `Fault`).

Related: [GAPS.md](GAPS.md) **G7**, [CI.md](CI.md), [REGRESSION.md](../tests/REGRESSION.md).

---

## Intent

After flip:

1. Honesty path = HolyC only (`repl-holyc-smoke`, `repl-holyc-regression`, `repl-cmp-smoke`, `bootloader-smoke`).
2. Drop **required** legacy dual-run (`repl-smoke` / `repl-regression`) from `qemu-integration`.
3. Optionally delete `bootstrap/worry_dream_repl.c` (+ legacy `Makefile.repl` link path) in a follow-up once nothing else references it.
4. Keep `SKIP_REPL_LEGACY` out of GitHub Actions forever (variable becomes obsolete or means “legacy already gone”).

---

## Pre-flight (must be green)

```bash
make a3-flip-check          # smoke + holyc-regression + repl-cmp → READY
make bootloader-smoke       # A3 criterion 2 (not inside a3-flip-check)
make trap-smoke             # optional focused G2; also covered in holyc-regression
```

Clear `REMAINING_BLOCKERS` in `tests/scripts/run_a3_flip_check.sh` only when SELF_HOST
says those rows are done.

---

## Draft: `Makefile` `qemu-integration`

**Remove** the legacy branch (keep HolyC + bootloader; leave 9p / PTY / DumpChanges):

```diff
 	@$(MAKE) repl-holyc-smoke
 	@$(MAKE) repl-holyc-regression
 	@$(MAKE) bootloader-smoke
-	# Deprecated legacy C guest (worry_dream). Still required until A3 flip criteria.
-	# Local opt-out only: SKIP_REPL_LEGACY=1 make qemu-integration (CI must not set this).
-ifeq ($(SKIP_REPL_LEGACY),1)
-	@echo "NOTE: SKIP_REPL_LEGACY=1 — skipping deprecated repl-smoke/repl-regression (not for CI)"
-else
-	@$(MAKE) repl-smoke
-	@$(MAKE) repl-regression
-endif
 	@$(MAKE) repl-9p-smoke
```

**ZMODEM in qemu-integration:** today `zmodem-smoke` still runs on legacy `repl.elf`.
After flip either:

- drop `zmodem-smoke` from `qemu-integration` (G11 waived; DumpChanges already required), or
- keep it as **optional local** only (same as `trzsz-smoke`).

Draft preference: **remove** `zmodem-smoke` from the required list when dual-run drops;
keep `dump-changes-smoke`.

```diff
 	@$(MAKE) repl-uart-xon-pty
-	@$(MAKE) zmodem-smoke
 	@$(MAKE) dump-changes-smoke
```

**Help text:** demote `repl-smoke` / `repl-regression` to “local legacy only / scheduled delete”;
add `a3-flip-check` as the readiness gate (already wired in scaffolding).

---

## Draft: `.github/workflows/ci.yml`

**No env change required** if Makefile no longer invokes legacy — the existing step:

```yaml
run: make && make qemu-integration
```

already picks up Makefile behavior. **Do not** add `SKIP_REPL_LEGACY=1`.

Optional cleanup (same PR or follow-up): drop `run_repl_smoke.sh` /
`run_repl_regression.sh` from the shellcheck file list once those scripts are deleted
or marked archive-only.

---

## Draft: docs / AGENTS (same flip PR)

| File | Change |
|------|--------|
| [SELF_HOST.md](SELF_HOST.md) | Mark A3 **Done**; empty G7 blocker list; checklist item “Flip default honesty gate” checked |
| [GAPS.md](GAPS.md) | G7 → Done; critical-path note |
| [CI.md](CI.md) | Legacy row → deleted / optional local |
| [REGRESSION.md](../tests/REGRESSION.md) | Primary gate = `repl-holyc-regression` only |
| [AGENTS.md](../AGENTS.md) | `repl-smoke` / `repl-regression` no longer “required CI” |
| [REPL.md](REPL.md) | Dual-run wording → HolyC-only honesty |

---

## Follow-up delete (separate commit after CI green)

Not required for the first flip PR, but the end state:

- Delete or move under `bootstrap/archive/`: `worry_dream_repl.c`, legacy `startup.s` link bits used only by `Makefile.repl` guest C path.
- Retire `make repl-smoke` / `repl-regression` targets or point them at a archived recipe.
- Remove `SKIP_REPL_LEGACY` plumbing.

---

## Explicit non-goals of the flip PR

- Deleting Mac `host/*.c`
- Embedding ZMODEM into thin `repl-holyc`
- Growing `jit.hc`
- Retiring `templeos-smoke` (that is **G10** / A4)
