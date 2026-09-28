# HiFive Unmatched: JTAG takeover into M-mode — what was measured, what works

Date: 2026-09-26. Everything here was measured on the board or read off the schematic; nothing is
copied from another board's notes (the repo's earlier Unmatched notes were, and were wrong).

## Result

From the U-Boot prompt, with the board's own firmware having trained DDR, a U74 hart was halted over
JTAG, forced to M-mode, pointed at a payload in DDR and resumed — and the payload printed on the UART:

```
halted    dmstatus=0x30382
dcsr=0x400000c3 (prv=3)   dpc=0x80007bce
mie=0  mstatus.MIE=0  dcsr prv=3  dpc=0x80200000     (each write read back)
resumed   dmstatus=0x30c82
TempleOS/RV64 hello from 0x80200000
```

`tools/unmatched/dmi_takeover.py` does it; `tools/unmatched/takeover_from_uboot.sh` wraps it with
the console dance (catch autoboot through the user's `screen`, poke the payload with `mw.l`, verify
with `md.l`, take over). `tools/unmatched/hello.S` is the payload; `srst_only.cfg` pulses the board
reset through the FTDI (it did not reset the board in the one test — the button did).

## The kernel platform image, same way

`tools/unmatched/load_and_takeover.sh <flat.bin>` is the whole cycle, hands-free except the reset
button: catch U-Boot's autoboot through the user's `screen`, `loady 0x80200000` fed by
`sz --ymodem` through the same window (~50 s for 323 KB), **`crc32` the DDR against the file**, then
the takeover. Run against the hifive_unmatched `plat.bin` (crt0 boots on hart 1), captured from a
cleared window so it is a single run:

```
halted    dcsr=0x400000c1 (prv=1)  dpc=0xfff93c42        <- inside relocated U-Boot
mie=0  mstatus.MIE=0  dcsr prv=3  dpc=0x80200000  resumed
plat-smoke: machine=hifive-unmatched
plat-smoke: uart_ok  clint_ok  clint_adv_ok  sifive_api  sifive_clint_ok
plat-smoke: sifive_no_hw_reset  sifive_plic_ok  plic_ok  memmap_ok
plat-smoke: PASS
ORACLE 0000000000000000
```

UART, CLINT (and that it advances), PLIC and the memory map, checked by the kernel's own HolyC on
the FU740. Two notes: the console emits LF without CR (cosmetic, but a real terminal staircases);
and one earlier run showed the sequence twice with `dpc` already in the image's idle loop at halt
time — not reproduced, not explained, recorded.

**A trap that did not fire:** `crt0.S` used to park every hart with `mhartid != 0`, and the takeover
lands on hart 1 (hart 0 is the S7). The image tested here already boots on hart 1 (`li t1,1; bne
t0,t1,halt`). Had it not, the fix planned was to enter at the instruction after the check — which on
this build would have been mid-instruction. Disassemble the image you are about to jump into.

## The board, from the schematic (rev 3, sheets 4 and 16)

| | |
|---|---|
| JTAG + console | one on-board **FT2232H** on the micro-USB ("Dual RS232-HS", `0403:6010`, no USB serial, so macOS names the ports by location). Channel A = JTAG, channel B = UART0 console, 115200 |
| **J18** | a 2-pin **JTAG MUX SELECT jumper** (TS3A5018 mux U12). No jumper = FT2232H. Jumper = header J6 |
| **J6** | external 2x5 JTAG header, Cortex-10 layout, **VDD_1V8 on pin 1: the FU740's JTAG is 1.8 V**. An Olimex ARM-USB-TINY-H (2.0–5.0 V) must not be connected to it |
| on-board JTAG path | FT2232H `ADBUS0-3` → **TXB0104** auto-direction shifter → 33 Ω → mux → SoC |
| `ADBUS4` | **`FT_JTAG_SRST`, active HIGH**, via Q8B onto `RESET_N`. `layout_init` must keep bit 4 low (`0x0008/0x001b` does); a `0x0038` experiment held the board in reset |

## The link, measured

Raw IDCODE scans inside one held session: 24/24 at 10 MHz, ~50% at 1 MHz, 6/24 at 100 kHz.
Debug-Module reads: nothing parses at 1–2 MHz, OpenOCD **asserts** at 3 MHz (`riscv-013.c:499`),
clean from 5 MHz. Over 300 scans at the best settings there is still a **2–3% per-scan corruption
floor** (8 MHz falling: 6 strays; 10 MHz falling: 9). Corrupt values are `0`, `1`, all-ones, or the
right value shifted one bit. Ruled out as causes: macOS FTDI driver contention (identical under
`sudo` with a clean detach), TRST/SRST levels, TDO sample edge, two cables, two USB ports. The floor
is in the TXB0104 + 33 Ω + mux chain, which no setting reaches.

**Consequence:** OpenOCD's `examine`/`halt` issue hundreds of unverified DMI ops and fail
essentially every time (0/6 measured), and one bad status is fatal to it. Raw `riscv dmi_read` /
`dmi_write` over the TCL port work in the same sessions. So the takeover is ~40 raw DMI ops, **each
read taken as the consensus of two consecutive identical, plausible reads and each write read back**
— a 2% floor becomes a ~0.04% chance of accepting garbage. Two failures shaped that rule: a lost
`command` write left `dpc` holding the previous `x8` and the hart resumed to `0x4000b0c2`
(`mcause=1`); and `dmstatus=0x80018642`, a corrupt word with the "allhalted" bit set, passed a bare
mask check while the hart was still running.

The FU740 debug module rejects abstract CSR access (`cmderr=2`); CSRs go through the program buffer
(`csrr s0,CSR; ebreak` + postexec, value via GPR `x8`).

## Memory map, from U-Boot on the board (`bdinfo`, `printenv`)

| | |
|---|---|
| DRAM | `0x80000000`, 16 GiB |
| OpenSBI (reserved) | `0x80000000`–`0x80040000` |
| U-Boot 2021.01 | relocated to `0xfff63000`; FDT at `0xff73d0e0` |
| U-Boot's load points | kernel `0x84000000`, fdt `0x88000000`, ramdisk `0x88300000` |
| **`0x80200000`** | **clear** — and SPL reuses it as the FIT load address every boot, so a payload there must be re-loaded after each reset |

## Inherited state at takeover

The hart arrives in S-mode (`dcsr.prv=1`) or, if caught mid-SBI-call, in M-mode inside OpenSBI.
`mtvec` still points at OpenSBI. `mstatus.MIE` was 0 both times measured; `mie` is zeroed anyway.
A real kernel entry must write `mtvec` first and own PMP before touching anything.

## U-Boot networking on this board does not work at gigabit (measured)

The stock U-Boot 2021.01 on the SD card: PHY answers over MDIO (OUI 0x01C1 model 0x37), `BMSR=0x796d`
link up, autoneg complete, `link up, 1000Mbps full-duplex` — and the first packet gets
`ethernet@10090000: TX timeout`, every time, into the BOOTP retry loop (and once wedged hard enough
that only the reset button got out). This is the known FU740 GEM TX-clock issue in U-Boot before
2021.04. Forcing the PHY to 100 Mb with `mii write` does not survive: the macb driver re-runs
autonegotiation from its own defaults on every `dhcp`, so `mii write 0 0 0x2100` and clearing the
1000BASE-T advertisement (`mii write 0 9 0`, `mii write 0 4 0x0101`) both came back as 1000 Mbps.
Linux configures the clock itself, which is why Linux networking works on the same board.

So tftp from THIS U-Boot needs one of: a 100 Mb switch/hub between board and router (the partner
then cannot offer gigabit), a newer U-Boot on the SD card, or a different transport.

## Fixed: U-Boot 2025.01 installed on p2 — tftp works

Built in Docker (`ubuntu:24.04`, `gcc-riscv64-linux-gnu`, `sifive_unmatched_defconfig`,
`OPENSBI=` QEMU's shipped generic `fw_dynamic.bin`): `u-boot-spl.bin` 87 KB, `u-boot.itb` 960 KB.
Written to the SD card from the Mac's reader by `~/uboot-unmatched/install_uboot_sd.sh` — finds the
card by the SiFive partition-type GUIDs (`5b193300…` = SPL = p1, `2e54b353…` = ITB = p2), backs both
up, writes **p2 only**, reads back and `cmp`s. SPL was left at 2021.01 on purpose; the banner now
reads `U-Boot SPL 2021.01` then `U-Boot 2025.01`, and the mixed pair boots fine.

Result on the board: `link up, 1000Mbps full-duplex`, `DHCP client bound to address 192.168.8.178
(254 ms)`, `TFTP from server 192.168.8.233 … Bytes transferred = 323224`, `crc32 … c4ee5f01`, then
the takeover and `plat-smoke: PASS`. Reset-to-PASS is under a minute.

One trap on the way: U-Boot's `dhcp` **overwrites `serverip`** with the DHCP server's address, so a
`setenv serverip` issued before it silently redirects tftp to the router. Name the server in the
request (`tftpboot 0x80200000 192.168.8.233:plat.bin`); the script does.

The router path was tried first and is closed with evidence: the LAN switch is an RTL8372N under
`swconfig` whose per-port attributes are `disable`, `pvid` and a read-only `link` — no speed forcing.

## Loading the real image

tftp is the transport (`UNMATCHED_XFER=tftp`, now the script's default); `loady` (ymodem) remains
as the fallback that needs no network at all (~50 s per 323 KB, so ~17 minutes for a 10 MB image).
Measured rates, same `plat.bin`, same board, `crc32` correct every time:

| server                                    | rate       | why                                                                        |
|-------------------------------------------|------------|----------------------------------------------------------------------------|
| the Mac, on **Wi-Fi** (`route get` → en0) | 11.7 KiB/s | TFTP is lock-step: one 1468-byte block per RTT, and the Wi-Fi RTT is 4–85 ms |
| same, `tftpwindowsize 8`                  | 8.8 KiB/s  | timeouts and whole-window retransmits on the jittery link                  |
| the Mac, **wired** (USB-C LAN, RTT 0.6 ms) | 40 KiB/s   | so the per-packet cost is macOS tftpd itself (~36 ms/packet), not the link |
| **the router** (dnsmasq TFTP, wired)      | 62.5 KiB/s | dnsmasq is the faster server (~23 ms/packet); the board is not the limit either way |

`tftpblocksize` and `tftpwindowsize` changed nothing on the wire (2025.01 already defaults to
1468-byte blocks; every run moved the same 23 block-groups). The router serves from `/tmp/tftp`
(RAM — restage after a router reboot): `uci set dhcp.@dnsmasq[0].enable_tftp=1; uci set
dhcp.@dnsmasq[0].tftp_root=/tmp/tftp; uci commit dhcp; /etc/init.d/dnsmasq restart`, then
`scp -O file root@192.168.8.1:/tmp/tftp/` and `tftpboot 0x80200000 192.168.8.1:file`. The script
does the scp itself (`UNMATCHED_TFTP_SSH`, default `root@192.168.8.1`). The board must never
`autoload`: a bare `dhcp` on U-Boot 2025.01 immediately tftps `C0A808B2.img` from the DHCP server
and blocks the prompt for ~40 s of `T`s.

Two console traps that cost twenty minutes here. After a `Ctrl-C` abort, U-Boot's line editor can
be left holding a fragment (`=> setenv`), and the next line typed is **appended** to it — `setenv
tftpboot 0x80200000 …` silently defined a variable and the crc32 that followed read stale DDR.
Do **not** flush it with a bare Enter — hush **repeats the last command on an empty line**, and `tftpboot` is repeatable (that is how one stray Enter restarted a transfer under a running script). Flush with Ctrl-U (kill line) then `true`. And a `Ctrl-C`
stuffed through `screen` can land late and abort the *next* command's transfer.

## The mask ROM speaks at 57600: `Error 0x0000000000000005`

After a power cycle the console showed garbage at 115200 and nothing that looked like U-Boot; the
DMI peek found hart 1 parked in the boot ROM (`dpc=0x101d8`, prv=3, PRCI PLLs bypassed) — SPL had
never run. At **57600 baud** the text was `Error 0x0000000000000005`: the FU740 ZSBL's SD error
ladder, where `0x5` = **CMD0 (`GO_IDLE_STATE`) got no reply** — the ROM never reached the GPT, let
alone SPL (`0x6` CMD8, `0x7` ACMD41, `0x8` CMD58, `0x9` CMD16, `0xa` bad GPT header, `0x3` SPL
partition not found). Cause: the microSD was not fully seated after the Mac-reader round trip.
Re-seating it fixed it; nothing on the card was changed. Two lessons: the ZSBL's UART runs at
57600, not 115200 (the `div=0xe1` the peek read is 57600 from the un-PLLed clock; my 26 MHz pclk
arithmetic was 2× off), and read the ROM's error code before suspecting the card's contents.

## Hands-free reset: `ndmreset`, in two sessions

`tools/unmatched/reset.sh` (used by the loader with `UNMATCHED_AUTO_RESET=1`). Writing
`dmcontrol.ndmreset` resets the debug module along with the chip on this board: the writing session
never gets another DMI answer (`DMI operation didn't complete in 2 seconds`, eight times), the console
goes silent, and the board sits **held in reset** — the first attempt looked like a wedge and needed
the button. A fresh OpenOCD session fixes it: three blind writes of `dmcontrol=dmactive` read back as
`0x1`, `dmstatus` is sane, and the console shows `U-Boot SPL 2021.01 … U-Boot 2025.01` from the mask
ROM. Verified with the window cleared before the write and nobody at the button. Prompt in ~15 s.

Proven end to end the same night, nobody at the bench: `UNMATCHED_AUTO_RESET=1 UNMATCHED_SCREEN_PID=<pid>
tools/unmatched/load_and_takeover.sh build/…/plat.bin` → JTAG reset → `U-Boot SPL 2021.01` → router tftp
→ `crc32` match → takeover → `plat-smoke: PASS`, `ORACLE 0`, in about two minutes. The REPL image
(agent build 20:13, 5,489,672 B) went through the same pipeline and died on silicon exactly as on the
model — `TRAP mcause=5 load-fault mtval=0x1f blob+0x115f20` — which is the useful result: the QEMU
`hifive-unmatched` model reproduces the board, so the fix can be made and gated there.

## The REPL runs on the FU740 (2026-09-26, late)

`A2 reg pane wired … probe ans=42 … A2: Cmp compiled 40+2 … >` on the board's UART, then `2+3;` →
`ans=5`, `10*7;` → `ans=70`, `1+1;` → `ans=2`: the guest HolyC compiler compiles and evaluates on
real silicon. Image: `tests/scripts/run_repl_unmatched_smoke.sh` (5,503,248 B, crc32 `8de8d2fd`),
run as `UNMATCHED_UBOOT_PRE='mw.q 0x80740000 0 0xf18000' UNMATCHED_AUTO_RESET=1
UNMATCHED_SCREEN_PID=<pid> tools/unmatched/load_and_takeover.sh build/exec/repl_unmatched.bin`.
Getting from "dies at blob+0x115f20" to the prompt was **four** board-only bugs, none visible on
any QEMU machine; each is named here with its evidence because the next port will hit the same four.

1. **The demo's own UART.** `kernel_repl_exepubs_demo.hc` byte-stored banners to virt's
   `0x10000000`, which on the FU740 is the PRCI (clock controller). Found by the board agent from an
   in-sync map; the build now writes a variant that delegates to the selected driver and asserts it.
2. **Memory assumed zero.** `MAlloc+0x168`: `ld a0,32(s1)` with `s1 = -1` → `mtval=0x1f`. Root
   cause (board agent, reproduced on the model byte for byte with a `-device loader` 0xff fill):
   `Kernel/KBootRV.HC` puts `the_heap`'s 1 KiB control block at a **fixed 0x82000000** that no
   section covers and nothing zeroes; QEMU's RAM is zero, the board's held `0xff`, and MAlloc read
   a free-list head of -1. Fixed in `tests/exec/harness/crt0.S`: zero `__bss_start..__bss_end`
   (NOBITS, only ever zero by layout luck) and a `ZERO_BASE/ZERO_LEN` window, before `sp` is set.
   Gate: `TOS_REPL_DIRTY_DDR=1 tests/scripts/run_repl_unmatched_smoke.sh` pre-fills the window with
   `0xff` and still requires `2+3` → `5`; it fails on purpose with the zeroing removed. Proven on
   the board the same night with no `mw.q` pre-command. (The `UNMATCHED_UBOOT_PRE` hook stays as a
   diagnostic lever — it is how the class was proven — but nothing needs it now.)
3. **Misaligned loads trap.** `BlkDevLock+0x114`, `mcause=4`, `mtval=0x82044834`: an I64 at
   offset 100 of a packed class. The U74 traps misaligned accesses; OpenSBI emulates them only for
   S-mode; QEMU never traps. Fixed for good in the C runtime: `bootstrap/holy_misaligned.h` emulates
   integer/FP, 32-bit/compressed loads and stores byte-wise in `HolyTrapDispatch` (`make
   misaligned-emu-test`, 36 host checks; AMOs still fall to the crash path).
4. **Hart 1 is not always U-Boot's hart.** OpenSBI's boot-hart lottery: one boot had hart 1 in
   OpenSBI's wait loop, the next had it in U-Boot; when U-Boot lives on another U74 it keeps
   polling the UART and answered `2+3;` with `Unknown command '2+3' - try 'help'`. The takeover
   now halts harts 0,2,3,4 and leaves them halted.

Also learned: after a takeover, `dmi_csrs`-style reads of `dpc/mcause/mepc/mtval` with the hart
briefly halted are the fastest diagnosis on this board — every one of the four above was named
that way within minutes, where the console alone said nothing.

## Also found on the way (not board-specific)

- **`*p->arr` on a member array loaded 8 bytes** (`host/parser.c`, commit `896e92ab`): the
  2026-08-27 deref fix covered local arrays only. `RedSeaFilesFind`'s `*tmpde->name!='.'` read
  `".."` as `0x2e2e`, sent the parent entry down the recurse branch, and every
  `FilesFind(FUF_RECURSE)` recursed into its own parent until `the_heap` itself was overwritten —
  the tier-1 agent's `DirNameAbs mtval=0x70`. Found with `the_heap` markers compiled from a scratch
  copy of the include tree (`HOLYC_INCLUDE_ROOT=<copy>`), after gdb watchpoints proved unusable in
  batch mode against QEMU's stub (`continue` returns at once: "target is running").
- **The REPL swallowed the first keystroke after its banner** — fixed, and it was three layers:
  (a) the SiFive driver had no soft RX ring, so `RVDocVT`'s size probe pushed bytes back into a
  C-runtime stub that dropped them (`RVUartSoftEnqueue` was one of the "benign" unresolved
  imports; the smoke now asserts it is resolved); with the ring in place the symptom became
  `[98;133R2+3;` — the terminal's cursor-position reply minus its ESC — which exposed (b) a
  probe that abandoned a half-read reply at its 40 ms QEMU-sized deadline, and finally (c) the
  real culprit, **`RVSifiveUartDataReady` read `rxdata` to test the empty bit, and on the FU740
  a read of `rxdata` dequeues**: every polled `TryGet` discarded the byte it saw and returned the
  next. `DataReady` now reads once and parks the byte for `GetC`. Proof on the board: `2+3;` as
  the very first keystroke → `ans=5` (image `21e717bd`). Diagnosed by sending synthetic
  `ESC[5;7R` replies at the prompt (handled) versus during a probe (eaten), then reading the
  platform primitives. QEMU's `sifive_u` dequeues on read too; nothing there polls with a reply
  in flight, which is why only silicon showed it. Gate: `make repl-unmatched-cpr-smoke`
  (`TOS_REPL_CPR=1`) — a reactive feeder answers the `'q' quits` line with `ESC[40;120R2+3;` inside
  the startup probe's 300 ms window; with the fix `ans=5`, with the pre-fix `DataReady` the first line
  is `[40;120R2+3;` and it fails — the board's failure, byte for byte, on `sifive_u`.
- **Do not run `run_repl_unmatched_smoke.sh` while anything else compiles the kernel.** It swaps
  `Kernel/RVAutoConf.HH` and `Kernel/Drv/*Selected.HH` to the SiFive UART under a restoring trap;
  a kernel compile from another process in that window inherits the SiFive UART and store-faults
  at `0x10010008` on `virt` (`kernel-fsshell-smoke` did, during a concurrent `qemu-integration`).

## A missing Print argument is an exception, and it was invisible (2026-09-28)

`for (i=0;i<10;i++) "Hello %d\n";` printed nothing and answered `ans=0`; with `,i` it printed.
Stock `StrPrintJoin` does `throw('StrPrint')` when a format runs past its arguments — TempleOS
semantics, kept by the port — but two things hid it. The host compiler's `throw` intrinsic stored
the code in the planted `__task.except_ch` only, while every HolyC catcher reads `Fs->except_ch`,
and once the kernel sets `Fs = adam` those are different cells: `PutExcept`, `DirContextNew`'s
catch and the REPL all read 0. And `ExePutS`'s catch swallowed the exception without a word.
Fixed: `EmitThrow` also stores through `Fs` into the real `CTask.except_ch` (offset looked up at
emit; `e_throw_fs_except_ch.hc` 0x3, was 0x0), and `ExePutS` prints `Except:%c` for anything but
the compiler's own errors. The unmatched smoke types `"%d %d\n",7;` and requires
`Except:StrPrint`; on the board the line above now says exactly that. A wrong guess of mine on
the way — that `Silent` was set — was disproved by toggling it at the prompt; the operator's
reading ("failing because of the lack of i, but not reporting") was the right one.
