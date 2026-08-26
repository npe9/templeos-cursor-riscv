// Two indirect calls through function-pointer members with DIFFERENT arities, in the same if/else
// (the kernel's PutS: `(*tmpk->put_s)(st)` vs `(*tmpk->put_key)(ch,0)`). The arg count of the
// second call must not overwrite the first's already-emitted CALL_INDIRECT — else the 1-arg call
// loads 2 args and the string argument lands in the wrong register.
class FP { Bool (*put_key)(I64 ch,I64 sc); Bool (*put_s)(U8 *st); };
U8 *cap_s; I64 cap_k;
Bool PS(U8 *st){ cap_s=st; return TRUE; }
Bool PK(I64 ch,I64 sc){ cap_k=ch; return TRUE; }
I64 got(FP *p,U8 *st,Bool use_s){
  if (use_s) { if ((*p->put_s)(st)) return 1; }
  else { I64 ch=*st; if ((*p->put_key)(ch,0)) return 2; }
  return 0;
}
I64 main(){
  FP f; f.put_s=&PS; f.put_key=&PK;
  U8 *msg="Z";
  got(&f,msg,TRUE);            // exercises put_s (1 arg)
  got(&f,"Q",FALSE);           // exercises put_key (2 args)
  return (cap_s==msg)*1 + (cap_k=='Q')*2 + (got(&f,msg,TRUE)==1)*4;   // 7
}
