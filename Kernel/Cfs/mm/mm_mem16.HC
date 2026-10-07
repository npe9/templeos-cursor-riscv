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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_mem16.c -- load, dump and fill for a memory
// region that can only be reached TWO BYTES AT A TIME.
//
// READ mm_mem8.HC FIRST. This file is its near-twin, and the whole value of keeping the three
// width files separate -- as NASA does -- is that the DIFFERENCES are small enough to list, and
// every one of them is behaviour:
//
//   1. THE LOOP COUNTS ELEMENTS, NOT BYTES: `i < SegmentSize / sizeof(uint16)`. A 200-byte
//      segment is 100 stores. mem8's loop counts bytes because for it the two are the same.
//   2. THE LOAD'S WRITE-ERROR PATH OVERWRITES PSP_Status BEFORE REPORTING IT, so its event
//      prints RC=0xFFFFFFFF -- NOT the code the PSP returned. mem8 prints the real code
//      (0xFFFFFFEB for this port's CFE_PSP_INVALID_MEM_ADDR) and mem32 prints it as a signed
//      decimal with "RC=%d". Three files, three renderings of one error, and a translator who
//      harmonised them would lose all three.
//   3. THE FILL WARNS AND TRUNCATES an odd length -- MM_FILL_MEM16_ALIGN_WARN_INF_EID -- and
//      then REPORTS AN ERROR ANYWAY, because the housekeeping guard compares BytesProcessed
//      against the COMMANDED NumOfBytes, which the truncation has already made unreachable.
//      mem8 has nothing to truncate.
//
// Item 3 is also why mem8's two "swap the housekeeping guard" mutations were provable no-ops and
// these are not: the truncation is the one input that makes `BytesProcessed == NumOfBytes` and
// `PSP_Status == CFE_PSP_SUCCESS` disagree. See docs/CFS_PLAN.md.
//
// MM_PSP_READ_ERR_EID is NOT drivable here either, for the reason mm_mem8.HC gives: its text
// prints `Tgt=%p`, a real pointer into MM_AppData.DumpBuffer.
#ifndef MM_MEM16_HC
#define MM_MEM16_HC

// MM_INTERNAL_OPT_CODE_MEM16_MEMTYPE is DEFINED in NASA's default configuration, so the whole
// file is live code. Not translated as `#if` -- docs/HOLYC_STRUCT_LIMITS.md #19 records that
// `#if <expr>` is unconditionally true here, which would make the guard agree by accident.

// --- cfe_psp.h -------------------------------------------------------------------------------
// The write half of the simulated window. The driver supplies it, as it supplies the 22 other
// CFE_PSP_* functions this port needs.
I32 CFE_PSP_MemWrite16(U64 MemoryAddress, U16 uint16Value);
I32 CFE_PSP_MemRead16(U64 MemoryAddress, U16 *uint16Value);

/*******************************************************************************/
// Load memory from a file using only 8 bit wide writes.
//
// THE SEGMENT LOOP IS THE SHAPE OF ALL SIX FUNCTIONS IN THE THREE WIDTH FILES: take up to
// MM_INTERNAL_MAX_LOAD_DATA_SEG bytes, move them, then MM_SegmentBreak so something else can
// run. A load of a megabyte is 5,243 segments.
//
// BytesRemaining IS int32 HERE AND uint32 IN THE OTHER TWO FUNCTIONS, which is NASA's own
// inconsistency and is kept: `while (BytesRemaining != 0)` reaches zero by subtraction either
// way, but the comparison against MM_INTERNAL_MAX_LOAD_DATA_SEG is signed in this one.
I32 MM_LoadMem16FromFile(U32 FileHandle, U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader,
                        U64 DestAddress)
{
  U32 i;
  I32 ReadLength;
  I32 PSP_Status = CFE_PSP_SUCCESS;
  I64 BytesProcessed = 0;
  I32 BytesRemaining = FileHeader->NumOfBytes;
  U16 *DataPointer16 = DestAddress(U16 *);
  U16 *ioBuffer16 = (&MM_AppData.LoadBuffer[0])(U16 *);
  I64 SegmentSize = MM_INTERNAL_MAX_LOAD_DATA_SEG;

  while (BytesRemaining != 0) {
    if (BytesRemaining < MM_INTERNAL_MAX_LOAD_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    /* Read file data into i/o buffer */
    // NASA writes this as `if ((ReadLength = OS_read(...)) != SegmentSize)`. HolyC's assignment
    // is a statement, not an expression, so the call is hoisted -- same single evaluation, same
    // order, one line instead of none.
    ReadLength = OS_read(FileHandle, ioBuffer16, SegmentSize);
    if (ReadLength != SegmentSize) {
      BytesRemaining = 0;
      PSP_Status = CFE_PSP_ERROR;
      CFE_EVS_SendEvent(MM_OS_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_read error received: RC = 0x%08X Expected = %u File = '%s'",
                        ReadLength, SegmentSize, FileName);
    } else {
      /* Load memory from i/o buffer using 8 bit wide writes */
      for (i = 0; i < SegmentSize / sizeof(U16); i++) {
        PSP_Status = CFE_PSP_MemWrite16(DataPointer16(U64), ioBuffer16[i]);
        if (PSP_Status == CFE_PSP_SUCCESS) {
          DataPointer16++;
        } else {
          /* CFE_PSP_MemWrite16 error */
          BytesRemaining = 0;
          // AND THE STATUS IS OVERWRITTEN BEFORE IT IS REPORTED, which mem8 does not do: the
          // event below prints CFE_PSP_ERROR and not the code CFE_PSP_MemWrite16 returned.
          // NASA's own order, kept.
          PSP_Status = CFE_PSP_ERROR;
          CFE_EVS_SendEvent(MM_PSP_WRITE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "PSP write memory error: RC=0x%08X, Address=%p, MemType=MEM16",
                            PSP_Status, DataPointer16);
          /* Stop load segment loop */
          break;
        }
      }

      if (PSP_Status == CFE_PSP_SUCCESS) {
        BytesProcessed += SegmentSize;
        BytesRemaining -= SegmentSize;

        /* Prevent CPU hogging between load segments */
        if (BytesRemaining != 0) {
          MM_SegmentBreak();
        }
      }
    }
  }

  /* Update last action statistics */
  // THE HOUSEKEEPING IS WRITTEN ONLY ON A COMPLETE LOAD, and the test is BytesProcessed against
  // the header's count rather than the status -- so a short load leaves the PREVIOUS command's
  // address and byte count in telemetry, with PSP_Status turned into an error here.
  if (BytesProcessed == FileHeader->NumOfBytes) {
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_LOAD_FROM_FILE;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM16;
    MM_AppData.HkTlm.Payload.Address = DestAddress;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
    StrNCpy(MM_AppData.HkTlm.Payload.FileName, FileName, CFE_MISSION_MAX_PATH_LEN);
  } else {
    PSP_Status = CFE_PSP_ERROR;
  }

  return PSP_Status;
}

/*******************************************************************************/
// Dump the requested number of bytes from memory to a file using only 8 bit wide reads.
//
// THE DUMP ADDRESS COMES FROM THE FILE HEADER, not from a parameter: NASA takes
// FileHeader->SymAddress.Offset directly, already resolved by the caller, where the load above
// takes a resolved DestAddress. Two ways of saying the same thing, kept as NASA wrote them.
I32 MM_DumpMem16ToFile(U32 FileHandle, U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader)
{
  I32 OS_Status;
  I32 PSP_Status = CFE_PSP_SUCCESS;
  U32 i;
  I64 BytesProcessed = 0;
  U32 BytesRemaining = FileHeader->NumOfBytes;
  U16 *DataPointer16 = FileHeader->SymAddress.Offset(U16 *);
  U16 *ioBuffer16 = (&MM_AppData.DumpBuffer[0])(U16 *);
  I64 SegmentSize = MM_INTERNAL_MAX_DUMP_DATA_SEG;

  while (BytesRemaining != 0) {
    if (BytesRemaining < MM_INTERNAL_MAX_DUMP_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    /* Load RAM data into i/o buffer */
    for (i = 0; i < SegmentSize / sizeof(U16); i++) {
      PSP_Status = CFE_PSP_MemRead16(DataPointer16(U64), &ioBuffer16[i]);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataPointer16++;
      } else {
        /* CFE_PSP_MemRead16 error */
        BytesRemaining = 0;
        // THE ONE EVENT IN THIS FILE A DIFFERENTIAL CANNOT COMPARE: Tgt is a real pointer into
        // MM_AppData.DumpBuffer. See the note at the top of this file.
        CFE_EVS_SendEvent(MM_PSP_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PSP read memory error: RC=0x%08X, Src=%p, Tgt=%p, Type=MEM16",
                          PSP_Status, DataPointer16, &ioBuffer16[i]);
        /* Stop load i/o buffer loop */
        break;
      }
    }

    /* Check for error loading i/o buffer */
    if (PSP_Status == CFE_PSP_SUCCESS) {
      /* Write i/o buffer contents to file */
      OS_Status = OS_write(FileHandle, ioBuffer16, SegmentSize);
      if (OS_Status == SegmentSize) {
        /* Update process counters */
        BytesRemaining -= SegmentSize;
        BytesProcessed += SegmentSize;

        /* Prevent CPU hogging between dump segments */
        if (BytesRemaining != 0) {
          MM_SegmentBreak();
        }
      } else {
        /* OS_write error */
        BytesRemaining = 0;
        PSP_Status = CFE_PSP_ERROR;
        CFE_EVS_SendEvent(MM_OS_WRITE_EXP_ERR_EID, CFE_EVS_EventType_ERROR,
                          "OS_write error received: RC = 0x%08X Expected = %u File = '%s'",
                          OS_Status, SegmentSize, FileName);
      }
    }
  }

  if (PSP_Status == CFE_PSP_SUCCESS) {
    /* Update last action statistics */
    // AND HERE THE TEST IS THE STATUS, not the byte count -- the opposite of the load above,
    // and NASA's own choice. It also writes Address from the header WITHOUT the
    // CFE_ES_MEMADDRESS_C cast the load uses, because the field is already that type.
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_DUMP_TO_FILE;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM16;
    MM_AppData.HkTlm.Payload.Address = FileHeader->SymAddress.Offset;
    StrNCpy(MM_AppData.HkTlm.Payload.FileName, FileName, CFE_MISSION_MAX_PATH_LEN);
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
  }

  return PSP_Status;
}

/*******************************************************************************/
// Fill memory with the command specified fill pattern using only 8 bit wide writes.
//
// THE PATTERN IS TRUNCATED TO TWO BYTES and housekeeping reports the TRUNCATED value, so a
// commanded 0xAABBCCDD comes back as 0xCCDD -- the app telling the operator what it actually
// wrote.
//
// AND SO IS THE LENGTH, WITH A WARNING. An odd NumOfBytes cannot be written in 16-bit stores, so
// NASA rounds it DOWN and says so in an INFORMATION event. The consequence is the interesting
// part: the housekeeping guard at the bottom compares BytesProcessed against the COMMANDED
// NumOfBytes, which the truncation has just made unreachable -- so an odd-length fill WARNS,
// writes the even part, LEAVES HOUSEKEEPING ALONE and RETURNS AN ERROR. All four at once.
I32 MM_FillMem16(U64 DestAddress, MM_FillMemCmd_t *CmdPtr)
{
  U32 i;
  I32 PSP_Status = CFE_PSP_SUCCESS;
  I64 BytesProcessed = 0;
  U32 BytesRemaining = CmdPtr->Payload.NumOfBytes;
  U32 NewBytesRemaining;
  U16 FillPattern16 = CmdPtr->Payload.FillPattern;
  U16 *DataPointer16 = DestAddress(U16 *);
  I64 SegmentSize = MM_INTERNAL_MAX_FILL_DATA_SEG;

  /* Check fill size and warn if not a multiple of 2 */
  if ((BytesRemaining % 2) != 0) {
    NewBytesRemaining = BytesRemaining - (BytesRemaining % 2);
    CFE_EVS_SendEvent(MM_FILL_MEM16_ALIGN_WARN_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "MM_FillMem16 NumOfBytes not multiple of 2. Reducing from %u to %u.",
                      BytesRemaining, NewBytesRemaining);
    BytesRemaining = NewBytesRemaining;
  }

  while (BytesRemaining != 0) {
    /* Set size of next segment */
    if (BytesRemaining < MM_INTERNAL_MAX_FILL_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    /* Fill next segment */
    for (i = 0; i < SegmentSize / sizeof(U16); i++) {
      PSP_Status = CFE_PSP_MemWrite16(DataPointer16(U64), FillPattern16);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataPointer16++;
      } else {
        /* CFE_PSP_MemWrite16 error */
        BytesRemaining = 0;
        CFE_EVS_SendEvent(MM_PSP_WRITE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PSP write memory error: RC=0x%08X, Address=%p, MemType=MEM16",
                          PSP_Status, DataPointer16);
        /* Stop fill segment loop */
        break;
      }
    }

    if (PSP_Status == CFE_PSP_SUCCESS) {
      /* Update process counters */
      BytesRemaining -= SegmentSize;
      BytesProcessed += SegmentSize;

      /* Prevent CPU hogging between fill segments */
      if (BytesRemaining != 0) {
        MM_SegmentBreak();
      }
    }
  }

  /* Update last action statistics */
  if (BytesProcessed == CmdPtr->Payload.NumOfBytes) {
    MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_FILL;
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM16;
    MM_AppData.HkTlm.Payload.Address = DestAddress;
    MM_AppData.HkTlm.Payload.DataValue = FillPattern16;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
  } else {
    PSP_Status = CFE_PSP_ERROR;
  }

  return PSP_Status;
}
#endif
