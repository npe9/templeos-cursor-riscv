// The other side of the same boundary: 8 bytes and under must still compile, and so must a
// POINTER to a large class. A diagnostic that also refused these would be worse than the bug.
class S8 { U32 a; U32 b; };
class Big { I64 a; I64 b; };
S8 Fits() { S8 v; v.a = 1; v.b = 2; return v; }
Big *ByPointer() { return NULL; }
I64 main() { S8 x; x = Fits; return x.a + (ByPointer == NULL); }
