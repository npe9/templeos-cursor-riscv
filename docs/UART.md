# UART / serial console (primer + this repo)

Teaching note for developers new to embedded / OS work. Covers **history**,
**how a UART works**, and **flow control** as implemented here.

Related: [CONSOLE.md](CONSOLE.md) (wishlist audit), [DRIVERS.md](DRIVERS.md)
(board matrix), [REPL.md](REPL.md), [FILE_EXPORT.md](FILE_EXPORT.md),
[NINEP.md](NINEP.md) (prefer 9P over terminal bulk copy), [BAREMETAL.md](BAREMETAL.md).

---

## Why this matters here

This project’s primary “keyboard + screen” is often a **serial port**: QEMU
`-nographic`, USB-UART on a board, or OpenOCD’s UART bridge. The HolyC REPL,
`Print` / panic dumps, `DumpFile`, and soft debugger all share that **one byte
pipe**. Understanding UART speed, FIFOs, and flow control explains why a 1 GHz
hart can still lose console bytes — and why Ctrl-S/Ctrl-Q exist.

**Rule of thumb:** use the UART for a **console** (text, readline, short dumps).
For bulk file copy, prefer **virtio-9p** ([NINEP.md](NINEP.md)) or framed export
([FILE_EXPORT.md](FILE_EXPORT.md)) — not raw `Cat` / endless `Print` into a PTY.

---

## Short history

| Era | What happened | Why OS people still care |
|-----|---------------|---------------------------|
| **Telegraph / teletype** | Characters as timed pulses; operators and machines needed pause/resume conventions | Flow control and “line” thinking precede computers |
| **RS-232 (1960s)** | Voltage-level serial between DTE (computer) and DCE (modem); DB-25 then DE-9 | Connector myths live on; **RTS/CTS** / **DTR/DSR** are RS-232 *modem* wires |
| **UART chips** | Bit timing + shift registers in silicon (8250 → **16550** + FIFO) | Register maps you poke from drivers today |
| **PC COM ports** | IRQ + MMIO/PIO 16550 clones; BIOS and early kernels boot on COM1 | “ttyS0” culture; FIFO depth (~16) still the mental model |
| **SoC UARTs** | Same idea, different MMIO: DesignWare 8250-class, SiFive UART, UARTLite, … | Kconfig picks `RVUart16550` vs `RVUartSifive` vs … |
| **USB-serial / virtio** | Host sees `/dev/ttyUSB*` or QEMU chardev; guest still talks UART or a virtio console | CI uses QEMU’s emulated 16550; boards use real silicon or bridges |
| **HTIF (Spike)** | Not a UART — a tohost/fromhost mailbox that *looks* like a console | `RVUartHtif` on spike: console API, different wire |

Lineage in this tree: **NS16550A / DW8250-class** on QEMU `virt` and many boards;
**SiFive UART** on `sifive_u` / `sifive_e`; **HTIF** on spike; others (Shakti,
UARTLite, Ibex) via the same `RVUart*` facade ([DRIVERS.md](DRIVERS.md)).

---

## How a UART works

### Byte pipe, not a network

A UART is a **asynchronous serial** endpoint: one wire (or pair) carries a stream
of **frames**, each usually one data byte. There is no packet header, no ACKs,
and no built-in “message” — just bits on a wire at an agreed **baud rate**.

```text
  CPU  ←→  TX/RX shift regs + FIFOs  ←→  line (TTL / RS-232 / USB-bridge)
                ↑
           MMIO registers
```

### Framing (what one character looks like on the wire)

Typical console setting **8N1** (8 data bits, no parity, 1 stop bit):

```text
  idle ──┐     ┌─── bit0 … bit7 ───┐     ┌── idle
         │start│   (LSB first)     │stop │
         └─────┘                   └─────┘
```

| Piece | Role |
|-------|------|
| **Start bit** | Always 0; tells the receiver “a byte is starting” |
| **Data bits** | Usually 8; sometimes 7 (+ parity) for old terminals |
| **Parity** | Optional error check (even/odd/none) — rarely used on modern consoles |
| **Stop bit(s)** | Always 1; gap before the next start bit |
| **Baud** | Symbol rate; for UART ≈ bits/sec on the wire. **115200** is common; bit time ≈ 8.7 µs |

Both ends must agree on baud and framing or you get garbage / framing errors.

### Shift registers and FIFOs

- **TX:** CPU writes a byte → hardware **shifts** it onto the line bit by bit.
- **RX:** hardware samples the line → assembles a byte → CPU reads it.
- **FIFO:** small hardware queue (classic 16550: **16** bytes each way) so the
  CPU need not service every single bit interrupt.

| Failure | Meaning |
|---------|---------|
| **Overrun** | RX FIFO full; new byte arrives → **dropped**. CPU too slow or IRQ off. |
| **Underrun** | TX starved (less visible on simple polled PutS). |

### Why a fast CPU still floods a terminal

At **115200 baud**, payload throughput is on the order of **~10 kB/s** (8N1 ≈
10 bits/byte on the wire). A hart at hundreds of MHz can fill that pipe in
microseconds of software time:

- Panic / `TrapDump` / long `Print`
- `DumpFile` base64 (~4/3 expansion)
- Editor redraw / `DMesg`

The **host PTY**, terminal emulator, or USB-serial bridge may buffer — then
stall. Without **flow control**, the guest keeps writing; the 16550 TX path
blocks on THRE, but RX on the *host* side (or intermediate buffers) can still
lose data the operator cares about. Flow control asks the **sender** to pause.

### MMIO: classic 16550 register sketch

QEMU `virt` places a 16550-compatible UART at `MEM_UART` / `CONFIG_UART_BASE`
(often `0x10000000`). Byte offsets (when `CONFIG_UART_REG_SHIFT=0`):

| Offset | Name | Use in this tree |
|--------|------|------------------|
| 0 | **THR** (write) / **RBR** (read) | Put byte / get byte |
| 1 | **IER** | IRQ enable (legacy REPL: RX data for Ctrl-C) |
| 5 | **LSR** | Line status: bit0 **DR** (data ready), bit5 **THRE** (TX holding empty) |

Word-spaced maps (`REG_SHIFT=2`, JH7110 / Xiangshan / Icicle) multiply the index
by 4; Kernel `RVUart16550` uses `U32` in/out so THRE waits see real LSR.

**Polling (what PutS usually does):** spin until `LSR.THRE`, write THR; spin
until `LSR.DR`, read RBR.

**Interrupts:** IER + PLIC so RX can wake `wfi` (Ctrl-C / break). Soft RX rings
(`bootstrap/seed/uart.hc`, `bootstrap/hc_repl/uart.hc`) drain the HW FIFO into a larger
software queue so keys are not lost during long TX.

### Why the OS / REPL cares

1. **Console identity** — early bring-up before FB/virtio.
2. **Shared medium** — readline, dumps, dbg, and logs contend for one stream
   ([CONSOLE.md](CONSOLE.md)).
3. **Speed mismatch** — needs FC or a better channel for bulk data.
4. **Board diversity** — same `PutS`/`GetC` API, different silicon
   ([DRIVERS.md](DRIVERS.md)).

---

## Flow control

Flow control answers: *who may send, and when?*

### Software: XON / XOFF (in-band)

Special bytes in the **same** data stream:

| Byte | Key | Name | Meaning |
|------|-----|------|---------|
| `0x13` | Ctrl-S | **XOFF** (DC3) | Receiver asks sender: **pause TX** |
| `0x11` | Ctrl-Q | **XON** (DC1) | Receiver asks sender: **resume TX** |

```text
  Host (terminal)                    Guest (UART Put / PutS)
       |                                    |
       |  ── lots of console text ──►       |
       |                                    |
       |  ◄── XOFF (0x13) ────────────────  |  (host buffer full / user pause)
       |                                    |  guest sets tx_paused, stops THR writes
       |  (guest TX silent; still polls RX) |
       |  ◄── XON  (0x11) ────────────────  |
       |                                    |  clear pause; resume Put
       |  ── remaining text ──────────►     |
```

**Who sends what (this project’s console model):** the **host** (operator or PTY
tool) sends XOFF/XON; the **guest** honors them by pausing **TX**. The guest
does **not** currently emit XOFF when its own RX ring fills (asymmetry — see
limits).

### Hardware: RTS / CTS (out-of-band)

RS-232 modem wires (simplified):

| Signal | Direction (classic) | Idea |
|--------|---------------------|------|
| **RTS** | DTE → DCE | “I want to send” / ready |
| **CTS** | DCE → DTE | “OK to send” |
| **DTR / DSR** | presence / “device ready” | Often ignored by bare UARTs |

No data bytes consumed — good for **binary**. QEMU virt **emulates** MCR/MSR,
but **stdio/PTY chardevs ignore TIOCM** — RTS does not throttle the host; CTS
stays asserted. **Status: soft stub APIs** (`UartRtsCts` / `RVUartRtsCts`) —
honest **no-op on virt** (flag only; Put does not wait on CTS).

### Interaction with line discipline and binary protocols

| Mode | FC behavior |
|------|-------------|
| Interactive REPL / `Print` | XON/XOFF **on** by default — Ctrl-S pauses bulk TX |
| Panic / long dump | Same — host can pause; don’t leave XOFF stuck |
| **ZMODEM / trzsz** | Auto **`UartXonXoff(0)`** — `0x11`/`0x13` are protocol bytes |
| Raw binary over UART | Disable FC or escape; otherwise false XOFF stalls forever |
| Virtio-9p | Separate channel — prefer for files ([NINEP.md](NINEP.md)) |

---

## This repo — shipped vs WIP

| Mechanism | Status | Where |
|-----------|--------|--------|
| Software **XON/XOFF** | **Shipped** (16550 console paths) | Seed `uart.hc`, `hc_repl/uart.hc`, Kernel `RVUart16550` |
| Enable / disable API | **Shipped** | `UartXonXoff` / `RVUartXonXoff` (default **on**) |
| Smoke | **Shipped** | `make repl-uart-xon-pty` |
| Auto-disable for ZMODEM/trzsz | **Shipped** | `zmodem.hc` / `trzsz.hc` save/restore FC |
| Guest→host XOFF when RX full | **Missing** | Host can still overrun guest RX under extreme flood |
| **RTS/CTS** | **Soft stub** | `UartRtsCts` / `RVUartRtsCts` — **no-op on virt** (MCR/MSR unused in Put) |
| Shared FC on SiFive / HTIF / UARTLite / … | **Missing** | Those `RVUart*` PutS paths have no XON/XOFF yet |

Gap tracker: [GAPS.md](GAPS.md) **G26** (SW done; RTS/CTS stubbed). Console audit:
[CONSOLE.md](CONSOLE.md) §12.

### Which UARTs honor XON/XOFF

| Path | Honors FC? | Notes |
|------|------------|--------|
| Seed blob REPL (`bootstrap/seed/uart.hc`) | **Yes** | Shared slots `0x870010F0` (fc) / `0x870010F8` (tx paused); IRQ + Put drain. The C half of this pair (`worry_dream_repl.c`) is **deleted** — the slots remain because the seed still uses them |
| Product `repl-holyc` / `hc_repl` | **Yes** | BSS `UartFc` / `UartTxPaused`; soft RX ring |
| Kernel `RVUart16550` | **Yes** | `RVUartFc` / `RVUartTxPaused`; **FC poll drops non-FC RX** (no ring) |
| `RVUartSifive`, `RVUartHtif`, `RVUartShakti`, `RVUartUartlite`, `RVUartIbex`, stub | **No** | Console PutS only today |

### Call path (16550)

**TX pause check** — every put:

1. Drain RX (see XOFF/XON early).
2. While FC enabled **and** `tx_paused`: keep draining RX (wait for XON).
3. Wait `LSR.THRE`; write **THR**.

**RX** — drain / get:

1. Read **RBR** while `LSR.DR`.
2. If FC on and byte is XON/XOFF → update pause flag; **do not** enqueue to readline.
3. Else enqueue / return to caller.

```text
  Host Ctrl-S
       │
       ▼
  RBR ──► UartFcIsCtrl / uart_fc_is_ctrl ──► UartFcNote (tx_paused=1)
       │
       ▼
  UartPut / RVUartPutS ── while (fc && tx_paused) ── poll RX ── wait XON
       │
  Host Ctrl-Q ──► tx_paused=0 ──► THR writes resume
```

### Key APIs / knobs

| API | Role |
|-----|------|
| `UartXonXoff(1)` / `UartXonXoff(0)` | Enable / disable SW FC (seed + `hc_repl`) |
| `UartFcGet()` | Current SW enable flag |
| `UartPut(ch)` | Raw byte out — drains RX, waits out XOFF, then pokes THR |
| `UartRtsCts(1\|0)` / `UartRtsCtsGet` | HW FC stub — **no-op on virt** |
| `UartFcNote` / `UartFcIsCtrl` | Internal: classify & apply XON/XOFF |
| `RVUartXonXoff(on)` / `RVUartRtsCts(on)` | Kernel 16550 twins |
| Shared slots (legacy C ↔ HolyC) | `0x870010F0` fc, `0x870010F8` tx paused |

Manual test: during `DumpFile("boot.hc");` or a long `UartStr`, type **Ctrl-S**
on the host PTY (TX should stall), then **Ctrl-Q** (resume). Automated:

```bash
make repl-uart-xon-pty
```

(`tests/scripts/run_repl_uart_xon_pty.sh` — runs `build/hc_repl.elf`, injects
XOFF mid-payload, asserts the EOT marker does not arrive until XON.)

The XON/XOFF entry points above are **prompt-callable on `repl-holyc`**:
`UartPut`, `UartXonXoff`, `UartFcGet`, `UartRtsCts` and `UartRtsCtsGet` are
JIT-registered in `bootstrap/hc_repl/repl.hc`. Loops around them have to live
in a function body (`U0 Blast(){for(…)…}`) — the thin `JitTry` has no toplevel
`while`/`for`, and `jit.hc` is deliberately not growing one.

### Limits / pitfalls

- **Binary xfer** must `UartXonXoff(0)` (ZMODEM/trzsz do this) or escape DC1/DC3.
- **Don’t XOFF forever** — guest TX spins in drain; looks like a hang.
- Kernel PutS FC poll **drops** non-control RX bytes (no soft ring) — fine for
  print-only plat smokes; not a full TTY.
- Non-16550 Kernel UARTs: no shared FC yet — Ctrl-S is just data (or ignored).
- Prefer **9P / framed dump** for files; FC is a safety net for console floods,
  not a file-transfer protocol ([NINEP.md](NINEP.md), [FILE_EXPORT.md](FILE_EXPORT.md)).
- `UartRtsCts(1)` on virt changes nothing about Put behavior — use XON/XOFF.

---

## Drivers in this tree (pointers)

| File | Role |
|------|------|
| `bootstrap/seed/uart.hc` | HolyC 16550 + XON/XOFF + shared ring (full UART REPL blob) |
| `bootstrap/hc_repl/uart.hc` | Thin HolyC 16550 + soft ring + FC (`repl-holyc`) |
| `Kernel/Drv/RVUart.HC` | Includes Kconfig-selected impl |
| `Kernel/Drv/RVUart16550.HC` | NS16550A / DW8250 + `RVUartXonXoff` |
| `Kernel/Drv/RVUartSifive.HC` | → `RVSifivePlat` (no FC yet) |
| `Kernel/Drv/RVUartHtif.HC` | Spike tohost/fromhost console |
| `Kernel/Drv/RVUart{Shakti,Uartlite,Ibex,Stub}.HC` | Other boards / placeholders |

Board ↔ UART kind: [DRIVERS.md](DRIVERS.md), [PLATFORM.md](../templeos-riscv/PLATFORM.md).

---

## Terminal size / type (not a UART register)

The UART carries bytes only — **rows, columns, and TERM name live in software**
(`bootstrap/seed/term.hc`). Defaults: **80×24**, name **`ansi`**.

| Who | How |
|-----|-----|
| Guest (HolyC) | `TermSize(80,24);` (cols, rows); `TermSetName("xterm");` `TermRep;` |
| Guest query | `TermQuery;` / `TermProbe;` — DSR CPR + `ESC[18t` (needs host PTY) |
| Host push | `ESC[8;rows;cols t` or OSC `ESC]777;cols;rows;name BEL` while probe/editors own RX |

Editors (`Vi` / `EditHoly`) call `TermProbe` then use `TermRows`/`TermCols`
(HolyC soft RX on `hc_repl`; same CSI as former worry_dream C). Piped CI keeps
defaults (no emulator reply). Full protocol: [CONSOLE.md](CONSOLE.md)
§ Terminal size / type negotiation. Smoke: `make term-probe-pty`.

---

## See also

- [FLOW_CONTROL.md](FLOW_CONTROL.md) — short ops sheet (same FC facts, denser tables)
- [CONSOLE.md](CONSOLE.md) — TTY / mux / size / FC wishlist
- [NINEP.md](NINEP.md) — remote FS; don’t abuse the console for bulk copy
- [FILE_EXPORT.md](FILE_EXPORT.md) — `DumpFile` / ZMODEM / trzsz + Ctrl-S tip
- [REPL.md](REPL.md) — interactive UART REPL
- [GAPS.md](GAPS.md) — G26 (SW done; RTS/CTS stub no-op on virt)
