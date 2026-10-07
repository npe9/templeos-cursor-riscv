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
// Translation of NASA's MD/fsw/src/md_cmds.c -- the six ground commands. Noop and
// ResetCounters are bookkeeping; Start and Stop walk a table MASK; Jam edits one entry; and
// SetSignature names a dwell stream. Twenty-three event ids, which is most of what an operator
// ever sees from this app.
//
// EVERY COMMAND WRITES TWO PLACES, and that is the shape of the file. MD keeps its working
// state in MD_AppData.MD_DwellTables and the ground's copy in a Table Services buffer, so each
// handler updates the control structure directly AND calls one of md_dwell_tbl.c's three
// editors to change the registered table. The editors can fail independently -- Start and Stop
// count the failures across the mask and report "failed for %d of %d tables" -- so a command
// can partly succeed, which is why Status and the two counters move separately.
//
// THE ADDRESS IN THE EVENT TEXT IS WHY THE DWELL WINDOW EXISTS. MD_JamDwellCmd prints
// "address 0x%08X" from a resolved cpuaddr in three of its rejection paths; that single line is
// what the simulated window was designed around, several commits before this file was written
// (docs/CFS_PLAN.md). An empty SymName gives the offset verbatim and a non-empty one resolves
// through the driver's OS_SymbolLookup stub, so both are literals chosen in the exercise.
//
// TWO CALL SITES PASS A 72-BYTE CLASS BY VALUE, and in HolyC they must pass its address:
// docs/HOLYC_STRUCT_LIMITS.md #26. tools/cfs/check_struct_copy.py refuses the by-value form in
// a DEFINITION, which is where MD_UpdateTableDwellEntry declares it -- but a missing `&` HERE
// is a CALL SITE and no gate in the set objects to it. Measured, so it is written down rather
// than assumed. What catches it is the transcript: the symbol name lives past offset 8, so a
// by-value call delivers `Offset` and nothing else.
//
// AND NASA PASSES A PARTIALLY-INITIALISED STRUCT IN THE NULL-JAM PATH. `NewDwellAddress` is a
// LOCAL, and the FieldLength == 0 branch sets only `.Offset` and `.SymName[0]` before handing
// the whole 72 bytes over -- the remaining bytes are uninitialised stack and get copied into
// the Table Services buffer. Same family as the uninitialised dump header in docs/CFS_PLAN.md.
// It is harmless to the app, which only ever reads SymName as a string, and it means the
// exercise must read it as a STRING too: a byte dump past the NUL cannot be compared across a
// host process and a QEMU guest.
#ifndef MD_CMDS_HC
#define MD_CMDS_HC

// md_version.h, for the Noop event text. MD_INTERNAL_MISSION_REV is in md_msg.HC.
#define MD_MAJOR_VERSION 7
#define MD_MINOR_VERSION 0
#define MD_REVISION      1

// md_eventids.h, the twenty-three ids this file raises.
#define MD_NOOP_INF_EID                     10
#define MD_RESET_INF_EID                    11
#define MD_START_DWELL_INF_EID              12
#define MD_STOP_DWELL_INF_EID               13
#define MD_EMPTY_TBLMASK_ERR_EID            14
#define MD_JAM_DWELL_INF_EID                30
#define MD_JAM_NULL_DWELL_INF_EID           31
#define MD_INVALID_JAM_TABLE_ERR_EID        32
#define MD_INVALID_ENTRY_ARG_ERR_EID        33
#define MD_INVALID_LEN_ARG_ERR_EID          34
#define MD_CANT_RESOLVE_JAM_ADDR_ERR_EID    35
#define MD_INVALID_JAM_ADDR_ERR_EID         36
#define MD_JAM_ADDR_NOT_32BIT_ERR_EID       37
#define MD_JAM_ADDR_NOT_16BIT_ERR_EID       38
#define MD_SET_SIGNATURE_INF_EID            46
#define MD_INVALID_SIGNATURE_TABLE_ERR_EID  47
#define MD_INVALID_SIGNATURE_LENGTH_ERR_EID 49
#define MD_ZERO_RATE_CMD_INF_EID            51
#define MD_START_DWELL_ERR_EID              56
#define MD_STOP_DWELL_ERR_EID               57
#define MD_SET_SIGNATURE_ERR_EID            58
#define MD_JAM_DWELL_ERR_EID                59
#define MD_JAM_NULL_DWELL_ERR_EID           60

/******************************************************************************/

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
/*                                                                 */
/* Noop command                                                    */
/*                                                                 */
/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

I32 MD_NoopCmd(MD_NoopCmd_t *Msg)
{
  CFE_EVS_SendEvent(MD_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "No-op command, Version %d.%d.%d.%d", MD_MAJOR_VERSION, MD_MINOR_VERSION,
                    MD_REVISION, MD_INTERNAL_MISSION_REV);

  MD_AppData.CommandCounter++;
  return CFE_SUCCESS;
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
/*                                                                 */
/* Reset counters command                                          */
/*                                                                 */
/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
I32 MD_ResetCountersCmd(MD_ResetCountersCmd_t *Msg)
{
  CFE_EVS_SendEvent(MD_RESET_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Reset Counters Cmd Received");
  MD_AppData.CommandCounter = 0;
  MD_AppData.CommandErrorCounter = 0;
  return CFE_SUCCESS;
}

I32 MD_StartDwellCmd(MD_StartDwellCmd_t *Msg)
{
  I32 ErrorCount = 0;
  I32 Status;
  I32 TableUpdateStatus;
  I32 NumTblInMask = 0; /* Purely as info for event message */
  U16 TableId = 0;
  U16 TableIndex;
  Bool AnyTablesInMask = FALSE;

  Status = CFE_SUCCESS;

  /*  Preview tables specified by command:                   */
  /*  Check that there's at least one valid table specified. */
  for (TableId = 1; TableId <= MD_INTERFACE_NUM_DWELL_TABLES; TableId++) {
    if (MD_TableIsInMask(TableId, Msg->Payload.TableMask)) {
      /* At least one valid Table Id is in Mask */
      AnyTablesInMask = TRUE;
    }
  }

  /*
  ** Handle specified operation.
  ** If nominal, start each of the specified tables.
  ** If error case was encountered, issue error message.
  */
  if (AnyTablesInMask) { /* Handle Nominal Case */

    for (TableId = 1; TableId <= MD_INTERFACE_NUM_DWELL_TABLES; TableId++) {
      if (MD_TableIsInMask(TableId, Msg->Payload.TableMask)) {
        NumTblInMask++;

        /* Setting Countdown to 1 causes a dwell packet to be issued */
        /* on first wakeup call received. */
        TableIndex = TableId - 1;
        MD_AppData.MD_DwellTables[TableIndex].Enabled = MD_Dwell_States_ENABLED;
        MD_AppData.MD_DwellTables[TableIndex].Countdown = 1;
        MD_AppData.MD_DwellTables[TableIndex].CurrentEntry = 0;
        MD_AppData.MD_DwellTables[TableIndex].PktOffset = 0;

        /* Change value in Table Services managed buffer */
        TableUpdateStatus = MD_UpdateTableEnabledField(TableIndex, MD_Dwell_States_ENABLED);
        if (TableUpdateStatus != CFE_SUCCESS) {
          ErrorCount++;
          Status = TableUpdateStatus;
        }

        /* If table contains a rate of zero, report that no processing will occur */
        if (MD_AppData.MD_DwellTables[TableIndex].Rate == 0) {
          CFE_EVS_SendEvent(MD_ZERO_RATE_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "Dwell Table %d is enabled with a delay of zero so no processing will occur",
                            TableId);
        }
      }
    }

    if (ErrorCount == 0) {
      MD_AppData.CommandCounter++;

      CFE_EVS_SendEvent(MD_START_DWELL_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Start Dwell Table command processed successfully for table mask 0x%04X",
                        Msg->Payload.TableMask);
    } else {
      MD_AppData.CommandErrorCounter++;

      CFE_EVS_SendEvent(MD_START_DWELL_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Start Dwell Table for mask 0x%04X failed for %d of %d tables",
                        Msg->Payload.TableMask, ErrorCount, NumTblInMask);
    }
  } else /* No valid table id's specified in mask */ {
    MD_AppData.CommandErrorCounter++;
    CFE_EVS_SendEvent(MD_EMPTY_TBLMASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "%s command rejected because no tables were specified in table mask (0x%04X)",
                      "Start Dwell", Msg->Payload.TableMask);
  }
  return Status;
}

/******************************************************************************/

I32 MD_StopDwellCmd(MD_StopDwellCmd_t *Msg)
{
  I32 ErrorCount = 0;
  I32 Status;
  I32 TableUpdateStatus;
  I32 NumTblInMask = 0; /* Purely as info for event message */
  U16 TableId = 0;
  U16 TableIndex;
  Bool AnyTablesInMask = FALSE;

  Status = CFE_SUCCESS;

  for (TableId = 1; TableId <= MD_INTERFACE_NUM_DWELL_TABLES; TableId++) {
    if (MD_TableIsInMask(TableId, Msg->Payload.TableMask)) {
      NumTblInMask++;
      TableIndex = TableId - 1;
      MD_AppData.MD_DwellTables[TableIndex].Enabled = MD_Dwell_States_DISABLED;
      MD_AppData.MD_DwellTables[TableIndex].Countdown = 0;
      MD_AppData.MD_DwellTables[TableIndex].CurrentEntry = 0;
      MD_AppData.MD_DwellTables[TableIndex].PktOffset = 0;

      AnyTablesInMask = TRUE;

      /* Change value in Table Services managed buffer */
      TableUpdateStatus = MD_UpdateTableEnabledField(TableIndex, MD_Dwell_States_DISABLED);
      if (TableUpdateStatus != CFE_SUCCESS) {
        ErrorCount++;
        Status = TableUpdateStatus;
      }
    }
  }

  if (AnyTablesInMask) {
    if (ErrorCount == 0) {
      CFE_EVS_SendEvent(MD_STOP_DWELL_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Stop Dwell Table command processed successfully for table mask 0x%04X",
                        Msg->Payload.TableMask);

      MD_AppData.CommandCounter++;
    } else {
      MD_AppData.CommandErrorCounter++;

      CFE_EVS_SendEvent(MD_STOP_DWELL_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Stop Dwell Table for mask 0x%04X failed for %d of %d tables",
                        Msg->Payload.TableMask, ErrorCount, NumTblInMask);
    }
  } else {
    CFE_EVS_SendEvent(MD_EMPTY_TBLMASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "%s command rejected because no tables were specified in table mask (0x%04X)",
                      "Stop Dwell", Msg->Payload.TableMask);
    MD_AppData.CommandErrorCounter++;
  }
  return Status;
}

/******************************************************************************/

I32 MD_JamDwellCmd(MD_JamDwellCmd_t *Msg)
{
  /* Local variables */
  I32 Status;
  Bool AllInputsValid = TRUE;
  U64 ResolvedAddr = 0;
  MD_DwellControlEntry_t *DwellEntryPtr; /* points to local task data */
  U16 EntryIndex;
  U8 TableIndex = 0;
  MD_SymAddr_t NewDwellAddress;

  Status = CFE_SUCCESS;

  /* In case Dwell Address sym name isn't null terminated, do it now. */
  // Msg->Payload.DwellAddress.SymName[CFE_MISSION_MAX_PATH_LEN - 1] = '\0';

  /*
  **  Check that TableId and EntryId command arguments,
  **  which are used as array indexes, are valid.
  */
  if (!MD_ValidTableId(Msg->Payload.TableId)) {
    CFE_EVS_SendEvent(MD_INVALID_JAM_TABLE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Jam Cmd rejected due to invalid Tbl Id arg = %d (Expect 1.. %d)",
                      Msg->Payload.TableId, MD_INTERFACE_NUM_DWELL_TABLES);

    AllInputsValid = FALSE;
  }

  else if (!MD_ValidEntryId(Msg->Payload.EntryId)) {
    CFE_EVS_SendEvent(MD_INVALID_ENTRY_ARG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Jam Cmd rejected due to invalid Entry Id arg = %d (Expect 1.. %d)",
                      Msg->Payload.EntryId, MD_INTERFACE_DWELL_TABLE_SIZE);

    AllInputsValid = FALSE;
  } else {
    AllInputsValid = TRUE;
  }

  /*
  **  If all inputs checked so far are valid, continue.
  */
  if (AllInputsValid == TRUE) {
    TableIndex = Msg->Payload.TableId - 1;
    EntryIndex = Msg->Payload.EntryId - 1;

    DwellEntryPtr = &MD_AppData.MD_DwellTables[TableIndex].Entry[EntryIndex];

    if (Msg->Payload.FieldLength == 0)
    /*
    **  Jam a null entry.  Set all entry fields to zero.
    */
    {
      /* Assign local values */
      DwellEntryPtr->ResolvedAddress = 0;
      DwellEntryPtr->Length = 0;
      DwellEntryPtr->Delay = 0;

      /* Update Table Services buffer */
      NewDwellAddress.Offset = 0;
      NewDwellAddress.SymName[0] = '\0';
      // NASA passes NewDwellAddress BY VALUE and only these two fields are set, so the rest of
      // the 72 bytes is uninitialised stack -- see the note at the top of this file. The `&` is
      // limit #26, and no gate checks a CALL SITE.
      Status = MD_UpdateTableDwellEntry(TableIndex, EntryIndex, 0, 0, &NewDwellAddress);

      /* Issue event */
      if (Status == CFE_SUCCESS) {
        CFE_EVS_SendEvent(MD_JAM_NULL_DWELL_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Successful Jam of a Null Dwell Entry to Dwell Tbl#%d Entry #%d",
                          Msg->Payload.TableId, Msg->Payload.EntryId);
      } else {
        CFE_EVS_SendEvent(MD_JAM_NULL_DWELL_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Failed Jam of a Null Dwell Entry to Dwell Tbl#%d Entry #%d",
                          Msg->Payload.TableId, Msg->Payload.EntryId);

        AllInputsValid = FALSE;
      }
    } else
    /*
    **  Process non-null entry.
    */
    {
      /*
      **  Check that address and field length arguments pass all validity checks.
      */

      /* Resolve and Validate Dwell Address */
      if (MD_ResolveSymAddr(&Msg->Payload.DwellAddress, &ResolvedAddr) == FALSE) {
        /* If DwellAddress argument couldn't be resolved, issue error event */
        CFE_EVS_SendEvent(MD_CANT_RESOLVE_JAM_ADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Jam Cmd rejected because symbolic address '%s' couldn't be resolved",
                          Msg->Payload.DwellAddress.SymName);
        AllInputsValid = FALSE;
      } else if (!MD_ValidFieldLength(Msg->Payload.FieldLength)) {
        CFE_EVS_SendEvent(MD_INVALID_LEN_ARG_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Jam Cmd rejected due to invalid Field Length arg = %d (Expect 0,1,2,or 4)",
                          Msg->Payload.FieldLength);
        AllInputsValid = FALSE;
      } else if (!MD_ValidAddrRange(ResolvedAddr, Msg->Payload.FieldLength)) {
        /* Issue event message that ResolvedAddr is invalid */
        CFE_EVS_SendEvent(MD_INVALID_JAM_ADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Jam Cmd rejected because address 0x%08X is not in a valid range",
                          ResolvedAddr);
        AllInputsValid = FALSE;
      }
      // MD_INTERFACE_ENFORCE_DWORD_ALIGN is 1, so this is NASA's `#else` arm. Its dead `== 0`
      // arm checks 16-bit instead -- and still says `Jam->Payload` where the live code says
      // `Msg->`, which is evidence in NASA's own tree that it is never compiled.
      else if ((Msg->Payload.FieldLength == 4) &&
               MD_Verify32Aligned(ResolvedAddr, Msg->Payload.FieldLength) != TRUE) {
        CFE_EVS_SendEvent(MD_JAM_ADDR_NOT_32BIT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Jam Cmd rejected because address 0x%08X is not 32-bit aligned",
                          ResolvedAddr);
        AllInputsValid = FALSE;
      } else if ((Msg->Payload.FieldLength == 2) &&
                 MD_Verify16Aligned(ResolvedAddr, Msg->Payload.FieldLength) != TRUE) {
        CFE_EVS_SendEvent(MD_JAM_ADDR_NOT_16BIT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Jam Cmd rejected because address 0x%08X is not 16-bit aligned",
                          ResolvedAddr);
        AllInputsValid = FALSE;
      } else {
        /* All inputs are valid */
        AllInputsValid = TRUE;
      }

      if (AllInputsValid == TRUE)
      /*
      ** Perform Jam Operation : Copy Resolved DwellAddress, Length, and Delay to
      ** local control structure.
      */
      {
        /* Jam the new values into Application control structure */
        DwellEntryPtr->ResolvedAddress = ResolvedAddr;
        DwellEntryPtr->Length = Msg->Payload.FieldLength;
        DwellEntryPtr->Delay = Msg->Payload.DwellDelay;

        /* Update values in Table Services buffer */
        NewDwellAddress.Offset = Msg->Payload.DwellAddress.Offset;

        // NASA'S SECOND sizeof IS WRITTEN OUT AS ITS CONSTANT. `sizeof(Msg->Payload.-
        // DwellAddress.SymName)` reaches the member through an ARROW, and
        // docs/HOLYC_STRUCT_LIMITS.md #16 records that `sizeof` through `->` DOES NOT PARSE --
        // it fails as a bare `0:1: error: parse error` with no line number, which is why this
        // took a bisect to find. The DOT form on the line above parses and is left alone
        // (pinned by tests/exec/cases/e_sizeof_member.hc). Both sizes resolve to
        // CFE_MISSION_MAX_PATH_LEN: SymName is `char[CFE_MISSION_MAX_PATH_LEN]` in
        // MD_SymAddr_t, which is the type of both the source and the destination here.
        CFE_SB_MessageStringGet(NewDwellAddress.SymName, Msg->Payload.DwellAddress.SymName, "",
                                sizeof(NewDwellAddress.SymName), CFE_MISSION_MAX_PATH_LEN);

        Status = MD_UpdateTableDwellEntry(TableIndex, EntryIndex, Msg->Payload.FieldLength,
                                          Msg->Payload.DwellDelay, &NewDwellAddress);

        /* Issue event */
        if (Status == CFE_SUCCESS) {
          CFE_EVS_SendEvent(MD_JAM_DWELL_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "Successful Jam to Dwell Tbl#%d Entry #%d", Msg->Payload.TableId,
                            Msg->Payload.EntryId);
        } else {
          CFE_EVS_SendEvent(MD_JAM_DWELL_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Failed Jam to Dwell Tbl#%d Entry #%d", Msg->Payload.TableId,
                            Msg->Payload.EntryId);

          AllInputsValid = FALSE;
        }
      }

    } /* end else Process non-null entry */

  } /* end if AllInputsValid */

  /*
  **  Handle bookkeeping.
  */
  if (AllInputsValid == TRUE) {
    MD_AppData.CommandCounter++;

    /* Update Dwell Table Control Info, including rate */
    MD_UpdateDwellControlInfo(TableIndex);

    /* If table contains a rate of zero, and it enabled report that no processing will occur */
    if ((MD_AppData.MD_DwellTables[TableIndex].Rate == 0) &&
        (MD_AppData.MD_DwellTables[TableIndex].Enabled == MD_Dwell_States_ENABLED)) {
      CFE_EVS_SendEvent(MD_ZERO_RATE_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Dwell Table %d is enabled with a delay of zero so no processing will occur",
                        Msg->Payload.TableId);
    }
  } else {
    MD_AppData.CommandErrorCounter++;
  }
  return Status;
}

/******************************************************************************/
// Present because MD_INTERFACE_SIGNATURE_OPTION is 1; NASA wraps the whole function in the
// `#if`. See md_msg.HC for why that is hand-resolved rather than written as a directive.

I32 MD_SetSignatureCmd(MD_SetSignatureCmd_t *Msg)
{
  I32 Status;
  U16 TblId = 0;
  U16 StringLength;

  Status = CFE_SUCCESS;

  TblId = Msg->Payload.TableId;

  /*
  **  Check for Null Termination of string
  */
  for (StringLength = 0; StringLength < MD_INTERFACE_SIGNATURE_FIELD_LENGTH; StringLength++) {
    if (Msg->Payload.Signature[StringLength] == '\0')
      break;
  }

  if (StringLength >= MD_INTERFACE_SIGNATURE_FIELD_LENGTH) {
    CFE_EVS_SendEvent(MD_INVALID_SIGNATURE_LENGTH_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Set Signature cmd rejected due to invalid Signature length");

    MD_AppData.CommandErrorCounter++;
  }

  /*
  ** Check for valid TableId argument
  */
  else if (!MD_ValidTableId(TblId)) {
    CFE_EVS_SendEvent(MD_INVALID_SIGNATURE_TABLE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Set Signature cmd rejected due to invalid Tbl Id arg = %d (Expect 1.. %d)",
                      TblId, MD_INTERFACE_NUM_DWELL_TABLES);

    MD_AppData.CommandErrorCounter++;
  }

  else

  /*
  **  Handle nominal case.
  */
  {
    /* Copy signature field to local dwell control structure */
    StrNCpy(MD_AppData.MD_DwellTables[TblId - 1].Signature, Msg->Payload.Signature,
            MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1);
    MD_AppData.MD_DwellTables[TblId - 1].Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1] = '\0';

    /* Update signature in Table Services buffer */
    Status = MD_UpdateTableSignature(TblId - 1, Msg->Payload.Signature);
    if (Status == CFE_SUCCESS) {
      CFE_EVS_SendEvent(MD_SET_SIGNATURE_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Successfully set signature for Dwell Tbl#%d to '%s'", TblId,
                        Msg->Payload.Signature);

      MD_AppData.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(MD_SET_SIGNATURE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to set signature for Dwell Tbl#%d. Update returned 0x%08X",
                        TblId, Status);

      MD_AppData.CommandErrorCounter++;
    }
  }
  return Status;
}
#endif
