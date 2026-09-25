// RVRegistry.HC — the runtime half of the TempleOS registry, in memory only.
//
// Stock code opens with the pair
//
//   RegDft("TempleOS/FlapBat","F64 best_score=9999;\n");
//   RegExe("TempleOS/FlapBat");
//
// In TempleOS both of these RUN while the file is being compiled, and compiling RegDft's string
// is what DECLARES best_score. An AOT compiler never runs them, so the host compiler does the
// declaring instead (host/parser.c, ParseRegistryDecls). What is left for runtime is the part
// that keeps the calls from being unresolved imports, plus a place for a real registry to land.
//
// What this is NOT: RegExe does not compile text (no guest compiler in a plain kernel image) and
// RegWrite does not persist (no ~/Registry.HC). A value written here is visible to RegFind for
// the rest of the boot and then gone. Reaching stock behaviour needs the DolDoc tree in
// ~/Registry.HC.Z plus ExePrint — see docs/DEMO_SURVEY.md.

#define REG_ENTRIES_MAX	64

class CRVRegEntry
{
  U8	*branch;
  U8	*text;
};

CRVRegEntry rv_reg_entries[REG_ENTRIES_MAX];
I64 rv_reg_cnt;

public CRVRegEntry *RegFind(U8 *branch)
{
  //The entry for a registry branch, or NULL. In-memory only; see the file header.
  I64 i;
  if (!branch)
    return NULL;
  for (i = 0; i < rv_reg_cnt; i++)
    if (!StrCmp(rv_reg_entries[i].branch, branch))
      return &rv_reg_entries[i];
  return NULL;
}

U0 RegSet(U8 *branch, U8 *text)
{
  CRVRegEntry *e = RegFind(branch);
  if (e) {
    Free(e->text);
    e->text = StrNew(text);
    return;
  }
  if (rv_reg_cnt >= REG_ENTRIES_MAX)
    return;
  e = &rv_reg_entries[rv_reg_cnt++];
  e->branch = StrNew(branch);
  e->text = StrNew(text);
}

public U0 RegDft(U8 *branch, U8 *dft_text)
{
  //Store a branch's default text if the branch is not present. The DECLARATIONS in dft_text were
  //already made by the host compiler at compile time — this only records the text.
  if (!RegFind(branch))
    RegSet(branch, dft_text);
}

public U0 RegExe(U8 *branch)
{
  //Stock: compile and run the branch's text, which assigns the globals RegDft declared. Here the
  //globals already carry their default initializers and there is no compiler to run, so a branch
  //with no stored text is the only thing worth reporting.
  if (!RegFind(branch))
    return;
}

public U0 RegWrite(U8 *branch, U8 *fmt, ...)
{
  //Stock: rewrite the branch in ~/Registry.HC so the value survives a reboot. Here it updates the
  //in-memory text only, so a high score lives until power-off.
  U8 *buf = StrPrintJoin(NULL, fmt, argc, argv);
  RegSet(branch, buf);
  Free(buf);
}
