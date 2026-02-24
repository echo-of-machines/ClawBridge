# silent-narrator-trigger.ps1 - Trigger accessibility via Narrator, silently
. "$PSScriptRoot\preamble.ps1"

# Use IAudioEndpointVolume COM to save/zero/restore master volume
if (-not ([System.Management.Automation.PSTypeName]'ClawBridgeAudio').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ClawBridgeAudio {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator {}

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    private interface IMMDeviceEnumerator {
        int NotImpl_EnumAudioEndpoints();
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    private interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr pParams,
                     [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
    }

    // IAudioEndpointVolume — full vtable with correct signatures
    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    private interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out uint pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
        int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    }

    private static IAudioEndpointVolume GetEndpointVolume() {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 1, out device);
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object obj;
        device.Activate(ref iid, 0x17, IntPtr.Zero, out obj);
        return (IAudioEndpointVolume)obj;
    }

    public static float GetVolume() {
        try {
            var vol = GetEndpointVolume();
            float level;
            vol.GetMasterVolumeLevelScalar(out level);
            return level;
        } catch (Exception ex) {
            Console.Error.WriteLine("GetVolume error: " + ex.Message);
            return -1f;
        }
    }

    public static bool SetVolume(float level) {
        try {
            var vol = GetEndpointVolume();
            Guid ctx = Guid.Empty;
            vol.SetMasterVolumeLevelScalar(level, ref ctx);
            return true;
        } catch (Exception ex) {
            Console.Error.WriteLine("SetVolume error: " + ex.Message);
            return false;
        }
    }
}
"@
}

# Save current volume and set to 0
$savedVolume = [ClawBridgeAudio]::GetVolume()
[ClawBridgeAudio]::SetVolume(0.0) | Out-Null

# Wait for volume change to fully propagate to audio stack
Start-Sleep -Seconds 1

# Start Narrator
$proc = Start-Process "Narrator.exe" -PassThru -ErrorAction SilentlyContinue
if (-not $proc) {
    if ($savedVolume -ge 0) { [ClawBridgeAudio]::SetVolume($savedVolume) | Out-Null }
    Write-Output "ERROR:NARRATOR_START_FAILED"
    exit 1
}

# Wait for accessibility tree to populate
Start-Sleep -Seconds 3

# Kill Narrator via Win+Ctrl+Enter system hotkey (Stop-Process gets Access Denied)
if (-not ([System.Management.Automation.PSTypeName]'ClawBridgeKeyboard').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ClawBridgeKeyboard {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const byte VK_LWIN = 0x5B;
    public const byte VK_CONTROL = 0x11;
    public const byte VK_RETURN = 0x0D;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    public static void SendWinCtrlEnter() {
        // Press Win+Ctrl+Enter (system Narrator toggle)
        keybd_event(VK_LWIN, 0, 0, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        keybd_event(VK_RETURN, 0, 0, UIntPtr.Zero);
        // Release all
        keybd_event(VK_RETURN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
"@
}

[ClawBridgeKeyboard]::SendWinCtrlEnter()

# Wait for Narrator to fully exit before restoring volume
$maxWait = 10
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Milliseconds 500
    $still = Get-Process -Name "Narrator" -ErrorAction SilentlyContinue
    if (-not $still) { break }
}

# Restore volume
if ($savedVolume -ge 0) {
    [ClawBridgeAudio]::SetVolume($savedVolume) | Out-Null
}

Write-Output "NARRATOR_DONE"
