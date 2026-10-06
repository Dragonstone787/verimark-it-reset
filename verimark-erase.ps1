<#
.SYNOPSIS
    Erases all fingerprints stored on a Kensington VeriMark IT fingerprint key.

.DESCRIPTION
    Sends the Synaptics driver's vendor "EraseDatabase" IOCTL (0x442028) directly to the sensor.
    The code was found by disassembling the official driver (synaWudfBioUsb123.dll,
    CBiometricDevice::OnEraseDatabase). Windows never sends this IOCTL itself.

    The Windows Biometric Service holds the sensor exclusively, so it is stopped while the
    IOCTL is sent and started again afterwards.

    Unofficial. Use at your own risk. This deletes EVERY fingerprint stored on the key.

.PARAMETER Force
    Skip the confirmation prompt and the driver version check.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verimark-erase.ps1
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'

# Hardware IDs handled by the Synaptics driver package this was tested with.
$SupportedIds    = @('vid_047d&pid_8054', 'vid_06cb&pid_00d6')
$TestedDriver    = '6.0.25.1123'
$IoctlEraseDb    = 0x442028

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run this script in an Administrator PowerShell.'
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class Bio {
    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid g; public int Flags; public IntPtr Reserved; }

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int flags);
    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, int size, out int req, IntPtr dev);
    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, int inSize, byte[] outBuf, int outSize, out int ret, IntPtr ov);

    // GUID_DEVINTERFACE_BIOMETRIC_READER
    static Guid BioGuid = new Guid("E2B5183A-99EA-4cc3-AD6B-80CA8D715B80");

    public static string FindPath(string match) {
        IntPtr set = SetupDiGetClassDevs(ref BioGuid, IntPtr.Zero, IntPtr.Zero, 0x12); // PRESENT | DEVICEINTERFACE
        try {
            for (int i = 0; ; i++) {
                var d = new SP_DEVICE_INTERFACE_DATA(); d.cbSize = Marshal.SizeOf(d);
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref BioGuid, i, ref d)) return null;
                int req; SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out req, IntPtr.Zero);
                IntPtr buf = Marshal.AllocHGlobal(req);
                try {
                    Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
                    if (SetupDiGetDeviceInterfaceDetail(set, ref d, buf, req, out req, IntPtr.Zero)) {
                        string p = Marshal.PtrToStringUni(buf + 4);
                        if (p.ToLower().Contains(match)) return p;
                    }
                } finally { Marshal.FreeHGlobal(buf); }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
    }

    public static string Ioctl(string path, uint code) {
        using (var h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) return "CreateFile failed, Win32 error " + Marshal.GetLastWin32Error();
            byte[] o = new byte[64]; int ret;
            bool ok = DeviceIoControl(h, code, null, 0, o, o.Length, out ret, IntPtr.Zero);
            return ok ? "OK (" + ret + " bytes returned)" : "DeviceIoControl failed, Win32 error " + Marshal.GetLastWin32Error();
        }
    }
}
'@

$path = $SupportedIds | ForEach-Object { [Bio]::FindPath($_) } | Where-Object { $_ } | Select-Object -First 1
if (-not $path) { throw 'No supported fingerprint key found. Is it plugged in and is the official driver installed?' }
"Device: $path"

$driver = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $hw = "$($_.HardWareID)".ToLower(); $_.DeviceClass -eq 'BIOMETRIC' -and ($SupportedIds | Where-Object { $hw.Contains($_) }) } | Select-Object -First 1
"Driver: $($driver.DriverProviderName) $($driver.DriverVersion)"
if ($driver.DriverVersion -ne $TestedDriver -and -not $Force) {
    throw "Only tested with driver $TestedDriver. Re-run with -Force to try anyway."
}

if (-not $Force) {
    $answer = Read-Host 'This deletes ALL fingerprints stored on the key. Type YES to continue'
    if ($answer -ne 'YES') { 'Aborted.'; return }
}

'Stopping Windows Biometric Service...'
Stop-Service WbioSrvc -Force
Start-Sleep -Seconds 2

try {
    'Sending EraseDatabase (0x442028)...'
    [Bio]::Ioctl($path, $IoctlEraseDb)
} finally {
    'Starting Windows Biometric Service...'
    Start-Service WbioSrvc
}
'Done. Unplug the key, wait 5 seconds, plug it back in, then set up the fingerprint again in Settings.'
