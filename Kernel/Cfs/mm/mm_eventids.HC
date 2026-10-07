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
// MEMORY MANAGER'S EVENT IDS -- the translation of NASA's fsw/inc/mm_eventids.h, whole, in
// NASA's order.
//
// A SEPARATE FILE, unlike MD's, and the reason is worth one line: MD's ids landed in
// md_app.HC because md_utils.c sends no events at all, so the first MD source that needed
// them was md_app.c. mm_utils.c sends six, and it is the FIRST MM source gated -- so the ids
// go where NASA puts them, in their own header, and every later MM source finds them there.
//
// THE GAPS ARE NASA'S: 39, 50, 58 and 59 are not defined. They were retired, and the numbers
// were not reused -- an event id is a ground-system interface, so renumbering the ids above a
// deleted one would silently change what every existing ground display means. Kept 1:1,
// including the holes, because an id this port invented would be a different interface.
#ifndef MM_EVENTIDS_HC
#define MM_EVENTIDS_HC

#define MM_INIT_INF_EID                   1
#define MM_NOOP_INF_EID                   2
#define MM_RESET_INF_EID                  3
#define MM_LOAD_WID_INF_EID               4
#define MM_LD_MEM_FILE_INF_EID            5
#define MM_FILL_INF_EID                   6
#define MM_PEEK_BYTE_INF_EID              7
#define MM_PEEK_WORD_INF_EID              8
#define MM_PEEK_DWORD_INF_EID             9
#define MM_POKE_BYTE_INF_EID              10
#define MM_POKE_WORD_INF_EID              11
#define MM_POKE_DWORD_INF_EID             12
#define MM_DMP_MEM_FILE_INF_EID           13
#define MM_DUMP_INEVENT_INF_EID           14
#define MM_PIPE_ERR_EID                   15
#define MM_MID_ERR_EID                    16
#define MM_CC_ERR_EID                     17
#define MM_CMD_LEN_ERR_EID                18
#define MM_MEMTYPE_ERR_EID                19
#define MM_SYMNAME_ERR_EID                20
#define MM_DATA_SIZE_BYTES_ERR_EID        21
#define MM_DATA_SIZE_BITS_ERR_EID         22
#define MM_ALIGN32_ERR_EID                23
#define MM_ALIGN16_ERR_EID                24
#define MM_OS_MEMVALIDATE_ERR_EID         25
#define MM_LOAD_FILE_CRC_ERR_EID          26
#define MM_LOAD_WID_CRC_ERR_EID           27
#define MM_OS_EEPROMWRITE8_ERR_EID        28
#define MM_OS_EEPROMWRITE16_ERR_EID       29
#define MM_OS_EEPROMWRITE32_ERR_EID       30
#define MM_OS_CREAT_ERR_EID               31
#define MM_OS_OPEN_ERR_EID                32
#define MM_OS_CLOSE_ERR_EID               33
#define MM_OS_READ_ERR_EID                34
#define MM_OS_READ_EXP_ERR_EID            35
#define MM_OS_WRITE_EXP_ERR_EID           36
#define MM_OS_STAT_ERR_EID                37
#define MM_COMPUTECRCFROMFILE_ERR_EID     38
#define MM_LD_FILE_SIZE_ERR_EID           40
#define MM_FILE_LOAD_PARAMS_ERR_EID       41
#define MM_CFE_FS_READHDR_ERR_EID         42
#define MM_CFE_FS_WRITEHDR_ERR_EID        43
#define MM_HKREQ_LEN_ERR_EID              44
#define MM_SYM_LOOKUP_INF_EID             45
#define MM_SYMNAME_NUL_ERR_EID            46
#define MM_SYMTBL_TO_FILE_INF_EID         47
#define MM_SYMFILENAME_NUL_ERR_EID        48
#define MM_SYMTBL_TO_FILE_FAIL_ERR_EID    49
#define MM_EEPROM_WRITE_ENA_INF_EID       51
#define MM_EEPROM_WRITE_ENA_ERR_EID       52
#define MM_EEPROM_WRITE_DIS_INF_EID       53
#define MM_EEPROM_WRITE_DIS_ERR_EID       54
#define MM_OS_ZERO_READ_ERR_EID           55
#define MM_PSP_READ_ERR_EID               56
#define MM_PSP_WRITE_ERR_EID              57
#define MM_CR_PIPE_ERR_EID                60
#define MM_HK_SUB_ERR_EID                 61
#define MM_CMD_SUB_ERR_EID                62
#define MM_FILL_MEM32_ALIGN_WARN_INF_EID  63
#define MM_FILL_MEM16_ALIGN_WARN_INF_EID  64
#endif
