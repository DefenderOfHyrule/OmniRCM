#if LINUX
using Avalonia.Platform;

namespace OmniRCM.Rcm;

internal static class DesktopLauncherInstaller
{
    private static string DesktopFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".local", "share", "applications", "omnircm.desktop");

    private static string IconPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "OmniRCM", "icon.png");

    public static bool IsInstalled() => File.Exists(DesktopFilePath);

    public static void Install()
    {
        string exe = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine the running executable path.");

        string iconPath = IconPath;
        Directory.CreateDirectory(Path.GetDirectoryName(iconPath)!);
        if (!File.Exists(iconPath))
        {
            using var stream = AssetLoader.Open(new Uri("avares://OmniRCM/Assets/icon.png"));
            using var file   = File.Create(iconPath);
            stream.CopyTo(file);
        }

        string desktopPath = DesktopFilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(desktopPath)!);
        File.WriteAllText(desktopPath,
            "[Desktop Entry]\n" +
            "Type=Application\n" +
            "Name=OmniRCM\n" +
            "Comment=Nintendo Switch RCM payload injector\n" +
            $"Exec=\"{exe}\"\n" +
            $"Icon={iconPath}\n" +
            "Terminal=false\n" +
            "Categories=Utility;\n" +
            "StartupNotify=true\n");

        TryRun("update-desktop-database", Path.GetDirectoryName(desktopPath)!);
    }

    public static void Uninstall()
    {
        try { File.Delete(DesktopFilePath); } catch { }
    }

    private static void TryRun(string exe, string arg)
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo(exe)
            {
                UseShellExecute        = false,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
            };
            psi.ArgumentList.Add(arg);
            using var p = System.Diagnostics.Process.Start(psi);
            p?.WaitForExit(2000);
        }
        catch { }
    }
}
#endif
