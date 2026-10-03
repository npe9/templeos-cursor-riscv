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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_syslog.c -- THE SYSTEM LOG.
//
// CFE_ES_WriteToSysLog is the one cFS call that appears in every module's error path, and the
// differential driver has been answering it with a six-line stub since the EVS module landed.
// This is the real thing: an 8 KiB RING BUFFER IN THE RESET AREA -- memory that survives a
// processor reset -- so that the log explaining why the last boot failed is readable after it.
//
// THE BUFFER IS NOT A SIMPLE RING, and that is the part worth reading slowly. There are three
// indices, all in the reset area:
//   SystemLogWriteIdx  one past the newest message, where the next one goes
//   SystemLogEndIdx    how much of the buffer has EVER been used, not its capacity
//   SystemLogEntryNum  a count, for telemetry
// EndIdx exists because the buffer wraps only in OVERWRITE mode, and when it wraps it records
// where the old tail was so a reader can reconstruct the order. In DISCARD mode -- the default
// -- the log simply fills up and stops, which is the right behaviour for a flight log: the
// FIRST messages after a fault are the ones that explain it.
//
// A READER THEREFORE STARTS IN THE MIDDLE OF A MESSAGE, and CFE_ES_SysLogReadData prepends a
// literal "<<FRAGMENT>> " tag when it does. That string is in the dump file.
#ifndef CFE_ES_SYSLOG_HC
#define CFE_ES_SYSLOG_HC
#include "cfe_es_global.HC" // CFE_ES_Global, and the reset area the log lives in
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_ES_ERR_SYS_LOG_FULL      0xC4000006(I32)
#define CFE_ES_FILE_IO_ERR           0xC4000014(I32)
// NOT an error: 0x44... is cFE's INFORMATION severity. A truncated message was still logged.
#define CFE_ES_ERR_SYS_LOG_TRUNCATED 0x44000029(I32)
// --- cfe_es_eventids.h ------------------------------------------------------------------------
#define CFE_ES_SYSLOG2_EID     18
#define CFE_ES_SYSLOG2_ERR_EID 55
// --- cfe_es_platform_cfg.h / cfe_es_log.h ----------------------------------------------------
#define CFE_PLATFORM_ES_SYSTEM_LOG_SIZE 8192
#define CFE_ES_MAX_SYSLOG_MSG_SIZE      148
#define CFE_ES_SYSLOG_READ_BUFFER_SIZE  444
#define CFE_ES_SYS_LOG_DESC             "ES system log data file"
// --- default_cfe_es_extern_typedefs.h: the two log modes -------------------------------------
// OVERWRITE is 0 and DISCARD is 1, and DISCARD is the default -- which is the opposite of what
// a ring buffer usually does, for the reason in the header comment above.
#define CFE_ES_LogMode_OVERWRITE 0
#define CFE_ES_LogMode_DISCARD   1
// --- cfe_es_log.h -----------------------------------------------------------------------------
class CFE_ES_SysLogReadBuffer_t
{
  I64 SizeLeft;
  // size_t
  I64 BlockSize;
  // size_t
  I64 EndIdx;
  // size_t
  I64 LastOffset;
  // size_t
  Bool IsFragment;
  U8 Data[CFE_ES_SYSLOG_READ_BUFFER_SIZE];
  U8 _pad0[3];
  // C's TAIL padding: Data ends at 477 and the struct aligns to its size_t members, so 480.
  // The read buffer is a file-write unit, and a short one would write three bytes less per
  // block than it accounted for.
};
// --- what this file needs from elsewhere ------------------------------------------------------
// cfe_es_api.c and cfe_es_task.c, neither gated yet. Three functions, so three stubs on both
// halves of the differential oracle -- the same temporary arrangement
// CFE_SB_SendSubscriptionReport had until cfe_sb_task.c landed.
U0 CFE_ES_LockSharedData(U8 *FunctionName, I32 LineNumber);
U0 CFE_ES_UnlockSharedData(U8 *FunctionName, I32 LineNumber);
U0 CFE_ES_FileWriteByteCntErr(U8 *Filename, I64 Requested, I32 Status);
// OSAL and FS.
I32 OS_printf(U8 *fmt,...);
I32 OS_OpenCreate(U32 *filedes, U8 *path, I32 flags, I32 access_mode);
I32 OS_write(U32 filedes, U8 *buffer, I64 nbytes);
I32 OS_close(U32 filedes);
U0 CFE_FS_InitHeader(CFE_FS_Header_t *Hdr, U8 *Description, U16 SubType);
I32 CFE_FS_WriteHeader(U32 FileDes, CFE_FS_Header_t *Hdr);
// cfe_time_api.HC, translated.
U0 CFE_TIME_Print(U8 *PrintBuffer, CFE_TIME_SysTime TimeToPrint);
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_SysLogClear_Unsync()
{
  /*
   * Note - no need to actually memset the SystemLog buffer -
   * by simply zeroing out the indices will cover it.
   */
  CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx = 0;
  CFE_ES_Global.ResetDataPtr->SystemLogEndIdx = 0;
  CFE_ES_Global.ResetDataPtr->SystemLogEntryNum = 0;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE FRAGMENT TEST IS `ReadIdx != EndIdx`, AND THAT IS NOT AN OFF-BY-ONE. WriteIdx is where
// the next message goes; EndIdx is the high-water mark. They are equal only when the log has
// never wrapped, so a reader starting at WriteIdx is mid-message exactly when they differ.
U0 CFE_ES_SysLogReadStart_Unsync(CFE_ES_SysLogReadBuffer_t *Buffer)
{
  I64 ReadIdx;
  I64 EndIdx;
  ReadIdx = CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx;
  EndIdx = CFE_ES_Global.ResetDataPtr->SystemLogEndIdx;
  /* If the write position is NOT at the tail of the buffer, then its a fragement */
  Buffer->IsFragment = ReadIdx != EndIdx;
  Buffer->SizeLeft = EndIdx;
  Buffer->LastOffset = ReadIdx;
  Buffer->EndIdx = EndIdx;
  Buffer->BlockSize = 0;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE COPY IS `MessageLen - 1` AND THEN THE LAST BYTE IS FORCED TO A NEWLINE. That is NASA's,
// and it is what guarantees every entry in the dump ends in one even when the message was
// truncated -- the caller's own trailing newline is overwritten with the same character in the
// normal case, so the two paths agree.
//
// NOTE THE LOCAL SNAPSHOTS. NASA's comment says the indices are read into stack variables
// because CFE_ES_Global.ResetDataPtr "may point directly into a slower NVRAM space". Keeping
// that structure matters for a reason the comment does not give: the reset area is also the
// thing a crashing processor is most likely to have left half-written, and touching it once
// per field rather than once per update is the difference.
I32 CFE_ES_SysLogAppend_Unsync(U8 *LogString)
{
  I32 ReturnCode;
  I64 MessageLen;
  I64 WriteIdx;
  I64 EndIdx;
  /*
   * Sanity check - Make sure the message length is actually reasonable
   * Do not allow any single message to consume more than half of the total log
   * (even this may be overly generous)
   */
  MessageLen = StrLen(LogString);
  if (MessageLen > CFE_PLATFORM_ES_SYSTEM_LOG_SIZE / 2) {
    MessageLen = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE / 2;
    ReturnCode = CFE_ES_ERR_SYS_LOG_TRUNCATED;
  } else {
    ReturnCode = CFE_SUCCESS;
  }
  /*
   * Final sanity check -- do not bother logging empty messages
   */
  if (MessageLen == 0) {
    return ReturnCode;
  }
  /*
   * Real work begins --
   * Take a local snapshot of the head & tail index values
   *
   * WriteIdx -> indicates 1 byte past the end of the newest message
   *      (this is the place where new messages will be added)
   *
   * EndIdx -> indicates the entire size of the buffer
   *
   * Keeping them in local stack variables allows more efficient modification,
   * since CFE_ES_Global.ResetDataPtr may point directly into a slower NVRAM space.
   */
  WriteIdx = CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx;
  EndIdx = CFE_ES_Global.ResetDataPtr->SystemLogEndIdx;
  /*
   * Check if the log message plus will fit between
   * the HeadIdx and the end of the buffer.
   *
   * If so, then the process can proceed as normal.
   *
   * If not, then the action depends on the setting of "SystemLogMode" which will be
   * to either discard (default) or overwrite
   */
  if (WriteIdx + MessageLen > CFE_PLATFORM_ES_SYSTEM_LOG_SIZE) {
    if (CFE_ES_Global.ResetDataPtr->SystemLogMode == CFE_ES_LogMode_OVERWRITE) {
      /* In "overwrite" mode, start back at the beginning of the buffer */
      EndIdx = WriteIdx;
      WriteIdx = 0;
    } else if (WriteIdx < CFE_PLATFORM_ES_SYSTEM_LOG_SIZE - CFE_TIME_PRINTED_STRING_SIZE) {
      /* In "discard" mode, save as much as possible and discard the remainder of the message
       * However this should only be done if there is enough room for at least a full timestamp,
       * otherwise the fragment will not be useful at all. */
      MessageLen = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE - WriteIdx;
      ReturnCode = CFE_ES_ERR_SYS_LOG_TRUNCATED;
    } else {
      /* entire message must be discarded */
      MessageLen = 0;
    }
  }
  if (MessageLen == 0) {
    ReturnCode = CFE_ES_ERR_SYS_LOG_FULL;
  } else {
    /*
     * Copy the message in, EXCEPT for the last char which is probably a newline
     */
    MemCpy(&CFE_ES_Global.ResetDataPtr->SystemLog[WriteIdx], LogString, MessageLen - 1);
    WriteIdx += MessageLen;
    /*
     * Ensure that the last-written character is a newline.
     * This would have been enforced already except in cases where
     * the message got truncated.
     */
    CFE_ES_Global.ResetDataPtr->SystemLog[WriteIdx - 1] = '\n';
    /*
     * Keep track of the buffer endpoint for future reference
     */
    if (WriteIdx > EndIdx) {
      EndIdx = WriteIdx;
    }
    /*
     * Export updated index values to the reset area for next time.
     */
    CFE_ES_Global.ResetDataPtr->SystemLogWriteIdx = WriteIdx;
    CFE_ES_Global.ResetDataPtr->SystemLogEndIdx = EndIdx;
    ++CFE_ES_Global.ResetDataPtr->SystemLogEntryNum;
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE VARIADIC SEAM, and the one deviation in this file. NASA's signature is
//   int32 CFE_ES_SysLogWrite_Unsync(const char *SpecStringPtr, ...)
// which it forwards to CFE_ES_SysLog_vsnprintf as a va_list. HolyC's variadic calling
// convention hands the callee an implicit (argc, argv) pair instead, so the forward passes
// those two rather than one va_list -- exactly the arrangement cfe_evs_utils.HC's
// EVS_GenerateEventTelemetry records, and check_signatures.py carries it in DEVIATIONS with
// the reason rather than exempting the function.
//
// This matters more than a calling convention usually would: the formatted text IS the log
// entry, so the differential oracle compares what this produces character for character.
I32 CFE_ES_SysLogWrite_Unsync(U8 *SpecStringPtr,...)
{
  U8 TmpString[CFE_ES_MAX_SYSLOG_MSG_SIZE];
  CFE_ES_SysLog_vsnprintf(TmpString, CFE_ES_MAX_SYSLOG_MSG_SIZE, SpecStringPtr, argc, argv);
  /* Output the entry to the console */
  OS_printf("%s", TmpString);
  /*
   * Append to the syslog buffer
   */
  return CFE_ES_SysLogAppend_Unsync(TmpString);
}
/*******************************************************************
 *
 * Additional helper functions
 *
 * These functions either perform all necessary synchronization internally,
 * or they have no specific synchronization requirements
 *
 *******************************************************************/
// The fragment tag, which NASA declares `static const char FRAGMENT_TAG[]` inside
// CFE_ES_SysLogReadData. A static local is a file-scope global in HolyC. The length matters:
// NASA copies `sizeof(FRAGMENT_TAG) - 1` bytes, i.e. without the terminator, so the tag is 13
// characters and the string below must stay exactly that.
U8 *CFE_ES_SysLogReadData_FRAGMENT_TAG = "<<FRAGMENT>> ";
#define CFE_ES_FRAGMENT_TAG_LEN 13
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THREE-WAY MINIMUM, and each of the three bounds is a different kind of limit: how much log is
// left to copy, how much room is left in the output buffer, and how far it is to the wrap
// point. Taking them in that order is why the loop can both wrap and fill in one pass.
//
// THE `BlockSize == 0` BREAK IS NASA'S OWN BELT AND BRACES -- its comment says "should be
// impossible for this to happen, just in case, do not spin endlessly". It is kept, because a
// translation that dropped it would turn an impossible state into a hang rather than a stop.
U0 CFE_ES_SysLogReadData(CFE_ES_SysLogReadBuffer_t *Buffer)
{
  I64 BlockSize;
  if (Buffer->IsFragment) {
    /* Add a tag indicating that this block of data does not begin w/a complete message */
    MemCpy(Buffer->Data, CFE_ES_SysLogReadData_FRAGMENT_TAG, CFE_ES_FRAGMENT_TAG_LEN);
    Buffer->BlockSize = CFE_ES_FRAGMENT_TAG_LEN;
    Buffer->IsFragment = FALSE;
  } else {
    Buffer->BlockSize = 0;
  }
  while (Buffer->SizeLeft > 0 && Buffer->BlockSize < CFE_ES_SYSLOG_READ_BUFFER_SIZE) {
    /*
     * The next block to copy will be the SMALLEST of:
     *  - total remaining (un-copied) size of the syslog data
     *  - space available in the output buffer
     *  - space between the current read offset and the end of the log buffer (wrap point)
     */
    BlockSize = CFE_ES_SYSLOG_READ_BUFFER_SIZE - Buffer->BlockSize;
    if (Buffer->LastOffset >= Buffer->EndIdx) {
      Buffer->LastOffset = 0;
    }
    if (Buffer->LastOffset + BlockSize > Buffer->EndIdx) {
      BlockSize = Buffer->EndIdx - Buffer->LastOffset;
    }
    if (BlockSize > Buffer->SizeLeft) {
      BlockSize = Buffer->SizeLeft;
    }
    if (BlockSize == 0) {
      /* should be impossible for this to happen,
       * just in case, do not spin endlessly */
      break;
    }
    MemCpy(&Buffer->Data[Buffer->BlockSize], &CFE_ES_Global.ResetDataPtr->SystemLog[Buffer->LastOffset], BlockSize);
    Buffer->BlockSize += BlockSize;
    Buffer->LastOffset += BlockSize;
    Buffer->SizeLeft -= BlockSize;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_SysLogSetMode(U32 Mode)
{
  I32 Status;
  if (Mode == CFE_ES_LogMode_OVERWRITE || Mode == CFE_ES_LogMode_DISCARD) {
    CFE_ES_Global.ResetDataPtr->SystemLogMode = Mode;
    Status = CFE_SUCCESS;
  } else {
    Status = CFE_ES_BAD_ARGUMENT;
  }
  return Status;
}
// NASA calls isspace() from <ctype.h>. The port has no libc, and the set matters: the trailing
// whitespace strip below is what guarantees exactly one newline at the end of every entry, so
// this is C's isspace for the default locale -- space, \t, \n, \v, \f, \r -- and nothing else.
Bool CFE_ES_SysLogIsSpace(U8 c)
{
  return c == ' ' || c == '\t' || c == '\n' || c == 0x0B || c == 0x0C || c == '\r';
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// EVERY ENTRY GETS A TIMESTAMP AND EXACTLY ONE TRAILING NEWLINE, and the second of those is
// why the whitespace strip is here rather than left to the caller. NASA's comment: "The caller
// may or may not have included a newline in the original format string. Most callers do, but
// some do not." So all trailing whitespace comes off and one newline goes back on -- which is
// also what makes CFE_ES_SysLogAppend_Unsync's `MessageLen - 1` copy correct.
//
// THE BufferSize > CFE_TIME_PRINTED_STRING_SIZE + 2 GUARD IS NOT COSMETIC: below that there is
// no room for a timestamp plus a newline and a NUL, and the function writes NOTHING but the
// terminator. A smaller buffer gets an empty string rather than a partial timestamp.
//
// The va_list parameter is (argc, argv) here -- see CFE_ES_SysLogWrite_Unsync above.
U0 CFE_ES_SysLog_vsnprintf(U8 *Buffer, I64 BufferSize, U8 *SpecStringPtr, I64 nargs, I64 *args)
{
  I64 StringLen;
  I64 MaxLen;
  I64 PrintLen;
  /*
   * write the current time into the TmpString buffer
   *
   * Note that CFE_TIME_Print() is expected to produce a string of exactly
   * CFE_TIME_PRINTED_STRING_SIZE in length.
   */
  StringLen = 0;
  if (BufferSize > CFE_TIME_PRINTED_STRING_SIZE + 2) {
    /*
     * The "useful" buffer size is two less than the supplied buffer -
     * due to the addition of a newline and a null char to terminate the string
     */
    MaxLen = BufferSize - 2;
    CFE_TIME_Print(Buffer, CFE_TIME_GetTime);
    /* using strlen() anyway in case the specific format of CFE_TIME_Print() changes someday */
    StringLen = StrLen(Buffer);
    if (StringLen < MaxLen) {
      /* overwrite null with a space to separate the timestamp from the content */
      Buffer[StringLen] = ' ';
      ++StringLen;
      /* note that vsnprintf() may return a size larger than the buffer, if it truncates. */
      PrintLen = StrPrintNV(&Buffer[StringLen], BufferSize - StringLen, SpecStringPtr, nargs, args);
      if (PrintLen > 0) {
        StringLen += PrintLen;
      }
    }
    if (StringLen > MaxLen) {
      /* the message got truncated */
      StringLen = MaxLen;
    }
    /*
     * Finalize the output string.
     *
     * To be consistent when writing to the console, it is important that
     * every printed string end in a newline - particularly if the console is buffered.
     *
     * The caller may or may not have included a newline in the original format
     * string.  Most callers do, but some do not.
     *
     * Strip off all trailing whitespace, and add back a single newline
     */
    while (StringLen > 0 && CFE_ES_SysLogIsSpace(Buffer[StringLen - 1])) {
      --StringLen;
    }
    Buffer[StringLen] = '\n';
    ++StringLen;
  }
  if (BufferSize > 0) {
    /* always output a null terminated string */
    Buffer[StringLen] = 0;
  }
}
// CFE_ES_SysLogDump's buffer: one 480-byte area used as the file header first and then as the
// log read buffer. NASA declares it as an ANONYMOUS union LOCAL inside the function, which
// HolyC has no syntax for -- so the TYPE is named at file scope here and the VARIABLE stays a
// local in CFE_ES_SysLogDump, which keeps NASA's per-call stack storage rather than making it
// shared. A file-scope variable would have been the easier translation and a worse one: this
// function runs from the ES task and from the background file writer.
union CFE_ES_SysLogDumpBuffer_t
{
  CFE_ES_SysLogReadBuffer_t LogData;
  CFE_FS_Header_t FileHdr;
};
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE LOCK IS TAKEN FOR THE FIRST READ ONLY, AND NASA EXPLAINS WHY AT LENGTH. The snapshot
// taken under the lock is enough: every later read uses the local index values, so a message
// written while the dump is in progress goes to a different part of the buffer. NASA's comment
// also says what the limit is -- a FLOOD of messages could still overwrite unread data, and
// "taking a lock here will not alleviate that situation - this means that the buffer simply
// isn't big enough". That argument is kept verbatim because it is the design, not a caveat.
I32 CFE_ES_SysLogDump(U8 *Filename)
{
  U32 fd = OS_OBJECT_ID_UNDEFINED;
  I32 OsStatus;
  I32 Status;
  I64 WritePos;
  I64 TotalSize;
  I64 LastReqSize;
  CFE_ES_SysLogDumpBuffer_t Buffer;
  OsStatus = OS_OpenCreate(&fd, Filename, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
  if (OsStatus != OS_SUCCESS) {
    CFE_EVS_SendEvent(CFE_ES_SYSLOG2_ERR_EID, CFE_EVS_EventType_ERROR, "Error creating file %s, RC = %ld", Filename, OsStatus);
    return CFE_ES_FILE_IO_ERR;
  }
  CFE_FS_InitHeader(&Buffer.FileHdr, CFE_ES_SYS_LOG_DESC, CFE_FS_SubType_ES_SYSLOG);
  TotalSize = 0;
  LastReqSize = sizeof(CFE_FS_Header_t);
  Status = CFE_FS_WriteHeader(fd, &Buffer.FileHdr);
  if (Status >= 0) {
    TotalSize += Status;
    /*
     * Get a snapshot of the buffer pointers and read the first block of
     * data while locked - ensuring that nothing additional can be written
     * into the syslog buffer while getting the first block of log data.
     */
    CFE_ES_LockSharedData("CFE_ES_SysLogDump", 472);
    CFE_ES_SysLogReadStart_Unsync(&Buffer.LogData);
    CFE_ES_SysLogReadData(&Buffer.LogData);
    CFE_ES_UnlockSharedData("CFE_ES_SysLogDump", 475);
    while (Buffer.LogData.BlockSize > 0) {
      WritePos = 0;
      while (WritePos < Buffer.LogData.BlockSize) {
        LastReqSize = Buffer.LogData.BlockSize - WritePos;
        OsStatus = OS_write(fd, &Buffer.LogData.Data[WritePos], LastReqSize);
        /* NOTE: this stops for errors or EOF code (0) */
        if (OsStatus <= 0) {
          break;
        }
        WritePos += OsStatus;
        TotalSize += OsStatus;
      }
      if (OsStatus <= 0) {
        Status = OsStatus;
        break;
      }
      /*
       * _NOT_ taking the lock for subsequent reads --
       *
       * All syslog index values use the local snapshots that were taken earlier.
       * (The shared memory index values are not referenced on subsequent reads)
       *
       * If a new syslog message _does_ get written while this is in progress, it
       * should be writing to a different part of the syslog buffer anyway, and
       * probably will not overwrite the data about to be read here.
       *
       * There is still a possibility of a "flood" of syslogs coming in which would
       * potentially overwrite unread data and cause message loss/corruption.  However
       * taking a lock here will not alleviate that situation - this means that the
       * buffer simply isn't big enough.
       */
      CFE_ES_SysLogReadData(&Buffer.LogData);
    }
  }
  OS_close(fd);
  if (Status <= 0) {
    CFE_ES_FileWriteByteCntErr(Filename, LastReqSize, Status);
    Status = CFE_ES_FILE_IO_ERR;
  } else {
    CFE_EVS_SendEvent(CFE_ES_SYSLOG2_EID, CFE_EVS_EventType_DEBUG, "%s written:Size=%lu,Entries=%u", Filename, TotalSize, CFE_ES_Global.TaskData.HkPacket.Payload.SysLogEntries);
    Status = CFE_SUCCESS;
  }
  return Status;
}
#endif
