using System.Security.Cryptography;

namespace DeskPilot.Agent;

/// <summary>
/// Pictures phones put on buttons and behind pages. Each is a file named by the first 16 hex characters of its
/// SHA-256, so the same picture is kept once and an id can never point outside the folder. The phone shrinks
/// pictures before sending them.
/// </summary>
public sealed class ImageStore(string folder)
{
    public const int MaxBytes = 700 * 1024;
    // shortcut: pictures nobody uses any more are kept, up to this many; clean them up if people hit it.
    const int MaxPictures = 1000;

    /// <summary>Whether <paramref name="id"/> looks like a picture id: 16 lowercase hex characters.</summary>
    public static bool IsId(string? id) =>
        id is { Length: 16 } && id.All(c => c is (>= '0' and <= '9') or (>= 'a' and <= 'f'));

    /// <summary>Keeps a picture. Returns why it can't, or null when it is kept.</summary>
    public string? Save(string id, byte[] bytes)
    {
        if (!IsId(id) || Convert.ToHexStringLower(SHA256.HashData(bytes))[..16] != id)
        {
            return "That picture arrived damaged. Try again.";
        }
        if (bytes.Length > MaxBytes)
        {
            return "That picture is too big. Pick a smaller one.";
        }
        if (Extension(bytes) is not { } extension)
        {
            return "DeskPilot takes JPEG, PNG, WebP and GIF pictures.";
        }
        Directory.CreateDirectory(folder);
        if (Find(id) is not null)
        {
            return null;
        }
        if (Directory.EnumerateFiles(folder).Count() >= MaxPictures)
        {
            return "DeskPilot is keeping too many pictures. Remove some from the images folder on the PC.";
        }
        // Written to a temporary file first, so a crash never leaves half a picture under a good id.
        var temporary = Path.Combine(folder, $"{id}.tmp");
        File.WriteAllBytes(temporary, bytes);
        File.Move(temporary, Path.Combine(folder, id + extension), overwrite: true);
        return null;
    }

    /// <summary>The picture with this id, or null when it isn't kept here.</summary>
    public byte[]? Read(string id) => IsId(id) && Find(id) is { } path ? File.ReadAllBytes(path) : null;

    string? Find(string id) =>
        Directory.Exists(folder)
            ? Directory.EnumerateFiles(folder, id + ".*").FirstOrDefault(path => !path.EndsWith(".tmp"))
            : null;

    static string? Extension(ReadOnlySpan<byte> bytes) => bytes switch
    {
        [0xFF, 0xD8, 0xFF, ..] => ".jpg",
        [0x89, 0x50, 0x4E, 0x47, ..] => ".png",
        [0x47, 0x49, 0x46, 0x38, ..] => ".gif",
        [0x52, 0x49, 0x46, 0x46, _, _, _, _, 0x57, 0x45, 0x42, 0x50, ..] => ".webp",
        _ => null,
    };
}
