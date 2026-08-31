// print.hc -- Print / PutChars / StrPrintJoin in HolyC (UART). PutCh/PutS in uart.hc.
U0 PjPutDec(U64 v, I64 width, U8 pad, I64 commas, I64 neg)
{
  U8 b[48];
  I64 n = 0, digits = 0, i;
  if (!v)
    b[n++] = '0';
  while (v) {
    if (commas && digits && digits % 3 == 0)
      b[n++] = ',';
    b[n++] = '0' + v % 10;
    v = v / 10;
    digits++;
  }
  if (neg)
    b[n++] = '-';
  while (n < width)
    b[n++] = pad;
  while (n)
    PutCh(b[--n]);
}

U0 PjPutHex(U64 v, I64 upper, I64 width)
{
  U8 b[24];
  I64 n = 0, d;
  U8 A;
  if (upper)
    A = 'A';
  else
    A = 'a';
  if (!v)
    b[n++] = '0';
  while (v) {
    d = v & 15;
    if (d < 10)
      b[n++] = '0' + d;
    else
      b[n++] = A + d - 10;
    v = v >> 4;
  }
  while (n < width)
    b[n++] = '0';
  while (n)
    PutCh(b[--n]);
}
// StrPrintJoin -- StrPrintJoin(fmt,argc,argv)
// NAME
//   StrPrintJoin - core formatted print engine
// SYNOPSIS
//   U0 StrPrintJoin(U8 *fmt,I64 argc,I64 *argv);
// DESCRIPTION
//   Walk fmt and emit via PutCh. Used by Print.
// INPUTS
//   fmt - format string
//   argc/argv - varargs payload
// OUTPUTS
//   UART text
// BUGS
//   Subset of TempleOS Print flags.
U0 StrPrintJoin(U8 *fmt, I64 argc, I64 *argv)
{
  I64 ai, width, prec, commas, rep, v, l, i, c;
  U8 *p, *sv, pad;
  F64 fv;
  I64 *ip;
  if (!fmt)
    return;
  ai = 0;
  p = fmt;
  while (*p) {
    if (*p != '%') {
      PutCh (*p);
      p++;
      goto cont;
    }
    p++;
    pad = ' ';
    width = 0;
    prec = -1;
    commas = 0;
    rep = 1;
    while (1) {
      if (*p == '-')
        p++;
      else if (*p == '0') {
        pad = '0';
        p++;
      } else if (*p == ',') {
        commas = 1;
        p++;
      } else
        break;
    }
    while (*p >= '0' && *p <= '9') {
      width = width * 10 + (*p - '0');
      p++;
    }
    if (*p == ',') {
      commas = 1;
      p++;
    }
    if (*p == '.') {
      p++;
      prec = 0;
      while (*p >= '0' && *p <= '9') {
        prec = prec * 10 + (*p - '0');
        p++;
      }
    }
    while (*p == 'h') {
      p++;
      if (*p == '?')
        p++;
      else if (*p == '*') {
        if (ai < argc)
          rep = argv[ai++];
        else
          rep = 0;
        p++;
      } else if (*p == '-') {
        p++;
        while (*p >= '0' && *p <= '9')
          p++;
      } else {
        v = 0;
        while (*p >= '0' && *p <= '9') {
          v = v * 10 + (*p - '0');
          p++;
        }
        if (v)
          rep = v;
        else
          rep = 1;
      }
    }
    if (*p == 'd') {
      if (ai < argc)
        v = argv[ai++];
      else
        v = 0;
      if (v < 0)
        PjPutDec(-v, width, pad, commas, 1);
      else
        PjPutDec(v, width, pad, commas, 0);
    } else if (*p == 'u') {
      if (ai < argc)
        v = argv[ai++];
      else
        v = 0;
      PjPutDec(v, width, pad, commas, 0);
    } else if (*p == 'x') {
      if (ai < argc)
        v = argv[ai++];
      else
        v = 0;
      PjPutHex(v, 0, 0);
    } else if (*p == 'X') {
      if (ai < argc)
        v = argv[ai++];
      else
        v = 0;
      PjPutHex(v, 1, 0);
    } else if (*p == 'p' || *p == 'P') {
      if (ai < argc)
        v = argv[ai++];
      else
        v = 0;
      PutCh('0');
      PutCh('x');
      PjPutHex(v, 0, 16);
    } else if (*p == 's') {
      if (ai < argc)
        sv = argv[ai++];
      else
        sv = 0;
      if (!sv)
        sv = "(null)";
      l = 0;
      while (sv[l])
        l++;
      for (i = l; i < width; i++)
        PutCh(' ');
      while (*sv) {
        PutCh (*sv);
        sv++;
      }
    } else if (*p == 'c') {
      if (ai < argc)
        c = argv[ai++];
      else
        c = 0;
      for (i = 0; i < rep; i++) {
        I64 ch = c;
        while (ch) {
          PutCh(ch & 255);
          ch = ch >> 8;
        }
      }
    } else if (*p == 'f' || *p == 'n') {
      if (ai < argc)
        v = argv[ai++];
      else
        v = 0;
      fv = 0.0;
      ip = &fv;
      *ip = v;
      if (prec < 0)
        prec = 3;
      // sign + int + frac
      if (fv < 0) {
        PutCh('-');
        fv = -fv;
      }
      v = ToI64(fv);
      PjPutDec(v, 0, ' ', 0, 0);
      PutCh('.');
      fv = fv - v;
      for (i = 0; i < prec; i++) {
        fv = fv * 10.0;
        v = ToI64(fv);
        PutCh('0' + v);
        fv = fv - v;
      }
    } else if (*p == '%')
      PutCh('%');
    else if (*p) {
      PutCh('%');
      PutCh (*p);
    }
    if (*p)
      p++;
    cont:
  }
}
// Print -- Print(fmt,...)
// NAME
//   Print - formatted print to the UART
// SYNOPSIS
//   U0 Print(U8 *fmt,...);
// DESCRIPTION
//   TempleOS-style formatted print to the serial console (%d/%x/%s/%c/%f and friends).
// INPUTS
//   fmt - format string; trailing args match Print placeholders
// OUTPUTS
//   Characters on the UART; no return value
// BUGS
//   HolyC reimplementation — subset of full TempleOS Print.
U0 Print(U8 *fmt,...)
{
  StrPrintJoin(fmt, argc, argv);
}

U0 PutChars(I64 ch)
{
  while (ch) {
    PutCh(ch & 255);
    ch = ch >> 8;
  }
}
