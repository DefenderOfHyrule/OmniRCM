using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using OmniRCM.Rcm;

namespace OmniRCM;

public partial class MainWindow : Window
{
    private static readonly OmniVersion CurrentVersion = new(1, 1, 1);

    private Settings _settings = Settings.Load();

    private string? _selectedPayloadPath;

    private readonly DispatcherTimer _pollTimer;
    private bool _deviceConnected;

    private bool _autoInjectFiredThisConnection;

    private CancellationTokenSource? _injectCts;
    private CancellationTokenSource? _fetchCts;

    private static readonly string[] Spinner = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"];
    private int _spinFrame;
    private readonly DispatcherTimer _spinTimer;
    private DispatcherTimer? _updateSpinTimer;

    public MainWindow()
    {
        InitializeComponent();

        VersionLabel.Text = $"v{CurrentVersion}";
        CreditsVersionLabel.Text = $"v{CurrentVersion}";
        Icon = App.AppIcon;

        if (!_settings.DarkTheme) ThemeManager.Toggle(this);
        else ThemeManager.Apply(this);
        UpdateThemeIcon();
        UpdateSettingsIcon();

        PayloadFetcher.SetCustomSources(_settings.CustomPayloadSources);
        PayloadFetcher.LoadCached();
        RefreshFetchedList();
        RefreshFavoritesList();
        RefreshSourcesList();
        RestoreLastSelection();

        ThemeToggle.Click    += (_, _) => { ThemeManager.Toggle(this); UpdateThemeIcon(); UpdateSettingsIcon(); };

        FetchButton.Click    += OnFetchClick;
        BrowseButton.Click   += OnBrowseClick;
        InjectButton.Click   += OnInjectClick;

#if WINDOWS
        InstallDriverButton.Click += async (_, _) => await OnInstallDriverClickAsync();
        DeviceInstallDriverButton.Click += async (_, _) => await OnInstallDriverClickAsync();
        DeviceInstallDriverButton.IsVisible = true;

        DriverHintTitle.Text       = "libusbK driver required";
        DriverHintDescription.Text = "The libusbK driver must be installed once before OmniRCM can talk to your Switch.";
        InstallDriverButton.Content   = "⬇ Install Driver";
        Avalonia.Controls.ToolTip.SetTip(InstallDriverButton, "Installs libusbK via the embedded driver package (UAC prompt may appear)");
        ZadigButton.Content           = "Get Zadig";
        Avalonia.Controls.ToolTip.SetTip(ZadigButton, "Open zadig.akeo.ie in your browser as an alternative");
        ZadigButton.Click += (_, _) =>
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName        = "https://zadig.akeo.ie",
                UseShellExecute = true,
            });
#elif LINUX
        InstallDriverButton.Click += async (_, _) => await OnInstallUdevRuleClickAsync();
        DeviceInstallDriverButton.Click += async (_, _) => await OnInstallUdevRuleClickAsync();
        DeviceInstallDriverButton.IsVisible = true;
        DeviceInstallDriverButton.Content   = "Setup udev";

        DriverHintTitle.Text       = "udev rule required";
        DriverHintDescription.Text = "A udev rule must be added once to allow OmniRCM to access your Switch without root.";
        InstallDriverButton.Content   = "⬇ Setup udev";
        ZadigButton.Content           = "Manual setup";
        Avalonia.Controls.ToolTip.SetTip(ZadigButton, "Open setup instructions in your browser");
        ZadigButton.Click += (_, _) =>
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName        = "https://switch.hacks.guide/extras/adding_udev.html",
                UseShellExecute = true,
            });
#else
        ZadigButton.Click += (_, _) =>
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName        = "https://zadig.akeo.ie",
                UseShellExecute = true,
            });
#endif

        CreditsButton.Click       += (_, _) => { CreditsOverlay.IsVisible = true; };
        CreditsCloseButton.Click  += (_, _) => { CreditsOverlay.IsVisible = false; };
        UpdateNowButton.Click     += (_, _) => _ = DoUpdateAsync();
        UpdateDismissButton.Click += (_, _) => { UpdateBannerBorder.IsVisible = false; };
        CreditsUpdateButton.Click += (_, _) => { CreditsOverlay.IsVisible = false; _ = DoUpdateAsync(); };
        CancelButton.Click   += (_, _) => { _injectCts?.Cancel(); _fetchCts?.Cancel(); };
        ClearLogButton.Click += (_, _) => { LogText.Text = ""; };

        SettingsButton.Click      += (_, _) => { SettingsOverlay.IsVisible = true; };
        SettingsCloseButton.Click += (_, _) => { SettingsOverlay.IsVisible = false; };

        AddFavoriteButton.Click += OnAddFavoriteClick;
        AddSourceButton.Click   += OnAddSourceClick;

        CustomPathBox.TextChanged    += (_, _) => OnCustomPathChanged();
        CustomRadio.IsCheckedChanged += (_, _) =>
        {
            if (CustomRadio.IsChecked != true) return;
            _selectedPayloadPath          = CustomPathBox.Text?.Trim() ?? "";
            _settings.LastSelectedPayload = "custom";
            _settings.Save();
            ShowPayloadType(_selectedPayloadPath);
            ReevaluateInjectButton();
        };

        AutoInjectToggle.IsChecked = _settings.AutoInject;
        AutoInjectToggle.IsCheckedChanged += OnAutoInjectToggled;

        MinimizeToTrayToggle.IsChecked = _settings.MinimizeToTray;
        MinimizeToTrayToggle.IsCheckedChanged += OnMinimizeToTrayToggled;

        LaunchOnBootToggle.IsChecked = _settings.LaunchOnBoot;
        LaunchOnBootToggle.IsCheckedChanged += OnLaunchOnBootToggled;

        StartMinimizedOnBootToggle.IsChecked = _settings.StartMinimizedOnBoot;
        StartMinimizedOnBootToggle.IsCheckedChanged += OnStartMinimizedOnBootToggled;

#if LINUX
        AppLauncherBorder.IsVisible  = true;
        AppLauncherToggle.IsChecked  = DesktopLauncherInstaller.IsInstalled();
        AppLauncherToggle.IsCheckedChanged += OnAppLauncherToggled;
#endif

        UpdateStartMinimizedEnabled();

        Closing += (_, e) =>
        {
            if (e.CloseReason == WindowCloseReason.ApplicationShutdown)
                return;

            if (_settings.MinimizeToTray)
            {
                e.Cancel = true;
                Hide();
            }
            else
            {
                e.Cancel = true;
                CleanShutdown();
            }
        };

        _spinTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
        _spinTimer.Tick += (_, _) =>
        {
            _spinFrame = (_spinFrame + 1) % Spinner.Length;
            DeviceSpinner.Text = Spinner[_spinFrame];
        };
        _spinTimer.Start();

        _pollTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
        _pollTimer.Tick += (_, _) => PollDevice();
        _pollTimer.Start();
        PollDevice();
        _ = CheckForUpdateAsync();
        AddHandler(KeyDownEvent, OnWindowKeyDown,
            RoutingStrategies.Tunnel, handledEventsToo: true);
    }

    public void CleanShutdown()
    {
        _pollTimer.Stop();
        _spinTimer.Stop();
        _updateSpinTimer?.Stop();
        _injectCts?.Cancel();
        _fetchCts?.Cancel();
        _settings.Save();

        if (Application.Current?.ApplicationLifetime
            is IClassicDesktopStyleApplicationLifetime desktop)
            desktop.Shutdown();
    }

    public void SaveSettings() => _settings.Save();

    private bool _injecting;

    private void PollDevice()
    {
        if (_injecting) return;
        bool present;
        try   { present = RcmDevice.IsPresent(); }
        catch { present = false; }

        if (present == _deviceConnected) return;

        _deviceConnected = present;

        if (present)
        {
            _autoInjectFiredThisConnection = false;
            OnDeviceConnected();
        }
        else
        {
            _autoInjectFiredThisConnection = false;
            OnDeviceDisconnected();
        }
    }

    private void SetPill(string color, string text)
    {
        PillDot.Fill             = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(color));
        DeviceStatusLabel.Text   = text;
    }

    private void SetResultPanel(string borderColor, string? detail = null)
    {
        ResultPanelBorder.BorderBrush = new Avalonia.Media.SolidColorBrush(
            Avalonia.Media.Color.Parse(borderColor));
        bool hasDetail = !string.IsNullOrEmpty(detail);
        ResultDivider.IsVisible     = hasDetail;
        ResultDetailLabel.IsVisible = hasDetail;
        if (hasDetail) ResultDetailLabel.Text = detail;
    }

    private void ClearResultPanel()
    {
        ResultPanelBorder.BorderBrush = (Avalonia.Media.IBrush)
            (Application.Current?.Resources["CardInnerBorder"]
             ?? new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#1E2330")));
        ResultDivider.IsVisible     = false;
        ResultDetailLabel.IsVisible = false;
        ResultDetailLabel.Text      = "";
    }

    private void OnDeviceConnected()
    {
        SetPill("#4CAF50", "RCM device connected");
        DeviceStateLabel.Text   = "Tegra RCM device detected";
        DeviceSpinner.IsVisible = false;
        ClearResultPanel();

        AppendLog("RCM device connected.");
        ReevaluateInjectButton();

        if (_settings.AutoInject && !_autoInjectFiredThisConnection &&
            !string.IsNullOrWhiteSpace(_selectedPayloadPath) &&
            File.Exists(_selectedPayloadPath))
        {
            _autoInjectFiredThisConnection = true;
            AppendLog("Auto-inject triggered.");
            _ = RunInjectAsync(_selectedPayloadPath);
        }
    }

    private void OnDeviceDisconnected()
    {
        SetPill("#607D8B", "Waiting for RCM device…");
        DeviceStateLabel.Text     = "Waiting for RCM device…";
        DeviceIdLabel.Text        = "";
        DeviceSpinner.IsVisible   = true;
        ZadigHintBorder.IsVisible = false;
        ClearResultPanel();

        AppendLog("Device disconnected.");
        ReevaluateInjectButton();
    }

    private void OnAutoInjectToggled(object? sender, RoutedEventArgs e)
    {
        _settings.AutoInject = AutoInjectToggle.IsChecked == true;
        _settings.Save();
    }

    private void OnMinimizeToTrayToggled(object? sender, RoutedEventArgs e)
    {
        _settings.MinimizeToTray = MinimizeToTrayToggle.IsChecked == true;
        _settings.Save();
    }

    private void OnLaunchOnBootToggled(object? sender, RoutedEventArgs e)
    {
        _settings.LaunchOnBoot = LaunchOnBootToggle.IsChecked == true;
        _settings.Save();
        ReRegisterAutostart();
        UpdateStartMinimizedEnabled();
    }

    private void OnStartMinimizedOnBootToggled(object? sender, RoutedEventArgs e)
    {
        _settings.StartMinimizedOnBoot = StartMinimizedOnBootToggle.IsChecked == true;
        _settings.Save();
        ReRegisterAutostart();
    }

#if LINUX
    private void OnAppLauncherToggled(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (AppLauncherToggle.IsChecked == true)
            {
                DesktopLauncherInstaller.Install();
                AppendLog("Added OmniRCM to the app launcher.");
            }
            else
            {
                DesktopLauncherInstaller.Uninstall();
                AppendLog("Removed OmniRCM from the app launcher.");
            }
        }
        catch (Exception ex)
        {
            AppendLog($"[app launcher] {ex.Message}");
        }
    }
#endif

    private void ReRegisterAutostart()
    {
        try
        {
            AutostartManager.Set(_settings.LaunchOnBoot, _settings.StartMinimizedOnBoot);
        }
        catch (Exception ex) { AppendLog($"[autostart] {ex.Message}"); }
    }

    private void UpdateStartMinimizedEnabled()
    {
        StartMinimizedBorder.Opacity  = _settings.LaunchOnBoot ? 1.0 : 0.4;
        StartMinimizedOnBootToggle.IsEnabled = _settings.LaunchOnBoot;
    }

    private readonly List<(RadioButton Radio, RemotePayload Payload)> _fetchedRadios = new();
    private UpdateChecker.UpdateInfo? _pendingUpdate;

    private void RefreshFetchedList()
    {
        foreach (var (rb, _) in _fetchedRadios)
            rb.IsCheckedChanged -= OnFetchedRadioChanged;
        _fetchedRadios.Clear();
        FetchedList.Children.Clear();

        foreach (var payload in PayloadFetcher.All)
        {
            string label = payload.IsDownloaded
                ? $"{payload.Name}  v{payload.Version}"
                : $"{payload.Name}  (not downloaded)";

            var rb = new RadioButton
            {
                GroupName = "PayloadGroup",
                Content   = EscapeAccessKeyText(label),
                IsEnabled = payload.IsDownloaded,
                FontSize  = 12,
                Margin    = new Thickness(0, 2),
            };
            rb.IsCheckedChanged += OnFetchedRadioChanged;
            _fetchedRadios.Add((rb, payload));
            FetchedList.Children.Add(rb);
        }

        foreach (var (rb, payload) in _fetchedRadios)
        {
            if (payload.Name == _settings.LastSelectedPayload && payload.IsDownloaded)
            {
                rb.IsChecked         = true;
                _selectedPayloadPath = payload.LocalPath;
                ShowPayloadType(_selectedPayloadPath);
                break;
            }
        }

        ReevaluateInjectButton();
    }

    private void OnFetchedRadioChanged(object? sender, RoutedEventArgs e)
    {
        if (sender is not RadioButton rb || rb.IsChecked != true) return;
        var entry = _fetchedRadios.FirstOrDefault(x => x.Radio == rb);
        if (entry.Payload is null) return;

        _selectedPayloadPath          = entry.Payload.LocalPath;
        _settings.LastSelectedPayload = entry.Payload.Name;
        _settings.LastCustomPayload   = "";
        _settings.Save();
        ShowPayloadType(_selectedPayloadPath);
        ReevaluateInjectButton();
    }

    private void RestoreLastSelection()
    {
        if (!string.IsNullOrEmpty(_settings.LastCustomPayload))
            CustomPathBox.Text = _settings.LastCustomPayload;

        if (_settings.LastSelectedPayload == "custom" &&
            !string.IsNullOrEmpty(_settings.LastCustomPayload))
        {
            CustomRadio.IsChecked = true;
            _selectedPayloadPath  = _settings.LastCustomPayload;
            ShowPayloadType(_selectedPayloadPath);
            ReevaluateInjectButton();
        }
    }

    private void OnCustomPathChanged()
    {
        _settings.LastCustomPayload = CustomPathBox.Text?.Trim() ?? "";
        if (CustomRadio.IsChecked == true)
        {
            _selectedPayloadPath = _settings.LastCustomPayload;
            ShowPayloadType(_selectedPayloadPath);
            ReevaluateInjectButton();
        }
    }

    private static string EscapeAccessKeyText(string text) => text.Replace("_", "__");

    private void RefreshFavoritesList()
    {
        FavoritesList.Children.Clear();
        NoFavoritesLabel.IsVisible = _settings.FavoritePayloads.Count == 0;

        foreach (var fav in _settings.FavoritePayloads.ToList())
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };

            var selectButton = new Button
            {
                Content                    = EscapeAccessKeyText(fav.Name),
                FontSize                   = 12,
                Padding                    = new Thickness(8, 5),
                HorizontalAlignment        = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Background                 = Brushes.Transparent,
                Foreground                 = (IBrush)(Application.Current?.Resources["TextPrimary"] ?? Brushes.White),
            };
            selectButton.Click += (_, _) => SelectFavoritePayload(fav);

            var removeButton = new Button
            {
                Content    = "✕",
                FontSize   = 10,
                Padding    = new Thickness(6, 5),
                Background = Brushes.Transparent,
                Foreground = (IBrush)(Application.Current?.Resources["TextMuted"] ?? Brushes.Gray),
            };
            removeButton.Click += (_, _) =>
            {
                _settings.FavoritePayloads.Remove(fav);
                _settings.Save();
                RefreshFavoritesList();
            };

            Grid.SetColumn(selectButton, 0);
            Grid.SetColumn(removeButton, 1);
            row.Children.Add(selectButton);
            row.Children.Add(removeButton);
            FavoritesList.Children.Add(row);
        }
    }

    private void SelectFavoritePayload(FavoritePayload fav)
    {
        if (!File.Exists(fav.Path))
        {
            AppendLog($"[ERROR] Favorite payload \"{fav.Name}\" no longer exists at {fav.Path}.");
            return;
        }

        CustomPathBox.Text            = fav.Path;
        CustomRadio.IsChecked         = true;
        _selectedPayloadPath          = fav.Path;
        _settings.LastCustomPayload   = fav.Path;
        _settings.LastSelectedPayload = "custom";
        _settings.Save();
        ShowPayloadType(fav.Path);
        ReevaluateInjectButton();
    }

    private async void OnAddFavoriteClick(object? sender, RoutedEventArgs e)
    {
        string path = CustomPathBox.Text?.Trim() ?? "";
        if (string.IsNullOrEmpty(path) || !File.Exists(path))
        {
            AppendLog("[ERROR] Select a valid custom payload file before saving it as a favorite.");
            return;
        }

        string defaultName = Path.GetFileNameWithoutExtension(path);
        string? name = await TextPromptDialog.AskAsync(
            this, "Save as favorite", "Give this payload a name to recognize it later.", defaultName);
        if (name is null) return;

        name = name.Trim();
        if (name.Length == 0) name = defaultName;

        var existing = _settings.FavoritePayloads.FirstOrDefault(f => f.Path == path);
        if (existing is not null) existing.Name = name;
        else _settings.FavoritePayloads.Add(new FavoritePayload { Name = name, Path = path });

        _settings.Save();
        RefreshFavoritesList();
        AppendLog($"Saved \"{name}\" as a favorite payload.");
    }

    private void RefreshSourcesList()
    {
        SourcesList.Children.Clear();
        NoSourcesLabel.IsVisible = _settings.CustomPayloadSources.Count == 0;

        foreach (var src in _settings.CustomPayloadSources.ToList())
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };

            var label = new TextBlock
            {
                Text              = $"{src.Name}  ({src.Repo})",
                FontSize          = 12,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground        = (IBrush)(Application.Current?.Resources["TextPrimary"] ?? Brushes.White),
            };

            var removeButton = new Button
            {
                Content    = "✕",
                FontSize   = 10,
                Padding    = new Thickness(6, 3),
                Background = Brushes.Transparent,
                Foreground = (IBrush)(Application.Current?.Resources["TextMuted"] ?? Brushes.Gray),
            };
            removeButton.Click += (_, _) =>
            {
                _settings.CustomPayloadSources.Remove(src);
                _settings.Save();
                PayloadFetcher.SetCustomSources(_settings.CustomPayloadSources);
                RefreshSourcesList();
                RefreshFetchedList();
            };

            Grid.SetColumn(label, 0);
            Grid.SetColumn(removeButton, 1);
            row.Children.Add(label);
            row.Children.Add(removeButton);
            SourcesList.Children.Add(row);
        }
    }

    private async void OnAddSourceClick(object? sender, RoutedEventArgs e)
    {
        var source = await AddPayloadSourceDialog.AskAsync(this);
        if (source is null) return;

        if (_settings.CustomPayloadSources.Any(s => s.Name.Equals(source.Name, StringComparison.OrdinalIgnoreCase)))
        {
            AppendLog($"[ERROR] A payload source named \"{source.Name}\" already exists.");
            return;
        }

        _settings.CustomPayloadSources.Add(source);
        _settings.Save();
        PayloadFetcher.SetCustomSources(_settings.CustomPayloadSources);
        RefreshSourcesList();
        RefreshFetchedList();
        AppendLog($"Added payload source \"{source.Name}\". Click Update to fetch it.");
    }

    private void ShowPayloadType(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path))
        {
            PayloadTypeBadge.IsVisible = false;
            return;
        }
        try
        {
            int readLen = Math.Min((int)new FileInfo(path).Length, 0x20000);
            byte[] hdr = new byte[readLen];
            using var fs = File.OpenRead(path);
            int got = 0;
            while (got < readLen)
            {
                int n = fs.Read(hdr, got, readLen - got);
                if (n == 0) break;
                got += n;
            }
            var type = RcmPayload.Detect(hdr);
            PayloadTypeLabel.Text = type switch
            {
                RcmPayload.PayloadType.Fusee         => "⚡ Detected: fusee (Atmosphere)",
                RcmPayload.PayloadType.Hekate        => "⚡ Detected: hekate",
                RcmPayload.PayloadType.TegraExplorer => "⚡ Detected: TegraExplorer",
                _                                    => "⚡ Detected: Generic payload",
            };
            PayloadTypeBadge.IsVisible = true;
        }
        catch { PayloadTypeBadge.IsVisible = false; }
    }

    private async void OnBrowseClick(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title         = "Select RCM payload (.bin)",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("RCM payload") { Patterns = ["*.bin"] },
                new FilePickerFileType("All files")   { Patterns = ["*"] }
            ]
        });
        if (files.Count == 0) return;
        string path = files[0].TryGetLocalPath() ?? files[0].Path.LocalPath;
        CustomPathBox.Text            = path;
        CustomRadio.IsChecked         = true;
        _selectedPayloadPath          = path;
        _settings.LastCustomPayload   = path;
        _settings.LastSelectedPayload = "custom";
        _settings.Save();
        ShowPayloadType(path);
        ReevaluateInjectButton();
    }

    private async void OnFetchClick(object? sender, RoutedEventArgs e)
    {
        _fetchCts?.Cancel();
        _fetchCts = new CancellationTokenSource();

        FetchButton.IsEnabled  = false;
        CancelButton.IsVisible = true;
        AppendLog("Fetching payloads...");

        try
        {
            await PayloadFetcher.FetchAllAsync(
                log => Dispatcher.UIThread.Post(() => AppendLog(log)),
                _fetchCts.Token);
        }
        catch (OperationCanceledException) { AppendLog("Fetch cancelled."); }
        catch (Exception ex)               { AppendLog($"[ERROR] {ex.Message}"); }
        finally
        {
            FetchButton.IsEnabled  = true;
            CancelButton.IsVisible = false;
            RefreshFetchedList();
            ReevaluateInjectButton();
        }
    }

    private void ReevaluateInjectButton()
    {
        bool hasPayload = !string.IsNullOrWhiteSpace(_selectedPayloadPath) &&
                          File.Exists(_selectedPayloadPath);
        InjectButton.IsEnabled = hasPayload;
        InjectButton.Background = new Avalonia.Media.SolidColorBrush(
            Avalonia.Media.Color.Parse(hasPayload ? "#4CAF50" : "#2A3040"));
    }

    private async void OnInjectClick(object? sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_selectedPayloadPath) ||
            !File.Exists(_selectedPayloadPath))
        {
            AppendLog("[ERROR] No valid payload selected.");
            return;
        }
        await RunInjectAsync(_selectedPayloadPath);
    }

    private async Task RunInjectAsync(string payloadPath)
    {
        _injectCts?.Cancel();
        _injectCts = new CancellationTokenSource();
        _injecting = true;

        InjectButton.IsEnabled = false;
        FetchButton.IsEnabled  = false;
        CancelButton.IsVisible = true;
        DeviceStateLabel.Text  = "Injecting…";
        SetPill("#42A5F5", "Injecting…");
        ClearResultPanel();

        try
        {
            var result = await RcmInjector.InjectAsync(
                payloadPath,
                log => Dispatcher.UIThread.Post(() => AppendLog(log)),
                _injectCts.Token);

            if (result.IsSuccess)
            {
                AppendLog($"✓ {result.Summary()}");
                DeviceStateLabel.Text     = "✓ Injection successful";
                DeviceIdLabel.Text        = $"Device ID: {result.DeviceId}";
                ZadigHintBorder.IsVisible = false;
                SetPill("#4CAF50", "Injection successful");
                SetResultPanel("#4CAF50",
                    "The payload was sent successfully. The Switch should now be booted into " +
                    "the selected payload. You may disconnect the USB cable and continue to follow the guide.");
            }
            else
            {
                AppendLog($"✗ {result.Summary()}");

                switch (result.Status.ToString())
                {
                    case "PatchedV1":
                        DeviceStateLabel.Text = "✗ Patched V1 console";
                        SetPill("#FFC107", "Patched V1 console");
                        SetResultPanel("#FFC107",
                            "This console has an updated bootROM and cannot be exploited via RCM.");
                        break;

                    case "PatchedV2":
                        DeviceStateLabel.Text = "✗ V2/Mariko console";
                        SetPill("#F44336", "V2/Mariko console");
                        SetResultPanel("#F44336",
                            "This is a Mariko (V2) console. The fusee-gelee exploit does not " +
                            "apply to this hardware revision.");
                        break;

                    default:
                        DeviceStateLabel.Text = "✗ Injection failed";
                        SetPill("#F44336", "Injection failed");
                        SetResultPanel("#F44336",
                            "An error occurred during injection. Check the log for details. " +
                            "Make sure the device was freshly put in RCM and the cable is properly connected.");
                        break;
                }

                if (result.Error is not null &&
                    (result.Error.Contains("libusbK") || result.Error.Contains("driver") ||
                     result.Error.Contains("Zadig")   || result.Error.Contains("Permission") ||
                     result.Error.Contains("Access")  || result.Error.Contains("udev")))
                    ZadigHintBorder.IsVisible = true;
            }
        }
        catch (OperationCanceledException)
        {
            AppendLog("Cancelled.");
            DeviceStateLabel.Text = "Cancelled.";
            SetPill("#607D8B", "Waiting for RCM device…");
            ClearResultPanel();
        }
        catch (Exception ex)
        {
            AppendLog($"[ERROR] {ex.Message}");
            DeviceStateLabel.Text = "✗ Error, see log.";
            SetPill("#F44336", "Injection failed");
            SetResultPanel("#F44336",
                "An error occurred during injection. Check the log for details.");
        }
        finally
        {
            _injecting             = false;
            InjectButton.IsEnabled = true;
            FetchButton.IsEnabled  = true;
            CancelButton.IsVisible = false;
            ReevaluateInjectButton();
        }
    }

#if WINDOWS
    private async Task OnInstallDriverClickAsync()
    {
        InstallDriverButton.IsEnabled = false;
        InstallDriverButton.Content   = "Installing…";
        AppendLog("Installing libusbK driver…");

        nint hwnd = TryGetHwnd();

        string? err = await Task.Run(() => WdiInstaller.InstallDriver(hwnd));

        if (err == WdiInstaller.NeedsElevationSentinel)
        {
            AppendLog("Elevation required, relaunching as administrator…");

            var proc = TryRelaunchElevated("--install-driver");
            if (proc is null)
            {
                AppendLog("Driver installation cancelled.");
                InstallDriverButton.Content   = "Install Driver";
                InstallDriverButton.IsEnabled = true;
                return;
            }

            int exitCode = await Task.Run(async () =>
            {
                await proc.WaitForExitAsync();
                return proc.ExitCode;
            });
            proc.Dispose();

            if (exitCode == 0)
            {
                AppendLog("✓ libusbK driver installed. (Re)-plug in your Switch.");
                ZadigHintBorder.IsVisible = false;
            }
            else
            {
                AppendLog($"[ERROR] Driver install failed (elevated process exited with code {exitCode}).");
                InstallDriverButton.Content   = "Install Driver";
                InstallDriverButton.IsEnabled = true;
            }
            return;
        }

        if (err is null)
        {
            AppendLog("✓ libusbK driver installed. (Re)-plug in your Switch.");
            ZadigHintBorder.IsVisible = false;
        }
        else
        {
            AppendLog($"[ERROR] {err}");
            InstallDriverButton.Content   = "Install Driver";
            InstallDriverButton.IsEnabled = true;
        }
    }

    private nint TryGetHwnd()
    {
        try
        {
            if (TryGetPlatformHandle() is { } h)
                return h.Handle;
        }
        catch { }
        return IntPtr.Zero;
    }

    private static System.Diagnostics.Process? TryRelaunchElevated(string args)
    {
        string? exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe)) return null;
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo(exe, args)
            {
                UseShellExecute = true,
                Verb            = "runas",
            };
            return System.Diagnostics.Process.Start(psi);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }
#endif

#if LINUX

    private async Task OnInstallUdevRuleClickAsync()
    {
        string scriptPath = UdevInstaller.GetScriptPath();
        string? error = null;

        for (int attempt = 0; attempt < 3; attempt++)
        {
            string? password = await SudoPasswordDialog.AskAsync(this, error);
            if (password is null)
            {
                AppendLog("Udev setup cancelled.");
                return;
            }

            AppendLog("Setting up udev rule…");
            try
            {
                (bool success, _) = await UdevInstaller.RunElevatedAsync(
                    scriptPath, password, line => AppendLog(line));

                if (success)
                {
                    AppendLog("Log out and back in for group membership to take effect.");
                    return;
                }

                error = "Authentication failed. Try again.";
            }
            catch (Exception ex)
            {
                AppendLog($"[ERROR] {ex.Message}");
                AppendLog("Falling back to opening a terminal instead…");
                await FallBackToTerminalAsync(scriptPath);
                return;
            }
        }

        AppendLog("[ERROR] Too many failed attempts.");
        await FallBackToTerminalAsync(scriptPath);
    }

    private async Task FallBackToTerminalAsync(string scriptPath)
    {
        (bool success, string log) = await Task.Run(() => UdevInstaller.OpenTerminal(scriptPath));
        if (success)
        {
            AppendLog("A terminal window has opened.");
            AppendLog("Enter your sudo password when prompted.");
        }
        else
        {
            AppendLog("[ERROR] Could not open a terminal either. Run the script manually:");
            AppendLog($"  bash \"{scriptPath}\"");
        }
    }
#endif

    private void AppendLog(string line)
    {
        Dispatcher.UIThread.Post(() =>
        {
            LogText.Text      += line + "\n";
            LogText.CaretIndex = LogText.Text?.Length ?? 0;
        });
    }

    private void UpdateThemeIcon()
    {
        string uri = ThemeManager.IsDark
            ? "avares://OmniRCM/Assets/sun.png"
            : "avares://OmniRCM/Assets/moon.png";
        ThemeIcon.Source = new Bitmap(AssetLoader.Open(new Uri(uri)));
        _settings.DarkTheme = ThemeManager.IsDark;
    }

    private void UpdateSettingsIcon()
    {
        SettingsIcon.Source = new Bitmap(AssetLoader.Open(new Uri("avares://OmniRCM/Assets/cog.png")));
    }

    private async Task CheckForUpdateAsync()
    {
        await Task.Delay(TimeSpan.FromSeconds(4));
        try
        {
            var info = await UpdateChecker.CheckAsync(CurrentVersion);
            if (info is null) return;
            _pendingUpdate = info;
            await Dispatcher.UIThread.InvokeAsync(() => ShowUpdateBanner(info));
        }
        catch { }
    }

    private void ShowUpdateBanner(UpdateChecker.UpdateInfo info)
    {
        string rid = UpdateChecker.DetectRid();
        UpdateBannerLabel.Text        = $"v{info.LatestVersion} available ({rid})";
        CreditsUpdateButton.Content   = $"Update to v{info.LatestVersion}";
        CreditsUpdateButton.IsVisible = true;
        UpdateBannerBorder.IsVisible  = true;
    }

    private async Task DoUpdateAsync()
    {
        if (_pendingUpdate is null) return;
        UpdateBannerBorder.IsVisible  = false;
        CreditsOverlay.IsVisible      = false;
        CreditsUpdateButton.IsVisible = false;

        if (string.IsNullOrEmpty(_pendingUpdate.DownloadUrl))
        {
            AppendLog($"[Simulated update] Would update to v{_pendingUpdate.LatestVersion}.");
            return;
        }

        ShowUpdateOverlay($"0%  -  {_pendingUpdate.AssetName}");

        try
        {
            string newExePath = await UpdateChecker.DownloadAndInstallAsync(
                _pendingUpdate,
                pct => Dispatcher.UIThread.Post(() =>
                    UpdateOverlayMessage.Text = $"{pct}%  -  {_pendingUpdate.AssetName}"));

            HideUpdateOverlay();
            AppendLog($"Updated to v{_pendingUpdate.LatestVersion}. Restarting...");

            await Dispatcher.UIThread.InvokeAsync(async () =>
            {
                try
                {
                    if (!string.IsNullOrEmpty(newExePath))
                    {
                        Program.ReleaseSingleInstanceLock();

                        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                        {
                            string bundlePath = newExePath.Contains(".app/Contents/MacOS")
                                ? Path.GetFullPath(Path.Combine(newExePath, "..", "..", ".."))
                                : newExePath;

                            var psi = new System.Diagnostics.ProcessStartInfo("open", $"-n \"{bundlePath}\"")
                            {
                                UseShellExecute       = false,
                                RedirectStandardError = true,
                            };

                            using var openProc = System.Diagnostics.Process.Start(psi);
                            if (openProc is not null)
                            {
                                string stderr = await openProc.StandardError.ReadToEndAsync();
                                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                                try { await openProc.WaitForExitAsync(cts.Token); } catch (OperationCanceledException) { }

                                if (openProc.ExitCode != 0 || !string.IsNullOrWhiteSpace(stderr))
                                    AppendLog($"[WARN] 'open' exited {openProc.ExitCode}: {stderr.Trim()}");
                            }
                        }
                        else
                        {
                            System.Diagnostics.Process.Start(
                                new System.Diagnostics.ProcessStartInfo(newExePath)
                                {
                                    UseShellExecute = RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
                                });
                        }
                    }
                }
                catch (Exception ex)
                {
                    AppendLog($"[WARN] Could not relaunch automatically: {ex.Message}");
                }
                _pollTimer.Stop();
                _spinTimer.Stop();
                _updateSpinTimer?.Stop();
                if (Application.Current?.ApplicationLifetime
                    is IClassicDesktopStyleApplicationLifetime desktop)
                    desktop.Shutdown();
            });
        }
        catch (Exception ex)
        {
            HideUpdateOverlay();
            AppendLog($"Update failed: {ex.Message}");
        }
    }

    private void ShowUpdateOverlay(string message)
    {
        UpdateOverlayMessage.Text = message;
        UpdateOverlay.IsVisible   = true;

        _updateSpinTimer ??= new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
        _updateSpinTimer.Tick += (_, _) =>
        {
            _spinFrame = (_spinFrame + 1) % Spinner.Length;
            UpdateOverlaySpinner.Text = Spinner[_spinFrame];
        };
        _updateSpinTimer.Start();
    }

    private void HideUpdateOverlay()
    {
        _updateSpinTimer?.Stop();
        UpdateOverlay.IsVisible = false;
    }

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.U
            && e.KeyModifiers.HasFlag(KeyModifiers.Control)
            && e.KeyModifiers.HasFlag(KeyModifiers.Shift))
            SimulateUpdate();
    }

    public void SimulateUpdate(string fakeVersion = "99.0.0")
    {
        var fakeInfo = new UpdateChecker.UpdateInfo(
            OmniVersion.TryParse(fakeVersion) ?? new OmniVersion(99, 0, 0),
            AssetName:   $"OmniRCM-{UpdateChecker.DetectRid()}.zip",
            DownloadUrl: "",
            AssetSize:   0);
        _pendingUpdate = fakeInfo;
        Dispatcher.UIThread.Post(() => ShowUpdateBanner(fakeInfo));
    }
}
