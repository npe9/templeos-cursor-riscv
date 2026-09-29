// Morse() — a different letter blinking on each LED, all at once.
//
// The Unmatched's PWM channels reach LEDs (measured: driving a channel brightens one), but nothing
// documents which is which, so the useful thing is to make each channel say something distinct.
// Timing is the conventional one: dash = 3 dots, gap between elements = 1 dot, gap between letters
// = 3 dots. The wait is a CLINT busy-loop -- the prompt is blocked while this runs, which is fine
// for a few seconds of blinking and avoids depending on a timer interrupt.
#ifndef RV_MORSE_UI_HC
#define RV_MORSE_UI_HC
#help_index "Dbg"
#define RV_MORSE_UNIT_MS 500   /* a dot you can read across a room; 160 was too quick to catch */
#define RV_MORSE_MAX     64

U8 *MorsePattern(I64 c)
{
  //Dots and dashes for A-Z and 0-9; anything else blinks nothing.
  if (c >= 'a' && c <= 'z')
    c = c - 'a' + 'A';
  switch (c) {
    case 'A': return ".-";      case 'B': return "-...";    case 'C': return "-.-.";
    case 'D': return "-..";     case 'E': return ".";       case 'F': return "..-.";
    case 'G': return "--.";     case 'H': return "....";    case 'I': return "..";
    case 'J': return ".---";    case 'K': return "-.-";     case 'L': return ".-..";
    case 'M': return "--";      case 'N': return "-.";      case 'O': return "---";
    case 'P': return ".--.";    case 'Q': return "--.-";    case 'R': return ".-.";
    case 'S': return "...";     case 'T': return "-";       case 'U': return "..-";
    case 'V': return "...-";    case 'W': return ".--";     case 'X': return "-..-";
    case 'Y': return "-.--";    case 'Z': return "--..";
    case '0': return "-----";   case '1': return ".----";   case '2': return "..---";
    case '3': return "...--";   case '4': return "....-";   case '5': return ".....";
    case '6': return "-....";   case '7': return "--...";   case '8': return "---..";
    case '9': return "----.";
  }
  return "";
}

I64 MorseSchedule(I64 c, U8 *slots, I64 cap)
{
  //Expand a letter into one on/off flag per time unit. Returns how many units it used.
  U8 *p = MorsePattern(c);
  I64 n = 0, i;
  while (*p && n < cap - 4) {
    i = 0;
    while (i < 3) {
      slots[n++] = 1;
      if (*p == '.')
        break;
      i++;
    }
    slots[n++] = 0;          // one unit of gap after every element
    p++;
  }
  slots[n++] = 0;            // ...and two more make the three-unit letter gap
  slots[n++] = 0;
  return n;
}

U0 MorseWaitMs(I64 ms)
{
  I64 deadline = *(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF) + ms * (CONFIG_TIMEBASE_FREQ / 1000);
  while (*(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF) < deadline)
    ;
}

U0 Led(I64 r = 0, I64 g = 0, I64 b = 0)
{
  //Set the RGB LED directly: Led(255,0,0) red, Led(0,255,0) green, Led(0,0,255) blue, Led(0,0,0) off.
  if (!RVPwmBase) {
    Print("Led: no PWM on this board\n");
    return;
  }
  RVPwmSet(RV_LED_RED, r);
  RVPwmSet(RV_LED_GREEN, g);
  RVPwmSet(RV_LED_BLUE, b);
}

U0 Blink(I64 ch = 1, I64 times = 10)
{
  //The simplest possible test: one channel, half a second on, half a second off.
  I64 i = 0;
  if (!RVPwmBase) {
    Print("Blink: no PWM on this board\n");
    return;
  }
  Print("Blink: channel %d, %d times at 1 Hz\n", ch, times);
  while (i < times) {
    RVPwmSet(ch, 255);
    MorseWaitMs(500);
    RVPwmSet(ch, 0);
    MorseWaitMs(500);
    i++;
  }
  RVPwmOff;
}

U0 Morse(I64 c1 = 'T', I64 c2 = 'E', I64 c3 = 'M', I64 reps = 3, I64 unit = RV_MORSE_UNIT_MS)
{
  //Blink c1 on PWM channel 1, c2 on 2, c3 on 3 — simultaneously, `reps` times.
  U8 s1[RV_MORSE_MAX], s2[RV_MORSE_MAX], s3[RV_MORSE_MAX];
  I64 n1, n2, n3, longest, i, r;
  if (!RVPwmBase) {
    Print("Morse: no PWM on this board\n");
    return;
  }
  n1 = MorseSchedule(c1, s1, RV_MORSE_MAX);
  n2 = MorseSchedule(c2, s2, RV_MORSE_MAX);
  n3 = MorseSchedule(c3, s3, RV_MORSE_MAX);
  longest = n1;
  if (n2 > longest)
    longest = n2;
  if (n3 > longest)
    longest = n3;
  Print("Morse: green %c=%s  red %c=%s  blue %c=%s   (%d units of %d ms, %d times)\n",
        c1, MorsePattern(c1), c2, MorsePattern(c2), c3, MorsePattern(c3),
        longest, unit, reps);
  r = 0;
  while (r < reps) {
    i = 0;
    while (i < longest) {
      // Each channel repeats its own letter independently, so three different-length letters stay
      // in step with themselves rather than being padded to the longest one.
      RVPwmSet(1, s1[i % n1] * 255);
      RVPwmSet(2, s2[i % n2] * 255);
      RVPwmSet(3, s3[i % n3] * 255);
      MorseWaitMs(unit);
      i++;
    }
    r++;
  }
  RVPwmSet(1, 0);
  RVPwmSet(2, 0);
  RVPwmSet(3, 0);
  RVPwmOff;
}
#endif
