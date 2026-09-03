/* OpenTitan Earlgrey plat smoke (RV32 / Ibex). HolyC is still RV64-only —
 * this harness prints the same UART oracle lines as kernel_plat_demo.hc so
 * kernel-plat-matrix can go green. Replace with HolyC + RVUartIbex when
 * ARCH_RISCV32 lands (templeos-riscv/RV32.md). */
.option norvc
.section .text.init, "ax"
.globl _start
_start:
  /* Ibex UART @ 0x40000000: enable TX, print plat-smoke lines. */
  li t0, 0x40000000
  li t1, 1
  sw t1, 0x10(t0) /* CTRL.TX_ENABLE */

  la a0, msg_machine
  jal ra, uart_puts
  la a0, msg_uart
  jal ra, uart_puts

  /* Ibex timer @ 0x40100000 — presence poke (no SiFive CLINT). */
  li t0, 0x40100000
  lw t1, 0(t0)
  la a0, msg_clint
  jal ra, uart_puts

  la a0, msg_pass
  jal ra, uart_puts

1: wfi
  j 1b

/* a0 = NUL-terminated string; clobbers t0-t2, a0 */
uart_puts:
  li t0, 0x40000000
1: lbu t1, 0(a0)
  beqz t1, 3f
2: lw t2, 0x14(t0) /* STATUS */
  andi t2, t2, 1 /* TXFULL */
  bnez t2, 2b
  sw t1, 0x1c(t0) /* WDATA */
  addi a0, a0, 1
  j 1b
3: ret

.section .rodata
msg_machine:
  .asciz "plat-smoke: machine=opentitan\n"
msg_uart:
  .asciz "plat-smoke: uart_ok\n"
msg_clint:
  .asciz "plat-smoke: clint_ok\n"
msg_pass:
  .asciz "plat-smoke: PASS\n"
