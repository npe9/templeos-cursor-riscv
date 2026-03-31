/* PCI Express ECAM (MMCONFIG) — QEMU `virt` maps bus 0 at 0x30000000 (see DTB pcie node). */
#ifndef TEMPLEOS_PCI_ECAM_H
#define TEMPLEOS_PCI_ECAM_H

#include <stdint.h>

#define QEMU_VIRT_PCI_ECAM_BASE 0x30000000ULL

static inline uintptr_t pci_cfg_addr(unsigned bus, unsigned dev, unsigned fn, unsigned off) {
  return (uintptr_t)(QEMU_VIRT_PCI_ECAM_BASE | ((bus & 0xffu) << 20) | ((dev & 31u) << 15) |
                     ((fn & 7u) << 12) | (off & 0xffcu));
}

static inline uint32_t pci_read32(unsigned bus, unsigned dev, unsigned fn, unsigned off) {
  return *(volatile uint32_t *)pci_cfg_addr(bus, dev, fn, off);
}

static inline uint16_t pci_read16(unsigned bus, unsigned dev, unsigned fn, unsigned off) {
  return *(volatile uint16_t *)(pci_cfg_addr(bus, dev, fn, off) + (off & 2u));
}

static inline uint8_t pci_read8(unsigned bus, unsigned dev, unsigned fn, unsigned off) {
  return *(volatile uint8_t *)(pci_cfg_addr(bus, dev, fn, off) + (off & 3u));
}

static inline void pci_write32(unsigned bus, unsigned dev, unsigned fn, unsigned off, uint32_t v) {
  *(volatile uint32_t *)pci_cfg_addr(bus, dev, fn, off) = v;
}

static inline void pci_write16(unsigned bus, unsigned dev, unsigned fn, unsigned off, uint16_t v) {
  *(volatile uint16_t *)(pci_cfg_addr(bus, dev, fn, off) + (off & 2u)) = v;
}

#endif
