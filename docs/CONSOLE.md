# UART console stack (wishlist audit)

Honest map of this repo against a **UART-centric console** wishlist for a tiny
RISC-V OS. Prefer board / HolyC language; QEMU is the CI harness.

**Preferred architecture (target):**

```text
UART bytes
  → framing / demux
    → ch0  console TTY
    → ch1  9P / remote FS
    → ch2  debugger (GDB RSP or soft dbg)
    → ch3  log / dmesg
    → ch4  RPC / ops
  → host: /dev/ttyTarget, /mnt/target, gdb -ex 'target remote …'
```

**Today:** one raw UART byte stream shared by readline, editors, `Print`,
`$HC_DUMP$` / ZMODEM / trzsz, and (separately) virtio-9p. No channel mux.

Related: [UART.md](UART.md) (primer + XON/XOFF), [REPL.md](REPL.md), [DEBUGGER.md](DEBUGGER.md),
[FILE_EXPORT.md](FILE_EXPORT.md), [NINEP.md](NINEP.md), [OPS.md](OPS.md), [BAREMETAL.md](BAREMETAL.md),
[GAPS.md](GAPS.md), [SELF_HOST.md](SELF_HOST.md), [DRIVERS.md](DRIVERS.md).

---

## Image honesty (read this first)

| Guest | What it is | Console strength |
|-------|------------|------------------|
| **Legacy** `bootstrap/repl.elf` (`worry_dream_repl.c`) | Deprecated C guest + full seed blob | Richest TTY/readline/dbg/export; **required** CI until A3 flip |
| **Product** `repl-holyc` / bootloader-repl | HolyC AOT; zero host slots | UART + memfs + DumpFile; readline/trap/Regs **catching up** (G1–G5) |
| **Kernel plat / phase3** | HolyC kernel plat / StartOS subset | Print/oracle UART; not the REPL console stack |
| **WinMgr / FB** | `BOARD_FB.md` | Dual-console: FB + **UART dig-down** (`RVWinSerial`); not full REPL stack |

Claims below are **have** only when the capability works on at least one supported
image; notes call out legacy-only vs product.

---

## Have / partial / missing (1:1 wishlist)

| # | Wishlist item | Status | What exists | Gaps |
|---|---------------|--------|-------------|------|
| **1** | Line discipline / TTY (canonical/raw, echo, erase/kill, CR/LF, flow, ^C, ^D) | **partial** | HolyC `tty.hc`: canon/raw, echo, ICRNL, opt-in ONLCR, erase/`^U`/`^W`, empty `^D`→`TtyEofHit`+`ReplLoop` exit; mid-line cursor in `ReplReadLine`; soft RX; **XON/XOFF** (#12) | Legacy C readline separate; Tab mid-line still EOL-ish; RTS/CTS stub |
| **2** | Terminal capabilities (ANSI/VT100 cursor, clear, inverse, colors, size, keypad) | **partial** | `term.hc` + C twin: `TermGoto` / `TermClear` / hide cursor; CSI/SS3/OSC input; `TermSize` / `TermProbe` / `TermRows`/`Cols`/`Name`; inverse on C path (`\x1b[7m`); `TF_COLOR` flag | No full color API; no application keypad; size probe needs a cooperating host PTY (`term-probe-pty`); WinMgr ≠ VT |
| **3** | Decent shell (history, editing, completion, pipelines/redir, run without losing console) | **partial** | HolyC **REPL** *is* the shell: multi-entry history Up/Down (16-slot ring + hist_seed demos), Tab/`CompTab` (incl. `asm{}`), mid-line arrows (TTY), `Run`/`Src`/editors; eval returns to `>` | No pipelines / redir / job control; multiline unit recall / live defines = **G5** residual; FunPick interactive still legacy-stronger |
| **4** | Console multiplexing (tmux-like / multiple VTs over UART) | **partial** | Soft `Vt`/`VtAttach`/`VtDetach`/`VtNext`; opt-in `VtCapture` (Print/UartStr dual-write) + `VtKeys` (Ctrl-A); framed `V\tN`; host `--vt-follow`/`--vt-split` | No panes; capture/keys default off; FB WinMgr separate |
| **5** | Binary-safe framing (escaped channels: dbg/xfer/RPC ≠ console text) | **partial** | `frame.hc` + `tools/uart_mux.py` (off by default; `UartMuxOn`); ad-hoc `$HC_DUMP$` / ZMODEM remain | Console PutCh wrap / RX demux / ch1·ch2·ch4 payloads still stubs; not in early boot Run |
| **6** | Remote filesystem (9P / UART FS — prefer over ZMODEM) | **partial** | **Virtio-9p client**: `Mount9p` / `NineExport` / `Virtio9pWritePath`; smokes `repl-9p-smoke`, `kernel-virtio-9p-smoke` — teach: [NINEP.md](NINEP.md) | No **UART** 9P; needs virtfs; guest-as-9p-server explicitly non-goal ([GAPS.md](GAPS.md)); ZMODEM on thin image **waived** (G11) — DumpFile + 9P |
| **7** | Debugger transport (GDB remote: regs/mem/bp/step/continue/threads) | **partial** | **Soft UART dig-down** ([DEBUGGER.md](DEBUGGER.md)). **Guest UART RSP**: `GdbStub;` / `make gdb-uart-smoke` (`?`/`g`/`m`/`Z0`/`z0`/soft-`s`/`c`→S05, raw `$HC_GDB$`). **Host** QEMU `-gdb` (`hwdbg-smoke`) | ch2 round-trip WIP (`GdbUseMux` flag); no live resume while attached; no SMP RSP |
| **8** | Logging facility (dmesg ring, severity, ≠ stdout) | **partial** | Seed `log.hc`: ring + `Log*`/`DMesg`; `LogMuxEmit` → ch3 when `frame.hc` + `UartMuxOn` | No Print-style varargs `LogF` |
| **9** | Crash monitor (trap dump + md/mw/regs/bt/reboot) | **have** | `CrashDump`/`CrashMon`/`CrashOnTrap`/`Md`/`Mw` (`crash.hc`); Help/Man; `SetTrapFn(&CrashOnTrap)` at boot; G2 `TrapInitOnce` on first Fault/Break/SetTrap; FB twin `RVWinSerial`/`RVCrashMon*` | Kernel Panic/`Dbg` x86-era |
| **10** | System inspection (ps, mem, irqs, uptime, devices, mounts, counters) | **partial** | Seed `sys.hc`: `Sys` / `Uptime` / `MemRep` / `IrqRep` / `DevRep` / `Cnts` (+ Help/Man); also `MemMap` / CSR / `FsChanges` / `mtime` | No `ps` / task table; no mounts table; timebase fixed (`SYS_TIMEBASE`) |
| **11** | Clock + terminal size negotiation | **partial** | CLINT `mtime` / `TimerArm`; optional Goldfish RTC; **size/type:** guest `g_term_rows`/`cols`/`name` (default 80×24 / `ansi`); `TermSize(cols,rows)` / `TermSetName`; host push `ESC[8;rows;cols t` or OSC `777;cols;rows;name BEL`; optional `TermQuery`/`TermProbe` | Wall-clock sync API for console still missing; OSC/CSI push only while TermProbe/editors own RX |
| **12** | Flow control (XON/XOFF or RTS/CTS) for panic/bulk | **partial** | Software **XON/XOFF** on virt 16550: seed `uart.hc` / C `UartPut` / `hc_repl` / Kernel `RVUart16550` — host Ctrl-S pauses TX, Ctrl-Q resumes; `UartXonXoff(0)` for binary (ZMODEM/trzsz auto-disable). Smoke: `make repl-uart-xon-pty`. **RTS/CTS soft stub** (`UartRtsCts`) — no-op on virt | Stub only for HW FC (virt chardev ignores modem lines). Kernel PutS FC poll may drop non-FC RX (no ring); `hc_repl` soft ring preserves keys. SiFive/HTIF/other UARTs: no shared FC yet |
| **13** | Recovery/update (bootloader, image upload, checksum, flash, recover without JTAG) | **partial** | HolyC `bootloader` + payload ([BAREMETAL.md](BAREMETAL.md)); SafeMode/Recover/DumpChanges; known-good pins; OpenOCD/gdb load | UART **image upload → verify → flash** without JTAG not first-class; pristine seed reinstall still power-cycle/rebuild |

---

## Recommended add order

Aligns with the stated tiny-OS priority
(**TTY → shell → crash → GDB remote → framed/mux UART → remote FS → richer UI**),
adjusted for what already exists.

| Pri | Add next | Why now | Depends / demote |
|-----|----------|---------|------------------|
| **1** | ~~HolyC line discipline + readline parity~~ — **slice landed** (`tty.hc`) | Product path owns canon/raw/echo/erase/kill/CRNL | Deepen ^C/^D + mid-line; finish before new shell features |
| **2** | ~~Crash monitor on product path~~ — **done** (`crash.hc` / `CrashOnTrap`) | Soft dbg + HolyC trapvec | Smoke: `make trap-smoke` (Fault → crash> go) |
| **3** | **Framed multi-channel UART** (ch0 console, ch2 dbg, ch3 log; escape binary) | Unblocks safe dbg/xfer without eating the prompt; prerequisite for mux + UART FS | Reuse `$HC_*$` lessons; **before** more ZMODEM |
| **4** | **GDB RSP (or thin subset) on dbg channel** | User priority; host qemu-gdbstub does **not** help bare UART-only boards | **Partial raw UART** (`GdbStub` / `gdb-uart-smoke`: regs/mem/`Z0`/soft-step); ch2 TX reserved (`GdbUseMux`); keep soft `Regs`/`Bp` |
| **5** | **dmesg ring → ch3** | Panic/bulk without stomping TTY; pairs with FC later | Ring **done**; ch3 via `frame.hc` `LogMuxEmit` when `UartMuxOn` |
| **6** | **VT multiplexing** (2–N logical consoles over ch0) | Soft slice landed (`console.hc`); deepen after PutCh wrap | Soft done; panes/Ctrl-A later |
| **7** | **UART 9P or framed FS** (ch1) | Virtio-9p already covers “remote FS” when virtfs exists; UART FS for boards without virtio | After #3; ZMODEM on thin **waived** (G11) |
| **8** | ~~Flow control (XON/XOFF)~~ — **done** (SW); RTS/CTS **stub** (no-op virt) | Panic/bulk Dump — see #12 | Real RTS/CTS when boards wire pins |
| **9** | **Richer terminal UI** (colors, keypad, status) | Editors already ANSI-capable | After TTY solid |
| **10** | **UART recover/update** (upload + checksum + flash) | Bootloader exists; close JTAG-free loop | After framing or dedicated boot protocol |
| **11** | **/proc-like inspection** (`ps`, mounts) | Seed helpers mostly done (`sys.hc`); remaining = ps/mounts | Anytime |

### Demote / skip (already covered enough)

| Item | Why demote |
|------|------------|
| **ZMODEM / trzsz expansion on `repl-holyc`** | **Waived (G11)** — DumpFile + DumpChanges + virtio-9p cover operate-through; embed refused (~28 KiB / JIT risk) |
| **Duplicating host qemu-gdbstub features in-guest for virt CI** | Already have `hwdbg-smoke` + OpenOCD; invest in **UART** GDB instead |
| **Full POSIX job control / pipelines** | REPL-as-shell is the product; pipes are L later |
| **WinMgr as UART console substitute** | Explicit non-goal for this stack |
| **Guest-as-9p-server / TCP 9p** | Already [GAPS.md](GAPS.md) non-goal |
| **Full tmux feature parity** early | Start with channels + 2 VTs |

---

## Framed multi-channel UART (landed sketch)

Keep one physical UART. HolyC framing in `bootstrap/seed/frame.hc` + host
`tools/uart_mux.py`. **Off by default** (`g_uart_mux=0`); `UartMuxOn;` for
experiments. Not in `BootHolyCRuntime` before seal (JIT heap) — memfs
`Run("frame.hc");` after boot, or AOT-`#include` after `log.hc` (`repl-holyc`).

### Wire format

```text
SYNC=0x7E | stuffed( CH | LEN16le | PAYLOAD | CRC8 )
```

- Stuffing: `0x7D` then `(b^0x20)` for `0x7E` / `0x7D` in the stuffed region.
- CRC8 poly `0x07` init 0 over unstuffed `CH||LEN||PAYLOAD`.
- `CH`: 0=console, 1=FS/9P, 2=dbg, 3=log, 4=RPC. Payload cap `FRAME_MAX` (64).
- Raw bytes (no open frame) pass through as console (mux-off REPL compat).

### Guest APIs

| API | Role |
|-----|------|
| `UartMuxOn` / `UartMuxOff` / `UartMuxGet` | Flag + `g_log_mux_ch=3`; default off |
| `FrameSend(ch,buf,len)` / `FramePutStr` | Emit one frame (raw `UartPut`) |
| `FrameFsSend` / `FrameDbgSend` / `FrameLogSend` / `FrameRpcSend` | Channel stubs |
| `LogMuxEmit` | Stub in `log.hc`; **redefined** in `frame.hc` → ch3 `"L\tsub\tmsg"` |

### Host

```bash
python3 tools/uart_mux.py --selftest
qemu-system-riscv64 … -nographic 2>&1 | python3 tools/uart_mux.py -o /tmp/mux
# Guest after Run("frame.hc"); :
#   UartMuxOn; LogInfo("mux","ch3"); FrameDbgSend("+",1); UartMuxOff;
```

Writes `console` / `fs` / `dbg` / `log` / `rpc` under `-o`.

### Migration

1. Framing **off** by default; `UartMuxOn;` after `Run("frame.hc");`.
2. Move `DumpFile` / GDB onto ch2/ch4 later so console never sees base64.
3. Then deepen VT mux / UART 9P.

Do **not** grow `jit.hc` for this — seeds + host tools only
([SELF_HOST.md](SELF_HOST.md)).

### Limits

- No PutCh wrap yet (console stays raw until optional TX wrap).
- Guest JIT: do not `Run` `frame.hc` mid-boot before vim-budget seeds.
- No RX demux in guest yet; host demux only.
- ch1/ch2/ch4 stubs only (no UART 9P / GDB RSP payload yet).

---

## Soft VT multiplexing (landed stub)

Four logical consoles over one UART (`bootstrap/seed/console.hc`, CONSOLE.md #4 /
G25). **Default unchanged:** VT0 is the REPL; no PutCh wrap; no keybind steals
input. Boot loads after `frame.hc` (for optional framed notify).

### How to switch

At the `>` prompt (HolyC APIs — no Ctrl-A yet):

```text
Vt(1);                 // soft-switch to VT1 (banner + scrollback replay)
VtAttach(1);           // tmux-ish alias of Vt
VtDetach;              // soft detach → VT0 (REPL)
VtPutStr("side note"); // line lands in VT1 buffer and echoes
VtCapture(1);          // opt-in: Print/UartStr dual-write into current VT
Print("captured\n");
VtCapture(0);
VtKeys(1);             // Ctrl-A then 0-3 / n / p / d / l  (readline)
VtList;                // * marks active
VtClear;
VtNext;  VtPrev;
VtHelp;  Man("Vt");
```

With framed mux (optional):

```text
Run("frame.hc");       // if not already booted in
UartMuxOn;
Vt(2);                 // also FrameSend(ch0, "V\t2")
UartMuxOff;
```

Host sketch:

```bash
python3 tools/uart_mux.py --selftest
qemu-system-riscv64 … -nographic 2>&1 | python3 tools/uart_mux.py -o /tmp/mux --vt-split
# → /tmp/mux/vt0 … vt3 (banner + framed V\tN split) plus console/log/…
```

### Guest APIs

| API | Role |
|-----|------|
| `Vt(n)` / `VtAttach(n)` / `VtDetach` / `VtNext` / `VtPrev` | Soft-switch; banner + replay; detach → VT0 |
| `VtCur` / `VtCount` / `VtList` | Query / inventory (`* ` = active) |
| `VtPutStr` / `VtTitle` / `VtClear` | Session line buffer + title; wipe scrollback |
| `VtCapture(1\|0)` / `VtCaptureGet` | Opt-in PutCh hook: Print/UartStr → current VT scrollback (still UART) |
| `VtKeys(1\|0)` / `VtKeysGet` | Opt-in Ctrl-A prefix in `RlReadKey` (default off) |
| `VtHelp` / `VtInit` | Cheat sheet / idempotent init (VT0=`repl`) |
| `VtMuxNotify` | Internal: framed `V\tN` on ch0 when `UartMuxOn` |

### Limits

- **Panes** not implemented (split views).
- Ctrl-A prefix is **opt-in** (`VtKeys(1)`); default readline unchanged.
- `VtCapture` dual-writes only (never hides UART) — REPL primacy preserved.
- `Print` / `UartStr` capture via PutCh hook; `FrameSend` stays on raw `UartPut`.
- Scrollback: 6 lines × 48 chars × 4 VTs (flat arrays; stub-sized).
- Framed notify requires `frame.hc` + `UartMuxOn`; soft banners always work.
- UART serial REPL remains primary vs FB WinMgr — VT mux does not claim exclusive UART.

Smoke: boot `VtList` + early interactive `Vt(1)` / `VtPutStr` / `VtCapture` /
`VtDetach` needles in `repl-holyc-smoke` / `repl-smoke`. Host:
`python3 tools/uart_mux.py --selftest` (also `--vt-split` / `--vt-follow` / `--vt-status`).

---

## Line discipline APIs (`bootstrap/seed/tty.hc`)

CONSOLE wishlist #1. Canonical vs raw over the shared UART soft ring. Default
**canon + echo + ICRNL**. XON/XOFF stays in `uart.hc` (not owned here). Product
`ReplReadLine` / `RlReadKey` call the hooks; Tab/history remain in `readline.hc`.

| API | Role |
|-----|------|
| `TtyCanon` / `TtyRaw` / `TtyModeGet` | Line-editing on/off (`TTY_CANON` / `TTY_RAW`) |
| `TtyEcho(on)` / `TtyEchoGet` | Local echo for printable input |
| `TtyIcrnl(on)` / `TtyIcrnlGet` | Map CR → NL on input |
| `TtyOnlcr(on)` / `TtyOnlcrGet` | Opt-in NL → CR+LF via `TtyOutCh`/`TtyOutNl` (default **off**; does not wrap `PutCh`) |
| `TtyMapIn` / `TtyInCh` | Input map + blocking get (soft ring) |
| `TtyOutCh` / `TtyOutNl` | Output helpers (ONLCR-aware) |
| `TtyIsErase` / `TtyIsKill` / `TtyIsWerase` / `TtyIsEof` | Canon classifiers (BS/DEL, `^U`, `^W`, `^D`) |
| `TtyEofHit` / `TtyEofClear` / `TtyEofRaise` | Session-EOF sticky flag (empty-line `^D`) |
| `TtyEchoErase` / `TtyEchoKill` / `TtyEchoCh` | Visual erase / echo helpers |
| `TtyWeraseLen` | Word-erase byte count for a buffer |
| `Tty` / `TtyHelp` / `TtyInit` | Status dump / cheat sheet / defaults |

**Defaults:** erase=`BS` (DEL also), kill=`^U`, werase=`^W`, eof=`^D`, ONLCR off.
In canon: empty `^D` sets `TtyEofHit` and exits `ReplLoop` (`tty eof`); non-empty
`^D` submits the line. Mid-line Left/Right/Home/End/Delete + insert in
`ReplReadLine` (`g_rl_cur`); Tab/history remain in `readline.hc`. Raw disables
erase/kill/eof classifiers (echo/ICRNL/ONLCR stay as set).

### Limits

- Legacy C `repl_read_line_ex` is not rewritten (product path owns the slice).
- Mid-line Tab still completes as if at EOL (`CompCx = n`); G5 may deepen.
- `TtyOnlcr` does **not** wrap global `PutCh` (binary / DumpFile safe).
- RTS/CTS still stub (#12).
- Do not grow `jit.hc` — seed + AOT `#include` only.

Smoke: boot `Tty;` plus `TtyRaw`/`TtyCanon` / `TtyMapIn(13)` / `TtyEofHit` /
`TtyOnlcrGet` needles in `repl-smoke` / `repl-holyc-smoke`.

---

## Gap IDs (pointers into GAPS.md)

| Wishlist | Closest existing gap / note |
|----------|----------------------------|
| TTY + ^C on HolyC | **G2**, **G5** — line discipline slice in `tty.hc` |
| Soft dbg / crash on HolyC | **G1**, crash monitor **have** on product (`crash.hc`) |
| Framed mux / UART GDB / VT mux / FC | **G22–G26** — ring (**G24** partial); soft VT (**G25** partial) in `console.hc`; mux framing still open |
| /proc-ish Sys | **G27** — core in `sys.hc`; remaining ps/mounts |
| Remote FS | Virtio-9p **done**; UART FS after framing |
| ZMODEM on product image | **G11 waived** — DumpFile + 9P; no thin embed |
| Bootloader / recover | **G20** / [OPS.md](OPS.md) / [BAREMETAL.md](BAREMETAL.md) |

---

## Crash monitor APIs (`bootstrap/seed/crash.hc`)

CONSOLE wishlist #9 on product `repl-holyc`. Boot binds `SetTrapFn(&CrashOnTrap)`
(no mtvec until first use). First `Fault`/`Break`/`SetTrap` runs `TrapInitOnce` →
`TrapInit`, which keeps that handler (or defaults to `SetTrap("CrashOnTrap")` if
unset). Sync faults dump then prompt `crash>`; type `go` to abort eval back to `>`.
Breakpoints still go through `DbgTrap`. G2: `make trap-smoke` (Fault/Break/Ctrl-C).

| API | Role |
|-----|------|
| `CrashDump` | Print cause/PC/SP/regs + `Bt` + peek `@pc` / `MEM_TRAP_SNAP` |
| `CrashMon` | Interactive `crash>` (`md`/`da`/`mw`/`regs`/`bt`/`pc`/`dump`/`go`/`reboot`) |
| `CrashOnTrap` | Default handler: IRQ/ecall pass-through; ebreak→`DbgTrap`; else dump+mon |
| `CrashHelp` | Cheat sheet (incl. FB twin pointer) |
| `Md(addr,n)` / `Mw(addr,val)` | DRAM hex+ASCII dump / aligned I64 store |
| `CrashParseAddr` | `pc`/`sp`/`fp`/`ra`/`snap` aliases for monitor cmds |

**FB twin:** Kernel `RVWinSerial` + host `RVCrashMon`/`RVCrashMonInit` (`bootstrap/holy_rt.h`) — UART dig-down (`help`/`regs`/`bt`/`md`/`mw`/`fault`/`crash`) while WinMgr is up ([BOARD_FB.md](../templeos-riscv/BOARD_FB.md)). Same command vocabulary; not the AOT `repl-holyc` ExePutS path.

Smoke: `make trap-smoke` — Fault→dump→`crash>`→`go`→`after-fault`; Break; SetTrap/Ecall;
Ctrl-C (`after-ctrlc`). Dig-down: `Man("CrashMon")`; `Help` lists entry points.

---

## Logging APIs (`bootstrap/seed/log.hc`)

Separate from `Print` / `UartStr` (console) and from `FsLog` (memfs journal).

| API | Role |
|-----|------|
| `Log(level, subsys, msg)` | Append to ring (`LOG_INFO` / `LOG_WARN` / `LOG_ERR`) |
| `LogInfo` / `LogWarn` / `LogErr` | Convenience wrappers |
| `DMesg(n=0)` | Dump ring → UART (oldest→newest); `n>0` = last n |
| `LogClear` / `LogInit` | Wipe ring |
| `LogCount` | Records currently held |
| `LogNow` | Stamp helper (RTC ns → mtime → seq) |
| `LogMuxEmit` / `g_log_mux_ch` | Stub in `log.hc`; `frame.hc` redefines → framed ch3 when `UartMuxOn` |

Timestamps via `LogNow`: Goldfish RTC ns when `MEM_RTC` mapped (same latch as
`RVRtcReadNs`), else CLINT `mtime`, else seq. Smoke: `LogInfo`/`Warn`/`Err` then
`DMesg` needles in `repl-smoke` / `repl-holyc-smoke`.

---

## System inspection APIs (`bootstrap/seed/sys.hc`)

UART `/proc`-ish helpers (CONSOLE.md #10). No `ps` / mounts yet.

| API | Role |
|-----|------|
| `Sys` | One-shot dump: uptime + mem + irq + devices + cnts |
| `Uptime` / `UptimeTicks` / `UptimeSecs` | CLINT mtime since `SysInit` (~10 MHz virt) |
| `MemRep` | HolyC heap bump + freelist summary |
| `IrqRep` | PLIC base + UART IRQ + offsets (live peek after TrapInit; no CLAIM) |
| `DevRep` | `MEM_*` presence + driver hints |
| `Cnts` | dmesg depth, fs journal depth (`Reg("mcycle")` for CSR counters) |
| `SysHelp` / `SysInit` | Cheat sheet / pin boot mtime |

Smoke: `Sys;` needles in `repl-smoke` / `repl-holyc-smoke`. Dig-down: `Man("Sys")`;
`Help` lists the entry points.

---

## Terminal size / type negotiation (`bootstrap/seed/term.hc`)

Guest stores geometry + TERM-ish name (CONSOLE.md #11). Defaults **80×24** /
**`ansi`**. Editors (`Vi` / `EditHoly`) read `TermRows` / `TermCols`.

| API | Role |
|-----|------|
| `TermSize(cols, rows)` | Set geometry cols-first (stty-style); `TermSize(80,24)` |
| `TermSetSize(rows, cols)` | Rows-first (legacy / C bridge) |
| `TermRows` / `TermCols` / `TermFlags` | Accessors |
| `TermName` / `TermNameAnsi` / `TermNameXterm` | TERM-ish string (default `"ansi"`) |
| `TermSetName(s)` | Arbitrary name (AOT/repl-holyc; legacy REPL: use presets or OSC 777) |
| `TermRep` | Print `cols x rows` + name + flags |
| `TermQuery` / `TermProbe` | Optional host query (DSR CPR + `ESC[18t`) |
| `TermHelp` | Cheat sheet |

**Host → guest push** (while `TermProbe` / editors own RX):

```text
ESC [ 8 ; rows ; cols t                 # xterm window-size (rows, cols)
ESC ] 777 ; cols ; rows ; name BEL      # custom OSC: size + termname
```

**Guest → host query:** `TermQuery;` / `TermProbe;` — needs a real PTY
(`make term-probe-pty`). Piped QEMU smoke times out and keeps defaults.

Smoke: `TermSize` / `TermSetSize` cases in `repl-smoke`; PTY probe via
`term-probe-pty`. `Help` / `Man("Term")` / `TermHelp`.

---

## Software flow control (XON/XOFF)

Host **Ctrl-S** (XOFF `0x13`) pauses UART TX; **Ctrl-Q** (XON `0x11`) resumes. Default **on**.

- Primer (history / FIFOs / FC): **[UART.md](UART.md)**
- Operator APIs / path table: **[FLOW_CONTROL.md](FLOW_CONTROL.md)**

| API / path | Notes |
|------------|--------|
| `UartXonXoff(1)` / `UartXonXoff(0)` | Enable / disable software FC (seed + `hc_repl`) |
| `UartFcGet` | Current XON/XOFF enable flag |
| `UartRtsCts(1\|0)` / `UartRtsCtsGet` | **Stub** — records HW FC intent; no-op on virt (no CTS gate) |
| Shared state | `0x870010F0` (fc) / `0x870010F8` (tx paused) — C IRQ drain + HolyC Put |
| Kernel | `RVUartXonXoff` / `RVUart16550` (`RVUartIn`/`Out` for `REG_SHIFT=2`) |
| ZMODEM / trzsz | Auto-`UartXonXoff(0)` for the session |

**Limits:** RTS/CTS is a **soft stub** (no-op on virt); XON/XOFF consumed (not readline input) when SW FC on; Kernel PutS FC poll may drop non-FC RX (`hc_repl` soft ring keeps keys); non-16550 UART kinds lack this path. Prefer 9P / framed dump for bulk files ([NINEP.md](NINEP.md)). Manual: during `DumpFile` / long `Print`, type Ctrl-S then Ctrl-Q on the host PTY. Smoke: `make repl-uart-xon-pty`.

---

## Smokes that touch this stack

| Target | Relevance |
|--------|-----------|
| `repl-smoke` / `repl-holyc-smoke` | Console + eval + **dmesg** + **Sys** + **Tty** + **Vt** + **TermSize**/TermRep |
| `trap-smoke` | G2 Fault/Break/Ctrl-C + **CrashMon** (`crash>` / go) |
| `repl-uart-echo-pty` / `term-probe-pty` | UART / size CPR + window-size |
| `repl-uart-xon-pty` | Software XON/XOFF (Ctrl-S pause / Ctrl-Q resume) |
| `dbg-smoke` / `hwdbg-smoke` / `gdb-uart-smoke` | Soft dbg / host qemu-gdbstub / guest UART RSP |
| `dump-changes-smoke` / `zmodem-smoke` / `trzsz-smoke` | Framed export (ad-hoc) |
| `repl-9p-smoke` / `kernel-virtio-9p-smoke` | Remote FS (virtio) |
| `kernel-win-interactive` / `kernel-win-serial-smoke` | FB WinMgr + UART `RVWinSerial` banner / help needle |

Update this page when PutCh wrap or Ctrl-A VT binds land; prefer probing seeds over guessing.
