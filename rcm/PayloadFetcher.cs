using System.IO.Compression;
using System.Net.Http;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using OmniRCM;

namespace OmniRCM.Rcm;

public sealed class RemotePayload
{
    public string Name       { get; set; } = "";
    public string CacheKey   { get; set; } = "";
    public string Repo       { get; set; } = "";
    public string? Version   { get; set; }
    public string? LocalPath { get; set; }

    public Func<string, bool>                          AssetFilter { get; set; } = _ => false;
    public Func<RemotePayload, string, Task<string>>?  PostProcess { get; set; }

    public bool IsDownloaded => LocalPath is not null && File.Exists(LocalPath);

    public string DisplayLabel => IsDownloaded
        ? $"{Name}  {(Version is not null ? "v" + Version : "")}"
        : $"{Name}  (not downloaded)";
}

public static class PayloadFetcher
{
    public static readonly string CacheDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "omnircm", "payloads");

    private static readonly HttpClient Http = new()
    {
        DefaultRequestHeaders = { { "User-Agent", "OmniRCM/payload-fetcher" } },
        Timeout = TimeSpan.FromSeconds(30)
    };

    public static readonly RemotePayload Fusee = new()
    {
        Name        = "fusee",
        CacheKey    = "fusee",
        Repo        = "Atmosphere-NX/Atmosphere",
        AssetFilter = name => name == "fusee.bin",
    };

    public static readonly RemotePayload Hekate = new()
    {
        Name        = "hekate",
        CacheKey    = "hekate",
        Repo        = "CTCaer/hekate",
        AssetFilter = name => name.StartsWith("hekate_ctcaer") && name.EndsWith(".zip"),
        PostProcess = (p, zip) => ExtractZipAsync(p, zip, "hekate_ctcaer*.bin"),
    };

    public static readonly RemotePayload TegraExplorer = new()
    {
        Name        = "TegraExplorer",
        CacheKey    = "tegraexplorer",
        Repo        = "suchmememanyskill/TegraExplorer",
        AssetFilter = name => name == "TegraExplorer.bin",
    };

    public static readonly RemotePayload[] BuiltIn = [Fusee, Hekate, TegraExplorer];

    private static List<RemotePayload> _custom = new();

    public static IReadOnlyList<RemotePayload> Custom => _custom;

    public static IEnumerable<RemotePayload> All => BuiltIn.Concat(_custom);

    public static void SetCustomSources(IEnumerable<CustomPayloadSource> sources)
    {
        var previous = _custom;
        _custom = sources.Select(BuildCustom).ToList();

        foreach (var updated in _custom)
        {
            var match = previous.FirstOrDefault(p => p.CacheKey == updated.CacheKey);
            if (match is null) continue;
            updated.Version   = match.Version;
            updated.LocalPath = match.LocalPath;
        }
    }

    private static RemotePayload BuildCustom(CustomPayloadSource src)
    {
        string cacheKey = "custom_" + SanitizeKey(src.Name);
        string match    = src.AssetMatch;

        var payload = new RemotePayload
        {
            Name        = src.Name,
            CacheKey    = cacheKey,
            Repo        = src.Repo,
            AssetFilter = name => MatchesAssetPattern(name, match),
        };

        if (src.IsZip)
        {
            string pattern = string.IsNullOrWhiteSpace(src.ZipInnerPattern) ? "*.bin" : src.ZipInnerPattern;
            payload.PostProcess = (p, zip) => ExtractZipAsync(p, zip, pattern);
        }

        return payload;
    }

    private static bool MatchesAssetPattern(string fileName, string pattern)
    {
        if (pattern.Contains('*') || pattern.Contains('?'))
            return Regex.IsMatch(fileName, WildcardToRegexPattern(pattern), RegexOptions.IgnoreCase);

        return fileName.Contains(pattern, StringComparison.OrdinalIgnoreCase);
    }

    private static string WildcardToRegexPattern(string pattern) =>
        "^" + Regex.Escape(pattern).Replace("\\*", ".*").Replace("\\?", ".") + "$";

    private static string SanitizeKey(string name)
    {
        string key = new string(name.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
        return string.IsNullOrEmpty(key) ? Guid.NewGuid().ToString("N")[..8] : key;
    }

    public static void LoadCached()
    {
        Directory.CreateDirectory(CacheDir);
        foreach (var p in All) TryRestoreFromCache(p);
    }

    public static async Task FetchAllAsync(Action<string> log, CancellationToken ct = default)
    {
        Directory.CreateDirectory(CacheDir);
        foreach (var payload in All)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                log($"Checking {payload.Name}...");
                await FetchOneAsync(payload, log, ct);
                log($"{payload.Name} {payload.Version ?? ""} ready.");
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { log($"[WARN] {payload.Name}: {ex.Message}"); }
        }
    }

    private static async Task FetchOneAsync(RemotePayload payload, Action<string> log, CancellationToken ct)
    {
        string json    = await Http.GetStringAsync($"https://api.github.com/repos/{payload.Repo}/releases/latest", ct);
        var    root    = JsonNode.Parse(json);
        string tag     = root?["tag_name"]?.GetValue<string>() ?? "";
        string version = tag.TrimStart('v', 'V');

        if (payload.Version == version && payload.IsDownloaded)
        { log($"  {payload.Name} already up to date ({tag})."); return; }

        string? dlUrl = null, assetName = null;
        foreach (var asset in root?["assets"]?.AsArray() ?? [])
        {
            string? name = asset?["name"]?.GetValue<string>();
            string? url  = asset?["browser_download_url"]?.GetValue<string>();
            if (name is null || url is null || !payload.AssetFilter(name)) continue;
            dlUrl = url; assetName = name; break;
        }

        if (dlUrl is null) { TryRestoreFromCache(payload); return; }

        log($"  Downloading {payload.Name} {tag}...");
        string tmpPath = Path.Combine(CacheDir, $"{payload.CacheKey}__{assetName}");
        await DownloadAsync(dlUrl, tmpPath, log, ct);

        string finalPath;
        if (payload.PostProcess is not null)
        {
            log($"  Extracting {payload.Name}...");
            finalPath = await payload.PostProcess(payload, tmpPath);
            try { File.Delete(tmpPath); } catch { }
        }
        else { finalPath = tmpPath; }

        payload.Version   = version;
        payload.LocalPath = finalPath;
        File.WriteAllText(VersionFile(payload), version);
        File.WriteAllText(LocalPathFile(payload), finalPath);
    }

    private static async Task DownloadAsync(string url, string dest, Action<string> log, CancellationToken ct)
    {
        using var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();
        long total = resp.Content.Headers.ContentLength ?? 0;
        await using var src = await resp.Content.ReadAsStreamAsync(ct);
        await using var dst = new FileStream(dest, FileMode.Create, FileAccess.Write);
        var buf = new byte[81920]; long received = 0; int lastPct = -1, read;
        while ((read = await src.ReadAsync(buf, ct)) > 0)
        {
            await dst.WriteAsync(buf.AsMemory(0, read), ct);
            received += read;
            if (total > 0) { int pct = (int)(received * 100 / total); if (pct / 10 != lastPct / 10) { log($"    {pct}%"); lastPct = pct; } }
        }
    }

    private static async Task<string> ExtractZipAsync(RemotePayload payload, string zipPath, string innerPattern)
    {
        string dir = Path.Combine(CacheDir, $"__{payload.CacheKey}_tmp__");
        if (Directory.Exists(dir)) Directory.Delete(dir, true);
        Directory.CreateDirectory(dir);
        ZipFile.ExtractToDirectory(zipPath, dir, overwriteFiles: true);

        string? bin = Directory.EnumerateFiles(dir, innerPattern, SearchOption.AllDirectories).FirstOrDefault()
                   ?? throw new FileNotFoundException($"No file matching \"{innerPattern}\" found in the downloaded archive.");

        string dest = Path.Combine(CacheDir, $"{payload.CacheKey}__{Path.GetFileName(bin)}");
        if (payload.LocalPath is not null && payload.LocalPath != dest && File.Exists(payload.LocalPath))
            try { File.Delete(payload.LocalPath); } catch { }

        File.Move(bin, dest, overwrite: true);

        try { Directory.Delete(dir, true); } catch { }
        await Task.CompletedTask;
        return dest;
    }

    private static void TryRestoreFromCache(RemotePayload payload)
    {
        string vf = VersionFile(payload);
        if (File.Exists(vf)) payload.Version = File.ReadAllText(vf).Trim();

        string lf = LocalPathFile(payload);
        if (File.Exists(lf))
        {
            string candidate = File.ReadAllText(lf).Trim();
            if (File.Exists(candidate)) payload.LocalPath = candidate;
        }
    }

    private static string VersionFile(RemotePayload p) =>
        Path.Combine(CacheDir, $"{p.CacheKey}.version");

    private static string LocalPathFile(RemotePayload p) =>
        Path.Combine(CacheDir, $"{p.CacheKey}.localpath");
}