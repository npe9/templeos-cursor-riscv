#!/usr/bin/env bash
# Host path-namespace smoke: A:/ + ::/ includes (tos fallback), __DIR__ → ::/… (tos stripped).
# See docs/PATHS.md (G28).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOLYC="${HOLYC:-$ROOT/holyc-riscv}"
T="$(mktemp -d "${TMPDIR:-/tmp}/path-ns.XXXXXX")"
trap 'rm -rf "$T"' EXIT

if [[ ! -x "$HOLYC" ]]; then
  make -C "$ROOT" holyc-riscv
fi

fail() { echo "FAIL path-namespace: $*" >&2; exit 1; }

# --- A:/Kernel include (drive letter) ---
cat >"$T/inc_a.hc" <<'EOF'
#include "A:/Demo/Directives.HC"
I64 main() { return 0; }
EOF
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$HOLYC" "$T/inc_a.hc" -o "$T/inc_a.bin" >/dev/null 2>"$T/inc_a.err"; then
  # Directives.HC may need more context; opening the file is enough — accept
  # undefined-symbol errors but not "Unable to open include".
  if grep -q 'Unable to open include' "$T/inc_a.err"; then
    cat "$T/inc_a.err" >&2
    fail "A:/Demo include not found"
  fi
fi

# --- ::/Apps → tos/Apps ---
cat >"$T/inc_apps.hc" <<'EOF'
#include "::/Apps/Span/Span.HH"
I64 main() { return 0; }
EOF
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$HOLYC" "$T/inc_apps.hc" -o "$T/inc_apps.bin" >/dev/null 2>"$T/inc_apps.err"; then
  if grep -q 'Unable to open include' "$T/inc_apps.err"; then
    cat "$T/inc_apps.err" >&2
    fail "::/Apps include (tos fallback) not found"
  fi
fi

# --- __DIR__ / __FILE__ StreamDir shape under tos/ (host tos/ → guest ::/) ---
mkdir -p "$ROOT/tos/_path_ns_probe"
cat >"$ROOT/tos/_path_ns_probe/dir_probe.hc" <<'EOF'
U8 *d=__DIR__;
U8 *f=__FILE__;
I64 main(){return 0;}
EOF
cleanup_probe() { rm -rf "$ROOT/tos/_path_ns_probe"; }
trap 'cleanup_probe; rm -rf "$T"' EXIT

HOLYC_INCLUDE_ROOT="$ROOT" "$HOLYC" "$ROOT/tos/_path_ns_probe/dir_probe.hc" -o "$T/dir_probe.bin" >/dev/null 2>"$T/dir_probe.err" \
  || { cat "$T/dir_probe.err" >&2; fail "dir_probe compile"; }

python3 - <<PY
import sys
data=open("$T/dir_probe.bin","rb").read()
text=data.decode("latin1", errors="ignore")
# expect ::/_path_ns_probe (tos/ stripped to ISO / StreamDir shape)
if "::/_path_ns_probe" not in text:
    print("missing ::/_path_ns_probe in blob", file=sys.stderr)
    hits=[repr(s) for s in text.split("\\0") if "path" in s or "tos" in s or s.startswith("/") or ":" in s[:3]]
    print("hits:", hits[:20], file=sys.stderr)
    sys.exit(1)
# must not keep host layout /tos/ in __DIR__
if "/tos/_path_ns_probe" in text:
    print("unexpected /tos/ retained in __DIR__", file=sys.stderr)
    sys.exit(1)
print("path-namespace host: A:/ + ::/Apps + __DIR__ ::/ (tos-stripped) OK")
PY

echo "PASS path-namespace-smoke"
