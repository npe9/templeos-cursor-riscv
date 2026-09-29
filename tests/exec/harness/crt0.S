# Call HolyC blob as I64 (*)(void); then print result for oracle harness.
# Multi-hart boards (icicle, …): only hart 0 runs the blob; others park in WFI
# so UART smoke lines are not interleaved across harts.
.section .text.init
.global _start

/* Which hart runs the image. 0 on every board where hart 0 is a full application
 * core. NOT the FU740/FU540: there hart 0 is the S7/E51 management core, which is
 * rv64imac — no F, no D — while harts 1..4 are U74/U54 (rv64gc). This image is built
 * -march=rv64imafdc -mabi=lp64d, so on those SoCs it must run on hart 1, and a
 * `bnez t0, halt` gate would pin it to precisely the hart that cannot execute it.
 * Verified under -M sifive_u: cpu 0 misa=0x8000000000101105 (D clear),
 * cpu 1 misa=0x800000000014112d (D set). See tests/exec/harness/hello_unmatched.S. */
#ifndef BOOT_HARTID
#define BOOT_HARTID 0
#endif
_start:
    csrr t0, mhartid
#if BOOT_HARTID == 0
    bnez t0, wrong_hart
#else
    li t1, BOOT_HARTID
    bne t0, t1, wrong_hart
#endif
    # Mask interrupts before anything else, because this image is no longer only ever
    # entered from reset. A JTAG takeover (tests/gdb/unmatched_takeover.gdb) enters it on
    # a hart that firmware was using, and on the Unmatched OpenSBI leaves mie=0x8 (MSIE,
    # for its IPIs) and its own mtvec installed. If mstatus.MIE is then set — which
    # RVTrapInit does — a pending machine software interrupt fires into a handler that
    # knows nothing about OpenSBI's IPI protocol. The takeover script masks these too,
    # but doing it here is what makes the image safe to enter from ANY prior state,
    # including as the SPL's next stage with no debugger involved. From reset these are
    # already zero, so this costs two instructions and changes nothing on any board that
    # boots normally.
    csrw mie, zero            # no source enabled
    csrci mstatus, 8          # mstatus.MIE = 0 (global gate off)
    # PMP is deliberately NOT touched. After a takeover we inherit OpenSBI's entries
    # (measured: pmpcfg0=0x1f1b181818 fencing the CLINT and firmware off from S/U), and
    # none of them has the L (lock) bit 0x80 set — so they do not apply to M-mode, which
    # is the only mode this kernel ever runs in. There is nothing to undo, and writing
    # PMP here would only risk locking ourselves out of the firmware region we are
    # allowed to reuse.
    #
    # Install a trap vector FIRST. Without one, mtvec is 0, so any fault jumps to
    # address 0, faults again fetching there, and loops forever — a silent hang with
    # no output, indistinguishable from an infinite loop.
    # This is a floor, not a policy: guests that want their own handler install it
    # later and win (bootstrap/holy_rt.h RVTrapInit / RVPreemptInit / RVTrapDiag /
    # RVPreemptReal all csrw mtvec). What this covers is the window before that —
    # which is where the faults nobody could see were happening.
    la t0, trap_entry         # 4-aligned => mtvec MODE=0 (direct)
    csrw mtvec, t0
    # Zero the memory this image ASSUMES is zero, because on real DRAM it is not.
    #
    # QEMU hands out zeroed RAM, so every gate in this tree has been testing against pristine
    # memory. A HiFive Unmatched's DDR held 0xff and the REPL image died in MAlloc reading a
    # heap-control pointer out of a window nobody had written: Kernel/KBootRV.HC puts
    # `CHeapCtrl *the_heap` at a FIXED 0x82000000 and MAlloc's first act is
    # `the_heap->malloc_free_lst`. Zero reads as an empty free list and takes the bump path;
    # 0xff reads as a list head of -1, and `f->size` then loads through -1. Reproduced on the
    # model by pre-filling 0x82000000..0x86000000 with 0xff via -device loader: the same
    # blob+0x115f20 the board reported.
    #
    # Two ranges. Both are done BEFORE sp is set, so the loop can never be zeroing the stack
    # it is standing on.
    #
    #   __bss_start/__bss_end  .bss is NOBITS, so `objcopy -O binary` emits nothing for it. It
    #                          has only ever been zero because it happens to sit BELOW a later
    #                          fixed-VMA section, which makes objcopy pad the gap — layout luck,
    #                          not a guarantee. Every linker script that uses this crt0 defines
    #                          these two symbols, and until now nothing referenced them.
    #   ZERO_BASE/ZERO_LEN     a window the image treats as pristine that no section covers, so
    #                          no linker symbol can describe it. Passed as -D (materialised with
    #                          li, which handles a full 64-bit address — `la` on a weak
    #                          undefined symbol would be a PC-relative range error). Default 0,
    #                          which emits no second loop at all.
    la t0, __bss_start
    la t1, __bss_end
    call zero_range
#ifndef ZERO_LEN
#define ZERO_LEN 0
#endif
#if ZERO_LEN > 0
    li t0, ZERO_BASE
    li t1, ZERO_BASE + ZERO_LEN
    call zero_range
#endif
    li t0, (1 << 13)          # mstatus.FS = Initial: F64 code traps otherwise
    csrs mstatus, t0
    la sp, __stack_top
    mv s0, sp
    call resolve_imports       # fill the blob's runtime import slots (bootstrap/holy_rt.h)

    la ra, after_user
    la t0, _binary_blob_bin_start
    jalr zero, t0, 0

after_user:
    call oracle_report
halt:
    wfi
    j halt

# A hart that is not the boot hart stops here. Silently, until now: if whatever enters this
# image picks a different hart than it was built for, the board simply produces nothing, which
# looks exactly like a bad load address, a dead UART, or a wedged card. That distinction matters
# most where there is no debugger attached -- being loaded by a bootloader off an SD card -- so
# when the build names a UART, say which hart arrived before going quiet. Guarded, so every
# other platform's image is byte-identical to before.
wrong_hart:
#ifdef BOOT_REPORT_UART
    li t2, BOOT_REPORT_UART
    li t3, 104                # 'h'
1:  lw t4, 0(t2)              # txdata bit31 = FIFO full; lw sign-extends, so full => negative
    bltz t4, 1b
    sw t3, 0(t2)
    andi t3, t0, 7            # t0 is still mhartid
    addi t3, t3, 48           # -> ASCII digit
2:  lw t4, 0(t2)
    bltz t4, 2b
    sw t3, 0(t2)
    li t3, 13                 # CR
3:  lw t4, 0(t2)
    bltz t4, 3b
    sw t3, 0(t2)
    li t3, 10                 # LF
4:  lw t4, 0(t2)
    bltz t4, 4b
    sw t3, 0(t2)
#endif
    j halt

# zero_range(t0 = start, t1 = end): byte loop, so it needs no alignment guarantee from the
# linker script and cannot overrun the end. Uses NO STACK — it is called before sp exists —
# and clobbers only t0. 284 KiB of .bss is a few hundred thousand stores, which is nothing
# once at boot and is the difference between running on real DRAM and not.
zero_range:
    bgeu t0, t1, 2f
1:
    sb zero, 0(t0)
    addi t0, t0, 1
    bltu t0, t1, 1b
2:
    ret

# Fatal-fault handler: report mcause/mepc/mtval and stop. Runs on its own stack
# because the faulting sp may be exactly what is broken. Does not return — a trap
# here means the case is dead, and halting beats spinning silently.
    .align 2
trap_entry:
    la sp, __trap_stack_top
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call trap_report
trap_halt:
    wfi
    j trap_halt

    .section .bss
    .align 4
trap_stack:
    .space 512
__trap_stack_top:

# QEMU spike HTIF console symbols (st_size must be 8). Linked @ 0x807FF000.
.section .tohost, "aw", @progbits
.align 6
.globl tohost
tohost:
    .dword 0
    .size tohost, 8
.align 6
.globl fromhost
fromhost:
    .dword 0
    .size fromhost, 8
