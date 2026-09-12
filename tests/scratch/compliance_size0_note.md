# `make compliance` failed every case for three commits — a measurement bug

RESOLVED. Recorded because the failure was **silent in the worst way**: the gate ran,
printed 100 confident `FAIL … code size 0 < min 48` lines, and none of them were real.

## Symptom

Every case, all suites:

```
FAIL tests/holyc/compliance/c010_types_integers.hc (types) — code size 0 < min 48
FAIL tests/holyc/compliance/c011_types_bool_void_f64_decl.hc (types) — code size 0 < min 48
…
```

A compiler that emitted zero bytes for `I64 main() { … return a+b; }` would be
catastrophically broken, which is what the output implies. It was not: compiling that
same file by hand produced a healthy 1632-byte blob.

## Cause

Two correct-looking things that stopped composing.

- `tests/scripts/run_holyc_compliance.sh:110` measures generated code by parsing the
  compiler's stdout: `sed -n 's/.*Code size: \([0-9][0-9]*\).*/\1/p'`. It has invoked
  the compiler as `"$HOLYC" "$fpath" -o /tmp/…bin` since it was written (`a401dd4`).
- `host/main_stub.c:151` — **`-o <file>` sets `quiet = 1`**, and `quiet` suppresses the
  `Code size:` print.

So the line the runner parses was never emitted, `sz` fell back to 0, and 0 is below
every minimum. `git log -S` dates the `-o` → quiet association to **`080f729`**
("Delete worry_dream C guest and ship RV Adam/Win/ODE product WIP") — three commits
before HEAD. Neither file was locally modified; this was red in the committed tree.

## Fix

Opt-in size print, so no existing script's captured stdout changes shape:

```c
// host/main_stub.c, before the !quiet block
if (quiet && getenv("HOLYC_PRINT_SIZE"))
  printf("Code size: %lld bytes\n", cc->code_size);
```

and the runner sets `HOLYC_PRINT_SIZE=1` on its invocation.

**Result: 100 OK, 0 FAIL, 1 xfail_ok — nothing genuine was hiding.**

## The fix that looks obvious and is wrong

"Just `wc -c` the output file instead of parsing stdout." Tempting, and it removes the
coupling — but the emitted blob carries an import table and data, so even a trivial
case measures ~1.3-1.8 KB. Every case would clear a 48-byte minimum unconditionally and
the check would become **vacuous while still printing OK**. That is a worse failure than
the one being fixed, because it is invisible. The minimum only means something if it
measures `cc->code_size`.

## Worth noticing

The runner's fallback is `[ -n "$sz" ] || sz=0`. Defaulting a *measurement* to a value
that happens to be below every threshold is what turned "I could not measure this" into
"this failed." A sentinel that cannot be confused with a real reading — or an explicit
"could not parse size" error — would have made this self-diagnosing on day one.
