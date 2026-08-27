// A small interactive shell on RISC-V that ties the whole OS stack together: it reads command
// lines over the UART via the receive INTERRUPT, runs a preemptively-scheduled background clock
// task the whole time, and stores files on the virtio-blk device through the simple filesystem.
// Commands: ls | cat <f> | write <f> <text> | uptime | help | q. All in HolyC over the runtime.
#include "/Kernel/Kernel_RV.PRJ"
class FSEntry { U8 name[24]; U32 start_blk; U32 size; };
class FSSuper { U32 magic, count, next_free, pad; FSEntry ent[15]; };
U0 FSFormat(){ FSSuper *s=CAlloc(512,NULL); s->magic=0x52564653; s->count=0; s->next_free=1; RVBlkWrite(0,s); }
I64 FSCreate(U8 *name, U8 *data, I64 len){
  FSSuper *s=CAlloc(512,NULL); RVBlkRead(0,s);
  if (s->count>=15) return -1;
  I64 blocks=(len+511)/512, i; if (blocks<1) blocks=1;
  FSEntry *e=&s->ent[s->count]; StrCpy(e->name,name); e->start_blk=s->next_free; e->size=len;
  U8 *blk=CAlloc(512,NULL);
  for (i=0;i<blocks;i++){ I64 j; for(j=0;j<512;j++) blk[j]=(i*512+j<len)?data[i*512+j]:0; RVBlkWrite(s->next_free+i,blk); }
  s->next_free+=blocks; s->count++; RVBlkWrite(0,s); return 0;
}
I64 FSRead(U8 *name, U8 *buf){
  FSSuper *s=CAlloc(512,NULL); RVBlkRead(0,s); I64 i;
  for (i=0;i<s->count;i++) if (StrCmp(s->ent[i].name,name)==0){
    I64 blocks=(s->ent[i].size+511)/512, b; if(blocks<1)blocks=1;
    for (b=0;b<blocks;b++){ U8 *t=CAlloc(512,NULL); RVBlkRead(s->ent[i].start_blk+b,t); I64 j; for(j=0;j<512;j++) buf[b*512+j]=t[j]; }
    return s->ent[i].size;
  }
  return -1;
}
U0 FSList(){ FSSuper *s=CAlloc(512,NULL); RVBlkRead(0,s); I64 i; Print("%d file(s):\n", s->count);
  for (i=0;i<s->count;i++) Print("  %s  %d bytes\n", s->ent[i].name, s->ent[i].size); }

I64 ticks_bg=0;
U0 clock_task(){ while (TRUE){ ticks_bg++; I64 s=0; while(s<40000)s++; } }

I64 ReadLine(U8 *buf, I64 max){
  I64 n=0;
  while (n<max-1){
    while (!RVUartHasInput()){}
    I64 c=RVUartGetBuffered();
    if (c=='\r' || c=='\n'){ Print("\n"); break; }
    if (c==8 || c==127){ if (n>0){ n--; Print("\b \b"); } continue; }
    buf[n]=c; n++;
    U8 e[2]; e[0]=c; e[1]=0; Print("%s", e);
  }
  buf[n]=0; return n;
}
I64 main(){
  RVKernelInit();
  if (RVBlkInit()) { Print("no disk\n"); return 1; }
  FSSuper *sb=CAlloc(512,NULL); RVBlkRead(0,sb);
  if (sb->magic != 0x52564653) FSFormat();
  U8 *bgstk=CAlloc(16384,NULL);
  RVPreemptInit(300000);
  RVPreemptSpawn(&clock_task,(bgstk+16384-16)&(~15));
  RVUartIrqInit();
  Print("RISC-V/HolyC shell. commands: ls | cat <f> | write <f> <text> | uptime | help | q\n");
  U8 line[128], *buf=CAlloc(2048,NULL);
  while (TRUE){
    Print("$ ");
    ReadLine(line,128);
    if (line[0]==0) continue;
    if (StrCmp(line,"q")==0){ Print("bye\n"); break; }
    if (StrCmp(line,"help")==0){ Print("ls, cat <f>, write <f> <text>, uptime, help, q\n"); continue; }
    if (StrCmp(line,"ls")==0){ FSList(); continue; }
    if (StrCmp(line,"uptime")==0){ Print("background ticks=%d\n", ticks_bg); continue; }
    if (StrNCmp(line,"cat ",4)==0){ I64 n=FSRead(line+4,buf); if (n<0) Print("no such file\n"); else { buf[n]=0; Print("%s\n", buf); } continue; }
    if (StrNCmp(line,"write ",6)==0){
      U8 *p=line+6, *name=p;
      while (*p && *p!=' ') p++;
      if (*p==' '){ *p=0; p++; FSCreate(name,p,StrLen(p)); Print("wrote %s (%d bytes)\n", name, StrLen(p)); }
      else Print("usage: write <f> <text>\n");
      continue;
    }
    Print("unknown command: %s\n", line);
  }
  return 0;
}
