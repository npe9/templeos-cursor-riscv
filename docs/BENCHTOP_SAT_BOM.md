# Benchtop satellite: what to buy, and what each part unblocks

A shopping list for turning the HiFive Unmatched cFS work into a real benchtop spacecraft. Ordered
by **what this port can already talk to**, because a part you cannot reach is not a part, it is a
project. Every line says which board interface it lands on and what driver work it implies.

Rough magnitudes only — prices move. Everything here is the kind of part Mouser stocks; where a
bare chip would mean QFN soldering, buy the breakout.

## What the board actually gives you to attach things to

| interface | status in this port | notes |
|---|---|---|
| I²C0 | driver exists, **reads only** | allow-list on 0x4C (TMP451), 0x50 (EEPROM), 0x58 (PMIC). Writes are a deliberate gap |
| SPI (QSPI2) | driver exists, SD read path proven | a second chip select is the cheap way to add SPI devices |
| UART0 | console | do not repurpose |
| UART1 @ `0x10011000` | in the memory map; **header presence unverified** | check before planning a GNSS on it |
| GPIO | driver exists, pins **0, 3, 4, 13** free | pin 2 is PMIC shutdown — guarded on purpose |
| PWM | driver exists | LEDs, fan header |
| Gigabit Ethernet | **works both directions, verified on the wire** | 9P and the bus network ride this |
| PCIe x16 slot, M.2 M-key, USB | read-only enumeration only | the address-translation windows are unstarted work |

Two consequences worth stating before the list. **Anything on PCIe or USB is gated** behind a
milestone that has not begun, so SDR-over-USB and FPGA-over-PCIe are not near-term. And **I²C
writes do not exist yet**, so every I²C sensor below implies opening that path — which also means
revisiting why it was closed (the power controller sits on the same bus).

Also: **check the header's logic level before wiring anything.** Level shifters are on the list for
that reason, not as an afterthought.

## Tier 1 — makes the architecture real, all on interfaces that work

These replace the simulated apps one for one, and none of them needs PCIe or USB.

| subsystem | part | interface | why this one |
|---|---|---|---|
| IMU | **TDK InvenSense ICM-42688-P** breakout | SPI (or I²C) | low noise, widely used, SPI avoids the I²C write gap entirely |
| Magnetometer | **ST IIS2MDC** or **Memsic MMC5983MA** breakout | I²C | completes `MAG_RAW` for attitude |
| GNSS | **u-blox SAM-M10Q** (patch antenna integrated) or **MAX-M10S** + antenna | UART + **1PPS** | the 1PPS pin into a free GPIO is a real time tone — that is what cFE TIME wants, and it turns `GNSS_TIME` from a number into a discipline source |
| Thermal | **TI TMP117** breakout | I²C | board already has a TMP451; a second, accurate sensor gives a limit-check input you control with your thumb |
| Power monitor | **TI INA226** breakout | I²C | bus voltage and current for `EPS_TLM`. This is the input the battery-sag fault acts on |
| Load switch | **TI TPS22918** breakout or a small relay board | GPIO | so "shed load" is a real action, not a telemetry point |
| External watchdog | **TI TPS3813** or **Maxim MAX6369** | GPIO | **the most underrated part here.** A windowed watchdog that resets the board when health-and-safety stops servicing it turns FDIR from a log message into a consequence |
| Level shifters | **TI TXB0104** / **TXS0108E** breakouts | — | between board header and 3.3 V sensors. Verify the header level first |
| I²C fan-out | **TCA9548A** mux breakout | I²C | keeps sensors off the bus the power controller lives on, which is the honest answer to the allow-list problem |
| Second flight node | **ST NUCLEO-H743ZI2** (or **NUCLEO-F767ZI**) | **Ethernet** | Ethernet is the point: the bus-network transport I built is raw-ethertype, so a second node needs no IP stack. This is the distributed-spacecraft experiment for the price of one dev board |
| Wiring | Dupont/JST jumpers, 0.1 in headers, breadboard or perfboard, 4.7 kΩ pull-ups | — | I²C needs the pull-ups; many breakouts include them |

Tier 1 total is modest — roughly the cost of one mid-range dev board plus sensors.

## Tier 2 — a real radio, without needing USB

The instinct is to buy an SDR. On this board that is premature: USB is behind PCIe and XHCI, neither
of which exists here. A **transceiver on SPI** gives the payload app real RF semantics now.

| part | interface | what it gives the SDR app |
|---|---|---|
| **Semtech SX1262** breakout (or SX1276) | SPI | actual transmit and receive, RSSI, channel activity detection — so `SDR_SIGNAL_DETECTED` comes from radio silicon instead of a counter |
| **TI CC1200** breakout | SPI | alternative, better for higher symbol rates |
| Antennas, SMA pigtails, 50 Ω dummy load | — | do not transmit into open air without checking your licence and band |

Keep an **ADALM-PLUTO** or **HackRF One** on the list as Tier 3, for when USB works — they are the
right instruments eventually, just not reachable yet.

## Tier 3 — gated behind PCIe work

Buy these when the address-translation milestone is done, not before.

| part | interface | gate |
|---|---|---|
| NVMe SSD (you have one) | M.2 M-key | PCIe enumeration + BAR setup + an NVMe driver |
| FPGA payload — **Lattice ECP5** or **iCE40UP5K** board | **SPI** if you pick a board with an SPI slave, PCIe if not | pick SPI and this moves to Tier 1 |
| SDR — ADALM-PLUTO / HackRF One | USB | XHCI over PCIe |
| PCIe FPGA card | PCIe | the largest single piece of work on this list |

## Tier 4 — spacecraft flavour, optional

| part | interface | why |
|---|---|---|
| **MCP2515 + TJA1050** CAN breakout | SPI | the FU740 has **no CAN**. This is how a CAN bus appears at all, or let the STM32 node own it |
| **MAX3490** RS-422 breakout | UART | an RS-422 link is what a real spacecraft bus tends to look like |
| Programmable bench PSU (e.g. Rigol DP712) | — | the honest way to make battery voltage fall on command |
| USB-serial adapter, second | UART1 | to use UART1 for GNSS while keeping the console |

## What the cFS translation simulates today, and the part that replaces each one

This list is the other half of a bill of materials: the port now carries **32 simulated
`CFE_PSP_*` functions and 59 simulated `OS_*` functions** behind the differential driver, and
every one of them is a place where real hardware or a real OS has to appear eventually. Most are
not parts at all — they are driver work on silicon the board already has — and saying which is
which is the useful distinction.

**MM, the Memory Manager, is what made this concrete.** It is the app whose whole job is to touch
memory the ground names, so it is the first thing in the port whose simulation is a *device*
rather than a counter. It needs four things real:

| what MM uses | simulated as | what makes it real | tier |
|---|---|---|---|
| `CFE_PSP_MemRead8/16/32`, `CFE_PSP_MemWrite8/16/32` | a 256-byte window at a literal address | **nothing to buy** — these are loads and stores to the FU740's own DRAM once the PSP has a real memory map. The simulation exists because a host pointer and a guest pointer never agree, not because the hardware is missing |
| `CFE_PSP_MemValidateRange` | a settable return code | **nothing to buy** — a PSP memory-range *table*, which is a port decision about which physical ranges the ground may patch. This is the single most safety-relevant unwritten table in the port |
| `CFE_PSP_EepromWrite8/16/32` | a second 256-byte window at `0x00200000` | **a part.** See below | 1 |
| `CFE_PSP_EepromWriteEnable/Disable` (by bank) | a counter and a settable code | **a GPIO into a write-protect pin.** See below | 1 |

### The nonvolatile part MM wants

| part | interface | why this one |
|---|---|---|
| **Infineon FM25V02A** FRAM breakout (32 KB, SPI) | SPI, second chip select | The honest modern stand-in for flight EEPROM: byte-writable, no erase block, no programming delay, ~10^14 write endurance. MM's `MM_PokeEeprom` wraps every EEPROM write in performance-log stamps *because an EEPROM programming cycle takes milliseconds* — with FRAM those stamps measure a bus transaction, which is the one place this substitution changes the telemetry's meaning. Say so when you wire it |
| **Microchip 24LC256** EEPROM breakout (32 KB, I²C) | I²C | The literal part, with the real programming delay — so `MM_EEPROM_POKE_PERF_ID` means what NASA meant. **Gated behind the I²C write gap**, and the board's own EEPROM already sits at 0x50, so this needs the TCA9548A mux from Tier 1 |
| **A GPIO wire to the part's `WP` pin** | GPIO (pins 0, 3, 4, 13 are free) | This is the cheap half and the important half. `MM_EepromWriteEnaCmd` and `MM_EepromWriteDisCmd` take a **bank number** and today they increment a counter. Wire `WP` and they become a real interlock: the ground has to explicitly unlock the part before a patch lands, and a stuck-enabled line is something the health app can notice. Same argument as the load switch and the external watchdog above — a command that cannot fail is not a command |

Pick **FRAM on SPI** first. It avoids the I²C write gap entirely, which is the same reason the IMU
is on SPI in Tier 1, and one `MM_PokeEeprom` of a known pattern followed by a power cycle and a
`MM_PeekCmd` is a complete end-to-end demonstration that the nonvolatile path works.

### What MM needs that is not a part at all

- **`OS_SymbolLookup` and `OS_SymbolTableDump`.** `MM_LookupSymCmd` turns a symbol name into an
  address, which is how an operator patches a build they do not have the map for — and
  `MM_SymTblToFileCmd` dumps the whole table. Both need the **loader** to keep a symbol table,
  which this port does not yet have. No hardware involved; it is the module-loading milestone.
- **A real `CFE_PSP_MemValidateRange`.** Worth repeating because it is the one that matters: with
  it stubbed, *every* address the ground names is accepted. MM's safety argument is entirely in
  `MM_VerifyPeekPokeParams` and `MM_VerifyLoadDumpParams`, and both of them defer the final
  question — "is this real memory, and of the right kind?" — to the PSP.

## What you cannot usefully buy

**A radiation source.** The corruption experiment should stay in software: deliberately flip bytes
in a checksummed region and watch the checksum app detect it and the sequence app respond. That is
already how the simulated build does it, and it is reproducible, which a real particle is not.

## Suggested first order

Everything in Tier 1 plus the SX1262 from Tier 2, **and the FM25V02A FRAM breakout with a wire to
its `WP` pin**. That buys: a real inertial and magnetic sensor, a real time reference with a
pulse-per-second tone, real power telemetry, a real load you can shed, a watchdog that actually
resets the machine, a second flight computer on Ethernet, a radio, and **a nonvolatile store the
ground can patch through an interlock it has to open first**. Every one of them lands on an
interface this port already drives or nearly drives, and each replaces one simulated app without
touching the others — which is the whole point of putting the software bus between them.

The FRAM is the newest line and the cheapest: it is the part that makes Memory Manager — 3,976
lines of translated NASA code, 100% gated, 2,803 differential transcript lines — do something to
a device instead of to an array.
