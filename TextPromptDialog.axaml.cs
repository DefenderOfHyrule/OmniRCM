using Avalonia.Controls;
using Avalonia.Input;

namespace OmniRCM;

public partial class TextPromptDialog : Window
{
    public TextPromptDialog()
    {
        InitializeComponent();

        ConfirmButton.Click += (_, _) => Close(InputBox.Text);
        CancelButton.Click  += (_, _) => Close(null);

        InputBox.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) Close(InputBox.Text);
            if (e.Key == Key.Escape) Close(null);
        };

        Opened += (_, _) =>
        {
            InputBox.Focus();
            InputBox.SelectAll();
        };
    }

    public static async Task<string?> AskAsync(
        Window owner, string title, string description, string defaultValue = "")
    {
        var dialog = new TextPromptDialog();
        dialog.TitleText.Text       = title;
        dialog.DescriptionText.Text = description;
        dialog.InputBox.Text        = defaultValue;
        return await dialog.ShowDialog<string?>(owner);
    }
}