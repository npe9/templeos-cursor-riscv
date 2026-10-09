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
// HEALTH & SAFETY'S FOUR TABLES -- the 1:1 translation of NASA's config/default_hs_tbldefs.h and
// config/default_hs_tblstruct.h.
//
// HS IS THE ONLY APP IN THIS PORT WITH FOUR LOADABLE TABLES, and each one configures a different
// monitor:
//
//   AMT  Application Monitor   32 entries x 26 bytes   "is app X still counting?"
//   EMT  Event Monitor         16 entries x 26 bytes   "did app X emit event N?"
//   XCT  Execution Counters    32 entries x 28 bytes   which counters appear in telemetry
//   MAT  Message Actions        8 entries x 24 bytes   a raw SB message to send as a response
//
// ### THE ACTION TYPE IS AN INDEX **AND** A SELECTOR, WHICH IS THE DESIGN TO UNDERSTAND
//
// An AMT or EMT entry's ActionType is one of four named constants (NOACT, PROC_RESET,
// APP_RESTART, EVENT/APP_DELETE) -- or **anything above HS_*ActType_LAST_NONMSG**, in which case
// it is `ActionType - LAST_NONMSG - 1` used as an INDEX INTO THE MESSAGE ACTIONS TABLE. So the
// same uint16 field means "do this built-in thing" for 0..3 and "send MAT entry N" for 4 and up,
// and `LAST_NONMSG` being 3 in both tables is what makes one validator shape work for both.
//
// That is why HS_MAX_MSG_ACT_TYPES (8) and the action-type range are coupled: a table validator
// has to reject an ActionType that indexes past the MAT, and the arithmetic is off-by-one in a
// way worth writing down -- ActionType 4 is MAT entry 0.
//
// ### THE MESSAGE ACTIONS TABLE HOLDS **RAW SB MESSAGES**
//
// HS_MATMsgBuf_t is a union of a 16-byte array and a CFE_SB_Buffer_t, which is NASA's way of
// getting the alignment of a message with the size of a byte array -- the same shape every
// command buffer in this port's exercises uses. So the ground uploads the BYTES of a command and
// HS transmits them verbatim when a monitor fires: HS does not interpret them at all. Its
// validator checks the message id, the length and the enable state, and nothing else.
//
// AND EACH ENTRY HAS A **COOLDOWN** rather than a rate limit on the event: HS_MATEntry_t.Cooldown
// is the minimum number of cycles between sends, counted down in HS_AppData.MsgActCooldown. So a
// monitor that fires every cycle sends its message once per cooldown period, and the suppression
// is per MAT entry rather than per monitor.
//
// ### THE NullTerm FIELDS ARE NASA'S, AND THEY ARE NOT PADDING
//
// Each of AMT, EMT and XCT ends its name with an explicit `NullTerm` field -- uint16 in two of
// them and uint32 in XCT. NASA's comment is "Buffer of nulls to terminate string", so the name is
// CFE_MISSION_MAX_API_LEN bytes and the terminator is guaranteed by a separate field rather than
// by reserving the last byte of the array. A validator checks it is actually zero
// (HS_*Val_ERR_NUL), which is the only reason the field is observable at all.
#ifndef HS_TBL_HC
#define HS_TBL_HC

#include "hs_cfg.HC"

// --- hs_tbldefs.h's constants ----------------------------------------------------------------
#define HS_State_DISABLED 0
#define HS_State_ENABLED  1

#define HS_StatusFlag_LOADED_XCT 0x01
#define HS_StatusFlag_LOADED_MAT 0x02
#define HS_StatusFlag_LOADED_AMT 0x04
#define HS_StatusFlag_LOADED_EMT 0x08
#define HS_StatusFlag_CDS_IN_USE 0x10

// The AMT's four built-in actions. Anything ABOVE LAST_NONMSG is a MAT index -- see the header.
#define HS_AMTActType_NOACT       0
#define HS_AMTActType_PROC_RESET  1
#define HS_AMTActType_APP_RESTART 2
#define HS_AMTActType_EVENT       3
#define HS_AMTActType_LAST_NONMSG 3

// The EMT's four. NOTE THE THIRD ONE DIFFERS FROM THE AMT'S: an event monitor can DELETE an
// application where an app monitor can only send an event. Same numeric value, different action.
#define HS_EMTActType_NOACT       0
#define HS_EMTActType_PROC_RESET  1
#define HS_EMTActType_APP_RESTART 2
#define HS_EMTActType_APP_DELETE  3
#define HS_EMTActType_LAST_NONMSG 3

#define HS_XCTResType_NOTYPE    0
#define HS_XCTResType_APP_MAIN  1
#define HS_XCTResType_APP_CHILD 2
#define HS_XCTResType_DEVICE    3
#define HS_XCTResType_ISR       4

#define HS_MATState_DISABLED 0
#define HS_MATState_ENABLED  1
#define HS_MATState_NOEVENT  2

// The four validators' codes. EVERY ONE IS NEGATIVE AND NONE IS A cFE STATUS -- they are table
// validation results cFE reads only as "not CFE_SUCCESS", so the specific value reaches a human
// through an event and nowhere else.
#define HS_AMTVal_NO_ERR   0
#define HS_AMTVal_ERR_ACT  -1
#define HS_AMTVal_ERR_NUL  -2
#define HS_EMTVal_NO_ERR   0
#define HS_EMTVal_ERR_ACT  -1
#define HS_EMTVal_ERR_NUL  -2
#define HS_XCTVal_NO_ERR   0
#define HS_XCTVal_ERR_TYPE -1
#define HS_XCTVal_ERR_NUL  -2
#define HS_MATVal_NO_ERR   0
#define HS_MATVal_ERR_ID   -1
#define HS_MATVal_ERR_LEN  -2
#define HS_MATVal_ERR_ENA  -3

/*******************************************************************************/
// One application-monitor entry. 26 bytes, and NASA DECLARES NO PADDING because none is needed:
// CFE_MISSION_MAX_API_LEN is 20, so the three uint16s land on 20, 22 and 24 and the structure
// ends at 26 with 2-byte alignment. A 26-byte structure in a 32-entry array is 832 bytes.
class HS_AMTEntry_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN]; // name of the application to be monitored
  U16 NullTerm;    // NASA's own: a buffer of nulls to terminate the name
  U16 CycleCount;  // cycles without a check-in before the application is declared missing
  U16 ActionType;  // what to do when it is -- see the header on the index/selector duality
};

/*******************************************************************************/
// One event-monitor entry. 26 bytes, the same shape as the AMT with EventID where CycleCount is.
class HS_EMTEntry_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN]; // name of the application generating the event
  U16 NullTerm;   // NASA's own
  U16 EventID;    // the event number being watched for
  U16 ActionType; // what to do when it is seen
};

/*******************************************************************************/
// One execution-counter entry. 28 bytes -- two more than the AMT, because NullTerm here is a
// uint32 rather than a uint16 and that forces ResourceType onto a 4-byte boundary.
//
// NASA'S OWN INCONSISTENCY, KEPT: three tables with a NullTerm field and one of them is twice as
// wide. It is observable -- the XCT is 28 bytes per entry where AMT and EMT are 26 -- so a
// translation that harmonised them would change the table a ground system uploads.
class HS_XCTEntry_t
{
  U8 ResourceName[CFE_MISSION_MAX_API_LEN]; // name of the resource being monitored
  U32 NullTerm;     // NASA's own, and a U32 here where the other two tables use a U16
  U32 ResourceType; // HS_XCTResType_*
};

/*******************************************************************************/
// The message-actions buffer: a union of a raw byte array and an SB buffer. 16 bytes.
//
// NASA'S WAY OF GETTING A MESSAGE'S ALIGNMENT WITH AN ARRAY'S SIZE -- the same shape every
// command buffer in this port's exercises uses, written out as a union because that is what it
// is. HS_MAX_MSG_ACT_SIZE is 16, and a CFE_SB_Buffer is an 8-byte alignment union, so the array
// is what decides the size.
union HS_MATMsgBuf_t
{
  U8 Message[HS_MAX_MSG_ACT_SIZE]; // the raw bytes the ground uploaded
  CFE_SB_Buffer Buffer;            // for alignment only
};

/*******************************************************************************/
// One message-action entry. 24 bytes: two uint16s and the 16-byte buffer, with four bytes of
// padding between them because the buffer is 8-byte aligned.
class HS_MATEntry_t
{
  U16 EnableState; // HS_MATState_*
  U16 Cooldown;    // minimum cycles between sends -- see the header
  U8 _pad0[4];     // C aligns the 8-byte-aligned buffer that follows
  HS_MATMsgBuf_t MsgBuf; // the message to send, verbatim
};

#endif
