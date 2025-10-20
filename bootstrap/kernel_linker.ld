/* Linker script for HolyC kernel */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS
{
    . = 0x80000000;
    
    .text : {
        *(.text.init)
        *(.text .text.*)
        . = ALIGN(8);
    } > RAM
    
    .rodata : {
        *(.rodata .rodata.*)
        . = ALIGN(8);
    } > RAM
    
    /* HolyC kernel binary */
    .holyc_kernel : {
        _binary_templeos_kernel_bin_start = .;
        KEEP(*(.data.templeos_kernel))
        _binary_templeos_kernel_bin_end = .;
        . = ALIGN(8);
    } > RAM
    
    .data : {
        _data_start = .;
        *(.data .data.*)
        . = ALIGN(8);
    } > RAM
    
    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(8);
        _bss_end = .;
    } > RAM
    
    __global_pointer$ = MIN(_data_start + 0x800, MAX(_data_start + 0x800, _bss_end - 0x800));
    
    . = ALIGN(0x1000);
    _stack_top = .;
    . = . + 0x400000;
    
    . = ALIGN(0x1000);
    _heap_start = .;
    
    _end = .;
}


