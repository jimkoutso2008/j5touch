# j5touch (also sloppped to death (10 dolphins were sacrificed for this one))

Windows touchscreen driver for the **Samsung Galaxy J5 2016 (SM-J510, MSM8916)**,
for Windows 10 ARM64 (tested in WinPE 10586.1078.th2_bnb). It needs the
[edk2-msm8916-j5xlte](https://github.com/jimkoutso2008/edk2-msm8916-j5xlte) firmware,
whose DSDT provides the `ACPI\J5TS0001` device.

Windows has no I2C (BLSP QUP) or GPIO (TLMM) drivers for this SoC, so `j5touch.sys`
does it itself. It's a WDM HID minidriver that:
- maps the TLMM pages of four pins (from the DSDT's `TSC0` resources),
- bit-bangs I2C to the Imagis IST3038C (SDA GPIO 18, SCL GPIO 19, INT GPIO 13,
  VDD enable GPIO 108; register protocol from Linux `imagis.c`),
- polls from a system thread and reports touches as a **HID absolute mouse**
  (single touch: tap = click, drag = drag).

## Building (WSL Debian, no WDK)

```bash
sudo apt install clang lld llvm mingw-w64-common osslsigncode openssl python3
```

```bash
bash build.sh
```

Output goes to `out/`: `j5touch.sys` (test-signed with a self-signed certificate
generated on first build) and `j5diag.exe`. `bash build.sh debug` builds
`j5touch-debug.c` instead, which also draws start-up stage squares and touch dots
straight onto the framebuffer.

The build uses Debian's clang/lld and the mingw-w64 DDK headers, patched locally
for ARM64. Things that had to be exactly right before 10586 would load it:
- `KeStallExecutionProcessor` is imported from `hal.dll`, not `ntoskrnl.exe`.
- PE layout like Microsoft's ARM64 drivers: 64 KB section alignment, base
  `0x1C0000000`, OS/subsystem version 10.0, a `.reloc` section, non-paged sections
  (otherwise `STATUS_INVALID_ADDRESS`, 0xC0000018).
- 64-bit structure packing for `IO_STACK_LOCATION` and friends (mingw-w64's
  headers use 32-bit packing on non-x64, which caused `MULTIPLE_IRP_COMPLETE_REQUESTS`).

## Installing into WinPE

The BCD must have `testsigning on` (and, for 10586, `nointegritychecks on`).

`drvload` refuses the INF without a signed catalog (0xE000022F), so install it
offline into `boot.wim` instead (needs `wimtools python3-hivex`):

```bash
bash install-bootwim.sh "/mnt/e/path/to/sd card/sources/boot.wim"
```

This copies the driver to `System32\drivers` and pre-installs the `j5touch` service
and the `Enum\ACPI\J5TS0001\0` devnode in the image's SYSTEM hive.
On Windows, [`add-touch-driver-dism.cmd`](add-touch-driver-dism.cmd)
(`dism /Add-Driver /ForceUnsigned`) is the alternative.

## Troubleshooting
- The driver writes `DriverEntry`, `AddDevice`, `StartDevice`, `ThreadRunning` and
  `ChipId` under `HKLM\SYSTEM\CurrentControlSet\Services\j5touch`.
  `ChipId` 0x38c means the chip answered; 0xffffffff means no answer.
- [`touchdiag.cmd`](touchdiag.cmd) shows the devnode, driver and HID state in a loop.
- `j5diag.exe` prints the devnode problem code and the `NtLoadDriver` status
  (WinPE has no event log, `sc` or `pnputil` to tell you why a driver didn't load).
