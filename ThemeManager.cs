using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Styling;

namespace OmniRCM;

public static class ThemeManager
{
    private static bool _isDark = true;
    public static bool IsDark => _isDark;

    public static void Toggle(Window window)
    {
        _isDark = !_isDark;
        Apply(window);
    }

    public static void Apply(Window window)
    {
        if (Application.Current is null) return;
        var variant = _isDark ? ThemeVariant.Dark : ThemeVariant.Light;
        Application.Current.RequestedThemeVariant = variant;
        window.RequestedThemeVariant = variant;
        window.Background = _isDark
            ? new SolidColorBrush(Color.Parse("#0F1117"))
            : new SolidColorBrush(Color.Parse("#F0F2F5"));
        UpdateResources(_isDark);
    }

    private static void UpdateResources(bool dark)
    {
        if (Application.Current?.Resources is null) return;
        var r = Application.Current.Resources;

        if (dark)
        {
            r["CardBg"]          = new SolidColorBrush(Color.Parse("#181C27"));
            r["CardBorder"]      = new SolidColorBrush(Color.Parse("#252A38"));
            r["CardInner"]       = new SolidColorBrush(Color.Parse("#0D1017"));
            r["CardInnerBorder"] = new SolidColorBrush(Color.Parse("#1E2330"));
            r["PillBg"]          = new SolidColorBrush(Color.Parse("#1A1F2E"));
            r["ButtonBg"]        = new SolidColorBrush(Color.Parse("#252A38"));
            r["TextPrimary"]     = new SolidColorBrush(Color.Parse("#ECEFF1"));
            r["TextMuted"]       = new SolidColorBrush(Color.Parse("#607D8B"));
            r["LogFg"]           = new SolidColorBrush(Color.Parse("#6A8A9A"));
            r["AccentGreen"]     = new SolidColorBrush(Color.Parse("#4CAF50"));
            r["AccentBlue"]      = new SolidColorBrush(Color.Parse("#42A5F5"));
            r["AccentRed"]       = new SolidColorBrush(Color.Parse("#EF5350"));
        }
        else
        {
            r["CardBg"]          = new SolidColorBrush(Color.Parse("#FFFFFF"));
            r["CardBorder"]      = new SolidColorBrush(Color.Parse("#D0D5E0"));
            r["CardInner"]       = new SolidColorBrush(Color.Parse("#F5F7FA"));
            r["CardInnerBorder"] = new SolidColorBrush(Color.Parse("#C8D0DC"));
            r["PillBg"]          = new SolidColorBrush(Color.Parse("#E8ECF8"));
            r["ButtonBg"]        = new SolidColorBrush(Color.Parse("#E8ECF2"));
            r["TextPrimary"]     = new SolidColorBrush(Color.Parse("#1A1A2E"));
            r["TextMuted"]       = new SolidColorBrush(Color.Parse("#546E7A"));
            r["LogFg"]           = new SolidColorBrush(Color.Parse("#37474F"));
            r["AccentGreen"]     = new SolidColorBrush(Color.Parse("#2E7D32"));
            r["AccentBlue"]      = new SolidColorBrush(Color.Parse("#1976D2"));
            r["AccentRed"]       = new SolidColorBrush(Color.Parse("#C62828"));
        }
    }
}
