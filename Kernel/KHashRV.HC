// KHashRV.HC — HolyC ports of KHashA.HC x86 primitives for RISC-V.
// KHashA's asm{} is skipped on RV; without these, HashAdd is an import into host
// holy_rt and mis-handles guest CHashTable pointers.
// Use index stores (not CHash**) — RV AOT miscompiles some ** stores.
I64 HashStr(U8 *st)
{
  // TempleOS SYS_HASH_STR (see KHashA.HC).
  U64 h = 0, c, carry;
  if (!st)
    return 0;
  while (c = *st++) {
    carry = h >> 63;
    h = (h << 1) + c + carry;
  }
  carry = (h >> 15) & 1;
  return h + (h >> 16) + carry;
}

CHash **HashBucketFind(U8 *needle_str, CHashTable *haystack_table)
{
  I64 i;
  if (!needle_str || !haystack_table || !haystack_table->body)
    return NULL;
  i = HashStr(needle_str) & haystack_table->mask;
  return &haystack_table->body[i];
}

U0 HashAdd(CHash *tmph, CHashTable *table)
{
  I64 i;
  if (!tmph || !table || !table->body)
    return;
  i = HashStr(tmph->str) & table->mask;
  tmph->next = table->body[i];
  table->body[i] = tmph;
}

CHash *HashSingleTableFind(U8 *needle_str, CHashTable *haystack_table, I64 mask, I64 instance = 1)
{
  CHash *tmph;
  U8 *a, *b;
  I64 i;
  if (!needle_str || !haystack_table || !haystack_table->body || instance <= 0)
    return NULL;
  i = HashStr(needle_str) & haystack_table->mask;
  tmph = haystack_table->body[i];
  while (tmph) {
    if ((tmph->type & mask) && tmph->str) {
      a = tmph->str;
      b = needle_str;
      while (*a && *a == *b) {
        a++;
        b++;
      }
      if (!*a && !*b) {
        if (--instance == 0) {
          tmph->use_cnt++;
          return tmph;
        }
      }
    }
    tmph = tmph->next;
  }
  return NULL;
}

CHash *HashFind(U8 *needle_str, CHashTable *haystack_table, I64 mask, I64 instance = 1)
{
  CHash *res;
  while (haystack_table) {
    res = HashSingleTableFind(needle_str, haystack_table, mask, instance);
    if (res)
      return res;
    haystack_table = haystack_table->next;
  }
  return NULL;
}

Bool HashRemDel(CHash *tmph, CHashTable *table, I64 instance = 1)
{
  I64 i;
  CHash *p;
  no_warn instance;
  if (!tmph || !table || !table->body)
    return FALSE;
  i = HashStr(tmph->str) & table->mask;
  if (table->body[i] == tmph) {
    table->body[i] = tmph->next;
    HashDel(tmph);
    return TRUE;
  }
  p = table->body[i];
  while (p && p->next) {
    if (p->next == tmph) {
      p->next = tmph->next;
      HashDel(tmph);
      return TRUE;
    }
    p = p->next;
  }
  return FALSE;
}
