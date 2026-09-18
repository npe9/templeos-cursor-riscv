// RVAsmReplUi.HC — AsmRepl: type instructions, watch the machine.
//
// AsmStep already runs one instruction against the debugger's register file and prints what
// moved. This is the loop around it: its own prompt with history and Tab completion, the
// register pane above, and memory beside it, both repainted after every step. The panes are
// documents rendered by Kernel/RVDocText.HC, so a step costs a few dozen bytes on the wire.
//
// Commands (anything else is assembled and stepped):
//   q            leave
//   d <addr>     point the memory pane somewhere (default: sp)
//   r            repaint
//   ?            the key list
//
// Include after RVDocVT.HC, RVDocText.HC, RVRegPane.HC, RVDbgView.HC and RVLineEd.HC.
#ifndef RV_ASM_REPL_UI_HC
#define RV_ASM_REPL_UI_HC
#help_index "Dbg"

#define ASMUI_CTX 0x87000400
// the register file: x0..x31, shared with the debugger and the _Xn labels

I64 asmui_mem_addr, asmui_running, asmui_step_fn;

// AsmReplInstallStep -- AsmReplInstallStep(&AsmStep)
// NAME
//   AsmReplInstallStep - give the loop its stepper
// DESCRIPTION
//   AsmStep lives in the compiler image (Compiler/RVAsmRepl.HC) and this loop lives in the
//   kernel image, which is linked first — so the call goes through a pointer, the same way the
//   register pane is handed to AsmStep. Without one, AsmRepl says so instead of stepping.
// SEE ALSO
//   AsmRepl  AsmStep
public U0 AsmReplInstallStep(I64 fn)
{
  asmui_step_fn = fn;
}

// Words Tab completes: registers first, then the mnemonics you actually type at a stepper.
U8 *AsmUiWords()
{
  return "zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 "
         "s11 t3 t4 t5 t6 addi add sub and or xor andi ori xori sll srl sra slli srli srai "
         "slt sltu slti sltiu lui auipc li mv nop ret jal jalr beq bne blt bge bltu bgeu "
         "lb lh lw ld lbu lhu lwu sb sh sw sd mul mulh div divu rem remu ecall ebreak";
}

// One completion, and only when it is unambiguous: a stepper that guesses wrong wastes a step.
I64 AsmUiComplete(U8 *word, U8 *out, I64 max)
{
  U8 *p, cand[32];
  I64 i, n, hits = 0;
  if (!word || !*word)
    return FALSE;
  n = StrLen(word);
  p = AsmUiWords();
  while (*p) {
    i = 0;
    while (*p && *p != ' ' && i < 30)
      cand[i++] = *p++;
    cand[i] = 0;
    while (*p == ' ')
      p++;
    if (i >= n && !MemCmp(cand, word, n)) {
      hits++;
      if (hits == 1 && i < max - 1)
        StrCpy(out, cand);
    }
  }
  return hits == 1;
}

U0 AsmUiPanes()
{
  I64 addr;
  RegPaneUpdate;
  addr = asmui_mem_addr;
  if (!addr)
    addr = *(I64 *)(ASMUI_CTX + 2 * 8);
  // sp by default — the stack is what you want beside a stepper. But this context's sp is only
  // set once something writes it, and a pane that shows nothing teaches nothing, so fall back
  // to the register file itself: `d <addr>` is then an obvious next move.
  if (!addr)
    addr = ASMUI_CTX;
  DbgDm(addr, 64);
}

// AsmRepl -- AsmRepl()
// NAME
//   AsmRepl - an assembler REPL with the registers and memory on screen
// SYNOPSIS
//   AsmRepl;
// DESCRIPTION
//   Each line is assembled and run against the debugger's register file (AsmStep), then the
//   register pane and the memory pane are repainted — so you watch the machine change rather
//   than reading a dump after the fact. History and Tab completion come from RVLineEd; the
//   registers are the same ones _A0 and Dr see, so you can leave the loop, poke a register
//   through a label, and come back.
// EXAMPLES
//   AsmRepl;
//     asm> li a0, 0x40
//     asm> add a1, a0, a0
//     asm> d 0x87000400      // point the memory pane at the register file itself
//     asm> q
// SEE ALSO
//   AsmStep  AsmRegs  Dr  Dbg  RVLineEd
public U0 AsmRepl()
{
  U8 line[192];
  I64 n, prev_fn;
  asmui_running = 1;
  prev_fn = rv_led_complete_fn;
  RVLineEdComplete(&AsmUiComplete);
  Cls;
  AsmUiPanes;
  "asm REPL: instructions are stepped; q leaves, d <addr> moves the memory pane, ? for keys\n";
  while (asmui_running) {
    n = RVLineEd(line, 192, "asm> ");
    if (n < 0)
      break;
    // Ctrl-C
    if (!n)
      continue;
    if (line[0] == 'q' && !line[1])
      break;
    if (line[0] == '?' && !line[1]) {
      "  q  leave    d <addr>  memory pane    r  repaint    anything else is stepped\n";
      continue;
    }
    if (line[0] == 'r' && !line[1]) {
      Cls;
      AsmUiPanes;
      continue;
    }
    if (line[0] == 'd' && line[1] == ' ') {
      asmui_mem_addr = Str2I64(line + 2);
      AsmUiPanes;
      continue;
    }
    if (asmui_step_fn) {
      I64 (*step)(U8 *t);
      step = asmui_step_fn;
      step(line);
    } else {
      "asm REPL: no stepper installed (AsmReplInstallStep)\n";
    }
    AsmUiPanes;
  }
  asmui_running = 0;
  RVLineEdComplete(prev_fn);
  Cls;
  "asm REPL: out\n";
}

#endif
