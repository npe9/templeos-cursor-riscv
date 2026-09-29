# Owning the board from reset: replacing U-Boot SPL

Goal: complete control of the HiFive Unmatched — TempleOS/RV as the first software the machine
runs, with no U-Boot and no OpenSBI. Everything below is grounded in FU740-C000 Manual v1p6
chapters 6 (Boot Process) and 7 (Clocking and Reset), and in what this port has already measured on
the board.

## What the hardware does before any of our code exists

- **Reset**: every core jumps to **`0x1004`**, running directly off the 26 MHz external clock. No
  PLLs are configured; `0x1000` holds the **MSEL pin state**, which the board's DIP switches set.
- **MSEL** picks the boot medium (Table 16). `1111` (default) has the ZSBL read QSPI0 x4 flash;
  `1011` ("rescue image from SD card") has both stages come from **QSPI2 SD**. That is how this
  board is actually strapped: `PeekU32(0x1000)` reads **11** on it, measured from the prompt. So
  every stage of the boot comes off the card, which is what makes both stages below viable and
  their recovery a card reader. `0000` **loops forever waiting for a
  debugger**, which is the escape hatch that makes all of this safe to attempt.
- **ZSBL** (mask ROM at `0x10000`, 32 KiB) brings up the SD card in SPI mode and loads the next
  stage from a GPT partition of type **`5B193300-FC78-40CD-8002-E86C45580B47`**. Its SD sequence is
  documented as: 10 SPI clocks with CS inactive, CMD0, CMD8, ACMD41, CMD58, CMD16, then the
  controller to 20 MHz and `READ_BLOCK_MULTIPLE` (CMD18) for the GPT and the payload.
- That stage runs from the **L2 LIM at `0x08000000`** — which exists because out of reset only way 0
  is cache and the other 15 ways are scratchpad. (By the time we take over from U-Boot, `WayEnable`
  is `0x0F` and the LIM is gone. It is available to *us* only if we are the early stage.)
- **U-Boot SPL** then trains DDR and loads a FIT from the partition of type `2E54B353-…`.

Three of those facts we did not take on trust: the mask ROM's SD ladder is the same one this port's
`Kernel/Drv/RVSdSpi.HC` now drives (its `Error 0x5` was CMD0 with no reply), the SPL partition GUID
is the one `Sd`/`SdRd(2)` reads back off the card, and `WayEnable = 0x0F` is what `L2` prints.

## Stage A — replace the payload, keep the stock SPL (no DDR work)

Leave partition 1 alone, so SiFive's SPL still trains DDR, and put TempleOS where the FIT lives.
The SPL jumps to it and nothing else runs: no OpenSBI, no U-Boot.

What it needs: the image in the form the SPL expects from that partition (a FIT wrapping our flat
binary with a load address and an entry point, or U-Boot's raw-payload path), and our entry to
survive being entered with DDR trained but nothing else set up — which is already true, because
that is exactly the state the JTAG takeover leaves us in today.

Risk: low. Recovery: rewrite partition 2 from a card reader. **This is the stage to do first** — it
delivers "the board boots TempleOS" without touching the hardest part.

## Stage B — be the SPL

Write a small TempleOS stage into partition 1 (GUID `5B193300-…`). The ZSBL loads it into the L2
LIM and jumps. It must, in order:

1. **Fit in the LIM.** Roughly 1.9 MB is available at `0x08000000` out of reset. The REPL image is
   5.5 MB, so this stage is a *loader*, not the system — the same division U-Boot uses.
2. **Configure the PRCI.** At reset the harts run at 26 MHz off `hfclk`; software must bring up
   `corepll` (1.0 GHz recommended, 1.5 GHz possible), `hfpclkpll` for the peripheral clocks that
   UART/SPI/I2C/PWM depend on, plus the dedicated DDR and GEMGXL PLLs. Note this port currently
   assumes firmware has done this — every peripheral divisor it uses was computed for the
   post-firmware clock (the I2C prescaler reads 0x0103 for ~96 kHz off a 125 MHz PCLK).
3. **Train DDR.** The hard part, and the only part with no existing TempleOS code: the memory
   controller at `0x100B0000`, its physical filter at `0x100B8000`, and DDR MGMT at `0x100C0000`,
   driven by a long initialisation and PHY-training sequence. The realistic route is to port
   U-Boot's `fu740` DDR driver rather than derive it; it is a register blob with a training loop.
4. **Load the system.** Read the main image from a partition into DRAM using the SD driver this
   port already has — `RVSdInit` + `RVSdReadBlk` work on this board today. The ROM uses CMD18 for
   speed; CMD17 per block is enough to start, and CMD18 is a small addition.
5. **Jump**, in M-mode, on a U74 (hart 1 — hart 0 is the S7 and cannot execute this image's
   `rv64gc` code; the crt0 already parks the wrong harts).

Risk: moderate, and **bounded** — the SD card is removable, the mask ROM always runs, and MSEL
`0000` halts for a debugger, so a bad SPL cannot brick the board. Recovery is a card reader, which
this project has already used once to install U-Boot 2025.01.

## Stage C — be the SBI (only if we want to host something else)

"Becoming the SBI" matters only for running an S-mode OS such as Linux underneath us. TempleOS
owns M-mode and needs no SBI for itself — it *is* the supervisor. If hosting Linux ever becomes the
goal, the work is the ecall interface (timer, IPI, console, hart start/stop) plus delegating traps,
and it is independent of Stages A and B.

## Order, and what each is worth

| stage | effort | what you get |
|---|---|---|
| A: replace the FIT payload | small | the board powers on into TempleOS; no U-Boot, no OpenSBI |
| B1: PRCI clocks in our code | medium | the port stops depending on firmware's clock setup |
| B2: DDR training | **large** | no SiFive firmware on the board at all |
| B3: SD loader in the LIM stage | small | already have the driver |
| C: SBI | medium | only needed to host Linux |

The honest ordering is A → B3 → B1 → B2, so that every step but the last is small and the hardest
one is attempted with the rest already working and a known-good fallback card on the shelf.
