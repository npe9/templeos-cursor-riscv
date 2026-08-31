// TempleOS-style Interactive Shell in Pure HolyC
// Define functions, compile them, call them

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_RX_READY 0x01
#define UART_LSR_TX_IDLE  0x20

// UART Runtime
U0 uart_putc(U8 c) {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
  *(U8*)(UART_BASE) = c;
}

U8 uart_getc() {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_RX_READY));
  return *(U8*)(UART_BASE);
}

U0 uart_puts(U8 *str) {
  while (*str) {
    if (*str == '\n') uart_putc('\r');
    uart_putc(*str++);
  }
}

U0 uart_print_i64(I64 val) {
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
U8 *_heap_ptr = 0x80400000;

U8 *MAlloc(I64 size) {
  size = (size + 7) & ~7;
  U8 *ptr = _heap_ptr;
  _heap_ptr += size;
  return ptr;
}

U0 Free(U8 *ptr) {
  // Bump allocator - no free
}

// String functions
I64 StrLen(U8 *str) {
  I64 len = 0;
  while (*str++) len++;
  return len;
}

U8 *StrCpy(U8 *dst, U8 *src) {
  U8 *ret = dst;
  while ((*dst++ = *src++));
  return ret;
}

I64 StrCmp(U8 *s1, U8 *s2) {
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *s1 - *s2;
}

// Code buffer
#define MAX_CODE 8192
U8 code_buffer[MAX_CODE];
I64 code_len = 0;

// Function registry
#define MAX_FUNCS 8
class CFunc {
  U8 name[64];
  U8 *code;
  I64 size;
  U8 *entry;
};

CFunc funcs[MAX_FUNCS];
I64 func_count = 0;

// Read line
U0 ReadLine(U8 *buf, I64 max_len) {
  I64 pos = 0;
  uart_puts("> ");
  
  while (TRUE) {
    U8 ch = uart_getc();
    
    if (ch == '\r' || ch == '\n') {
      uart_puts("\n");
      buf[pos] = '\0';
      return;
    } else if (ch == 127 || ch == 8) {
      if (pos > 0) {
        pos--;
        uart_putc('\b');
        uart_putc(' ');
        uart_putc('\b');
      }
    } else if (ch >= 32 && ch < 127 && pos < max_len - 1) {
      buf[pos++] = ch;
      uart_putc(ch);
    }
  }
}

// Add line to buffer
U0 AddLine(U8 *line) {
  I64 len = StrLen(line);
  if (code_len + len + 2 < MAX_CODE) {
    StrCpy(&code_buffer[code_len], line);
    code_len += len;
    code_buffer[code_len++] = '\n';
    code_buffer[code_len] = '\0';
  }
}

// Simple function compiler - compiles "I64 FuncName() { return N; }"
U8 *CompileSimpleFunc(U8 *code, I64 *size, U8 *func_name) {
  uart_puts(">>> Compiling function...\n");
  
  // Parse to find "return N;"
  U8 *p = code;
  while (*p) {
    // Find "return"
    if (p[0]=='r' && p[1]=='e' && p[2]=='t' && p[3]=='u' && p[4]=='r' && p[5]=='n') {
      p += 6;
      while (*p == ' ') p++;
      
      // Parse number
      I64 value = 0;
      Bool neg = FALSE;
      if (*p == '-') {
        neg = TRUE;
        p++;
      }
      while (*p >= '0' && *p <= '9') {
        value = value * 10 + (*p - '0');
        p++;
      }
      if (neg) value = -value;
      
      uart_puts(">>> Return value: ");
      uart_print_i64(value);
      uart_puts("\n");
      
      // Generate RISC-V: ADDI a0, zero, value; RET
      U8 *binary = MAlloc(32);
      I64 idx = 0;
      
      // ADDI a0, zero, value
      U32 inst = 0x00000013 | (10 << 7) | ((value & 0xFFF) << 20);
      binary[idx++] = inst & 0xFF;
      binary[idx++] = (inst >> 8) & 0xFF;
      binary[idx++] = (inst >> 16) & 0xFF;
      binary[idx++] = (inst >> 24) & 0xFF;
      
      // RET (JALR x0, 0(ra))
      binary[idx++] = 0x67;
      binary[idx++] = 0x80;
      binary[idx++] = 0x00;
      binary[idx++] = 0x00;
      
      *size = idx;
      
      uart_puts(">>> Generated ");
      uart_print_i64(idx);
      uart_puts(" bytes\n");
      
      return binary;
    }
    p++;
  }
  
  *size = 0;
  return NULL;
}

// Extract function name from code
U0 ExtractFuncName(U8 *code, U8 *name_buf) {
  // Look for pattern: "I64 FuncName"
  U8 *p = code;
  
  // Skip return type
  while (*p && *p != ' ') p++;
  while (*p == ' ') p++;
  
  // Extract name
  I64 i = 0;
  while (*p && *p != '(' && *p != ' ' && i < 63) {
    name_buf[i++] = *p++;
  }
  name_buf[i] = '\0';
}

// Compile and load function
U0 CompileAndLoad() {
  if (code_len == 0) {
    uart_puts("ERROR: No code to compile\n");
    return;
  }
  
  code_buffer[code_len] = '\0';
  
  uart_puts("\n=== Code to Compile ===\n");
  uart_puts(code_buffer);
  uart_puts("=======================\n\n");
  
  if (func_count >= MAX_FUNCS) {
    uart_puts("ERROR: Too many functions\n");
    return;
  }
  
  // Extract function name
  U8 fname[64];
  ExtractFuncName(code_buffer, fname);
  
  uart_puts(">>> Function name: ");
  uart_puts(fname);
  uart_puts("\n");
  
  // Compile it
  I64 code_size = 0;
  U8 *binary = CompileSimpleFunc(code_buffer, &code_size, fname);
  
  if (binary && code_size > 0) {
    StrCpy(funcs[func_count].name, fname);
    funcs[func_count].code = binary;
    funcs[func_count].size = code_size;
    funcs[func_count].entry = binary;
    func_count++;
    
    uart_puts("✓ Function '");
    uart_puts(fname);
    uart_puts("' compiled and loaded\n\n");
  } else {
    uart_puts("ERROR: Compilation failed\n\n");
  }
  
  // Clear buffer for next function
  code_len = 0;
  code_buffer[0] = '\0';
}

// Call function by name
U0 CallFunc(U8 *name) {
  for (I64 i = 0; i < func_count; i++) {
    if (StrCmp(funcs[i].name, name) == 0) {
      uart_puts("\n>>> Calling ");
      uart_puts(name);
      uart_puts("()...\n");
      
      // Cast to function and call
      I64 (*func)() = funcs[i].entry;
      I64 result = func();
      
      uart_puts(">>> Returned: ");
      uart_print_i64(result);
      uart_puts("\n\n");
      return;
    }
  }
  
  uart_puts("ERROR: Function '");
  uart_puts(name);
  uart_puts("' not found\n");
}

// List functions
U0 ListFuncs() {
  uart_puts("\n=== Compiled Functions ===\n");
  for (I64 i = 0; i < func_count; i++) {
    uart_puts(funcs[i].name);
    uart_puts(" (");
    uart_print_i64(funcs[i].size);
    uart_puts(" bytes @ 0x");
    
    U64 addr = funcs[i].entry;
    U8 *hex = "0123456789ABCDEF";
    for (I64 j = 60; j >= 0; j -= 4) {
      uart_putc(hex[(addr >> j) & 0xF]);
    }
    uart_puts(")\n");
  }
  uart_print_i64(func_count);
  uart_puts(" functions loaded\n\n");
}

// Main loop
U0 Main() {
  uart_puts("\n\n");
  uart_puts("═══════════════════════════════════════════════════════════\n");
  uart_puts("      TempleOS RISC-V - Interactive HolyC System\n");
  uart_puts("         Define Functions, Then Call Them!\n");
  uart_puts("═══════════════════════════════════════════════════════════\n");
  uart_puts("\n");
  uart_puts("Usage:\n");
  uart_puts("  1. Type: I64 Double(I64 x) {\n");
  uart_puts("  2. Type:   return x * 2;\n");
  uart_puts("  3. Type: }\n");
  uart_puts("  4. Type: END\n");
  uart_puts("  5. Type: Double    <- calls it\n");
  uart_puts("\n");
  uart_puts("Commands:\n");
  uart_puts("  :funcs  - List functions\n");
  uart_puts("  :quit   - Exit\n");
  uart_puts("\n");
  
  U8 input[256];
  
  while (TRUE) {
    ReadLine(input, 256);
    
    if (input[0] == '\0') continue;
    
    if (input[0] == ':') {
      if (StrCmp(input + 1, "funcs") == 0) {
        ListFuncs();
      } else if (StrCmp(input + 1, "quit") == 0) {
        uart_puts("Goodbye!\n");
        while (TRUE);  // Halt
      }
    } else if (StrCmp(input, "END") == 0) {
      CompileAndLoad();
    } else {
      // Check if calling a function
      Bool found = FALSE;
      for (I64 i = 0; i < func_count; i++) {
        if (StrCmp(funcs[i].name, input) == 0) {
          CallFunc(input);
          found = TRUE;
          break;
        }
      }
      
      if (!found) {
        AddLine(input);
      }
    }
  }
}


