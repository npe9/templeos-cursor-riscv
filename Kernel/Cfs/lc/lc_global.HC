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
// LIMIT CHECKER'S STATE -- the types and globals from NASA's fsw/src/lc_app.h.
//
// LC KEEPS ITS STATE IN TWO PIECES AND THE SPLIT IS THE DESIGN: LC_OperData_t is NASA's comment
// "The operational data is not saved to the CDS", LC_AppData_t is "saved and restored from the CDS
// when the app is configured to use it". So the 9,336-byte structure with the table pointers, the
// handles and the hash table is rebuilt every boot, and the 24 bytes of counters and the current
// state survive a processor reset. CS had one AppData and put its CDS bytes in a six-byte buffer;
// LC stores a whole struct, which is why LC_APPDATA_CDSNAME exists.
//
// ### THE HASH TABLE IS THE REASON LC IS NOT O(watchpoints) PER PACKET
//
// LC subscribes to every MsgId its watchpoint table names and has to answer, for each arriving
// packet, "which watchpoints read this message?" -- up to 176 of them. NASA's answer is a
// 256-entry table indexed by the LOW BYTE OF THE MSGID (LC_HASH_TABLE_MASK is 0x00FF), each entry
// a linked list of MsgIds that hash there, each of those carrying a linked list of watchpoint
// indices.
//
// AND BOTH LISTS ARE ALLOCATED OUT OF FIXED ARRAYS IN THIS SAME STRUCT, not from a heap:
// MessageLinks[176] and WatchPtLinks[176]. There are at most 176 watchpoints, so at most 176 of
// each link can ever be needed, and LC never calls an allocator for them. That is what makes
// LC_OperData_t 9 KB and what makes the whole mechanism analysable: no allocation on the packet
// path, and a bound that is a table size rather than a hope.
//
// LC_WDT_SEARCH_PERF_ID in lc_perfids.HC brackets exactly this lookup -- the second performance
// marker in an app whose predecessors had one each, because this is the cost that has to be
// measurable on the ground.
#ifndef LC_GLOBAL_HC
#define LC_GLOBAL_HC

#include "lc_msg.HC"
#include "lc_tbl.HC"

// --- lc_app.h's own constants -----------------------------------------------------------------

// The three CDS areas. LC stores its results tables AND its application data, where CS stored six
// bytes of state.
#define LC_WRT_CDSNAME     "LC_CDS_WRT"
#define LC_ART_CDSNAME     "LC_CDS_ART"
#define LC_APPDATA_CDSNAME "LC_CDS_AppData"

#define LC_PIPE_NAME "LC_CMD_PIPE"

// THE TWENTY-THREE TableResults BITS, which are a RECORD OF HOW LC CAME UP rather than a status.
// LC's init has to cope with: a CDS that exists, one that does not, a results table that was
// restored, one that was defaulted, and a definition table that was critical or not -- and the
// combination determines whether LC trusts what it restored. Each bit is set as that step
// happens, and lc_app.c reports the whole word in one event. A single enum could not say "CDS
// enabled AND created AND the WRT came from the CDS but the ADT was defaulted".
#define LC_CDS_ENABLED  0x00000001
#define LC_CDS_CREATED  0x00000002
#define LC_CDS_RESTORED 0x00000004
#define LC_CDS_UPDATED  0x00000008

#define LC_WRT_DEFAULT_DATA 0x00000010
#define LC_WRT_CDS_CREATED  0x00000020
#define LC_WRT_CDS_RESTORED 0x00000040
#define LC_WRT_TBL_CREATED  0x00000080

#define LC_ART_DEFAULT_DATA 0x00000100
#define LC_ART_CDS_CREATED  0x00000200
#define LC_ART_CDS_RESTORED 0x00000400
#define LC_ART_TBL_CREATED  0x00000800

#define LC_APP_DEFAULT_DATA 0x00001000
#define LC_APP_CDS_CREATED  0x00002000
#define LC_APP_CDS_RESTORED 0x00004000

#define LC_WDT_DEFAULT_TBL  0x00010000
#define LC_WDT_CRITICAL_TBL 0x00020000
#define LC_WDT_TBL_RESTORED 0x00040000
#define LC_WDT_NOT_CRITICAL 0x00080000

#define LC_ADT_DEFAULT_TBL  0x00100000
#define LC_ADT_CRITICAL_TBL 0x00200000
#define LC_ADT_TBL_RESTORED 0x00400000
#define LC_ADT_NOT_CRITICAL 0x00800000

// NASA: "Wakes up LC every 1 second for routine maintenance whether a message was received or
// not." The same shape as CS_WAKEUP_TIMEOUT, and the same consequence for an exercise: on a real
// pipe the timeout arm is "no action", so nothing ends LC_AppMain's loop.
#define LC_SB_TIMEOUT 1000

// The hash table's size and the mask that indexes it. NASA's comment is "presumes MessageID as
// hash function input", and the mask being 0x00FF with 256 entries is what makes the hash the low
// byte of the id and nothing more.
#define LC_HASH_TABLE_ENTRIES 256
#define LC_HASH_TABLE_MASK    0x00FF

/*******************************************************************************/
// A watchpoint-index link. 16 bytes.
//
// NASA DECLARES `uint16 Spare` AND STILL NEEDS FOUR MORE BYTES OF PADDING. The struct is
// 8-aligned because of the pointer, so after Next(8) + WatchIndex(2) + Spare(2) = 12 the C
// compiler pads to 16. `Spare` is NASA's own alignment member and the `_pad0[4]` is the tail the
// C adds; both are here, and only the second is this translation's.
class LC_WatchPtList_t
{
  LC_WatchPtList_t *Next; // next element
  U16 WatchIndex;         // watchpoint table index
  U16 Spare;              // NASA's own structure alignment pad
  U8 _pad0[4];            // C pads the tail to the pointer's 8-byte alignment
};

/*******************************************************************************/
// A MsgId link: one message id that hashes to a given bucket, with the list of watchpoints that
// read it. 24 bytes.
class LC_MessageList_t
{
  LC_MessageList_t *Next;  // next element
  CFE_SB_MsgId MessageID;  // the message id for this link
  U16 Spare;               // NASA's own structure alignment pad
  U8 _pad0[2];             // C aligns the pointer that follows
  LC_WatchPtList_t *WatchPtList; // watchpoints that read this message id
};

/*******************************************************************************/
// LC's operational data. 9,336 bytes, and NOT in the CDS.
class LC_OperData_t
{
  U32 CmdPipe; // CFE_SB_PipeId_t
  U8 _pad0[4]; // C aligns the four table pointers that follow

  LC_WDTEntry_t *WDTPtr; // watchpoint  definition table
  LC_ADTEntry_t *ADTPtr; // actionpoint definition table

  LC_WRTEntry_t *WRTPtr; // watchpoint  results table
  LC_ARTEntry_t *ARTPtr; // actionpoint results table

  // FOUR SIGNED 16-BIT HANDLES, and the signedness matters for the same reason it did in CS:
  // CFE_TBL_Handle_t is an int16 and CFE_TBL_BAD_TABLE_HANDLE is -1, so holding these unsigned
  // makes CFE_TBL_HANDLE_IS_VALID answer TRUE for the one value that means "no handle". Two bytes
  // either way, so no layout gate can see it.
  I16 WDTHandle; // CFE_TBL_Handle_t
  I16 ADTHandle; // CFE_TBL_Handle_t
  I16 WRTHandle; // CFE_TBL_Handle_t
  I16 ARTHandle; // CFE_TBL_Handle_t

  U32 WRTDataCDSHandle; // CFE_ES_CDSHandle_t
  U32 ARTDataCDSHandle; // CFE_ES_CDSHandle_t
  U32 AppDataCDSHandle; // CFE_ES_CDSHandle_t

  U16 WatchpointCount; // in-use watchpoints defined in the WDT
  U16 MessageIDsCount; // UNIQUE message ids referenced by the WDT

  LC_HkPacket_t HkPacket; // the housekeeping telemetry packet

  U32 TableResults; // the twenty-three bits above: how LC came up

  // Each entry is a linked list of all the MsgIds the hash function sends to that index.
  LC_MessageList_t *HashTable[LC_HASH_TABLE_ENTRIES];

  // The link pools. See the note at the top: at most 176 watchpoints, so at most 176 of each
  // link, and LC never allocates one.
  LC_MessageList_t MessageLinks[LC_MAX_WATCHPOINTS];
  LC_WatchPtList_t WatchPtLinks[LC_MAX_WATCHPOINTS];

  Bool HaveActiveCDS; // critical data store in use
  U8 _pad1[7];        // C pads the tail to the structure's 8-byte alignment
};

/*******************************************************************************/
// LC's application data. 24 bytes, and this IS what goes in the CDS.
//
// CDSSavedOnExit IS THE ONLY MEMBER THAT IS NOT A COUNTER OR A STATE, AND IT DOES NOT MEAN WHAT
// ITS NAME SAYS. It reads "saved on exit", and it is really "DID THE PREVIOUS SESSION EVER SAVE?"
//
// Traced through all six LC sources, because the name invited a guess: the field is assigned in
// exactly ONE place -- LC_UpdateTaskCDS sets it to LC_CDS_SAVED -- and read in two,
// LC_CreateTaskCDS's restore arm and LC_AppMain's exit path. **LC_CDS_NOT_SAVED (0x0F0F) IS
// DEFINED AND NEVER USED ANYWHERE IN LC.** Nothing ever clears the flag.
//
// So the semantics are cumulative, not per-exit, and NASA's own comment at the restore site says
// so: "Success - only if previous session saved CDS data at least once". A restored CDS whose flag
// is not LC_CDS_SAVED means the previous run never reached a maintenance cycle -- NOT that it
// crashed. A run that saved once and then crashed leaves the flag set and its last saved counters
// behind, which is the intended behaviour and is why there is no clean/unclean distinction to
// make.
//
// The two values are still each other's bit complement, which is the usual trick for a flag that
// must survive a half-written word -- it is just that only one of them is ever written.
class LC_AppData_t
{
  U16 CmdCount;    // command counter
  U16 CmdErrCount; // command error counter

  U32 APSampleCount;       // total actionpoints sampled
  U32 MonitoredMsgCount;   // total messages monitored
  U32 RTSExecCount;        // total RTS sequences initiated
  U16 PassiveRTSExecCount; // RTS sequences NOT initiated because LC or the AP was passive

  U16 CDSSavedOnExit; // LC_CDS_SAVED once any run has saved; see the block comment above
  U8 CurrentLCState;  // current LC application operating state
  U8 _pad0[3];        // C pads the tail to the structure's 4-byte alignment
};

// --- the two globals --------------------------------------------------------------------------
//
// NASA declares these `extern` in lc_app.h and defines them in lc_app.c. The translation defines
// them HERE, in the vocabulary, for the reason every app in this port has: a HolyC `extern`
// outside the module-loader's window is a module-local dummy, so a global has exactly one
// definition and it lives with its type.
LC_OperData_t LC_OperData; // operational data, rebuilt every boot
LC_AppData_t LC_AppData;   // application data, saved to and restored from the CDS

#endif
