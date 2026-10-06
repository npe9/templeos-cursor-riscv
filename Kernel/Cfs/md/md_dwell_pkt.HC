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
// Translation of NASA's MD/fsw/src/md_dwell_pkt.c -- the part of Memory Dwell that actually
// reads memory. Four functions: the loop, the one read, the send, and a three-line reset.
//
// THE DWELL LOOP IS A COUNTDOWN PER TABLE, not a timer per entry. Every wakeup decrements
// Countdown; when it hits zero the current entry is read, Countdown is reloaded from THAT
// entry's Delay, and the next entry becomes current. A Delay of zero therefore means "read the
// next one in the same wakeup", which is why the collection is a `while (Countdown == 0)` and
// not an `if` -- a table of zero delays reads every entry and sends in one call. That also
// means NASA's sum-of-delays Rate can be zero while entries exist, and the `Rate > 0` guard
// above is what stops that table being processed at all.
//
// THE PACKET SHRINKS TO FIT. MD_SendDwellPkt sets the message size to
// sizeof(MD_DwellPkt_t) - 25*4 + DataSize, i.e. the fixed part plus only the bytes actually
// dwelled, so a table reading four bytes sends a 60-byte packet rather than a 156-byte one.
//
// THE SIGNATURE COPY IS NASA'S strncpy, PADDING AND ALL. CfsStr.HC's StrNCpy reproduces
// strncpy exactly -- it zero-fills the remainder of the destination and does NOT terminate
// when the source is longer than n. Both halves of the transcript dump the Signature field, so
// a MemCpy here instead of a bounded copy would show up as the bytes AFTER the terminator
// differing, which is precisely the kind of difference a "looks fine" copy hides.
#ifndef MD_DWELL_PKT_HC
#define MD_DWELL_PKT_HC

// md_dwell_pkt.h's anonymous enum. NOTE THE NAMES HAVE NO MD_ PREFIX -- that is NASA's, not a
// transcription slip, and it is why tools/cfs/check_constants.py needs them named explicitly:
// its candidate filter is ^(CFE_|OS_|OSAL_|MD_)\w+$ and these four match none of it.
#define ONE_BYTE_MEM_ADDR_READ_ERR   -1
#define TWO_BYTE_MEM_ADDR_READ_ERR   -2
#define FOUR_BYTE_MEM_ADDR_READ_ERR  -3
#define INVALID_DWELL_ADDR_LEN       -4

// md_eventids.h, the one id this file raises.
#define MD_DWELL_LOOP_GET_DWELL_DATA_ERR_EID 70

// MD_DwellLoop calls both of these before they are defined.
I32 MD_GetDwellData(U16 TblIndex, U16 EntryIndex);
U0 MD_SendDwellPkt(U16 TableIndex);

/******************************************************************************/

I32 MD_DwellLoop(MD_Wakeup_t *Msg)
{
  I32 Result;
  I32 Status;
  U16 TblIndex;
  U16 EntryIndex;
  U16 NumDwellAddresses;
  MD_DwellPacketControl_t *TblPtr = NULL;

  Status = CFE_SUCCESS;

  /* Check each dwell table */
  for (TblIndex = 0; TblIndex < MD_INTERFACE_NUM_DWELL_TABLES; TblIndex++) {
    TblPtr = &MD_AppData.MD_DwellTables[TblIndex];
    NumDwellAddresses = TblPtr->AddrCount;

    /* Process enabled dwell tables */
    if ((TblPtr->Enabled == MD_Dwell_States_ENABLED) && (TblPtr->Rate > 0)) {
      /*
      ** Handle special case that dwell pkt is already full because
      ** pkt size was shortened after data had been written to the pkt.
      */

      if (TblPtr->CurrentEntry >= NumDwellAddresses) {
        MD_SendDwellPkt(TblIndex);

        /* Initialize CurrentEntry index */
        TblPtr->CurrentEntry = 0;
        TblPtr->PktOffset = 0;
        TblPtr->Countdown = TblPtr->Entry[NumDwellAddresses - 1].Delay;
      }

      else
      /*
      ** Handle nominal processing
      */
      {
        /* Decrement counter */
        TblPtr->Countdown--;

        /* Check if it's time to collect data */
        while (TblPtr->Countdown == 0) {
          EntryIndex = TblPtr->CurrentEntry;

          /* Read data for next address and write it to dwell pkt */
          Result = MD_GetDwellData(TblIndex, EntryIndex);

          if (Result != CFE_SUCCESS) {
            /* Send error event message */
            CFE_EVS_SendEvent(MD_DWELL_LOOP_GET_DWELL_DATA_ERR_EID, CFE_EVS_EventType_ERROR,
                              "Dwell Table failed to read entry %d in table %d ", EntryIndex,
                              TblIndex);
            /* Don't exit here yet, still need to increment counters or send the packet */
            Status = Result;
          }

          /* Check if the dwell pkt is now full */
          if (EntryIndex == NumDwellAddresses - 1)

          /* Case:  Just filled last active entry of dwell table */
          {
            /*
            ** Send dwell packet
            */

            MD_SendDwellPkt(TblIndex);

            /*
            ** Assign control values to cause dwell processing to
            ** continue at beginning of dwell control structure.
            */

            /* Reset countdown timer based on current Delay field */
            TblPtr->Countdown = TblPtr->Entry[EntryIndex].Delay;

            /* Initialize CurrentEntry index */
            TblPtr->CurrentEntry = 0;
            TblPtr->PktOffset = 0;
          }

          else
          /* Case: There are more addresses to read for current pkt.*/
          {
            /*
            ** Assign control values to cause dwell processing to
            ** continue at next entry in dwell control structure.
            */

            /* Reset countdown timer based on current Delay field */
            TblPtr->Countdown = TblPtr->Entry[EntryIndex].Delay;

            /* Increment CurrentEntry index */
            TblPtr->CurrentEntry++;
          }

        } /* end while Countdown == 0 */

      } /* end else handle nominal processing */

    } /* end if current dwell stream enabled */

  } /* end for each dwell table */
  return Status;
}

/******************************************************************************/

I32 MD_GetDwellData(U16 TblIndex, U16 EntryIndex)
{
  U8 NumBytes = 0;      /* Num of bytes to read */
  U32 MemReadVal = 0;   /* 1-, 2-, or 4-byte value */
  MD_DwellPacketControl_t *TblPtr = &MD_AppData.MD_DwellTables[TblIndex];
  I32 Status = CFE_SUCCESS;
  U64 DwellAddress;     /* dwell address */

  /* How many bytes to read?*/
  NumBytes = TblPtr->Entry[EntryIndex].Length;

  /* fetch data pointed to by this address */
  DwellAddress = TblPtr->Entry[EntryIndex].ResolvedAddress;

  // NASA WRITES `(uint8 *)&MemReadVal` AND `(uint16 *)&MemReadVal` HERE, and the casts are
  // not needed in HolyC -- not because HolyC is lax, but because the width of the write is
  // decided by the CALLEE's declared parameter type, which is uint8 */uint16 */uint32 * in
  // NASA's cfe_psp_memaccess_api.h and U8 */U16 */U32 * in the driver's stubs. Measured with a
  // four-line probe: preset MemReadVal to 0xFFFFFFFF, call the U8 * form, and it reads back
  // 0xFFFFFFAB -- one byte written, three untouched, which is exactly what NASA's cast buys.
  // MemReadVal is zeroed above, so the upper bytes of a 1- or 2-byte dwell stay zero, and the
  // MemCpy below takes only NumBytes of it anyway.
  switch (NumBytes) {
    case 1:
      if (CFE_PSP_MemRead8(DwellAddress, &MemReadVal) != CFE_PSP_SUCCESS) {
        Status = ONE_BYTE_MEM_ADDR_READ_ERR;
      }
      break;
    case 2:
      if (CFE_PSP_MemRead16(DwellAddress, &MemReadVal) != CFE_PSP_SUCCESS) {
        Status = TWO_BYTE_MEM_ADDR_READ_ERR;
      }
      break;
    case 4:
      if (CFE_PSP_MemRead32(DwellAddress, &MemReadVal) != CFE_PSP_SUCCESS) {
        Status = FOUR_BYTE_MEM_ADDR_READ_ERR;
      }
      break;
    default:
      /* Invalid dwell length */
      /* Shouldn't ever get here unless length value was corrupted. */
      Status = INVALID_DWELL_ADDR_LEN;
      break;
  }

  /* If value was read successfully, copy value to dwell packet. */
  /* Wouldn't want to copy, if say, there was an invalid length & we */
  /* didn't read. */
  if (Status == CFE_SUCCESS) {
    MemCpy(&MD_AppData.MD_DwellPkt[TblIndex].Payload.Data[TblPtr->PktOffset], &MemReadVal,
           NumBytes);
  }

  /* Update write location in dwell packet */
  TblPtr->PktOffset += NumBytes;

  return Status;
}

/******************************************************************************/

U0 MD_SendDwellPkt(U16 TableIndex)
{
  U16 DwellPktSize = 0; /* Dwell Packet Size, in bytes */

  /* Assign pointers to structures */
  MD_DwellPacketControl_t *TblPtr = &MD_AppData.MD_DwellTables[TableIndex];
  MD_DwellPkt_t *PktPtr = &MD_AppData.MD_DwellPkt[TableIndex];

  /*
  ** Assign packet fields.
  */
  PktPtr->Payload.TableId = TableIndex + 1;
  PktPtr->Payload.AddrCount = TblPtr->AddrCount;
  PktPtr->Payload.Rate = TblPtr->Rate;
  // MD_INTERFACE_SIGNATURE_OPTION is 1, so this pair is compiled. Written out rather than
  // guarded: docs/HOLYC_STRUCT_LIMITS.md #19 -- `#if <expr>` is unconditionally true here, so
  // an `#if` would take this branch whatever the value was. The value is anchored instead, by
  // check_constants comparing MD_INTERFACE_SIGNATURE_OPTION against NASA's header.
  StrNCpy(PktPtr->Payload.Signature, TblPtr->Signature,
          MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1);
  /* Make sure string is null-terminated. */
  PktPtr->Payload.Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH - 1] = '\0';
  PktPtr->Payload.ByteCount = TblPtr->DataSize;

  /*
  ** Set packet length in header.
  */

  DwellPktSize = sizeof(MD_DwellPkt_t) - MD_INTERFACE_DWELL_TABLE_SIZE * 4 + TblPtr->DataSize;

  // CFE_MSG_PTR(x) is NASA's macro for &x.Msg -- written out, as it is in cfe_tbl_task.HC.
  CFE_MSG_SetSize(&PktPtr->TelemetryHeader.Msg, DwellPktSize);

  /*
  ** Send dwell telemetry packet.
  */
  CFE_SB_TimeStampMsg(&PktPtr->TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&PktPtr->TelemetryHeader.Msg, TRUE);
}

/******************************************************************************/

U0 MD_StartDwellStream(U16 TableIndex)
{
  MD_AppData.MD_DwellTables[TableIndex].Countdown = 1;
  MD_AppData.MD_DwellTables[TableIndex].CurrentEntry = 0;
  MD_AppData.MD_DwellTables[TableIndex].PktOffset = 0;
}
#endif
