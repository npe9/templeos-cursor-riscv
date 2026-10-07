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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_dispatch.c -- MM's FRONT DOOR: the length
// check, the thirteen-way command-code switch, and the pipe router that decides which of MM's
// two message ids a buffer carries.
//
// THIS FILE IS THE WHOLE OF MM'S ATTACK SURFACE. Everything the ground can make MM do arrives
// through MM_TaskPipe, and the only things standing between a malformed packet and a memory
// write are MM_VerifyCmdLength and the switch's default arm. So the two error counters it moves
// are the interesting output, and `MM_ProcessGroundCommand` calls MM_ResetHk FIRST -- before it
// has even looked at the command code -- so every command starts from a cleared "last action".
//
// MM_TaskPipe CACHES ITS TWO MsgIds IN STATIC LOCALS, exactly as md_dispatch.c and the three
// cFE dispatchers do -- see the note at the function.
#ifndef MM_DISPATCH_HC
#define MM_DISPATCH_HC

/*******************************************************************************/
// mm_fcncodes.h. Each reaches NASA's code through MM_CCVAL(x), which
// default_mm_fcncode_values.h defines as MM_FunctionCode_##x -- a named enum whose members are
// the numbers below. Written out, because HolyC has no token pasting.
#define MM_NOOP_CC               0
#define MM_RESET_COUNTERS_CC     1
#define MM_PEEK_CC               2
#define MM_POKE_CC               3
#define MM_LOAD_MEM_WID_CC       4
#define MM_LOAD_MEM_FROM_FILE_CC 5
#define MM_DUMP_MEM_TO_FILE_CC   6
#define MM_DUMP_IN_EVENT_CC      7
#define MM_FILL_MEM_CC           8
#define MM_LOOKUP_SYM_CC         9
#define MM_SYM_TBL_TO_FILE_CC    10
#define MM_EEPROM_WRITE_ENA_CC   11
#define MM_EEPROM_WRITE_DIS_CC   12

/*******************************************************************************/
// Verify command packet length.
//
// IT COUNTS THE BAD COMMAND ITSELF, which is why the handlers do not: a length failure never
// reaches one. And it reads the MsgId and the function code ONLY on the failure path, because
// they are needed for the event and nowhere else.
Bool MM_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  I64 ActualLength = 0;
  // CFE_SB_INVALID_MSG_ID is CFE_SB_MSGID_C(0) in the C, a compound literal HolyC cannot spell,
  // so cfe_sb_msgid.HC makes it a function. Same value, same meaning -- and the declaration
  // initialiser is safe here because CFE_SB_MsgId is four bytes (limit #27 truncates at eight;
  // check_struct_copy.py exempts by size).
  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId();
  U16 FcnCode = 0;

  CFE_MSG_GetSize(MsgPtr, &ActualLength);

  /*
  ** Verify the command packet length.
  */
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);

    CFE_EVS_SendEvent(MM_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid Msg length: ID = 0x%X,  CC = %u, Len = %u, Expected = %u",
                      CFE_SB_MsgIdToValue(MsgId), FcnCode, ActualLength, ExpectedLength);

    result = FALSE;

    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
  }

  return result;
}

/*******************************************************************************/
// Process a command pipe message.
//
// THIRTEEN COMMANDS, EACH WITH ITS OWN EXPECTED LENGTH, and the length is `sizeof` the command
// type -- so the switch is also the table that says how big each command is. A wrong sizeof here
// would reject the right packet, which is why check_padding measuring all fourteen message
// classes matters more than it looks.
U0 MM_ProcessGroundCommand(CFE_SB_Buffer *BufPtr)
{
  U16 CommandCode = 0;

  MM_ResetHk(); /* Clear all "Last Action" data */

  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);
  switch (CommandCode) {
    case MM_NOOP_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_NoopCmd_t))) {
        MM_NoopCmd(BufPtr);
      }
      break;

    case MM_RESET_COUNTERS_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_ResetCountersCmd_t))) {
        MM_ResetCountersCmd(BufPtr);
      }
      break;

    case MM_PEEK_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_PeekCmd_t))) {
        MM_PeekCmd(BufPtr);
      }
      break;

    case MM_POKE_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_PokeCmd_t))) {
        MM_PokeCmd(BufPtr);
      }
      break;

    case MM_LOAD_MEM_WID_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_LoadMemWIDCmd_t))) {
        MM_LoadMemWIDCmd(BufPtr);
      }
      break;

    case MM_LOAD_MEM_FROM_FILE_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_LoadMemFromFileCmd_t))) {
        MM_LoadMemFromFileCmd(BufPtr);
      }
      break;

    case MM_DUMP_MEM_TO_FILE_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_DumpMemToFileCmd_t))) {
        MM_DumpMemToFileCmd(BufPtr);
      }
      break;

    case MM_DUMP_IN_EVENT_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_DumpInEventCmd_t))) {
        MM_DumpInEventCmd(BufPtr);
      }
      break;

    case MM_FILL_MEM_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_FillMemCmd_t))) {
        MM_FillMemCmd(BufPtr);
      }
      break;

    case MM_LOOKUP_SYM_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_LookupSymCmd_t))) {
        MM_LookupSymCmd(BufPtr);
      }
      break;

    case MM_SYM_TBL_TO_FILE_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_SymTblToFileCmd_t))) {
        MM_SymTblToFileCmd(BufPtr);
      }
      break;

    case MM_EEPROM_WRITE_ENA_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_EepromWriteEnaCmd_t))) {
        MM_EepromWriteEnaCmd(BufPtr);
      }
      break;

    case MM_EEPROM_WRITE_DIS_CC:
      if (MM_VerifyCmdLength(&BufPtr->Msg, sizeof(MM_EepromWriteDisCmd_t))) {
        MM_EepromWriteDisCmd(BufPtr);
      }
      break;

    default:
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      CFE_EVS_SendEvent(MM_CC_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid ground command code %d",
                        CommandCode);
      break;
  }
}

/*******************************************************************************/
//  Purpose:
//     This routine will process any packet that is received on the SAMPLE
//     command pipe.
//
// NASA'S COMMENT SAYS "SAMPLE" because this file began as a copy of the sample app's, which is
// how every cFS app's dispatcher begins. Kept.
U0 MM_TaskPipe(CFE_SB_Buffer *BufPtr)
{
  // THE TWO MESSAGE IDS ARE CACHED IN STATIC LOCALS, zero-initialised, which is NASA's
  // CFE_SB_MSGID_RESERVED (0) -- the same arrangement cfe_es_dispatch.HC, cfe_evs_dispatch.HC,
  // cfe_ta_dispatch.HC and md_dispatch.HC record. These are the FIFTH pair to share the names
  // CMD_MID and SEND_HK_MID in one tree, and for one commit all of them collided because a
  // HolyC static local became a global under its bare name (docs/HOLYC_STRUCT_LIMITS.md #12).
  // The fill is load-bearing: unfilled, every route falls through to the unknown-id arm.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;

  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId();

  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    /*
    ** Initialize application MID values
    */
    CMD_MID = CFE_SB_ValueToMsgId(MM_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(MM_SEND_HK_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MsgId);

  if (CFE_SB_MsgId_Equal(MsgId, CMD_MID)) {
    /*
    ** MM ground commands
    */
    MM_ProcessGroundCommand(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MsgId, SEND_HK_MID)) {
    /*
    ** Housekeeping telemetry request
    */
    MM_SendHkCmd(BufPtr);
  } else {
    /*
    ** Unrecognized Message ID
    */
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid command pipe message ID: 0x%08lX", CFE_SB_MsgIdToValue(MsgId));
  }
}
#endif
