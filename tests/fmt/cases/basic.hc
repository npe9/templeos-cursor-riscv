// intentionally ugly — spaces around ops, bad indent, cramped control
#include "Foo.HH"
#define N 3
U0  Demo ( I64 a , I64 b ) {
I64 i , s = 0 ;
if( a ) {
s = a + b ;
} else if ( b ) s = b ; else s = 0 ;
for ( i = 0 ; i < N ; i ++ )
s = s + i ;
while ( s > 10 ) s = s - 1 ;
try {
Foo ;
} catch {
Fs -> catch_except = TRUE ;
}
asm {
HcNop::
	nop
	ret
}
}
Demo ;
