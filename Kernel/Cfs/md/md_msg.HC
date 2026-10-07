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
// MEMORY DWELL'S VOCABULARY -- the translation of NASA's MD config headers:
// default_md_interface_cfg_values.h, default_md_extern_typedefs.h, default_md_tbldefs.h,
// default_md_msgdefs.h and default_md_msgstruct.h. This is the FIRST cFS APP in the port, so
// it is worth saying what one is: an app is mission software that runs on top of cFE and
// talks to it only through the public API. Nothing in cFE knows MD exists.
//
// WHAT MEMORY DWELL DOES. The ground gives it a list of (address, length, delay) triples --
// a DWELL TABLE -- and MD walks the list, reads each address, packs the bytes into a
// telemetry packet, and sends it. It is the tool you use when the thing you need to see has
// no telemetry point of its own. Four tables, 25 entries each, independently startable.
//
// THE ADDRESSES ARE THE WHOLE PROBLEM for a differential transcript, and the answer is in
// docs/CFS_PLAN.md: the dwell PACKET carries only the bytes read, but NASA's own event text
// prints a resolved cpuaddr with %08X, and a host process and a QEMU guest never agree about
// a real address. MD_ResolveSymAddr returns Offset VERBATIM when SymName is empty, so the
// exercise uses literal window addresses that are the same constant on both halves, and the
// window itself is simulated hardware behind CFE_PSP_MemRead8/16/32.
//
// A DWELL TABLE IS A cFE TABLE, registered with CFE_TBL_Register and loaded, validated and
// activated by the ground through Table Services. So MD is also the first thing in this port
// that USES tbl from the outside rather than being tested from inside it.
#ifndef MD_MSG_HC
#define MD_MSG_HC

/*******************************************************************************/
// md_interface_cfg.h. Every one of these reaches NASA's code through
// MD_INTERFACE_CFGVAL(x), which default_md_interface_cfg_values.h defines as
// DEFAULT_MD_INTERFACE_##x -- "use the default configuration value for all". The values below
// are those defaults, resolved, because HolyC has no token pasting.
#define MD_INTERFACE_SIGNATURE_FIELD_LENGTH 32
#define MD_INTERFACE_NUM_DWELL_TABLES       4
#define MD_INTERFACE_DWELL_TABLE_SIZE       25

// THESE TWO ARE NOT COMPILED AS `#if` AND THAT IS DELIBERATE. Both guard conditional code in
// NASA's sources, and docs/HOLYC_STRUCT_LIMITS.md #19 records that `#if <expr>` is
// unconditionally TRUE in this compiler unless the operand is a literal 0. So an `#if
// MD_INTERFACE_SIGNATURE_OPTION == 1` here would take the true branch whatever the value was.
// It happens to be 1, which is the DANGEROUS case: the two halves would agree by accident and
// nothing would fail. Every such branch is therefore hand-resolved to the branch this
// configuration takes, with the value stated at the site, and these two names exist only so
// the value can be read and checked by check_constants against NASA's header.
#define MD_INTERFACE_ENFORCE_DWORD_ALIGN    1
#define MD_INTERFACE_SIGNATURE_OPTION       1

/*******************************************************************************/
// md_internal_cfg.h -- the private side of the configuration, reaching NASA's code through
// MD_INTERNAL_CFGVAL(x) the same way.
// md_msgids.h. Both resolve through CFE_PLATFORM_MD_TLM_MIDVAL and a topic id, so the values
// are written out and check_constants compares them against NASA's own expansion.
#define MD_HK_TLM_MID         0x890
#define MD_DWELL_PKT_MID_BASE 0x891
#define MD_CMD_MID            0x1890
#define MD_SEND_HK_MID        0x1891
#define MD_WAKEUP_MID         0x1892

#define MD_INTERNAL_PIPE_DEPTH  50
#define MD_INTERNAL_MISSION_REV 0xFF

/*******************************************************************************/
// default_md_extern_typedefs.h. AN ADDRESS AS THE GROUND SPELLS IT: either a symbol name
// plus an offset, or -- when SymName is the empty string -- the offset alone, used as an
// absolute address. MD_ResolveSymAddr is the only thing that interprets it.
class MD_SymAddr_t
{
  U64 Offset; // cpuaddr
  U8 SymName[CFE_MISSION_MAX_PATH_LEN];
};

// MD_Dwell_States, a 2-value C enum and so four bytes wide where it is a member.
#define MD_Dwell_States_DISABLED 0
#define MD_Dwell_States_ENABLED  1

/*******************************************************************************/
// default_md_tbldefs.h. ONE ENTRY OF A DWELL TABLE AS THE GROUND LOADS IT. A zero Length is
// the terminator, which is why MD_UpdateDwellControlInfo stops at the first one rather than
// counting to 25.
class MD_TableLoadEntry_t
{
  U16 Length;
  U16 Delay;
  // MD_SymAddr_t opens with a cpuaddr, so NASA's struct is 8-aligned and the two U16s above
  // leave four bytes before DwellAddress at offset 8. check_padding measures it.
  U8 _pad0[4];
  MD_SymAddr_t DwellAddress;
};

// default_md_tblstruct.h. THE TABLE AS IT ARRIVES FROM A FILE. Signature is present because
// MD_INTERFACE_SIGNATURE_OPTION is 1 -- see the note on that constant above for why this is
// written out rather than guarded.
class MD_DwellTableLoad_t
{
  U32 Enabled; // MD_Dwell_States
  U8 Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH];
  // Entry[] is 8-aligned for the same reason, and 4 + 32 is 36.
  U8 _pad0[4];
  MD_TableLoadEntry_t Entry[MD_INTERFACE_DWELL_TABLE_SIZE];
};

/*******************************************************************************/
// default_md_msgdefs.h -- the command and telemetry payloads.

// START and STOP both take a bitmask of tables, bit 0 being table 1. MD_TableIsInMask is the
// one function that reads it.
class MD_CmdStartStop_Payload_t
{
  U16 TableMask;
  U16 Padding; // NASA's own name for it, not this port's padding
};

// THE DWELL PACKET. Data is the only thing in MD that carries memory contents to the ground,
// and the four-bytes-per-entry bound is a worst case: an entry may dwell 1, 2 or 4 bytes.
class MD_DwellPkt_Payload_t
{
  U8 TableId;
  U8 AddrCount;
  U16 ByteCount;
  U32 Rate;
  U8 Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH];
  U8 Data[MD_INTERFACE_DWELL_TABLE_SIZE * 4];
};

// JAM writes one entry of one table in place, without a file load. It is how an operator
// changes a single address, and it is the command that resolves a symbolic address -- so it
// is also the command whose rejection events print an address.
class MD_CmdJam_Payload_t
{
  U16 TableId;
  U16 EntryId;
  U16 FieldLength;
  U16 DwellDelay;
  MD_SymAddr_t DwellAddress;
};

// Present because MD_INTERFACE_SIGNATURE_OPTION is 1.
class MD_CmdSetSignature_Payload_t
{
  U16 TableId;
  U16 Padding; // NASA's own name
  U8 Signature[MD_INTERFACE_SIGNATURE_FIELD_LENGTH];
};

// HOUSEKEEPING. Six parallel arrays, one element per table, which is MD reporting the whole
// of its control state every cycle.
class MD_HkTlm_Payload_t
{
  U8 InvalidCmdCntr;
  U8 ValidCmdCntr;
  U16 DwellEnabledMask;
  U16 DwellTblAddrCount[MD_INTERFACE_NUM_DWELL_TABLES];
  U16 NumWaitsPerPkt[MD_INTERFACE_NUM_DWELL_TABLES];
  U16 ByteCount[MD_INTERFACE_NUM_DWELL_TABLES];
  U16 DwellPktOffset[MD_INTERFACE_NUM_DWELL_TABLES];
  U16 DwellTblEntry[MD_INTERFACE_NUM_DWELL_TABLES];
  U16 Countdown[MD_INTERFACE_NUM_DWELL_TABLES];
};

/*******************************************************************************/
// default_md_msgstruct.h -- a header and a payload each, the shape every cFS message has.
class MD_HkTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  MD_HkTlm_Payload_t Payload;
};

class MD_StartDwellCmd_t
{
  CFE_MSG_CommandHeader Header;
  MD_CmdStartStop_Payload_t Payload;
};

class MD_StopDwellCmd_t
{
  CFE_MSG_CommandHeader Header;
  MD_CmdStartStop_Payload_t Payload;
};

class MD_DwellPkt_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  MD_DwellPkt_Payload_t Payload;
};

class MD_JamDwellCmd_t
{
  CFE_MSG_CommandHeader Header;
  MD_CmdJam_Payload_t Payload;
};

// Present because MD_INTERFACE_SIGNATURE_OPTION is 1.
class MD_SetSignatureCmd_t
{
  CFE_MSG_CommandHeader Header;
  MD_CmdSetSignature_Payload_t Payload;
};

class MD_NoopCmd_t
{
  CFE_MSG_CommandHeader CmdHeader;
};

class MD_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CmdHeader;
};

class MD_Wakeup_t
{
  CFE_MSG_CommandHeader CmdHeader;
};

class MD_SendHkCmd_t
{
  CFE_MSG_CommandHeader CmdHeader;
};
#endif
