/* Hash Table Implementation - Based on TempleOS CHash.HC */

#include "hash_table_bare.h"


// Hash function (simple but effective)
U64 HashStr(const char *str) {
  U64 hash = 5381;
  int c;
  
  while ((c = *str++)) {
    hash = ((hash << 5) + hash) + c; // hash * 33 + c
  }
  
  return hash;
}

CHashTable *HashTableNew(I64 size) {
  CHashTable *table = calloc(1, sizeof(CHashTable));
  
  // Round up to power of 2
  I64 actual_size = 256;
  while (actual_size < size) {
    actual_size *= 2;
  }
  
  table->body = calloc(actual_size, sizeof(CHashEntry*));
  table->mask = actual_size - 1;
  
  return table;
}

void HashTableFree(CHashTable *table) {
  if (!table) return;
  
  for (I64 i = 0; i <= table->mask; i++) {
    CHashEntry *entry = table->body[i];
    while (entry) {
      CHashEntry *next = entry->next;
      free(entry->str);
      free(entry);
      entry = next;
    }
  }
  
  free(table->body);
  free(table);
}

void HashAdd(CHashEntry *entry, CHashTable *table) {
  U64 hash = HashStr(entry->str);
  I64 index = hash & table->mask;
  
  // Add to front of bucket chain
  entry->next = table->body[index];
  table->body[index] = entry;
}

CHashEntry *HashFind(const char *str, CHashTable *table, I64 type_mask) {
  if (!table || !str) return NULL;
  
  U64 hash = HashStr(str);
  I64 index = hash & table->mask;
  
  CHashEntry *entry = table->body[index];
  while (entry) {
    if (strcmp(entry->str, str) == 0 && (entry->type & type_mask)) {
      return entry;
    }
    entry = entry->next;
  }
  
  return NULL;
}

CHashClass *HashClassNew(const char *name, I64 raw_type, I64 size) {
  // Allocate 6 entries (for 0-5 pointer levels)
  CHashClass *entries = calloc(6, sizeof(CHashClass));
  
  for (int i = 0; i < 6; i++) {
    entries[i].str = name ? strdup(name) : NULL;
    entries[i].type = HTT_CLASS;
    entries[i].raw_type = raw_type;
    entries[i].ptr_stars_cnt = i;
    
    if (i == 0) {
      entries[i].size = size;
    } else {
      entries[i].size = 8;  // Pointer size
      entries[i].raw_type = 7;  // RT_PTR
    }
  }
  
  return entries;
}

CHashKeyword *HashKeywordNew(const char *name, I64 keyword_code) {
  CHashKeyword *kw = calloc(1, sizeof(CHashKeyword));
  kw->str = strdup(name);
  kw->type = HTT_KEYWORD;
  kw->keyword_code = keyword_code;
  return kw;
}

void HashInitInternalTypes(CHashTable *table) {
  // From CInit.HC - internal_types_table
  struct { I64 type; I64 size; const char *name; } types[] = {
    {0, 0, "I0"},   {0, 0, "U0"},
    {1, 1, "I8"},   {2, 1, "U8"},  {1, 1, "Bool"},
    {3, 2, "I16"},  {4, 2, "U16"},
    {5, 4, "I32"},  {6, 4, "U32"},
    {7, 8, "I64"},  {8, 8, "U64"},
    {9, 8, "F64"},
  };
  
  for (int i = 0; i < sizeof(types)/sizeof(types[0]); i++) {
    CHashClass *cls = HashClassNew(types[i].name, types[i].type, types[i].size);
    cls->type = HTT_INTERNAL_TYPE;
    HashAdd((CHashEntry*)cls, table);
  }
}

