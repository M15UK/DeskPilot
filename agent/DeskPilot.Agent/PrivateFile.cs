namespace DeskPilot.Agent;

/// <summary>Saves files that only the current user can read, without leaving a half written file after a crash.</summary>
public static class PrivateFile
{
    public static void Write(string path, ReadOnlySpan<byte> bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".tmp";
        // On Windows the user's local app data folder is already private to that user.
        var options = new FileStreamOptions { Mode = FileMode.Create, Access = FileAccess.Write };
        if (!OperatingSystem.IsWindows())
        {
            options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        }
        using (var stream = new FileStream(temp, options))
        {
            stream.Write(bytes);
        }
        File.Move(temp, path, overwrite: true);
    }
}
