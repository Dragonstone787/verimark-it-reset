# VeriMark IT reset

**This wipes all fingerprints currently stored on the reader.**

Fix for the Kensington VeriMark IT fingerprint key when Windows Hello won't add a fingerprint.

Unofficial, use at your own risk.

## Black screen after entering the PIN

Your Windows Hello data is probably broken. Make sure you know your account password, because this removes your PIN.

1. Open PowerShell (not as admin) and run:
   ```powershell
   certutil -DeleteHelloContainer
   ```
2. Sign out and sign back in with your password.
3. Set up a new PIN in Settings > Accounts > Sign-in options.
4. Set up your fingerprint again.

## "Storage full"

The key stores fingerprints on itself. If you reinstall Windows without removing your fingerprint first, it stays on the key and can't be deleted from Windows anymore.

`verimark-erase.ps1` wipes all fingerprints from the key. Not fully tested yet, feedback welcome.

Plug in the key and run this in PowerShell as admin:

```powershell
powershell -ExecutionPolicy Bypass -File .\verimark-erase.ps1
```

Then unplug the key, plug it back in and set up your fingerprint again.

Works with:
- Kensington VeriMark IT (`USB\VID_047D&PID_8054`)
- Synaptics `USB\VID_06CB&PID_00D6` (same sensor, untested)

Tested with driver 6.0.25.1123. Other VeriMark models won't work.

## How it works

The official driver has a built-in erase command (`0x442028`) that Windows never uses. The script sends it directly to the key.
