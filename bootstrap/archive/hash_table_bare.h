/* Hash Table System - Matches TempleOS CHash.HC */

#ifndef HASH_TABLE_H
#define HASH_TABLE_H

#include <stdint.h>
#include <stdbool.h>
#include "bare_runtime.h"

typedef int64_t I64;
typedef uint64_t U64;
typedef uint8_t U8;
typedef double F64;

// Hash Table Type Flags (from CompilerA.HH)
#define HTT_KEYWORD           0x001
#define HTT_ASM_KEYWORD       0x002
#define HTT_OPCODE            0x004
#define HTT_REG               0x008
#define HTT_CLASS             0x010
#define HTT_INTERNAL_TYPE     0x020
#define HTT_DEFINE_STR        0x040
#define HTT_GLBL_VAR          0x080
#define HTT_FUN               0x100
#define HTT_WORD              0x200
#define HTT_DICT_WORD         0x400
#define HTT_FILE              0x800
#define HTT_MODULE            0x1000
#define HTT_EXPORT_SYS_SYM    0x2000

// Hash Table
typedef struct CHashTable {
  struct CHashEntry **body;  // Array of hash buckets
  I64 mask;                  // Size mask (size - 1)
} CHashTable;

// Base hash entry (all hash entries start with these fields)
typedef struct CHashEntry {
  struct CHashEntry *next;   // Next in bucket chain
  char *str;                 // Entry name
  I64 type;                  // HTT_* flags
  I64 use_cnt;              // Usage count
} CHashEntry;

// Class member list
typedef struct CMemberLst {
  struct CMemberLst *next;
  char *str;                // Member name
  I64 offset;               // Offset in bytes from struct base
  I64 size;                 // Size in bytes
  struct CHashClass *member_class;  // Type of this member
  
  // Bit field support
  I64 bit_offset;           // Bit offset within the byte
  I64 bit_width;            // Width in bits (0 = not a bit field)
} CMemberLst;

// Hash entry for classes/types
typedef struct CHashClass {
  struct CHashEntry *next;
  char *str;
  I64 type;                  // HTT_CLASS or HTT_INTERNAL_TYPE
  I64 use_cnt;
  
  I64 raw_type;             // RT_I8, RT_I64, etc.
  I64 size;                 // Size in bytes
  I64 ptr_stars_cnt;        // Number of pointer levels (0, 1, 2, ...)
  I64 flags;                // Class flags
  
  struct CHashClass *base_class;     // Inheritance
  CMemberLst *member_lst;            // Class members
} CHashClass;

// Hash entry for functions
typedef struct CHashFun {
  struct CHashEntry *next;
  char *str;
  I64 type;                  // HTT_FUN
  I64 use_cnt;
  
  I64 raw_type;             // Return type
  I64 size;                 // Function size
  I64 ptr_stars_cnt;        // Pointer level
  
  I64 exe_addr;             // Function address
  I64 arg_cnt;              // Argument count
  struct CHashClass *return_class;   // Return type
  struct CMemberLst *member_lst;     // Parameters
  void *entry_label;
} CHashFun;

// Hash entry for keywords
typedef struct CHashKeyword {
  struct CHashEntry *next;
  char *str;
  I64 type;                  // HTT_KEYWORD
  I64 use_cnt;
  
  I64 keyword_code;         // KW_IF, KW_WHILE, etc.
} CHashKeyword;

// Hash entry for #define macros
typedef struct CHashDefine {
  struct CHashEntry *next;
  char *str;
  I64 type;                  // HTT_DEFINE_STR
  I64 use_cnt;
  
  char *data;               // Replacement text
  char **param_names;       // Parameter names for parameterized macros
  int param_count;          // Number of parameters (0 for simple defines)
} CHashDefine;

// Array dimensions (forward declaration for global variables)
typedef struct CArrayDim {
  struct CArrayDim *next;
  I64 cnt;                  // Count for this dimension
  I64 total_cnt;            // Total count (product of all dimensions)
} CArrayDim;

// Hash entry for global variables
typedef struct CHashGlblVar {
  struct CHashEntry *next;
  char *str;
  I64 type;                  // HTT_GLBL_VAR
  I64 use_cnt;
  
  U8 *data_addr;            // Variable address
  I64 data_addr_rip;        // RIP offset for AOT
  CHashClass *var_class;    // Variable type
  I64 size;                 // Size in bytes
  I64 flags;                // GVF_* flags
  bool is_function_pointer;
  U8 function_return_type;
  int func_ptr_param_count;
  I64 element_size;
  U8 raw_type;
  U8 pointed_to_type;
  CArrayDim dim;            // Array dimensions
  struct CHashFun *fun_ptr; // If it's a function pointer variable
} CHashGlblVar;

// Global variable flags
#define GVF_EXTERN     0x01
#define GVF_IMPORT     0x02
#define GVF_ALIAS      0x04
#define GVF_FUN        0x08
#define GVF_ARRAY      0x10
#define GVF_DATA_HEAP  0x20

// Hash table functions
CHashTable *HashTableNew(I64 size);
void HashTableFree(CHashTable *table);
void HashAdd(CHashEntry *entry, CHashTable *table);
CHashEntry *HashFind(const char *str, CHashTable *table, I64 type_mask);
CHashEntry *HashRemove(CHashTable *table, const char *str, I64 type_mask);
U64 HashStr(const char *str);

// Type functions
CHashClass *HashClassNew(const char *name, I64 raw_type, I64 size);
CHashKeyword *HashKeywordNew(const char *name, I64 keyword_code);

// Initialize with internal types
void HashInitInternalTypes(CHashTable *table);

#endif

