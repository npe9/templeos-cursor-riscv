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
// Translation of NASA's MD/fsw/src/md_dwell_tbl.c -- where MD meets Table Services. Eight
// functions: the validation callback the ground's table load is checked by, the three
// functions under it, the copy into working state, and three ground-commanded edits that go
// through CFE_TBL_GetAddress / CFE_TBL_Modified / CFE_TBL_ReleaseAddress.
//
// THIS IS THE FIRST THING IN THE PORT THAT USES tbl FROM THE OUTSIDE. Everything tbl-related
// up to now was tbl's own code exercised from within its module; here an app registers a
// table, the ground loads it, tbl calls back into MD_TableValidationFunc to ask whether the
// bytes are acceptable, and MD edits the buffer in place through the handle.
//
// VALIDATION COUNTS EVERYTHING BEFORE IT REFUSES ANYTHING. MD_CheckTableEntries walks all 25
// entries, remembers the FIRST error and its index, and keeps counting good/bad/unused past
// it -- so the informational event reports the whole table even when entry 1 is already
// wrong. NASA's comment says so: "Keep counting good,bad,unused, don't exit immediately".
//
// FOUR `#if`s ARE HAND-RESOLVED HERE, AND ONE OF THEM IS A SHAPE HolyC CANNOT EXPRESS AT ALL.
// docs/HOLYC_STRUCT_LIMITS.md #19: `#if <expr>` is unconditionally true in this compiler, so
// every one of these would take its first branch whatever the value was. Both switches are 1
// in this configuration and both values are anchored by check_constants comparing them against
// NASA's header, which is what makes hand-resolving safe rather than a guess:
//
//   MD_INTERFACE_SIGNATURE_OPTION == 1   wraps a mid-function DECLARATION (`uint16
//                                        StringLength;`) and, further down, an `else if`
//                                        CLAUSE in the middle of an if/else chain. A
//                                        preprocessor conditional around one arm of a chain
//                                        has no HolyC spelling even if `#if` worked.
//   MD_INTERFACE_SIGNATURE_OPTION == 1   also wraps the whole of MD_UpdateTableSignature and
//                                        the signature copy in MD_CopyUpdatedTbl.
//   MD_INTERFACE_ENFORCE_DWORD_ALIGN     selects 32-bit alignment checking over 16-bit for a
//                                        4-byte dwell. The value is 1, so the `#else` arm is
//                                        the live one -- and NASA's dead `== 0` arm still
//                                        says `Jam->Payload` where the live code says `Msg->`,
//                                        which is evidence in NASA's own tree that it is
//                                        never compiled.
#ifndef MD_DWELL_TBL_HC
#define MD_DWELL_TBL_HC

// md_eventids.h, the thirteen ids this file raises.
#define MD_ZERO_RATE_TBL_INF_EID       40
#define MD_RESOLVE_ERR_EID             41
#define MD_RANGE_ERR_EID               42
#define MD_TBL_HAS_LEN_ERR_EID         43
#define MD_TBL_ENA_FLAG_EID            44
#define MD_TBL_ALIGN_ERR_EID           45
#define MD_TBL_SIG_LEN_ERR_EID         50
#define MD_DWELL_TBL_INF_EID           52
#define MD_UPDATE_TBL_EN_ERR_EID       53
#define MD_UPDATE_TBL_DWELL_ERR_EID    54
#define MD_UPDATE_TBL_SIG_ERR_EID      55
#define MD_TBL_VAL_NULL_PTR_ERR_EID    63
#define MD_TBL_ENTRY_ERR_EID           75

// MD_TableValidationFunc calls all three before they are defined.
I32 MD_ReadDwellTable(MD_DwellTableLoad_t *TblPtr, U16 *ActiveAddrCountPtr, U16 *SizePtr,
                      U32 *RatePtr);
I32 MD_CheckTableEntries(MD_DwellTableLoad_t *TblPtr, U16 *ErrorEntryArg);
I32 MD_ValidTableEntry(MD_TableLoadEntry_t *TblEntryPtr);

/******************************************************************************/

I32 MD_TableValidationFunc(U8 *TblPtr)
{
  U16 ActiveEntryCount = 0;
  U16 Size = 0;
  U32 Rate = 0;
  I32 Status = CFE_SUCCESS; /* Initialize to valid table */
  MD_DwellTableLoad_t *LocalTblPtr = TblPtr;
  U16 TblErrorEntryIndex = 0; /* Zero-based entry number for error; */
                              /* valid if there is an error.        */
  // NASA declares StringLength inside the `#if MD_INTERFACE_SIGNATURE_OPTION == 1` block, in
  // the middle of the function. Hoisted here because the option is 1 and the declaration is
  // therefore live; see the note at the top of this file.
  U16 StringLength;

  if (TblPtr == NULL) {
    Status = MD_INVALID_ADDR_ERROR;

    CFE_EVS_SendEvent(MD_TBL_VAL_NULL_PTR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Dwell Table rejected because of null table pointer");

    return Status;
  }

  /*
  **  Check for Null Termination of string
  */
  for (StringLength = 0; StringLength < MD_INTERFACE_SIGNATURE_FIELD_LENGTH; StringLength++) {
    if (LocalTblPtr->Signature[StringLength] == '\0')
      break;
  }

  /* Check that Enabled flag has valid value. */
  if ((LocalTblPtr->Enabled != MD_Dwell_States_DISABLED) &&
      (LocalTblPtr->Enabled != MD_Dwell_States_ENABLED)) {
    CFE_EVS_SendEvent(MD_TBL_ENA_FLAG_EID, CFE_EVS_EventType_ERROR,
                      "Dwell Table rejected because value of enable flag (%d) is invalid",
                      LocalTblPtr->Enabled);
    Status = MD_TBL_ENA_FLAG_ERROR;
  }

  // The `else if` NASA wraps in `#if MD_INTERFACE_SIGNATURE_OPTION == 1`. A preprocessor
  // conditional around ONE ARM of an if/else chain has no HolyC spelling at all, working `#if`
  // or not, so the arm is written out because the option is 1.
  else if (StringLength >= MD_INTERFACE_SIGNATURE_FIELD_LENGTH) {
    CFE_EVS_SendEvent(MD_TBL_SIG_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Dwell Table rejected because Signature length was invalid");

    Status = MD_SIG_LEN_TBL_ERROR;
  }

  else {
    /* Read Dwell Table to get entry count, byte size, and dwell rate */
    MD_ReadDwellTable(LocalTblPtr, &ActiveEntryCount, &Size, &Rate);

    /* Validate entry contents */
    Status = MD_CheckTableEntries(LocalTblPtr, &TblErrorEntryIndex);

    if (Status == CFE_SUCCESS) {
      /* Allow ground to uplink a table with 0 delay, but if the table is enabled, report that the table will not
       * be processed */
      if ((LocalTblPtr->Enabled == MD_Dwell_States_ENABLED) && (Rate == 0)) {
        CFE_EVS_SendEvent(
            MD_ZERO_RATE_TBL_INF_EID, CFE_EVS_EventType_INFORMATION,
            "Dwell Table is enabled but no processing will occur for table being loaded (rate is zero)");
      }
    } else if (Status == MD_RESOLVE_ERROR) {
      CFE_EVS_SendEvent(
          MD_RESOLVE_ERR_EID, CFE_EVS_EventType_ERROR,
          "Dwell Table rejected because address (sym='%s'/offset=0x%08X) in entry #%d couldn't be resolved",
          LocalTblPtr->Entry[TblErrorEntryIndex].DwellAddress.SymName,
          LocalTblPtr->Entry[TblErrorEntryIndex].DwellAddress.Offset, TblErrorEntryIndex + 1);
    } else if (Status == MD_INVALID_ADDR_ERROR) {
      CFE_EVS_SendEvent(
          MD_RANGE_ERR_EID, CFE_EVS_EventType_ERROR,
          "Dwell Table rejected because address (sym='%s'/offset=0x%08X) in entry #%d was out of range",
          LocalTblPtr->Entry[TblErrorEntryIndex].DwellAddress.SymName,
          LocalTblPtr->Entry[TblErrorEntryIndex].DwellAddress.Offset, TblErrorEntryIndex + 1);
    } else if (Status == MD_INVALID_LEN_ERROR) {
      CFE_EVS_SendEvent(MD_TBL_HAS_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Dwell Table rejected because length (%d) in entry #%d was invalid",
                        LocalTblPtr->Entry[TblErrorEntryIndex].Length, TblErrorEntryIndex + 1);
    } else /* Status == MD_NOT_ALIGNED_ERROR is only remaining option */ {
      CFE_EVS_SendEvent(MD_TBL_ALIGN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Dwell Table rejected because address (sym='%s'/offset=0x%08X) in entry #%d not properly "
                        "aligned for %d-byte dwell",
                        LocalTblPtr->Entry[TblErrorEntryIndex].DwellAddress.SymName,
                        LocalTblPtr->Entry[TblErrorEntryIndex].DwellAddress.Offset,
                        TblErrorEntryIndex + 1, LocalTblPtr->Entry[TblErrorEntryIndex].Length);
    }

  } /* end else MD_ReadDwellTable */

  return Status;
}

/******************************************************************************/
I32 MD_ReadDwellTable(MD_DwellTableLoad_t *TblPtr, U16 *ActiveAddrCountPtr, U16 *SizePtr,
                      U32 *RatePtr)
{
  /* parameters cannot be NULL - checked by calling function */

  U16 EntryId;
  *ActiveAddrCountPtr = 0;
  *SizePtr = 0;
  *RatePtr = 0;

  for (EntryId = 0;
       (EntryId < MD_INTERFACE_DWELL_TABLE_SIZE) && (TblPtr->Entry[EntryId].Length != 0);
       EntryId++) {
    /* *ActiveAddrCountPtr++; */
    (*ActiveAddrCountPtr)++;
    *SizePtr += TblPtr->Entry[EntryId].Length;
    *RatePtr += TblPtr->Entry[EntryId].Delay;
  } /* end while */

  return CFE_SUCCESS;
}
/******************************************************************************/
I32 MD_CheckTableEntries(MD_DwellTableLoad_t *TblPtr, U16 *ErrorEntryArg)
{
  I32 Status;
  I32 FirstErrorCode = CFE_SUCCESS;
  U16 EntryIndex;
  I32 FirstBadIndex = -1;

  I32 GoodCount = 0;
  I32 BadCount = 0;
  I32 UnusedCount = 0;

  *ErrorEntryArg = 0;

  /* parameters cannot be NULL - checked by calling function */

  /*
  **   Check each Dwell Table entry for valid address range
  */
  for (EntryIndex = 0; EntryIndex < MD_INTERFACE_DWELL_TABLE_SIZE; EntryIndex++) {
    Status = MD_ValidTableEntry(&TblPtr->Entry[EntryIndex]);

    if (Status == CFE_SUCCESS) {
      if (TblPtr->Entry[EntryIndex].Length == 0) {
        /*
        ** Stop reading through the table when the entry length is
        ** zero, remaining entries count as unused
        */
        break;
      } else {
        GoodCount++;
      }
    } else {
      /* Status != CFE_SUCCESS */
      BadCount++;
      if (FirstBadIndex == -1) {
        FirstBadIndex = EntryIndex;
        *ErrorEntryArg = FirstBadIndex;
        FirstErrorCode = Status;
        /* Keep counting good,bad,unused, don't exit immediately */

        CFE_EVS_SendEvent(MD_TBL_ENTRY_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Table entry %d failed with status 0x%08X", EntryIndex, Status);
      }
    }
  }

  UnusedCount = MD_INTERFACE_DWELL_TABLE_SIZE - EntryIndex;

  /*
  ** Generate informational event with error totals
  */
  CFE_EVS_SendEvent(MD_DWELL_TBL_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "MD Dwell Tbl verify results: good = %d, bad = %d, unused = %d", GoodCount,
                    BadCount, UnusedCount);

  return FirstErrorCode;
}

/******************************************************************************/
I32 MD_ValidTableEntry(MD_TableLoadEntry_t *TblEntryPtr)
{
  I32 Status = MD_ERROR;
  U16 DwellLength = 0;
  U64 ResolvedAddr = 0;

  DwellLength = TblEntryPtr->Length;

  if (DwellLength == 0) {
    Status = CFE_SUCCESS;
  } else {
    if (MD_ResolveSymAddr(&TblEntryPtr->DwellAddress, &ResolvedAddr) != TRUE) {
      /* Symbol was non-null AND was not in Symbol Table */
      Status = MD_RESOLVE_ERROR;
    }

    else if (MD_ValidAddrRange(ResolvedAddr, DwellLength) != TRUE) {
      /* Address is in invalid range  */
      Status = MD_INVALID_ADDR_ERROR;
    } else if (MD_ValidFieldLength(DwellLength) != TRUE) {
      Status = MD_INVALID_LEN_ERROR;
    }
    // MD_INTERFACE_ENFORCE_DWORD_ALIGN is 1, so this is NASA's `#else` arm -- 32-bit alignment
    // for a 4-byte dwell. The dead `== 0` arm checks 16-bit instead.
    else if ((DwellLength == 4) && MD_Verify32Aligned(ResolvedAddr, DwellLength) != TRUE) {
      Status = MD_NOT_ALIGNED_ERROR;
    } else if ((DwellLength == 2) && MD_Verify16Aligned(ResolvedAddr, DwellLength) != TRUE) {
      Status = MD_NOT_ALIGNED_ERROR;
    } else {
      Status = CFE_SUCCESS;
    }

  } /* end else */

  return Status;
}

/******************************************************************************/
U0 MD_CopyUpdatedTbl(MD_DwellTableLoad_t *MD_LoadTablePtr, U8 TblIndex)
{
  U8 EntryIndex;
  U64 ResolvedAddr = 0;
  MD_TableLoadEntry_t *ThisLoadEntry = NULL;
  MD_DwellPacketControl_t *LocalControlStruct = &MD_AppData.MD_DwellTables[TblIndex];

  /* Null check on MD_LoadTablePtr not necessary - table passed validation */

  /* Copy 'Enabled' field from load structure to internal control structure. */
  LocalControlStruct->Enabled = MD_LoadTablePtr->Enabled;

  /* Copy 'Signature' field from load structure to internal control structure. */
  // MD_INTERFACE_SIGNATURE_OPTION is 1.
  StrNCpy(LocalControlStruct->Signature, MD_LoadTablePtr->Signature,
          MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1);

  /* Ensure that resulting string is null-terminated */
  LocalControlStruct->Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1] = '\0';

  /* For each row in the table load, */
  /* copy length, delay, and address fields from load structure to */
  /* internal control structure. */
  for (EntryIndex = 0; EntryIndex < MD_INTERFACE_DWELL_TABLE_SIZE; EntryIndex++) {
    /* Get ResolvedAddr & insert in local control structure */

    ThisLoadEntry = &MD_LoadTablePtr->Entry[EntryIndex];

    MD_ResolveSymAddr(&ThisLoadEntry->DwellAddress, &ResolvedAddr);

    MD_AppData.MD_DwellTables[TblIndex].Entry[EntryIndex].ResolvedAddress = ResolvedAddr;
    MD_AppData.MD_DwellTables[TblIndex].Entry[EntryIndex].Length = ThisLoadEntry->Length;
    MD_AppData.MD_DwellTables[TblIndex].Entry[EntryIndex].Delay = ThisLoadEntry->Delay;

  } /* end for loop */

  /* Update Dwell Table Control Info, used to process dwell packets */
  MD_UpdateDwellControlInfo(TblIndex);
}

/******************************************************************************/
I32 MD_UpdateTableEnabledField(U16 TableIndex, U16 FieldValue)
{
  I32 Status = CFE_SUCCESS;
  MD_DwellTableLoad_t *MD_LoadTablePtr = NULL;

  Status = CFE_TBL_GetAddress(&MD_LoadTablePtr, MD_AppData.MD_TableHandle[TableIndex]);

  if ((Status != CFE_SUCCESS) && (Status != CFE_TBL_INFO_UPDATED)) {
    CFE_EVS_SendEvent(MD_UPDATE_TBL_EN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "MD_UpdateTableEnabledField, TableIndex %d: CFE_TBL_GetAddress Returned 0x%08x",
                      TableIndex, Status);
  } else {
    MD_LoadTablePtr->Enabled = FieldValue;

    CFE_TBL_Modified(MD_AppData.MD_TableHandle[TableIndex]);

    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[TableIndex]);

    Status = CFE_SUCCESS;
  }

  return Status;
}

/******************************************************************************/

// NASA TAKES NewDwellAddress BY VALUE, AND THE TRANSLATION TAKES A POINTER. MD_SymAddr_t is 72
// bytes and docs/HOLYC_STRUCT_LIMITS.md #26 measures that a class parameter passed by value
// carries only its FIRST EIGHT -- the rest arrives as the next argument's value, silently. This
// is the first place in the port to reach that cliff, and tools/cfs/check_struct_copy.py now
// refuses the by-value form outright, so the deviation is enforced rather than remembered.
// Recorded in check_signatures.py's DEVIATIONS with this reason.
//
// The assignment below is then `EntryPtr->DwellAddress = *NewDwellAddress`, and THAT form is
// whole: tests/exec/cases/e_struct_copy_into_slot.hc measures `ptr->member = *p` as a complete
// copy, where `arr[i] = s` and `*ptr = s` are the two broken destinations (#21).
I32 MD_UpdateTableDwellEntry(U16 TableIndex, U16 EntryIndex, U16 NewLength, U16 NewDelay,
                             MD_SymAddr_t *NewDwellAddress)
{
  I32 Status = CFE_SUCCESS;
  MD_DwellTableLoad_t *MD_LoadTablePtr = NULL;
  MD_TableLoadEntry_t *EntryPtr = NULL;

  /* Get pointer to Table */
  Status = CFE_TBL_GetAddress(&MD_LoadTablePtr, MD_AppData.MD_TableHandle[TableIndex]);

  if ((Status != CFE_SUCCESS) && (Status != CFE_TBL_INFO_UPDATED)) {
    CFE_EVS_SendEvent(MD_UPDATE_TBL_DWELL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "MD_UpdateTableDwellEntry, TableIndex %d: CFE_TBL_GetAddress Returned 0x%08x",
                      TableIndex, Status);
  } else {
    /* Get pointer to specific entry */
    EntryPtr = &MD_LoadTablePtr->Entry[EntryIndex];

    /* Copy new numerical values to Table Services buffer */
    EntryPtr->Length = NewLength;
    EntryPtr->Delay = NewDelay;

    /* Copy symbol name to Table Services buffer */
    EntryPtr->DwellAddress = *NewDwellAddress;

    /* Notify Table Services that buffer was modified */
    CFE_TBL_Modified(MD_AppData.MD_TableHandle[TableIndex]);

    /* Release access to Table Services buffer */
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[TableIndex]);

    Status = CFE_SUCCESS;
  }

  return Status;
}

/******************************************************************************/
// Present because MD_INTERFACE_SIGNATURE_OPTION is 1; NASA wraps the whole function in the
// `#if`. NewSignature is `const char[MD_INTERFACE_SIGNATURE_FIELD_LENGTH]` in NASA's
// declaration, which is a POINTER in C and is written as one here.
I32 MD_UpdateTableSignature(U16 TableIndex, U8 *NewSignature)
{
  I32 Status = CFE_SUCCESS;
  MD_DwellTableLoad_t *MD_LoadTablePtr = NULL;

  /* Get pointer to Table */
  Status = CFE_TBL_GetAddress(&MD_LoadTablePtr, MD_AppData.MD_TableHandle[TableIndex]);

  if ((Status != CFE_SUCCESS) && (Status != CFE_TBL_INFO_UPDATED)) {
    CFE_EVS_SendEvent(MD_UPDATE_TBL_SIG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "MD_UpdateTableSignature, TableIndex %d: CFE_TBL_GetAddress Returned 0x%08x",
                      TableIndex, Status);
  } else {
    /* Copy Signature to dwell structure */
    StrNCpy(MD_LoadTablePtr->Signature, NewSignature,
            MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1);

    MD_LoadTablePtr->Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1] = '\0';

    /* Notify Table Services that buffer was modified */
    CFE_TBL_Modified(MD_AppData.MD_TableHandle[TableIndex]);

    /* Release access to Table Services buffer */
    CFE_TBL_ReleaseAddress(MD_AppData.MD_TableHandle[TableIndex]);

    Status = CFE_SUCCESS;
  }

  return Status;
}
#endif
