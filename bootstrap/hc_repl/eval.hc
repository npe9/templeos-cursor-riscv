// eval.hc -- line dispatch for the AOT HolyC REPL.
// Full TempleOS-style JIT Eval needs a guest compiler (not in this image).
// Here: builtin cmds (Dir/Src/…) + I64 expression Eval for digits/ops.
U8 repl_line[512];
I64 repl_len;
I64 eval_pos;
I64 eval_tok;
// 0=end 1=num 2=op 3=lparen 4=rparen
I64 eval_num;
I64 eval_op;
I64 eval_err;
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
  if (!(s[i] >= '0' && s[i] <= '9') && s[i] != '(' && s[i] != '+' && s[i] != '-')
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
  while (line[i] == ' ' || line[i] == '\t' || line[i] == ';')
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

U0 Help()
{
  UartStr("TempleOS RISC-V — HolyC AOT REPL (Mac-built; no C guest runtime)\n");
  UartStr("  Eval     >  I64 expr / fun defs; Print / \"fmt\", args;\n");
  UartStr("  Files    Dir; Src(\"f\"); Cat(\"f.hc\"); Run(\"f.hc\"); Cd/Pwd;\n");
  UartStr("  Help     help;  Help;\n");
  UartStr("  Note     Full Man/MemMap/Regs/asm/history: use bootstrap repl.elf\n");
  UartStr("  Soft     platform halt/reset to leave (Reset; on full REPL)\n");
}

U0 ReplEvalLine(U8 *line)
{
  I64 v, jr;
  if (!line)
    return;
  while (*line == ' ' || *line == '\t')
    line++;
  if (!*line)
    return;
  if (CmdIs(line, "help") || CmdIs(line, "Help")) {
    Help();
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
  if (CmdStrArg(line, "Cd")) {
    Cd(FsTmp);
    return;
  }
  jr = JitTry(line);
  if (jr)
    return;
  if (IsExprLine(line)) {
    v = EvalI64Line(line);
    if (eval_err) {
      "Eval: bad expression\n";
      return;
    }
    Print("ans=%p=%d\n", v, v);
    return;
  }
  UartStr("Eval: not recognized. try help;\n");
}
