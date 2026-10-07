// AN ARRAY OF FUNCTION POINTERS WORKS; CALLING THROUGH AN ELEMENT DIRECTLY DOES NOT.
//
// LOUD, not silent, which is the only reason this is a short case: `map[0](&one)` is
//
//     error: Expected ';' or ','
//
// at the `(`. Three of the four spellings around it are fine, and the one that fails is the one a
// C reader would write first:
//
//     I32 (*map[4])(U8 *);        declaring it            OK
//     fn = map[0]; fn(&one);      via a variable          OK
//     call(map[3], &one);         passed as an argument   OK
//     map[0](&one);               called in place         PARSE ERROR
//
// MEASURED BEFORE TRANSLATING cs_init.c, not after failing to. NASA's CS_InitAllTables keeps four
// `static const` arrays indexed by checksum type, one of them an array of
// CFE_TBL_CallbackFuncPtr_t, and the question was whether that shape could be translated at all.
// It can: NASA assigns the element to a local (`ValidationFunc = TABLE_CALLBACK_MAP[TableId];`) and
// passes the local on, which is the second spelling above. So this case exists to record the
// boundary rather than to report a blocked translation -- and if a later cFS source does write
// `table[i](args)`, the workaround is one assignment and this is where the answer is.
//
// cFE's own command-handler tables were checked and do not use the failing form either.
I64 main();

I32 a(U8 *p)
{
  return 10 + *p;
}

I32 b(U8 *p)
{
  return 20 + *p;
}

// The NULL guard is here because a table of handlers with holes in it is the whole reason such a
// table exists -- CS's own EventIdMap and callback map both leave the two code-segment rows unset.
I32 call(I32 (*f)(U8 *), U8 *p)
{
  if (f == NULL)
    return 99;
  return f(p);
}

I64 main()
{
  I32 (*map[4])(U8 *);
  I32 (*fn)(U8 *);
  U8 one = 1;
  I64 r;

  map[0] = &a;
  map[1] = &b;
  map[2] = NULL;
  map[3] = &a;

  // Byte 3: through a local variable. 11.
  fn = map[0];
  r = call(fn, &one);
  // Byte 2: a different element, so the index is doing work. 21.
  fn = map[1];
  r = r << 8 | call(fn, &one);
  // Byte 1: the hole. 99 -- and it has to be a value the two real handlers cannot produce.
  fn = map[2];
  r = r << 8 | call(fn, &one);
  // Byte 0: the element passed straight as an argument, no local. 11.
  r = r << 8 | call(map[3], &one);
  return r;
}
