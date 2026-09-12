# `tools/uart_mux.py` dropped console output — two bugs, both silent

Found while trying to actually *use* the soft VT multiplexing (G25) rather than read
about it. Both are data-loss bugs, both invisible, and nothing in CI exercises this
tool — `make` has no target for it; the only check is its own `--selftest`, which
passed throughout because it tested the wrong path.

## Bug 1 — a literal `~` in console text truncated the rest of the session

`printf … | qemu … | cat` gave 3415 bytes. The same run through `uart_mux.py` gave
**1910**. Deterministic, byte-identical across runs.

Cause: the wire format uses `SYNC = 0x7E`, and there is exactly one `0x7E` in the whole
stream — at offset **1910**, the `~` in the REPL's own boot banner:

```
--- uptime ---
  up 0 s  (602D4 ticks @ ~10000000 Hz)
```

The parser took it as SYNC, read the next two bytes as a little-endian length
(arbitrary text → almost always > 256, so the "frame complete" test never fired),
buffered the remaining ~1500 bytes to EOF, failed CRC, and `return`ed — **discarding
the buffer**. Every failure path in `_finish_frame` dropped its bytes.

Since the REPL prints that banner at boot, *every* muxed session lost everything after
it. Which is to say: the tool never worked on this image.

Fixed two ways:
- `_recover_raw()` — on any frame-validation failure, re-emit the original still-stuffed
  bytes (SYNC included) as console instead of dropping them.
- Early abort — once 3 bytes are buffered and the implied length exceeds 256, give up
  immediately rather than swallowing the stream to EOF. A real frame is ≤ FRAME_MAX (64).

Result: `| cat` and `| uart_mux.py` now agree at 3415 bytes.

## Bug 2 — soft VT banner detection could never match

`--vt-split` is documented to split sessions on "soft banners / framed `V\tN`". The
banner path was dead: `feed()` calls `_note_console_bytes(bytes([b]))` **one byte at a
time** on the raw path, and `VT_BANNER_RE` (`--- VT ([0-3]) \(`) is a multi-byte
pattern. A regex spanning 10 bytes cannot match a 1-byte input, ever.

This mattered more than it looks. Framed mode requires `UartMuxOn`, which **is not
reachable in the shipped `repl-holyc.elf`** — it lives in `Lib/frame.hc`, and
`Run("Lib/frame.hc")` does not register it (`Eval: not recognized`), matching GAPS.md
G22's "not in early boot Run". So the framed path is unavailable and the banner path
was broken, which is why VT splitting produced `vt1=0B vt2=0B` every time.

Fixed with a carry-over buffer (`_cons_pending`) so banners are matched across chunk
and call boundaries, holding back `VT_BANNER_HOLD` bytes for a straddling prefix, and
consuming a matched banner so a retained tail cannot re-match it.

Two ordering subtleties the fix had to get right, both caught by assertions:
- A **framed** VT switch is out-of-band relative to the pending console buffer, so it
  must flush pending first — otherwise bytes belonging to the VT being left are
  attributed to the one being entered.
- A matched banner must be **consumed** (`last = m.end()`), not just emitted, or the
  retained tail re-matches it on the next call. That inflated a 2-switch stream to 16.

## Why the selftest passed through all of this

`selftest()` builds a stream where the VT switches come from framed `encode_frame(0,
b"V\t1")` payloads. Those go straight to `_vt_switch` via `_finish_frame`, so
`vt_switches >= 2` and `b"side-session" in d.vt[1]` both held while the soft-banner
path — the only one that works on the real image — did nothing. The stream also
contained no bare `0x7E` outside a frame, so bug 1 never fired either.

Added a second selftest block that feeds a soft-banner-only stream **one byte at a
time**, including a bare `~`, and asserts the switches and per-VT content. That is the
shape the real REPL produces.

## Bug 3 (guest side) — `frame.hc` was compiled in but never published

`UartMuxOn();` answered `JIT: unknown fun UartMuxOn`, which looked like a missing
include. It was not: `bootstrap/hc_repl/repl.hc:13` has `#include
"/bootstrap/seed/frame.hc"`, so the code was in the image the whole time.

The REPL resolves names through an explicit table — `JitAdd("Name", &Name, argc,
is_void)` in `repl.hc` (~230 entries, `JIT_FUN_MAX` 384). Every `Vt*` from `console.hc`
is registered there; **nothing from `frame.hc` was**. Compiled, linked, unreachable.

`Run("Lib/frame.hc")` is not a workaround: `Run` does not register functions at all —
a trivial `U0 Zzz(){…}` written to `Tmp/` and Run'd is still `not recognized`.

Fixed by publishing the four entry points next to the `Vt*` block:

```c
JitAdd("UartMuxOn", &UartMuxOn, 0, 1);
JitAdd("UartMuxOff", &UartMuxOff, 0, 1);
JitAdd("UartMuxGet", &UartMuxGet, 0, 0);
JitAdd("FramePutStr", &FramePutStr, 2, 1);
```

Framed channels now work: `frames=4`, `pane=1|2`, `--vt-panes` renders side by side.

## The gate: `make mux-smoke`

Nothing in `make` referenced `uart_mux.py` — no target, no CI job — which is how three
bugs coexisted in the console stack while everything reported success. Added
`tests/scripts/run_mux_smoke.sh`.

Two runs, because the correct invariant differs:

- **Framing off** — the demuxer must be **byte-for-byte transparent**. This is the
  check that catches bug 1, and it is only meaningful because the boot banner contains
  a bare `~`, which the gate asserts. Soft banners must still split vt1/vt2, with a
  negative check that vt2's output does not leak into vt1.
- **Framing on** — parity no longer holds *by design* (framed packets are consumed, not
  echoed), so it asserts `frames>0`, `vt_sw=3` for three distinct switches (catching
  the framed+banner double-count), `pane=1|2`, and that `--vt-panes` renders.

Two traps the gate hit while being written, both worth keeping in mind:

- The first version compared byte counts **across two separate QEMU runs**. The banner
  prints an uptime tick count whose digit-length varies, so it flapped by one byte —
  which reads exactly like data loss. It now captures once and replays the same bytes.
- The first version asserted parity with framing **on**, which fails legitimately.

**Verified the gate actually catches the bugs**: restoring the original `uart_mux.py`
makes it fail with `plain=3352B muxed=1910B` plus both split failures; restoring the
fix makes it pass.

## Bug 4 — "redefine the stub" never worked, so ch3 was dead

`LogInfo(...)` produced nothing on framed ch3. `log.hc` declares a stub `LogMuxEmit`
and calls it from `LogEmit`; `frame.hc`, included immediately after, defines
`LogMuxEmit` again with the real `FrameSend(ch3, …)` body. The comment in `log.hc` said
"stub until frame.hc loads and redefines LogMuxEmit."

That is not how this image is built. `repl.hc` `#include`s both into **one AOT
translation unit**, so the call site in `log.hc` binds to the definition in scope at
that point — the stub — and `frame.hc`'s version is dead code. Nothing warned; the
channel was simply always empty.

Fixed with the idiom already used elsewhere in the same tree (`uart.hc`'s
`g_uart_putc_hook`, which `console.hc` installs for `VtCapture`):

- `log.hc` gains `U0 (*g_log_mux_hook)(I64, U8 *, U8 *)` and calls it from `LogMuxEmit`.
- `frame.hc` renames its body to `FrameLogMuxEmit` (with a forward declaration, since
  `UartMuxOn` takes its address before the definition) and installs it in `UartMuxOn`.

Now:

```
=== ch3 (log) ===
I	mux	framed ch3 works
W	mux	warn line
```

Worth noting the shape of this bug: **a comment described a mechanism that the build
does not provide**, and the code was written to match the comment.

So I audited the other "redefines" claims in the seed tree. The result is reassuring
but the reasoning is worth keeping:

| Claim | Verdict |
|---|---|
| `man.hc` "redefines" `DocFileFor` / `SymFile` / `SrcFile` / `SrcText` from `sym.hc` | **Fine.** `bootstrap/seed/sym.hc` is deliberately never included (`dbg_jit_sym.hc:3`: "do not include seed/sym.hc (Src clash with dir.hc)"). `man_sym.hc` also defines `DocFileFor` but has **no call sites of its own**, and every `DocFileFor(` call lives in `man.hc` *after* its own definition at line 405. No call site binds to the wrong one. |
| `ed.hc` / `edit.hc` / `str.hc` "redefines the C Ed / Edit / …" | Different mechanism — those replace **C host slots**, not a HolyC symbol in the same translation unit. Not this bug. |

The distinguishing question is always the same: **is there a call site that is compiled
before the "real" definition?** For `LogMuxEmit` there was (`log.hc`'s own `LogEmit`),
and that is exactly why it was the one that broke.

## Still open

Channels ch1 (FS) and ch2 (debugger) remain unexercised — nothing routes to them in a
plain REPL session. ch0 (console + VT/pane notifies) and ch3 (log) are gated by
`mux-smoke`.

There is still **no live TTY split**. `VtPane` records intent; `--vt-panes` renders at
EOF. Real tiling would need the guest to own the screen, which fights readline — the
reason `console.hc` says "layout intent only".
