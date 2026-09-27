# HiFive Unmatched (SiFive FU740-C000) — what it takes, and what is actually verified

Status line first, because the rest of this document is detail:

| claim | how |
|---|---|
| The board image builds and runs at its real link address | `make kernel-plat-hifive-unmatched-smoke` — real `plat.bin` at 0x80200000 on `-M sifive_u` |
| That gate can fail | `make kernel-plat-hifive-unmatched-controls` — five controls, each must fail |
| The JTAG takeover procedure works | `make unmatched-takeover-smoke` — OpenSBI in the chain, hart halted in S-mode, gdb takes it |
| …in the mode the board will actually use | `make unmatched-takeover-preloaded` — image already in DDR, JTAG does only the dozen ops |
| Those gates can fail | four `TOS_TAKEOVER_BREAK=` controls, in both load modes, each must fail |
| The HolyC **REPL** image for this board | **builds and evaluates `2+3` = 5** under the full OpenSBI → S-mode → JTAG-takeover chain — §11 |
| The board's JTAG TAP scans, and raw DMI reads work | measured on a live board (IDCODE 0x20000913) |
| An OpenOCD **examine or halt** completes reliably | **NO.** A 1-5% per-scan DMI corruption floor no setting removes — §7. Use raw DMI with consensus reads. |
| **The plat kernel runs on real FU740 silicon** | **YES.** ymodem into DDR at 0x80200000, crc32-verified, raw-DMI takeover from the U-Boot prompt, hart 1, `dcsr.prv=3` — every `plat-smoke` line once and `PASS`, plus `ORACLE 0`. §10 |
| The **REPL** runs on real silicon | not yet — the image is now buildable (§9 fixed); handoff details in §10 |

Nothing below distinguishes "I reasoned this" from "I measured this" by tone — measurements
are quoted with the numbers.

---

## 0. Corrections to earlier notes in this tree

Six things that were written down before and are wrong.

**`CONFIG_UART_REG_SHIFT` is not just wrong for this board, it is inapplicable.**
`tests/scripts/hifive_unmatched_board_help.sh` claimed `REG_SHIFT=2`. `templeos-riscv/Kconfig`
has `config UART_REG_SHIFT` with `depends on UART_16550`, and this board is `CONFIG_UART_SIFIVE=y`.
A SiFive UART has no register-shift concept at all. The line was copy-paste from the JH7110
siblings, along with `ENTRY 0x40200000`, `go 0x40200000`, `load_image … 0x40200000`,
`FB_PRESENT_SIMPLEFB` and `-M virt`. All fixed. `tests/openocd/hifive_unmatched_load_plat.tcl`
was already correct at 0x80200000; only the help text was wrong.

**A QEMU machine model is not needed, and the reason is stronger than "the maps match".**
`-M sifive_u` models the FU540, and for UART/CLINT/PLIC the FU740 is the same
(UART0 0x10010000 SiFive, CLINT 0x02000000, PLIC 0x0C000000, DRAM 0x80000000). But the
better reason is that it models the same *topology*: one management core plus N application
cores, with different ISAs. That is the property this port was getting wrong.

**"The wrong UART harness blocks output" was overstated for the plat demo and understated
for everything else.** `tests/exec/cases/kernel_plat_demo.hc` prints exclusively through
HolyC `RVUartPutS`, which uses `CONFIG_UART_BASE` and was always correct. So
`plat-smoke: PASS` appeared on `-M sifive_u` with the C harness writing bytes into the
PRCI — and a gate that checked only that needle passed. What the broken C harness actually
silenced was `trap_report`, the crash monitor, and the `^C` RX path: i.e. every diagnostic,
which is the worst possible thing to lose on a first bring-up. The plat demo's own header
says as much: *"Never call RVMemMap() here — harness Print is virt UART @ 0x10000000."*

**Polled REPL input was never the problem.** `Kernel/Drv/RVUartSifive.HC` routes
`RVUartGetC` to `RVSifiveUartGetC`, which is SiFive-correct, and `Kernel/RVLineEd.HC:177`
calls `RVUartGetC`. The 16550-shaped RX code is only in the C runtime
(`bootstrap/holy_rt.h`): `holy_crash_getc` (the crash monitor) and the PLIC RX IRQ path
(`^C`). Both are now SiFive-capable, but neither was ever in the polled REPL's way.

**`CONFIG_UART_IRQ` was 0.** Kconfig's own help text for the board said "IRQ 39" while
`UART_IRQ` had no `PLATFORM_HIFIVE_UNMATCHED` default, so it fell through to 0 — the
"no interrupt" source. 39 is confirmed twice over: FU740-C000 manual v1p6 §13.2 Table 59
("39 39 UART 0"), and `fu740-c000.dtsi`'s `uart0: serial@10010000 { … interrupts = <39>; }`.
Now 39. Note `-M sifive_u` wires UART0 to PLIC source 4, so the PLIC path in the plat demo
is *vacuous under emulation* for this board — it enables a source nothing drives. That is
the honest state: correct for hardware, untested by the emulated gate.

**`0x80200000` was an assertion in a comment. It is now evidenced** — see §2. It survived.

---

## 1. The two defects that made a good image look dead

### 1a. The C half of every board image described QEMU's `virt`

`tests/exec/harness/oracle_out.c` did `*(volatile unsigned char *)UART_BASE = c` with
`UART_BASE` defaulting to `0x10000000`, and `bootstrap/holy_rt.h` defaulted
`HOLY_UART_BASE` to the same with 16550 offsets (IER at +1, LSR at +5). On the FU740:

* `0x10010000` is a **SiFive** UART: 32-bit `TXDATA` at +0 with FULL in bit 31, `RXDATA`
  at +4 with EMPTY in bit 31, `ie` at +0x10. A byte store at +0 is not "the same write,
  narrower".
* `0x10000000` is the **PRCI** — the clock controller. Those writes went into clock
  registers.

`-DHOLY_UART_BASE=` could move the address but not change the device. Measured, with a
throwaway `_start` that calls `oracle_report(0x1234)`, linked at 0x80200000, on `-M sifive_u`:

```
A: default oracle (byte store @ 0x10000000)          -> (nothing)
B: -DHOLY_UART_SIFIVE=1 -DUART_BASE=0x10010000UL     -> ORACLE 0000000000001234
```

Fix: a `HOLY_UART_SIFIVE` knob, default 0, in both files, plus `HOLY_UART_IRQ` made
overridable (it was an unguarded `#define … 10`, i.e. virt's, on every board) and the PLIC
enable write corrected — it was `1u << irq`, which is the wrong word *and* undefined
behaviour for FU740 UART0's 39. `tests/scripts/build_kernel_plat.sh` now reads
`CONFIG_UART_SIFIVE/BASE/IRQ`, `CONFIG_CLINT_BASE` and `CONFIG_PLIC_BASE` out of the
applied `.config` and passes them through for any SiFive-UART board.

Two things guard the blast radius. The default path is **byte-identical**: disassembling
`oracle_out.o` built from the pre-change and post-change sources gives identical output.
And the variant gets its own object path (`oracle_out-sfu-<base>-irq<n>.o`) because the
staleness test in that script is mtime-only — a shared `oracle_out.o` would have been
handed to the next board with the wrong flags baked in, which is precisely the class of
bug this tree keeps getting bitten by.

`make kernel-plat-matrix`: **ok=12 fail=0** (up from 11 — `hifive_unmatched` was built by
the matrix but never run; it is a member now).

### 1b. The image was pinned to the one hart that cannot execute it

`tests/exec/harness/crt0.S` gated on `csrr t0, mhartid; bnez t0, halt`. On the FU740,
hart 0 is the **S7** and harts 1–4 are **U74s**; the S7 is rv64imac — no F, no D. The image
is `-march=rv64imafdc -mabi=lp64d`. The gate pinned it to the only core that cannot run it.

`-M sifive_u` reproduces this exactly. Measured:

```
CPU #0: model=sifive-e51   misa=0x8000000000101105   (D clear)
CPU #1: model=sifive-u54   misa=0x800000000014112d   (D set)
```

It "worked" until now only because `kernel_plat_demo.hc` happens to emit no FP instruction.
Anything larger — certainly the compiler and the REPL — would have taken an illegal
instruction on its first double, on hardware, with `trap_report` writing into the PRCI and
therefore printing nothing.

`crt0.S` now takes `-DBOOT_HARTID`; `hifive_unmatched` and `sifive_u` build with 1. The
variant gets its own object path for the same reason as above.

Independent confirmation from OpenSBI itself, which picks the boot hart on this machine:

```
Domain0 Boot HART         : 1
Boot HART Base ISA        : rv64imafdc
```

---

## 2. The load address, measured rather than assumed

Two independent lines of evidence, and they agree.

**From the firmware's own mouth, on the emulated leg.** `-M sifive_u`'s default `-bios` is
`opensbi-riscv64-generic-fw_dynamic.bin` (OpenSBI v1.5.1 as shipped with QEMU 10.1.3). Its
banner reports its footprint, and its domain table reports exactly what it fences off:

```
Firmware Base             : 0x80000000
Firmware Size             : 337 KB
Firmware RW Offset        : 0x40000
Domain0 Region00          : 0x0000000002000000-0x000000000200ffff M: (I,R,W) S/U: ()
Domain0 Region01          : 0x0000000080040000-0x000000008005ffff M: (R,W)   S/U: ()
Domain0 Region02          : 0x0000000080000000-0x000000008003ffff M: (R,X)   S/U: ()
Domain0 Region03          : 0x000000000c000000-0x000000000fffffff M: (I,R,W) S/U: (R,W)
Domain0 Region04          : 0x0000000000000000-0xffffffffffffffff M: ()      S/U: (R,W,X)
Domain0 Next Arg1         : 0x0000000087e00000        <- the DTB it hands on
Boot HART MIDELEG         : 0x0000000000000222
Boot HART MEDELEG         : 0x000000000000b109
```

Firmware occupies `0x80000000..0x8005FFFF` — 384 KiB. `0x80200000` is clear by 1.6 MiB.
And the same numbers appear as PMP registers on the boot hart, read over gdb (§3).

**From the board's own tooling, for the real thing.** Mainline U-Boot, `board/sifive/unmatched/Kconfig`:
`TEXT_BASE` is `0x80200000 if RISCV_SMODE` (which is what this board builds) and
`SPL_OPENSBI_LOAD_ADDR` is `0x80000000`; `arch/riscv/dts/binman.dtsi` places `opensbi` at
`SPL_OPENSBI_LOAD_ADDR` and `uboot` at `TEXT_BASE` in the FIT. **That bounds firmware to the
2 MiB below 0x80200000 as a hard constraint** — if it overran, the stock image would not boot.
`sifive_unmatched_defconfig` sets `CONFIG_SYS_LOAD_ADDR=0x80200000`, so `$loadaddr` is the
same address. SPL itself never touches low DRAM: `SPL_TEXT_BASE` is `0x08000000`, the L2
LIM, and `CONFIG_SPL_STACK=0x81cfe60` is `0x081C_FE60` in that LIM — **not** `0x81CF_E060`
in DRAM, a misreading worth naming because it would move the answer. And U-Boot's own
Unmatched boot log shows Linux at exactly this address:

```
OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
node   0: [mem 0x0000000080200000-0x000000027fffffff]
```

**Where live U-Boot ends up.** `arch/riscv/cpu/fu740/dram.c` overrides
`board_get_usable_ram_top` and returns `SZ_4G` if `ram_top` is above it, so relocated U-Boot
sits just under `0x1_0000_0000` — roughly `0xFF00_0000..0x1_0000_0000` once its 8 MiB
malloc arena, gd, fdt and stacks are reserved. **Not** near the top of the 16 GiB
(`0x4_8000_0000`), which is where the risk was assumed to be. Either way our payload is
~2 GiB clear of it.

**Conclusion: 0x80200000 stands, and it is the address the board's own tooling designates.**
`0x84000000..0x84400000` also works but is worse: it is `CONFIG_SPL_LOAD_FIT_ADDRESS` and, on
2022-era firmware, `kernel_addr_r`.

### The thing that is NOT at 0x80200000, and matters more

**The image is position-independent, so the load address barely constrains correctness — but
its FIXED absolute addresses do.** Everything is `-mcmodel=medany` and `auipc`-relative;
measured, the same `plat.bin` runs unchanged at several addresses:

```
0x80000000 PASS   0x80200000 PASS   0x81000000 PASS   0x84000000 PASS   0x90000000 no
```

(the last only because it is past the end of `-M sifive_u`'s default DRAM). This is why the
gate asserts the ELF entry point *structurally* instead of inferring it from output — "did
it print?" cannot tell a right load address from a wrong one here. It also means the real
memory hazard is elsewhere: the Kconfig fixed areas, which are absolute no matter where the
image is loaded.

```
CONFIG_HEAP_BASE      0x86000000     CONFIG_SYS_FIXED_AREA 0x87000000
CONFIG_FB_SOFT_BASE   0x86100000     CONFIG_MEMFS_BASE     0x87800000
CONFIG_STACK_BASE     0x87F00000     CONFIG_TOS_API_ADDR   0x80300000
```

So the image writes to `0x86000000..0x88000000` wherever you put it. Against the measured
map that is safe — it is above SPL's dead BSS at `0x85000000` and below both eras'
`fdt_addr_r` — with one specific collision to know about: **OpenSBI hands the DTB at
`0x87e00000` (`Domain0 Next Arg1`), which is inside the MEMFS window.** Harmless here,
because after an M-mode takeover we never read that DTB. It would not be harmless if this
port ever starts consuming the firmware's device tree.

Also note `CONFIG_TOS_API_ADDR=0x80300000` is only 1 MiB above the load address, and the
board `plat.bin` is 323 KB today. Not a collision now; it would become one if the image grew
past 1 MiB.

---

## 3. What OpenSBI leaves behind, and why M-mode takeover is the *small* change

Read over gdb from the boot hart, after OpenSBI ran, on `-M sifive_u -smp 2`:

```
mhartid=1  priv=1  misa=0x800000000014112d  mstatus=0x8000000a00006080
mtvec=0x800003c8                 <- OpenSBI's trap handler
mie=0x8                          <- MSIE, for its IPIs; mstatus.MIE=0
pmpcfg0=0x1f1b181818
pmpaddr0=0x801fff     -> 0x02000000 +64K   CLINT,        S/U: none
pmpaddr1=0x20013fff   -> 0x80040000 +128K  firmware RW,  S/U: none
pmpaddr2=0x20007fff   -> 0x80000000 +256K  firmware R+X, S/U: none
pmpaddr3=0x37fffff    -> 0x0C000000 +64M   PLIC,         S/U: R+W
pmpaddr4=0xffffffffffffffff -> whole space, S/U: R+W+X
a1=0x87e00000         -> the DTB
satp=0x0              -> bare; gdb's `load` needs no translation
```

Four conclusions:

1. **PMP does not have to be undone.** No `pmpcfg` byte has the lock bit `0x80` set, so none
   of it applies to M-mode. After the privilege raise we inherit a machine we can fully
   drive. Nothing in the kernel needs a PMP-aware startup path.
2. **S-mode entry is not the cheaper option it sounds like.** PMP entry 0 denies S/U access
   to the CLINT at `0x02000000`, and `RVClintMtime()` is the second thing the plat demo
   touches after the UART. It would fault immediately. This is on top of the structural
   argument, which holds: `crt0.S` writes `mtvec`, `HolyRVTrapInit` sets `mtvec`+`mstatus.MIE`,
   `RVUartIrqInit` sets `mie.MEIE`, the trap-recover set reads `mcause/mepc/mtval`, and
   `Kernel/RVDbgView.HC` / `RVRegPane.HC` display machine CSRs. An S-mode port means an
   `stvec/scause/sepc/stval` variant of the whole trap layer. **No evidence was found of this
   port making any SBI call** — `ecall` appears only as a trap *cause* to report. So the
   coordinator's read is confirmed: M-mode takeover is the smaller change, and it is what the
   port already is.
3. **`mtvec` is self-healing but observably so.** `crt0.S` installs its own vector first
   thing. When something goes wrong before that, you see OpenSBI's handler instead — the
   wrong-pc negative control lands in `sbi_trap_error: hart1: trap0: …`, which is exactly
   OpenSBI's `mtvec` still being in charge. Useful, not a problem.
4. **`mie=0x8` must be cleared.** A machine software interrupt left enabled fires the moment
   the kernel sets `mstatus.MIE`, into a handler that knows nothing of OpenSBI's IPI
   protocol. The takeover script clears `mie`/`mip`.

**Secondary harts.** OpenSBI parks the others in its HSM wait loop, in M-mode, with PMP
*not yet* programmed (measured: hart 0 `pmpcfg0=0x0`). After the takeover they are still
OpenSBI's, spinning in firmware we have overwritten only at `0x80200000` — which they are
not executing. `crt0.S`'s `BOOT_HARTID` gate means they would park in our own `wfi` loop if
they ever did arrive. This is fine for bring-up and is **not** a multi-hart story: nothing
brings those harts under the kernel's control, and `kernel-smp-smoke` is a `-M virt` thing.

---

## 4. The takeover procedure — one script, two targets

`tests/gdb/unmatched_takeover.gdb` holds everything that touches machine state, and it is
byte-identical between the two legs:

```
  <halt>                          # leg-specific, see below
  eval "file %s", $tos_elf        # AFTER selecting the hart -- see the flen note
  load
  set $priv = 3
  set $mie = 0
  set $mip = 0
  set $pc = _start
  <resume>                        # leg-specific
```

What differs is only how each server is *driven*, and each difference is written out in its
own wrapper rather than hidden:

| | QEMU (`unmatched_takeover_qemu.gdb`) | OpenOCD (`unmatched_takeover_openocd.gdb`) |
|---|---|---|
| port | `:1234` | `:3333` |
| pick a hart | `add-inferior; inferior 2; attach 2; thread 2.1` | `thread 2` (harts are targets, not inferiors) |
| halt | `tbreak *$tos_fw_done; continue` | `monitor halt` |
| resume | `detach inferiors 1-2` | `detach` |
| verified | **yes**, gated | **no board was attached** |

Four things that cost a run each and are worth knowing before you touch the hardware:

**The ELF cannot be on the gdb command line.** Both servers describe the hart you first land
on, and on both that is the FPU-less management core. gdb compares its `flen` against the
ELF's and refuses outright: `bfd requires flen 8, but target has flen 0`. Connect, select a
U74, *then* `file`.

**`interrupt` is useless in a batch script.** It is asynchronous, gdb never settles, and every
following command fails with `Cannot execute this command while the target is running`.
Tried four ways (`interrupt`, `interrupt -a`, detaching the other inferior,
`schedule-multiple on`) — all four. The synchronous equivalent of "the board is sitting at
the prompt" is a temporary breakpoint: let firmware run, stop exactly there. On the real
board you do not need this at all, because the board really is already halted — which is why
`tos_halt` is leg-specific.

**`set schedule-multiple on` is load-bearing on the QEMU leg.** Without it the `continue`
inside `tos_halt` resumes only inferior 2, OpenSBI's boot hart never runs, and the breakpoint
is never reached.

**The final resume is `detach`, not `continue`.** `continue` never returns in a script, and
over QEMU's gdbstub it races with the stub's own bookkeeping (the hart is marked `[running]`
the moment `pc` is written) and reports the same "target is running" error while the guest
runs anyway. `detach` means "resume and stop debugging", which is the last act of a takeover.
Interactively you would type `continue` and keep `^C`.

### The gap that had to be closed to make this apples-to-apples

The first working version of this gate was **not** testing the privilege raise. Under QEMU
with OpenSBI and no payload, OpenSBI has nothing to `mret` into: it faults jumping to
next-address `0x0` and stays in M-mode. So a hart halted under QEMU was *already* `priv=3`,
`set $priv = 3` was a no-op, and the `nopriv` negative control **passed** — while on the
board the hart will be in S-mode, running U-Boot proper. That is exactly the
"works one way in QEMU and another on the board" failure that would have voided the exercise.

`tests/exec/harness/smode_idle.S` closes it: 20 lines of RV64 that print a banner and then
`wfi` forever, linked at `0x80400000` (deliberately not `0x80200000`), handed to QEMU as
`-kernel`. OpenSBI `mret`s into it in S-mode, and the emulated hart is now in the same
privilege state as a board at the U-Boot prompt. Measured, from the passing gate:

```
[takeover] mhartid=1 priv=1 pc=0x80400024
[takeover] misa=0x800000000014112d mstatus=0x8000000a00006080
[takeover] inherited mtvec=0x800003c8 mie=0x8 (firmware's)
[takeover] inherited pmpcfg0=0x1f1b181818 pmpaddr0=0x801fff (no L bit => M-mode unrestricted)
[takeover] load
[takeover] entering at 0x80200000 with priv=3 mie=0x0
```

The gate requires OpenSBI's banner *and* the S-mode stub's banner on the UART, so a run that
quietly lost its firmware cannot pass.

---

## 5. Gates, and each one seen to fail

`make kernel-plat-hifive-unmatched-controls` — five controls on the board-image gate:

1. **Wrong load address.** The obvious form of this control *does not work*, and finding that
   out was worth more than the control: the image is position-independent (§2), so loading it
   at 0x80000000 still prints `plat-smoke: PASS`. The gate therefore asserts the ELF entry
   point, and the control breaks *that* rule by feeding it `plat-qemu.elf`, the same image
   linked at 0x80000000.
2. **Wrong machine.** Same bytes on `-M virt`, same `-smp 2`, same boot hart — only the
   console device differs. Output vanishes, which is what proves it is coming through the
   SiFive UART at 0x10010000.
3. **The C harness needle.** Relink the *same* HolyC blob against the default 16550 oracle.
   `plat-smoke: PASS` still appears (HolyC, `CONFIG_UART_BASE`) and `ORACLE ` disappears.
   This is the bug from §1a reproduced on demand; a one-needle gate passes here.
4. **The needle rule itself.** Feed the checker `PASS` without `ORACLE` and require a
   non-zero exit.
5. **Wrong hart.** Reset PC on hart 0. Silence — the `BOOT_HARTID` gate holds.

`make unmatched-takeover-smoke` — four controls, via `TOS_TAKEOVER_BREAK=`:

| control | what it breaks | expected |
|---|---|---|
| `badpc` | enters at 0x80800000 | fails; lands in OpenSBI's `sbi_trap_error` dump |
| `nopriv` | skips `set $priv = 3` | fails — and it is the reason `smode_idle.S` exists |
| `wronghart` | takes over the E51 instead of a U54 | fails |
| `nofirmware` | `-bios none` | fails: the firmware markers are missing |

`make -n` was used as the negative control for every new Makefile target — this tree has had
a prerequisite that expanded to empty because it referenced a variable assigned 67 lines
later.

---

## 6. What remains for the physical board

**Nothing needs to be built.** No U-Boot, no OpenSBI, no SD card. The board's own firmware
in SPI flash does the one job we cannot do ourselves (train DDR), and then we take the
machine away from it over JTAG. QEMU ships the OpenSBI binary used for the emulated leg
(`/opt/homebrew/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin`); nothing was cross-built.

**And no external probe is needed — but see §7, because the on-board one is the blocker.**
From the schematics (rev 3, sheets 4 and 16), which replace what this tree used to say:

* **The debug interface is an FT2232H on the board**, behind the same micro-USB that carries
  the console: channel A → JTAG, channel B → console. Channel B goes through a TXS0102 to
  UART0 at 1.8 V, 115200. **There is no CP2105 on this board**, and earlier notes calling the
  micro-USB "the CP2105 console" were wrong twice over.
* It enumerates as "Dual RS232-HS", `0403:6010`, with **no USB serial number**, so macOS names
  the two ports by USB location. The lower of the pair is channel A; the numbers move with
  the physical port, so identify them by ordering.
* **`J18` is not a JTAG header.** It is a 2-pin **JTAG mux select jumper** (TS3A5018 mux U12,
  100 K pull-down): no jumper selects the on-board FT2232H (the default), a jumper selects the
  external header. This tree used to describe a "2x6 0.05in JTAG header J18". There is none.
* **`J6` is the external header**: 2x5, Cortex-10 pinout — 1 VDD_1V8 (VTref), 2 TMS, 3 GND,
  4 TCK, 5 GND, 6 TDO, 7 key, 8 TDI, 9 GND, 10 RESET_N.
* **There is no probe fallback with the hardware on hand.** The FU740's JTAG is **1.8 V**; an
  Olimex ARM-USB-TINY-H is a 2.0–5.0 V probe and **must not be connected to J6**. An earlier
  note in this document suggested exactly that as the fallback. It is not one, and it risks
  the SoC.
* **`ADBUS4` = `FT_JTAG_SRST`, active HIGH** through Q8B onto RESET_N. A `layout_init` that
  drives ADBUS4 high **resets the board** — `0x0038` does; the correct `0x0008 0x001b` keeps
  it low. ADBUS5-7 are NC, so SiFive's `nSRST -oe 0x0020` line is inert here.

The measured OpenOCD configs live on the main tree (`hifive_unmatched_ft2232h.cfg`,
`hifive_unmatched_hart1.cfg`); this document does not duplicate them.

**Order**: power on and let the board's own ZSBL → U-Boot SPL → OpenSBI run (SPL is what
trains DDR), then stop at the **U-Boot prompt**. Prefer that over a booted Linux, for three
measured reasons: under Linux the MMU is on, so `satp` is non-zero and gdb's memory writes
are translated — a `load` to 0x80200000 may not land at physical 0x80200000; Linux runs SMP
on all four U74s, so stealing one leaves three to RCU-stall and panic; and a getty owns the
console. **Never `reset halt` a cold board** — that halts the FU740 before DDR exists and
`load` writes into nothing.

Then, and only after the §7 pre-flight:

```
openocd -f tests/openocd/hifive_unmatched_hart1.cfg &
tests/scripts/unmatched_jtag_floor_check.sh 300 0
make kernel-hifive_unmatched && make hello-unmatched
riscv64-elf-gdb -q -batch -ex 'set $tos_elf = ".../hello.elf"' \
    -x tests/gdb/unmatched_takeover_openocd.gdb
```

**Start with `hello.elf`, not the kernel.** 745 bytes of assembly that prints before
touching any CSR (so it survives being entered in S-mode by mistake), then `mhartid`,
`misa`, and an actual `fadd.d`. It separates "can we get code running at all" from "does
the kernel work", and it names the two failures most likely on this board instead of
hanging:

```
TempleOS/RISC-V: hello from the HiFive Unmatched (FU740)
hello: mhartid=1
hello: misa=0x800000000014112d
hello: misa.D set (U74) - running the FPU probe
hello: fadd.d 2.0+3.0 = 5
hello-unmatched: OK
```

and on the wrong hart:

```
hello: misa.D CLEAR - this hart has no FPU
hello: WRONG HART - this is the S7 (hart 0). TempleOS/RV is rv64imafdc/lp64d;
       load and resume on a U74 (hart 1..4) instead.
```

---

## 7. The actual blocker on hardware: a JTAG DMI corruption floor

This is the honest state of the board as of this writing, and it is the reason nothing has
been loaded on it. It is also the most misleading kind of failure, so the numbers matter.

**Adapter speed is not an optimisation, and slower is worse.** Measured over 300+
alternating `dmstatus`/`abstractcs`/`dmcontrol` scans per setting, in one held OpenOCD
session, through the on-board FT2232H:

| setting | stray values in 300+ scans |
|---|---|
| 10 MHz, `tdo_sample_edge falling` | 9 |
| 8 MHz, falling | 6 |
| 8 MHz, rising | 8 (+1 hard error) |
| 6 MHz, falling | 7 |
| 3 MHz | OpenOCD **asserts** (`riscv-013.c:499: info->abits != 0`) |
| 1–2 MHz | total collapse — 0 of 30 reads parse |

So there is a ~2-3% per-scan floor that **no setting reaches zero on**, and below about
4 MHz it is not a floor but a collapse. The original `hifive_unmatched.cfg` advice — "1 MHz
to start, raise to 10 MHz once proven" — was itself the bug.

**Why small probes lie, and why this needed a dedicated check.** Raw
`riscv dmi_write`/`dmi_read` pairs come back 0-bad-out-of-30, and a 60-operation probe looks
perfect. An OpenOCD *target examine* or a *halt* issues **hundreds** of DMI operations, and
OpenOCD treats a single bad DMI status as **fatal, with no retry**. At a 2-3% floor that is
a near-certain failure. This is exactly why an earlier report of "24/24 clean IDCODE reads"
and "found 5 harts" was both true and misleading: those succeeded, and the operations that
matter do not.

`tests/scripts/unmatched_jtag_floor_check.sh` is the pre-flight that reproduces this: 300
`dmstatus` reads over OpenOCD's TCL RPC port, counting everything that is not the modal
value. Run it before `load`, because the alternative is finding out through an assert
half-way through writing to DDR.

**Already ruled out, so do not re-chase them:** macOS FTDI driver contention (identical
under `sudo` after a clean detach), the TDO sample edge (both measured above), TRST/SRST
levels, and the cable and host port (identical after swapping both — a further cable swap
is in progress).

**Where the floor probably comes from, and why no OpenOCD setting fixes it.** The schematic
path is FT2232HL `ADBUS0-3` → **U4, a TXB0104 auto-direction 3.3↔1.8 V level shifter** →
33 R series resistors → the TS3A5018 mux → the SoC. An auto-direction shifter in a
bidirectional JTAG path is a plausible origin for exactly this kind of sporadic sampling
failure, and none of it is reachable from software. Best measured setting is **8–9 MHz with
`tdo_sample_edge falling`** (~1–2%).

**And there is no probe fallback.** See §6: J6 is 1.8 V and the available Olimex probe is
2.0–5.0 V.

**So the plan changed, and this is the important consequence.** A gdb `load` of a
multi-megabyte image is *hundreds of thousands* of DMI operations. At a 1-5% per-scan floor
with no retry, that will not complete — and it is not worth trying to make it. The two
viable hardware paths are:

1. **U-Boot puts the image in DDR** (`tftp 0x80200000 plat.bin`, or from SD) **and JTAG does
   only the dozen operations it alone can do**: halt, force M-mode, set pc, resume. A dozen
   can be retried by hand; a `load` cannot.
2. **Package the M-mode kernel as the SPL's next stage**, so it runs with no debugger at all.
   No takeover, no JTAG — but also no ability to halt and inspect.

Path 1 is what the emulated gate now exercises: `make unmatched-takeover-preloaded` places
the image with QEMU's `-device loader` (standing in for U-Boot's tftp) and then runs the
*same* takeover script with `$tos_skip_load = 1`, so gdb writes nothing and only the
privilege switch, pc and resume happen. Measured:

```
takeover: LOAD=pre -- image placed at 0x80200000 before boot (stands in for U-Boot tftp)
[takeover] mhartid=1 priv=1 pc=0x80400024
[takeover] load SKIPPED: image already in DDR (U-Boot tftp / SD).
[takeover] Only the dozen ops JTAG alone can do follow.
[takeover] entering at 0x80200000 with priv=3 mie=0x0
  -> plat-smoke: PASS, ORACLE 0000000000000000
```

The gate asserts gdb wrote nothing (no `Loading section` lines), or the mode would be
indistinguishable from the default and would prove nothing about the hardware path. All four
negative controls still fail in this mode, including `nopriv` — which matters most here,
because the privilege switch is the one step JTAG has to do either way.

**One state to recognise:** `dmstatus 0x30382` is `allhalted|anyhalted|resumeack`, i.e. a
hart left halted by an earlier session whose resume never ran. That looks like a dead board
and is not one. The floor-check script names it.

---

## 8. Specific things that could still differ on real silicon

Listed because "it works in QEMU" is not a claim about hardware:

* **Everything in §7.** Until an examine and a halt complete reliably, the takeover cannot
  be attempted at all, let alone verified.
* **Hart selection and `set $priv = 3` through OpenOCD.** The only parts of the takeover
  that are not the same code the emulated gate exercises. Check `p/x $mhartid` before
  resuming. If the privilege write is refused, `monitor reg priv 3` is the fallback; if
  *neither* works, stop — S-mode entry is not a fallback (§3).
* **The REPL.** Blocked on two located kernel bugs, not on anything board-specific — §9.
* **The PLIC/`^C` path is untested for this board even under emulation.**
  `CONFIG_UART_IRQ` is now 39, which is right for the FU740 and wrong for `-M sifive_u`
  (which wires UART0 to source 4). So the SiFive-correct `HolyRVUartIrqInit` code is
  compiled and reachable but has never had a real interrupt delivered to it. **Treat `^C`
  in the REPL as unverified.** Polled input does not depend on it (§0).
* **U-Boot generation matters for one thing.** On mainline U-Boot `kernel_addr_r=0x80200000`
  — the same address as our payload. Do not run a boot command after loading, or
  `setenv kernel_addr_r 0x84000000` first. On 2022-era firmware `kernel_addr_r` is already
  `0x84000000` and this does not apply.
* **PCIe, SD, SPI, the Cadence GEM and the framebuffer are all untouched.**
  `CONFIG_SIFIVE_ETH_BASE` is deliberately left 0: the FU740 does have a GEM at 0x10090000,
  but a non-zero base selects `RVSifiveGemYes`, whose loopback self-test has only ever run
  against QEMU's model. `CONFIG_SIFIVE_GPIO_RESET_PIN` stays 32 (none) for the same
  reason — the board's reset pin is unverified, and `RVSifiveCanReset` reporting
  `sifive_no_hw_reset` is the correct answer until someone checks.

---

## 9. The REPL for this board: two kernel bugs, both located

Deliverable-wise this is the one thing that does **not** work, so here is exactly why rather
than a summary. `tests/scripts/run_repl_unmatched_smoke.sh` and
`tests/exec/harness/link_exepubs_hifive_unmatched.ld` are in place and correct — the REPL
image links at 0x80200000, against the SiFive harness, entered on hart 1 — and it still does
not run. Two independent kernel bugs, both pre-existing, both outside this board's own port.

### 9a. The virtio block driver's constants are Kconfig-gated but its body is not

A non-virtio board cannot compile the REPL at all. Three errors:

```
Kernel/RVDisasm.HC:265:23:            Undefined variable 'MEM_VIRTIO'
Kernel/BlkDev/DskVirtioRV.HC:260:25:  Undefined variable 'BDT_VIRTIO'
Kernel/BlkDev/DskVirtioRV.HC:311:60:  Undefined variable 'BDT_VIRTIO'
```

* `MEM_VIRTIO` comes from `kconfig.py`'s `mem_aliases` loop, which only emits an alias when
  the symbol is in `.config`. `CONFIG_VIRTIO_MMIO_BASE` `depends on HAS_VIRTIO_MMIO`, so on
  this board it is absent and the alias is never defined. Note the *sibling* generated header
  does emit `MEM_VIRTIO 0` via `_mem_hex(virtio)` — so the two headers already disagree, and
  making `RVAutoConf.HH` match is a bug fix, not a workaround.
* `BDT_VIRTIO` is defined in `Kernel/KernelA.HH:2610` under `#ifdef RISCV_VIRT`, and
  `RISCV_VIRT` is emitted only for `PLATFORM_VIRT`. Every *consumer* is likewise `#ifdef
  RISCV_VIRT` (6 sites, all in `Kernel/BlkDev/`), but `DskVirtioRV.HC`'s **body is compiled
  unconditionally** — and it cannot simply be wrapped, because this tree's own rule is that
  `#ifdef` around HolyC function bodies turns them into unresolved imports.

**Measured fix, as an experiment (not committed):** defining `MEM_VIRTIO 0` when virtio is
absent, and making `BDT_VIRTIO`/`BDT_TYPES_NUM` unconditional, is enough to compile. Two
lines. It was not landed because `KernelA.HH` is shared with the stock x86 distro and
`BDT_TYPES_NUM` 6 → 7 sizes arrays there; that deserves its own change and its own 12-board
matrix gate, not a rider on this one.

### 9b. `GetTSC` reads the `time` CSR, which SiFive cores do not implement

With 9a patched, the image builds (10.7 MB flat) and then traps immediately:

```
TRAP mcause=0x2 (illegal-insn) mepc=0x808cba64 mtval=0xc0102573 blob+0xcba64
```

`0xc0102573` decodes as `csrrs a0, 0xc01, zero` — `csrr a0, time`. The source is
`Kernel/KUtilsRV.HC:714`:

```
asm {
        GetTSC::
        rdtime  a0
        ret
}
```

This works on `-M virt` (whose default CPU is the generic `rv64`) and is illegal on
`-M sifive_u` (`sifive-u54`), which is why no existing gate caught it. **It is not merely a
QEMU-model artifact:** SiFive's U-series cores do not implement the `time` CSR in the core
either — `rdtime` traps and is conventionally emulated by M-mode firmware. Since an M-mode
takeover replaces `mtvec` with our own, nothing emulates it, so this would trap on real FU740
silicon too.

The fix is to read the CLINT's memory-mapped `mtime` (`MEM_CLINT + CONFIG_CLINT_MTIME_OFF`,
which `RVClintMtime()` already does) instead of `rdtime` whenever the platform is not virt.
That is also a shared-kernel change touching every board's timestamp path — `GetTSC` feeds
RedSea `unique_id` and mouse/keyboard timing — so, like 9a, it wants its own change with the
matrix as its gate.

**What this means for the goal.** `hc_repl` on an Unmatched over serial needs 9a and 9b
fixed; neither is about the board description, the UART, the link address or the hart, all of
which are now correct and gated. The plat kernel, which exercises UART + CLINT + PLIC +
MemMap through the full takeover, does run.

---

## 10. It runs on the hardware

The plat kernel built here — SiFive-UART C harness, linked at 0x80200000, hart 1 — has run on
a real HiFive Unmatched. Recorded because it settles several of the questions above
empirically, and because the procedure is now repeatable.

**What was done** (the tooling lives on the main tree: `tools/unmatched/load_and_takeover.sh`,
`dmi_takeover.py`, and `docs/UNMATCHED_JTAG.md`, which is the measured record):

1. Reset-catch into the U-Boot prompt, so SPL + OpenSBI had trained DDR.
2. `loady 0x80200000` in U-Boot + `sz --ymodem` on the host — ~50 s for 323 KB at 115200.
3. `crc32` in U-Boot over the DDR range, compared against the file. This step is not
   optional; see the note about SPL below.
4. A **raw-DMI** takeover (not OpenOCD's target layer): halt hart 1, `mie = 0`,
   `mstatus.MIE = 0`, `dcsr.prv = 3`, `dpc = 0x80200000`, resume.
5. Output on UART0: every `plat-smoke` line exactly once, `plat-smoke: PASS`, and
   `ORACLE 0000000000000000`.

**What that confirms.** The SiFive UART harness (the `ORACLE` line is the C half, §1a), the
hart-1 `crt0` gate (§1b — the alternative plan of entering at `0x80200008` to skip a hart-0
check would have landed mid-instruction on this image), the 0x80200000 load address (§2), and
M-mode entry over an inherited OpenSBI machine with its PMP untouched (§3). The hart was
halted at `prv=1`, `pc=0xfff93c42` — inside relocated U-Boot — so the S-mode-to-M-mode switch
the emulated gate rehearses is exactly the switch the hardware needed.

### The verified memory map, from the board

`bdinfo` / `printenv` on the board, with U-Boot 2021.01:

| region | contents |
|---|---|
| `0x80000000`–`0x80040000` | OpenSBI, reserved (matches the 337 KB / Domain0 regions in §2) |
| **`0x80200000`** | **our payload.** Clear — but see the warning below |
| `0x84000000` | U-Boot `kernel_addr_r` |
| `0x88000000` / `0x88300000` | U-Boot `fdt_addr_r` / `ramdisk_addr_r` |
| `0xff73d0e0` | the FDT U-Boot passes on |
| `0xfff63000` | **relocated U-Boot** — i.e. just under 4 GiB, exactly as `arch/riscv/cpu/fu740/dram.c`'s `SZ_4G` cap predicts (§2), not near the top of the 16 GiB |
| `0x80000000` + 16 GiB | DRAM |

**The warning, learned the hard way: SPL reuses 0x80200000 as its FIT load address on every
boot.** So anything placed there is gone after a reset and must be re-loaded — and a takeover
that skips the re-load lands in *leftover image bytes* from the previous cycle, which looks
like a successful run of the wrong thing. That is what the `crc32` step in the procedure is
for, and it is why 0x80200000 being "clear" means clear *while the board sits at the prompt*,
not reserved for us.

### Why the takeover must not trust a single DMI read

Two real failures on hardware made this non-negotiable, and they are worth knowing because
both looked like something else:

* A **silently lost `command` write** left `dpc` holding a previous `x8` value, so the hart
  resumed to `0x4000b0c2` and took `mcause=1`. It looked like a bad payload.
* `dmstatus` came back `0x80018642` — corrupt, but with the `allhalted` bit set — and passed a
  bare mask check while the hart was **still running**.

So every read is the consensus of two consecutive identical plausible reads, and every write
is read back. The takeover is ~40 raw DMI operations under that rule. Also note the FU740's
debug module **rejects abstract CSR access** (`cmderr=2`): CSRs are read through the **program
buffer** (`csrr s0, CSR; ebreak` + postexec, value out via GPR `x8`).

### Getting a multi-megabyte image onto the board

Two transports, and the one you would reach for first does not work on the stock card.

**tftp is blocked by a U-Boot bug, not by the network.** U-Boot 2021.01 — what ships on the
SD card — cannot transmit at gigabit on this SoC: the FU740 GEM has a TX-clock bug that was
fixed upstream in **2021.04**. The symptom is specific and misleading, because the link looks
perfectly healthy: PHY negotiates **1000FDX, link up**, and then every BOOTP packet dies with
`TX timeout`. Forcing 100 Mb with `mii` does not survive, either — the `macb` driver
re-autonegotiates on each `dhcp`, so the force is undone before the transfer starts. So tftp
needs **either a switch port forced to 100 Mb, or a newer U-Boot**. A v2025.01 build for
`sifive_unmatched` is the fix in progress; on this card SPL goes to the GPT partition of type
`5b193300` (p1) and `u-boot.itb` to type `2e54b353` (p2).

**ymodem works today and is the fallback.** `loady 0x80200000` in U-Boot plus `sz --ymodem`
on the host: measured ~50 s for 323 KB, so roughly **6 minutes for 3.5 MB** at 115200.
Acceptable, and it needs nothing but the console that is already attached.

Either way, `crc32` in U-Boot over the loaded range, compared against the file, before the
takeover — see the SPL warning above for why that is not optional.

### Two things the emulated gate could not have told us

* **CRLF.** The console showed a staircase: every line fed but never returned. QEMU
  `-nographic` cooks its own output and hides this completely. Fixed in
  `Kernel/Drv/RVSifiveYes.HC`'s `RVSifiveUartPutS` — the driver, not a hundred format
  strings.
* **Enter at `_start`, never at an offset.** `crt0.S` now masks interrupts before installing
  `mtvec` (two instructions), so every offset inside the prologue has moved. `0x80200000` is
  the only entry point.

---

## 11. The REPL image

`make unmatched-takeover-preloaded TAKEOVER=repl` takes the REPL image over from OpenSBI on
hart 1 in S-mode and reaches its prompt. `tests/scripts/run_repl_unmatched_smoke.sh` builds it
and requires **`ans=5`** out for `2+3;` in — the REPL having *compiled and evaluated*, not
merely printed a prompt.

Three board-specific things and nothing else: the FU740 Kconfig applied (so the HolyC half's
`CONFIG_UART_BASE` is 0x10010000), the C harness built for the SiFive register layout at that
base, and linked at 0x80200000 entering on hart 1.

### The third virt-hardwired console, and the assertion that was checking the wrong file

§1a fixed the C harness. §9 fixed two kernel bugs. There was a **third**, and it is the one
that actually killed the first image on hardware — in the *test case itself*:

```
tests/exec/cases/kernel_repl_exepubs_demo.hc:18
    #define MEM_UART 0x10000000
    U0 UartPutC(I64 ch) { U8 *uart = MEM_UART; *uart = ch; }
```

That overrides the Kconfig-generated `MEM_UART` with virt's 16550 base and byte-stores to it.
On an FU740 that address is the PRCI, so every banner the demo prints — `A2 ExePutS REPL`
included — was a byte store into the clock controller. Invisible on `-M virt`, where the
address really *is* the UART, which is why `make repl-cmp-smoke` passes there and why this
needed hardware (or an honest board model) to find.

The case is owned elsewhere, so the build does not edit it: it writes a variant whose
`UartPutC` delegates to the Kconfig-selected driver (SiFive-correct and CRLF-correct on every
board) and **asserts the substitution happened** — a silent no-op would put the fault straight
back. It also asserts the variant contains no `0x10000000` at all, which promptly caught the
literal in my own explanatory comment.

**Three process lessons, each of which cost a cycle:**

* **Assert on the artifact the compiler reads.** The script checked `templeos-riscv/.config`
  and reported the base as correct while `Kernel/RVAutoConf.HH` — what `#include` actually
  pulls in — could disagree. It now asserts on `RVAutoConf.HH` *and* on
  `Kernel/Drv/RVUartSelected.HH` / `RVSifiveSelected.HH`, because the driver selection is a
  third artifact that can disagree with both.
* **A map from a different board's config mis-attributes every address.** Resolving the fault
  through a map built with virt's headers named `RVExePubsWireDbg`; a map built with the
  board's headers named `UartPutC+0x60`, which was correct. The build now emits
  `build/exec/repl_unmatched.map` beside the binary and the smoke resolves fault addresses
  through it automatically.
* **Scaffolding can collide with the payload.** The S-mode stub sat at 0x80400000, fine for the
  323 KB plat image and silently clobbered by the 5.4 MB REPL image, which presents as the
  whole takeover failing with no S-mode banner and no obvious cause. Moved to 0x84000000, and
  the runner now asserts payload and stub do not overlap.

### Size

5,489,712 bytes flat, 36% of it zero. The blob VMA moved from `link_exepubs.ld`'s 0x80800000
down to 0x80300000, which cut ~7.2 MB of linker-gap zeros — safe because nothing refers to the
blob by absolute address (crt0 reaches it with `la`, import slots are blob-relative, and a scan
for 8-byte words pointing into the old blob window found zero).

### Residual imports: 8 symbols the C runtime stubs to 0

`tools/blob_imports.py` reports 32 lines; eight print `[import unresolved: …]` at boot and are
stubbed to return 0. **None is dereferenced as a pointer, so none traps** — but two return
wrong *values*, which is worth knowing before reading anything they feed:

| symbol | type | consequence |
|---|---|---|
| `RVUartSoftEnqueue` | `U0` | harmless |
| `DocFormBwd`, `DocFormFwd` | `U0` | harmless — interactive DolDoc form editing, not reachable from a serial REPL |
| `DocDataFmt`, `DocDataScan` | `U0` | harmless, same |
| `PopUpPickLst` | `I64` | returns 0, i.e. "picked item 0"; needs a window to reach at all |
| `ToU64` | `U64` | **returns 0**, so the asm-UI's unsigned branch-taken display compares 0 with 0 and is wrong |
| `GetMcause` | `I64` | **returns 0**, so anything displaying it reads mcause=0. The REPL's own fault path uses `RVTrapRecoverCause()`, not this. |

### What in the image still assumes virt: at driver level, nothing

The board's Kconfig selects `RVVirtioMmioNo`, `RVFbKindNone`, `RVUartSifive`, `RVTimerClint`,
`RVPlicHw`, `RVSifiveYes`, and `HAS_FW_CFG` / `FB_PRESENT_RAMFB` / `HAS_GOLDFISH_RTC` /
every `HAS_VIRTIO_*` are off. So virtio, fw_cfg, ramfb and the goldfish RTC are all compiled
out or stubbed rather than reachable. The residual risk is the eight symbols above.

### It wants nothing in a0/a1

`crt0.S` never reads them, `resolve_imports(void)` takes no arguments, and the blob is entered
by `jalr` with no argument setup. No DTB either — every address comes from Kconfig at compile
time, which is also why the firmware's device tree at 0x87e00000 being inside the MEMFS window
does not matter.

### Enter at `_start`, never at an offset

`crt0.S` masks interrupts (`csrw mie, zero; csrci mstatus, 8`) before installing `mtvec`,
verified by disassembly, so the image is safe entered from any prior state — including as the
SPL's next stage with no debugger. That also moved every offset inside the prologue.
0x80200000 is the only entry point.
