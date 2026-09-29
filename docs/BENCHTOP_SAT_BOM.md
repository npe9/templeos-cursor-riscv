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

## What you cannot usefully buy

**A radiation source.** The corruption experiment should stay in software: deliberately flip bytes
in a checksummed region and watch the checksum app detect it and the sequence app respond. That is
already how the simulated build does it, and it is reproducible, which a real particle is not.

## Suggested first order

Everything in Tier 1 plus the SX1262 from Tier 2. That buys: a real inertial and magnetic sensor, a
real time reference with a pulse-per-second tone, real power telemetry, a real load you can shed, a
watchdog that actually resets the machine, a second flight computer on Ethernet, and a radio. Every
one of them lands on an interface this port already drives or nearly drives, and each replaces one
simulated app without touching the others — which is the whole point of putting the software bus
between them.
