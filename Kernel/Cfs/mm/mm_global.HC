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
// MEMORY MANAGER'S STATE -- the translation of NASA's fsw/src/mm_app.h, plus the global
// instance. Same arrangement as md_global.HC and the four cFE globals: NASA declares
// MM_AppData `extern` in mm_app.h and defines it in mm_app.c, and the translation defines it
// here beside its type so the global does not move when a different implementation file
// happens to be gated first.
//
// MM HAS NO CONTROL STRUCTURE, which is the structural difference from MD. MD keeps four
// running dwell streams and walks them every cycle; MM does one thing per command and
// remembers only what it did. So MM_AppData is a housekeeping packet, a pipe, a run status
// and THREE I/O BUFFERS -- and the buffers are the whole of its working state.
#ifndef MM_GLOBAL_HC
#define MM_GLOBAL_HC

// WHICH COMMAND'S LIMITS TO APPLY. MM_VerifyLoadDumpParams takes one of these as VerifyType
// and uses it to pick a MaxSize, because a load, a dump, a fill, a dump-into-an-event and a
// load-with-interrupts-disabled have five different bounds for the same memory type.
#define MM_VERIFY_DUMP  0
#define MM_VERIFY_LOAD  1
#define MM_VERIFY_EVENT 2
#define MM_VERIFY_FILL  3
#define MM_VERIFY_WID   4

// Long enough for "MEM_EEPROM" and its NUL, which is the longest of the five names
// MM_VerifyLoadDumpParams prints.
#define MM_MAX_MEM_TYPE_STR_LEN 11

/*******************************************************************************/
// THE WHOLE APPLICATION, in one object -- 1,312 bytes, against MD's 2,608.
//
// THE THREE BUFFERS ARE 400 BYTES EACH, NOT 200, and that is NASA's arithmetic rather than a
// translation choice: NASA declares them `size_t LoadBuffer[MM_INTERNAL_MAX_LOAD_DATA_SEG / 4]`,
// so a 200-byte segment becomes 50 elements -- of an EIGHT-byte type on this target. The
// division by four reads as if size_t were 4 bytes, which it was on the 32-bit targets this
// code grew up on. Kept verbatim: the arrays are what the load and dump loops index, and
// halving them would change where a segment break falls.
class MM_AppData_t
{
  MM_HkTlm_t HkTlm;
  U32 CmdPipe; // CFE_SB_PipeId_t
  U32 RunStatus;
  U64 LoadBuffer[MM_INTERNAL_MAX_LOAD_DATA_SEG / 4];
  U64 DumpBuffer[MM_INTERNAL_MAX_DUMP_DATA_SEG / 4];
  U64 FillBuffer[MM_INTERNAL_MAX_FILL_DATA_SEG / 4];
};

/*******************************************************************************/
// The global. NASA: `MM_AppData_t MM_AppData;` at the top of mm_app.c.
MM_AppData_t MM_AppData;
#endif
