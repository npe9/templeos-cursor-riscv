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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_cmds.c -- MM's FOURTEEN GROUND COMMANDS, and
// the largest source in the app at 1,116 lines.
//
// THIS IS WHERE EVERY OTHER MM FILE IS CALLED FROM. The width files, the generic paths, the
// validators and the resolver are all leaves; this file is the only caller of any of them, and
// its shape is the same five steps over and over:
//
//     resolve the symbolic address  ->  verify the parameters  ->  switch on the memory type
//       ->  call the right worker  ->  move the command counter and send an event
//
// SO THE COMMAND COUNTERS ARE THE PRODUCT OF THIS FILE, and they are the thing to watch: every
// one of the fourteen returns CFE_SUCCESS whatever happened, and the ONLY record of a failure is
// CommandErrorCounter plus an event. A handler that returned a status nobody reads would be
// indistinguishable from one that worked.
//
// ------------------------------------------------------------------------------------------
// MM_FillMemCmd COUNTS A FAILED FILL AS A SUCCESS, and it is translated verbatim:
//
//     if (Status == CFE_PSP_SUCCESS) {
//         if (LastAction == MM_LastAction_FILL) { CommandCounter++; ...event... }
//         else                                 { CommandErrorCounter++; }
//     } else {
//         MM_AppData.HkTlm.Payload.CommandCounter++;      <-- the SUCCESS counter
//     }
//
// WHICH INPUT REACHES THE `else` TOOK MEASURING, and the first answer written here was wrong.
// It said an unaligned length does it, because mm_mem16.c and mm_mem32.c round the length down
// and then fail their housekeeping guard -- but MM_VerifyLoadDumpParams checks the alignment of
// the SIZE as well as the address for those two memory types, so an unaligned fill is refused
// one level earlier and lands in the OUTER else, which counts correctly. The rounding warning in
// mm_mem16/32 is defensive code that this command path cannot reach at all.
//
// The route that does reach it is a PSP WRITE FAILURE: MM_FillMem8/16/32 return CFE_PSP_ERROR
// when a store is refused, which on real hardware is a fill that ran off the end of a region.
// So a fill that wrote PART of its range and then failed moves MM's SUCCESS counter and sends no
// event at all -- the ground sees a command that worked. The second upstream defect this app has
// produced, and kept for the same reason as the first. Driven with the simulated window's
// store-failure knob.
// ------------------------------------------------------------------------------------------
#ifndef MM_CMDS_HC
#define MM_CMDS_HC

// --- mm_version.h ----------------------------------------------------------------------------
#define MM_MAJOR_VERSION 7
#define MM_MINOR_VERSION 0
#define MM_REVISION      1

// --- osapi-file.h ----------------------------------------------------------------------------
#ifndef OS_READ_WRITE
#define OS_READ_WRITE 2
#endif

// --- cfe_psp.h -------------------------------------------------------------------------------
// The EEPROM bank lock. On real hardware these drive a write-protect line; the driver supplies
// them, and unlike the EepromWrite* trio they have no simulated region of their own because
// nothing in MM reads back a bank's state.
I32 CFE_PSP_EepromWriteEnable(U32 Bank);
I32 CFE_PSP_EepromWriteDisable(U32 Bank);

// --- what this file needs from elsewhere -----------------------------------------------------
I32 OS_SymbolTableDump(U8 *filename, I64 size_limit);

// NASA declares EventString `static` INSIDE MM_DumpInEventCmd -- 122 bytes, too big to want on
// the stack and needed only there. Hoisted to file scope under the enclosing function's name,
// which is this port's convention for a static local (docs/HOLYC_STRUCT_LIMITS.md #12: HolyC
// scopes a static local's NAME globally, so a bare `EventString` would be a collidable global).
U8 MM_DumpInEventCmd_EventString[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];

/*******************************************************************************/
// Housekeeping request.
//
// AND IT DOES NOT MOVE THE COMMAND COUNTER, which NASA says in a comment and which matters:
// housekeeping arrives once a second, so counting it would swamp the number that tells an
// operator how many real commands MM has run.
I32 MM_SendHkCmd(MM_SendHkCmd_t *Msg)
{
  /*
  ** Send housekeeping telemetry packet
  */
  CFE_SB_TimeStampMsg(&MM_AppData.HkTlm.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&MM_AppData.HkTlm.TelemetryHeader.Msg, TRUE);

  /*
  ** This command does not affect the command execution counter
  */

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Noop command.
I32 MM_NoopCmd(MM_NoopCmd_t *Msg)
{
  MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_NOOP;
  MM_AppData.HkTlm.Payload.CommandCounter++;

  CFE_EVS_SendEvent(MM_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "No-op command. Version %d.%d.%d.%d", MM_MAJOR_VERSION, MM_MINOR_VERSION,
                    MM_REVISION, MM_INTERNAL_MISSION_REV);

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset counters command.
I32 MM_ResetCountersCmd(MM_ResetCountersCmd_t *Msg)
{
  MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_RESET;
  MM_AppData.HkTlm.Payload.CommandCounter = 0;
  MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;

  CFE_EVS_SendEvent(MM_RESET_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Reset counters command received");

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Lookup symbol name command.
//
// THE ONE COMMAND WHOSE WHOLE PRODUCT IS AN ADDRESS. It writes HkTlm.Address and nothing else,
// so the ground can learn where a symbol lives before poking it -- which is how an operator
// uses MM on a build they do not have the map for.
I32 MM_LookupSymCmd(MM_LookupSymCmd_t *Msg)
{
  I32 OS_Status;
  U64 ResolvedAddr = 0;
  U8 SymName[CFE_MISSION_MAX_PATH_LEN];

  /* Make sure string is null terminated before attempting to process it */
  CFE_SB_MessageStringGet(SymName, Msg->Payload.SymName, NULL, CFE_MISSION_MAX_PATH_LEN,
                          CFE_MISSION_MAX_PATH_LEN);

  /*
  ** Check if the symbol name string is a nul string
  */
  if (OS_strnlen(SymName, CFE_MISSION_MAX_PATH_LEN) == 0) {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_NUL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "NUL (empty) string specified as symbol name");
  } else {
    /*
    ** If symbol name is not an empty string look it up using the OSAL API
    */
    OS_Status = OS_SymbolLookup(&ResolvedAddr, SymName);
    if (OS_Status == OS_SUCCESS) {
      /* Update telemetry */
      MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_SYM_LOOKUP;
      MM_AppData.HkTlm.Payload.Address = ResolvedAddr;

      MM_AppData.HkTlm.Payload.CommandCounter++;
      CFE_EVS_SendEvent(MM_SYM_LOOKUP_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Symbol Lookup Command: Name = '%s' Addr = %p", SymName, ResolvedAddr);
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Symbolic address can't be resolved: Name = '%s'", SymName);
    }

  } /* end OS_strnlen(Msg->Payload.SymName, CFE_MISSION_MAX_PATH_LEN) == 0 else
     */

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Dump symbol table to file command.
I32 MM_SymTblToFileCmd(MM_SymTblToFileCmd_t *Msg)
{
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
  I32 OS_Status;

  /* Make sure string is null terminated before attempting to process it */
  CFE_SB_MessageStringGet(FileName, Msg->Payload.FileName, NULL, CFE_MISSION_MAX_PATH_LEN,
                          CFE_MISSION_MAX_PATH_LEN);

  /*
  ** Check if the filename string is a nul string
  */
  if (OS_strnlen(FileName, CFE_MISSION_MAX_PATH_LEN) == 0) {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMFILENAME_NUL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "NUL (empty) string specified as symbol dump file name");
  } else {
    OS_Status = OS_SymbolTableDump(FileName, MM_INTERNAL_MAX_DUMP_FILE_DATA_SYMTBL);
    if (OS_Status == OS_SUCCESS) {
      /* Update telemetry */
      MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_SYMTBL_SAVE;
      StrPrintN(MM_AppData.HkTlm.Payload.FileName, CFE_MISSION_MAX_PATH_LEN, "%s", FileName);

      MM_AppData.HkTlm.Payload.CommandCounter++;
      CFE_EVS_SendEvent(MM_SYMTBL_TO_FILE_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Symbol Table Dump to File Started: Name = '%s'", FileName);
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      CFE_EVS_SendEvent(MM_SYMTBL_TO_FILE_FAIL_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error dumping symbol table, OS_Status= 0x%X, File='%s'", OS_Status,
                        FileName);
    }
  } /* end OS_strnlen(FileName, CFE_MISSION_MAX_PATH_LEN) == 0 else */

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// EEPROM write-enable command.
//
// BOTH EVENTS PRINT THE STATUS, success and failure, which is unusual -- and useful, because the
// PSP's own return code is the only evidence the bank was really unlocked.
I32 MM_EepromWriteEnaCmd(MM_EepromWriteEnaCmd_t *Msg)
{
  I32 cFE_Status;

  /*
  ** Call the cFE to write-enable the requested bank
  */
  cFE_Status = CFE_PSP_EepromWriteEnable(Msg->Payload.Bank);
  if (cFE_Status == CFE_PSP_SUCCESS) {
    /* Update telemetry */
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_EEPROMWRITE_ENA;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_EEPROM;

    MM_AppData.HkTlm.Payload.CommandCounter++;
    CFE_EVS_SendEvent(MM_EEPROM_WRITE_ENA_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "EEPROM bank %d write enabled, cFE_Status= 0x%X", Msg->Payload.Bank,
                      cFE_Status);
  } else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_EEPROM_WRITE_ENA_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error requesting EEPROM bank %d write enable, cFE_Status= 0x%X",
                      Msg->Payload.Bank, cFE_Status);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// EEPROM write-disable command.
I32 MM_EepromWriteDisCmd(MM_EepromWriteDisCmd_t *Msg)
{
  I32 cFE_Status;

  /*
  ** Call the cFE to write-enable the requested bank
  */
  cFE_Status = CFE_PSP_EepromWriteDisable(Msg->Payload.Bank);
  if (cFE_Status == CFE_PSP_SUCCESS) {
    /* Update telemetry */
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_EEPROMWRITE_DIS;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_EEPROM;

    MM_AppData.HkTlm.Payload.CommandCounter++;
    CFE_EVS_SendEvent(MM_EEPROM_WRITE_DIS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "EEPROM bank %d write disabled, cFE_Status= 0x%X", Msg->Payload.Bank,
                      cFE_Status);
  } else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_EEPROM_WRITE_DIS_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error requesting EEPROM bank %d write disable, cFE_Status= 0x%X",
                      Msg->Payload.Bank, cFE_Status);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Memory poke ground command.
//
// THE ADDRESS IS COPIED OUT OF THE MESSAGE FIRST, and that is not a style choice:
// MM_ResolveSymAddr WRITES to its argument -- it NUL-terminates the last byte of the name -- and
// the message is const. So every handler here takes a local copy of the MM_SymAddr_t and
// resolves THAT. A local class assignment is whole in this compiler; it is the array-slot and
// bare-pointer forms that lose their tail (docs/HOLYC_STRUCT_LIMITS.md #21).
I32 MM_PokeCmd(MM_PokeCmd_t *Msg)
{
  U64 DestAddress = 0;
  MM_SymAddr_t DestSymAddress;
  I32 Status;

  DestSymAddress = Msg->Payload.DestSymAddress;

  /* Resolve the symbolic address in command message */
  Status = MM_ResolveSymAddr(&DestSymAddress, &DestAddress);

  if (Status == OS_SUCCESS) {
    /* Run necessary checks on command parameters */
    Status = MM_VerifyPeekPokeParams(DestAddress, Msg->Payload.MemType, Msg->Payload.DataSize);

    /* Check the specified memory type and call the appropriate routine */
    if (Status == OS_SUCCESS) {
      /* Check if we need special EEPROM processing */
      if (Msg->Payload.MemType == MM_MemType_EEPROM) {
        Status = MM_PokeEeprom(Msg, DestAddress);
      } else {
        /*
        ** We can use this routine for all other memory types
        *  (including the optional ones)
        */
        Status = MM_PokeMem(Msg, DestAddress);
      }

      if (Status == CFE_PSP_SUCCESS) {
        MM_AppData.HkTlm.Payload.CommandCounter++;
      } else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      }
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    } /* end MM_VerifyPeekPokeParams if */
  } /* end MM_ResolveSymAddr */
  else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Symbolic address can't be resolved: Name = '%s'", DestSymAddress.SymName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Load memory with interrupts disabled. Only valid for RAM addresses.
//
// THE DATA TRAVELS INSIDE THE COMMAND, up to MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA bytes with a
// CRC, and the move is a single memcpy -- no segments, no MM_SegmentBreak, nothing else gets to
// run between the first byte and the last. That is the whole point of the command: a patch that
// cannot be seen half-applied.
//
// AND THE MEMORY TYPE IS HARD-CODED TO RAM, not taken from the message, because an EEPROM
// programming cycle cannot be done uninterruptibly.
I32 MM_LoadMemWIDCmd(MM_LoadMemWIDCmd_t *Msg)
{
  U32 ComputedCRC;
  U64 DestAddress = 0;
  MM_SymAddr_t DestSymAddress;

  DestSymAddress = Msg->Payload.DestSymAddress;

  /* Resolve the symbolic address in command message */
  if (MM_ResolveSymAddr(&DestSymAddress, &DestAddress) == OS_SUCCESS) {
    /*
    ** Run some necessary checks on command parameters
    ** NOTE: A load with interrupts disabled command is only valid for RAM
    *addresses
    */
    if (MM_VerifyLoadDumpParams(DestAddress, MM_MemType_RAM, Msg->Payload.NumOfBytes,
                                MM_VERIFY_WID) == CFE_PSP_SUCCESS) {
      /* Verify data integrity check value */
      ComputedCRC = CFE_ES_CalculateCRC(Msg->Payload.DataArray, Msg->Payload.NumOfBytes, 0,
                                        MM_INTERNAL_LOAD_WID_CRC_TYPE);
      /*
      ** If the CRC matches do the load
      */
      if (ComputedCRC == Msg->Payload.Crc) {
        /* Load input data to input memory address */
        MemCpy(DestAddress(U8 *), Msg->Payload.DataArray, Msg->Payload.NumOfBytes);

        MM_AppData.HkTlm.Payload.CommandCounter++;
        CFE_EVS_SendEvent(MM_LOAD_WID_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Load Memory WID Command: Wrote %d bytes to address: %p",
                          Msg->Payload.NumOfBytes, DestAddress);

        /* Update last action statistics */
        MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_LOAD_WID;
        MM_AppData.HkTlm.Payload.Address = DestAddress;
        MM_AppData.HkTlm.Payload.MemType = MM_MemType_RAM;
        MM_AppData.HkTlm.Payload.BytesProcessed = Msg->Payload.NumOfBytes;
      } else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
        CFE_EVS_SendEvent(MM_LOAD_WID_CRC_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Interrupts Disabled Load CRC failure: Expected = "
                          "0x%X Calculated = 0x%X",
                          Msg->Payload.Crc, ComputedCRC);
      }
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    } /* end MM_VerifyLoadWIDParams */
  } /* end MM_ResolveSymAddr if */
  else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Symbolic address can't be resolved: Name = '%s'", DestSymAddress.SymName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Load memory from a file command.
//
// SEVEN NESTED CHECKS BEFORE A BYTE MOVES, and the order is the interesting part: open, read
// both headers, verify the file's SIZE against the header's claim, compute the CRC over the
// whole remaining file, SEEK BACK to the start of the data, compare the CRC, resolve the
// header's symbolic address, verify the parameters. Only then the switch on memory type.
//
// THE SEEK IS NOT HOUSEKEEPING. MM_ComputeCRCFromFile reads to end of file, so without it the
// load would start from EOF and move nothing -- and the check that it landed where it should is
// folded into the SAME `if` as the CRC comparison, so a failed seek is reported as a CRC error.
I32 MM_LoadMemFromFileCmd(MM_LoadMemFromFileCmd_t *Msg)
{
  I32 Status;
  U32 FileHandle = OS_OBJECT_ID_UNDEFINED;
  U64 DestAddress = 0;
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
  CFE_FS_Header_t CFEFileHeader;
  MM_LoadDumpFileHeader_t MMFileHeader;
  U32 ComputedCRC;
  I32 LSeekSize;

  MemSet(&MMFileHeader, 0, sizeof(MM_LoadDumpFileHeader_t));

  /* Make sure string is null terminated before attempting to process it */
  CFE_SB_MessageStringGet(FileName, Msg->Payload.FileName, NULL, CFE_MISSION_MAX_PATH_LEN,
                          CFE_MISSION_MAX_PATH_LEN);

  /* Open load file for reading */
  Status = OS_OpenCreate(&FileHandle, FileName, OS_FILE_FLAG_NONE, OS_READ_ONLY);
  if (Status == OS_SUCCESS) {
    /* Read in the file headers */
    Status = MM_ReadFileHeaders(FileName, FileHandle, &CFEFileHeader, &MMFileHeader);
    if (Status == OS_SUCCESS) {
      /* Verify the file size is correct */
      Status = MM_VerifyLoadFileSize(FileName, &MMFileHeader);
      if (Status == OS_SUCCESS) {
        /* Verify data integrity check value */
        Status = MM_ComputeCRCFromFile(FileHandle, &ComputedCRC, MM_INTERNAL_LOAD_FILE_CRC_TYPE);
        if (Status == OS_SUCCESS) {
          /*
          ** Reset the file pointer to the start of the load data, need to do
          *this
          ** because MM_ComputeCRCFromFile reads to the end of file
          */
          LSeekSize = OS_lseek(FileHandle,
                               sizeof(CFE_FS_Header_t) + sizeof(MM_LoadDumpFileHeader_t),
                               OS_SEEK_SET);
          if (LSeekSize != sizeof(CFE_FS_Header_t) + sizeof(MM_LoadDumpFileHeader_t)) {
            Status = OS_ERROR;
          }

          /* Check the computed CRC against the file header CRC */
          if (ComputedCRC == MMFileHeader.Crc && Status == OS_SUCCESS) {
            /* Resolve symbolic address in file header */
            Status = MM_ResolveSymAddr(&MMFileHeader.SymAddress, &DestAddress);

            if (Status == OS_SUCCESS) {
              /* Run necessary checks on command parameters */
              Status = MM_VerifyLoadDumpParams(DestAddress, MMFileHeader.MemType,
                                               MMFileHeader.NumOfBytes, MM_VERIFY_LOAD);
              if (Status == CFE_PSP_SUCCESS) {
                /* Call the load routine for the specified memory type */
                switch (MMFileHeader.MemType) {
                  case MM_MemType_RAM:
                  case MM_MemType_EEPROM:
                    Status =
                        MM_LoadMemFromFile(FileHandle, FileName, &MMFileHeader, DestAddress);
                    break;

                  case MM_MemType_MEM32:
                    Status =
                        MM_LoadMem32FromFile(FileHandle, FileName, &MMFileHeader, DestAddress);
                    break;

                  case MM_MemType_MEM16:
                    Status =
                        MM_LoadMem16FromFile(FileHandle, FileName, &MMFileHeader, DestAddress);
                    break;

                  case MM_MemType_MEM8:
                    Status =
                        MM_LoadMem8FromFile(FileHandle, FileName, &MMFileHeader, DestAddress);
                    break;

                  /*
                  ** We don't need a default case, a bad MemType will get caught
                  ** in the MM_VerifyFileLoadParams function and we won't get here
                  */
                  default:
                    Status = OS_ERROR;
                    break;
                }

                if (Status == OS_SUCCESS) {
                  MM_AppData.HkTlm.Payload.CommandCounter++;
                  CFE_EVS_SendEvent(MM_LD_MEM_FILE_INF_EID, CFE_EVS_EventType_INFORMATION,
                                    "Load Memory From File Command: Loaded %d bytes to "
                                    "address %p from file '%s'",
                                    MM_AppData.HkTlm.Payload.BytesProcessed, DestAddress,
                                    FileName);
                } else {
                  MM_AppData.HkTlm.Payload.CommandErrorCounter++;
                }
              } /* end MM_VerifyFileLoadParams if */
              else {
                MM_AppData.HkTlm.Payload.CommandErrorCounter++;
                CFE_EVS_SendEvent(MM_FILE_LOAD_PARAMS_ERR_EID, CFE_EVS_EventType_ERROR,
                                  "Load file failed parameters check: File = '%s'", FileName);
              }
            } /* end MM_ResolveSymAddr if */
            else {
              MM_AppData.HkTlm.Payload.CommandErrorCounter++;
              CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Symbolic address can't be resolved: Name = '%s'",
                                MMFileHeader.SymAddress.SymName);
            }

          } /* end ComputedCRC == MMFileHeader.Crc if */
          else {
            MM_AppData.HkTlm.Payload.CommandErrorCounter++;
            CFE_EVS_SendEvent(MM_LOAD_FILE_CRC_ERR_EID, CFE_EVS_EventType_ERROR,
                              "Load file CRC failure: Expected = 0x%X "
                              "Calculated = 0x%X File = '%s'",
                              MMFileHeader.Crc, ComputedCRC, FileName);
          }

        } /* end MM_ComputeCRCFromFile if */
        else {
          MM_AppData.HkTlm.Payload.CommandErrorCounter++;
          CFE_EVS_SendEvent(MM_COMPUTECRCFROMFILE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "MM_ComputeCRCFromFile error received: RC = 0x%08X File = '%s'",
                            Status, FileName);
        }
      } else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      } /* end MM_VerifyLoadFileSize */
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    } /* end MM_ReadFileHeaders if */

    /* Close the load file for all cases after the open call succeeds */
    Status = OS_close(FileHandle);
    if (Status != OS_SUCCESS) {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      CFE_EVS_SendEvent(MM_OS_CLOSE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_close error received: RC = 0x%08X File = '%s'", Status, FileName);
    }

  } /* end OS_OpenCreate if */
  else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    // AND THIS ONE PRINTS THE RAW MESSAGE FIELD, not the NUL-terminated local copy -- the only
    // event in the file that does. NASA's own inconsistency, kept.
    CFE_EVS_SendEvent(MM_OS_OPEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "OS_OpenCreate error received: RC = %d File = '%s'", Status,
                      Msg->Payload.FileName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Fill memory command.
//
// SEE THE SECOND UPSTREAM DEFECT AT THE TOP OF THIS FILE. The `else` on the status check moves
// the SUCCESS counter, so a width fill that failed -- which an unaligned length guarantees --
// is counted as a command that worked, with no event at all.
//
// AND THE SUCCESS PATH CHECKS LastAction RATHER THAN THE STATUS, which is how it detects that
// MM_FillMem (the generic one, which returns void) did its job: the only evidence a void
// function ran is the housekeeping it wrote.
I32 MM_FillMemCmd(MM_FillMemCmd_t *Msg)
{
  U64 DestAddress = 0;
  I32 Status = CFE_SUCCESS;
  // NASA WRITES THIS AS A DECLARATION INITIALISER -- `MM_SymAddr_t DestSymAddress =
  // Msg->Payload.DestSymAddress;` -- and in THIS compiler that form copies only the FIRST EIGHT
  // BYTES, silently, where the same copy as a separate assignment statement is whole.
  // docs/HOLYC_STRUCT_LIMITS.md #27, measured by tests/exec/cases/e_class_decl_init.hc.
  //
  // IT COST A TRANSCRIPT DIVERGENCE TO FIND. The Offset survived (it is the first eight bytes)
  // and SymName did not, so MM_ResolveSymAddr saw a NON-EMPTY name in uninitialised stack,
  // took the symbol-lookup branch instead of the offset branch, and the fill went to
  // md_sym_addr + Offset. The command was set up correctly and the address was wrong.
  //
  // The other four handlers in this file declare and then assign, which is why only this one
  // broke. Split here to match them; tools/cfs/check_struct_copy.py now refuses the form
  // outright so the next one cannot be silent.
  MM_SymAddr_t DestSymAddress;

  DestSymAddress = Msg->Payload.DestSymAddress;

  /* Resolve symbolic address */
  if (MM_ResolveSymAddr(&DestSymAddress, &DestAddress) == OS_SUCCESS) {
    /* Run necessary checks on command parameters */
    if (MM_VerifyLoadDumpParams(DestAddress, Msg->Payload.MemType, Msg->Payload.NumOfBytes,
                                MM_VERIFY_FILL) == CFE_SUCCESS) {
      switch (Msg->Payload.MemType) {
        case MM_MemType_RAM:
        case MM_MemType_EEPROM:
          MM_FillMem(DestAddress, Msg);
          break;

        case MM_MemType_MEM32:
          Status = MM_FillMem32(DestAddress, Msg);
          break;

        case MM_MemType_MEM16:
          Status = MM_FillMem16(DestAddress, Msg);
          break;

        case MM_MemType_MEM8:
          Status = MM_FillMem8(DestAddress, Msg);
          break;

          /*
          ** We don't need a default case, a bad MemType will get caught
          ** in the MM_VerifyLoadDumpParams function and we won't get here
          */
        default:
          Status = CFE_PSP_ERROR;
          break;
      }

      if (Status == CFE_PSP_SUCCESS) {
        if (MM_AppData.HkTlm.Payload.LastAction == MM_LastAction_FILL) {
          MM_AppData.HkTlm.Payload.CommandCounter++;
          CFE_EVS_SendEvent(MM_FILL_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "Fill Memory Command: Filled %d bytes at address: "
                            "%p with pattern: 0x%08X",
                            MM_AppData.HkTlm.Payload.BytesProcessed, DestAddress,
                            MM_AppData.HkTlm.Payload.DataValue);
        } else {
          MM_AppData.HkTlm.Payload.CommandErrorCounter++;
        }
      } else {
        // THE DEFECT. NASA's own line, verbatim: the SUCCESS counter on a failed fill.
        MM_AppData.HkTlm.Payload.CommandCounter++;
      }
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    }
  } else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Symbolic address can't be resolved: Name = '%s'", DestSymAddress.SymName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Memory peek command.
//
// ONE ROUTINE FOR EVERY MEMORY TYPE, unlike the poke -- a read needs no EEPROM programming
// cycle, so MM_PeekMem's three PSP widths cover all five types.
//
// AND ITS SYMBOL-ERROR EVENT PRINTS THE MESSAGE'S OWN FIELD where the poke's prints the local
// copy. The copy is the one MM_ResolveSymAddr NUL-terminated, so the two can differ when the
// ground sends 64 non-NUL bytes. NASA's inconsistency, kept.
I32 MM_PeekCmd(MM_PeekCmd_t *Msg)
{
  U64 SrcAddress = 0;
  MM_SymAddr_t SrcSymAddress;
  I32 Status = OS_SUCCESS;

  SrcSymAddress = Msg->Payload.SrcSymAddress;

  /* Resolve the symbolic address in command message */
  Status = MM_ResolveSymAddr(&SrcSymAddress, &SrcAddress);

  if (Status == OS_SUCCESS) {
    /* Run necessary checks on command parameters */
    Status = MM_VerifyPeekPokeParams(SrcAddress, Msg->Payload.MemType, Msg->Payload.DataSize);

    /* Check the specified memory type and call the appropriate routine */
    if (Status == OS_SUCCESS) {
      /*
      ** We use this single peek routine for all memory types
      ** (including the optional ones)
      */
      Status = MM_PeekMem(Msg, SrcAddress);
      if (Status == CFE_PSP_SUCCESS) {
        MM_AppData.HkTlm.Payload.CommandCounter++;
      } else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      }
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    }
  } /* end MM_ResolveSymAddr if */
  else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Symbolic address can't be resolved: Name = '%s'",
                      Msg->Payload.SrcSymAddress.SymName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Dump memory to file command.
//
// THE HEADERS ARE WRITTEN TWICE, and that is the shape of the whole function: MM cannot know the
// dump's CRC until the data is on disk, so it writes a header with Crc = 0, writes the data,
// SEEKS BACK past both headers, computes the CRC over what it just wrote, and writes the headers
// again. The second write is what makes the file loadable.
I32 MM_DumpMemToFileCmd(MM_DumpMemToFileCmd_t *Msg)
{
  I32 Status;
  U32 FileHandle = OS_OBJECT_ID_UNDEFINED;
  U64 SrcAddress = 0;
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
  MM_SymAddr_t SrcSymAddress;
  CFE_FS_Header_t CFEFileHeader;
  MM_LoadDumpFileHeader_t MMFileHeader;

  SrcSymAddress = Msg->Payload.SrcSymAddress;

  /* Make sure strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(FileName, Msg->Payload.FileName, NULL, CFE_MISSION_MAX_PATH_LEN,
                          CFE_MISSION_MAX_PATH_LEN);

  /* Resolve the symbolic address in command message */
  Status = MM_ResolveSymAddr(&SrcSymAddress, &SrcAddress);

  if (Status == OS_SUCCESS) {
    /* Run necessary checks on command parameters */
    Status = MM_VerifyLoadDumpParams(SrcAddress, Msg->Payload.MemType, Msg->Payload.NumOfBytes,
                                     MM_VERIFY_DUMP);

    if (Status == OS_SUCCESS) {
      /*
      ** Initialize the cFE primary file header structure
      */
      CFE_FS_InitHeader(&CFEFileHeader, MM_INTERNAL_CFE_HDR_DESCRIPTION,
                        MM_INTERNAL_CFE_HDR_SUBTYPE);

      /*
      ** Initialize the MM secondary file header structure
      */
      MemSet(&MMFileHeader, 0, sizeof(MM_LoadDumpFileHeader_t));
      MMFileHeader.SymAddress.SymName[0] = MM_INTERNAL_CLEAR_SYMNAME;

      /*
      ** Copy command data to file secondary header
      */
      MMFileHeader.SymAddress.Offset = SrcAddress;
      MMFileHeader.MemType = Msg->Payload.MemType;
      MMFileHeader.NumOfBytes = Msg->Payload.NumOfBytes;

      /*
      ** Create and open dump file
      */
      Status = OS_OpenCreate(&FileHandle, FileName,
                             OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_READ_WRITE);
      if (Status == OS_SUCCESS) {
        /* Write the file headers */
        Status = MM_WriteFileHeaders(FileName, FileHandle, &CFEFileHeader, &MMFileHeader);
        if (Status == OS_SUCCESS) {
          switch (MMFileHeader.MemType) {
            case MM_MemType_RAM:
            case MM_MemType_EEPROM:
              Status = MM_DumpMemToFile(FileHandle, FileName, &MMFileHeader);
              break;

            case MM_MemType_MEM32:
              Status = MM_DumpMem32ToFile(FileHandle, FileName, &MMFileHeader);
              break;

            case MM_MemType_MEM16:
              Status = MM_DumpMem16ToFile(FileHandle, FileName, &MMFileHeader);
              break;

            case MM_MemType_MEM8:
              Status = MM_DumpMem8ToFile(FileHandle, FileName, &MMFileHeader);
              break;
            default:
              /* This branch will never be executed. MMFileHeader.MemType will
               * always be valid value for this switch statement it is verified
               * via MM_VerifyFileLoadDumpParams */
              Status = CFE_PSP_ERROR;
              break;
          }

          if (Status == CFE_PSP_SUCCESS) {
            /*
            ** Compute CRC of dumped data
            */
            Status = OS_lseek(FileHandle,
                              sizeof(CFE_FS_Header_t) + sizeof(MM_LoadDumpFileHeader_t),
                              OS_SEEK_SET);
            if (Status != sizeof(CFE_FS_Header_t) + sizeof(MM_LoadDumpFileHeader_t)) {
              MM_AppData.HkTlm.Payload.CommandErrorCounter++;
            } else {
              Status = MM_ComputeCRCFromFile(FileHandle, &MMFileHeader.Crc,
                                             MM_INTERNAL_DUMP_FILE_CRC_TYPE);
              if (Status == OS_SUCCESS) {
                /*
                ** Rewrite the file headers. The subfunctions will take care of
                *moving
                ** the file pointer to the beginning of the file so we don't
                *need to do it
                ** here.
                */
                Status = MM_WriteFileHeaders(FileName, FileHandle, &CFEFileHeader,
                                             &MMFileHeader);
                if (Status == OS_SUCCESS) {
                  /*
                  ** Update last action statistics
                  */
                  MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_DUMP_TO_FILE;
                  MM_AppData.HkTlm.Payload.MemType = Msg->Payload.MemType;
                  MM_AppData.HkTlm.Payload.Address = SrcAddress;
                  MM_AppData.HkTlm.Payload.BytesProcessed = Msg->Payload.NumOfBytes;
                  StrPrintN(MM_AppData.HkTlm.Payload.FileName, CFE_MISSION_MAX_PATH_LEN, "%s",
                            FileName);

                  MM_AppData.HkTlm.Payload.CommandCounter++;
                  CFE_EVS_SendEvent(MM_DMP_MEM_FILE_INF_EID, CFE_EVS_EventType_INFORMATION,
                                    "Dump Memory To File Command: Dumped %d bytes from "
                                    "address %p to file '%s'",
                                    MM_AppData.HkTlm.Payload.BytesProcessed, SrcAddress,
                                    FileName);
                } else {
                  MM_AppData.HkTlm.Payload.CommandErrorCounter++;
                }

              } /* end MM_ComputeCRCFromFile if */
              else {
                MM_AppData.HkTlm.Payload.CommandErrorCounter++;
                CFE_EVS_SendEvent(MM_COMPUTECRCFROMFILE_ERR_EID, CFE_EVS_EventType_ERROR,
                                  "MM_ComputeCRCFromFile error received: RC = "
                                  "0x%08X File = '%s'",
                                  Status, FileName);
              }
            }
          } else {
            MM_AppData.HkTlm.Payload.CommandErrorCounter++;
          }
        } else {
          MM_AppData.HkTlm.Payload.CommandErrorCounter++;
        } /* end MM_WriteFileHeaders if */

        /* Close dump file */
        Status = OS_close(FileHandle);
        if (Status != OS_SUCCESS) {
          MM_AppData.HkTlm.Payload.CommandErrorCounter++;
          CFE_EVS_SendEvent(MM_OS_CLOSE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "OS_close error received: RC = 0x%08X File = '%s'", Status,
                            FileName);
        }

      } /* end OS_OpenCreate if */
      else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
        CFE_EVS_SendEvent(MM_OS_CREAT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "OS_OpenCreate error received: RC = %d File = '%s'", Status,
                          FileName);
      }
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    } /* end MM_VerifyFileLoadDumpParams if */
  } /* end MM_ResolveSymAddr if */
  else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Symbolic address can't be resolved: Name = '%s'", SrcSymAddress.SymName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Dump memory in event message command.
//
// THE EVENT TEXT IS BUILT BY CONCATENATION, five characters per byte, and the bound is
// CFE_MISSION_EVS_MAX_MESSAGE_LENGTH -- which is where MM_INTERNAL_MAX_DUMP_INEVENT_BYTES comes
// from: (122 - (13 + 33)) / 5 = 15. The 13 is the header "Memory Dump: " and the 33 is the
// worst-case tail "from address: %p". So this one command's maximum is derived from how wide an
// event message is, which is why the constant looks arbitrary and is not.
//
// EVERY APPEND GOES THROUGH CFE_SB_MessageStringGet, not strcat: it takes the remaining space
// and cannot overrun. NASA's "SAD" comments say that is why the snprintf returns are unchecked.
I32 MM_DumpInEventCmd(MM_DumpInEventCmd_t *Msg)
{
  U32 i;
  I32 EventStringTotalLength = 0;
  U64 SrcAddress = 0;
  U8 *BytePtr;
  U8 TempString[MM_INTERNAL_DUMPINEVENT_TEMP_CHARS];
  // NASA: `const char HeaderString[] = "Memory Dump: ";` and then `sizeof(HeaderString)` as the
  // source size -- FOURTEEN, the thirteen characters and the NUL. A HolyC pointer's sizeof is 8,
  // so the number is written out; getting it wrong truncates the header to seven characters.
  U8 *HeaderString = "Memory Dump: ";
  MM_SymAddr_t SrcSymAddress;
  I32 Status;

  /*
  ** Allocate a dump buffer. It's declared this way to ensure it stays
  ** longword aligned since MM_INTERNAL_MAX_DUMP_INEVENT_BYTES can be adjusted
  ** by changing the maximum event message string size.
  */
  U32 DumpBuffer[(MM_INTERNAL_MAX_DUMP_INEVENT_BYTES + 3) / 4];

  SrcSymAddress = Msg->Payload.SrcSymAddress;

  /* Resolve the symbolic source address in the command message */
  Status = MM_ResolveSymAddr(&SrcSymAddress, &SrcAddress);

  if (Status == OS_SUCCESS) {
    /* Run necessary checks on command parameters */
    Status = MM_VerifyLoadDumpParams(SrcAddress, Msg->Payload.MemType, Msg->Payload.NumOfBytes,
                                     MM_VERIFY_EVENT);

    if (Status == CFE_PSP_SUCCESS) {
      /* Fill a local data buffer with the dump words */
      Status = MM_FillDumpInEventBuffer(SrcAddress, Msg, DumpBuffer(U8 *));

      if (Status == CFE_PSP_SUCCESS) {
        /*
        ** Prepare event message string header
        ** 13 characters, not counting NUL terminator
        */
        CFE_SB_MessageStringGet(&MM_DumpInEventCmd_EventString[EventStringTotalLength],
                                HeaderString, NULL,
                                CFE_MISSION_EVS_MAX_MESSAGE_LENGTH - EventStringTotalLength, 14);
        EventStringTotalLength = OS_strnlen(MM_DumpInEventCmd_EventString,
                                            CFE_MISSION_EVS_MAX_MESSAGE_LENGTH);

        /*
        ** Build dump data string
        ** Each byte of data requires 5 characters of string space
        ** Note this really only allows up to ~15 bytes using default config
        */
        BytePtr = DumpBuffer(U8 *);
        for (i = 0; i < Msg->Payload.NumOfBytes; i++) {
          /* SAD: No need to check snprintf return; CFE_SB_MessageStringGet()
           * handles safe concatenation and prevents overflow */
          StrPrintN(TempString, MM_INTERNAL_DUMPINEVENT_TEMP_CHARS, "0x%02X ", *BytePtr);
          CFE_SB_MessageStringGet(&MM_DumpInEventCmd_EventString[EventStringTotalLength],
                                  TempString, NULL,
                                  CFE_MISSION_EVS_MAX_MESSAGE_LENGTH - EventStringTotalLength,
                                  MM_INTERNAL_DUMPINEVENT_TEMP_CHARS);
          EventStringTotalLength = OS_strnlen(MM_DumpInEventCmd_EventString,
                                              CFE_MISSION_EVS_MAX_MESSAGE_LENGTH);
          BytePtr++;
        }

        /*
        ** Append tail
        ** This adds up to 33 characters depending on pointer representation
        *including the NUL terminator
        */
        /* SAD: No need to check snprintf return; CFE_SB_MessageStringGet()
         * handles safe concatenation and prevents overflow */
        StrPrintN(TempString, MM_INTERNAL_DUMPINEVENT_TEMP_CHARS, "from address: %p",
                  SrcAddress);
        CFE_SB_MessageStringGet(&MM_DumpInEventCmd_EventString[EventStringTotalLength],
                                TempString, NULL,
                                CFE_MISSION_EVS_MAX_MESSAGE_LENGTH - EventStringTotalLength,
                                MM_INTERNAL_DUMPINEVENT_TEMP_CHARS);

        /* Send it out */
        CFE_EVS_SendEvent(MM_DUMP_INEVENT_INF_EID, CFE_EVS_EventType_INFORMATION, "%s",
                          MM_DumpInEventCmd_EventString);

        /* Update telemetry */
        MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_DUMP_INEVENT;
        MM_AppData.HkTlm.Payload.MemType = Msg->Payload.MemType;
        MM_AppData.HkTlm.Payload.Address = SrcAddress;
        MM_AppData.HkTlm.Payload.BytesProcessed = Msg->Payload.NumOfBytes;
        MM_AppData.HkTlm.Payload.CommandCounter++;
      } else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
      } /* end MM_FillDumpInEventBuffer if */
    } else {
      MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    } /* end MM_VerifyFileLoadDumpParams if */
  } /* end MM_ResolveSymAddr if */
  else {
    MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    CFE_EVS_SendEvent(MM_SYMNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Symbolic address can't be resolved: Name = '%s'", SrcSymAddress.SymName);
  }

  /* Nothing atypical needs to be done so return success */
  return CFE_SUCCESS;
}
#endif
