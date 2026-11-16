namespace OmniRCM.Rcm;

public static class RcmInjector
{
    public enum Result
    {
        Success,
        DeviceNotFound,
        ReadIdFailed,
        PayloadBuildFailed,
        PayloadSendFailed,
        SwitchBufferFailed,
        PatchedV1,
        PatchedV2,
        SmashError,
        Cancelled,
    }

    public sealed class InjectionResult
    {
        public Result  Status   { get; init; }
        public string? DeviceId { get; init; }
        public string? Error    { get; init; }
        public bool    IsSuccess => Status == Result.Success;

        public string Summary() => Status switch
        {
            Result.Success            => $"Injection successful, device ID: {DeviceId}",
            Result.DeviceNotFound     => Error ?? DeviceNotFoundMessage(),
            Result.ReadIdFailed       => "Failed to read device ID. Try a different USB cable/port.",
            Result.PayloadBuildFailed => Error ?? "Failed to build RCM payload.",
            Result.PayloadSendFailed  => Error ?? "Payload transfer failed. Try a different USB cable or port.",
            Result.SwitchBufferFailed => "Failed to switch to high DMA buffer. Try a different USB port.",
            Result.PatchedV1          => "Console is patched (V1 patched console), this console is not exploitable via RCM.",
            Result.PatchedV2          => "Console is not exploitable via RCM (V2/Mariko console).",
            Result.SmashError         => Error ?? "Stack smash failed with an unexpected error.",
            Result.Cancelled          => "Injection cancelled.",
            _                         => "Unknown error."
        };
    }

    private const int SmashTimeoutSeconds = 10;

    private static bool _seenV1TimeoutAtF000;

    public static void ResetState()
    {
        _seenV1TimeoutAtF000 = false;
    }

    public static Task<InjectionResult> InjectAsync(
        string payloadPath, Action<string> log, CancellationToken ct = default)
        => Task.Run(() => Inject(payloadPath, log, ct), ct);

    private static InjectionResult Inject(
        string payloadPath, Action<string> log, CancellationToken ct)
    {
        byte[] userPayload;
        try
        {
            userPayload = File.ReadAllBytes(payloadPath);
            log($"Loaded: {Path.GetFileName(payloadPath)} ({userPayload.Length:N0} bytes)");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Fail(Result.PayloadBuildFailed, $"Cannot read file: {ex.Message}");
        }

        ct.ThrowIfCancellationRequested();

        byte[]? buf = RcmPayload.Build(userPayload, out string? buildErr);
        if (buf is null) return Fail(Result.PayloadBuildFailed, buildErr);

        int blocks = buf.Length / 0x1000;
        log($"Buffer built: {buf.Length:N0} bytes in {blocks} blocks");

        ct.ThrowIfCancellationRequested();

        log("Opening RCM device...");
        var (dev, openErr) = RcmDevice.TryOpenWithDiag();
        if (dev is null)
        {
            if (openErr is not null) return Fail(Result.DeviceNotFound, openErr);
            return new InjectionResult { Status = Result.DeviceNotFound };
        }
        using var _ = dev;

        ct.ThrowIfCancellationRequested();

        byte[]? idBuf = dev.ReadBytes(0x10);
        if (idBuf is null) return new InjectionResult { Status = Result.ReadIdFailed };
        string idHex = BitConverter.ToString(idBuf).Replace("-", "");
        log($"Device ID: {idHex}");

        ct.ThrowIfCancellationRequested();

        if (idHex.EndsWith("2101D0"))
        {
            log("\nThis device ID identifies as a Mariko (T214) console.");
            return new InjectionResult { Status = Result.PatchedV2, DeviceId = idHex };
        }

        log($"Sending payload ({blocks} blocks)...");

        if (OperatingSystem.IsWindows())
            dev.SetWriteTimeout(2000);

        const int MarikoStopOffset = 0x10000;

        for (int i = 0; i < blocks; i++)
        {
            ct.ThrowIfCancellationRequested();
            byte[] block = buf[(i * 0x1000)..((i + 1) * 0x1000)];
            int offset = i * 0x1000;

            int writeResult = dev.WriteSingleBlockResult(block, log);
            if (writeResult < 0)
            {
                bool isTimeout = writeResult == -2;
                bool isV1Signal = writeResult == -1;

                if (isV1Signal)
                    return new InjectionResult { Status = Result.PatchedV1, DeviceId = idHex };

                if (isTimeout && offset == 0xF000)
                {
                    _seenV1TimeoutAtF000 = true;
                    return new InjectionResult { Status = Result.PatchedV1, DeviceId = idHex };
                }

                if (isTimeout && offset == MarikoStopOffset)
                {
                    if (_seenV1TimeoutAtF000)
                        return new InjectionResult { Status = Result.PatchedV1, DeviceId = idHex };
                    if (idHex.EndsWith("01101062"))
                        return new InjectionResult { Status = Result.PatchedV1, DeviceId = idHex };
                    return new InjectionResult { Status = Result.PatchedV2, DeviceId = idHex };
                }

                string msg = i == 0
                    ? "First block rejected; console may be patched (V1), is not in RCM, or is experiencing a USB issue."
                    : $"Transfer failed at block {i + 1}/{blocks} ({i * 0x1000:N0} of {buf.Length:N0} bytes sent).\n" +
                      "This usually means a bad USB cable, port, or hub. Try: a direct port on the PC, a shorter cable, or a different USB-A/C cable.";
                return Fail(Result.PayloadSendFailed, msg);
            }

            if (offset == 0xF000)
                _seenV1TimeoutAtF000 = false;
        }
        log("Payload sent.");

        ct.ThrowIfCancellationRequested();

        if (!dev.SwitchToHighBuffer())
            return new InjectionResult { Status = Result.SwitchBufferFailed };

        ct.ThrowIfCancellationRequested();

        log($"Smashing the stack (timeout: {SmashTimeoutSeconds}s)...");

        using var smashCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        smashCts.CancelAfter(TimeSpan.FromSeconds(SmashTimeoutSeconds));

        SmashResult smash;
        try
        {
            smash = dev.SmashStack(log, smashCts.Token);
        }
        catch (OperationCanceledException)
        {
            smash = smashCts.IsCancellationRequested && !ct.IsCancellationRequested
                ? SmashResult.TimedOut
                : SmashResult.Error;
        }

        return smash switch
        {
            SmashResult.Success   => new InjectionResult { Status = Result.Success, DeviceId = idHex },
            SmashResult.PatchedV1 => new InjectionResult { Status = Result.PatchedV1, DeviceId = idHex },
            SmashResult.TimedOut  => new InjectionResult
            {
                Status   = (_seenV1TimeoutAtF000 || idHex.EndsWith("01101062"))
                    ? Result.PatchedV1
                    : Result.PatchedV2,
                DeviceId = idHex,
            },
            _                     => Fail(Result.SmashError, null),
        };
    }

    private static string DeviceNotFoundMessage()
    {
        string msg = "No Tegra RCM device found.\n" +
            "• If you just injected a payload, the console may be in a stale state. Unplug it, hold power for 13 seconds and re-enter RCM.\n" +
            "• Try a different USB cable or port to rule out USB stack errors.";

        if (OperatingSystem.IsWindows())
            msg += "\n• Make sure the APX device has the libusbK driver installed (use the Install Driver button or Zadig).";
        else if (OperatingSystem.IsLinux())
            msg += "\n• Make sure the udev rule is installed and active (run Setup udev)." +
                   "\n• A full reboot may be required (logging out is not always enough on some distros).";

        return msg;
    }

    private static InjectionResult Fail(Result s, string? msg) =>
        new() { Status = s, Error = msg };
}
