#!/bin/bash
# TempleOS / HolyC language compliance — wrapper around the manifest-driven suite.
# Historical inline tests live under tests/holyc/compliance/*.hc (manifest_syntax.tsv).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║         TempleOS / HolyC compliance (expanded suite)                   ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Syntax matrix:    tests/holyc/compliance/manifest_syntax.tsv"
echo "TempleOS tree:    tests/holyc/compliance/manifest_templeos_tree.tsv"
echo "Runner:           tests/scripts/run_holyc_compliance.sh"
echo ""

exec "$SCRIPT_DIR/run_holyc_compliance.sh" --suite all "$@"
