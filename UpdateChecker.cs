using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;

namespace OmniRCM;

public static class UpdateChecker
{
    private const string ApiUrl = "https://api.github.com/repos/DefenderOfHyrule/OmniRCM/releases/latest";

    public sealed record UpdateInfo(
        OmniVersion LatestVersion,
        string      AssetName,
        string      DownloadUrl,
        long        AssetSize);

    public static string DetectRid()
    {
        string? builtRid = AppContext.GetData("RUNTIME_IDENTIFIER") as string;
        if (!string.IsNullOrEmpty(builtRid))
            return builtRid;

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return "win-x64";

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            return "osx";

        return RuntimeInformation.ProcessArchitecture == Architecture.Arm64
            ? "linux-arm64"
            : "linux-x64";
    }

    public static async Task<UpdateInfo?> CheckAsync(OmniVersion currentVersion, CancellationToken ct = default)
    {
        try
        {
            using var http = new HttpClient();
            http.DefaultRequestHeaders.Add("User-Agent", $"OmniRCM/{currentVersion}");
            http.Timeout = TimeSpan.FromSeconds(10);

            string json = await http.GetStringAsync(ApiUrl, ct);
            var root = JsonNode.Parse(json);
            if (root is null) return null;

            string? tagName = root["tag_name"]?.GetValue<string>();
            if (string.IsNullOrEmpty(tagName)) return null;

            string cleaned = tagName.TrimStart('v', 'V');
            OmniVersion? latest = OmniVersion.TryParse(cleaned);
            if (latest is null) return null;

            if (!latest.NewerThan(currentVersion)) return null;

            string rid            = DetectRid();
            string expectedPrefix = $"OmniRCM-{rid}";

            var assets = root["assets"]?.AsArray();
            if (assets is null) return null;

            UpdateInfo? archiveMatch    = null;
            UpdateInfo? executableMatch = null;

            foreach (var asset in assets)
            {
                string? name = asset?["name"]?.GetValue<string>();
                string? url  = asset?["browser_download_url"]?.GetValue<string>();
                long    size = asset?["size"]?.GetValue<long>() ?? 0L;

                if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(url)) continue;
                if (!name.StartsWith(expectedPrefix, StringComparison.OrdinalIgnoreCase)) continue;

                bool isArchive = name.EndsWith(".zip",    StringComparison.OrdinalIgnoreCase)
                              || name.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase)
                              || name.EndsWith(".gz",     StringComparison.OrdinalIgnoreCase);

                var info = new UpdateInfo(latest, name, url, size);
                if (isArchive)
                    archiveMatch ??= info;
                else
                    executableMatch ??= info;
            }

            return executableMatch ?? archiveMatch;
        }
        catch (OperationCanceledException) { return null; }
        catch                              { return null; }
    }

    public static async Task DownloadAndInstallAsync(
        UpdateInfo        info,
        Action<int>       progressCallback,
        CancellationToken ct = default)
    {
        string exePath = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine the running executable path.");

        string dir = exePath.Contains(".app/Contents/MacOS")
            ? Path.GetFullPath(Path.Combine(Path.GetDirectoryName(exePath)!, "..", "..", ".."))
            : Path.GetDirectoryName(exePath)!;

        string tmpBase = Path.Combine(Path.GetTempPath(), "omnircm_update");
        Directory.CreateDirectory(tmpBase);
        string tmpFile = Path.Combine(tmpBase, "__omnircm_update_download__");

        using var http = new HttpClient();
        http.DefaultRequestHeaders.Add("User-Agent", "OmniRCM/update");
        http.Timeout = TimeSpan.FromMinutes(10);

        using var response = await http.GetAsync(
            info.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();

        long total = response.Content.Headers.ContentLength ?? info.AssetSize;

        await using (var fs  = new FileStream(tmpFile, FileMode.Create, FileAccess.Write, FileShare.None))
        await using (var src = await response.Content.ReadAsStreamAsync(ct))
        {
            var  buffer     = new byte[81920];
            long downloaded = 0;
            int  read;
            while ((read = await src.ReadAsync(buffer, ct)) > 0)
            {
                await fs.WriteAsync(buffer.AsMemory(0, read), ct);
                downloaded += read;
                if (total > 0) progressCallback((int)(downloaded * 100 / total));
            }
        }
        progressCallback(100);

        bool isArchive = info.AssetName.EndsWith(".zip",    StringComparison.OrdinalIgnoreCase)
                      || info.AssetName.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase)
                      || info.AssetName.EndsWith(".gz",     StringComparison.OrdinalIgnoreCase);

        if (!isArchive)
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                using var chmod = System.Diagnostics.Process.Start(
                    new System.Diagnostics.ProcessStartInfo("chmod", $"+x \"{tmpFile}\"")
                    { UseShellExecute = false })!;
                await chmod.WaitForExitAsync(ct);
            }

            string backupPath = exePath + ".old";
            if (File.Exists(backupPath)) File.Delete(backupPath);
            File.Move(exePath, backupPath);
            File.Move(tmpFile, exePath);
            try { File.Delete(backupPath); } catch { }
            return;
        }

        string extractDir = Path.Combine(tmpBase, "__omnircm_update_extract__");
        if (Directory.Exists(extractDir)) Directory.Delete(extractDir, true);
        Directory.CreateDirectory(extractDir);

        try
        {
            if (info.AssetName.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                System.IO.Compression.ZipFile.ExtractToDirectory(tmpFile, extractDir, overwriteFiles: true);
            }
            else
            {
                var psi = new System.Diagnostics.ProcessStartInfo(
                    "tar", $"-xzf \"{tmpFile}\" -C \"{extractDir}\"")
                {
                    RedirectStandardError = true,
                    UseShellExecute       = false
                };
                using var p = System.Diagnostics.Process.Start(psi)!;
                await p.WaitForExitAsync(ct);
                if (p.ExitCode != 0)
                    throw new InvalidOperationException(
                        $"tar exited {p.ExitCode}: {await p.StandardError.ReadToEndAsync(ct)}");
            }

            string[] candidates = Directory.GetFiles(extractDir, "*", SearchOption.AllDirectories);

            string? appBundle = Directory.GetDirectories(extractDir, "*.app", SearchOption.AllDirectories)
                .FirstOrDefault(d => Path.GetFileNameWithoutExtension(d)
                    .StartsWith("OmniRCM", StringComparison.OrdinalIgnoreCase));

            if (appBundle is not null)
            {
                string appTarget = exePath.Contains(".app/Contents/MacOS")
                    ? Path.GetFullPath(Path.Combine(exePath, "..", "..", ".."))
                    : Path.Combine(dir, Path.GetFileName(appBundle));

                string backupApp = appTarget + ".old";
                if (Directory.Exists(backupApp)) Directory.Delete(backupApp, true);
                Directory.Move(appTarget, backupApp);
                Directory.Move(appBundle, appTarget);
                try { Directory.Delete(backupApp, true); } catch { }
                try { Directory.Delete(tmpBase,   true); } catch { }
                return;
            }

            string? newBinary = candidates.FirstOrDefault(f =>
            {
                string name = Path.GetFileName(f);
                return name.StartsWith("OmniRCM", StringComparison.OrdinalIgnoreCase)
                    && !name.EndsWith(".zip",   StringComparison.OrdinalIgnoreCase)
                    && !name.EndsWith(".gz",    StringComparison.OrdinalIgnoreCase)
                    && !name.EndsWith(".plist", StringComparison.OrdinalIgnoreCase);
            });

            if (newBinary is null)
                throw new FileNotFoundException("Could not find the OmniRCM binary inside the downloaded archive.");

            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                using var chmod = System.Diagnostics.Process.Start(
                    new System.Diagnostics.ProcessStartInfo("chmod", $"+x \"{newBinary}\"")
                    { UseShellExecute = false })!;
                await chmod.WaitForExitAsync(ct);
            }

            string backupPath = exePath + ".old";
            if (File.Exists(backupPath)) File.Delete(backupPath);
            File.Move(exePath, backupPath);
            File.Copy(newBinary, exePath, overwrite: false);
            try { File.Delete(backupPath); } catch { }
        }
        finally
        {
            try { File.Delete(tmpFile); }               catch { }
            try { Directory.Delete(extractDir, true); } catch { }
        }
    }
}
