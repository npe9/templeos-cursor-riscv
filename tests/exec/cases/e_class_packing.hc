// HolyC classes are FULLY PACKED: no inter-member padding, no alignment, no tail padding.
//
// This is authentic TempleOS -- the kernel's own structures depend on it -- and it is NOT what
// a C compiler does. It is pinned here because the NASA cFS translation reasons about it:
// tools/cfs/check_padding.py computes each translated class's layout from a model that says
// "sum the member sizes", and compares that against the REAL offsets of NASA's struct as
// reported by the host C compiler. Where C pads, the translation has to carry the padding
// explicitly or the two layouts differ by a few bytes with nothing to notice.
//
// cFE's CFE_FS_FileWriteMetaData_t is the first struct in the translation where that happens:
//
//     volatile bool IsPending;                 1 byte  at 0
//     char FileName[CFE_MISSION_MAX_PATH_LEN]; 64      at 1, ending at 65
//     CFE_FS_SubType_Enum_t FileSubType;       uint32  at 68 in C -- THREE BYTES OF PADDING
//
// C aligns the uint32 to a multiple of 4; HolyC puts it at 65. Measured: sizeof 117 against
// NASA's 120, and every member from FileSubType on shifted by 3.
//
// If the model in check_padding.py is ever wrong, it is wrong in the direction of silently
// approving a layout mismatch, so the model's premise is a gate of its own. These are the exact
// shapes it relies on: a narrow member before a wider one, a wider member before a narrow one
// (tail padding), an array before a wider scalar, and a nested class.
class Narrow
{
  U8 a;
  U32 b;      // C: offset 4.  HolyC: offset 1.
};

class Tail
{
  U32 a;
  U8 b;       // C: sizeof 8 (tail padding to align 4). HolyC: sizeof 5.
};

class AfterArray
{
  Bool flag;      // 1 byte
  U8 name[64];    // 1..64
  U32 subtype;    // C: 68.  HolyC: 65.  This is the cFE case above.
  U8 desc[32];
  U0 (*on_event)();
};

class Nest
{
  U8 lead;
  Narrow inner;   // a packed class nests packed: no alignment bump at the member either
  U8 trail;
};

I64 main()
{
  Narrow n;
  Tail t;
  AfterArray a;
  Nest z;
  I64 r = 0;

  // Bool is one byte, which is what makes the cFE case a 3-byte shift and not a 7-byte one.
  r = r * 10 + sizeof(Bool);

  r = r * 10 + sizeof(Narrow);                               // 5
  r = r * 10 + ((U8 *)&n.b - (U8 *)&n.a);                    // 1

  r = r * 10 + sizeof(Tail);                                 // 5
  r = r * 10 + ((U8 *)&t.b - (U8 *)&t.a);                    // 4

  r = r * 1000 + sizeof(AfterArray);                         // 1 + 64 + 4 + 32 + 8 = 109
  r = r * 100 + ((U8 *)&a.subtype - (U8 *)&a.flag);          // 65
  r = r * 1000 + ((U8 *)&a.on_event - (U8 *)&a.flag);        // 101

  r = r * 10 + sizeof(Nest);                                 // 1 + 5 + 1 = 7
  r = r * 10 + ((U8 *)&z.inner - (U8 *)&z.lead);             // 1
  r = r * 10 + ((U8 *)&z.trail - (U8 *)&z.lead);             // 6
  return r;
}
