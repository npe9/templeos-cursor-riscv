/* tests/host/relax_test.c — unit test for host/backend/relax.c (monotone-growth relaxation).
 * Models an x86-JCC-like arch: class 0 = rel8 (2 bytes, reaches [-128,127]); class 1 = rel32
 * (6 bytes, reaches anything). Builds on the host with plain cc (no ISA toolchain needed):
 *   make relax-test
 */
#include "../../host/backend/relax.h"
#include <stdio.h>
#include <string.h>

static int  jcc_size(uint8_t k, uint8_t c) { (void)k; return c == 0 ? 2 : 6; }
static uint8_t jcc_max(uint8_t k)          { (void)k; return 1; }
static int  jcc_reaches(uint8_t k, uint8_t c, int64_t d) {
  (void)k;
  return c == 0 ? (d >= -128 && d <= 127) : 1;   /* class 1 (rel32) reaches everything */
}
static const RelaxArch JCC = { jcc_size, jcc_max, jcc_reaches };

static int fails;
#define CHECK(cond, msg) do { if (!(cond)) { printf("  FAIL: %s\n", msg); fails++; } } while (0)

enum { B /*branch*/, F /*fixed*/, L /*label*/ };
static RelaxFrag mk(int t, int kind, int32_t label, int32_t len) {
  RelaxFrag f; memset(&f, 0, sizeof f);
  f.type = (uint8_t)(t == B ? RELAX_BRANCH : t == F ? RELAX_FIXED : RELAX_LABEL);
  f.kind = (uint8_t)kind; f.label_id = label; f.fixed_len = len;
  return f;
}

int main(void) {
  /* --- 1. a short branch stays short (target within rel8) --- */
  {
    RelaxFrag fr[] = { mk(B,0,1,0), mk(F,0,0,10), mk(L,0,1,0) };
    int p = relax_run(fr, 3, &JCC);
    CHECK(p >= 1, "short: converged");
    CHECK(fr[0].size_class == 0, "short: branch stays rel8");
    CHECK(fr[0].offset == 0 && fr[2].offset == 12, "short: offsets (2 + 10)");
  }

  /* --- 2. a far branch must grow to rel32 --- */
  {
    RelaxFrag fr[] = { mk(B,0,1,0), mk(F,0,0,300), mk(L,0,1,0) };
    int p = relax_run(fr, 3, &JCC);
    CHECK(p >= 1, "far: converged");
    CHECK(fr[0].size_class == 1, "far: branch grows to rel32");
    CHECK(fr[2].offset == 306, "far: label after 6-byte branch + 300 fixed");
  }

  /* --- 3. CASCADE: b2's growth pushes b1's target out of rel8, forcing b1 to grow too.
   *     Single-pass relaxation gets this wrong (it would leave b1 short); the fixed point
   *     catches the second-order growth. Layout:
   *       [0] b1 -> L2 (target starts at offset 127 = exactly rel8-reachable)
   *       [1] b2 -> L3 (far -> grows +4, which shifts L2 to 131 > 127 -> b1 must grow)
   *       [2] FIXED 123   [3] L2   [4] FIXED 300   [5] L3                                   */
  {
    RelaxFrag fr[] = { mk(B,0,2,0), mk(B,0,3,0), mk(F,0,0,123), mk(L,0,2,0), mk(F,0,0,300), mk(L,0,3,0) };
    int p = relax_run(fr, 6, &JCC);
    CHECK(p >= 1, "cascade: converged");
    CHECK(fr[0].size_class == 1, "cascade: b1 grew (second-order, via b2's growth)");
    CHECK(fr[1].size_class == 1, "cascade: b2 grew (direct)");
    /* final: b1(6) b2(6) fixed(123) L2@135 fixed(300) L3@435 */
    CHECK(fr[3].offset == 135, "cascade: L2 offset");
    CHECK(fr[5].offset == 435, "cascade: L3 offset");
    /* b1 reaches L2: disp 135 needs rel32; b2 reaches L3: disp 429 needs rel32 — both consistent */
  }

  /* --- 4. branch to a missing label fails cleanly --- */
  {
    RelaxFrag fr[] = { mk(B,0,9,0), mk(L,0,1,0) };
    CHECK(relax_run(fr, 2, &JCC) == -1, "missing label: returns -1");
  }

  /* --- 5. no fragments is a valid no-op --- */
  CHECK(relax_run(0, 0, &JCC) >= 1, "empty: converges trivially");

  if (fails) { printf("relax-test: %d FAILED\n", fails); return 1; }
  printf("relax-test: OK (short, far, cascade, missing-label, empty)\n");
  return 0;
}
