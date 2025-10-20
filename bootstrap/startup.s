# RISC-V Startup Code for Bootstrapping
# Minimal initialization for bare-metal RISC-V

.section .text.init
.global _start

_start:
    # Disable interrupts
    csrw mie, zero
    csrw mip, zero
    
    # Set up stack pointer
    # QEMU virt machine has RAM at 0x80000000
    # Reserve first 4MB for code/data, stack grows down from there
    la sp, _stack_top
    
    # Clear BSS section
    la t0, _bss_start
    la t1, _bss_end
clear_bss:
    beq t0, t1, clear_bss_done
    sd zero, 0(t0)
    addi t0, t0, 8
    j clear_bss
clear_bss_done:
    
    # Set up global pointer
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    
    # Set up trap vector (optional, for now point to a simple handler)
    la t0, _trap_handler
    csrw mtvec, t0
    
    # Initialize frame pointer (s0) to match stack pointer
    # This is needed for functions that save/restore s0
    mv s0, sp
    
    # Jump to main
    call main
    
    # If main returns, halt
_halt:
    wfi
    j _halt

# Simple trap handler (just halt for now)
.align 4
_trap_handler:
    # Save context if needed
    # For now, just halt
    j _halt

.section .bss
.align 12
    .space 0x400000  # 4MB stack
_stack_top:

.section .data
_bss_start:
    .quad 0

_bss_end:
    .quad 0


