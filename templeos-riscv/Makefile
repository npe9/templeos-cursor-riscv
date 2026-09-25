# TempleOS/RISC-V — OS image (separate from repo-root HolyC compiler sources).
# Prerequisites: ../holyc-riscv (make -C .. holyc-riscv), riscv64-unknown-elf-*.
#
# Platform Kconfig (HolyC OS drivers use Kernel/RVAutoConf.HH):
#   make defconfig | defconfig-<machine> | menuconfig | syncconfig | list-defconfigs
# Machines: virt sifive_u sifive_e spike shakti_c microchip_icicle
#           xiangshan amd_microblaze_v opentitan visionfive2 milkv_mars host
#           (see PLATFORM.md)
# Multi-machine device drivers are HolyC (Kernel/Drv/*), not C.

PREFIX ?= riscv64-unknown-elf-
CC := $(PREFIX)gcc
LD := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy

HOLYC ?= ../holyc-riscv
QEMU ?= qemu-system-riscv64
PYTHON ?= python3
KCONFIG := $(PYTHON) scripts/kconfig.py

AUTOCONF := include/generated/autoconf.h
KCONFIG_MK := include/generated/kconfig.mk
-include $(KCONFIG_MK)

# From kconfig.mk when present; virt CI defaults otherwise.
MARCH ?= rv64imafdc
MABI ?= lp64d

CFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany -O2 -g \
	-nostdlib -ffreestanding -fno-builtin -Wall -Wextra \
	-Ikernel -Iinclude

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

DEFCONFIGS := virt sifive_u sifive_e spike shakti_c microchip_icicle \
	xiangshan amd_microblaze_v opentitan visionfive2 milkv_mars hifive_unmatched \
	host none

.PHONY: all image guest selfhost qemu qemu-selfhost clean check-holyc redsea-smoke-img \
	defconfig defconfig-virt menuconfig menuconfig-test syncconfig qemu-args list-defconfigs help \
	$(foreach m,$(DEFCONFIGS),defconfig-$(m)) \
	$(foreach m,$(DEFCONFIGS),qemu-args-$(m))

all: image

# --- Kconfig -----------------------------------------------------------------
MCONF := scripts/kconfig/mconf
CONF  := scripts/kconfig/conf

# scripts/kconfig.py is write-if-different: a re-sync that changes nothing leaves the
# generated files' mtime alone, which is what stops AOT units (build/aot/win/kernel.d
# includes RVAutoConf.HH and the Drv/RV*Selected.HH selects) from rebuilding for free.
# The side effect is that any file a sync legitimately skipped stays older than
# .config forever, so a rule keyed on their own mtime would re-run the generator on
# every invocation. Let a stamp own freshness instead, and depend on it order-only so
# these targets are still generated on demand when absent (after make clean), yet
# never look perpetually stale. Consumers keep depending on $(AUTOCONF) directly:
# its mtime now moves exactly when the config content changed.
KCONFIG_STAMP := include/generated/.autoconf-stamp

$(KCONFIG_STAMP): .config scripts/kconfig.py Kconfig Kconfig.machines
	@$(KCONFIG) sync
	@mkdir -p $(@D)
	@touch $@

$(AUTOCONF) $(KCONFIG_MK) ../Kernel/RVAutoConf.HH: | $(KCONFIG_STAMP)
	@$(KCONFIG) sync

.config:
	@$(KCONFIG) defconfig virt

# Explicit rules — GNU Make 3.81 drops pattern recipes when targets are in .PHONY.
define DEFCONFIG_template
.PHONY: defconfig-$(1)
defconfig-$(1):
	$$(KCONFIG) defconfig $(1)
endef
$(foreach m,$(DEFCONFIGS),$(eval $(call DEFCONFIG_template,$(m))))

defconfig: defconfig-virt

list-defconfigs:
	@$(KCONFIG) list-defconfigs

# Linux mconf + lxdialog (vendored scripts/kconfig). Needs TTY + ncurses + host cc.
$(MCONF) $(CONF):
	$(MAKE) -C scripts/kconfig

menuconfig: $(MCONF)
	@if [ ! -t 0 ] || [ ! -t 1 ]; then \
		echo "error: menuconfig requires an interactive TTY" >&2; \
		echo "hint: run \`make menuconfig\` from a terminal" >&2; \
		exit 1; \
	fi
	./$(MCONF) Kconfig
	$(KCONFIG) sync

menuconfig-test:
	$(KCONFIG) menuconfig-test

syncconfig:
	$(KCONFIG) sync

qemu-args:
	@$(KCONFIG) qemu-args

# Resolve harness argv for a machine without rewriting global .config / RVAutoConf.HH
define QEMU_ARGS_template
.PHONY: qemu-args-$(1)
qemu-args-$(1):
	$$(KCONFIG) qemu-args $(1)
endef
$(foreach m,$(DEFCONFIGS),$(eval $(call QEMU_ARGS_template,$(m))))

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

$(BUILD)/boot.o: $(BOOT_S) $(AUTOCONF)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(BOOT_S) -o $@

$(BUILD)/kernel.o: $(KERNEL_C) $(AUTOCONF)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $(KERNEL_C) -o $@

$(BUILD)/guest_call.o: $(GUEST_CALL_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -O0 -c $(GUEST_CALL_C) -o $@

$(BUILD)/virtio_mmio.o: $(VIRTIO_C) $(AUTOCONF)
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
$(BUILD)/tos-rv.elf: $(BUILD)/boot.o $(BUILD)/trap_entry.o $(BUILD)/kernel.o $(BUILD)/guest_call.o \
		$(BUILD)/virtio_mmio.o $(BUILD)/virtio_mmio_blk.o $(BUILD)/virtio_blk_pci.o $(BUILD)/redsea_min.o \
		$(BUILD)/blob_in.o $(BUILD)/compiler_blob_in.o $(LINK)
	cd $(BUILD) && $(LD) -T ../$(LINK) -nostdlib --no-warn-mismatch -o tos-rv.elf \
		boot.o trap_entry.o kernel.o guest_call.o virtio_mmio.o virtio_mmio_blk.o virtio_blk_pci.o \
		redsea_min.o blob_in.o compiler_blob_in.o

$(BUILD)/tos-rv-selfhost.elf: $(BUILD)/boot.o $(BUILD)/trap_entry.o $(BUILD)/kernel.o $(BUILD)/guest_call.o \
		$(BUILD)/virtio_mmio.o $(BUILD)/virtio_mmio_blk.o $(BUILD)/virtio_blk_pci.o $(BUILD)/redsea_min.o \
		$(BUILD)/blob_selfhost_in.o $(BUILD)/compiler_blob_in.o $(LINK_SELFHOST)
	cd $(BUILD) && $(LD) -T ../$(LINK_SELFHOST) -nostdlib --no-warn-mismatch -o tos-rv-selfhost.elf \
		boot.o trap_entry.o kernel.o guest_call.o virtio_mmio.o virtio_mmio_blk.o virtio_blk_pci.o \
		redsea_min.o blob_selfhost_in.o compiler_blob_in.o

redsea-smoke-img:
	@mkdir -p $(BUILD)
	python3 scripts/mk_redsea_smoke_img.py $(BUILD)/redsea_smoke.img

guest: $(BUILD)/guest.bin
image: $(BUILD)/tos-rv.elf
selfhost: $(BUILD)/tos-rv-selfhost.elf

qemu: $(BUILD)/tos-rv.elf
	@args=`$(KCONFIG) qemu-args`; \
	$(QEMU) $$args -kernel $(BUILD)/tos-rv.elf -nographic </dev/null

qemu-selfhost: $(BUILD)/tos-rv-selfhost.elf
	@args=`$(KCONFIG) qemu-args`; \
	$(QEMU) $$args -kernel $(BUILD)/tos-rv-selfhost.elf -nographic </dev/null

clean:
	rm -rf $(BUILD)
	$(MAKE) -C scripts/kconfig clean

help:
	@echo "TempleOS/RISC-V image + platform Kconfig"
	@echo "  defconfig / defconfig-<machine> / list-defconfigs"
	@echo "  menuconfig              - Linux mconf + lxdialog (needs ncurses + TTY)"
	@echo "  menuconfig-test         - build mconf/conf; conf --olddefconfig sanity"
	@echo "  syncconfig / qemu-args / qemu-args-<machine>"
	@echo "  image / qemu            - C bootstrap + HolyC guest (virt-oriented console)"
	@echo "  Multi-kernel (repo root): make kernel-<machine> / kernels / list-kernels"
	@echo "  Multi-machine OS drivers: Kernel/Drv/* + make kernel-plat-smoke (repo root)"
	@echo "Machines: $(DEFCONFIGS)"
	@echo "See KCONFIG.md / PLATFORM.md"
