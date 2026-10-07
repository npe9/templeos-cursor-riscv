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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_mem8.c -- load, dump and fill for a memory
// region that can only be reached ONE BYTE AT A TIME.
//
// WHY THE THREE WIDTHS ARE THREE FILES. mm_mem8.c, mm_mem16.c and mm_mem32.c are
// near-identical, and that is not duplication NASA failed to factor out: a MEM8 device
// physically cannot take a 16-bit store, so the width is a property of the hardware and the
// loop that touches it has to be written for one width. The differences between the three are
// exactly the interesting part, and keeping them as three files is what makes them readable.
//
// THIS IS THE FIRST SOURCE IN THE PORT THAT WRITES MEMORY. MD only ever read; MM pokes, fills
// and loads. So the simulated window MD established (MD_SIM_WINDOW_BASE in the driver) gains a
// write half here, behind CFE_PSP_MemWrite8 -- the same arrangement, and the same reason the
// addresses are literal constants rather than a real buffer's address.
//
// ONE BRANCH HERE CANNOT BE DRIVEN BY A DIFFERENTIAL TRANSCRIPT AT ALL, and it is worth being
// precise about which. MM_PSP_READ_ERR_EID's text is
//     "PSP read memory error: RC=0x%08X, Src=%p, Tgt=%p, Type=MEM8"
// and `Tgt` is `&ioBuffer8[i]` -- a REAL POINTER into MM_AppData.DumpBuffer, not an address the
// ground supplied. Every other address in MM's event text is a number that came from a command
// and is therefore the same constant on both halves; this one is wherever the linker put
// MM_AppData, and a host process and a QEMU guest never agree about that. So the exercise
// drives the other three error events in this file and NOT this one, and says so. See
// docs/CFS_PLAN.md.
#ifndef MM_MEM8_HC
#define MM_MEM8_HC

// MM_INTERNAL_OPT_CODE_MEM8_MEMTYPE is DEFINED in NASA's default configuration, so the whole
// file is live code. Not translated as `#if` -- docs/HOLYC_STRUCT_LIMITS.md #19 records that
// `#if <expr>` is unconditionally true here, which would make the guard agree by accident.

// --- cfe_psp.h -------------------------------------------------------------------------------
// The write half of the simulated window. The driver supplies it, as it supplies the 22 other
// CFE_PSP_* functions this port needs.
I32 CFE_PSP_MemWrite8(U64 MemoryAddress, U8 ByteValue);
I32 CFE_PSP_MemRead8(U64 MemoryAddress, U8 *ByteValue);

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
I32 MM_LoadMem8FromFile(U32 FileHandle, U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader,
                        U64 DestAddress)
{
  U32 i;
  I32 ReadLength;
  I32 PSP_Status = CFE_PSP_SUCCESS;
  I64 BytesProcessed = 0;
  I32 BytesRemaining = FileHeader->NumOfBytes;
  U8 *DataPointer8 = DestAddress(U8 *);
  U8 *ioBuffer8 = (&MM_AppData.LoadBuffer[0])(U8 *);
  I64 SegmentSize = MM_INTERNAL_MAX_LOAD_DATA_SEG;

  while (BytesRemaining != 0) {
    if (BytesRemaining < MM_INTERNAL_MAX_LOAD_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    /* Read file data into i/o buffer */
    // NASA writes this as `if ((ReadLength = OS_read(...)) != SegmentSize)`. HolyC's assignment
    // is a statement, not an expression, so the call is hoisted -- same single evaluation, same
    // order, one line instead of none.
    ReadLength = OS_read(FileHandle, ioBuffer8, SegmentSize);
    if (ReadLength != SegmentSize) {
      BytesRemaining = 0;
      PSP_Status = CFE_PSP_ERROR;
      CFE_EVS_SendEvent(MM_OS_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OS_read error received: RC = 0x%08X Expected = %u File = '%s'",
                        ReadLength, SegmentSize, FileName);
    } else {
      /* Load memory from i/o buffer using 8 bit wide writes */
      for (i = 0; i < SegmentSize; i++) {
        PSP_Status = CFE_PSP_MemWrite8(DataPointer8(U64), ioBuffer8[i]);
        if (PSP_Status == CFE_PSP_SUCCESS) {
          DataPointer8++;
        } else {
          /* CFE_PSP_MemWrite8 error */
          BytesRemaining = 0;
          CFE_EVS_SendEvent(MM_PSP_WRITE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "PSP write memory error: RC=0x%08X, Address=%p, MemType=MEM8",
                            PSP_Status, DataPointer8);
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
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM8;
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
I32 MM_DumpMem8ToFile(U32 FileHandle, U8 *FileName, MM_LoadDumpFileHeader_t *FileHeader)
{
  I32 OS_Status;
  I32 PSP_Status = CFE_PSP_SUCCESS;
  U32 i;
  I64 BytesProcessed = 0;
  U32 BytesRemaining = FileHeader->NumOfBytes;
  U8 *DataPointer8 = FileHeader->SymAddress.Offset(U8 *);
  U8 *ioBuffer8 = (&MM_AppData.DumpBuffer[0])(U8 *);
  I64 SegmentSize = MM_INTERNAL_MAX_DUMP_DATA_SEG;

  while (BytesRemaining != 0) {
    if (BytesRemaining < MM_INTERNAL_MAX_DUMP_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    /* Load RAM data into i/o buffer */
    for (i = 0; i < SegmentSize; i++) {
      PSP_Status = CFE_PSP_MemRead8(DataPointer8(U64), &ioBuffer8[i]);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataPointer8++;
      } else {
        /* CFE_PSP_MemRead8 error */
        BytesRemaining = 0;
        // THE ONE EVENT IN THIS FILE A DIFFERENTIAL CANNOT COMPARE: Tgt is a real pointer into
        // MM_AppData.DumpBuffer. See the note at the top of this file.
        CFE_EVS_SendEvent(MM_PSP_READ_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PSP read memory error: RC=0x%08X, Src=%p, Tgt=%p, Type=MEM8",
                          PSP_Status, DataPointer8, &ioBuffer8[i]);
        /* Stop load i/o buffer loop */
        break;
      }
    }

    /* Check for error loading i/o buffer */
    if (PSP_Status == CFE_PSP_SUCCESS) {
      /* Write i/o buffer contents to file */
      OS_Status = OS_write(FileHandle, ioBuffer8, SegmentSize);
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
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM8;
    MM_AppData.HkTlm.Payload.Address = FileHeader->SymAddress.Offset;
    StrNCpy(MM_AppData.HkTlm.Payload.FileName, FileName, CFE_MISSION_MAX_PATH_LEN);
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
  }

  return PSP_Status;
}

/*******************************************************************************/
// Fill memory with the command specified fill pattern using only 8 bit wide writes.
//
// THE PATTERN IS TRUNCATED TO ONE BYTE, and the housekeeping reports the TRUNCATED value --
// `DataValue = (uint32)FillPattern8` and not the commanded FillPattern. So a ground operator who
// commands 0xAABBCCDD for a MEM8 region sees 0xDD come back, which is the app telling them what
// it actually wrote.
I32 MM_FillMem8(U64 DestAddress, MM_FillMemCmd_t *CmdPtr)
{
  U32 i;
  I32 PSP_Status = CFE_PSP_SUCCESS;
  I64 BytesProcessed = 0;
  U32 BytesRemaining = CmdPtr->Payload.NumOfBytes;
  U8 FillPattern8 = CmdPtr->Payload.FillPattern;
  U8 *DataPointer8 = DestAddress(U8 *);
  I64 SegmentSize = MM_INTERNAL_MAX_FILL_DATA_SEG;

  while (BytesRemaining != 0) {
    /* Set size of next segment */
    if (BytesRemaining < MM_INTERNAL_MAX_FILL_DATA_SEG) {
      SegmentSize = BytesRemaining;
    }

    /* Fill next segment */
    for (i = 0; i < SegmentSize; i++) {
      PSP_Status = CFE_PSP_MemWrite8(DataPointer8(U64), FillPattern8);
      if (PSP_Status == CFE_PSP_SUCCESS) {
        DataPointer8++;
      } else {
        /* CFE_PSP_MemWrite8 error */
        BytesRemaining = 0;
        CFE_EVS_SendEvent(MM_PSP_WRITE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PSP write memory error: RC=0x%08X, Address=%p, MemType=MEM8",
                          PSP_Status, DataPointer8);
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
    MM_AppData.HkTlm.Payload.MemType = MM_MemType_MEM8;
    MM_AppData.HkTlm.Payload.Address = DestAddress;
    MM_AppData.HkTlm.Payload.DataValue = FillPattern8;
    MM_AppData.HkTlm.Payload.BytesProcessed = BytesProcessed;
  } else {
    PSP_Status = CFE_PSP_ERROR;
  }

  return PSP_Status;
}
#endif
