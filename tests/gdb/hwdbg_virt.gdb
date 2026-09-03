# tests/gdb/hwdbg_virt.gdb — QEMU virt gdbstub smoke (make hwdbg-smoke)
# Expect: attach, break at _start, stepi, Sdtrig CSRs readable, software+hw break.
set architecture riscv:rv64
set pagination off
set confirm off
set remotetimeout 10

target remote localhost:3333

break *_start
continue

printf "hwdbg: at _start pc=0x%lx\n", $pc
printf "hwdbg: tselect=0x%lx tdata1=0x%lx tinfo=0x%lx\n", $tselect, $tdata1, $tinfo

# Soft single-step via gdbstub (not guest dcsr.step)
stepi
printf "hwdbg: after stepi pc=0x%lx\n", $pc

# Confirm trigger CSR WARL accepts mcontrol store|M (before any long continue)
set $tselect = 0
set $tdata1 = 0
set $tdata2 = 0x80100000
set $tdata1 = 0x2000000000000042
printf "hwdbg: armed mcontrol tdata1=0x%lx tdata2=0x%lx\n", $tdata1, $tdata2

# Software breakpoint at next sequential insn — reliable on virt gdbstub
set $sb = $pc + 4
break *$sb
printf "hwdbg: break @ 0x%lx\n", $sb
continue
printf "hwdbg: hit break pc=0x%lx\n", $pc

# Hardware breakpoint (gdb may map to trigger); one insn ahead again
delete breakpoints
set $hb = $pc + 4
hbreak *$hb
printf "hwdbg: hbreak @ 0x%lx\n", $hb
continue
printf "hwdbg: hit hbreak pc=0x%lx\n", $pc

quit
