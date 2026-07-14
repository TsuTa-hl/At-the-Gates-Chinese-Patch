using System;
using System.Collections.Generic;
using System.Reflection;
using System.Text;

namespace AtG.RuntimeText
{
    public struct CjkMeasuredText
    {
        public CjkMeasuredText(float width, float height)
        {
            Width = width;
            Height = height;
        }
        public readonly float Width;
        public readonly float Height;
    }

    public static class CjkWordWrapCore
    {
        private static readonly object Gate = new object();
        private static readonly Dictionary<Type, Accessors> Cache =
            new Dictionary<Type, Accessors>();

        public static void ProcessWord(object processor,
            Func<object, string, CjkMeasuredText> measure)
        {
            if (processor == null) throw new ArgumentNullException("processor");
            if (measure == null) throw new ArgumentNullException("measure");
            var access = Resolve(processor.GetType());
            var word = (string)access.Word.GetValue(processor);
            if (!CjkText.ContainsBreakableCjk(word))
            {
                access.OriginalWordMethod.Invoke(processor, null);
                return;
            }

            var font = access.ChunkFont.GetValue(processor);
            var builder = (StringBuilder)access.TextSoFar.GetValue(processor);
            var currentX = GetFloat(access.CurrentX, processor);
            var currentWidth = GetFloat(access.WidthOfTextSoFar, processor);
            var widthOfSpace = GetFloat(access.WidthOfSpace, processor);
            var wrappedShift = GetFloat(access.WrappedLineShiftX, processor);
            var maxWidth = (int)access.MaxLineWidthAllowed.GetValue(processor);
            var appendSpace = (bool)access.AppendSpaceBeforeNextWord.GetValue(processor);
            var prefixWidth = appendSpace ? widthOfSpace : 0f;
            var firstAvailable = maxWidth - currentX - currentWidth - prefixWidth;
            var fullAvailable = Math.Max(0f, maxWidth - wrappedShift);
            var pieces = CjkLineBreaker.SplitWord(word, firstAvailable, fullAvailable,
                value => measure(font, value).Width);

            if (pieces.Count > 0 && measure(font, pieces[0]).Width > firstAvailable &&
                builder.Length > 0)
            {
                access.FinishFullLine.Invoke(processor, null);
                builder = (StringBuilder)access.TextSoFar.GetValue(processor);
                appendSpace = false;
                currentWidth = GetFloat(access.WidthOfTextSoFar, processor);
                pieces = CjkLineBreaker.SplitWord(word, fullAvailable, fullAvailable,
                    value => measure(font, value).Width);
            }

            for (var index = 0; index < pieces.Count; index++)
            {
                if (index > 0)
                {
                    access.FinishFullLine.Invoke(processor, null);
                    builder = (StringBuilder)access.TextSoFar.GetValue(processor);
                    currentWidth = GetFloat(access.WidthOfTextSoFar, processor);
                    appendSpace = false;
                }
                if (appendSpace)
                {
                    builder.Append(' ');
                    currentWidth += widthOfSpace;
                    appendSpace = false;
                }
                var piece = pieces[index];
                var measured = measure(font, piece);
                builder.Append(piece);
                currentWidth += measured.Width;
                access.WidthOfTextSoFar.SetValue(processor, currentWidth);
                access.LineHeight.SetValue(processor,
                    Math.Max(GetFloat(access.LineHeight, processor), measured.Height));
            }

            access.AppendSpaceBeforeNextWord.SetValue(processor, true);
            var splitter = access.WordsInLine.GetValue(processor);
            var next = (string)access.SplitterNext.Invoke(splitter, null);
            access.WordsInLine.SetValue(processor, splitter);
            access.Word.SetValue(processor, next);
        }

        public static void ProcessOriginal(object processor)
        {
            if (processor == null) throw new ArgumentNullException("processor");
            Resolve(processor.GetType()).OriginalWordMethod.Invoke(processor, null);
        }

        private static float GetFloat(FieldInfo field, object instance)
        {
            return Convert.ToSingle(field.GetValue(instance));
        }

        private static Accessors Resolve(Type type)
        {
            lock (Gate)
            {
                Accessors access;
                if (!Cache.TryGetValue(type, out access))
                {
                    access = new Accessors(type);
                    Cache.Add(type, access);
                }
                return access;
            }
        }

        private sealed class Accessors
        {
            private const BindingFlags Flags = BindingFlags.Instance |
                BindingFlags.Public | BindingFlags.NonPublic;

            public Accessors(Type type)
            {
                ChunkFont = Field(type, "ChunkFont");
                Word = Field(type, "Word");
                CurrentX = Field(type, "CurrentX");
                WidthOfTextSoFar = Field(type, "WidthOfTextSoFar");
                WidthOfSpace = Field(type, "WidthOfSpace");
                TextSoFar = Field(type, "TextSoFar");
                MaxLineWidthAllowed = Field(type, "MaxLineWidthAllowed");
                WrappedLineShiftX = Field(type, "WrappedLineShiftX");
                LineHeight = Field(type, "LineHeight");
                AppendSpaceBeforeNextWord = Field(type, "AppendSpaceBeforeNextWord");
                WordsInLine = Field(type, "WordsInLine");
                OriginalWordMethod = Method(type, "ProcessChunk_Normal_Word");
                FinishFullLine = Method(type, "ProcessChunk_Normal_FinishFullLine");
                SplitterNext = Method(WordsInLine.FieldType, "Next");
            }

            public readonly FieldInfo ChunkFont;
            public readonly FieldInfo Word;
            public readonly FieldInfo CurrentX;
            public readonly FieldInfo WidthOfTextSoFar;
            public readonly FieldInfo WidthOfSpace;
            public readonly FieldInfo TextSoFar;
            public readonly FieldInfo MaxLineWidthAllowed;
            public readonly FieldInfo WrappedLineShiftX;
            public readonly FieldInfo LineHeight;
            public readonly FieldInfo AppendSpaceBeforeNextWord;
            public readonly FieldInfo WordsInLine;
            public readonly MethodInfo OriginalWordMethod;
            public readonly MethodInfo FinishFullLine;
            public readonly MethodInfo SplitterNext;

            private static FieldInfo Field(Type type, string name)
            {
                return type.GetField(name, Flags) ??
                    throw new MissingFieldException(type.FullName, name);
            }

            private static MethodInfo Method(Type type, string name)
            {
                return type.GetMethod(name, Flags) ??
                    throw new MissingMethodException(type.FullName, name);
            }
        }
    }
}
