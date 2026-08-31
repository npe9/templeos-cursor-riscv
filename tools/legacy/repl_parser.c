/* Cicl REPL Parser - Based on TempleOS LexStmt2Bin (CMain.HC:1-33) */

#include "holyc_compiler.h"
#include <stdlib.h>
#include <string.h>

/* Parse and compile one REPL statement
 * This is like TempleOS LexStmt2Bin - compile one statement, execute immediately
 * 
 * TempleOS pattern (CMain.HC:1-33):
 *   - COCInit() - Initialize code context
 *   - PrsStmt() - Parse ONE statement
 *   - ICAdd(IC_RETURN_VAL2/IC_RET) - Add return
 *   - COCCompile() - Generate machine code
 */

bool ParseREPLStatement(Compiler *cc) {
  // Clear any previous IC list
  cc->ic_head = NULL;
  cc->ic_tail = NULL;
  
  // Parse one statement (match TempleOS LexStmt2Bin:10)
  if (!ParseStatement(cc)) {
    return false;
  }
  
  // Add implicit return (match TempleOS LexStmt2Bin:11-14)
  // The statement result is on the stack, return it
  ICAdd(cc, IC_RETURN_VAL, 0, RT_I64);
  ICAdd(cc, IC_RET, 0, RT_I64);
  
  return true;
}

