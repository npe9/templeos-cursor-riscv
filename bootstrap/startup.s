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
    
    # Enable the FPU: mstatus.FS = Initial (01). The compiler is built -mabi=lp64d and touches
    # doubles (lexer token_f64), and any F64 code we emit needs it too; FS=Off traps on the first
    # floating-point instruction (illegal instruction, mcause 2).
    li t0, (1 << 13)
    csrs mstatus, t0
    # Initialize frame pointer (s0) to match stack pointer
    # This is needed for functions that save/restore s0
    mv s0, sp

    # (No hardcoded UART poke here: startup uses only linker-defined symbols, so it is
    #  platform-agnostic. The REPL prints its own "> " prompt once main runs, and the UART
    #  base for actual I/O is set per platform via -DUART_BASE in worry_dream_repl.c.)

    # Jump to main
    call main
    
    # If main returns, halt
_halt:
    wfi
    j _halt

# Pre-main halt stub. TrapInit() installs C TrapVec→TrapCtxSave→trapvec→TrapCtxRestore.
.align 4
_trap_handler:
    j _halt

.section .bss
.align 12
    .space 0x100000  # 1MB stack (reduced from 4MB)
_stack_top:

# Remove duplicate symbol definitions - linker script provides these


