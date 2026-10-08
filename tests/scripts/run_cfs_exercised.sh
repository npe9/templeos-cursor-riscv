#!/bin/bash
# WHICH OF AN APP'S NASA FUNCTIONS DOES THE EXERCISE ACTUALLY RUN?
#
# The existing gates answer two different questions. check_coverage asks "is every NASA function
# PRESENT in the translation"; the differential asks "do the two halves AGREE on what they
# printed". NEITHER asks "was this function ever CALLED" -- and a function can be translated,
# gated, byte-compared and never executed, with the transcript reading exactly the same either
# way. That is the blind spot docs/ records as a gate passing on what it cannot see, and it is
# the one this script closes.
#
# It builds the C half with gcov instrumentation, runs it, and reads per-function execution out of
# the line counts. MEASURING THE C HALF IS THE RIGHT CHOICE: the HolyC half is byte-identical to
# it, so a function the C half never entered was never entered on either side.
#
#     tests/scripts/run_cfs_exercised.sh LC        # one app
#     tests/scripts/run_cfs_exercised.sh           # every gated app
#
# IT IS NOT IN THE SMOKE, on purpose: a --coverage build of the whole oracle plus gcov over 120
# objects takes longer than the differential itself, and the number only moves when an exercise
# block is added. Run it when one is.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# Reuse the smoke's OWN variable block (its lines 11..214) so the include path and the source list
# cannot drift from the real gate's. Line 10 sets ROOT from $0 and is skipped for that reason.
eval "$(sed -n '11,214p' tests/scripts/run_cfs_xlat_smoke.sh | sed '/^for /,/^done$/d')"

APPS=${*:-MD MM CS LC}
for APP in $APPS; do
  OUT="$ROOT/build/exercised/$APP"
  rm -rf "$OUT"; mkdir -p "$OUT"
  (
    cd "$OUT"
    # shellcheck disable=SC2086
    "${HOSTCC:-cc}" -O0 -w --coverage $INC -I"$ROOT/tests/cfs" -o ref \
       "$ROOT/tests/cfs/oracle_ccsdspri.c" $SRC_C "$GENDIR/cfe_configid_nametable.c" \
       "$GENDIR/cfe_target_config.c" "$GENDIR/cfe_platformcfg_tables.c"
    ./ref > ref.txt
    for f in "$ROOT/vendor/$APP"/fsw/src/*.c; do
      b=$(basename "$f" .c)
      # clang names the data file after the OUTPUT BINARY, not the source: ref-lc_watch.gcda.
      # The first version looked for lc_watch.gcda, found nothing, and reported "0 of 56
      # functions run" -- which the transcript immediately contradicted. The python below now
      # refuses to print a number when it parsed no records.
      [ -f "ref-$b.gcda" ] || continue
      gcov -f -o . "ref-$b.gcda" >/dev/null 2>&1 || true
    done
    python3 "$ROOT/tools/cfs/exercised_count.py" "$APP"
  )
done
