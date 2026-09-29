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

`tools/unmatched/mk_stage_a.sh` builds that payload and prints the console blocks to paste. It
needs no `mkimage`: a FIT is a flattened device tree, so `dtc` makes one, and the script checks the
result really does start `d00dfeed`. The image node is `type = "firmware"`, `os = "u-boot"`,
`load` and `entry` both `0x80200000` — `os = "opensbi"` would have the SPL try to boot a firmware
blob with a device tree, which is the thing being removed, whereas `"u-boot"` makes it jump in
M-mode and stop having opinions.

Three things that came out of building it:

- **It does not fit, and that changes the verdict below.** The current REPL image is 5,594,328
  bytes, so the FIT is 10,928 blocks of 512. SiFive's standard layout gives the loader2 partition
  8,192 blocks (4 MiB). Read the real numbers off this card with `part list mmc 0` first, because
  everything else depends on them; the script's block 1 does exactly that. If p2 really is 4 MiB,
  there are three ways out and they are not equally cheap:

  1. **Shrink the payload.** A build without the compiler, or the `RV_THIN_LOADER` configuration,
     is the only option here that keeps the risk where this plan claims it is.
  2. **Put a small loader in the FIT** that reads the real image off another partition with
     `Kernel/Drv/RVSdSpi.HC`. This is Stage B3 arriving early, and it is the option that scales.
  3. **Grow the partition.** Cheap to say and the worst of the three: it rewrites the GPT, which
     is what the ZSBL reads to find partition 1, so a bad write takes out the stock SPL as well as
     the payload — and MSEL `1011` means there is no flash to fall back to. Recovery is a card
     reader, not a retry at the prompt. Do not start here.

  So Stage A is small **only if the payload fits**. On a stock card the REPL image does not — but
  something else already does. `build/kernels/hifive_unmatched/plat.bin` is 344,832 bytes, which
  the script turns into a **675-block** FIT, comfortably inside a 4 MiB loader2. That is the
  platform demo: it brings up the UART, the CLINT timer and the PLIC and prints `plat-smoke: PASS`.
  Booting *it* off the card proves the entire chain — ZSBL, SPL, FIT, load address, entry, hart —
  with nothing bigger than a reset at stake, and it needs no repartitioning and no new code:

  ```
  tools/unmatched/mk_stage_a.sh build/kernels/hifive_unmatched/plat.bin
  ```

  Do that before anything else in this section. Only once the board has powered on into TempleOS
  code with no U-Boot does the question of where the 5.5 MB image lives become worth answering,
  and by then it is a sizing problem rather than an unknown.
- **The payload can be proven before the card is touched.** Block 2 tftps the FIT into RAM and
  runs `iminfo` then `bootm` on it. That exercises the FIT structure and our entry point with the
  card untouched, so a mistake costs a reset rather than a reinstall. U-Boot's `bootm` parses more
  than the SPL does, which makes it a fair first gate but not a complete one. The script writes a
  real `hash-1` node with the payload's crc32 into the FIT so that `iminfo` has something to check
  — without it, a pass would mean only that U-Boot found nothing to verify.
- **The card also carries a working Linux, and Stage A takes it out.** Observed 2026-09-29: a
  reset with nothing pressing a key autoboots the board all the way into `FreedomUSDK 2021.03.01`
  at a login prompt, with the ethernet link up at 1 Gbps. So partition 2 is not a spare slot --
  it holds the U-Boot that boots that system, and overwriting it ends the Linux boot as well as
  the bootloader. That is recoverable from a card reader and it is a real cost to weigh, and it
  is another argument for doing the 675-block demo payload on a SECOND card rather than this one.
- **Back up partition 2 first, not afterwards.** Partition 1 stays stock, so a bad payload leaves
  the SPL running with nothing loadable, and MSEL 11 means there is no flash to fall back to.
  `tftpput` works for this only against a server that accepts writes — dnsmasq's TFTP is read-only,
  so this one goes to the Mac's own `tftpd`, and the destination file has to exist and be writable
  before the board sends it. Pulling the card and `dd`-ing it is the version with no caveats.

A wrong-hart entry used to be silent. `crt0.S` now prints `hN` over UART0 for the hart it turns
away, because being loaded by an SPL means no debugger is attached and "the board went quiet" would
otherwise be indistinguishable from a bad load address. The hart-0 negative control asserts that
string rather than asserting silence, and hart 0 does print it: the path is plain rv64i, so the
FPU-less S7 can run it.

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
   post-firmware clock. Measured 2026-09-29: PCLK is **130 MHz** (hfpclkpll 260 MHz / 2), so the
   I2C prescaler `0x0103` is exactly 100 kHz and the "125 MHz" this tree assumed was wrong.
   `Clk()` at the prompt reports the core clock and PCLK as measurements first (`mcycle` against
   the CLINT, and the console's own baud divisor) and only then decodes the PRCI, so it says
   whether those numbers are real before any of them is rewritten. Running it is what found both
   the 130 MHz and a bug in the port's own PLL decode.

   The values Stage B has to reproduce, all measured on this board: corepll 1196 MHz, ddrpll
   923 MHz, gemgxlpll 125.125 MHz, hfpclkpll 260 MHz, PCLK 130 MHz, off a 26 MHz crystal.
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
| A: replace the FIT payload | small *if it fits* | the board powers on into TempleOS; no U-Boot, no OpenSBI |
| B1: PRCI clocks in our code | medium | the port stops depending on firmware's clock setup |
| B2: DDR training | **large** | no SiFive firmware on the board at all |
| B3: SD loader in the LIM stage | small | already have the driver |
| C: SBI | medium | only needed to host Linux |

The honest ordering is A → B3 → B1 → B2, so that every step but the last is small and the hardest
one is attempted with the rest already working and a known-good fallback card on the shelf.
