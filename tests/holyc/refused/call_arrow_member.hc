// `fn(args)->member` DOES NOT COMPILE, and the diagnostic names the wrong class.
//
// HolyC resolves the `->` against the type of the call's FIRST ARGUMENT rather than against the
// function's return type. Here GetA returns `A *` and takes a `B *`, and the compiler reports
//     No member 'y' in class 'B' (->)
// which is the shape worth recording: the message blames a class that has nothing to do with
// the expression, so the first reading of it is that the WRONG FUNCTION is being called.
//
// Being refused is the correct outcome and is why this is a refusal test rather than a bug
// report: the alternative -- reading `y` at B's offset for `y`, or at some offset of its own --
// would be a silent wrong load. The cFS translation hits this shape wherever NASA writes
// `CFE_ES_ComputeCRC_GetParams(x)->Algorithm`, and the workaround is a local:
//     A *p = GetA(&b, 1);  p->y
// docs/HOLYC_STRUCT_LIMITS.md #17.
class A
{
  U32 x;
  U32 y;
};

class B
{
  U32 p;
};
A GA;
A *GetA(B *b, U16 k)
{
  return &GA;
}

I64 main()
{
  B b;
  GA.x = 7;
  GA.y = 9;
  return GetA(&b, 1)->y;
}
