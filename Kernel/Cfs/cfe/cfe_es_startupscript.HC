/************************************************************************
 * NASA Docket No. GSC-19,200-1, and identified as "cFS Draco"
 *
 * Copyright (c) 2023 United States Government as represented by the
 * Administrator of the National Aeronautics and Space Administration.
 * All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License. You may obtain
 * a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ************************************************************************/
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_startupscript.c -- HOW A SPACECRAFT
// DECIDES WHAT TO RUN.
//
// Four functions, and they are the only thing between a text file on disk and the set of
// applications a flight computer boots with. Each line of the script is eight comma-separated
// fields terminated by a semicolon:
//
//     CFE_APP, /cf/sch.so, SCH_AppMain, SCH, 80, 16384, 0x0, 0;
//     CFE_LIB, /cf/cfs_lib.so, CFS_LibInit, CFS_LIB, 0, 0, 0x0, 0;
//
// and the parser is deliberately forgiving in ways worth naming, because each one is a decision
// about what a half-written script does to a vehicle.
//
// A '!' ENDS THE FILE, wherever it appears, and NASA treats it exactly like a read returning
// zero -- "EOF reported from OSAL is treated the same as the EOF from a ! char". So a script can
// be truncated on purpose, and a script whose tail is garbage can be cut off by one character.
//
// WHITESPACE IS NOT A DELIMITER, isgraph is. Every non-printing byte is dropped rather than
// ending a token, which is what lets the file be written with spaces and newlines between
// fields. The delimiters are ',' and ';' and nothing else.
//
// A MALFORMED LINE IS LOGGED AND SKIPPED, never fatal, and the detection is a trick worth
// keeping: both the line buffer and the token list are declared ONE LARGER than the allowed
// maximum, so "did we fill it" IS "was the input too long". NASA's comment says so -- "because
// both of these buffers are sized +1 from the allowed amount, it means if we filled it, then
// the input was too long".
//
// AND THE VOLATILE SCRIPT WINS ON A PROCESSOR RESET. CFE_ES_OpenStartupScript tries
// /ram/cfe_es_startup.scr first and falls back to the nonvolatile one, which is how a ground
// operator changes what the next processor reset boots without touching the flight disk.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC    CFE_ES_AppStartParams_t
//     cfe_fs_api.HC       CFE_FS_ParseInputFileName and the file categories
//     cfe_es_apps.HC      CFE_ES_AppCreate and CFE_ES_LoadLibrary, which this file exists to call
//     ../CfsStr.HC        StrToUL and IsGraph, cFS's two borrowed C-library primitives
#ifndef CFE_ES_STARTUPSCRIPT_HC
#define CFE_ES_STARTUPSCRIPT_HC
// --- cfe_es_startupscript.h -----------------------------------------------------------------
#define CFE_ES_STARTSCRIPT_MAX_TOKENS_PER_LINE 8
#define CFE_ES_START_BUFF_SIZE                 128
// --- cfe_es_internal_cfg.h ------------------------------------------------------------------
// `CFE_PLATFORM_ES_CFGVAL(VOLATILE_STARTUP_FILE)` upstream, which this configuration resolves
// to the RAM disk's copy of the script.
#ifndef CFE_PLATFORM_ES_VOLATILE_STARTUP_FILE
#define CFE_PLATFORM_ES_VOLATILE_STARTUP_FILE "/ram/cfe_es_startup.scr"
#endif
// --- osapi-file.h ---------------------------------------------------------------------------
#ifndef OS_FILE_FLAG_NONE
#define OS_FILE_FLAG_NONE 0x00
#endif
// --- osconfig.h -----------------------------------------------------------------------------
// The clamp for a startup-script priority field. cfe_es_global.HC names it too, under the same
// guard -- one definition per name, which is the lesson cfe_es_cds.HC records.
#ifndef OS_MAX_TASK_PRIORITY
#define OS_MAX_TASK_PRIORITY 255
#endif
// --- what this file needs from elsewhere ----------------------------------------------------
// CFE_ES_StartApplications calls the parser, which is defined after it.
I32 CFE_ES_ParseFileEntry(U8 **TokenList, U32 NumTokens);

/*----------------------------------------------------------------
 *
 * Local helper function
 * Opens the startup script file
 *
 *-----------------------------------------------------------------*/
// TWO CHANCES, AND THE ORDER IS THE POLICY. On a PROCESSOR reset the volatile copy is tried
// first, so a script written to the RAM disk by a ground command is what the next reset runs;
// on a power-on reset there is no volatile disk worth reading and only the nonvolatile path is
// tried. The fallback is unconditional, so a volatile script that is missing or unreadable
// costs one log line and nothing else.
//
// IT RETURNS AN UNDEFINED ID RATHER THAN A STATUS, and the caller tests it with
// OS_ObjectIdDefined -- so "no script" and "a script that will not open" are the same thing to
// the caller, which is why both paths log before giving up.
U32 CFE_ES_OpenStartupScript(U32 ResetType, U8 *StartFilePath)
{
  U8 ScriptFileName[OS_MAX_PATH_LEN];
  U32 AppFile;
  I32 Status;
  I32 OsStatus;
  Bool FileOpened;
  FileOpened = FALSE;
  /*
  ** Get the ES startup script filename.
  ** If this is a Processor Reset, try to open the file in the volatile disk first.
  */
  if (ResetType == CFE_PSP_RST_TYPE_PROCESSOR) {
    /*
    ** First Attempt to parse as file in the volatile disk (temp area).
    */
    Status = CFE_FS_ParseInputFileName(ScriptFileName, CFE_PLATFORM_ES_VOLATILE_STARTUP_FILE,
                                       OS_MAX_PATH_LEN, CFE_FS_FileCategory_TEMP);
    if (Status == CFE_SUCCESS) {
      OsStatus = OS_OpenCreate(&AppFile, ScriptFileName, OS_FILE_FLAG_NONE, OS_READ_ONLY);
      if (OsStatus == OS_SUCCESS) {
        FileOpened = TRUE;
      } else {
        CFE_ES_WriteToSysLog("%s: Cannot Open Volatile Startup file: %s, Trying Nonvolatile.\n",
                             "CFE_ES_OpenStartupScript", ScriptFileName);
      }
    } else {
      /* not expected -- likely a misconfiguration in CFE_PLATFORM_ES_VOLATILE_STARTUP_FILE setting */
      CFE_ES_WriteToSysLog("%s: CFE_FS_ParseInputFileName() RC=%08x parsing volatile script file name.\n",
                           "CFE_ES_OpenStartupScript", Status);
    }
  }
  /*
  ** This if block covers two cases: A Power on reset, and a Processor reset when
  ** the startup file on the volatile file system could not be opened.
  */
  if (!FileOpened) {
    /*
    ** Try to Open the file passed in to the cFE start.
    */
    Status = CFE_FS_ParseInputFileName(ScriptFileName, StartFilePath, OS_MAX_PATH_LEN,
                                       CFE_FS_FileCategory_SCRIPT);
    if (Status == CFE_SUCCESS) {
      OsStatus = OS_OpenCreate(&AppFile, ScriptFileName, OS_FILE_FLAG_NONE, OS_READ_ONLY);
      if (OsStatus == OS_SUCCESS) {
        FileOpened = TRUE;
      } else {
        CFE_ES_WriteToSysLog("%s: Error, Can't Open ES App Startup file: %s, EC = %ld\n",
                             "CFE_ES_OpenStartupScript", ScriptFileName, OsStatus);
      }
    } else {
      /* not expected -- likely a misconfiguration in the user-supplied StartFilePath */
      CFE_ES_WriteToSysLog("%s: CFE_FS_ParseInputFileName() RC=%08x parsing StartFilePath.\n",
                           "CFE_ES_OpenStartupScript", Status);
    }
  }
  if (FileOpened) {
    CFE_ES_WriteToSysLog("%s: Opened ES App Startup file: %s\n", "CFE_ES_OpenStartupScript",
                         ScriptFileName);
  } else {
    /* be sure to return undefined if this did not work */
    AppFile = OS_OBJECT_ID_UNDEFINED;
  }
  return AppFile;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Reads a single line from the startup script
 *
 *-----------------------------------------------------------------*/
// ONE BYTE AT A TIME, AND THE RETURN VALUE CARRIES THREE ANSWERS: negative is a read error,
// zero is end of file, positive is "a line ended at a ';'". The caller's loop condition is
// `while (OsStatus > 0)`, so the distinction between the last two is what stops the walk.
//
// THE TOKENS ARE POINTERS INTO THE CALLER'S BUFFER, built by overwriting each ',' with a NUL as
// it is read -- so the line is split in place and no copying happens. The caller passes
// &TokenList[1] because it has already set TokenList[0] to the start of the buffer.
//
// AND THE TERMINATING NUL IS RESERVED BEFORE THE LOOP STARTS: `--EndPtr` with NASA's comment
// "Save 1 char for the terminating NULL, always required". Everything past the buffer is
// dropped rather than truncating the line, which is what the caller's length check then
// notices.
I32 CFE_ES_ReadStartupLine(U32 AppFile, U8 **TokenList, I64 *NumTokensPtr, U8 *BuffPtr,
                           I64 *BuffSizePtr)
{
  I32 OsStatus;
  U8 c;
  U8 *CurrPtr;
  U8 *EndPtr;
  U8 **CurrTokenPtr;
  U8 **LastTokenPtr;
  /* placeholder values - overwritten later */
  OsStatus = OS_ERROR;
  CurrPtr = BuffPtr;
  EndPtr = CurrPtr + *BuffSizePtr;
  CurrTokenPtr = TokenList;
  LastTokenPtr = CurrTokenPtr + *NumTokensPtr;
  --EndPtr; /* Save 1 char for the terminating NULL, always required */
  while (1) {
    c = 0;
    OsStatus = OS_read(AppFile, &c, 1);
    if (OsStatus < OS_SUCCESS) {
      /* Leave OsStatus with error code - will be returned */
      break;
    }
    if (OsStatus == 0 || c == '!') {
      /* End of file marker */
      /* EOF reported from OSAL is treated the same as the EOF from a ! char */
      OsStatus = 0;
      break;
    }
    if (c == ';') {
      /* End of Line Reached, OsStatus will be left >0 */
      break;
    }
    /* process all other chars, if buffer space permits */
    if (CurrPtr < EndPtr) {
      if (c == ',') {
        /*
        ** replace the field delimiter with a null
        ** This is used to separate the tokens
        */
        *CurrPtr = 0;
        ++CurrPtr;
        if (CurrTokenPtr < LastTokenPtr) {
          *CurrTokenPtr = CurrPtr;
          ++CurrTokenPtr;
        }
      } else if (IsGraph(c)) {
        /* store normal (non-space) chars */
        *CurrPtr = c;
        ++CurrPtr;
      }
    }
  }
  /* space for this terminating NUL was reserved at the beginning */
  *CurrPtr = 0;
  *NumTokensPtr = CurrTokenPtr - TokenList;
  *BuffSizePtr = CurrPtr - BuffPtr;
  return OsStatus;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE BUFFERS ARE ONE BYTE AND ONE TOKEN LARGER THAN THE MAXIMUM, ON PURPOSE, and that is the
// whole malformed-line detector: filling them is the same event as overrunning them. NASA:
// "because both of these buffers are sized +1 from the allowed amount, it means if we filled
// it, then the input was too long."
//
// A MALFORMED LINE DOES NOT STOP THE BOOT -- it is logged and skipped, and NumLines is not
// incremented, so the warning's line number counts GOOD lines rather than file lines. That is
// NASA's, and it means the number in the log is not the line a text editor would show.
//
// A READ ERROR DOES stop it, because the file is no longer trustworthy. End of file does not
// warn at all: it is the normal way the loop ends.
U0 CFE_ES_StartApplications(U32 ResetType, U8 *StartFilePath)
{
  U8 ES_AppLoadBuffer[CFE_ES_START_BUFF_SIZE + 1]; /* A buffer of for a line in a file */
  U8 *TokenList[CFE_ES_STARTSCRIPT_MAX_TOKENS_PER_LINE + 1];
  I64 NumTokens;
  I64 NumLines;
  I64 BuffLen; /* Length of the current buffer */
  U32 AppFile = OS_OBJECT_ID_UNDEFINED;
  I32 OsStatus;
  /* There may be more than one startup script - this finds and opens the correct one */
  AppFile = CFE_ES_OpenStartupScript(ResetType, StartFilePath);
  /*
  ** If the file is opened in either the Nonvolatile or the Volatile disk, process it.
  */
  if (OS_ObjectIdDefined(AppFile)) {
    MemSet(ES_AppLoadBuffer, 0x0, CFE_ES_START_BUFF_SIZE + 1);
    NumLines = 0;
    /*
    ** Parse the lines from the file. If it has an error
    ** or reaches EOF, then abort the loop.
    */
    do {
      /* The first token is always assumed to be at the beginning of the line */
      TokenList[0] = ES_AppLoadBuffer;
      NumTokens = CFE_ES_STARTSCRIPT_MAX_TOKENS_PER_LINE;
      BuffLen = CFE_ES_START_BUFF_SIZE + 1;
      OsStatus = CFE_ES_ReadStartupLine(AppFile, &TokenList[1], &NumTokens, ES_AppLoadBuffer,
                                        &BuffLen);
      if (OsStatus < OS_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Error Reading Startup file. EC = %ld\n",
                             "CFE_ES_StartApplications", OsStatus);
        break;
      }
      /* Note: because both of these buffers are sized +1 from the allowed amount,
       * it means if we filled it, then the input was too long */
      if (BuffLen >= CFE_ES_START_BUFF_SIZE ||
          NumTokens >= CFE_ES_STARTSCRIPT_MAX_TOKENS_PER_LINE) {
        /* The line was not formed correctly */
        CFE_ES_WriteToSysLog("%s: **WARNING** File Line %u is malformed: %u bytes, %u tokens.\n",
                             "CFE_ES_StartApplications", NumLines + 1, BuffLen, NumTokens);
      } else if (NumTokens > 0) {
        /* Send the line to the file parser */
        CFE_ES_ParseFileEntry(TokenList, 1 + NumTokens);
        ++NumLines;
      }
    } while (OsStatus > 0);
    /*
    ** close the file
    */
    OS_close(AppFile);
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// EIGHT FIELDS, AND ONLY FOUR OF THEM ARE READ FOR A LIBRARY. Field 0 is the entry type, 1 the
// file, 2 the entry symbol, 3 the module name; a CFE_APP also reads 4 (priority), 5 (stack) and
// 7 (exception action). FIELD 6 IS NEVER READ BY ANYTHING -- it is reserved, and a script that
// puts something meaningful there is writing to nobody.
//
// THE RANGE CHECKS ARE CLAMPS, NOT REFUSALS, which is the decision this function is really
// about. A priority over OS_MAX_TASK_PRIORITY becomes OS_MAX_TASK_PRIORITY; any exception
// action above RESTART_APP becomes PROC_RESTART, with NASA's reasoning kept verbatim -- "If
// it's non-zero, assume it means reset CPU". So a typo in the exception field makes the
// spacecraft MORE willing to reset itself, never less. The stack size is passed through with no
// limit at all: "No specific upper/lower limit for stack size - will pass value through".
//
// AN UNKNOWN ENTRY TYPE IS CFE_ES_ERR_APP_CREATE, not a parse error, because by the time the
// type is read everything else has already been accepted.
I32 CFE_ES_ParseFileEntry(U8 **TokenList, U32 NumTokens)
{
  U8 *ModuleName;
  U8 *EntryType;
  U64 ParsedValue;
  // NASA uses `union { CFE_ES_AppId_t AppId; CFE_ES_LibId_t LibId; } IdBuf;` -- two names for
  // one word, chosen by which branch runs. Both are CFE_ResourceId_t underneath and this port
  // represents every resource id as a U32, so the union has nothing to overlay: one variable.
  U32 IdBuf;
  I32 Status;
  CFE_ES_AppStartParams_t ParamBuf;
  MemSet(&ParamBuf, 0, sizeof(CFE_ES_AppStartParams_t));
  /*
  ** Check to see if the correct number of items were parsed
  */
  if (NumTokens < 8) {
    CFE_ES_WriteToSysLog("%s: Invalid ES Startup file entry: %u\n", "CFE_ES_ParseFileEntry",
                         NumTokens);
    return CFE_ES_BAD_ARGUMENT;
  }
  /* Get pointers to specific tokens that are simple strings used as-is */
  EntryType = TokenList[0];
  ModuleName = TokenList[3];
  /*
   * Other tokens will need to be scrubbed/converted.
   * Both Libraries and Apps use File Name (1) and Symbol Name (2) fields so copy those now
   */
  MemSet(&ParamBuf, 0, sizeof(CFE_ES_AppStartParams_t));
  Status = CFE_FS_ParseInputFileName(ParamBuf.BasicInfo.FileName, TokenList[1], OS_MAX_PATH_LEN,
                                     CFE_FS_FileCategory_DYNAMIC_MODULE);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Invalid ES Startup script file name: %s\n",
                         "CFE_ES_ParseFileEntry", TokenList[1]);
    return Status;
  }
  StrNCpy(ParamBuf.BasicInfo.InitSymbolName, TokenList[2], OS_MAX_API_NAME - 1);
  if (StrCmp(EntryType, "CFE_APP") == 0) {
    CFE_ES_WriteToSysLog("%s: Loading file: %s, APP: %s\n", "CFE_ES_ParseFileEntry",
                         ParamBuf.BasicInfo.FileName, ModuleName);
    /*
     * Priority and Exception action have limited ranges, which is checked here
     * Task priority cannot be bigger than OS_MAX_TASK_PRIORITY
     */
    ParsedValue = StrToUL(TokenList[4]);
    if (ParsedValue > OS_MAX_TASK_PRIORITY) {
      ParamBuf.MainTaskInfo.Priority = OS_MAX_TASK_PRIORITY;
    } else {
      /* convert parsed value to correct type */
      ParamBuf.MainTaskInfo.Priority = ParsedValue;
    }
    /* No specific upper/lower limit for stack size - will pass value through */
    ParamBuf.MainTaskInfo.StackSize = StrToUL(TokenList[5]);
    /*
    ** Validate Some parameters
    ** Exception action should be 0 ( Restart App ) or
    ** 1 ( Processor reset ). If it's non-zero, assume it means
    ** reset CPU.
    */
    ParsedValue = StrToUL(TokenList[7]);
    if (ParsedValue > CFE_ES_ExceptionAction_RESTART_APP) {
      ParamBuf.ExceptionAction = CFE_ES_ExceptionAction_PROC_RESTART;
    } else {
      /* convert parsed value to correct type */
      ParamBuf.ExceptionAction = ParsedValue;
    }
    /*
    ** Now create the application
    */
    Status = CFE_ES_AppCreate(&IdBuf, ModuleName, &ParamBuf);
  } else if (StrCmp(EntryType, "CFE_LIB") == 0) {
    CFE_ES_WriteToSysLog("%s: Loading shared library: %s\n", "CFE_ES_ParseFileEntry",
                         ParamBuf.BasicInfo.FileName);
    /*
    ** Now load the library
    */
    Status = CFE_ES_LoadLibrary(&IdBuf, ModuleName, &ParamBuf.BasicInfo);
  } else {
    CFE_ES_WriteToSysLog("%s: Unexpected EntryType %s in startup file.\n",
                         "CFE_ES_ParseFileEntry", EntryType);
    Status = CFE_ES_ERR_APP_CREATE;
  }
  return Status;
}
#endif
