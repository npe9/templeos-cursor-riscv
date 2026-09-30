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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-printf.c.
//
// TWO CONFIGURATION FACTS decide the shape of this, and both were read out of the generated
// osconfig.h rather than guessed:
//
//   OS_PRINTF_CONSOLE_NAME is "" in this build, so sizeof() of it is 1 and the ring buffer is
//   (1 + OS_BUFFER_SIZE) * OS_BUFFER_MSG_DEPTH = (1 + 172) * 100 = 17300 bytes. It also means
//   console->device_name[0] is 0, so the name-prefix CopyOut in OS_ConsoleWrite copies nothing
//   -- the branch is translated anyway, because a different configuration would take it.
//
//   OSAL_CONFIG_CONSOLE_ASYNC is undefined, so OS_CONSOLE_IS_ASYNC is false and OS_ConsoleWrite
//   calls OS_ConsoleOutput_Impl directly instead of posting to a utility task.
//
// WHERE OS_printf's FORMATTING GOES. NASA calls vsnprintf. In the kernel the right thing is
// TempleOS's own StrPrintJoin, which takes exactly the (fmt, argc, argv) that a HolyC variadic
// receives -- see Kernel/StrPrint.HC. It is not size-bounded and it allocates, so the bounded
// StrPrintN in Kernel/Cfs/CfsStr.HC is what a fixed OS_BUFFER_SIZE buffer needs; see the note
// there on why its conversions are C's while its name is TempleOS's.
#ifndef OSAPI_PRINTF_HC
#define OSAPI_PRINTF_HC
#include "os_shared_console.HC"
#include "../CfsStr.HC"

#define OS_CONSOLE_IS_ASYNC FALSE

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_ConsoleCreate_Impl(OS_object_token_t *token);
U0 OS_ConsoleOutput_Impl(OS_object_token_t *token);
U0 OS_ConsoleWakeup_Impl(OS_object_token_t *token);

// Reserve buffer memory for the printf console device. NASA sizes this with sizeof() of the
// name string literal; the arithmetic is spelled out above.
U8 OS_printf_buffer_mem[(1 + OS_BUFFER_SIZE) * OS_BUFFER_MSG_DEPTH];

// The global console state table.
OS_console_internal_record_t OS_console_table[OS_MAX_CONSOLES];

I32 OS_ConsoleAPI_Init()
{
  OS_console_internal_record_t *console;
  I32 return_code;
  OS_object_token_t token;
  OS_common_record_t *grec;
  MemSet(OS_console_table, 0, sizeof(OS_console_table));
  // Configure a console device to be used for OS_printf() calls.
  return_code = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_CONSOLE, OS_PRINTF_CONSOLE_NAME, &token);
  if (return_code == OS_SUCCESS) {
    console = &OS_console_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, console, device_name, OS_PRINTF_CONSOLE_NAME)
    MemSet(console, 0, sizeof(OS_console_internal_record_t));
    StrNCpy(console->device_name, OS_PRINTF_CONSOLE_NAME, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = console->device_name;
    // Initialize the ring buffer pointers.
    console->BufBase = OS_printf_buffer_mem;
    console->BufSize = sizeof(OS_printf_buffer_mem);
    console->IsAsync = OS_CONSOLE_IS_ASYNC;
    return_code = OS_ConsoleCreate_Impl(&token);
    // Check result, finalize record, and unlock global table.
    return_code = OS_ObjectIdFinalizeNew(return_code, &token,
                                         &OS_SharedGlobalVars.PrintfConsoleId);
    // Printf can be enabled by default now that the buffer is configured.
    OS_SharedGlobalVars.PrintfEnabled = TRUE;
  }
  return return_code;
}

// Local helper, not part of the OSAL API. Write into the console ring buffer.
//
// NextWritePos is an input-output: it is the position to start writing at, which may or may not
// be the global's value, and it is updated ONLY if the whole string was written. The intent is
// that a message either goes in entirely or not at all, never truncated.
I32 OS_Console_CopyOut(OS_console_internal_record_t *console, U8 *Str, I64 *NextWritePos)
{
  U8 *pmsg;
  I64 WriteOffset;
  I32 return_code;
  return_code = OS_ERROR;
  pmsg = Str;
  WriteOffset = *NextWritePos;
  while (TRUE) {
    if (*pmsg == 0) {
      // String is complete.
      *NextWritePos = WriteOffset;
      return_code = OS_SUCCESS;
      break;
    }
    console->BufBase[WriteOffset] = *pmsg;
    WriteOffset = WriteOffset + 1;
    if (WriteOffset >= console->BufSize)
      WriteOffset = 0;
    if (WriteOffset == console->ReadPos) {
      // out of space
      return_code = OS_QUEUE_FULL;
      break;
    }
    ++pmsg;
  }
  return return_code;
}

I32 OS_ConsoleWrite(U32 console_id, U8 *Str)
{
  I32 return_code;
  OS_object_token_t token;
  OS_console_internal_record_t *console;
  I64 PendingWritePos;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_CONSOLE, console_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    console = &OS_console_table[OS_ObjectIndexFromToken(&token)];
    // The entire string should be put to the ring buffer, or none of it. Therefore the WritePos
    // in the table is not updated until complete success.
    PendingWritePos = console->WritePos;
    if (console->device_name[0] != 0)
      return_code = OS_Console_CopyOut(console, console->device_name, &PendingWritePos);
    if (return_code == OS_SUCCESS)
      return_code = OS_Console_CopyOut(console, Str, &PendingWritePos);
    // ALL-OR-NOTHING, and NASA enforces it TWICE. OS_Console_CopyOut breaks WITHOUT updating
    // *NextWritePos when it runs out of space, and this guard commits WritePos only on success.
    // Either one alone is sufficient, so no single mutation to either can be observed: a
    // control that broke just this guard left the transcript identical, because PendingWritePos
    // still held the value it was initialised to. Breaking BOTH does change it
    // (allornone wr_moved=1, and the ring drains 97 bytes instead of 17,279), so the transcript
    // does cover the property -- it is the redundancy, not the gate, that hides a single fault.
    if (return_code == OS_SUCCESS) {
      // the entire message was successfully written
      console->WritePos = PendingWritePos;
    } else {
      // the message did not fit
      ++console->OverflowEvents;
    }
    // Notify the underlying console implementation of new data, which forwards it to the actual
    // device. Done while still LOCKED, so it supports a synchronous or asynchronous backend.
    if (console->IsAsync)
      OS_ConsoleWakeup_Impl(&token); // post the sem for the utility task to run
    else
      OS_ConsoleOutput_Impl(&token); // output directly
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

U0 OS_printf(U8 *String, ...)
{
  U8 msg_buffer[OS_BUFFER_SIZE];
  I64 actualsz;
  // BUGCHECK_VOID(String != NULL) -- see osapi_errors.HC on why the wording is not translated.
  if (String == NULL)
    return;
  if (OS_SharedGlobalVars.GlobalState != OS_INIT_MAGIC_NUMBER) {
    // Catch some historical mis-use of the OS_printf() call: it should NOT be called before
    // OS_API_Init(). NASA dumps the message through OS_DEBUG here, which is a NO-OP unless
    // OSAL_CONFIG_DEBUG_PRINTF is enabled, and it is not in this build -- so the message is
    // silently discarded, and this branch is that discard.
    return;
  } else if (OS_SharedGlobalVars.PrintfEnabled) {
    // Format and determine the size of string to write.
    actualsz = StrPrintNV(msg_buffer, sizeof(msg_buffer), String, argc, argv);
    if (actualsz < 0) {
      // unlikely: the formatter failed
      actualsz = 0;
    } else if (actualsz >= OS_BUFFER_SIZE) {
      // truncate
      actualsz = OS_BUFFER_SIZE - 1;
    }
    msg_buffer[actualsz] = 0;
    OS_ConsoleWrite(OS_SharedGlobalVars.PrintfConsoleId, msg_buffer);
  }
}

U0 OS_printf_disable()
{
  OS_SharedGlobalVars.PrintfEnabled = FALSE;
}

U0 OS_printf_enable()
{
  OS_SharedGlobalVars.PrintfEnabled = TRUE;
}
#endif
