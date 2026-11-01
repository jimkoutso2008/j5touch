#!/bin/bash
# Install j5touch.sys into a WinPE boot.wim offline (WSL Debian / Linux).
# drvload refuses the INF without a signed catalog, so instead this copies the
# driver and pre-installs the service and the ACPI\J5TS0001 devnode in the
# image's SYSTEM hive. Needs: wimtools python3-hivex
#   bash install-bootwim.sh /path/to/sources/boot.wim [out/j5touch.sys]
set -e
WIM="$(realpath "$1")"
SYS="$(realpath "${2:-$(dirname "$0")/out/j5touch.sys}")"
[ -f "$WIM" ] && [ -f "$SYS" ] || { echo "usage: $0 boot.wim [j5touch.sys]"; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$W"
wimextract "$WIM" 1 /Windows/System32/config/SYSTEM --dest-dir=. --no-acls >/dev/null
cp SYSTEM SYSTEM.orig

python3 - <<'PY'
import hivex
HID_GUID = '{745a17a0-74d3-11d0-b6fe-00a0c90f57da}'
DESC = 'J5 2016 touchscreen (IST3038C)'
def sz(s):  return {'t': 1, 'value': (s + '\0').encode('utf-16le')}
def esz(s): return {'t': 2, 'value': (s + '\0').encode('utf-16le')}
def msz(l): return {'t': 7, 'value': ('\0'.join(l) + '\0\0').encode('utf-16le')}
def dw(n):  return {'t': 4, 'value': n.to_bytes(4, 'little')}
def setv(h, node, vals):
    h.node_set_values(node, [dict(v, key=k) for k, v in vals.items()])
def child(h, parent, name):
    return h.node_get_child(parent, name) or h.node_add_child(parent, name)

h = hivex.Hivex('SYSTEM', write=True)
cs = h.node_get_child(h.root(), 'ControlSet001')

svc = child(h, h.node_get_child(cs, 'Services'), 'j5touch')
setv(h, svc, {'Type': dw(1), 'Start': dw(3), 'ErrorControl': dw(1),
              'ImagePath': esz(r'\SystemRoot\System32\drivers\j5touch.sys'),
              'DisplayName': sz(DESC)})

cls = h.node_get_child(h.node_get_child(h.node_get_child(cs, 'Control'), 'Class'), HID_GUID)
drv = child(h, cls, '0000')
setv(h, drv, {'DriverDesc': sz(DESC), 'ProviderName': sz('j5xlte-edk2'),
              'DriverVersion': sz('1.0.0.0'), 'DriverDate': sz('11-1-2026'),
              'MatchingDeviceId': sz('acpi\\j5ts0001')})

inst = child(h, child(h, child(h, child(h, cs, 'Enum'), 'ACPI'), 'J5TS0001'), '0')
setv(h, inst, {'HardwareID': msz(['ACPI\\J5TS0001', '*J5TS0001']), 'DeviceDesc': sz(DESC),
               'Mfg': sz('j5xlte-edk2'), 'Service': sz('j5touch'), 'Class': sz('HIDClass'),
               'ClassGUID': sz(HID_GUID), 'Driver': sz(HID_GUID + '\\0000'),
               'ConfigFlags': dw(0), 'Capabilities': dw(0)})
h.commit(None)
print('SYSTEM hive updated')
PY

cp "$SYS" j5touch.sys
printf '%s\n' "add SYSTEM /Windows/System32/config/SYSTEM" \
              "add j5touch.sys /Windows/System32/drivers/j5touch.sys" | wimupdate "$WIM" 1
echo "Done. Copy $WIM to the SD card."
