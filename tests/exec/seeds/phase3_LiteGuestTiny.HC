I64 rv_menu_personal_n;
public U0 RVMenuPersonalInit(){rv_menu_personal_n=8;}
public I64 RVMenuPersonalCount(){if(!rv_menu_personal_n)RVMenuPersonalInit;return rv_menu_personal_n;}
public I64 RVMenuPersonalId(I64 i){return i+1;}
public U8 *RVMenuPersonalName(I64 i){return "X";}
public I64 RVMenuPersonalWidth(){return 12;}
