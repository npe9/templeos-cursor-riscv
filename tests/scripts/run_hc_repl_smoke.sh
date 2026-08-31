#!/usr/bin/env bash
# Smoke: HolyC AOT REPL — Dir/Src + guest JIT covering core repl-smoke language.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
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

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT/bootstrap/hc_repl" all

# Mandate: Mac-AOT guest has no 0x87001xxx host slots and does not link worry_dream/holy_rt.
if grep -RIn --include='*.hc' -E '0x87001[0-9A-Fa-f]{3}' "$ROOT/bootstrap/hc_repl" \
  | grep -v -E 'No 0x87001|no 0x87001'; then
  echo "FAIL hc-repl-smoke — HolyC sources still reference host slots" >&2
  exit 1
fi
if command -v "${CROSS_NM:-riscv64-unknown-elf-nm}" >/dev/null 2>&1; then
  NM="${CROSS_NM:-riscv64-unknown-elf-nm}"
elif command -v nm >/dev/null 2>&1; then
  NM=nm
else
  NM=""
fi
if [ -n "$NM" ] && [ -f "$ELF" ]; then
  if "$NM" "$ELF" 2>/dev/null | grep -Ei 'worry_dream|holy_rt|RuntimeRegister'; then
    echo "FAIL hc-repl-smoke — ELF links C runtime symbols" >&2
    exit 1
  fi
fi

# Core language cases from tests/scripts/run_repl_smoke.sh (HolyC guest JIT path).
input=""
expected=""
add_case() {
  input+="$1"$'\n'
  if [ $# -gt 1 ]; then expected+="$2"$'\n'; fi
}

add_case 'Dir;'
add_case 'Src("hello.hc");'
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
add_case 'I64 Loop(I64 n) { I64 i, s = 0; for (i = 0; i < n; i++) s += i; return s; }'
add_case 'Loop(10);' 000000000000002d
add_case 'I64 Dec(I64 n) { while (n > 0) { n--; } return n; }'
add_case 'Dec(3);' 0000000000000000
add_case 'I64 Pre() { I64 i = 5; I64 j = ++i; return j * 10 + i; }'
add_case 'Pre();' 0000000000000042
add_case 'I64 Arr() { I64 a[4]; a[0] = 1; a[1] = 2; a[2] = 3; return a[0] + a[1] + a[2]; }'
add_case 'Arr();' 0000000000000006
add_case 'I64 Ptr() { I64 x = 1; I64 *p = &x; *p = 7; return x; }'
add_case 'Ptr();' 0000000000000007
add_case 'I64 Chain() { I64 a, b; a = b = 3; return a + b; }'
add_case 'Chain();' 0000000000000006
add_case 'I64 Byte() { U8 b; b = 255; return b; }'
add_case 'Byte();' 00000000000000ff
add_case 'I64 Dw() { I64 i = 0; do { i++; } while (i < 5); return i; }'
add_case 'Dw();' 0000000000000005
add_case 'class P { I64 x; I64 y; };'
add_case 'I64 Cl() { P p; p.x = 1; p.y = 2; return p.x + p.y; }'
add_case 'Cl();' 0000000000000003
add_case 'I64 gv = 40;'
add_case 'gv += 2;' 000000000000002a
add_case 'gv;' 000000000000002a
add_case 'I64 Id(I64 v) { return v; } Id(Id(6));' 0000000000000006
add_case 'I64 Sl(U8 *t) { I64 n = 0; while (t[n]) n++; return n; } Sl("hello!");' 0000000000000006
add_case 'Print("jit-print");'
add_case 'Atoi("123");' 000000000000007b
add_case 'U8 *s = MAlloc(16);'
add_case 'StrCpy(s, "abc");'
add_case 'StrLen(s);' 0000000000000003

log="$(mktemp)"
# shellcheck disable=SC2086
printf '%s' "$input" | $TIMEOUT_CMD 90 "$QEMU" -M virt -bios none -kernel "$ELF" -nographic \
  >"$log" 2>&1 || true

fail=0
need() {
  if ! grep -qF "$1" "$log"; then
    echo "FAIL hc-repl-smoke — missing: $1" >&2
    fail=1
  fi
}

need "HolyC AOT REPL"
need "> "
need "Dir: "
need "hello.hc"
need "Hello from HolyC memfs"
need "jit-print"

# Compare ans= hex sequence (non-void statements only)
mapfile -t got_ans < <(grep -oE 'ans=0x[0-9a-fA-F]+' "$log" | sed 's/ans=0x//' | tr 'A-F' 'a-f')
mapfile -t exp_ans < <(printf '%s' "$expected")
if [ "${#got_ans[@]}" -lt "${#exp_ans[@]}" ]; then
  echo "FAIL hc-repl-smoke — got ${#got_ans[@]} ans lines, expected ${#exp_ans[@]}" >&2
  fail=1
else
  i=0
  while [ "$i" -lt "${#exp_ans[@]}" ]; do
    g="${got_ans[$i]}"
    # strip leading zeros for compare flexibility, but prefer exact 16-digit match
    e="${exp_ans[$i]}"
    if [ "$g" != "$e" ]; then
      # allow shorter hex without leading zeros in g
      g_norm=$(printf '%016x' "0x$g" 2>/dev/null || echo "$g")
      if [ "$g_norm" != "$e" ] && [ "$g" != "$e" ]; then
        echo "FAIL hc-repl-smoke — ans[$i]: got $g want $e" >&2
        fail=1
      fi
    fi
    i=$((i + 1))
  done
fi

if [ "$fail" -ne 0 ]; then
  echo "---- ans lines ----" >&2
  grep -E 'ans=|JIT:' "$log" | head -50 >&2
  echo "---- log tail ----" >&2
  tail -20 "$log" >&2
  rm -f "$log"
  exit 1
fi

echo "HolyC AOT REPL smoke: OK (${#exp_ans[@]} ans oracles + Dir/Src/Print)"
rm -f "$log"
exit 0
