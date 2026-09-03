// TempleOS/RISC-V split bootloader — HolyC asm{} AOT'd by host holyc-riscv.
// Product guest image: no gcc/gas/ld. Pack with pack_bootloader.py.
//
// boot_cfg.hc (generated) supplies ENTRY_POINT / copy addresses as numeric literals.
// #ifdef BOOT_COPY wraps whole asm{} blocks (HolyC #if NAME is define-presence).
#include "boot_cfg.hc"
#ifdef BOOT_COPY
asm {
	_start::
	csrw	0x304, zero
	csrw	0x344, zero
	csrr	t0, mhartid
	bnez	t0, halt
	li	t0, PAYLOAD_SRC
	li	t1, PAYLOAD_END
	li	t2, ENTRY_POINT
	copy_loop:
	bge	t0, t1, go
	ld	t3, 0(t0)
	sd	t3, 0(t2)
	addi	t0, t0, 8
	addi	t2, t2, 8
	j	copy_loop
	go:
	li	t0, ENTRY_POINT
	jr	t0
	halt:
	wfi
	j	halt
}
#else
asm {
	_start::
	csrw	0x304, zero
	csrw	0x344, zero
	csrr	t0, mhartid
	bnez	t0, halt
	li	t0, ENTRY_POINT
	jr	t0
	halt:
	wfi
	j	halt
}
#endif
