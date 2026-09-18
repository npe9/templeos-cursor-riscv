# HolyC AOT REPL — Mac holyc-riscv → RISC-V ELF. No crt0.S / no C guest runtime.
ROOT := $(abspath ../..)
BUILD := $(ROOT)/build
HOLYC := $(ROOT)/holyc-riscv
PREFIX ?= riscv64-unknown-elf-
LD := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy

.PHONY: all clean run seed_embed.hc repl-holyc blob

all: $(BUILD)/hc_repl.elf $(BUILD)/repl-holyc.elf

# Flat HolyC AOT blob only (no GNU ld/objcopy). Used by make bootloader / bootloader-smoke.
blob: $(BUILD)/hc_repl.blob.bin

# Alias for docs/CI naming — same HolyC-only guest as hc_repl.elf (no worry_dream link).
$(BUILD)/repl-holyc.elf: $(BUILD)/hc_repl.elf
	cp $< $@
	@echo "✓ Built $@ (HolyC AOT guest — parallel to legacy bootstrap/repl.elf)"

seed_embed.hc: gen_embed.py uart.hc fs.hc dir.hc eval.hc repl.hc jit.hc exepubs.hc start.hc \
               fs_dump_changes.hc man_sym.hc ide_bridge.hc ide_src.hc ../seed_layout.py \
               ../seed/MemMapSelected.hc ../seed/uart.hc ../seed/mem.hc ../seed/str.hc \
               ../seed/print.hc ../seed/fs.hc ../seed/run.hc ../seed/dir.hc \
               ../seed/files.hc ../seed/boot.hc ../seed/tutorial.hc \
               ../seed/man.hc ../seed/man_topics.hc ../seed/funs.hc \
               ../seed/term.hc ../seed/ed.hc ../seed/edit.hc ../seed/vim.hc \
               ../seed/RVEditorSelected.hc ../seed/trap.hc ../seed/soft_let.hc \
               ../seed/home_wrappers.hc ../seed/disasm.hc ../seed/ninep.hc ../seed/gdbstub.hc \
               ../seed/csr_decode.hc ../seed/csr.hc ../seed/debug.hc ../seed/crash.hc ../seed/callers.hc ../seed/dbg_jit_sym.hc
	python3 gen_embed.py

$(BUILD)/hc_repl.blob.bin: repl.hc seed_embed.hc uart.hc fs.hc dir.hc eval.hc jit.hc exepubs.hc start.hc \
                           fs_dump_changes.hc man_sym.hc ide_bridge.hc ide_src.hc trap_vec_off.hc $(HOLYC) \
                           ../seed/mem.hc ../seed/str.hc ../seed/print.hc ../seed/log.hc ../seed/frame.hc \
                           ../seed/files.hc ../seed/man.hc ../seed/term.hc ../seed/ed.hc \
                           ../seed/edit.hc ../seed/vim.hc ../seed/RVEditorSelected.hc \
                           ../seed/trap.hc ../seed/MemMapSelected.hc ../seed/sys.hc \
                           ../seed/soft_let.hc ../seed/home_wrappers.hc ../seed/disasm.hc \
                           ../seed/ninep.hc ../seed/gdbstub.hc \
                           ../seed/csr_decode.hc ../seed/csr.hc ../seed/debug.hc ../seed/crash.hc \
                           ../seed/callers.hc ../seed/dbg_jit_sym.hc patch_imports.py
	@mkdir -p $(BUILD)
	@test -x $(HOLYC) || $(MAKE) -C $(ROOT) holyc-riscv
	HOLYC_INCLUDE_ROOT=$(ROOT) HOLYC_MAP=$(BUILD)/repl.map $(HOLYC) repl.hc -o $@
	python3 patch_imports.py $@ $(BUILD)/repl.map trap_vec_off.hc
	@# Force elf rebuild whenever blob changes (avoid stale hc_repl.elf after csr edits).
	@rm -f $(BUILD)/hc_repl.elf $(BUILD)/repl-holyc.elf

$(BUILD)/hc_repl.elf: $(BUILD)/hc_repl.blob.bin link.ld
	# AOT blob mixes code + writable globals — need RWE (not readonly).
	cd $(BUILD) && $(OBJCOPY) -I binary -O elf64-littleriscv \
	  --rename-section .data=.text,alloc,load,code,contents \
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

repl-holyc: $(BUILD)/repl-holyc.elf

clean:
	rm -f seed_embed.hc $(BUILD)/hc_repl.elf $(BUILD)/repl-holyc.elf \
	      $(BUILD)/hc_repl.blob.bin $(BUILD)/blob_in.o $(BUILD)/hc_repl_crt0.o
