// INTEGER DIVISION IN A CONSTANT EXPRESSION IS **FLOATING POINT** IN THIS COMPILER.
//
// NASA's standard round-up-to-a-multiple idiom is `((N + K - 1) / K) * K`, and cFS uses it for
// every bit-packed array size. In C, `(176 + 15) / 16` is 11 and `* 4` makes 44. Here the division
// produces 11.9375, the multiply makes 47.75, and the truncation happens ONCE AT THE END -- so the
// array is 47 bytes instead of 44.
//
// It was found by check_padding on LC_HkTlm_Payload_t: 162 bytes against NASA's 156, and
// 4 + 47 + 91 + 8 + 12 is exactly 162. A wrong array bound inside a struct that goes on the wire.
//
// THE COMPILER IS NOT THE PROBLEM, AND THIS CASE IS WHAT ESTABLISHED THAT. The answer below is
// 44, 88, 11, 3 -- C's answer exactly -- so HolyC's `/` IS integer division. What read 47 was
// check_padding's own evaluator, which ended in Python's `int(eval(...))` where `/` is TRUE
// division. The gate is fixed (tools/cfs/cfs_expr.py) and this case stays, because the next
// person to see a six-byte layout difference should be able to rule the language out in one run
// instead of reasoning about it.
I64 main()
{
  U8 a[(((176 + 15) / 16) * 4)]; // LC_HKWR_NUM_BYTES -- C says 44
  U8 b[(((176 + 7) / 8) * 4)];   // LC_HKAR_NUM_BYTES -- C says 88
  I64 q = (176 + 15) / 16;       // C says 11
  I64 r = 7 / 2;                 // C says 3
  // sizeof(a), sizeof(b), q and r, each as two hex digits, packed into one 64-bit answer.
  return (sizeof(a) << 24) | (sizeof(b) << 16) | (q << 8) | r;
}
