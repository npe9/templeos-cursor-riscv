/* Host unit test for bootstrap/holy_misaligned.h — the M-mode misaligned load/store emulator.
 * QEMU never raises mcause 4/6 for a plain misaligned access, so the decoder and the byte-wise
 * execution are proven here, on the Mac, against a fake trap frame and a byte buffer; the board
 * proves the hook. Encodings are from riscv64-unknown-elf-as (see the commit) and from the
 * HiFive Unmatched's own fault (0x00053503 = ld a0,0(a0), mtval 4 mod 8). */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "../../bootstrap/holy_misaligned.h"

static int fails;
#define CHECK(c) do { if (!(c)) { fails++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); } } while (0)

static unsigned char mem[64] __attribute__((aligned(16)));
static unsigned short code[4] __attribute__((aligned(4)));
static long long frame[32];

static int run(unsigned int insn, int len, unsigned long addr) {
  code[0] = (unsigned short)insn; code[1] = (unsigned short)(insn >> 16);
  (void)len;
  return HolyMisalignedEmu(frame, (unsigned long)code, addr);
}

int main(void) {
  HolyMisInsn d;
  int i;
  /* --- decoder --- */
  CHECK(HolyMisDecode(0x00053503, &d) && !d.is_store && !d.is_fp && d.width == 8 && d.reg == 10 && d.len == 4);
  CHECK(HolyMisDecode(0x0644a283, &d) && !d.is_store && d.width == 4 && d.sign_ext && d.reg == 5);
  CHECK(HolyMisDecode(0x00275683, &d) && d.width == 2 && !d.sign_ext && d.reg == 13);
  CHECK(HolyMisDecode(0xfff80783, &d) && d.width == 1 && d.sign_ext && d.reg == 15);
  CHECK(HolyMisDecode(0x00b63423, &d) && d.is_store && d.width == 8 && d.reg == 11);      /* sd a1,8(a2) */
  CHECK(HolyMisDecode(0x00452607, &d) && d.is_fp && !d.is_store && d.width == 4 && d.reg == 12);
  CHECK(HolyMisDecode(0x6108, &d) && d.width == 8 && d.reg == 10 && d.len == 2);           /* c.ld a0,0(a0) */
  CHECK(HolyMisDecode(0xe60c, &d) && d.is_store && d.width == 8 && d.reg == 11);           /* c.sd a1,8(a2) */
  CHECK(HolyMisDecode(0x2908, &d) && d.is_fp && d.width == 8 && d.reg == 10);              /* c.fld fa0 */
  CHECK(HolyMisDecode(0xad0c, &d) && d.is_fp && d.is_store && d.width == 8 && d.reg == 11);/* c.fsd fa1 */
  CHECK(HolyMisDecode(0x43d8, &d) && d.width == 4 && d.sign_ext && d.reg == 14);           /* c.lw a4 */
  CHECK(HolyMisDecode(0xc188, &d) && d.is_store && d.width == 4 && d.reg == 10);           /* c.sw a0 */
  CHECK(HolyMisDecode(0x6542, &d) && d.width == 8 && d.reg == 10);                         /* c.ldsp a0 */
  CHECK(HolyMisDecode(0xec2e, &d) && d.is_store && d.width == 8 && d.reg == 11);           /* c.sdsp a1 */
  CHECK(!HolyMisDecode(0x00b6352f, &d));                                                   /* amoadd.d: decline */
  CHECK(!HolyMisDecode(0x00000013, &d));                                                   /* addi: decline */
  CHECK(!HolyMisDecode(0x0001, &d));                                                       /* c.nop: decline */

  /* --- execution: the board's fault, ld a0 from a 4-aligned address --- */
  for (i = 0; i < 64; i++) mem[i] = (unsigned char)(0x10 + i);
  memset(frame, 0, sizeof frame);
  CHECK(run(0x00053503, 4, (unsigned long)&mem[4]) == 4);
  CHECK((unsigned long long)frame[10] == 0x1b1a191817161514ULL);
  /* sign extension: lw of 0xff.. and lb of 0x80.. */
  mem[5] = 0xff; mem[6] = 0xff; mem[7] = 0xff; mem[4] = 0xfe;
  CHECK(run(0x0644a283, 4, (unsigned long)&mem[4]) == 4 && frame[5] == -2);
  mem[9] = 0x80; frame[15] = 1;
  CHECK(run(0xfff80783, 4, (unsigned long)&mem[9]) == 4 && frame[15] == -128);
  /* lhu: no sign extension */
  mem[11] = 0x34; mem[12] = 0xf2;
  CHECK(run(0x00275683, 4, (unsigned long)&mem[11]) == 4 && frame[13] == 0xf234);
  /* store: sd a1 -> 8 bytes at an odd address, byte order little-endian */
  frame[11] = 0x1122334455667788LL;
  CHECK(run(0x00b63423, 4, (unsigned long)&mem[17]) == 4);
  CHECK(mem[17] == 0x88 && mem[24] == 0x11 && mem[16] == 0x20 && mem[25] == 0x29);   /* neighbours untouched */
  /* x0 as store data writes zeros; x0 as load target writes nothing */
  CHECK(run(0x00063423, 4, (unsigned long)&mem[33]) == 4 && mem[33] == 0 && mem[40] == 0);  /* sd x0,8(a2) */
  frame[0] = 0x55; CHECK(run(0x00053003, 4, (unsigned long)&mem[4]) == 4 && frame[0] == 0x55); /* ld x0 */
  /* compressed load/store */
  mem[44] = 0xaa; mem[45] = 0xbb; mem[46] = 0xcc; mem[47] = 0xdd; mem[48] = 0xee; mem[49] = 0xff; mem[50] = 0x01; mem[51] = 0x02;
  CHECK(run(0x6188, 2, (unsigned long)&mem[44]) == 2 && (unsigned long long)frame[10] == 0x0201ffeeddccbbaaULL);
  frame[12] = 0x0123456789abcdefLL;
  CHECK(run(0xe690, 2, (unsigned long)&mem[53]) == 2 && mem[53] == 0xef && mem[60] == 0x01);
  /* FP: flw NaN-boxes, fld/fsd round-trip through the fake FP file */
  CHECK(run(0x00452607, 4, (unsigned long)&mem[5]) == 4 && (holy_mis_host_f[12] >> 32) == 0xffffffffULL);
  holy_mis_host_f[11] = 0xdeadbeefcafef00dULL;
  CHECK(run(0xad0c, 2, (unsigned long)&mem[1]) == 2 && mem[1] == 0x0d && mem[8] == 0xde);
  CHECK(run(0x2188, 2, (unsigned long)&mem[1]) == 2 && holy_mis_host_f[10] == 0xdeadbeefcafef00dULL);
  /* sp as an integer destination is declined (not in the frame) */
  CHECK(run(0x00053103, 4, (unsigned long)&mem[4]) == 0);   /* ld sp,0(a0) */
  /* AMO declined */
  CHECK(run(0x00b6352f, 4, (unsigned long)&mem[4]) == 0);
  CHECK(holy_mis_count == 12);

  printf(fails ? "misaligned-emu-test: %d FAIL\n" : "misaligned-emu-test: PASS (%d checks)\n", fails ? fails : 36);
  return fails ? 1 : 0;
}
