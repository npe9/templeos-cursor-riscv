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

