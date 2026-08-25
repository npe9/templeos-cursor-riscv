I64 Sum(I64 n,...){ I64 i,s=n; for (i=0;i<argc;i++) s+=argv[i]; return s; }
Sum(1,2,3)*10+Sum(4);
