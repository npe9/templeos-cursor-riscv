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
// Translation of NASA's MD/fsw/src/md_utils.c -- the leaf of the app, and the first cFS app
// source in this port. Nine functions: one bitmask reader, one summariser, five validators
// and the address resolver everything else depends on.
//
// WHY THIS FILE FIRST. module_deps.py --fresh says MD is fully acyclic in this configuration
// and names this as the leaf, so it is gated with no stand-ins at all. The order it gives is
// md_utils -> md_dwell_pkt -> md_dwell_tbl -> md_cmds -> md_app -> md_dispatch, which is NOT
// CMake's APP_SRC_FILES order.
//
// MD_ResolveSymAddr IS THE ONE THAT MATTERS. Its empty-SymName branch returns the caller's
// Offset verbatim as an absolute address, with no symbol lookup -- which is what lets the
// differential transcript exercise MD at all, because a literal offset is the same number on
// a host process and a QEMU guest while a looked-up symbol's address is not.
#ifndef MD_UTILS_HC
#define MD_UTILS_HC

/******************************************************************************/

Bool MD_TableIsInMask(I16 TableId, U16 TableMask)
{
  U16 LocalMask = TableMask;
  Bool Status = FALSE;

  /* Shift TableId - 1 times */
  if (TableId - 1) {
    LocalMask = LocalMask >> (TableId - 1);
  }

  /* If result is odd, */
  /* then table is in mask. */
  if ((LocalMask & 1(U16)) == 1(U16))
    Status = TRUE;

  return Status;
}

/******************************************************************************/

U0 MD_UpdateDwellControlInfo(U16 TableIndex)
{
  /* Initialize local data */
  U16 EntryIndex = 0;
  U16 NumDwellAddresses = 0;
  U16 NumDwellDataBytes = 0;
  U32 NumDwellDelayCounts = 0;
  MD_DwellPacketControl_t *TblPtr = &MD_AppData.MD_DwellTables[TableIndex];

  /*
  ** Sum Address Count, Data Size, and Rate from Dwell Entries
  */
  while ((EntryIndex < MD_INTERFACE_DWELL_TABLE_SIZE) && (TblPtr->Entry[EntryIndex].Length != 0)) {
    NumDwellAddresses++;
    NumDwellDataBytes += TblPtr->Entry[EntryIndex].Length;
    NumDwellDelayCounts += TblPtr->Entry[EntryIndex].Delay;
    EntryIndex++;
  }

  /* Copy totals to dwell control structure. */
  TblPtr->AddrCount = NumDwellAddresses;
  TblPtr->DataSize = NumDwellDataBytes;
  TblPtr->Rate = NumDwellDelayCounts;
}

/******************************************************************************/

/*
**  Data Validation Functions
*/
/******************************************************************************/
Bool MD_ValidEntryId(U16 EntryId)
{
  Bool IsValid = FALSE;

  if ((EntryId >= 1) && (EntryId <= MD_INTERFACE_DWELL_TABLE_SIZE)) {
    /* validate  value (1..MD_INTERFACE_DWELL_TABLE_SIZE ) */
    IsValid = TRUE;
  }

  return IsValid;
}

/******************************************************************************/

Bool MD_ValidAddrRange(U64 Addr, U32 Size)
{
  Bool IsValid = FALSE;

  if (CFE_PSP_MemValidateRange(Addr, Size, CFE_PSP_MEM_ANY) == OS_SUCCESS) {
    IsValid = TRUE;
  }

  return IsValid;
}

/******************************************************************************/
Bool MD_ValidTableId(U16 TableId)
{
  Bool IsValid = FALSE;

  if ((TableId >= 1) && (TableId <= MD_INTERFACE_NUM_DWELL_TABLES)) {
    IsValid = TRUE;
  }

  return IsValid;
}

/******************************************************************************/

Bool MD_ValidFieldLength(U16 FieldLength)
{
  Bool IsValid = FALSE;

  if ((FieldLength == 0) || (FieldLength == 1) || (FieldLength == 2) || (FieldLength == 4)) {
    IsValid = TRUE;
  }

  return IsValid;
}

/******************************************************************************/

Bool MD_Verify32Aligned(U64 Address, U32 Size)
{
  Bool IsAligned;

  if (Address % sizeof(U32) != 0) {
    IsAligned = FALSE;
  } else if (Size % sizeof(U32) != 0) {
    IsAligned = FALSE;
  } else {
    IsAligned = TRUE;
  }

  return IsAligned;
}

/******************************************************************************/

Bool MD_Verify16Aligned(U64 Address, U32 Size)
{
  Bool IsAligned;

  if (Address % sizeof(U16) != 0) {
    IsAligned = FALSE;
  } else if (Size % sizeof(U16) != 0) {
    IsAligned = FALSE;
  } else {
    IsAligned = TRUE;
  }

  return IsAligned;
}

/******************************************************************************/

Bool MD_ResolveSymAddr(MD_SymAddr_t *SymAddr, U64 *ResolvedAddr)
{
  Bool Valid;
  I32 OS_Status;

  /*
  ** NUL terminate the very end of the symbol name string array as a
  ** safety measure
  */
  // SymAddr->SymName[CFE_MISSION_MAX_PATH_LEN - 1] = '\0';

  /*
  ** If the symbol name string is a nul string
  ** we use the offset as the absolute address
  */
  if (StrLen(SymAddr->SymName) == 0) {
    *ResolvedAddr = SymAddr->Offset;
    Valid = TRUE;
  } else {
    /*
    ** If symbol name is not an empty string look it up
    ** using the OSAL API and add the offset if it succeeds
    */
    OS_Status = OS_SymbolLookup(ResolvedAddr, SymAddr->SymName);
    if (OS_Status == OS_SUCCESS) {
      *ResolvedAddr += SymAddr->Offset;
      Valid = TRUE;
    } else
      Valid = FALSE;
  }
  return Valid;
}
#endif
