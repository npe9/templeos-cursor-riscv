Bool isalpha(I64 c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

Bool isdigit(I64 c) {
  return c >= '0' && c <= '9';
}

Bool isalnum(I64 c) {
  return isalpha(c) || isdigit(c);
}

