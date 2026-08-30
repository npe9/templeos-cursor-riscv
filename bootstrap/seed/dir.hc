// Dir() reimplemented in HolyC -- redefines the C built-in, so the directory listing is
// itself editable: Src("Dir") brings this up. Uses FileCount/FileName/FileSize.
U0 Dir() {
  I64 i, n = FileCount();
  if (!n) { "  (no files)\n"; return; }
  for (i = 0; i < n; i++)
    "  %s  %d bytes\n", FileName(i), FileSize(i);
}
