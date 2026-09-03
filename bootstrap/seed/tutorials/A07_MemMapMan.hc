// A07_MemMapMan.hc -- Part A7: MemMap dig-down and Man pages
//
// HOW TO WORK THIS LAB
//   Run("A07_MemMapMan.hc");  edit Fill_in;  Run again.
//
// LEARNING GOALS
//   Hardware on this port is discovered through the memory map, not through
//   a host emulator monitor. Workflow:
//     1. MemMap;           -- regions + driver column
//     2. MemMapFind(name); -- address for "uart","clint","plic","fs",...
//     3. MemMapDrvFind(name); -- which HolyC driver owns the window
//     4. Man("Topic");     -- CLINT, UART, PLIC, SiFive, Virtio*, MemMap,...
//
//   Soft arenas (MEM_FS memfs, MEM_HEAP) sit beside MMIO. Mixing them up
//   (writing "files" into UART, etc.) is a classic bug -- the map is the
//   ground truth for this board profile (Kconfig / RVSifivePlat may retarget).
//
// NEXT
//   A08_REPLDrills -- Part A capstone combining tools.
U0 A07_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 A07_Demo()
{
  U8 *drv;
  Print("A07 demo: live dig-down\n");
  MemMap;
  drv = MemMapDrvFind("uart");
  Print("uart driver string: %s\n", drv);
  Print("Also: Man(\"MemMap\"); Man(\"UART\"); Man(\"PLIC\"); Man(\"CLINT\");\n");
  A07_Expect("A07_uart_addr", MemMapFind("uart"), MEM_UART);
  A07_Expect("A07_clint_addr", MemMapFind("clint"), MEM_CLINT);
}
// Ex1 Warmup: UART base.
I64 A07_Ex1_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex2: PLIC base.
I64 A07_Ex2_Plic()
{
  // TODO Fill_in: return MemMapFind("plic");
  return 0;
}
// Ex3: memfs base.
I64 A07_Ex3_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex4: heap base.
I64 A07_Ex4_Heap()
{
  // TODO Fill_in: return MemMapFind("heap");
  return 0;
}
// Ex5: driver string for uart -- compare to MemMapDrvFind.
// Return 1 if StrCmp(MemMapDrvFind("uart"), MemMapDrvFind("uart"))==0
// (tautology warmup) AND find returns non-NULL.
I64 A07_Ex5_UartDrvOk()
{
  U8 *d;
  // TODO Fill_in:
  //   d = MemMapDrvFind("uart");
  //   if (d) return 1;
  //   return 0;
  return 0;
}
// Ex6: virtio window (may exist even if net unused).
I64 A07_Ex6_Virtio()
{
  // TODO Fill_in: return MemMapFind("virtio");
  return 0;
}
// Ex7: RAM base MEM_RAM.
I64 A07_Ex7_Ram()
{
  // TODO Fill_in: return MemMapFind("ram");
  return 0;
}
// Ex8 Challenge: return 1 iff uart and clint bases differ (they must).
I64 A07_Ex8_Distinct()
{
  // TODO Fill_in:
  //   if (MemMapFind("uart") != MemMapFind("clint")) return 1;
  //   return -1;
  return 0;
}

U0 A07_Check()
{
  Print("-- A07 exercises --\n");
  A07_Expect("Ex1_Uart", A07_Ex1_Uart(), MEM_UART);
  A07_Expect("Ex2_Plic", A07_Ex2_Plic(), MEM_PLIC);
  A07_Expect("Ex3_Fs", A07_Ex3_Fs(), MEM_FS);
  A07_Expect("Ex4_Heap", A07_Ex4_Heap(), MEM_HEAP);
  A07_Expect("Ex5_UartDrvOk", A07_Ex5_UartDrvOk(), 1);
  A07_Expect("Ex6_Virtio", A07_Ex6_Virtio(), MEM_VIRTIO);
  A07_Expect("Ex7_Ram", A07_Ex7_Ram(), MEM_RAM);
  A07_Expect("Ex8_Distinct", A07_Ex8_Distinct(), 1);
}

U0 A07()
{
  Print("=== A07 MemMap & Man ===\n");
  A07_Demo();
  A07_Check();
  Print("Next: Run(\"A08_REPLDrills.hc\");\n");
}
A07;
