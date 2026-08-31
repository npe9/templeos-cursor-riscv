// TempleOS-style Kernel for RISC-V
// Compiler + Editor running together, no libc dependencies

#define UART_BASE 0x10000000
#define UART_LSR  5
#define UART_LSR_RX_READY 0x01
#define UART_LSR_TX_IDLE  0x20

// UART Driver
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

U0 uart_print_hex(U64 val) {
  U8 *hex = "0123456789ABCDEF";
  uart_puts("0x");
  for (I64 i = 60; i >= 0; i -= 4) {
    uart_putc(hex[(val >> i) & 0xF]);
  }
}

// Memory management (simple bump allocator)
U8 *_heap_ptr = 0x80400000;
U8 *_heap_end = 0x88000000;

U8 *malloc(I64 size) {
  size = (size + 7) & ~7;
  if (_heap_ptr + size >= _heap_end) {
    uart_puts("ERROR: Out of memory!\n");
    return NULL;
  }
  U8 *ptr = _heap_ptr;
  _heap_ptr += size;
  return ptr;
}

U0 free(U8 *ptr) {
  // Bump allocator - no free
}

// String functions
I64 strlen(U8 *str) {
  I64 len = 0;
  while (*str++) len++;
  return len;
}

U8 *strcpy(U8 *dst, U8 *src) {
  U8 *ret = dst;
  while ((*dst++ = *src++));
  return ret;
}

I64 strcmp(U8 *s1, U8 *s2) {
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *s1 - *s2;
}

U8 *strdup(U8 *str) {
  I64 len = strlen(str);
  U8 *new_str = malloc(len + 1);
  if (new_str) strcpy(new_str, str);
  return new_str;
}

// Code buffer
#define MAX_CODE 16384
U8 code_buffer[MAX_CODE];
I64 code_len = 0;

// Compiled code storage
U8 *compiled_code = NULL;
I64 compiled_size = 0;

// Read line from UART
U0 ReadLine(U8 *buf, I64 max_len) {
  I64 pos = 0;
  uart_puts("> ");
  
  while (TRUE) {
    U8 ch = uart_getc();
    
    if (ch == '\r' || ch == '\n') {
      uart_puts("\n");
      buf[pos] = '\0';
      return;
    } else if (ch == 127 || ch == 8) {  // Backspace
      if (pos > 0) {
        pos--;
        uart_putc('\b');
        uart_putc(' ');
        uart_putc('\b');
      }
    } else if (ch == 3) {  // Ctrl-C
      uart_puts("^C\n");
      buf[0] = '\0';
      return;
    } else if (ch >= 32 && ch < 127 && pos < max_len - 1) {
      buf[pos++] = ch;
      uart_putc(ch);
    }
  }
}

U0 ShowBanner() {
  uart_puts("\n\n");
  uart_puts("═══════════════════════════════════════════════════════════\n");
  uart_puts("      TempleOS RISC-V - Interactive Kernel\n");
  uart_puts("         Compiler + Editor Live System\n");
  uart_puts("═══════════════════════════════════════════════════════════\n");
  uart_puts("\n");
  uart_puts("Commands:\n");
  uart_puts("  :list   - Show code buffer\n");
  uart_puts("  :clear  - Clear buffer\n");
  uart_puts("  :go     - Compile and run\n");
  uart_puts("  :test   - Run test function\n");
  uart_puts("  :quit   - Exit\n");
  uart_puts("\n");
  uart_puts("Type HolyC code, then :go to compile and execute!\n");
  uart_puts("\n");
}

U0 ListCode() {
  uart_puts("\n=== Code Buffer ===\n");
  uart_puts(code_buffer);
  uart_puts("===================\n");
}

U0 ClearCode() {
  code_len = 0;
  code_buffer[0] = '\0';
  uart_puts("Buffer cleared\n");
}

U0 AddLine(U8 *line) {
  I64 len = strlen(line);
  if (code_len + len + 2 >= MAX_CODE) {
    uart_puts("ERROR: Buffer full!\n");
    return;
  }
  strcpy(&code_buffer[code_len], line);
  code_len += len;
  code_buffer[code_len++] = '\n';
  code_buffer[code_len] = '\0';
}

// Simple test function we can execute
U0 TestFunction() {
  uart_puts("\n>>> TestFunction() called!\n");
  uart_puts(">>> This proves code execution works\n");
  
  I64 x = 5;
  I64 y = 3;
  I64 sum = x + y;
  
  uart_puts(">>> 5 + 3 = ");
  uart_print_i64(sum);
  uart_puts("\n");
  
  I64 fact = 1;
  for (I64 i = 1; i <= 5; i++) {
    fact = fact * i;
  }
  uart_puts(">>> 5! = ");
  uart_print_i64(fact);
  uart_puts("\n");
  
  uart_puts(">>> Test complete!\n\n");
}

Bool CompileAndRun() {
  uart_puts("\n>>> Compiling HolyC code...\n");
  uart_puts(">>> Code buffer size: ");
  uart_print_i64(code_len);
  uart_puts(" bytes\n");
  
  // For now, we'll use a pre-compiled test
  // TODO: Actually call the compiler here
  uart_puts(">>> TODO: Real compilation not yet integrated\n");
  uart_puts(">>> Would compile this code:\n");
  ListCode();
  
  uart_puts("\n>>> For demo: calling pre-compiled TestFunction\n");
  TestFunction();
  
  return TRUE;
}

U0 ProcessCommand(U8 *input) {
  if (input[0] == '\0') return;
  
  if (input[0] == ':') {
    // Commands
    if (strcmp(input + 1, "list") == 0) {
      ListCode();
    } else if (strcmp(input + 1, "clear") == 0) {
      ClearCode();
    } else if (strcmp(input + 1, "go") == 0) {
      CompileAndRun();
    } else if (strcmp(input + 1, "test") == 0) {
      TestFunction();
    } else if (strcmp(input + 1, "quit") == 0) {
      uart_puts("\nExiting...\n");
      while (TRUE);  // Halt
    } else {
      uart_puts("Unknown command. Try :list, :go, :test, :quit\n");
    }
  } else {
    // Add code line
    AddLine(input);
  }
}

// Main kernel loop
U0 Main() {
  ShowBanner();
  
  U8 input[256];
  
  while (TRUE) {
    ReadLine(input, 256);
    ProcessCommand(input);
  }
}


