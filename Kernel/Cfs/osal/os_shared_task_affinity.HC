/************************************************************************
 * NASA Docket No. GSC-18,719-1, and identified as "core Flight System:
 * Bootes"
 *
 * Copyright (c) 2020 United States Government as represented by the
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

// The DECLARATIONS from OSAL's src/os/inc/osapi-task-affinity.h: the cpu-set type, the four
// macros that manipulate it, and the public API. Split out of osapi_task_affinity.HC, which
// holds the bodies, for the reason the whole os_shared_*.HC convention exists -- cFE's task
// affinity module includes this header and must NOT drag in OSAL's implementation, which
// reaches into the id map and would pull the entire portable layer behind it.
//
// THE FOUR MACROS ARE FUNCTIONS HERE. In the C they are macros, with `do { } while (0)`
// wrappers for statement safety. Every call site in cFS passes them a pointer and uses them as
// a statement, so the call-site text is unchanged and the argument order is unchanged; what
// changes is that HolyC type-checks them. The alternative was a multi-line macro, and those
// are a place this compiler has surprises: a one-line `#define SETB(cpu, p) (p)[(cpu)/8] |= ...`
// used to store at the wrong index entirely -- see docs/HOLYC_STRUCT_LIMITS.md #4.
#ifndef OS_SHARED_TASK_AFFINITY_HC
#define OS_SHARED_TASK_AFFINITY_HC
#include "osconfig.HC"

// A bit per core. With OS_MAX_CPUS == 1 this is a single byte, which is why the division and
// shift below are never exercised past bit 0 in this configuration -- the oracle drives them
// directly for that reason.
class OS_cpuset_t
{
  U8 affinity_mask[(OS_MAX_CPUS + 7) / 8];
};

U0 OS_CPUSET_ZERO(OS_cpuset_t *cpusetptr)
{
  // NASA writes sizeof(cpusetptr->affinity_mask). `sizeof` of a member reached through a
  // POINTER does not parse in HolyC, so the bound is written out; it is the same expression
  // the member declaration uses.
  MemSet(cpusetptr->affinity_mask, 0, (OS_MAX_CPUS + 7) / 8);
}

U0 OS_CPUSET_SET(I64 cpu, OS_cpuset_t *cpusetptr)
{
  if (cpu < OS_MAX_CPUS)
    cpusetptr->affinity_mask[cpu / 8] |= 1 << (cpu % 8);
}

U0 OS_CPUSET_CLR(I64 cpu, OS_cpuset_t *cpusetptr)
{
  if (cpu < OS_MAX_CPUS)
    cpusetptr->affinity_mask[cpu / 8] &= ~(1 << (cpu % 8));
}

Bool OS_CPUSET_ISSET(I64 cpu, OS_cpuset_t *cpusetptr)
{
  if (cpu < OS_MAX_CPUS)
    return (cpusetptr->affinity_mask[cpu / 8] & (1 << (cpu % 8))) != 0;
  return 0;
}

// The public API. The bodies are in osapi_task_affinity.HC; a user of the TYPE does not need
// them, and cFE is such a user.
U32 OS_TaskAffinityCoresConfigured();
U32 OS_TaskAffinityGetCoresConfigured();
I32 OS_TaskAffinitySetAffinity(U32 task_id, OS_cpuset_t cpuset);
I32 OS_TaskAffinityGetAffinity(U32 task_id, OS_cpuset_t *cpuset);
#endif
