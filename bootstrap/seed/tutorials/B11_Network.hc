// B11_Network.hc -- CSAPP 3e Ch.11: Network Programming
// GAP: Berkeley sockets / Tiny web server are not in the UART REPL.
// Board hook: VirtioNet (Kernel/Drv/VirtioNet.HC) + MEM_VIRTIO MMIO window.
//
// HOW TO WORK THIS LAB
//   Run("B11_Network.hc");  MemMap;  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Client/server, sockets, HTTP. Remap: discover virtio MMIO, understand
//   device negotiation conceptually, run host smokes when available
//   (tests/scripts/run_kernel_virtio_net_smoke.sh). Still learn packet I/O
//   as "another MEM_* driver", not POSIX.
//
// NEXT
//   B12_Concurrent -- timer + early SMP.
U0 B11_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B11_Demo()
{
  Print("B11 GAP: no sockets / Tiny server in UART REPL.\n");
  Print("Hook: VirtioNet + MEM_VIRTIO=%X\n", MEM_VIRTIO);
  Print("Virtio magic @ base often 'virt' = 0x74726976 (LE)\n");
  Print("Peek interactively if mapped: Print(\"%%X\\n\", *(U32 *)MEM_VIRTIO);\n");
  Print("Host smoke: make kernel-virtio-net-smoke (when Kernel built).\n");
  B11_Expect("B11_virtio_sym", MemMapFind("virtio"), MEM_VIRTIO);
}
// Ex1 Warmup: virtio base.
I64 B11_Ex1_Virtio()
{
  // TODO Fill_in: return MemMapFind("virtio");
  return 0;
}
// Ex2: expected magic constant 0x74726976 ('virt' LE).
I64 B11_Ex2_MagicConst()
{
  // TODO Fill_in: return 0x74726976;
  return 0;
}
// Ex3: affirm socket gap.
I64 B11_Ex3_NoSockets()
{
  // TODO Fill_in: return 1;  // true: no BSD sockets in REPL
  return -1;
}
// Ex4: network is still MMIO-driven here -- uart and virtio both < MEM_RAM?
I64 B11_Ex4_BothMmio()
{
  // TODO Fill_in:
  //   if (MEM_UART < MEM_RAM && MEM_VIRTIO < MEM_RAM) return 1;
  //   return 0;
  return 0;
}
// Ex5: StrLen("virtio").
I64 B11_Ex5_NameLen()
{
  // TODO Fill_in: return StrLen("virtio");
  return 0;
}
// Ex6: Ethernet-ish MTU common default 1500 -- return 1500 for concept.
I64 B11_Ex6_Mtu()
{
  // TODO Fill_in: return 1500;
  return 0;
}
// Ex7 Challenge: IPv4 addr packing 10.0.0.1 -> 0x0A000001.
I64 B11_Ex7_PackIp()
{
  // TODO Fill_in: return (10 << 24) | (0 << 16) | (0 << 8) | 1;
  return 0;
}
// Ex8 Challenge: checksum toy -- sum bytes of "OK" = 'O'+'K'.
I64 B11_Ex8_ToySum()
{
  // TODO Fill_in: return 'O' + 'K';
  return 0;
}

U0 B11_Check()
{
  Print("-- B11 exercises --\n");
  B11_Expect("Ex1_Virtio", B11_Ex1_Virtio(), MEM_VIRTIO);
  B11_Expect("Ex2_MagicConst", B11_Ex2_MagicConst(), 0x74726976);
  B11_Expect("Ex3_NoSockets", B11_Ex3_NoSockets(), 1);
  B11_Expect("Ex4_BothMmio", B11_Ex4_BothMmio(), 1);
  B11_Expect("Ex5_NameLen", B11_Ex5_NameLen(), 6);
  B11_Expect("Ex6_Mtu", B11_Ex6_Mtu(), 1500);
  B11_Expect("Ex7_PackIp", B11_Ex7_PackIp(), 0x0A000001);
  B11_Expect("Ex8_ToySum", B11_Ex8_ToySum(), 'O' + 'K');
}

U0 B11()
{
  Print("=== B11 CSAPP Ch.11 Network programming ===\n");
  B11_Demo();
  B11_Check();
  Print("Next: Run(\"B12_Concurrent.hc\");\n");
}
B11;
