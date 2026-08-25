#!/bin/bash
# Smoke-test the bare-metal REPL (bootstrap/repl.elf) under QEMU: feed statements over the
# UART, compare the printed answers (one "0x..." line per statement) with the expected sequence.
# Covers cross-statement function calls (exe_addr indirection), redefinition, recursion, >8
# args, and a run of consecutive calls (catches per-statement stack drift).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

CALLS=64
input=""
expected=""
add_case() { # add_case "<statement>" [expected-hex-16-digits]
  input+="$1"$'\n'
  if [ $# -gt 1 ]; then expected+="$2"$'\n'; fi
}

add_case 'I64 Add(I64 a, I64 b) { return a + b; }'
add_case 'Add(1,1);' 0000000000000002
add_case 'Add(40,2);' 000000000000002a
add_case 'I64 F() { return 1; }'
add_case 'F();' 0000000000000001
add_case 'I64 F() { return 2; }'
add_case 'F();' 0000000000000002
add_case 'I64 Fib(I64 n) { if (n < 2) return n; return Fib(n-1) + Fib(n-2); }'
add_case 'Fib(10);' 0000000000000037
add_case 'I64 Get11th(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j, I64 k) { return k; }'
add_case 'Get11th(1,2,3,4,5,6,7,8,9,10,11);' 000000000000000b
# Codegen regressions found by execution probing (each was silently wrong or a no-op before).
add_case 'I64 Loop(I64 n) { I64 i, s = 0; for (i = 0; i < n; i++) s += i; return s; }'
add_case 'Loop(10);' 000000000000002d
add_case 'I64 Dec(I64 n) { while (n > 0) { n--; } return n; }'
add_case 'Dec(3);' 0000000000000000
add_case 'I64 Pre() { I64 i = 5; I64 j = ++i; return j * 10 + i; }'
add_case 'Pre();' 0000000000000042
add_case 'I64 Neg() { I32 v = -1; I64 w = -4; return (v == -1) + (w >> 1 == -2) + (!0) + (~0 == -1); }'
add_case 'Neg();' 0000000000000004
add_case 'I64 Arr() { I64 a[4]; a[0] = 1; a[1] = 2; a[2] = 3; return a[0] + a[1] + a[2]; }'
add_case 'Arr();' 0000000000000006
add_case 'I64 Ptr() { I64 x = 1; I64 *p = &x; *p = 7; return x; }'
add_case 'Ptr();' 0000000000000007
add_case 'I64 Chain() { I64 a, b; a = b = 3; return a + b; }'
add_case 'Chain();' 0000000000000006
add_case 'I64 Byte() { U8 b; b = 255; return b; }'
add_case 'Byte();' 00000000000000ff
add_case 'I64 Cnt() { static I64 c = 0; c++; return c; }'
add_case 'Cnt();' 0000000000000001
add_case 'Cnt();' 0000000000000002
# Top-level grammar, runtime, control flow, aggregates (all execution-checked).
add_case '"%d + %d = %d\n", 40, 2, 42;' 0000000000000000
add_case 'U8 *s = MAlloc(16); StrCpy(s, "abc"); StrLen(s);' 0000000000000003
add_case 'I64 Sw(I64 v) { switch (v) { case 1...5: return 99; case 7: return 70; default: return 0; } }'
add_case 'Sw(3);' 0000000000000063
add_case 'Sw(7);' 0000000000000046
add_case 'Sw(9);' 0000000000000000
add_case 'I64 Dw() { I64 i = 0; do { i++; } while (i < 5); return i; }'
add_case 'Dw();' 0000000000000005
add_case 'I64 Gt() { I64 x = 0; goto mid; x = 100; mid: x = x + 5; return x; }'
add_case 'Gt();' 0000000000000005
add_case 'I64 C2(I64 x) { if (x < 0) return 0; else if (x == 0) return 1; else return 3; }'
add_case 'C2(5) + C2(-1) + C2(0);' 0000000000000004
add_case 'class P { I64 x; I64 y; };'
add_case 'I64 Cl() { P p; p.x = 1; p.y = 2; return p.x + p.y; }'
add_case 'Cl();' 0000000000000003
add_case 'I64 M2() { I64 m[2][3]; I64 i, j, s = 0; for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) { m[i][j] = i + j; s += m[i][j]; } return s; }'
add_case 'M2();' 0000000000000009
add_case '#define TWICE(x) ((x) + (x))'
add_case 'TWICE(0x41) + 1;' 0000000000000083
add_case 'I64 gv = 40;'
add_case 'gv += 2; gv;' 000000000000002a
add_case "'AB';" 0000000000004241
add_case 'I64 Id(I64 v) { return v; } Id(Id(6));' 0000000000000006
add_case 'I64 Sl(U8 *t) { I64 n = 0; while (t[n]) n++; return n; } Sl("hello!");' 0000000000000006
# F64, casts, HolyC call forms, function pointers, globals in expressions.
add_case 'F64 fa = 7.5; I64 fn = 3; I64 fr = fa / 2.5 + fn * 1.5; fr;' 0000000000000007
add_case '2.5 * 4.0 + 1.0 > 10.0;' 0000000000000001
add_case 'I64 Half(F64 v) { return v / 2.0; } Half(9.0);' 0000000000000004
add_case '(U8)(-1) + (I8)200 + (I64)2.9;' 00000000000000c9
add_case 'I64 F42() { return 42; } F42 + 1;' 000000000000002b
add_case 'I64 Sq(I64 v) { return v * v; } I64 (*fp)(I64) = &Sq; fp(3);' 0000000000000009
add_case 'I64 ga = 3; I64 gb = 4; ga * gb + ga;' 000000000000000f
# Default arguments, unsigned arithmetic, try/catch/throw (incl. across a call and nested).
add_case 'I64 Dflt(I64 a, I64 b = 3) { return a + b; } Dflt(2) * 10 + Dflt(2, 4);' 0000000000000038
add_case 'U64 ubig = -1; (ubig > 0) + (ubig / 2 == 0x7FFFFFFFFFFFFFFF) + ((U32)(-1) >> 4 == 0x0FFFFFFF);' 0000000000000003
add_case 'I64 Boom() { throw(7); return 1; }'
add_case 'I64 Try2() { try { Boom(); return 99; } catch { return except_ch + 100; } }'
add_case 'Try2();' 000000000000006b
add_case 'I64 Try5() { try { try { throw(1); } catch { throw(2); } } catch { return except_ch * 10; } return 0; } Try5();' 0000000000000014
add_case 'I64 Try3() { try { return 5; } catch { return 6; } } Try3() + Try2() - 107;' 0000000000000005
for ((i = 1; i <= CALLS; i++)); do
  add_case "Add($i,1);" "$(printf '%016x' $((i + 1)))"
done

# Sentinel: the REPL never exits (it spins on the UART after EOF), so stop QEMU as soon as
# the last answer is printed; the timeout only bounds a hung/crashed REPL.
add_case '4919;' 0000000000001337

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
printf '%s' "$input" | $TIMEOUT_CMD 60 "$QEMU" -M virt -bios none -kernel "$BOOT/repl.elf" -nographic >"$log" 2>&1 &
qpid=$!
for ((t = 0; t < 600; t++)); do
  if grep -q '^0x0000000000001337' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
out="$(tr -d '\r' <"$log")"
got="$(echo "$out" | grep -o '^0x[0-9a-f]\{16\}' | sed 's/^0x//' || true)"

if [ "$got" != "${expected%$'\n'}" ]; then
  echo "FAIL REPL smoke — answer sequence mismatch" >&2
  diff <(echo "${expected%$'\n'}") <(echo "$got") >&2 || true
  echo "--- REPL transcript ---" >&2
  echo "$out" >&2
  exit 1
fi
if ! echo "$out" | grep -q '^40 + 2 = 42$'; then
  echo "FAIL REPL smoke — Print output missing (expected '40 + 2 = 42')" >&2
  echo "$out" >&2
  exit 1
fi
n=$(echo "$got" | wc -l | tr -d ' ')
echo "OK   REPL: define/call, redefine, Fib(10), 11 args, loops/++/+=/arrays/pointers/static, Print/strings, switch/do/goto, class, 2-D, macros, F64, casts, fn ptrs, defaults, unsigned, try/catch, $CALLS calls ($n answers)"
echo "REPL smoke: OK"
