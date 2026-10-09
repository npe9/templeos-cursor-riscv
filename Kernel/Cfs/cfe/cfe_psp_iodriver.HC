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
// THE PSP's I/O DRIVER ABSTRACTION AND WATCHDOG INTERFACE -- the 1:1 translation of NASA's
// PSP/fsw/modules/iodriver/inc/iodriver_base.h, iodriver_analog_io.h and
// PSP/fsw/inc/cfe_psp_watchdog_api.h.
//
// THESE ARE **INTERFACES**, NOT IMPLEMENTATIONS. NASA's PSP ships one implementation per board;
// this port has no board with either device, so the implementation is simulated in the
// differential's two halves and the exercise steers it. What lives here is only what NASA's
// headers declare: the types, the opcodes and the three argument constructors.
//
// ### THE ARGUMENT IS A UNION AND THE CONSTRUCTORS ARE HEADER `static inline`s
//
// CFE_PSP_IODriver_Arg_t is a union of a void*, a const void*, a const char* and a uint32, and
// NASA builds one with CFE_PSP_IODriver_VPARG / CONST_STR / U32ARG -- three one-line inline
// functions in the header. docs/ records that a header `static inline` is not a dependency: it
// TRAVELS WITH ITS CALLER, so these three are translated here as ordinary functions and
// check_header_inlines is what keeps them honest against NASA's bodies.
//
// **THE UNION IS WHY THE OPCODE AND THE ARGUMENT CANNOT BE TYPE-CHECKED TOGETHER.** SET_RUNNING
// takes a uint32, LOOKUP_SUBSYSTEM takes a string and ANALOG_IO_READ_CHANNELS takes a pointer to
// a read/write descriptor, all through one 8-byte parameter. A caller that passed the wrong
// constructor would compile; HS's five call sites each use the right one and the exercise drives
// all five.
//
// ### AND A LOOKUP RETURNS ITS ANSWER AS A POSITIVE STATUS
//
// LOOKUP_SUBSYSTEM and LOOKUP_SUBCHANNEL return the id, not a status with the id in an
// out-parameter -- so zero is a valid answer and the caller tests `< 0`. That is the opposite of
// every cFE convention in this port and it is stated here as well as at HS's call sites, because
// a reader arriving from cfe_tbl or cfe_sb will have the other convention in mind.
#ifndef CFE_PSP_IODRIVER_HC
#define CFE_PSP_IODRIVER_HC

/*******************************************************************************/
// Which device, subsystem and channel a command is aimed at. 8 bytes.
class CFE_PSP_IODriver_Location
{
  U32 PspModuleId;  // device selection
  U16 SubsystemId;  // instance or subsystem number
  U16 SubchannelId; // subchannel number; 0 for devices without multiple channels
};

/*******************************************************************************/
// One command argument, four ways. 8 bytes.
//
// NASA's `void *Vptr` and `const void *ConstVptr` are both U8 * here -- the port's mapping for a
// void pointer -- and they overlay the same eight bytes either way, so the union's layout is
// unchanged. `ConstStr` is the same storage read as a string.
union CFE_PSP_IODriver_Arg
{
  U8 *Vptr;
  U8 *ConstVptr;
  U8 *ConstStr;
  // NASA'S MEMBER IS NAMED `U32`, WHICH IS ALSO A TYPE NAME, and HolyC accepts it. A first draft
  // of this file renamed it to `U32Val` on the assumption that `U32 U32;` would not parse --
  // check_structs caught the rename as `missing: U32 / extra: U32Val`, and a two-line exec case
  // then showed the assumption was simply wrong: the member and the type live in different
  // namespaces, both the declaration and `a.U32 = 7` compile. So there is NO renaming in this
  // file and the union is NASA's field for field.
  U32 U32;
};

/*******************************************************************************/
// An analog read or write: how many channels, and where the samples go. 16 bytes.
//
// CFE_PSP_IODriver_AdcCode_t is NASA's `int32`, so `Samples` is an I32 * and a sample is SIGNED --
// which matters for HS's `Sample >> 8`, an arithmetic shift on a negative code.
class CFE_PSP_IODriver_AnalogRdWr
{
  U16 NumChannels; // length of the Samples array
  U8 _pad0[6];     // C aligns the pointer that follows
  I32 *Samples;    // CFE_PSP_IODriver_AdcCode_t * -- the ADC/DAC samples
};

// --- the generic opcodes, from iodriver_base.h ------------------------------------------------
#define CFE_PSP_IODriver_NOOP              0
#define CFE_PSP_IODriver_SET_RUNNING       1
#define CFE_PSP_IODriver_GET_RUNNING       2
#define CFE_PSP_IODriver_SET_CONFIGURATION 3
#define CFE_PSP_IODriver_GET_CONFIGURATION 4
#define CFE_PSP_IODriver_LOOKUP_SUBSYSTEM  5
#define CFE_PSP_IODriver_LOOKUP_SUBCHANNEL 6
#define CFE_PSP_IODriver_SET_DIRECTION     7
#define CFE_PSP_IODriver_QUERY_DIRECTION   8

// The per-class bases. Each device class numbers its own opcodes from one of these, so an analog
// opcode and a discrete one can never collide.
#define CFE_PSP_IODriver_ANALOG_IO_CLASS_BASE   0x00010000
#define CFE_PSP_IODriver_DISCRETE_IO_CLASS_BASE 0x00020000

// --- iodriver_analog_io.h. NASA declares these as an enum whose first member is
// CFE_PSP_IODriver_ANALOG_IO_NOOP = ANALOG_IO_CLASS_BASE, so READ_CHANNELS is BASE + 1.
#define CFE_PSP_IODriver_ANALOG_IO_NOOP          CFE_PSP_IODriver_ANALOG_IO_CLASS_BASE
#define CFE_PSP_IODriver_ANALOG_IO_READ_CHANNELS (CFE_PSP_IODriver_ANALOG_IO_CLASS_BASE + 1)

/*******************************************************************************/
// The three argument constructors. NASA's header `static inline`s, translated whole because that
// is what a header inline is -- part of every caller.
CFE_PSP_IODriver_Arg CFE_PSP_IODriver_VPARG(U8 *x)
{
  CFE_PSP_IODriver_Arg a;
  a.Vptr = x;
  return a;
}

CFE_PSP_IODriver_Arg CFE_PSP_IODriver_CONST_STR(U8 *x)
{
  CFE_PSP_IODriver_Arg a;
  a.ConstStr = x;
  return a;
}

CFE_PSP_IODriver_Arg CFE_PSP_IODriver_U32ARG(U32 x)
{
  CFE_PSP_IODriver_Arg a;
  a.U32 = x;
  return a;
}

#endif
