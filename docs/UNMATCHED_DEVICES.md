# The rest of the HiFive Unmatched: PCIe, USB, QuadSPI, ethernet, I2C, PWM

Paths, not drivers. Nothing below is implemented except where it says so. Device facts are from
`fu740-c000.dtsi` and `hifive-unmatched-a00.dts` (the U-Boot 2025.01 tree that boots this board),
read rather than remembered.

**The dependency that reorders everything: USB is downstream of PCIe.** The FU740 has no USB
controller — neither dts contains a USB, XHCI or ULPI *node*. The board's USB 3.0 comes from a
PCIe-attached bridge, and the only evidence of it in the device tree is three GPIO line names
(`UBRDG_RSTN` 7, `ULPI_RSTN` 9, `UHUB_RSTN` 11, all resets we can now toggle from the prompt). Linux
finds that bridge by enumerating PCIe. So there is no USB milestone until PCIe enumerates, and XHCI
is the largest driver on this page once it does.

Everything else is independent of PCIe and can be done in any order.

## PCIe: a path, not a driver

Nothing here is implemented yet. This is the route from "the board has an x8 slot and an M.2 that
U-Boot already brings up" to "TempleOS/RV enumerates it", written down while the device facts are
fresh (`fu740-c000.dtsi`, `hifive-unmatched-a00.dts`, and U-Boot's own output on the board).

## What the hardware gives us

| thing | value | where it comes from |
|---|---|---|
| root complex | `sifive,fu740-pcie` (a DesignWare core) | SoC dtsi |
| **config space (ECAM)** | **`0xDF0000000`, 256 MiB** | `reg-names` entry `"config"` |
| DesignWare DBI | `0xE00000000`, 2 GiB | `reg-names` entry `"dbi"` — controller registers incl. the iATU, **not** config space |
| SiFive mgmt block | `0x100D0000`, 4 KiB | `reg-names` entry `"mgmt"` |
| I/O window | `0x60080000` | `ranges` entry `0x81000000` |
| IRQs | 56–64 (9 of them: MSI plus the INTx legs) | dtsi `interrupts` |
| power enable | **GPIO 5** (`PCIe_PWREN`) | board dts line names |
| reset | **GPIO 8** (`PCIe_PERSTN`), active low | board dts line names |
| clocks | PRCI — already configured by firmware | dtsi `clocks = <&prci ...>` |
| observed | `PCIE-0: Link up (Gen1-x8, Bus0)` | U-Boot on this board |

Two consequences worth stating before any code is written:

**The config space is above 4 GiB.** `0xDF0000000` needs 36 bits, so every pointer in an ECAM walk
must be a full `I64` and every offset computation must stay 64-bit. That is exactly the class of bug
this port fixed twice in one day — `sizeof(<class> *)` answering 208 instead of 8, and `*p->arr`
loading 8 bytes from a byte array — so an ECAM walk written in HolyC is a place to be deliberate,
not breezy. A `U32 *` cast against a 64-bit base is the specific mistake to watch for.

**A takeover-time bring-up is far easier than a cold one.** We enter after U-Boot has already
powered the slot, released `PERSTN`, trained the link and set the PRCI clocks — `Link up (Gen1-x8)`
is printed before we exist. So the first milestone can *skip* bring-up entirely and only read. A
cold boot from SPL would additionally owe: `PCIe_PWREN` high, ≥100 ms before releasing
`PCIe_PERSTN` (the spec's T-PVPERL), the DesignWare core's own LTSSM setup, and ATU window
programming — all of which are why this is a path and not an afternoon.

## Milestones

### Milestone 1, as far as the board allowed (2026-09-28)

`Kernel/Drv/RVPcie.HC` + `Kernel/RVPcieUi.HC`, verb `Pci`. Read-only, and it stopped exactly where
reads stop being enough. What the board taught us, in the order it taught us:

- Aiming the enumerator at `0xE00000000` **half worked, which is worse than failing**: bus 0 dev 0
  read `0xF15E` correctly and every other function came back as aliased controller registers
  (`0xF15E` repeated, then `0x0100:0x0007`). That window is the **dbi**, and DesignWare aliases the
  root port's own config space at dbi+0. The dts names all three windows; only the middle one is
  config space.
- Aiming it at the real config window (`0xDF0000000`) returns **all-ones**: after U-Boot finishes,
  the iATU no longer maps config cycles, so there is nothing to read there at all.
- So on this board a read-only pass can honestly report exactly one thing — the root port, through
  the dbi alias: `vendor 0xF15E device 0x0000`, which matches U-Boot's own `pci` output. `Pci` now
  prints that plus what is missing, rather than walking a window of ones and presenting controller
  registers as devices.
- A smaller trap worth keeping: reading the device id at dbi+4 returns `0x0007`, which looks like a
  device id and is in fact the Command register (IO|MEM|BusMaster). Only U-Boot's independent
  enumeration caught it. Compare against an existing enumerator whenever one is available.

**Milestone 1b, the first write:** program the DesignWare iATU to map config cycles for a target bus,
then the existing walker works unchanged — it already follows bridges to their secondary buses, which
this board needs, since the USB controller sits two buses below the root behind an ASM2824 switch.
The windows are `dbi 0xE00000000`, `config 0xDF0000000`, `mgmt 0x100D0000`; the ATU viewport
registers live in the dbi. Ground truth to aim at, from U-Boot on this board:

```
00.00.00   0xf15e 0x0000  Bridge          root complex (SiFive)
01.00.00   0x1b21 0x2824  Bridge          ASMedia ASM2824 PCIe switch
02.00/02/03/04/08        0x1b21 0x2824    its downstream ports
04.00.00   0x1b21 0x1142  Serial bus 0x03 ASMedia ASM1142 USB 3.1 — this is the board's USB
```

That last line is the measured proof of the claim at the top of this file: the Unmatched's USB is an
XHCI behind PCIe, so it cannot work before the iATU does.

1. **Read the config space and enumerate.** With `RVGpioRd` you can already confirm pin 5 high and
   pin 8 released from the prompt. Then a `PciCfgRd32(bus,dev,fn,off)` over ECAM at
   `0xE00000000 + (bus<<20 | dev<<15 | fn<<12) + off`, a `Pci()` verb that walks bus 0 and prints
   vendor/device/class per function, and nothing else. Purely observational, unbrickable, and it
   answers "does the port see the link U-Boot trained?". This is the milestone to aim at first.
2. **Read a BAR and map it.** Report the BARs firmware assigned rather than reassigning them; the
   windows are already live, which sidesteps ATU programming completely.
3. **An INTx or MSI arrives.** PLIC IRQs 56–64 with the hart-1 context this port now gets right —
   the same fix that made the UART's interrupt reachable. `mip.MEIP` on our hart is the observable,
   exactly as `plat-smoke: plic_meip_ok` does for the UART today.
4. **A real driver.** Two candidates, and they differ in kind: the M.2 slot wants **NVMe**, which is
   a new driver but a well-specified one (admin queue, one I/O queue, identify, read/write) and would
   give this board a disk far better than the SD card; a PCIe **NIC** would instead want a real
   device's descriptor rings, since `VirtioPci*.HC` in this tree only ever meets a virtio device,
   which no physical card is. NVMe is the better first target.
5. **Cold bring-up**, if the port ever boots from SPL rather than being taken over.

## What exists in the tree already, and what it is not

`Kernel/Drv/VirtioPci.HC`, `VirtioPciBlk.HC`, `VirtioPciNet.HC` and `NinePVirtioPci.HC` do PCI
config access and BAR mapping — but against QEMU's PCIe host bridge on `-M virt`, with virtio
devices behind it. The config mechanics there are worth reading and partly reusable; the device
layer is not, because an Unmatched has no virtio hardware. Treat those files as the ECAM reference,
not as a head start on a driver.

## Caveat carried over, and now downgraded to a question

This document used to state flatly that GEM DMA is not coherent with the caches on the FU540/740.
That was never measured, and the evidence runs both ways. Against coherency: only the PCIe node in
the device tree carries `dma-coherent`. For it: Linux drove this board's ethernet for years with no
cache maintenance whatsoever, which is hard to explain unless on-chip masters reach memory through
the L2 front port. `EthAb()` settles it in one command — it runs the TX probe twice, once with
`RVL2FlushRange` over the descriptor and buffer arena and once without, and prints the return code,
the TX descriptor status word and TXSTATUS for each. If both runs fail identically, coherency is
not the fault and the PHY link, the GEMGXL clock and the queue base are the suspects.

Until that runs, nothing here should be written as though the answer were known.

## Clocks — the assumption this port had never checked (2026-09-29)

Every divisor in this port was computed for the clocks U-Boot leaves behind, and nothing ever
verified them. That is fine while firmware boots the board and fatal the moment we are the
firmware, so `Clk()` reports the clock tree measurement-first:

- **Core frequency** from `mcycle` against the CLINT's `mtime` over 100 ms. `mtime` counts rtcclk
  at 1 MHz, a rate the board documents, so this needs no register map to be right.
- **PCLK** from the console's own baud divisor: the SiFive UART's seventh word, and
  `pclk = 115200 * (div + 1)`. The console is demonstrably working, so this is a fact about the
  hardware rather than a reading of a table.
- **Then** the PRCI decode — corepll, ddrpll, gemgxlpll, hfpclkpll and the PCLK divider, using
  U-Boot's `fu740-prci` offsets, with the raw register words printed beside them.

The decode checks itself against the measurement and says `DISAGREE` when they differ by more than
2%, because the offsets are the part most likely to be wrong. It also flags the case that matters
for the drivers already in the tree: if PCLK is not about 125 MHz, the I2C prescaler of `0x0103`
and everything else derived from that number are wrong rather than merely undocumented.

### What the board actually answered (2026-09-29)

Measured on the hardware, at the prompt, from `Dump(0x10000000,6)` plus the console divisor and a
`mcycle`-against-`mtime` window:

| clock | decoded from PRCI | cross-check |
|---|---|---|
| corepll | 1196 MHz (divr 2, divf 275, divq 2) | ~1.19 GHz measured over a 17 s window |
| ddrpll | 923 MHz (divr 0, divf 70, divq 2) | — |
| gemgxlpll | 125.125 MHz (divr 2, divf 230, divq 5) | exactly the GMII clock gigabit needs |
| hfpclkpll | 260 MHz (divr 2, divf 239, divq 4) | — |
| PCLK | 130 MHz (hfpclkpll / 2) | console divisor 1128, so 115200 × 1129 = 130.06 MHz |

Four things came out of that, and two of them were this port being wrong:

- **The offset table is right.** `gemgxlpll` decoding to 125.125 MHz is not a coincidence a wrong
  table produces, and `corepll` matching the measured core clock settles it.
- **The output-divider model was wrong.** `RVPrciPllHz` treated `*_plloutdiv` as a rate divider,
  which made the core 598 MHz. `coreplloutdiv` reads 0 and the core runs at 1.196 GHz, so no
  division happens; bit 31 is a clock enable. Linux's `fu740-prci` models these as the bare PLL
  output too. Fixed, and `Clk`'s self-check is what would have caught it on sight.
- **PCLK is 130 MHz, not the 125 MHz written down all over this tree.** Harmless in the direction
  it was wrong: the OpenCores I²C prescaler `0x0103` gives `PCLK/(5×260)`, which at 130 MHz is
  *exactly* 100 kHz. The divisor was always right for this board; the comments calling it
  "~96 kHz" were the error. The SPI comment (`~400 kHz`, `12.5 MHz`) is likewise 417 kHz and
  13 MHz, both still fine for an SD card.
- **`mtime` really is 1 MHz.** Two reads 3 s apart differed by 3,128,544 ticks.

Configuring these PLLs is step 2 of Stage B in `UNMATCHED_FIRMWARE.md`. Reading them honestly was
the prerequisite, and it has now paid for itself twice before a single PLL was written.

## USB — blocked behind PCIe, then large

No SoC block, no dts node. After PCIe milestone 1 (enumeration) the bridge appears as a class
`0x0C0330` function; after that it is a full XHCI driver: device-context base array, command and
event rings, a transfer ring per endpoint, port reset and speed negotiation, then per-class drivers
(HID for a keyboard, mass storage for a stick). The three `*_RSTN` GPIOs must be released first —
which `GpioArm; GpioWr(7,1)` can already do by hand. Realistically this is the last thing on the
board to work, and a USB keyboard is the only reason to want it, since the console is serial.

## QuadSPI — the cheapest win on the board, because the flash is already memory

Three SiFive SPI controllers, and the interesting part is the *second* `reg` entry on two of them:

| controller | regs | IRQ | attached | note |
|---|---|---|---|---|
| QSPI0 `0x10040000` | + **`0x20000000`, 256 MiB** | 41 | `jedec,spi-nor` | direct-mapped flash window — but `fctrl.en` will not set on this board, so it reads zeros (see below) |
| QSPI1 `0x10041000` | + a window | 42 | nothing on this board | |
| QSPI2 `0x10050000` | one reg only | 43 | `mmc-spi-slot` — **the SD card** | gated by `EN_VDD_SD` (14), detected on `SD_CD` (15) |

**Measured, and it corrects the obvious reading of that table.** `Dump(0x20000000)` returns all
zeros, and the reason is not the window: QSPI0's `fctrl.en` (offset `0x60`, bit 0) — the bit that
enables direct-mapped reads — is **0 and will not take a 1**. `FlashMap(1)` writes it and reads back
`0`. Meanwhile every other register in that block reads plausibly (`sckdiv=1`, `csdef=1`,
`delay0=0x00010001`, and `ffmt=0x30007`, i.e. firmware did program the flash instruction format), so
the controller is clocked and reachable — only the mapped reader refuses to arm.

Candidates for why, in the order worth checking: a PRCI gate specific to the direct-map path that
firmware leaves closed; a required `csmode`/`fmt` state the controller demands before `fctrl` latches;
or U-Boot's SPI driver disabling the feature in a way that persists. Note the Unmatched's SPL comes
from the SD card, not from flash, so nothing in the boot path needs this window — it may simply never
be armed on this board.

Reading the flash therefore still wants a driver: PIO through `txdata`/`rxdata` with a `0x03` read
command, which is a small amount of code and unblocked by any of the above. `FlashMap(on)` stays as
the one-bit experiment and an honest report of what the hardware answers.

**The SD card is the best useful target on the whole board.** `mmc-spi-slot` means SD in SPI mode,
which is a small protocol — CMD0, CMD8, ACMD41, CMD58, CMD16, then CMD17/CMD24 for single blocks.
Those are exactly the commands the mask ROM's error ladder enumerates, which this port already
decoded the hard way from `Error 0x0000000000000005`. It would give the board the RedSea disk that
`make tos` already boots under virtio, which is the difference between a REPL and a system.

## Ethernet — reachable and readable from the prompt (2026-09-28)

`CONFIG_SIFIVE_ETH_BASE` is now `0x10090000` for this board and `Eth` reports the controller without
touching it. On the board, straight after a takeover:

```
GEM @ 0x10090000  irq 55
  MAC 70:B3:D5:92:FF:1D   (slot 3, programmed by firmware from the board EEPROM)
  ncr   0x00000000  rx=0 tx=0          U-Boot halts the controller after a transfer
  ncfgr 0x00100402  full-duplex, gigabit
  rxq   0xFF749F70  txq 0xFF74A1C0     U-Boot's rings, in its relocated memory
```

That MAC matches the one U-Boot prints, which is the register map confirmed independently. Two traps
on the way, both found by contradicting a plausible reading with a raw `Dump`:

- `sifive_gem_base` was set **only** by `RVSifiveGemInit`, so every access before init went to
  address 0. Reads returned zeros -- `Eth` reported a perfectly configured controller as dead -- and
  `RVSifiveGemWr` would have written into the mask-ROM region. The accessors now default the base
  from Kconfig and refuse when the board has no GEM.
- The MAC is **not in slot 1**. Cadence GEM has four specific-address slots (`0x88`, `0x90`, `0x98`,
  `0xA0`); U-Boot leaves the address in slot 3 on this board, so a reader hardwired to `SA1B` sees
  zeros. `Eth` scans all four and names the one it found.

## Ethernet — what is still needed to send a packet

The driver already exists: `Kernel/Drv/RVSifiveGemYes.HC` (Cadence GEM), and today's device audit
gave it the right IRQ (**55** on the FU740; 53 is I2C1). What it still needs:

- `CONFIG_SIFIVE_ETH_BASE = 0x10090000` — it is `0x0` for this board, so the driver compiles and is
  never wired. That one line is the first experiment.
- The **second window, `0x100a0000`**: the GEMGXL management block, which the current driver does not
  know about.
- `GEMGXL_RST` (GPIO 12) pulsed — doable by hand right now: `GpioArm; GpioWr(12,0)` … `GpioArm;
  GpioWr(12,1)`.
- `phy-mode = "gmii"`, PHY at MDIO address 0, clocks from `GEMGXLPLL` that firmware has already set —
  another reason a takeover is easier than a cold boot.
- The MAC: U-Boot reads it from the 24c02 EEPROM and prints it (`70:b3:d5:92:ff:1d` on this board).
- **The open question that matters:** whether descriptor rings here need the L2 controller's flush
  registers at all. Every device this port has driven so far was MMIO-only or a coherent QEMU
  model, so this is new ground and the most likely source of "it almost works" bugs — but the
  answer is a measurement (`EthAb()`), not a deduction from the device tree.

## I2C — small, and it is where the board's personality lives

I2C0 `0x10030000`, IRQ 52, an OpenCores-style master with **8-bit registers at a 4-byte stride**
(`reg-shift = <2>`, `reg-io-width = <1>`). A polled master is on the order of a hundred lines. On the
bus:

| address | device | what it gives |
|---|---|---|
| `0x4c` | **TMP451** | the board temperature, at the prompt (its alert is the `THERM` GPIO) |
| `0x58` | **DA9063 PMIC** | a *real* hardware reset, an RTC, a watchdog, and the on-key |
| `0x50` | 24c02 EEPROM | the serial number and MAC U-Boot prints |

Two consequences worth noting: a `Temp()` verb is the single most charming thing this board could do
from a HolyC prompt, and the PMIC is the honest answer to `plat-smoke: sifive_no_hw_reset` — a true
reset lives there, not on a GPIO. Neither can be tested on QEMU (`sifive_u` models no I2C), so this
is board-only bring-up; write it with the DMI-readback lesson in mind and do not trust a value the
link hands back without a known-value self-check.

## PWM — cheap and visible

Two controllers, `0x10020000` (IRQs 44–47) and `0x10021000` (IRQs 48–51), both enabled in the board
dts. Four compare channels each; the Unmatched routes them at the fan and LED headers. A handful of
register writes for something you can see across the room, which makes it a good first device for
anyone learning this port.

## Order, if you want one

1. **Now, no new driver:** read the SPI-NOR at `0x20000000`; toggle GPIO by hand.
2. **Small and self-contained:** PWM; then I2C0 and `Temp()`.
3. **Most useful:** SD over QSPI2 → a real RedSea disk on hardware.
4. **Closest to done:** GEM ethernet (one config line to start, then whatever `EthAb()` says).
5. **Gated on PCIe:** enumeration (read-only) → NVMe on the M.2 → XHCI → USB devices.
