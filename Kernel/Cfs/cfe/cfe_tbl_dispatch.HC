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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_dispatch.c -- THE COMMAND
// DISPATCHER, and the file CMakeLists picks when EDS is off, which is this configuration.
// cfe_tbl_eds_dispatch.c is the alternative and check_manifest reports both.
//
// A TABLE OF FUNCTION POINTERS, NOT A SWITCH, which is where it differs from every other
// module's dispatcher in this port. Twelve rows plus a terminator, each naming a message id, a
// command code, an expected LENGTH and a handler; CFE_TBL_SearchCmdHandlerTbl walks it and
// CFE_TBL_TaskPipe calls what it found.
//
// THE THREE-WAY ERROR IS THE POINT OF THE SEARCH. It distinguishes
//
//   wrong LENGTH          the id and code matched, the size did not   CFE_TBL_LEN_ERR_EID
//   bad COMMAND CODE      the id matched, no row had that code        CFE_TBL_CC1_ERR_EID
//   unknown MESSAGE ID    no row had that id at all                   CFE_TBL_MID_ERR_EID
//
// and `FoundMsg` exists only to tell the second from the third. Note that only the bad-command-
// code arm bumps CommandErrorCounter here -- a wrong length or an unknown id does not, because
// a handler that never ran cannot have counted anything and NASA chose not to count it either.
//
// **THE TABLE IS FILLED AT RUNTIME, AND THE ORDER MATTERS.** NASA's is a `const` file-scope
// array with initialisers; HolyC has no file-scope aggregate initialiser, so
// CFE_TBL_CmdHandlerTblInit() below does the filling and MUST RUN BEFORE ANY DISPATCH. That is
// a recorded hazard in this project -- a static-in-C table that becomes a runtime fill fails
// SILENTLY when the reader runs first, and it has cost five lost config entries and an empty
// block-size array before. The driver calls it beside CFE_PlatformConfigTablesInit, which
// exists for exactly the same reason.
//
// AND THE MID CACHE IS LAZY, which the table depends on: the rows hold POINTERS to
// CFE_TBL_CMD_MID_CACHE and CFE_TBL_SEND_HK_MID_CACHE, both initialised to
// CFE_SB_MSGID_RESERVED (zero), and the first search fills them. So a row's message id is
// resolved on first use rather than at load -- which is what lets the table be `const` upstream
// while still picking up a runtime-configured id.
#ifndef CFE_TBL_DISPATCH_HC
#define CFE_TBL_DISPATCH_HC
// cfe_tbl_fcncodes.h: the ten ground command codes, contiguous here unlike ES's.
#ifndef CFE_TBL_NOOP_CC
#define CFE_TBL_NOOP_CC           0
#define CFE_TBL_RESET_COUNTERS_CC 1
#define CFE_TBL_LOAD_CC           2
#define CFE_TBL_DUMP_CC           3
#define CFE_TBL_VALIDATE_CC       4
#define CFE_TBL_ACTIVATE_CC       5
#define CFE_TBL_DUMP_REGISTRY_CC  6
#define CFE_TBL_SEND_REGISTRY_CC  7
#define CFE_TBL_DELETE_CDS_CC     8
#define CFE_TBL_ABORT_LOAD_CC     9
#endif
// cfe_tbl_eventids.h
#ifndef CFE_TBL_MID_ERR_EID
#define CFE_TBL_MID_ERR_EID 50
#endif
#ifndef CFE_TBL_CC1_ERR_EID
#define CFE_TBL_CC1_ERR_EID 51
#endif
#ifndef CFE_TBL_LEN_ERR_EID
#define CFE_TBL_LEN_ERR_EID 52
#endif
#ifndef CFE_STATUS_UNKNOWN_MSG_ID
#define CFE_STATUS_UNKNOWN_MSG_ID 0xC8000003(I32)
#endif
// cfe_tbl_dispatch.c's own message-type enum. TERM is zero so the terminator row's zeroed
// MsgTypes is already correct -- but the loop stops on a NULL MsgId, not on this.
#ifndef CFE_TBL_TERM_MSGTYPE
#define CFE_TBL_TERM_MSGTYPE 0
#define CFE_TBL_MSG_MSGTYPE  1
#define CFE_TBL_CMD_MSGTYPE  2
#endif
// One row of CFE_TBL_CmdHandlerTbl. The MsgProcFuncPtr member is a function pointer, which
// check_fnptr_members compares against NASA's return kind and parameter count.
class CFE_TBL_CmdHandlerTblRec_t
{
  CFE_SB_MsgId *MsgId;
  U16 CmdCode;
  U8 _pad0[6];
  I64 ExpectedLength;
  I32 (*MsgProcFuncPtr)(U8 *);
  U32 MsgTypes;
  U8 _pad1[4];
};
// NASA's two file-scope MID caches, initialised to CFE_SB_MSGID_RESERVED, which is
// CFE_SB_MSGID_WRAP_VALUE(0) -- zero, so a HolyC global is already in the right state.
CFE_SB_MsgId CFE_TBL_SEND_HK_MID_CACHE;
CFE_SB_MsgId CFE_TBL_CMD_MID_CACHE;
// Twelve rows plus the terminator.
CFE_TBL_CmdHandlerTblRec_t CFE_TBL_CmdHandlerTbl[13];
I32 CFE_TBL_SearchCmdHandlerTbl(U16 *TableIdxOut, CFE_SB_MsgId MessageID, U16 CommandCode);
// THE RUNTIME FILL. Each row is NASA's CFE_TBL_ENTRY(id, ccode, paramtype, handlerfunc,
// msgtype) macro written out: a pointer to the id CACHE, the command code, sizeof the payload
// TYPE, the handler, and the message type. The sizeof is what makes the length check mean
// something, which is why cfe_tbl_msg.HC's command classes are measured by check_padding.
U0 CFE_TBL_CmdHandlerTblInit()
{
  CFE_TBL_CmdHandlerTblRec_t *r;
  MemSet(CFE_TBL_CmdHandlerTbl, 0, sizeof(CFE_TBL_CmdHandlerTblRec_t) * 13);
  /* SEND_HK Entry */
  r = &CFE_TBL_CmdHandlerTbl[0];
  r->MsgId = &CFE_TBL_SEND_HK_MID_CACHE;
  r->CmdCode = 0;
  r->ExpectedLength = sizeof(CFE_TBL_SendHkCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_SendHkCmd;
  r->MsgTypes = CFE_TBL_MSG_MSGTYPE;
  /* Everything else */
  r = &CFE_TBL_CmdHandlerTbl[1];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_NOOP_CC;
  r->ExpectedLength = sizeof(CFE_TBL_NoopCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_NoopCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[2];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_RESET_COUNTERS_CC;
  r->ExpectedLength = sizeof(CFE_TBL_ResetCountersCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_ResetCountersCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[3];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_LOAD_CC;
  r->ExpectedLength = sizeof(CFE_TBL_LoadCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_LoadCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[4];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_DUMP_CC;
  r->ExpectedLength = sizeof(CFE_TBL_DumpCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_DumpCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[5];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_VALIDATE_CC;
  r->ExpectedLength = sizeof(CFE_TBL_ValidateCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_ValidateCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[6];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_ACTIVATE_CC;
  r->ExpectedLength = sizeof(CFE_TBL_ActivateCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_ActivateCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[7];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_DUMP_REGISTRY_CC;
  r->ExpectedLength = sizeof(CFE_TBL_DumpRegistryCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_DumpRegistryCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[8];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_SEND_REGISTRY_CC;
  r->ExpectedLength = sizeof(CFE_TBL_SendRegistryCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_SendRegistryCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[9];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_DELETE_CDS_CC;
  r->ExpectedLength = sizeof(CFE_TBL_DeleteCDSCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_DeleteCDSCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  r = &CFE_TBL_CmdHandlerTbl[10];
  r->MsgId = &CFE_TBL_CMD_MID_CACHE;
  r->CmdCode = CFE_TBL_ABORT_LOAD_CC;
  r->ExpectedLength = sizeof(CFE_TBL_AbortLoadCmd_t);
  r->MsgProcFuncPtr = &CFE_TBL_AbortLoadCmd;
  r->MsgTypes = CFE_TBL_CMD_MSGTYPE;
  /* list terminator (keep last) */
  r = &CFE_TBL_CmdHandlerTbl[11];
  r->MsgId = NULL;
  r->CmdCode = 0;
  r->ExpectedLength = 0;
  r->MsgProcFuncPtr = NULL;
  r->MsgTypes = CFE_TBL_TERM_MSGTYPE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TaskPipe(CFE_SB_Buffer *SBBufPtr)
{
  CFE_SB_MsgId MessageID;
  U16 CommandCode;
  U16 CmdIndx;
  I64 ActualLength;
  I64 ExpectedLength;
  I32 CmdStatus;
  MessageID = CFE_SB_InvalidMsgId;
  CommandCode = 0;
  ActualLength = 0;
  CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MessageID);
  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &CommandCode);
  /* Search the Command Handler Table for a matching message */
  CmdStatus = CFE_TBL_SearchCmdHandlerTbl(&CmdIndx, MessageID, CommandCode);
  /* Check to see if a matching command was found */
  if (CmdStatus == CFE_SUCCESS) {
    /* Verify Message Length before processing */
    CFE_MSG_GetSize(&SBBufPtr->Msg, &ActualLength);
    ExpectedLength = CFE_TBL_CmdHandlerTbl[CmdIndx].ExpectedLength;
    if (ActualLength == ExpectedLength) {
      /* All checks have passed, call the appropriate message handler */
      CmdStatus = CFE_TBL_CmdHandlerTbl[CmdIndx].MsgProcFuncPtr(SBBufPtr);
    } else {
      /* Bad Message Length */
      CmdStatus = CFE_STATUS_WRONG_MSG_LENGTH;
    }
  }
  if (CmdStatus != CFE_SUCCESS) {
    if (CmdStatus == CFE_STATUS_WRONG_MSG_LENGTH) {
      CFE_EVS_SendEvent(CFE_TBL_LEN_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid msg length -- ID = 0x%X, CC = %u, Len = %u, Expected = %u", CFE_SB_MsgIdToValue(MessageID), CommandCode, ActualLength, CFE_TBL_CmdHandlerTbl[CmdIndx].ExpectedLength);
    } else if (CmdStatus == CFE_STATUS_BAD_COMMAND_CODE) {
      CFE_EVS_SendEvent(CFE_TBL_CC1_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid command code -- ID = 0x%X, CC = %u", CFE_SB_MsgIdToValue(MessageID), CommandCode);
      // ONLY THIS ARM COUNTS THE ERROR. A wrong length or an unknown message id raises its
      // event and leaves CommandErrorCounter alone, which is NASA's choice -- an unknown id
      // may not even have been meant for Table Services.
      /* Update the command error counter */
      CFE_TBL_Global.CommandErrorCounter++;
    } else {
      CFE_EVS_SendEvent(CFE_TBL_MID_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid message ID -- ID = 0x%X", CFE_SB_MsgIdToValue(MessageID));
    }
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_SearchCmdHandlerTbl(U16 *TableIdxOut, CFE_SB_MsgId MessageID, U16 CommandCode)
{
  I16 TblIndx;
  I32 Status;
  Bool FoundMsg;
  Bool FoundMatch;
  FoundMsg = FALSE;
  FoundMatch = FALSE;
  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CFE_TBL_CMD_MID_CACHE)) {
    CFE_TBL_CMD_MID_CACHE = CFE_SB_ValueToMsgId(CFE_TBL_CMD_MID);
    CFE_TBL_SEND_HK_MID_CACHE = CFE_SB_ValueToMsgId(CFE_TBL_SEND_HK_MID);
  }
  for (TblIndx = 0; CFE_TBL_CmdHandlerTbl[TblIndx].MsgId != NULL; ++TblIndx) {
    /* Check to see if we found a matching Message ID */
    if (CFE_SB_MsgId_Equal (*CFE_TBL_CmdHandlerTbl[TblIndx].MsgId, MessageID)) {
      /* Flag any found message IDs so that if there is an error,        */
      /* we can determine if it was a bad message ID or bad command code */
      FoundMsg = TRUE;
      /* If entry in the Command Handler Table is a command entry, */
      /* then check for a matching command code                    */
      if (CFE_TBL_CmdHandlerTbl[TblIndx].MsgTypes == CFE_TBL_CMD_MSGTYPE) {
        if (CFE_TBL_CmdHandlerTbl[TblIndx].CmdCode == CommandCode) {
          /* Found matching message ID and Command Code */
          FoundMatch = TRUE;
          break;
        }
      } else {
        /* Message is not a command message with specific command code */
        /* Automatically assume a match when legit */
        /* Message ID is all that is required      */
        FoundMatch = TRUE;
        break;
      }
    }
  }
  /* If we failed to find a match, return a negative index */
  if (FoundMatch) {
    Status = CFE_SUCCESS;
    *TableIdxOut = TblIndx;
  } else if (FoundMsg) {
    /* A matching message ID was found, so the command code must be bad */
    Status = CFE_STATUS_BAD_COMMAND_CODE;
  } else {
    /* No matching message ID was found */
    Status = CFE_STATUS_UNKNOWN_MSG_ID;
  }
  return Status;
}
#endif
