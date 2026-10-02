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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_api.c -- THE SOFTWARE BUS'S PUBLIC API.
// Twenty-five functions: create and delete a pipe, subscribe and unsubscribe, allocate and
// release a buffer, transmit and receive.
//
// THIS IS THE FILE EVERY OTHER MODULE WAS STUBBED AGAINST. CFE_SB_TransmitMsg,
// CFE_SB_CreatePipe, CFE_SB_Subscribe and CFE_SB_ReceiveBuffer are recording stubs in the
// differential driver for config, fs, ta, evs and time; with this translated they become real
// code on both sides of the comparison.
//
// AND THE FOUR BUSIEST FUNCTIONS ARE NEARLY EMPTY, which is the shape to notice. TransmitMsg,
// TransmitBuffer, ReceiveBuffer and their WithRoute variants are each a dozen lines over the
// transaction machinery in cfe_sb_priv.HC: init, set up, execute, report, return the status.
// All of the fan-out, the optimistic accounting and the per-pipe error handling lives there.
// What is here is the PUBLIC contract -- argument checking, resource lifetime and the events.
//
// THE EVENT-AT-THE-END PATTERN IS DELIBERATE AND WORTH KEEPING. Every function in this file
// records a PendingEventID while holding the shared-data lock and sends the event after
// releasing it, because sending an event goes through SB and taking the lock twice would
// deadlock. Each `switch (PendingEventID)` at the bottom of a function is that, not a style.
#ifndef CFE_SB_API_HC
#define CFE_SB_API_HC
#include "cfe_sb_priv.HC" // the pipe table, the destination list and the transaction machine
// --- cfe_sb_eventids.h: the twenty this file raises -------------------------------------------
#define CFE_SB_CR_PIPE_BAD_ARG_EID          2
#define CFE_SB_MAX_PIPES_MET_EID            3
#define CFE_SB_CR_PIPE_ERR_EID              4
#define CFE_SB_PIPE_ADDED_EID               5
#define CFE_SB_HASHCOLLISION_EID            23
#define CFE_SB_SUBSCRIPTION_RCVD_EID        10
#define CFE_SB_UNSUB_ARG_ERR_EID            11
#define CFE_SB_UNSUB_NO_SUBS_EID            12
#define CFE_SB_DEL_PIPE_ERR1_EID            46
#define CFE_SB_PIPE_DELETED_EID             47
#define CFE_SB_SUBSCRIPTION_REMOVED_EID     48
#define CFE_SB_UNSUB_INV_PIPE_EID           52
#define CFE_SB_UNSUB_INV_CALLER_EID         53
#define CFE_SB_DEL_PIPE_ERR2_EID            54
#define CFE_SB_SETPIPEOPTS_ID_ERR_EID       55
#define CFE_SB_SETPIPEOPTS_OWNER_ERR_EID    56
#define CFE_SB_SETPIPEOPTS_EID              57
#define CFE_SB_GETPIPEOPTS_ID_ERR_EID       58
#define CFE_SB_GETPIPEOPTS_PTR_ERR_EID      59
#define CFE_SB_GETPIPEOPTS_EID              60
#define CFE_SB_GETPIPENAME_EID              62
#define CFE_SB_GETPIPENAME_NULL_PTR_EID     63
#define CFE_SB_GETPIPENAME_ID_ERR_EID       64
#define CFE_SB_GETPIPEIDBYNAME_EID          65
#define CFE_SB_GETPIPEIDBYNAME_NULL_ERR_EID 66
#define CFE_SB_GETPIPEIDBYNAME_NAME_ERR_EID 67
#define CFE_SB_CR_PIPE_NAME_TAKEN_EID       69
#define CFE_SB_CR_PIPE_NO_FREE_EID          70
// --- cfe_sb_api_typedefs.h: the "no pipe" id ------------------------------------------------
// NASA writes CFE_SB_PIPEID_C(CFE_RESOURCEID_UNDEFINED); the wrapper is the identity for the
// SIMPLE resourceid variant this port builds, so the value is the undefined id itself. Every
// function in this file that takes a pipe id rejects it, which is what makes it worth naming.
#define CFE_SB_INVALID_PIPE CFE_RESOURCEID_UNDEFINED
// --- cfe_core_resourceid_basevalues.h: where an APP id starts --------------------------------
// CFE_SB_DeletePipeFull compares the caller's app id against the pipe's owner, so an exercise
// of that refusal needs a second app id -- and an app id is not an integer, it is a value in
// this space. NASA's is an ENUMERATOR rather than a #define, which is a shape this project has
// been bitten by before (a gate looking for a #define passes by not finding one), so it is
// written here the same way cfe_sb_global.HC writes the pipe-id base.
#define CFE_RESOURCEID_ES_APPID_BASE_OFFSET (OS_OBJECT_TYPE_USER + 1)
#define CFE_ES_APPID_BASE CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_ES_APPID_BASE_OFFSET)
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_SB_MAX_PIPES_MET 0xCA000004(I32)
#define CFE_SB_PIPE_CR_ERR   0xCA000005(I32)
#define CFE_SB_BUF_ALOC_ERR  0xCA000008(I32)
#define CFE_SB_MAX_MSGS_MET  0xCA000009(I32)
#define CFE_SB_MAX_DESTS_MET 0xCA00000A(I32)
// --- osconfig.h / cfe_resourceid.h ------------------------------------------------------------
// osapi-error.h: the three OSAL codes CFE_SB_CreatePipe branches on, each with its own event.
// cfe_sb_priv.HC already carries the queue-state codes; these are the IDENTITY ones.
#ifndef OS_ERR_NO_FREE_IDS
#define OS_ERR_NO_FREE_IDS    -14
#define OS_ERR_NAME_TAKEN     -15
#define OS_ERR_INVALID_ID     -16
#define OS_ERR_NAME_NOT_FOUND -17
#endif
#ifndef CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT
#define CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT 4
#endif
#ifndef OS_QUEUE_MAX_DEPTH
#define OS_QUEUE_MAX_DEPTH 50
#endif
// CFE_RESOURCEID_RESERVED marks a table slot as TAKEN BUT NOT YET VALID, which is what lets
// CreatePipe and DeletePipeFull drop the lock while they talk to OSAL: another task finds the
// slot occupied and will not reuse it, and no one can subscribe to a half-built pipe.
#ifndef CFE_RESOURCEID_RESERVED
#define CFE_RESOURCEID_RESERVED 0xFFFFFFFF
#endif
#ifndef CFE_ES_TASKID_UNDEFINED
#define CFE_ES_TASKID_UNDEFINED CFE_RESOURCEID_UNDEFINED
#define CFE_ES_APPID_UNDEFINED  CFE_RESOURCEID_UNDEFINED
#endif
// --- cfe_sb_priv.h: the callback argument ----------------------------------------------------
// CFE_SBR_ForEachRouteId takes a callback and a void*; this is what DeletePipeFull passes
// through it, so the callback can know which pipe is going away.
class CFE_SB_RemovePipeCallback_t
{
  U8 *FullName;
  // Full name (app.task) for error reporting
  U32 PipeId;
  // Pipe id to remove -- CFE_SB_PipeId_t
  U8 _pad0[4];
  // C's tail padding: the struct aligns to its pointer member, so sizeof is 16, not 12
};
// --- what this file needs from elsewhere ------------------------------------------------------
// Declared here and defined below, because the C's order has each used above its definition.
I32 CFE_SB_DeletePipeFull(U32 PipeId, U32 AppId);
I32 CFE_SB_SubscribeFull(CFE_SB_MsgId MsgId, U32 PipeId, CFE_SB_Qos_t Quality, U16 MsgLim,
                         U8 Scope);
I32 CFE_SB_UnsubscribeFull(CFE_SB_MsgId MsgId, U32 PipeId, U8 Scope, U32 AppId);
CFE_SB_Buffer *CFE_SB_AllocateMessageBuffer(I64 MsgSize);
I32 CFE_SB_GetPipeName(U8 *PipeNameBuf, I64 PipeNameSize, U32 PipeId);
// cfe_sb_task.c, not yet translated -- SubscribeFull reports every GLOBAL subscription on the
// bus so that other processors can mirror the route.
I32 CFE_SB_SendSubscriptionReport(CFE_SB_MsgId MsgId, U32 PipeId, CFE_SB_Qos_t Quality);
// OSAL's QUEUE API, and these three are declared HERE rather than relied on from the chain:
// osapi_queue.HC belongs to the OSAL translation, which is a separate gate with a separate
// build, so the cFE side has to name what it calls. The signatures are copied from there, and
// a disagreement would be invisible -- see docs/HOLYC_STRUCT_LIMITS.md on what an unresolved
// name does instead of erroring.
I32 OS_QueueCreate(U32 *queue_id, U8 *queue_name, I64 queue_depth, I64 data_size, U32 flags);
I32 OS_QueueDelete(U32 queue_id);
I32 OS_QueueGetIdByName(U32 *queue_id, U8 *queue_name);
U8 *MemCpy(U8 *dst, U8 *src, I64 size);
// NOT redeclared here, deliberately: CFE_ES_GetAppName, CFE_ResourceId_FindNext,
// CFE_ResourceId_ToIndex and CFE_SBR_ForEachRouteId all arrive through the include chain
// (cfe_evs_utils.HC, cfe_resourceid.HC, the SBR route module). A second declaration that
// disagreed with the definition on a parameter width or a function-pointer arity is precisely
// the shape HolyC does not diagnose -- the first draft of this file had one, declaring
// CFE_SBR_ForEachRouteId's throttle argument as U8 * where the definition says
// CFE_SBR_Throttle *.

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_PipeId_ToIndex(U32 PipeID, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(PipeID, CFE_SB_PIPEID_BASE, CFE_PLATFORM_SB_MAX_PIPES, Idx);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THREE LOCKED SECTIONS AND ONE OSAL CALL BETWEEN THEM. The slot is reserved under the first
// lock, OS_QueueCreate runs UNLOCKED because it may block, and the second lock either fills the
// descriptor in or frees the slot again. Doing the queue create while locked would hold the bus
// against every other task for the duration of an OS call.
I32 CFE_SB_CreatePipe(U32 *PipeIdPtr, U16 Depth, U8 *PipeName)
{
  U32 AppId;
  U32 TskId;
  U32 SysQueueId;
  I32 OsStatus;
  I32 Status;
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 PendingPipeId = CFE_RESOURCEID_UNDEFINED;
  U16 PendingEventId;
  U8 FullName[OS_MAX_API_NAME * 2];
  Status = CFE_SUCCESS;
  SysQueueId = OS_OBJECT_ID_UNDEFINED;
  PendingEventId = 0;
  PipeDscPtr = NULL;
  OsStatus = OS_SUCCESS;
  /*
   * Get caller AppId.
   *
   * This is needed for both success and failure cases,
   * as it is stored in the Pipe Descriptor on success,
   * and used for events on failure,  so get it now.
   */
  CFE_ES_GetAppID(&AppId);
  /* get callers TaskId */
  CFE_ES_GetTaskID(&TskId);
  /* check input parameters */
  // THE WHOLE OF THIS BRANCH IS OFF-LIMITS TO THE DIFFERENTIAL DRIVER, not just the NULL case.
  // All four conditions land on CFE_SB_CR_PIPE_BAD_ARG_EID, whose text prints `ptr=0x%lx` -- the
  // address of the caller's variable. A host process and a QEMU guest put that variable at
  // different addresses, so even `Depth = 0` with a perfectly valid pointer produces two
  // different transcript lines and a failure that has nothing to do with the translation. The
  // Depth=0 case is the obvious one to add; this comment is here so the next person does not.
  if (PipeIdPtr == NULL || Depth > OS_QUEUE_MAX_DEPTH || Depth == 0 ||
      (PipeName != NULL && PipeName[0] == 0)) {
    PendingEventId = CFE_SB_CR_PIPE_BAD_ARG_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    /* Get an available Pipe Descriptor which must be done while locked */
    CFE_SB_LockSharedData("CFE_SB_CreatePipe", 0);
    /* get first available entry in pipe table */
    PendingPipeId = CFE_ResourceId_FindNext(CFE_SB_Global.LastPipeId, CFE_PLATFORM_SB_MAX_PIPES,
                                            &CFE_SB_CheckPipeDescSlotUsed);
    PipeDscPtr = CFE_SB_LocatePipeDescByID(PendingPipeId);
    /* if pipe table is full, send event and return error */
    if (PipeDscPtr == NULL) {
      PendingEventId = CFE_SB_MAX_PIPES_MET_EID;
      Status = CFE_SB_MAX_PIPES_MET;
    } else {
      /* Fully clear the entry, just in case of stale data */
      MemSet(PipeDscPtr, 0, sizeof(CFE_SB_PipeD_t));
      CFE_SB_PipeDescSetUsed(PipeDscPtr, CFE_RESOURCEID_RESERVED);
      CFE_SB_Global.LastPipeId = PendingPipeId;
    }
    CFE_SB_UnlockSharedData("CFE_SB_CreatePipe", 0);
  }
  if (Status == CFE_SUCCESS) {
    /* create the queue */
    OsStatus = OS_QueueCreate(&SysQueueId, PipeName, Depth, sizeof(CFE_SB_BufferD_t *), 0);
    if (OsStatus != OS_SUCCESS) {
      if (OsStatus == OS_ERR_NAME_TAKEN) {
        PendingEventId = CFE_SB_CR_PIPE_NAME_TAKEN_EID;
      } else if (OsStatus == OS_ERR_NO_FREE_IDS) {
        PendingEventId = CFE_SB_CR_PIPE_NO_FREE_EID;
      } else {
        /* some other unexpected error */
        PendingEventId = CFE_SB_CR_PIPE_ERR_EID;
      }
      /* translate OSAL error to CFE error code */
      Status = CFE_SB_PIPE_CR_ERR;
    }
  }
  CFE_SB_LockSharedData("CFE_SB_CreatePipe", 0);
  if (Status == CFE_SUCCESS) {
    /* fill in the pipe table fields */
    PipeDscPtr->SysQueueId = SysQueueId;
    PipeDscPtr->MaxQueueDepth = Depth;
    PipeDscPtr->AppId = AppId;
    CFE_SB_PipeDescSetUsed(PipeDscPtr, PendingPipeId);
    /* Increment the Pipes in use ctr and if it's > the high water mark,*/
    /* adjust the high water mark */
    CFE_SB_Global.StatTlmMsg.Payload.PipesInUse++;
    if (CFE_SB_Global.StatTlmMsg.Payload.PipesInUse >
        CFE_SB_Global.StatTlmMsg.Payload.PeakPipesInUse) {
      CFE_SB_Global.StatTlmMsg.Payload.PeakPipesInUse =
          CFE_SB_Global.StatTlmMsg.Payload.PipesInUse;
    }
  } else {
    /*
     * If a descriptor had been allocated, then free it.
     */
    if (PipeDscPtr != NULL) {
      CFE_SB_PipeDescSetFree(PipeDscPtr);
      PipeDscPtr = NULL;
    }
    PendingPipeId = CFE_RESOURCEID_UNDEFINED;
    /* Increment error counter for all errors */
    CFE_SB_Global.HKTlmMsg.Payload.CreatePipeErrorCounter++;
  }
  CFE_SB_UnlockSharedData("CFE_SB_CreatePipe", 0);
  /* Send any pending events now, after final unlock */
  switch (PendingEventId) {
    case CFE_SB_CR_PIPE_BAD_ARG_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_CR_PIPE_BAD_ARG_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "CreatePipeErr:Bad Input Arg:app=%s,ptr=0x%lx,depth=%d,maxdepth=%d",
                                 CFE_SB_GetAppTskName(TskId, FullName), PipeIdPtr, Depth,
                                 OS_QUEUE_MAX_DEPTH);
      break;
    case CFE_SB_MAX_PIPES_MET_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_MAX_PIPES_MET_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId, "CreatePipeErr:Max Pipes(%d)In Use.app %s",
                                 CFE_PLATFORM_SB_MAX_PIPES,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_CR_PIPE_NAME_TAKEN_EID:
      CFE_EVS_SendEventWithAppID(
          CFE_SB_CR_PIPE_NAME_TAKEN_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId,
          "CreatePipeErr:OS_QueueCreate failed, name taken (app=%s, name=%s)",
          CFE_SB_GetAppTskName(TskId, FullName), PipeName);
      break;
    case CFE_SB_CR_PIPE_NO_FREE_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_CR_PIPE_NO_FREE_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "CreatePipeErr:OS_QueueCreate failed, no free id's (app=%s)",
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_CR_PIPE_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "CreatePipeErr:OS_QueueCreate returned %ld,app %s", OsStatus,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    default:
      break;
  }
  if (Status == CFE_SUCCESS) {
    /* send debug event */
    CFE_EVS_SendEventWithAppID(CFE_SB_PIPE_ADDED_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId, "Pipe Created:name %s,id %d,app %s", PipeName,
                               CFE_ResourceId_ToInteger(PendingPipeId),
                               CFE_SB_GetAppTskName(TskId, FullName));
    /* give the pipe handle to the caller */
    *PipeIdPtr = PendingPipeId;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_DeletePipe(U32 PipeId)
{
  U32 CallerId;
  I32 Status = 0;
  /* get the callers Application Id */
  CFE_ES_GetAppID(&CallerId);
  Status = CFE_SB_DeletePipeFull(PipeId, CallerId);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_DeletePipeWithAppId(U32 PipeId, U32 AppId)
{
  I32 Status = 0;
  Status = CFE_SB_DeletePipeFull(PipeId, AppId);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Callback for deleting a pipe from a route
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_RemovePipeFromRoute(CFE_SBR_RouteId RouteId, U8 *ArgPtr)
{
  CFE_SB_DestinationD_t *destptr;
  CFE_SB_RemovePipeCallback_t *args;
  args = ArgPtr;
  destptr = CFE_SB_GetDestPtr(RouteId, args->PipeId);
  if (destptr != NULL) {
    CFE_SB_RemoveDest(RouteId, destptr);
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SLOT IS RESERVED, NOT FREED, BEFORE THE UNLOCK. Between the two locked sections this
// function drains the queue and deletes it, and during that window the pipe must be
// unusable but not reusable -- so the id is set to CFE_RESOURCEID_RESERVED rather than cleared.
// A free slot there would let another task create a pipe on top of one being torn down.
I32 CFE_SB_DeletePipeFull(U32 PipeId, U32 AppId)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  I32 Status;
  U32 TskId;
  CFE_SB_BufferD_t *BufDscPtr;
  U32 SysQueueId;
  U8 FullName[OS_MAX_API_NAME * 2];
  I64 BufDscSize;
  CFE_SB_RemovePipeCallback_t Args;
  U16 PendingEventID;
  Status = CFE_SUCCESS;
  PendingEventID = 0;
  SysQueueId = OS_OBJECT_ID_UNDEFINED;
  BufDscPtr = NULL;
  /* take semaphore to prevent a task switch during this call */
  CFE_SB_LockSharedData("CFE_SB_DeletePipeFull", 0);
  /* check input parameter */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    PendingEventID = CFE_SB_DEL_PIPE_ERR1_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  }
  /* check that the given AppId is the owner of the pipe */
  else if (AppId != PipeDscPtr->AppId) {
    PendingEventID = CFE_SB_DEL_PIPE_ERR2_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    /* Remove the pipe from all routes */
    Args.PipeId = PipeId;
    Args.FullName = FullName;
    CFE_SBR_ForEachRouteId(&CFE_SB_RemovePipeFromRoute, &Args, NULL);
    /*
     * With the route removed there should be no new messages written to this pipe,
     * but the pipe ID itself also needs to be invalidated now (before releasing lock).
     */
    SysQueueId = PipeDscPtr->SysQueueId;
    BufDscPtr = PipeDscPtr->LastBuffer;
    /*
     * Mark entry as "reserved" so other resources can be deleted
     * while the SB global is unlocked.
     */
    CFE_SB_PipeDescSetUsed(PipeDscPtr, CFE_RESOURCEID_RESERVED);
  }
  CFE_SB_UnlockSharedData("CFE_SB_DeletePipeFull", 0);
  /* remove any messages that might be on the pipe */
  if (Status == CFE_SUCCESS) {
    while (TRUE) {
      /* decrement refcount of any previous buffer */
      if (BufDscPtr != NULL) {
        CFE_SB_LockSharedData("CFE_SB_DeletePipeFull", 0);
        CFE_SB_DecrBufUseCnt(BufDscPtr);
        CFE_SB_UnlockSharedData("CFE_SB_DeletePipeFull", 0);
        BufDscPtr = NULL;
      }
      if (OS_QueueGet(SysQueueId, &BufDscPtr, sizeof(BufDscPtr), &BufDscSize, OS_CHECK) !=
          OS_SUCCESS) {
        /* no more messages */
        break;
      }
    }
    /* Delete the underlying OS queue */
    OS_QueueDelete(SysQueueId);
  }
  /*
   * Final cleanup with global data locked
   */
  CFE_SB_LockSharedData("CFE_SB_DeletePipeFull", 0);
  if (Status == CFE_SUCCESS) {
    CFE_SB_PipeDescSetFree(PipeDscPtr);
    --CFE_SB_Global.StatTlmMsg.Payload.PipesInUse;
  } else {
    CFE_SB_Global.HKTlmMsg.Payload.DeletePipeErrorCounter++;
  }
  CFE_SB_UnlockSharedData("CFE_SB_DeletePipeFull", 0);
  /* Send Events */
  if (PendingEventID != 0) {
    /* get TaskId of caller for events */
    CFE_ES_GetTaskID(&TskId);
  } else {
    TskId = CFE_ES_TASKID_UNDEFINED;
  }
  switch (PendingEventID) {
    case CFE_SB_DEL_PIPE_ERR1_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_DEL_PIPE_ERR1_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe Delete Error:Bad Argument,PipedId %ld,Requestor %s", PipeId,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_DEL_PIPE_ERR2_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_DEL_PIPE_ERR2_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe Delete Error:Caller(%s) is not the owner of pipe %ld",
                                 CFE_SB_GetAppTskName(TskId, FullName), PipeId);
      break;
    default:
      break;
  }
  if (Status == CFE_SUCCESS) {
    /*
     * Get the app name of the actual pipe owner for the event string
     * as this may be different than the task doing the deletion.
     */
    CFE_ES_GetAppName(FullName, AppId, sizeof(FullName));
    CFE_EVS_SendEventWithAppID(CFE_SB_PIPE_DELETED_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId, "Pipe Deleted:id %d,owner %s", PipeId,
                               FullName);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_SetPipeOpts(U32 PipeId, U8 Opts)
{
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 AppID;
  U32 TskId;
  U16 PendingEventID;
  I32 Status;
  U8 FullName[OS_MAX_API_NAME * 2];
  PendingEventID = 0;
  Status = CFE_ES_GetAppID(&AppID);
  if (Status != CFE_SUCCESS) {
    /* shouldn't happen... */
    return Status;
  }
  /* take semaphore to prevent a task switch during this call */
  CFE_SB_LockSharedData("CFE_SB_SetPipeOpts", 0);
  /* check input parameter */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    PendingEventID = CFE_SB_SETPIPEOPTS_ID_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  }
  /* check that the caller AppId is the owner of the pipe */
  else if (AppID != PipeDscPtr->AppId) {
    PendingEventID = CFE_SB_SETPIPEOPTS_OWNER_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    PipeDscPtr->Opts = Opts;
  }
  /* If anything went wrong, increment the error counter before unlock */
  if (Status != CFE_SUCCESS) {
    CFE_SB_Global.HKTlmMsg.Payload.PipeOptsErrorCounter++;
  }
  CFE_SB_UnlockSharedData("CFE_SB_SetPipeOpts", 0);
  /* Send Events */
  if (PendingEventID != 0) {
    /* get TaskId of caller for events */
    CFE_ES_GetTaskID(&TskId);
  } else {
    TskId = CFE_ES_TASKID_UNDEFINED;
  }
  switch (PendingEventID) {
    case CFE_SB_SETPIPEOPTS_ID_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_SETPIPEOPTS_ID_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe Opts Error:Bad Argument,PipedId %lu,Requestor %s", PipeId,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_SETPIPEOPTS_OWNER_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_SETPIPEOPTS_OWNER_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe Opts Set Error: Caller(%s) is not the owner of pipe %lu",
                                 CFE_SB_GetAppTskName(TskId, FullName), PipeId);
      break;
    default:
      break;
  }
  if (Status == CFE_SUCCESS) {
    /* get AppID of caller for events */
    CFE_ES_GetAppName(FullName, AppID, sizeof(FullName));
    CFE_EVS_SendEventWithAppID(CFE_SB_SETPIPEOPTS_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId, "Pipe opts set:id %lu,owner %s, opts=0x%02x",
                               PipeId, FullName, Opts);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_GetPipeOpts(U32 PipeId, U8 *OptsPtr)
{
  I32 Status;
  U32 TskId;
  U8 FullName[OS_MAX_API_NAME * 2];
  U16 PendingEventID;
  CFE_SB_PipeD_t *PipeDscPtr;
  PendingEventID = 0;
  Status = CFE_SUCCESS;
  /* take semaphore to prevent a task switch during this call */
  CFE_SB_LockSharedData("CFE_SB_GetPipeOpts", 0);
  /* check input parameter */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    PendingEventID = CFE_SB_GETPIPEOPTS_ID_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else if (OptsPtr == NULL) {
    PendingEventID = CFE_SB_GETPIPEOPTS_PTR_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    *OptsPtr = PipeDscPtr->Opts;
  }
  /* If anything went wrong, increment the error counter before unlock */
  if (Status != CFE_SUCCESS) {
    CFE_SB_Global.HKTlmMsg.Payload.PipeOptsErrorCounter++;
  }
  CFE_SB_UnlockSharedData("CFE_SB_GetPipeOpts", 0);
  /* Send Events */
  if (PendingEventID != 0) {
    /* get TaskId of caller for events */
    CFE_ES_GetTaskID(&TskId);
  } else {
    TskId = CFE_ES_TASKID_UNDEFINED;
  }
  switch (PendingEventID) {
    case CFE_SB_GETPIPEOPTS_PTR_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPEOPTS_PTR_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId, "Pipe Opts Error:Bad Argument,Requestor %s",
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_GETPIPEOPTS_ID_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPEOPTS_ID_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe Opts Error:Bad Argument,PipeId %lu,Requestor %s", PipeId,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    default:
      break;
  }
  if (Status == CFE_SUCCESS) {
    CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPEOPTS_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId, "Pipe opts get:id %lu, opts=0x%02x", PipeId,
                               *OptsPtr);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_GetPipeName(U8 *PipeNameBuf, I64 PipeNameSize, U32 PipeId)
{
  I32 Status;
  U16 PendingEventID;
  U32 TskId;
  U8 FullName[OS_MAX_API_NAME * 2];
  PendingEventID = 0;
  if (PipeNameBuf == NULL || PipeNameSize == 0) {
    PendingEventID = CFE_SB_GETPIPENAME_NULL_PTR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    Status = CFE_SB_GetPipeNamePriv(PipeId, PipeNameBuf, PipeNameSize);
    if (Status != CFE_SUCCESS) {
      PendingEventID = CFE_SB_GETPIPENAME_ID_ERR_EID;
    }
  }
  /* Send Events */
  if (PendingEventID != 0) {
    /* get TaskId of caller for events */
    CFE_ES_GetTaskID(&TskId);
  } else {
    TskId = CFE_ES_TASKID_UNDEFINED;
  }
  switch (PendingEventID) {
    case CFE_SB_GETPIPENAME_NULL_PTR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPENAME_NULL_PTR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId, "Pipe Name Error:NullPtr,Requestor %s",
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_GETPIPENAME_ID_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPENAME_ID_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe Id Error:Bad Argument,Id=%lu,Requestor %s", PipeId,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    default:
      break;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SEARCH IS BY OSAL QUEUE ID, NOT BY NAME. OSAL already owns the name->queue mapping, so
// this asks OSAL for the queue and then scans the pipe table for the descriptor holding it.
// Two different pipes cannot hold the same queue id, so the first match is the answer.
I32 CFE_SB_GetPipeIdByName(U32 *PipeIdPtr, U8 *PipeName)
{
  I32 OsStatus;
  I32 Status;
  U32 TskId;
  U32 Idx;
  U8 FullName[OS_MAX_API_NAME * 2];
  U16 PendingEventID;
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 SysQueueId;
  PendingEventID = 0;
  SysQueueId = OS_OBJECT_ID_UNDEFINED;
  if (PipeName == NULL || PipeIdPtr == NULL) {
    PendingEventID = CFE_SB_GETPIPEIDBYNAME_NULL_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    /* Get QueueID from OSAL */
    OsStatus = OS_QueueGetIdByName(&SysQueueId, PipeName);
    if (OsStatus == OS_SUCCESS) {
      Status = CFE_SUCCESS;
    } else {
      PendingEventID = CFE_SB_GETPIPEIDBYNAME_NAME_ERR_EID;
      Status = CFE_SB_BAD_ARGUMENT;
    }
  }
  CFE_SB_LockSharedData("CFE_SB_GetPipeIdByName", 0);
  if (Status == CFE_SUCCESS) {
    Idx = CFE_PLATFORM_SB_MAX_PIPES;
    PipeDscPtr = CFE_SB_Global.PipeTbl;
    while (TRUE) {
      if (Idx == 0) {
        PendingEventID = CFE_SB_GETPIPEIDBYNAME_NAME_ERR_EID;
        Status = CFE_SB_BAD_ARGUMENT;
        break;
      }
      if (OS_ObjectIdEqual(PipeDscPtr->SysQueueId, SysQueueId)) {
        /* grab the ID before we release the lock */
        *PipeIdPtr = CFE_SB_PipeDescGetID(PipeDscPtr);
        break;
      }
      --Idx;
      ++PipeDscPtr;
    }
  }
  if (Status != CFE_SUCCESS) {
    ++CFE_SB_Global.HKTlmMsg.Payload.GetPipeIdByNameErrorCounter;
  }
  CFE_SB_UnlockSharedData("CFE_SB_GetPipeIdByName", 0);
  /* Send Events */
  if (PendingEventID != 0) {
    /* get TaskId of caller for events */
    CFE_ES_GetTaskID(&TskId);
  } else {
    TskId = CFE_ES_TASKID_UNDEFINED;
  }
  switch (PendingEventID) {
    case CFE_SB_GETPIPEIDBYNAME_NULL_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPEIDBYNAME_NULL_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe ID By Name Error:Bad Argument,Requestor %s",
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_GETPIPEIDBYNAME_NAME_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPEIDBYNAME_NAME_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Pipe ID By Name Error:Bad Argument,Requestor %s",
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    default:
      break;
  }
  if (Status == CFE_SUCCESS) {
    CFE_EVS_SendEventWithAppID(CFE_SB_GETPIPEIDBYNAME_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId, "PipeIdByName name=%s id=%lu", PipeName,
                               *PipeIdPtr);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_SubscribeEx(CFE_SB_MsgId MsgId, U32 PipeId, CFE_SB_Qos_t Quality, U16 MsgLim)
{
  return CFE_SB_SubscribeFull(MsgId, PipeId, Quality, MsgLim, CFE_SB_MSG_GLOBAL);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_SubscribeLocal(CFE_SB_MsgId MsgId, U32 PipeId, U16 MsgLim)
{
  return CFE_SB_SubscribeFull(MsgId, PipeId, CFE_SB_DEFAULT_QOS, MsgLim, CFE_SB_MSG_LOCAL);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_Subscribe(CFE_SB_MsgId MsgId, U32 PipeId)
{
  return CFE_SB_SubscribeFull(MsgId, PipeId, CFE_SB_DEFAULT_QOS, CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT,
                              CFE_SB_MSG_GLOBAL);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE DESTINATION SEARCH LOOP EXITS THREE WAYS AND `DestPtr == NULL` DISTINGUISHES THEM. Running
// off the end leaves DestPtr NULL and means "no existing subscription, add one"; breaking on a
// duplicate or on the per-packet limit leaves it non-NULL, which is exactly what suppresses the
// add below. That is why the `if (DestPtr == NULL)` is not an `else`: it is reading the loop's
// exit reason out of the induction variable.
I32 CFE_SB_SubscribeFull(CFE_SB_MsgId MsgId, U32 PipeId, CFE_SB_Qos_t Quality, U16 MsgLim,
                         U8 Scope)
{
  CFE_SBR_RouteId RouteId;
  CFE_SB_PipeD_t *PipeDscPtr;
  I32 Status;
  U32 TskId;
  U32 AppId;
  CFE_SB_DestinationD_t *DestPtr;
  U32 DestCount;
  U8 FullName[OS_MAX_API_NAME * 2];
  U32 Collisions;
  U16 PendingEventID;
  PendingEventID = 0;
  Status = CFE_SUCCESS;
  DestPtr = NULL;
  Collisions = 0;
  /* get the callers Application Id */
  CFE_ES_GetAppID(&AppId);
  /* get TaskId of caller for events */
  CFE_ES_GetTaskID(&TskId);
  /* take semaphore to prevent a task switch during this call */
  CFE_SB_LockSharedData("CFE_SB_SubscribeFull", 0);
  /* check that the pipe has been created */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    PendingEventID = CFE_SB_SUB_INV_PIPE_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else if (PipeDscPtr->AppId != AppId) {
    PendingEventID = CFE_SB_SUB_INV_CALLER_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  }
  /* check message id key and scope */
  else if (!CFE_SB_IsValidMsgId(MsgId) || Scope > 1) {
    PendingEventID = CFE_SB_SUB_ARG_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    /* Get the route, adding one if it does not exist already */
    RouteId = CFE_SBR_GetRouteId(MsgId);
    if (!CFE_SBR_IsValidRouteId(RouteId)) {
      /* Add the route */
      RouteId = CFE_SBR_AddRoute(MsgId, &Collisions);
      /* if all routing table elements are used, send event */
      if (!CFE_SBR_IsValidRouteId(RouteId)) {
        PendingEventID = CFE_SB_MAX_MSGS_MET_EID;
        Status = CFE_SB_MAX_MSGS_MET;
      } else {
        /* Increment the MsgIds in use ctr and if it's > the high water mark,*/
        /* adjust the high water mark */
        CFE_SB_Global.StatTlmMsg.Payload.MsgIdsInUse++;
        if (CFE_SB_Global.StatTlmMsg.Payload.MsgIdsInUse >
            CFE_SB_Global.StatTlmMsg.Payload.PeakMsgIdsInUse) {
          CFE_SB_Global.StatTlmMsg.Payload.PeakMsgIdsInUse =
              CFE_SB_Global.StatTlmMsg.Payload.MsgIdsInUse;
        }
      }
    }
  }
  /* If successful up to this point, check if new dest should be added to this route */
  if (Status == CFE_SUCCESS) {
    DestCount = 0;
    for (DestPtr = CFE_SBR_GetDestListHeadPtr(RouteId); DestPtr != NULL; DestPtr = DestPtr->Next) {
      ++DestCount;
      /* Check if duplicate, see documentation on CFE_SB_DUP_SUBSCRIP_ERR */
      if (DestPtr->PipeId == PipeId) {
        PendingEventID = CFE_SB_DUP_SUBSCRIP_EID;
        break;
      }
      /* Check if limit reached */
      if (DestCount >= CFE_PLATFORM_SB_MAX_DEST_PER_PKT) {
        PendingEventID = CFE_SB_MAX_DESTS_MET_EID;
        Status = CFE_SB_MAX_DESTS_MET;
        break;
      }
    }
    /* If no existing dest found, add one now */
    if (DestPtr == NULL) {
      DestPtr = CFE_SB_GetDestinationBlk();
      if (DestPtr == NULL) {
        PendingEventID = CFE_SB_DEST_BLK_ERR_EID;
        Status = CFE_SB_BUF_ALOC_ERR;
      } else {
        /* initialize destination block */
        DestPtr->PipeId = PipeId;
        DestPtr->MsgId2PipeLim = MsgLim;
        DestPtr->Active = CFE_SB_ACTIVE;
        DestPtr->BuffCount = 0;
        DestPtr->DestCnt = 0;
        DestPtr->Scope = Scope;
        DestPtr->Prev = NULL;
        DestPtr->Next = NULL;
        /* add destination node */
        CFE_SB_AddDestNode(RouteId, DestPtr);
        CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse++;
        if (CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse >
            CFE_SB_Global.StatTlmMsg.Payload.PeakSubscriptionsInUse) {
          CFE_SB_Global.StatTlmMsg.Payload.PeakSubscriptionsInUse =
              CFE_SB_Global.StatTlmMsg.Payload.SubscriptionsInUse;
        }
      }
    }
  }
  /* Increment counter before unlock */
  CFE_SB_IncrementSubscribeCounters(PendingEventID);
  CFE_SB_UnlockSharedData("CFE_SB_SubscribeFull", 0);
  /* Send events now that the SB resources are unlocked */
  CFE_SB_IssueSubscribeEvents(PendingEventID, PipeId, MsgId, Scope);
  /* If no other event pending, send a debug event indicating success */
  if (Status == CFE_SUCCESS && PendingEventID == 0) {
    CFE_EVS_SendEventWithAppID(CFE_SB_SUBSCRIPTION_RCVD_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId,
                               "Subscription Rcvd:MsgId 0x%x on PipeId %lu,app %s",
                               CFE_SB_MsgIdToValue(MsgId), PipeId,
                               CFE_SB_GetAppTskName(TskId, FullName));
  }
  if (Status == CFE_SUCCESS && Scope == CFE_SB_MSG_GLOBAL) {
    CFE_SB_SendSubscriptionReport(MsgId, PipeId, Quality);
  }
  if (Collisions != 0) {
    CFE_EVS_SendEventWithAppID(CFE_SB_HASHCOLLISION_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId,
                               "Msg hash collision: MsgId = 0x%x, collisions = %u",
                               CFE_SB_MsgIdToValue(MsgId), Collisions);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_Unsubscribe(CFE_SB_MsgId MsgId, U32 PipeId)
{
  U32 CallerId;
  I32 Status = 0;
  /* get the callers Application Id */
  CFE_ES_GetAppID(&CallerId);
  Status = CFE_SB_UnsubscribeFull(MsgId, PipeId, CFE_SB_MSG_GLOBAL, CallerId);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_UnsubscribeLocal(CFE_SB_MsgId MsgId, U32 PipeId)
{
  U32 CallerId;
  I32 Status = 0;
  /* get the callers Application Id */
  CFE_ES_GetAppID(&CallerId);
  Status = CFE_SB_UnsubscribeFull(MsgId, PipeId, CFE_SB_MSG_LOCAL, CallerId);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_UnsubscribeWithAppId(CFE_SB_MsgId MsgId, U32 PipeId, U32 AppId)
{
  I32 Status = 0;
  Status = CFE_SB_UnsubscribeFull(MsgId, PipeId, CFE_SB_MSG_LOCAL, AppId);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// "NO SUBSCRIPTION" IS NOT AN ERROR HERE. Both the no-route and the no-destination paths set
// PendingEventID without touching Status, so unsubscribing something that was never subscribed
// returns CFE_SUCCESS with an INFORMATION event. Only a bad pipe, a non-owner caller or a bad
// message id fail -- the operation is idempotent by design, because app teardown unsubscribes
// everything it might have subscribed.
I32 CFE_SB_UnsubscribeFull(CFE_SB_MsgId MsgId, U32 PipeId, U8 Scope, U32 AppId)
{
  I32 Status;
  CFE_SBR_RouteId RouteId;
  U32 TskId;
  CFE_SB_DestinationD_t *DestPtr;
  U8 FullName[OS_MAX_API_NAME * 2];
  U8 PipeName[OS_MAX_API_NAME];
  CFE_SB_PipeD_t *PipeDscPtr;
  U16 PendingEventID;
  PendingEventID = 0;
  Status = CFE_SUCCESS;
  DestPtr = NULL;
  /* get TaskId of caller for events */
  CFE_ES_GetTaskID(&TskId);
  /* take semaphore to prevent a task switch during this call */
  CFE_SB_LockSharedData("CFE_SB_UnsubscribeFull", 0);
  /* check that the pipe has been created */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(PipeId);
  if (!CFE_SB_PipeDescIsMatch(PipeDscPtr, PipeId)) {
    PendingEventID = CFE_SB_UNSUB_INV_PIPE_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  }
  /* if given 'AppId' is not the owner of the pipe, send error event and return */
  else if (PipeDscPtr->AppId != AppId) {
    PendingEventID = CFE_SB_UNSUB_INV_CALLER_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  }
  /* check input parameters */
  else if (!CFE_SB_IsValidMsgId(MsgId) || Scope > 1) {
    PendingEventID = CFE_SB_UNSUB_ARG_ERR_EID;
    Status = CFE_SB_BAD_ARGUMENT;
  } else {
    /* get routing id */
    RouteId = CFE_SBR_GetRouteId(MsgId);
    /* Status remains CFE_SUCCESS if route is valid or not */
    if (!CFE_SBR_IsValidRouteId(RouteId)) {
      /* If there are no subscriptions, simply report via event */
      PendingEventID = CFE_SB_UNSUB_NO_SUBS_EID;
    } else {
      /* Get the destination pointer */
      DestPtr = CFE_SB_GetDestPtr(RouteId, PipeId);
      if (DestPtr != NULL) {
        /* match found, remove destination */
        CFE_SB_RemoveDest(RouteId, DestPtr);
      } else {
        PendingEventID = CFE_SB_UNSUB_NO_SUBS_EID;
      }
    }
  }
  CFE_SB_UnlockSharedData("CFE_SB_UnsubscribeFull", 0);
  switch (PendingEventID) {
    case CFE_SB_UNSUB_NO_SUBS_EID:
      CFE_SB_GetPipeName(PipeName, sizeof(PipeName), PipeId);
      CFE_EVS_SendEventWithAppID(CFE_SB_UNSUB_NO_SUBS_EID, CFE_EVS_EventType_INFORMATION,
                                 CFE_SB_Global.AppId,
                                 "Unsubscribe Err:No subs for Msg 0x%x on %s,app %s",
                                 CFE_SB_MsgIdToValue(MsgId), PipeName,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_UNSUB_INV_PIPE_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_UNSUB_INV_PIPE_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Unsubscribe Err:Invalid Pipe Id Msg=0x%x,Pipe=%lu,app=%s",
                                 CFE_SB_MsgIdToValue(MsgId), PipeId,
                                 CFE_SB_GetAppTskName(TskId, FullName));
      break;
    case CFE_SB_UNSUB_INV_CALLER_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_UNSUB_INV_CALLER_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Unsubscribe Err:Caller(%s) is not the owner of pipe %lu,Msg=0x%x",
                                 CFE_SB_GetAppTskName(TskId, FullName), PipeId,
                                 CFE_SB_MsgIdToValue(MsgId));
      break;
    case CFE_SB_UNSUB_ARG_ERR_EID:
      CFE_EVS_SendEventWithAppID(CFE_SB_UNSUB_ARG_ERR_EID, CFE_EVS_EventType_ERROR,
                                 CFE_SB_Global.AppId,
                                 "Unsubscribe Err:Bad Arg,MsgId 0x%x,PipeId %lu,app %s,scope %d",
                                 CFE_SB_MsgIdToValue(MsgId), PipeId,
                                 CFE_SB_GetAppTskName(TskId, FullName), Scope);
      break;
    default:
      break;
  }
  /* if no other event pending, send a debug event for successful unsubscribe */
  if (Status == CFE_SUCCESS && PendingEventID == 0) {
    CFE_EVS_SendEventWithAppID(CFE_SB_SUBSCRIPTION_REMOVED_EID, CFE_EVS_EventType_DEBUG,
                               CFE_SB_Global.AppId, "Subscription Removed:Msg 0x%x on pipe %lu,app %s",
                               CFE_SB_MsgIdToValue(MsgId), PipeId,
                               CFE_SB_GetAppTskName(TskId, FullName));
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// AND HERE IS THE PAYOFF OF TRANSLATING cfe_sb_priv.c FIRST. The four busiest functions on the
// bus are each a dozen lines: init a transaction on a stack-local state block, set it up, execute
// it, report the events it accumulated, return its status. Every `if (CFE_SB_MessageTxn_IsOK)`
// is the error short-circuit -- the transaction carries its own failure, so no step has to test
// the previous one's return value.
I32 CFE_SB_ReceiveBuffer(CFE_SB_Buffer **BufPtr, U32 PipeId, I32 TimeOut)
{
  CFE_SB_ReceiveTxn_State_t TxnBuf;
  CFE_SB_MessageTxn_State_t *Txn;
  Txn = CFE_SB_ReceiveTxn_Init(&TxnBuf, BufPtr);
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_MessageTxn_SetTimeout(Txn, TimeOut);
  }
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_ReceiveTxn_SetPipeId(Txn, PipeId);
    /*
     * Set the verify flag true by default -
     * in the default impl verify is a no-op that always succeeds.
     * If an actual implementation is provided, it will be used here.
     */
    CFE_SB_MessageTxn_SetEndpoint(Txn, TRUE);
  }
  if (BufPtr != NULL) {
    /*
     * Note - the API should qualify the parameter as "const", but this is
     * kept non-const for backward compatibility.  Callers should never write to
     * the returned buffer, it is const in practice.
     */
    *BufPtr = CFE_SB_ReceiveTxn_Execute(Txn);
  }
  CFE_SB_MessageTxn_ReportEvents(Txn);
  return CFE_SB_MessageTxn_GetStatus(Txn);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_ReceiveBufferWithRoute(U32 PipeId, CFE_SB_Buffer **BufPtr, I64 *BufSize,
                                  CFE_SB_MsgId *RoutingMsgId, Bool IsTermination, I32 TimeOut)
{
  CFE_SB_ReceiveTxn_State_t TxnBuf;
  CFE_SB_MessageTxn_State_t *Txn;
  Txn = CFE_SB_ReceiveTxn_Init(&TxnBuf, BufPtr);
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_MessageTxn_SetTimeout(Txn, TimeOut);
  }
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_ReceiveTxn_SetPipeId(Txn, PipeId);
    CFE_SB_MessageTxn_SetEndpoint(Txn, IsTermination);
  }
  if (BufPtr != NULL) {
    *BufPtr = CFE_SB_ReceiveTxn_Execute(Txn);
  }
  /* Export the other details if the user asked for them */
  if (BufSize != NULL) {
    *BufSize = CFE_SB_MessageTxn_GetContentSize(Txn);
  }
  if (RoutingMsgId != NULL) {
    *RoutingMsgId = CFE_SB_MessageTxn_GetRoutingMsgId(Txn);
  }
  CFE_SB_MessageTxn_ReportEvents(Txn);
  return CFE_SB_MessageTxn_GetStatus(Txn);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE OVERSIZE CHECK RUNS BEFORE THE STATUS CHECK AND RETURNS NULL DIRECTLY. That is NASA's
// order, not a tidier one: a too-large request is reported even when CFE_ES_GetAppID failed, and
// the AppName it prints is then the empty string the declaration initialised.
CFE_SB_Buffer *CFE_SB_AllocateMessageBuffer(I64 MsgSize)
{
  U32 AppId;
  U8 AppName[OS_MAX_API_NAME];
  CFE_SB_BufferD_t *BufDscPtr;
  CFE_SB_Buffer *BufPtr;
  I32 Status;
  MemSet(AppName, 0, sizeof(AppName)); // char AppName[OS_MAX_API_NAME] = {""};
  AppId = CFE_ES_APPID_UNDEFINED;
  BufDscPtr = NULL;
  BufPtr = NULL;
  Status = CFE_ES_GetAppID(&AppId);
  if (MsgSize > CFE_MISSION_SB_MAX_SB_MSG_SIZE) {
    CFE_ES_GetAppName(AppName, AppId, sizeof(AppName));
    CFE_ES_WriteToSysLog("%s %s: Failed, requested size %zu larger than allowed %d\n", AppName,
                         "CFE_SB_AllocateMessageBuffer", MsgSize, CFE_MISSION_SB_MAX_SB_MSG_SIZE);
    return NULL;
  }
  /* get callers AppId */
  if (Status == CFE_SUCCESS) {
    CFE_SB_LockSharedData("CFE_SB_AllocateMessageBuffer", 0);
    /*
     * All this needs to do is get a descriptor from the pool,
     * and associate that descriptor with this app ID, so it
     * can be freed if this app is deleted before it uses it.
     */
    BufDscPtr = CFE_SB_GetBufferFromPool(MsgSize);
    if (BufDscPtr != NULL) {
      /* Track the buffer as a zero-copy assigned to this app ID */
      BufDscPtr->AppId = AppId;
      BufPtr = &BufDscPtr->Content;
      CFE_SB_TrackingListAdd(&CFE_SB_Global.ZeroCopyList, &BufDscPtr->Link);
    }
    CFE_SB_UnlockSharedData("CFE_SB_AllocateMessageBuffer", 0);
  }
  if (BufPtr != NULL) {
    /*
     * If a buffer was obtained, wipe it now.
     * (This ensures the buffer is fully cleared at least once,
     * no stale data from a prior use of the same memory)
     */
    MemSet(BufPtr, 0, MsgSize);
  }
  return BufPtr;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_ReleaseMessageBuffer(CFE_SB_Buffer *BufPtr)
{
  CFE_SB_BufferD_t *BufDscPtr;
  I32 Status;
  /*
   * Sanity Check that the pointers are not NULL
   */
  if (BufPtr == NULL) {
    return CFE_SB_BAD_ARGUMENT;
  }
  CFE_SB_LockSharedData("CFE_SB_ReleaseMessageBuffer", 0);
  Status = CFE_SB_ZeroCopyBufferValidate(BufPtr, &BufDscPtr);
  if (Status == CFE_SUCCESS) {
    /* Clear the ownership app ID and decrement use count (may also free) */
    BufDscPtr->AppId = CFE_ES_APPID_UNDEFINED;
    CFE_SB_DecrBufUseCnt(BufDscPtr);
  }
  CFE_SB_UnlockSharedData("CFE_SB_ReleaseMessageBuffer", 0);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_TransmitBuffer(CFE_SB_Buffer *BufPtr, Bool IsOrigination)
{
  CFE_SB_TransmitTxn_State_t TxnBuf;
  CFE_SB_MessageTxn_State_t *Txn;
  Txn = CFE_SB_TransmitTxn_Init(&TxnBuf, BufPtr);
  /* In this context, the user should have set the the size and MsgId in the content */
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_TransmitTxn_SetupFromMsg(Txn, &BufPtr->Msg);
  }
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    /* Save passed-in parameters */
    CFE_SB_MessageTxn_SetEndpoint(Txn, IsOrigination);
    CFE_SB_TransmitTxn_Execute(Txn, BufPtr);
  }
  /* send an event for each pipe write error that may have occurred */
  CFE_SB_MessageTxn_ReportEvents(Txn);
  return CFE_SB_MessageTxn_GetStatus(Txn);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE `BufPtr = NULL` AFTER Execute IS LOAD-BEARING DOCUMENTATION, NOT A CLEANUP. The broadcast
// CONSUMES the buffer -- ownership passes to the destination pipes and the use count it was born
// with is handed over -- so touching BufPtr afterwards would be a use-after-free. NASA nulls it
// to make that unwritable rather than merely unwise, and the translation keeps the line.
I32 CFE_SB_TransmitMsg(CFE_MSG_Message *MsgPtr, Bool IsOrigination)
{
  CFE_SB_TransmitTxn_State_t TxnBuf;
  CFE_SB_MessageTxn_State_t *Txn;
  CFE_SB_Buffer *BufPtr;
  BufPtr = NULL;
  Txn = CFE_SB_TransmitTxn_Init(&TxnBuf, MsgPtr);
  /* In this context, the user should have set the the size and MsgId in the content */
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_TransmitTxn_SetupFromMsg(Txn, MsgPtr);
  }
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    /* Get buffer - note this pre-initializes the returned buffer with
     * a use count of 1, which refers to this task as it fills the buffer. */
    BufPtr = CFE_SB_AllocateMessageBuffer(CFE_SB_MessageTxn_GetContentSize(Txn));
    if (BufPtr == NULL) {
      CFE_SB_MessageTxn_SetEventAndStatus(Txn, CFE_SB_GET_BUF_ERR_EID, CFE_SB_BUF_ALOC_ERR);
    }
  }
  /*
   * If a buffer was obtained above, then copy the content into it
   * and broadcast it to all subscribers in the route.
   *
   * Note - if there is no route / no subscribers, the "Status" will
   * be CFE_SUCCESS because CFE_SB_TransmitMsgValidate() succeeded,
   * but there will be no buffer because CFE_SBR_IsValidRouteId() returned
   * false.
   *
   * But if the descriptor is non-null it means the message is valid and
   * there is a route to send it to.
   */
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    /* Copy actual message content into buffer */
    MemCpy(&BufPtr->Msg, MsgPtr, CFE_SB_MessageTxn_GetContentSize(Txn));
    /* Save passed-in parameters */
    CFE_SB_MessageTxn_SetEndpoint(Txn, IsOrigination);
    CFE_SB_TransmitTxn_Execute(Txn, BufPtr);
    /*
     * The broadcast function consumes the buffer, so it should not be
     * accessed in this function anymore
     */
    BufPtr = NULL;
  }
  /* send an event for each pipe write error that may have occurred */
  CFE_SB_MessageTxn_ReportEvents(Txn);
  return CFE_SB_MessageTxn_GetStatus(Txn);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_TransmitBufferWithRoute(CFE_SB_Buffer *BufPtr, I64 ContentSize,
                                   CFE_SB_MsgId RoutingMsgId, Bool IsOrigination, I32 TimeOut)
{
  CFE_SB_TransmitTxn_State_t TxnBuf;
  CFE_SB_MessageTxn_State_t *Txn;
  Txn = CFE_SB_TransmitTxn_Init(&TxnBuf, BufPtr);
  /*
   * Sanity Check that the pointers are not NULL
   */
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    /* Save passed-in parameters and execute */
    CFE_SB_MessageTxn_SetContentSize(Txn, ContentSize);
    CFE_SB_MessageTxn_SetRoutingMsgId(Txn, RoutingMsgId);
    CFE_SB_MessageTxn_SetTimeout(Txn, TimeOut);
    CFE_SB_MessageTxn_SetEndpoint(Txn, IsOrigination);
  }
  if (CFE_SB_MessageTxn_IsOK(Txn)) {
    CFE_SB_TransmitTxn_Execute(Txn, BufPtr);
  }
  /* send an event for each pipe write error that may have occurred */
  CFE_SB_MessageTxn_ReportEvents(Txn);
  return CFE_SB_MessageTxn_GetStatus(Txn);
}
#endif
