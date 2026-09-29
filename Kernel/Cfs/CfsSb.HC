// CfsSb.HC — software bus, time and events: the cFS architecture, native in HolyC.
//
// This is NOT NASA's cFE. It is the same architecture -- publish/subscribe on message IDs, pipes
// with depth, event messages, mission-elapsed time -- written for this port so the app layer above
// it can be built and exercised now, on hardware that mostly does not exist yet. When the cFS
// translation in docs/CFS_PLAN.md lands, the apps move over and this goes away. Keeping the
// message IDs and the CCSDS-shaped header the same is what makes that move mechanical.
//
// Deliberately static: fixed tables, fixed-size messages, ring buffers, no allocation anywhere.
// That is not a shortcut. Flight software wants a bounded worst case more than it wants elasticity,
// and a bus that cannot fail to allocate is one less fault to inject.
#ifndef CFS_SB_HC
#define CFS_SB_HC
#define CFS_MSG_PAYLOAD   96
#define CFS_MAX_PIPES     12
#define CFS_MAX_SUBS      64
#define CFS_PIPE_DEPTH    8
#define CFS_MAX_APPS      16
// Message IDs. Grouped the way an APID map is: sensors 0x100, navigation 0x200, payload 0x300,
// power 0x400, housekeeping/FDIR 0x500, commands 0x600.
#define CFS_MID_IMU_RAW        0x0101
#define CFS_MID_MAG_RAW        0x0102
#define CFS_MID_GNSS_TIME      0x0103
#define CFS_MID_GNSS_POSITION  0x0104
#define CFS_MID_NAV_STATE      0x0201
#define CFS_MID_ATTITUDE_QUAT  0x0202
#define CFS_MID_ANGULAR_RATE   0x0203
#define CFS_MID_SDR_STATUS     0x0301
#define CFS_MID_SDR_SIGNAL     0x0302
#define CFS_MID_SDR_CAPTURE    0x0303
#define CFS_MID_EPS_TLM        0x0401
#define CFS_MID_FPGA_TLM       0x0402
#define CFS_MID_HK_TLM         0x0501
#define CFS_MID_EVENT          0x0502
#define CFS_MID_SAFE_MODE      0x0503
#define CFS_MID_CMD_SDR        0x0601
#define CFS_MID_CMD_EPS        0x0602
// Event severities, cFE's four.
#define CFS_EVS_DEBUG     0
#define CFS_EVS_INFO      1
#define CFS_EVS_ERROR     2
#define CFS_EVS_CRITICAL  3

class CCfsMsg
{
  U16 mid;
  U16 seq;
  U16 len;
  U16 pad;
  I64 met_us;
  U8 data[CFS_MSG_PAYLOAD];
};

class CCfsPipe
{
  U8 name[16];
  I64 in_use;
  I64 head;
  I64 tail;
  I64 depth;
  I64 dropped;
  I64 received;
  CCfsMsg slot[CFS_PIPE_DEPTH];
};

class CCfsSub
{
  U16 mid;
  I64 pipe;
  I64 in_use;
};

CCfsPipe cfs_pipe[CFS_MAX_PIPES];
CCfsSub cfs_sub[CFS_MAX_SUBS];
I64 cfs_sb_sent;
I64 cfs_sb_nosub;
U16 cfs_seq_ctr;
I64 cfs_evs_count[4];
I64 cfs_evs_quiet;
// --- time ---------------------------------------------------------------------------------
// Mission elapsed time. CLINT mtime is 1 MHz on this board -- measured, not assumed -- so the
// tick IS microseconds and MET needs no scaling. On a platform with a different timebase this is
// the one place that has to change.
I64 cfs_met_epoch;
// Simulated time, and it is not a shortcut. A scheduler driven by the wall clock makes every test
// depend on how fast the host happens to be: run 400 cycles in a tight loop and only a couple of
// microseconds of mission time pass, so nothing becomes due and the whole timeline collapses. That
// is exactly what the first run of the sim did -- 2 IMU executions in 400 cycles.
//
// With virtual time the tick advances the clock by a fixed step, so a cycle count IS a duration,
// every app runs the number of times its period says, and the result is bit-identical on any host.
// Real time stays available for running against hardware; the flag chooses.
I64 cfs_vtime_en;
I64 cfs_vtime_us;
I64 cfs_vtime_step_us;

I64 CfsTimeUs()
{
  if (cfs_vtime_en)
    return cfs_vtime_us;
  return GetTSC - cfs_met_epoch;
}

U0 CfsTimeSimulate(I64 step_us)
{
  //Switch to simulated time, advancing step_us per scheduler tick.
  cfs_vtime_en = 1;
  cfs_vtime_us = 0;
  cfs_vtime_step_us = step_us;
}

U0 CfsTimeAdvance()
{
  if (cfs_vtime_en)
    cfs_vtime_us += cfs_vtime_step_us;
}

I64 CfsTimeSec()
{
  return CfsTimeUs / CONFIG_TIMEBASE_FREQ;
}

U0 CfsTimeInit()
{
  cfs_met_epoch = GetTSC;
  cfs_vtime_en = 0;
  cfs_vtime_us = 0;
  cfs_vtime_step_us = 0;
}
// --- events -------------------------------------------------------------------------------
U0 CfsEvs(U8 *app, I64 sev, U8 *text)
{
  U8 *tag;
  if (sev < 0 || sev > 3)
    sev = CFS_EVS_INFO;
  cfs_evs_count[sev]++;
  if (cfs_evs_quiet)
    return;
  tag = "DEBUG";
  if (sev == CFS_EVS_INFO)
    tag = "INFO";
  if (sev == CFS_EVS_ERROR)
    tag = "ERROR";
  if (sev == CFS_EVS_CRITICAL)
    tag = "CRIT";
  RVUartPutS("EVS ");
  RVUartPutS(tag);
  RVUartPutS(" ");
  RVUartPutS(app);
  RVUartPutS(": ");
  RVUartPutS(text);
  RVUartPutS("\n");
}
// --- bus ----------------------------------------------------------------------------------
U0 CfsSbInit()
{
  I64 i, j;
  for (i = 0; i < CFS_MAX_PIPES; i++) {
    cfs_pipe[i].in_use = 0;
    cfs_pipe[i].head = 0;
    cfs_pipe[i].tail = 0;
    cfs_pipe[i].depth = CFS_PIPE_DEPTH;
    cfs_pipe[i].dropped = 0;
    cfs_pipe[i].received = 0;
  }
  for (j = 0; j < CFS_MAX_SUBS; j++)
    cfs_sub[j].in_use = 0;
  cfs_sb_sent = 0;
  cfs_sb_nosub = 0;
  cfs_seq_ctr = 0;
}

I64 CfsSbCreatePipe(U8 *name, I64 depth)
{
  I64 i;
  for (i = 0; i < CFS_MAX_PIPES; i++) {
    if (!cfs_pipe[i].in_use) {
      cfs_pipe[i].in_use = 1;
      cfs_pipe[i].head = 0;
      cfs_pipe[i].tail = 0;
      cfs_pipe[i].dropped = 0;
      cfs_pipe[i].received = 0;
      if (depth > 0 && depth <= CFS_PIPE_DEPTH)
        cfs_pipe[i].depth = depth;
      else
        cfs_pipe[i].depth = CFS_PIPE_DEPTH;
      StrCpy(cfs_pipe[i].name, name);
      return i;
    }
  }
  return -1;
}

I64 CfsSbSubscribe(U16 mid, I64 pipe)
{
  I64 j;
  if (pipe < 0 || pipe >= CFS_MAX_PIPES || !cfs_pipe[pipe].in_use)
    return -1;
  for (j = 0; j < CFS_MAX_SUBS; j++) {
    if (!cfs_sub[j].in_use) {
      cfs_sub[j].in_use = 1;
      cfs_sub[j].mid = mid;
      cfs_sub[j].pipe = pipe;
      return 0;
    }
  }
  return -2;
}
// Deliver to every subscriber. A full pipe DROPS and counts, it does not block and it does not
// grow: "the queue filled" is one of the faults this system exists to detect, so it has to be a
// real, observable outcome rather than something the bus papers over.
I64 CfsSbSend(U16 mid, U8 *data, I64 len)
{
  I64 j, p, nh, delivered = 0;
  I64 now = CfsTimeUs;
  if (len < 0)
    len = 0;
  if (len > CFS_MSG_PAYLOAD)
    len = CFS_MSG_PAYLOAD;
  cfs_seq_ctr++;
  for (j = 0; j < CFS_MAX_SUBS; j++) {
    if (!cfs_sub[j].in_use || cfs_sub[j].mid != mid)
      continue;
    p = cfs_sub[j].pipe;
    nh = (cfs_pipe[p].head + 1) % cfs_pipe[p].depth;
    if (nh == cfs_pipe[p].tail) {
      cfs_pipe[p].dropped++;
      continue;
    }
    cfs_pipe[p].slot[cfs_pipe[p].head].mid = mid;
    cfs_pipe[p].slot[cfs_pipe[p].head].seq = cfs_seq_ctr;
    cfs_pipe[p].slot[cfs_pipe[p].head].len = len;
    cfs_pipe[p].slot[cfs_pipe[p].head].met_us = now;
    if (data && len > 0)
      MemCpy(cfs_pipe[p].slot[cfs_pipe[p].head].data, data, len);
    cfs_pipe[p].head = nh;
    delivered++;
  }
  cfs_sb_sent++;
  if (!delivered)
    cfs_sb_nosub++;
  return delivered;
}

I64 CfsSbReceive(I64 pipe, CCfsMsg *out)
{
  I64 t;
  if (pipe < 0 || pipe >= CFS_MAX_PIPES || !cfs_pipe[pipe].in_use || !out)
    return 0;
  if (cfs_pipe[pipe].tail == cfs_pipe[pipe].head)
    return 0;
  t = cfs_pipe[pipe].tail;
  MemCpy(out, &cfs_pipe[pipe].slot[t], sizeof(CCfsMsg));
  cfs_pipe[pipe].tail = (t + 1) % cfs_pipe[pipe].depth;
  cfs_pipe[pipe].received++;
  return 1;
}

I64 CfsSbPipeDropped(I64 pipe)
{
  if (pipe < 0 || pipe >= CFS_MAX_PIPES)
    return -1;
  return cfs_pipe[pipe].dropped;
}
// Fill a pipe on purpose. Injecting "the bus backed up" is a first-class fault in the FDIR
// experiment, and it must be triggerable without waiting for a real overload.
I64 CfsSbFloodPipe(I64 pipe, U16 mid, I64 n)
{
  I64 i, sent = 0;
  U8 junk[8];
  for (i = 0; i < 8; i++)
    junk[i] = i;
  for (i = 0; i < n; i++)
    sent += CfsSbSend(mid, junk, 8);
  return sent;
}
#endif
