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
// HEALTH & SAFETY'S TWO VALIDATORS -- the 1:1 translation of NASA's fsw/src/hs_utils.c, 80 lines
// and two functions. The smallest source in this port.
//
// ### BOTH FUNCTIONS HAVE A TEST THAT CANNOT FAIL, AND IT IS NASA'S
//
// Each reads
//
//     if (ActionType < HS_AMTActType_NOACT)      /* NOACT is 0 */
//     {
//         IsValid = false;
//     }
//
// and ActionType is a **uint16**, so `ActionType < 0` is unsigned and never true. The compiler
// does not warn because the constant is a macro rather than a literal 0, and the branch is dead
// in both functions.
//
// IT IS KEPT VERBATIM. The lower bound is the right thing to express -- the field is a uint16
// today and a signed widening would make the test live again -- and removing it would be a
// judgement about NASA's types rather than a translation. The exercise drives ActionType 0 so the
// arm the comparison guards is covered from the other side; the dead branch itself is not
// reachable by any input and is named here instead.
//
// ### THE UPPER BOUND IS WHERE THE INDEX/SELECTOR DUALITY LIVES
//
//     ActionType > (HS_AMTActType_LAST_NONMSG + HS_MAX_MSG_ACT_TYPES)     3 + 8 = 11
//
// So 0..3 are the built-in actions and 4..11 are message-action indices 0..7 -- see hs_tbl.HC.
// Eleven is the last valid value and twelve is the first invalid one, which is the boundary the
// exercise drives on both sides.
//
// AND THE TWO FUNCTIONS ARE IDENTICAL EXCEPT FOR WHICH CONSTANTS THEY NAME. Both LAST_NONMSG
// values are 3, so they compute the same bound from different names -- which is exactly the shape
// where a translation could collapse them into one and nothing would notice. They are separate
// here because they are separate upstream, and a mission that changed one LAST_NONMSG would find
// out which.
#ifndef HS_UTILS_HC
#define HS_UTILS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hs_cfg.HC, hs_msg.HC, hs_tbl.HC, hs_global.HC, hs_eventids.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13. HK paid for that
// lesson: sixteen functions compiled, passed every static gate and were not in the binary.

// --- hs_utils.h's prototypes -----------------------------------------------------------------
Bool HS_AMTActionIsValid(U16 ActionType);
Bool HS_EMTActionIsValid(U16 ActionType);

/*******************************************************************************/
// Verify an Application Monitor Table action type.
Bool HS_AMTActionIsValid(U16 ActionType)
{
  Bool IsValid = TRUE;

  // DEAD BRANCH, NASA'S, AND KEPT: ActionType is unsigned and HS_AMTActType_NOACT is 0.
  if (ActionType < HS_AMTActType_NOACT) {
    IsValid = FALSE;
  } else if (ActionType > HS_AMTActType_LAST_NONMSG + HS_MAX_MSG_ACT_TYPES) {
    /* HS allows for HS_AMTActType_LAST_NONMSG actions by default and
       HS_MAX_MSG_ACT_TYPES message actions defined in the Message
       Action Table. */
    IsValid = FALSE;
  }

  return IsValid;
}

/*******************************************************************************/
// Verify an Event Monitor Table action type. The same shape, different constants -- see the
// header on why the two are not one function.
Bool HS_EMTActionIsValid(U16 ActionType)
{
  Bool IsValid = TRUE;

  if (ActionType < HS_EMTActType_NOACT) {
    IsValid = FALSE;
  } else if (ActionType > HS_EMTActType_LAST_NONMSG + HS_MAX_MSG_ACT_TYPES) {
    /* HS allows for HS_EMTActType_LAST_NONMSG actions by default and
       HS_MAX_MSG_ACT_TYPES message actions defined in the Message
       Action Table. */
    IsValid = FALSE;
  }

  return IsValid;
}

#endif
