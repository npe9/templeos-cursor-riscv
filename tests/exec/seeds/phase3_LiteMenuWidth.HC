I64 rv_menu_personal_n;
public U0 RVMenuPersonalInit()
{
  rv_menu_personal_n = 8;
}

public I64 RVMenuPersonalCount()
{
  if (!rv_menu_personal_n)
    RVMenuPersonalInit;
  return rv_menu_personal_n;
}

public I64 RVMenuPersonalWidth()
{
  if (!rv_menu_personal_n)
    RVMenuPersonalInit;
  return 12;
}

public I64 RVMenuWidthSelfTest()
{
  I64 n;
  I64 w;
  n = RVMenuPersonalCount;
  w = RVMenuPersonalWidth;
  if (n != 8)
    return 1;
  if (w != 12)
    return 2;
  return 8;
}
