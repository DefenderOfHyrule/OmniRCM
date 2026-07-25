using System.Runtime.InteropServices;

namespace OmniRCM;

public static class AutostartManager
{
    public static bool IsEnabled()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return IsEnabledWindows();
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            return File.Exists(DesktopFilePath());
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            return File.Exists(PlistPath());
        return false;
    }

    public static void Set(bool enable, bool minimized)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            SetWindows(enable, minimized);
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            SetLinux(enable, minimized);
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            SetMacOS(enable, minimized);
    }

    const string RegKey  = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    const string RegName = "OmniRCM";

    static bool IsEnabledWindows()
    {
#if WINDOWS
#pragma warning disable CA1416
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RegKey);
        return key?.GetValue(RegName) is not null;
#pragma warning restore CA1416
#else
        return false;
#endif
    }

    static void SetWindows(bool enable, bool minimized)
    {
#if WINDOWS
#pragma warning disable CA1416
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RegKey, writable: true);
        if (key is null) return;
        if (enable)
        {
            string args = minimized ? " --minimized" : "";
            key.SetValue(RegName, $"\"{Environment.ProcessPath}\"{args}");
        }
        else
        {
            key.DeleteValue(RegName, throwOnMissingValue: false);
        }
#pragma warning restore CA1416
#endif
    }

    static string DesktopFilePath()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config", "autostart");
        return Path.Combine(dir, "omnircm.desktop");
    }

    static void SetLinux(bool enable, bool minimized)
    {
        string path = DesktopFilePath();
        if (enable)
        {
            string args = minimized ? " --minimized" : "";
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path,
                "[Desktop Entry]\n" +
                "Type=Application\n" +
                "Name=OmniRCM\n" +
                $"Exec=\"{Environment.ProcessPath}\"{args}\n" +
                "Hidden=false\n" +
                "NoDisplay=false\n" +
                "X-GNOME-Autostart-enabled=true\n");
        }
        else
        {
            try { File.Delete(path); } catch { }
        }
    }

    static string PlistPath()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Library", "LaunchAgents");
        return Path.Combine(dir, "com.omnircm.app.plist");
    }

    static void SetMacOS(bool enable, bool minimized)
    {
        string path = PlistPath();
        if (enable)
        {
            string minimizedArg = minimized
                ? "\n\t\t<string>--minimized</string>"
                : "";
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path,
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\"\n" +
                "\t\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" +
                "<plist version=\"1.0\">\n" +
                "<dict>\n" +
                "\t<key>Label</key><string>com.omnircm.app</string>\n" +
                "\t<key>ProgramArguments</key>\n" +
                "\t<array>\n" +
                $"\t\t<string>{Environment.ProcessPath}</string>{minimizedArg}\n" +
                "\t</array>\n" +
                "\t<key>RunAtLoad</key><true/>\n" +
                "</dict>\n" +
                "</plist>\n");
        }
        else
        {
            try { File.Delete(path); } catch { }
        }
    }
}
