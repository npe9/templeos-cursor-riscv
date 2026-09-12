#exe {Cd(__DIR__);};
#include "DskStrA"
#include "DskCache"
#ifdef RV_THIN_LOADER
#include "DskFatAtaStubs_RV" // no-op FAT/ATA/ISO — SoftCall is RedSea+virtio only
#else
#include "DskATA"
#include "DskATAId"
#endif
#include "DskBlkDev"
#include "DskDrv"
#include "DskBlk"
#include "DskClus"
#include "DskStrB"
#include "DskAddDev"
#include "DskDirA"
#include "FileSysRedSea"
#ifndef RV_THIN_LOADER
#include "FileSysFAT"
#endif
#include "FileSys9P_RV" // G28: FSt_9P FileRead/FilesFind/Cd via soft P:
#include "DskDirContext"
#include "DskFind"
#include "DskDirB"
#include "DskFile"
#include "DskCFile"
#include "DskCopy"
#ifndef RV_THIN_LOADER
#include "DskCDDVD"
#endif
#include "DskFmt"
#exe {Cd("..");};
