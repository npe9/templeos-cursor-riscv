#define UART_BASE 0x10000000
#define UART_THR  0
#define UART_LSR  5
#define UART_LSR_TX_IDLE  0x20

U0 uart_putc(U8 c) {
  while (!(*(U8*)(UART_BASE + UART_LSR) & UART_LSR_TX_IDLE));
  *(U8*)(UART_BASE + UART_THR) = c;
}

