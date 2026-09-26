/* hello_unmatched.S — the smallest thing that answers "is our code running on the
 * HiFive Unmatched at all?", separately from "does the kernel work?".
 *
 * Pure RV64 assembly. No C, no runtime, no relocations, no heap, no stack use in
 * the print helpers (they are leaves), and no CSR write before the first line of
 * output. Load it over JTAG at 0x80200000, set pc, resume; read UART0 at 115200 8N1.
 *
 * It is also a board *probe*, because three things about this board can make a
 * perfectly good kernel image look dead, and each one has a different fix:
 *
 *   1. Privilege. At the U-Boot prompt the hart is in S-mode. If you set pc and
 *      resume without raising the privilege level, the first `csrr mhartid` is an
 *      illegal instruction and OpenSBI's trap handler eats you. So this payload
 *      prints its banner with a plain MMIO store FIRST (legal in S-mode, and
 *      OpenSBI's PMP grants S/U access to everything outside its own region), and
 *      only then touches a machine CSR. Banner but nothing after it => you are not
 *      in M-mode; in OpenOCD, `reg priv 3` before `resume`.
 *
 *   2. Which hart. The FU740 is 1x S7 (hart 0) + 4x U74 (harts 1-4). Hart 0 has no
 *      F/D — it is rv64imac. TempleOS/RV is built -march=rv64imafdc -mabi=lp64d, so
 *      it must run on a U74. This prints mhartid and misa and then actually executes
 *      an fadd.d, so "wrong hart" shows up as a named failure instead of a hang.
 *      QEMU -M sifive_u models the same split (cpu 0 = sifive-e51, cpu 1 = sifive-u54),
 *      which is why this payload is testable under emulation.
 *
 *   3. The UART. 0x10010000 is a SiFive UART: 32-bit TXDATA at +0 with a FULL bit in
 *      bit 31. A byte store to 0x10000000 (virt's 16550 THR) hits the FU740 PRCI —
 *      the clock controller — and prints nothing while quietly writing to clocks.
 *
 * Nothing here needs U-Boot to be built or replaced: the board's own firmware trains
 * DDR and brings UART0 up, and then we take the machine over.
 */

  .equ UART0,        0x10010000   /* FU740 UART0 (SiFive, not 16550) */
  .equ UART_TXDATA,  0x00         /* bit31 = FULL */

  .section .text.init,"ax",@progbits
  .globl _start
_start:
  /* A stack, PC-relative, so the payload works at whatever address it was loaded
   * at. The helpers below are leaves and do not need it; a later addition would. */
  lla   sp, _stack_top

  /* (1) Banner with no CSR access, so it survives being entered in S-mode. */
  lla   a0, msg_banner
  call  puts

  /* (2) mhartid: the first machine CSR. If output stops here, see note 1 above. */
  lla   a0, msg_hart
  call  puts
  csrr  a0, mhartid
  call  puthex1
  call  putnl

  /* misa: which extensions this hart really has. */
  lla   a0, msg_misa
  call  puts
  csrr  a0, misa
  call  puthex16
  call  putnl

  /* (3) D extension present?  misa bit 3 = 'D'. Do not execute an FP instruction on
   * a hart that lacks it — that is an illegal instruction, not a slow path. */
  csrr  t0, misa
  andi  t1, t0, (1 << 3)
  bnez  t1, have_d

  lla   a0, msg_no_d
  call  puts
  lla   a0, msg_wrong_hart
  call  puts
  j     spin

have_d:
  lla   a0, msg_has_d
  call  puts
  /* mstatus.FS = Initial (1<<13). Without it every FP instruction traps even on a
   * hart that has the unit. */
  li    t0, (1 << 13)
  csrs  mstatus, t0
  /* A real double-precision add, so "the FPU works" is executed, not inferred. */
  li    a0, 2
  fcvt.d.l fa0, a0
  li    a0, 3
  fcvt.d.l fa1, a0
  fadd.d   fa2, fa0, fa1
  fcvt.l.d a0, fa2
  lla   a0, msg_fp
  call  puts
  fcvt.l.d a0, fa2
  call  puthex1
  call  putnl

  /* The line a gate greps for. Reaching it means: code fetched and executed from the
   * address we loaded it at, machine CSRs readable, the right hart, FPU live, and the
   * SiFive UART at 0x10010000 carrying output. */
  lla   a0, msg_ok
  call  puts

spin:
  wfi
  j     spin

/* --- output helpers. Leaves: no stack, no calls, no CSRs. ---------------------- */

/* puts(a0 = NUL-terminated string). Clobbers t0,t1,t3,t4. */
puts:
  mv    t3, a0
  li    t0, UART0
1:
  lbu   t4, 0(t3)
  beqz  t4, 3f
2:
  lw    t1, UART_TXDATA(t0)   /* lw sign-extends: FULL (bit31) => negative */
  bltz  t1, 2b
  sw    t4, UART_TXDATA(t0)
  addi  t3, t3, 1
  j     1b
3:
  ret

/* puthex1(a0 = value): low nibble only. Clobbers t0,t1,t6. */
puthex1:
  andi  t6, a0, 15
  li    t1, 10
  blt   t6, t1, 1f
  addi  t6, t6, 'a' - 10
  j     2f
1:
  addi  t6, t6, '0'
2:
  li    t0, UART0
3:
  lw    t1, UART_TXDATA(t0)
  bltz  t1, 3b
  sw    t6, UART_TXDATA(t0)
  ret

/* puthex16(a0 = value): all 16 nibbles, high first. Clobbers t0,t1,t2,t5,t6. */
puthex16:
  li    t5, 60
1:
  srl   t6, a0, t5
  andi  t6, t6, 15
  li    t2, 10
  blt   t6, t2, 2f
  addi  t6, t6, 'a' - 10
  j     3f
2:
  addi  t6, t6, '0'
3:
  li    t0, UART0
4:
  lw    t1, UART_TXDATA(t0)
  bltz  t1, 4b
  sw    t6, UART_TXDATA(t0)
  addi  t5, t5, -4
  bgez  t5, 1b
  ret

/* putnl(): one '\n'. Clobbers t0,t1,t4. */
putnl:
  li    t0, UART0
  li    t4, '\n'
1:
  lw    t1, UART_TXDATA(t0)
  bltz  t1, 1b
  sw    t4, UART_TXDATA(t0)
  ret

  .section .rodata,"a",@progbits
msg_banner:
  .asciz "\nTempleOS/RISC-V: hello from the HiFive Unmatched (FU740)\n"
msg_hart:
  .asciz "hello: mhartid="
msg_misa:
  .asciz "hello: misa=0x"
msg_has_d:
  .asciz "hello: misa.D set (U74) - running the FPU probe\n"
msg_no_d:
  .asciz "hello: misa.D CLEAR - this hart has no FPU\n"
msg_wrong_hart:
  .asciz "hello: WRONG HART - this is the S7 (hart 0). TempleOS/RV is rv64imafdc/lp64d;\n       load and resume on a U74 (hart 1..4) instead.\n"
msg_fp:
  .asciz "hello: fadd.d 2.0+3.0 = "
msg_ok:
  .asciz "hello-unmatched: OK\n"

  .section .bss,"aw",@nobits
  .align 4
  .space 4096
_stack_top:
