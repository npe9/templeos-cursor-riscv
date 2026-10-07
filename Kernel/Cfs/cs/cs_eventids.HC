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
// CHECKSUM'S EVENT IDS -- the translation of NASA's fsw/inc/cs_eventids.h, whole, in NASA's
// order. 155 of them, against MM's 54 and MD's 23, and the count is the first honest measure of
// what CS is: six checksum types times enable, disable, report, recompute and miscompare, each
// with its own id so a ground display can tell which of the six went wrong without parsing a
// string.
//
// THE GAP IS NASA'S: 151 is not defined. 150 is CS_CFE_TEXT_SEG_INF_EID and 152 is
// CS_CMD_COMPUTE_PROG_ERR_EID. An event id is a ground-system interface, so a retired id is
// left as a hole rather than reused -- the same reason mm_eventids.HC keeps four.
#ifndef CS_EVENTIDS_HC
#define CS_EVENTIDS_HC

#define CS_INIT_INF_EID                             1
#define CS_NOOP_INF_EID                             2
#define CS_RESET_INF_EID                            3
#define CS_DISABLE_ALL_INF_EID                      4
#define CS_ENABLE_ALL_INF_EID                       5
#define CS_DISABLE_CFECORE_INF_EID                  6
#define CS_ENABLE_CFECORE_INF_EID                   7
#define CS_DISABLE_OS_INF_EID                       8
#define CS_ENABLE_OS_INF_EID                        9
#define CS_BASELINE_CFECORE_INF_EID                 10
#define CS_NO_BASELINE_CFECORE_INF_EID              11
#define CS_BASELINE_OS_INF_EID                      12
#define CS_NO_BASELINE_OS_INF_EID                   13
#define CS_RECOMPUTE_CFECORE_STARTED_DBG_EID        14
#define CS_RECOMPUTE_CFECORE_CREATE_CHDTASK_ERR_EID 15
#define CS_RECOMPUTE_CFECORE_CHDTASK_ERR_EID        16
#define CS_RECOMPUTE_OS_STARTED_DBG_EID             17
#define CS_RECOMPUTE_OS_CREATE_CHDTASK_ERR_EID      18
#define CS_RECOMPUTE_OS_CHDTASK_ERR_EID             19
#define CS_ONESHOT_STARTED_DBG_EID                  20
#define CS_ONESHOT_CREATE_CHDTASK_ERR_EID           21
#define CS_ONESHOT_CHDTASK_ERR_EID                  22
#define CS_ONESHOT_MEMVALIDATE_ERR_EID              23
#define CS_ONESHOT_CANCELLED_INF_EID                24
#define CS_ONESHOT_CANCEL_DELETE_CHDTASK_ERR_EID    25
#define CS_ONESHOT_CANCEL_NO_CHDTASK_ERR_EID        26
#define CS_EEPROM_MISCOMPARE_ERR_EID                27
#define CS_MEMORY_MISCOMPARE_ERR_EID                28
#define CS_TABLES_MISCOMPARE_ERR_EID                29
#define CS_APP_MISCOMPARE_ERR_EID                   30
#define CS_CFECORE_MISCOMPARE_ERR_EID               31
#define CS_OS_MISCOMPARE_ERR_EID                    32
#define CS_MID_ERR_EID                              33
#define CS_CC_ERR_EID                               34
#define CS_EXIT_ERR_EID                             35
#define CS_CMD_LEN_ERR_EID                          36
#define CS_DISABLE_EEPROM_INF_EID                   37
#define CS_ENABLE_EEPROM_INF_EID                    38
#define CS_BASELINE_EEPROM_INF_EID                  39
#define CS_NO_BASELINE_EEPROM_INF_EID               40
#define CS_BASELINE_INVALID_ENTRY_EEPROM_ERR_EID    41
#define CS_RECOMPUTE_EEPROM_STARTED_DBG_EID         42
#define CS_RECOMPUTE_EEPROM_CREATE_CHDTASK_ERR_EID  43
#define CS_RECOMPUTE_INVALID_ENTRY_EEPROM_ERR_EID   44
#define CS_RECOMPUTE_EEPROM_CHDTASK_ERR_EID         45
#define CS_ENABLE_EEPROM_ENTRY_INF_EID              46
#define CS_ENABLE_EEPROM_INVALID_ENTRY_ERR_EID      47
#define CS_DISABLE_EEPROM_ENTRY_INF_EID             48
#define CS_DISABLE_EEPROM_INVALID_ENTRY_ERR_EID     49
#define CS_GET_ENTRY_ID_EEPROM_INF_EID              50
#define CS_GET_ENTRY_ID_EEPROM_NOT_FOUND_INF_EID    51
#define CS_DISABLE_MEMORY_INF_EID                   52
#define CS_ENABLE_MEMORY_INF_EID                    53
#define CS_BASELINE_MEMORY_INF_EID                  54
#define CS_NO_BASELINE_MEMORY_INF_EID               55
#define CS_BASELINE_INVALID_ENTRY_MEMORY_ERR_EID    56
#define CS_RECOMPUTE_MEMORY_STARTED_DBG_EID         57
#define CS_RECOMPUTE_MEMORY_CREATE_CHDTASK_ERR_EID  58
#define CS_RECOMPUTE_INVALID_ENTRY_MEMORY_ERR_EID   59
#define CS_RECOMPUTE_MEMORY_CHDTASK_ERR_EID         60
#define CS_ENABLE_MEMORY_ENTRY_INF_EID              61
#define CS_ENABLE_MEMORY_INVALID_ENTRY_ERR_EID      62
#define CS_DISABLE_MEMORY_ENTRY_INF_EID             63
#define CS_DISABLE_MEMORY_INVALID_ENTRY_ERR_EID     64
#define CS_GET_ENTRY_ID_MEMORY_INF_EID              65
#define CS_GET_ENTRY_ID_MEMORY_NOT_FOUND_INF_EID    66
#define CS_DISABLE_TABLES_INF_EID                   67
#define CS_ENABLE_TABLES_INF_EID                    68
#define CS_BASELINE_TABLE_INF_EID                   69
#define CS_NO_BASELINE_TABLE_INF_EID                70
#define CS_BASELINE_INVALID_NAME_TABLES_ERR_EID     71
#define CS_RECOMPUTE_TABLES_STARTED_DBG_EID         72
#define CS_RECOMPUTE_TABLES_CREATE_CHDTASK_ERR_EID  73
#define CS_RECOMPUTE_UNKNOWN_NAME_TABLES_ERR_EID    74
#define CS_RECOMPUTE_TABLES_CHDTASK_ERR_EID         75
#define CS_ENABLE_TABLES_NAME_INF_EID               76
#define CS_ENABLE_TABLES_UNKNOWN_NAME_ERR_EID       77
#define CS_DISABLE_TABLES_NAME_INF_EID              78
#define CS_DISABLE_TABLES_UNKNOWN_NAME_ERR_EID      79
#define CS_DISABLE_APP_INF_EID                      80
#define CS_ENABLE_APP_INF_EID                       81
#define CS_BASELINE_APP_INF_EID                     82
#define CS_NO_BASELINE_APP_INF_EID                  83
#define CS_BASELINE_INVALID_NAME_APP_ERR_EID        84
#define CS_RECOMPUTE_APP_STARTED_DBG_EID            85
#define CS_RECOMPUTE_APP_CREATE_CHDTASK_ERR_EID     86
#define CS_RECOMPUTE_UNKNOWN_NAME_APP_ERR_EID       87
#define CS_RECOMPUTE_APP_CHDTASK_ERR_EID            88
#define CS_ENABLE_APP_NAME_INF_EID                  89
#define CS_ENABLE_APP_UNKNOWN_NAME_ERR_EID          90
#define CS_DISABLE_APP_NAME_INF_EID                 91
#define CS_DISABLE_APP_UNKNOWN_NAME_ERR_EID         92
#define CS_COMPUTE_APP_NOT_FOUND_ERR_EID            93
#define CS_COMPUTE_TABLES_NOT_FOUND_ERR_EID         94
#define CS_RECOMPUTE_FINISH_EEPROM_MEMORY_INF_EID   95
#define CS_RECOMPUTE_ERROR_TABLES_ERR_EID           96
#define CS_RECOMPUTE_ERROR_APP_ERR_EID              97
#define CS_RECOMPUTE_FINISH_TABLES_INF_EID          98
#define CS_RECOMPUTE_FINISH_APP_INF_EID             99
#define CS_ONESHOT_FINISHED_INF_EID                 100
#define CS_VAL_EEPROM_STATE_ERR_EID                 101
#define CS_VAL_EEPROM_RANGE_ERR_EID                 102
#define CS_VAL_MEMORY_STATE_ERR_EID                 103
#define CS_VAL_MEMORY_RANGE_ERR_EID                 104
#define CS_VAL_TABLES_STATE_ERR_EID                 105
#define CS_VAL_APP_STATE_ERR_EID                    106
#define CS_PROCESS_EEPROM_MEMORY_NO_ENTRIES_INF_EID 107
#define CS_PROCESS_APP_NO_ENTRIES_INF_EID           108
#define CS_PROCESS_TABLES_NO_ENTRIES_INF_EID        109
#define CS_TBL_INIT_ERR_EID                         110
#define CS_TBL_UPDATE_ERR_EID                       111
#define CS_CR_PIPE_ERR_EID                          112
#define CS_INIT_SB_SUBSCRIBE_HK_ERR_EID             113
#define CS_INIT_SB_SUBSCRIBE_BACK_ERR_EID           114
#define CS_INIT_SB_SUBSCRIBE_CMD_ERR_EID            115
#define CS_INIT_EEPROM_ERR_EID                      116
#define CS_INIT_MEMORY_ERR_EID                      117
#define CS_INIT_TABLES_ERR_EID                      118
#define CS_INIT_APP_ERR_EID                         119
#define CS_COMPUTE_TABLES_RELEASE_ERR_EID           120
#define CS_COMPUTE_TABLES_ERR_EID                   121
#define CS_COMPUTE_APP_ERR_EID                      122
#define CS_UPDATE_EEPROM_ERR_EID                    123
#define CS_UPDATE_MEMORY_ERR_EID                    124
#define CS_UPDATE_TABLES_ERR_EID                    125
#define CS_UPDATE_APP_ERR_EID                       126
#define CS_OS_TEXT_SEG_INF_EID                      127
#define CS_COMPUTE_APP_PLATFORM_DBG_EID             128
#define CS_ENABLE_TABLE_DEF_NOT_FOUND_DBG_EID       129
#define CS_DISABLE_TABLE_DEF_NOT_FOUND_DBG_EID      130
#define CS_ENABLE_APP_DEF_NOT_FOUND_DBG_EID         131
#define CS_DISABLE_APP_DEF_NOT_FOUND_DBG_EID        132
#define CS_DISABLE_MEMORY_DEF_EMPTY_DBG_EID         133
#define CS_ENABLE_MEMORY_DEF_EMPTY_DBG_EID          134
#define CS_DISABLE_EEPROM_DEF_EMPTY_DBG_EID         135
#define CS_ENABLE_EEPROM_DEF_EMPTY_DBG_EID          136
#define CS_VAL_TABLES_DEF_TBL_DUPL_ERR_EID          137
#define CS_VAL_TABLES_DEF_TBL_ZERO_NAME_ERR_EID     138
#define CS_VAL_TABLES_INF_EID                       139
#define CS_VAL_APP_DEF_TBL_DUPL_ERR_EID             140
#define CS_VAL_APP_DEF_TBL_ZERO_NAME_ERR_EID        141
#define CS_VAL_APP_INF_EID                          142
#define CS_VAL_MEMORY_INF_EID                       143
#define CS_VAL_EEPROM_INF_EID                       144
#define CS_CR_CDS_REG_ERR_EID                       145
#define CS_CR_CDS_CPY_ERR_EID                       146
#define CS_CR_CDS_RES_ERR_EID                       147
#define CS_UPDATE_CDS_ERR_EID                       148
#define CS_EXIT_INF_EID                             149
#define CS_CFE_TEXT_SEG_INF_EID                     150
#define CS_CMD_COMPUTE_PROG_ERR_EID                 152
#define CS_BKGND_COMPUTE_PROG_INF_EID               153
#define CS_VAL_APP_DEF_TBL_LONG_NAME_ERR_EID        154
#define CS_VAL_TABLES_DEF_TBL_LONG_NAME_ERR_EID     155
#endif
