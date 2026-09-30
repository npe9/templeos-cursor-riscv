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
// NASA's OWN message code, 1:1-translated, sits under this bus. cfe_msg_integrity.HC brings the
// whole chain: the CCSDS primary header accessors, the v1 message-id encoding, the command and
// telemetry secondary headers, CFE_MSG_Init, and the origination hook that stamps a packet on
// its way out. Every one of those is gated byte-for-byte against the unmodified C by
// tests/scripts/run_cfs_xlat_smoke.sh, so what this bus puts on the wire is CCSDS because
// NASA's code put it there, not because this file imitates the layout.
#include "cfe/cfe_msg_init.HC"
#include "cfe/cfe_msg_integrity.HC"
#define CFS_MSG_PAYLOAD   96
#define CFS_MAX_PIPES     12
#define CFS_MAX_SUBS      64
#define CFS_PIPE_DEPTH    8
#define CFS_MAX_APPS      16
// Message IDs. Grouped the way an APID map is: sensors 0x100, navigation 0x200, payload 0x300,
// power 0x400, housekeeping/FDIR 0x500, commands 0x600.
//
// THESE ARE NOW REAL CCSDS STREAM IDS, not arbitrary tags, and that is a behavioural change
// rather than a renaming. In the cFS v1 message-id format the id IS the 16-bit stream id, so the
// TYPE bit (0x1000) and the HAS-SECONDARY-HEADER bit (0x0800) live inside the id itself. A
// telemetry id therefore has 0x0800 set and a command id has 0x1800, exactly as cFE's own
// examples use 0x0801 and 0x1801. Get this wrong and nothing looks broken: subscribing to
// 0x0101 and publishing something whose header says 0x0901 simply never matches, and a bus
// where no one receives anything is indistinguishable from a bus with no traffic.
//
// The apid grouping below is unchanged -- only the two class bits are new -- so the map a ground
// station would keep still reads the same way.
#define CFS_TLM_MID(apid) (0x0800 | (apid))
#define CFS_CMD_MID(apid) (0x1800 | (apid))
#define CFS_MID_IMU_RAW        CFS_TLM_MID(0x101)
#define CFS_MID_MAG_RAW        CFS_TLM_MID(0x102)
#define CFS_MID_GNSS_TIME      CFS_TLM_MID(0x103)
#define CFS_MID_GNSS_POSITION  CFS_TLM_MID(0x104)
#define CFS_MID_NAV_STATE      CFS_TLM_MID(0x201)
#define CFS_MID_ATTITUDE_QUAT  CFS_TLM_MID(0x202)
#define CFS_MID_ANGULAR_RATE   CFS_TLM_MID(0x203)
#define CFS_MID_SDR_STATUS     CFS_TLM_MID(0x301)
#define CFS_MID_SDR_SIGNAL     CFS_TLM_MID(0x302)
#define CFS_MID_SDR_CAPTURE    CFS_TLM_MID(0x303)
#define CFS_MID_EPS_TLM        CFS_TLM_MID(0x401)
#define CFS_MID_FPGA_TLM       CFS_TLM_MID(0x402)
#define CFS_MID_HK_TLM         CFS_TLM_MID(0x501)
#define CFS_MID_EVENT          CFS_TLM_MID(0x502)
#define CFS_MID_SAFE_MODE      CFS_TLM_MID(0x503)
#define CFS_MID_CMD_SDR        CFS_CMD_MID(0x601)
#define CFS_MID_CMD_EPS        CFS_CMD_MID(0x602)
// Event severities, cFE's four.
#define CFS_EVS_DEBUG     0
#define CFS_EVS_INFO      1
#define CFS_EVS_ERROR     2
#define CFS_EVS_CRITICAL  3

// A message is now a REAL CCSDS PACKET. The header is NASA's CFE_MSG_TelemetryHeader -- six
// bytes of primary header, six of timestamp, four spare -- and the payload follows it
// contiguously, which is what makes CFE_MSG_SetSize's byte count mean what it says and what
// lets CFE_MSG_ComputeCheckSum walk the whole packet. The old ad-hoc {mid, seq, len, pad,
// met_us} is gone: every one of those five fields is now a field of the CCSDS header, read and
// written only through the translated accessors.
//
// Nothing outside this file touches the header directly. CfsMsgId, CfsMsgLen and CfsMsgTimeUs
// below are the whole interface, so the apps did not need to learn CCSDS to keep working.
class CCfsMsg
{
  CFE_MSG_TelemetryHeader Hdr;
  U8 data[CFS_MSG_PAYLOAD];
};
// Every slot reserves the LARGER of cFE's two headers, 16 bytes, even for a command whose real
// CFE_MSG_CommandHeader is 8. That is this bus's choice, not cFE's: a fixed-size slot wants one
// payload offset, and both header types begin with the same CFE_MSG_Message so the accessors do
// not care. The consequence to know is that a command's checksum covers eight bytes it does not
// use, consistently at both ends.
#define CFS_MSG_HDR_BYTES sizeof(CFE_MSG_TelemetryHeader)

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
// THE CLOCK cFE ASKS FOR. cfe_msg_integrity.HC declares CFE_TIME_GetTime and does not define it
// -- in real cFS the TIME module owns it, and that module is not translated yet -- so this bus
// supplies it from its own mission-elapsed time. Leaving it undefined would NOT have failed to
// build: a HolyC prototype with no definition becomes an import that the link fills silently,
// and OriginationAction would have stamped every packet with whatever answered. The cfs-xlat
// gate now asserts an empty import trailer for exactly that reason.
//
// The conversion is lossy in one direction and that is CCSDS, not this code: the telemetry
// secondary header carries 32 bits of seconds and 16 of subseconds, so the finest timestamp a
// packet can hold is 1/65536 s, about 15.3 us. Both conversions round to nearest rather than
// truncate, because two truncations compound and a 5 ms tick would read back as 4.989 ms.
CFE_TIME_SysTime CFE_TIME_GetTime()
{
  CFE_TIME_SysTime t;
  I64 us = CfsTimeUs;
  t.Seconds = us / 1000000;
  // 2^-32-second units, rounded. SetMsgTime keeps only the top 16 bits of this.
  t.Subseconds = ((us % 1000000) * 4294967296 + 500000) / 1000000;
  return t;
}

I64 CfsSbSend(U16 mid, U8 *data, I64 len)
{
  I64 j, p, nh, delivered = 0;
  Bool acceptable;
  CCfsMsg *slot;
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
    slot = &cfs_pipe[p].slot[cfs_pipe[p].head];
    // NASA's code builds the packet from here down. Init clears it, plants the CCSDS defaults
    // (version 0, unsegmented), writes the message id into the stream id and sets the length.
    CFE_MSG_Init(&slot->Hdr.Msg, CFE_SB_ValueToMsgId(mid), CFS_MSG_HDR_BYTES + len);
    CFE_MSG_SetSequenceCount(&slot->Hdr.Msg, cfs_seq_ctr & CFE_MSG_SEQCNT_MASK);
    // PAYLOAD BEFORE ORIGINATION, and the order is not cosmetic. OriginationAction checksums a
    // COMMAND over every byte the length field covers, so copying the payload after it would
    // checksum zeros and then overwrite them -- a packet that fails its own validation, in a
    // sim that does not yet validate any. Real cFS has the same ordering for the same reason:
    // an app fills its payload and only then hands the message to the bus.
    if (data && len > 0)
      MemCpy(slot->data, data, len);
    // The origination hook, called for its SIDE EFFECTS exactly as cFE calls it: it timestamps
    // telemetry and checksums commands, and whichever does not apply to this packet fails
    // harmlessly. The id's own type bit decides which, so there is no branch here.
    CFE_MSG_OriginationAction(&slot->Hdr.Msg, sizeof(CCfsMsg), &acceptable);
    cfs_pipe[p].head = nh;
    delivered++;
  }
  cfs_sb_sent++;
  if (!delivered)
    cfs_sb_nosub++;
  return delivered;
}

// The whole interface the apps use. Each one reads the CCSDS header through the translated
// accessors, so an app never learns the bit layout and a header-format change stays in this file.
U16 CfsMsgId(CCfsMsg *m)
{
  CFE_SB_MsgId id;
  if (!m)
    return 0;
  CFE_MSG_GetMsgId(&m->Hdr.Msg, &id);
  return CFE_SB_MsgIdToValue(id);
}

I64 CfsMsgLen(CCfsMsg *m)
{
  I64 sz = 0;
  if (!m)
    return 0;
  CFE_MSG_GetSize(&m->Hdr.Msg, &sz);
  sz -= CFS_MSG_HDR_BYTES;
  if (sz < 0)
    return 0;
  return sz;
}

// Zero for a command, which carries a checksum where telemetry carries a time. GetMsgTime says
// so by returning WRONG_MSG_TYPE, and it zeroes the out-parameter itself.
I64 CfsMsgTimeUs(CCfsMsg *m)
{
  CFE_TIME_SysTime t;
  if (!m)
    return 0;
  if (CFE_MSG_GetMsgTime(&m->Hdr.Msg, &t) != CFE_SUCCESS)
    return 0;
  return t.Seconds * 1000000 + (t.Subseconds * 1000000 + 2147483648) / 4294967296;
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
