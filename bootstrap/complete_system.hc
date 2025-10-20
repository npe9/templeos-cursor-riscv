// Complete TempleOS-style RISC-V System in ONE HolyC File
// UART Driver + Editor + REPL - Everything

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_RX_READY 0x01
#define UART_LSR_TX_IDLE  0x20

// UART Driver
U0 PutC(U8 c) {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
  *(U8*)(UART_BASE) = c;
}

U8 GetC() {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_RX_READY));
  return *(U8*)(UART_BASE);
}

U0 Print(U8 *str) {
  while (*str) {
    if (*str == '\n') PutC('\r');
    PutC(*str++);
  }
}

U0 PrintNum(I64 val) {
  U8 buf[32];
  I64 i = 0;
  Bool neg = FALSE;
  
  if (val < 0) {
    neg = TRUE;
    val = -val;
  }
  
  if (val == 0) {
    PutC('0');
    return;
  }
  
  while (val > 0) {
    buf[i++] = '0' + (val % 10);
    val /= 10;
  }
  
  if (neg) PutC('-');
  while (i > 0) PutC(buf[--i]);
}

// Memory
U8 *heap = 0x80500000;

U8 *Alloc(I64 size) {
  U8 *ptr = heap;
  heap += (size + 7) & ~7;
  return ptr;
}

// String
I64 SLen(U8 *s) {
  I64 len = 0;
  while (*s++) len++;
  return len;
}

U8 *SCpy(U8 *dst, U8 *src) {
  while ((*dst++ = *src++));
  return dst;
}

I64 SCmp(U8 *s1, U8 *s2) {
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *s1 - *s2;
}

// Code buffer
#define MAX_CODE 2048
U8 code_buf[MAX_CODE];
I64 code_len = 0;

// Functions
#define MAX_FUNCS 8
class Func {
  U8 name[64];
  U8 *code;
  I64 size;
};

Func funcs[MAX_FUNCS];
I64 func_count = 0;

// Read line
U0 ReadLine(U8 *buf, I64 max) {
  I64 pos = 0;
  Print("> ");
  
  while (TRUE) {
    U8 ch = GetC();
    
    if (ch == '\r' || ch == '\n') {
      Print("\n");
      buf[pos] = '\0';
      return;
    } else if (ch == 127 || ch == 8) {
      if (pos > 0) {
        pos--;
        PutC('\b');
        PutC(' ');
        PutC('\b');
      }
    } else if (ch >= 32 && ch < 127 && pos < max - 1) {
      buf[pos++] = ch;
      PutC(ch);
    }
  }
}

// Mini compiler - compiles "return N;"
U8 *Compile(U8 *src, I64 *size) {
  // Find "return"
  U8 *p = src;
  while (*p && !(*p=='r' && p[1]=='e' && p[2]=='t')) p++;
  if (!*p) {
    *size = 0;
    return NULL;
  }
  
  p += 6;  // Skip "return"
  while (*p == ' ') p++;
  
  // Parse number
  I64 val = 0;
  Bool neg = FALSE;
  if (*p == '-') {
    neg = TRUE;
    p++;
  }
  while (*p >= '0' && *p <= '9') {
    val = val * 10 + (*p - '0');
    p++;
  }
  if (neg) val = -val;
  
  // Generate RISC-V: ADDI a0, zero, val; RET
  U8 *code = Alloc(16);
  U32 inst = 0x00000013 | (10 << 7) | ((val & 0xFFF) << 20);
  code[0] = inst & 0xFF;
  code[1] = (inst >> 8) & 0xFF;
  code[2] = (inst >> 16) & 0xFF;
  code[3] = (inst >> 24) & 0xFF;
  code[4] = 0x67;
  code[5] = 0x80;
  code[6] = 0x00;
  code[7] = 0x00;
  
  *size = 8;
  return code;
}

// Main REPL
U0 Main() {
  Print("\n\n");
  Print("═══════════════════════════════════════════════════════════\n");
  Print("      TempleOS RISC-V - HolyC Bootstrap System\n");
  Print("      Compiled with HolyC, Running on RISC-V!\n");
  Print("═══════════════════════════════════════════════════════════\n");
  Print("\n");
  Print("Enter: I64 Answer() { return 42; }\n");
  Print("Then type 'Answer' to call it\n");
  Print("\n");
  
  U8 input[256];
  
  while (TRUE) {
    ReadLine(input, 256);
    
    if (input[0] == '\0') continue;
    
    // Check if calling a function
    for (I64 i = 0; i < func_count; i++) {
      if (SCmp(funcs[i].name, input) == 0) {
        Print("\n>>> Calling ");
        Print(funcs[i].name);
        Print("()...\n");
        
        I64 (*f)() = funcs[i].code;
        I64 result = f();
        
        Print(">>> Returned: ");
        PrintNum(result);
        Print("\n\n");
        goto next_line;
      }
    }
    
    // Check for quit
    if (SCmp(input, ":quit") == 0) {
      Print("Goodbye!\n");
      while (TRUE);
    }
    
    // Add to code buffer
    I64 len = SLen(input);
    if (code_len + len + 1 < MAX_CODE) {
      SCpy(&code_buf[code_len], input);
      code_len += len;
      code_buf[code_len++] = '\n';
      code_buf[code_len] = '\0';
      
      // Check if complete (ends with })
      if (input[0] == '}' || SCmp(input, "END") == 0) {
        Print("\n>>> Compiling...\n");
        
        I64 code_size;
        U8 *binary = Compile(code_buf, &code_size);
        
        if (binary && code_size > 0) {
          // Extract function name
          U8 *p = code_buf;
          while (*p && *p != ' ') p++;
          while (*p == ' ') p++;
          
          I64 i = 0;
          while (*p && *p != '(' && i < 63) {
            funcs[func_count].name[i++] = *p++;
          }
          funcs[func_count].name[i] = '\0';
          
          funcs[func_count].code = binary;
          funcs[func_count].size = code_size;
          func_count++;
          
          Print("✓ Compiled '");
          Print(funcs[func_count-1].name);
          Print("'\n\n");
        }
        
        code_len = 0;
        code_buf[0] = '\0';
      }
    }
    
    next_line:;
  }
}


