// Pointer arithmetic must scale by element size (p+1 for I64* is p+8).
I64 main(){
  I64 v[4]; v[0]=10;v[1]=20;v[2]=30;v[3]=40;
  I64 *p=v;
  return (*(p+1)==20)*1 + (*(p+3)==40)*2 + ((p+2)-p==2)*4 + (p[2]==30)*8 +
         (*(p+2)+sizeof(v)==62)*16;   // 0x1f if all correct
}
