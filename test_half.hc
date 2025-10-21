// Minimal Runtime Library for RISC-V Bootstrapping
// Provides only UART I/O and simple memory allocation

#define UART_BASE 0x10000000  // QEMU virt machine UART address
#define UART_RBR  0           // Receiver Buffer Register (read)
#define UART_THR  0           // Transmitter Holding Register (write)
#define UART_LSR  5           // Line Status Register
#define UART_LSR_RX_READY 0x01
#define UART_LSR_TX_IDLE  0x20

// Simple heap allocator (bump pointer)
U8 *_heap_start = 0x80400000;  // Start after 4MB
U8 *_heap_ptr = 0x80400000;
U8 *_heap_end = 0x88000000;    // 128MB heap

// UART I/O Functions

U0 uart_putc(U8 c) {
  // Wait for transmitter to be ready
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
  
  // Write character
  *(U8*)(UART_BASE + UART_THR) = c;
}

U8 uart_getc() {
  // Wait for data to be ready
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_RX_READY));
  
  // Read character
  return *(U8*)(UART_BASE + UART_RBR);
}

U0 uart_puts(U8 *str) {
  while (*str) {
    if (*str == '\n') {
      uart_putc('\r');
    }
    uart_putc(*str++);
  }
}

U0 uart_puti64(I64 val) {
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
  
  if (neg) {
    uart_putc('-');
  }
  
  while (i > 0) {
    uart_putc(buf[--i]);
  }
}

U0 uart_puthex(U64 val) {
  U8 *hex = "0123456789ABCDEF";
  uart_puts("0x");
  
  for (I64 i = 60; i >= 0; i -= 4) {
    uart_putc(hex[(val >> i) & 0xF]);
  }
}

// Memory Management

U8 *malloc(I64 size) {
  // Align to 8 bytes
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
  // Simple bump allocator - no-op for free
  // Could implement a free list later
}

U8 *calloc(I64 count, I64 size) {
  I64 total = count * size;
  U8 *ptr = malloc(total);
  
  if (ptr) {
    // Zero memory
    for (I64 i = 0; i < total; i++) {
      ptr[i] = 0;
    }
  }
  
  return ptr;
}

U8 *realloc(U8 *ptr, I64 new_size) {
  // Simplified realloc - just allocate new memory
  U8 *new_ptr = malloc(new_size);
  
  if (new_ptr && ptr) {
    // Copy old data (we don't track original size, so this is unsafe)
    // For bootstrapping, try to avoid realloc
    for (I64 i = 0; i < new_size; i++) {
      new_ptr[i] = ptr[i];
    }
  }
  
  return new_ptr;
}

// String Functions

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
  if (new_str) {
    strcpy(new_str, str);
  }
  return new_str;
