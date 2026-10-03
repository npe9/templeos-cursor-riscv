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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_priv.c -- SB's INTERNALS: the pipe
// table, the destination lists, the recursion guard, and the MESSAGE TRANSACTION state machine
// that both CFE_SB_TransmitMsg and CFE_SB_ReceiveBuffer are built on.
//
// THE TRANSACTION IS THE IDEA IN THIS FILE. Sending is a FAN-OUT: find every pipe subscribed to
// a message id, try each one, report once. A failure on the fourth pipe must not undo the first
// three or stop the fifth, so each pipe carries its own PendingEventId and OsStatus and the
// transaction carries one overall status plus the FIRST event worth reporting. Receiving runs
// the same machine with a single pipe in the set -- which is why the type is MessageTxn and the
// handler is a function POINTER: CFE_SB_MessageTxn_ProcessPipes walks the set and calls either
// CFE_SB_TransmitTxn_PipeHandler, which returns TRUE to keep broadcasting, or
// CFE_SB_ReceiveTxn_PipeHandler, which returns FALSE because a read services one pipe.
//
// AND THE ACCOUNTING IS OPTIMISTIC ON PURPOSE. CFE_SB_TransmitTxn_FindDestinations increments
// each pipe's queue depth and the destination's buffer count BEFORE the queue write is
// attempted, because the write is expected to succeed; CFE_SB_TransmitTxn_PipeHandler undoes
// exactly those two increments when it does not. Reading the pair together is the only way the
// counters make sense.
#ifndef CFE_SB_PRIV_HC
#define CFE_SB_PRIV_HC
#include "cfe_sb_global.HC" // the types, the constants and CFE_SB_Global
#include "cfe_sb_buf.HC"    // the buffer descriptor's lifetime and the tracking list
// --- cfe_sb_eventids.h: the fourteen this file raises ----------------------------------------
#define CFE_SB_INIT_EID                        1
#define CFE_SB_SUB_ARG_ERR_EID                 6
#define CFE_SB_DUP_SUBSCRIP_EID                7
#define CFE_SB_MAX_MSGS_MET_EID                8
#define CFE_SB_MAX_DESTS_MET_EID               9
#define CFE_SB_SEND_BAD_ARG_EID                13
#define CFE_SB_SEND_NO_SUBS_EID                14
#define CFE_SB_MSG_TOO_BIG_EID                 15
#define CFE_SB_GET_BUF_ERR_EID                 16
#define CFE_SB_MSGID_LIM_ERR_EID               17
#define CFE_SB_RCV_BAD_ARG_EID                 18
#define CFE_SB_BAD_PIPEID_EID                  19
#define CFE_SB_DEST_BLK_ERR_EID                20
#define CFE_SB_SEND_INV_MSGID_EID              21
#define CFE_SB_Q_FULL_ERR_EID                  25
#define CFE_SB_Q_WR_ERR_EID                    26
#define CFE_SB_Q_RD_ERR_EID                    27
#define CFE_SB_SUB_INV_PIPE_EID                50
#define CFE_SB_SUB_INV_CALLER_EID              51
#define CFE_SB_SEND_MESSAGE_INTEGRITY_FAIL_EID 71
#define CFE_SB_RCV_MESSAGE_INTEGRITY_FAIL_EID  72
// --- cfe_error.h: the statuses this file returns ---------------------------------------------
#define CFE_SB_TIME_OUT       0xCA000001(I32)
#define CFE_SB_NO_MESSAGE     0xCA000002(I32)
#define CFE_SB_PIPE_RD_ERR    0xCA000006(I32)
#define CFE_SB_MSG_TOO_BIG    0xCA000007(I32)
#define CFE_SB_BUFFER_INVALID 0xCA00000E(I32)
#define CFE_SB_FAILED         1
// --- osapi-error.h / osapi-idmap.h: the OSAL codes this file branches on ---------------------
// OS_PEND and OS_CHECK are TIMEOUTS, not statuses: -1 means block forever and 0 means do not
// block, which is why CFE_SB_MessageTxn_GetOsTimeout returns one of them or a millisecond count.
#ifndef OS_PEND
#define OS_PEND  -1
#define OS_CHECK 0
#endif
#ifndef OS_QUEUE_EMPTY
#define OS_QUEUE_EMPTY   -8
#define OS_QUEUE_FULL    -9
#define OS_QUEUE_TIMEOUT -10
#endif
#ifndef OS_OBJECT_ID_UNDEFINED
#define OS_OBJECT_ID_UNDEFINED 0
#endif
// --- default_cfe_es_extern_typedefs.h --------------------------------------------------------
// ES is not translated, and this is the one ES TYPE this file needs: CFE_SB_GetAppTskName reads
// AppName and TaskName out of it to build the "app.task" string every SB event carries. The
// layout is NASA's and check_padding measures it, so the two Spare bytes at the end are not
// decoration -- they are what makes the struct the size CFE_ES_GetTaskInfo writes.
#ifndef CFE_ES_TASKINFO_DEFINED
#define CFE_ES_TASKINFO_DEFINED
class CFE_ES_TaskInfo_t
{
  U32 TaskId;
  U32 ExecutionCounter;
  U8 TaskName[CFE_MISSION_MAX_API_LEN];
  U32 AppId;
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U8 _pad0[4];
  // C aligns StackSize to 8
  I64 StackSize;
  // CFE_ES_MemOffset_t -- EIGHT bytes, not four. It was U32 for one run and check_padding named
  // it: a memory offset is a size_t-width quantity, and getting it wrong moved Priority and
  // Spare and made the struct 60 bytes against NASA's 72. CFE_ES_GetTaskInfo writes this.
  U16 Priority;
  // CFE_ES_TaskPriority_Atom_t
  U8 Spare[2];
  // NASA's own, for alignment
  U8 _pad1[4];
  // TAIL padding: StackSize is 8-aligned, so C rounds 68 up to 72
};
#endif
// --- the dimensions and options --------------------------------------------------------------
#define CFE_MISSION_SB_MAX_SB_MSG_SIZE 32768
#define CFE_SB_PIPEOPTS_IGNOREMINE     0x00000001
// INT32_MIN, which GetEventDetails uses as "this is not a real OS status" so the value cannot
// alias one. NASA's comment says exactly that.
#define INT32_MIN -2147483648
// --- what this file needs from elsewhere ------------------------------------------------------
// Declared here and defined below, because the C's order has each used above its definition.
U0 CFE_SB_MessageTxn_SetEventAndStatus(CFE_SB_MessageTxn_State_t *TxnPtr, U16 EventId, I32 Status);
U0 CFE_SB_RemoveDestNode(CFE_SBR_RouteId RouteId, CFE_SB_DestinationD_t *NodeToRemove);
I32 CFE_SB_GetPipeNamePriv(U32 PipeId, U8 *PipeNameBuf, I64 PipeNameSize);
U0 CFE_SB_ReceiveTxn_SetPipeId(CFE_SB_MessageTxn_State_t *TxnPtr, U32 PipeId);
Bool CFE_SB_MessageTxn_ReportSingleEvent(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *ContextPtr, U16 EventId);
// cfe_sb_api.c, which is NOT yet translated. Two functions, stubbed by the differential driver
// on both sides for now and recorded as temporary -- the same arrangement CFE_TIME_Tone1HzISR
// had until cfe_time_tone.c landed. They go away when api.c does.
I32 CFE_SB_DeletePipeWithAppId(U32 PipeId, U32 AppId);
I32 CFE_SB_GetPipeName(U8 *PipeNameBuf, I64 PipeNameSize, U32 PipeId);
// ES, EVS, MSG, SBR and OSAL.
I32 CFE_ES_GetAppID(U32 *AppIdPtr);
I32 CFE_ES_GetTaskID(U32 *TaskIdPtr);
I32 CFE_ES_GetTaskInfo(CFE_ES_TaskInfo_t *TaskInfo, U32 TaskId);
I32 CFE_ES_TaskID_ToIndex(U32 TaskID, U32 *Idx);
I32 CFE_ES_WriteToSysLog(U8 *Spec,...);
I32 CFE_EVS_SendEventWithAppID(U16 EventID, U16 EventType, U32 AppID, U8 *Spec,...);
I32 CFE_SB_PipeId_ToIndex(U32 PipeID, U32 *Idx);
I32 OS_MutSemTake(U32 sem_id);
I32 OS_MutSemGive(U32 sem_id);
I32 OS_QueuePut(U32 queue_id, U8 *data, I64 size, I32 timeout);
I32 OS_QueueGet(U32 queue_id, U8 *data, I64 size, I64 *size_copied, I32 timeout);
I32 OS_GetResourceName(U32 object_id, U8 *buffer, I64 buffer_size);
U8 *StrNCpy(U8 *dst, U8 *src, I64 n);
I64 StrNCmp(U8 *a, U8 *b, I64 n);
I64 StrPrintN(U8 *Buf, I64 Size, U8 *Fmt, I64 a0 = 0, I64 a1 = 0, I64 a2 = 0, I64 a3 = 0, I64 a4 = 0, I64 a5 = 0, I64 a6 = 0, I64 a7 = 0);
U8 *MemSet(U8 *dst, I64 dat, I64 size);
// --- cfe_sb.h: the bit helpers ----------------------------------------------------------------
// NASA's CFE_BIT/CFE_SET/CFE_CLR/CFE_TST. They are one-line macros upstream and functions here,
// because HolyC's macro expansion has no parameters -- the same move CFE_TIME_Copy records.
// StopRecurseFlags is a U32 per task, so the bit index is 0..31.
U32 CFE_SB_BitSet(U32 Word, I64 Bit)
{
  return Word | (1 << Bit);
}

U32 CFE_SB_BitClr(U32 Word, I64 Bit)
{
  return Word & ~(1 << Bit);
}

Bool CFE_SB_BitTst(U32 Word, I64 Bit)
{
  return (Word & (1 << Bit)) != 0;
}
// --- cfe_sb_priv.h: the inline accessors ------------------------------------------------------
// NASA declares these `static inline` in the header. HolyC has neither, so they are plain
// functions in this unit -- the deviation cfe_time_task.HC records for its TaskInit_* helpers.
Bool CFE_SB_TrackingListIsEnd(CFE_SB_BufferLink_t *List, CFE_SB_BufferLink_t *Node)
{
  /* Normally Node==NULL should not happen, but if it does, do not infinite loop */
  return Node == NULL || Node == List;
}

CFE_SB_BufferLink_t *CFE_SB_TrackingListGetNext(CFE_SB_BufferLink_t *Node)
{
  return Node->Next;
}

Bool CFE_SB_PipeDescIsUsed(CFE_SB_PipeD_t *PipeDscPtr)
{
  return CFE_ResourceId_IsDefined(PipeDscPtr->PipeId);
}

U32 CFE_SB_PipeDescGetID(CFE_SB_PipeD_t *PipeDscPtr)
{
  return PipeDscPtr->PipeId;
}

U0 CFE_SB_PipeDescSetUsed(CFE_SB_PipeD_t *PipeDscPtr, U32 PendingID)
{
  PipeDscPtr->PipeId = PendingID;
}

U0 CFE_SB_PipeDescSetFree(CFE_SB_PipeD_t *PipeDscPtr)
{
  PipeDscPtr->PipeId = CFE_RESOURCEID_UNDEFINED;
  // CFE_SB_INVALID_PIPE is CFE_SB_PIPEID_C(CFE_RESOURCEID_UNDEFINED); this port spells ids as
  // plain U32, so the wrapper is the identity and the base constant is what is written.
}
// A pipe descriptor matches an id only if the pointer is non-NULL AND the id in the slot is the
// one asked for. The NULL half matters: CFE_SB_LocatePipeDescByID returns NULL for an index out
// of range, and every caller here pairs Locate with IsMatch for that reason.
Bool CFE_SB_PipeDescIsMatch(CFE_SB_PipeD_t *PipeDscPtr, U32 PipeID)
{
  return PipeDscPtr != NULL && PipeDscPtr->PipeId == PipeID;
}

Bool CFE_SB_MessageTxn_IsOK(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  return TxnPtr->Status == CFE_SUCCESS && TxnPtr->TransactionEventId == 0;
}

I64 CFE_SB_MessageTxn_GetContentSize(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  return TxnPtr->ContentSize;
}

CFE_SB_MsgId CFE_SB_MessageTxn_GetRoutingMsgId(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  return TxnPtr->RoutingMsgId;
}

I32 CFE_SB_MessageTxn_GetStatus(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  return TxnPtr->Status;
}
// --- cfe_sb_priv.h: the shared-data lock -----------------------------------------------------
// NASA passes __func__ and __LINE__ so a mutex failure names its caller. HolyC has neither --
// __LINE__ is a TempleOS `#exe` block this compiler skips (docs/HOLYC_STRUCT_LIMITS.md #15) --
// so the function name is spelled out and the line is 0. Nothing in the gated transcript reaches
// these diagnostics: they fire only when the OS mutex itself fails.
U0 CFE_SB_LockSharedData(U8 *FuncName, I32 LineNumber)
{
  I32 OsStatus;
  U32 AppId;
  OsStatus = OS_MutSemTake(CFE_SB_Global.SharedDataMutexId);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_GetAppID(&AppId);
    CFE_ES_WriteToSysLog("CFE_SB_LockSharedData: SharedData Mutex Take Err Stat=%d,App=%u,Func=%s,Line=%d\n", OsStatus, AppId, FuncName, LineNumber);
  }
}

U0 CFE_SB_UnlockSharedData(U8 *FuncName, I32 LineNumber)
{
  I32 OsStatus;
  U32 AppId;
  OsStatus = OS_MutSemGive(CFE_SB_Global.SharedDataMutexId);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_GetAppID(&AppId);
    CFE_ES_WriteToSysLog("CFE_SB_UnlockSharedData: SharedData Mutex Give Err Stat=%d,App=%u,Func=%s,Line=%d\n", OsStatus, AppId, FuncName, LineNumber);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_SB_DestinationD_t *CFE_SB_GetDestPtr(CFE_SBR_RouteId RouteId, U32 PipeId)
{
  CFE_SB_DestinationD_t *destptr;
  destptr = CFE_SBR_GetDestListHeadPtr(RouteId);
  /* Check all destinations */
  while (destptr != NULL) {
    if (destptr->PipeId == PipeId) {
      break;
    }
    destptr = destptr->Next;
  }
  return destptr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_ValidateMsgId(CFE_SB_MsgId MsgId)
{
  if (!CFE_SB_IsValidMsgId(MsgId)) {
    return CFE_SB_FAILED;
  } else {
    return CFE_SUCCESS;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_SB_PipeD_t *CFE_SB_LocatePipeDescByID(U32 PipeId)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 Idx;
  if (CFE_SB_PipeId_ToIndex(PipeId, &Idx) == CFE_SUCCESS) {
    PipeDscPtr = &CFE_SB_Global.PipeTbl[Idx];
  } else {
    PipeDscPtr = NULL;
  }
  return PipeDscPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_SB_CheckPipeDescSlotUsed(U32 CheckId)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  /*
   * Note - The pointer here should never be NULL because the ID should always be
   * within the expected range, but if it ever is NULL, this should return true
   * such that the caller will _not_ attempt to use the record.
   */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(CheckId);
  return PipeDscPtr == NULL || CFE_SB_PipeDescIsUsed(PipeDscPtr);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U8 *CFE_SB_GetAppTskName(U32 TaskId, U8 *FullName)
{
  CFE_ES_TaskInfo_t TaskInfo;
  CFE_ES_TaskInfo_t *ptr = &TaskInfo;
  U8 AppName[OS_MAX_API_NAME];
  U8 TskName[OS_MAX_API_NAME];
  if (CFE_ES_GetTaskInfo(ptr, TaskId) != CFE_SUCCESS) {
    /* unlikely, but possible if TaskId is bogus */
    StrNCpy(FullName, "Unknown", OS_MAX_API_NAME - 1);
    FullName[OS_MAX_API_NAME - 1] = 0;
    // NASA writes sizeof(ptr->AppName). `sizeof` OF A MEMBER THROUGH A POINTER does not parse in
    // this compiler, and it fails in the worst available way: it swallows the rest of the
    // compilation unit and reports "parse error" at line 0 of the TOP-LEVEL file, naming neither
    // this file nor this line. docs/HOLYC_STRUCT_LIMITS.md #16. The value is the array's bound,
    // which check_padding verifies on CFE_ES_TaskInfo_t -- the same substitution
    // cfe_time_utils.HC records for sizeof(arr)/sizeof(arr[0]).
  } else if (StrNCmp(ptr->AppName, ptr->TaskName, CFE_MISSION_MAX_API_LEN) == 0) {
    /* if app name and task name are the same */
    StrNCpy(FullName, ptr->AppName, OS_MAX_API_NAME - 1);
    FullName[OS_MAX_API_NAME - 1] = 0;
  } else {
    /* AppName and TskName buffers and strncpy are needed to limit string sizes */
    StrNCpy(AppName, ptr->AppName, sizeof(AppName) - 1);
    AppName[sizeof(AppName) - 1] = 0;
    StrNCpy(TskName, ptr->TaskName, sizeof(TskName) - 1);
    TskName[sizeof(TskName) - 1] = 0;
    StrPrintN(FullName, OS_MAX_API_NAME * 2, "%s.%s", AppName, TskName);
  }
  return FullName;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE RECURSION GUARD. Sending an event goes THROUGH SB, so an error raised while sending an
// error would recurse forever. One bit per event per TASK is what stops it: a task that is
// already reporting event N is DENIED a second N until CFE_SB_FinishSendEvent clears the bit.
// A negative Bit means "no guard applies", which is how the receive-side events opt out.
U32 CFE_SB_RequestToSendEvent(U32 TaskId, I32 Bit)
{
  U32 Indx;
  if (Bit < 0) {
    return CFE_SB_GRANTED;
  }
  if (CFE_ES_TaskID_ToIndex(TaskId, &Indx) != CFE_SUCCESS) {
    return CFE_SB_DENIED;
  }
  /* if bit is set... */
  if (CFE_SB_BitTst(CFE_SB_Global.StopRecurseFlags[Indx], Bit)) {
    return CFE_SB_DENIED;
  } else {
    CFE_SB_Global.StopRecurseFlags[Indx] = CFE_SB_BitSet(CFE_SB_Global.StopRecurseFlags[Indx], Bit);
    return CFE_SB_GRANTED;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_FinishSendEvent(U32 TaskId, I32 Bit)
{
  U32 Indx;
  if (Bit < 0) {
    return;
  }
  if (CFE_ES_TaskID_ToIndex(TaskId, &Indx) != CFE_SUCCESS) {
    return;
  }
  /* clear the bit so the task may send this event again */
  CFE_SB_Global.StopRecurseFlags[Indx] = CFE_SB_BitClr(CFE_SB_Global.StopRecurseFlags[Indx], Bit);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// The destination list is SINGLY-headed and doubly-linked, and a new node goes at the FRONT --
// which is why there is no tail pointer and why CFE_SBR_SetDestListHeadPtr is called on every
// insert. Note this is a different list from the buffer tracking list in cfe_sb_buf.HC: that one
// is circular and empty-points-at-itself, this one is NULL-terminated. Two lists, two
// conventions, in one module.
I32 CFE_SB_AddDestNode(CFE_SBR_RouteId RouteId, CFE_SB_DestinationD_t *NewNode)
{
  CFE_SB_DestinationD_t *WBS;
  /* Will Be Second (WBS) node */
  CFE_SB_DestinationD_t *listheadptr;
  listheadptr = CFE_SBR_GetDestListHeadPtr(RouteId);
  /* if first node in list */
  if (listheadptr == NULL) {
    /* initialize the new node */
    NewNode->Next = NULL;
    NewNode->Prev = NULL;
  } else {
    WBS = listheadptr;
    /* initialize the new node */
    NewNode->Next = WBS;
    NewNode->Prev = NULL;
    /* insert the new node */
    WBS->Prev = NewNode;
  }
  /* Update Head */
  CFE_SBR_SetDestListHeadPtr(RouteId, NewNode);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_RemoveDest(CFE_SBR_RouteId RouteId, CFE_SB_DestinationD_t *DestPtr)
{
  CFE_SB_RemoveDestNode(RouteId, DestPtr);
  CFE_SB_PutDestinationBlk(DestPtr);
  CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse--;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_RemoveDestNode(CFE_SBR_RouteId RouteId, CFE_SB_DestinationD_t *NodeToRemove)
{
  CFE_SB_DestinationD_t *PrevNode;
  CFE_SB_DestinationD_t *NextNode;
  if (NodeToRemove->Prev == NULL && NodeToRemove->Next == NULL) {
    /* Clear destinations if this is the only node in the list */
    CFE_SBR_SetDestListHeadPtr(RouteId, NULL);
  } else if (NodeToRemove->Prev == NULL) {
    /* First in the list, set the next node to list head */
    NextNode = NodeToRemove->Next;
    NextNode->Prev = NULL;
    CFE_SBR_SetDestListHeadPtr(RouteId, NextNode);
  } else if (NodeToRemove->Next == NULL) {
    /* Last in the list, remove previous pointer */
    PrevNode = NodeToRemove->Prev;
    PrevNode->Next = NULL;
  } else {
    /* Middle of list, remove */
    PrevNode = NodeToRemove->Prev;
    NextNode = NodeToRemove->Next;
    PrevNode->Next = NextNode;
    NextNode->Prev = PrevNode;
  }
  /* initialize the node before returning it to the heap */
  NodeToRemove->Next = NULL;
  NodeToRemove->Prev = NULL;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_ZeroCopyReleaseAppId(U32 AppId)
{
  CFE_SB_BufferLink_t *NextLink;
  CFE_SB_BufferD_t *DscPtr;
  /*
   * First go through the "ZeroCopy" tracking list and find all nodes
   * with a matching AppID.  This needs to be done while locked to
   * prevent other tasks from changing the list at the same time.
   */
  if (CFE_ResourceId_IsDefined(AppId)) {
    CFE_SB_LockSharedData("CFE_SB_ZeroCopyReleaseAppId", 467);
    /* Get start of list */
    NextLink = CFE_SB_TrackingListGetNext(&CFE_SB_Global.ZeroCopyList);
    while (!CFE_SB_TrackingListIsEnd(&CFE_SB_Global.ZeroCopyList, NextLink)) {
      /* Get buffer descriptor pointer */
      // The Link is the FIRST member of the descriptor, so the two addresses are the same one.
      DscPtr = NextLink;
      /* Read the next link now in case this node gets moved */
      NextLink = CFE_SB_TrackingListGetNext(NextLink);
      /* Check if it is a zero-copy buffer owned by this app */
      if (DscPtr->AppId == AppId) {
        /* If so, decrement the use count as the app has now gone away */
        CFE_SB_DecrBufUseCnt(DscPtr);
      }
    }
    CFE_SB_UnlockSharedData("CFE_SB_ZeroCopyReleaseAppId", 489);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// The buffer handed to an app is a MEMBER of the descriptor, so the descriptor is found by
// subtracting the member's offset -- which is why CFE_SB_BUFFERD_CONTENT_OFFSET has to be
// exactly right, and why getting it wrong by eight bytes was worth a gate (cfe_sb_buf.HC).
I32 CFE_SB_ZeroCopyBufferValidate(CFE_SB_Buffer *BufPtr, CFE_SB_BufferD_t **BufDscPtr)
{
  U8 *BufDscAddr;
  /*
   * Calculate descriptor pointer from buffer pointer -
   * The buffer is just a member (offset) in the descriptor
   */
  // THE CAST IS NASA'S AND IT IS LOAD-BEARING. NASA writes `(cpuaddr)BufPtr - offsetof(...)`,
  // an INTEGER subtraction. Without the cast this is pointer arithmetic and HolyC scales the 56
  // by sizeof(CFE_SB_Buffer), exactly as C would -- the first draft of this line dropped it and
  // the descriptor came back inside another buffer's payload. It surfaced as a store fault in
  // CFE_SB_TrackingListRemove, one module away. tests/exec/cases/e_ptr_minus_int_scales.hc.
  BufDscAddr = BufPtr(U8 *) - CFE_SB_BUFFERD_CONTENT_OFFSET;
  *BufDscPtr = BufDscAddr;
  /*
   * Check that the descriptor is actually a "zero copy" type,
   */
  if (!CFE_ResourceId_IsDefined ((*BufDscPtr)->AppId)) {
    return CFE_SB_BUFFER_INVALID;
  }
  /* Basic sanity check passed */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// Deleting an app deletes its pipes -- and the DelList exists because the pipe table is walked
// UNDER THE LOCK while CFE_SB_DeletePipeWithAppId must be called WITHOUT it. Collect first,
// delete after: the same shape as every "do not call out with a lock held" loop.
I32 CFE_SB_CleanUpApp(U32 Id)
{
  U32 i;
  U32 DelCount;
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 DelList[CFE_PLATFORM_SB_MAX_PIPES];
  U32 AppId;
  AppId = Id;
  PipeDscPtr = CFE_SB_Global.PipeTbl;
  DelCount = 0;
  CFE_SB_LockSharedData("CFE_SB_CleanUpApp", 100);
  /* loop through the pipe table looking for pipes owned by AppId */
  for (i = 0; i < CFE_PLATFORM_SB_MAX_PIPES; ++i) {
    if (CFE_SB_PipeDescIsUsed(PipeDscPtr) && PipeDscPtr->AppId == AppId) {
      DelList[DelCount] = CFE_SB_PipeDescGetID(PipeDscPtr);
      ++DelCount;
    }
    ++PipeDscPtr;
  }
  CFE_SB_UnlockSharedData("CFE_SB_CleanUpApp", 113);
  for (i = 0; i < DelCount; ++i) {
    CFE_SB_DeletePipeWithAppId(DelList[i], AppId);
  }
  /* Release any zero copy buffers */
  CFE_SB_ZeroCopyReleaseAppId(AppId);
  return CFE_SUCCESS;
}
/******************************************************************
 *
 * MESSAGE TRANSACTION IMPLEMENTATION FUNCTIONS
 *
 ******************************************************************/
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_MessageTxn_Init(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *PipeSet, U16 MaxPipes, U8 *RefMemPtr)
{
  // NASA clears `offsetof(CFE_SB_TransmitTxn_State_t, DestSet)` -- the COMMON HEADER only, not
  // sizeof(*TxnPtr) and not the destination array behind it. HolyC has no offsetof; the value is
  // sizeof(CFE_SB_MessageTxn_State_t), which is where DestSet begins, and check_padding measures
  // both numbers against NASA's compiler.
  MemSet(TxnPtr, 0, sizeof(CFE_SB_MessageTxn_State_t));
  TxnPtr->PipeSet = PipeSet;
  TxnPtr->MaxPipes = MaxPipes;
  /* The reference pointer is kept just for (potential) reporting in events, etc.
   * It is not dereferenced from here. */
  TxnPtr->RefMemPtr = RefMemPtr;
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_MessageTxn_SetTimeout(CFE_SB_MessageTxn_State_t *TxnPtr, I32 Timeout)
{
  TxnPtr->UserTimeoutParam = Timeout;
  if (Timeout > 0) {
    /* Convert to an absolute timeout */
    TxnPtr->TimeoutMode = CFE_SB_MessageTxn_TimeoutMode_TIMED;
    CFE_PSP_GetTime(&TxnPtr->AbsTimeout);
    TxnPtr->AbsTimeout = OS_TimeAdd(TxnPtr->AbsTimeout, OS_TimeFromTotalMilliseconds(Timeout));
  } else if (Timeout == CFE_SB_POLL) {
    TxnPtr->TimeoutMode = CFE_SB_MessageTxn_TimeoutMode_POLL;
  } else if (Timeout == CFE_SB_PEND_FOREVER) {
    TxnPtr->TimeoutMode = CFE_SB_MessageTxn_TimeoutMode_PEND;
  } else {
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_RCV_BAD_ARG_EID, CFE_SB_BAD_ARGUMENT);
  }
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// ELEVEN EVENT TEXTS IN ONE SWITCH, and the two outputs beside the message are what make the
// recursion guard work: ReqBit says WHICH guard bit this event uses (-1 for "no guard"), and
// EventType says whether it counts as an error. A default case that produced a message with no
// bit would recurse.
U0 CFE_SB_MessageTxn_GetEventDetails(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *ContextPtr, U16 EventId, U32 TskId, U8 *EvtMsg, I64 EvtMsgSize, U16 *EventType, I32 *ReqBit)
{
  U8 FullName[OS_MAX_API_NAME * 2];
  U8 PipeName[OS_MAX_API_NAME];
  I32 LocalOsStatus;
  if (ContextPtr == NULL) {
    LocalOsStatus = INT32_MIN;
    /* should not be used; do not alias any actual OS status */
    StrPrintN(PipeName, sizeof(PipeName), "[n/a]");
  } else {
    LocalOsStatus = ContextPtr->OsStatus;
    if (ContextPtr->PendingEventId == CFE_SB_BAD_PIPEID_EID) {
      /* do not attempt to map to a pipe name if reporting a bad pipeID event - use its ID */
      StrPrintN(PipeName, sizeof(PipeName), "%u", ContextPtr->PipeId);
    } else {
      CFE_SB_GetPipeNamePriv(ContextPtr->PipeId, PipeName, sizeof(PipeName));
    }
  }
  switch (EventId) {
    case CFE_SB_SEND_BAD_ARG_EID :
    *ReqBit = CFE_SB_SEND_BAD_ARG_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Send Err:Bad input argument,Arg 0x%x,App %s", TxnPtr->RefMemPtr, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_SEND_INV_MSGID_EID :
    *ReqBit = CFE_SB_SEND_INV_MSGID_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Send Err:Invalid MsgId(0x%x)in msg,App %s", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_MSG_TOO_BIG_EID :
    *ReqBit = CFE_SB_MSG_TOO_BIG_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Send Err:Msg Too Big MsgId=0x%x,app=%s,size=%d,MaxSz=%d", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), CFE_SB_GetAppTskName(TskId, FullName), TxnPtr->ContentSize, CFE_MISSION_SB_MAX_SB_MSG_SIZE);
    break;
    case CFE_SB_SEND_NO_SUBS_EID :
    *ReqBit = CFE_SB_SEND_NO_SUBS_EID_BIT;
    *EventType = CFE_EVS_EventType_INFORMATION;
    StrPrintN(EvtMsg, EvtMsgSize, "No subscribers for MsgId 0x%x,sender %s", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_GET_BUF_ERR_EID :
    *ReqBit = CFE_SB_GET_BUF_ERR_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Send Err:Request for Buffer Failed. MsgId 0x%x,app %s,size %d", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), CFE_SB_GetAppTskName(TskId, FullName), TxnPtr->ContentSize);
    break;
    case CFE_SB_MSGID_LIM_ERR_EID :
    *ReqBit = CFE_SB_MSGID_LIM_ERR_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Msg Limit Err,MsgId 0x%x,pipe %s,sender %s", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), PipeName, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_Q_FULL_ERR_EID :
    *ReqBit = CFE_SB_Q_FULL_ERR_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Pipe Overflow,MsgId 0x%x,pipe %s,sender %s", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), PipeName, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_Q_WR_ERR_EID :
    *ReqBit = CFE_SB_Q_WR_ERR_EID_BIT;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Pipe Write Err,MsgId 0x%x,pipe %s,sender %s,stat %d", CFE_SB_MsgIdToValue(TxnPtr->RoutingMsgId), PipeName, CFE_SB_GetAppTskName(TskId, FullName), LocalOsStatus);
    break;
    case CFE_SB_Q_RD_ERR_EID :
    *ReqBit = -1;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Pipe Read Err,pipe %s,app %s,stat %d", PipeName, CFE_SB_GetAppTskName(TskId, FullName), LocalOsStatus);
    break;
    case CFE_SB_RCV_BAD_ARG_EID :
    *ReqBit = -1;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Rcv Err:Bad Input Arg:BufPtr 0x%x,pipe %s,t/o %d,app %s", TxnPtr->RefMemPtr, PipeName, TxnPtr->UserTimeoutParam, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_BAD_PIPEID_EID :
    *ReqBit = -1;
    *EventType = CFE_EVS_EventType_ERROR;
    StrPrintN(EvtMsg, EvtMsgSize, "Rcv Err:PipeId %s does not exist,app %s", PipeName, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    default:
    EvtMsg[0] = 0;
    *ReqBit = 0;
    *EventType = 0;
    break;
  }
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
Bool CFE_SB_MessageTxn_ReportSingleEvent(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *ContextPtr, U16 EventId)
{
  U32 TskId;
  U16 EventType;
  U8 Message[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  I32 ReqBit;
  /* get task id for events and Sender Info*/
  CFE_ES_GetTaskID(&TskId);
  CFE_SB_MessageTxn_GetEventDetails(TxnPtr, ContextPtr, EventId, TskId, Message, sizeof(Message), &EventType, &ReqBit);
  if (EventType > 0 && CFE_SB_RequestToSendEvent(TskId, ReqBit) == CFE_SB_GRANTED) {
    CFE_EVS_SendEventWithAppID(EventId, EventType, CFE_SB_Global.AppId, "%s", Message);
    /* clear the bit so the task may send this event again */
    CFE_SB_FinishSendEvent(TskId, ReqBit);
  }
  /* If the event type was an error, this should increment the general error counter */
  return EventType >= CFE_EVS_EventType_ERROR;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// ONE TRANSACTION EVENT PLUS ONE PER PIPE, and the counter it lands in depends on which side
// and which failure: transmit has a single error counter, receive separates a bad ARGUMENT from
// an internal queue error. NASA's comment says so and the three-way if is where it lives.
U0 CFE_SB_MessageTxn_ReportEvents(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  U32 i;
  U32 NumErrors;
  Bool IsError;
  NumErrors = 0;
  if (TxnPtr->TransactionEventId != 0) {
    IsError = CFE_SB_MessageTxn_ReportSingleEvent(TxnPtr, NULL, TxnPtr->TransactionEventId);
    if (IsError) {
      ++NumErrors;
    }
  }
  for (i = 0; i < TxnPtr->NumPipes; ++i) {
    if (TxnPtr->PipeSet[i].PendingEventId != 0) {
      IsError = CFE_SB_MessageTxn_ReportSingleEvent(TxnPtr, &TxnPtr->PipeSet[i], TxnPtr->PipeSet[i].PendingEventId);
      if (IsError) {
        ++NumErrors;
      }
    }
  }
  if (NumErrors > 0) {
    /*
     * Increment the error only if there was a real error,
     * such as a validation issue or failure to allocate a buffer.
     */
    CFE_SB_LockSharedData("CFE_SB_MessageTxn_ReportEvents", 842);
    if (TxnPtr->IsTransmit) {
      CFE_SB_Global.HKTlmMsg.Payload.MsgSendErrorCounter++;
    } else if (TxnPtr->Status == CFE_SB_BAD_ARGUMENT) {
      ++CFE_SB_Global.HKTlmMsg.Payload.MsgReceiveErrorCounter;
    } else {
      /* For any other unexpected error (e.g. CFE_SB_Q_RD_ERR_EID) */
      ++CFE_SB_Global.HKTlmMsg.Payload.InternalErrorCounter;
    }
    CFE_SB_UnlockSharedData("CFE_SB_MessageTxn_ReportEvents", 858);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// FIRST WRITER WINS, for both fields and independently. A later failure does not overwrite the
// event that explains the first one, and a later status does not overwrite a status already set
// -- which is what lets the setup functions run in sequence without each checking the last.
U0 CFE_SB_MessageTxn_SetEventAndStatus(CFE_SB_MessageTxn_State_t *TxnPtr, U16 EventId, I32 Status)
{
  if (TxnPtr->TransactionEventId == 0) {
    TxnPtr->TransactionEventId = EventId;
  }
  if (TxnPtr->Status == CFE_SUCCESS) {
    TxnPtr->Status = Status;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_MessageTxn_SetRoutingMsgId(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_MsgId RoutingMsgId)
{
  /* validate the msgid in the message */
  if (!CFE_SB_IsValidMsgId(RoutingMsgId)) {
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_SEND_INV_MSGID_EID, CFE_SB_BAD_ARGUMENT);
  } else {
    TxnPtr->RoutingMsgId = RoutingMsgId;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_MessageTxn_SetContentSize(CFE_SB_MessageTxn_State_t *TxnPtr, I64 ContentSize)
{
  if (ContentSize > CFE_MISSION_SB_MAX_SB_MSG_SIZE) {
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_MSG_TOO_BIG_EID, CFE_SB_MSG_TOO_BIG);
  } else {
    TxnPtr->ContentSize = ContentSize;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TransmitTxn_SetupFromMsg(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_MSG_Message *MsgPtr)
{
  I32 Status;
  I64 MsgSize;
  CFE_SB_MsgId MsgId;
  if (CFE_SB_MessageTxn_IsOK(TxnPtr)) {
    /* In this context, the user should have set the the size and MsgId in the content */
    Status = CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    if (Status == CFE_SUCCESS) {
      CFE_SB_MessageTxn_SetRoutingMsgId(TxnPtr, MsgId);
    } else {
      CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_SEND_BAD_ARG_EID, Status);
    }
  }
  if (CFE_SB_MessageTxn_IsOK(TxnPtr)) {
    Status = CFE_MSG_GetSize(MsgPtr, &MsgSize);
    if (Status == CFE_SUCCESS) {
      CFE_SB_MessageTxn_SetContentSize(TxnPtr, MsgSize);
    } else {
      CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_SEND_BAD_ARG_EID, Status);
    }
  }
}
/******************************************************************
 *
 * TRANSMIT TRANSACTION IMPLEMENTATION FUNCTIONS
 *
 ******************************************************************/
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_SB_MessageTxn_State_t *CFE_SB_TransmitTxn_Init(CFE_SB_TransmitTxn_State_t *TxnPtr, U8 *RefMemPtr)
{
  CFE_SB_MessageTxn_Init(&TxnPtr->MessageTxn_State, TxnPtr->DestSet, CFE_PLATFORM_SB_MAX_DEST_PER_PKT, RefMemPtr);
  TxnPtr->MessageTxn_State.IsTransmit = TRUE;
  /* No matter what, the mem pointer from the caller should not be NULL */
  if (RefMemPtr == NULL) {
    CFE_SB_MessageTxn_SetEventAndStatus(&TxnPtr->MessageTxn_State, CFE_SB_SEND_BAD_ARG_EID, CFE_SB_BAD_ARGUMENT);
  }
  return &TxnPtr->MessageTxn_State;
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// THE OPTIMISTIC HALF. The queue depth and the destination's buffer count go up HERE, before
// anything is written, because the write is expected to succeed; CFE_SB_TransmitTxn_PipeHandler
// undoes exactly these two when it does not. The message-limit check is also here rather than at
// the write, so a destination over its limit is recorded as a pipe error and the OTHER
// destinations still get the message.
U0 CFE_SB_TransmitTxn_AddDestination(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_DestinationD_t *DestPtr, CFE_SB_PipeD_t *PipeDscPtr, CFE_SB_BufferD_t *BufDscPtr)
{
  CFE_SB_PipeSetEntry_t *ContextPtr;
  ContextPtr = &TxnPtr->PipeSet[TxnPtr->NumPipes];
  ++TxnPtr->NumPipes;
  MemSet(ContextPtr, 0, sizeof(CFE_SB_PipeSetEntry_t));
  ContextPtr->PipeId = CFE_SB_PipeDescGetID(PipeDscPtr);
  ContextPtr->SysQueueId = PipeDscPtr->SysQueueId;
  /* if Msg limit exceeded, log event, increment counter */
  /* and go to next destination */
  if (DestPtr->BuffCount >= DestPtr->MsgId2PipeLim) {
    ContextPtr->PendingEventId = CFE_SB_MSGID_LIM_ERR_EID;
    ++CFE_SB_Global.HKTlmMsg.Payload.MsgLimitErrorCounter;
    ++PipeDscPtr->SendErrors;
    ++TxnPtr->NumPipeErrs;
  } else {
    CFE_SB_IncrBufUseCnt(BufDscPtr);
    ++DestPtr->BuffCount;
    ++PipeDscPtr->CurrentQueueDepth;
    if (PipeDscPtr->CurrentQueueDepth > PipeDscPtr->PeakQueueDepth) {
      PipeDscPtr->PeakQueueDepth = PipeDscPtr->CurrentQueueDepth;
    }
  }
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TransmitTxn_FindDestinations(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_BufferD_t *BufDscPtr)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_DestinationD_t *DestPtr;
  U32 AppId;
  Bool IsAcceptable;
  I32 Status;
  /*
   * get app id for loopback testing  -
   * This is only used if one or more of the destinations has its "IGNOREMINE" option set,
   * but it should NOT be gotten while locked.
   */
  CFE_ES_GetAppID(&AppId);
  /* take semaphore to prevent a task switch during processing */
  CFE_SB_LockSharedData("CFE_SB_TransmitTxn_FindDestinations", 1049);
  /* Get the routing id */
  BufDscPtr->DestRouteId = CFE_SBR_GetRouteId(TxnPtr->RoutingMsgId);
  /* For an invalid route / no subscribers this whole logic can be skipped */
  if (CFE_SBR_IsValidRouteId(BufDscPtr->DestRouteId)) {
    /* If this is the origination, then update the message content (while locked) */
    if (TxnPtr->IsEndpoint) {
      CFE_SBR_IncrementSequenceCounter(BufDscPtr->DestRouteId);
      /* Set the sequence count from the route */
      CFE_MSG_SetSequenceCount(&BufDscPtr->Content.Msg, CFE_SBR_GetSequenceCounter(BufDscPtr->DestRouteId));
    }
    /* Send the packet to all destinations  */
    DestPtr = CFE_SBR_GetDestListHeadPtr(BufDscPtr->DestRouteId);
    while (DestPtr != NULL && TxnPtr->NumPipes < TxnPtr->MaxPipes) {
      if (DestPtr->Active == CFE_SB_ACTIVE) {
        /* destination is active */
        PipeDscPtr = CFE_SB_LocatePipeDescByID(DestPtr->PipeId);
      } else {
        PipeDscPtr = NULL;
      }
      if (CFE_SB_PipeDescIsMatch(PipeDscPtr, DestPtr->PipeId)) {
        // IGNOREMINE is the loopback filter: a pipe with it set does not receive messages its
        // OWN app sent. That is why AppId was fetched before the lock.
        if ((PipeDscPtr->Opts & CFE_SB_PIPEOPTS_IGNOREMINE) == 0 || PipeDscPtr->AppId != AppId) {
          CFE_SB_TransmitTxn_AddDestination(TxnPtr, DestPtr, PipeDscPtr, BufDscPtr);
        }
      }
      DestPtr = DestPtr->Next;
    }
  } else {
    /* if there have been no subscriptions for this pkt, */
    /* increment the dropped pkt cnt, send event and return success */
    CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter++;
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_SEND_NO_SUBS_EID, CFE_SUCCESS);
  }
  /*
   * Remove this from whatever list it was in
   *
   * If it was a singleton/new buffer this has no effect.
   * If it was a zero-copy buffer this removes it from the ZeroCopyList.
   */
  CFE_SB_TrackingListRemove(&BufDscPtr->Link);
  /* clear the AppID field in case it was a zero copy buffer,
   * as it is no longer owned by that app after broadcasting */
  BufDscPtr->AppId = CFE_RESOURCEID_UNDEFINED;
  /* track the buffer as an in-transit message */
  CFE_SB_TrackingListAdd(&CFE_SB_Global.InTransitList, &BufDscPtr->Link);
  CFE_SB_UnlockSharedData("CFE_SB_TransmitTxn_FindDestinations", 1114);
  /*
   * Lastly, if this is the origination point, now that all headers should
   * have known values (including sequence) - invoke the mission-specific
   * message origination action.
   */
  if (CFE_SB_MessageTxn_IsOK(TxnPtr) && TxnPtr->IsEndpoint) {
    Status = CFE_MSG_OriginationAction(&BufDscPtr->Content.Msg, BufDscPtr->AllocatedSize, &IsAcceptable);
    if (Status != CFE_SUCCESS || !IsAcceptable) {
      CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, CFE_SB_SEND_MESSAGE_INTEGRITY_FAIL_EID, Status);
    }
  }
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// ONE TIMEOUT, RE-READ PER PIPE. In TIMED mode the remaining time is recomputed from the
// absolute deadline each time, so a fan-out to five pipes does not get five full timeouts -- and
// once the deadline has passed every remaining pipe degrades to OS_CHECK rather than failing.
I32 CFE_SB_MessageTxn_GetOsTimeout(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  I32 OsTimeout;
  OS_time_t TimeNow;
  switch (TxnPtr->TimeoutMode) {
    case CFE_SB_MessageTxn_TimeoutMode_PEND :
    OsTimeout = OS_PEND;
    break;
    case CFE_SB_MessageTxn_TimeoutMode_TIMED :
    CFE_PSP_GetTime(&TimeNow);
    OsTimeout = OS_TimeGetTotalMilliseconds(OS_TimeSubtract(TxnPtr->AbsTimeout, TimeNow));
    if (OsTimeout < 0) {
      /* timeout has already expired, so all remaining pipes should be CHECK only */
      OsTimeout = OS_CHECK;
    }
    break;
    case CFE_SB_MessageTxn_TimeoutMode_POLL :
    default:
    OsTimeout = OS_CHECK;
    break;
  }
  return OsTimeout;
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// THE PESSIMISTIC HALF, and it undoes precisely what AddDestination did: the pipe's queue depth
// and the destination's buffer count, each guarded by a > 0 test because the pipe may have been
// deleted or the subscription dropped since. Returns TRUE always: a broadcast keeps going.
Bool CFE_SB_TransmitTxn_PipeHandler(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *ContextPtr, U8 *Arg)
{
  CFE_SB_DestinationD_t *DestPtr;
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_BufferD_t *BufDscPtr;
  BufDscPtr = Arg;
  /*
   * Write the buffer descriptor to the queue of the pipe.  Note that
   * accounting for depth and buffer limits was already done as part
   * of "FindDestinations" assuming this write will be successful.
   */
  ContextPtr->OsStatus = OS_QueuePut(ContextPtr->SysQueueId, &BufDscPtr, sizeof(BufDscPtr), CFE_SB_MessageTxn_GetOsTimeout(TxnPtr));
  /*
   * If it succeeded, nothing else to do.  But if it fails then we must undo the
   * optimistic depth accounting done earlier.
   */
  if (ContextPtr->OsStatus != OS_SUCCESS) {
    ++TxnPtr->NumPipeErrs;
    CFE_SB_LockSharedData("CFE_SB_TransmitTxn_PipeHandler", 1198);
    if (ContextPtr->OsStatus == OS_QUEUE_FULL) {
      ContextPtr->PendingEventId = CFE_SB_Q_FULL_ERR_EID;
      CFE_SB_Global.HKTlmMsg.Payload.PipeOverflowErrorCounter++;
    } else {
      /* Unexpected error while writing to queue. */
      ContextPtr->PendingEventId = CFE_SB_Q_WR_ERR_EID;
      CFE_SB_Global.HKTlmMsg.Payload.InternalErrorCounter++;
    }
    PipeDscPtr = CFE_SB_LocatePipeDescByID(ContextPtr->PipeId);
    if (CFE_SB_PipeDescIsMatch(PipeDscPtr, ContextPtr->PipeId) && PipeDscPtr->CurrentQueueDepth > 0) {
      --PipeDscPtr->CurrentQueueDepth;
    }
    DestPtr = CFE_SB_GetDestPtr(BufDscPtr->DestRouteId, ContextPtr->PipeId);
    if (DestPtr != NULL && DestPtr->BuffCount > 0) {
      DestPtr->BuffCount--;
    }
    CFE_SB_DecrBufUseCnt(BufDscPtr);
    CFE_SB_UnlockSharedData("CFE_SB_TransmitTxn_PipeHandler", 1226);
  }
  /* always keep going when sending (broadcast) */
  return TRUE;
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// THE ONE PLACE THE TWO DIRECTIONS MEET. HandlerFunc is a function POINTER -- NASA's
// CFE_SB_MessageTxn_PipeHandler_t, spelled out here because HolyC has no typedef -- and its
// return value is the loop's continue condition: transmit returns TRUE to broadcast on, receive
// returns FALSE because a read services one pipe. A pipe that already has a pending event is
// SKIPPED rather than retried.
U0 CFE_SB_MessageTxn_ProcessPipes(Bool (*HandlerFunc)(CFE_SB_MessageTxn_State_t *, CFE_SB_PipeSetEntry_t *, U8 *), CFE_SB_MessageTxn_State_t *TxnPtr, U8 *Arg)
{
  U32 i;
  CFE_SB_PipeSetEntry_t *ContextPtr;
  Bool should_continue;
  should_continue = TRUE;
  for (i = 0; should_continue && i < TxnPtr->NumPipes; ++i) {
    ContextPtr = &TxnPtr->PipeSet[i];
    if (ContextPtr->PendingEventId == 0) {
      should_continue = HandlerFunc(TxnPtr, ContextPtr, Arg);
    }
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TransmitTxn_Execute(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_Buffer *BufPtr)
{
  I32 Status;
  CFE_SB_BufferD_t *BufDscPtr;
  /* Sanity check on the input buffer - if this doesn't work, stop now */
  Status = CFE_SB_ZeroCopyBufferValidate(BufPtr, &BufDscPtr);
  if (Status != CFE_SUCCESS) {
    /* There is currently no event defined for this */
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, 0, Status);
    return;
  }
  /* Save passed-in routing parameters into the descriptor */
  BufDscPtr->ContentSize = CFE_SB_MessageTxn_GetContentSize(TxnPtr);
  BufDscPtr->MsgId = CFE_SB_MessageTxn_GetRoutingMsgId(TxnPtr);
  /* Convert the route to a set of pipes/destinations */
  CFE_SB_TransmitTxn_FindDestinations(TxnPtr, BufDscPtr);
  /* Note the above function always succeeds - even if no pipes are subscribed,
   * the transaction will simply have 0 pipes and this next call becomes a no-op */
  CFE_SB_MessageTxn_ProcessPipes(&CFE_SB_TransmitTxn_PipeHandler, TxnPtr, BufDscPtr);
  /*
   * Decrement the buffer UseCount - This means that the caller
   * should not use the buffer anymore after this call.
   */
  CFE_SB_LockSharedData("CFE_SB_TransmitTxn_Execute", 1294);
  CFE_SB_DecrBufUseCnt(BufDscPtr);
  CFE_SB_UnlockSharedData("CFE_SB_TransmitTxn_Execute", 1296);
}
/******************************************************************
 *
 * RECEIVE TRANSACTION IMPLEMENTATION FUNCTIONS
 *
 ******************************************************************/
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_SB_MessageTxn_State_t *CFE_SB_ReceiveTxn_Init(CFE_SB_ReceiveTxn_State_t *TxnPtr, U8 *RefMemPtr)
{
  CFE_SB_MessageTxn_Init(&TxnPtr->MessageTxn_State, &TxnPtr->Source, 1, RefMemPtr);
  TxnPtr->MessageTxn_State.IsTransmit = FALSE;
  /* No matter what, the mem pointer from the caller should not be NULL */
  /* note that the event ID is different between send and recv */
  if (RefMemPtr == NULL) {
    CFE_SB_MessageTxn_SetEventAndStatus(&TxnPtr->MessageTxn_State, CFE_SB_RCV_BAD_ARG_EID, CFE_SB_BAD_ARGUMENT);
  }
  return &TxnPtr->MessageTxn_State;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_MessageTxn_SetEndpoint(CFE_SB_MessageTxn_State_t *TxnPtr, Bool IsEndpoint)
{
  TxnPtr->IsEndpoint = IsEndpoint;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// SETTING THE PIPE ALSO RELEASES THE PREVIOUS BUFFER, and NASA's comment explains why: apps call
// CFE_SB_ReceiveBuffer in a loop and there is no separate "I am done with that one" call, so
// each receive is read as an implicit release of the last. NASA also records the cost -- it
// prevents several child tasks sharing one pipe in a worker pattern.
U0 CFE_SB_ReceiveTxn_SetPipeId(CFE_SB_MessageTxn_State_t *TxnPtr, U32 PipeId)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_PipeSetEntry_t *ContextPtr;
  /* For now, there is just one of these */
  ContextPtr = TxnPtr->PipeSet;
  MemSet(ContextPtr, 0, sizeof(CFE_SB_PipeSetEntry_t));
  ContextPtr->PipeId = PipeId;
  TxnPtr->NumPipes = 1;
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  CFE_SB_LockSharedData("CFE_SB_ReceiveTxn_SetPipeId", 1356);
  /* If the pipe does not exist or PipeId is out of range... */
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    ContextPtr->PendingEventId = CFE_SB_BAD_PIPEID_EID;
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, 0, CFE_SB_BAD_ARGUMENT);
    ++TxnPtr->NumPipeErrs;
  } else {
    ContextPtr->SysQueueId = PipeDscPtr->SysQueueId;
    /*
     * Un-reference any previous buffer from the last call.
     */
    if (PipeDscPtr->LastBuffer != NULL) {
      /* Decrement the Buffer Use Count, which will Free buffer if it becomes 0 */
      CFE_SB_DecrBufUseCnt(PipeDscPtr->LastBuffer);
      PipeDscPtr->LastBuffer = NULL;
    }
  }
  CFE_SB_UnlockSharedData("CFE_SB_ReceiveTxn_SetPipeId", 1392);
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// TWO REFERENCES CHANGE HANDS HERE. The buffer gains one because the pipe descriptor now holds
// it in LastBuffer, and loses one because the reference that was sitting in the queue is gone --
// so a buffer read by its only subscriber ends at a use count of one, owned by the pipe, and is
// freed by the NEXT receive on that pipe. The unconditional decrement at the end is the queue's
// reference; the conditional increment above it is the pipe's.
U0 CFE_SB_ReceiveTxn_ExportReference(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *ContextPtr, CFE_SB_BufferD_t *BufDscPtr, CFE_SB_BufferD_t **ParentBufDscPtrP)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_DestinationD_t *DestPtr;
  PipeDscPtr = CFE_SB_LocatePipeDescByID(ContextPtr->PipeId);
  /* Now re-lock to store the buffer in the pipe descriptor */
  CFE_SB_LockSharedData("CFE_SB_ReceiveTxn_ExportReference", 1412);
  /*
   * NOTE: This uses the same PipeDscPtr that was found earlier.
   * But it has to be revalidated because its theoretically possible
   * the pipe got deleted between now and then.
   */
  if (CFE_SB_PipeDescIsMatch(PipeDscPtr, ContextPtr->PipeId)) {
    /*
    ** Load the pipe tables 'CurrentBuff' with the buffer descriptor
    ** ptr corresponding to the message just read.
    */
    CFE_SB_IncrBufUseCnt(BufDscPtr);
    PipeDscPtr->LastBuffer = BufDscPtr;
    /*
     * Also set the Receivers pointer to the address of the actual message
     */
    *ParentBufDscPtrP = BufDscPtr;
    /* get pointer to destination to be used in decrementing msg limit cnt*/
    DestPtr = CFE_SB_GetDestPtr(BufDscPtr->DestRouteId, ContextPtr->PipeId);
    /*
    ** DestPtr would be NULL if the msg is unsubscribed to while it is on
    ** the pipe. The BuffCount may be zero if the msg is unsubscribed to and
    ** then resubscribed to while it is on the pipe. Both of these cases are
    ** considered nominal and are handled by the code below.
    */
    if (DestPtr != NULL && DestPtr->BuffCount > 0) {
      DestPtr->BuffCount--;
    }
    if (PipeDscPtr->CurrentQueueDepth > 0) {
      --PipeDscPtr->CurrentQueueDepth;
    }
  } else {
    CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, 0, CFE_SB_PIPE_RD_ERR);
    /* should send the bad pipe ID event here too */
    ContextPtr->PendingEventId = CFE_SB_BAD_PIPEID_EID;
  }
  /* Always decrement the use count, for the ref that was in the queue */
  CFE_SB_DecrBufUseCnt(BufDscPtr);
  CFE_SB_UnlockSharedData("CFE_SB_ReceiveTxn_ExportReference", 1467);
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
// AN EMPTY QUEUE AND A TIMEOUT ARE NOT ERRORS. Both set a status and NO pending event, because
// polling an empty pipe is the normal use of CFE_SB_POLL and a timeout is the normal use of a
// nonzero one. Only the third branch -- anything else from the queue -- raises an event.
Bool CFE_SB_ReceiveTxn_PipeHandler(CFE_SB_MessageTxn_State_t *TxnPtr, CFE_SB_PipeSetEntry_t *ContextPtr, U8 *Arg)
{
  CFE_SB_BufferD_t *BufDscPtr = NULL;
  CFE_SB_BufferD_t **ParentBufDscPtrP;
  I64 BufDscSize;
  ParentBufDscPtrP = Arg;
  /* Read the buffer descriptor address from the queue.  */
  ContextPtr->OsStatus = OS_QueueGet(ContextPtr->SysQueueId, &BufDscPtr, sizeof(BufDscPtr), &BufDscSize, CFE_SB_MessageTxn_GetOsTimeout(TxnPtr));
  /*
   * translate the return value -
   *
   * CFE functions have their own set of RC values should not directly return OSAL codes
   * The size should always match.  If it does not, then generate CFE_SB_Q_RD_ERR_EID.
   */
  if (ContextPtr->OsStatus == OS_SUCCESS && BufDscPtr != NULL && BufDscSize == sizeof(BufDscPtr)) {
    CFE_SB_ReceiveTxn_ExportReference(TxnPtr, ContextPtr, BufDscPtr, ParentBufDscPtrP);
  } else {
    *ParentBufDscPtrP = NULL;
    if (ContextPtr->OsStatus == OS_QUEUE_EMPTY) {
      /* normal if using CFE_SB_POLL */
      CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, 0, CFE_SB_NO_MESSAGE);
    } else if (ContextPtr->OsStatus == OS_QUEUE_TIMEOUT) {
      /* normal if using a nonzero timeout */
      CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, 0, CFE_SB_TIME_OUT);
    } else {
      /* off-nominal condition, report an error event */
      CFE_SB_MessageTxn_SetEventAndStatus(TxnPtr, 0, CFE_SB_PIPE_RD_ERR);
      ContextPtr->PendingEventId = CFE_SB_Q_RD_ERR_EID;
    }
  }
  /* Read ops only process one pipe */
  return FALSE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A LOOP, because a message that FAILS VERIFICATION is dropped and the next one is read. The
// re-call to SetPipeId at the bottom is not a reset: it is what releases the rejected buffer,
// since SetPipeId's other job is un-referencing the previous one.
CFE_SB_Buffer *CFE_SB_ReceiveTxn_Execute(CFE_SB_MessageTxn_State_t *TxnPtr)
{
  CFE_SB_BufferD_t *BufDscPtr;
  CFE_SB_Buffer *Result;
  Bool IsAcceptable;
  I32 Status;
  Result = NULL;
  while (CFE_SB_MessageTxn_IsOK(TxnPtr)) {
    BufDscPtr = NULL;
    /*
     * Read from the pipe(s).  Currently this is just one but someday could
     * become more than one e.g. a high-pri and a low-pri queue.
     */
    CFE_SB_MessageTxn_ProcessPipes(&CFE_SB_ReceiveTxn_PipeHandler, TxnPtr, &BufDscPtr);
    /* If nothing received, then quit */
    if (BufDscPtr == NULL) {
      TxnPtr->RoutingMsgId = CFE_SB_InvalidMsgId;
      TxnPtr->ContentSize = 0;
      Result = NULL;
      break;
    }
    if (TxnPtr->IsEndpoint) {
      Status = CFE_MSG_VerificationAction(&BufDscPtr->Content.Msg, BufDscPtr->AllocatedSize, &IsAcceptable);
      if (Status != CFE_SUCCESS) {
        /* This typically should not happen - only if VerificationAction got bad arguments */
        IsAcceptable = FALSE;
      }
    } else {
      /* If no verification being done at this stage - consider everything "good" */
      IsAcceptable = TRUE;
    }
    if (IsAcceptable) {
      /*
       * Replicate the buffer descriptor MsgId and ContentSize in the transaction.
       *
       * This does not use the functions that check the values because that will
       * send an event and set an error status if they are bad.  But on the recv side,
       * it is already here - whatever we got should be returned.
       */
      TxnPtr->RoutingMsgId = BufDscPtr->MsgId;
      TxnPtr->ContentSize = BufDscPtr->ContentSize;
      Result = &BufDscPtr->Content;
      break;
    }
    /* Report an event indicating the buffer is being dropped */
    CFE_SB_MessageTxn_ReportSingleEvent(TxnPtr, TxnPtr->PipeSet, CFE_SB_RCV_MESSAGE_INTEGRITY_FAIL_EID);
    /*
     * Also need to re-set the PipeId for proper accounting.  This buffer will be dropped,
     * and this decrements the use count and removes it from the LastBuffer pointer in the
     * Pipe Descriptor
     */
    CFE_SB_ReceiveTxn_SetPipeId(TxnPtr, TxnPtr->PipeSet->PipeId);
  }
  return Result;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_GetPipeNamePriv(U32 PipeId, U8 *PipeNameBuf, I64 PipeNameSize)
{
  I32 OsStatus;
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 SysQueueId;
  I32 Status;
  Status = CFE_SUCCESS;
  SysQueueId = OS_OBJECT_ID_UNDEFINED;
  /* take semaphore to prevent a task switch during this call */
  CFE_SB_LockSharedData("CFE_SB_GetPipeNamePriv", 1625);
  /* check input parameter */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    SysQueueId = PipeDscPtr->SysQueueId;
  }
  CFE_SB_UnlockSharedData("CFE_SB_GetPipeNamePriv", 1638);
  if (Status == CFE_SUCCESS) {
    OsStatus = OS_GetResourceName(SysQueueId, PipeNameBuf, PipeNameSize);
    if (OsStatus != OS_SUCCESS) {
      Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  } else {
    MemSet(PipeNameBuf, 0, PipeNameSize);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// SIX EVENTS MEAN "SUBSCRIBE FAILED" AND ONE MEANS "ALREADY SUBSCRIBED", and they land in
// different counters -- a duplicate subscription is not an error, it is a thing worth counting.
U0 CFE_SB_IncrementSubscribeCounters(U16 EventID)
{
  switch (EventID) {
    case CFE_SB_SUB_INV_PIPE_EID :
    case CFE_SB_SUB_INV_CALLER_EID :
    case CFE_SB_SUB_ARG_ERR_EID :
    case CFE_SB_MAX_MSGS_MET_EID :
    case CFE_SB_MAX_DESTS_MET_EID :
    case CFE_SB_DEST_BLK_ERR_EID :
    CFE_SB_Global.HKTlmMsg.Payload.SubscribeErrorCounter++;
    break;
    case CFE_SB_DUP_SUBSCRIP_EID :
    CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter++;
    break;
    default:
    /* If there isn't an error, don't increment error counters */
    break;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_IssueSubscribeEvents(U16 PendingEventID, U32 PipeId, CFE_SB_MsgId MsgId, U16 Scope)
{
  U32 TskId;
  U8 FullName[OS_MAX_API_NAME * 2];
  U8 PipeName[OS_MAX_API_NAME];
  switch (PendingEventID) {
    case CFE_SB_DUP_SUBSCRIP_EID :
    CFE_ES_GetTaskID(&TskId);
    CFE_SB_GetPipeName(PipeName, sizeof(PipeName), PipeId);
    CFE_EVS_SendEventWithAppID(CFE_SB_DUP_SUBSCRIP_EID, CFE_EVS_EventType_INFORMATION, CFE_SB_Global.AppId, "Duplicate Subscription,MsgId 0x%x on %s pipe,app %s", CFE_SB_MsgIdToValue(MsgId), PipeName, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_SUB_INV_CALLER_EID :
    CFE_ES_GetTaskID(&TskId);
    CFE_EVS_SendEventWithAppID(CFE_SB_SUB_INV_CALLER_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Subscribe Err:Caller(%s) is not the owner of pipe %u,Msg=0x%x", CFE_SB_GetAppTskName(TskId, FullName), PipeId, CFE_SB_MsgIdToValue(MsgId));
    break;
    case CFE_SB_SUB_INV_PIPE_EID :
    CFE_ES_GetTaskID(&TskId);
    CFE_EVS_SendEventWithAppID(CFE_SB_SUB_INV_PIPE_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Subscribe Err:Invalid Pipe Id,Msg=0x%x,PipeId=%u,App %s", CFE_SB_MsgIdToValue(MsgId), PipeId, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_DEST_BLK_ERR_EID :
    CFE_EVS_SendEventWithAppID(CFE_SB_DEST_BLK_ERR_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Subscribe Err:Request for Destination Blk failed for Msg 0x%x", CFE_SB_MsgIdToValue(MsgId));
    break;
    case CFE_SB_MAX_DESTS_MET_EID :
    CFE_ES_GetTaskID(&TskId);
    CFE_SB_GetPipeName(PipeName, sizeof(PipeName), PipeId);
    CFE_EVS_SendEventWithAppID(CFE_SB_MAX_DESTS_MET_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Subscribe Err:Max Dests(%d)In Use For Msg 0x%x,pipe %s,app %s", CFE_PLATFORM_SB_MAX_DEST_PER_PKT, CFE_SB_MsgIdToValue(MsgId), PipeName, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_MAX_MSGS_MET_EID :
    CFE_ES_GetTaskID(&TskId);
    CFE_SB_GetPipeName(PipeName, sizeof(PipeName), PipeId);
    CFE_EVS_SendEventWithAppID(CFE_SB_MAX_MSGS_MET_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Subscribe Err:Max Msgs(%d)In Use,MsgId 0x%x,pipe %s,app %s", CFE_PLATFORM_SB_MAX_MSG_IDS, CFE_SB_MsgIdToValue(MsgId), PipeName, CFE_SB_GetAppTskName(TskId, FullName));
    break;
    case CFE_SB_SUB_ARG_ERR_EID :
    CFE_ES_GetTaskID(&TskId);
    CFE_EVS_SendEventWithAppID(CFE_SB_SUB_ARG_ERR_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Subscribe Err:Bad Arg,MsgId 0x%x,PipeId %u,app %s,scope %d", CFE_SB_MsgIdToValue(MsgId), PipeId, CFE_SB_GetAppTskName(TskId, FullName), Scope);
    break;
    default:
    /* No error means no event issued */
    break;
  }
}
#endif
