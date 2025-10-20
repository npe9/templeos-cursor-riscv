/* RISC-V Linker Script for Bootstrapping */
/* QEMU virt machine memory layout */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* QEMU virt machine RAM starts at 0x80000000 */
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS
{
    . = 0x80000000;
    
    /* Code section */
    .text : {
        *(.text.init)
        *(.text .text.*)
        . = ALIGN(8);
    } > RAM
    
    /* Read-only data */
    .rodata : {
        *(.rodata .rodata.*)
        . = ALIGN(8);
    } > RAM
    
    /* Data section */
    _data_start = .;
    .data : {
        *(.data .data.*)
        . = ALIGN(8);
    } > RAM
    
    /* BSS section */
    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(8);
        _bss_end = .;
    } > RAM
    
    /* Global pointer */
    __global_pointer$ = MIN(_data_start + 0x800, MAX(_data_start + 0x800, _bss_end - 0x800));
    
    /* Stack (grows downward) */
    . = ALIGN(0x1000);
    _stack_top = .;
    . = . + 0x400000; /* 4MB stack */
    
    /* Heap starts after stack */
    . = ALIGN(0x1000);
    _heap_start = .;
    
    /* End of image */
    _end = .;
}

