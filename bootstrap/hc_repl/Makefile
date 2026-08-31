# HolyC AOT REPL — Mac holyc-riscv → RISC-V ELF. No crt0.S / no C guest runtime.
ROOT := $(abspath ../..)
BUILD := $(ROOT)/build
HOLYC := $(ROOT)/holyc-riscv
PREFIX ?= riscv64-unknown-elf-
LD := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy

.PHONY: all clean run seed_embed.hc

all: $(BUILD)/hc_repl.elf

seed_embed.hc: gen_embed.py uart.hc fs.hc dir.hc eval.hc repl.hc jit.hc start.hc \
               ../seed/mem.hc ../seed/str.hc ../seed/print.hc
	python3 gen_embed.py

$(BUILD)/hc_repl.blob.bin: repl.hc seed_embed.hc uart.hc fs.hc dir.hc eval.hc jit.hc start.hc \
                           $(HOLYC) ../seed/mem.hc ../seed/str.hc ../seed/print.hc
	@mkdir -p $(BUILD)
	@test -x $(HOLYC) || $(MAKE) -C $(ROOT) holyc-riscv
	HOLYC_INCLUDE_ROOT=$(ROOT) $(HOLYC) repl.hc -o $@

$(BUILD)/hc_repl.elf: $(BUILD)/hc_repl.blob.bin link.ld
	cd $(BUILD) && $(OBJCOPY) -I binary -O elf64-littleriscv \
	  --rename-section .data=.data,alloc,load,readonly,data,contents \
	  hc_repl.blob.bin blob_in.o
	cd $(BUILD) && $(OBJCOPY) \
	  --redefine-sym _binary_hc_repl_blob_bin_start=_binary_blob_bin_start \
	  --redefine-sym _binary_hc_repl_blob_bin_end=_binary_blob_bin_end \
	  --redefine-sym _binary_hc_repl_blob_bin_size=_binary_blob_bin_size \
	  blob_in.o
	cd $(BUILD) && $(LD) -T $(abspath link.ld) -nostdlib --no-warn-mismatch \
	  -o hc_repl.elf blob_in.o
	@echo "✓ Built $@ (HolyC blob only — entry=_start)"

run: $(BUILD)/hc_repl.elf
	qemu-system-riscv64 -M virt -bios none -kernel $(BUILD)/hc_repl.elf -nographic

clean:
	rm -f seed_embed.hc $(BUILD)/hc_repl.elf $(BUILD)/hc_repl.blob.bin \
	      $(BUILD)/blob_in.o $(BUILD)/hc_repl_crt0.o
