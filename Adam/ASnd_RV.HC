// ASnd_RV.HC — soft Snd/Music shims so stock Apps (Span SongTask) #include.
// No PC speaker / NoteStash; Play is a no-op. Full Adam/ASnd deferred.
#ifndef ASND_RV_HC
#define ASND_RV_HC
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
public U0 SndTaskEndCB()
{
  //Soft Adam SndTaskEndCB — no hardware mute.
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

public U0 MusicSettingsRst()
{
  music.octave = 4;
  music.note_len = 1.0;
  music.meter_top = 4;
  music.meter_bottom = 4;
  music.tempo = 2.5;
  music.stacatto_factor = 0.9;
  music.play_note_num = 0;
  rv_snd_rst_hits++;
}

public U0 Play(U8 *st, U8 *words = NULL)
{
  //Soft Play — count only; Yield so stock SongTask while(TRUE) cooperates.
  no_warn st;
  no_warn words;
  rv_snd_play_hits++;
  Yield;
}

public U0 RVSndNote(I8 ona = 0)
{
  //Soft ona probe for Psalmody (stock Snd in KMisc is PC-speaker OutU8 no-op on RV).
  no_warn ona;
  rv_snd_ona_hits++;
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
#endif
