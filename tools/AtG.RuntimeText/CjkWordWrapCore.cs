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
        private static readonly object ResidualGate = new object();
        private static readonly Dictionary<string, int> ResidualBudgets =
            new Dictionary<string, int>(StringComparer.Ordinal);
        private static DateTime ResidualBudgetExpiresUtc;

        public static void ProcessWord(object processor,
            Func<object, string, CjkMeasuredText> measure)
        {
            ProcessWord(processor, measure, null);
        }

        public static void ProcessWord(object processor,
            Func<object, string, CjkMeasuredText> measure,
            Func<object, string, float[]> measurePrefixes)
        {
            if (processor == null) throw new ArgumentNullException("processor");
            if (measure == null) throw new ArgumentNullException("measure");
            var access = Resolve(processor.GetType());
            var sourceWord = (string)access.Word.GetValue(processor);
            var word = DisplayStringLocalizer.LocalizeRichText(sourceWord);
            var consumedFollowingWords = 0;
            if (StringComparer.Ordinal.Equals(sourceWord, word) &&
                DisplayStringLocalizer.HasTokenizedRichTextWordSequenceStart(sourceWord))
            {
                List<string> followingWords;
                string sequenceTranslation;
                int sequenceConsumedFollowingWords;
                var splitter = access.WordsInLine.GetValue(processor);
                if (TryGetFollowingWords(access, splitter, out followingWords) &&
                    DisplayStringLocalizer.TryLocalizeRichTextWordSequence(sourceWord,
                        followingWords, out sequenceTranslation,
                        out sequenceConsumedFollowingWords))
                {
                    word = sequenceTranslation;
                    consumedFollowingWords = sequenceConsumedFollowingWords;
                }
            }
            if (sourceWord.IndexOf("unable以", StringComparison.Ordinal) >= 0)
                word = word.Replace("unable以", "无法在冬季留在");
            if (!StringComparer.Ordinal.Equals(sourceWord, word))
                access.Word.SetValue(processor, word);

            // The original composite is tokenized as separate ASCII words
            // after the localized winter prefix. Keep a short-lived, exact
            // budget so their source advances are not added before the
            // following Chinese concept link.
            if (word.IndexOf("无法在冬季留在", StringComparison.Ordinal) >= 0 ||
                sourceWord.IndexOf("unable以", StringComparison.Ordinal) >= 0)
            {
                lock (ResidualGate)
                {
                    ResidualBudgets.Clear();
                    ResidualBudgets["spend"] = 1;
                    ResidualBudgets["the"] = 2;
                    ResidualBudgets["winter"] = 1;
                    ResidualBudgets["inside"] = 1;
                    ResidualBudgetExpiresUtc = DateTime.UtcNow.AddMilliseconds(500);
                }
            }

            var builder = (StringBuilder)access.TextSoFar.GetValue(processor);
            if (TrySuppressLocalizedResidualWord(sourceWord))
            {
                access.AppendSpaceBeforeNextWord.SetValue(processor, false);
                var skipSplitter = access.WordsInLine.GetValue(processor);
                var skipNext = (string)access.SplitterNext.Invoke(skipSplitter, null);
                access.WordsInLine.SetValue(processor, skipSplitter);
                access.Word.SetValue(processor, skipNext);
                return;
            }

            if (!CjkText.ContainsBreakableCjk(word))
            {
                access.OriginalWordMethod.Invoke(processor, null);
                return;
            }

            var font = access.ChunkFont.GetValue(processor);
            var currentX = GetFloat(access.CurrentX, processor);
            var currentWidth = GetFloat(access.WidthOfTextSoFar, processor);
            var widthOfSpace = GetFloat(access.WidthOfSpace, processor);
            var wrappedShift = GetFloat(access.WrappedLineShiftX, processor);
            var maxWidth = (int)access.MaxLineWidthAllowed.GetValue(processor);
            var appendSpace = (bool)access.AppendSpaceBeforeNextWord.GetValue(processor);
            var prefixWidth = appendSpace ? widthOfSpace : 0f;
            var firstAvailable = maxWidth - currentX - currentWidth - prefixWidth;
            var fullAvailable = Math.Max(0f, maxWidth - wrappedShift);
            var prefixWidths = measurePrefixes == null ? null : measurePrefixes(font, word);
            var pieces = prefixWidths == null
                ? CjkLineBreaker.SplitWord(word, firstAvailable, fullAvailable,
                    value => measure(font, value).Width)
                : CjkLineBreaker.SplitWord(word, firstAvailable, fullAvailable, prefixWidths);

            if (pieces.Count > 0 && measure(font, pieces[0]).Width > firstAvailable &&
                builder.Length > 0)
            {
                access.FinishFullLine.Invoke(processor, null);
                builder = (StringBuilder)access.TextSoFar.GetValue(processor);
                appendSpace = false;
                currentWidth = GetFloat(access.WidthOfTextSoFar, processor);
                pieces = prefixWidths == null
                    ? CjkLineBreaker.SplitWord(word, fullAvailable, fullAvailable,
                        value => measure(font, value).Width)
                    : CjkLineBreaker.SplitWord(word, fullAvailable, fullAvailable, prefixWidths);
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
            AdvanceWords(access, processor, consumedFollowingWords);
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

        private static bool TrySuppressLocalizedResidualWord(string sourceWord)
        {
            var suppressed = false;
            lock (ResidualGate)
            {
                if (DateTime.UtcNow > ResidualBudgetExpiresUtc)
                {
                    ResidualBudgets.Clear();
                }
                else
                {
                    int count;
                    if (ResidualBudgets.TryGetValue(sourceWord, out count) && count > 0)
                    {
                        if (count == 1) ResidualBudgets.Remove(sourceWord);
                        else ResidualBudgets[sourceWord] = count - 1;
                        suppressed = true;
                    }
                }
            }

            return suppressed;
        }

        private static bool TryGetFollowingWords(Accessors access, object splitter,
            out List<string> words)
        {
            words = null;
            if (splitter == null || access.SplitterText == null ||
                access.SplitterStartIndex == null || access.SplitterLength == null ||
                access.SplitterDelimiter == null) return false;

            var source = access.SplitterText.GetValue(splitter) as string;
            if (source == null) return false;
            var startIndex = Convert.ToInt32(access.SplitterStartIndex.GetValue(splitter));
            var length = Convert.ToInt32(access.SplitterLength.GetValue(splitter));
            if (length < 0 || length > source.Length || startIndex < 0 || startIndex > length)
                return false;

            var delimiter = Convert.ToChar(access.SplitterDelimiter.GetValue(splitter));
            words = new List<string>();
            while (startIndex < length)
            {
                var endIndex = source.IndexOf(delimiter, startIndex);
                if (endIndex < 0 || endIndex > length) endIndex = length;
                words.Add(source.Substring(startIndex, endIndex - startIndex));
                startIndex = endIndex + 1;
            }
            return true;
        }

        private static void AdvanceWords(Accessors access, object processor,
            int consumedFollowingWords)
        {
            var splitter = access.WordsInLine.GetValue(processor);
            string next = null;
            for (var index = 0; index <= consumedFollowingWords; index++)
                next = (string)access.SplitterNext.Invoke(splitter, null);
            access.WordsInLine.SetValue(processor, splitter);
            access.Word.SetValue(processor, next);
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
                SplitterText = OptionalField(WordsInLine.FieldType, "str");
                SplitterDelimiter = OptionalField(WordsInLine.FieldType, "delimeter");
                SplitterStartIndex = OptionalField(WordsInLine.FieldType, "startIndex");
                SplitterLength = OptionalField(WordsInLine.FieldType, "length");
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
            public readonly FieldInfo SplitterText;
            public readonly FieldInfo SplitterDelimiter;
            public readonly FieldInfo SplitterStartIndex;
            public readonly FieldInfo SplitterLength;

            private static FieldInfo Field(Type type, string name)
            {
                return type.GetField(name, Flags) ??
                    throw new MissingFieldException(type.FullName, name);
            }

            private static FieldInfo OptionalField(Type type, string name)
            {
                return type.GetField(name, Flags);
            }

            private static MethodInfo Method(Type type, string name)
            {
                return type.GetMethod(name, Flags) ??
                    throw new MissingMethodException(type.FullName, name);
            }
        }
    }
}
