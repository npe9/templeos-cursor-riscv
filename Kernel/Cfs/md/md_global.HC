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
// MEMORY DWELL'S STATE -- the translation of NASA's fsw/src/md_app.h, plus the global
// instance. Same arrangement as cfe_es_global.HC, cfe_sb_global.HC, cfe_evs_global.HC and
// cfe_tbl_global.HC: NASA declares MD_AppData `extern` in md_app.h and defines it in
// md_app.c, and the translation defines it here beside its type so the global does not move
// when a different implementation file happens to be gated first.
//
// THE CONTROL STRUCTURE IS NOT THE TABLE. A dwell table arrives from the ground as
// MD_DwellTableLoad_t -- symbol names and offsets, 2,040 bytes of it. MD copies it into an
// MD_DwellPacketControl_t, which holds RESOLVED addresses and the running counters the dwell
// loop needs. MD_CopyUpdatedTbl is the one that crosses between them, and the two types are
// deliberately not interchangeable: one is an interface, the other is working state.
//
// ResolvedAddress IS A cpuaddr and that is the single field in this port whose VALUE cannot
// be compared across the two halves of the transcript. docs/CFS_PLAN.md records the
// consequence and the answer.
#ifndef MD_GLOBAL_HC
#define MD_GLOBAL_HC

#define MD_DWELL_TABLE_BASENAME "DWELL_TABLE"

// NASA wakes MD every second whether a message arrived or not, so the dwell loop runs on the
// timeout rather than on traffic.
#define MD_SB_TIMEOUT 1000

// Table validation results. EVERY ONE OF THESE NEEDS THE (I32) POSTFIX CAST: they are
// high-bit values compared against a 32-bit status, and without the cast the literal is a
// positive 64-bit integer that no comparison can ever match. Thirty cFE constants had exactly
// this defect and the comparisons against them were dead code -- see the note in
// docs/CFS_PLAN.md and docs/HOLYC_STRUCT_LIMITS.md.
#define MD_ERROR               -1
#define MD_TBL_ENA_FLAG_ERROR  0xc0000001(I32)
#define MD_ZERO_RATE_TBL_ERROR 0xc0000002(I32)
#define MD_RESOLVE_ERROR       0xc0000003(I32)
#define MD_INVALID_ADDR_ERROR  0xc0000004(I32)
#define MD_INVALID_LEN_ERROR   0xc0000005(I32)
#define MD_NOT_ALIGNED_ERROR   0xc0000006(I32)
#define MD_SIG_LEN_TBL_ERROR   0xc0000007(I32)

// MD_SearchCmdHndlrTbl's "no such command code".
#define MD_BAD_CMD_CODE -1

/*******************************************************************************/
// ONE DWELL SPECIFICATION, RESOLVED. The ground's symbol name is gone by the time a
// specification reaches this type -- MD_ResolveSymAddr has already turned it into a number.
class MD_DwellControlEntry_t
{
  U16 Length;
  U16 Delay;
  // ResolvedAddress is a cpuaddr and so 8-aligned, leaving four bytes after the two U16s.
  U8 _pad0[4];
  U64 ResolvedAddress; // cpuaddr
};

// ONE DWELL STREAM'S WORKING STATE. Rate is the SUM of the individual delays, computed by
// MD_UpdateDwellControlInfo rather than commanded, and Countdown walks it down to zero.
// Filler is NASA's own name for its alignment field, not this port's padding.
class MD_DwellPacketControl_t
{
  U16 Enabled;
  U16 AddrCount;
  U32 Rate;
  U32 Countdown;
  U16 PktOffset;
  U16 CurrentEntry;
  U16 DataSize;
  U16 Filler; // NASA's own name for it
  // Entry[] is 8-aligned through ResolvedAddress, and the run above is 20 bytes.
  U8 _pad0[4];
  MD_DwellControlEntry_t Entry[MD_INTERFACE_DWELL_TABLE_SIZE];
  // Present because MD_INTERFACE_SIGNATURE_OPTION is 1 -- see md_msg.HC.
  U8 Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH];
};

/*******************************************************************************/
// THE WHOLE APPLICATION, in one object. Four dwell streams, four outgoing packets, four cFE
// table handles and the names they were registered under.
class MD_AppData_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  MD_HkTlm_t HkPkt;
  // CmdPipe is a resource id and so 4-aligned; the two counters plus a 68-byte HkPkt end at 70.
  U8 _pad0[2];
  U32 CmdPipe; // CFE_SB_PipeId_t
  // MD_DwellTables is 8-aligned through MD_DwellControlEntry_t.
  U8 _pad1[4];
  MD_DwellPacketControl_t MD_DwellTables[MD_INTERFACE_NUM_DWELL_TABLES];
  MD_DwellPkt_t MD_DwellPkt[MD_INTERFACE_NUM_DWELL_TABLES];
  U32 RunStatus;
  U8 MD_TableName[MD_INTERFACE_NUM_DWELL_TABLES][CFE_MISSION_TBL_MAX_NAME_LENGTH + 1];
  I16 MD_TableHandle[MD_INTERFACE_NUM_DWELL_TABLES]; // CFE_TBL_Handle_t
};

// NASA's command handler table record: a command code and the message length it must have.
// md_dispatch.c is the only thing that reads it.
class MD_CmdHandlerTblRec_t
{
  U32 CmdCode;
  U32 ExpectedLength;
};

/*******************************************************************************/
// The global. NASA: `MD_AppData_t MD_AppData;` at the top of md_app.c.
MD_AppData_t MD_AppData;
#endif
