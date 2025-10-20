/* HolyC Lexer - Tokenizes HolyC source code */

#include "holyc_compiler.h"
#include <ctype.h>

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
  // Skip DolDoc formatting sequences: $$...$$
  if (lex->ptr[0] == '$' && lex->ptr[1] == '$') {
    lex->ptr += 2;
    lex->col += 2;
    
    // Skip until we find the closing $$
    while (*lex->ptr && !(lex->ptr[0] == '$' && lex->ptr[1] == '$')) {
      if (*lex->ptr == '\n') {
        lex->line++;
        lex->col = 1;
      } else {
        lex->col++;
      }
      lex->ptr++;
    }
    
    // Skip the closing $$
    if (lex->ptr[0] == '$' && lex->ptr[1] == '$') {
      lex->ptr += 2;
      lex->col += 2;
    }
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
  while (isalpha(*lex->ptr) && i < 63) {
    directive[i++] = *lex->ptr++;
    lex->col++;
  }
  directive[i] = '\0';
  
  if (strcmp(directive, "define") == 0) {
    // Parse #define NAME VALUE
    
    // Skip whitespace
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Get macro name
    char name[256];
    i = 0;
    while ((isalnum(*lex->ptr) || *lex->ptr == '_') && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';
    
    // Skip whitespace
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Get replacement text (rest of line)
    char value[1024];
    i = 0;
    while (*lex->ptr && *lex->ptr != '\n' && i < 1023) {
      value[i++] = *lex->ptr++;
      lex->col++;
    }
    value[i] = '\0';
    
    // Trim trailing whitespace
    while (i > 0 && (value[i-1] == ' ' || value[i-1] == '\t')) {
      value[--i] = '\0';
    }
    
    // Add to define table
    CHashDefine *def = calloc(1, sizeof(CHashDefine));
    def->str = strdup(name);
    def->type = HTT_DEFINE_STR;
    def->data = strdup(value);
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
    
    // Read the file
    FILE *f = fopen(filename, "r");
    if (!f) {
      // Try adding .HC extension (no snprintf like HolyC)
      // In bare metal, #include not supported
      f = NULL;
    }
    
    if (f) {
      // Get file size
      fseek(f, 0, SEEK_END);
      long fsize = ftell(f);
      fseek(f, 0, SEEK_SET);
      
      // Read file
      char *include_src = malloc(fsize + 1);
      fread(include_src, 1, fsize, f);
      include_src[fsize] = '\0';
      fclose(f);
      
      // Push current file onto include stack
      IncludeFile *inc = calloc(1, sizeof(IncludeFile));
      inc->src = lex->src;
      inc->ptr = lex->ptr;
      inc->filename = lex->filename;
      inc->line = lex->line;
      inc->col = lex->col;
      inc->next = lex->include_stack;
      lex->include_stack = inc;
      
      // Switch to included file
      lex->src = include_src;
      lex->ptr = include_src;
      lex->filename = strdup(filename);
      lex->line = 1;
      lex->col = 1;
      
      return;  // Don't skip to next line
    }
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
    while ((isalnum(*lex->ptr) || *lex->ptr == '_') && i < 255) {
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
    while ((isalnum(*lex->ptr) || *lex->ptr == '_') && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';
    
    // Remove from define table
    CHashEntry *entry = HashFind(name, cc->define_table, HTT_DEFINE_STR);
    if (entry) {
      // TODO: Proper hash table removal
      // For now, just mark it as removed by clearing the data
      CHashDefine *def = (CHashDefine*)entry;
      if (def->data) {
        free(def->data);
        def->data = strdup("");
      }
    }
  }

skip_line:
  
  // Skip to end of line for all directives
  while (*lex->ptr && *lex->ptr != '\n') {
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
          if (*body == '#' && (isalpha(body[1]) || body[1] == '_')) {
            body++;  // Skip '#'
            
            // Get parameter name
            char param_name[64];
            int pn_len = 0;
            while ((isalnum(*body) || *body == '_') && pn_len < 63) {
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
          
          if (isalpha(*body) || *body == '_') {
            // Possible parameter name
            char param_name[64];
            int pn_len = 0;
            char *temp = body;
            
            while ((isalnum(*temp) || *temp == '_') && pn_len < 63) {
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
      if (lex->token_str) free(lex->token_str);
      lex->token_str = strdup(def->data);
      
      // Try to parse the macro value as a number
      char *endptr;
      I64 ival = strtoll(def->data, &endptr, 0);
      if (*endptr == '\0') {
        // It's a number
        lex->token_i64 = ival;
        return TK_I64;
      }
      
      // Otherwise return as identifier (will be looked up again)
      return TK_IDENT;
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
  bool is_hex = false;
  
  // Check for 0x prefix
  if (lex->ptr[0] == '0' && (lex->ptr[1] == 'x' || lex->ptr[1] == 'X')) {
    is_hex = true;
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
  } else {
    // Parse decimal digits manually (no atoll in bare metal)
    while (*lex->ptr >= '0' && *lex->ptr <= '9') {
      value = value * 10 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  }
  
  lex->token_i64 = value;
  return TK_I64;
}

static int LexString(Lexer *lex) {
  char buf[1024];
  int len = 0;
  char quote = *lex->ptr++;
  lex->col++;
  
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
        case 'd': // \d = $$ (DolDoc escape)
          buf[len++] = '$';
          buf[len++] = '$';
          break;
        default: buf[len++] = *lex->ptr;
      }
      lex->ptr++;
      lex->col++;
    } else if (*lex->ptr == '$' && lex->ptr[1] == '$') {
      // DolDoc formatting sequence: $$...$$
      // Skip the opening $$
      lex->ptr += 2;
      lex->col += 2;
      
      // Skip until we find the closing $$
      while (*lex->ptr && !(*lex->ptr == '$' && lex->ptr[1] == '$')) {
        if (*lex->ptr == '\n') {
          lex->line++;
          lex->col = 1;
        } else {
          lex->col++;
        }
        lex->ptr++;
      }
      
      // Skip the closing $$
      if (*lex->ptr == '$' && lex->ptr[1] == '$') {
        lex->ptr += 2;
        lex->col += 2;
      }
      
      // Don't add DolDoc content to the string - just skip it
    } else {
      buf[len++] = *lex->ptr++;
      lex->col++;
    }
  }
  
  if (*lex->ptr == quote) {
    lex->ptr++;
    lex->col++;
  }
  
  buf[len] = '\0';
  if (lex->token_str) free(lex->token_str);
  lex->token_str = strdup(buf);
  return TK_STR;
}

void LexNext(Compiler *cc) {
  Lexer *lex = &cc->lex;
  
  // Skip whitespace, comments, DolDoc, and preprocessor directives
  while (true) {
    SkipWhitespace(lex);
    if (lex->ptr[0] == '/' && (lex->ptr[1] == '/' || lex->ptr[1] == '*')) {
      SkipComment(lex);
    } else if (lex->ptr[0] == '$' && lex->ptr[1] == '$') {
      SkipDolDoc(lex);
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
      
      // Free included file
      free(lex->src);
      free(lex->filename);
      
      // Restore previous file
      lex->src = inc->src;
      lex->ptr = inc->ptr;
      lex->filename = inc->filename;
      lex->line = inc->line;
      lex->col = inc->col;
      
      free(inc);
      
      // Continue lexing from restored position
      return LexNext(cc);
    }
    
    // Really at EOF
    lex->token = TK_EOF;
    return;
  }
  
  // Identifier or keyword
  if ((*lex->ptr >= 'a' && *lex->ptr <= 'z') || (*lex->ptr >= 'A' && *lex->ptr <= 'Z') || *lex->ptr == '_') {
    lex->token = LexIdentifier(cc);
    return;
  }
  
  // Number
  if (*lex->ptr >= '0' && *lex->ptr <= '9') {
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
  
  // Single character
  lex->token = *lex->ptr++;
  lex->col++;
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
  
  
  saved->token_str = cc->lex.token_str ? strdup(cc->lex.token_str) : NULL;
  
  
  saved->hash_entry = cc->lex.hash_entry;
  
  
  // Push onto stack
  saved->next = cc->lex.stack;
  cc->lex.stack = saved;
  
}

void LexPopRestore(Compiler *cc) {
  // Restore lexer state from stack
  if (!cc->lex.stack) return;  // Nothing to restore
  
  LexerStack *saved = cc->lex.stack;
  
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

