// man.hc -- Man("Name"): integrated help, TempleOS style. A function's man page is the doc
// comment block at the top of the source unit that defined it (every seed file carries one);
// Man prints it plus the symbol's address/size and how to go deeper (Uf, Src).
U0 Man(U8 *name) {
  U8 *s; I64 a, n, i;
  a = FnAddr(name);
  s = SrcText(name);
  if (!a && !s) { "Man: no such symbol: %s\n", name; return; }
  if (a) {
    n = FnSize(name);
    if (n) { "%s: 0x%08X, %d bytes (HolyC)  --  Uf(\"%s\"); Src(\"%s\");\n", name, a, n, name, name; }
    else   { "%s: 0x%08X (C builtin)  --  Uf(\"%s\");\n", name, a, name; }
  }
  if (s) {
    i = 0;
    if (s[0] == '/' && s[1] == '/') {
      while (s[i] == '/' && s[i + 1] == '/') {   // the unit's leading doc block
        while (s[i] && s[i] != '\n') { PutCh(s[i]); i++; }
        PutCh('\n');
        if (s[i]) i++;
      }
    } else {                                     // no doc block: show the signature line
      while (s[i] && s[i] != '{' && s[i] != '\n' && i < 100) { PutCh(s[i]); i++; }
      "\n";
    }
  } else { "(no HolyC source -- a C builtin)\n"; }
}
