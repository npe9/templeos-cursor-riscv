// Soft tip: DefineLstLoad Soft Call (stock DocInit ST_DOC_CMDS plant).
import I64 DefineLstLoad(U8 *dname, U8 *lst);
public I64 AdamLiteDocInitDefLstLoadProbe()
{
  DefineLstLoad("SOFT_ST_DOC_CMDS", "TX\0CR\0");
  return 1;
}
