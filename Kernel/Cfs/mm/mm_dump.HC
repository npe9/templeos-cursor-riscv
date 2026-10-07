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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_dump.c -- the four ways MM gets memory OUT:
// a peek into an event, a region into a file, the two headers that file carries, and a small
// region into an event's text.
//
// THE GENERIC PATH DEREFERENCES THE ADDRESS DIRECTLY, and that is the structural news in this
// file. mm_mem8/16/32 reach memory only through CFE_PSP_MemRead*, which is what let the port
// put a SIMULATED WINDOW of literal addresses behind them. MM_DumpMemToFile does
// `memcpy(ioBuffer, SourcePtr, SegmentSize)` -- a real load from a real pointer -- and
// MM_FillDumpInEventBuffer's RAM and EEPROM arm does the same. A literal 0x00100000 is a wild
// pointer, not a window, so those two paths are exercised against a REAL driver-owned array.
//
// THE CONSEQUENCE IS THAT THEIR HOUSEKEEPING ADDRESS CANNOT BE PRINTED. MM_DumpMemToFile writes
// `Address = FileHeader->SymAddress.Offset`, which for those paths is wherever the linker put
// the driver's array -- a different number on each half. The exercise asserts it by COMPARISON
// instead: it prints whether the field equals the array's address, which is true on both halves
// and still fails if the field is set from the wrong place. See docs/CFS_PLAN.md.
//
// WHICH EVENTS ARE DRIVABLE, as a list, because it is not obvious:
//   MM_PeekMem's two          -- YES. Both print only `Addr = %p` of the address the GROUND
//                                supplied, and MM_PeekMem reaches memory through the PSP, so
//                                its exercise uses the simulated window and the number is a
//                                constant on both halves.
//   MM_DumpMemToFile's        -- YES. Its one event has no %p at all.
//   MM_WriteFileHeaders' two  -- YES, no %p.
//   MM_FillDumpInEventBuffer's three -- NO. Each prints `Tgt=%p`, the caller's DumpBuffer, for
//                                the same reason mm_mem8.HC's read error is undrivable. Their
//                                SUCCESS paths are exercised; the three error arms are not.
#ifndef MM_DUMP_HC
#define MM_DUMP_HC

// --- cfe_psp.h -------------------------------------------------------------------------------
// MM_PeekMem starts PSP_Status at NOT_IMPLEMENTED rather than at an error, so a DataSize the
// switch does not recognise returns -27 and reports `MemType=MEM0` -- the one status in MM that
// means "no branch ran" rather than "a branch failed".
#define CFE_PSP_ERROR_NOT_IMPLEMENTED -27

// --- what this file needs from elsewhere -----------------------------------------------------
I32 CFE_FS_WriteHeader(U32 FileDes, CFE_FS_Header_t *Hdr);

/*******************************************************************************/
// Read 8, 16, or 32 bits of data from any given input address.
//
// THE EVENT ID IS CHOSEN BY THE WIDTH -- three different INFORMATION events for one command --
// and EventID stays 0 if the PSP failed, which is why the success and failure paths are two
// separate CFE_EVS_SendEvent calls rather than one with a variable id.
I32 MM_PeekMem(MM_PeekCmd_t *CmdPtr, U64 SrcAddress)
{
  U8 ByteValue = 0;
  U16 WordValue = 0;
  U32 DWordValue = 0;
  I32 PSP_Status = CFE_PSP_ERROR_NOT_IMPLEMENTED;
  I64 BytesProcessed = 0;
  U32 DataValue = 0;
  I64 DataSize = 0;
  U32 EventID = 0;

  /*
  ** Read the requested number of bytes and report in an event message
  */
  switch (CmdPtr->Payload.DataSize) {
    case MM_INTERNAL_BYTE_BIT_WIDTH:

      PSP_Status = CFE_PSP_MemRead8(SrcAddress, &ByteValue);
      DataSize = 8;
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataValue = ByteValue;
        BytesProcessed = sizeof(U8);
        EventID = MM_PEEK_BYTE_INF_EID;
      }
      break;

    case MM_INTERNAL_WORD_BIT_WIDTH:

      PSP_Status = CFE_PSP_MemRead16(SrcAddress, &WordValue);
      DataSize = 16;
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataValue = WordValue;
        BytesProcessed = sizeof(U16);
        EventID = MM_PEEK_WORD_INF_EID;
      }
      break;

    case MM_INTERNAL_DWORD_BIT_WIDTH:

      PSP_Status = CFE_PSP_MemRead32(SrcAddress, &DWordValue);
      DataSize = 32;
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataValue = DWordValue;
        BytesProcessed = sizeof(U32);
        EventID = MM_PEEK_DWORD_INF_EID;
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
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_PEEK;
    MM_AppData.HkTlm.Payload.MemType = CmdPtr->Payload.MemType;
    MM_AppData.HkTlm.Payload.Address = SrcAddress;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
    MM_AppData.HkTlm.Payload.DataValue = DataValue;

    CFE_EVS_SendEvent(EventID, CFE_EVS_EventType_INFORMATION,
                      "Peek Command: Addr = %p Size = %u bits Data = 0x%08X", SrcAddress,
                      DataSize, DataValue);
  } else {
    CFE_EVS_SendEvent(MM_PSP_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                      "PSP read memory error: RC=%d, Address=%p, MemType=MEM%u", PSP_Status,
                      SrcAddress, DataSize);
  }

  return PSP_Status;
}

/*******************************************************************************/
// Dump the requested number of bytes from memory to a file.
//
// THE GENERIC DUMP: no PSP, no width. `memcpy` straight out of the address, which is what makes
// it the RAM and EEPROM path -- those memory types take an ordinary load. See the note at the
// top of this file for what that costs a differential transcript.
//
// AND IT REPORTS FileHeader->MemType RATHER THAN A CONSTANT, because unlike the three width
// files this one function serves two memory types and cannot know which it was called for.
I32 MM_DumpMemToFile(U32 FileHandle, U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader)
{
  I32 OS_Status = OS_SUCCESS;
  U32 BytesRemaining = FileHeader->NumOfBytes;
  I64 BytesProcessed = 0;
  I64 SegmentSize = MM_INTERNAL_MAX_DUMP_DATA_SEG;
  U8 *SourcePtr = FileHeader->SymAddress.Offset(U8 *);
  U8 *ioBuffer = (&MM_AppData.DumpBuffer[0])(U8 *);

  while (BytesRemaining != 0) {
    if (BytesRemaining < MM_INTERNAL_MAX_DUMP_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    MemCpy(ioBuffer, SourcePtr, SegmentSize);

    OS_Status = OS_write(FileHandle, ioBuffer, SegmentSize);
    if (OS_Status == SegmentSize) {
      SourcePtr += SegmentSize;
      BytesRemaining -= SegmentSize;
      BytesProcessed += SegmentSize;

      /* Prevent CPU hogging between dump segments */
      if (BytesRemaining != 0) {
        MM_SegmentBreak();
      }

      // AND THE STATUS IS RESET TO SUCCESS HERE, inside the loop, which matters: OS_write
      // returns the BYTE COUNT, so without this line a successful dump would return 200 rather
      // than 0 and every caller's `== CFE_SUCCESS` would fail.
      OS_Status = OS_SUCCESS;
    } else {
      BytesRemaining = 0;
      CFE_EVS_SendEvent(MM_OS_WRITE_EXP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_write error received: RC = %d, Expected = %u, File = '%s'", OS_Status,
                        SegmentSize, FileName);
    }
  }

  /* Update last action statistics */
  if (BytesProcessed == FileHeader->NumOfBytes) {
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_DUMP_TO_FILE;
    MM_AppData.HkTlm.Payload.MemType = FileHeader->MemType;
    MM_AppData.HkTlm.Payload.Address = FileHeader->SymAddress.Offset;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
    StrNCpy(MM_AppData.HkTlm.Payload.FileName, FileName, CFE_MISSION_MAX_PATH_LEN);
  } else {
    OS_Status = OS_ERROR;
  }

  return OS_Status;
}

/*******************************************************************************/
// Write the cFE primary and MM secondary file headers.
//
// TWO HEADERS, TWO DIFFERENT WRITERS: cFE's goes through CFE_FS_WriteHeader, which byte-swaps
// and timestamps it; MM's goes through a plain OS_write of sizeof(MM_LoadDumpFileHeader_t).
//
// THAT sizeof IS 88 AND THE STRUCT'S LAST BYTE IS TAIL PADDING, so NASA writes one byte of
// WHATEVER THE CALLER LEFT ON THE STACK into every dump file. docs/CFS_PLAN.md records the same
// defect in cFE's table dump. Both halves of the differential zero the header before calling,
// which is the driver's choice and not NASA's -- stated at the exercise, because a zero there is
// evidence about the driver and not about the translation.
//
// BOTH ERROR ARMS REPORT OS_ERR_INVALID_SIZE RATHER THAN WHAT WENT WRONG, and the event prints
// the status AFTER it has been replaced -- so a write that failed and a write that was short are
// indistinguishable to the ground. NASA's own choice; the event text is the evidence.
I32 MM_WriteFileHeaders(U8 *FileName, U32 FileHandle, CFE_FS_Header_t *CFEHeader,
                        MM_LoadDumpFileHeader_t *MMHeader)
{
  I32 OS_Status;

  /*
  ** Write out the primary cFE file header
  */
  OS_Status = CFE_FS_WriteHeader(FileHandle, CFEHeader);
  if (OS_Status != sizeof(CFE_FS_Header_t)) {
    /* We either got an error or didn't write as much data as expected */
    OS_Status = OS_ERR_INVALID_SIZE;
    CFE_EVS_SendEvent(MM_CFE_FS_WRITEHDR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "CFE_FS_WriteHeader error received: RC = %d Expected = %d File = '%s'",
                      OS_Status, sizeof(CFE_FS_Header_t), FileName);

  } /* end CFE_FS_WriteHeader if */
  else {
    /*
    ** Write out the secondary MM file header
    */
    OS_Status = OS_write(FileHandle, MMHeader, sizeof(MM_LoadDumpFileHeader_t));
    if (OS_Status != sizeof(MM_LoadDumpFileHeader_t)) {
      /* We either got an error or didn't read as much data as expected */
      OS_Status = OS_ERR_INVALID_SIZE;
      CFE_EVS_SendEvent(MM_OS_WRITE_EXP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_write error received: RC = %d Expected = %u File = '%s'", OS_Status,
                        sizeof(MM_LoadDumpFileHeader_t), FileName);
    } else {
      OS_Status = OS_SUCCESS;
    }
  } /* end CFE_FS_WriteHeader else */

  return OS_Status;
}

/*******************************************************************************/
// Fill a buffer with data to be dumped in an event message string.
//
// FOUR ARMS FOR ONE OPERATION, which is the clearest statement in MM of what a memory type IS:
// RAM and EEPROM share a plain memcpy, while MEM32, MEM16 and MEM8 each walk the region in
// their own width through the PSP. `case RAM:` and `case EEPROM:` share a body, and HolyC's
// switch falls through exactly as C's does -- measured, with both an empty label and a
// non-empty case without a break, before this was written.
//
// AND THE BUFFER POINTER IS ADVANCED BY REASSIGNING THE PARAMETER, so the caller's pointer is
// untouched and the loop needs no index into it. NASA's own shape.
I32 MM_FillDumpInEventBuffer(U64 SrcAddress, MM_DumpInEventCmd_t *CmdPtr, U8 *DumpBuffer)
{
  // NASA guards this declaration with `#if defined(MEM8) || defined(MEM16) || defined(MEM32)`,
  // and all three are defined in this configuration, so the variable exists. Not translated as
  // a directive -- docs/HOLYC_STRUCT_LIMITS.md #19.
  U32 i;
  /* cppcheck-suppress unusedVariable */
  I32 PSP_Status = CFE_PSP_ERROR;

  /* Initialize buffer */
  MemSet(DumpBuffer, 0, MM_INTERNAL_MAX_DUMP_INEVENT_BYTES);

  switch (CmdPtr->Payload.MemType) {
    case MM_MemType_RAM:
    case MM_MemType_EEPROM:
      MemCpy(DumpBuffer, SrcAddress(U8 *), CmdPtr->Payload.NumOfBytes);
      PSP_Status = CFE_PSP_SUCCESS;

      break;

    case MM_MemType_MEM32:
      for (i = 0; i < CmdPtr->Payload.NumOfBytes / 4; i++) {
        PSP_Status = CFE_PSP_MemRead32(SrcAddress, DumpBuffer(U32 *));
        if (PSP_Status == CFE_PSP_SUCCESS) {
          SrcAddress += sizeof(U32);
          DumpBuffer = DumpBuffer + sizeof(U32);
        } else {
          /* CFE_PSP_MemRead32 error */
          CFE_EVS_SendEvent(MM_PSP_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                            "PSP read memory error: RC=%d, Src=%p, Tgt=%p, Type=MEM32",
                            PSP_Status, SrcAddress, DumpBuffer);
          /* Stop load dump buffer loop */
          break;
        }
      }
      break;

    case MM_MemType_MEM16:
      for (i = 0; i < CmdPtr->Payload.NumOfBytes / 2; i++) {
        PSP_Status = CFE_PSP_MemRead16(SrcAddress, DumpBuffer(U16 *));
        if (PSP_Status == CFE_PSP_SUCCESS) {
          SrcAddress += sizeof(U16);
          DumpBuffer = DumpBuffer + sizeof(U16);
        } else {
          /* CFE_PSP_MemRead16 error */
          CFE_EVS_SendEvent(MM_PSP_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                            "PSP read memory error: RC=%d, Src=%p, Tgt=%p, Type=MEM16",
                            PSP_Status, SrcAddress, DumpBuffer);
          /* Stop load dump buffer loop */
          break;
        }
      }
      break;

    case MM_MemType_MEM8:
      for (i = 0; i < CmdPtr->Payload.NumOfBytes; i++) {
        PSP_Status = CFE_PSP_MemRead8(SrcAddress, DumpBuffer);
        if (PSP_Status == CFE_PSP_SUCCESS) {
          SrcAddress++;
          DumpBuffer = DumpBuffer + 1;
        } else {
          /* CFE_PSP_MemRead8 error */
          CFE_EVS_SendEvent(MM_PSP_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                            "PSP read memory error: RC=%d, Src=%p, Tgt=%p, Type=MEM8", PSP_Status,
                            SrcAddress, DumpBuffer);
          /* Stop load dump buffer loop */
          break;
        }
      }
      break;
    default:
      /* This branch will never be executed. CmdPtr->Payload.MemType will always
       * be valid value for this switch statement it is verified via
       * MM_VerifyFileLoadDumpParams */
      break;

  } /* end CmdPtr->Payload.MemType switch */

  return PSP_Status;
}
#endif
