using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using OmniRCM.Rcm;

namespace OmniRCM;

internal static class Program
{
    public static bool StartMinimized { get; private set; }

    private static PosixSignalRegistration? _sigtermReg;
    private static PosixSignalRegistration? _sigintReg;

    private static FileStream? _lockFile;

    [STAThread]
    public static void Main(string[] args)
    {
#if WINDOWS
        if (args.Contains("--install-driver"))
        {
            RunHeadlessDriverInstall();
            return;
        }
#endif

        if (!AcquireSingleInstanceLock())
            return;

        StartMinimized = args.Contains("--minimized");

        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            Environment.SetEnvironmentVariable("AVALONIA_X11_USE_SESSION_MANAGEMENT", "0");

            _sigtermReg = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnPosixSignal);
            _sigintReg  = PosixSignalRegistration.Create(PosixSignal.SIGINT,  OnPosixSignal);
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

#if WINDOWS
    private static void RunHeadlessDriverInstall()
    {
        string? err = WdiInstaller.InstallDriver(IntPtr.Zero);
        if (err is null)
        {
            Environment.Exit(0);
        }
        else
        {
            try
            {
                string log = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "OmniRCM", "driver_install_error.txt");
                File.WriteAllText(log, err);
            }
            catch { }
            Environment.Exit(1);
        }
    }
#endif

    private static bool AcquireSingleInstanceLock()
    {
        string dir  = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "omnircm");
        string path = Path.Combine(dir, "instance.lock");

        try
        {
            Directory.CreateDirectory(dir);
            _lockFile = new FileStream(
                path,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None,
                bufferSize: 1,
                FileOptions.DeleteOnClose);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
    }

    public static void ReleaseSingleInstanceLock()
    {
        _lockFile?.Dispose();
        _lockFile = null;
    }

    private static void OnPosixSignal(PosixSignalContext ctx)
    {
        ctx.Cancel = true;

        var lifetime = Application.Current?.ApplicationLifetime
            as IClassicDesktopStyleApplicationLifetime;

        if (lifetime?.MainWindow is MainWindow win)
            win.SaveSettings();

        lifetime?.Shutdown();
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
