I64 sw(I64 x){ switch [x] { case -1: return 2; case 'a': return 3; case 1...3: return 4; } return 0; }
I64 k(I64 a,I64){ a>>=2; a<<=1; a%=7; lock a++; return a; }
sw(-1)*1000+sw('a')*100+sw(2)*10+k(40,9);
