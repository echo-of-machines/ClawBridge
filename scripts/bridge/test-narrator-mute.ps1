# test-narrator-mute.ps1 - Set volume to 0, start Narrator, don't restore
. "$PSScriptRoot\preamble.ps1"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class TestAudio {
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
        var vol = GetEndpointVolume();
        float level;
        vol.GetMasterVolumeLevelScalar(out level);
        return level;
    }

    public static void SetVolume(float level) {
        var vol = GetEndpointVolume();
        Guid ctx = Guid.Empty;
        vol.SetMasterVolumeLevelScalar(level, ref ctx);
    }
}
"@

# Set volume to 0
$saved = [TestAudio]::GetVolume()
Write-Output "SAVED: $saved"
[TestAudio]::SetVolume(0.0)
Write-Output "SET TO 0: $([TestAudio]::GetVolume())"

# Wait for volume change to fully propagate
Start-Sleep -Seconds 1

# Start Narrator - volume stays at 0
Write-Output "STARTING NARRATOR (volume at 0, will NOT restore)"
Start-Process "Narrator.exe" -ErrorAction SilentlyContinue
Write-Output "DONE - listen for Narrator. Use Win+Ctrl+Enter to stop it."
Write-Output "To restore volume later: [TestAudio]::SetVolume($saved)"
