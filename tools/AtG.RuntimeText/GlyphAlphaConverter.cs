using System;
using System.Runtime.InteropServices;

namespace AtG.RuntimeText
{
    internal static class GlyphAlphaConverter
    {
        public static byte[] FromBgra(IntPtr scan0, int width, int height, int stride)
        {
            if (scan0 == IntPtr.Zero) throw new ArgumentNullException("scan0");
            if (width <= 0) throw new ArgumentOutOfRangeException("width");
            if (height <= 0) throw new ArgumentOutOfRangeException("height");
            if (stride == 0 || Math.Abs(stride) < checked(width * 4))
                throw new ArgumentOutOfRangeException("stride");

            var rowBytes = Math.Abs(stride);
            var source = new byte[checked(rowBytes * height)];
            for (var row = 0; row < height; row++)
            {
                var rowAddress = IntPtr.Add(scan0, checked(row * stride));
                Marshal.Copy(rowAddress, source, checked(row * rowBytes), rowBytes);
            }
            return FromBgra(source, width, height, rowBytes);
        }

        public static byte[] FromBgra(byte[] source, int width, int height, int stride)
        {
            if (source == null) throw new ArgumentNullException("source");
            if (width <= 0) throw new ArgumentOutOfRangeException("width");
            if (height <= 0) throw new ArgumentOutOfRangeException("height");
            if (stride == 0 || Math.Abs(stride) < checked(width * 4))
                throw new ArgumentOutOfRangeException("stride");
            var required = checked(Math.Abs(stride) * height);
            if (source.Length < required)
                throw new ArgumentException("Source does not contain every bitmap row.", "source");

            var output = new byte[checked(width * height * 4)];
            for (var y = 0; y < height; y++)
            {
                var sourceY = stride > 0 ? y : height - 1 - y;
                var sourceOffset = checked(sourceY * Math.Abs(stride));
                var targetOffset = checked(y * width * 4);
                for (var x = 0; x < width; x++)
                {
                    var alpha = source[sourceOffset + x * 4 + 3];
                    var pixel = targetOffset + x * 4;
                    output[pixel] = alpha;
                    output[pixel + 1] = alpha;
                    output[pixel + 2] = alpha;
                    output[pixel + 3] = alpha;
                }
            }
            return output;
        }
    }
}
