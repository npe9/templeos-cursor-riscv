// Demo: C-style for (...;...;...) — supported by TempleOS HolyC and holyc-riscv.
// Sum 0..4 → 10; empty-init for (;…;…) and ++ in the incr clause.
U0 ForLoopDemo()
{
  I64 i,s=0;
  for (i=0;i<5;i++)
    s=s+i;
  "for sum 0..4 = %d (expect 10)\n",s;

  s=0;
  i=0;
  for (;i<4;i=i+1)
    s=s+i;
  "for (;i<4;i++) sum = %d (expect 6)\n",s;
}

ForLoopDemo;
