// Minimal UART Line Editor for Bootstrapping
// Simple line-based text editor and command interpreter

#define MAX_LINE_LEN 256
#define MAX_BUFFER_LINES 256
#define MAX_FILES 8

// Global editor state
U8 buffer[MAX_BUFFER_LINES][MAX_LINE_LEN];
I64 buffer_lines = 0;
I64 current_line = 0;
Bool insert_mode = TRUE;

// File storage
U8 *file_names[MAX_FILES];
U8 *file_data[MAX_FILES];
I64 file_sizes[MAX_FILES];
I64 num_files = 0;

// Command line editing
U8 cmd_buffer[MAX_LINE_LEN];
I64 cmd_pos = 0;

// Editor Functions

U0 EditorClear() {
  for (I64 i = 0; i < MAX_BUFFER_LINES; i++) {
    buffer[i][0] = 0;
  }
  buffer_lines = 0;
  current_line = 0;
}

U0 EditorInsertLine(U8 *line) {
  if (buffer_lines >= MAX_BUFFER_LINES) {
    uart_puts("ERROR: Buffer full!\n");
    return;
  }
  
  // Shift lines down
  for (I64 i = buffer_lines; i > current_line; i--) {
    strcpy(buffer[i], buffer[i-1]);
  }
  
  strcpy(buffer[current_line], line);
  buffer_lines++;
  current_line++;
}

U0 EditorDeleteLine() {
  if (current_line >= buffer_lines) {
    uart_puts("ERROR: No line to delete!\n");
    return;
  }
  
  // Shift lines up
  for (I64 i = current_line; i < buffer_lines - 1; i++) {
    strcpy(buffer[i], buffer[i+1]);
  }
  
  buffer_lines--;
  if (current_line >= buffer_lines) {
    current_line = buffer_lines - 1;
  }
  if (current_line < 0) {
    current_line = 0;
  }
}

U0 EditorList() {
  uart_puts("=== Buffer Contents ===\n");
  for (I64 i = 0; i < buffer_lines; i++) {
    if (i == current_line) {
      uart_puts(">");
    } else {
      uart_puts(" ");
    }
    uart_puti64(i);
    uart_puts(": ");
    uart_puts(buffer[i]);
    uart_puts("\n");
  }
  uart_puti64(buffer_lines);
  uart_puts(" lines total\n");
}

U0 EditorSave(U8 *filename) {
  if (num_files >= MAX_FILES) {
    uart_puts("ERROR: Too many files!\n");
    return;
  }
  
  // Calculate total size
  I64 total_size = 0;
  for (I64 i = 0; i < buffer_lines; i++) {
    total_size += strlen(buffer[i]) + 1;  // +1 for newline
  }
  
  // Allocate memory
  U8 *data = malloc(total_size + 1);
  if (!data) {
    uart_puts("ERROR: Out of memory!\n");
    return;
  }
  
  // Copy buffer to file data
  U8 *ptr = data;
  for (I64 i = 0; i < buffer_lines; i++) {
    strcpy(ptr, buffer[i]);
    ptr += strlen(buffer[i]);
    *ptr++ = '\n';
  }
  *ptr = 0;
  
  // Save file
  file_names[num_files] = strdup(filename);
  file_data[num_files] = data;
  file_sizes[num_files] = total_size;
  num_files++;
  
  uart_puts("Saved ");
  uart_puti64(buffer_lines);
  uart_puts(" lines (");
  uart_puti64(total_size);
  uart_puts(" bytes) to: ");
  uart_puts(filename);
  uart_puts("\n");
}

U0 EditorLoad(U8 *filename) {
  // Find file
  I64 file_idx = -1;
  for (I64 i = 0; i < num_files; i++) {
    if (strcmp(file_names[i], filename) == 0) {
      file_idx = i;
      break;
    }
  }
  
  if (file_idx < 0) {
    uart_puts("ERROR: File not found: ");
    uart_puts(filename);
    uart_puts("\n");
    return;
  }
  
  // Clear buffer
  EditorClear();
  
  // Load lines from file
  U8 *ptr = file_data[file_idx];
  U8 line_buf[MAX_LINE_LEN];
  I64 line_pos = 0;
  
  while (*ptr) {
    if (*ptr == '\n') {
      line_buf[line_pos] = 0;
      EditorInsertLine(line_buf);
      line_pos = 0;
    } else if (line_pos < MAX_LINE_LEN - 1) {
      line_buf[line_pos++] = *ptr;
    }
    ptr++;
  }
  
  // Add last line if not empty
  if (line_pos > 0) {
    line_buf[line_pos] = 0;
    EditorInsertLine(line_buf);
  }
  
  current_line = 0;
  
  uart_puts("Loaded ");
  uart_puti64(buffer_lines);
  uart_puts(" lines from: ");
  uart_puts(filename);
  uart_puts("\n");
}

U0 EditorCompile(U8 *filename) {
  uart_puts("Compiling: ");
  uart_puts(filename);
  uart_puts("\n");
  
  // TODO: Call compiler
  // For now, just print that we would compile
  uart_puts("TODO: Integrate with holyc-riscv compiler\n");
}

U0 EditorListFiles() {
  uart_puts("=== Stored Files ===\n");
  for (I64 i = 0; i < num_files; i++) {
    uart_puts(file_names[i]);
    uart_puts(" (");
    uart_puti64(file_sizes[i]);
    uart_puts(" bytes)\n");
  }
  uart_puti64(num_files);
  uart_puts(" files total\n");
}

U0 EditorHelp() {
  uart_puts("\n=== Editor Commands ===\n");
  uart_puts("i <text>     - Insert line at current position\n");
  uart_puts("d            - Delete current line\n");
  uart_puts("l            - List buffer contents\n");
  uart_puts("g <line>     - Go to line number\n");
  uart_puts("s <file>     - Save buffer to file\n");
  uart_puts("o <file>     - Open (load) file\n");
  uart_puts("c <file>     - Compile file\n");
  uart_puts("f            - List stored files\n");
  uart_puts("n            - New (clear buffer)\n");
  uart_puts("h            - Show this help\n");
  uart_puts("q            - Quit editor\n");
  uart_puts("\nDirect text entry: Lines not starting with command are inserted\n\n");
}

U0 EditorProcessCommand(U8 *cmd) {
  // Skip leading whitespace
  while (*cmd == ' ' || *cmd == '\t') cmd++;
  
  if (!*cmd) return;  // Empty command
  
  // Parse command
  U8 cmd_char = *cmd++;
  while (*cmd == ' ' || *cmd == '\t') cmd++;  // Skip whitespace after command
  
  switch (cmd_char) {
    case 'i':  // Insert line
      if (*cmd) {
        EditorInsertLine(cmd);
        uart_puts("Inserted line ");
        uart_puti64(current_line - 1);
        uart_puts("\n");
      } else {
        uart_puts("ERROR: i command requires text\n");
      }
      break;
      
    case 'd':  // Delete line
      EditorDeleteLine();
      uart_puts("Deleted line\n");
      break;
      
    case 'l':  // List buffer
      EditorList();
      break;
      
    case 'g':  // Go to line
      if (*cmd) {
        I64 line = atoi(cmd);
        if (line >= 0 && line < buffer_lines) {
          current_line = line;
          uart_puts("Current line: ");
          uart_puti64(current_line);
          uart_puts("\n");
        } else {
          uart_puts("ERROR: Invalid line number\n");
        }
      } else {
        uart_puts("ERROR: g command requires line number\n");
      }
      break;
      
    case 's':  // Save file
      if (*cmd) {
        EditorSave(cmd);
      } else {
        uart_puts("ERROR: s command requires filename\n");
      }
      break;
      
    case 'o':  // Open file
      if (*cmd) {
        EditorLoad(cmd);
      } else {
        uart_puts("ERROR: o command requires filename\n");
      }
      break;
      
    case 'c':  // Compile file
      if (*cmd) {
        EditorCompile(cmd);
      } else {
        uart_puts("ERROR: c command requires filename\n");
      }
      break;
      
    case 'f':  // List files
      EditorListFiles();
      break;
      
    case 'n':  // New buffer
      EditorClear();
      uart_puts("Buffer cleared\n");
      break;
      
    case 'h':  // Help
      EditorHelp();
      break;
      
    case 'q':  // Quit
      uart_puts("Quit not implemented (would exit to OS)\n");
      break;
      
    default:
      // Not a command - insert as text
      cmd--;  // Back up to include the first character
      EditorInsertLine(cmd);
      uart_puts("Inserted line ");
      uart_puti64(current_line - 1);
      uart_puts("\n");
  }
}

U0 EditorReadLine() {
  cmd_pos = 0;
  uart_puts("> ");
  
  while (TRUE) {
    U8 ch = uart_getc();
    
    if (ch == '\r' || ch == '\n') {
      uart_puts("\n");
      cmd_buffer[cmd_pos] = 0;
      return;
    } else if (ch == 127 || ch == 8) {  // Backspace or DEL
      if (cmd_pos > 0) {
        cmd_pos--;
        uart_putc('\b');
        uart_putc(' ');
        uart_putc('\b');
      }
    } else if (ch == 3) {  // Ctrl-C
      uart_puts("^C\n");
      cmd_buffer[0] = 0;
      return;
    } else if (ch >= 32 && ch < 127) {  // Printable character
      if (cmd_pos < MAX_LINE_LEN - 1) {
        cmd_buffer[cmd_pos++] = ch;
        uart_putc(ch);
      }
    }
  }
}

U0 EditorMain() {
  RuntimeInit();
  
  uart_puts("\n=== TempleOS UART Editor ===\n");
  uart_puts("Type 'h' for help\n\n");
  
  EditorClear();
  
  while (TRUE) {
    EditorReadLine();
    EditorProcessCommand(cmd_buffer);
  }
}


