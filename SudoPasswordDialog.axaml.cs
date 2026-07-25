using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;

namespace OmniRCM;

public partial class SudoPasswordDialog : Window
{
    public SudoPasswordDialog()
    {
        InitializeComponent();

        ConfirmButton.Click += (_, _) => Confirm();
        CancelButton.Click  += (_, _) => Close(null);

        PasswordBox.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) Confirm();
            if (e.Key == Key.Escape) Close(null);
        };

        Opened += (_, _) => PasswordBox.Focus();
    }

    private void Confirm()
    {
        string password = PasswordBox.Text ?? "";
        if (string.IsNullOrEmpty(password))
        {
            ShowError("Enter your password.");
            return;
        }
        Close(password);
    }

    public void ShowError(string message)
    {
        ErrorText.Text      = message;
        ErrorText.IsVisible = true;
    }

    public static async System.Threading.Tasks.Task<string?> AskAsync(Window owner, string? errorMessage = null)
    {
        var dialog = new SudoPasswordDialog();
        if (!string.IsNullOrEmpty(errorMessage))
            dialog.ShowError(errorMessage);

        return await dialog.ShowDialog<string?>(owner);
    }
}
