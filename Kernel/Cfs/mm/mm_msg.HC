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
// MEMORY MANAGER'S VOCABULARY -- the translation of NASA's MM config headers:
// default_mm_internal_cfg_values.h (through fsw/inc/mm_internal_cfg.h), mm_interface_cfg.h,
// default_mm_msgids.h, default_mm_extern_typedefs.h, default_mm_msgdefs.h,
// default_mm_msgstruct.h and default_mm_filedefs.h.
//
// WHAT MEMORY MANAGER DOES, AND WHY IT IS THE SECOND APP. MD reads memory; MM writes it. The
// ground can peek one byte, word or dword; poke one; fill a region with a pattern; load a
// region from a file; dump a region to a file or into an event; look a symbol up; and
// enable or disable EEPROM writes. It is the app you use to patch a running spacecraft.
//
// SO MM NEEDS THE WRITE HALF OF THE SIMULATED MEMORY WINDOW that MD established, and a second
// simulated region for EEPROM -- see the driver. The reason the window is a range of LITERAL
// addresses rather than a real buffer is unchanged and is recorded in docs/CFS_PLAN.md: a host
// process and a QEMU guest never agree about a real address, and MM's events print the
// resolved address in almost every one of them.
//
// MM PRINTS %p, AND NO EARLIER GATED SOURCE DID. Six of mm_utils.c's events render the address
// with "%p", which Kernel/Cfs/CfsStr.HC's formatter did not implement -- an unhandled
// conversion comes out as its own two characters AND DOES NOT CONSUME ITS ARGUMENT, so every
// argument after it shifts. tools/cfs/check_formats.py is the static gate that now says so
// before a transcript has to.
#ifndef MM_MSG_HC
#define MM_MSG_HC

/*******************************************************************************/
// mm_interface_cfg.h. Reaches NASA's code through MM_INTERFACE_CFGVAL(x), which
// default_mm_interface_cfg_values.h defines as DEFAULT_MM_INTERFACE_##x -- "use the default
// configuration value for all". The value below is that default, resolved, because HolyC has
// no token pasting. The same holds for every MM_INTERNAL_* name further down.
#define MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA 200

/*******************************************************************************/
// mm_internal_cfg.h -- the private side of the configuration.
//
// Two of these are not literals in NASA's header and are written out here with the expansion
// stated, because check_constants compares the value this file declares against NASA's own
// preprocessor:
//   CMD_PIPE_DEPTH            = 3 * CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT, and that limit is 4
//   MAX_DUMP_INEVENT_BYTES    = (CFE_MISSION_EVS_MAX_MESSAGE_LENGTH - (13 + 33)) / 5, and
//                               CFE_MISSION_EVS_MAX_MESSAGE_LENGTH is 122, so (122 - 46) / 5
#define MM_INTERNAL_CMD_PIPE_DEPTH  12
#define MM_INTERNAL_CMD_PIPE_NAME   "MM_CMD_PIPE"
#define MM_INTERNAL_SB_TIMEOUT      1000
#define MM_INTERNAL_CFE_HDR_SUBTYPE 0x4D4D5354
#define MM_INTERNAL_CFE_HDR_DESCRIPTION "Memory Manager dump file"

// The per-memory-type command limits. All six of the MEM8/MEM16/MEM32 sets are present because
// MM_INTERNAL_OPT_CODE_MEM8_MEMTYPE, _MEM16_ and _MEM32_ are all DEFINED in NASA's default
// configuration -- so none of the #ifdef'd cases in mm_utils.c, mm_mem8.c, mm_mem16.c or
// mm_mem32.c is excluded, and check_coverage sees every function.
#define MM_INTERNAL_MAX_LOAD_FILE_DATA_RAM    1048576
#define MM_INTERNAL_MAX_LOAD_FILE_DATA_EEPROM 131072
#define MM_INTERNAL_MAX_LOAD_FILE_DATA_MEM32  1048576
#define MM_INTERNAL_MAX_LOAD_FILE_DATA_MEM16  1048576
#define MM_INTERNAL_MAX_LOAD_FILE_DATA_MEM8   1048576
#define MM_INTERNAL_MAX_DUMP_FILE_DATA_RAM    1048576
#define MM_INTERNAL_MAX_DUMP_FILE_DATA_EEPROM 131072
#define MM_INTERNAL_MAX_DUMP_FILE_DATA_SYMTBL 131072
#define MM_INTERNAL_MAX_DUMP_FILE_DATA_MEM32  1048576
#define MM_INTERNAL_MAX_DUMP_FILE_DATA_MEM16  1048576
#define MM_INTERNAL_MAX_DUMP_FILE_DATA_MEM8   1048576
#define MM_INTERNAL_MAX_FILL_DATA_RAM         1048576
#define MM_INTERNAL_MAX_FILL_DATA_EEPROM      131072
#define MM_INTERNAL_MAX_FILL_DATA_MEM32       1048576
#define MM_INTERNAL_MAX_FILL_DATA_MEM16       1048576
#define MM_INTERNAL_MAX_FILL_DATA_MEM8        1048576

// The i/o segment sizes. These three are ARRAY BOUNDS in MM_AppData_t -- and NASA divides each
// by 4 while declaring the arrays `size_t`, so a 200-byte segment is 50 eight-byte elements and
// the buffer is 400 bytes. That is NASA's arithmetic, kept verbatim; check_padding measures it.
#define MM_INTERNAL_MAX_LOAD_DATA_SEG 200
#define MM_INTERNAL_MAX_DUMP_DATA_SEG 200
#define MM_INTERNAL_MAX_FILL_DATA_SEG 200

#define MM_INTERNAL_PROCESSOR_CYCLE        0
#define MM_INTERNAL_MISSION_REV            0xFF
#define MM_INTERNAL_MAX_DUMP_INEVENT_BYTES 15
#define MM_INTERNAL_DUMPINEVENT_TEMP_CHARS 36

// CFE_MISSION_ES_DEFAULT_CRC, which is CFE_ES_CrcType_16_ARC -- 1.
#define MM_INTERNAL_DUMP_FILE_CRC_TYPE 1
#define MM_INTERNAL_LOAD_WID_CRC_TYPE  1
#define MM_INTERNAL_LOAD_FILE_CRC_TYPE 1

// The four "cleared" values MM_ResetHk writes. NASA spells the two character ones '\0'.
#define MM_INTERNAL_CLEAR_SYMNAME '\0'
#define MM_INTERNAL_CLEAR_FNAME   '\0'
#define MM_INTERNAL_CLEAR_ADDR    0
#define MM_INTERNAL_CLEAR_PATTERN 0

// The three peek/poke widths, in BITS -- the ground commands a width, not a size.
#define MM_INTERNAL_BYTE_BIT_WIDTH  8
#define MM_INTERNAL_WORD_BIT_WIDTH  16
#define MM_INTERNAL_DWORD_BIT_WIDTH 32

/*******************************************************************************/
// default_mm_msgids.h. Each resolves through CFE_PLATFORM_CMD_TOPICID_TO_MIDV or its telemetry
// twin and an MM topic id (0x88 command, 0x89 send-hk, 0x87 telemetry), so the values are
// written out and check_constants compares them against NASA's own expansion.
#define MM_CMD_MID     0x1888
#define MM_SEND_HK_MID 0x1889
#define MM_HK_TLM_MID  0x887

/*******************************************************************************/
// default_mm_extern_typedefs.h.
//
// MM_MemAddress_t is CFE_ES_MemAddress_t, which this port's cFE configuration makes a uint64 --
// the same choice cfe_tbl_msg.HC records for the three MemAddress fields in the registry
// packet. MM_MemSize_t is a uint32.

// MM_LastAction_Enum_t is a `typedef uint8` over an ANONYMOUS enum, so unlike MD's
// MD_Dwell_States these values are one byte wide WHEREVER they are stored -- HkTlm declares
// LastAction as a plain uint8. Fourteen of them, and they are the whole of what housekeeping
// says about what MM last did.
#define MM_LastAction_NOACTION        0
#define MM_LastAction_PEEK            1
#define MM_LastAction_POKE            2
#define MM_LastAction_LOAD_FROM_FILE  3
#define MM_LastAction_LOAD_WID        4
#define MM_LastAction_DUMP_TO_FILE    5
#define MM_LastAction_DUMP_INEVENT    6
#define MM_LastAction_FILL            7
#define MM_LastAction_SYM_LOOKUP      8
#define MM_LastAction_SYMTBL_SAVE     9
#define MM_LastAction_EEPROMWRITE_ENA 10
#define MM_LastAction_EEPROMWRITE_DIS 11
#define MM_LastAction_NOOP            12
#define MM_LastAction_RESET           13

// MM_MemType_Enum_t IS A NAMED `typedef enum`, so it is four bytes wide as a member and as a
// parameter -- which is the opposite of MM_LastAction above, and the distinction is load-bearing
// in six of MM's payload layouts.
#define MM_MemType_NOMEMTYPE 0
#define MM_MemType_RAM       1
#define MM_MemType_EEPROM    2
#define MM_MemType_MEM8      3
#define MM_MemType_MEM16     4
#define MM_MemType_MEM32     5

// AN ADDRESS AS THE GROUND SPELLS IT: either a symbol name plus an offset, or -- when SymName
// is the empty string -- the offset alone, used as an absolute address. MM_ResolveSymAddr is
// the only thing that interprets it, and it is the function every other MM address path calls
// first. Same shape as MD_SymAddr_t and a separate type, because it is a separate app's
// interface.
class MM_SymAddr_t
{
  U64 Offset; // MM_MemAddress_t
  U8 SymName[CFE_MISSION_MAX_PATH_LEN];
};

/*******************************************************************************/
// default_mm_msgdefs.h -- the command and telemetry payloads. EVERY ONE THAT CARRIES AN
// ADDRESS ends with an MM_SymAddr_t, which opens with a uint64 and so forces the payload to
// 8-byte alignment; that is where most of NASA's own Padding fields come from, and they carry
// NASA's names rather than this port's.

class MM_PeekCmd_Payload_t
{
  U32 DataSize; // MM_MemSize_t -- in BITS for a peek, not bytes
  U32 MemType;  // MM_MemType_Enum_t
  MM_SymAddr_t SrcSymAddress;
};

class MM_PokeCmd_Payload_t
{
  U32 DataSize; // MM_MemSize_t -- in BITS
  U32 MemType;  // MM_MemType_Enum_t
  U32 Data;
  U8 Padding2[4]; // NASA's own name, and NASA's own gap
  MM_SymAddr_t DestSymAddress;
};

// LOAD WITH INTERRUPTS DISABLED. The data travels INSIDE the command, up to
// MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA bytes of it, with a CRC -- there is no file and no
// chance for anything else to run between the first byte and the last.
class MM_LoadMemWIDCmd_Payload_t
{
  U8 NumOfBytes;
  U8 Padding[3]; // NASA's own name
  U32 Crc;
  MM_SymAddr_t DestSymAddress;
  U8 DataArray[MM_INTERFACE_MAX_UNINTERRUPTIBLE_DATA];
};

class MM_DumpInEventCmd_Payload_t
{
  U32 MemType; // MM_MemType_Enum_t
  U8 NumOfBytes;
  U8 Padding[3]; // NASA's own name
  MM_SymAddr_t SrcSymAddress;
};

// The load command carries ONLY a filename: the address, length and memory type come from the
// file's own MM_LoadDumpFileHeader_t below.
class MM_LoadMemFromFileCmd_Payload_t
{
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
};

class MM_DumpMemToFileCmd_Payload_t
{
  U32 MemType;    // MM_MemType_Enum_t
  U32 NumOfBytes; // MM_MemSize_t
  MM_SymAddr_t SrcSymAddress;
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
};

class MM_FillMemCmd_Payload_t
{
  U32 MemType;    // MM_MemType_Enum_t
  U32 NumOfBytes; // MM_MemSize_t
  U32 FillPattern;
  U8 Padding[4]; // NASA's own name
  MM_SymAddr_t DestSymAddress;
};

class MM_LookupSymCmd_Payload_t
{
  U8 SymName[CFE_MISSION_MAX_PATH_LEN];
};

class MM_SymTblToFileCmd_Payload_t
{
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
};

class MM_EepromWriteEnaCmd_Payload_t
{
  U32 Bank;
};

class MM_EepromWriteDisCmd_Payload_t
{
  U32 Bank;
};

// HOUSEKEEPING. MM reports WHAT IT LAST DID rather than a standing state, which is the
// difference between a patch tool and a monitor: there is one LastAction, one address, one
// value and one byte count, and they describe the most recent command.
class MM_HkTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 LastAction; // MM_LastAction_Enum_t, one byte -- see the note on the enum above
  U8 Padding;    // NASA's own name
  U32 MemType;   // MM_MemType_Enum_t, four bytes
  U64 Address;   // MM_MemAddress_t
  U32 DataValue;
  U32 BytesProcessed; // MM_MemSize_t
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
};

/*******************************************************************************/
// default_mm_msgstruct.h -- each payload above with its cFE header in front.

class MM_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class MM_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class MM_PeekCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_PeekCmd_Payload_t Payload;
};

class MM_PokeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_PokeCmd_Payload_t Payload;
};

class MM_LoadMemWIDCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_LoadMemWIDCmd_Payload_t Payload;
};

class MM_DumpInEventCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_DumpInEventCmd_Payload_t Payload;
};

class MM_LoadMemFromFileCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_LoadMemFromFileCmd_Payload_t Payload;
};

class MM_DumpMemToFileCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_DumpMemToFileCmd_Payload_t Payload;
};

class MM_FillMemCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_FillMemCmd_Payload_t Payload;
};

class MM_LookupSymCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_LookupSymCmd_Payload_t Payload;
};

class MM_SymTblToFileCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_SymTblToFileCmd_Payload_t Payload;
};

class MM_EepromWriteEnaCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_EepromWriteEnaCmd_Payload_t Payload;
};

class MM_EepromWriteDisCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  MM_EepromWriteDisCmd_Payload_t Payload;
};

class MM_HkTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  MM_HkTlm_Payload_t Payload;
};

class MM_SendHkCmd_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
};

/*******************************************************************************/
// default_mm_filedefs.h. THE HEADER MM WRITES AFTER cFE's OWN FILE HEADER, in every dump and
// expected in every load: where the data came from or goes, how much of it there is, and a CRC.
class MM_LoadDumpFileHeader_t
{
  MM_SymAddr_t SymAddress;
  U32 NumOfBytes;
  U32 Crc;
  U32 MemType; // MM_MemType_Enum_t
  U8 Spare[3];
  // C's tail padding: the struct aligns to 8 through SymAddress's uint64, and Spare[3] ends at
  // 87. A trailing pad is invisible to every member offset and shows up only in sizeof, which
  // is exactly what a file header's record size is -- so it is written out rather than left to
  // the compiler.
  U8 _pad0[1];
};
#endif
