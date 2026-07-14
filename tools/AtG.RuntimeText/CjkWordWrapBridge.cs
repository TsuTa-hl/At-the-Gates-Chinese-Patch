using System;
using Microsoft.Xna.Framework.Graphics;

namespace AtG.RuntimeText
{
    public static class CjkWordWrapBridge
    {
        public static void ProcessWord(object processor)
        {
            try
            {
                CjkWordWrapCore.ProcessWord(processor, delegate(object font, string text)
                {
                    var size = TextRenderer.MeasureString((SpriteFont)font, text);
                    return new CjkMeasuredText(size.X, size.Y);
                });
            }
            catch (Exception ex)
            {
                RuntimeTextTrace.Write("cjk-word-wrap-failed", null, null, ex);
                CjkWordWrapCore.ProcessOriginal(processor);
            }
        }
    }
}
