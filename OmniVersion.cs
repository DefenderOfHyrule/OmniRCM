namespace OmniRCM;

public sealed class OmniVersion
{
    public int Major { get; }
    public int Minor { get; }
    public int Micro { get; }

    public OmniVersion(int major, int minor, int micro)
    {
        Major = major; Minor = minor; Micro = micro;
    }

    public bool NewerThan(OmniVersion v)
    {
        if (Major != v.Major) return Major > v.Major;
        if (Minor != v.Minor) return Minor > v.Minor;
        return Micro > v.Micro;
    }

    public override string ToString() => $"{Major}.{Minor}.{Micro}";

    public static OmniVersion? TryParse(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var parts = s.Split('.');
        if (parts.Length < 2) return null;
        if (!int.TryParse(parts[0], out int major)) return null;
        if (!int.TryParse(parts[1], out int minor)) return null;
        int micro = 0;
        if (parts.Length >= 3) int.TryParse(parts[2], out micro);
        return new OmniVersion(major, minor, micro);
    }
}
