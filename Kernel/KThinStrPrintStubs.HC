// KThinStrPrintStubs.HC — RV_THIN_LOADER: drop full StrPrint.HC (~41 KiB;
// StrPrintJoin alone ~33 KiB). SoftCall UART lives in Kernel.BIN; thin only
// needs Print/StrPrint for RVKMain banners + RVThinUartI64 (%s/%d).
// SoftCall KernelPrintSoft proves StrPrintJoin lite (%s/%d/%X/%c) in Kernel.BIN (→'KP').
#ifndef K_THIN_STRPRINT_STUBS_HC
#define K_THIN_STRPRINT_STUBS_HC
#define THIN_SPRINT_CAP 256
U0 ThinPutI64(U8 *dst, I64 *pos, I64 cap, I64 v, I64 radix, Bool upper)
{
  U8 tmp[72];
  I64 n = 0, i, dig, neg = 0;
  U64 u;
  if (radix < 2)
    radix = 10;
  if (v < 0 && radix == 10) {
    neg = 1;
    u = -v;
  } else
    u = v;
  if (!u) {
    tmp[n++] = '0';
  } else {
    while (u) {
      dig = u % radix;
      u /= radix;
      if (dig < 10)
        tmp[n++] = '0' + dig;
      else if (upper)
        tmp[n++] = 'A' + dig - 10;
      else
        tmp[n++] = 'a' + dig - 10;
    }
  }
  if (neg && *pos < cap - 1)
    dst[(*pos)++] = '-';
  for (i = n - 1; i >= 0 && *pos < cap - 1; i--)
    dst[(*pos)++] = tmp[i];
}

U8 *StrPrintJoin(U8 *dst, U8 *fmt, I64 argc, I64 *argv)
{
  U8 buf[THIN_SPRINT_CAP];
  U8 *out, *s;
  I64 pos = 0, ai = 0, ch, own = 0;
  if (!fmt)
    fmt = "";
  if (!dst) {
    out = buf;
    own = 1;
  } else
    out = dst;
  while (ch = *fmt++) {
    if (ch != '%' || !*fmt) {
      if (pos < THIN_SPRINT_CAP - 1)
        out[pos++] = ch;
      continue;
    }
    ch = *fmt++;
    // Skip thin-unused flags/width/precision (full join is gated).
    while (ch == '-' || ch == '+' || ch == ' ' || ch == '#' || ch == '0')
      ch = *fmt++;
    while (ch >= '0' && ch <= '9')
      ch = *fmt++;
    if (ch == '.') {
      ch = *fmt++;
      while (ch >= '0' && ch <= '9')
        ch = *fmt++;
    }
    if (ch == 'l' || ch == 'L' || ch == 'h')
      ch = *fmt++;
    switch (ch) {
      case '%' :
      if (pos < THIN_SPRINT_CAP - 1)
        out[pos++] = '%';
      break;
      case 's' :
      s = 0;
      if (ai < argc)
        s = argv[ai++];
      if (!s)
        s = "";
      while (*s && pos < THIN_SPRINT_CAP - 1)
        out[pos++] = *s++;
      break;
      case 'c' :
      if (ai < argc && pos < THIN_SPRINT_CAP - 1)
        out[pos++] = argv[ai++];
      break;
      case 'd' :
      case 'i' :
      if (ai < argc)
        ThinPutI64(out, &pos, THIN_SPRINT_CAP, argv[ai++], 10, FALSE);
      break;
      case 'u' :
      if (ai < argc)
        ThinPutI64(out, &pos, THIN_SPRINT_CAP, argv[ai++], 10, FALSE);
      break;
      case 'x' :
      if (ai < argc)
        ThinPutI64(out, &pos, THIN_SPRINT_CAP, argv[ai++], 16, FALSE);
      break;
      case 'X' :
      case 'p' :
      case 'P' :
      if (ai < argc)
        ThinPutI64(out, &pos, THIN_SPRINT_CAP, argv[ai++], 16, TRUE);
      break;
      case 'z' :
      case 'Z' :
      // StrPrintFlags (%z Define) unused on thin Jump — skip arg.
      if (ai < argc)
        ai++;
      break;
      case 'f' :
      case 'e' :
      case 'g' :
      case 'n' :
      case 'Q' :
      case 'q' :
      case 'D' :
      case 'T' :
      if (ai < argc)
        ai++;
      break;
      default:
      break;
    }
  }
  out[pos] = 0;
  if (own) {
    s = MAlloc(pos + 1);
    if (!s)
      return NULL;
    MemCpy(s, out, pos + 1);
    return s;
  }
  return out;
}

U8 *StrPrint(U8 *dst, U8 *fmt,...)
{
  return StrPrintJoin(dst, fmt, argc, argv);
}

U8 *CatPrint(U8 *_dst, U8 *fmt,...)
{
  U8 *dst = _dst;
  if (!_dst)
    return StrPrintJoin(NULL, fmt, argc, argv);
  while (*dst)
    dst++;
  StrPrintJoin(dst, fmt, argc, argv);
  return _dst;
}

U0 Print(U8 *fmt,...)
{
  U8 *buf = StrPrintJoin(NULL, fmt, argc, argv);
  if (buf) {
    PutS(buf);
    Free(buf);
  }
}

U8 *MStrPrint(U8 *fmt,...)
{
  U8 *buf = StrPrintJoin(NULL, fmt, argc, argv), *res;
  if (!buf)
    return NULL;
  res = StrNew(buf);
  Free(buf);
  return res;
}

U0 PrintErr(U8 *fmt,...)
{
  U8 *buf = StrPrintJoin(NULL, fmt, argc, argv);
  PutS("ERROR: ");
  if (buf) {
    PutS(buf);
    Free(buf);
  }
}

U0 PrintWarn(U8 *fmt,...)
{
  U8 *buf = StrPrintJoin(NULL, fmt, argc, argv);
  PutS("WARNING: ");
  if (buf) {
    PutS(buf);
    Free(buf);
  }
}
// DolDoc/date helpers live in full StrPrint.HC — unused on thin Jump.
U8 *MPrintTime(CDate cdt)
{
  no_warn cdt;
  return StrNew("");
}

U8 *MPrintDate(CDate cdt)
{
  no_warn cdt;
  return StrNew("");
}
#endif
