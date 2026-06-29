param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$Characters,

    [string]$FontFamily = "Microsoft YaHei UI",
    [float]$FontSize = 16,
    [switch]$Bold,
    [int]$TextureWidth = 4096,
    [int]$Padding = 2,
    [string]$PreviewPngPath
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

if (-not ("AtGChinesePatch.XnaMergedSpriteFontBuilder" -as [type])) {
    Add-Type -ReferencedAssemblies "System.Drawing" -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Text;

namespace AtGChinesePatch
{
    public static class XnaMergedSpriteFontBuilder
    {
        private struct Rect
        {
            public int X;
            public int Y;
            public int Width;
            public int Height;
        }

        private sealed class GlyphInfo
        {
            public char Character;
            public Rect Bounds;
            public Rect Cropping;
            public float LeftSideBearing;
            public float WidthIncludingBearings;
            public float RightSideBearing;
        }

        private sealed class SpriteFontData
        {
            public int TextureWidth;
            public int TextureHeight;
            public byte[] TextureData;
            public int LineSpacing;
            public float Spacing;
            public bool HasDefaultCharacter;
            public char DefaultCharacter;
            public List<GlyphInfo> Glyphs = new List<GlyphInfo>();
        }

        public static void Build(string sourcePath, string outputPath, string previewPngPath, string fontFamily, float fontSize, bool bold, string characters, int textureWidth, int padding)
        {
            var original = ReadSpriteFont(sourcePath);
            var existingCharacters = new HashSet<char>(original.Glyphs.Select(g => g.Character));
            var newCharacters = new SortedSet<char>();

            foreach (char ch in characters ?? "")
            {
                if (ch == '\r' || ch == '\n' || ch == '\t')
                    continue;
                if (Char.IsControl(ch) && ch != ' ')
                    continue;
                if (!existingCharacters.Contains(ch))
                    newCharacters.Add(ch);
            }

            if (newCharacters.Count == 0)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
                File.Copy(sourcePath, outputPath, true);
                if (!String.IsNullOrEmpty(previewPngPath))
                    SavePreview(original.TextureWidth, original.TextureHeight, original.TextureData, previewPngPath);
                return;
            }

            int outputTextureWidth = Math.Max(textureWidth, original.TextureWidth);
            var style = bold ? FontStyle.Bold : FontStyle.Regular;
            using (var font = new Font(fontFamily, fontSize, style, GraphicsUnit.Pixel))
            using (var measureBitmap = new Bitmap(8, 8, PixelFormat.Format32bppPArgb))
            using (var measureGraphics = Graphics.FromImage(measureBitmap))
            {
                measureGraphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                measureGraphics.PageUnit = GraphicsUnit.Pixel;

                var format = (StringFormat)StringFormat.GenericTypographic.Clone();
                format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;

                int fontLineSpacing = Math.Max(1, (int)Math.Ceiling(font.GetHeight(measureGraphics) + padding * 2));
                int rowHeight = Math.Max(original.LineSpacing, fontLineSpacing) + padding * 2;
                int x = 0;
                int y = original.TextureHeight + padding;

                var appended = new List<GlyphInfo>();
                foreach (char ch in newCharacters)
                {
                    float measured = MeasureCharacter(measureGraphics, font, format, ch);
                    int advance = Math.Max(1, (int)Math.Ceiling(measured) + padding * 2);
                    int width = Math.Max(1, advance);
                    int height = rowHeight;

                    if (x + width > outputTextureWidth)
                    {
                        x = 0;
                        y += rowHeight;
                    }

                    appended.Add(new GlyphInfo {
                        Character = ch,
                        Bounds = new Rect { X = x, Y = y, Width = width, Height = height },
                        Cropping = new Rect { X = 0, Y = 0, Width = width, Height = height },
                        LeftSideBearing = 0,
                        WidthIncludingBearings = width,
                        RightSideBearing = 0
                    });

                    x += width;
                }

                int outputTextureHeight = Math.Max(original.TextureHeight, y + rowHeight);
                using (var atlas = CreateBitmapFromRgba(outputTextureWidth, outputTextureHeight, original.TextureData, original.TextureWidth, original.TextureHeight))
                using (var graphics = Graphics.FromImage(atlas))
                using (var brush = new SolidBrush(Color.White))
                {
                    graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    graphics.PageUnit = GraphicsUnit.Pixel;

                    foreach (var glyph in appended)
                    {
                        if (glyph.Character == ' ')
                            continue;
                        graphics.DrawString(glyph.Character.ToString(), font, brush, glyph.Bounds.X + padding, glyph.Bounds.Y + padding, format);
                    }

                    if (!String.IsNullOrEmpty(previewPngPath))
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(previewPngPath));
                        atlas.Save(previewPngPath, ImageFormat.Png);
                    }

                    original.TextureWidth = outputTextureWidth;
                    original.TextureHeight = outputTextureHeight;
                    original.TextureData = GetPremultipliedTextureBytes(atlas);
                    original.Glyphs.AddRange(appended);
                    original.Glyphs = original.Glyphs.OrderBy(g => g.Character).ToList();

                    byte[] xnb = BuildXnb(original);
                    Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
                    File.WriteAllBytes(outputPath, xnb);
                }
            }
        }

        private static SpriteFontData ReadSpriteFont(string sourcePath)
        {
            using (var stream = File.OpenRead(sourcePath))
            using (var reader = new BinaryReader(stream, Encoding.UTF8))
            {
                string magic = Encoding.ASCII.GetString(reader.ReadBytes(3));
                if (magic != "XNB")
                    throw new InvalidDataException("Not an XNB file.");

                reader.ReadByte(); // platform
                reader.ReadByte(); // version
                byte flags = reader.ReadByte();
                if ((flags & 0x80) != 0)
                    throw new InvalidDataException("Compressed XNB files are not supported.");

                reader.ReadInt32(); // file size

                int readerCount = Read7BitEncodedInt(reader);
                for (int i = 0; i < readerCount; i++)
                {
                    int nameLength = Read7BitEncodedInt(reader);
                    reader.ReadBytes(nameLength);
                    reader.ReadInt32();
                }

                Read7BitEncodedInt(reader); // shared resource count
                Read7BitEncodedInt(reader); // SpriteFont reader type id

                Read7BitEncodedInt(reader); // Texture2D reader type id
                int surfaceFormat = reader.ReadInt32();
                if (surfaceFormat != 0)
                    throw new InvalidDataException("Only Color texture format is supported.");

                var result = new SpriteFontData();
                result.TextureWidth = reader.ReadInt32();
                result.TextureHeight = reader.ReadInt32();
                int mipCount = reader.ReadInt32();
                if (mipCount != 1)
                    throw new InvalidDataException("Only one mip level is supported.");

                int textureDataSize = reader.ReadInt32();
                result.TextureData = reader.ReadBytes(textureDataSize);

                var bounds = ReadRectangleList(reader);
                var cropping = ReadRectangleList(reader);
                var chars = ReadCharList(reader);

                result.LineSpacing = reader.ReadInt32();
                result.Spacing = reader.ReadSingle();
                var kernings = ReadVector3List(reader);

                result.HasDefaultCharacter = reader.ReadByte() != 0;
                if (result.HasDefaultCharacter)
                    result.DefaultCharacter = reader.ReadChar();

                if (bounds.Count != cropping.Count || bounds.Count != chars.Count || bounds.Count != kernings.Count)
                    throw new InvalidDataException("SpriteFont glyph lists have mismatched lengths.");

                for (int i = 0; i < chars.Count; i++)
                {
                    result.Glyphs.Add(new GlyphInfo {
                        Character = chars[i],
                        Bounds = bounds[i],
                        Cropping = cropping[i],
                        LeftSideBearing = kernings[i].Item1,
                        WidthIncludingBearings = kernings[i].Item2,
                        RightSideBearing = kernings[i].Item3
                    });
                }

                return result;
            }
        }

        private static List<Rect> ReadRectangleList(BinaryReader reader)
        {
            Read7BitEncodedInt(reader); // list reader type id
            int count = reader.ReadInt32();
            var result = new List<Rect>(count);
            for (int i = 0; i < count; i++)
            {
                result.Add(new Rect {
                    X = reader.ReadInt32(),
                    Y = reader.ReadInt32(),
                    Width = reader.ReadInt32(),
                    Height = reader.ReadInt32()
                });
            }
            return result;
        }

        private static List<char> ReadCharList(BinaryReader reader)
        {
            Read7BitEncodedInt(reader); // list reader type id
            int count = reader.ReadInt32();
            var result = new List<char>(count);
            for (int i = 0; i < count; i++)
                result.Add(reader.ReadChar());
            return result;
        }

        private static List<Tuple<float, float, float>> ReadVector3List(BinaryReader reader)
        {
            Read7BitEncodedInt(reader); // list reader type id
            int count = reader.ReadInt32();
            var result = new List<Tuple<float, float, float>>(count);
            for (int i = 0; i < count; i++)
                result.Add(Tuple.Create(reader.ReadSingle(), reader.ReadSingle(), reader.ReadSingle()));
            return result;
        }

        private static float MeasureCharacter(Graphics graphics, Font font, StringFormat format, char ch)
        {
            if (ch == ' ')
                return Math.Max(4.0f, font.Size * 0.45f);

            var size = graphics.MeasureString(ch.ToString(), font, new PointF(0, 0), format);
            return Math.Max(1.0f, size.Width);
        }

        private static Bitmap CreateBitmapFromRgba(int outputWidth, int outputHeight, byte[] originalRgba, int originalWidth, int originalHeight)
        {
            var bitmap = new Bitmap(outputWidth, outputHeight, PixelFormat.Format32bppPArgb);
            var rect = new Rectangle(0, 0, outputWidth, outputHeight);
            var data = bitmap.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
            try
            {
                int stride = Math.Abs(data.Stride);
                byte[] raw = new byte[stride * outputHeight];
                for (int row = 0; row < originalHeight; row++)
                {
                    int srcRow = row * originalWidth * 4;
                    int dstRow = row * stride;
                    for (int col = 0; col < originalWidth; col++)
                    {
                        int src = srcRow + col * 4;
                        int dst = dstRow + col * 4;
                        raw[dst + 0] = originalRgba[src + 2];
                        raw[dst + 1] = originalRgba[src + 1];
                        raw[dst + 2] = originalRgba[src + 0];
                        raw[dst + 3] = originalRgba[src + 3];
                    }
                }
                System.Runtime.InteropServices.Marshal.Copy(raw, 0, data.Scan0, raw.Length);
            }
            finally
            {
                bitmap.UnlockBits(data);
            }

            return bitmap;
        }

        private static byte[] GetPremultipliedTextureBytes(Bitmap bitmap)
        {
            var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            var data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
            try
            {
                int stride = Math.Abs(data.Stride);
                byte[] raw = new byte[stride * bitmap.Height];
                System.Runtime.InteropServices.Marshal.Copy(data.Scan0, raw, 0, raw.Length);

                byte[] result = new byte[bitmap.Width * bitmap.Height * 4];
                for (int row = 0; row < bitmap.Height; row++)
                {
                    int srcRow = row * stride;
                    int dstRow = row * bitmap.Width * 4;
                    for (int col = 0; col < bitmap.Width; col++)
                    {
                        int src = srcRow + col * 4;
                        int dst = dstRow + col * 4;
                        result[dst + 0] = raw[src + 2];
                        result[dst + 1] = raw[src + 1];
                        result[dst + 2] = raw[src + 0];
                        result[dst + 3] = raw[src + 3];
                    }
                }
                return result;
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
        }

        private static void SavePreview(int width, int height, byte[] rgba, string previewPngPath)
        {
            using (var bitmap = CreateBitmapFromRgba(width, height, rgba, width, height))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(previewPngPath));
                bitmap.Save(previewPngPath, ImageFormat.Png);
            }
        }

        private static byte[] BuildXnb(SpriteFontData font)
        {
            using (var stream = new MemoryStream())
            using (var writer = new BinaryWriter(stream, Encoding.UTF8))
            {
                writer.Write(Encoding.ASCII.GetBytes("XNB"));
                writer.Write((byte)'w');
                writer.Write((byte)5);
                writer.Write((byte)1);
                writer.Write((int)0);

                Write7BitEncodedInt(writer, 8);
                WriteReader(writer, "Microsoft.Xna.Framework.Content.SpriteFontReader, Microsoft.Xna.Framework.Graphics, Version=4.0.0.0, Culture=neutral, PublicKeyToken=842cf8be1de50553");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.Texture2DReader, Microsoft.Xna.Framework.Graphics, Version=4.0.0.0, Culture=neutral, PublicKeyToken=842cf8be1de50553");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.ListReader`1[[Microsoft.Xna.Framework.Rectangle, Microsoft.Xna.Framework, Version=4.0.0.0, Culture=neutral, PublicKeyToken=842cf8be1de50553]]");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.RectangleReader");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.ListReader`1[[System.Char, mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089]]");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.CharReader");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.ListReader`1[[Microsoft.Xna.Framework.Vector3, Microsoft.Xna.Framework, Version=4.0.0.0, Culture=neutral, PublicKeyToken=842cf8be1de50553]]");
                WriteReader(writer, "Microsoft.Xna.Framework.Content.Vector3Reader");

                Write7BitEncodedInt(writer, 0);
                Write7BitEncodedInt(writer, 1);

                Write7BitEncodedInt(writer, 2);
                writer.Write((int)0);
                writer.Write((int)font.TextureWidth);
                writer.Write((int)font.TextureHeight);
                writer.Write((int)1);
                writer.Write((int)font.TextureData.Length);
                writer.Write(font.TextureData);

                Write7BitEncodedInt(writer, 3);
                writer.Write((int)font.Glyphs.Count);
                foreach (var glyph in font.Glyphs)
                    WriteRectangle(writer, glyph.Bounds);

                Write7BitEncodedInt(writer, 3);
                writer.Write((int)font.Glyphs.Count);
                foreach (var glyph in font.Glyphs)
                    WriteRectangle(writer, glyph.Cropping);

                Write7BitEncodedInt(writer, 5);
                writer.Write((int)font.Glyphs.Count);
                foreach (var glyph in font.Glyphs)
                    WriteChar(writer, glyph.Character);

                writer.Write((int)font.LineSpacing);
                writer.Write((float)font.Spacing);

                Write7BitEncodedInt(writer, 7);
                writer.Write((int)font.Glyphs.Count);
                foreach (var glyph in font.Glyphs)
                {
                    writer.Write((float)glyph.LeftSideBearing);
                    writer.Write((float)glyph.WidthIncludingBearings);
                    writer.Write((float)glyph.RightSideBearing);
                }

                writer.Write((byte)(font.HasDefaultCharacter ? 1 : 0));
                if (font.HasDefaultCharacter)
                    WriteChar(writer, font.DefaultCharacter);

                writer.Flush();
                byte[] bytes = stream.ToArray();
                byte[] size = BitConverter.GetBytes(bytes.Length);
                Array.Copy(size, 0, bytes, 6, 4);
                return bytes;
            }
        }

        private static void WriteReader(BinaryWriter writer, string name)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(name);
            Write7BitEncodedInt(writer, bytes.Length);
            writer.Write(bytes);
            writer.Write((int)0);
        }

        private static void WriteRectangle(BinaryWriter writer, Rect rect)
        {
            writer.Write((int)rect.X);
            writer.Write((int)rect.Y);
            writer.Write((int)rect.Width);
            writer.Write((int)rect.Height);
        }

        private static void WriteChar(BinaryWriter writer, char ch)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(new char[] { ch });
            writer.Write(bytes);
        }

        private static int Read7BitEncodedInt(BinaryReader reader)
        {
            int count = 0;
            int shift = 0;
            byte b;
            do
            {
                if (shift == 35)
                    throw new FormatException("Bad 7-bit encoded integer.");
                b = reader.ReadByte();
                count |= (b & 0x7F) << shift;
                shift += 7;
            }
            while ((b & 0x80) != 0);
            return count;
        }

        private static void Write7BitEncodedInt(BinaryWriter writer, int value)
        {
            uint v = (uint)value;
            while (v >= 0x80)
            {
                writer.Write((byte)(v | 0x80));
                v >>= 7;
            }
            writer.Write((byte)v);
        }
    }
}
'@
}

if (!(Test-Path -LiteralPath $SourcePath)) {
    throw "Source SpriteFont not found: $SourcePath"
}

$preview = $PreviewPngPath
if ([string]::IsNullOrWhiteSpace($preview)) {
    $preview = [IO.Path]::ChangeExtension($OutputPath, ".png")
}

[AtGChinesePatch.XnaMergedSpriteFontBuilder]::Build(
    [IO.Path]::GetFullPath($SourcePath),
    [IO.Path]::GetFullPath($OutputPath),
    [IO.Path]::GetFullPath($preview),
    $FontFamily,
    $FontSize,
    [bool]$Bold,
    $Characters,
    $TextureWidth,
    $Padding
)
