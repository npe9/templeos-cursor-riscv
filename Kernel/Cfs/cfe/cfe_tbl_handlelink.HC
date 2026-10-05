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
// TABLE SERVICES' HANDLE-LINK LIST NODE -- the translation of NASA's cfe_tbl_handlelink.c, the
// smallest source in the module and deliberately the first one gated: it is the only one of the
// fifteen that never touches CFE_TBL_Global, so it can be made to work before the 592 KB of
// state behind the rest of them is proven reachable.
//
// WHY THE LINKS ARE IDS AND NOT POINTERS. A table may be shared by several apps, and each app
// gets its own ACCESS DESCRIPTOR. The descriptors for one table are chained together, and the
// chain is threaded through this two-field node -- but the field type is CFE_TBL_HandleId_t, an
// index into CFE_TBL_Global.Handles, not a CFE_TBL_AccessDescriptor_t *. The reason is that the
// registry record holding the list HEAD gets written to the critical data store and read back
// after a processor reset, when every pointer it used to hold would be meaningless. An index
// into a fixed array survives that; an address does not.
//
// UNDEFINED IS ZERO, which is why a zeroed CFE_TBL_Global already has every list correctly
// empty, and why CFE_TBL_HandleLinkInit is nonetheless called explicitly: the record it
// initialises may be being recycled rather than seen for the first time.
#ifndef CFE_TBL_HANDLELINK_HC
#define CFE_TBL_HANDLELINK_HC
// The two id spellings NASA's source uses. CFE_TBL_HANDLEID_UNDEFINED is
// CFE_TBL_HANDLEID_C(CFE_RESOURCEID_UNDEFINED), and CFE_RESOURCEID_UNDEFINED is a wrapped zero;
// the CFE_TBL_HANDLEID_C cast exists in C only to make a compiler refuse a table handle where
// some other kind of resource id is wanted, and HolyC has one id type, so it relabels nothing.
#ifndef CFE_TBL_HANDLEID_UNDEFINED
#define CFE_TBL_HANDLEID_UNDEFINED CFE_RESOURCEID_UNDEFINED
#endif

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_HandleLinkInit(CFE_TBL_HandleLink_t *LinkPtr)
{
  LinkPtr->Prev = CFE_TBL_HANDLEID_UNDEFINED;
  LinkPtr->Next = CFE_TBL_HANDLEID_UNDEFINED;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_HandleLinkIsAttached(CFE_TBL_HandleLink_t *LinkPtr)
{
  // NASA writes CFE_TBL_HandleID_IsDefined(LinkPtr->Next), a static inline in cfe_tbl.h whose
  // whole body is CFE_RESOURCEID_TEST_DEFINED(x). That family of inlines exists to give each
  // kind of resource id its own C type so the compiler refuses a mix-up; with one id type they
  // all collapse onto the CFE_ResourceId_* function they wrap, which is what every other module
  // in this port does too.
  return CFE_ResourceId_IsDefined(LinkPtr->Next);
}
#endif
