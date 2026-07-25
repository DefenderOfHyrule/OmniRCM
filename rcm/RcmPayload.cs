namespace OmniRCM.Rcm;

public static class RcmPayload
{
    private static readonly byte[] Intermezzo =
    [
        0x5C, 0x00, 0x9F, 0xE5, 0x5C, 0x10, 0x9F, 0xE5, 0x5C, 0x20, 0x9F, 0xE5, 0x01, 0x20, 0x42, 0xE0,
        0x0E, 0x00, 0x00, 0xEB, 0x48, 0x00, 0x9F, 0xE5, 0x10, 0xFF, 0x2F, 0xE1, 0x00, 0x00, 0xA0, 0xE1,
        0x48, 0x00, 0x9F, 0xE5, 0x48, 0x10, 0x9F, 0xE5, 0x01, 0x29, 0xA0, 0xE3, 0x07, 0x00, 0x00, 0xEB,
        0x38, 0x00, 0x9F, 0xE5, 0x01, 0x19, 0xA0, 0xE3, 0x01, 0x00, 0x80, 0xE0, 0x34, 0x10, 0x9F, 0xE5,
        0x03, 0x28, 0xA0, 0xE3, 0x01, 0x00, 0x00, 0xEB, 0x20, 0x00, 0x9F, 0xE5, 0x10, 0xFF, 0x2F, 0xE1,
        0x04, 0x30, 0x91, 0xE4, 0x04, 0x30, 0x80, 0xE4, 0x04, 0x20, 0x52, 0xE2, 0xFB, 0xFF, 0xFF, 0x1A,
        0x1E, 0xFF, 0x2F, 0xE1,
        0x00, 0xF0, 0x00, 0x40,
        0x20, 0x00, 0x01, 0x40,
        0x7C, 0x00, 0x01, 0x40,
        0x00, 0x00, 0x01, 0x40,
        0x40, 0x0E, 0x01, 0x40,
        0x00, 0x70, 0x01, 0x40,
    ];

    private static readonly byte[] SpreadPattern = [0x00, 0x00, 0x01, 0x40];

    private const int MaxPayloadSize = 0x1ED58;
    private const int MaxTotalSize   = 0x30298;
    private const int PacketSize     = 0x1000;

    public enum PayloadType { Fusee, Hekate, TegraExplorer, Generic }

    public static PayloadType Detect(byte[] payload)
    {
        if (payload.Length < 5) return PayloadType.Generic;

        if (payload[0] == 0xDF && payload[1] == 0xF0 &&
            payload[2] == 0x2F && payload[3] == 0xE3)
            return PayloadType.Fusee;

        if (payload[0] == 0x08 && payload[1] == 0x00 &&
            payload[2] == 0x4F && payload[3] == 0xE2)
        {
            byte[] switchbrew = "switchbrew"u8.ToArray();
            int hekateLen = Math.Min(payload.Length, 0x500);
            for (int i = 0; i <= hekateLen - switchbrew.Length; i++)
                if (payload.AsSpan(i, switchbrew.Length).SequenceEqual(switchbrew))
                    return PayloadType.Hekate;
        }

        byte[] tePrintln = "println"u8.ToArray();
        for (int i = 0; i <= payload.Length - tePrintln.Length; i++)
            if (payload.AsSpan(i, tePrintln.Length).SequenceEqual(tePrintln))
                return PayloadType.TegraExplorer;

        return PayloadType.Generic;
    }

    public static byte[]? Build(byte[] userPayload, out string? error)
    {
        if (userPayload.Length > MaxPayloadSize)
        {
            error = $"Payload too large: {userPayload.Length:N0} bytes (max {MaxPayloadSize:N0})";
            return null;
        }
        if (userPayload.Length < 0x4000)
        {
            error = $"Payload too small: {userPayload.Length:N0} bytes (min {0x4000:N0})";
            return null;
        }

        int totalSize = 0x10E8 + userPayload.Length + 0x21C0;
        totalSize += PacketSize - (totalSize % PacketSize);
        if ((totalSize / PacketSize % 2) == 0)
            totalSize += PacketSize;

        if (totalSize > MaxTotalSize)
        {
            error = $"Computed buffer too large: 0x{totalSize:X} (max 0x{MaxTotalSize:X})";
            return null;
        }

        var payload = new byte[totalSize];

        payload[0] = 0x98; payload[1] = 0x02; payload[2] = 0x03;

        Intermezzo.CopyTo(payload, 0x2A8);

        Array.Copy(userPayload, 0, payload, 0x10E8, 0x4000);

        for (int i = 0; i < 0x870; i++)
            SpreadPattern.CopyTo(payload, 0x50E8 + i * 4);

        int remaining = userPayload.Length - 0x4000;
        if (remaining > 0)
            Array.Copy(userPayload, 0x4000, payload, 0x72A8, remaining);

        error = null;
        return payload;
    }
}
