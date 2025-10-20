// Worry Dream Machine - Pure HolyC Runtime
// NO C library dependencies - 100% HolyC

// ═══════════════════════════════════════════════════════════════
// HARDWARE ACCESS
// ═══════════════════════════════════════════════════════════════

U0 UartPut(U8 ch) {
  U8 *lsr;
  U8 *thr;
  lsr = 0x10000005;
  thr = 0x10000000;
  while (!(*lsr & 32)) {}
  *thr = ch;
}

U8 UartGet() {
  U8 *lsr;
  U8 *rbr;
  lsr = 0x10000005;
  rbr = 0x10000000;
  while (!(*lsr & 1)) {}
  return *rbr;
}

// ═══════════════════════════════════════════════════════════════
// STRING I/O
// ═══════════════════════════════════════════════════════════════

U0 PutChar(U8 ch) {
  if (ch == 10) UartPut(13);
  UartPut(ch);
}

U0 Print(U8 *str) {
  while (*str) {
    PutChar(*str);
    str = str + 1;
  }
}

U8 GetChar() {
  return UartGet();
}

// ═══════════════════════════════════════════════════════════════
// STRING FUNCTIONS
// ═══════════════════════════════════════════════════════════════

I64 StrLen(U8 *str) {
  I64 len;
  len = 0;
  while (*str) {
    len = len + 1;
    str = str + 1;
  }
  return len;
}

U0 StrCpy(U8 *dst, U8 *src) {
  while (*src) {
    *dst = *src;
    dst = dst + 1;
    src = src + 1;
  }
  *dst = 0;
}

I64 StrCmp(U8 *a, U8 *b) {
  while (*a && *a == *b) {
    a = a + 1;
    b = b + 1;
  }
  if (*a < *b) return -1;
  if (*a > *b) return 1;
  return 0;
}

// ═══════════════════════════════════════════════════════════════
// NUMBER I/O
// ═══════════════════════════════════════════════════════════════

U0 PrintHex(I64 val) {
  I64 i;
  U8 digit;
  
  Print("0x");
  
  i = 60;
  while (i >= 0) {
    digit = (val >> i) & 15;
    if (digit < 10) {
      PutChar(48 + digit);
    } else {
      PutChar(97 + digit - 10);
    }
    i = i - 4;
  }
}

U0 PrintDec(I64 val) {
  U8 buf[32];
  I64 i;
  I64 v;
  
  if (val == 0) {
    PutChar(48);
    return;
  }
  
  i = 0;
  v = val;
  if (v < 0) {
    PutChar(45);
    v = -v;
  }
  
  while (v > 0) {
    buf[i] = 48 + (v % 10);
    v = v / 10;
    i = i + 1;
  }
  
  while (i > 0) {
    i = i - 1;
    PutChar(buf[i]);
  }
}

// ═══════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════

U8 *heap_start;
U8 *heap_ptr;

U0 HeapInit() {
  heap_start = 0x80100000;
  heap_ptr = heap_start;
}

U8 *MAlloc(I64 size) {
  U8 *ptr;
  ptr = heap_ptr;
  heap_ptr = heap_ptr + size;
  return ptr;
}

U0 Free(U8 *ptr) {
  // No-op for now
}

// ═══════════════════════════════════════════════════════════════
// MATH FUNCTIONS
// ═══════════════════════════════════════════════════════════════

I64 Abs(I64 x) {
  if (x < 0) return -x;
  return x;
}

I64 Min(I64 a, I64 b) {
  if (a < b) return a;
  return b;
}

I64 Max(I64 a, I64 b) {
  if (a > b) return a;
  return b;
}

// ═══════════════════════════════════════════════════════════════
// REPL
// ═══════════════════════════════════════════════════════════════

U0 PrintBanner() {
  Print("\n");
  Print("═══════════════════════════════════════════════════════════\n");
  Print("  WORRY DREAM MACHINE\n");
  Print("  Pure HolyC on RISC-V\n");
  Print("═══════════════════════════════════════════════════════════\n");
  Print("\n");
}

I64 ReadLine(U8 *buf, I64 max) {
  I64 pos;
  U8 ch;
  
  pos = 0;
  while (1) {
    ch = GetChar();
    
    if (ch == 13 || ch == 10) {
      buf[pos] = 0;
      Print("\n");
      return pos;
    }
    
    if (ch == 127 || ch == 8) {
      if (pos > 0) {
        pos = pos - 1;
        UartPut(8);
        UartPut(32);
        UartPut(8);
      }
    } else {
      if (pos < max - 1) {
        buf[pos] = ch;
        pos = pos + 1;
        PutChar(ch);
      }
    }
  }
  
  return pos;
}

U0 REPL() {
  U8 line[256];
  I64 len;
  
  PrintBanner();
  
  while (1) {
    Print("> ");
    len = ReadLine(line, 256);
    
    if (len == 0) {
      // Empty line
    } else {
      // Echo back for now
      Print("You typed: ");
      Print(line);
      Print("\n");
    }
  }
}

I64 Main() {
  HeapInit();
  REPL();
  return 0;
}


