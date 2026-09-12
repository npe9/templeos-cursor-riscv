// Soft tip rung C of the stock DocInit_RV Soft Cmp bisect ladder.
// Rung B + the stock DefineLoad/DefineLstLoad calls verbatim: long adjacent
// string literals carrying embedded NULs ("TX\0CR\0...") are the first Soft Cmp
// lexer surface the guest DocInit_RV variant never exercises.
#include "A:/Compiler/DolDocDefines.HC"
#define HTT_DEFINE_STR 0x4
#define DHT_DOC_CMD 1
import I64 DefineLoad(U8 *dname, U8 *st);
import I64 DefineLstLoad(U8 *dname, U8 *lst);
import I64 HashFind(U8 *needle, I64 table, I64 mask);
import I64 HashTableNew(I64 size, I64 mem_task = 0);
U0 DocInitRungC()
{
  if (doldoc.hash && HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return;
  if (Fs && Fs->hash_table) {
    if (!HashFind("FM_PICK_FILE", Fs->hash_table, HTT_DEFINE_STR))
      DefineLoad("FM_PICK_FILE", "1");
    if (!HashFind("FM_PICK_DIR", Fs->hash_table, HTT_DEFINE_STR))
      DefineLoad("FM_PICK_DIR", "2");
  }
  if (!HashFind("ST_DOC_CMDS", Fs->hash_table, HTT_DEFINE_STR))
    DefineLstLoad("ST_DOC_CMDS", "TX\0CR\0SR\0TB\0PB\0CU\0MK\0PT\0CL\0PL\0LM\0RM\0HD\0FO\0ID\0FG\0" "BG\0FD\0BD\0WW\0HL\0BK\0IV\0UL\0SX\0SY\0CM\0AN\0LK\0BT\0" "DA\0CB\0LS\0MA\0MU\0HX\0TR\0SP\0IB\0IS\0SO\0HC\0ER\0");
  if (!HashFind("ST_DOC_FLAGS", Fs->hash_table, HTT_DEFINE_STR))
    DefineLstLoad("ST_DOC_FLAGS", "T\0LEN\0A\0D\0HTML\0LE\0LM\0RE\0RM\0BI\0BP\0RT\0SX\0SY\0SCX\0U\0" "LC\0LIS\0RC\0RIS\0LX\0CX\0RX\0TY\0CY\0BY\0" "HL\0WW\0BK\0IV\0SEL\0UL\0" "TC\0PRY\0MRX\0WR\0L\0X\0Q\0FST\0B\0S\0BD\0C\0CA\0RD\0UD\0P\0M\0" "TRM\0Z\0H\0TR\0LS\0SK\0PU\0SIF\0FS\0NC\0DD\0DL\0DRT\0");
  if (!HashFind("ST_LINK_TYPES", Fs->hash_table, HTT_DEFINE_STR))
    DefineLstLoad("ST_LINK_TYPES", "FI\0FA\0FF\0FL\0MN\0PI\0PF\0PL\0BF\0DN\0HI\0AD\0AI\0AA\0AF\0AL\0");
  if (!doldoc.hash) {
    doldoc.hash = HashTableNew(512);
    if (!doldoc.hash)
      return;
  }
  doldoc.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
}

public I64 RVDocInitRungCSelfTest()
{
  DocInitRungC;
  if (!doldoc.hash)
    return 2;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 3;
  return 1;
}
