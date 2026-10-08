#!/usr/bin/env python3
"""ONE C integer-constant-expression evaluator, because two copies had the same bug.

WHY THIS FILE EXISTS. check_padding.eval_int and check_constants.expr_value both ended with

    int(eval(s))

and **Python's `/` is TRUE DIVISION**. In C, `((176 + 15) / 16) * 4` is `11 * 4` = 44. In Python it
is `11.9375 * 4` = 47.75, and the `int()` truncates once, at the END, giving 47.

THE BUG NEEDS A DIVISION FOLLOWED BY SOMETHING ELSE, which is why it hid for 109 sources. Nine
array bounds in the translation already divide -- `CFE_MISSION_ES_PERF_MAX_IDS / 8`,
`(OS_MAX_NUM_OPEN_FILES + 7) / 8`, `MM_INTERNAL_MAX_LOAD_DATA_SEG / 4` and six more -- and for a
bare `X / N` with non-negative operands `int(x/n)` and C's `x/n` agree exactly. Every one of them
was right by luck.

LC IS WHERE THE LUCK RAN OUT. NASA's bit-packed housekeeping arrays round UP to a whole number of
4-byte words:

    #define LC_HKWR_NUM_BYTES (((LC_MAX_WATCHPOINTS  + 15) / 16) * 4)   /* 44 */
    #define LC_HKAR_NUM_BYTES (((LC_MAX_ACTIONPOINTS +  7) /  8) * 4)   /* 88 */

so check_padding measured LC_HkTlm_Payload_t as 4 + 47 + 91 + 8 + 12 = 162 against NASA's 156 and
reported a layout mismatch -- in a struct that was CORRECT. The translation had NASA's expression,
character for character, and the gate could not evaluate it.

### AND THE FIRST DIAGNOSIS WAS WRONG IN A WAY WORTH RECORDING

The 6-byte difference and that arithmetic made it look like HolyC's `/` was floating point, which
would have been a serious language finding. It is not: a driven exec case,
tests/exec/cases/e_const_int_div.hc, asks the compiler directly and gets `2c580b03` -- 44, 88, 11
and 3, which is C's answer exactly. The compiler was right, NASA's expression was right, the
translation was right, and the measuring instrument was wrong. Checking the tool before believing
a finding about the language is the cheap half of that lesson.

### TRUNCATION DIRECTION

C truncates toward ZERO; Python's `//` FLOORS. They differ only when exactly one operand is
negative, which no size, count or array bound in cFS is -- and `evaluate()` refuses a negative
result rather than returning one, so a future expression that could tell the difference fails
loudly instead of being quietly floored.
"""
import re

# Only arithmetic, after every name has been substituted. No calls, no attributes, no names.
_SAFE = re.compile(r'^[\d\s()+\-*/%<>&|^~xXa-fA-F]+$')


def evaluate(expr):
    """The value of a C integer constant expression, or None if it is not one.

    `/` becomes `//` so the division is integer at the point C would make it integer, rather than
    at the end. The substitution is textual and deliberately does not touch `//` that is already
    there: a C constant expression cannot contain a comment by the time it reaches here, and
    doubling an existing `//` would turn it into a syntax error rather than a silent wrong answer.
    """
    s = expr.strip()
    if not s or not _SAFE.match(s):
        return None
    s = re.sub(r'(?<!/)/(?!/)', '//', s)
    try:
        v = eval(s, {"__builtins__": {}}, {})
    except Exception:
        return None
    if not isinstance(v, int):
        return None
    if v < 0:
        # Not "impossible" -- refused, because C truncates toward zero and // floors, so this is
        # the one case where the two disagree and this evaluator must not guess which was meant.
        return None
    return v


if __name__ == "__main__":
    # The driven control, and the first case is the one that found the bug.
    cases = [
        ("((176 + 15) / 16) * 4", 44),    # LC_HKWR_NUM_BYTES -- 47 with true division
        ("((176 + 7) / 8) * 4", 88),      # LC_HKAR_NUM_BYTES -- 91 with true division
        ("(176 + 15) / 16", 11),          # a bare quotient: both ways agree, which is why it hid
        ("7 / 2", 3),
        ("(64 + 7) / 8", 8),              # osapi-select.h's shape
        ("0x10 + 0x10", 32),
        ("8 * 4 / 2", 16),
        ("1 / 2", 0),                     # C gives 0; true division then int() also gives 0
        ("(1 / 2) * 4", 0),               # C gives 0; TRUE division gives 2 -- the same bug again
    ]
    bad = 0
    for e, want in cases:
        got = evaluate(e)
        if got != want:
            print("FAIL cfs-expr — %r gave %r, C gives %r" % (e, got, want))
            bad = 1
    # And it must REFUSE what it cannot evaluate, rather than returning something.
    for e in ["NAME + 1", "__import__('os')", "", "1 +", "-4 / 2"]:
        if evaluate(e) is not None:
            print("FAIL cfs-expr — %r should be refused, got %r" % (e, evaluate(e)))
            bad = 1
    if not bad:
        print("cfs-expr: %d C integer expressions evaluate as C does, including the "
              "divide-then-multiply shape that read 47 instead of 44; 5 refusals" % len(cases))
    raise SystemExit(bad)
