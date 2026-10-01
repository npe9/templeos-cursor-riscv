/* Hash Table System - Matches TempleOS CHash.HC */

#ifndef HASH_TABLE_H
#define HASH_TABLE_H

#include <stdint.h>
#include <stdbool.h>

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
#define HTT_ENUM              0x4000

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
  // Type info for typed loads/stores and pointer/array members
  U8 raw_type;              // RT_* of the member (RT_I64 for pointers)
  U8 pointed_to_type;       // pointee type for pointer members (0 = not a pointer)
  U8 ptr_depth;             // pointer levels
  bool is_array;            // `U8 name[8]`: the member is its address
  // `I32 (*fn)(I64)`: the member holds a code address, so `x.fn(a)` / `p->fn(a)` is a CALL
  // through it, not a load of it. Without this flag the two are indistinguishable (a fnptr
  // member records raw_type=RT_I64 and pointed_to_type=0, exactly like a plain I64 member),
  // and the postfix parser took the load: `return m.fn(5)` compiled to the POINTER VALUE
  // with no diagnostic, while the statement and assignment forms were parse errors.
  bool is_func_ptr;
  I64 elem_size;            // element size for array/pointer members
  // `U8 name[4][96]`: flat storage, subscript k advances dim_stride[k] bytes. Mirrors the
  // ndims/dim_stride a local Symbol and a CHashGlblVar already carry; without it a partial
  // subscript of a member (`w.rows[n]`) stepped one ELEMENT and then dereferenced, so it
  // yielded a loaded byte instead of the row address.
  int ndims;                // 0/1 = flat; >1 = multi-dimensional
  I64 dim_stride[4];
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
  
  I64 raw_type;             // Return RT_* (RT_I64 for pointer returns)
  I64 size;                 // Function size
  I64 ptr_stars_cnt;        // Return pointer depth (0 for scalar returns)
  U8 ret_pointed_to;        // Pointee RT_* when ptr_stars_cnt > 0 (`U8 *LstSub` → RT_U8)
  
  I64 exe_addr;             // Function address
  I64 arg_cnt;              // Argument count
  struct CHashClass *return_class;   // Return type
  struct CMemberLst *member_lst;     // Parameters
  void *entry_label;        // CLabel* — stable for forward decl + unified AOT (PC-rel IC_CALL)
  bool is_extern;           // runtime function: call through import_var's slot (AOT: data section)
  int entry_label_defined;  // a body was parsed (extern declarations before it do not make it an import)
  struct CHashGlblVar *import_var;
  I64 param_cnt;            // declared parameters (0 for runtime-registered functions: unchecked)
  U8 param_has_default[16];
  I64 param_default[16];
  bool is_varargs;          // `...`: hidden argc/argv parameters follow the fixed ones
  bool param_typed;         // parameter types known: convert call arguments per the mask
  unsigned param_f64_mask;  // bit i: parameter i is F64
  char *param_default_src[16];  // expression defaults (source text) evaluated at each call site
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

// Enum value entry
typedef struct CHashEnumValue {
  struct CHashEntry *next;
  char *str;
  I64 type;                  // HTT_ENUM
  I64 use_cnt;

  I64 value;                 // Enumerated value
} CHashEnumValue;

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
  U8 ptr_depth;             // pointer levels (`U8 **argv` is 2)
  U8 pointed_to_type;
  CArrayDim dim;            // Array dimensions
  int ndims;                // >1 = multi-dimensional (dim_stride per subscript level)
  I64 dim_stride[4];        // bytes advanced by one step of subscript k
  struct CHashFun *fun_ptr; // If it's a function pointer variable
  bool self_resolved;       // import slot filled by this unit's own entry chunk (not in the loader directory)
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
void HashTableClear(CHashTable *table);
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

