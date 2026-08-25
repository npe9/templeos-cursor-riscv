/* HolyC Lexer - Tokenizes HolyC source code */

#include "holyc_compiler.h"
#include <ctype.h>

#define IS_ALPHA_CHAR(c) (((c) >= 'a' && (c) <= 'z') || ((c) >= 'A' && (c) <= 'Z'))
#define IS_DIGIT_CHAR(c) ((c) >= '0' && (c) <= '9')
#define IS_ALNUM_CHAR(c) (IS_ALPHA_CHAR(c) || IS_DIGIT_CHAR(c) || (c) == '_')

#define MAX_INCLUDE_PATH 1024

static bool EndsWith(const char *str, const char *suffix) {
  if (!str || !suffix) return false;
  size_t str_len = strlen(str);
  size_t suffix_len = strlen(suffix);
  if (suffix_len > str_len) return false;
  return strcmp(str + str_len - suffix_len, suffix) == 0;
}

static bool ReadEntireFile(const char *path, char **out_src) {
  if (!path || !out_src) return false;

  FILE *f = fopen(path, "rb");
  if (!f) return false;

  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return false;
  }
  long fsize = ftell(f);
  if (fsize < 0) {
    fclose(f);
    return false;
  }
  if (fseek(f, 0, SEEK_SET) != 0) {
    fclose(f);
    return false;
  }

  char *buffer = malloc((size_t)fsize + 1);
  if (!buffer) {
    fclose(f);
    return false;
  }

  size_t read = fread(buffer, 1, (size_t)fsize, f);
  fclose(f);
  if (read != (size_t)fsize) {
    free(buffer);
    return false;
  }

  buffer[fsize] = '\0';
  *out_src = buffer;
  return true;
}

static void ExtractDirectory(const char *path, char *out_dir, size_t out_size) {
  if (!out_dir || out_size == 0) return;
  out_dir[0] = '\0';
  if (!path || !path[0] || path[0] == '<') return;

  const char *last_forward = strrchr(path, '/');
  const char *last_back = strrchr(path, '\\');
  const char *slash = last_forward;
  if (last_back && (!slash || last_back > slash)) {
    slash = last_back;
  }
  if (!slash) return;

  size_t dir_len = (size_t)(slash - path);
  if (dir_len >= out_size) {
    dir_len = out_size - 1;
  }
  memcpy(out_dir, path, dir_len);
  out_dir[dir_len] = '\0';
}

static bool NeedsSeparator(const char *dir) {
  if (!dir || !dir[0]) return false;
  size_t len = strlen(dir);
  char last = dir[len - 1];
  return !(last == '/' || last == '\\');
}

static bool TryIncludeInDirectory(const char *dir,
                                  const char *filename,
                                  char *resolved,
                                  size_t resolved_size,
                                  char **out_src) {
  if (!filename || !resolved || !out_src) return false;

  char candidate[MAX_INCLUDE_PATH];
  int written;
  if (dir && dir[0]) {
    written = StrPrintF(candidate,
                       sizeof(candidate),
                       NeedsSeparator(dir) ? "%s/%s" : "%s%s",
                       dir,
                       filename);
  } else {
    written = StrPrintF(candidate, sizeof(candidate), "%s", filename);
  }

  if (written < 0 || written >= (int)sizeof(candidate)) {
    return false;
  }

  if (ReadEntireFile(candidate, out_src)) {
    StrPrintF(resolved, resolved_size, "%s", candidate);
    return true;
  }

  if (!EndsWith(filename, ".HC")) {
    if (dir && dir[0]) {
      written = StrPrintF(candidate,
                         sizeof(candidate),
                         NeedsSeparator(dir) ? "%s/%s.HC" : "%s%s.HC",
                         dir,
                         filename);
    } else {
      written = StrPrintF(candidate, sizeof(candidate), "%s.HC", filename);
    }

    if (written < 0 || written >= (int)sizeof(candidate)) {
      return false;
    }

    if (ReadEntireFile(candidate, out_src)) {
      StrPrintF(resolved, resolved_size, "%s", candidate);
      return true;
    }
  }

  return false;
}

static bool IsAbsolutePath(const char *path) {
  if (!path || !path[0]) return false;
#ifdef _WIN32
  if (path[0] == '/' || path[0] == '\\') return true;
  if (strlen(path) > 1 && path[1] == ':') return true;
  return false;
#else
  return path[0] == '/';
#endif
}

static bool LoadIncludeFile(Compiler *cc,
                            const char *filename,
                            char **out_src,
                            char *resolved_path,
                            size_t resolved_size) {
  if (!filename || !out_src || !resolved_path) return false;

  if (filename[0] == ':' && filename[1] == ':' && filename[2] == '/') filename += 2;   // `::/Adam/…`: the boot drive's root
  if (IsAbsolutePath(filename)) {
    // TempleOS paths are rooted at the distribution ("/Kernel/KernelA.HH"): HOLYC_INCLUDE_ROOT
    // names that directory on the host (the exec scripts point it at the repo root).
#ifndef BARE_METAL
    const char *root = getenv("HOLYC_INCLUDE_ROOT");
    if (root && *root) {
      char rooted[MAX_INCLUDE_PATH];
      int w = StrPrintF(rooted, sizeof(rooted), "%s%s", root, filename);
      if (w > 0 && w < (int)sizeof(rooted)) {
        if (TryIncludeInDirectory(NULL, rooted, resolved_path, resolved_size, out_src)) return true;
        if (!EndsWith(filename, ".HC") && !EndsWith(filename, ".HH")) {
          char tmp2[MAX_INCLUDE_PATH];
          int w2 = StrPrintF(tmp2, sizeof(tmp2), "%s.HC", rooted);
          if (w2 > 0 && w2 < (int)sizeof(tmp2) && TryIncludeInDirectory(NULL, tmp2, resolved_path, resolved_size, out_src)) return true;
        }
      }
    }
#endif
    if (TryIncludeInDirectory(NULL, filename, resolved_path, resolved_size, out_src)) {
      return true;
    }
    if (!EndsWith(filename, ".HC")) {
      char tmp[MAX_INCLUDE_PATH];
      int written = StrPrintF(tmp, sizeof(tmp), "%s.HC", filename);
      if (written >= 0 && written < (int)sizeof(tmp)) {
        if (TryIncludeInDirectory(NULL, tmp, resolved_path, resolved_size, out_src)) {
          return true;
        }
      }
    }
    return false;
  }

  char current_dir[MAX_INCLUDE_PATH];
  ExtractDirectory(cc->lex.filename, current_dir, sizeof(current_dir));

  if (current_dir[0]) {
    if (TryIncludeInDirectory(current_dir, filename, resolved_path, resolved_size, out_src)) {
      return true;
    }
    if (!EndsWith(filename, ".HC") && !EndsWith(filename, ".HH")) {   // `#include "KStart16"` → KStart16.HC
      char tmp[MAX_INCLUDE_PATH];
      int written = StrPrintF(tmp, sizeof(tmp), "%s.HC", filename);
      if (written > 0 && written < (int)sizeof(tmp) &&
          TryIncludeInDirectory(current_dir, tmp, resolved_path, resolved_size, out_src)) return true;
    }
  }

  if (TryIncludeInDirectory(NULL, filename, resolved_path, resolved_size, out_src)) {
    return true;
  }

  return false;
}

static const struct {
  const char *name;
  int token;
} keywords[] = {
  {"if", KW_IF},
  {"else", KW_ELSE},
  {"while", KW_WHILE},
  {"for", KW_FOR},
  {"return", KW_RETURN},
  {"break", KW_BREAK},
  {"class", KW_CLASS},
  {"enum", KW_ENUM},
  {"public", KW_PUBLIC},
  {"I0", KW_I0},
  {"U0", KW_U0},
  {"I8", KW_I8},
  {"U8", KW_U8},
  {"I16", KW_I16},
  {"U16", KW_U16},
  {"I32", KW_I32},
  {"U32", KW_U32},
  {"I64", KW_I64},
  {"U64", KW_U64},
  {"F64", KW_F64},
  {NULL, 0}
};

static void FreeDefine(CHashDefine *def) {
  if (!def) return;
  if (def->data) free(def->data);
  if (def->param_names) {
    for (int i = 0; i < def->param_count; i++) {
      if (def->param_names[i]) free(def->param_names[i]);
    }
    free(def->param_names);
  }
  if (def->str) free(def->str);
  free(def);
}

static void SkipWhitespace(Lexer *lex) {
  while (*lex->ptr && (*lex->ptr == ' ' || *lex->ptr == '\t' || *lex->ptr == '\n' || *lex->ptr == '\r')) {
    if (*lex->ptr == '\n') {
      lex->line++;
      lex->col = 1;
    } else {
      lex->col++;
    }
    lex->ptr++;
  }
}

static void SkipComment(Lexer *lex) {
  if (lex->ptr[0] == '/' && lex->ptr[1] == '/') {
    // Line comment
    while (*lex->ptr && *lex->ptr != '\n') {
      lex->ptr++;
    }
  } else if (lex->ptr[0] == '/' && lex->ptr[1] == '*') {
    // Block comment
    lex->ptr += 2;
    while (*lex->ptr) {
      if (lex->ptr[0] == '*' && lex->ptr[1] == '/') {
        lex->ptr += 2;
        break;
      }
      if (*lex->ptr == '\n') {
        lex->line++;
        lex->col = 1;
      }
      lex->ptr++;
    }
  }
}

static void SkipDolDoc(Lexer *lex) {
  // Skip a DolDoc command in source text: `$XX,...$` (single dollars on disk; `$$` inside
  // is an escaped '$'). Called with ptr at the opening '$'.
  lex->ptr++;
  lex->col++;
  while (*lex->ptr) {
    if (lex->ptr[0] == '$') {
      if (lex->ptr[1] == '$') { lex->ptr += 2; lex->col += 2; continue; }   // escaped
      lex->ptr++; lex->col++;                                               // closing
      return;
    }
    if (*lex->ptr == '\n') { lex->line++; lex->col = 1; } else lex->col++;
    lex->ptr++;
  }
}

static void HandlePreprocessor(Compiler *cc) {
  Lexer *lex = &cc->lex;
  
  // Skip preprocessor directive (starts with #)
  if (*lex->ptr != '#') return;
  
  lex->ptr++;  // Skip '#'
  lex->col++;
  
  // Skip whitespace
  while (*lex->ptr == ' ' || *lex->ptr == '\t') {
    lex->ptr++;
    lex->col++;
  }
  
  // Get directive name
  char directive[64];
  int i = 0;
  while (IS_ALPHA_CHAR(*lex->ptr) && i < 63) {
    directive[i++] = *lex->ptr++;
    lex->col++;
  }
  directive[i] = '\0';
  
  if (strcmp(directive, "define") == 0) {
    // Parse #define NAME VALUE or #define NAME(params) VALUE

    // Skip whitespace
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }

    // Get macro name
    char name[256];
    i = 0;
    while ((IS_ALNUM_CHAR(*lex->ptr)) && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';

    // Parse parameter list if present immediately after the name
    char *param_names_buf[16];
    int param_count = 0;

    if (*lex->ptr == '(') {
      lex->ptr++;
      lex->col++;

      while (*lex->ptr && *lex->ptr != ')') {
        while (*lex->ptr == ' ' || *lex->ptr == '\t') {
          lex->ptr++;
          lex->col++;
        }

        if (*lex->ptr == ')') break;  // Allow trailing whitespace before ')'

        char param[256];
        int pj = 0;
        while ((IS_ALNUM_CHAR(*lex->ptr)) && pj < 255) {
          param[pj++] = *lex->ptr++;
          lex->col++;
        }
        param[pj] = '\0';

        if (pj == 0) {
          // Unsupported token (like variadic); treat as empty and break
          break;
        }

        if (param_count < 16) {
          param_names_buf[param_count++] = strdup(param);
        }

        while (*lex->ptr == ' ' || *lex->ptr == '\t') {
          lex->ptr++;
          lex->col++;
        }

        if (*lex->ptr == ',') {
          lex->ptr++;
          lex->col++;
          continue;
        }
        break;
      }

      if (*lex->ptr == ')') {
        lex->ptr++;
        lex->col++;
      }

      // Skip whitespace between parameter list and replacement
      while (*lex->ptr == ' ' || *lex->ptr == '\t') {
        lex->ptr++;
        lex->col++;
      }
    } else {
      // No parameters: skip whitespace before replacement
      while (*lex->ptr == ' ' || *lex->ptr == '\t') {
        lex->ptr++;
        lex->col++;
      }
    }

    // Get replacement text (rest of line)
    char value[8192];
    i = 0;
    while (*lex->ptr && *lex->ptr != '\n' && i < (int)sizeof(value) - 1) {
      if (*lex->ptr == '\\' && (lex->ptr[1] == '\n' || (lex->ptr[1] == '\r' && lex->ptr[2] == '\n'))) {
        // backslash-newline: the definition continues on the next line
        lex->ptr += (lex->ptr[1] == '\r') ? 3 : 2;
        lex->line++;
        lex->col = 1;
        value[i++] = ' ';
        continue;
      }
      value[i++] = *lex->ptr++;
      lex->col++;
    }
    value[i] = '\0';
    
    // Trim trailing whitespace
    while (i > 0 && (value[i-1] == ' ' || value[i-1] == '\t')) {
      value[--i] = '\0';
    }
    
    // Add to define table
    CHashEntry *existing = HashRemove(cc->define_table, name, HTT_DEFINE_STR);
    if (existing && (existing->type & HTT_DEFINE_STR)) {
      FreeDefine((CHashDefine*)existing);
    }

    CHashDefine *def = calloc(1, sizeof(CHashDefine));
    def->str = strdup(name);
    def->type = HTT_DEFINE_STR;
    def->data = strdup(value);
    if (param_count > 0) {
      def->param_count = param_count;
      def->param_names = calloc(param_count, sizeof(char*));
      for (int idx = 0; idx < param_count; idx++) {
        def->param_names[idx] = param_names_buf[idx];
      }
    } else {
      def->param_count = 0;
      def->param_names = NULL;
    }
    HashAdd((CHashEntry*)def, cc->define_table);
  } else if (strcmp(directive, "include") == 0) {
    // Parse #include "filename"
    
    // Skip whitespace
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Expect quote
    if (*lex->ptr != '"') {
      // Skip to end of line
      goto skip_line;
    }
    lex->ptr++;  // Skip opening quote
    lex->col++;
    
    // Get filename
    char filename[512];
    i = 0;
    while (*lex->ptr && *lex->ptr != '"' && *lex->ptr != '\n' && i < 511) {
      filename[i++] = *lex->ptr++;
      lex->col++;
    }
    filename[i] = '\0';
    
    if (*lex->ptr == '"') {
      lex->ptr++;  // Skip closing quote
      lex->col++;
    }
    
    char resolved_path[MAX_INCLUDE_PATH];
    char *include_src = NULL;
    if (!LoadIncludeFile(cc, filename, &include_src, resolved_path, sizeof(resolved_path))) {
      char err_msg[256];
      StrPrintF(err_msg, sizeof(err_msg), "Unable to open include file '%s'", filename);
      Error(cc, err_msg);
      goto skip_line;
    }

    IncludeFile *inc = calloc(1, sizeof(IncludeFile));
    inc->src = lex->src;
    inc->ptr = lex->ptr;
    inc->filename = lex->filename;
    inc->line = lex->line;
    inc->col = lex->col;
    inc->next = lex->include_stack;
    lex->include_stack = inc;

    lex->src = include_src;
    lex->ptr = include_src;
    lex->filename = strdup(resolved_path);
    lex->line = 1;
    lex->col = 1;

    return;  // Don't skip to next line
  } else if (strcmp(directive, "ifdef") == 0 || strcmp(directive, "ifndef") == 0) {
    // #ifdef or #ifndef
    bool is_ifndef = (strcmp(directive, "ifndef") == 0);
    
    // Get macro name
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    char name[256];
    i = 0;
  while ((IS_ALNUM_CHAR(*lex->ptr)) && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';
    
    // Check if defined
    CHashEntry *entry = HashFind(name, cc->define_table, HTT_DEFINE_STR);
    bool is_defined = (entry != NULL);
    
    // Determine if we should skip
    bool should_skip = is_ifndef ? is_defined : !is_defined;
    
    cc->ifdef_depth++;
    if (should_skip) {
      cc->preprocessor_skip = true;
    }
  } else if (strcmp(directive, "ifjit") == 0 || strcmp(directive, "ifaot") == 0) {
    // TempleOS build-mode conditionals: this compiler is always the AOT side.
    if (strcmp(directive, "ifjit") == 0) cc->preprocessor_skip = true;
    cc->ifdef_depth++;
  } else if (strcmp(directive, "exe") == 0) {
    // #exe { … } runs code at compile time in TempleOS; nothing to run here — skip the block
    // (it may span lines), then the rest of the line.
    while (*lex->ptr == ' ' || *lex->ptr == '\t') { lex->ptr++; lex->col++; }
    if (*lex->ptr == '{') {
      int depth = 0;
      do {
        if (*lex->ptr == '{') depth++;
        else if (*lex->ptr == '}') depth--;
        else if (*lex->ptr == '\n') { lex->line++; lex->col = 0; }
        lex->ptr++; lex->col++;
      } while (*lex->ptr && depth > 0);
    }
    while (*lex->ptr && *lex->ptr != '\n') { lex->ptr++; lex->col++; }
  } else if (strcmp(directive, "if") == 0) {
    // #if - simplified: only support #if 0 and #if 1
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Get the condition (only support literal 0 or 1)
    if (*lex->ptr == '0') {
      cc->preprocessor_skip = true;
      lex->ptr++;
    }
    // Any non-zero is treated as true (skip nothing)
    
    cc->ifdef_depth++;
  } else if (strcmp(directive, "elif") == 0) {
    // #elif - else if for preprocessor
    if (cc->ifdef_depth > 0) {
      // If we were already processing (not skipping), now skip
      if (!cc->preprocessor_skip) {
        cc->preprocessor_skip = true;
      } else {
        // Evaluate condition
        while (*lex->ptr == ' ' || *lex->ptr == '\t') {
          lex->ptr++;
          lex->col++;
        }
        
        // Get the condition (only support literal 0 or 1)
        if (*lex->ptr == '0') {
          cc->preprocessor_skip = true;
        } else if (*lex->ptr == '1') {
          cc->preprocessor_skip = false;
        }
        // For anything else, treat as false
      }
    }
  } else if (strcmp(directive, "else") == 0) {
    // #else - toggle skip state
    if (cc->ifdef_depth > 0) {
      cc->preprocessor_skip = !cc->preprocessor_skip;
    }
  } else if (strcmp(directive, "endif") == 0) {
    // #endif - pop ifdef state
    if (cc->ifdef_depth > 0) {
      cc->ifdef_depth--;
      if (cc->ifdef_depth == 0) {
        cc->preprocessor_skip = false;
      }
    }
  } else if (strcmp(directive, "undef") == 0) {
    // #undef - undefine a macro
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Get macro name
    char name[256];
    i = 0;
  while ((IS_ALNUM_CHAR(*lex->ptr)) && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';
    
    // Remove from define table
    CHashEntry *removed = HashRemove(cc->define_table, name, HTT_DEFINE_STR);
    if (removed && (removed->type & HTT_DEFINE_STR)) {
      FreeDefine((CHashDefine*)removed);
    }
  }

skip_line:
  
  // Skip to end of line for all directives (a backslash continues the line: `#help_index "…"\`)
  while (*lex->ptr) {
    if (lex->ptr[0] == '\\' && lex->ptr[1] == '\n') { lex->ptr += 2; lex->line++; continue; }
    if (lex->ptr[0] == '\\' && lex->ptr[1] == '\r' && lex->ptr[2] == '\n') { lex->ptr += 3; lex->line++; continue; }
    if (*lex->ptr == '\n') break;
    lex->ptr++;
  }
  if (*lex->ptr == '\n') {
    lex->ptr++;
    lex->line++;
    lex->col = 1;
  }
}

static int LexIdentifier(Compiler *cc) {
  Lexer *lex = &cc->lex;
  char buf[256];
  int len = 0;
  
  // Check if character is alphanumeric or underscore or extended ASCII
  #define IS_IDENT_CHAR(c) ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || (unsigned char)c >= 128)
  
  while (IS_IDENT_CHAR(*lex->ptr)) {
    if (len < 255) {
      buf[len++] = *lex->ptr;
    }
    lex->ptr++;
    lex->col++;
  }
  buf[len] = '\0';
  
  #undef IS_IDENT_CHAR
  
  if (lex->token_str) free(lex->token_str);
  lex->token_str = strdup(buf);
  
  // Check if it's a #define macro first
  CHashEntry *def_entry = HashFind(buf, cc->define_table, HTT_DEFINE_STR);
  if (def_entry && (def_entry->type & HTT_DEFINE_STR)) {
    CHashDefine *def = (CHashDefine*)def_entry;
    
    // Check if it's a parameterized macro
    if (def->param_count > 0) {
      // Need to check if followed by '('
      // Save current position
      char *saved_ptr = lex->ptr;
      int saved_col = lex->col;
      
      // Skip whitespace to check for '('
      while (*lex->ptr && (*lex->ptr == ' ' || *lex->ptr == '\t')) {
        lex->ptr++;
        lex->col++;
      }
      
      if (*lex->ptr == '(') {
        // It's a macro call - parse arguments
        lex->ptr++;  // Skip '('
        lex->col++;
        
        char *args[16];
        int arg_count = 0;
        
        // Parse arguments
        while (arg_count < 16 && *lex->ptr && *lex->ptr != ')') {
          // Skip whitespace
          while (*lex->ptr && (*lex->ptr == ' ' || *lex->ptr == '\t')) {
            lex->ptr++;
            lex->col++;
          }
          
          // Collect argument text
          char arg_buf[256];
          int arg_len = 0;
          int paren_depth = 0;
          
          while (*lex->ptr && arg_len < 255) {
            if (*lex->ptr == '(') {
              paren_depth++;
              arg_buf[arg_len++] = *lex->ptr++;
              lex->col++;
            } else if (*lex->ptr == ')') {
              if (paren_depth == 0) break;
              paren_depth--;
              arg_buf[arg_len++] = *lex->ptr++;
              lex->col++;
            } else if (*lex->ptr == ',' && paren_depth == 0) {
              break;
            } else {
              arg_buf[arg_len++] = *lex->ptr++;
              lex->col++;
            }
          }
          
          arg_buf[arg_len] = '\0';
          
          // Trim trailing whitespace
          while (arg_len > 0 && (arg_buf[arg_len-1] == ' ' || arg_buf[arg_len-1] == '\t')) {
            arg_buf[--arg_len] = '\0';
          }
          
          args[arg_count++] = strdup(arg_buf);
          
          // Skip comma if present
          if (*lex->ptr == ',') {
            lex->ptr++;
            lex->col++;
          }
        }
        
        if (*lex->ptr == ')') {
          lex->ptr++;  // Skip ')'
          lex->col++;
        }
        
        // Expand macro: substitute parameters in macro body
        char expanded[1024];
        int exp_len = 0;
        char *body = def->data;
        
        while (*body && exp_len < 1023) {
          // Check for # (stringification)
          if (*body == '#' && (IS_ALPHA_CHAR(body[1]) || body[1] == '_')) {
            body++;  // Skip '#'
            
            // Get parameter name
            char param_name[64];
            int pn_len = 0;
            while ((IS_ALNUM_CHAR(*body) || *body == '_') && pn_len < 63) {
              param_name[pn_len++] = *body++;
            }
            param_name[pn_len] = '\0';
            
            // Find matching parameter and stringify it
            bool found = false;
            for (int i = 0; i < def->param_count && i < arg_count; i++) {
              if (def->param_names[i] && strcmp(param_name, def->param_names[i]) == 0) {
                // Stringify: add quotes around argument
                if (exp_len < 1022) {
                  expanded[exp_len++] = '"';
                  int arg_len = strlen(args[i]);
                  if (exp_len + arg_len < 1022) {
                    strcpy(&expanded[exp_len], args[i]);
                    exp_len += arg_len;
                  }
                  expanded[exp_len++] = '"';
                }
                found = true;
                break;
              }
            }
            
            if (!found) {
              // Not a parameter, keep the # and name
              expanded[exp_len++] = '#';
              if (exp_len + pn_len < 1023) {
                strcpy(&expanded[exp_len], param_name);
                exp_len += pn_len;
              }
            }
            continue;
          }
          
          // Check for ## (token pasting)
          if (*body == '#' && body[1] == '#') {
            body += 2;  // Skip '##'
            // Skip whitespace after ##
            while (*body == ' ' || *body == '\t') body++;
            // Token pasting: just continue without adding anything
            // The tokens on either side will be concatenated
            continue;
          }
          
          // Check if this is a parameter name
          bool found_param = false;
          
          if (IS_ALPHA_CHAR(*body) || *body == '_') {
            // Possible parameter name
            char param_name[64];
            int pn_len = 0;
            char *temp = body;
            
            while ((IS_ALNUM_CHAR(*temp) || *temp == '_') && pn_len < 63) {
              param_name[pn_len++] = *temp++;
            }
            param_name[pn_len] = '\0';
            
            // Check if it matches a parameter
            for (int i = 0; i < def->param_count && i < arg_count; i++) {
              if (def->param_names[i] && strcmp(param_name, def->param_names[i]) == 0) {
                // Substitute with argument
                int arg_len = strlen(args[i]);
                if (exp_len + arg_len < 1023) {
                  strcpy(&expanded[exp_len], args[i]);
                  exp_len += arg_len;
                }
                body = temp;
                found_param = true;
                break;
              }
            }
          }
          
          if (!found_param) {
            expanded[exp_len++] = *body++;
          }
        }
        expanded[exp_len] = '\0';
        
        // Free arguments
        for (int i = 0; i < arg_count; i++) {
          free(args[i]);
        }
        
        // Re-lex the expanded text by pushing it onto the include stack
        IncludeFile *inc = calloc(1, sizeof(IncludeFile));
        inc->src = lex->src;
        inc->ptr = lex->ptr;
        inc->filename = lex->filename;
        inc->line = lex->line;
        inc->col = lex->col;
        inc->next = lex->include_stack;
        lex->include_stack = inc;
        
        // Replace with expanded macro text
        lex->src = strdup(expanded);
        lex->ptr = lex->src;
        lex->filename = strdup("<macro expansion>");
        lex->line = 1;
        lex->col = 1;
        
        // Recurse to lex first token from expanded text
        LexNext(cc);
        return cc->lex.token;
      } else {
        // Not followed by '(' - restore position and treat as identifier
        lex->ptr = saved_ptr;
        lex->col = saved_col;
      }
    } else {
      // Simple (non-parameterized) macro
      IncludeFile *inc = calloc(1, sizeof(IncludeFile));
      inc->src = lex->src;
      inc->ptr = lex->ptr;
      inc->filename = lex->filename;
      inc->line = lex->line;
      inc->col = lex->col;
      inc->next = lex->include_stack;
      lex->include_stack = inc;

      const char *replacement = def->data ? def->data : "";
      lex->src = strdup(replacement);
      lex->ptr = lex->src;
      lex->filename = strdup("<macro expansion>");
      lex->line = 1;
      lex->col = 1;

      LexNext(cc);
      return cc->lex.token;
    }
  }
  
  // Look up in hash table (like original Lex.HC)
  lex->hash_entry = HashFind(buf, cc->hash_table, 0xFFFFFFFF);
  
  if (lex->hash_entry) {
    // Check if it's a keyword
    if (lex->hash_entry->type & HTT_KEYWORD) {
      CHashKeyword *kw = (CHashKeyword*)lex->hash_entry;
      return kw->keyword_code;
    }
    // Type/class/function - return as identifier
    return TK_IDENT;
  }
  
  // Not in hash table yet
  return TK_IDENT;
}

static int LexNumber(Lexer *lex) {
  I64 value = 0;
  
  // Check for 0x prefix
  if (lex->ptr[0] == '0' && (lex->ptr[1] == 'x' || lex->ptr[1] == 'X')) {
    lex->ptr += 2; // Skip '0x'
    lex->col += 2;
    
    // Parse hex digits manually
    while (*lex->ptr) {
      char c = *lex->ptr;
      if (c >= '0' && c <= '9') {
        value = value * 16 + (c - '0');
      } else if (c >= 'a' && c <= 'f') {
        value = value * 16 + (c - 'a' + 10);
      } else if (c >= 'A' && c <= 'F') {
        value = value * 16 + (c - 'A' + 10);
      } else {
        break;
      }
      lex->ptr++;
      lex->col++;
    }
  } else if (lex->ptr[0] == '0' && (lex->ptr[1] == 'b' || lex->ptr[1] == 'B') &&
             (lex->ptr[2] == '0' || lex->ptr[2] == '1')) {
    // 0b binary (HolyC LexGetNumber)
    lex->ptr += 2;
    lex->col += 2;
    while (*lex->ptr == '0' || *lex->ptr == '1') {
      value = value * 2 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  } else if (lex->ptr[0] == '0' && (lex->ptr[1] == 'd' || lex->ptr[1] == 'D') &&
             (lex->ptr[2] >= '0' && lex->ptr[2] <= '9')) {
    // 0d decimal
    lex->ptr += 2;
    lex->col += 2;
    while (*lex->ptr >= '0' && *lex->ptr <= '9') {
      value = value * 10 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  } else if (lex->ptr[0] == '0' && (lex->ptr[1] == 'o' || lex->ptr[1] == 'O') &&
             (lex->ptr[2] >= '0' && lex->ptr[2] <= '7')) {
    // 0o octal
    lex->ptr += 2;
    lex->col += 2;
    while (*lex->ptr >= '0' && *lex->ptr <= '7') {
      value = value * 8 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  } else {
    // Parse decimal digits manually (no atoll in bare metal)
    while (*lex->ptr >= '0' && *lex->ptr <= '9') {
      value = value * 10 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  }
  
  // Floating literal: digits ['.' digits] [e[+-]digits]  (decimal only; 0x... never gets here)
  bool exp_follows = (*lex->ptr == 'e' || *lex->ptr == 'E') &&
                     ((lex->ptr[1] >= '0' && lex->ptr[1] <= '9') ||
                      ((lex->ptr[1] == '+' || lex->ptr[1] == '-') && lex->ptr[2] >= '0' && lex->ptr[2] <= '9'));
  if ((*lex->ptr == '.' && lex->ptr[1] >= '0' && lex->ptr[1] <= '9') || exp_follows) {
    F64 f = (F64)value, scale = 0.1;
    if (*lex->ptr == '.') {
      lex->ptr++; lex->col++;
      while (*lex->ptr >= '0' && *lex->ptr <= '9') {
        f += (F64)(*lex->ptr - '0') * scale;
        scale /= 10.0;
        lex->ptr++; lex->col++;
      }
    }
    if ((*lex->ptr == 'e' || *lex->ptr == 'E') &&
        ((lex->ptr[1] >= '0' && lex->ptr[1] <= '9') ||
         ((lex->ptr[1] == '+' || lex->ptr[1] == '-') && lex->ptr[2] >= '0' && lex->ptr[2] <= '9'))) {
      lex->ptr++; lex->col++;
      int neg = 0, e = 0;
      if (*lex->ptr == '+' || *lex->ptr == '-') { neg = (*lex->ptr == '-'); lex->ptr++; lex->col++; }
      while (*lex->ptr >= '0' && *lex->ptr <= '9') { e = e * 10 + (*lex->ptr - '0'); lex->ptr++; lex->col++; }
      // Scale by 10^e with exact powers up to 1e22 and as few roundings as possible.
      static const double p10[] = { 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
                                    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22 };
      double scale10 = 1.0;
      int ee = e;
      while (ee > 22) { scale10 *= 1e22; ee -= 22; }
      scale10 *= p10[ee];
      f = neg ? f / scale10 : f * scale10;
    }
    lex->token_f64 = f;
    return TK_F64;
  }
  lex->token_i64 = value;
  return TK_I64;
}

static int LexString(Lexer *lex) {
  static char buf[65536];   // TempleOS strings (DolDoc text) run long; static: not on the stack
  int len = 0;
  char quote = *lex->ptr++;
  lex->col++;
  
  for (;;) {
  while (*lex->ptr && *lex->ptr != quote) {
    if (*lex->ptr == '\\') {
      lex->ptr++;
      lex->col++;
      switch (*lex->ptr) {
        case 'n': buf[len++] = '\n'; break;
        case 't': buf[len++] = '\t'; break;
        case 'r': buf[len++] = '\r'; break;
        case '\\': buf[len++] = '\\'; break;
        case '"': buf[len++] = '"'; break;
        case '\'': buf[len++] = '\''; break;
        case 'd': // \d = '$' (DolDoc escape)
          buf[len++] = '$';
          break;
        default: buf[len++] = *lex->ptr;
      }
      lex->ptr++;
      lex->col++;
    } else if (*lex->ptr == '$' && lex->ptr[1] >= 'A' && lex->ptr[1] <= 'Z') {
      // A DolDoc command inside a string (`$TX,"512Meg",D="…"$`): quotes inside it do not end
      // the literal. Copied verbatim; the UART runtime shows it as-is.
      buf[len++] = *lex->ptr++; lex->col++;
      while (*lex->ptr) {
        if (lex->ptr[0] == '$') {
          if (lex->ptr[1] == '$') { buf[len++] = '$'; lex->ptr += 2; lex->col += 2; continue; }
          buf[len++] = *lex->ptr++; lex->col++;
          break;
        }
        if (*lex->ptr == '\n') { lex->line++; lex->col = 1; } else lex->col++;
        buf[len++] = *lex->ptr++;
      }
    } else if (*lex->ptr == '$' && lex->ptr[1] == '$') {
      // `$$` is a literal '$' in HolyC source (DolDoc escape); "$$FG,RED$$" carries a DolDoc
      // command to the console, which the UART runtime strips at print time.
      buf[len++] = '$';
      lex->ptr += 2;
      lex->col += 2;
    } else {
      buf[len++] = *lex->ptr++;
      lex->col++;
    }
  }
  
  if (*lex->ptr == quote) {
    lex->ptr++;
    lex->col++;
  }
  if (quote == '"') {
    // Adjacent literals concatenate ("a" "b", also across lines and comments).
    char *p = lex->ptr; int line = lex->line, col = lex->col;
    for (;;) {
      while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') { if (*p == '\n') { line++; col = 1; } else col++; p++; }
      if (p[0] == '/' && p[1] == '/') { while (*p && *p != '\n') p++; continue; }
      if (p[0] == '/' && p[1] == '*') { p += 2; while (*p && !(p[0] == '*' && p[1] == '/')) { if (*p == '\n') line++; p++; } if (*p) p += 2; continue; }
      break;
    }
    if (*p == '"') { lex->ptr = p + 1; lex->line = line; lex->col = col + 1; continue; }
  }
  break;
  }
  
  buf[len] = '\0';
  if (lex->token_str) free(lex->token_str);
  lex->token_str = malloc(len + 1);
  memcpy(lex->token_str, buf, len + 1);
  lex->token_str_len = len;
  if (quote == '\'') {
    // HolyC char literal: up to 8 chars packed little-endian into an I64 ('AB' == 0x4241).
    lex->token_i64 = 0;
    for (int i = 0; i < len && i < 8; i++) lex->token_i64 |= (I64)(U8)buf[i] << (8 * i);
    lex->token_is_char = true;
    return TK_I64;
  }
  return TK_STR;
}

static void LexNextInner(Compiler *cc);
// Read `text` as the next tokens, holding the current token back until the text is exhausted
// (default arguments are expressions evaluated at each call site).
void LexPushStringPending(Compiler *cc, const char *text) {
  Lexer *lex = &cc->lex;
  IncludeFile *inc = calloc(1, sizeof(IncludeFile));
  inc->src = lex->src; inc->ptr = lex->ptr; inc->filename = lex->filename; inc->line = lex->line; inc->col = lex->col;
  inc->has_pending = true;
  inc->p_token = lex->token; inc->p_i64 = lex->token_i64; inc->p_f64 = lex->token_f64;
  inc->p_is_char = lex->token_is_char; inc->p_str_len = lex->token_str_len; inc->p_hash = lex->hash_entry;
  inc->p_str = lex->token_str; lex->token_str = NULL;
  inc->next = lex->include_stack;
  lex->include_stack = inc;
  lex->src = strdup(text);
  lex->ptr = lex->src;
  lex->filename = strdup("<default argument>");
  lex->line = 1; lex->col = 1;
  LexNext(cc);
}
// Drop a pushed default-argument string after a parse error inside it, so the next item
// resumes at the token that was held back.
void LexAbandonPendingString(Compiler *cc) {
  Lexer *lex = &cc->lex;
  while (lex->include_stack) {
    IncludeFile *inc = lex->include_stack;
    bool pend = inc->has_pending;
    lex->include_stack = inc->next;
    lex->src = inc->src; lex->ptr = inc->ptr; lex->filename = inc->filename; lex->line = inc->line; lex->col = inc->col;
    if (pend) {
      lex->token = inc->p_token; lex->token_i64 = inc->p_i64; lex->token_f64 = inc->p_f64;
      lex->token_is_char = inc->p_is_char; lex->token_str_len = inc->p_str_len; lex->hash_entry = inc->p_hash;
      if (lex->token_str) free(lex->token_str);
      lex->token_str = inc->p_str; inc->p_str = NULL;
      free(inc);
      return;
    }
    free(inc);
  }
}
void LexNext(Compiler *cc) {
  LexNextInner(cc);
#ifndef BARE_METAL
  {
    static const char *tf = NULL; static int inited = 0;
    if (!inited) { tf = getenv("HOLYC_TOKTRACE"); inited = 1; }
    if (tf && cc->lex.filename && strstr(cc->lex.filename, tf))
      fprintf(stderr, "[tok] %s:%d tok=%d '%s' depth=%d\n", cc->lex.filename, cc->lex.line, cc->lex.token,
              (cc->lex.token == TK_IDENT || cc->lex.token == TK_STR) && cc->lex.token_str ? cc->lex.token_str : "", cc->lex.brace_depth);
  }
#endif
}
static void LexNextInner(Compiler *cc) {
  Lexer *lex = &cc->lex;
  lex->token_is_char = false;
  
  // Skip whitespace, comments, DolDoc, and preprocessor directives
  while (true) {
    SkipWhitespace(lex);
    if (lex->ptr[0] == '/' && (lex->ptr[1] == '/' || lex->ptr[1] == '*')) {
      SkipComment(lex);
    } else if (lex->ptr[0] == '$' && lex->ptr[1] == '$') {
      // `$$` in code: the current address (`Fs->rip=$$;`) or, in a class body, the offset.
      lex->ptr += 2; lex->col += 2; lex->token = TK_DOLLAR; return;
    } else if (lex->ptr[0] == '$' && lex->ptr[1] >= 'A' && lex->ptr[1] <= 'Z') {
      // A DolDoc command in code. `$IB,"…",BI=n$` embeds binary data (a sprite) and is an
      // expression: NULL here, the data is not carried. Others (`$SP…$` definitions) vanish.
      bool is_ib = (lex->ptr[1] == 'I' && lex->ptr[2] == 'B');
      SkipDolDoc(lex);
      if (is_ib) {
        lex->token = TK_I64; lex->token_i64 = 0; lex->token_is_char = false;
        if (lex->token_str) free(lex->token_str);
        lex->token_str = strdup(""); lex->token_str_len = 0;
        cc->asm_blocks_skipped++;
        return;
      }
    } else if (*lex->ptr == '#') {
      HandlePreprocessor(cc);
    } else {
      break;
    }
  }
  
  // If preprocessor says skip, consume tokens until #else or #endif
  if (cc->preprocessor_skip && *lex->ptr != '#') {
    // Skip lines until we hit a preprocessor directive
    while (*lex->ptr && *lex->ptr != '#') {
      if (*lex->ptr == '\n') {
        lex->line++;
        lex->col = 1;
      } else {
        lex->col++;
      }
      lex->ptr++;
    }
    if (*lex->ptr == '#') {
      // Process the directive (might be #endif or #else)
      HandlePreprocessor(cc);
      // Recurse to get next real token
      return LexNext(cc);
    }
  }
  
  // End of file - check if we need to pop include stack
  if (!*lex->ptr) {
    if (lex->include_stack) {
      // Pop back to previous file
      IncludeFile *inc = lex->include_stack;
      lex->include_stack = inc->next;
      
      // The finished buffer is intentionally not freed: a LexPush taken inside it may still
      // be restored after the lookahead ran past its end.
      
      // Restore previous file
      lex->src = inc->src;
      lex->ptr = inc->ptr;
      lex->filename = inc->filename;
      lex->line = inc->line;
      lex->col = inc->col;
      if (inc->has_pending) {   // a pushed string ended: resume with the token held back
        lex->token = inc->p_token; lex->token_i64 = inc->p_i64; lex->token_f64 = inc->p_f64;
        lex->token_is_char = inc->p_is_char; lex->token_str_len = inc->p_str_len; lex->hash_entry = inc->p_hash;
        if (lex->token_str) free(lex->token_str);
        lex->token_str = inc->p_str; inc->p_str = NULL; inc->has_pending = false;
        if (!lex->stack) free(inc);
        return;
      }
      // Keep the frame while a lookahead is pending: LexPopRestore re-links it if the
      // LexPush was taken inside this buffer (a macro's last token, `_intern IC_BT Bool …`).
#ifndef BARE_METAL
      if (getenv("HOLYC_TRACE") && lex->stack) fprintf(stderr, "[trace] frame pop with pending lookahead: back to %s:%d\n", lex->filename ? lex->filename : "?", lex->line);
#endif
      if (!lex->stack) free(inc);
      
      // Continue lexing from restored position
      return LexNext(cc);
    }
    
    // Really at EOF
    lex->token = TK_EOF;
    return;
  }
  
  // Identifier or keyword
  if ((*lex->ptr >= 'a' && *lex->ptr <= 'z') || (*lex->ptr >= 'A' && *lex->ptr <= 'Z') || *lex->ptr == '_' ||
      ((unsigned char)*lex->ptr >= 128 && (unsigned char)*lex->ptr != 0xEC && (unsigned char)*lex->ptr != 0xE3 &&
       !((unsigned char)lex->ptr[0] == 0xE2 && (unsigned char)lex->ptr[1] == 0x88) &&
       !((unsigned char)lex->ptr[0] == 0xCF && (unsigned char)lex->ptr[1] == 0x80))) {   // `µs`: TempleOS charset
    lex->token = LexIdentifier(cc);
    return;
  }
  
  // Number
  if ((*lex->ptr >= '0' && *lex->ptr <= '9') || (*lex->ptr == '.' && lex->ptr[1] >= '0' && lex->ptr[1] <= '9')) {
    lex->token = LexNumber(lex);
    return;
  }
  
  // String
  if (*lex->ptr == '"' || *lex->ptr == '\'') {
    lex->token = LexString(lex);
    return;
  }
  
  // Two-character operators
  if (lex->ptr[0] == '=' && lex->ptr[1] == '=') {
    lex->token = TK_EQU_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '!' && lex->ptr[1] == '=') {
    lex->token = TK_NOT_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '<' && lex->ptr[1] == '=') {
    lex->token = TK_LESS_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '>' && lex->ptr[1] == '=') {
    lex->token = TK_GREATER_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '<' && lex->ptr[1] == '<' && lex->ptr[2] == '=') {
    lex->token = TK_SHL_EQU;
    lex->ptr += 3;
    lex->col += 3;
    return;
  }
  if (lex->ptr[0] == '>' && lex->ptr[1] == '>' && lex->ptr[2] == '=') {
    lex->token = TK_SHR_EQU;
    lex->ptr += 3;
    lex->col += 3;
    return;
  }
  if (lex->ptr[0] == '%' && lex->ptr[1] == '=') {
    lex->token = TK_MOD_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '<' && lex->ptr[1] == '<') {
    lex->token = TK_SHL;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '>' && lex->ptr[1] == '>') {
    lex->token = TK_SHR;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '&' && lex->ptr[1] == '&') {
    lex->token = TK_AND_AND;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '|' && lex->ptr[1] == '|') {
    lex->token = TK_OR_OR;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '^' && lex->ptr[1] == '^') {
    lex->token = TK_XOR_XOR;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '+' && lex->ptr[1] == '+') {
    lex->token = TK_ADD_ADD;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '+' && lex->ptr[1] == '=') {
    lex->token = TK_ADD_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '-' && lex->ptr[1] == '-') {
    lex->token = TK_SUB_SUB;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '-' && lex->ptr[1] == '=') {
    lex->token = TK_SUB_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '-' && lex->ptr[1] == '>') {
    lex->token = TK_ARROW;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '*' && lex->ptr[1] == '=') {
    lex->token = TK_MUL_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '/' && lex->ptr[1] == '=') {
    lex->token = TK_DIV_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '&' && lex->ptr[1] == '=') {
    lex->token = TK_AND_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '|' && lex->ptr[1] == '=') {
    lex->token = TK_OR_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '^' && lex->ptr[1] == '=') {
    lex->token = TK_XOR_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == ':' && lex->ptr[1] == ':') {
    lex->token = TK_DBL_COLON;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '.' && lex->ptr[1] == '.' && lex->ptr[2] == '.') {
    lex->token = TK_ELLIPSIS;
    lex->ptr += 3;
    lex->col += 3;
    return;
  }
  
  // `π` (TempleOS char 0xE3, or UTF-8 CF 80): F64 pi literal
  if ((unsigned char)lex->ptr[0] == 0xE3 ||
      ((unsigned char)lex->ptr[0] == 0xCF && (unsigned char)lex->ptr[1] == 0x80)) {
    lex->ptr += ((unsigned char)lex->ptr[0] == 0xE3) ? 1 : 2;
    lex->col++;
    lex->token = TK_F64;
    lex->token_f64 = 3.141592653589793;
    return;
  }
  // `∞` (TempleOS char 0xEC, or UTF-8 on the host): F64 infinity literal
  if ((unsigned char)lex->ptr[0] == 0xEC ||
      ((unsigned char)lex->ptr[0] == 0xE2 && (unsigned char)lex->ptr[1] == 0x88 && (unsigned char)lex->ptr[2] == 0x9E)) {
    lex->ptr += ((unsigned char)lex->ptr[0] == 0xEC) ? 1 : 3;
    lex->col++;
    lex->token = TK_F64;
    lex->token_f64 = __builtin_inf();
    return;
  }
  // Single character
  lex->token = *lex->ptr++;
  lex->col++;
  if (lex->token == '{') lex->brace_depth++;
  else if (lex->token == '}') lex->brace_depth--;
}

bool LexExpect(Compiler *cc, int token) {
  if (cc->lex.token != token) {
    // Error: token mismatch (no stdio like HolyC)
    return false;
  }
  LexNext(cc);
  return true;
}

bool IsKeyword(const char *str) {
  for (int i = 0; keywords[i].name; i++) {
    if (strcmp(str, keywords[i].name) == 0) {
      return true;
    }
  }
  return false;
}

void Error(Compiler *cc, const char *msg) {
  if (!cc->error) {
    cc->error = strdup(msg);
    cc->error_line = cc->lex.line;
    cc->error_file = cc->lex.filename;
  }
  // No fprintf - HolyC doesn't use stdio
}

// ═══════════════════════════════════════════════════════════════
// LEXER STATE STACK (LexPush/LexPop)
// ═══════════════════════════════════════════════════════════════

void LexPush(Compiler *cc) {
  
  // Save current lexer state onto stack
  LexerStack *saved = calloc(1, sizeof(LexerStack));
  
  
  if (!saved) {
    // Allocation failed - can't save state
    // This will break lookahead, but prevents crash
    return;
  }
  
  
  // Check cc validity
  if (!cc) {
    free(saved);
    return;
  }
  
  
  saved->ptr = cc->lex.ptr;
  
  saved->line = cc->lex.line;
  saved->col = cc->lex.col;
  saved->token = cc->lex.token;
  saved->token_i64 = cc->lex.token_i64;
  saved->token_f64 = cc->lex.token_f64;
  
  
  if (cc->lex.token_str) {
    size_t n = (cc->lex.token == TK_STR) ? (size_t)cc->lex.token_str_len : strlen(cc->lex.token_str);
    saved->token_str = malloc(n + 1);
    memcpy(saved->token_str, cc->lex.token_str, n + 1);
  } else saved->token_str = NULL;
  saved->token_str_len = cc->lex.token_str_len;
  saved->brace_depth = cc->lex.brace_depth;
  
  
  saved->hash_entry = cc->lex.hash_entry;
  saved->src = cc->lex.src;
  saved->filename = cc->lex.filename;
  saved->include_stack = cc->lex.include_stack;
  
  
  // Push onto stack
  saved->next = cc->lex.stack;
  cc->lex.stack = saved;
  
}

void LexPopRestore(Compiler *cc) {
  // Restore lexer state from stack
  if (!cc->lex.stack) return;  // Nothing to restore
  
  LexerStack *saved = cc->lex.stack;
  
  // Unwind any #include / macro-expansion frames entered during the lookahead, so that
  // src/ptr describe the same buffer again (a macro used inside parentheses hits this).
  IncludeFile *f = cc->lex.include_stack;
  while (f && f != saved->include_stack) f = f->next;
  if (f == saved->include_stack) {
    while (cc->lex.include_stack != saved->include_stack) {
      IncludeFile *inc = cc->lex.include_stack;
      cc->lex.include_stack = inc->next;
      cc->lex.src = inc->src;
      cc->lex.filename = inc->filename;
      free(inc);
    }
    cc->lex.src = saved->src;
    cc->lex.filename = saved->filename;
  } else {
    // Frames finished during the lookahead were popped (kept alive above): re-link them so
    // the saved buffer resumes and then returns to the outer file where it left off.
    cc->lex.include_stack = saved->include_stack;
    cc->lex.src = saved->src;
    cc->lex.filename = saved->filename;
  }
  // Restore state
  cc->lex.ptr = saved->ptr;
  cc->lex.line = saved->line;
  cc->lex.col = saved->col;
  cc->lex.token = saved->token;
  cc->lex.token_i64 = saved->token_i64;
  cc->lex.token_f64 = saved->token_f64;
  
  // Free old token_str and restore saved one
  if (cc->lex.token_str) free(cc->lex.token_str);
  cc->lex.token_str = saved->token_str;  // Transfer ownership
  cc->lex.token_str_len = saved->token_str_len;
  cc->lex.brace_depth = saved->brace_depth;
  
  cc->lex.hash_entry = saved->hash_entry;
  
  // Pop from stack
  cc->lex.stack = saved->next;
  free(saved);
}

void LexPopNoRestore(Compiler *cc) {
  // Discard saved state without restoring
  if (!cc->lex.stack) return;
  
  LexerStack *saved = cc->lex.stack;
  
  // Free the saved token_str
  if (saved->token_str) free(saved->token_str);
  
  // Pop from stack
  cc->lex.stack = saved->next;
  free(saved);
}

