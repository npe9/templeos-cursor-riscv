// Test goto and labels
I64 TestGoto(I64 x) {
  if (x < 0) {
    goto error_label;
  }
  
  return x * 2;
  
error_label:
  return -1;
}

I64 TestLoop() {
  I64 i = 0;
  I64 sum = 0;
  
loop_start:
  if (i >= 10) {
    goto done;
  }
  sum = sum + i;
  i = i + 1;
  goto loop_start;
  
done:
  return sum;
}
