// Runs the real TempleOS kernel hash table (KHashA/B): HashTableNew, StrNew, HashAdd, HashFind.
#include "/Kernel/Kernel_RV.PRJ"
// kernel hash table: HashTableNew, HashAdd a CHashGlblVar-ish, HashFind
I64 main()
{
  CHashTable *ht = HashTableNew(64, NULL);
  CHash *e = CAlloc(sizeof(CHash), NULL);
  e->str = StrNew("foo", NULL);
  e->type = HTT_GLBL_VAR;
  HashAdd(e, ht);
  CHash *f = HashFind("foo", ht, 0xFFFFFFFF);
  CHash *g = HashFind("bar", ht, 0xFFFFFFFF);
  return (f == e) * 10 + (g == NULL);
}
