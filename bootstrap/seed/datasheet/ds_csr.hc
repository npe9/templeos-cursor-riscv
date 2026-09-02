// ds_csr.hc -- RISC-V privileged CSR datasheet sheets (subset).
// Derived from privileged ISA; owned as structured HolyC for DsDecode.
// Edit + Run("ds_csr.hc"); to refresh (boot already loads this).
U0 DsSheetMstatus()
{
  DsBegin("mstatus", "csr", DS_KIND_CSR, CSR_MSTATUS, 8);
  DsField("SIE", 1, 1, "0=off,1=on", "Supervisor interrupt enable");
  DsField("MIE", 3, 3, "0=off,1=on", "Machine interrupt enable");
  DsField("SPIE", 5, 5, "0=off,1=on", "Supervisor prior IE");
  DsField("MPIE", 7, 7, "0=off,1=on", "Machine prior IE");
  DsField("SPP", 8, 8, "0=U,1=S", "Supervisor prior privilege");
  DsField("VS", 9, 10, "0=Off,1=Initial,2=Clean,3=Dirty", "Vector status");
  DsField("MPP", 11, 12, "0=U,1=S,3=M", "Machine prior privilege");
  DsField("FS", 13, 14, "0=Off,1=Initial,2=Clean,3=Dirty", "FP status");
  DsField("XS", 15, 16, "0=Off,1=Initial,2=Clean,3=Dirty", "Extension status");
  DsField("MPRV", 17, 17, "0=off,1=on", "Modify privilege for loads/stores");
  DsField("SUM", 18, 18, "0=off,1=on", "Permit supervisor user memory");
  DsField("MXR", 19, 19, "0=off,1=on", "Make executable readable");
  DsField("TVM", 20, 20, "0=off,1=on", "Trap virtual memory");
  DsField("TW", 21, 21, "0=off,1=on", "Timeout wait");
  DsField("TSR", 22, 22, "0=off,1=on", "Trap SRET");
  DsField("UXL", 32, 33, "1=32,2=64", "U-mode XLEN");
  DsField("SXL", 34, 35, "1=32,2=64", "S-mode XLEN");
  DsField("SD", 63, 63, "0=clean,1=dirty", "Some dirty state");
  DsEnd;
}

U0 DsSheetMie()
{
  DsBegin("mie", "csr", DS_KIND_CSR, CSR_MIE, 8);
  DsField("SSIE", 1, 1, "0=off,1=on", "Supervisor soft IRQ enable");
  DsField("MSIE", 3, 3, "0=off,1=on", "Machine soft IRQ enable");
  DsField("STIE", 5, 5, "0=off,1=on", "Supervisor timer IRQ enable");
  DsField("MTIE", 7, 7, "0=off,1=on", "Machine timer IRQ enable");
  DsField("SEIE", 9, 9, "0=off,1=on", "Supervisor ext IRQ enable");
  DsField("MEIE", 11, 11, "0=off,1=on", "Machine ext IRQ enable");
  DsEnd;
}

U0 DsSheetMip()
{
  DsBegin("mip", "csr", DS_KIND_CSR, CSR_MIP, 8);
  DsField("SSIP", 1, 1, "0=clear,1=pending", "Supervisor soft pending");
  DsField("MSIP", 3, 3, "0=clear,1=pending", "Machine soft pending");
  DsField("STIP", 5, 5, "0=clear,1=pending", "Supervisor timer pending");
  DsField("MTIP", 7, 7, "0=clear,1=pending", "Machine timer pending");
  DsField("SEIP", 9, 9, "0=clear,1=pending", "Supervisor ext pending");
  DsField("MEIP", 11, 11, "0=clear,1=pending", "Machine ext pending");
  DsEnd;
}

U0 DsSheetMcause()
{
  DsBegin("mcause", "csr", DS_KIND_CSR, CSR_MCAUSE, 8);
  DsField("CODE", 0, 62, 0, "Exception/interrupt code");
  DsField("INT", 63, 63, "0=exception,1=interrupt", "Interrupt bit");
  DsEnd;
}

U0 DsSheetMtvec()
{
  DsBegin("mtvec", "csr", DS_KIND_CSR, CSR_MTVEC, 8);
  DsField("MODE", 0, 1, "0=Direct,1=Vectored", "Trap vector mode");
  DsField("BASE", 2, 63, 0, "Trap vector base (<<2)");
  DsEnd;
}

U0 DsSheetMisa()
{
  DsBegin("misa", "csr", DS_KIND_CSR, CSR_MISA, 8);
  DsField("A", 0, 0, "0=no,1=yes", "Atomic");
  DsField("C", 2, 2, "0=no,1=yes", "Compressed");
  DsField("D", 3, 3, "0=no,1=yes", "Double FP");
  DsField("F", 5, 5, "0=no,1=yes", "Single FP");
  DsField("I", 8, 8, "0=no,1=yes", "RV32/64I base");
  DsField("M", 12, 12, "0=no,1=yes", "Multiply/divide");
  DsField("S", 18, 18, "0=no,1=yes", "Supervisor");
  DsField("U", 20, 20, "0=no,1=yes", "User");
  DsField("MXL", 62, 63, "1=32,2=64", "Machine XLEN");
  DsEnd;
}

U0 DsSheetSatp()
{
  DsBegin("satp", "csr", DS_KIND_CSR, CSR_SATP, 8);
  DsField("PPN", 0, 43, 0, "Physical page number of root");
  DsField("ASID", 44, 59, 0, "Address space id");
  DsField("MODE", 60, 63, "0=Bare,8=Sv39,9=Sv48", "Address translation mode");
  DsEnd;
}

U0 DsCsrInit()
{
  DsSheetMstatus;
  DsSheetMie;
  DsSheetMip;
  DsSheetMcause;
  DsSheetMtvec;
  DsSheetMisa;
  DsSheetSatp;
}
DsCsrInit;
