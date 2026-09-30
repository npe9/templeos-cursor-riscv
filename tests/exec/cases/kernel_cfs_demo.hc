// The simulated spacecraft: bus, apps, and the fault-detection loop, all running on one machine.
//
// No hardware is attached. Every sensor here is a deterministic simulation (see Kernel/Cfs) and
// says SIM in its events, so a log from this can never be mistaken for one taken with real sensors.
// What is real is the architecture: apps only ever talk through the software bus, so replacing a
// simulated sensor with a driver later touches nothing else.
//
// The gate asserts the FDIR chain end to end, not merely that messages flow:
//   sensing -> navigation -> limit check -> stored sequence -> safe mode
// plus health-and-safety noticing an app that stopped executing, the recorder capturing a stream,
// the checksum app catching deliberate memory corruption, and the bus DROPPING when a pipe fills.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/Cfs/CfsApps.HC"
U0 Say(U8 *s)
{
  RVUartPutS(s);
}

U0 SayNum(U8 *label, I64 v)
{
  U8 d[24];
  I64 i = 0, j;
  RVUartPutS(label);
  if (v < 0) {
    RVUartPutS("-");
    v = -v;
  }
  if (!v)
    d[i++] = '0';
  while (v > 0) {
    d[i++] = '0' + v % 10;
    v /= 10;
  }
  j = i;
  while (j > 0) {
    U8 one[2];
    j--;
    one[0] = d[j];
    one[1] = 0;
    RVUartPutS(one);
  }
  RVUartPutS("\n");
}

// One number and a trailing space. SayNum ends its own line, so it cannot be reused here.
U0 SayNumSp(I64 v)
{
  U8 d[24];
  I64 i = 0, j;
  if (!v)
    d[i++] = '0';
  while (v > 0) {
    d[i++] = '0' + v % 10;
    v /= 10;
  }
  j = i;
  while (j > 0) {
    U8 one[2];
    j--;
    one[0] = d[j];
    one[1] = 0;
    RVUartPutS(one);
  }
  RVUartPutS(" ");
}
// A deliberately corruptible region for the checksum app to watch.
U8 cfs_payload_region[64];

U0 CfsBuildSequences()
{
  // RTS 0: the SDR capture timeline. Signal detected -> configure, capture, mark complete.
  CfsScAdd(0, CFS_SC_EVENT, 0, 0, 0, "capture begin");
  CfsScAdd(0, CFS_SC_SEND, 0, CFS_MID_CMD_SDR, 1, "");
  CfsScAdd(0, CFS_SC_SEND, 0, CFS_MID_SDR_CAPTURE, 4096, "");
  CfsScAdd(0, CFS_SC_EVENT, 0, 0, 0, "capture complete");
  // RTS 1: load shed. Battery low -> disable the payload, then the FPGA.
  CfsScAdd(1, CFS_SC_EVENT, 0, 0, 0, "load shed");
  CfsScAdd(1, CFS_SC_DISABLE, 0, 0, CFS_APP_SDR, "");
  CfsScAdd(1, CFS_SC_DISABLE, 0, 0, CFS_APP_FPGA, "");
  // RTS 2: safe mode. The response to a dead app or a checksum fault.
  CfsScAdd(2, CFS_SC_EVENT, 0, 0, 0, "entering safe mode");
  CfsScAdd(2, CFS_SC_DISABLE, 0, 0, CFS_APP_SDR, "");
  CfsScAdd(2, CFS_SC_SAFE, 0, 0, 1, "");
}

I64 main()
{
  I64 i, cyc;
  RVUartInit();
  Say("cfs-sim: start\n");
  CfsTimeInit();
  // 5 ms of mission time per scheduler cycle, so a cycle count is a duration and the run is
  // reproducible on any host. 400 cycles below is therefore 2 seconds of mission time.
  CfsTimeSimulate(5000);
  CfsSbInit();
  CfsScInit();
  // Pipes and subscriptions. NAV listens to the IMU; LC gets its own pipe as watchpoints are
  // added; DS records three streams.
  cfs_nav_pipe = CfsSbCreatePipe("NAV", 8);
  cfs_lc_pipe = CfsSbCreatePipe("LC", 8);
  cfs_ds_pipe = CfsSbCreatePipe("DS", 8);
  CfsSbSubscribe(CFS_MID_IMU_RAW, cfs_nav_pipe);
  CfsDsSubscribe(CFS_MID_NAV_STATE);
  CfsDsSubscribe(CFS_MID_EPS_TLM);
  CfsDsSubscribe(CFS_MID_SDR_STATUS);
  // Apps and their rates. Periods are milliseconds of mission-elapsed time.
  CfsAppSet(CFS_APP_GNSS, "GNSS", 100, 1);
  CfsAppSet(CFS_APP_IMU, "IMU", 10, 1);
  CfsAppSet(CFS_APP_NAV, "NAV", 20, 1);
  CfsAppSet(CFS_APP_SDR, "SDR", 50, 1);
  CfsAppSet(CFS_APP_EPS, "EPS", 100, 1);
  CfsAppSet(CFS_APP_FPGA, "FPGA", 100, 1);
  CfsAppSet(CFS_APP_LC, "LC", 20, 1);
  CfsAppSet(CFS_APP_HS, "HS", 200, 1);
  CfsAppSet(CFS_APP_SC, "SC", 20, 1);
  CfsAppSet(CFS_APP_DS, "DS", 50, 1);
  CfsAppSet(CFS_APP_CS, "CS", 200, 1);
  CfsBuildSequences();
  cfs_hs_rts = 2;
  cfs_sim_gnss_fix = 3;
  cfs_sim_eps_mv = 8200;
  cfs_sim_sdr_signal_at = 20;
  cfs_sim_fpga_silent = 0;
  // Watchpoints: a detected signal starts the capture sequence; a low battery sheds load.
  CfsLcAdd("SDR signal -> capture", CFS_MID_SDR_SIGNAL, 0, CFS_LC_GT, 5000, 0);
  CfsLcAdd("battery low -> shed", CFS_MID_EPS_TLM, 0, CFS_LC_LT, 7000, 1);
  for (i = 0; i < 64; i++)
    cfs_payload_region[i] = i;
  CfsCsArm(cfs_payload_region, 64);
  Say("cfs-sim: configured\n");
  // ---- phase 1: nominal ----------------------------------------------------------------
  for (cyc = 0; cyc < 400; cyc++)
    CfsSchTick();
  SayNum("cfs-sim: nominal cycles=", cfs_sch_cycles);
  SayNum("cfs-sim: imu_runs=", cfs_app[CFS_APP_IMU].run_ctr);
  SayNum("cfs-sim: nav_runs=", cfs_app[CFS_APP_NAV].run_ctr);
  SayNum("cfs-sim: ds_records=", cfs_ds_records);
  SayNum("cfs-sim: sc_completed=", cfs_sc_completed);
  if (cfs_app[CFS_APP_NAV].run_ctr > 0 && cfs_ds_records > 0)
    Say("cfs-sim: nominal_ok\n");
  // The SDR detection should have tripped LC and run the capture sequence.
  if (cfs_wp[0].trips > 0 && cfs_sc_completed > 0)
    Say("cfs-sim: capture_chain_ok\n");
  // ---- is the bus actually carrying CCSDS? ----------------------------------------------
  // The apps would keep working over any header at all, so "messages flow" proves nothing about
  // the format. This decodes a packet TWICE -- once with NASA's accessors, once by reading raw
  // bytes -- and requires the two to agree. A ground station parsing this stream would see a
  // conformant CCSDS space packet, which is the whole reason for putting the translated module
  // underneath rather than beside.
  {
    CCfsMsg probe;
    U8 payload[12];
    // NOT named pi: Kernel/KernelA.HH:50 defines pi as a #define for the F64 bit pattern of PI,
    // so `I64 pi;` expands to `I64 (0x400921FB54442D18(F64));` and the compiler reports
    // "<macro expansion>:1:20: Expected '*' in function pointer declarator" with no source line
    // to look at. Short lowercase locals in kernel-including code are a hazard for this reason.
    I64 bidx;
    CFE_SB_MsgId pid;
    CFE_TIME_SysTime pt;
    I64 psize = 0, ptype = 0;
    Bool psec = FALSE, pvalid = FALSE;
    U16 pver = 0xFF;
    I64 ok = 1;
    U8 *raw = &probe;
    // A pipe of its own, created here, so the packet received below is unambiguously the one
    // sent below -- the NAV pipe carries real traffic by now and would hand back someone else's.
    I64 ppipe = CfsSbCreatePipe("PROBE", 4);
    I64 tsend, tgot, terr;
    CfsSbSubscribe(CFS_MID_IMU_RAW, ppipe);
    // Built byte by byte on purpose: HolyC has no \xNN string escape (measured -- "\x11"[0] is
    // not 0x11), and a payload that quietly was not what it claimed would make the checks below
    // agree about the wrong thing.
    for (bidx = 0; bidx < 12; bidx++)
      payload[bidx] = 0x11 * (bidx + 1);
    tsend = CfsTimeUs;
    CfsSbSend(CFS_MID_IMU_RAW, payload, 12);
    if (!CfsSbReceive(ppipe, &probe)) {
      Say("cfs-sim: ccsds_FAIL no packet\n");
    } else {
      CFE_MSG_GetMsgId(&probe.Hdr.Msg, &pid);
      CFE_MSG_GetSize(&probe.Hdr.Msg, &psize);
      CFE_MSG_GetType(&probe.Hdr.Msg, &ptype);
      CFE_MSG_GetHasSecondaryHeader(&probe.Hdr.Msg, &psec);
      CFE_MSG_GetHeaderVersion(&probe.Hdr.Msg, &pver);
      // The six primary-header bytes, straight out of memory. These are what goes on a wire.
      // Routing now goes through NASA's hash map, so say so with numbers: how many routes the
      // subscriptions created and how many hash collisions it cost. A linear scan would have
      // neither.
      SayNum("cfs-sim: sbr_routes=", CFE_SBR_RDATA.RouteIdxTop);
      SayNum("cfs-sim: sbr_collisions=", cfs_sb_collisions);
            Say("cfs-sim: ccsds_pri=");
      SayNumSp(raw[0]);
      SayNumSp(raw[1]);
      SayNumSp(raw[2]);
      SayNumSp(raw[3]);
      SayNumSp(raw[4]);
      SayNumSp(raw[5]);
      Say("\n");
      // Accessors and raw bytes must agree: stream id is big-endian in bytes 0..1, and the
      // length field is the CCSDS one -- total size minus seven, not the payload size.
      if (CFE_SB_MsgIdToValue(pid) != CFS_MID_IMU_RAW)
        ok = 0;
      if (raw[0] != (CFS_MID_IMU_RAW >> 8) || raw[1] != (CFS_MID_IMU_RAW & 0xFF))
        ok = 0;
      if (psize != 16 + 12 || (raw[4] << 8) + raw[5] != psize - 7)
        ok = 0;
      if (ptype != CFE_MSG_Type_Tlm || !psec || pver != 0)
        ok = 0;
      // Unsegmented, which is what CFE_MSG_InitDefaultHdr plants: the top two bits of byte 2.
      if ((raw[2] & 0xC0) != 0xC0)
        ok = 0;
      // A telemetry packet carries a time, and it must ROUND-TRIP to the MET the bus stamped
      // it with. Not merely "nonzero": the first version of this check asserted nonzero and
      // failed, because it ran before any tick and the correct answer at MET 0 is 0. Asserting
      // a value that is only right once the clock has moved is a test of the clock, not of the
      // packet -- so this runs after phase 1 and compares against the MET captured at send.
      //
      // The tolerance is CCSDS, not slop: the telemetry secondary header holds 32 bits of
      // seconds and 16 of subseconds, so the finest representable step is 1/65536 s, about
      // 15.3 us, and a round trip can land one tick away.
      if (CFE_MSG_GetMsgTime(&probe.Hdr.Msg, &pt) != CFE_SUCCESS)
        ok = 0;
      if (tsend <= 0)
        ok = 0; // would make the comparison below vacuous
      tgot = CfsMsgTimeUs(&probe);
      terr = tgot - tsend;
      if (terr < 0)
        terr = -terr;
      if (terr > 16)
        ok = 0;
      SayNum("cfs-sim: ccsds_terr_us=", terr);
      if (CfsMsgLen(&probe) != 12 || probe.data[0] != 0x11 || probe.data[11] != 0xCC)
        ok = 0;
      if (ok)
        Say("cfs-sim: ccsds_ok\n");
      else
        Say("cfs-sim: ccsds_FAIL decode disagrees\n");
    }
    // And a COMMAND takes the other branch of the same origination hook: a checksum, no time.
    // This is the ordering bug's witness -- checksum the packet before the payload is in it and
    // ValidateChecksum says no.
    {
      CCfsMsg cprobe;
      I64 cpipe = CfsSbCreatePipe("CMDPROBE", 4);
      CfsSbSubscribe(CFS_MID_CMD_EPS, cpipe);
      for (bidx = 0; bidx < 4; bidx++)
        payload[bidx] = bidx + 1;
      CfsSbSend(CFS_MID_CMD_EPS, payload, 4);
      if (!CfsSbReceive(cpipe, &cprobe)) {
        Say("cfs-sim: cmdcsum_FAIL no packet\n");
      } else {
        pvalid = FALSE;
        if (CFE_MSG_ValidateChecksum(&cprobe.Hdr.Msg, &pvalid) == CFE_SUCCESS && pvalid &&
            CfsMsgTimeUs(&cprobe) == 0 && CfsMsgId(&cprobe) == CFS_MID_CMD_EPS)
          Say("cfs-sim: cmdcsum_ok\n");
        else
          Say("cfs-sim: cmdcsum_FAIL\n");
      }
    }
  }
  // ---- phase 2: battery sag -> load shed ------------------------------------------------
  cfs_sim_eps_mv = 6400;
  for (cyc = 0; cyc < 200; cyc++)
    CfsSchTick();
  if (cfs_wp[1].trips > 0 && !cfs_app[CFS_APP_SDR].enabled)
    Say("cfs-sim: load_shed_ok\n");
  else
    Say("cfs-sim: load_shed_FAIL\n");
  // ---- phase 3: an app hangs -> HS declares it dead -> safe mode ------------------------
  cfs_app[CFS_APP_SDR].enabled = 1;
  cfs_app[CFS_APP_SDR].declared_dead = 0;
  cfs_app[CFS_APP_IMU].hung = 1;
  Say("cfs-sim: injecting IMU hang\n");
  for (cyc = 0; cyc < 600; cyc++)
    CfsSchTick();
  SayNum("cfs-sim: hs_deaths=", cfs_hs_deaths);
  if (cfs_app[CFS_APP_IMU].declared_dead && cfs_hs_deaths > 0)
    Say("cfs-sim: hs_detect_ok\n");
  else
    Say("cfs-sim: hs_detect_FAIL\n");
  if (cfs_safe_mode)
    Say("cfs-sim: safe_mode_ok\n");
  else
    Say("cfs-sim: safe_mode_FAIL\n");
  // ---- phase 4: memory corruption -> CS catches it --------------------------------------
  cfs_payload_region[7] = 0xAA;
  for (cyc = 0; cyc < 300; cyc++)
    CfsSchTick();
  SayNum("cfs-sim: cs_faults=", cfs_cs_faults);
  if (cfs_cs_faults > 0)
    Say("cfs-sim: cs_detect_ok\n");
  else
    Say("cfs-sim: cs_detect_FAIL\n");
  // ---- phase 5: fill a pipe -> the bus drops, visibly ----------------------------------
  CfsSbFloodPipe(cfs_nav_pipe, CFS_MID_IMU_RAW, 64);
  SayNum("cfs-sim: nav_dropped=", CfsSbPipeDropped(cfs_nav_pipe));
  if (CfsSbPipeDropped(cfs_nav_pipe) > 0)
    Say("cfs-sim: queue_drop_ok\n");
  else
    Say("cfs-sim: queue_drop_FAIL\n");
  SayNum("cfs-sim: sb_sent=", cfs_sb_sent);
  SayNum("cfs-sim: evs_crit=", cfs_evs_count[CFS_EVS_CRITICAL]);
  Say("cfs-sim: done\n");
  return 0;
}
