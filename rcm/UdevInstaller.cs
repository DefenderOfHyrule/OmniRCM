#if LINUX
using System.Diagnostics;
using System.Linq;
using System.Text;

namespace OmniRCM.Rcm;

internal static class UdevInstaller
{
    private const string GroupName = "nintendo_switch";
    private const string RulesFile = "/etc/udev/rules.d/70-switch.rules";

    public static bool IsInstalled()
    {
        try { return File.Exists(RulesFile) && File.ReadAllText(RulesFile).Contains(GroupName); }
        catch { return false; }
    }

    public static string GetScriptPath()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OmniRCM");
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "setup_udev.sh");

        var sb = new StringBuilder();
        sb.AppendLine("#!/bin/bash");
        sb.AppendLine("echo 'OmniRCM udev setup - enter your password when prompted'");
        sb.AppendLine("echo ''");
        sb.AppendLine($"groupadd -f {GroupName}");
        sb.AppendLine($"usermod -a -G {GroupName} {Environment.UserName}");
        sb.AppendLine("mkdir -p /etc/udev/rules.d");
        sb.AppendLine($"echo 'SUBSYSTEMS==\"usb\", ATTRS{{manufacturer}}==\"NVIDIA Corp.\", ATTRS{{product}}==\"APX\", GROUP=\"{GroupName}\"' | tee {RulesFile}");
        sb.AppendLine("chmod 644 " + RulesFile);
        sb.AppendLine("udevadm control --reload-rules");
        sb.AppendLine("udevadm trigger");
        sb.AppendLine("echo ''");
        sb.AppendLine("echo 'Done! Log out and back in for group membership to take effect.'");
        sb.AppendLine("echo 'This window will close in 5 seconds...'");
        sb.AppendLine("sleep 5");

        File.WriteAllText(path, sb.ToString());
        if (OperatingSystem.IsLinux())
            File.SetUnixFileMode(path,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
                UnixFileMode.GroupRead | UnixFileMode.OtherRead);
        return path;
    }

    public static async Task<(bool Success, string Output)> RunElevatedAsync(
        string scriptPath, string password, Action<string>? onOutput = null, CancellationToken ct = default)
    {
        var psi = new ProcessStartInfo("sudo")
        {
            RedirectStandardInput  = true,
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            UseShellExecute        = false,
        };
        psi.ArgumentList.Add("-S");
        psi.ArgumentList.Add("-k");
        psi.ArgumentList.Add("-p");
        psi.ArgumentList.Add("");
        psi.ArgumentList.Add("bash");
        psi.ArgumentList.Add(scriptPath);

        using var proc = Process.Start(psi);
        if (proc is null) return (false, "Could not start sudo.");

        var output = new StringBuilder();
        void Capture(object? _, DataReceivedEventArgs e)
        {
            if (e.Data is null) return;
            output.AppendLine(e.Data);
            onOutput?.Invoke(e.Data);
        }
        proc.OutputDataReceived += Capture;
        proc.ErrorDataReceived  += Capture;
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        await proc.StandardInput.WriteLineAsync(password);
        await proc.StandardInput.FlushAsync(ct);
        proc.StandardInput.Close();

        await proc.WaitForExitAsync(ct);
        return (proc.ExitCode == 0, output.ToString());
    }

    public static (bool Success, string Log) OpenTerminal(string scriptPath)
    {
        var log = new StringBuilder();

        // Each entry: (executable, args)
        // The script path is passed as a separate arg where possible to avoid
        // shell quoting issues. For terminals that only accept -e "command string"
        // we use bash -c to wrap it.
        (string exe, string[] args)[] terminals =
        [
            // KDE
            ("konsole",            ["-e", "sudo", "bash", scriptPath]),
            // GNOME / Ubuntu
            ("gnome-terminal",     ["--", "sudo", "bash", scriptPath]),
            // XFCE
            ("xfce4-terminal",     ["-e", $"sudo bash {scriptPath}"]),
            // Debian/Ubuntu generic alias
            ("x-terminal-emulator",["-e", $"sudo bash {scriptPath}"]),
            // LXQt / LXDE
            ("lxterminal",         ["-e", $"sudo bash {scriptPath}"]),
            // MATE
            ("mate-terminal",      ["-e", $"sudo bash {scriptPath}"]),
            // Cinnamon
            ("tilix",              ["-e", "sudo", "bash", scriptPath]),
            // Xterm (almost always available as fallback)
            ("xterm",              ["-e", "sudo", "bash", scriptPath]),
            // Modern GPU-accelerated terminals
            ("kitty",              ["sudo", "bash", scriptPath]),
            ("alacritty",         ["-e", "sudo", "bash", scriptPath]),
            ("wezterm",            ["start", "--", "sudo", "bash", scriptPath]),
            ("foot",               ["sudo", "bash", scriptPath]),
        ];

        foreach (var (exe, args) in terminals)
        {
            if (Which(exe) is null) continue;

            try
            {
                var psi = new ProcessStartInfo(exe) { UseShellExecute = false };
                foreach (var a in args) psi.ArgumentList.Add(a);

                var proc = Process.Start(psi);
                if (proc is not null)
                {
                    log.AppendLine($"{exe} started (PID {proc.Id})");
                    return (true, log.ToString().Trim());
                }
            }
            catch (Exception ex)
            {
                log.AppendLine($"{exe} failed: {ex.Message}");
            }
        }

        log.AppendLine("No terminal emulator found.");
        log.AppendLine("Tried: " + string.Join(", ", terminals.Select(t => t.exe)));
        return (false, log.ToString().Trim());
    }

    private static string? Which(string program)
    {
        try
        {
            var psi = new ProcessStartInfo("which", program)
            {
                UseShellExecute        = false,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return null;
            string output = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit();
            return p.ExitCode == 0 && !string.IsNullOrEmpty(output) ? output : null;
        }
        catch { return null; }
    }
}
#endif
