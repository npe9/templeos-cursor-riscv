/* RISC-V linker script for the bare-metal REPL.
 *
 * The load/link base is parameterized: it defaults to QEMU virt's RAM base, and a platform
 * (or a direct override) supplies a different one with `--defsym LOAD_BASE=0x...`. See the
 * PLATFORM table in Makefile.repl. All addresses below are relative to LOAD_BASE, and startup.s
 * uses only linker-defined symbols, so retargeting the whole image is just that one base.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

/* Default base; `--defsym LOAD_BASE=...` from the Makefile overrides this (verified: defsym wins). */
PROVIDE(LOAD_BASE = 0x80000000);

SECTIONS
{
    . = LOAD_BASE;

    /* Code (.text.init holds _start, so it lands first at the load base) */
    .text : {
        *(.text.init)
        *(.text .text.*)
        . = ALIGN(8);
    }

    /* Read-only data */
    .rodata : {
        *(.rodata .rodata.*)
        . = ALIGN(8);
    }

    /* Data */
    _data_start = .;
    .data : {
        *(.data .data.*)
        . = ALIGN(8);
    }

    /* BSS */
    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(8);
        _bss_end = .;
    }

    /* Global pointer */
    __global_pointer$ = MIN(_data_start + 0x800, MAX(_data_start + 0x800, _bss_end - 0x800));

    . = ALIGN(0x1000);
    _stack_top = .;
    _heap_start = .;
    _end = .;
}
