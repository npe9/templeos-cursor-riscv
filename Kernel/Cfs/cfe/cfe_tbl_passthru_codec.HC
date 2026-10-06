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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_passthru_codec.c -- THE CODEC THAT
// DOES NOTHING, which is the point of it.
//
// cFS can be built two ways. With EDS enabled, a table file carries an externally-specified
// encoding and `cfe_tbl_eds_codec.c` translates between the file's layout and the processor's.
// WITHOUT it -- this configuration -- a table file is a raw image of the table's memory, so
// the "codec" is a set of functions that copy and return CFE_SUCCESS. CMake picks one of the
// two; tools/cfs/check_manifest.py is what records which branch a configuration takes.
//
// That makes this file the DEFINITION OF THE SEAM rather than an implementation of it, and
// several functions are deliberately empty: ValidateCodecConfig has "nothing to check here in
// this implementation", ReleaseCodecBuffer has "nothing to do", AcquireCodecBuffer returns the
// in-progress buffer because there is no separate one to decode into, and Encode/Decode are a
// straight copy guarded by a pointer comparison -- "the bits are the same".
//
// THE ONE THING IT REALLY DOES IS BYTE ORDER. A cFE table file header is BIG ENDIAN on the
// wire, always, so that a file written on one processor can be loaded on another. This target
// is little endian, so the three 32-bit fields are swapped on the way in and on the way out.
// The endianness test is NASA's own trick -- read the first byte of 0x01020304 and see whether
// it is 0x04 -- and it is done at run time rather than by #ifdef, which is why the swap is in
// the translation at all rather than being configured away.
//
// AND THE HEADER'S SIZES ARE 32-BIT ON PURPOSE. NASA's note: "the Offset and NumBytes fields
// in the table header are to 32 bits for backward compatibility with existing CFE versions.
// This means that even on 64-bit CPUs, individual table files will be limited to 4GiB."
#ifndef CFE_TBL_PASSTHRU_CODEC_HC
#define CFE_TBL_PASSTHRU_CODEC_HC
// cfe_tbl_eventids.h
#ifndef CFE_TBL_FILE_TBL_HDR_ERR_EID
#define CFE_TBL_FILE_TBL_HDR_ERR_EID      55
#define CFE_TBL_WRITE_TBL_HDR_ERR_EID     64
#define CFE_TBL_LOAD_EXCEEDS_SIZE_ERR_EID 72
#endif
// cfe_error.h
#ifndef CFE_TBL_ERR_NO_TBL_HEADER
#define CFE_TBL_ERR_NO_TBL_HEADER 0xCC00001E(I32)
#define CFE_TBL_ERR_ACCESS 0xCC00002C(I32)
#define CFE_TBL_ERR_FILE_TOO_LARGE 0xCC000014(I32)
#define CFE_TBL_WARN_PARTIAL_LOAD  0x4C000022
#define CFE_TBL_WARN_SHORT_FILE    0x4C000015
#endif

// --- default_cfe_tbl_extern_typedefs.h ------------------------------------------------------
// The table-specific file header, which follows the CFE_FS header and precedes the data.
class CFE_TBL_File_Hdr_t
{
  U32 Reserved; // Future Use: NumTblSegments in File?
  U32 Offset;   // Byte Offset at which load should commence
  U32 NumBytes; // Number of bytes to load into table
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN]; // Fully qualified name of table to load
};

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_ByteSwapUint32(U32 *Uint32ToSwapPtr)
{
  // THROUGH A LOCAL COPY, and that is not incidental: InPtr reads from Temp while OutPtr
  // writes to the original, so no byte is read after it has been overwritten. Swapping in
  // place with two pointers into the same word would corrupt it.
  I32 Temp = *Uint32ToSwapPtr;
  U8 *InPtr = &Temp;
  U8 *OutPtr = Uint32ToSwapPtr;
  /* SAD: Safe access to InPtr[0-3] and OutPtr[0-3] as both manipulate bytes within 4-byte
  ** integers. */
  OutPtr[0] = InPtr[3];
  OutPtr[1] = InPtr[2];
  OutPtr[2] = InPtr[1];
  OutPtr[3] = InPtr[0];
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_ByteSwapTblHeader(CFE_TBL_File_Hdr_t *HdrPtr)
{
  // THREE FIELDS, NOT FOUR. TableName is bytes and needs no swapping -- which is also why the
  // header can be read as a struct at all.
  CFE_TBL_ByteSwapUint32(&HdrPtr->Reserved);
  CFE_TBL_ByteSwapUint32(&HdrPtr->Offset);
  CFE_TBL_ByteSwapUint32(&HdrPtr->NumBytes);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DecodeHeadersFromFile(CFE_TBL_TxnState_t *Txn, U32 FileDescriptor,
                                  CFE_TBL_File_Hdr_t *HeaderPtr)
{
  U32 EndianCheck = 0x01020304;
  I32 ReturnCode;
  I32 OsStatus;
  CFE_TBL_File_Hdr_t Buffer;
  /* In this mode file data is read directly to the struct */
  OsStatus = OS_read(FileDescriptor, &Buffer, sizeof(CFE_TBL_File_Hdr_t));
  /* Verify successful read of cFE Table File Header */
  if (OsStatus != sizeof(CFE_TBL_File_Hdr_t)) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_TBL_HDR_ERR_EID, OsStatus,
                        sizeof(CFE_TBL_File_Hdr_t));
    ReturnCode = CFE_TBL_ERR_NO_TBL_HEADER;
  } else {
    /* cppcheck-suppress knownConditionTrueFalse */
    if (*(&EndianCheck)(U8 *) == 0x04) {
      /* If this is a little endian processor, then the standard cFE Table Header,   */
      /* which is in big endian format, must be swapped so that the data is readable */
      CFE_TBL_ByteSwapTblHeader(&Buffer);
    }
    /*
    ** Ensure termination of all local strings. These were read from a file, so they
    ** must be treated with appropriate care.  This could happen in case the file got
    ** damaged in transit or simply was not written properly to begin with.
    */
    Buffer.TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1] = '\0';
    /* Export the data to the user buffer */
    MemCpy(HeaderPtr, &Buffer, sizeof(CFE_TBL_File_Hdr_t));
    ReturnCode = CFE_SUCCESS;
  }
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_EncodeHeadersToFile(CFE_TBL_TxnState_t *Txn, U32 FileDescriptor,
                                CFE_TBL_File_Hdr_t *HeaderPtr)
{
  U32 EndianCheck = 0x01020304;
  I32 ReturnCode;
  I32 OsStatus;
  CFE_TBL_File_Hdr_t Buffer;
  MemCpy(&Buffer, HeaderPtr, sizeof(CFE_TBL_File_Hdr_t));
  /* cppcheck-suppress knownConditionTrueFalse */
  if (*(&EndianCheck)(U8 *) == 0x04) {
    /* If this is a little endian processor, then byte swap the header to a big endian format */
    /* to maintain the cFE Header standards */
    CFE_TBL_ByteSwapTblHeader(&Buffer);
  }
  /* Output the Table Image Header to the Dump File */
  OsStatus = OS_write(FileDescriptor, &Buffer, sizeof(CFE_TBL_File_Hdr_t));
  /* Make sure the header was output completely */
  if (OsStatus != sizeof(CFE_TBL_File_Hdr_t)) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_WRITE_TBL_HDR_ERR_EID, OsStatus,
                        sizeof(CFE_TBL_File_Hdr_t));
    ReturnCode = CFE_TBL_ERR_ACCESS;
  } else {
    ReturnCode = CFE_SUCCESS;
  }
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateCodecLoadSize(CFE_TBL_TxnState_t *Txn, CFE_TBL_File_Hdr_t *HeaderPtr)
{
  I32 Status;
  U32 ActualSize;
  U32 ProjectedSize;
  /* Because the file sizes and in-memory size is the same, this check is simple */
  ActualSize = CFE_TBL_RegRecGetSize(CFE_TBL_TxnRegRec(Txn));
  ProjectedSize = HeaderPtr->Offset + HeaderPtr->NumBytes;
  // THE FIRST TEST IS AN OVERFLOW CHECK, not a duplicate of the second: Offset and NumBytes
  // are both 32-bit and attacker-supplied, so their sum can wrap. A wrapped sum is smaller
  // than Offset, and would otherwise pass the size test and then be used as a length.
  if (ProjectedSize < HeaderPtr->Offset || ProjectedSize > ActualSize) {
    Status = CFE_TBL_ERR_FILE_TOO_LARGE;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_EXCEEDS_SIZE_ERR_EID, ProjectedSize, ActualSize);
  } else {
    Status = CFE_SUCCESS;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_CodecGetFinalStatus(CFE_TBL_TxnState_t *Txn, CFE_TBL_File_Hdr_t *HeaderPtr)
{
  I32 Status;
  /* Any Table load that starts beyond the first byte is a "partial load" */
  /* But a file that starts with the first byte and ends before filling   */
  /* the whole table is just considered "short".                          */
  if (HeaderPtr->Offset > 0)
    Status = CFE_TBL_WARN_PARTIAL_LOAD;
  else if (HeaderPtr->NumBytes < CFE_TBL_RegRecGetSize(CFE_TBL_TxnRegRec(Txn)))
    Status = CFE_TBL_WARN_SHORT_FILE;
  else
    Status = CFE_SUCCESS;
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateCodecConfig(CFE_TBL_TableConfig_t *ReqCfg)
{
  no_warn ReqCfg;
  /* Nothing to check here in this implementation */
  return CFE_SUCCESS;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_AcquireCodecBuffer(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  /* No separate buffer - just load direct */
  return CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_ReleaseCodecBuffer(CFE_TBL_LoadBuff_t *BufferPtr)
{
  no_warn BufferPtr;
  /* Nothing to do */
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_EncodeOutputData(CFE_TBL_TxnState_t *Txn, CFE_TBL_LoadBuff_t *SourceBuffer,
                             CFE_TBL_LoadBuff_t *DestBuffer)
{
  no_warn Txn;
  if (SourceBuffer != DestBuffer) {
    /* This does a straight copy, the bits are the same */
    CFE_TBL_LoadBuffCopyData(DestBuffer, CFE_TBL_LoadBuffGetReadPointer(SourceBuffer),
                             CFE_TBL_LoadBuffGetContentSize(SourceBuffer));
  }
  return CFE_SUCCESS;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DecodeInputData(CFE_TBL_TxnState_t *Txn, CFE_TBL_LoadBuff_t *SourceBuffer,
                            CFE_TBL_LoadBuff_t *DestBuffer)
{
  no_warn Txn;
  if (SourceBuffer != DestBuffer) {
    /* This does a straight copy, the bits are the same */
    CFE_TBL_LoadBuffCopyData(DestBuffer, CFE_TBL_LoadBuffGetReadPointer(SourceBuffer),
                             CFE_TBL_LoadBuffGetContentSize(SourceBuffer));
  }
  return CFE_SUCCESS;
}
#endif
