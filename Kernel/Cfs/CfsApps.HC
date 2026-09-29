// CfsApps.HC — the app layer: simulated sensors, scheduler, limit checker, health monitor,
// stored commands, recorder and checksum. Everything talks through CfsSb; nothing talks to a
// driver directly, which is the property that lets a simulated sensor be replaced by a real one
// without any other app noticing.
//
// Simulated on purpose: none of this hardware is attached to the board yet. The point is that the
// architecture, the message set and the fault responses can all be built and tested now, and each
// simulated app is a drop-in for a driver later. Every sim app is marked SIM in its event text so
// a log can never be mistaken for one taken with real sensors.
#ifndef CFS_APPS_HC
#define CFS_APPS_HC
#include "CfsSb.HC"
#define CFS_APP_GNSS  0
#define CFS_APP_IMU   1
#define CFS_APP_NAV   2
#define CFS_APP_SDR   3
#define CFS_APP_EPS   4
#define CFS_APP_FPGA  5
#define CFS_APP_LC    6
#define CFS_APP_HS    7
#define CFS_APP_SC    8
#define CFS_APP_DS    9
#define CFS_APP_CS    10
#define CFS_APP_N     11

class CCfsApp
{
  U8 name[12];
  I64 enabled;
  I64 run_ctr;
  I64 period_ms;
  I64 next_due_us;
  I64 hung;
  I64 declared_dead;
};

CCfsApp cfs_app[CFS_APP_N];
I64 cfs_sch_cycles;
I64 cfs_safe_mode;
I64 cfs_safe_reason;
// --- payload helpers ----------------------------------------------------------------------
U0 CfsPutU32(U8 *p, I64 off, U32 v)
{
  p[off] = v & 0xFF;
  p[off + 1] = (v >> 8) & 0xFF;
  p[off + 2] = (v >> 16) & 0xFF;
  p[off + 3] = (v >> 24) & 0xFF;
}

U32 CfsGetU32(U8 *p, I64 off)
{
  return p[off] | (p[off + 1] << 8) | (p[off + 2] << 16) | (p[off + 3] << 24);
}
// --- simulated sensors --------------------------------------------------------------------
// Values are integer and deterministic: a sim whose output depends on timing is a sim whose test
// fails intermittently. Each app derives its numbers from its own run counter.
I64 cfs_sim_gnss_fix;
I64 cfs_sim_eps_mv;
I64 cfs_sim_sdr_signal_at;
I64 cfs_sim_fpga_silent;

U0 CfsAppGnss()
{
  U8 d[24];
  I64 k = cfs_app[CFS_APP_GNSS].run_ctr;
  CfsPutU32(d, 0, CfsTimeSec);
  CfsPutU32(d, 4, cfs_sim_gnss_fix);
  CfsSbSend(CFS_MID_GNSS_TIME, d, 8);
  // A slow synthetic ground track. Units are arbitrary; what matters downstream is that it moves.
  CfsPutU32(d, 0, 100000 + k * 37);
  CfsPutU32(d, 4, 200000 + k * 11);
  CfsPutU32(d, 8, 400000 + k);
  CfsSbSend(CFS_MID_GNSS_POSITION, d, 12);
}

U0 CfsAppImu()
{
  U8 d[24];
  I64 k = cfs_app[CFS_APP_IMU].run_ctr;
  // Triangle waves stand in for a rate sensor: bounded, signed, and exactly reproducible.
  I64 gx = (k % 40) - 20, gy = (k % 24) - 12, gz = (k % 8) - 4;
  CfsPutU32(d, 0, gx);
  CfsPutU32(d, 4, gy);
  CfsPutU32(d, 8, gz);
  CfsSbSend(CFS_MID_IMU_RAW, d, 12);
  CfsPutU32(d, 0, 300 + (k % 10));
  CfsPutU32(d, 4, 120);
  CfsPutU32(d, 8, 4000);
  CfsSbSend(CFS_MID_MAG_RAW, d, 12);
}

I64 cfs_nav_pipe;

U0 CfsAppNav()
{
  CCfsMsg m;
  U8 d[24];
  I64 got = 0, gx = 0, gy = 0, gz = 0;
  // Consume everything queued, then publish once. An app that publishes per input message
  // amplifies its own backlog, which is how a bus overload becomes unrecoverable.
  while (CfsSbReceive(cfs_nav_pipe, &m)) {
    if (m.mid == CFS_MID_IMU_RAW) {
      gx = CfsGetU32(m.data, 0);
      gy = CfsGetU32(m.data, 4);
      gz = CfsGetU32(m.data, 8);
      got++;
    }
  }
  if (!got)
    return;
  CfsPutU32(d, 0, gx);
  CfsPutU32(d, 4, gy);
  CfsPutU32(d, 8, gz);
  CfsSbSend(CFS_MID_ANGULAR_RATE, d, 12);
  // A placeholder quaternion: identity plus a wobble driven by the rate. Not an estimator.
  CfsPutU32(d, 0, 10000);
  CfsPutU32(d, 4, gx);
  CfsPutU32(d, 8, gy);
  CfsPutU32(d, 12, gz);
  CfsSbSend(CFS_MID_ATTITUDE_QUAT, d, 16);
  CfsPutU32(d, 0, got);
  CfsPutU32(d, 4, CfsTimeSec);
  CfsSbSend(CFS_MID_NAV_STATE, d, 8);
}

U0 CfsAppSdr()
{
  U8 d[24];
  I64 k = cfs_app[CFS_APP_SDR].run_ctr;
  CfsPutU32(d, 0, k);
  CfsPutU32(d, 4, 2400);
  CfsSbSend(CFS_MID_SDR_STATUS, d, 8);
  // Fire a detection once, at a chosen cycle, so the LC -> SC capture path is exercised
  // deterministically instead of whenever a random number says so.
  if (cfs_sim_sdr_signal_at && k == cfs_sim_sdr_signal_at) {
    CfsPutU32(d, 0, 9000);
    CfsPutU32(d, 4, 145800);
    CfsSbSend(CFS_MID_SDR_SIGNAL, d, 8);
    CfsEvs("SDR", CFS_EVS_INFO, "SIM signal detected");
  }
}

U0 CfsAppEps()
{
  U8 d[16];
  CfsPutU32(d, 0, cfs_sim_eps_mv);
  CfsPutU32(d, 4, 250);
  CfsSbSend(CFS_MID_EPS_TLM, d, 8);
}

U0 CfsAppFpga()
{
  U8 d[8];
  if (cfs_sim_fpga_silent)
    return;
  CfsPutU32(d, 0, cfs_app[CFS_APP_FPGA].run_ctr);
  CfsSbSend(CFS_MID_FPGA_TLM, d, 4);
}
// --- LC: watchpoints and actionpoints -----------------------------------------------------
#define CFS_MAX_WP 8
#define CFS_LC_GT  0
#define CFS_LC_LT  1

class CCfsWp
{
  U16 mid;
  I64 off;
  I64 op;
  I64 thresh;
  I64 in_use;
  I64 trips;
  I64 rts;
  I64 latched;
  U8 label[28];
};

CCfsWp cfs_wp[CFS_MAX_WP];
I64 cfs_lc_pipe;
I64 cfs_lc_evals;

I64 CfsLcAdd(U8 *label, U16 mid, I64 off, I64 op, I64 thresh, I64 rts)
{
  I64 i;
  for (i = 0; i < CFS_MAX_WP; i++) {
    if (!cfs_wp[i].in_use) {
      cfs_wp[i].in_use = 1;
      cfs_wp[i].mid = mid;
      cfs_wp[i].off = off;
      cfs_wp[i].op = op;
      cfs_wp[i].thresh = thresh;
      cfs_wp[i].rts = rts;
      cfs_wp[i].trips = 0;
      cfs_wp[i].latched = 0;
      StrCpy(cfs_wp[i].label, label);
      CfsSbSubscribe(mid, cfs_lc_pipe);
      return i;
    }
  }
  return -1;
}

I64 CfsScStart(I64 rts);
// Re-arm a watchpoint. Operator action, or the tail of a recovery sequence that believes it fixed
// the cause -- which is the honest place for the decision, not inside the detector.
I64 CfsLcReset(I64 wp)
{
  if (wp < 0 || wp >= CFS_MAX_WP || !cfs_wp[wp].in_use)
    return -1;
  cfs_wp[wp].latched = 0;
  return 0;
}

U0 CfsAppLc()
{
  CCfsMsg m;
  I64 i, v;
  while (CfsSbReceive(cfs_lc_pipe, &m)) {
    for (i = 0; i < CFS_MAX_WP; i++) {
      if (!cfs_wp[i].in_use || cfs_wp[i].mid != m.mid)
        continue;
      // Latched, the way a cFS actionpoint is disarmed once it fires. Without this a condition
      // that stays true re-triggers on every message: the first run of this sim logged the same
      // battery-low event dozens of times and spent so long on the UART that the run timed out.
      // A recovery that re-runs while its own condition is still true is also just wrong.
      if (cfs_wp[i].latched)
        continue;
      if (cfs_wp[i].off + 4 > m.len)
        continue;
      cfs_lc_evals++;
      v = CfsGetU32(m.data, cfs_wp[i].off);
      if (cfs_wp[i].op == CFS_LC_GT && v <= cfs_wp[i].thresh)
        continue;
      if (cfs_wp[i].op == CFS_LC_LT && v >= cfs_wp[i].thresh)
        continue;
      cfs_wp[i].trips++;
      cfs_wp[i].latched = 1;
      CfsEvs("LC", CFS_EVS_ERROR, cfs_wp[i].label);
      if (cfs_wp[i].rts >= 0)
        CfsScStart(cfs_wp[i].rts);
    }
  }
}
// --- SC: stored command sequences ---------------------------------------------------------
#define CFS_SC_END      0
#define CFS_SC_SEND     1
#define CFS_SC_DISABLE  2
#define CFS_SC_ENABLE   3
#define CFS_SC_SAFE     4
#define CFS_SC_EVENT    5
#define CFS_MAX_RTS     4
#define CFS_MAX_STEPS   8

class CCfsStep
{
  I64 kind;
  I64 delay_ms;
  U16 mid;
  I64 arg;
  U8 text[20];
};

CCfsStep cfs_rts[CFS_MAX_RTS][CFS_MAX_STEPS];
I64 cfs_rts_len[CFS_MAX_RTS];
I64 cfs_sc_active;
I64 cfs_sc_step;
I64 cfs_sc_next_us;
I64 cfs_sc_completed;

U0 CfsScInit()
{
  I64 i;
  for (i = 0; i < CFS_MAX_RTS; i++)
    cfs_rts_len[i] = 0;
  cfs_sc_active = -1;
  cfs_sc_step = 0;
  cfs_sc_completed = 0;
}

I64 CfsScAdd(I64 rts, I64 kind, I64 delay_ms, U16 mid, I64 arg, U8 *text)
{
  I64 n;
  if (rts < 0 || rts >= CFS_MAX_RTS)
    return -1;
  n = cfs_rts_len[rts];
  if (n >= CFS_MAX_STEPS)
    return -2;
  cfs_rts[rts][n].kind = kind;
  cfs_rts[rts][n].delay_ms = delay_ms;
  cfs_rts[rts][n].mid = mid;
  cfs_rts[rts][n].arg = arg;
  StrCpy(cfs_rts[rts][n].text, text);
  cfs_rts_len[rts] = n + 1;
  return 0;
}

I64 CfsScStart(I64 rts)
{
  if (rts < 0 || rts >= CFS_MAX_RTS || !cfs_rts_len[rts])
    return -1;
  // One sequence at a time. A second trigger while a recovery is running is ignored rather than
  // interleaved: two recovery sequences fighting over the same actuators is worse than a late one.
  if (cfs_sc_active >= 0)
    return -2;
  cfs_sc_active = rts;
  cfs_sc_step = 0;
  cfs_sc_next_us = CfsTimeUs;
  CfsEvs("SC", CFS_EVS_INFO, "sequence started");
  return 0;
}

U0 CfsAppSc()
{
  U8 d[8];
  I64 k, a;
  if (cfs_sc_active < 0)
    return;
  if (CfsTimeUs < cfs_sc_next_us)
    return;
  if (cfs_sc_step >= cfs_rts_len[cfs_sc_active]) {
    cfs_sc_active = -1;
    cfs_sc_completed++;
    CfsEvs("SC", CFS_EVS_INFO, "sequence complete");
    return;
  }
  k = cfs_rts[cfs_sc_active][cfs_sc_step].kind;
  a = cfs_rts[cfs_sc_active][cfs_sc_step].arg;
  if (k == CFS_SC_SEND) {
    CfsPutU32(d, 0, a);
    CfsSbSend(cfs_rts[cfs_sc_active][cfs_sc_step].mid, d, 4);
  }
  if (k == CFS_SC_DISABLE && a >= 0 && a < CFS_APP_N) {
    cfs_app[a].enabled = 0;
    CfsEvs("SC", CFS_EVS_INFO, "app disabled by sequence");
  }
  if (k == CFS_SC_ENABLE && a >= 0 && a < CFS_APP_N)
    cfs_app[a].enabled = 1;
  if (k == CFS_SC_SAFE) {
    cfs_safe_mode = 1;
    cfs_safe_reason = a;
    CfsPutU32(d, 0, a);
    CfsSbSend(CFS_MID_SAFE_MODE, d, 4);
    CfsEvs("SC", CFS_EVS_CRITICAL, "SAFE MODE");
  }
  if (k == CFS_SC_EVENT)
    CfsEvs("SC", CFS_EVS_INFO, cfs_rts[cfs_sc_active][cfs_sc_step].text);
  cfs_sc_next_us = CfsTimeUs + cfs_rts[cfs_sc_active][cfs_sc_step].delay_ms * 1000;
  cfs_sc_step++;
}
// --- HS: is each app still executing? -----------------------------------------------------
#define CFS_HS_WINDOW 4
I64 cfs_hs_last[CFS_APP_N];
I64 cfs_hs_stale[CFS_APP_N];
I64 cfs_hs_deaths;
I64 cfs_hs_rts;

U0 CfsAppHs()
{
  I64 i;
  for (i = 0; i < CFS_APP_N; i++) {
    if (i == CFS_APP_HS)
      continue;
    if (!cfs_app[i].enabled || cfs_app[i].declared_dead) {
      cfs_hs_last[i] = cfs_app[i].run_ctr;
      cfs_hs_stale[i] = 0;
      continue;
    }
    if (cfs_app[i].run_ctr == cfs_hs_last[i])
      cfs_hs_stale[i]++;
    else
      cfs_hs_stale[i] = 0;
    cfs_hs_last[i] = cfs_app[i].run_ctr;
    // "Stopped executing" is counted, not asserted on the first miss: a single late cycle is
    // normal on a cooperative scheduler and declaring death on it would make HS the fault.
    if (cfs_hs_stale[i] >= CFS_HS_WINDOW) {
      cfs_app[i].declared_dead = 1;
      cfs_hs_deaths++;
      CfsEvs("HS", CFS_EVS_CRITICAL, cfs_app[i].name);
      if (cfs_hs_rts >= 0)
        CfsScStart(cfs_hs_rts);
    }
  }
}
// --- DS: the recorder ---------------------------------------------------------------------
#define CFS_DS_CAP 4096
U8 cfs_ds_buf[CFS_DS_CAP];
I64 cfs_ds_len;
I64 cfs_ds_records;
I64 cfs_ds_pipe;
I64 cfs_ds_lost;

U0 CfsDsSubscribe(U16 mid)
{
  CfsSbSubscribe(mid, cfs_ds_pipe);
}

U0 CfsAppDs()
{
  CCfsMsg m;
  I64 need;
  while (CfsSbReceive(cfs_ds_pipe, &m)) {
    // Fixed 16-byte record: mid, len, MET seconds, first payload word. Enough to prove routing
    // and ordering without pretending to be a real file format.
    need = 16;
    if (cfs_ds_len + need > CFS_DS_CAP) {
      cfs_ds_lost++;
      continue;
    }
    CfsPutU32(cfs_ds_buf, cfs_ds_len, m.mid);
    CfsPutU32(cfs_ds_buf, cfs_ds_len + 4, m.len);
    CfsPutU32(cfs_ds_buf, cfs_ds_len + 8, m.met_us / 1000);
    if (m.len >= 4)
      CfsPutU32(cfs_ds_buf, cfs_ds_len + 12, CfsGetU32(m.data, 0));
    else
      CfsPutU32(cfs_ds_buf, cfs_ds_len + 12, 0);
    cfs_ds_len += need;
    cfs_ds_records++;
  }
}
// --- CS: checksum over a memory range -----------------------------------------------------
I64 cfs_cs_base;
I64 cfs_cs_len;
U32 cfs_cs_ref;
I64 cfs_cs_faults;

U32 CfsCsSum(I64 base, I64 len)
{
  U8 *p = base;
  U32 s = 0x1234;
  I64 i;
  for (i = 0; i < len; i++)
    s = (s << 1) + (s >> 15) + p[i];
  return s & 0xFFFF;
}

U0 CfsCsArm(I64 base, I64 len)
{
  cfs_cs_base = base;
  cfs_cs_len = len;
  cfs_cs_ref = CfsCsSum(base, len);
  cfs_cs_faults = 0;
}

U0 CfsAppCs()
{
  U32 now;
  if (!cfs_cs_len)
    return;
  now = CfsCsSum(cfs_cs_base, cfs_cs_len);
  if (now != cfs_cs_ref) {
    cfs_cs_faults++;
    cfs_cs_ref = now;
    CfsEvs("CS", CFS_EVS_CRITICAL, "checksum mismatch");
    if (cfs_hs_rts >= 0)
      CfsScStart(cfs_hs_rts);
  }
}
// --- SCH: the only thing that calls apps --------------------------------------------------
// Static dispatch by id rather than a table of function pointers: one less codegen corner to
// trust, and a flight scheduler with a fixed app set loses nothing by it.
U0 CfsAppRun(I64 id)
{
  if (id == CFS_APP_GNSS) {
    CfsAppGnss;
    return;
  }
  if (id == CFS_APP_IMU) {
    CfsAppImu;
    return;
  }
  if (id == CFS_APP_NAV) {
    CfsAppNav;
    return;
  }
  if (id == CFS_APP_SDR) {
    CfsAppSdr;
    return;
  }
  if (id == CFS_APP_EPS) {
    CfsAppEps;
    return;
  }
  if (id == CFS_APP_FPGA) {
    CfsAppFpga;
    return;
  }
  if (id == CFS_APP_LC) {
    CfsAppLc;
    return;
  }
  if (id == CFS_APP_HS) {
    CfsAppHs;
    return;
  }
  if (id == CFS_APP_SC) {
    CfsAppSc;
    return;
  }
  if (id == CFS_APP_DS) {
    CfsAppDs;
    return;
  }
  if (id == CFS_APP_CS)
    CfsAppCs;
}

U0 CfsSchTick()
{
  I64 i, now;
  CfsTimeAdvance();
  now = CfsTimeUs;
  cfs_sch_cycles++;
  for (i = 0; i < CFS_APP_N; i++) {
    if (!cfs_app[i].enabled || cfs_app[i].declared_dead)
      continue;
    if (now < cfs_app[i].next_due_us)
      continue;
    cfs_app[i].next_due_us = now + cfs_app[i].period_ms * 1000;
    // A hung app is scheduled and returns without doing anything -- which is exactly what HS has
    // to catch, and why the run counter is bumped by the APP, not by the scheduler.
    if (cfs_app[i].hung)
      continue;
    CfsAppRun(i);
    cfs_app[i].run_ctr++;
  }
}

U0 CfsAppSet(I64 id, U8 *name, I64 period_ms, I64 enabled)
{
  StrCpy(cfs_app[id].name, name);
  cfs_app[id].period_ms = period_ms;
  cfs_app[id].enabled = enabled;
  cfs_app[id].run_ctr = 0;
  cfs_app[id].next_due_us = 0;
  cfs_app[id].hung = 0;
  cfs_app[id].declared_dead = 0;
}
#endif
