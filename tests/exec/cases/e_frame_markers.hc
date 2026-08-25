I64 F(U8 *dst,U8 *fmt){ U8 *p,**pp,buf[20000],buf2[100]; buf[19999]=3; buf2[99]=4; pp=&dst; if (!fmt) throw('x'); p=fmt; return (*pp==dst)*1000+buf[19999]*100+buf2[99]*10+(p[0]=='q')+sizeof(buf); }
F("a","q");
