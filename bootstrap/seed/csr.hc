// csr.hc -- RISC-V MemMap / GPR / CSR symbols + real csrr/csrw Get/Set + Reg dig-down.
// Boot after sym.hc (MemMap/Regs slots). Edit live: Run("csr.hc");
// ---- Memory-map symbols (use without hardcoding 0x85…) -----------------------------------
#define MEM_RAM        0x80000000
#define MEM_TEST       0x00100000
#define MEM_CLINT      0x02000000
#define MEM_CLINT_MTIME_OFF    0xBFF8
#define MEM_CLINT_MTIMECMP_OFF 0x4000
#define MEM_MTIME      0x0200BFF8
#define MEM_MTIMECMP   0x02004000
#define MEM_PLIC       0x0C000000
#define MEM_UART       0x10000000
#define MEM_VIRTIO     0x10001000
#define MEM_VIRTIO_STRIDE 0x1000
#define MEM_FW_CFG     0x10100000
#define MEM_FS         0x85000000
#define MEM_HEAP       0x86000000
#define MEM_FB         0x86100000
#define MEM_FIXED      0x87000000
#define MEM_TRAP_SNAP  0x87000100
#define MEM_REGS_SNAP  0x87000300
#define MEM_HOST_SLOTS 0x87001000
#define MEM_STACK      0x87F00000
// Kernel phase3 Compiler.BIN embed — not present in the UART REPL image.
#define MEM_COMPILER   0
// ---- Region ↔ HolyC driver (typical virt-style MEM_* defaults; Kernel uses RVMemMap.HC + Kconfig) --------
// Last column of MemMap(); dig-down: MemMapDrvFind("uart"); Man("MemMap");
#define MEMMAP_DRV_UART    "RVUart16550 / uart.hc"
#define MEMMAP_DRV_CLINT   "RVTimer / CLINT"
#define MEMMAP_DRV_PLIC    "RVPlicHw"
#define MEMMAP_DRV_VIRTIO  "DskVirtioRV / RVVirtioMmio*"
#define MEMMAP_DRV_FB      "RVFb / ramfb"
#define MEMMAP_DRV_FW_CFG  "RVFwCfgYes"
#define MEMMAP_DRV_FS      "fs.hc"
#define MEMMAP_DRV_HEAP    "mem.hc"
#define MEMMAP_DRV_TRAP    "trap.hc"
#define MEMMAP_DRV_REGS    "Regs / csr.hc"
#define MEMMAP_DRV_TEST    "[plat SiFive test]"
#define MEMMAP_DRV_RAM     "[plat DRAM]"
// ---- GPR ABI indices (REG_SP etc.; string dig-down via Reg("sp")) -------------------------
#define REG_ZERO 0
#define REG_RA   1
#define REG_SP   2
#define REG_GP   3
#define REG_TP   4
#define REG_T0   5
#define REG_T1   6
#define REG_T2   7
#define REG_S0   8
#define REG_FP   8
#define REG_S1   9
#define REG_A0   10
#define REG_A1   11
#define REG_A2   12
#define REG_A3   13
#define REG_A4   14
#define REG_A5   15
#define REG_A6   16
#define REG_A7   17
#define REG_S2   18
#define REG_S3   19
#define REG_S4   20
#define REG_S5   21
#define REG_S6   22
#define REG_S7   23
#define REG_S8   24
#define REG_S9   25
#define REG_S10  26
#define REG_S11  27
#define REG_T3   28
#define REG_T4   29
#define REG_T5   30
#define REG_T6   31
// ---- CSR address constants (CSRGet(CSR_MSTATUS); also Reg("mstatus")) --------------------
#define CSR_SATP     0x180
#define CSR_SSCRATCH 0x140
#define CSR_MSTATUS  0x300
#define CSR_MISA     0x301
#define CSR_MIE      0x304
#define CSR_MTVEC    0x305
#define CSR_MSCRATCH 0x340
#define CSR_MEPC     0x341
#define CSR_MCAUSE   0x342
#define CSR_MTVAL    0x343
#define CSR_MIP      0x344
#define CSR_MHARTID  0xF14
asm {
	HcGetMStatus::
	csrr	a0, 0x300
	ret
	HcSetMStatus::
	csrw	0x300, a0
	ret
	HcGetMIsa::
	csrr	a0, 0x301
	ret
	HcSetMIsa::
	csrw	0x301, a0
	ret
	HcGetMie::
	csrr	a0, 0x304
	ret
	HcSetMie::
	csrw	0x304, a0
	ret
	HcGetMtvec::
	csrr	a0, 0x305
	ret
	HcSetMtvec::
	csrw	0x305, a0
	fencei
	ret
	HcGetMScratch::
	csrr	a0, 0x340
	ret
	HcSetMScratch::
	csrw	0x340, a0
	ret
	HcGetMepc::
	csrr	a0, 0x341
	ret
	HcSetMepc::
	csrw	0x341, a0
	ret
	HcGetMcause::
	csrr	a0, 0x342
	ret
	HcSetMcause::
	csrw	0x342, a0
	ret
	HcGetMtval::
	csrr	a0, 0x343
	ret
	HcSetMtval::
	csrw	0x343, a0
	ret
	HcGetMip::
	csrr	a0, 0x344
	ret
	HcSetMip::
	csrw	0x344, a0
	ret
	HcGetSatp::
	csrr	a0, 0x180
	ret
	HcSetSatp::
	csrw	0x180, a0
	ret
	HcGetSScratch::
	csrr	a0, 0x140
	ret
	HcSetSScratch::
	csrw	0x140, a0
	ret
	HcGetMHartId::
	csrr	a0, 0xF14
	ret
}
// GetMStatus -- GetMStatus()
// NAME
//   GetMStatus - read mstatus (CSR_MSTATUS / csrr)
// SYNOPSIS
//   I64 GetMStatus();
// DESCRIPTION
//   Real csrr of machine status (MIE, FS, privilege stack, …). Pair with SetMStatus.
//   Siblings: GetMie/GetMtvec/GetMepc/GetMcause/GetMtval/GetMScratch/GetMip/GetMIsa/
//   GetSatp/GetSScratch/GetMHartId. Numeric: CSRGet(CSR_MSTATUS). Dig-down: Reg("mstatus").
// INPUTS
//   none
// OUTPUTS
//   Current mstatus value
// BUGS
//   M-mode only on this port (bare-metal seed profile).
I64 GetMStatus()
{
  return HcGetMStatus();
}

U0 SetMStatus(I64 v)
{
  HcSetMStatus(v);
}

I64 GetMIsa()
{
  return HcGetMIsa();
}

U0 SetMIsa(I64 v)
{
  HcSetMIsa(v);
}

I64 GetMie()
{
  return HcGetMie();
}

U0 SetMie(I64 v)
{
  HcSetMie(v);
}

I64 GetMtvec()
{
  return HcGetMtvec();
}

U0 SetMtvec(I64 v)
{
  HcSetMtvec(v);
}

I64 GetMScratch()
{
  return HcGetMScratch();
}

U0 SetMScratch(I64 v)
{
  HcSetMScratch(v);
}

I64 GetMepc()
{
  return HcGetMepc();
}

U0 SetMepc(I64 v)
{
  HcSetMepc(v);
}

I64 GetMcause()
{
  return HcGetMcause();
}

U0 SetMcause(I64 v)
{
  HcSetMcause(v);
}

I64 GetMtval()
{
  return HcGetMtval();
}

U0 SetMtval(I64 v)
{
  HcSetMtval(v);
}

I64 GetMip()
{
  return HcGetMip();
}

U0 SetMip(I64 v)
{
  HcSetMip(v);
}

I64 GetSatp()
{
  return HcGetSatp();
}

U0 SetSatp(I64 v)
{
  HcSetSatp(v);
}

I64 GetSScratch()
{
  return HcGetSScratch();
}

U0 SetSScratch(I64 v)
{
  HcSetSScratch(v);
}
// GetMHartId -- GetMHartId()
// NAME
//   GetMHartId - read mhartid (read-only)
// SYNOPSIS
//   I64 GetMHartId();
// DESCRIPTION
//   Hardware thread id. SetMHartId is a documented no-op (CSR is RO).
// INPUTS
//   none
// OUTPUTS
//   mhartid
// BUGS
//   SetMHartId ignores its argument.
I64 GetMHartId()
{
  return HcGetMHartId();
}

U0 SetMHartId(I64 v)
{
  /* RO */
}

I64 GetMTime()
{
  return *(I64 *)MEM_MTIME;
}
// TempleOS RFLAGS shims → mstatus on RISC-V.
I64 GetRFlags()
{
  return GetMStatus();
}

U0 SetRFlags(I64 f)
{
  SetMStatus(f);
}
// CSRGet -- CSRGet(csr)
// NAME
//   CSRGet - read a CSR by numeric CSR_* constant
// SYNOPSIS
//   I64 CSRGet(I64 csr);
// DESCRIPTION
//   Dispatch on CSR_MSTATUS / CSR_MEPC / … to the matching Get* (real csrr). Prefer named
//   GetMStatus when you know which CSR; use CSRGet when the address is symbolic.
// INPUTS
//   csr - CSR_* address constant
// OUTPUTS
//   CSR value, or 0 if unknown
// BUGS
//   Unknown csr numbers return 0 (no illegal-instruction probe).
I64 CSRGet(I64 csr)
{
  if (csr == CSR_MSTATUS)
    return GetMStatus();
  if (csr == CSR_MISA)
    return GetMIsa();
  if (csr == CSR_MIE)
    return GetMie();
  if (csr == CSR_MTVEC)
    return GetMtvec();
  if (csr == CSR_MSCRATCH)
    return GetMScratch();
  if (csr == CSR_MEPC)
    return GetMepc();
  if (csr == CSR_MCAUSE)
    return GetMcause();
  if (csr == CSR_MTVAL)
    return GetMtval();
  if (csr == CSR_MIP)
    return GetMip();
  if (csr == CSR_SATP)
    return GetSatp();
  if (csr == CSR_SSCRATCH)
    return GetSScratch();
  if (csr == CSR_MHARTID)
    return GetMHartId();
  return 0;
}
// CSRSet -- CSRSet(csr,v)
// NAME
//   CSRSet - write a CSR by CSR_* constant
// SYNOPSIS
//   U0 CSRSet(I64 csr,I64 v);
// DESCRIPTION
//   Dispatch to Set*. mhartid is RO (no-op). mip/misa are WARL — hardware may ignore bits.
// INPUTS
//   csr - CSR_* constant
//   v - value to write
// OUTPUTS
//   none
// BUGS
//   Unknown csr: no-op. Do not point mtvec at junk (SetMtvec / TrapInit).
U0 CSRSet(I64 csr, I64 v)
{
  if (csr == CSR_MSTATUS) {
    SetMStatus(v);
    return;
  }
  if (csr == CSR_MISA) {
    SetMIsa(v);
    return;
  }
  if (csr == CSR_MIE) {
    SetMie(v);
    return;
  }
  if (csr == CSR_MTVEC) {
    SetMtvec(v);
    return;
  }
  if (csr == CSR_MSCRATCH) {
    SetMScratch(v);
    return;
  }
  if (csr == CSR_MEPC) {
    SetMepc(v);
    return;
  }
  if (csr == CSR_MCAUSE) {
    SetMcause(v);
    return;
  }
  if (csr == CSR_MTVAL) {
    SetMtval(v);
    return;
  }
  if (csr == CSR_MIP) {
    SetMip(v);
    return;
  }
  if (csr == CSR_SATP) {
    SetSatp(v);
    return;
  }
  if (csr == CSR_SSCRATCH) {
    SetSScratch(v);
    return;
  }
  if (csr == CSR_MHARTID) {
    SetMHartId(v);
    return;
  }
}
// MemMapFind -- MemMapFind("heap")
// NAME
//   MemMapFind - resolve a MemMap region name to an address
// SYNOPSIS
//   I64 MemMapFind(U8 *name);
// DESCRIPTION
//   Symbolic lookup for MEM_* regions: "ram","heap","fb","fs","uart","stack","code","jit_heap",
//   "plic","clint","trap","regs",… Live JIT bases come from host slots. See MemMap; and MEM_*.
// INPUTS
//   name - region name (case-insensitive)
// OUTPUTS
//   Address, or 0 if unknown / n/a (e.g. "compiler" on REPL)
// BUGS
//   "code"/"jit_heap" need host slots published by the C REPL.
I64 MemMapFind(U8 *name)
{
  I64 p;
  if (!name)
    return 0;
  if (!StrICmp(name, "ram") || !StrICmp(name, "mem_ram"))
    return MEM_RAM;
  if (!StrICmp(name, "heap") || !StrICmp(name, "mem_heap") || !StrICmp(name, "hc_heap"))
    return MEM_HEAP;
  if (!StrICmp(name, "fb") || !StrICmp(name, "mem_fb") || !StrICmp(name, "ramfb"))
    return MEM_FB;
  if (!StrICmp(name, "fs") || !StrICmp(name, "memfs") || !StrICmp(name, "mem_fs"))
    return MEM_FS;
  if (!StrICmp(name, "uart") || !StrICmp(name, "mem_uart"))
    return MEM_UART;
  if (!StrICmp(name, "stack") || !StrICmp(name, "mem_stack"))
    return MEM_STACK;
  if (!StrICmp(name, "plic") || !StrICmp(name, "mem_plic"))
    return MEM_PLIC;
  if (!StrICmp(name, "clint") || !StrICmp(name, "mem_clint"))
    return MEM_CLINT;
  if (!StrICmp(name, "virtio") || !StrICmp(name, "mem_virtio"))
    return MEM_VIRTIO;
  if (!StrICmp(name, "fw_cfg") || !StrICmp(name, "fwcfg") || !StrICmp(name, "mem_fw_cfg"))
    return MEM_FW_CFG;
  if (!StrICmp(name, "test") || !StrICmp(name, "mem_test"))
    return MEM_TEST;
  if (!StrICmp(name, "fixed") || !StrICmp(name, "mem_fixed"))
    return MEM_FIXED;
  if (!StrICmp(name, "trap") || !StrICmp(name, "trap_snap") || !StrICmp(name, "mem_trap_snap"))
    return MEM_TRAP_SNAP;
  if (!StrICmp(name, "regs") || !StrICmp(name, "regs_snap") || !StrICmp(name, "mem_regs_snap"))
    return MEM_REGS_SNAP;
  if (!StrICmp(name, "slots") || !StrICmp(name, "host") || !StrICmp(name, "mem_host_slots"))
    return MEM_HOST_SLOTS;
  if (!StrICmp(name, "mtime") || !StrICmp(name, "mem_mtime"))
    return MEM_MTIME;
  if (!StrICmp(name, "compiler") || !StrICmp(name, "mem_compiler"))
    return MEM_COMPILER;
  if (!StrICmp(name, "code") || !StrICmp(name, "mem_code") || !StrICmp(name, "code_mem")) {
    p = *(I64 *)0x87001140;
    return p;
  }
  if (!StrICmp(name, "jit_heap") || !StrICmp(name, "heap_mem") || !StrICmp(name, "mem_jit_heap")) {
    p = *(I64 *)0x87001148;
    return p;
  }
  return 0;
}
// MemMapDrvFind -- MemMapDrvFind("uart")
// NAME
//   MemMapDrvFind - HolyC driver (or subsystem) for a MEM_* region
// SYNOPSIS
//   U8 *MemMapDrvFind(U8 *name);
// DESCRIPTION
//   Maps region names to the owning driver string shown in MemMap's last column.
//   Virt REPL defaults match Kernel/Drv selects (RVUart16550, RVTimer, RVPlicHw, …).
//   Kernel builds: see Kernel/Drv/RVMemMap.HC (Kconfig-driven). Dig-down from MemMap;
//   Man("MemMap"); MemMapDrv;
// INPUTS
//   name - same aliases as MemMapFind ("uart","clint","plic","virtio","fb",…)
// OUTPUTS
//   Static driver hint string, or 0 if unknown
// BUGS
//   Seed table is typical virt-style MEM_*; other boards need Kernel RVMemMap + defconfig.
U8 *MemMapDrvFind(U8 *name)
{
  if (!name)
    return 0;
  if (!StrICmp(name, "uart") || !StrICmp(name, "mem_uart"))
    return MEMMAP_DRV_UART;
  if (!StrICmp(name, "clint") || !StrICmp(name, "mem_clint") || !StrICmp(name, "mtime") || !StrICmp(name, "mtimecmp") || !StrICmp(name, "mem_mtime") || !StrICmp(name, "mem_mtimecmp"))
    return MEMMAP_DRV_CLINT;
  if (!StrICmp(name, "plic") || !StrICmp(name, "mem_plic"))
    return MEMMAP_DRV_PLIC;
  if (!StrICmp(name, "virtio") || !StrICmp(name, "mem_virtio"))
    return MEMMAP_DRV_VIRTIO;
  if (!StrICmp(name, "fb") || !StrICmp(name, "mem_fb") || !StrICmp(name, "ramfb"))
    return MEMMAP_DRV_FB;
  if (!StrICmp(name, "fw_cfg") || !StrICmp(name, "fwcfg") || !StrICmp(name, "mem_fw_cfg"))
    return MEMMAP_DRV_FW_CFG;
  if (!StrICmp(name, "fs") || !StrICmp(name, "memfs") || !StrICmp(name, "mem_fs"))
    return MEMMAP_DRV_FS;
  if (!StrICmp(name, "heap") || !StrICmp(name, "mem_heap") || !StrICmp(name, "hc_heap"))
    return MEMMAP_DRV_HEAP;
  if (!StrICmp(name, "trap") || !StrICmp(name, "trap_snap") || !StrICmp(name, "mem_trap_snap"))
    return MEMMAP_DRV_TRAP;
  if (!StrICmp(name, "regs") || !StrICmp(name, "regs_snap") || !StrICmp(name, "mem_regs_snap"))
    return MEMMAP_DRV_REGS;
  if (!StrICmp(name, "test") || !StrICmp(name, "mem_test"))
    return MEMMAP_DRV_TEST;
  if (!StrICmp(name, "ram") || !StrICmp(name, "mem_ram"))
    return MEMMAP_DRV_RAM;
  return 0;
}
// MemMapDrv -- MemMapDrv()
// NAME
//   MemMapDrv - print MMIO/region → driver table only
// SYNOPSIS
//   U0 MemMapDrv();
// DESCRIPTION
//   Compact legend of which HolyC driver owns each MEM_* window (same strings as
//   MemMap's driver column). Prefer MemMap for live JIT sizes; use this for a
//   glanceable driver map. Man("MemMap"); MemMapDrvFind("uart");
// INPUTS
//   none
// OUTPUTS
//   UART table
// BUGS
//   Virt defaults in csr.hc; Kernel uses RVMemMap.HC + RVAutoConf.HH.
U0 MemMapDrv()
{
  UartStr("MemMapDrv — region → HolyC driver (this profile; see Man(\"MemMap\")):\n");
  "  MEM_UART    0x%X  %s\n", MEM_UART, MEMMAP_DRV_UART;
  "  MEM_CLINT   0x%X  %s\n", MEM_CLINT, MEMMAP_DRV_CLINT;
  "  MEM_PLIC    0x%X  %s\n", MEM_PLIC, MEMMAP_DRV_PLIC;
  "  MEM_VIRTIO  0x%X  %s\n", MEM_VIRTIO, MEMMAP_DRV_VIRTIO;
  "  MEM_FW_CFG  0x%X  %s\n", MEM_FW_CFG, MEMMAP_DRV_FW_CFG;
  "  MEM_FB      0x%X  %s\n", MEM_FB, MEMMAP_DRV_FB;
  "  MEM_FS      0x%X  %s\n", MEM_FS, MEMMAP_DRV_FS;
  "  MEM_HEAP    0x%X  %s\n", MEM_HEAP, MEMMAP_DRV_HEAP;
  "  MEM_TEST    0x%X  %s\n", MEM_TEST, MEMMAP_DRV_TEST;
  UartStr("  MemMap;  MemMapDrvFind(\"uart\");  Man(\"MemMap\");\n");
}
// Reg -- Reg("sp") / Reg("mstatus")
// NAME
//   Reg - dig-down one GPR or CSR by name
// SYNOPSIS
//   I64 Reg(U8 *name);
// DESCRIPTION
//   Prints value + short description. GPRs use a call-site snap (same as Regs). CSRs use live
//   csrr. Accepts ABI names (sp,ra,a0), xN, REG_* tails, and CSR names (mstatus,mepc,…).
//   From MemMap: Regs; Reg("mstatus"); GetMStatus; Man("Regs"); RegHelp;
// INPUTS
//   name - register or CSR name string
// OUTPUTS
//   Value, or -1 if unknown
// BUGS
//   Needs host reg_one_stub slot on repl.elf; CSR Get* still work without it.
I64 Reg(U8 *name)
{
  I64 (*rg)(U8 *name);
  rg = *(I64 *)0x87001150;
  if (rg)
    return rg(name);
  if (!name)
    return -1;
  if (!StrICmp(name, "mstatus")) {
    "  mstatus = 0x%X  machine status\n", GetMStatus();
    return GetMStatus();
  }
  if (!StrICmp(name, "mepc")) {
    "  mepc = 0x%X\n", GetMepc();
    return GetMepc();
  }
  if (!StrICmp(name, "mcause")) {
    "  mcause = 0x%X\n", GetMcause();
    return GetMcause();
  }
  if (!StrICmp(name, "mtvec")) {
    "  mtvec = 0x%X\n", GetMtvec();
    return GetMtvec();
  }
  if (!StrICmp(name, "mie")) {
    "  mie = 0x%X\n", GetMie();
    return GetMie();
  }
  if (!StrICmp(name, "mip")) {
    "  mip = 0x%X\n", GetMip();
    return GetMip();
  }
  if (!StrICmp(name, "mtval")) {
    "  mtval = 0x%X\n", GetMtval();
    return GetMtval();
  }
  if (!StrICmp(name, "mscratch")) {
    "  mscratch = 0x%X\n", GetMScratch();
    return GetMScratch();
  }
  if (!StrICmp(name, "misa")) {
    "  misa = 0x%X\n", GetMIsa();
    return GetMIsa();
  }
  if (!StrICmp(name, "satp")) {
    "  satp = 0x%X\n", GetSatp();
    return GetSatp();
  }
  if (!StrICmp(name, "sscratch")) {
    "  sscratch = 0x%X\n", GetSScratch();
    return GetSScratch();
  }
  if (!StrICmp(name, "mhartid")) {
    "  mhartid = 0x%X\n", GetMHartId();
    return GetMHartId();
  }
  UartStr("Reg: host slot empty (CSR name fallback missed)\n");
  return -1;
}
// RegHelp -- RegHelp()
// NAME
//   RegHelp - list GPR/CSR/MEM symbols and Get/Set APIs
// SYNOPSIS
//   U0 RegHelp();
// DESCRIPTION
//   TempleOS-ish help for dig-down: MemMap → Regs → Reg("name") / GetMStatus / CSRGet(CSR_*).
// INPUTS
//   none
// OUTPUTS
//   UART legend
// BUGS
//   Hand-maintained; keep in sync with csr.hc defines.
U0 RegHelp()
{
  UartStr("RegHelp — MemMap / GPR / CSR dig-down\n");
  UartStr("  MemMap;  MemMapDrv;  MemMapFind(\"heap\");  MemMapDrvFind(\"uart\");\n");
  UartStr("  Print(\"%X\\n\", MEM_HEAP);  Regs;  Reg(\"sp\");  Reg(\"mstatus\");  Dr;\n");
  UartStr("MEM_*: RAM FS HEAP FB FIXED TRAP_SNAP REGS_SNAP STACK UART CLINT PLIC VIRTIO FW_CFG\n");
  UartStr("Drivers (MemMap last col): RVUart16550 RVTimer/CLINT RVPlicHw DskVirtioRV RVFb\n");
  UartStr("REG_*: ZERO RA SP GP TP T0-T6 S0-S11 A0-A7 (indices for docs / Reg(\"sp\"))\n");
  UartStr("CSR_*: MSTATUS MISA MIE MTVEC MSCRATCH MEPC MCAUSE MTVAL MIP SATP SSCRATCH MHARTID\n");
  UartStr("Get/Set: GetMStatus/SetMStatus GetMie/SetMie GetMtvec/SetMtvec GetMepc/SetMepc\n");
  UartStr("  GetMcause/SetMcause GetMtval/SetMtval GetMScratch/SetMScratch GetMip/SetMip\n");
  UartStr("  GetMIsa/SetMIsa GetSatp/SetSatp GetSScratch/SetSScratch GetMHartId (RO)\n");
  UartStr("  CSRGet(CSR_MSTATUS); CSRSet(CSR_MIE,v); GetRFlags/SetRFlags (= mstatus)\n");
  UartStr("Man(\"Regs\"); Man(\"MemMap\"); Man(\"GetMStatus\"); Man(\"MemMapFind\"); CpuRep;\n");
}
// CpuRep -- CpuRep()
// NAME
//   CpuRep - short CPU / CSR report (TempleOS CpuRep feel)
// SYNOPSIS
//   U0 CpuRep();
// DESCRIPTION
//   Prints hart id, misa, mstatus, mtvec, mie, mepc and points at Regs/RegHelp.
// INPUTS
//   none
// OUTPUTS
//   UART summary
// BUGS
//   Single-hart M-mode virt profile only.
U0 CpuRep()
{
  UartStr("CpuRep (RV64 M-mode):\n");
  "  mhartid=0x%X  misa=0x%X\n", GetMHartId(), GetMIsa();
  "  mstatus=0x%X  mtvec=0x%X  mie=0x%X\n", GetMStatus(), GetMtvec(), GetMie();
  "  mepc=0x%X  mcause=0x%X  satp=0x%X\n", GetMepc(), GetMcause(), GetSatp();
  UartStr("  Regs; Reg(\"mstatus\"); RegHelp; Man(\"Regs\");\n");
}
