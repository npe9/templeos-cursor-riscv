# UART flow control (XON/XOFF + RTS/CTS)

Operator / API sheet for this RISC-V TempleOS / HolyC tree.

**Teaching primer** (history, framing, FIFOs, baud, RTS/CTS concepts):
**[UART.md](UART.md)**. Wishlist: [CONSOLE.md](CONSOLE.md) §12; drivers:
[DRIVERS.md](DRIVERS.md). Prefer **9P** for bulk files ([NINEP.md](NINEP.md)),
not raw terminal floods.

## Why it exists (short)

A 16550 can push bytes faster than a slow PTY or dump decoder can drain.
Without FC, **panic dumps**, `DumpFile`, and long `Print` lose characters.

| Kind | Wire signal | This tree |
|------|-------------|-----------|
| **Software** XON/XOFF | In-band: XOFF=`0x13` (Ctrl-S), XON=`0x11` (Ctrl-Q) | **Shipped** on virt 16550 paths |
| **Hardware** RTS/CTS | Extra modem lines (MCR/MSR) | **Soft stub** — **no-op on QEMU virt** |

XON/XOFF must **not** reach readline when FC is on (consumed in the drain path).
`hc_repl` drains into a **soft RX ring** during Put / XON wait so keys are not
dropped (Kernel `RVUartFcPoll` still drops non-FC RX — no ring there).

## Behavior (guest TX) — software FC

```text
host types Ctrl-S  →  guest sees XOFF  →  UartPut / RVUartPutS spin (drain RX)
host types Ctrl-Q  →  guest sees XON   →  TX continues
```

1. Every put path drains RX (so the 16550 FIFO cannot overflow while we TX).
2. If software FC is **enabled** and the shared/local **paused** flag is set,
   put blocks in a drain loop until XON clears it.
3. XON/XOFF are **consumed** in the drain path — not enqueued to the readline
   ring (seed + C IRQ + `hc_repl` soft ring).

Guest → host XOFF (pause the *host* when our RX ring fills) is **not** sent
today; only host→guest pause of guest TX is honored.

## Hardware RTS/CTS (stub)

QEMU’s 16550 **emulates** MCR (RTS/DTR) and MSR (CTS/DSR/…). On **virt** with
`-serial stdio` / PTY, the chardev returns `-ENOTSUP` for TIOCM: **RTS writes
do not throttle the host**, and **CTS stays asserted**. Gating `UartPut` on
`MSR.CTS` would be a silent no-op (or a hang risk on boards with floating
modem lines).

So this tree ships **honest soft stubs** only:

| API | Effect on virt |
|-----|----------------|
| `UartRtsCts(1\|0)` / `UartRtsCtsGet` | Records intent flag (`UartHwFc`); **does not** wait on CTS |
| `RVUartRtsCts(1\|0)` / `RVUartRtsCtsGet` | Same for Kernel 16550 (`RVUartHwFc`) |

Independent of XON/XOFF — enabling the stub does **not** disable software FC.
Real boards with wired RTS/CTS need a future driver that asserts MCR.RTS and
waits on MSR.CTS in Put (not shipped).

## How to enable / disable

| Image / API | Default | Knob |
|-------------|---------|------|
| Legacy REPL + seed `uart.hc` | SW FC **on** (after `Run`) | `UartXonXoff(1\|0)`; `UartFcGet` |
| Product `hc_repl` | SW FC **on** (`UartFc`) | same `UartXonXoff` / `UartFcGet` |
| Kernel `RVUart16550` | SW FC **on** | `RVUartXonXoff(1\|0)`; `RVUartFc` / `RVUartTxPaused` |
| Any of the above | HW FC **off** (stub) | `UartRtsCts(1\|0)` / `RVUartRtsCts` — **no-op on virt** |

Binary protocols that may carry `0x11`/`0x13` as data **must** turn SW FC off
for the session. **ZMODEM** and **trzsz** already save/restore via
`UartXonXoff(0)` around `ZmodemBegin` / `TrzszBegin`.

Manual check: during a long `DumpFile("…");` or `Print` flood, type **Ctrl-S**
on the host PTY (output should stall), then **Ctrl-Q** (resume).

Automated: `make repl-uart-xon-pty` (legacy `repl.elf`, virt 16550; PTY clears
host IXON and injects XOFF/XON). Requires a healthy seed boot so `UartPut` /
`UartXonXoff` are defined — if boot aborts (OOM / fault mid-seed), the smoke
cannot exercise FC (interactive `1+1;` may still work).

## Which UART paths honor FC

| Path | XON/XOFF? | RTS/CTS? | Notes |
|------|-----------|----------|--------|
| `bootstrap/seed/uart.hc` | **Yes** | Stub (`UartRtsCts`) | Shared SW state @ `0x870010F0` / `0x870010F8` |
| `bootstrap/worry_dream_repl.c` | **Yes** | — | Same SW addresses; IRQ drain syncs pause |
| `bootstrap/hc_repl/uart.hc` | **Yes** | Stub | Soft RX ring during Put / XON poll (keys kept) |
| `Kernel/Drv/RVUart16550.HC` | **Yes** | Stub (`RVUartRtsCts`) | `RVUartFcPoll` **drops** non-FC RX (no ring) |
| SiFive / HTIF / Shakti / Uartlite / Ibex / Stub | **No** | **No** | No shared FC layer yet |

`Print` / panic-ish UART on the REPL goes through HolyC `PutCh` → `UartPut`
after seeds load, so SW FC applies. Kernel plat smoke prints go through
`RVUartPutS` when the selected driver is 16550.

## Implementation notes (exact)

### Shared host-slot state (legacy seed + C)

| Address | Meaning |
|---------|---------|
| `0x870010F0` (`UART_FC_ADDR` / `HC_SLOT_UART_FC`) | `I64` — nonzero = software FC enabled |
| `0x870010F8` (`UART_TX_PAUSED_ADDR` / `HC_SLOT_UART_TX_PAUSED`) | `I64` — nonzero = TX paused (saw XOFF) |

`HostSlotsInstall` seeds fc=1, paused=0. Seed `uart.hc` also writes those on
`Run("uart.hc")`. HW stub state is BSS (`UartHwFc` / `RVUartHwFc`), not a host
slot.

### HolyC APIs (REPL)

```text
U0 UartXonXoff(I64 on);   // 1 = on, 0 = off (clears paused)
I64 UartFcGet();          // current SW enable flag
U0 UartRtsCts(I64 on);    // HW FC intent — soft no-op on virt
I64 UartRtsCtsGet();      // nonzero if UartRtsCts(1) was requested
U0 UartPut(I64 ch);       // drains; waits while SW-paused; THRE; poke THR
U0 UartRxDrain();         // FIFO → ring; XON/XOFF → pause flag only
```

Helpers (not Man topics): `UartFcNote`, `UartFcIsCtrl` (seed / hc_repl).

### Kernel APIs (16550 only)

```text
U0 RVUartXonXoff(I64 on);
U0 RVUartRtsCts(I64 on);  // soft stub — no-op on virt
I64 RVUartRtsCtsGet();
U0 RVUartFcPoll();        // drain RBR; update RVUartTxPaused; drop non-FC RX
Bool RVUartPutS(U8 *st);  // poll + wait paused + THRE via RVUartIn(5)
```

**REG_SHIFT=2:** never poke LSR/THR with byte loads on word-spaced maps
(Xiangshan / Mars / Icicle) — `RVUartIn`/`Out` already choose U32 vs U8.

### Constants

| Name | Value |
|------|-------|
| XON / DC1 / Ctrl-Q | `0x11` |
| XOFF / DC3 / Ctrl-S | `0x13` |
| 16550 MCR offset / RTS bit | `4` / `0x02` (emulated; unused by stub Put) |
| 16550 MSR offset / CTS bit | `6` / `0x10` (emulated; unused by stub Put) |

## Limits and failure modes

- **RTS/CTS on virt is a stub** — flag only; no MCR poke, no CTS wait in Put.
- When SW FC is on, Ctrl-S/Ctrl-Q are **not** available as literal input to
  editors / readline (turn FC off if you need those bytes).
- Kernel `RVUartFcPoll` during `PutS` **drops** non-FC RX (no ring) — fine for
  plat smoke / panic print; bad if you expect GetLine concurrent with PutS.
  Product `hc_repl` Put drains into a soft ring instead (keys preserved).
- Non-16550 Kernel UART selections ignore these APIs.
- Host must actually send XOFF (terminal IXOFF / manual Ctrl-S). QEMU `-serial
  stdio` with a raw PTY in CI does; some GUI consoles may swallow Ctrl-S.
- **PTY gotcha:** host line discipline **IXON** can emit real XOFF into the guest
  during boot floods and freeze `UartPut` forever. CI PTY smokes clear
  `IXON|IXOFF|IXANY` on the PTY (`run_repl_uart_echo_pty.sh`,
  `run_repl_uart_xon_pty.sh`) and inject XOFF only when testing FC.
- Turning SW FC off mid-pause clears the paused flag (`UartXonXoff(0)`).

## See also

- [UART.md](UART.md) — history / how UART works / FC concepts
- [CONSOLE.md](CONSOLE.md) — wishlist #12 + short API table
- [NINEP.md](NINEP.md) — prefer 9P over terminal bulk copy
- [FILE_EXPORT.md](FILE_EXPORT.md) — DumpFile / overrun notes
- [GAPS.md](GAPS.md) — G26 (SW done; RTS/CTS stubbed no-op on virt)
- `tests/scripts/run_repl_uart_xon_pty.sh` — automated pause/resume check
