// RVThinLoader.HH — forward decls for G9 thin-loader handoff (body in RVThinLoader.HC).
#ifndef RV_THIN_LOADER_HH
#define RV_THIN_LOADER_HH
// Kernel.BIN InitLite writes this magic; thin loader / phase3 verify after Call.
#ifndef KERNEL_BIN_MAGIC_ADDR
#define KERNEL_BIN_MAGIC_ADDR 0x8700E000
#endif
#ifndef KERNEL_BIN_MAGIC_VAL
#define KERNEL_BIN_MAGIC_VAL 0x4B494E49
#endif
// Thin loader plants STAY before Jump KernelEntry; Entry SoftCall+loops (phase3 leaves 0).
#ifndef KERNEL_BIN_STAY_ADDR
#define KERNEL_BIN_STAY_ADDR 0x8700E008
#endif
#ifndef KERNEL_BIN_STAY_VAL
#define KERNEL_BIN_STAY_VAL 0x53544159
#endif
// LoadBuf HashAdds exports + plants &KernelEntry; thin Jump via HashFind→Call.
#ifndef KERNEL_BIN_ENTRY_ADDR
#define KERNEL_BIN_ENTRY_ADDR 0x8700E010
#endif
// Host-linked Kernel.BIN seed (link_exepubs.ld .compiler_bin) — drops chicken-egg MMIO+raw.
#ifndef KERNEL_EMBED_ADDR
#define KERNEL_EMBED_ADDR 0x81000000
#endif
extern U0 RVThinLoader();
extern Bool rv_thin_loader_ok;
#endif
