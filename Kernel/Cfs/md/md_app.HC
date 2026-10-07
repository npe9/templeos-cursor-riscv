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
// Translation of NASA's MD/fsw/src/md_app.c -- MD's startup, its main loop, and the
// housekeeping packet. Seven functions, and the last of the app's six gated sources.
//
// IT IS A CYCLE WITH md_dispatch.c AND THEY ARE GATED TOGETHER. MD_AppMain calls MD_TaskPipe
// from there; MD_ProcessGroundCommand's switch calls MD_SendHkCmd from here. The same shape as
// every cFE module's task/dispatch pair, and the reason tools/cfs/module_deps.py had to stop
// attributing MD_TaskPipe to the EDS variant before it could say so.
//
// THE FOUR DWELL TABLES ARE CRITICAL. NASA registers them `CFE_TBL_OPT_DEFAULT |
// CFE_TBL_OPT_CRITICAL`, which means Table Services keeps a copy in the Critical Data Store so
// a processor reset can recover them -- and MD_InitTableServices' long branch is entirely about
// that recovery: CFE_TBL_Register answering CFE_TBL_INFO_RECOVERED_TBL, the recovered image
// being handed to MD_TableValidationFunc, and MD_CopyUpdatedTbl plus MD_StartDwellStream if it
// passes. This is the only place in the app where a table arrives without the ground sending
// it.
//
// MD_AppData IS DEFINED HERE, NOT IN THE DRIVER. Until this file was gated, the C half of the
// differential oracle supplied `MD_AppData_t MD_AppData;` itself, because NASA defines it in
// this source. tools/cfs/check_oracle_globals.py refuses that overlap -- a C tentative
// definition in two translation units MERGES SILENTLY -- so the oracle's copy goes away in the
// same commit that gates this file. That gate was written four commits ago with this deadline
// in mind.
//
// snprintf BECOMES StrPrintN, AND THE `< 0` BRANCH GOES WITH IT. NASA checks `Status < 0` after
// each snprintf to catch an encoding error; CfsStr.HC's StrPrintN returns the length it wrote
// and never a negative, so those two branches are unreachable in the translation exactly as
// they are unreachable in the C for these arguments (a literal format and a small integer).
// The branches are kept because they are NASA's, and because the event ids in them are real.
#ifndef MD_APP_HC
#define MD_APP_HC

// md_perfids.h
#define MD_APPMAIN_PERF_ID 26

// md_eventids.h, the fifteen ids this file raises.
#define MD_INIT_INF_EID                    1
#define MD_PIPE_ERR_EID                    2
#define MD_RECOVERED_TBL_VALID_INF_EID     3
#define MD_RECOVERED_TBL_NOT_VALID_ERR_EID 4
#define MD_DWELL_TBL_TOO_LARGE_CRIT_EID    5
#define MD_TBL_REGISTER_CRIT_EID           6
#define MD_TBL_INIT_INF_EID                7
#define MD_TBL_STATUS_ERR_EID              20
#define MD_NO_TBL_COPY_ERR_EID             39
#define MD_INIT_TBL_NAME_ERR_EID           61
#define MD_INIT_TBL_FILENAME_ERR_EID       62
#define MD_CR_PIPE_ERR_EID                 71
#define MD_SUB_HK_ERR_EID                  72
#define MD_SUB_CMD_ERR_EID                 73
#define MD_SUB_WAKEUP_ERR_EID              74

// md_internal_cfg.h -- the two this file uses that md_msg.HC does not already carry.
#define MD_INTERNAL_PIPE_NAME           "MD_CMD_PIPE"
#define MD_INTERNAL_TBL_FILENAME_FORMAT "/cf/md_dw%02d.tbl"

// cfe_error.h. Both are 0xc0000000, and MD_ManageDwellTable masks a status with the first and
// compares against the second to ask "is this an error at all".
#define CFE_SEVERITY_BITMASK 0xc0000000(I32)
#define CFE_SEVERITY_ERROR   0xc0000000(I32)

// MD_AppMain calls MD_TaskPipe, which is defined in md_dispatch.HC -- the other half of this
// cycle, included after this file.
U0 MD_TaskPipe(CFE_SB_Buffer *BufPtr);
// And these three are defined below MD_AppMain.
I32 MD_AppInit();
U0 MD_InitControlStructures();
I32 MD_InitSoftwareBusServices();
I32 MD_InitTableServices();
I32 MD_ManageDwellTable(U8 TblIndex);

/*******************************************************************************/
// NASA: `MD_AppData_t MD_AppData;` at the top of md_app.c. Defined in md_global.HC beside its
// type, the arrangement every cfe_*_global.HC records.

U0 MD_AppMain()
{
  I32 Status = CFE_SUCCESS;
  U8 TblIndex = 0;
  CFE_SB_Buffer *BufPtr = NULL;

  MD_AppData.RunStatus = CFE_ES_RunStatus_APP_RUN;

  /* Create the first Performance Log entry */
  CFE_ES_PerfLogEntry(MD_APPMAIN_PERF_ID);

  /* Initialize the task */
  Status = MD_AppInit();

  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("MD:Application Init Failed,RC=%08x\n", Status);
    MD_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
  }

  /* Loop Forever, or until ES exit command, or SB error  */
  while (CFE_ES_RunLoop(&MD_AppData.RunStatus) == TRUE) {
    /* Copy any newly loaded tables */
    for (TblIndex = 0; TblIndex < MD_INTERFACE_NUM_DWELL_TABLES; TblIndex++) {
      MD_ManageDwellTable(TblIndex);

    } /* end for each table loop */

    CFE_ES_PerfLogExit(MD_APPMAIN_PERF_ID);

    /* Wait for next message */
    Status = CFE_SB_ReceiveBuffer(&BufPtr, MD_AppData.CmdPipe, MD_SB_TIMEOUT);
    if (Status == CFE_SB_TIME_OUT) {
      /* No action, but also no error */
    } else if (Status != CFE_SUCCESS) {
      /*
      ** Exit on pipe read error
      */
      CFE_EVS_SendEvent(MD_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "SB Pipe Read Error, App will exit. Pipe Return Status = %08x", Status);

      MD_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }

    CFE_ES_PerfLogEntry(MD_APPMAIN_PERF_ID);

    /* Process message if received successfully */
    if (Status == CFE_SUCCESS) {
      MD_TaskPipe(BufPtr);
    }

  } /* end while forever loop */

  /*
  ** Performance Log Exit Stamp.
  */
  CFE_ES_PerfLogExit(MD_APPMAIN_PERF_ID);

  /*
  ** Exit the Application
  */
  CFE_ES_ExitApp(MD_AppData.RunStatus);
}

/******************************************************************************/

I32 MD_AppInit()
{
  /*
  ** Locals
  */
  I32 Status = CFE_SUCCESS;

  MD_AppData.CommandCounter = 0;
  MD_AppData.CommandErrorCounter = 0;

  /* Initialize local control structures */
  MD_InitControlStructures();

  /* Register for event services...*/
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_NO_FILTER);

  if (Status == CFE_SUCCESS) {
    /*
    ** Set up for Software Bus Services
    */
    Status = MD_InitSoftwareBusServices();
  } else {
    CFE_ES_WriteToSysLog("MD_APP:Call to CFE_EVS_Register Failed:RC=%d\n", Status);
  }

  /*
  ** Register for Table Services
  */
  if (Status == CFE_SUCCESS) {
    Status = MD_InitTableServices();
  }

  /*
  ** Issue Event Message
  */
  if (Status == CFE_SUCCESS) {
    Status = CFE_EVS_SendEvent(MD_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                               "MD Initialized.  Version %d.%d.%d.%d", MD_MAJOR_VERSION,
                               MD_MINOR_VERSION, MD_REVISION, MD_INTERNAL_MISSION_REV);
  }

  return Status;
}

/******************************************************************************/
U0 MD_InitControlStructures()
{
  U16 TblIndex;
  MD_DwellPacketControl_t *DwellControlPtr = NULL;

  for (TblIndex = 0; TblIndex < MD_INTERFACE_NUM_DWELL_TABLES; TblIndex++) {
    DwellControlPtr = &MD_AppData.MD_DwellTables[TblIndex];

    MemSet(DwellControlPtr, 0, sizeof(MD_DwellPacketControl_t));

    /* Countdown must be set to 1 since it's decremented at the top of */
    /* the dwell loop. */
    DwellControlPtr->Countdown = 1;

    // MD_INTERFACE_SIGNATURE_OPTION is 1. NASA copies an EMPTY string over the whole field,
    // which strncpy zero-fills -- redundant after the MemSet above, and kept because it is
    // NASA's line.
    StrNCpy(DwellControlPtr->Signature, "", MD_INTERFACE_SIGNATURE_FIELD_LENGTH);

  } /* end for TblIndex loop */
}

/******************************************************************************/
I32 MD_InitSoftwareBusServices()
{
  I32 Status = CFE_SUCCESS;
  U16 TblIndex;

  /*
  ** Initialize housekeeping telemetry packet (clear user data area)
  */
  // CFE_MSG_PTR(x) is NASA's &x.Msg, written out as it is elsewhere in this port.
  CFE_MSG_Init(&MD_AppData.HkPkt.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(MD_HK_TLM_MID),
               sizeof(MD_HkTlm_t));
  /*
  ** Initialize dwell packets (clear user data area)
  */
  for (TblIndex = 0; TblIndex < MD_INTERFACE_NUM_DWELL_TABLES; TblIndex++) {
    CFE_MSG_Init(&MD_AppData.MD_DwellPkt[TblIndex].TelemetryHeader.Msg,
                 CFE_SB_ValueToMsgId(MD_DWELL_PKT_MID_BASE + TblIndex),
                 sizeof(MD_DwellPkt_t)); /* this is max pkt size */

    // MD_INTERFACE_SIGNATURE_OPTION is 1.
    MD_AppData.MD_DwellPkt[TblIndex].Payload.Signature[0] = '\0';
  }

  /*
  **  Create Software Bus message pipe
  */
  Status = CFE_SB_CreatePipe(&MD_AppData.CmdPipe, MD_INTERNAL_PIPE_DEPTH, MD_INTERNAL_PIPE_NAME);

  if (Status == CFE_SUCCESS) {
    /*
     ** Subscribe to Housekeeping request commands
     */
    Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(MD_SEND_HK_MID), MD_AppData.CmdPipe);

    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(MD_SUB_HK_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to subscribe to HK requests  RC = %d", Status);
    }
  } else {
    CFE_EVS_SendEvent(MD_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Failed to create pipe.  RC = %d", Status);
  }

  /*
  ** Subscribe to MD ground command packets
  */
  if (Status == CFE_SUCCESS) {
    Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(MD_CMD_MID), MD_AppData.CmdPipe);

    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(MD_SUB_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to subscribe to commands.  RC = %d", Status);
    }
  }

  /*
  ** Subscribe to MD wakeup packets
  */
  if (Status == CFE_SUCCESS) {
    Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(MD_WAKEUP_MID), MD_AppData.CmdPipe);

    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(MD_SUB_WAKEUP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to subscribe to wakeup messages.  RC = %08x", Status);
    }
  }

  return Status;
}

/******************************************************************************/

I32 MD_InitTableServices()
{
  I32 Status = CFE_SUCCESS;
  I32 GetAddressResult = 0;
  U8 TblIndex;
  Bool RecoveredValidTable = TRUE; /* for current table */
  Bool TableInitValidFlag = TRUE;  /* for all tables so far*/
  MD_DwellTableLoad_t *MD_LoadTablePtr = NULL;
  U16 TblRecos = 0; /* Number of Tables Recovered */
  U16 TblInits = 0; /* Number of Tables Initialized */
  U8 TblFileName[OS_MAX_PATH_LEN];

  /*
  ** For each table, load recovered data if available and valid.
  ** Otherwise, load initial data.
  */

  for (TblIndex = 0; (TblIndex < MD_INTERFACE_NUM_DWELL_TABLES) && (TableInitValidFlag == TRUE);
       TblIndex++) {
    RecoveredValidTable = FALSE;

    /* Prepare Table Name */
    // snprintf -> StrPrintN, and the size is written out: NASA's
    // `sizeof(MD_AppData.MD_TableName[TblIndex])` indexes a 2-D member inside a sizeof, which
    // is the arrow/sizeof family limit #16 territory. The field is
    // char[CFE_MISSION_TBL_MAX_NAME_LENGTH + 1], which is what the sizeof resolves to.
    Status = StrPrintN(MD_AppData.MD_TableName[TblIndex], CFE_MISSION_TBL_MAX_NAME_LENGTH + 1,
                       "%s%d", MD_DWELL_TABLE_BASENAME, TblIndex + 1);
    if (Status < 0) {
      CFE_EVS_SendEvent(MD_INIT_TBL_NAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "TableName could not be made. Err=0x%08X, Idx=%u", Status, TblIndex);

      TableInitValidFlag = FALSE;

      /* Advance to the next index */
      continue;
    }

    /* allows total of CFE_TBL_MAX_NAME_LENGTH characters to be copied */
    Status = StrPrintN(TblFileName, OS_MAX_PATH_LEN, MD_INTERNAL_TBL_FILENAME_FORMAT,
                       TblIndex + 1);

    if (Status < 0) {
      CFE_EVS_SendEvent(MD_INIT_TBL_FILENAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "TblFileName could not be made. Err=0x%08X, Idx=%u", Status, TblIndex);

      TableInitValidFlag = FALSE;

      /* Advance to the next index */
      continue;
    }

    /* Register Dwell Table #tblnum */
    Status = CFE_TBL_Register(&MD_AppData.MD_TableHandle[TblIndex], /* Table Handle (to be returned) */
                              MD_AppData.MD_TableName[TblIndex],    /*   Table Name */
                              sizeof(MD_DwellTableLoad_t),          /* Size of Table being Registered */
                              CFE_TBL_OPT_DEFAULT | CFE_TBL_OPT_CRITICAL,
                              &MD_TableValidationFunc); /* Ptr to table validation function */

    /* Check for recovered table data */
    if (Status == CFE_TBL_INFO_RECOVERED_TBL) {
      /* Restore dwell table contents from CDS */

      GetAddressResult = CFE_TBL_GetAddress(&MD_LoadTablePtr, MD_AppData.MD_TableHandle[TblIndex]);

      if (GetAddressResult != CFE_TBL_INFO_UPDATED) {
        CFE_EVS_SendEvent(MD_NO_TBL_COPY_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Didn't update MD tbl #%d due to unexpected CFE_TBL_GetAddress return: 0x%08X",
                          TblIndex + 1, GetAddressResult);
      }

      else /* GetAddressResult == CFE_TBL_INFO_UPDATED*/ {
        if (MD_TableValidationFunc(MD_LoadTablePtr) == CFE_SUCCESS) {
          MD_CopyUpdatedTbl(MD_LoadTablePtr, TblIndex);

          if (MD_LoadTablePtr->Enabled == MD_Dwell_States_ENABLED) {
            MD_StartDwellStream(TblIndex);
          }

          RecoveredValidTable = TRUE;
          TblRecos++;
          CFE_EVS_SendEvent(MD_RECOVERED_TBL_VALID_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "Recovered Dwell Table #%d is valid and has been copied to the MD App",
                            TblIndex + 1);
        } else {
          CFE_EVS_SendEvent(MD_RECOVERED_TBL_NOT_VALID_ERR_EID, CFE_EVS_EventType_ERROR,
                            "MD App will reinitialize Dwell Table #%d because recovered table is not valid",
                            TblIndex + 1);
        }

      } /* end if(GetAddressResult != CFE_TBL_INFO_UPDATED) */

      /* Unlock Table */
      CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[TblIndex]);

    } /* end if Register indicates recovered data */

    else if (Status == CFE_TBL_ERR_INVALID_SIZE) {
      CFE_EVS_SendEvent(MD_DWELL_TBL_TOO_LARGE_CRIT_EID, CFE_EVS_EventType_CRITICAL,
                        "Dwell Table(s) are too large to register: %u bytes, %d entries",
                        sizeof(MD_DwellTableLoad_t), MD_INTERFACE_DWELL_TABLE_SIZE);
      TableInitValidFlag = FALSE;
    }

    else if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(MD_TBL_REGISTER_CRIT_EID, CFE_EVS_EventType_CRITICAL,
                        "CFE_TBL_Register error %08x received for tbl#%u", Status, TblIndex + 1);
      TableInitValidFlag = FALSE;
    } else {
      /* Table is registered and valid */
      TableInitValidFlag = TRUE;
    }

    /*
    ** Load initial values if needed
    */
    if ((RecoveredValidTable == FALSE) && (TableInitValidFlag == TRUE)) {
      Status = CFE_TBL_Load(MD_AppData.MD_TableHandle[TblIndex],
                            CFE_TBL_SRC_FILE, /*  following ptr is memory ptr */
                            TblFileName);     /* Pointer to data to be loaded */

      MD_AppData.MD_DwellTables[TblIndex].Enabled = MD_Dwell_States_DISABLED;

      if (Status != CFE_SUCCESS) {
        CFE_ES_WriteToSysLog("MD_APP: Error 0x%08X received loading tbl#%u\n", Status,
                             TblIndex + 1);
        TableInitValidFlag = FALSE;
      } else {
        TblInits++;
      }
    }

    if (TableInitValidFlag == TRUE) {
      /* Update Dwell Table Control Info, including rate */
      MD_UpdateDwellControlInfo(TblIndex);
    }

  } /* end for loop */

  /* Output init and recovery event message */
  CFE_EVS_SendEvent(MD_TBL_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Dwell Tables Recovered: %u, Dwell Tables Initialized: %u", TblRecos,
                    TblInits);

  if (TableInitValidFlag == TRUE) {
    return CFE_SUCCESS;
  } else {
    return Status;
  }
}

/******************************************************************************/
I32 MD_ManageDwellTable(U8 TblIndex)
{
  I32 Status = CFE_SUCCESS;
  I32 GetAddressResult = 0;
  Bool FinishedManaging = FALSE;
  MD_DwellTableLoad_t *MD_LoadTablePtr = NULL;

  while (!FinishedManaging) {
    /* Determine if the table has a pending validation or update */
    Status = CFE_TBL_GetStatus(MD_AppData.MD_TableHandle[TblIndex]);

    if (Status == CFE_TBL_INFO_VALIDATION_PENDING) {
      /* Validate the specified Table */
      Status = CFE_TBL_Validate(MD_AppData.MD_TableHandle[TblIndex]);

      if (Status != CFE_SUCCESS) {
        /* If an error occurred during Validate, */
        /* then do not perform any more managing */
        FinishedManaging = TRUE;
      }
    } else if (Status == CFE_TBL_INFO_UPDATE_PENDING) {
      Status = CFE_TBL_Update(MD_AppData.MD_TableHandle[TblIndex]);

      /* If table was updated, copy contents to local structure */
      if (Status == CFE_SUCCESS) {
        GetAddressResult = CFE_TBL_GetAddress(&MD_LoadTablePtr,
                                              MD_AppData.MD_TableHandle[TblIndex]);

        if (GetAddressResult == CFE_TBL_INFO_UPDATED) {
          MD_CopyUpdatedTbl(MD_LoadTablePtr, TblIndex);

          if (MD_LoadTablePtr->Enabled == MD_Dwell_States_ENABLED) {
            MD_StartDwellStream(TblIndex);
          }
        } else {
          CFE_EVS_SendEvent(MD_NO_TBL_COPY_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Didn't update MD tbl #%d due to unexpected CFE_TBL_GetAddress return: %u",
                            TblIndex + 1, GetAddressResult);
        }

        /* Unlock Table */
        CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[TblIndex]);
      }

      /* After an Update, always assume we are done */
      /* and return Update Status */
      FinishedManaging = TRUE;
    } else if ((Status & CFE_SEVERITY_BITMASK) == CFE_SEVERITY_ERROR) {
      CFE_EVS_SendEvent(MD_TBL_STATUS_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Received unexpected error %08x from CFE_TBL_GetStatus for tbl #%u",
                        Status, TblIndex + 1);
      FinishedManaging = TRUE;
    }

    else {
      FinishedManaging = TRUE;
    }
  }

  return Status;
}

/******************************************************************************/
I32 MD_SendHkCmd(MD_SendHkCmd_t *Msg)
{
  U8 TblIndex;
  U16 MemDwellEnableBits = 0;
  MD_HkTlm_t *HkPktPtr = NULL;
  MD_DwellPacketControl_t *ThisDwellTablePtr = NULL;

  /* Assign pointer used as shorthand to access Housekeeping Packet fields */
  HkPktPtr = &MD_AppData.HkPkt;

  /* Assign values for command counters */

  HkPktPtr->Payload.ValidCmdCntr = MD_AppData.CommandCounter;
  HkPktPtr->Payload.InvalidCmdCntr = MD_AppData.CommandErrorCounter;

  for (TblIndex = 0; TblIndex < MD_INTERFACE_NUM_DWELL_TABLES; TblIndex++) {
    /*
    **  Prepare the DwellEnabledMask showing which dwell streams are enabled
    */

    /*   The dwell enabled bits are set in the following bit pattern:
     0x0001 = table 1 enabled, 0x0002 = table 2 enabled
     0x0004 = table 3 enabled, 0x0008 = table 4 enabled,
     0x0010 = table 5 enabled, etc.
    */
    MemDwellEnableBits |= (MD_AppData.MD_DwellTables[TblIndex].Enabled << (TblIndex));

    /* Assign pointer used as shorthand to access current dwell tbl data */
    ThisDwellTablePtr = &MD_AppData.MD_DwellTables[TblIndex];

    /*
    **  Insert current values for each dwell stream
    */
    HkPktPtr->Payload.DwellTblAddrCount[TblIndex] = ThisDwellTablePtr->AddrCount;
    HkPktPtr->Payload.NumWaitsPerPkt[TblIndex] = ThisDwellTablePtr->Rate;
    HkPktPtr->Payload.DwellPktOffset[TblIndex] = ThisDwellTablePtr->PktOffset;
    HkPktPtr->Payload.ByteCount[TblIndex] = ThisDwellTablePtr->DataSize;
    HkPktPtr->Payload.DwellTblEntry[TblIndex] = ThisDwellTablePtr->CurrentEntry;
    HkPktPtr->Payload.Countdown[TblIndex] = ThisDwellTablePtr->Countdown;
  }

  HkPktPtr->Payload.DwellEnabledMask = MemDwellEnableBits;

  /*
  ** Send housekeeping telemetry packet...
  */
  CFE_SB_TimeStampMsg(&HkPktPtr->TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&HkPktPtr->TelemetryHeader.Msg, TRUE);

  return CFE_SUCCESS;
}
#endif
