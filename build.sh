#!/bin/bash
# Build j5touch.sys (+ j5diag.exe) for Windows ARM64 with Debian's clang/lld,
# no WDK. Run in WSL Debian:  bash build.sh [debug]   (needs clang lld llvm
# mingw-w64-common osslsigncode openssl python3). Output goes to ./out.
# "debug" builds j5touch-debug.c, which also draws on the framebuffer.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
B=~/.cache/j5touch-build
DRV=j5touch.c; [ "$1" = debug ] && DRV=j5touch-debug.c
mkdir -p "$B" "$SRC/out" && cd "$B"

# --- mingw-w64 12's DDK headers know x86/amd64/arm32 only: local ARM64 copies
if [ ! -f ddk-arm64/wdm.h ]; then
  mkdir -p ddk-arm64
  cp /usr/share/mingw-w64/include/ddk/wdm.h /usr/share/mingw-w64/include/ddk/ntddk.h ddk-arm64/
  python3 - <<'PY'
p='ddk-arm64/wdm.h'; s=open(p).read()
o='#elif defined(_M_ARM)\n#include <armddk.h>\n'
s=s.replace(o,'#elif defined(__aarch64__)\n#include "arm64ddk.h"\n'+o)
# 64-bit structure packing (IO_STACK_LOCATION etc.), not the 32-bit pshpack4
s=s.replace('#if !defined(_AMD64_) && !defined(_IA64_)\n','#if !defined(_AMD64_) && !defined(_IA64_) && !defined(__aarch64__)\n')
s=s.replace('# if defined(_AMD64_)\n  _ANONYMOUS_UNION union {','# if defined(_AMD64_) || defined(__aarch64__)\n  _ANONYMOUS_UNION union {')
open(p,'w').write(s)
p='ddk-arm64/ntddk.h'; s=open(p).read()
s=s.replace('#elif defined(_M_ARM)\n#else\n#error Unknown Architecture','#elif defined(__aarch64__)\n#elif defined(_M_ARM)\n#else\n#error Unknown Architecture')
open(p,'w').write(s)
PY
  cat > ddk-arm64/arm64ddk.h <<'H'
/* Minimal ARM64 bits for mingw-w64 12's wdm.h */
#pragma once
#define PASSIVE_LEVEL   0
#define LOW_LEVEL       0
#define APC_LEVEL       1
#define DISPATCH_LEVEL  2
#define CLOCK_LEVEL     13
#define IPI_LEVEL       14
#define HIGH_LEVEL      15
#define PAGE_SIZE       0x1000
#define PAGE_SHIFT      12L
typedef ULONG PFN_COUNT;
typedef ULONG64 PFN_NUMBER, *PPFN_NUMBER;
typedef LONG64 SPFN_NUMBER, *PSPFN_NUMBER;
typedef struct _KFLOATING_SAVE { ULONG Dummy; } KFLOATING_SAVE, *PKFLOATING_SAVE;
#ifndef InterlockedExchangePointer
#define InterlockedExchangePointer _InterlockedExchangePointer
#endif
NTKERNELAPI KIRQL NTAPI KeGetCurrentIrql(VOID);
H
fi

# --- import libraries (checked against the WinPE 10586 binaries)
cat > ntoskrnl.def <<'DEF'
LIBRARY ntoskrnl.exe
EXPORTS
IoReleaseCancelSpinLock
IofCallDriver
IofCompleteRequest
KeAcquireSpinLockRaiseToDpc
KeReleaseSpinLock
KeInitializeEvent
KeSetEvent
KeWaitForSingleObject
MmMapIoSpace
MmUnmapIoSpace
ObReferenceObjectByHandle
ObfDereferenceObject
PoCallDriver
PoStartNextPowerIrp
PsCreateSystemThread
PsTerminateSystemThread
RtlWriteRegistryValue
ZwClose
memcpy
memset
DEF
printf 'LIBRARY hal.dll\nEXPORTS\nKeStallExecutionProcessor\n' > hal.def
printf 'LIBRARY hidclass.sys\nEXPORTS\nHidRegisterMinidriver\n' > hidclass.def
printf 'LIBRARY ntdll.dll\nEXPORTS\nNtLoadDriver\nRtlAdjustPrivilege\nRtlInitUnicodeString\n' > ntdll.def
printf 'LIBRARY cfgmgr32.dll\nEXPORTS\nCM_Locate_DevNodeW\nCM_Get_DevNode_Status\n' > cfgmgr32.def
printf 'LIBRARY kernel32.dll\nEXPORTS\nGetStdHandle\nWriteFile\nExitProcess\n' > kernel32.def
for l in ntoskrnl hal hidclass ntdll cfgmgr32 kernel32; do llvm-dlltool -m arm64 -d $l.def -l $l.lib; done

RES=$(clang -print-resource-dir)/include
KCFLAGS="--target=aarch64-w64-mingw32 -O2 -ffreestanding -fno-builtin -fno-stack-protector -fno-exceptions -fno-asynchronous-unwind-tables -nostdinc \
 -isystem $B/ddk-arm64 -isystem $RES -isystem /usr/share/mingw-w64/include -isystem /usr/share/mingw-w64/include/ddk \
 -D_KERNEL_MODE -DNTDDI_VERSION=0x0A000000 -D_WIN32_WINNT=0x0A00 -Wall -Wno-unknown-pragmas -Wno-missing-braces"

# --- driver: layout like Microsoft's ARM64 drivers (64K sections, 10.0, .reloc, non-paged)
clang $KCFLAGS -c "$SRC/$DRV" -o j5touch.o
lld-link /nologo /driver /subsystem:native,10.0 /osversion:10.0 /version:10.0 /entry:DriverEntry /machine:arm64 /nodefaultlib \
  /base:0x1C0000000 /align:0x10000 /filealign:0x200 /tsaware:no /release \
  /out:j5touch.sys j5touch.o ntoskrnl.lib hal.lib hidclass.lib
python3 - <<'PY'
import struct
p='j5touch.sys'; b=bytearray(open(p,'rb').read())
pe=struct.unpack_from('<I',b,0x3C)[0]; n=struct.unpack_from('<H',b,pe+6)[0]; opt=struct.unpack_from('<H',b,pe+20)[0]
for i in range(n):
    o=pe+24+opt+40*i
    if bytes(b[o:o+8]).rstrip(b'\0') in (b'.text',b'.rdata',b'.data'):
        struct.pack_into('<I',b,o+36,struct.unpack_from('<I',b,o+36)[0]|0x08000000)  # IMAGE_SCN_MEM_NOT_PAGED
open(p,'wb').write(b)
PY

# --- test signature (WinPE runs with testsigning on)
if [ ! -f testsign.key ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout testsign.key -out testsign.crt \
    -subj "/CN=j5xlte-edk2 test signing" -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1
fi
rm -f "$SRC/out/j5touch.sys"
osslsigncode sign -certs testsign.crt -key testsign.key -h sha256 -n "j5touch" -in j5touch.sys -out "$SRC/out/j5touch.sys"

# --- j5diag.exe: devnode problem code + NtLoadDriver status
clang --target=aarch64-w64-mingw32 -O2 -ffreestanding -fno-builtin -fno-stack-protector -fno-asynchronous-unwind-tables -nostdinc \
  -isystem $RES -isystem /usr/share/mingw-w64/include -D_WIN32_WINNT=0x0A00 -DUNICODE -Wall -c "$SRC/j5diag.c" -o j5diag.o
lld-link /nologo /subsystem:console,10.0 /osversion:10.0 /entry:mainCRTStartup /machine:arm64 /nodefaultlib \
  /out:"$SRC/out/j5diag.exe" j5diag.o ntdll.lib cfgmgr32.lib kernel32.lib
ls -la "$SRC/out"
