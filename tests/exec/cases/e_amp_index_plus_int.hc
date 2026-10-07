// ADDING AN INTEGER TO `&array[i]` SCALES BY EIGHT, NOT BY THE ELEMENT SIZE.
//
// A SECOND SURFACE OF LIMIT #4, not a new limit. docs/HOLYC_STRUCT_LIMITS.md #4 records that
// SUBSCRIPTING a parenthesised `&array[N]` falls back to an 8-byte element because the `&` site
// throws away the container symbol and with it PtrElemInfo. The same fallback applies to
// ARITHMETIC on that expression, and it is the form a reader is least likely to suspect:
//
//     W garr[8];              // W is 56 bytes
//     garr + 1                ->  +56 bytes    correct
//     &garr[1]                ->  +56 bytes    correct
//     p = garr; p + 1         ->  +56 bytes    correct
//     &garr[0] + 1            ->  +8 bytes     WRONG, and silently so
//     &garr[0] + 7            ->  +56 bytes    WRONG, and indistinguishable from correct
//
// THE LAST LINE IS WHY THIS NEEDS ITS OWN CASE. With N a multiple of sizeof/8 the wrong answer
// is a VALID element address, so the defect produces a plausible pointer rather than a fault --
// and the first probe written for it used N=3 against a 56-byte element, where 3 bytes and 24
// bytes both land inside element 0 and the two explanations are the same number. Only an N and
// a size whose product crosses an element boundary tell "one byte per unit" from "eight".
//
// FOUND IN THE CS EXERCISE, from a transcript diff of ONE LINE. `CS_GetTableTypeAsString` has a
// `default:` arm that CS's own code cannot reach, because every caller passes
// `&CS_AppData.Tbl[n]` for n in 0..5; the exercise reached it with `&CS_AppData.Tbl[0] +
// CS_NUM_TABLES`. CS_TableWrapper_t is 112 bytes, so 6 * 8 = 48 bytes is still inside element 0,
// `CS_GetTableId` returned 0 and the line read "cFE Core" where NASA's C read "Undef". The
// exercise now writes `CS_AppData.Tbl + CS_NUM_TABLES`, which is right in both.
//
// THE WORKAROUNDS, both already required by #4: name the array without the `&`/subscript, or
// take the base into a local pointer variable first.
I64 main();

// 56 bytes: not a power of two, and NOT a multiple of 16, so an 8-byte step and a 56-byte step
// disagree at every N from 1 to 6.
class W
{
  U64 a;
  U64 b;
  U64 c;
  U64 d;
  U64 e;
  U64 f;
  U64 g;
};

class G
{
  W t[6];
};

W garr[8];
G g;
W *gp;

// Every answer is in BYTES -- a pointer DIFFERENCE scales too, and would hide the thing under
// test behind a second application of the same rule.
I64 bytes(W *p, W *base)
{
  return p(U8 *) - base(U8 *);
}

// EACH FORM GETS ITS OWN FUNCTION, and the result is EIGHT bytes wide on purpose. The first
// draft packed nine one-byte answers with eight shifts -- seventy-two bits into sixty-four -- and
// the top one fell off the end. The value still looked plausible, and reading it as nine fields
// said a CORRECT spelling (`gp = garr; p = gp + 1`) returned 8. Two probes were written to chase
// that before the arithmetic was checked, and a third (zz_pa3, deleted) proved there was nothing
// there: a `&garr[1]` in an earlier function does NOT leave an 8-byte pointee behind. The three
// correct spellings are therefore folded into ONE byte below, so the whole answer fits.
I64 f_array_plus()
{
  W *p = garr + 1;
  return bytes(p, garr);
}

I64 f_amp_index()
{
  W *p = &garr[1];
  return bytes(p, garr);
}

I64 f_var_plus()
{
  W *p;
  gp = garr;
  p = gp + 1;
  return bytes(p, garr);
}

I64 f_amp_index0_plus_file()
{
  W *p = &garr[0] + 1;
  return bytes(p, garr);
}

I64 f_amp_index0_plus_member()
{
  W *p = &g.t[0] + 1;
  return bytes(p, g.t);
}

I64 f_amp_index0_plus_local()
{
  W la[6];
  W *p = &la[0] + 1;
  return bytes(p, la);
}

I64 f_amp_index0_plus_ptr()
{
  W *p;
  gp = garr;
  p = &gp[0] + 1;
  return bytes(p, garr);
}

// N = 7 lands exactly on element 1 under an 8-byte step, so the wrong answer is a VALID element
// address. Divided by 56 because the correct answer, 392, does not fit a byte: 1 today, 7 when
// fixed.
I64 f_amp_index0_plus_seven()
{
  W *p = &garr[0] + 7;
  return bytes(p, garr) / 56;
}

I64 main()
{
  I64 r;

  // Byte 7: the three CORRECT spellings, folded. 7 always.
  r = (f_array_plus() == 56) | (f_amp_index() == 56) << 1 | (f_var_plus() == 56) << 2;
  // Bytes 6..3: the defect, four containers deep -- a file-scope array, a class member array, a
  // local array, and through a pointer. 8 today, 56 when fixed.
  r = r << 8 | f_amp_index0_plus_file();
  r = r << 8 | f_amp_index0_plus_member();
  r = r << 8 | f_amp_index0_plus_local();
  r = r << 8 | f_amp_index0_plus_ptr();
  // Byte 2: the step is EIGHT, not one. 1 today, 7 when fixed.
  r = r << 8 | f_amp_index0_plus_seven();
  // Byte 1: sizeof(W) is 56, so the two scalings are distinguishable at all. 0x38 always.
  r = r << 8 | sizeof(W);
  // Byte 0: and `gp += 1` is a THIRD answer -- ONE byte, neither 8 nor 56. Compound assignment to
  // a pointer does not scale at all. Measured here because the probe that found it was already
  // running; it is a sibling of the form above and not a separate limit.
  gp = garr;
  gp += 1;
  r = r << 8 | bytes(gp, garr);
  return r;
}
