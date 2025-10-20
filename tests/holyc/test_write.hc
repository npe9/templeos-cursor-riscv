I64 WriteChar() { U8 *uart; uart = 0x10000000; *uart = 88; return 1; }
I64 Main() { return WriteChar(); }
