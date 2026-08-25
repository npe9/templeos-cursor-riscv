I64 tt() { try { throw(3); } catch { return except_ch + 4; } return 0; }
tt();
