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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_crc.c -- THE CHECKSUM.
//
// The first file of the ES module, and the smallest: 131 lines, three functions and a
// 256-entry table. It is here first because it has NO dependencies -- not on the pool, not on
// the resource tables, not on OSAL. Everything else in ES does.
//
// CFE_ES_CalculateCRC uses it to check a Critical Data Store, and TBL uses it on every table
// image. NASA ships exactly one real algorithm, CRC-16/ARC, plus a NONE placeholder that
// always returns 0 and is the catch-all for an unimplemented selection.
#ifndef CFE_ES_CRC_HC
#define CFE_ES_CRC_HC
#include "cfe_sb_util.HC" // CFE_SUCCESS and the integer typedefs, by way of the common chain
// --- cfe_es_api_typedefs.h: the algorithm identifiers ----------------------------------------
// NASA spells these as an ENUM, which is a shape this project has learned to be careful with:
// check_constants.py resolves an enumerator through the probe's second pass, so these ARE
// compared against NASA's header rather than taken on trust.
#define CFE_ES_CrcType_NONE   0
#define CFE_ES_CrcType_16_ARC 1
#define CFE_ES_CrcType_MAX    2
// The algorithm is reached through a function pointer so that CFE_ES_CalculateCRC does not
// have to know which one it is calling. `const struct` in the C -- the table below is read
// only, and nothing writes to it.
class CFE_ES_ComputeCRC_Params_t
{
  U32 InitialValue;
  U32 FinalXOR;
  // Function that implments the processing for this algorithm
  U32 (*Algorithm)(U8 *DataPtr, I64 DataLength, U32 InputCRC);
};

U32 CFE_ES_ComputeCRC_Algo_NONE(U8 *DataPtr, I64 DataLength, U32 InputCRC)
{
  /* This is a placeholder algorithm that always returns 0, no matter what the input was */
  return 0;
}
// NASA declares this table `static` INSIDE CFE_ES_ComputeCRC_Algo_16_ARC. A static local is a
// file-scope global in HolyC, so it is one here -- and the name carries the function's, which
// is the convention the other static-local translations in this port use.
//
// The 256 values are NASA's, lifted verbatim rather than generated: a table a tool rebuilt
// from the polynomial would be a second implementation to get wrong, and the whole point of a
// 1:1 translation is that there is only one.
U16 CFE_ES_ComputeCRC_Algo_16_ARC_CrcTable[256] = {0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241, 0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440, 0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40, 0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841, 0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40, 0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41, 0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641, 0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040, 0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240, 0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441, 0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41, 0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840, 0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41, 0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40, 0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640, 0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041, 0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240, 0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441, 0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41, 0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840, 0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41, 0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40, 0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640, 0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041, 0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241, 0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440, 0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40, 0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841, 0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40, 0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41, 0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641, 0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040};
U32 CFE_ES_ComputeCRC_Algo_16_ARC(U8 *DataPtr, I64 DataLength, U32 InputCRC)
{
  I64 i;
  U16 Index;
  U16 Crc;
  U8 *BufPtr;
  i = DataLength;
  BufPtr = DataPtr;
  Crc = InputCRC;
  while (i > 0) {
    /*
     * It is assumed that the supplied buffer is in a
     * directly-accessible memory space that does not
     * require special logic to access
     */
    Index = *BufPtr;
    Index = (Crc ^ Index) & 0x00FF;
    Crc = ((Crc >> 8) & 0x00FF) ^ CFE_ES_ComputeCRC_Algo_16_ARC_CrcTable[Index];
    --i;
    ++BufPtr;
  }
  return Crc;
}
// The two static tables CFE_ES_ComputeCRC_GetParams returns pointers INTO, hoisted to file
// scope for the same reason as the CRC table above. HolyC takes an aggregate initialiser
// containing a FUNCTION POINTER at file scope -- measured before this was written, because the
// recorded limit about aggregate initialisers is a LOCAL one and reads as if it applied here.
// So these need no invented init function and are as close to NASA's `static const` as the
// language allows.
//
// THE "NONE" ENTRY IN THE MAIN TABLE HAS A NULL ALGORITHM AND THAT IS DELIBERATE -- NASA's own
// comment says so. CFE_ES_CrcType_NONE does have a defined algorithm (the one above, which
// returns 0), but the table entry leaves it NULL so that the catch-all below is reachable from
// a type that IS in range. Testing coverage, in NASA's words.
CFE_ES_ComputeCRC_Params_t CFE_ES_ComputeCRC_GetParams_CRC_PARAM_NONE = {0, 0, &CFE_ES_ComputeCRC_Algo_NONE};
CFE_ES_ComputeCRC_Params_t CFE_ES_ComputeCRC_GetParams_CRC_PARAM_TABLE[CFE_ES_CrcType_MAX] = {{0, 0, NULL}, {0, 0, &CFE_ES_ComputeCRC_Algo_16_ARC}};
CFE_ES_ComputeCRC_Params_t *CFE_ES_ComputeCRC_GetParams(U32 CrcType)
{
  CFE_ES_ComputeCRC_Params_t *ParamPtr;
  if (CrcType < CFE_ES_CrcType_MAX) {
    ParamPtr = &CFE_ES_ComputeCRC_GetParams_CRC_PARAM_TABLE[CrcType];
  } else {
    ParamPtr = NULL;
  }
  /* Catch-all: Fall back to NONE if not implemented */
  if (ParamPtr == NULL || ParamPtr->Algorithm == NULL) {
    ParamPtr = &CFE_ES_ComputeCRC_GetParams_CRC_PARAM_NONE;
  }
  return ParamPtr;
}
#endif
