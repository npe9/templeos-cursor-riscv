/* smode_idle.S — a stand-in for U-Boot proper, so the emulated takeover rehearsal is
 * actually apples-to-apples about PRIVILEGE.
 *
 * Why this file exists. On the board, the hart you halt is running U-Boot proper, which
 * OpenSBI started in S-MODE. Under QEMU with OpenSBI and no payload, OpenSBI has nothing
 * to mret into: it tries to jump to next address 0x0, takes a fault, and sits in its own
 * M-mode trap handler. So a hart halted under QEMU is already in M-mode, and the
 * `set $priv = 3` line in the takeover script is a silent no-op — measured: the
 * TOS_TAKEOVER_BREAK=nopriv control PASSED, which means that leg was not testing the one
 * thing most likely to differ on hardware.
 *
 * Hand this to QEMU as -kernel and OpenSBI mrets into it in S-mode, and now the emulated
 * hart is in the same privilege state as a board sitting at the U-Boot prompt. The nopriv
 * control then fails, as it must.
 *
 * It is deliberately three useful instructions and no CSR access: reading mhartid or
 * writing mtvec from S-mode is an illegal instruction, which is the whole point. The UART
 * is reachable because OpenSBI's PMP grants S/U R+W+X to everything outside its own
 * region (measured: pmpcfg0=0x1f1b181818, entry 4 = whole space S/U RWX).
 *
 * Linked at 0x80400000, NOT 0x80200000, so it does not sit where the TempleOS payload
 * will be loaded. See link_smode_idle.ld.
 */

  .equ UART0, 0x10010000     /* SiFive UART TXDATA, bit31 = FULL */

  .section .text.init,"ax",@progbits
  .globl _start
_start:
  lla   t3, msg
  li    t0, UART0
1:
  lbu   t4, 0(t3)
  beqz  t4, 3f
2:
  lw    t1, 0(t0)
  bltz  t1, 2b
  sw    t4, 0(t0)
  addi  t3, t3, 1
  j     1b
  /* The "prompt". A halted hart here is in S-mode, like the board's. The label is
   * global so the takeover script can break HERE rather than at _start: breaking at
   * the entry would stop before the banner is printed, and the banner is the gate's
   * evidence that firmware really mret'd into S-mode. */
  .globl _at_prompt
3:
_at_prompt:
  wfi
  j     3b

  .section .rodata,"a",@progbits
msg:
  .asciz "smode-stub: S-mode idle (stands in for the U-Boot prompt)\n"
