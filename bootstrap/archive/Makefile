# Bootstrap System - Cross-compile HolyC for RISC-V

RISCV_PREFIX = riscv64-unknown-elf-
AS = $(RISCV_PREFIX)as
LD = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump

# Host compiler
HOLYC = ./holyc-riscv

ASFLAGS = -march=rv64imafdc -mabi=lp64d
LDFLAGS = -T linker.ld -nostdlib --no-warn-mismatch

.PHONY: all clean run

all: bootstrap.elf

# Compile HolyC files to RISC-V using HOST compiler
runtime.bin: minimal_runtime.hc
	$(HOLYC) $< -o $@

compiler.bin: mini_compiler.hc
	$(HOLYC) $< -o $@

# Convert binaries to object files (rename .data to .text for executable code)
runtime.o: runtime.bin
	$(OBJCOPY) -I binary -O elf64-littleriscv -B riscv:rv64 --rename-section .data=.text $< $@
	riscv64-unknown-elf-objcopy --set-section-flags .text=contents,alloc,load,readonly,code $@

compiler.o: compiler.bin
	$(OBJCOPY) -I binary -O elf64-littleriscv -B riscv:rv64 --rename-section .data=.text $< $@
	riscv64-unknown-elf-objcopy --set-section-flags .text=contents,alloc,load,readonly,code $@

# Startup code
startup.o: startup.s
	$(AS) $(ASFLAGS) -o $@ $<

# Main shim
main_shim.o: main_shim.c
	riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -c -o $@ $<

# Link everything
bootstrap.elf: startup.o main_shim.o runtime.o compiler.o
	$(LD) $(LDFLAGS) -o $@ $^
	$(OBJDUMP) -d $@ > bootstrap.dis
	@echo ""
	@echo "✓ Bootstrap system built: bootstrap.elf"
	@ls -lh bootstrap.elf

# Run in QEMU
run: bootstrap.elf
	@echo "Running TempleOS RISC-V Bootstrap..."
	qemu-system-riscv64 -M virt -bios none -kernel bootstrap.elf -nographic

clean:
	rm -f *.o *.elf *.bin *.dis
