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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_valresult.c AND the five
// `static inline` accessors of cfe_tbl_valresult.h -- VALIDATION IS A REQUEST, NOT A CALL.
//
// WHY THERE IS A RESULT BLOCK AT ALL. An app may register a VALIDATION FUNCTION for its table,
// and the ground can ask for a buffer to be validated. Table Services cannot run that function
// itself: it belongs to the app, it may take time, and it must run in the app's own task. So
// the request is RECORDED in one of ten result blocks, the block goes to
// CFE_TBL_VALIDATION_PENDING, and the app picks it up the next time it calls CFE_TBL_Manage.
// The answer comes back as PERFORMED with a status, and the ground reads it in housekeeping
// telemetry. Exactly the shape as the dump-control blocks in cfe_tbl_dumpctl.c.
//
// A TABLE WITH NO VALIDATION FUNCTION IS ASSUMED VALID, and that path is the interesting one:
// the block is still allocated -- NASA's comment says why, "it was a specific request/command
// to validate this, and by initializing the result block (even if its a noop) then the result
// will be sent in the next HK TLM" -- but it goes straight to PERFORMED, the buffer is marked
// valid on the spot, and an INFORMATION event says so. So "validated" and "nobody checked it"
// are the same state to a reader of telemetry, distinguishable only by that event.
//
// AND NOTE WHICH EVENT IS NOT AN ERROR. Four events here; three are CFE_EVS_EventType_ERROR
// and CFE_TBL_ASSUMED_VALID_INF_EID is INFORMATION. That demotion is one line in the helper
// and is the only thing separating "we could not validate your table" from "there was nothing
// to validate".
#ifndef CFE_TBL_VALRESULT_HC
#define CFE_TBL_VALRESULT_HC
// cfe_tbl_eventids.h
#ifndef CFE_TBL_ASSUMED_VALID_INF_EID
#define CFE_TBL_ASSUMED_VALID_INF_EID          23
#define CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID   67
#define CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID     80
#define CFE_TBL_VALIDATION_IN_PROGRESS_ERR_EID 104
#endif
#ifndef CFE_TBL_VALRESULTID_IS_VALID
#define CFE_TBL_VALRESULTID_IS_VALID(x) CFE_ResourceId_IsDefined(x)
#define CFE_TBL_VALRESULTID_INT(x)      CFE_ResourceId_ToInteger(x)
#endif

// --- cfe_tbl_valresult.h: the five accessors ------------------------------------------------
Bool CFE_TBL_ValidationResultIsUsed(CFE_TBL_ValidationResult_t *BuffPtr)
{
  return CFE_TBL_VALRESULTID_IS_VALID(BuffPtr->ValId);
}

U0 CFE_TBL_ValidationResultSetUsed(CFE_TBL_ValidationResult_t *BuffPtr, U32 PendingId)
{
  BuffPtr->ValId = PendingId;
}

U0 CFE_TBL_ValidationResultSetFree(CFE_TBL_ValidationResult_t *BuffPtr)
{
  // BOTH fields, and the state first, for the reason cfe_tbl_dumpctl.c's twin records: a
  // recycled block that kept PERFORMED would be read as an answer nobody asked for.
  BuffPtr->State = CFE_TBL_VALIDATION_FREE;
  BuffPtr->ValId = CFE_TBL_VALRESULTID_UNDEFINED;
}

U32 CFE_TBL_ValidationResultGetId(CFE_TBL_ValidationResult_t *BuffPtr)
{
  return BuffPtr->ValId;
}

Bool CFE_TBL_ValidationResultIsMatch(CFE_TBL_ValidationResult_t *BuffPtr, U32 ValId)
{
  return BuffPtr != NULL && CFE_ResourceId_Equal(BuffPtr->ValId, ValId);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidationResultId_ToIndex(U32 ValResultId, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(ValResultId, CFE_TBL_VALRESULTID_BASE,
                                CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS, Idx);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_ValidationResult_t *CFE_TBL_LocateValidationResultByID(U32 ValResultId)
{
  CFE_TBL_ValidationResult_t *ResultPtr;
  U32 Idx;
  if (CFE_TBL_ValidationResultId_ToIndex(ValResultId, &Idx) == CFE_SUCCESS)
    ResultPtr = &CFE_TBL_Global.ValidationResults[Idx];
  else
    ResultPtr = NULL;
  return ResultPtr;
}

// THE NEXT TWO ARE IN THE OPPOSITE ORDER TO NASA'S SOURCE, for the reason recorded in
// cfe_tbl_accdesc.HC: GetNextValResultBlock takes the ADDRESS of
// CheckValidationResultSlotUsed and HolyC resolves `&function` against the definition.

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_CheckValidationResultSlotUsed(U32 CheckId)
{
  CFE_TBL_ValidationResult_t *BuffPtr;
  /*
  ** Note - The pointer here should never be NULL because the ID should always be
  ** within the expected range, but if it ever is NULL, this should return true
  ** such that the caller will _not_ attempt to use the record.
  */
  BuffPtr = CFE_TBL_LocateValidationResultByID(CheckId);
  return BuffPtr == NULL || CFE_TBL_ValidationResultIsUsed(BuffPtr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_GetNextValResultBlock()
{
  return CFE_ResourceId_FindNext(CFE_TBL_Global.LastValidationResultId,
                                 CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS,
                                 &CFE_TBL_CheckValidationResultSlotUsed);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_ValidationResult_t *CFE_TBL_TxnCheckValidationRequest(CFE_TBL_TxnState_t *Txn)
{
  U32 PreviousValId;
  CFE_TBL_ValidationResult_t *ValResultPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  /* check if validation is already pending */
  PreviousValId = RegRecPtr->PendingValId;
  ValResultPtr = CFE_TBL_LocateValidationResultByID(PreviousValId);
  if (CFE_TBL_ValidationResultIsMatch(ValResultPtr, PreviousValId)) {
    /* A validation is already pending and has not been completed yet */
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_VALIDATION_IN_PROGRESS_ERR_EID, 0,
                        CFE_TBL_VALRESULTID_INT(PreviousValId));
  } else {
    /* No validation is already pending */
    ValResultPtr = NULL;
  }
  return ValResultPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_ValidationResult_t *CFE_TBL_TxnSetupValidationRequest(CFE_TBL_TxnState_t *Txn,
                                                              U16 BufferSelect)
{
  U32 NextValId;
  CFE_TBL_ValidationResult_t *ValResultPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *SelectedBufferPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  ValResultPtr = NULL;
  SelectedBufferPtr = CFE_TBL_GetSelectedBuffer(RegRecPtr, BufferSelect);
  if (SelectedBufferPtr == NULL) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID, 0, BufferSelect);
  } else {
    /*
    ** Get a result block
    **
    ** NOTE: this is always allocating a result block even if there is no validation function.
    ** This is because it was a specific request/command to validate this, and by initializing
    ** the result block (even if its a "noop") then the result will be sent in the next HK TLM
    */
    NextValId = CFE_TBL_GetNextValResultBlock();
    ValResultPtr = CFE_TBL_LocateValidationResultByID(NextValId);
    if (ValResultPtr == NULL) {
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID, 0, 0);
    } else {
      /* If owner has a validation function, then notify the  */
      /* table owner that there is data to be validated       */
      if (CFE_TBL_RegRecGetValidationFunc(RegRecPtr) != NULL) {
        /* Set this Validation Response Block for deferred processing by the app */
        ValResultPtr->State = CFE_TBL_VALIDATION_PENDING;
        ValResultPtr->Result = 0;
        StrNCpy(ValResultPtr->TableName, CFE_TBL_RegRecGetName(RegRecPtr),
                CFE_TBL_MAX_FULL_NAME_LEN);
        ValResultPtr->CrcOfTable = SelectedBufferPtr->Crc;
        ValResultPtr->BufferSelect = BufferSelect;
        CFE_TBL_ValidationResultSetUsed(ValResultPtr, NextValId);
        CFE_TBL_Global.LastValidationResultId = NextValId;
        RegRecPtr->PendingValId = CFE_TBL_ValidationResultGetId(ValResultPtr);
        /* Maintain statistic on number of validation requests given to applications */
        CFE_TBL_Global.NumValRequests++;
      } else {
        /* If there isn't a validation function pointer, then the process is complete  */
        /* By setting this value, we are letting the Housekeeping process recognize it */
        /* as data to be sent to the ground in telemetry.                              */
        ValResultPtr->State = CFE_TBL_VALIDATION_PERFORMED;
        SelectedBufferPtr->IsValid = TRUE;
        CFE_TBL_TxnAddEvent(Txn, CFE_TBL_ASSUMED_VALID_INF_EID, 0, 0);
      }
    }
  }
  return ValResultPtr;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_SendValidationEventHelper(CFE_TBL_TxnEvent_t *Event, CFE_TBL_TxnEventContext_t *Ctxt)
{
  U16 EventType;
  U8 EventString[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  /* The majority of the events are errors, but this can be reset later to demote to info/debug */
  EventType = CFE_EVS_EventType_ERROR;
  EventString[0] = 0;
  switch (Event->EventId) {
    case CFE_TBL_TOO_MANY_VALIDATIONS_ERR_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "Too many Table Validations have been requested");
      break;
    case CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "Request had illegal buffer parameter (0x%08X)", Event->EventData2);
      break;
    case CFE_TBL_ASSUMED_VALID_INF_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "No Validation Function has been registered, assumed valid");
      // THE ONE DEMOTION. Everything else here is an error; "there was nothing to validate"
      // is information, and this line is all that separates them in telemetry.
      EventType = CFE_EVS_EventType_INFORMATION;
      break;
    case CFE_TBL_VALIDATION_IN_PROGRESS_ERR_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "Validation already in progress, id=%x", Event->EventData2);
      break;
  }
  if (EventString[0] == 0)
    return FALSE;
  /* Finally send the actual event by appending all the info we have */
  CFE_EVS_SendEventWithAppID(Event->EventId, EventType, CFE_TBL_Global.TableTaskAppId,
                             "%s,app=%s,tbl=%s:%s", Ctxt->Operation, Ctxt->CallerName,
                             Ctxt->TableName, EventString);
  return TRUE;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SendValidationEvents(CFE_TBL_TxnState_t *Txn)
{
  CFE_TBL_SendTransactionEvents(Txn, "Validate", &CFE_TBL_SendValidationEventHelper, NULL);
}
#endif
