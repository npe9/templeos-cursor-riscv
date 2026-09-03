// trzsz.hc -- native trzsz guest→host send (tsz-compatible). Needs zmodem.hc RX helpers.
// Wire: #ACT/#CFG JSON + zlib(store)+base64 + MD5. Host: tools/uart_recv_trzsz.py or stock trzsz.
#define TZ_TO 40000000
#define TZ_CHUNK 1024
#define TZ_VER "1.0.0"
U8 TzLine[384];
I64 TzLn;
U8 TzZlib[1280];
I64 TzZn;
U8 TzB64[1800];
I64 TzBn;
U8 TzDig[16];
U32 TzMd5A;
U32 TzMd5B;
U32 TzMd5C;
U32 TzMd5D;
U32 TzMd5n;
U8 TzMd5Blk[64];
I64 TzOpen;
I64 TzUid;
U32 TzRotL(U32 x, I64 n)
{
  return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF;
}

U32 TzF(U32 x, U32 y, U32 z)
{
  return (x & y) | (((~x) & 0xFFFFFFFF) & z);
}

U32 TzG(U32 x, U32 y, U32 z)
{
  return (x & z) | (y & ((~z) & 0xFFFFFFFF));
}

U32 TzH(U32 x, U32 y, U32 z)
{
  return x ^ y ^ z;
}

U32 TzI(U32 x, U32 y, U32 z)
{
  return y ^ (x | ((~z) & 0xFFFFFFFF));
}

U0 TzMd5FF(U32 *a, U32 b, U32 c, U32 d, U32 x, I64 s, U32 ac)
{
  *a = (*a + TzF(b, c, d) + x + ac) & 0xFFFFFFFF;
  *a = TzRotL (*a, s);
  *a = (*a + b) & 0xFFFFFFFF;
}

U0 TzMd5GG(U32 *a, U32 b, U32 c, U32 d, U32 x, I64 s, U32 ac)
{
  *a = (*a + TzG(b, c, d) + x + ac) & 0xFFFFFFFF;
  *a = TzRotL (*a, s);
  *a = (*a + b) & 0xFFFFFFFF;
}

U0 TzMd5HH(U32 *a, U32 b, U32 c, U32 d, U32 x, I64 s, U32 ac)
{
  *a = (*a + TzH(b, c, d) + x + ac) & 0xFFFFFFFF;
  *a = TzRotL (*a, s);
  *a = (*a + b) & 0xFFFFFFFF;
}

U0 TzMd5II(U32 *a, U32 b, U32 c, U32 d, U32 x, I64 s, U32 ac)
{
  *a = (*a + TzI(b, c, d) + x + ac) & 0xFFFFFFFF;
  *a = TzRotL (*a, s);
  *a = (*a + b) & 0xFFFFFFFF;
}

U0 TzMd5Transform(U8 *blk)
{
  U32 a, b, c, d, x[16];
  I64 i;
  for (i = 0; i < 16; i++)
    x[i] = (blk[i * 4] & 255) | ((blk[i * 4 + 1] & 255) << 8) | ((blk[i * 4 + 2] & 255) << 16) | ((blk[i * 4 + 3] & 255) << 24);
  a = TzMd5A;
  b = TzMd5B;
  c = TzMd5C;
  d = TzMd5D;
  TzMd5FF(&a, b, c, d, x[0], 7, 0xD76AA478);
  TzMd5FF(&d, a, b, c, x[1], 12, 0xE8C7B756);
  TzMd5FF(&c, d, a, b, x[2], 17, 0x242070DB);
  TzMd5FF(&b, c, d, a, x[3], 22, 0xC1BDCEEE);
  TzMd5FF(&a, b, c, d, x[4], 7, 0xF57C0FAF);
  TzMd5FF(&d, a, b, c, x[5], 12, 0x4787C62A);
  TzMd5FF(&c, d, a, b, x[6], 17, 0xA8304613);
  TzMd5FF(&b, c, d, a, x[7], 22, 0xFD469501);
  TzMd5FF(&a, b, c, d, x[8], 7, 0x698098D8);
  TzMd5FF(&d, a, b, c, x[9], 12, 0x8B44F7AF);
  TzMd5FF(&c, d, a, b, x[10], 17, 0xFFFF5BB1);
  TzMd5FF(&b, c, d, a, x[11], 22, 0x895CD7BE);
  TzMd5FF(&a, b, c, d, x[12], 7, 0x6B901122);
  TzMd5FF(&d, a, b, c, x[13], 12, 0xFD987193);
  TzMd5FF(&c, d, a, b, x[14], 17, 0xA679438E);
  TzMd5FF(&b, c, d, a, x[15], 22, 0x49B40821);
  TzMd5GG(&a, b, c, d, x[1], 5, 0xF61E2562);
  TzMd5GG(&d, a, b, c, x[6], 9, 0xC040B340);
  TzMd5GG(&c, d, a, b, x[11], 14, 0x265E5A51);
  TzMd5GG(&b, c, d, a, x[0], 20, 0xE9B6C7AA);
  TzMd5GG(&a, b, c, d, x[5], 5, 0xD62F105D);
  TzMd5GG(&d, a, b, c, x[10], 9, 0x02441453);
  TzMd5GG(&c, d, a, b, x[15], 14, 0xD8A1E681);
  TzMd5GG(&b, c, d, a, x[4], 20, 0xE7D3FBC8);
  TzMd5GG(&a, b, c, d, x[9], 5, 0x21E1CDE6);
  TzMd5GG(&d, a, b, c, x[14], 9, 0xC33707D6);
  TzMd5GG(&c, d, a, b, x[3], 14, 0xF4D50D87);
  TzMd5GG(&b, c, d, a, x[8], 20, 0x455A14ED);
  TzMd5GG(&a, b, c, d, x[13], 5, 0xA9E3E905);
  TzMd5GG(&d, a, b, c, x[2], 9, 0xFCEFA3F8);
  TzMd5GG(&c, d, a, b, x[7], 14, 0x676F02D9);
  TzMd5GG(&b, c, d, a, x[12], 20, 0x8D2A4C8A);
  TzMd5HH(&a, b, c, d, x[5], 4, 0xFFFA3942);
  TzMd5HH(&d, a, b, c, x[8], 11, 0x8771F681);
  TzMd5HH(&c, d, a, b, x[11], 16, 0x6D9D6122);
  TzMd5HH(&b, c, d, a, x[14], 23, 0xFDE5380C);
  TzMd5HH(&a, b, c, d, x[1], 4, 0xA4BEEA44);
  TzMd5HH(&d, a, b, c, x[4], 11, 0x4BDECFA9);
  TzMd5HH(&c, d, a, b, x[7], 16, 0xF6BB4B60);
  TzMd5HH(&b, c, d, a, x[10], 23, 0xBEBFBC70);
  TzMd5HH(&a, b, c, d, x[13], 4, 0x289B7EC6);
  TzMd5HH(&d, a, b, c, x[0], 11, 0xEAA127FA);
  TzMd5HH(&c, d, a, b, x[3], 16, 0xD4EF3085);
  TzMd5HH(&b, c, d, a, x[6], 23, 0x04881D05);
  TzMd5HH(&a, b, c, d, x[9], 4, 0xD9D4D039);
  TzMd5HH(&d, a, b, c, x[12], 11, 0xE6DB99E5);
  TzMd5HH(&c, d, a, b, x[15], 16, 0x1FA27CF8);
  TzMd5HH(&b, c, d, a, x[2], 23, 0xC4AC5665);
  TzMd5II(&a, b, c, d, x[0], 6, 0xF4292244);
  TzMd5II(&d, a, b, c, x[7], 10, 0x432AFF97);
  TzMd5II(&c, d, a, b, x[14], 15, 0xAB9423A7);
  TzMd5II(&b, c, d, a, x[5], 21, 0xFC93A039);
  TzMd5II(&a, b, c, d, x[12], 6, 0x655B59C3);
  TzMd5II(&d, a, b, c, x[3], 10, 0x8F0CCC92);
  TzMd5II(&c, d, a, b, x[10], 15, 0xFFEFF47D);
  TzMd5II(&b, c, d, a, x[1], 21, 0x85845DD1);
  TzMd5II(&a, b, c, d, x[8], 6, 0x6FA87E4F);
  TzMd5II(&d, a, b, c, x[15], 10, 0xFE2CE6E0);
  TzMd5II(&c, d, a, b, x[6], 15, 0xA3014314);
  TzMd5II(&b, c, d, a, x[13], 21, 0x4E0811A1);
  TzMd5II(&a, b, c, d, x[4], 6, 0xF7537E82);
  TzMd5II(&d, a, b, c, x[11], 10, 0xBD3AF235);
  TzMd5II(&c, d, a, b, x[2], 15, 0x2AD7D2BB);
  TzMd5II(&b, c, d, a, x[9], 21, 0xEB86D391);
  TzMd5A = (TzMd5A + a) & 0xFFFFFFFF;
  TzMd5B = (TzMd5B + b) & 0xFFFFFFFF;
  TzMd5C = (TzMd5C + c) & 0xFFFFFFFF;
  TzMd5D = (TzMd5D + d) & 0xFFFFFFFF;
}

U0 TzMd5Init()
{
  TzMd5A = 0x67452301;
  TzMd5B = 0xEFCDAB89;
  TzMd5C = 0x98BADCFE;
  TzMd5D = 0x10325476;
  TzMd5n = 0;
}

U0 TzMd5Update(U8 *p, I64 n)
{
  I64 i, off;
  for (i = 0; i < n; i++) {
    off = TzMd5n & 63;
    TzMd5Blk[off] = p[i];
    TzMd5n++;
    if (off == 63)
      TzMd5Transform(TzMd5Blk);
  }
}

U0 TzMd5Final(U8 *out)
{
  I64 i, off;
  U64 bits;
  off = TzMd5n & 63;
  TzMd5Blk[off] = 0x80;
  off++;
  if (off > 56) {
    while (off < 64) {
      TzMd5Blk[off] = 0;
      off++;
    }
    TzMd5Transform(TzMd5Blk);
    off = 0;
  }
  while (off < 56) {
    TzMd5Blk[off] = 0;
    off++;
  }
  bits = TzMd5n * 8;
  for (i = 0; i < 8; i++)
    TzMd5Blk[56 + i] = (bits >> (8 * i)) & 255;
  TzMd5Transform(TzMd5Blk);
  for (i = 0; i < 4; i++) {
    out[i] = (TzMd5A >> (8 * i)) & 255;
    out[4 + i] = (TzMd5B >> (8 * i)) & 255;
    out[8 + i] = (TzMd5C >> (8 * i)) & 255;
    out[12 + i] = (TzMd5D >> (8 * i)) & 255;
  }
}

U32 TzAdler(U8 *p, I64 n)
{
  U32 a, b;
  I64 i;
  a = 1;
  b = 0;
  i = 0;
  while (i < n) {
    a = (a + (p[i] & 255)) % 65521;
    b = (b + a) % 65521;
    i++;
  }
  return (b << 16) | a;
}

I64 TzZlibStore(U8 *src, I64 n, U8 *dst, I64 cap)
{
  U32 ad;
  I64 o, ln, nln;
  if (n < 0 || n > 65535 || cap < n + 11)
    return -1;
  dst[0] = 0x78;
  dst[1] = 0x01;
  dst[2] = 0x01;
  ln = n;
  nln = (~ln) & 0xFFFF;
  dst[3] = ln & 255;
  dst[4] = (ln >> 8) & 255;
  dst[5] = nln & 255;
  dst[6] = (nln >> 8) & 255;
  o = 0;
  while (o < n) {
    dst[7 + o] = src[o];
    o++;
  }
  ad = TzAdler(src, n);
  dst[7 + n] = (ad >> 24) & 255;
  dst[8 + n] = (ad >> 16) & 255;
  dst[9 + n] = (ad >> 8) & 255;
  dst[10 + n] = ad & 255;
  return n + 11;
}

U0 TzB64Enc(U8 *src, I64 n)
{
  I64 i, v, rem;
  TzBn = 0;
  i = 0;
  while (i + 2 < n) {
    v = ((src[i] & 255) << 16) | ((src[i + 1] & 255) << 8) | (src[i + 2] & 255);
    TzB64[TzBn] = B64At ((v >> 18) & 63);
    TzBn++;
    TzB64[TzBn] = B64At ((v >> 12) & 63);
    TzBn++;
    TzB64[TzBn] = B64At ((v >> 6) & 63);
    TzBn++;
    TzB64[TzBn] = B64At(v & 63);
    TzBn++;
    i += 3;
  }
  rem = n - i;
  if (rem == 1) {
    v = (src[i] & 255) << 16;
    TzB64[TzBn] = B64At ((v >> 18) & 63);
    TzBn++;
    TzB64[TzBn] = B64At ((v >> 12) & 63);
    TzBn++;
    TzB64[TzBn] = '=';
    TzBn++;
    TzB64[TzBn] = '=';
    TzBn++;
  } else if (rem == 2) {
    v = ((src[i] & 255) << 16) | ((src[i + 1] & 255) << 8);
    TzB64[TzBn] = B64At ((v >> 18) & 63);
    TzBn++;
    TzB64[TzBn] = B64At ((v >> 12) & 63);
    TzBn++;
    TzB64[TzBn] = B64At ((v >> 6) & 63);
    TzBn++;
    TzB64[TzBn] = '=';
    TzBn++;
  }
  TzB64[TzBn] = 0;
}

I64 TzEncodeBuf(U8 *src, I64 n)
{
  TzZn = TzZlibStore(src, n, TzZlib, 1280);
  if (TzZn < 0)
    return -1;
  TzB64Enc(TzZlib, TzZn);
  return TzBn;
}

U0 TzPutRaw(U8 *s, I64 n)
{
  I64 i;
  i = 0;
  while (i < n) {
    UartPut(s[i] & 255);
    i++;
  }
}

U0 TzSendEnc(U8 *typ, U8 *src, I64 n)
{
  if (TzEncodeBuf(src, n) < 0)
    return;
  UartPut('#');
  UartStr(typ);
  UartPut(':');
  TzPutRaw(TzB64, TzBn);
  UartPut('\n');
}

U0 TzSendIntLine(U8 *typ, I64 v)
{
  U8 b[24];
  I64 i, t;
  UartPut('#');
  UartStr(typ);
  UartPut(':');
  if (v < 0) {
    UartPut('-');
    v = -v;
  }
  if (!v)
    UartPut('0');
  else {
    i = 0;
    t = v;
    while (t && i < 22) {
      b[i] = '0' + t % 10;
      i++;
      t = t / 10;
    }
    while (i) {
      i--;
      UartPut(b[i]);
    }
  }
  UartPut('\n');
}

I64 TzReadLine()
{
  I64 c, n;
  TzLn = 0;
  ZmArm();
  n = 0;
  while (1) {
    c = ZmWait1();
    if (c < 0)
      return -1;
    /* FC is off for the session — host wake XON/XOFF must not prefix #ACT/#SUCC. */
    if (c == 0x11 || c == 0x13)
      continue;
    if (c == '\r')
      continue;
    if (c == '\n') {
      TzLine[TzLn] = 0;
      return TzLn;
    }
    if (TzLn < 380) {
      TzLine[TzLn] = c;
      TzLn++;
    }
    n++;
    if (n > 200000)
      return -1;
  }
  return -1;
}

I64 TzExpect(U8 *typ)
{
  I64 i, n;
  U8 *p;
  n = TzReadLine();
  if (n < 0)
    return -1;
  if (TzLine[0] != '#')
    return -1;
  p = typ;
  i = 1;
  while (*p) {
    if (TzLine[i] != *p)
      return -1;
    i++;
    p++;
  }
  if (TzLine[i] != ':')
    return -1;
  return i + 1;
}

I64 TzExpectSucc()
{
  return TzExpect("SUCC");
}

U0 TzTrigger()
{
  U8 id[16];
  I64 i, v, n;
  // \x1b7::TRZSZ:TRANSFER:S:1.0.0:0000000000000:0\r\n
  UartPut(0x1B);
  UartPut('7');
  UartStr("::TRZSZ:TRANSFER:S:");
  UartStr(TZ_VER);
  UartPut(':');
  TzUid = GetMTime() & 0x7FFFFFFF;
  v = TzUid;
  i = 0;
  if (!v) {
    id[i] = '0';
    i++;
  } else {
    while (v && i < 13) {
      id[i] = '0' + v % 10;
      i++;
      v = v / 10;
    }
  }
  n = i;
  while (n < 13) {
    UartPut('0');
    n++;
  }
  while (i) {
    i--;
    UartPut(id[i]);
  }
  UartPut(':');
  UartPut('0');
  UartPut('\r');
  UartPut('\n');
}
I64 TzFcSaved;
I64 TrzszBegin()
{
  TzFcSaved = UartFcGet();
  UartXonXoff(0);
  /* Wake host if boot/IXOFF left the chardev paused; raw XON is fine with FC off. */
  UartPut(UART_XON);
  /* binary framing */
  TzOpen = 0;
  TzTrigger();
  // Wait for #ACT:… (do not require zlib decode; stock clients always confirm here)
  while (1) {
    if (TzReadLine() < 0) {
      UartStr("trzsz: no host (start uart_recv_trzsz.py / trzsz)\n");
      UartXonXoff(TzFcSaved);
      return 0;
    }
    if (TzLn >= 5 && TzLine[0] == '#' && TzLine[1] == 'A' && TzLine[2] == 'C' && TzLine[3] == 'T' && TzLine[4] == ':')
      break;
  }
  // CFG: quiet base64 mode, protocol 1
  TzSendEnc("CFG", "{\"lang\":\"hc\",\"quiet\":true,\"protocol\":1}", 39);
  TzOpen = 1;
  return 1;
}

U0 TrzszEnd()
{
  if (!TzOpen)
    return;
  // Host client_exit → #EXIT:…; ignore body
  TzExpect("EXIT");
  TzOpen = 0;
  UartXonXoff(TzFcSaved);
}

I64 TrzszSendFile(U8 *name)
{
  U8 *d, *nm, *base;
  I64 n, i, left, take, off;
  if (!TzOpen)
    return -1;
  d = FileRead(name);
  n = FileLen(name);
  if (!d || n < 0)
    return -1;
  nm = name;
  i = FsFind(name);
  if (i >= 0)
    nm = FsName(i);
  if (nm[0] == '/')
    nm++;
  // basename for NAME (non-directory mode)
  base = nm;
  i = 0;
  while (nm[i]) {
    if (nm[i] == '/')
      base = nm + i + 1;
    i++;
  }
  TzSendEnc("NAME", base, FsStrLen(base));
  if (TzExpectSucc() < 0)
    return -1;
  TzSendIntLine("SIZE", n);
  if (TzExpectSucc() < 0)
    return -1;
  TzMd5Init();
  off = 0;
  left = n;
  while (left > 0) {
    take = left;
    if (take > TZ_CHUNK)
      take = TZ_CHUNK;
    TzSendEnc("DATA", d + off, take);
    TzMd5Update(d + off, take);
    if (TzExpectSucc() < 0)
      return -1;
    off += take;
    left -= take;
  }
  TzMd5Final(TzDig);
  TzSendEnc("MD5", TzDig, 16);
  if (TzExpectSucc() < 0)
    return -1;
  return n;
}

I64 TrzszSessionBegin(I64 num)
{
  if (!TrzszBegin())
    return 0;
  TzSendIntLine("NUM", num);
  if (TzExpectSucc() < 0) {
    TzOpen = 0;
    UartXonXoff(TzFcSaved);
    return 0;
  }
  return 1;
}
// TrzszSend -- TrzszSend("file")
// NAME
//   TrzszSend - export a memfs file with native trzsz (tsz) over UART
// SYNOPSIS
//   U0 TrzszSend(U8 *name);
// DESCRIPTION
//   Speaks native trzsz: TRANSFER:S trigger, #CFG JSON, zlib+base64 #DATA,
//   MD5. Compatible with stock trzsz client and tools/uart_recv_trzsz.py.
//   ZMODEM remains ZmodemSend (trzsz --zmodem / rz).
// EXAMPLES
//   TrzszSend("boot.hc");
// SEE ALSO
//   ZmodemSend  TrzszSendDir  TrzszSendChanges  DumpFile
// BUGS
//   Send-only; no guest recv (trz). Times out if no host client.
U0 TrzszSend(U8 *name)
{
  if (FileLen(name) < 0) {
    UartStr("trzsz: no such file: ");
    if (name)
      UartStr(name);
    PutCh('\n');
    return;
  }
  if (!TrzszSessionBegin(1))
    return;
  TrzszSendFile(name);
  TrzszEnd();
}
// TrzszSendDir -- TrzszSendDir("Tutorials")
// NAME
//   TrzszSendDir - native-trzsz-send every memfs file under a directory prefix
// SYNOPSIS
//   U0 TrzszSendDir(U8 *name);
// SEE ALSO
//   TrzszSend  ZmodemSendDir
U0 TrzszSendDir(U8 *name)
{
  I64 i, n, pl, k, cnt;
  U8 *nm;
  if (!name)
    return;
  i = 0;
  while (name[i] && i < 90) {
    FsTmp[i] = name[i];
    i++;
  }
  if (i && FsTmp[i - 1] != '/') {
    FsTmp[i] = '/';
    i++;
  }
  FsTmp[i] = 0;
  FsResolve(FsTmp);
  pl = FsStrLen(FsResolveBuf);
  if (!pl) {
    UartStr("TrzszSendDir: empty prefix\n");
    return;
  }
  i = 0;
  while (i < pl && i < 63) {
    ZmPref[i] = FsResolveBuf[i];
    i++;
  }
  ZmPref[i] = 0;
  cnt = 0;
  n = FileCount();
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    if (!nm || ZmIsDotDir(nm))
      continue;
    if (!ZmPrefOk(nm, ZmPref, pl))
      continue;
    cnt++;
  }
  if (!cnt) {
    UartStr("TrzszSendDir: no files\n");
    return;
  }
  if (!TrzszSessionBegin(cnt))
    return;
  k = 0;
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    if (!nm || ZmIsDotDir(nm))
      continue;
    if (!ZmPrefOk(nm, ZmPref, pl))
      continue;
    if (TrzszSendFile(nm) >= 0)
      k++;
  }
  TrzszEnd();
  "trzsz dir %s (%d files)\n", name, k;
}
// TrzszSendChanges -- TrzszSendChanges()
// NAME
//   TrzszSendChanges - native-trzsz-send memfs files dirtied this session
// SYNOPSIS
//   U0 TrzszSendChanges();
// SEE ALSO
//   ZmodemSendChanges  FsChanges  DumpChanges
U0 TrzszSendChanges()
{
  I64 i, k, n;
  U8 *nm;
  k = 0;
  for (i = 0; i < MEMFS_MAX; i++) {
    if (!FsSlotUsed(i) || !FsIsDirty(i))
      continue;
    nm = FsName(i);
    if (ZmIsDotDir(nm))
      continue;
    k++;
  }
  if (!k) {
    UartStr("TrzszSendChanges: no dirty files\n");
    return;
  }
  if (!TrzszSessionBegin(k))
    return;
  n = 0;
  for (i = 0; i < MEMFS_MAX; i++) {
    if (!FsSlotUsed(i) || !FsIsDirty(i))
      continue;
    nm = FsName(i);
    if (ZmIsDotDir(nm))
      continue;
    if (TrzszSendFile(nm) >= 0)
      n++;
  }
  TrzszEnd();
  "trzsz changes (%d files)\n", n;
}
