/*
 * j5diag.exe - why isn't j5touch.sys running? (WinPE has no event log,
 * sc.exe or pnputil, so ask Plug and Play and the kernel directly.)
 *
 *  1. CM_Get_DevNode_Status for ACPI\J5TS0001\0: status flags + problem code
 *     (the "Code NN" Device Manager would show).
 *  2. NtLoadDriver on the j5touch service: the exact NTSTATUS the kernel's
 *     image loader returns (0xC000010E = it is already loaded).
 *
 * No C runtime; output through WriteFile.
 */

#include <windows.h>

typedef LONG NTSTATUS;
typedef struct {
  USHORT Length;
  USHORT MaximumLength;
  PWSTR  Buffer;
} UNICODE_STRING_T;

__declspec(dllimport) NTSTATUS NTAPI NtLoadDriver(UNICODE_STRING_T *DriverServiceName);
__declspec(dllimport) NTSTATUS NTAPI RtlAdjustPrivilege(ULONG Privilege, BOOLEAN Enable, BOOLEAN Client, BOOLEAN *WasEnabled);
__declspec(dllimport) VOID NTAPI RtlInitUnicodeString(UNICODE_STRING_T *Dest, PCWSTR Source);

typedef DWORD DEVINST_T;
__declspec(dllimport) DWORD WINAPI CM_Locate_DevNodeW(DEVINST_T *DevInst, LPCWSTR DeviceId, ULONG Flags);
__declspec(dllimport) DWORD WINAPI CM_Get_DevNode_Status(ULONG *Status, ULONG *Problem, DEVINST_T DevInst, ULONG Flags);

#define SE_LOAD_DRIVER_PRIVILEGE 10
#define DN_DRIVER_LOADED         0x00000002
#define DN_STARTED               0x00000008
#define DN_HAS_PROBLEM           0x00000400

static HANDLE mOut;

static void Put(const char *S)
{
  DWORD Len = 0;
  DWORD Written;

  while (S[Len]) {
    Len++;
  }
  WriteFile(mOut, S, Len, &Written, NULL);
}

static void PutHex(ULONG V)
{
  char Buf[11];
  int  I;

  Buf[0] = '0';
  Buf[1] = 'x';
  for (I = 0; I < 8; I++) {
    Buf[2 + I] = "0123456789ABCDEF"[(V >> (28 - 4 * I)) & 0xF];
  }
  Buf[10] = 0;
  Put(Buf);
}

static void PutDec(ULONG V)
{
  char Buf[12];
  int  I = 11;

  Buf[I] = 0;
  do {
    Buf[--I] = (char)('0' + V % 10);
    V /= 10;
  } while (V && I > 0);
  Put(&Buf[I]);
}

void __cdecl mainCRTStartup(void)
{
  DEVINST_T        Dev;
  ULONG            Status  = 0;
  ULONG            Problem = 0;
  DWORD            Cr;
  BOOLEAN          Was;
  UNICODE_STRING_T Svc;
  NTSTATUS         Nt;

  mOut = GetStdHandle(STD_OUTPUT_HANDLE);
  Put("=== j5diag ===\r\n");

  Cr = CM_Locate_DevNodeW(&Dev, L"ACPI\\J5TS0001\\0", 0);
  Put("CM_Locate_DevNode ACPI\\J5TS0001\\0: CR ");
  PutDec(Cr);
  Put(Cr == 0 ? " (found)\r\n" : " (not found)\r\n");
  if (Cr == 0) {
    Cr = CM_Get_DevNode_Status(&Status, &Problem, Dev, 0);
    Put("  status ");
    PutHex(Status);
    Put(" driver-loaded ");
    PutDec((Status & DN_DRIVER_LOADED) != 0);
    Put(" started ");
    PutDec((Status & DN_STARTED) != 0);
    Put(" has-problem ");
    PutDec((Status & DN_HAS_PROBLEM) != 0);
    Put("\r\n  problem code ");
    PutDec(Problem);
    Put(" (Device Manager \"Code ");
    PutDec(Problem);
    Put("\")\r\n");
  }

  Nt = RtlAdjustPrivilege(SE_LOAD_DRIVER_PRIVILEGE, TRUE, FALSE, &Was);
  Put("SeLoadDriverPrivilege: ");
  PutHex((ULONG)Nt);
  Put("\r\n");

  RtlInitUnicodeString(&Svc, L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\j5touch");
  Nt = NtLoadDriver(&Svc);
  Put("NtLoadDriver(j5touch): ");
  PutHex((ULONG)Nt);
  if ((ULONG)Nt == 0) {
    Put(" = loaded now\r\n");
  } else if ((ULONG)Nt == 0xC000010E) {
    Put(" = was already loaded\r\n");
  } else {
    Put(" = kernel refused to load it\r\n");
  }

  ExitProcess(0);
}
