// KThinSndStubs.HC — RV_THIN_LOADER: drop PC-speaker Snd/ScrnCast (~4.5 KiB).
// ASnd_RV/VirtioSnd gated; SoftCall never Beeps on thin Jump.
#ifndef K_THIN_SND_STUBS_HC
#define K_THIN_SND_STUBS_HC
U0 (*fp_snd_rv)(I8 ona);
F64 Ona2Freq(I8 ona)
{
  no_warn ona;
  return 0.0;
}

I8 Freq2Ona(F64 freq)
{
  no_warn freq;
  return 0;
}

U0 Snd(I8 ona = 0)
{
  no_warn ona;
}

Bool ScrnCast(Bool val = ON, Bool just_audio = FALSE, U8 *print_fmt = "B:/Tmp/%X.GR")
{
  no_warn val;
  no_warn just_audio;
  no_warn print_fmt;
  return FALSE;
}

U0 SndRst()
{
}

U0 Beep(I8 ona = 62, Bool busy = FALSE)
{
  no_warn ona;
  no_warn busy;
}

Bool Mute(Bool val)
{
  no_warn val;
  return FALSE;
}
#endif
