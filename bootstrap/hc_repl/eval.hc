// eval.hc -- line dispatch for the AOT HolyC REPL.
// A2: compile/eval statements go through ExePutS (exepubs.hc), not raw JitTry.
// Builtin cmds (Dir/Src/…) + I64 expression Eval fallback for digits/ops.
U8 repl_line[512];
I64 repl_len;
I64 eval_pos;
I64 eval_tok;
// 0=end 1=num 2=op 3=lparen 4=rparen
I64 eval_num;
I64 eval_op;
I64 eval_err;
// Set by ReplEvalOne on compile/eval failure; ReplLoop reseeds g_rl_seed.
I64 g_repl_eval_err;
U0 EvalSkip()
{
  while (repl_line[eval_pos] == ' ' || repl_line[eval_pos] == '\t')
    eval_pos++;
}

U0 EvalLex()
{
  I64 c, v, neg;
  EvalSkip();
  c = repl_line[eval_pos];
  if (!c || c == ';') {
    eval_tok = 0;
    return;
  }
  if (c == '(') {
    eval_pos++;
    eval_tok = 3;
    return;
  }
  if (c == ')') {
    eval_pos++;
    eval_tok = 4;
    return;
  }
  if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%') {
    eval_op = c;
    eval_pos++;
    eval_tok = 2;
    return;
  }
  if (c >= '0' && c <= '9') {
    v = 0;
    while (repl_line[eval_pos] >= '0' && repl_line[eval_pos] <= '9') {
      v = v * 10 + (repl_line[eval_pos] - '0');
      eval_pos++;
    }
    eval_num = v;
    eval_tok = 1;
    return;
  }
  eval_err = 1;
  eval_tok = 0;
}
I64 EvalExpr();
// forward
I64 EvalPrim()
{
  I64 v, op;
  if (eval_tok == 3) {
    EvalLex();
    v = EvalExpr();
    if (eval_tok != 4) {
      eval_err = 1;
      return 0;
    }
    EvalLex();
    return v;
  }
  if (eval_tok == 2 && (eval_op == '+' || eval_op == '-')) {
    op = eval_op;
    EvalLex();
    v = EvalPrim();
    if (op == '-')
      return -v;
    return v;
  }
  if (eval_tok != 1) {
    eval_err = 1;
    return 0;
  }
  v = eval_num;
  EvalLex();
  return v;
}

I64 EvalTerm()
{
  I64 v, r, op;
  v = EvalPrim();
  while (!eval_err && eval_tok == 2 && (eval_op == '*' || eval_op == '/' || eval_op == '%')) {
    op = eval_op;
    EvalLex();
    r = EvalPrim();
    if (op == '*')
      v = v *r;
    else if (op == '/') {
      if (!r) {
        eval_err = 1;
        return 0;
      }
      v = v / r;
    } else {
      if (!r) {
        eval_err = 1;
        return 0;
      }
      v = v % r;
    }
  }
  return v;
}

I64 EvalExpr()
{
  I64 v, r, op;
  v = EvalTerm();
  while (!eval_err && eval_tok == 2 && (eval_op == '+' || eval_op == '-')) {
    op = eval_op;
    EvalLex();
    r = EvalTerm();
    if (op == '+')
      v = v + r;
    else
      v = v - r;
  }
  return v;
}

I64 EvalI64Line(U8 *s)
{
  I64 i = 0, v;
  while (s[i] && i < 511) {
    repl_line[i] = s[i];
    i++;
  }
  repl_line[i] = 0;
  // strip trailing ;
  while (i > 0 && (repl_line[i - 1] == ';' || repl_line[i - 1] == ' ' || repl_line[i - 1] == '\t')) {
    i--;
    repl_line[i] = 0;
  }
  eval_pos = 0;
  eval_err = 0;
  EvalLex();
  if (eval_tok == 0) {
    eval_err = 1;
    return 0;
  }
  v = EvalExpr();
  EvalSkip();
  if (repl_line[eval_pos])
    eval_err = 1;
  if (eval_err)
    return 0;
  return v;
}

I64 IsExprLine(U8 *s)
{
  I64 i = 0, c, seen = 0;
  while (s[i] == ' ' || s[i] == '\t')
    i++;
  if (!(s[i] >= '0' && s[i] <= '9') && s[i] != '(' && s[i] != '+' && s[i] != '-' && s[i] != '*')
    return 0;
  while (s[i]) {
    c = s[i];
    if (c >= '0' && c <= '9') {
      seen = 1;
      i++;
      continue;
    }
    if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '(' || c == ')' || c == ' ' || c == '\t' || c == ';') {
      i++;
      continue;
    }
    return 0;
  }
  return seen;
}

I64 StrEq(U8 *a, U8 *b)
{
  if (!a)
    a = "";
  if (!b)
    b = "";
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}
// Match "Name" or "Name;" or "Name();" (optional spaces).
I64 CmdIs(U8 *line, U8 *name)
{
  I64 i = 0, j = 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  while (name[j] && line[i] == name[j]) {
    i++;
    j++;
  }
  if (name[j])
    return 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] == '(') {
    i++;
    while (line[i] == ' ' || line[i] == '\t')
      i++;
    if (line[i] != ')')
      return 0;
    i++;
  }
  while (line[i] == ' ' || line[i] == '\t' || line[i] == ';' || line[i] == '\r' || line[i] == '\n')
    i++;
  return !line[i];
}
// Extract Src("name") / Cat("name") argument into FsTmp.
I64 CmdStrArg(U8 *line, U8 *verb)
{
  I64 i = 0, j = 0, q;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  while (verb[j] && line[i] == verb[j]) {
    i++;
    j++;
  }
  if (verb[j])
    return 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != '(')
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  q = line[i];
  if (q != '"' && q != '\'')
    return 0;
  i++;
  j = 0;
  while (line[i] && line[i] != q && j < 150) {
    FsTmp[j] = line[i];
    j++;
    i++;
  }
  FsTmp[j] = 0;
  if (line[i] != q)
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != ')')
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t' || line[i] == ';')
    i++;
  return !line[i];
}

I64 CmdParseI64(U8 *line, I64 *io, I64 *out)
{
  I64 i, v, neg, d;
  i = *io;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  v = 0;
  neg = 0;
  if (line[i] == '-') {
    neg = 1;
    i++;
  }
  if (line[i] == '0' && (line[i + 1] == 'x' || line[i + 1] == 'X')) {
    i = i + 2;
    while (1) {
      d = -1;
      if (line[i] >= '0' && line[i] <= '9')
        d = line[i] - '0';
      else if (line[i] >= 'a' && line[i] <= 'f')
        d = line[i] - 'a' + 10;
      else if (line[i] >= 'A' && line[i] <= 'F')
        d = line[i] - 'A' + 10;
      if (d < 0)
        break;
      v = v * 16 + d;
      i++;
    }
  } else if (line[i] >= '0' && line[i] <= '9') {
    while (line[i] >= '0' && line[i] <= '9') {
      v = v * 10 + (line[i] - '0');
      i++;
    }
  } else
    return 0;
  if (neg)
    v = -v;
  *out = v;
  *io = i;
  return 1;
}
// DumpMem(addr,n) or DumpMem(addr,n,"label") — AOT call, not JIT (lui sign-extend).
I64 CmdDumpMem(U8 *line)
{
  I64 i, j, addr, n, q;
  U8 lab[64];
  i = 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != 'D' || line[i + 1] != 'u' || line[i + 2] != 'm' || line[i + 3] != 'p' || line[i + 4] != 'M' || line[i + 5] != 'e' || line[i + 6] != 'm')
    return 0;
  i = i + 7;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != '(')
    return 0;
  i++;
  if (!CmdParseI64(line, &i, &addr))
    return 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != ',')
    return 0;
  i++;
  if (!CmdParseI64(line, &i, &n))
    return 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  lab[0] = 'm';
  lab[1] = 'e';
  lab[2] = 'm';
  lab[3] = 0;
  if (line[i] == ',') {
    i++;
    while (line[i] == ' ' || line[i] == '\t')
      i++;
    q = line[i];
    if (q != '"' && q != '\'')
      return 0;
    i++;
    j = 0;
    while (line[i] && line[i] != q && j < 63) {
      lab[j] = line[i];
      j++;
      i++;
    }
    lab[j] = 0;
    if (line[i] != q)
      return 0;
    i++;
  }
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != ')')
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t' || line[i] == ';')
    i++;
  if (line[i])
    return 0;
  DumpMem(addr, n, lab);
  return 1;
}

U0 Help()
{
  UartStr("TempleOS RISC-V — HolyC AOT REPL (repl-holyc.elf)\n");
  UartStr("  Eval     >  ExePutS compile loop; I64 expr / fun defs; Print;\n");
  UartStr("  Files    Dir; Cd(\"Lib\"); Cat(\"print.hc\"); Src(\"hello.hc\");\n");
  UartStr("  Editors  Vi / Ed / EditHoly; Src opens preferred editor (:q / q)\n");
  UartStr("  Man      Man(\"Print\"); Man(\"ABI\"); Man(\"Regs\"); Sections;\n");
  UartStr("  Funs     FunsList;  Funs(\"Print\");  FunsSec(3);\n");
  UartStr("  Dig-down MemMap; Regs; Reg(\"mstatus\"); CsrExplain(\"mcause\"); DbgHelp;\n");
  UartStr("  Crash    Fault → crash> md/mw/regs/bt/go; CrashHelp; Man(\"CrashMon\");\n");
  UartStr("  Sys      Sys; Uptime; MemRep; IrqRep; DevRep; Cnts;\n");
  UartStr("  Term     TermSize(80,24); TermRep; TermQuery; TermHelp;\n");
  UartStr("  Tty      Tty; TtyCanon; TtyRaw; TtyEcho(1); TtyHelp;\n");
  UartStr("  VT       Vt(1); VtDetach; VtCapture(1); VtKeys(1); VtPane(0,1); VtList; VtHelp;\n");
  UartStr("  Log      LogInfo(\"boot\",\"msg\"); DMesg; LogClear;\n");
  UartStr("  Tab      mid-token=sym/MEM_*/path/asm{}; else 2sp; multiline ...\n");
  UartStr("  Keys     Up/Down=history  Left/Right/Home/End  Tab  ^U/^W  BS  empty ^D=eof\n");
  UartStr("  Edit     syntax/eval error re-shows line for mid-line fix (arrows/Home/End)\n");
  UartStr("  Export   DumpFile; DumpChanges; FsChanges; FsReplay; Recover;\n");
  UartStr("  Help     help;  Help;\n");
  UartStr("  A2       ExePutS→Jit here; guest Cmp=make repl-cmp\n");
  UartStr("  Trap     TrapInit; Fault; Break;  Ctrl-C during eval\n");
  UartStr("  Note     ZMODEM waived on thin image; DumpFile / 9P; FunPick partial\n");
  UartStr("  Soft     SafeMode; Recover; Reset; Halt;\n");
  UartStr("  QEMU     Quit; Exit; Fail; HardReset;  // SiFive test @ MEM_TEST\n");
}
U8 eval_stmt[512];
U8 eval_asm_tok[32];
U8 eval_asm_op1[32];
U8 eval_asm_op2[32];
U8 eval_asm_op3[32];
I64 eval_asm_err;
U8 *eval_asm_p;
// Top-level ; outside strings/{}/() — compound REPL line.
I64 EvalHasTopSemi(U8 *line)
{
  I64 depth, paren, in_str, q;
  U8 *p;
  if (!line)
    return 0;
  p = line;
  depth = 0;
  paren = 0;
  in_str = 0;
  q = 0;
  while (*p) {
    if (in_str) {
      if (*p == '\\' && p[1]) {
        p = p + 2;
        continue;
      }
      if (*p == q)
        in_str = 0;
      p++;
      continue;
    }
    if (*p == '"' || *p == '\'') {
      in_str = 1;
      q = *p;
      p++;
      continue;
    }
    if (*p == '{')
      depth++;
    if (*p == '}') {
      if (depth > 0)
        depth--;
    }
    if (*p == '(')
      paren++;
    if (*p == ')' && paren > 0)
      paren--;
    if (*p == ';' && depth == 0 && paren == 0)
      return 1;
    p++;
  }
  return 0;
}
// Copy one ;-delimited unit (respect {}/strings) into eval_stmt; advance *io.
I64 EvalTakeStmt(U8 *line, I64 *io)
{
  I64 i, depth, paren, in_str, q, start;
  U8 *p, *end;
  if (!line || !io)
    return 0;
  p = line + *io;
  while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n' || *p == ';')
    p++;
  if (!*p) {
    *io = p - line;
    return 0;
  }
  start = p - line;
  depth = 0;
  paren = 0;
  in_str = 0;
  q = 0;
  end = p;
  while (*p) {
    if (in_str) {
      if (*p == '\\' && p[1]) {
        p = p + 2;
        end = p;
        continue;
      }
      if (*p == q)
        in_str = 0;
      p++;
      end = p;
      continue;
    }
    if (*p == '"' || *p == '\'') {
      in_str = 1;
      q = *p;
      p++;
      end = p;
      continue;
    }
    if (*p == '{')
      depth++;
    if (*p == '}') {
      if (depth > 0)
        depth--;
    }
    if (*p == '(')
      paren++;
    if (*p == ')' && paren > 0)
      paren--;
    if (*p == ';' && depth == 0 && paren == 0) {
      end = p;
      p++;
      break;
    }
    if (*p == '}' && depth == 0) {
      end = p + 1;
      p++;
      break;
    }
    p++;
    end = p;
  }
  i = 0;
  while (start + i < end - line && i < 511) {
    eval_stmt[i] = line[start + i];
    i++;
  }
  eval_stmt[i] = 0;
  *io = p - line;
  return i > 0;
}

U0 EvalAsmSkip()
{
  while (*eval_asm_p == ' ' || *eval_asm_p == '\t' || *eval_asm_p == '\r' || *eval_asm_p == '\n' || *eval_asm_p == ',')
    eval_asm_p++;
}

I64 EvalAsmIdent(U8 *out, I64 max)
{
  I64 n = 0;
  I64 c;
  EvalAsmSkip();
  while (*eval_asm_p && n < max - 1) {
    c = *eval_asm_p;
    if (c >= 'a' && c <= 'z')
      ;
    else if (c >= 'A' && c <= 'Z')
      ;
    else if (c >= '0' && c <= '9')
      ;
    else if (c == '_')
      ;
    else
      break;
    out[n] = c;
    n++;
    eval_asm_p++;
  }
  out[n] = 0;
  return n > 0;
}

I64 EvalAsmNum(I64 *out)
{
  I64 v, neg, d, base;
  neg = 0;
  EvalAsmSkip();
  if (*eval_asm_p == '-') {
    neg = 1;
    eval_asm_p++;
  }
  base = 10;
  v = 0;
  if (*eval_asm_p == '0' && (eval_asm_p[1] == 'x' || eval_asm_p[1] == 'X')) {
    base = 16;
    eval_asm_p = eval_asm_p + 2;
    while (1) {
      d = -1;
      if (*eval_asm_p >= '0' && *eval_asm_p <= '9')
        d = *eval_asm_p - '0';
      else if (*eval_asm_p >= 'a' && *eval_asm_p <= 'f')
        d = *eval_asm_p - 'a' + 10;
      else if (*eval_asm_p >= 'A' && *eval_asm_p <= 'F')
        d = *eval_asm_p - 'A' + 10;
      if (d < 0)
        break;
      v = v *base + d;
      eval_asm_p++;
    }
  } else if (*eval_asm_p >= '0' && *eval_asm_p <= '9') {
    while (*eval_asm_p >= '0' && *eval_asm_p <= '9') {
      v = v * 10 + (*eval_asm_p - '0');
      eval_asm_p++;
    }
  } else
    return 0;
  if (neg)
    v = -v;
  *out = v;
  return 1;
}

I64 EvalAsmReg()
{
  if (!EvalAsmIdent(eval_asm_op1, 32))
    return -1;
  return RegGprIndex(eval_asm_op1);
}

I64 EvalAsmInsn()
{
  I64 rd, rs1, rs2, imm;
  if (!EvalAsmIdent(eval_asm_tok, 32))
    return 0;
  if (eval_asm_tok[0] == '#' || (eval_asm_tok[0] == '/' && eval_asm_p[0] == '/'))
    return 1;
  if (!StrICmp(eval_asm_tok, "li")) {
    rd = EvalAsmReg();
    if (rd < 0 || !EvalAsmNum(&imm))
      return -1;
    JitLi(rd, imm);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "addi")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    if (rd < 0 || rs1 < 0 || !EvalAsmNum(&imm))
      return -1;
    JitI(0, rd, rs1, imm);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "mv")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    if (rd < 0 || rs1 < 0)
      return -1;
    JitI(0, rd, rs1, 0);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "nop")) {
    JitI(0, 0, 0, 0);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "lui")) {
    rd = EvalAsmReg();
    if (rd < 0 || !EvalAsmNum(&imm))
      return -1;
    JitLui(rd, (imm >> 12) & 0xFFFFF);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "add")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    rs2 = EvalAsmReg();
    if (rd < 0 || rs1 < 0 || rs2 < 0)
      return -1;
    JitR(0, 0, rd, rs1, rs2);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "sub")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    rs2 = EvalAsmReg();
    if (rd < 0 || rs1 < 0 || rs2 < 0)
      return -1;
    JitR(0x20, 0, rd, rs1, rs2);
    return 1;
  }
  // Shift-immediate: RV64 funct6=0/0x10 with a 6-bit shamt in imm[5:0].
  if (!StrICmp(eval_asm_tok, "slli")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    if (rd < 0 || rs1 < 0 || !EvalAsmNum(&imm))
      return -1;
    JitI(1, rd, rs1, imm & 63);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "srli")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    if (rd < 0 || rs1 < 0 || !EvalAsmNum(&imm))
      return -1;
    JitI(5, rd, rs1, imm & 63);
    return 1;
  }
  if (!StrICmp(eval_asm_tok, "srai")) {
    rd = EvalAsmReg();
    rs1 = EvalAsmReg();
    if (rd < 0 || rs1 < 0 || !EvalAsmNum(&imm))
      return -1;
    JitI(5, rd, rs1, (imm & 63) | 0x400);
    return 1;
  }
  eval_asm_err = 1;
  return -1;
}
// Encode body[0..end) at jit_at. Unknown mnemonic / bad operand / stray token = -1
// (a non-advancing token would otherwise spin the caller's walk forever).
I64 EvalAsmBody(U8 *body, U8 *end)
{
  I64 rc;
  eval_asm_p = body;
  eval_asm_err = 0;
  while (eval_asm_p < end) {
    rc = EvalAsmInsn();
    if (rc <= 0)
      return -1;
    while (*eval_asm_p == ';' || *eval_asm_p == ' ' || *eval_asm_p == '\t' || *eval_asm_p == '\r' || *eval_asm_p == '\n')
      eval_asm_p++;
  }
  return 1;
}
// REPL asm { … } — thin encode via jit_at (no host Cmp). Minimal mnemonics only.
I64 EvalAsmRun(U8 *line)
{
  U8 *p, *body, *tramp;
  I64 i;
  if (!line)
    return 0;
  i = 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if ((line[i] != 'a' && line[i] != 'A') || (line[i + 1] != 's' && line[i + 1] != 'S') || (line[i + 2] != 'm' && line[i + 2] != 'M'))
    return 0;
  i = i + 3;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != '{')
    return 0;
  p = line + i + 1;
  body = p;
  while (*p && *p != '}')
    p++;
  if (*p != '}')
    return 0;
  tramp = jit_at;
  if (EvalAsmBody(body, p) < 0) {
    UartStr("Eval: asm error\n");
    return -1;
  }
  JitJalr(0, 1, 0);
  JitFenceI;
  JitCallEntry(tramp);
  // Snap now — Reg("a0") must not re-snap after HolyC arg clobber.
  RegsSnapOnly();
  g_reg_snap_fresh = 1;
  return 1;
}
// I64 Name() { asm { … } } — leaf fun whose whole body is one unlabeled asm block.
// jit.hc has no asm parser and must not grow, so encode it here and register the
// entry in jit_funs so later Name(); calls resolve like any other JIT fun.
I64 EvalAsmFunDef(U8 *line)
{
  U8 *body, *end, *entry;
  U8 name[JIT_NAME_MAX];
  I64 i, j, is_void;
  if (!line)
    return 0;
  i = 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  is_void = -1;
  if (line[i] == 'U' && line[i + 1] == '0')
    is_void = 1;
  else if (line[i] == 'U' && line[i + 1] == '8')
    is_void = 0;
  else if (line[i] == 'I' && line[i + 1] == '3' && line[i + 2] == '2')
    is_void = 0;
  else if (line[i] == 'I' && line[i + 1] == '6' && line[i + 2] == '4')
    is_void = 0;
  if (is_void < 0)
    return 0;
  i = i + 2;
  if (line[i] == '2' || line[i] == '4')
    i++;
  if (line[i] != ' ' && line[i] != '\t')
    return 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  j = 0;
  while (j < JIT_NAME_MAX - 1 && ((line[i] >= 'a' && line[i] <= 'z') || (line[i] >= 'A' && line[i] <= 'Z') || (line[i] >= '0' && line[i] <= '9') || line[i] == '_')) {
    name[j] = line[i];
    j++;
    i++;
  }
  name[j] = 0;
  if (!j)
    return 0;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  if (line[i] != '(')
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t')
    i++;
  // Args would need slot binding — leave those to jit.hc's JitParseFun.
  if (line[i] != ')')
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t' || line[i] == '\r' || line[i] == '\n')
    i++;
  if (line[i] != '{')
    return 0;
  i++;
  while (line[i] == ' ' || line[i] == '\t' || line[i] == '\r' || line[i] == '\n')
    i++;
  if ((line[i] != 'a' && line[i] != 'A') || (line[i + 1] != 's' && line[i + 1] != 'S') || (line[i + 2] != 'm' && line[i + 2] != 'M'))
    return 0;
  i = i + 3;
  while (line[i] == ' ' || line[i] == '\t' || line[i] == '\r' || line[i] == '\n')
    i++;
  if (line[i] != '{')
    return 0;
  body = line + i + 1;
  end = body;
  while (*end && *end != '}')
    end++;
  if (*end != '}')
    return 0;
  // The asm block must be the whole body: only the closing fun brace may follow.
  i = 1;
  while (end[i] == ' ' || end[i] == '\t' || end[i] == '\r' || end[i] == '\n')
    i++;
  if (end[i] != '}')
    return 0;
  i++;
  while (end[i] == ' ' || end[i] == '\t' || end[i] == '\r' || end[i] == '\n' || end[i] == ';')
    i++;
  if (end[i])
    return 0;
  // Leaf: no prologue, so the block owns a0 and sp/ra stay the caller's (same
  // contract as a bare asm{} line). ret lets JitGenCall treat it as a normal fun.
  entry = jit_at;
  jit_err = 0;
  if (EvalAsmBody(body, end) < 0) {
    UartStr("Eval: asm error\n");
    return -1;
  }
  JitJalr(0, 1, 0);
  JitFenceI;
  if (jit_err || JitAdd(name, entry, 0, is_void) < 0) {
    UartStr("Eval: asm fun table full\n");
    return -1;
  }
  return 1;
}

U0 ReplEvalOne(U8 *line)
{
  I64 v, jr, arc;
  if (!line)
    return;
  while (*line == ' ' || *line == '\t')
    line++;
  if (!*line)
    return;
  // Session #define → Tab registry (thin path; no host define_table / expansion).
  if (DefTryRegister(line))
    return;
  arc = EvalAsmRun(line);
  if (arc < 0) {
    g_repl_eval_err = 1;
    return;
  }
  if (arc > 0)
    return;
  arc = EvalAsmFunDef(line);
  if (arc < 0) {
    g_repl_eval_err = 1;
    return;
  }
  if (arc > 0)
    return;
  if (CmdStrArg(line, "Ed")) {
    Ed(FsTmp);
    return;
  }
  if (CmdStrArg(line, "Run")) {
    Run(FsTmp);
    return;
  }
  if (CmdStrArg(line, "Vi")) {
    Vi(FsTmp);
    return;
  }
  if (CmdIs(line, "help") || CmdIs(line, "Help")) {
    Help();
    return;
  }
  if (CmdIs(line, "Sections")) {
    Sections();
    return;
  }
  if (CmdIs(line, "FunsList")) {
    FunsList();
    return;
  }
  if (CmdIs(line, "Regs") || CmdIs(line, "Dr")) {
    Regs();
    return;
  }
  if (CmdIs(line, "MemMap")) {
    MemMap();
    return;
  }
  if (CmdIs(line, "MemMapDrv")) {
    MemMapDrv();
    return;
  }
  if (CmdIs(line, "Bt") || CmdIs(line, "StkRep")) {
    StkRep();
    return;
  }
  if (CmdIs(line, "DbgHelp")) {
    DbgHelp();
    return;
  }
  if (CmdIs(line, "CrashHelp")) {
    CrashHelp();
    return;
  }
  if (CmdIs(line, "CrashDump")) {
    CrashDump();
    return;
  }
  if (CmdIs(line, "CrashMon")) {
    CrashMon();
    return;
  }
  if (CmdIs(line, "RegHelp")) {
    RegHelp();
    return;
  }
  if (CmdStrArg(line, "Reg")) {
    I64 v;
    v = Reg(FsTmp);
    Print("ans=%p=%d\n", v, v);
    return;
  }
  if (CmdIs(line, "RegsRestoreDemo")) {
    RegsRestoreDemo();
    return;
  }
  if (CmdIs(line, "Dir") || CmdIs(line, "Ls")) {
    Dir();
    return;
  }
  if (CmdIs(line, "Pwd")) {
    Pwd();
    return;
  }
  if (CmdStrArg(line, "Src")) {
    Src(FsTmp);
    return;
  }
  if (CmdStrArg(line, "Cat")) {
    Cat(FsTmp);
    return;
  }
  if (CmdStrArg(line, "DumpFile")) {
    DumpFile(FsTmp);
    return;
  }
  if (CmdIs(line, "DumpChanges")) {
    DumpChanges();
    return;
  }
  if (CmdIs(line, "FsChanges")) {
    FsChanges();
    return;
  }
  if (CmdIs(line, "FsLog")) {
    FsLog();
    return;
  }
  if (CmdIs(line, "FsEpoch")) {
    Print("epoch=%d\n", FsEpoch());
    return;
  }
  if (CmdIs(line, "FsDiff")) {
    FsDiff();
    return;
  }
  if (CmdIs(line, "FsReplay")) {
    Print("replay=%d\n", FsReplay());
    return;
  }
  if (CmdIs(line, "FsRecover") || CmdIs(line, "Recover")) {
    Print("recover=%d\n", FsRecover());
    return;
  }
  if (CmdIs(line, "DMesg")) {
    DMesg();
    return;
  }
  if (CmdIs(line, "Sys")) {
    Sys();
    return;
  }
  if (CmdIs(line, "SysHelp")) {
    SysHelp();
    return;
  }
  if (CmdIs(line, "Tty")) {
    Tty();
    return;
  }
  if (CmdIs(line, "TtyHelp")) {
    TtyHelp();
    return;
  }
  if (CmdIs(line, "TtyCanon")) {
    TtyCanon();
    return;
  }
  if (CmdIs(line, "TtyRaw")) {
    TtyRaw();
    return;
  }
  if (CmdIs(line, "TtyInit")) {
    TtyInit();
    return;
  }
  if (CmdIs(line, "TtyEofClear")) {
    TtyEofClear();
    return;
  }
  if (CmdIs(line, "TermRep")) {
    TermRep();
    return;
  }
  if (CmdIs(line, "TermHelp")) {
    TermHelp();
    return;
  }
  if (CmdIs(line, "Uptime")) {
    Uptime();
    return;
  }
  if (CmdIs(line, "MemRep")) {
    MemRep();
    return;
  }
  if (CmdIs(line, "IrqRep")) {
    IrqRep();
    return;
  }
  if (CmdIs(line, "DevRep")) {
    DevRep();
    return;
  }
  if (CmdIs(line, "Cnts")) {
    Cnts();
    return;
  }
  if (CmdIs(line, "LogClear")) {
    LogClear();
    return;
  }
  if (CmdIs(line, "LogInit")) {
    LogInit();
    return;
  }
  if (CmdIs(line, "LogCount")) {
    Print("log_count=%d\n", LogCount());
    return;
  }
  if (CmdDumpMem(line))
    return;
  if (CmdStrArg(line, "Cd")) {
    Cd(FsTmp);
    return;
  }
  if (CmdStrArg(line, "MkDir") || CmdStrArg(line, "DirMk")) {
    MkDir(FsTmp);
    return;
  }
  // A2: TempleOS-shaped compile entry (ExePutS), not direct JitTry.
  jr = ExePutS(line, NULL);
  if (jr < 0) {
    g_repl_eval_err = 1;
    return;
  }
  if (jr > 0)
    return;
  if (IsExprLine(line)) {
    v = EvalI64Line(line);
    if (eval_err) {
      "Eval: bad expression\n";
      g_repl_eval_err = 1;
      return;
    }
    Print("ans=%p=%d\n", v, v);
    return;
  }
  UartStr("Eval: not recognized. try help;\n");
}

U0 ReplEvalLine(U8 *line)
{
  I64 pos = 0, n = 0;
  g_repl_eval_err = 0;
  if (!line)
    return;
  // Fast path: one statement (usual REPL line) — avoid split buffer.
  if (!EvalHasTopSemi(line)) {
    ReplEvalOne(line);
    return;
  }
  while (EvalTakeStmt(line, &pos)) {
    n++;
    if (n > 1)
      break;
  }
  if (n <= 1) {
    ReplEvalOne(line);
    return;
  }
  pos = 0;
  while (EvalTakeStmt(line, &pos)) {
    ReplEvalOne(eval_stmt);
    if (g_repl_eval_err)
      return;
  }
}
