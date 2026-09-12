// HolyC sub_switch (`start:` / `end:` inside a switch body).
// Two regressions, both of which made `break` inside a sub_switch run the wrong code:
//   1. `end:` fell through into the body of whatever case followed it, so a break out of the
//      sub_switch silently executed the next case.
//   2. `start:` blocks NEST (PrsStmt has `start: case KW_ASM: … start: case KW_LOCK:`) but the
//      parser tracked only one open group, so the outer block's sub_end label was never
//      defined and its breaks jumped to an unresolved label.
// The second one is why `asm{}` in the REPL died *after* its arm had completed.
I64 Pick(I64 x)
{
  I64 r = 0;
  switch (x) {
    case 0:
      r = 10;
      break;
    start:
      r += 1;          // sub_switch entry code: runs before any case in the group
    case 2:
      r += 20;
      break;
    case 3:
      r += 30;
      break;
    end:
    case 4:
      r = 40;
      break;
  }
  return r;
}

I64 Nest(I64 x)
{
  I64 r = 0;
  switch (x) {
    start:
      r += 1;
    case 1:
      r += 100;
      break;
    start:
      r += 2;
    case 5:
      r += 500;
      break;
    end:
    end:
    case 9:
      r = 900;
      break;
  }
  return r;
}

I64 main()
{
  I64 r = 0;
  r += (Pick(0) == 10) * 1;
  r += (Pick(2) == 21) * 2;     // entry code + case 2, break must leave the switch
  r += (Pick(3) == 31) * 4;
  r += (Pick(4) == 40) * 8;     // case after end: still reachable on its own
  r += (Nest(1) == 101) * 16;   // outer start: group
  r += (Nest(5) == 502) * 32;   // inner start: group (nesting)
  r += (Nest(9) == 900) * 64;
  return r;
  // 0x7F
}
