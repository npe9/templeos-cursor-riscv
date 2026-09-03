// fw_cfg smoke: signature + file-dir without ramfb.
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVFwCfg.HC"
I64 main()
{
  I64 n, sel;
  RVUartInit();
  RVUartPutS("fwcfg-smoke: boot\n");
  if (!RVFwCfgBase()) {
    RVUartPutS("fwcfg-smoke: FAIL absent\n");
    return 1;
  }
  if (!RVFwCfgSigOk()) {
    RVUartPutS("fwcfg-smoke: FAIL sig\n");
    return 1;
  }
  n = RVFwCfgFileCount();
  if (n < 1) {
    RVUartPutS("fwcfg-smoke: FAIL empty dir\n");
    return 1;
  }
  sel = RVFwCfgFind("etc/no-such-fwcfg-file");
  if (sel >= 0) {
    RVUartPutS("fwcfg-smoke: FAIL phantom\n");
    return 1;
  }
  RVUartPutS("fwcfg-smoke: PASS\n");
  return 0;
}
