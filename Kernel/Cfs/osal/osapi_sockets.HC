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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-sockets.c.
//
// Sockets share OS_stream_table with osapi-file.c, and the whole module is a STATE MACHINE over
// stream_state: BOUND, LISTENING, CONNECTED, READABLE, WRITABLE. Almost every function's real
// content is which combination of those bits it demands and which it sets, so that is what the
// transcript has to pin -- an error code alone does not distinguish "not a socket" from "wrong
// state", and NASA returns different codes for those two on purpose.
#ifndef OSAPI_SOCKETS_HC
#define OSAPI_SOCKETS_HC
#include "os_shared_sockets.HC"
#include "../CfsStr.HC"

#define LOCAL_OBJID_TYPE_SOCKET OS_OBJECT_TYPE_OS_STREAM

// The backend seam -- sixteen functions, the largest of any module. Declared before use because
// HolyC is single-pass.
I32 OS_SocketOpen_Impl(OS_object_token_t *token);
I32 OS_SocketBindAddress_Impl(OS_object_token_t *token, OS_SockAddr_t *Addr);
I32 OS_SocketListen_Impl(OS_object_token_t *token);
I32 OS_SocketAccept_Impl(OS_object_token_t *sock_token, OS_object_token_t *conn_token,
                         OS_SockAddr_t *Addr, OS_time_t abs_timeout);
I32 OS_SocketConnect_Impl(OS_object_token_t *token, OS_SockAddr_t *Addr, OS_time_t abs_timeout);
I32 OS_SocketShutdown_Impl(OS_object_token_t *token, I64 Mode);
I32 OS_SocketRecvFrom_Impl(OS_object_token_t *token, U8 *buffer, I64 buflen,
                           OS_SockAddr_t *RemoteAddr, OS_time_t abs_timeout);
I32 OS_SocketSendTo_Impl(OS_object_token_t *token, U8 *buffer, I64 buflen,
                         OS_SockAddr_t *RemoteAddr);
I32 OS_SocketGetInfo_Impl(OS_object_token_t *token, OS_socket_prop_t *sock_prop);
I32 OS_SocketAddrInit_Impl(OS_SockAddr_t *Addr, I64 Domain);
I32 OS_SocketAddrToString_Impl(U8 *buffer, I64 buflen, OS_SockAddr_t *Addr);
I32 OS_SocketAddrFromString_Impl(OS_SockAddr_t *Addr, U8 *string);
I32 OS_SocketAddrGetPort_Impl(U16 *PortNum, OS_SockAddr_t *Addr);
I32 OS_SocketAddrSetPort_Impl(OS_SockAddr_t *Addr, U16 PortNum);
I32 OS_SocketGetOption_Impl(OS_object_token_t *token, I64 opt_id, OS_socket_optval_t *optval);
I32 OS_SocketSetOption_Impl(OS_object_token_t *token, I64 opt_id, OS_socket_optval_t *optval);

I32 OS_SocketAPI_Init()
{
  // NASA: a placeholder, which also keeps this a non-empty compilation unit when
  // OS_INCLUDE_NETWORK is off.
  return OS_SUCCESS;
}

// Local helper, not part of the OSAL API. Builds the stream's name from the address, the port
// and, for an accepted connection, the listening socket's name.
U0 OS_CreateSocketName(OS_object_token_t *token, OS_SockAddr_t *Addr, U8 *parent_name)
{
  I64 len;
  U16 port;
  OS_stream_internal_record_t *sock;
  sock = &OS_stream_table[OS_ObjectIndexFromToken(token)];
  if (OS_SocketAddrToString_Impl(sock->stream_name, OS_MAX_PATH_LEN, Addr) != OS_SUCCESS)
    sock->stream_name[0] = 0;
  if (OS_SocketAddrGetPort_Impl(&port, Addr) == OS_SUCCESS) {
    len = OS_strnlen(sock->stream_name, OS_MAX_PATH_LEN);
    StrPrintN(&sock->stream_name[len], OS_MAX_PATH_LEN - len, ":%u", port);
  }
  if (parent_name) {
    // Append the name from the parent socket.
    len = OS_strnlen(sock->stream_name, OS_MAX_PATH_LEN);
    StrPrintN(&sock->stream_name[len], OS_MAX_PATH_LEN - len, "-%s", parent_name);
  }
}

I32 OS_SocketOpen(U32 *sock_id, I64 Domain, I64 Type)
{
  OS_object_token_t token;
  OS_stream_internal_record_t *stream;
  I32 return_code;
  if (sock_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_SOCKET, NULL, &token);
  if (return_code == OS_SUCCESS) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    MemSet(stream, 0, sizeof(OS_stream_internal_record_t));
    stream->socket_domain = Domain;
    stream->socket_type = Type;
    return_code = OS_SocketOpen_Impl(&token);
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, sock_id);
  }
  return return_code;
}

// A convenience wrapper over bind+listen, kept for backward compatibility.
I32 OS_SocketBind(U32 sock_id, OS_SockAddr_t *Addr)
{
  I32 return_code;
  return_code = OS_SocketBindAddress(sock_id, Addr);
  if (return_code == OS_SUCCESS) {
    return_code = OS_SocketListen(sock_id);
    // A datagram socket has nothing to listen on, and that is not an error here: the
    // INCORRECT_OBJ_TYPE from OS_SocketListen is swallowed so an old caller still sees success.
    if (return_code == OS_ERR_INCORRECT_OBJ_TYPE)
      return_code = OS_SUCCESS;
  }
  return return_code;
}

I32 OS_SocketListen(U32 sock_id)
{
  OS_stream_internal_record_t *stream;
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    // Three DIFFERENT rejections, and the codes differ on purpose: not a stream socket at all,
    // versus a stream socket in the wrong state.
    if (stream->socket_domain == OS_SocketDomain_INVALID ||
        stream->socket_type != OS_SocketType_STREAM) {
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    } else if ((stream->stream_state & OS_STREAM_STATE_BOUND) == 0) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else if ((stream->stream_state &
                (OS_STREAM_STATE_LISTENING | OS_STREAM_STATE_CONNECTED)) != 0) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      return_code = OS_SocketListen_Impl(&token);
      if (return_code == OS_SUCCESS)
        stream->stream_state |= OS_STREAM_STATE_LISTENING;
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketBindAddress(U32 sock_id, OS_SockAddr_t *Addr)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_stream_internal_record_t *stream;
  OS_object_token_t token;
  I32 return_code;
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    base = &OS_common_table[OS_STREAM_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    if (stream->socket_domain == OS_SocketDomain_INVALID) {
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    } else if ((stream->stream_state &
                (OS_STREAM_STATE_BOUND | OS_STREAM_STATE_CONNECTED)) != 0) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      return_code = OS_SocketBindAddress_Impl(&token, Addr);
      if (return_code == OS_SUCCESS) {
        // The socket only GETS A NAME once it is bound -- before that the record's name_entry
        // is NULL, which is why OS_SocketGetInfo on an unbound socket has nothing to copy.
        OS_CreateSocketName(&token, Addr, NULL);
        record->name_entry = stream->stream_name;
        stream->stream_state |= OS_STREAM_STATE_BOUND;
      }
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketAcceptAbs(U32 sock_id, U32 *connsock_id, OS_SockAddr_t *Addr, OS_time_t abs_timeout)
{
  OS_common_record_t *sock_record;
  OS_common_record_t *conn_record;
  OS_common_record_t *base;
  OS_stream_internal_record_t *sock;
  OS_stream_internal_record_t *conn;
  OS_object_token_t sock_token;
  OS_object_token_t conn_token;
  I32 return_code;
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (connsock_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // NASA zeroes these to silence a static-analysis warning about possible uninitialised use;
  // it cannot actually happen, because return_code gates every read.
  conn_record = NULL;
  sock_record = NULL;
  sock = NULL;
  conn = NULL;
  MemSet(&sock_token, 0, sizeof(OS_object_token_t));
  MemSet(&conn_token, 0, sizeof(OS_object_token_t));
  base = &OS_common_table[OS_STREAM_BASE];
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                   &sock_token);
  if (return_code == OS_SUCCESS) {
    sock_record = &base[OS_ObjectIndexFromToken(&sock_token)];
    sock = &OS_stream_table[OS_ObjectIndexFromToken(&sock_token)];
    if (sock->socket_type != OS_SocketType_STREAM) {
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    } else if ((sock->stream_state & (OS_STREAM_STATE_BOUND | OS_STREAM_STATE_CONNECTED)) !=
               OS_STREAM_STATE_BOUND) {
      // Bound but NOT connected -- an exact match, not a bit test, so a connected socket is
      // refused as well as an unbound one.
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      // A second object id for the accepted connection.
      return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_SOCKET, NULL, &conn_token);
      if (return_code == OS_SUCCESS) {
        conn_record = &base[OS_ObjectIndexFromToken(&conn_token)];
        conn = &OS_stream_table[OS_ObjectIndexFromToken(&conn_token)];
        MemSet(conn, 0, sizeof(OS_stream_internal_record_t));
        conn->socket_domain = sock->socket_domain;
        conn->socket_type = sock->socket_type;
        OS_SocketAddrInit_Impl(Addr, sock->socket_domain);
        return_code = OS_SocketAccept_Impl(&sock_token, &conn_token, Addr, abs_timeout);
        if (return_code == OS_SUCCESS) {
          // The connection's name is built from the REMOTE address plus the listening
          // socket's name, which is what makes an accepted socket identifiable.
          OS_CreateSocketName(&conn_token, Addr, sock_record->name_entry);
          conn_record->name_entry = conn->stream_name;
          conn->stream_state |= OS_STREAM_STATE_CONNECTED;
        }
        return_code = OS_ObjectIdFinalizeNew(return_code, &conn_token, connsock_id);
      }
    }
    OS_ObjectIdRelease(&sock_token);
  }
  return return_code;
}

I32 OS_SocketAccept(U32 sock_id, U32 *connsock_id, OS_SockAddr_t *Addr, I32 timeout)
{
  return OS_SocketAcceptAbs(sock_id, connsock_id, Addr, OS_TimeFromRelativeMilliseconds(timeout));
}

I32 OS_SocketConnectAbs(U32 sock_id, OS_SockAddr_t *Addr, OS_time_t abs_timeout)
{
  OS_stream_internal_record_t *stream;
  OS_object_token_t token;
  I32 return_code;
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    if (stream->socket_domain == OS_SocketDomain_INVALID) {
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    } else if (stream->socket_type == OS_SocketType_STREAM &&
               (stream->stream_state & OS_STREAM_STATE_CONNECTED) != 0) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      return_code = OS_SocketConnect_Impl(&token, Addr, abs_timeout);
      // A successful connect sets THREE bits, not one: the socket becomes connected and both
      // readable and writable.
      if (return_code == OS_SUCCESS)
        stream->stream_state |= OS_STREAM_STATE_CONNECTED | OS_STREAM_STATE_READABLE |
                                OS_STREAM_STATE_WRITABLE;
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketShutdown(U32 sock_id, I64 Mode)
{
  OS_stream_internal_record_t *stream;
  OS_object_token_t token;
  I32 return_code;
  // Confirm Mode is one of the three acceptable values. A BUGCHECK, so it logs.
  if (!(Mode == OS_SocketShutdownMode_SHUT_READ || Mode == OS_SocketShutdownMode_SHUT_WRITE ||
        Mode == OS_SocketShutdownMode_SHUT_READWRITE)) {
    OS_printf("bugcheck\n");
    return OS_ERR_INVALID_ARGUMENT;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_SOCKET, sock_id, &token);
  if (return_code == OS_SUCCESS) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    if (stream->socket_domain == OS_SocketDomain_INVALID) {
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    } else if (stream->socket_type == OS_SocketType_STREAM &&
               (stream->stream_state & OS_STREAM_STATE_CONNECTED) == 0) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      return_code = OS_SocketShutdown_Impl(&token, Mode);
      // Mode is a BITMASK, which is why SHUT_READWRITE is 3: it clears both bits in one call.
      if (return_code == OS_SUCCESS) {
        if (Mode & OS_SocketShutdownMode_SHUT_READ)
          stream->stream_state &= ~OS_STREAM_STATE_READABLE;
        if (Mode & OS_SocketShutdownMode_SHUT_WRITE)
          stream->stream_state &= ~OS_STREAM_STATE_WRITABLE;
      }
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketConnect(U32 sock_id, OS_SockAddr_t *Addr, I32 timeout)
{
  return OS_SocketConnectAbs(sock_id, Addr, OS_TimeFromRelativeMilliseconds(timeout));
}

I32 OS_SocketRecvFromAbs(U32 sock_id, U8 *buffer, I64 buflen, OS_SockAddr_t *RemoteAddr,
                         OS_time_t abs_timeout)
{
  OS_stream_internal_record_t *stream;
  OS_object_token_t token;
  I32 return_code;
  // RemoteAddr is deliberately NOT checked: in certain configurations it can validly be null.
  if (buffer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(buflen > 0 && buflen < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    if (stream->socket_type != OS_SocketType_DATAGRAM) {
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    } else if ((stream->stream_state & OS_STREAM_STATE_BOUND) == 0) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      return_code = OS_SocketRecvFrom_Impl(&token, buffer, buflen, RemoteAddr, abs_timeout);
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketRecvFrom(U32 sock_id, U8 *buffer, I64 buflen, OS_SockAddr_t *RemoteAddr, I32 timeout)
{
  return OS_SocketRecvFromAbs(sock_id, buffer, buflen, RemoteAddr,
                              OS_TimeFromRelativeMilliseconds(timeout));
}

I32 OS_SocketSendTo(U32 sock_id, U8 *buffer, I64 buflen, OS_SockAddr_t *RemoteAddr)
{
  OS_stream_internal_record_t *stream;
  OS_object_token_t token;
  I32 return_code;
  if (buffer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(buflen > 0 && buflen < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  // Unlike RecvFrom, SendTo DOES require the address.
  if (RemoteAddr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
    // NOTE: no BOUND check here, unlike RecvFrom -- sending does not require a local address.
    if (stream->socket_type != OS_SocketType_DATAGRAM)
      return_code = OS_ERR_INCORRECT_OBJ_TYPE;
    else
      return_code = OS_SocketSendTo_Impl(&token, buffer, buflen, RemoteAddr);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketGetIdByName(U32 *sock_id, U8 *sock_name)
{
  I32 return_code;
  if (sock_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (sock_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdFindByName(LOCAL_OBJID_TYPE_SOCKET, sock_name, sock_id);
  return return_code;
}

I32 OS_SocketGetInfo(U32 sock_id, OS_socket_prop_t *sock_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  I32 return_code;
  if (sock_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(sock_prop, 0, sizeof(OS_socket_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_SOCKET, sock_id, &token);
  if (return_code == OS_SUCCESS) {
    base = &OS_common_table[OS_STREAM_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    // NOTE no NULL guard on name_entry, unlike OS_TaskGetInfo -- an UNBOUND socket has none.
    StrNCpy(sock_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
    sock_prop->creator = record->creator;
    return_code = OS_SocketGetInfo_Impl(&token, sock_prop);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SocketAddrInit(OS_SockAddr_t *Addr, I64 Domain)
{
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_SocketAddrInit_Impl(Addr, Domain);
}

I32 OS_SocketAddrToString(U8 *buffer, I64 buflen, OS_SockAddr_t *Addr)
{
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (buffer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(buflen > 0 && buflen < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  return OS_SocketAddrToString_Impl(buffer, buflen, Addr);
}

I32 OS_SocketAddrFromString(OS_SockAddr_t *Addr, U8 *string)
{
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (string == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_SocketAddrFromString_Impl(Addr, string);
}

I32 OS_SocketAddrGetPort(U16 *PortNum, OS_SockAddr_t *Addr)
{
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (PortNum == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_SocketAddrGetPort_Impl(PortNum, Addr);
}

I32 OS_SocketAddrSetPort(OS_SockAddr_t *Addr, U16 PortNum)
{
  if (Addr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_SocketAddrSetPort_Impl(Addr, PortNum);
}

I32 OS_SocketGetOption(U32 sock_id, I64 opt_id, OS_socket_optval_t *optval)
{
  I32 return_code;
  OS_object_token_t token;
  if (optval == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (opt_id < OS_socket_option_UNDEFINED || opt_id >= OS_socket_option_MAX) {
    return_code = OS_ERR_INVALID_ARGUMENT;
  } else {
    // Cleared only on the VALID-option path: a bad option id leaves the caller's value alone.
    MemSet(optval, 0, sizeof(OS_socket_optval_t));
    return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                     &token);
    if (return_code == OS_SUCCESS) {
      return_code = OS_SocketGetOption_Impl(&token, opt_id, optval);
      OS_ObjectIdRelease(&token);
    }
  }
  return return_code;
}

I32 OS_SocketSetOption(U32 sock_id, I64 opt_id, OS_socket_optval_t *optval)
{
  I32 return_code;
  OS_object_token_t token;
  if (optval == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (opt_id < OS_socket_option_UNDEFINED || opt_id >= OS_socket_option_MAX) {
    return_code = OS_ERR_INVALID_ARGUMENT;
  } else {
    return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_SOCKET, sock_id,
                                     &token);
    if (return_code == OS_SUCCESS) {
      return_code = OS_SocketSetOption_Impl(&token, opt_id, optval);
      OS_ObjectIdRelease(&token);
    }
  }
  return return_code;
}
#endif
