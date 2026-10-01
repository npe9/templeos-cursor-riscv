// A `static` LOCAL must belong to ITS function, and HolyC has no function-scoped storage, so the
// compiler makes one by putting the variable in the global hash table. The table is keyed by the
// BARE NAME, which means two functions declaring a static of the same name used to collide:
// ParseGlobalVariable found the first one's entry, reused it, and re-callocd its storage, so the
// first function's already-emitted global address belonged to no table entry and
// AOTGlobalByAddr emitted it as literally 0.
//
//     li   a0,0
//     ld   a0,0(a0)      -> load-fault at address 0
//
// Found translating cFS: every cFE module's dispatcher caches its message ids in
// `static CFE_SB_MsgId_t CMD_MID, SEND_HK_MID`, so the second translated dispatcher silently
// broke the first one -- and the fault appeared in the EARLIER function, four files away from
// the declaration that caused it. docs/HOLYC_STRUCT_LIMITS.md #12.
//
// What this case pins, and why each line of it is here:
//
//   - the same static NAME in three different functions, each keeping its own value across
//     calls. That is the collision itself.
//   - TWO statics per function, because the declarations are retired as a group and the second
//     one is where an off-by-one in that loop would show.
//   - `static I64 a, b;` in one declaration, which goes down a different parser path from
//     `static I64 a; static I64 b;`.
//   - an INITIALISED static (`= 7`), which must be initialised ONCE and not on every call.
//   - a FILE-SCOPE global with the same name as the statics, declared before them and read
//     after them. It must still be 500. This is the half of the bug that reached further: a
//     static local hijacked a real global's entry, and the global's own address was the one
//     orphaned.
#define XUART 0x10000000
U0 S(U8 *s)
{
  U8 *u = XUART;
  while (*s)
    *u = *s++;
}

I64 Fold(I64 r, I64 v)
{
  return r * 1000 + v;
}
// The file-scope global the statics below shadow by name. Nothing may re-aim it.
I64 n = 500;
I64 m = 600;
I64 A()
{
  static I64 n;
  static I64 m = 7;
  n++;
  m += 2;
  return Fold(n, m);
}

I64 B()
{
  static I64 n;
  static I64 m = 70;
  n += 10;
  m += 20;
  return Fold(n, m);
}
// One declaration, two names: the comma path.
I64 C()
{
  static I64 n, m;
  n += 100;
  m += 300;
  return Fold(n, m);
}

I64 main()
{
  I64 r = 0;
  r = Fold(r, A());
  // 1,9
  r = Fold(r, B());
  // 10,90
  r = Fold(r, C());
  // 100,300
  r = Fold(r, A());
  // 2,11   -- the initialiser ran once, not again
  r = Fold(r, B());
  // 20,110
  r = Fold(r, C());
  // 200,600
  // the file-scope pair, untouched
  r = r * 1000 + n;
  // 500
  r = r * 1000 + m;
  // 600
  return r & 0xFFFFFFFFFFFF;
}
