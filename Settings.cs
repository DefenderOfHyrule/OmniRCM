using System.Text.Json;
using System.Text.Json.Serialization;

namespace OmniRCM;

public sealed class Settings
{
    public static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "omnircm", "settings.json");

    public bool   AutoInject            { get; set; } = false;
    public bool   MinimizeToTray        { get; set; } = false;
    public bool   LaunchOnBoot          { get; set; } = false;
    public bool   StartMinimizedOnBoot  { get; set; } = true;
    public bool   DarkTheme             { get; set; } = true;
    public string LastCustomPayload     { get; set; } = "";
    public string LastSelectedPayload   { get; set; } = "";

    public List<FavoritePayload>     FavoritePayloads     { get; set; } = new();
    public List<CustomPayloadSource> CustomPayloadSources { get; set; } = new();

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                string json = File.ReadAllText(FilePath);
                return JsonSerializer.Deserialize(json, SettingsJsonContext.Default.Settings)
                       ?? new Settings();
            }
        }
        catch { }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath,
                JsonSerializer.Serialize(this, SettingsJsonContext.Default.Settings));
        }
        catch { }
    }
}

public sealed class FavoritePayload
{
    public string Name { get; set; } = "";
    public string Path { get; set; } = "";
}

public sealed class CustomPayloadSource
{
    public string Name            { get; set; } = "";
    public string Repo            { get; set; } = "";
    public string AssetMatch      { get; set; } = "";
    public bool   IsZip           { get; set; } = false;
    public string ZipInnerPattern { get; set; } = "*.bin";
}

[JsonSerializable(typeof(Settings))]
[JsonSourceGenerationOptions(WriteIndented = true)]
internal partial class SettingsJsonContext : JsonSerializerContext { }
