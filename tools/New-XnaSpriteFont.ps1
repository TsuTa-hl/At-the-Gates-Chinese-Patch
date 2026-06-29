param(
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

if (-not ("AtGChinesePatch.XnaSpriteFontBuilder" -as [type])) {
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
    public static class XnaSpriteFontBuilder
    {
        private struct GlyphInfo
        {
            public char Character;
            public int X;
            public int Y;
            public int Width;
            public int Height;
            public float Advance;
        }

        public static void Build(string outputPath, string previewPngPath, string fontFamily, float fontSize, bool bold, string characters, int textureWidth, int padding)
        {
            if (String.IsNullOrEmpty(characters))
                throw new ArgumentException("No characters were provided.");

            var chars = new SortedSet<char>();
            foreach (char ch in characters)
            {
                if (ch == '\r' || ch == '\n' || ch == '\t')
                    continue;
                if (Char.IsControl(ch) && ch != ' ')
                    continue;
                chars.Add(ch);
            }

            for (char ch = (char)32; ch <= (char)126; ch++)
                chars.Add(ch);
            for (char ch = (char)160; ch <= (char)384; ch++)
                chars.Add(ch);
            chars.Add('?');

            var style = bold ? FontStyle.Bold : FontStyle.Regular;
            using (var font = new Font(fontFamily, fontSize, style, GraphicsUnit.Pixel))
            using (var measureBitmap = new Bitmap(8, 8, PixelFormat.Format32bppPArgb))
            using (var measureGraphics = Graphics.FromImage(measureBitmap))
            {
                measureGraphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                measureGraphics.PageUnit = GraphicsUnit.Pixel;

                var format = (StringFormat)StringFormat.GenericTypographic.Clone();
                format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;

                int lineSpacing = Math.Max(1, (int)Math.Ceiling(font.GetHeight(measureGraphics) + padding * 2));
                var glyphs = new List<GlyphInfo>();
                int x = 0;
                int y = 0;
                int rowHeight = lineSpacing + padding * 2;

                foreach (char ch in chars)
                {
                    float measured = MeasureCharacter(measureGraphics, font, format, ch);
                    int advance = Math.Max(1, (int)Math.Ceiling(measured) + padding * 2);
                    int width = Math.Max(1, advance);
                    int height = rowHeight;

                    if (x + width > textureWidth)
                    {
                        x = 0;
                        y += rowHeight;
                    }

                    glyphs.Add(new GlyphInfo {
                        Character = ch,
                        X = x,
                        Y = y,
                        Width = width,
                        Height = height,
                        Advance = width
                    });
                    x += width;
                }

                int textureHeight = Math.Max(rowHeight, y + rowHeight);

                using (var atlas = new Bitmap(textureWidth, textureHeight, PixelFormat.Format32bppPArgb))
                using (var graphics = Graphics.FromImage(atlas))
                using (var brush = new SolidBrush(Color.White))
                {
                    graphics.Clear(Color.Transparent);
                    graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    graphics.PageUnit = GraphicsUnit.Pixel;

                    foreach (var glyph in glyphs)
                    {
                        if (glyph.Character == ' ')
                            continue;
                        graphics.DrawString(glyph.Character.ToString(), font, brush, glyph.X + padding, glyph.Y + padding, format);
                    }

                    if (!String.IsNullOrEmpty(previewPngPath))
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(previewPngPath));
                        atlas.Save(previewPngPath, ImageFormat.Png);
                    }

                    byte[] textureData = GetPremultipliedTextureBytes(atlas);
                    byte[] xnb = BuildXnb(textureWidth, textureHeight, textureData, glyphs, lineSpacing);
                    Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
                    File.WriteAllBytes(outputPath, xnb);
                }
            }
        }

        private static float MeasureCharacter(Graphics graphics, Font font, StringFormat format, char ch)
        {
            if (ch == ' ')
                return Math.Max(4.0f, font.Size * 0.45f);

            var size = graphics.MeasureString(ch.ToString(), font, new PointF(0, 0), format);
            return Math.Max(1.0f, size.Width);
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
                        byte b = raw[src + 0];
                        byte g = raw[src + 1];
                        byte r = raw[src + 2];
                        byte a = raw[src + 3];
                        result[dst + 0] = r;
                        result[dst + 1] = g;
                        result[dst + 2] = b;
                        result[dst + 3] = a;
                    }
                }
                return result;
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
        }

        private static byte[] BuildXnb(int width, int height, byte[] textureData, List<GlyphInfo> glyphs, int lineSpacing)
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
                writer.Write((int)width);
                writer.Write((int)height);
                writer.Write((int)1);
                writer.Write((int)textureData.Length);
                writer.Write(textureData);

                Write7BitEncodedInt(writer, 3);
                writer.Write((int)glyphs.Count);
                foreach (var glyph in glyphs)
                    WriteRectangle(writer, glyph.X, glyph.Y, glyph.Width, glyph.Height);

                Write7BitEncodedInt(writer, 3);
                writer.Write((int)glyphs.Count);
                foreach (var glyph in glyphs)
                    WriteRectangle(writer, 0, 0, glyph.Width, glyph.Height);

                Write7BitEncodedInt(writer, 5);
                writer.Write((int)glyphs.Count);
                foreach (var glyph in glyphs)
                    WriteChar(writer, glyph.Character);

                writer.Write((int)lineSpacing);
                writer.Write((float)0);

                Write7BitEncodedInt(writer, 7);
                writer.Write((int)glyphs.Count);
                foreach (var glyph in glyphs)
                {
                    writer.Write((float)0);
                    writer.Write((float)glyph.Advance);
                    writer.Write((float)0);
                }

                writer.Write((byte)1);
                WriteChar(writer, '?');

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

        private static void WriteRectangle(BinaryWriter writer, int x, int y, int width, int height)
        {
            writer.Write((int)x);
            writer.Write((int)y);
            writer.Write((int)width);
            writer.Write((int)height);
        }

        private static void WriteChar(BinaryWriter writer, char ch)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(new char[] { ch });
            writer.Write(bytes);
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

$preview = $PreviewPngPath
if ([string]::IsNullOrWhiteSpace($preview)) {
    $preview = [IO.Path]::ChangeExtension($OutputPath, ".png")
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$previewDir = Split-Path -Parent $preview
if ($previewDir) {
    New-Item -ItemType Directory -Force -Path $previewDir | Out-Null
}

[AtGChinesePatch.XnaSpriteFontBuilder]::Build(
    [IO.Path]::GetFullPath($OutputPath),
    [IO.Path]::GetFullPath($preview),
    $FontFamily,
    $FontSize,
    [bool]$Bold,
    $Characters,
    $TextureWidth,
    $Padding
)
