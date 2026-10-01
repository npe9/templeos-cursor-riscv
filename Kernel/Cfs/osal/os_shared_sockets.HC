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

// 1:1 HolyC translation of the socket types, from OSAL src/os/inc/osapi-sockets.h. The socket
// records themselves live in OS_stream_table, shared with osapi-file.c -- see os_shared_file.HC.
#ifndef OS_SHARED_SOCKETS_HC
#define OS_SHARED_SOCKETS_HC
#include "osconfig.HC"
#include "os_shared_file.HC"

#define OS_SOCKADDR_MAX_LEN 28

// OS_SocketDomain_t. OS_SocketDomain_INVALID is defined in os_shared_file.HC, because
// osapi-file.c needs it to tell a plain file from a socket in the table they share.
#define OS_SocketDomain_INET  1
#define OS_SocketDomain_INET6 2
#define OS_SocketDomain_MAX   3

// OS_SocketType_t
#define OS_SocketType_INVALID  0
#define OS_SocketType_DATAGRAM 1
#define OS_SocketType_STREAM   2
#define OS_SocketType_MAX      3

// OS_SocketShutdownMode_t. NASA's own note: these are ALSO A BITMASK, so the specific values
// matter -- OS_SocketShutdown tests `Mode & SHUT_READ` and `Mode & SHUT_WRITE`, and
// SHUT_READWRITE is 3 precisely so that it sets both.
#define OS_SocketShutdownMode_NONE           0
#define OS_SocketShutdownMode_SHUT_READ      1
#define OS_SocketShutdownMode_SHUT_WRITE     2
#define OS_SocketShutdownMode_SHUT_READWRITE 3

// OS_socket_option_t
#define OS_socket_option_UNDEFINED 0
#define OS_socket_option_IP_DSCP   1
#define OS_socket_option_MAX       2

// A union in the C, sized and aligned for the worst case. The AlignU32 and AlignPtr members
// exist only to force alignment; nothing reads them.
union OS_SockAddrData_t
{
  U8 Buffer[OS_SOCKADDR_MAX_LEN];
  U32 AlignU32;
  U8 *AlignPtr;
  // The point of this union is stated in NASA's comment: it exists to give the storage a
  // minimum ALIGNMENT, so that a system address can be cast into it. A C compiler therefore
  // rounds its 28-byte Buffer up to the pointer alignment and the union is 32 bytes. HolyC
  // takes the widest member and stops, so the size has to be stated.
  U8 _pad0[32]; // C rounds the struct up to its alignment; HolyC does not
};

class OS_SockAddr_t
{
  I64 ActualLength; // size_t
  OS_SockAddrData_t AddrData;
};

class OS_socket_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;
};

// A union in the C too: only an integer matters today, but the shape allows other types later.
union OS_socket_optval_t
{
  I32 IntVal;
};
#endif
