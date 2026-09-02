/* Link firmware head + embedded RAM payload for QEMU virt CFI flash.
 *
 * FLASH_BASE — reset vector / pflash map (virt DT flash@20000000, 32 MiB).
 * RAM_BASE   — where the payload ELF is copied and executed (virt DRAM).
 *
 * Override bases: --defsym FLASH_BASE=0x... --defsym RAM_BASE=0x...
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

PROVIDE(FLASH_BASE = 0x20000000);
PROVIDE(RAM_BASE   = 0x80000000);

SECTIONS
{
    . = FLASH_BASE;

    .text.init : {
        *(.text.init)
    }

    .fw_payload : {
        _fw_payload_start = .;
        KEEP(*(.fw_payload))
        . = ALIGN(8);
        _fw_payload_end = .;
    }

    _fw_image_end = .;
}
