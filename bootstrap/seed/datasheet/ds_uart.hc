// ds_uart.hc -- NS16550A UART datasheet sheets @ MEM_UART.
// Byte offsets match uart.hc / csr.hc UART_* macros.
U0 DsSheetUartLsr()
{
  DsBegin("uart.lsr", "uart", DS_KIND_MMIO, MEM_UART + UART_LSR_OFF, 1);
  DsField("DR", 0, 0, "0=empty,1=data", "Receiver data ready");
  DsField("OE", 1, 1, "0=ok,1=overrun", "Overrun error");
  DsField("PE", 2, 2, "0=ok,1=parity", "Parity error");
  DsField("FE", 3, 3, "0=ok,1=framing", "Framing error");
  DsField("BI", 4, 4, "0=ok,1=break", "Break interrupt");
  DsField("THRE", 5, 5, "0=full,1=empty", "TX holding register empty");
  DsField("TEMT", 6, 6, "0=busy,1=empty", "Transmitter empty");
  DsField("ERR", 7, 7, "0=ok,1=error", "Error in RCVR FIFO");
  DsEnd;
}

U0 DsSheetUartIer()
{
  DsBegin("uart.ier", "uart", DS_KIND_MMIO, MEM_UART + 1, 1);
  DsField("RDA", 0, 0, "0=off,1=on", "Received data available IRQ");
  DsField("THRE", 1, 1, "0=off,1=on", "THRE IRQ");
  DsField("RLS", 2, 2, "0=off,1=on", "Receiver line status IRQ");
  DsField("MS", 3, 3, "0=off,1=on", "Modem status IRQ");
  DsEnd;
}

U0 DsSheetUartLcr()
{
  DsBegin("uart.lcr", "uart", DS_KIND_MMIO, MEM_UART + 3, 1);
  DsField("WLS", 0, 1, "0=5,1=6,2=7,3=8", "Word length select");
  DsField("STB", 2, 2, "0=1stop,1=2stop", "Stop bits");
  DsField("PEN", 3, 3, "0=off,1=on", "Parity enable");
  DsField("EPS", 4, 4, "0=odd,1=even", "Even parity select");
  DsField("STICK", 5, 5, "0=off,1=on", "Stick parity");
  DsField("BREAK", 6, 6, "0=off,1=on", "Set break");
  DsField("DLAB", 7, 7, "0=data,1=divisor", "Divisor latch access");
  DsEnd;
}

U0 DsSheetUartMcr()
{
  DsBegin("uart.mcr", "uart", DS_KIND_MMIO, MEM_UART + 4, 1);
  DsField("DTR", 0, 0, "0=deassert,1=assert", "Data terminal ready");
  DsField("RTS", 1, 1, "0=deassert,1=assert", "Request to send");
  DsField("OUT1", 2, 2, 0, "User output 1");
  DsField("OUT2", 3, 3, 0, "User output 2 / IRQ enable on PC");
  DsField("LOOP", 4, 4, "0=normal,1=loop", "Local loopback");
  DsEnd;
}

U0 DsUartInit()
{
  DsSheetUartLsr;
  DsSheetUartIer;
  DsSheetUartLcr;
  DsSheetUartMcr;
}
DsUartInit;
