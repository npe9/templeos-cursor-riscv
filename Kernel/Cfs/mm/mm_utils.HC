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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_utils.c -- MM's leaf, and the first source of
// the port's SECOND cFS application.
//
// Eight functions: the housekeeping reset, the segment break, the two parameter validators,
// the two alignment checks, the address resolver and the file CRC. MM's whole safety argument
// lives in the two validators -- every command that writes memory passes through one of them
// first, and what they accept is the definition of what the ground can reach.
//
// THE TWO VALIDATORS ARE NOT TWO COPIES OF ONE IDEA. MM_VerifyPeekPokeParams takes a width in
// BITS, because a peek or a poke names a machine operation; MM_VerifyLoadDumpParams takes a
// length in BYTES and also takes WHICH COMMAND is asking, because a load, a dump, a fill, a
// dump-into-an-event and a load-with-interrupts-disabled have five different size bounds for
// the same memory type. Thirty combinations, and NASA's own comment says the correctness of the
// cross product rests on MaxSize STAYING ZERO for the pairs no branch sets -- a zero MaxSize
// then fails the size check at the end, which is where the rejection is supposed to happen.
// That is why the exercise walks it as a grid.
//
// EVERY EVENT HERE PRINTS AN ADDRESS WITH %p. See the note at the top of mm_msg.HC: no
// previously gated NASA source used that conversion, Kernel/Cfs/CfsStr.HC did not implement it,
// and an unhandled conversion does not consume its argument.
#ifndef MM_UTILS_HC
#define MM_UTILS_HC

// --- cfe_psp.h --------------------------------------------------------------------------------
// The memory-type selectors CFE_PSP_MemValidateRange takes, and the one PSP status mm_utils.c
// returns that no other translated file has needed. CFE_PSP_SUCCESS and CFE_PSP_ERROR are
// defined by several files already, each guarded, because the PSP is simulated in this port and
// has no translated header of its own.
#define CFE_PSP_MEM_RAM    1
#define CFE_PSP_MEM_EEPROM 2
#ifndef CFE_PSP_SUCCESS
#define CFE_PSP_SUCCESS 0
#endif
#ifndef CFE_PSP_ERROR
#define CFE_PSP_ERROR -1
#endif
#define CFE_PSP_ERROR_ADDRESS_MISALIGNED -3

// --- osapi-error.h ---------------------------------------------------------------------------
// The three OSAL statuses MM_VerifyPeekPokeParams returns. OSAL is not translated INTO the cFS
// differential driver -- it has its own gate and its own driver -- so the handful of OS_* values
// a cFS source needs are declared where that source needs them, which is what cfe_es_api.HC and
// cfe_fs_priv.HC already do for OS_ERROR and OS_SUCCESS. check_constants compares all three
// against NASA's own header, so a wrong number here is a gate failure and not a silent one.
#ifndef OS_ERROR_ADDRESS_MISALIGNED
#define OS_ERROR_ADDRESS_MISALIGNED -3
#endif
#ifndef OS_ERR_INVALID_SIZE
#define OS_ERR_INVALID_SIZE -40
#endif
#ifndef OS_ERR_INVALID_ARGUMENT
#define OS_ERR_INVALID_ARGUMENT -42
#endif

// NASA's own file-local macro: the read size MM_ComputeCRCFromFile works in.
#define FILE_CRC_BUFFER_SIZE 200

// --- what this file needs from elsewhere ------------------------------------------------------
// The PSP, which is not translated.
I32 CFE_PSP_MemValidateRange(U64 Address, I64 Size, U32 MemoryType);
// OSAL's symbol table, which on a real target is the loader's. The address MM hands the ground
// comes out of here.
I32 OS_SymbolLookup(U64 *SymbolAddress, U8 *SymbolName);

// AND TWO OF THIS FILE'S OWN, forward-declared rather than moved. NASA's two validators call
// the two alignment checks, which NASA defines BELOW them -- in C that works because mm_utils.h
// declares all eight. HolyC needs the declaration at the point of the call, and the choice is
// between reordering the file and declaring forward; declaring forward keeps the translation in
// NASA's order, which is what makes a line-by-line reading of the two possible.
Bool MM_Verify32Aligned(U64 Address, I64 Size);
Bool MM_Verify16Aligned(U64 Address, I64 Size);

/*******************************************************************************/
// Reset the local housekeeping variables to default parameters.
//
// NOT THE COUNTERS. CommandCounter and CommandErrorCounter are untouched -- this is called at
// the START of each command to clear what the LAST one reported, so a command that fails early
// does not leave the previous command's address in telemetry.
U0 MM_ResetHk()
{
  MM_AppData.HkTlm.Payload.LastAction = MM_LastAction_NOACTION;
  MM_AppData.HkTlm.Payload.MemType = MM_MemType_NOMEMTYPE;
  MM_AppData.HkTlm.Payload.Address = MM_INTERNAL_CLEAR_ADDR;
  MM_AppData.HkTlm.Payload.DataValue = MM_INTERNAL_CLEAR_PATTERN;
  MM_AppData.HkTlm.Payload.BytesProcessed = 0;
  MM_AppData.HkTlm.Payload.FileName[0] = MM_INTERNAL_CLEAR_FNAME;
}

/*******************************************************************************/
// Process a load, dump, or fill segment break.
//
// THE ONE PLACE MM YIELDS. A fill of a megabyte would otherwise hold the CPU for its whole
// duration, so the load, dump and fill loops call this every segment. MM_INTERNAL_PROCESSOR_CYCLE
// is 0 in this configuration, which makes OS_TaskDelay(0) a bare reschedule request rather
// than a sleep -- and the two performance-log stamps around it are how the ground sees the cost.
U0 MM_SegmentBreak()
{
  /*
  ** Performance Log entry stamp
  */
  CFE_ES_PerfLogEntry(MM_SEGBREAK_PERF_ID);

  /*
  ** Give something else the chance to run
  */
  OS_TaskDelay(MM_INTERNAL_PROCESSOR_CYCLE);

  /*
  ** Performance Log exit stamp
  */
  CFE_ES_PerfLogExit(MM_SEGBREAK_PERF_ID);
}

/*******************************************************************************/
// Verify peek and poke command parameters.
//
// TWO CHECKS IN SEQUENCE, AND THE SECOND ONLY IF THE FIRST PASSED: first the width must be 8,
// 16 or 32 bits and the address must be aligned for it; then the memory type must be one the
// PSP will validate, and for the three optional types the width must match the type's own
// access size. A MEM16 region can only be reached 16 bits at a time, which is a property of
// the hardware and not of the command.
I32 MM_VerifyPeekPokeParams(U64 Address, U32 MemType, I64 SizeInBits)
{
  I64 SizeInBytes;
  I32 OS_Status = OS_SUCCESS;

  switch (SizeInBits) {
    case MM_INTERNAL_BYTE_BIT_WIDTH:
      SizeInBytes = 1;
      break;

    case MM_INTERNAL_WORD_BIT_WIDTH:
      SizeInBytes = 2;
      if (MM_Verify16Aligned(Address, SizeInBytes) != TRUE) {
        OS_Status = OS_ERROR_ADDRESS_MISALIGNED;
        CFE_EVS_SendEvent(MM_ALIGN16_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Data and address not 16 bit aligned: Addr = %p Size = %u", Address,
                          SizeInBytes);
      }
      break;

    case MM_INTERNAL_DWORD_BIT_WIDTH:
      SizeInBytes = 4;
      if (MM_Verify32Aligned(Address, SizeInBytes) != TRUE) {
        OS_Status = OS_ERROR_ADDRESS_MISALIGNED;
        CFE_EVS_SendEvent(MM_ALIGN32_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Data and address not 32 bit aligned: Addr = %p Size = %u", Address,
                          SizeInBytes);
      }
      break;

    default:
      OS_Status = OS_ERR_INVALID_SIZE;
      CFE_EVS_SendEvent(MM_DATA_SIZE_BITS_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Data size in bits invalid: Data Size = %u", SizeInBits);
      break;
  }

  /* Do other checks if this one passed */
  if (OS_Status == OS_SUCCESS) {
    switch (MemType) {
      case MM_MemType_RAM:
        OS_Status = CFE_PSP_MemValidateRange(Address, SizeInBytes, CFE_PSP_MEM_RAM);

        if (OS_Status != CFE_PSP_SUCCESS) {
          CFE_EVS_SendEvent(MM_OS_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "CFE_PSP_MemValidateRange error received: RC = "
                            "0x%08X Addr = %p Size = %u "
                            "MemType = MEM_RAM",
                            OS_Status, Address, SizeInBytes);
        }
        break;

      case MM_MemType_EEPROM:
        OS_Status = CFE_PSP_MemValidateRange(Address, SizeInBytes, CFE_PSP_MEM_EEPROM);

        if (OS_Status != CFE_PSP_SUCCESS) {
          CFE_EVS_SendEvent(MM_OS_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "CFE_PSP_MemValidateRange error received: RC = "
                            "0x%08X Addr = %p Size = %u "
                            "MemType = MEM_EEPROM",
                            OS_Status, Address, SizeInBytes);
        }
        break;

      // MM_INTERNAL_OPT_CODE_MEM32_MEMTYPE, MEM16 and MEM8 are all DEFINED in NASA's default
      // configuration, so all three arms below are live code and check_coverage sees the whole
      // function. The guards are not translated as `#if` -- docs/HOLYC_STRUCT_LIMITS.md #19
      // records that `#if <expr>` is unconditionally true in this compiler, which would make a
      // guard here agree by accident.
      case MM_MemType_MEM32:
        OS_Status = CFE_PSP_MemValidateRange(Address, SizeInBytes, CFE_PSP_MEM_RAM);

        if (OS_Status != CFE_PSP_SUCCESS) {
          CFE_EVS_SendEvent(MM_OS_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "CFE_PSP_MemValidateRange error received: RC = "
                            "0x%08X Addr = %p Size = %u MemType = MEM32",
                            OS_Status, Address, SizeInBytes);
        }
        /*
        ** Peeks and Pokes must be 32 bits wide for this memory type
        */
        // AND THE EVENT PRINTS SizeInBits, NOT SizeInBytes -- NASA's own choice, and the one
        // place in this function where the two differ in the text. A translator "fixing" it to
        // SizeInBytes would print 1 where NASA prints 8.
        else if (SizeInBytes != 4) {
          OS_Status = OS_ERR_INVALID_SIZE;
          CFE_EVS_SendEvent(MM_DATA_SIZE_BITS_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Data size in bits invalid: Data Size = %u", SizeInBits);
        }
        break;

      case MM_MemType_MEM16:
        OS_Status = CFE_PSP_MemValidateRange(Address, SizeInBytes, CFE_PSP_MEM_RAM);

        if (OS_Status != CFE_PSP_SUCCESS) {
          CFE_EVS_SendEvent(MM_OS_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "CFE_PSP_MemValidateRange error received: RC = "
                            "0x%08X Addr = %p Size = %u MemType = MEM16",
                            OS_Status, Address, SizeInBytes);
        }
        /*
        ** Peeks and Pokes must be 16 bits wide for this memory type
        */
        else if (SizeInBytes != 2) {
          OS_Status = OS_ERR_INVALID_SIZE;
          CFE_EVS_SendEvent(MM_DATA_SIZE_BITS_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Data size in bits invalid: Data Size = %u", SizeInBits);
        }
        break;

      case MM_MemType_MEM8:
        OS_Status = CFE_PSP_MemValidateRange(Address, SizeInBytes, CFE_PSP_MEM_RAM);

        if (OS_Status != CFE_PSP_SUCCESS) {
          CFE_EVS_SendEvent(MM_OS_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                            "CFE_PSP_MemValidateRange error received: RC = "
                            "0x%08X Addr = %p Size = %u MemType = MEM8",
                            OS_Status, Address, SizeInBytes);
        }
        /*
        ** Peeks and Pokes must be 8 bits wide for this memory type
        */
        else if (SizeInBytes != 1) {
          OS_Status = OS_ERR_INVALID_SIZE;
          CFE_EVS_SendEvent(MM_DATA_SIZE_BITS_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Data size in bits invalid: Data Size = %u", SizeInBits);
        }
        break;

      default:
        OS_Status = OS_ERR_INVALID_ARGUMENT;
        CFE_EVS_SendEvent(MM_MEMTYPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Invalid memory type specified: MemType = %d", MemType);
        break;

    } /* end switch */

  } /* end OS_Status == OS_SUCCESS if */

  return OS_Status;
}

/*******************************************************************************/
// Verify load/dump memory parameters.
//
// THE GRID. Five VerifyTypes by six MemTypes, and the switch below does not decide anything --
// it only SETS UP the three values (MaxSize, PSP_MemType, MemTypeStr) that the three blocks
// after it check. NASA's own comment explains the one thing that is easy to get wrong: the
// VerifyType arms have NO else clause, deliberately, because an unreached combination must
// leave MaxSize at 0 and be rejected by the size check at the end. A translator who "completed"
// those if-chains with an else would turn a rejection into an acceptance.
I32 MM_VerifyLoadDumpParams(U64 Address, U32 MemType, I64 SizeInBytes, U8 VerifyType)
{
  I32 PSP_Status = CFE_PSP_SUCCESS;
  I64 MaxSize = 0;
  U32 PSP_MemType = 0;
  // Deliberately uninitialised, exactly as NASA leaves it: it is read only in the final
  // MemValidateRange event, which cannot run unless the switch above set it.
  U8 MemTypeStr[MM_MAX_MEM_TYPE_STR_LEN];

  if ((VerifyType != MM_VERIFY_LOAD) && (VerifyType != MM_VERIFY_DUMP) &&
      (VerifyType != MM_VERIFY_EVENT) && (VerifyType != MM_VERIFY_FILL) &&
      (VerifyType != MM_VERIFY_WID)) {
    PSP_Status = CFE_PSP_ERROR;
  }

  /* The DumpInEvent and LoadMemWID commands use the same max size for all
   * memory types. Therefore if one of these is the command being verified,
   * the max size can be set here rather than in the switch statement */
  if (VerifyType == MM_VERIFY_EVENT) {
    MaxSize = MM_INTERNAL_MAX_DUMP_INEVENT_BYTES;
  } else if (VerifyType == MM_VERIFY_WID) {
    MaxSize = MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA;
  }

  if (PSP_Status == CFE_PSP_SUCCESS) {
    /* All memory types and verification types do fundamentally the same set
       of checks.  This switch-case statement sets up the values used to
       perform the checks at the end of the function.  Two memory types
       also require special handling which is performed in the appropriate
       case. */
    switch (MemType) {
      /* else clauses are not needed in the VerifyType checks because the
          VerifyType is checked above and if the MaxSize is left unchanged,
          it will force an error when the size is checked as it should */
      case MM_MemType_RAM:
        if (VerifyType == MM_VERIFY_LOAD) {
          MaxSize = MM_INTERNAL_MAX_LOAD_FILE_DATA_RAM;
        } else if (VerifyType == MM_VERIFY_DUMP) {
          MaxSize = MM_INTERNAL_MAX_DUMP_FILE_DATA_RAM;
        } else if (VerifyType == MM_VERIFY_FILL) {
          MaxSize = MM_INTERNAL_MAX_FILL_DATA_RAM;
        }
        PSP_MemType = CFE_PSP_MEM_RAM;
        /* SAD: No need to check snprintf return value; buffer size can store
         * "MEM_RAM" without overflow */
        StrPrintN(MemTypeStr, MM_MAX_MEM_TYPE_STR_LEN, "%s", "MEM_RAM");
        break;
      case MM_MemType_EEPROM:
        if (VerifyType == MM_VERIFY_LOAD) {
          MaxSize = MM_INTERNAL_MAX_LOAD_FILE_DATA_EEPROM;
        } else if (VerifyType == MM_VERIFY_DUMP) {
          MaxSize = MM_INTERNAL_MAX_DUMP_FILE_DATA_EEPROM;
        } else if (VerifyType == MM_VERIFY_FILL) {
          MaxSize = MM_INTERNAL_MAX_FILL_DATA_EEPROM;
        }
        PSP_MemType = CFE_PSP_MEM_EEPROM;
        /* SAD: No need to check snprintf return value; buffer size can store
         * "MEM_EEPROM" without overflow */
        StrPrintN(MemTypeStr, MM_MAX_MEM_TYPE_STR_LEN, "%s", "MEM_EEPROM");
        break;
      case MM_MemType_MEM32:
        if (VerifyType == MM_VERIFY_LOAD) {
          MaxSize = MM_INTERNAL_MAX_LOAD_FILE_DATA_MEM32;
        } else if (VerifyType == MM_VERIFY_DUMP) {
          MaxSize = MM_INTERNAL_MAX_DUMP_FILE_DATA_MEM32;
        } else if (VerifyType == MM_VERIFY_FILL) {
          MaxSize = MM_INTERNAL_MAX_FILL_DATA_MEM32;
        }
        PSP_MemType = CFE_PSP_MEM_RAM;
        /* SAD: No need to check snprintf return value; buffer size can store
         * "MEM32" without overflow */
        StrPrintN(MemTypeStr, MM_MAX_MEM_TYPE_STR_LEN, "%s", "MEM32");
        if (MM_Verify32Aligned(Address, SizeInBytes) != TRUE) {
          PSP_Status = CFE_PSP_ERROR_ADDRESS_MISALIGNED;
          CFE_EVS_SendEvent(MM_ALIGN32_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Data and address not 32 bit aligned: Addr = %p Size = %u", Address,
                            SizeInBytes);
        }
        break;
      case MM_MemType_MEM16:
        if (VerifyType == MM_VERIFY_LOAD) {
          MaxSize = MM_INTERNAL_MAX_LOAD_FILE_DATA_MEM16;
        } else if (VerifyType == MM_VERIFY_DUMP) {
          MaxSize = MM_INTERNAL_MAX_DUMP_FILE_DATA_MEM16;
        } else if (VerifyType == MM_VERIFY_FILL) {
          MaxSize = MM_INTERNAL_MAX_FILL_DATA_MEM16;
        }
        PSP_MemType = CFE_PSP_MEM_RAM;
        /* SAD: No need to check snprintf return value; buffer size can store
         * "MEM16" without overflow */
        StrPrintN(MemTypeStr, MM_MAX_MEM_TYPE_STR_LEN, "%s", "MEM16");
        if (MM_Verify16Aligned(Address, SizeInBytes) != TRUE) {
          PSP_Status = CFE_PSP_ERROR_ADDRESS_MISALIGNED;
          CFE_EVS_SendEvent(MM_ALIGN16_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Data and address not 16 bit aligned: Addr = %p Size = %u", Address,
                            SizeInBytes);
        }
        break;
      // MEM8 HAS NO ALIGNMENT CHECK, and that is not an omission: every address is byte
      // aligned. It is the one case arm that differs in shape from its two neighbours.
      case MM_MemType_MEM8:
        if (VerifyType == MM_VERIFY_LOAD) {
          MaxSize = MM_INTERNAL_MAX_LOAD_FILE_DATA_MEM8;
        } else if (VerifyType == MM_VERIFY_DUMP) {
          MaxSize = MM_INTERNAL_MAX_DUMP_FILE_DATA_MEM8;
        } else if (VerifyType == MM_VERIFY_FILL) {
          MaxSize = MM_INTERNAL_MAX_FILL_DATA_MEM8;
        }
        PSP_MemType = CFE_PSP_MEM_RAM;
        /* SAD: No need to check snprintf return value; buffer size can store
         * "MEM8" without overflow */
        StrPrintN(MemTypeStr, MM_MAX_MEM_TYPE_STR_LEN, "%s", "MEM8");
        break;
      default:
        PSP_Status = CFE_PSP_ERROR;
        CFE_EVS_SendEvent(MM_MEMTYPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Invalid memory type specified: MemType = %d", MemType);

        break;
    } /* end MemType switch */
  }

  if (PSP_Status == CFE_PSP_SUCCESS) {
    if ((SizeInBytes == 0) || (SizeInBytes > MaxSize)) {
      PSP_Status = CFE_PSP_ERROR;
      CFE_EVS_SendEvent(MM_DATA_SIZE_BYTES_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Data size in bytes invalid or exceeds limits: Data Size = %u",
                        SizeInBytes);
    }
  }

  if (PSP_Status == CFE_PSP_SUCCESS) {
    PSP_Status = CFE_PSP_MemValidateRange(Address, SizeInBytes, PSP_MemType);

    if (PSP_Status != CFE_PSP_SUCCESS) {
      CFE_EVS_SendEvent(MM_OS_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "CFE_PSP_MemValidateRange error received: RC = 0x%08X "
                        "Addr = %p Size = %u MemType = %s",
                        PSP_Status, Address, SizeInBytes, MemTypeStr);
    }
  }

  return PSP_Status;
}

/*******************************************************************************/
// BOTH ARMS MATTER. The address AND the size must both divide, which is why a 4-aligned address
// with a 6-byte length is rejected -- the far end of the region would be misaligned.
Bool MM_Verify32Aligned(U64 Address, I64 Size)
{
  Bool IsAligned = FALSE;

  if (Address % sizeof(U32) == 0 && Size % sizeof(U32) == 0) {
    IsAligned = TRUE;
  }

  return IsAligned;
}

/*******************************************************************************/

Bool MM_Verify16Aligned(U64 Address, I64 Size)
{
  Bool IsAligned = FALSE;

  if (Address % sizeof(U16) == 0 && Size % sizeof(U16) == 0) {
    IsAligned = TRUE;
  }

  return IsAligned;
}

/*******************************************************************************/
// THE ONE FUNCTION EVERY MM ADDRESS PATH CALLS FIRST. An empty symbol name means the offset IS
// the address, which is the branch this port's exercises stand on -- a literal constant is the
// same number on the host and in the guest, and a real pointer never is. See docs/CFS_PLAN.md.
//
// A LOOKUP FAILURE LEAVES *ResolvedAddr ALONE, which is a property of the branch and not of the
// return value: OS_SymbolLookup is only added to when it succeeded.
I32 MM_ResolveSymAddr(MM_SymAddr_t *SymAddr, U64 *ResolvedAddr)
{
  I32 OS_Status = OS_SUCCESS;

  /*
  ** NUL terminate the very end of the symbol name string array as a
  ** safety measure
  */
  SymAddr->SymName[CFE_MISSION_MAX_PATH_LEN - 1] = '\0';

  /*
  ** If the symbol name string is a nul string
  ** we use the offset as the absolute address
  */
  if (OS_strnlen(SymAddr->SymName, CFE_MISSION_MAX_PATH_LEN) == 0) {
    *ResolvedAddr = SymAddr->Offset;
  } else {
    /*
    ** If symbol name is not an empty string look it up
    ** using the OSAL API and add the offset if it succeeds
    */
    OS_Status = OS_SymbolLookup(ResolvedAddr, SymAddr->SymName);
    if (OS_Status == OS_SUCCESS) {
      *ResolvedAddr += SymAddr->Offset;
    }
  }

  return OS_Status;
}

// NASA declares this `static uint8 DataArray[FILE_CRC_BUFFER_SIZE]` INSIDE
// MM_ComputeCRCFromFile. A static local is a file-scope object with a function-scoped name, and
// this port hoists those to file scope under the enclosing function's name -- the same thing
// cfe_es_crc.HC does for the two CRC tables, and for the same reason recorded in
// docs/HOLYC_STRUCT_LIMITS.md #12: HolyC scopes a static local's NAME globally, so a bare
// `DataArray` here would be a global that any other file could collide with.
U8 MM_ComputeCRCFromFile_DataArray[FILE_CRC_BUFFER_SIZE];

/*******************************************************************************/
// Compute the CRC of data in a file.
// Operates from the current location of the file pointer to EOF.
//
// THE LOOP CONDITION IS THE RETURN VALUE OF OS_read, so this ends three ways: a zero read is
// end of file and the CRC is handed back; a negative read is an error and is returned INSTEAD
// of writing *CrcPtr; and a short read is simply folded in and the loop goes round again. The
// middle case is the one worth a line -- on an error the caller's CRC is left untouched.
I32 MM_ComputeCRCFromFile(U32 FileHandle, U32 *CrcPtr, U32 TypeCRC)
{
  I32 ByteCntr;
  I32 OS_Status = OS_SUCCESS;
  U32 TempCrc = 0;

  do {
    /*
    ** Read in some data
    */
    ByteCntr = OS_read(FileHandle, MM_ComputeCRCFromFile_DataArray, FILE_CRC_BUFFER_SIZE);

    /*
    ** If we didn't hit end of file on the last read...
    */
    if (ByteCntr > 0) {
      /*
      ** Calculate the CRC based upon the previous CRC calculation
      */
      TempCrc = CFE_ES_CalculateCRC(MM_ComputeCRCFromFile_DataArray, ByteCntr, TempCrc, TypeCRC);
    }

  } while (ByteCntr > 0);

  /*
  ** Check if we broke out of the loop because of an error return
  ** from the OS_read call
  */
  if (ByteCntr < 0) {
    OS_Status = ByteCntr;
  } else {
    *CrcPtr = TempCrc;
  }

  return OS_Status;
}
#endif
