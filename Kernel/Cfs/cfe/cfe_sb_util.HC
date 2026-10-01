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

// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_util.c -- the software bus's own
// accessors for reading and writing message header fields, sitting directly on the message
// module translated in this directory.
//
// TWO CROSS-MODULE CALLS, and they are the whole dependency list for this file (measured by
// grepping it for CFE_<other module>_ symbols rather than by reading its includes -- it pulls
// the umbrella header cfe_sb_module_all.h, which makes an include-based dependency count say
// zero and mean nothing):
//   CFE_TIME_GetTime        declared in cfe_time_api.HC, supplied by whoever links this
//   CFE_ES_WriteToSysLog    a printf-style log sink, declared here and stubbed by the harness
//
// CFE_ES_WriteToSysLog IS VARIADIC HERE, and every call site passes NASA's own arguments. It
// used to take a plain string, with the wording left outside the comparison -- that was
// defensible while there was no formatter, and StrPrintNV is the formatter now. HolyC has no
// __func__, so each site writes the enclosing function's NAME into the literal where NASA
// writes "%s" and passes `__func__`. That is not an approximation: __func__ expands to exactly
// that name, so the two produce the same characters, and the transcript compares them.
#ifndef CFE_SB_UTIL_HC
#define CFE_SB_UTIL_HC
#include "cfe_time_api.HC"
#include "cfe_sb_msgid.HC"
// From cfe_error.h.
#define CFE_SB_BAD_ARGUMENT 0xCA000003(I32)
// From cmake/sample_defs/example_mission_cfg.h, reaching this file as
// CFE_MISSION_SB_CFGVAL(MAX_SB_MSG_SIZE).
#define CFE_MISSION_SB_MAX_SB_MSG_SIZE 32768
// Declared, not defined: see the note above. Returns a status in the C; nothing checks it here.
// The `...` is load-bearing -- a HolyC call site builds (argc, argv) only if it already knows
// the callee is variadic. tools/cfs/check_variadic.py.
I32 CFE_ES_WriteToSysLog(U8 *Msg, ...);
// CFE_SB_MsgHdrSize comes from cfe_sb_msg_id_util.c, translated in cfe_sb_msgid.HC, which this
// file includes above. NOT re-declared here: a prototype for a function that is ALREADY DEFINED
// turns the rest of this file's definitions into imports, silently -- measured, see below.

U8 *CFE_SB_GetUserData(CFE_MSG_Message *MsgPtr)
{
  U8 *BytePtr;
  I64 HdrSize;
  if (MsgPtr == NULL) {
    CFE_ES_WriteToSysLog("CFE_SB_GetUserData: Failed invalid arguments\n");
    return NULL;
  }
  BytePtr = MsgPtr(U8 *);
  HdrSize = CFE_SB_MsgHdrSize(MsgPtr);
  return BytePtr + HdrSize;
}

I64 CFE_SB_GetUserDataLength(CFE_MSG_Message *MsgPtr)
{
  I64 TotalMsgSize = 0;
  I64 HdrSize;
  if (MsgPtr == NULL)
    return TotalMsgSize;
  CFE_MSG_GetSize(MsgPtr, &TotalMsgSize);
  HdrSize = CFE_SB_MsgHdrSize(MsgPtr);
  return TotalMsgSize - HdrSize;
}

U0 CFE_SB_SetUserDataLength(CFE_MSG_Message *MsgPtr, I64 DataLength)
{
  I64 TotalMsgSize;
  I64 HdrSize;
  if (MsgPtr == NULL) {
    CFE_ES_WriteToSysLog("CFE_SB_SetUserDataLength: Failed invalid arguments\n");
  } else {
    HdrSize = CFE_SB_MsgHdrSize(MsgPtr);
    TotalMsgSize = HdrSize + DataLength;
    if (TotalMsgSize <= CFE_MISSION_SB_MAX_SB_MSG_SIZE)
      CFE_MSG_SetSize(MsgPtr, TotalMsgSize);
    else
      CFE_ES_WriteToSysLog("CFE_SB_SetUserDataLength: Failed TotalMsgSize too large\n");
  }
}

U0 CFE_SB_TimeStampMsg(CFE_MSG_Message *MsgPtr)
{
  CFE_MSG_SetMsgTime(MsgPtr, CFE_TIME_GetTime);
}

// NOTE, carried across from the original rather than fixed: there is NO null check on
// SourceStringPtr here, and the DefaultString test dereferences it. A caller passing NULL with a
// nonzero SourceMaxSize faults. The sibling CFE_SB_MessageStringSet below does check it. This is
// a 1:1 translation, so the asymmetry is preserved; the oracle exercises the paths that are safe
// to exercise in both languages.
I32 CFE_SB_MessageStringGet(U8 *DestStringPtr, U8 *SourceStringPtr, U8 *DefaultString,
                            I64 DestMaxSize, I64 SourceMaxSize)
{
  I32 Result;
  // Error/default response
  if (DestMaxSize == 0 || DestStringPtr == NULL) {
    Result = CFE_SB_BAD_ARGUMENT;
  } else {
    Result = 0;
    // Check if should use the default, and if so, use the full destination size for it
    if (DefaultString != NULL && (SourceMaxSize == 0 || *SourceStringPtr == 0)) {
      SourceStringPtr = DefaultString;
      SourceMaxSize = DestMaxSize;
    }
    // Reserve 1 character for the required NUL
    --DestMaxSize;
    while (SourceMaxSize > 0 && *SourceStringPtr != 0 && DestMaxSize > 0) {
      *DestStringPtr = *SourceStringPtr;
      ++DestStringPtr;
      ++SourceStringPtr;
      --SourceMaxSize;
      --DestMaxSize;
      ++Result;
    }
    // Put the NUL in the last character
    *DestStringPtr = 0;
  }
  return Result;
}

I32 CFE_SB_MessageStringSet(U8 *DestStringPtr, U8 *SourceStringPtr, I64 DestMaxSize,
                            I64 SourceMaxSize)
{
  I32 Result;
  if (SourceStringPtr == NULL || DestStringPtr == NULL) {
    Result = CFE_SB_BAD_ARGUMENT;
  } else {
    Result = 0;
    while (SourceMaxSize > 0 && *SourceStringPtr != 0 && DestMaxSize > 0) {
      *DestStringPtr = *SourceStringPtr;
      ++DestStringPtr;
      ++SourceStringPtr;
      ++Result;
      --DestMaxSize;
      --SourceMaxSize;
    }
    // Pad the remainder of the destination with NUL -- this is NOT merely terminating the
    // string, it zero-fills to the end, so a shorter name overwrites a longer one completely.
    while (DestMaxSize > 0) {
      *DestStringPtr = 0;
      ++DestStringPtr;
      --DestMaxSize;
    }
  }
  return Result;
}
#endif
