# TempleOS/RISC-V — OS image (separate from repo-root HolyC compiler sources).
# Prerequisites: ../holyc-riscv (make -C .. holyc-riscv), riscv64-unknown-elf-*.

PREFIX ?= riscv64-unknown-elf-
CC := $(PREFIX)gcc
LD := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy

HOLYC ?= ../holyc-riscv
QEMU ?= qemu-system-riscv64

MARCH ?= rv64imafdc
MABI ?= lp64d

CFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany -O2 -g \
	-nostdlib -ffreestanding -fno-builtin -Wall -Wextra \
	-Ikernel

BUILD := build
LINK := link/kernel.ld
LINK_SELFHOST := link/kernel_selfhost.ld

KERNEL_C := kernel/kernel.c
GUEST_CALL_C := kernel/guest_call.c
VIRTIO_C := kernel/virtio_mmio.c
VIRTIO_MMIO_BLK_C := kernel/virtio_mmio_blk.c
VIRTIO_BLK_PCI_C := kernel/virtio_blk_pci.c
REDSEA_C := kernel/redsea_min.c
BOOT_S := kernel/boot.S
TRAP_S := kernel/trap_entry.S

.PHONY: all image guest selfhost qemu qemu-selfhost clean check-holyc redsea-smoke-img

all: image

check-holyc:
	@if [ ! -x "$(HOLYC)" ] && [ ! -f "$(HOLYC)" ]; then \
		echo "error: $(HOLYC) missing — build with: make -C .. holyc-riscv" >&2; \
		exit 1; \
	fi

$(BUILD)/guest.bin: guest/kmain.hc check-holyc
	@mkdir -p $(BUILD)
	"$(HOLYC)" guest/kmain.hc -o $@

$(BUILD)/selfhost.bin: selfhost/toy_eval.hc check-holyc
	@mkdir -p $(BUILD)
	"$(HOLYC)" selfhost/toy_eval.hc -o $@

$(BUILD)/blob_in.o: $(BUILD)/guest.bin
	$(OBJCOPY) -I binary -O elf64-littleriscv -B riscv \
		--rename-section .data=.data,alloc,load,readonly,contents \
		$< $@

$(BUILD)/blob_selfhost_in.o: $(BUILD)/selfhost.bin
	$(OBJCOPY) -I binary -O elf64-littleriscv -B riscv \
		--rename-section .data=.data,alloc,load,readonly,contents \
		$< $@

# Phase B: COMP magic + RV64 ret at +4 (compiler.BIN placeholder).
$(BUILD)/compiler_slot.bin: Makefile
	@mkdir -p $(BUILD)
	python3 -c 'import sys; sys.stdout.buffer.write(bytes([0x43,0x4f,0x4d,0x50,0x67,0x80,0x00,0x00]))' > $@

$(BUILD)/compiler_blob_in.o: $(BUILD)/compiler_slot.bin
	$(OBJCOPY) -I binary -O elf64-littleriscv -B riscv \
		--rename-section .data=.data,alloc,load,readonly,contents \
		$< $@

$(BUILD)/boot.o: $(BOOT_S)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(BOOT_S) -o $@

$(BUILD)/kernel.o: $(KERNEL_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(KERNEL_C) -o $@

$(BUILD)/guest_call.o: $(GUEST_CALL_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -O0 -c $(GUEST_CALL_C) -o $@

$(BUILD)/virtio_mmio.o: $(VIRTIO_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(VIRTIO_C) -o $@

$(BUILD)/virtio_mmio_blk.o: $(VIRTIO_MMIO_BLK_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(VIRTIO_MMIO_BLK_C) -o $@

$(BUILD)/virtio_blk_pci.o: $(VIRTIO_BLK_PCI_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(VIRTIO_BLK_PCI_C) -o $@

$(BUILD)/redsea_min.o: $(REDSEA_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(REDSEA_C) -o $@

$(BUILD)/trap_entry.o: $(TRAP_S)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(TRAP_S) -o $@

# Link from $(BUILD) so kernel.ld can name inputs blob_in.o (matches tests/exec harness).
$(BUILD)/tos-rv.elf: $(BUILD)/boot.o $(BUILD)/trap_entry.o $(BUILD)/kernel.o $(BUILD)/guest_call.o $(BUILD)/virtio_mmio.o $(BUILD)/virtio_mmio_blk.o $(BUILD)/virtio_blk_pci.o $(BUILD)/redsea_min.o $(BUILD)/blob_in.o $(BUILD)/compiler_blob_in.o $(LINK)
	cd $(BUILD) && $(LD) -T ../$(LINK) -nostdlib --no-warn-mismatch -o tos-rv.elf \
		boot.o trap_entry.o kernel.o guest_call.o virtio_mmio.o virtio_mmio_blk.o virtio_blk_pci.o redsea_min.o blob_in.o compiler_blob_in.o

$(BUILD)/tos-rv-selfhost.elf: $(BUILD)/boot.o $(BUILD)/trap_entry.o $(BUILD)/kernel.o $(BUILD)/guest_call.o $(BUILD)/virtio_mmio.o $(BUILD)/virtio_mmio_blk.o $(BUILD)/virtio_blk_pci.o $(BUILD)/redsea_min.o $(BUILD)/blob_selfhost_in.o $(BUILD)/compiler_blob_in.o $(LINK_SELFHOST)
	cd $(BUILD) && $(LD) -T ../$(LINK_SELFHOST) -nostdlib --no-warn-mismatch -o tos-rv-selfhost.elf \
		boot.o trap_entry.o kernel.o guest_call.o virtio_mmio.o virtio_mmio_blk.o virtio_blk_pci.o redsea_min.o blob_selfhost_in.o compiler_blob_in.o

redsea-smoke-img:
	@mkdir -p $(BUILD)
	python3 scripts/mk_redsea_smoke_img.py $(BUILD)/redsea_smoke.img

guest: $(BUILD)/guest.bin
image: $(BUILD)/tos-rv.elf
selfhost: $(BUILD)/tos-rv-selfhost.elf

qemu: $(BUILD)/tos-rv.elf
	$(QEMU) -M virt -bios none -kernel $(BUILD)/tos-rv.elf -nographic </dev/null

qemu-selfhost: $(BUILD)/tos-rv-selfhost.elf
	$(QEMU) -M virt -bios none -kernel $(BUILD)/tos-rv-selfhost.elf -nographic </dev/null

clean:
	rm -rf $(BUILD)
