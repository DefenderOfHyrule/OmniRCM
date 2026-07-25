using Avalonia.Controls;

namespace OmniRCM;

public partial class AddPayloadSourceDialog : Window
{
    private static readonly string[] ReservedNames = ["fusee", "hekate", "tegraexplorer", "custom"];

    public AddPayloadSourceDialog()
    {
        InitializeComponent();

        IsZipCheck.IsCheckedChanged += (_, _) => ZipPatternPanel.IsVisible = IsZipCheck.IsChecked == true;
        ConfirmButton.Click += (_, _) => Confirm();
        CancelButton.Click  += (_, _) => Close(null);
    }

    private void Confirm()
    {
        string name       = NameBox.Text?.Trim() ?? "";
        string repo       = RepoBox.Text?.Trim() ?? "";
        string assetMatch = AssetMatchBox.Text?.Trim() ?? "";

        if (name.Length == 0 || repo.Length == 0 || assetMatch.Length == 0)
        {
            ShowError("All fields are required.");
            return;
        }

        if (!repo.Contains('/'))
        {
            ShowError("Repository must be in the form owner/repo.");
            return;
        }

        if (ReservedNames.Contains(name.ToLowerInvariant()))
        {
            ShowError("That name is reserved, please choose another.");
            return;
        }

        var source = new CustomPayloadSource
        {
            Name            = name,
            Repo            = repo,
            AssetMatch      = assetMatch,
            IsZip           = IsZipCheck.IsChecked == true,
            ZipInnerPattern = ZipPatternBox.Text?.Trim() is { Length: > 0 } p ? p : "*.bin",
        };

        Close(source);
    }

    private void ShowError(string message)
    {
        ErrorText.Text      = message;
        ErrorText.IsVisible = true;
    }

    public static async Task<CustomPayloadSource?> AskAsync(Window owner)
    {
        var dialog = new AddPayloadSourceDialog();
        return await dialog.ShowDialog<CustomPayloadSource?>(owner);
    }
}