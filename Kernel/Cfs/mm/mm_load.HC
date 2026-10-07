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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_load.c -- the six ways MM gets data INTO
// memory: a poke to RAM, a poke to EEPROM, a region from a file, the two checks that file
// passes first, and a fill.
//
// EEPROM IS A SEPARATE WRITE PATH AND THAT IS THE NEWS IN THIS FILE. A poke to RAM goes through
// CFE_PSP_MemWrite*; a poke to EEPROM goes through CFE_PSP_EepromWrite*, which on real hardware
// unlocks the part, issues a programming cycle and waits -- so MM wraps the EEPROM paths in
// performance-log stamps that the RAM ones do not have. The driver supplies a SECOND simulated
// region for it, separate from the RAM window, because the two are separate devices.
//
// THE GENERIC PATHS DEREFERENCE DIRECTLY, as mm_dump.c's do: MM_LoadMemFromFile and MM_FillMem
// `memcpy` to the address. See the note at the top of mm_dump.HC for what that costs.
//
// ------------------------------------------------------------------------------------------
// MM_FillMem HAS AN UPSTREAM DEFECT AND IT IS TRANSLATED VERBATIM. NASA builds its scratch
// segment with
//
//     uint8 *FillBuffer = (uint8 *)&MM_AppData.FillBuffer[0];
//     for (i = 0; i < (MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(uint32)); i++)
//         FillBuffer[i] = CmdPtr->Payload.FillPattern;
//
// FillBuffer is a BYTE pointer, so `FillBuffer[i]` writes ONE byte -- but the loop runs
// 200/4 = 50 times. So a 200-byte fill segment gets the pattern's low byte in its first FIFTY
// bytes and KEEPS WHATEVER WAS IN MM_AppData.FillBuffer in the other 150. The intent was
// plainly `((uint32 *)FillBuffer)[i] = FillPattern` -- 50 words, 200 bytes, pattern throughout.
//
// This is NASA's code and the translation's job is to be NASA's code, so it is kept exactly,
// and the exercise PRINTS the boundary: bytes 0 and 49 carry the pattern, bytes 50 and 199 do
// not. A translator who "fixed" it would produce a port that behaves differently from the
// flight software it claims to be, which is the one failure this project cannot afford.
// docs/CFS_PLAN.md records it as an upstream finding rather than a port decision.
// ------------------------------------------------------------------------------------------
#ifndef MM_LOAD_HC
#define MM_LOAD_HC

// --- cfe_psp.h -------------------------------------------------------------------------------
// The EEPROM writers. The driver supplies them over a second simulated region.
I32 CFE_PSP_EepromWrite8(U64 MemoryAddress, U8 ByteValue);
I32 CFE_PSP_EepromWrite16(U64 MemoryAddress, U16 uint16Value);
I32 CFE_PSP_EepromWrite32(U64 MemoryAddress, U32 uint32Value);

// --- what this file needs from elsewhere -----------------------------------------------------
I32 CFE_FS_ReadHeader(CFE_FS_Header_t *Hdr, U32 FileDes);
I32 OS_stat(U8 *path, os_fstat_t *filestats);

/*******************************************************************************/
// Write 8, 16, or 32 bits of data to any RAM memory address.
//
// THE MIRROR OF MM_PeekMem: same three-arm switch, same NOT_IMPLEMENTED initial status, same
// per-width event id.
//
// THE DIFFERENCE BETWEEN THEM IS SYNTACTIC AND NOT BEHAVIOURAL, and the first version of this
// comment claimed otherwise. It said BytesProcessed and DataSize are set before the write here
// where "the peek sets them only on success" -- measured, the peek sets DataSize unconditionally
// too, and BytesProcessed is a LOCAL that only reaches housekeeping on success in both, so
// neither placement is observable. A mutation written to catch the difference was a no-op by
// construction, which is how the claim was found. The real per-arm assertions are the byte
// counts the exercise now captures after each poke, and `MemType=MEM0` in the error event when
// no arm set DataSize at all.
I32 MM_PokeMem(MM_PokeCmd_t *CmdPtr, U64 DestAddress)
{
  U8 ByteValue;
  U16 WordValue;
  I32 PSP_Status = CFE_PSP_ERROR_NOT_IMPLEMENTED;
  U32 DataValue = 0;
  I64 BytesProcessed = 0;
  I64 DataSize = 0; /* only used for giving MEM type/size in events */
  U32 EventID = 0;

  /* Write input number of bits to destination address */
  switch (CmdPtr->Payload.DataSize) {
    case MM_INTERNAL_BYTE_BIT_WIDTH:
      ByteValue = CmdPtr->Payload.Data;
      DataValue = ByteValue;
      BytesProcessed = sizeof(U8);
      DataSize = 8;
      // NASA writes the call inside the `if`. HolyC's assignment is a statement, so it is
      // hoisted -- same single evaluation, same order.
      PSP_Status = CFE_PSP_MemWrite8(DestAddress, ByteValue);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        EventID = MM_POKE_BYTE_INF_EID;
      }
      break;

    case MM_INTERNAL_WORD_BIT_WIDTH:
      WordValue = CmdPtr->Payload.Data;
      DataValue = WordValue;
      BytesProcessed = sizeof(U16);
      DataSize = 16;
      PSP_Status = CFE_PSP_MemWrite16(DestAddress, WordValue);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        EventID = MM_POKE_WORD_INF_EID;
      }
      break;

    case MM_INTERNAL_DWORD_BIT_WIDTH:
      DataValue = CmdPtr->Payload.Data;
      BytesProcessed = sizeof(U32);
      DataSize = 32;
      PSP_Status = CFE_PSP_MemWrite32(DestAddress, DataValue);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        EventID = MM_POKE_DWORD_INF_EID;
      }
      break;

    /*
    ** We don't need a default case, a bad DataSize will get caught
    ** in the MM_VerifyPeekPokeParams function and we won't get here
    */
    default:
      break;
  }

  if (PSP_Status == CFE_PSP_SUCCESS) {
    /* Update cmd counter and last action stats */
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_POKE;
    MM_AppData.HkTlm.Payload.MemType = CmdPtr->Payload.MemType;
    MM_AppData.HkTlm.Payload.Address = DestAddress;
    MM_AppData.HkTlm.Payload.DataValue = DataValue;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;

    CFE_EVS_SendEvent(EventID, CFE_EVS_EventType_INFORMATION,
                      "Poke Command: Addr = %p, Size = %u bits, Data = 0x%08X", DestAddress,
                      DataSize, DataValue);
  } else {
    CFE_EVS_SendEvent(MM_PSP_WRITE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "PSP write memory error: RC=0x%08X, Address=%p, MemType=MEM%u", PSP_Status,
                      DestAddress, DataSize);
  }

  return PSP_Status;
}

/*******************************************************************************/
// Write 8, 16, or 32 bits of data to any EEPROM memory address.
//
// THREE DIFFERENCES FROM MM_PokeMem, all of them because EEPROM is a different device:
//   1. PERFORMANCE-LOG STAMPS around the whole function. An EEPROM programming cycle takes
//      milliseconds, which is the only write in MM worth timing.
//   2. EACH ARM SENDS ITS OWN EVENT, success or failure, rather than one pair at the end -- so
//      the error id is per width (MM_OS_EEPROMWRITE8/16/32_ERR_EID) where RAM has one.
//   3. THE SUCCESS EVENT PRINTS THE DATA AT THE COMMANDED WIDTH: 0x%02X, 0x%04X, 0x%08X. RAM
//      always prints 0x%08X. So a one-byte EEPROM poke of 0xDD reads `Data = 0xDD` here and
//      `Data = 0x000000DD` from the RAM path.
I32 MM_PokeEeprom(MM_PokeCmd_t *CmdPtr, U64 DestAddress)
{
  U8 ByteValue;
  U16 WordValue;
  I32 PSP_Status = CFE_PSP_ERROR_NOT_IMPLEMENTED;
  U32 DataValue = 0;
  I64 BytesProcessed = 0;

  CFE_ES_PerfLogEntry(MM_EEPROM_POKE_PERF_ID);

  /* Write input number of bits to destination address */
  switch (CmdPtr->Payload.DataSize) {
    case MM_INTERNAL_BYTE_BIT_WIDTH:
      ByteValue = CmdPtr->Payload.Data;
      DataValue = ByteValue;
      BytesProcessed = sizeof(U8);
      PSP_Status = CFE_PSP_EepromWrite8(DestAddress, ByteValue);
      if (PSP_Status != CFE_PSP_SUCCESS) {
        CFE_EVS_SendEvent(MM_OS_EEPROMWRITE8_ERR_EID, CFE_EVS_EventType_ERROR,
                          "CFE_PSP_EepromWrite8 error received: RC = 0x%08X, Addr = %p",
                          PSP_Status, DestAddress);
      } else {
        CFE_EVS_SendEvent(MM_POKE_BYTE_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Poke Command: Addr = %p, Size = 8 bits, Data = 0x%02X", DestAddress,
                          ByteValue);
      }
      break;

    case MM_INTERNAL_WORD_BIT_WIDTH:
      WordValue = CmdPtr->Payload.Data;
      DataValue = WordValue;
      BytesProcessed = sizeof(U16);
      PSP_Status = CFE_PSP_EepromWrite16(DestAddress, WordValue);
      if (PSP_Status != CFE_PSP_SUCCESS) {
        CFE_EVS_SendEvent(MM_OS_EEPROMWRITE16_ERR_EID, CFE_EVS_EventType_ERROR,
                          "CFE_PSP_EepromWrite16 error received: RC = 0x%08X, Addr = %p",
                          PSP_Status, DestAddress);
      } else {
        CFE_EVS_SendEvent(MM_POKE_WORD_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Poke Command: Addr = %p, Size = 16 bits, Data = 0x%04X", DestAddress,
                          WordValue);
      }
      break;

    case MM_INTERNAL_DWORD_BIT_WIDTH:
      DataValue = CmdPtr->Payload.Data;
      BytesProcessed = sizeof(U32);
      PSP_Status = CFE_PSP_EepromWrite32(DestAddress, CmdPtr->Payload.Data);
      if (PSP_Status != CFE_PSP_SUCCESS) {
        CFE_EVS_SendEvent(MM_OS_EEPROMWRITE32_ERR_EID, CFE_EVS_EventType_ERROR,
                          "CFE_PSP_EepromWrite32 error received: RC = 0x%08X, Addr = %p",
                          PSP_Status, DestAddress);
      } else {
        CFE_EVS_SendEvent(MM_POKE_DWORD_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Poke Command: Addr = %p, Size = 32 bits, Data = 0x%08X", DestAddress,
                          CmdPtr->Payload.Data);
      }
      break;

    /*
    ** We don't need a default case, a bad DataSize will get caught
    ** in the MM_VerifyPeekPokeParams function and we won't get here
    */
    default:
      break;
  }

  if (PSP_Status == CFE_PSP_SUCCESS) {
    /* Update cmd counter and last action stats */
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_POKE;
    MM_AppData.HkTlm.Payload.MemType = CmdPtr->Payload.MemType;
    MM_AppData.HkTlm.Payload.Address = DestAddress;
    MM_AppData.HkTlm.Payload.DataValue = DataValue;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
  }

  CFE_ES_PerfLogExit(MM_EEPROM_POKE_PERF_ID);

  return PSP_Status;
}

/*******************************************************************************/
// Loads memory from a file.
//
// THE PERFORMANCE STAMPS ARE CONDITIONAL ON THE MEMORY TYPE, which is the one place in MM where
// a log marker is taken only sometimes -- an EEPROM load is slow and a RAM load is not. So the
// SAME function produces two entries or none depending on a field in the file's own header.
I32 MM_LoadMemFromFile(U32 FileHandle, U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader,
                       U64 DestAddress)
{
  I32 BytesRemaining = FileHeader->NumOfBytes;
  I64 BytesProcessed = 0;
  I64 SegmentSize = MM_INTERNAL_MAX_LOAD_DATA_SEG;
  U8 *ioBuffer = (&MM_AppData.LoadBuffer[0])(U8 *);
  U8 *TargetPointer = DestAddress(U8 *);
  I32 Status = OS_SUCCESS;
  I32 ReadLength;

  if (FileHeader->MemType == MM_MemType_EEPROM) {
    CFE_ES_PerfLogEntry(MM_EEPROM_FILELOAD_PERF_ID);
  }

  while (BytesRemaining != 0) {
    if (BytesRemaining < MM_INTERNAL_MAX_LOAD_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    ReadLength = OS_read(FileHandle, ioBuffer, SegmentSize);
    if (ReadLength == SegmentSize) {
      MemCpy(TargetPointer, ioBuffer, SegmentSize);

      BytesRemaining -= SegmentSize;
      BytesProcessed += SegmentSize;
      TargetPointer += SegmentSize;

      /* Prevent CPU hogging between load segments */
      if (BytesRemaining != 0) {
        MM_SegmentBreak();
      }
    } else {
      BytesRemaining = 0;
      Status = OS_ERROR;
      CFE_EVS_SendEvent(MM_OS_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_read error received: RC = 0x%08X Expected = %u File = '%s'",
                        ReadLength, SegmentSize, FileName);
    }
  }

  if (FileHeader->MemType == MM_MemType_EEPROM) {
    CFE_ES_PerfLogExit(MM_EEPROM_FILELOAD_PERF_ID);
  }

  /* Update last action statistics */
  if (BytesProcessed == FileHeader->NumOfBytes) {
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_LOAD_FROM_FILE;
    MM_AppData.HkTlm.Payload.MemType = FileHeader->MemType;
    MM_AppData.HkTlm.Payload.Address = DestAddress;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
    StrNCpy(MM_AppData.HkTlm.Payload.FileName, FileName, CFE_MISSION_MAX_PATH_LEN);
  } else {
    Status = OS_ERROR;
  }

  return Status;
}

/*******************************************************************************/
// Verify load file size.
//
// THE EXPECTED SIZE IS THE HEADER'S CLAIM PLUS BOTH HEADERS, so this is the check that catches a
// file whose header says one thing and whose length says another -- a truncated upload.
I32 MM_VerifyLoadFileSize(U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader)
{
  I32 OS_Status;
  I64 ExpectedSize;
  I32 ActualSize; /* The size returned by OS_stat is signed */
  os_fstat_t FileStats;

  MemSet(&FileStats, 0, sizeof(os_fstat_t));

  /*
  ** Get the filesystem statistics on our load file
  */
  OS_Status = OS_stat(FileName, &FileStats);
  if (OS_Status != OS_SUCCESS) {
    CFE_EVS_SendEvent(MM_OS_STAT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "OS_stat error received: RC = 0x%08X File = '%s'", OS_Status, FileName);
  } else {
    /*
    ** Check the reported size of the file against what it should be based
    ** upon the number of load bytes specified in the file header
    */
    // OS_FILESTAT_SIZE(x) is `((x).FileSize)` -- an OSAL accessor macro, written out.
    ActualSize = FileStats.FileSize;
    ExpectedSize =
        FileHeader->NumOfBytes + sizeof(CFE_FS_Header_t) + sizeof(MM_LoadDumpFileHeader_t);
    if (ActualSize != ExpectedSize) {
      OS_Status = OS_ERR_INVALID_SIZE;

      /*
      ** Note: passing FileStats.st_size in this event message will cause
      ** a segmentation fault under cygwin during unit testing, so we added
      ** the variable ActualSize to this function.
      */
      CFE_EVS_SendEvent(MM_LD_FILE_SIZE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Load file size error: Reported by OS = %d Expected = %u File = '%s'",
                        ActualSize, ExpectedSize, FileName);
    }
  }

  return OS_Status;
}

/*******************************************************************************/
// Read the cFE primary and MM secondary file headers.
//
// THE MIRROR OF MM_WriteFileHeaders, with one difference worth noting: this one sends the event
// BEFORE replacing the status, so the ground sees what CFE_FS_ReadHeader actually returned. The
// writer replaces it first and reports -40. Same two arms, opposite order.
I32 MM_ReadFileHeaders(U8 *FileName, U32 FileHandle, CFE_FS_Header_t *CFEHeader,
                       MM_LoadDumpFileHeader_t *MMHeader)
{
  I32 OS_Status;

  /*
  ** Read in the primary cFE file header
  */
  OS_Status = CFE_FS_ReadHeader(CFEHeader, FileHandle);
  if (OS_Status != sizeof(CFE_FS_Header_t)) {
    /* We either got an error or didn't read as much data as expected */
    CFE_EVS_SendEvent(MM_CFE_FS_READHDR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "CFE_FS_ReadHeader error received: RC = 0x%08X Expected "
                      "= %u File = '%s'",
                      OS_Status, sizeof(CFE_FS_Header_t), FileName);

    OS_Status = OS_ERR_INVALID_SIZE;
  } /* end CFE_FS_ReadHeader if */
  else {
    /*
    ** Read in the secondary MM file header
    */
    OS_Status = OS_read(FileHandle, MMHeader, sizeof(MM_LoadDumpFileHeader_t));
    if (OS_Status != sizeof(MM_LoadDumpFileHeader_t)) {
      /* We either got an error or didn't read as much data as expected */
      CFE_EVS_SendEvent(MM_OS_READ_EXP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_read error received: RC = 0x%08X Expected = %u File = '%s'",
                        OS_Status, sizeof(MM_LoadDumpFileHeader_t), FileName);

      OS_Status = OS_ERR_INVALID_SIZE;
    } else {
      OS_Status = OS_SUCCESS;
    } /* end OS_read if */
  } /* end CFE_FS_ReadHeader else */

  return OS_Status;
}

/*******************************************************************************/
// Fill memory with the command specified fill pattern.
//
// SEE THE UPSTREAM DEFECT AT THE TOP OF THIS FILE. The scratch-segment loop below runs
// MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(uint32) = 50 times through a BYTE pointer, so it fills
// 50 of the 200 bytes and leaves the other 150 holding whatever MM_AppData.FillBuffer held
// before. Kept exactly as NASA wrote it; the exercise prints the boundary.
//
// AND THIS IS THE ONE FUNCTION IN MM THAT RETURNS NOTHING AND CANNOT FAIL. There is no status,
// no error event and no guard on the housekeeping update -- a fill of a bad address is a wild
// store and MM finds out when the processor does.
U0 MM_FillMem(U64 DestAddress, MM_FillMemCmd_t *CmdPtr)
{
  U16 i;
  I64 BytesProcessed = 0;
  U32 BytesRemaining = CmdPtr->Payload.NumOfBytes;
  U32 SegmentSize = MM_INTERNAL_MAX_FILL_DATA_SEG;
  U8 *TargetPointer = DestAddress(U8 *);
  U8 *FillBuffer = (&MM_AppData.FillBuffer[0])(U8 *);

  /* Create a scratch buffer with one fill segment */
  for (i = 0; i < MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(U32); i++) {
    FillBuffer[i] = CmdPtr->Payload.FillPattern;
  }

  /* Start EEPROM performance monitor */
  if (CmdPtr->Payload.MemType == MM_MemType_EEPROM) {
    CFE_ES_PerfLogEntry(MM_EEPROM_FILL_PERF_ID);
  }

  /* Fill memory one segment at a time */
  while (BytesRemaining != 0) {
    /* Last fill segment may be partial size */
    if (BytesRemaining < MM_INTERNAL_MAX_FILL_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    MemCpy(TargetPointer, FillBuffer, SegmentSize);

    TargetPointer += SegmentSize;
    BytesProcessed += SegmentSize;
    BytesRemaining -= SegmentSize;

    /* Prevent CPU hogging between load segments */
    if (BytesRemaining != 0) {
      MM_SegmentBreak();
    }
  }

  /* Stop EEPROM performance monitor */
  if (CmdPtr->Payload.MemType == MM_MemType_EEPROM) {
    CFE_ES_PerfLogExit(MM_EEPROM_FILL_PERF_ID);
  }

  /* Update last action statistics */
  MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_FILL;
  MM_AppData.HkTlm.Payload.MemType = CmdPtr->Payload.MemType;
  MM_AppData.HkTlm.Payload.Address = DestAddress;
  MM_AppData.HkTlm.Payload.DataValue = CmdPtr->Payload.FillPattern;
  MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;

  return;
}
#endif
