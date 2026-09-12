// ASnd_RV.HC — RISC-V music/Play + Snd path for stock Apps (Span SongTask, Psalmody).
// Real Play note parse → Snd(ona); default per-note Yield (SongTask smoke-safe).
// Opt-in rv_snd_real_timing: RVJiffies wake_jiffy Sleep (TempleOS SleepUntil shape).
// PC speaker OutU8 is inert on virt — RVSnd fills a soft PCM ring + records ona;
// VirtioSnd TX when DeviceID 25 present. ScrnCast.record → queue CSndData for AUWrite.
#ifndef ASND_RV_HC
#define ASND_RV_HC
#define RV_SND_PCM_N 256
#define RV_SND_VIRTIO_ID 25
#define RV_SND_MAGIC 0x74726976
public class CMusicGlbls
{
  U8 *cur_song;
  CTask *cur_song_task;
  I64 octave;
  F64 note_len;
  U8 note_map[7];
  Bool mute;
  I64 meter_top, meter_bottom;
  F64 tempo, stacatto_factor;
  I64 play_note_num;
  F64 tM_correction, last_Beat, last_tM;
};
CMusicGlbls music = {NULL, NULL, 4, 1.0, {0, 2, 3, 5, 7, 8, 10}, FALSE, 4, 4, 2.5, 0.9, 0, 0, 0, 0};
I64 rv_snd_play_hits;
I64 rv_snd_rst_hits;
I64 rv_snd_ona_hits;
I64 rv_snd_note_hits;
I64 rv_snd_pcm_n;
I64 rv_snd_pcm_phase;
I64 rv_snd_pcm_tx_cursor;
I64 rv_snd_cur_ona;
I64 rv_snd_virtio_base;
I64 rv_snd_tx_ok;
Bool rv_snd_real_timing;
Bool rv_snd_jiffies_ready;
I16 rv_snd_pcm[RV_SND_PCM_N];
public U0 SndTaskEndCB()
{
  //Soft Adam SndTaskEndCB — mute via Snd; no Exit (HolyYield never TaskEnd).
  Snd;
}

public I8 Note2Ona(I64 note, I64 octave = 4)
{
  //Adam ASnd Note2Ona — Mid C is ona=51, note=3, octave=4.
  if (note < 3)
    return (octave + 1) * 12 + note;
  else
    return octave * 12 + note;
}

public I8 Ona2Note(I8 ona)
{
  return ona % 12;
}

public I8 Ona2Octave(I8 ona)
{
  I64 note = ona % 12, octave = ona / 12;
  if (note < 3)
    return octave - 1;
  else
    return octave;
}

public F64 tM()
{
  //Time in seconds synced to music — prefer RV jiffies when armed.
  return (ToF64(RVJiffies()) + music.tM_correction) / JIFFY_FREQ;
}

public U0 RVSndRealTiming(Bool on)
{
  //Opt-in wall-clock note waits. Default Play stays Yield-only (Span smoke-safe).
  rv_snd_real_timing = on;
  if (on && !rv_snd_jiffies_ready) {
    RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
    rv_snd_jiffies_ready = TRUE;
  }
}

public F64 Beat()
{
  F64 res, cur_tM;
  cur_tM = tM;
  res = music.last_Beat;
  if (music.tempo)
    res += (cur_tM - music.last_tM) * music.tempo;
  music.last_tM = cur_tM;
  music.last_Beat = res;
  return res;
}

U8 *MusicSetOctave(U8 *st)
{
  I64 ch;
  ch = *st++;
  while ('0' <= ch <= '9') {
    music.octave = ch - '0';
    ch = *st++;
  }
  return --st;
}

U8 *MusicSetMeter(U8 *st)
{
  I64 ch;
  ch = *st++;
  while (ch == 'M') {
    ch = *st++;
    if ('0' <= ch <= '9') {
      music.meter_top = ch - '0';
      ch = *st++;
    }
    if (ch == '/')
      ch = *st++;
    if ('0' <= ch <= '9') {
      music.meter_bottom = ch - '0';
      ch = *st++;
    }
  }
  return --st;
}

U8 *MusicSetNoteLen(U8 *st)
{
  Bool cont = TRUE;
  do {
    switch (*st++) {
      case 'w' :
      music.note_len = 4.0;
      break;
      case 'h' :
      music.note_len = 2.0;
      break;
      case 'q' :
      music.note_len = 1.0;
      break;
      case 'e' :
      music.note_len = 0.5;
      break;
      case 's' :
      music.note_len = 0.25;
      break;
      case 't' :
      music.note_len = 2.0 * music.note_len / 3.0;
      break;
      case '.' :
      music.note_len = 1.5 * music.note_len;
      break;
      default:
      st--;
      cont = FALSE;
    }
  } while (cont);
  return st;
}

U0 RVSndPcmFill(I8 ona)
{
  //Soft square-wave into ring (8 kHz) — UART pcm_n + optional VirtioSnd TX period.
  F64 freq, period;
  I64 i, half, s, idx, tx;
  if (!ona)
    return;
  freq = Ona2Freq(ona);
  if (freq < 1.0)
    return;
  period = 8000.0 / freq;
  half = ToI64(period / 2.0);
  if (half < 1)
    half = 1;
  for (i = 0; i < 32; i++) {
    if ((rv_snd_pcm_phase / half) & 1)
      s = 8000;
    else
      s = -8000;
    idx = rv_snd_pcm_n % RV_SND_PCM_N;
    rv_snd_pcm[idx] = s;
    rv_snd_pcm_n++;
    rv_snd_pcm_phase++;
  }
  if (virtio_snd_started && rv_snd_pcm_n >= VSND_PERIOD_BYTES / 2) {
    tx = VirtioSndTxFromRing(rv_snd_pcm, RV_SND_PCM_N, &rv_snd_pcm_tx_cursor);
    if (tx > 0)
      rv_snd_tx_ok = virtio_snd_tx_ok;
  }
}

public U0 RVSnd(I8 ona = 0)
{
  //RV Snd backend — replace PC-speaker OutU8; keep scrncast.ona for stock polls.
  // When scrncast.record (incl. just_audio), queue CSndData like stock Snd → AUWrite.
  CSndData *d;
  if (Bt(&sys_semas[SEMA_MUTE], 0))
    return;
  if (LBts(&sys_semas[SEMA_SND], 0))
    return;
  scrncast.ona = ona;
  rv_snd_cur_ona = ona;
  rv_snd_ona_hits++;
  if (ona)
    RVSndPcmFill(ona);
  if (!IsDbgMode && scrncast.record) {
    d = ACAlloc(sizeof(CSndData));
    if (d) {
      d->ona = ona;
      d->tS = tS;
      QueIns(d, scrncast.snd_head.last);
    }
  }
  LBtr(&sys_semas[SEMA_SND], 0);
}

I64 VirtioSndProbe()
{
  //DeviceID 25 slot — VirtioSndFind when Kernel VirtioSnd is linked.
  rv_snd_virtio_base = VirtioSndFind();
  return rv_snd_virtio_base;
}

U0 RVPlayNoteWait(F64 jiffy_len)
{
  //Default: one Yield per note (SongTask smoke-safe).
  // Opt-in: SleepUntil-shaped wait on RVJiffies (mtime), not cnts.jiffies.
  I64 n, wake;
  Bool old_idle;
  if (rv_snd_real_timing) {
    n = ToI64(jiffy_len);
    if (n < 1)
      n = 1;
    if (!rv_snd_jiffies_ready) {
      RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
      rv_snd_jiffies_ready = TRUE;
    }
    wake = RVJiffies() + n;
    if (Fs) {
      old_idle = LBts(&Fs->task_flags, TASKf_IDLE);
      Fs->wake_jiffy = wake;
      Yield;
      LBEqu(&Fs->task_flags, TASKf_IDLE, old_idle);
      //HolyYield skips wake_jiffy sleepers when armed; x86 Sched clears on restore.
      Fs->wake_jiffy = 0;
    }
    //Cooperative spin if Yield unwired / single-task; no-op once wake passed.
    while (RVJiffies() < wake)
      if (Fs)
        Yield;
    return;
  }
  no_warn jiffy_len;
  Yield;
}

public U0 MusicSettingsRst()
{
  music.octave = 4;
  music.note_len = 1.0;
  music.meter_top = 4;
  music.meter_bottom = 4;
  music.tempo = 2.5;
  music.stacatto_factor = 0.9;
  music.play_note_num = 0;
  music.last_Beat = 0.0;
  music.last_tM = tM;
  music.tM_correction = 0;
  SndRst;
  rv_snd_rst_hits++;
}

public U0 Play(U8 *st, U8 *words = NULL)
{
  //Stock ASnd Play note language → Snd; Yield or RVJiffies Sleep (rv_snd_real_timing).
  U8 *last_st, *word;
  I64 note, octave, i = 0, ona;
  Bool tie;
  F64 d, on_jiffies, off_jiffies;
  no_warn words;
  rv_snd_play_hits++;
  music.play_note_num = 0;
  while (st && *st) {
    tie = FALSE;
    do {
      last_st = st;
      if (*st == '(') {
        tie = TRUE;
        st++;
      } else {
        st = MusicSetMeter(st);
        st = MusicSetOctave(st);
        st = MusicSetNoteLen(st);
      }
    } while (st != last_st);
    if (!*st)
      break;
    note = *st++ - 'A';
    if (note < 7) {
      note = music.note_map[note];
      octave = music.octave;
      if (*st == 'b') {
        note--;
        if (note == 2)
          octave--;
        st++;
      } else if (*st == '#') {
        note++;
        if (note == 3)
          octave++;
        st++;
      }
      ona = Note2Ona(note, octave);
    } else
      ona = 0;
    if (words && (word = LstSub(i++, words)) && StrCmp(word, " "))
      "%s", word;
    d = JIFFY_FREQ *music.note_len / music.tempo;
    if (tie) {
      on_jiffies = d;
      off_jiffies = 0;
    } else {
      on_jiffies = d *music.stacatto_factor;
      off_jiffies = d * (1.0 - music.stacatto_factor);
    }
    if (!music.mute)
      Snd(ona);
    RVPlayNoteWait(on_jiffies);
    music.tM_correction += on_jiffies - ToI64(on_jiffies);
    if (!music.mute && !tie)
      Snd;
    if (off_jiffies > 0)
      RVPlayNoteWait(off_jiffies);
    music.tM_correction += off_jiffies - ToI64(off_jiffies);
    music.play_note_num++;
    rv_snd_note_hits++;
  }
}

public U8 *GodWordStr(I64 bits = 17)
{
  //Soft Adam/GodWordStr — Psalmody JukeBox reward text.
  no_warn bits;
  return StrNew("God");
}

public U8 *GodSongStr()
{
  //Soft Adam/GodSongStr — Psalmody random song insert.
  return StrNew("5qC");
}

U0 RVSndInstall()
{
  fp_snd_rv = &RVSnd;
  rv_snd_tx_ok = 0;
  rv_snd_pcm_tx_cursor = 0;
  //Best-effort PCM TX start when -device virtio-sound* present; else probe-only.
  if (VirtioSndProbe())
    VirtioSndInit();
}
RVSndInstall;
#endif
