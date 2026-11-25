using System.Security.Cryptography;

namespace DeskPilot.Agent.Tests;

public class ImageStoreTests
{
    static readonly byte[] Png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

    static string IdOf(byte[] bytes) => Convert.ToHexStringLower(SHA256.HashData(bytes))[..16];

    [Fact]
    public void KeepsAPictureByItsIdAndGivesItBack()
    {
        using var folder = new TempFolder();
        var store = new ImageStore(folder.Path);

        Assert.Null(store.Save(IdOf(Png), Png));
        Assert.Null(store.Save(IdOf(Png), Png)); // the same picture again is fine

        Assert.Equal(Png, store.Read(IdOf(Png)));
        Assert.Single(Directory.GetFiles(folder.Path));
    }

    [Fact]
    public void RefusesAPictureWhoseIdDoesNotMatch()
    {
        using var folder = new TempFolder();
        var store = new ImageStore(folder.Path);

        Assert.NotNull(store.Save("0123456789abcdef", Png));
        Assert.Null(store.Read("0123456789abcdef"));
    }

    [Fact]
    public void RefusesFilesThatAreNotPictures()
    {
        using var folder = new TempFolder();
        byte[] program = [(byte)'M', (byte)'Z', 0x90, 0];

        Assert.NotNull(new ImageStore(folder.Path).Save(IdOf(program), program));
    }

    [Fact]
    public void RefusesAHugePicture()
    {
        using var folder = new TempFolder();
        var huge = new byte[ImageStore.MaxBytes + 1];
        Png.CopyTo(huge, 0);

        Assert.NotNull(new ImageStore(folder.Path).Save(IdOf(huge), huge));
    }

    [Theory]
    [InlineData("../../../secret")]
    [InlineData("ABCDEF0123456789")]
    [InlineData("")]
    public void OnlyReadsPictureIds(string id)
    {
        using var folder = new TempFolder();

        Assert.Null(new ImageStore(folder.Path).Read(id));
        Assert.False(ImageStore.IsId(id));
    }
}
