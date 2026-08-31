// Minimal HolyC Compiler in HolyC
// No libc dependencies - uses only runtime functions
// Can compile simple HolyC functions and execute them

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_RX_READY 0x01
#define UART_LSR_TX_IDLE  0x20

// Runtime API (no libc!)
U0 uart_putc(U8 c) {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
  *(U8*)(UART_BASE) = c;
}

U8 uart_getc() {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_RX_READY));
  return *(U8*)(UART_BASE);
}

U0 Print(U8 *str) {
  while (*str) {
    if (*str == '\n') uart_putc('\r');
    uart_putc(*str++);
  }
}

U0 PrintI64(I64 val) {
  U8 buf[32];
  I64 i = 0;
  Bool neg = FALSE;
  
  if (val < 0) {
    neg = TRUE;
    val = -val;
  }
  
  if (val == 0) {
    uart_putc('0');
    return;
  }
  
  while (val > 0) {
    buf[i++] = '0' + (val % 10);
    val /= 10;
  }
  
  if (neg) uart_putc('-');
  while (i > 0) uart_putc(buf[--i]);
}

// Memory
U8 *_heap = 0x80400000;

U8 *Alloc(I64 size) {
  size = (size + 7) & ~7;
  U8 *ptr = _heap;
  _heap += size;
  return ptr;
}

// String API
I64 SLen(U8 *s) {
  I64 len = 0;
  while (*s++) len++;
  return len;
}

U8 *SCpy(U8 *dst, U8 *src) {
  U8 *ret = dst;
  while ((*dst++ = *src++));
  return ret;
}

I64 SCmp(U8 *s1, U8 *s2) {
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *s1 - *s2;
}

// Simple lexer
class Token {
  I64 type;
  I64 ival;
  U8 sval[64];
};

#define TK_EOF 0
#define TK_IDENT 1
#define TK_NUM 2
#define TK_LBRACE 3
#define TK_RBRACE 4
#define TK_LPAREN 5
#define TK_RPAREN 6
#define TK_SEMI 7
#define TK_RETURN 8
#define TK_I64 9
#define TK_STAR 10
#define TK_PLUS 11
#define TK_MINUS 12

U8 *lex_ptr;
Token tok;

U0 SkipWhite() {
  while (*lex_ptr == ' ' || *lex_ptr == '\t' || *lex_ptr == '\n' || *lex_ptr == '\r') {
    lex_ptr++;
  }
}

U0 NextToken() {
  SkipWhite();
  
  if (!*lex_ptr) {
    tok.type = TK_EOF;
    return;
  }
  
  // Numbers
  if (*lex_ptr >= '0' && *lex_ptr <= '9') {
    tok.type = TK_NUM;
    tok.ival = 0;
    while (*lex_ptr >= '0' && *lex_ptr <= '9') {
      tok.ival = tok.ival * 10 + (*lex_ptr - '0');
      lex_ptr++;
    }
    return;
  }
  
  // Identifiers and keywords
  if ((*lex_ptr >= 'a' && *lex_ptr <= 'z') || (*lex_ptr >= 'A' && *lex_ptr <= 'Z') || *lex_ptr == '_') {
    I64 i = 0;
    while ((*lex_ptr >= 'a' && *lex_ptr <= 'z') || (*lex_ptr >= 'A' && *lex_ptr <= 'Z') ||
           (*lex_ptr >= '0' && *lex_ptr <= '9') || *lex_ptr == '_') {
      if (i < 63) tok.sval[i++] = *lex_ptr;
      lex_ptr++;
    }
    tok.sval[i] = '\0';
    
    // Check keywords
    if (SCmp(tok.sval, "return") == 0) {
      tok.type = TK_RETURN;
    } else if (SCmp(tok.sval, "I64") == 0) {
      tok.type = TK_I64;
    } else {
      tok.type = TK_IDENT;
    }
    return;
  }
  
  // Single char tokens
  if (*lex_ptr == '{') { tok.type = TK_LBRACE; lex_ptr++; return; }
  if (*lex_ptr == '}') { tok.type = TK_RBRACE; lex_ptr++; return; }
  if (*lex_ptr == '(') { tok.type = TK_LPAREN; lex_ptr++; return; }
  if (*lex_ptr == ')') { tok.type = TK_RPAREN; lex_ptr++; return; }
  if (*lex_ptr == ';') { tok.type = TK_SEMI; lex_ptr++; return; }
  if (*lex_ptr == '*') { tok.type = TK_STAR; lex_ptr++; return; }
  if (*lex_ptr == '+') { tok.type = TK_PLUS; lex_ptr++; return; }
  if (*lex_ptr == '-') { tok.type = TK_MINUS; lex_ptr++; return; }
  
  lex_ptr++;  // Skip unknown
  NextToken();
}

// Simple code generator
U8 *code_gen;

U0 EmitU32(U32 val) {
  *code_gen++ = val & 0xFF;
  *code_gen++ = (val >> 8) & 0xFF;
  *code_gen++ = (val >> 16) & 0xFF;
  *code_gen++ = (val >> 24) & 0xFF;
}

U0 EmitADDI(U8 rd, U8 rs1, I64 imm) {
  U32 inst = 0x13 | (rd << 7) | (0 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20);
  EmitU32(inst);
}

U0 EmitADD(U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd << 7) | (0 << 12) | (rs1 << 15) | (rs2 << 20) | (0 << 25);
  EmitU32(inst);
}

U0 EmitMUL(U8 rd, U8 rs1, U8 rs2) {
  U32 inst = 0x33 | (rd << 7) | (0 << 12) | (rs1 << 15) | (rs2 << 20) | (1 << 25);
  EmitU32(inst);
}

U0 EmitRET() {
  EmitU32(0x00008067);  // JALR x0, 0(ra)
}

// Compile "I64 FuncName() { return N; }"
U8 *Compile(U8 *source, I64 *size) {
  Print(">>> Compiling...\n");
  
  lex_ptr = source;
  U8 *code_start = Alloc(256);
  code_gen = code_start;
  
  NextToken();
  
  // Parse: I64 FuncName() { return N; }
  if (tok.type != TK_I64) {
    Print("ERROR: Expected I64\n");
    *size = 0;
    return NULL;
  }
  NextToken();
  
  if (tok.type != TK_IDENT) {
    Print("ERROR: Expected function name\n");
    *size = 0;
    return NULL;
  }
  
  Print(">>> Function: ");
  Print(tok.sval);
  Print("\n");
  
  NextToken();
  
  // Skip ()
  if (tok.type != TK_LPAREN) {
    Print("ERROR: Expected (\n");
    *size = 0;
    return NULL;
  }
  NextToken();
  
  if (tok.type != TK_RPAREN) {
    Print("ERROR: Expected )\n");
    *size = 0;
    return NULL;
  }
  NextToken();
  
  if (tok.type != TK_LBRACE) {
    Print("ERROR: Expected {\n");
    *size = 0;
    return NULL;
  }
  NextToken();
  
  // Parse return statement
  if (tok.type != TK_RETURN) {
    Print("ERROR: Expected return\n");
    *size = 0;
    return NULL;
  }
  NextToken();
  
  // Get return value
  if (tok.type == TK_NUM) {
    // return N;
    I64 retval = tok.ival;
    Print(">>> Return: ");
    PrintI64(retval);
    Print("\n");
    
    // Generate: ADDI a0, zero, retval; RET
    EmitADDI(10, 0, retval);
    EmitRET();
  } else {
    Print("ERROR: Only 'return N;' supported\n");
    *size = 0;
    return NULL;
  }
  
  *size = code_gen - code_start;
  
  Print(">>> Generated ");
  PrintI64(*size);
  Print(" bytes\n");
  
  return code_start;
}

// Function table
class Func {
  U8 name[64];
  U8 *code;
  I64 size;
};

Func funcs[8];
I64 func_count = 0;

// Read input
U0 ReadLine(U8 *buf, I64 max) {
  I64 pos = 0;
  Print("> ");
  
  while (TRUE) {
    U8 ch = uart_getc();
    
    if (ch == '\r' || ch == '\n') {
      Print("\n");
      buf[pos] = '\0';
      return;
    } else if (ch == 127 || ch == 8) {
      if (pos > 0) {
        pos--;
        uart_putc('\b');
        uart_putc(' ');
        uart_putc('\b');
      }
    } else if (ch >= 32 && ch < 127 && pos < max - 1) {
      buf[pos++] = ch;
      uart_putc(ch);
    }
  }
}

// Main
U0 Main() {
  Print("\n\n");
  Print("═══════════════════════════════════════════════════════════\n");
  Print("   TempleOS RISC-V - HolyC Bootstrapping System\n");
  Print("      Pure HolyC Compiler (No Libc!)\n");
  Print("═══════════════════════════════════════════════════════════\n");
  Print("\n");
  Print("Enter function:\n");
  Print("  I64 Double(I64 x) { return x * 2; }\n");
  Print("Then type: Double\n");
  Print("\n");
  
  U8 input[256];
  U8 code[1024];
  I64 code_len = 0;
  
  while (TRUE) {
    ReadLine(input, 256);
    
    if (input[0] == '\0') continue;
    
    // Check if calling a function
    Bool found = FALSE;
    for (I64 i = 0; i < func_count; i++) {
      if (SCmp(funcs[i].name, input) == 0) {
        Print("\n>>> Calling ");
        Print(funcs[i].name);
        Print("()...\n");
        
        I64 (*f)() = funcs[i].code;
        I64 result = f();
        
        Print(">>> Result: ");
        PrintI64(result);
        Print("\n\n");
        
        found = TRUE;
        break;
      }
    }
    
    if (found) continue;
    
    // Check for commands
    if (input[0] == ':') {
      if (SCmp(input + 1, "quit") == 0) {
        Print("Goodbye!\n");
        while (TRUE);
      }
      continue;
    }
    
    // Otherwise add to code buffer
    I64 len = SLen(input);
    if (code_len + len + 1 < 1024) {
      SCpy(&code[code_len], input);
      code_len += len;
      code[code_len++] = '\n';
      code[code_len] = '\0';
      
      // Check if we have a complete function (ends with })
      if (input[0] == '}') {
        Print("\n>>> Function complete\n");
        
        // Compile it
        I64 code_size;
        U8 *binary = Compile(code, &code_size);
        
        if (binary && code_size > 0) {
          // Extract function name (look for "I64 Name(")
          U8 *p = code;
          while (*p && *p != ' ') p++;  // Skip I64
          while (*p == ' ') p++;        // Skip spaces
          
          I64 i = 0;
          while (*p && *p != '(' && i < 63) {
            funcs[func_count].name[i++] = *p++;
          }
          funcs[func_count].name[i] = '\0';
          
          funcs[func_count].code = binary;
          funcs[func_count].size = code_size;
          func_count++;
          
          Print("✓ Function '");
          Print(funcs[func_count-1].name);
          Print("' compiled\n");
          Print("✓ Type '");
          Print(funcs[func_count-1].name);
          Print("' to call it\n\n");
        }
        
        code_len = 0;
        code[0] = '\0';
      }
    }
  }
}


