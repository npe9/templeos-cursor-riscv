// csr.hc -- RISC-V MemMap / GPR / CSR symbols + real csrr/csrw Get/Set + Reg dig-down.
// Boot after MemMapSelected.hc (board MEM_*) + sym.hc (MemMap/Regs slots). Edit: Run("csr.hc");
// Board MEM_* / MEMMAP_DRV_* come from MemMapSelected.hc (make -C templeos-riscv syncconfig).
// PLIC pending offset is architectural (not a Kconfig symbol).
#define MEM_PLIC_PENDING_OFF   0x1000
// NS16550A byte offsets @ MEM_UART (THR/RBR at +0).
#define UART_LSR_OFF  5
#define UART_LSR_THRE  0x20
#define UART_LSR_DR    0x01
// Legacy virtio-mmio register offsets (MagicValue 'virt' = 0x74726976).
#define VIRTIO_MAGIC           0x74726976
#define VIRTIO_REG_MAGIC       0x00
#define VIRTIO_REG_VERSION     0x04
#define VIRTIO_REG_DEVICE_ID   0x08
#define VIRTIO_REG_GUEST_PGSZ  0x28
#define VIRTIO_REG_STATUS      0x70
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
#define CSR_SSTATUS    0x100
#define CSR_SIE        0x104
#define CSR_STVEC      0x105
#define CSR_SSCRATCH   0x140
#define CSR_SEPC       0x141
#define CSR_SCAUSE     0x142
#define CSR_STVAL      0x143
#define CSR_SIP        0x144
#define CSR_SATP       0x180
#define CSR_MSTATUS    0x300
#define CSR_MISA       0x301
#define CSR_MEDELEG    0x302
#define CSR_MIDELEG    0x303
#define CSR_MIE        0x304
#define CSR_MTVEC      0x305
#define CSR_MCOUNTEREN 0x306
#define CSR_MSCRATCH   0x340
#define CSR_MEPC       0x341
#define CSR_MCAUSE     0x342
#define CSR_MTVAL      0x343
#define CSR_MIP        0x344
#define CSR_MCYCLE     0xB00
#define CSR_MINSTRET   0xB02
#define CSR_CYCLE      0xC00
#define CSR_TIME       0xC01
#define CSR_INSTRET    0xC02
#define CSR_MHARTID    0xF14
I64 g_reg_snap_asm;
I64 g_reg_entry;
I64 g_reg_snap_fresh;
// set by EvalAsmRun — RegEntry skips re-snap once so Reg("a0") sees post-asm GPRs
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
	HcGetMedeleg::
	csrr	a0, 0x302
	ret
	HcSetMedeleg::
	csrw	0x302, a0
	ret
	HcGetMideleg::
	csrr	a0, 0x303
	ret
	HcSetMideleg::
	csrw	0x303, a0
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
	HcGetMCounterEn::
	csrr	a0, 0x306
	ret
	HcSetMCounterEn::
	csrw	0x306, a0
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
	HcGetMCycle::
	csrr	a0, 0xB00
	ret
	HcGetMInstret::
	csrr	a0, 0xB02
	ret
	HcGetCycle::
	// M-mode: prefer mcycle (0xB00). U-mode cycle (0xC00) can illegal-trap
	// without Zicntr / mcounteren; mcycle is always legal in M-mode.
	csrr	a0, 0xB00
	ret
	HcGetInstret::
	csrr	a0, 0xB02
	ret
	HcGetSStatus::
	csrr	a0, 0x100
	ret
	HcSetSStatus::
	csrw	0x100, a0
	ret
	HcGetSie::
	csrr	a0, 0x104
	ret
	HcSetSie::
	csrw	0x104, a0
	ret
	HcGetStvec::
	csrr	a0, 0x105
	ret
	HcSetStvec::
	csrw	0x105, a0
	fencei
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
	HcGetSepc::
	csrr	a0, 0x141
	ret
	HcSetSepc::
	csrw	0x141, a0
	ret
	HcGetScause::
	csrr	a0, 0x142
	ret
	HcSetScause::
	csrw	0x142, a0
	ret
	HcGetStval::
	csrr	a0, 0x143
	ret
	HcSetStval::
	csrw	0x143, a0
	ret
	HcGetSip::
	csrr	a0, 0x144
	ret
	HcSetSip::
	csrw	0x144, a0
	ret
	HcGetMHartId::
	csrr	a0, 0xF14
	ret
	RegSnapAsm::
	addi	sp, sp, -16
	sd	t6, 0(sp)
	sd	t5, 8(sp)
	lui	t6, 0x10E00
	slli	t6, t6, 3
	sd	x1, 0x308(t6)
	addi	t5, sp, 16
	sd	t5, 0x310(t6)
	sd	x3, 0x318(t6)
	sd	x4, 0x320(t6)
	sd	x5, 0x328(t6)
	sd	x6, 0x330(t6)
	sd	x7, 0x338(t6)
	sd	x8, 0x340(t6)
	sd	x9, 0x348(t6)
	sd	x10, 0x350(t6)
	sd	x11, 0x358(t6)
	sd	x12, 0x360(t6)
	sd	x13, 0x368(t6)
	sd	x14, 0x370(t6)
	sd	x15, 0x378(t6)
	sd	x16, 0x380(t6)
	sd	x17, 0x388(t6)
	sd	x18, 0x390(t6)
	sd	x19, 0x398(t6)
	sd	x20, 0x3A0(t6)
	sd	x21, 0x3A8(t6)
	sd	x22, 0x3B0(t6)
	sd	x23, 0x3B8(t6)
	sd	x24, 0x3C0(t6)
	sd	x25, 0x3C8(t6)
	sd	x26, 0x3D0(t6)
	sd	x27, 0x3D8(t6)
	sd	x28, 0x3E0(t6)
	sd	x29, 0x3E8(t6)
	ld	t5, 8(sp)
	sd	t5, 0x3F0(t6)
	ld	t5, 0(sp)
	sd	t5, 0x3F8(t6)
	ld	t5, 8(sp)
	ld	t6, 0(sp)
	addi	sp, sp, 16
	ret
}

U0 RegsSnapOnly()
{
  // Inline asm — must match RegSnapAsm (also used from Reg:: / JIT g_reg_snap_asm).
  asm {
	addi	sp, sp, -16
	sd	t6, 0(sp)
	sd	t5, 8(sp)
	lui	t6, 0x10E00
	slli	t6, t6, 3
	sd	x1, 0x308(t6)
	addi	t5, sp, 16
	sd	t5, 0x310(t6)
	sd	x3, 0x318(t6)
	sd	x4, 0x320(t6)
	sd	x5, 0x328(t6)
	sd	x6, 0x330(t6)
	sd	x7, 0x338(t6)
	sd	x8, 0x340(t6)
	sd	x9, 0x348(t6)
	sd	x10, 0x350(t6)
	sd	x11, 0x358(t6)
	sd	x12, 0x360(t6)
	sd	x13, 0x368(t6)
	sd	x14, 0x370(t6)
	sd	x15, 0x378(t6)
	sd	x16, 0x380(t6)
	sd	x17, 0x388(t6)
	sd	x18, 0x390(t6)
	sd	x19, 0x398(t6)
	sd	x20, 0x3A0(t6)
	sd	x21, 0x3A8(t6)
	sd	x22, 0x3B0(t6)
	sd	x23, 0x3B8(t6)
	sd	x24, 0x3C0(t6)
	sd	x25, 0x3C8(t6)
	sd	x26, 0x3D0(t6)
	sd	x27, 0x3D8(t6)
	sd	x28, 0x3E0(t6)
	sd	x29, 0x3E8(t6)
	ld	t5, 8(sp)
	sd	t5, 0x3F0(t6)
	ld	t5, 0(sp)
	sd	t5, 0x3F8(t6)
	ld	t5, 8(sp)
	ld	t6, 0(sp)
	addi	sp, sp, 16
  }
}

U0 RegsRestoreOnly()
{
  // Do not reload ra/sp/fp/s* — HolyC frames use them. Only temps/args Print may smash.
  asm {
	lui	t6, 0x10E00
	slli	t6, t6, 3
	ld	x5, 0x328(t6)
	ld	x6, 0x330(t6)
	ld	x7, 0x338(t6)
	ld	x10, 0x350(t6)
	ld	x11, 0x358(t6)
	ld	x12, 0x360(t6)
	ld	x13, 0x368(t6)
	ld	x14, 0x370(t6)
	ld	x15, 0x378(t6)
	ld	x16, 0x380(t6)
	ld	x17, 0x388(t6)
	ld	x28, 0x3E0(t6)
	ld	x29, 0x3E8(t6)
	ld	x30, 0x3F0(t6)
	ld	t6, 0x3F8(t6)
  }
}
// GetMStatus -- GetMStatus()
// NAME
//   GetMStatus - read mstatus (machine status CSR)
// SYNOPSIS
//   I64 GetMStatus();
// DESCRIPTION
//   Reads the machine status register (interrupt enable, FPU dirty bits, …).
//   Pair with SetMStatus / CSRGet(CSR_MSTATUS) / Reg("mstatus").
// EXAMPLES
//   Print("%X\n", GetMStatus());
//   Reg("mstatus");
//   Print("%X\n", CSRGet(CSR_MSTATUS));
// SEE ALSO
//   SetMStatus  CSRGet  Reg  Regs  MIE  TrapInit
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

I64 GetMedeleg()
{
  return HcGetMedeleg();
}

U0 SetMedeleg(I64 v)
{
  HcSetMedeleg(v);
}

I64 GetMideleg()
{
  return HcGetMideleg();
}

U0 SetMideleg(I64 v)
{
  HcSetMideleg(v);
}

I64 GetMCounterEn()
{
  return HcGetMCounterEn();
}

U0 SetMCounterEn(I64 v)
{
  HcSetMCounterEn(v);
}

I64 GetMCycle()
{
  return HcGetMCycle();
}

I64 GetMInstret()
{
  return HcGetMInstret();
}

I64 GetCycle()
{
  return HcGetCycle();
}

I64 GetInstret()
{
  return HcGetInstret();
}

I64 GetSStatus()
{
  return HcGetSStatus();
}

U0 SetSStatus(I64 v)
{
  HcSetSStatus(v);
}

I64 GetSie()
{
  return HcGetSie();
}

U0 SetSie(I64 v)
{
  HcSetSie(v);
}

I64 GetStvec()
{
  return HcGetStvec();
}

U0 SetStvec(I64 v)
{
  HcSetStvec(v);
}

I64 GetSepc()
{
  return HcGetSepc();
}

U0 SetSepc(I64 v)
{
  HcSetSepc(v);
}

I64 GetScause()
{
  return HcGetScause();
}

U0 SetScause(I64 v)
{
  HcSetScause(v);
}

I64 GetStval()
{
  return HcGetStval();
}

U0 SetStval(I64 v)
{
  HcSetStval(v);
}

I64 GetSip()
{
  return HcGetSip();
}

U0 SetSip(I64 v)
{
  HcSetSip(v);
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
//   Reads a control/status register given its CSR_* number (e.g. CSR_MSTATUS).
//   Prefer named helpers (GetMStatus) when you know which register; use CSRGet
//   when the address is symbolic or passed around.
// EXAMPLES
//   Print("%X\n", CSRGet(CSR_MSTATUS));
//   Print("%X\n", GetMStatus());
//   Reg("mstatus");
// SEE ALSO
//   CSRSet  GetMStatus  Reg  Regs  RegHelp  CSR
// BUGS
//   Unknown csr numbers return 0 (no illegal-instruction probe).
I64 CSRGet(I64 csr)
{
  if (csr == CSR_MSTATUS)
    return GetMStatus();
  if (csr == CSR_MISA)
    return GetMIsa();
  if (csr == CSR_MEDELEG)
    return GetMedeleg();
  if (csr == CSR_MIDELEG)
    return GetMideleg();
  if (csr == CSR_MIE)
    return GetMie();
  if (csr == CSR_MTVEC)
    return GetMtvec();
  if (csr == CSR_MCOUNTEREN)
    return GetMCounterEn();
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
  if (csr == CSR_MCYCLE)
    return GetMCycle();
  if (csr == CSR_MINSTRET)
    return GetMInstret();
  if (csr == CSR_CYCLE)
    return GetCycle();
  if (csr == CSR_INSTRET)
    return GetInstret();
  if (csr == CSR_SSTATUS)
    return GetSStatus();
  if (csr == CSR_SIE)
    return GetSie();
  if (csr == CSR_STVEC)
    return GetStvec();
  if (csr == CSR_SATP)
    return GetSatp();
  if (csr == CSR_SSCRATCH)
    return GetSScratch();
  if (csr == CSR_SEPC)
    return GetSepc();
  if (csr == CSR_SCAUSE)
    return GetScause();
  if (csr == CSR_STVAL)
    return GetStval();
  if (csr == CSR_SIP)
    return GetSip();
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
//   Writes a control/status register by CSR_* number. Some registers are
//   read-only or WARL (hardware may ignore bits). Do not point mtvec at junk —
//   use TrapInit for the normal trap path.
// EXAMPLES
//   Print("%X\n", CSRGet(CSR_MIE));
//   // CSRSet(CSR_MIE, CSRGet(CSR_MIE)|128);  // set MTIE carefully
//   Man("CLINT");
// SEE ALSO
//   CSRGet  SetMStatus  TrapInit  RegHelp  CSR
// BUGS
//   Unknown csr: no-op. mhartid is RO.
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
  if (csr == CSR_MEDELEG) {
    SetMedeleg(v);
    return;
  }
  if (csr == CSR_MIDELEG) {
    SetMideleg(v);
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
  if (csr == CSR_MCOUNTEREN) {
    SetMCounterEn(v);
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
  if (csr == CSR_SSTATUS) {
    SetSStatus(v);
    return;
  }
  if (csr == CSR_SIE) {
    SetSie(v);
    return;
  }
  if (csr == CSR_STVEC) {
    SetStvec(v);
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
  if (csr == CSR_SEPC) {
    SetSepc(v);
    return;
  }
  if (csr == CSR_SCAUSE) {
    SetScause(v);
    return;
  }
  if (csr == CSR_STVAL) {
    SetStval(v);
    return;
  }
  if (csr == CSR_SIP) {
    SetSip(v);
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
//   Strings come from MemMapSelected.hc (Kconfig UART/PLIC/virtio/FB picks).
//   Kernel builds: see Kernel/Drv/RVMemMap.HC. Dig-down from MemMap;
//   Man("MemMap"); MemMapDrv;
// INPUTS
//   name - same aliases as MemMapFind ("uart","clint","plic","virtio","fb",…)
// OUTPUTS
//   Static driver hint string, or 0 if unknown
// BUGS
//   Seed table tracks MemMapSelected.hc (Kconfig); Kernel: RVMemMap.HC + RVAutoConf.HH.
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
//   MemMapSelected.hc (Kconfig); Kernel uses RVMemMap.HC + RVAutoConf.HH.
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
// ---- HolyC Regs snap+print+restore (MEM_REGS_SNAP). Soft path; Hw* / Sdtrig stay separate.
// ABI name table: RegGprIndex + RegGprLine (avoid U8*[32] walk — AOT hang on repl-holyc).
U0 RegLineDesc(U8 *name, I64 v, U8 *desc)
{
  UartStr("  ");
  UartStr(name);
  UartStr(" = ");
  Print("%p", v);
  if (desc && *desc) {
    UartStr("  ");
    UartStr(desc);
  }
  PutCh('\n');
}
// RegGprDigit -- parse trailing decimal digits (a7→7, s10→10); -1 if junk remains.
I64 RegGprDigit(U8 *s)
{
  I64 n;
  if (!s || !*s)
    return -1;
  n = 0;
  while (*s >= '0' && *s <= '9') {
    n = n * 10 + (*s - '0');
    s++;
  }
  if (*s)
    return -1;
  return n;
}
// RegGprIndex -- resolve xN / ABI / fp / REG_* without g_gpr_abi[] walk (AOT hang).
I64 RegGprIndex(U8 *name)
{
  I64 n;
  U8 *p;
  U8 c0;
  if (!name || !*name)
    return -1;
  if ((name[0] == 'x' || name[0] == 'X') && name[1] >= '0' && name[1] <= '9') {
    n = 0;
    p = name + 1;
    while (*p >= '0' && *p <= '9') {
      n = n * 10 + (*p - '0');
      p++;
    }
    if (!*p && n >= 0 && n < 32)
      return n;
    return -1;
  }
  if ((name[0] == 'R' || name[0] == 'r') && (name[1] == 'E' || name[1] == 'e') && (name[2] == 'G' || name[2] == 'g')) {
    p = name + 3;
    if (*p == '_')
      p++;
    name = p;
    if (!*name)
      return -1;
  }
  if (!StrICmp(name, "zero"))
    return REG_ZERO;
  if (!StrICmp(name, "ra"))
    return REG_RA;
  if (!StrICmp(name, "sp"))
    return REG_SP;
  if (!StrICmp(name, "gp"))
    return REG_GP;
  if (!StrICmp(name, "tp"))
    return REG_TP;
  if (!StrICmp(name, "fp") || !StrICmp(name, "s0"))
    return REG_FP;
  if (!StrICmp(name, "s1"))
    return REG_S1;
  c0 = name[0];
  if (c0 >= 'A' && c0 <= 'Z')
    c0 += 32;
  if (c0 == 't' && name[1]) {
    n = RegGprDigit(name + 1);
    if (n >= 0 && n <= 2)
      return REG_T0 + n;
    if (n >= 3 && n <= 6)
      return REG_T3 + (n - 3);
  }
  if (c0 == 'a' && name[1]) {
    n = RegGprDigit(name + 1);
    if (n >= 0 && n <= 7)
      return REG_A0 + n;
  }
  if (c0 == 's' && name[1]) {
    n = RegGprDigit(name + 1);
    if (n == 0 || n == 1)
      return REG_S0 + n;
    if (n >= 2 && n <= 11)
      return REG_S2 + (n - 2);
  }
  return -1;
}
// RegGprLine -- one GPR line xN/abi = value (Print only — UartStr chains hung Reg on AOT).
U0 RegGprLine(I64 i, I64 v)
{
  if (i == 0)
    "  x00/zero = %p  hardwired zero\n", v;
  else if (i == 1)
    "  x01/ra = %p  return address\n", v;
  else if (i == 2)
    "  x02/sp = %p  stack pointer\n", v;
  else if (i == 3)
    "  x03/gp = %p  global pointer\n", v;
  else if (i == 4)
    "  x04/tp = %p  thread pointer\n", v;
  else if (i == 5)
    "  x05/t0 = %p  temp (caller-saved)\n", v;
  else if (i == 6)
    "  x06/t1 = %p  temp (caller-saved)\n", v;
  else if (i == 7)
    "  x07/t2 = %p  temp (caller-saved)\n", v;
  else if (i == 8)
    "  x08/s0 = %p  saved / frame ptr (fp)\n", v;
  else if (i == 9)
    "  x09/s1 = %p  saved (callee-saved)\n", v;
  else if (i == 10)
    "  x10/a0 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 11)
    "  x11/a1 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 12)
    "  x12/a2 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 13)
    "  x13/a3 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 14)
    "  x14/a4 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 15)
    "  x15/a5 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 16)
    "  x16/a6 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 17)
    "  x17/a7 = %p  arg/ret (caller-saved)\n", v;
  else if (i == 18)
    "  x18/s2 = %p  saved (callee-saved)\n", v;
  else if (i == 19)
    "  x19/s3 = %p  saved (callee-saved)\n", v;
  else if (i == 20)
    "  x20/s4 = %p  saved (callee-saved)\n", v;
  else if (i == 21)
    "  x21/s5 = %p  saved (callee-saved)\n", v;
  else if (i == 22)
    "  x22/s6 = %p  saved (callee-saved)\n", v;
  else if (i == 23)
    "  x23/s7 = %p  saved (callee-saved)\n", v;
  else if (i == 24)
    "  x24/s8 = %p  saved (callee-saved)\n", v;
  else if (i == 25)
    "  x25/s9 = %p  saved (callee-saved)\n", v;
  else if (i == 26)
    "  x26/s10 = %p  saved (callee-saved)\n", v;
  else if (i == 27)
    "  x27/s11 = %p  saved (callee-saved)\n", v;
  else if (i == 28)
    "  x28/t3 = %p  temp (caller-saved)\n", v;
  else if (i == 29)
    "  x29/t4 = %p  temp (caller-saved)\n", v;
  else if (i == 30)
    "  x30/t5 = %p  temp (caller-saved)\n", v;
  else if (i == 31)
    "  x31/t6 = %p  temp (caller-saved)\n", v;
  else
    "  x??/? = %p\n", v;
}
// ---- CSR bitfield decode (explicit bit tests; no table walks — repl-holyc AOT) ----
U0 CsrDecodeMstatus(I64 v)
{
  I64 mpp, fs, xs, vs, uxl, sxl;
  if (v & 1)
    Print("   UIE=1 (user interrupts enabled)\n");
  if (v & 2)
    Print("   SIE=1 (supervisor interrupts enabled)\n");
  if (v & 8)
    Print("   MIE=1 (machine interrupts enabled)\n");
  else
    Print("   MIE=0 (machine interrupts disabled)\n");
  if (v & 16)
    Print("   UPIE=1 (user prior IE)\n");
  if (v & 32)
    Print("   SPIE=1 (supervisor prior IE)\n");
  if (v & 128)
    Print("   MPIE=1 (machine prior IE)\n");
  if (v & 256)
    Print("   SPP=1 (prior privilege S-mode)\n");
  vs = (v >> 9) & 3;
  if (vs)
    Print("   VS=%d (%s)\n", vs, vs == 1 ? "Initial" : vs == 2 ? "Clean" : vs == 3 ? "Dirty" : "?");
  mpp = (v >> 11) & 3;
  if (mpp == 1)
    Print("   MPP=01 (S-mode)\n");
  else if (mpp == 3)
    Print("   MPP=11 (M-mode)\n");
  else if (mpp == 2)
    Print("   MPP=10 (reserved)\n");
  else
    Print("   MPP=00 (U-mode)\n");
  fs = (v >> 13) & 3;
  if (fs)
    Print("   FS=%d (%s)\n", fs, fs == 1 ? "Initial" : fs == 2 ? "Clean" : fs == 3 ? "Dirty" : "?");
  xs = (v >> 15) & 3;
  if (xs)
    Print("   XS=%d (%s)\n", xs, xs == 1 ? "Initial" : xs == 2 ? "Clean" : xs == 3 ? "Dirty" : "?");
  if (v & 0x20000)
    Print("   MPRV=1 (loads/stores at MPP privilege)\n");
  if (v & 0x40000)
    Print("   SUM=1 (supervisor may access user pages)\n");
  if (v & 0x80000)
    Print("   MXR=1 (executable pages readable)\n");
  if (v & 0x100000)
    Print("   TVM=1 (trap satp/tlb ops from S-mode)\n");
  if (v & 0x200000)
    Print("   TW=1 (trap WFI from S-mode)\n");
  if (v & 0x400000)
    Print("   TSR=1 (trap sret from S-mode)\n");
  uxl = (v >> 32) & 3;
  if (uxl == 1)
    Print("   UXL=01 (32-bit U-mode)\n");
  else if (uxl == 2)
    Print("   UXL=10 (64-bit U-mode)\n");
  sxl = (v >> 34) & 3;
  if (sxl == 1)
    Print("   SXL=01 (32-bit S-mode)\n");
  else if (sxl == 2)
    Print("   SXL=10 (64-bit S-mode)\n");
  if (v & 0x8000000000000000)
    Print("   SD=1 (some state dirty)\n");
}

U0 CsrDecodeMisa(I64 v)
{
  I64 mxl, any;
  mxl = (v >> 62) & 3;
  if (mxl == 1)
    Print("   MXL=01 (RV32)\n");
  else if (mxl == 2)
    Print("   MXL=10 (RV64)\n");
  else if (mxl)
    Print("   MXL=%d (?)\n", mxl);
  any = 0;
  if (v & 1) {
    Print("   A");
    any = 1;
  }
  if (v & 4) {
    if (any)
      Print(" C");
    else
      Print("   C");
    any = 1;
  }
  if (v & 8) {
    if (any)
      Print(" D");
    else
      Print("   D");
    any = 1;
  }
  if (v & 32) {
    if (any)
      Print(" F");
    else
      Print("   F");
    any = 1;
  }
  if (v & 256) {
    if (any)
      Print(" I");
    else
      Print("   I");
    any = 1;
  }
  if (v & 4096) {
    if (any)
      Print(" M");
    else
      Print("   M");
    any = 1;
  }
  if (v & 262144) {
    if (any)
      Print(" S");
    else
      Print("   S");
    any = 1;
  }
  if (v & 1048576) {
    if (any)
      Print(" U");
    else
      Print("   U");
    any = 1;
  }
  if (any)
    Print(" (ISA extensions set)\n");
}

U0 CsrDecodeIrqBits(I64 v, U8 *kind)
{
  if (v & 2)
    Print("   SSIE=1 (supervisor soft %s)\n", kind);
  if (v & 8)
    Print("   MSIE=1 (machine soft %s)\n", kind);
  if (v & 32)
    Print("   STIE=1 (supervisor timer %s)\n", kind);
  if (v & 128)
    Print("   MTIE=1 (machine timer %s)\n", kind);
  if (v & 512)
    Print("   SEIE=1 (supervisor external %s)\n", kind);
  if (v & 2048)
    Print("   MEIE=1 (machine external %s)\n", kind);
}

U0 CsrDecodeMie(I64 v)
{
  CsrDecodeIrqBits(v, "enable");
}

U0 CsrDecodeMip(I64 v)
{
  if (v & 2)
    Print("   SSIP=1 (supervisor soft pending)\n");
  if (v & 8)
    Print("   MSIP=1 (machine soft pending)\n");
  if (v & 32)
    Print("   STIP=1 (supervisor timer pending)\n");
  if (v & 128)
    Print("   MTIP=1 (machine timer pending)\n");
  if (v & 512)
    Print("   SEIP=1 (supervisor external pending)\n");
  if (v & 2048)
    Print("   MEIP=1 (machine external pending)\n");
}

U0 CsrDecodeMtvec(I64 v)
{
  I64 mode;
  mode = v & 3;
  if (mode == 0)
    Print("   MODE=0 (Direct)\n");
  else if (mode == 1)
    Print("   MODE=1 (Vectored)\n");
  else
    Print("   MODE=%d (?)\n", mode);
  Print("   BASE=%p (trap entry)\n", v & ~3);
}

U0 CsrDecodeMepc(I64 v)
{
  Print("   PC=%p", v);
  if (v & 1)
    Print(" (bit0 set — compressed or misaligned)");
  Print("\n");
  Print("   mret target\n");
}
// McauseCauseName -- symbolic interrupt/exception name for mcause (CSR 0x342).
U8 *McauseCauseName(I64 v)
{
  I64 intr, code;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  if (intr) {
    if (code == 0)
      return "user soft interrupt";
    if (code == 1)
      return "supervisor soft interrupt";
    if (code == 3)
      return "machine soft interrupt";
    if (code == 4)
      return "user timer interrupt";
    if (code == 5)
      return "supervisor timer interrupt";
    if (code == 7)
      return "machine timer interrupt";
    if (code == 8)
      return "user external interrupt";
    if (code == 9)
      return "supervisor external interrupt";
    if (code == 11)
      return "machine external interrupt";
    return "interrupt";
  }
  if (code == 0)
    return "insn address misaligned";
  if (code == 1)
    return "insn access fault";
  if (code == 2)
    return "illegal instruction";
  if (code == 3)
    return "breakpoint";
  if (code == 4)
    return "load address misaligned";
  if (code == 5)
    return "load access fault";
  if (code == 6)
    return "store address misaligned";
  if (code == 7)
    return "store access fault";
  if (code == 8)
    return "ecall from U-mode";
  if (code == 9)
    return "ecall from S-mode";
  if (code == 11)
    return "ecall from M-mode";
  if (code == 12)
    return "insn page fault";
  if (code == 13)
    return "load page fault";
  if (code == 15)
    return "store page fault";
  return "exception";
}
// McausePrint -- compact crash-line decode: mcause=0xN  Exception/Interrupt code=N (name)
U0 McausePrint(I64 v)
{
  I64 intr, code;
  U8 *name;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  name = McauseCauseName(v);
  if (intr)
    "  mcause=0x%X  Interrupt code=%d (%s)\n", v, code, name;
  else
    "  mcause=0x%X  Exception code=%d (%s)\n", v, code, name;
}

U0 CsrDecodeMcause(I64 v)
{
  I64 intr, code;
  U8 *name;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  name = McauseCauseName(v);
  if (intr)
    Print("   Interrupt=1 (%s)\n", name);
  else
    Print("   Exception (Interrupt=0)\n   code=%d (%s)\n", code, name);
  if (intr) {
    Print("   code=%d (", code);
    if (code == 11)
      Print("MEI");
    else if (code == 7)
      Print("MTI");
    else if (code == 3)
      Print("MSI");
    else if (code == 9)
      Print("SEI");
    else if (code == 5)
      Print("STI");
    else if (code == 1)
      Print("SSI");
    else
      Print("?");
    Print(")\n");
  }
}

U0 CsrDecodeMtval(I64 v, I64 mcause_hint)
{
  I64 intr, code;
  if (!v) {
    Print("   (zero)\n");
    return;
  }
  code = mcause_hint;
  if (code < 0) {
    code = GetMcause();
  }
  intr = (code >> 63) & 1;
  code = code & 0x7FFFFFFFFFFFFFFF;
  if (!intr && (code == 0 || code == 2))
    Print("   faulting instruction bits (misaligned/illegal insn)\n");
  else if (!intr && code >= 4 && code <= 7)
    Print("   bad address for load/store\n");
  else if (!intr && code >= 12 && code <= 15)
    Print("   faulting virtual address\n");
  Print("   value=%p\n", v);
}

U0 CsrDecodeMscratch(I64 v)
{
  if (v)
    Print("   scratch=%p (trap/OS private)\n", v);
  else
    Print("   (zero — unused)\n");
}

U0 CsrDecodeMhartid(I64 v)
{
  Print("   hart %d (read-only)\n", v);
}

U0 CsrDecodeMtime(I64 v)
{
  Print("   CLINT MMIO @ MEM_MTIME (not CSR; CSR_TIME=0xC01 is read-only shadow)\n");
  Print("   ticks=%d\n", v);
}
// CsrExplainVal -- decode CSR bitfields for a known value (Print only — AOT-safe).
U0 CsrExplainVal(U8 *name, I64 v, I64 mcause_hint)
{
  if (!name || !*name)
    return;
  if (!StrICmp(name, "mstatus")) {
    CsrDecodeMstatus(v);
    return;
  }
  if (!StrICmp(name, "misa")) {
    CsrDecodeMisa(v);
    return;
  }
  if (!StrICmp(name, "mie")) {
    CsrDecodeMie(v);
    return;
  }
  if (!StrICmp(name, "mip")) {
    CsrDecodeMip(v);
    return;
  }
  if (!StrICmp(name, "mtvec")) {
    CsrDecodeMtvec(v);
    return;
  }
  if (!StrICmp(name, "mepc")) {
    CsrDecodeMepc(v);
    return;
  }
  if (!StrICmp(name, "mcause")) {
    CsrDecodeMcause(v);
    return;
  }
  if (!StrICmp(name, "mtval")) {
    CsrDecodeMtval(v, mcause_hint);
    return;
  }
  if (!StrICmp(name, "mscratch")) {
    CsrDecodeMscratch(v);
    return;
  }
  if (!StrICmp(name, "mhartid")) {
    CsrDecodeMhartid(v);
    return;
  }
  if (!StrICmp(name, "mtime")) {
    CsrDecodeMtime(v);
    return;
  }
}
// CsrExplain -- CsrExplain("mstatus") / live decode; alias path for Reg dig-down.
I64 CsrExplain(U8 *name)
{
  I64 v;
  if (!name || !*name) {
    UartStr("CsrExplain: need CSR name — Reg(\"mstatus\"); Bits(\"mstatus\"); Man(\"CSR\");\n");
    return -1;
  }
  if (!StrICmp(name, "mtime")) {
    v = *(I64 *)MEM_MTIME;
    Print("mtime = 0x%X\n", v);
    CsrExplainVal("mtime", v, -1);
    return v;
  }
  if (!StrICmp(name, "mstatus"))
    v = GetMStatus();
  else if (!StrICmp(name, "misa"))
    v = GetMIsa();
  else if (!StrICmp(name, "mie"))
    v = GetMie();
  else if (!StrICmp(name, "mip"))
    v = GetMip();
  else if (!StrICmp(name, "mtvec"))
    v = GetMtvec();
  else if (!StrICmp(name, "mepc"))
    v = GetMepc();
  else if (!StrICmp(name, "mcause"))
    v = GetMcause();
  else if (!StrICmp(name, "mtval"))
    v = GetMtval();
  else if (!StrICmp(name, "mscratch"))
    v = GetMScratch();
  else if (!StrICmp(name, "mhartid"))
    v = GetMHartId();
  else {
    UartStr("CsrExplain: unknown — try RegHelp; Bits(\"mstatus\"); Man(\"CSR\");\n");
    return -1;
  }
  Print("%s = 0x%X\n", name, v);
  CsrExplainVal(name, v, -1);
  return v;
}
// CsrDecodeVal -- CsrDecodeVal("mcause", 3) decode without live CSR read.
U0 CsrDecodeVal(U8 *name, I64 v)
{
  if (!name || !*name) {
    UartStr("CsrDecodeVal: need name + value — CsrDecodeVal(\"mcause\", 3);\n");
    return;
  }
  Print("%s = 0x%X\n", name, v);
  CsrExplainVal(name, v, -1);
}
// Called after GPRs are frozen in MEM_REGS_SNAP (or zeros if snap skipped).
U0 RegsDumpHc()
{
  I64 i, v;
  UartStr("GPRs at Regs stub entry (xN/abi; snap+restore; Man(\"ABI\")):\n");
  for (i = 1; i < 32; i++) {
    v = *(I64 *)(MEM_REGS_SNAP + i * 8);
    RegGprLine(i, v);
  }
  // Spill CSRs via inline csrr (HcGet* calls after the first hung on holyc AOT).
  asm {
	lui	t6, 0x10E00
	slli	t6, t6, 3
	csrr	t5, 0x300
	sd	t5, 0x400(t6)
	csrr	t5, 0x301
	sd	t5, 0x408(t6)
	csrr	t5, 0x304
	sd	t5, 0x410(t6)
	csrr	t5, 0x305
	sd	t5, 0x418(t6)
	csrr	t5, 0x341
	sd	t5, 0x420(t6)
	csrr	t5, 0x342
	sd	t5, 0x428(t6)
	csrr	t5, 0x343
	sd	t5, 0x430(t6)
	csrr	t5, 0x340
	sd	t5, 0x438(t6)
	csrr	t5, 0x344
	sd	t5, 0x440(t6)
	csrr	t5, 0xF14
	sd	t5, 0x448(t6)
  }
  UartStr("CSRs (CSR_* / GetMStatus… ; Reg(\"mstatus\"); Man(\"Regs\")):\n");
  v = *(I64 *)(MEM_REGS_SNAP + 0x100);
  RegLineDesc("mstatus ", v, "machine status (MIE/FS/...)");
  CsrExplainVal("mstatus", v, -1);
  v = *(I64 *)(MEM_REGS_SNAP + 0x108);
  RegLineDesc("misa    ", v, "ISA / extension bitmap (WARL)");
  v = *(I64 *)(MEM_REGS_SNAP + 0x110);
  RegLineDesc("mie     ", v, "machine interrupt enable");
  v = *(I64 *)(MEM_REGS_SNAP + 0x118);
  RegLineDesc("mtvec   ", v, "trap vector base");
  v = *(I64 *)(MEM_REGS_SNAP + 0x120);
  RegLineDesc("mepc    ", v, "exception PC (mret target)");
  v = *(I64 *)(MEM_REGS_SNAP + 0x128);
  RegLineDesc("mcause  ", v, "trap cause (interrupt|code)");
  CsrExplainVal("mcause", v, -1);
  v = *(I64 *)(MEM_REGS_SNAP + 0x130);
  RegLineDesc("mtval   ", v, "bad addr / faulting insn");
  v = *(I64 *)(MEM_REGS_SNAP + 0x138);
  RegLineDesc("mscratch", v, "M scratch");
  v = *(I64 *)(MEM_REGS_SNAP + 0x140);
  RegLineDesc("mip     ", v, "machine interrupt pending");
  v = *(I64 *)(MEM_REGS_SNAP + 0x148);
  RegLineDesc("mhartid ", v, "hardware thread id (RO)");
  v = *(I64 *)MEM_MTIME;
  RegLineDesc("mtime   ", v, "CLINT cycle (MMIO, not CSR)");
  UartStr("Dig-down: Reg(\"sp\"); Reg(\"mstatus\"); CsrExplain(\"mcause\"); Bits(\"mie\"); RegHelp;\n");
}
// Print one reg from MEM_REGS_SNAP (GPRs) or live CSR. Called from Reg:: after
// RegSnapAsm — GPR indices reflect call-site values, not post-prologue live regs.
I64 RegOneHc(U8 *name)
{
  I64 gi, v;
  if (!name || !*name) {
    UartStr("Reg: need a name — Reg(\"sp\"); Reg(\"mstatus\"); RegHelp;\n");
    return -1;
  }
  gi = RegGprIndex(name);
  if (gi >= 0) {
    v = *(I64 *)(MEM_REGS_SNAP + gi * 8);
    RegGprLine(gi, v);
    if (!StrICmp(name, "fp") && gi == REG_FP)
      "  (fp is alias for s0/x08)\n";
    return v;
  }
  if (!StrICmp(name, "mstatus")) {
    v = GetMStatus();
    RegLineDesc("mstatus", v, "machine status");
    CsrExplainVal("mstatus", v, -1);
    return v;
  }
  if (!StrICmp(name, "mepc")) {
    v = GetMepc();
    RegLineDesc("mepc", v, "exception PC");
    CsrExplainVal("mepc", v, -1);
    return v;
  }
  if (!StrICmp(name, "mcause")) {
    v = GetMcause();
    RegLineDesc("mcause", v, "trap cause");
    CsrExplainVal("mcause", v, -1);
    return v;
  }
  if (!StrICmp(name, "mtvec")) {
    v = GetMtvec();
    RegLineDesc("mtvec", v, "trap vector");
    CsrExplainVal("mtvec", v, -1);
    return v;
  }
  if (!StrICmp(name, "mie")) {
    v = GetMie();
    RegLineDesc("mie", v, "interrupt enable");
    CsrExplainVal("mie", v, -1);
    return v;
  }
  if (!StrICmp(name, "mip")) {
    v = GetMip();
    RegLineDesc("mip", v, "interrupt pending");
    CsrExplainVal("mip", v, -1);
    return v;
  }
  if (!StrICmp(name, "mtval")) {
    v = GetMtval();
    RegLineDesc("mtval", v, "bad addr / insn");
    CsrExplainVal("mtval", v, GetMcause());
    return v;
  }
  if (!StrICmp(name, "mscratch")) {
    v = GetMScratch();
    RegLineDesc("mscratch", v, "M scratch");
    CsrExplainVal("mscratch", v, -1);
    return v;
  }
  if (!StrICmp(name, "misa")) {
    v = GetMIsa();
    RegLineDesc("misa", v, "ISA bitmap");
    CsrExplainVal("misa", v, -1);
    return v;
  }
  if (!StrICmp(name, "satp")) {
    v = GetSatp();
    RegLineDesc("satp", v, "addr xlate");
    return v;
  }
  if (!StrICmp(name, "sscratch")) {
    v = GetSScratch();
    RegLineDesc("sscratch", v, "S scratch");
    return v;
  }
  if (!StrICmp(name, "mhartid")) {
    v = GetMHartId();
    RegLineDesc("mhartid", v, "hart id");
    CsrExplainVal("mhartid", v, -1);
    return v;
  }
  if (!StrICmp(name, "mtime")) {
    v = *(I64 *)MEM_MTIME;
    RegLineDesc("mtime   ", v, "CLINT cycle (MMIO)");
    CsrExplainVal("mtime", v, -1);
    return v;
  }
  UartStr("Reg: unknown \"");
  UartStr(name);
  UartStr("\" — try RegHelp; or Regs;\n");
  return -1;
}
// Legacy worry_dream publishes C fns at 0x87001xxx. On repl-holyc that page is
// bare DRAM — non-zero garbage must not be jal'd (Regs hung after soft banner).
// Define before MemMap/Regs (no &OnTrap-style forward-ref on the checker).
I64 SoftDbgSlotFnOk(I64 p)
{
  /* Legacy only: HostSlotsInstall publishes SOFTDBG_SLOT_MAGIC at 0x87001FF8. */
  if (*(I64 *)0x87001FF8 != 0x534C4F54)
    return 0;
  if (!p)
    return 0;
  if (p < 0x80000000 || p >= 0x87000000)
    return 0;
  return 1;
}

I64 RegStubPtrOk(I64 p)
{
  // HostSlotsInstall C stubs (reg_one_stub/regs_snap_stub) — no magic required.
  if (!p)
    return 0;
  if (p >= 0x80000000 && p < 0x87000000)
    return 1;
  return 0;
}

U0 SoftDbgHostSlotsClear()
{
  I64 i, base;
  base = 0x87001000;
  i = 0;
  while (i < 512) {
    *(I64 *)(base + i * 8) = 0;
    i++;
  }
}
// MemMap -- MemMap()
// NAME
//   MemMap - print RISC-V memory map with MEM_* symbols and owning drivers
// SYNOPSIS
//   U0 MemMap();
// DESCRIPTION
//   Lists RAM, HolyC memfs/heap, FB, trap/regs snaps, stack, and MMIO with driver
//   column. Legacy repl.elf may use a C host slot for live JIT code_mem sizes;
//   otherwise this HolyC map (same dig-down as MemMapDrv).
// EXAMPLES
//   MemMap;  MemMapFind("heap");  MemMapDrvFind("uart");
// SEE ALSO
//   MemMapDrv  MemMapFind  Regs  RegHelp  Man("MemMap")
U0 MemMap()
{
  I64 (*mm)();
  I64 code_base, heap_base;
  mm = *(I64 *)0x87001128;
  if (SoftDbgSlotFnOk(mm)) {
    mm();
    return;
  }
  UartStr("Memory map (RISC-V; MEM_* in csr.hc; last col = HolyC driver):\n");
  "  MEM_RAM        0x%X  DRAM                          %s\n", MEM_RAM, MEMMAP_DRV_RAM;
  code_base = *(I64 *)0x87001140;
  heap_base = *(I64 *)0x87001148;
  if (code_base)
    "  MEM_CODE     @ %p  [live JIT code_mem]\n", code_base;
  if (heap_base)
    "  MEM_JIT_HEAP @ %p  [live C heap_mem]\n", heap_base;
  "  MEM_FS         0x%X  HolyC memfs arena           %s\n", MEM_FS, MEMMAP_DRV_FS;
  "  MEM_HEAP       0x%X  HolyC MAlloc arena          %s\n", MEM_HEAP, MEMMAP_DRV_HEAP;
  "  MEM_FB         0x%X  soft FB (ramfb)             %s\n", MEM_FB, MEMMAP_DRV_FB;
  "  MEM_FIXED      0x%X  trap/regs + host slots      [plat]\n", MEM_FIXED;
  "  MEM_TRAP_SNAP  0x%X  DbgReg / trap GPRs          %s\n", MEM_TRAP_SNAP, MEMMAP_DRV_TRAP;
  "  MEM_REGS_SNAP  0x%X  Regs() GPR snapshot         %s\n", MEM_REGS_SNAP, MEMMAP_DRV_REGS;
  "  MEM_STACK      0x%X  Boot/Reset stack (down)     [plat]\n", MEM_STACK;
  "  MEM_UART       0x%X  16550                       %s\n", MEM_UART, MEMMAP_DRV_UART;
  "  MEM_CLINT      0x%X  mtime/mtimecmp              %s\n", MEM_CLINT, MEMMAP_DRV_CLINT;
  "  MEM_PLIC       0x%X  external IRQs               %s\n", MEM_PLIC, MEMMAP_DRV_PLIC;
  "  MEM_VIRTIO     0x%X  virtio-mmio                 %s\n", MEM_VIRTIO, MEMMAP_DRV_VIRTIO;
  "  MEM_FW_CFG     0x%X  QEMU fw_cfg                 %s\n", MEM_FW_CFG, MEMMAP_DRV_FW_CFG;
  "  MEM_TEST       0x%X  SiFive test                 %s\n", MEM_TEST, MEMMAP_DRV_TEST;
  UartStr("Dig-down: Regs; Reg(\"mstatus\"); MemMapDrvFind(\"uart\"); Man(\"MemMap\"); RegHelp;\n");
  UartStr("  MemMapFind(\"heap\");  Print(\"%X\\n\", MEM_HEAP);\n");
}
// Regs -- Regs()
// NAME
//   Regs - dump all GPRs + CSRs with descriptions
// SYNOPSIS
//   U0 Regs();
// DESCRIPTION
//   Snapshots GPRs at stub entry into MEM_REGS_SNAP, prints them + CSRs, then
//   restores so UART print does not smash live regs. Prefer this soft path over
//   Hw*/Sdtrig. Dig-down: Reg("sp"); RegHelp; Man("Regs"); docs/DEBUGGER.md.
// BUGS
//   Stub-entry freeze (not mid-expr). Same-line asm{…}; Regs / Reg("a7").
#define HC_SLOT_REGS     0x87001130
#define HC_SLOT_REG_ONE  0x87001150
U0 Regs()
{
  I64 (*regs_stub)();
  // Host slots only on legacy repl.elf (HC_SLOT_COMPILE); hc-repl leaves page zero/garbage.
  if (*(I64 *)0x87001000) {
    regs_stub = *(I64 *)HC_SLOT_REGS;
    if (RegStubPtrOk ((I64)regs_stub)) {
      regs_stub();
      return;
    }
  }
  UartStr("Regs (HolyC soft):\n");
  RegsSnapOnly();
  RegsDumpHc();
  RegsRestoreOnly();
}

I64 RegEntry(U8 *name)
{
  if (!g_reg_snap_fresh)
    RegsSnapOnly();
  g_reg_snap_fresh = 0;
  return RegOneHc(name);
}

I64 Reg(U8 *name)
{
  I64 (*reg_one)(U8 *);
  if (!name)
    return -1;
  if (*(I64 *)0x87001000) {
    reg_one = *(I64 *)HC_SLOT_REG_ONE;
    if (RegStubPtrOk ((I64)reg_one))
      return reg_one(name);
  }
  return RegEntry(name);
}

U0 RegSnapAddrFix()
{
  asm {
	la	t0, RegSnapAsm
	la	t1, g_reg_snap_asm
	sd	t0, 0(t1)
  }
  g_reg_entry = RegEntry;
}
// RegHelp -- RegHelp()
// NAME
//   RegHelp - list GPR/CSR/MEM symbols and Get/Set APIs
// SYNOPSIS
//   U0 RegHelp();
// DESCRIPTION
//   Cheat sheet for MemMap → Regs → Reg("name") dig-down: MEM_* windows, REG_*
//   names, CSR_* constants, and the Get/Set helpers that read them.
// EXAMPLES
//   RegHelp;
//   MemMap;
//   Regs;
// SEE ALSO
//   Regs  Reg  MemMap  CSRGet  Man  CSR
// BUGS
//   Hand-maintained; keep in sync with csr.hc / MemMapSelected.hc.
U0 RegHelp()
{
  UartStr("RegHelp — MemMap / GPR / CSR dig-down\n");
  UartStr("  MemMap;  MemMapDrv;  MemMapFind(\"heap\");  MemMapDrvFind(\"uart\");\n");
  UartStr("  Print(\"%X\\n\", MEM_HEAP);  Regs;  Reg(\"sp\");  Reg(\"mstatus\");  CsrExplain(\"mcause\");  Bits(\"mie\");  Dr;\n");
  UartStr("MEM_*: RAM FS HEAP FB FIXED TRAP_SNAP REGS_SNAP STACK UART CLINT PLIC VIRTIO FW_CFG\n");
  UartStr("Drivers (MemMap last col): RVUart16550 RVTimer/CLINT RVPlicHw DskVirtioRV RVFb\n");
  UartStr("GPR aliases: x0-x31, zero/ra/sp/fp/gp/t*/s*/a*, REG_*; case-insensitive\n");
  UartStr("  Reg(\"a0\"); Reg(\"x10\"); Reg(\"fp\"); Man(\"ABI\"); Man(\"Reg\"); Run(\"A02_RegsABI.hc\");\n");
  UartStr("CSR_*: M*/S* + MCYCLE/MINSTRET/CYCLE/INSTRET (see RegHelp / Man(\"CSR\"))\n");
  UartStr("CSR decode: Reg(\"mstatus\"); CsrExplain(\"mcause\"); Bits(\"mie\"); Man(\"mstatus\");\n");
  UartStr("Datasheet: DsFind(\"uart\"); DsShow(\"mstatus\"); DsDecode(\"uart.lsr\",0x21); Man(\"Datasheet\");\n");
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
  "  Regs; Reg(\"mstatus\"); CsrExplain(\"mcause\"); Bits(\"mie\"); RegHelp; Man(\"Regs\");\n";
}
