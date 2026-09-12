// The other half of the `_start` entry contract: a unit with no top-level statements must not
// grow an `__init_globals` chunk or have its `_start` call retargeted. Only definitions here,
// so `_start` still calls Two() directly.
// ORACLE 0000000000000002.
I64 Two()
{
  return 2;
}

asm {
	_start::
	mv	s0, ra
	call	Two
	mv	ra, s0
	ret
}
