I64 Add3(I64 a,I64 b){ return a+b; }
I64 (*gfp)(I64,I64)=&Add3;
I64 c(){ I64 (*fp)(I64,I64)=&Add3; return (*fp)(3,4)*10+(*gfp)(1,2); }
c();
