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

## Loading the real image

`mw.l` through the console carried the 82-byte hello; `loady` (ymodem, `lrzsz`) carried the 323 KB
platform image in ~50 s and is the proven path; the 10.7 MB REPL image over ymodem is ~17 minutes.
tftp is scripted (`UNMATCHED_XFER=tftp`) but blocked by the U-Boot gigabit TX bug above. The other
transport that avoids U-Boot networking entirely: boot the board's Linux, copy the image onto the
SD boot partition over Linux's (working) network, reset, and `load mmc` it from U-Boot.
