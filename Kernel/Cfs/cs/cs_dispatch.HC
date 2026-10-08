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
// CHECKSUM'S DISPATCHER -- the 1:1 translation of NASA's fsw/src/cs_dispatch.c, 442 lines and three
// functions, of which one is a FORTY-CASE SWITCH and that is the whole file.
//
// CS HAS MORE COMMANDS THAN MD AND MM PUT TOGETHER -- 40 against 7 and 10 -- and the reason is the
// organising idea of the app: six checksum types crossed with enable, disable, report-baseline and
// recompute-baseline, plus the per-entry and per-name variants, plus one-shot. Every case is the
// same three lines, which is what makes the file long rather than hard.
//
// THE OTHER HALF OF CS'S SEVEN-SOURCE CYCLE IS HERE. CS_AppPipe is called by cs_app.c and calls
// into all five command files; CS_UpdateCDS in cs_app.c is called by all five of them. Two edges.
// The other forty are a dispatcher calling its own handlers -- a tree, not a cycle -- which is what
// docs/CFS_PLAN.md measured before choosing to gate these seven together.
#ifndef CS_DISPATCH_HC
#define CS_DISPATCH_HC

// The five command files' handlers, which NASA reaches through five headers. Forty-two declarations
// rather than a stand-in: every one is real logic in a file gated by this same commit.
//
// ALL FORTY-TWO RETURN CFE_Status_t AND THE DISPATCHER IGNORES IT. Not one is `void` -- checked
// against NASA rather than assumed, because a first draft declared them U0 here and
// check_signatures is what would have refused it. The value is unused on every one of the forty
// call sites below, which is NASA's own shape: the handlers report through housekeeping counters and
// events, not through a return.
I32 CS_SendHkCmd(CS_SendHkCmd_t *CmdPtr);
I32 CS_BackgroundCheckCycleCmd(CS_BackgroundCheckCycleCmd_t *CmdPtr);
I32 CS_NoopCmd(CS_NoopCmd_t *CmdPtr);
I32 CS_ResetCountersCmd(CS_ResetCountersCmd_t *CmdPtr);
I32 CS_OneShotCmd(CS_OneShotCmd_t *CmdPtr);
I32 CS_CancelOneShotCmd(CS_CancelOneShotCmd_t *CmdPtr);
I32 CS_EnableAllCSCmd(CS_EnableAllCSCmd_t *CmdPtr);
I32 CS_DisableAllCSCmd(CS_DisableAllCSCmd_t *CmdPtr);
I32 CS_EnableCfeCoreCmd(CS_EnableCfeCoreCmd_t *CmdPtr);
I32 CS_DisableCfeCoreCmd(CS_DisableCfeCoreCmd_t *CmdPtr);
I32 CS_ReportBaselineCfeCoreCmd(CS_ReportBaselineCfeCoreCmd_t *CmdPtr);
I32 CS_RecomputeBaselineCfeCoreCmd(CS_RecomputeBaselineCfeCoreCmd_t *CmdPtr);
I32 CS_EnableOSCmd(CS_EnableOSCmd_t *CmdPtr);
I32 CS_DisableOSCmd(CS_DisableOSCmd_t *CmdPtr);
I32 CS_ReportBaselineOSCmd(CS_ReportBaselineOSCmd_t *CmdPtr);
I32 CS_RecomputeBaselineOSCmd(CS_RecomputeBaselineOSCmd_t *CmdPtr);
I32 CS_EnableEepromCmd(CS_EnableEepromCmd_t *CmdPtr);
I32 CS_DisableEepromCmd(CS_DisableEepromCmd_t *CmdPtr);
I32 CS_ReportBaselineEntryIDEepromCmd(CS_ReportBaselineEntryIDEepromCmd_t *CmdPtr);
I32 CS_RecomputeBaselineEepromCmd(CS_RecomputeBaselineEepromCmd_t *CmdPtr);
I32 CS_EnableEntryIDEepromCmd(CS_EnableEntryIDEepromCmd_t *CmdPtr);
I32 CS_DisableEntryIDEepromCmd(CS_DisableEntryIDEepromCmd_t *CmdPtr);
I32 CS_GetEntryIDEepromCmd(CS_GetEntryIDEepromCmd_t *CmdPtr);
I32 CS_EnableMemoryCmd(CS_EnableMemoryCmd_t *CmdPtr);
I32 CS_DisableMemoryCmd(CS_DisableMemoryCmd_t *CmdPtr);
I32 CS_ReportBaselineEntryIDMemoryCmd(CS_ReportBaselineEntryIDMemoryCmd_t *CmdPtr);
I32 CS_RecomputeBaselineMemoryCmd(CS_RecomputeBaselineMemoryCmd_t *CmdPtr);
I32 CS_EnableEntryIDMemoryCmd(CS_EnableEntryIDMemoryCmd_t *CmdPtr);
I32 CS_DisableEntryIDMemoryCmd(CS_DisableEntryIDMemoryCmd_t *CmdPtr);
I32 CS_GetEntryIDMemoryCmd(CS_GetEntryIDMemoryCmd_t *CmdPtr);
I32 CS_EnableTablesCmd(CS_EnableTablesCmd_t *CmdPtr);
I32 CS_DisableTablesCmd(CS_DisableTablesCmd_t *CmdPtr);
I32 CS_ReportBaselineTableCmd(CS_ReportBaselineTableCmd_t *CmdPtr);
I32 CS_RecomputeBaselineTableCmd(CS_RecomputeBaselineTableCmd_t *CmdPtr);
I32 CS_EnableNameTableCmd(CS_EnableNameTableCmd_t *CmdPtr);
I32 CS_DisableNameTableCmd(CS_DisableNameTableCmd_t *CmdPtr);
I32 CS_EnableAppsCmd(CS_EnableAppsCmd_t *CmdPtr);
I32 CS_DisableAppsCmd(CS_DisableAppsCmd_t *CmdPtr);
I32 CS_ReportBaselineAppCmd(CS_ReportBaselineAppCmd_t *CmdPtr);
I32 CS_RecomputeBaselineAppCmd(CS_RecomputeBaselineAppCmd_t *CmdPtr);
I32 CS_EnableNameAppCmd(CS_EnableNameAppCmd_t *CmdPtr);
I32 CS_DisableNameAppCmd(CS_DisableNameAppCmd_t *CmdPtr);

/*******************************************************************************/
// THE LENGTH CHECK EVERY ROUTE GOES THROUGH, and it counts the error ITSELF -- so a caller that
// forgot to stop on FALSE would count one bad command twice. Note it reads the length FIRST and
// only looks up the MsgId and function code when the length is wrong: three accessor calls saved on
// every good command, which matters at CS's command rate.
Bool CS_VerifyCmdLength(CFE_MSG_Message *msg, I64 ExpectedLength)
{
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId();
  U16 CommandCode = 0; // CFE_MSG_FcnCode_t
  Bool Result = TRUE;
  I64 ActualLength = 0;

  CFE_MSG_GetSize(msg, &ActualLength);

  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(msg, &MessageID);
    CFE_MSG_GetFcnCode(msg, &CommandCode);

    CFE_EVS_SendEvent(CS_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid msg length: ID = 0x%08lX, CC = %d, Len = %lu, Expected = %lu",
                      CFE_SB_MsgIdToValue(MessageID), CommandCode, ActualLength, ExpectedLength);
    Result = FALSE;
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return Result;
}

/*******************************************************************************/
// THE THREE MESSAGE IDS ARE CACHED IN STATIC LOCALS, zero-initialised, which is NASA's
// CFE_SB_MSGID_RESERVED (0) -- the same arrangement cfe_es_dispatch.HC, cfe_evs_dispatch.HC,
// cfe_ta_dispatch.HC, md_dispatch.HC and mm_dispatch.HC record. These are the SIXTH set to share
// the names CMD_MID and SEND_HK_MID in one tree; for one commit all of them collided, because a
// HolyC static local became a global under its bare name (docs/HOLYC_STRUCT_LIMITS.md #12, fixed).
// BACKGROUND_CYCLE_MID is new with CS -- no earlier app has a third subscription.
//
// AND THE FILL IS LOAD-BEARING: unfilled, every route falls through to the unknown-id arm. The
// guard is on CMD_MID alone, so all three are filled together or not at all.
I32 CS_AppPipe(CFE_SB_Buffer *BufPtr)
{
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId BACKGROUND_CYCLE_MID;
  static CFE_SB_MsgId SEND_HK_MID;

  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId();

  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(CS_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(CS_SEND_HK_MID);
    BACKGROUND_CYCLE_MID = CFE_SB_ValueToMsgId(CS_BACKGROUND_CYCLE_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

  if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_SendHkCmd_t))) {
      CS_SendHkCmd(BufPtr);
    }
  } else if (CFE_SB_MsgId_Equal(MessageID, BACKGROUND_CYCLE_MID)) {
    if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_BackgroundCheckCycleCmd_t))) {
      CS_BackgroundCheckCycleCmd(BufPtr);
    }
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    CS_ProcessCmd(BufPtr);
  } else {
    CFE_EVS_SendEvent(CS_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid command pipe message ID: 0x%08lX",
                      CFE_SB_MsgIdToValue(MessageID));
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// FORTY CASES, each the same three lines: check the length for THIS command's type, then call its
// handler. The per-command type is the point -- a bare command header is 8 bytes, an EntryID
// command is 12, a table-name command is 48 -- so the length check is per-case and not per-pipe.
U0 CS_ProcessCmd(CFE_SB_Buffer *BufPtr)
{
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId();
  U16 CommandCode = 0;

  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);

  switch (CommandCode) {
    case CS_NOOP_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_NoopCmd_t))) {
        CS_NoopCmd(BufPtr);
      }
      break;
    case CS_RESET_COUNTERS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ResetCountersCmd_t))) {
        CS_ResetCountersCmd(BufPtr);
      }
      break;
    case CS_ONE_SHOT_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_OneShotCmd_t))) {
        CS_OneShotCmd(BufPtr);
      }
      break;
    case CS_CANCEL_ONE_SHOT_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_CancelOneShotCmd_t))) {
        CS_CancelOneShotCmd(BufPtr);
      }
      break;
    case CS_ENABLE_ALL_CS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableAllCSCmd_t))) {
        CS_EnableAllCSCmd(BufPtr);
      }
      break;
    case CS_DISABLE_ALL_CS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableAllCSCmd_t))) {
        CS_DisableAllCSCmd(BufPtr);
      }
      break;
    case CS_ENABLE_CFE_CORE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableCfeCoreCmd_t))) {
        CS_EnableCfeCoreCmd(BufPtr);
      }
      break;
    case CS_DISABLE_CFE_CORE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableCfeCoreCmd_t))) {
        CS_DisableCfeCoreCmd(BufPtr);
      }
      break;
    case CS_REPORT_BASELINE_CFE_CORE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ReportBaselineCfeCoreCmd_t))) {
        CS_ReportBaselineCfeCoreCmd(BufPtr);
      }
      break;
    case CS_RECOMPUTE_BASELINE_CFE_CORE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_RecomputeBaselineCfeCoreCmd_t))) {
        CS_RecomputeBaselineCfeCoreCmd(BufPtr);
      }
      break;
    case CS_ENABLE_OS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableOSCmd_t))) {
        CS_EnableOSCmd(BufPtr);
      }
      break;
    case CS_DISABLE_OS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableOSCmd_t))) {
        CS_DisableOSCmd(BufPtr);
      }
      break;
    case CS_REPORT_BASELINE_OS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ReportBaselineOSCmd_t))) {
        CS_ReportBaselineOSCmd(BufPtr);
      }
      break;
    case CS_RECOMPUTE_BASELINE_OS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_RecomputeBaselineOSCmd_t))) {
        CS_RecomputeBaselineOSCmd(BufPtr);
      }
      break;
    case CS_ENABLE_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableEepromCmd_t))) {
        CS_EnableEepromCmd(BufPtr);
      }
      break;
    case CS_DISABLE_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableEepromCmd_t))) {
        CS_DisableEepromCmd(BufPtr);
      }
      break;
    case CS_REPORT_BASELINE_ENTRY_ID_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ReportBaselineEntryIDEepromCmd_t))) {
        CS_ReportBaselineEntryIDEepromCmd(BufPtr);
      }
      break;
    case CS_RECOMPUTE_BASELINE_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_RecomputeBaselineEepromCmd_t))) {
        CS_RecomputeBaselineEepromCmd(BufPtr);
      }
      break;
    case CS_ENABLE_ENTRY_ID_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableEntryIDEepromCmd_t))) {
        CS_EnableEntryIDEepromCmd(BufPtr);
      }
      break;
    case CS_DISABLE_ENTRY_ID_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableEntryIDEepromCmd_t))) {
        CS_DisableEntryIDEepromCmd(BufPtr);
      }
      break;
    case CS_GET_ENTRY_ID_EEPROM_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_GetEntryIDEepromCmd_t))) {
        CS_GetEntryIDEepromCmd(BufPtr);
      }
      break;
    case CS_ENABLE_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableMemoryCmd_t))) {
        CS_EnableMemoryCmd(BufPtr);
      }
      break;
    case CS_DISABLE_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableMemoryCmd_t))) {
        CS_DisableMemoryCmd(BufPtr);
      }
      break;
    case CS_REPORT_BASELINE_ENTRY_ID_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ReportBaselineEntryIDMemoryCmd_t))) {
        CS_ReportBaselineEntryIDMemoryCmd(BufPtr);
      }
      break;
    case CS_RECOMPUTE_BASELINE_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_RecomputeBaselineMemoryCmd_t))) {
        CS_RecomputeBaselineMemoryCmd(BufPtr);
      }
      break;
    case CS_ENABLE_ENTRY_ID_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableEntryIDMemoryCmd_t))) {
        CS_EnableEntryIDMemoryCmd(BufPtr);
      }
      break;
    case CS_DISABLE_ENTRY_ID_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableEntryIDMemoryCmd_t))) {
        CS_DisableEntryIDMemoryCmd(BufPtr);
      }
      break;
    case CS_GET_ENTRY_ID_MEMORY_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_GetEntryIDMemoryCmd_t))) {
        CS_GetEntryIDMemoryCmd(BufPtr);
      }
      break;
    case CS_ENABLE_TABLES_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableTablesCmd_t))) {
        CS_EnableTablesCmd(BufPtr);
      }
      break;
    case CS_DISABLE_TABLES_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableTablesCmd_t))) {
        CS_DisableTablesCmd(BufPtr);
      }
      break;
    case CS_REPORT_BASELINE_TABLE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ReportBaselineTableCmd_t))) {
        CS_ReportBaselineTableCmd(BufPtr);
      }
      break;
    case CS_RECOMPUTE_BASELINE_TABLE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_RecomputeBaselineTableCmd_t))) {
        CS_RecomputeBaselineTableCmd(BufPtr);
      }
      break;
    case CS_ENABLE_NAME_TABLE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableNameTableCmd_t))) {
        CS_EnableNameTableCmd(BufPtr);
      }
      break;
    case CS_DISABLE_NAME_TABLE_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableNameTableCmd_t))) {
        CS_DisableNameTableCmd(BufPtr);
      }
      break;
    case CS_ENABLE_APPS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableAppsCmd_t))) {
        CS_EnableAppsCmd(BufPtr);
      }
      break;
    case CS_DISABLE_APPS_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableAppsCmd_t))) {
        CS_DisableAppsCmd(BufPtr);
      }
      break;
    case CS_REPORT_BASELINE_APP_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_ReportBaselineAppCmd_t))) {
        CS_ReportBaselineAppCmd(BufPtr);
      }
      break;
    case CS_RECOMPUTE_BASELINE_APP_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_RecomputeBaselineAppCmd_t))) {
        CS_RecomputeBaselineAppCmd(BufPtr);
      }
      break;
    case CS_ENABLE_NAME_APP_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_EnableNameAppCmd_t))) {
        CS_EnableNameAppCmd(BufPtr);
      }
      break;
    case CS_DISABLE_NAME_APP_CC:
      if (CS_VerifyCmdLength(&BufPtr->Msg, sizeof(CS_DisableNameAppCmd_t))) {
        CS_DisableNameAppCmd(BufPtr);
      }
      break;

    default:
      CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);
      CFE_EVS_SendEvent(CS_CC_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid ground command code: ID = 0x%08lX, CC = %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode);

      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
      break;
  } // end switch
}
#endif
