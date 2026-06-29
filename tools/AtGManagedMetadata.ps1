$ErrorActionPreference = "Stop"

if ("AtG.ManagedMetadataReader" -as [type]) {
    return
}

Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AtG {
    public sealed class LdstrRecord {
        public string AssemblyName;
        public string DllPath;
        public string TypeFullName;
        public string MethodName;
        public int MethodToken;
        public int StringToken;
        public int ILOffset;
        public int UserStringHeapOffset;
        public int UserStringEntryBytes;
        public byte UserStringTerminalByte;
        public string Value;
        public int Length;
    }

    public sealed class PatchSpec {
        public string Original;
        public string Translation;
        public int MethodToken;
        public int StringToken;
        public string TypeFullName;
        public string MethodName;
        public bool Optional;
    }

    public sealed class PatchResult {
        public string Original;
        public string Translation;
        public int MatchCount;
        public int HeapPatchCount;
    }

    public static class ManagedMetadataReader {
        private struct Section {
            public uint VirtualAddress;
            public uint VirtualSize;
            public uint RawPointer;
            public uint RawSize;
        }

        private sealed class Metadata {
            public byte[] Bytes;
            public string Path;
            public int MetadataOffset;
            public int TablesOffset;
            public int StringsOffset;
            public int UserStringsOffset;
            public int UserStringsSize;
            public int BlobOffset;
            public byte HeapSizes;
            public int[] RowCounts;
            public int[] TableOffsets;
            public List<Section> Sections;
            public string AssemblyName;

            public int StringIndexSize { get { return (HeapSizes & 0x01) != 0 ? 4 : 2; } }
            public int GuidIndexSize { get { return (HeapSizes & 0x02) != 0 ? 4 : 2; } }
            public int BlobIndexSize { get { return (HeapSizes & 0x04) != 0 ? 4 : 2; } }
        }

        private sealed class TypeRow {
            public string FullName;
            public int MethodList;
        }

        private sealed class MethodRow {
            public uint Rva;
            public string Name;
        }

        public static LdstrRecord[] GetLdstrRecords(string path) {
            Metadata md = LoadMetadata(path);
            TypeRow[] types = ReadTypeRows(md);
            MethodRow[] methods = ReadMethodRows(md);
            List<LdstrRecord> records = new List<LdstrRecord>();

            for (int typeIndex = 0; typeIndex < types.Length; typeIndex++) {
                int start = types[typeIndex].MethodList;
                int end = methods.Length + 1;
                if (typeIndex + 1 < types.Length) {
                    end = types[typeIndex + 1].MethodList;
                }

                if (start < 1) {
                    continue;
                }
                if (end < start) {
                    end = start;
                }
                if (end > methods.Length + 1) {
                    end = methods.Length + 1;
                }

                for (int methodRid = start; methodRid < end; methodRid++) {
                    if (methodRid < 1 || methodRid > methods.Length) {
                        continue;
                    }
                    MethodRow method = methods[methodRid - 1];
                    if (method.Rva == 0) {
                        continue;
                    }

                    int bodyOffset;
                    try {
                        bodyOffset = RvaToOffset(md, method.Rva);
                    }
                    catch {
                        continue;
                    }

                    int codeOffset;
                    int codeSize;
                    if (!TryReadMethodBody(md.Bytes, bodyOffset, out codeOffset, out codeSize)) {
                        continue;
                    }

                    int codeEnd = codeOffset + codeSize;
                    if (codeOffset < 0 || codeEnd > md.Bytes.Length) {
                        continue;
                    }

                    for (int p = codeOffset; p <= codeEnd - 5; p++) {
                        if (md.Bytes[p] != 0x72) {
                            continue;
                        }

                        int token = ReadI32(md.Bytes, p + 1);
                        if ((token & unchecked((int)0xff000000)) != 0x70000000) {
                            continue;
                        }

                        int userStringIndex = token & 0x00ffffff;
                        UserStringValue value;
                        if (!TryReadUserString(md, userStringIndex, out value)) {
                            continue;
                        }

                        records.Add(new LdstrRecord {
                            AssemblyName = md.AssemblyName,
                            DllPath = path,
                            TypeFullName = types[typeIndex].FullName,
                            MethodName = method.Name,
                            MethodToken = unchecked((int)0x06000000) | methodRid,
                            StringToken = token,
                            ILOffset = p - codeOffset,
                            UserStringHeapOffset = userStringIndex,
                            UserStringEntryBytes = value.EntryBytes,
                            UserStringTerminalByte = value.TerminalByte,
                            Value = value.Text,
                            Length = value.Text == null ? 0 : value.Text.Length
                        });
                    }
                }
            }

            return records.ToArray();
        }

        public static PatchResult[] PatchLdstr(string sourcePath, string outputPath, PatchSpec[] specs) {
            if (specs == null) {
                specs = new PatchSpec[0];
            }

            byte[] bytes = File.ReadAllBytes(sourcePath);
            Metadata md = LoadMetadata(sourcePath, bytes);
            LdstrRecord[] records = GetLdstrRecords(sourcePath);
            List<PatchResult> results = new List<PatchResult>();
            HashSet<int> patchedHeapOffsets = new HashSet<int>();

            foreach (PatchSpec spec in specs) {
                if (spec == null || String.IsNullOrEmpty(spec.Original)) {
                    continue;
                }
                if (spec.Translation == null) {
                    spec.Translation = "";
                }

                List<LdstrRecord> matches = new List<LdstrRecord>();
                foreach (LdstrRecord record in records) {
                    if (record.Value != spec.Original) {
                        continue;
                    }
                    if (spec.MethodToken != 0 && record.MethodToken != spec.MethodToken) {
                        continue;
                    }
                    if (spec.StringToken != 0 && record.StringToken != spec.StringToken) {
                        continue;
                    }
                    if (!String.IsNullOrEmpty(spec.TypeFullName) && record.TypeFullName != spec.TypeFullName) {
                        continue;
                    }
                    if (!String.IsNullOrEmpty(spec.MethodName) && record.MethodName != spec.MethodName) {
                        continue;
                    }
                    matches.Add(record);
                }

                if (matches.Count == 0) {
                    if (spec.Optional) {
                        results.Add(new PatchResult {
                            Original = spec.Original,
                            Translation = spec.Translation,
                            MatchCount = 0,
                            HeapPatchCount = 0
                        });
                        continue;
                    }
                    throw new InvalidOperationException("IL string source not found: " + spec.Original);
                }

                int heapPatchCount = 0;
                foreach (LdstrRecord match in matches) {
                    if (patchedHeapOffsets.Contains(match.UserStringHeapOffset)) {
                        continue;
                    }

                    byte[] encoded = EncodeUserString(spec.Translation, match.UserStringTerminalByte);
                    if (encoded.Length > match.UserStringEntryBytes) {
                        throw new InvalidOperationException(
                            "Replacement is longer than existing #US heap entry for '" +
                            spec.Original + "'. Original entry bytes: " + match.UserStringEntryBytes +
                            ", replacement entry bytes: " + encoded.Length + "."
                        );
                    }

                    int absolute = md.UserStringsOffset + match.UserStringHeapOffset;
                    Array.Copy(encoded, 0, bytes, absolute, encoded.Length);
                    for (int i = encoded.Length; i < match.UserStringEntryBytes; i++) {
                        bytes[absolute + i] = 0;
                    }
                    patchedHeapOffsets.Add(match.UserStringHeapOffset);
                    heapPatchCount++;
                }

                results.Add(new PatchResult {
                    Original = spec.Original,
                    Translation = spec.Translation,
                    MatchCount = matches.Count,
                    HeapPatchCount = heapPatchCount
                });
            }

            string outDir = Path.GetDirectoryName(outputPath);
            if (!String.IsNullOrEmpty(outDir)) {
                Directory.CreateDirectory(outDir);
            }
            File.WriteAllBytes(outputPath, bytes);
            return results.ToArray();
        }

        private struct UserStringValue {
            public string Text;
            public int EntryBytes;
            public byte TerminalByte;
        }

        private static bool TryReadUserString(Metadata md, int index, out UserStringValue value) {
            value = new UserStringValue();
            if (index < 0 || index >= md.UserStringsSize) {
                return false;
            }

            int p = md.UserStringsOffset + index;
            int length;
            int prefixBytes;
            if (!TryReadCompressedUInt(md.Bytes, p, out length, out prefixBytes)) {
                return false;
            }

            if (length < 0 || index + prefixBytes + length > md.UserStringsSize) {
                return false;
            }

            int textBytes = length > 0 ? length - 1 : 0;
            if (textBytes < 0) {
                return false;
            }
            if ((textBytes % 2) != 0) {
                textBytes--;
            }

            value.Text = textBytes == 0 ? "" : Encoding.Unicode.GetString(md.Bytes, p + prefixBytes, textBytes);
            value.EntryBytes = prefixBytes + length;
            value.TerminalByte = length > 0 ? md.Bytes[p + prefixBytes + length - 1] : (byte)0;
            return true;
        }

        private static byte[] EncodeUserString(string text, byte terminalByte) {
            byte[] textBytes = Encoding.Unicode.GetBytes(text == null ? "" : text);
            int length = textBytes.Length + 1;
            byte[] prefix = EncodeCompressedUInt(length);
            byte[] output = new byte[prefix.Length + length];
            Array.Copy(prefix, 0, output, 0, prefix.Length);
            Array.Copy(textBytes, 0, output, prefix.Length, textBytes.Length);
            output[output.Length - 1] = terminalByte;
            return output;
        }

        private static byte[] EncodeCompressedUInt(int value) {
            if (value < 0) {
                throw new ArgumentOutOfRangeException("value");
            }
            if (value <= 0x7f) {
                return new byte[] { (byte)value };
            }
            if (value <= 0x3fff) {
                return new byte[] {
                    (byte)(((value >> 8) & 0x3f) | 0x80),
                    (byte)(value & 0xff)
                };
            }
            return new byte[] {
                (byte)(((value >> 24) & 0x1f) | 0xc0),
                (byte)((value >> 16) & 0xff),
                (byte)((value >> 8) & 0xff),
                (byte)(value & 0xff)
            };
        }

        private static bool TryReadCompressedUInt(byte[] bytes, int offset, out int value, out int bytesRead) {
            value = 0;
            bytesRead = 0;
            if (offset < 0 || offset >= bytes.Length) {
                return false;
            }

            byte b0 = bytes[offset];
            if ((b0 & 0x80) == 0) {
                value = b0;
                bytesRead = 1;
                return true;
            }
            if ((b0 & 0xc0) == 0x80) {
                if (offset + 1 >= bytes.Length) {
                    return false;
                }
                value = ((b0 & 0x3f) << 8) | bytes[offset + 1];
                bytesRead = 2;
                return true;
            }
            if ((b0 & 0xe0) == 0xc0) {
                if (offset + 3 >= bytes.Length) {
                    return false;
                }
                value = ((b0 & 0x1f) << 24) |
                        (bytes[offset + 1] << 16) |
                        (bytes[offset + 2] << 8) |
                        bytes[offset + 3];
                bytesRead = 4;
                return true;
            }
            return false;
        }

        private static Metadata LoadMetadata(string path) {
            return LoadMetadata(path, File.ReadAllBytes(path));
        }

        private static Metadata LoadMetadata(string path, byte[] bytes) {
            if (bytes.Length < 0x40 || ReadU16(bytes, 0) != 0x5a4d) {
                throw new InvalidOperationException("Not a PE file: " + path);
            }

            int pe = (int)ReadU32(bytes, 0x3c);
            if (ReadU32(bytes, pe) != 0x00004550) {
                throw new InvalidOperationException("Missing PE signature: " + path);
            }

            int sectionCount = ReadU16(bytes, pe + 6);
            int optionalHeaderSize = ReadU16(bytes, pe + 20);
            int optional = pe + 24;
            int magic = ReadU16(bytes, optional);
            int dataDirectory = magic == 0x20b ? optional + 112 : optional + 96;
            uint cliRva = ReadU32(bytes, dataDirectory + 14 * 8);
            if (cliRva == 0) {
                throw new InvalidOperationException("No CLR header found: " + path);
            }

            List<Section> sections = new List<Section>();
            int sectionOffset = optional + optionalHeaderSize;
            for (int i = 0; i < sectionCount; i++) {
                int s = sectionOffset + i * 40;
                sections.Add(new Section {
                    VirtualSize = ReadU32(bytes, s + 8),
                    VirtualAddress = ReadU32(bytes, s + 12),
                    RawSize = ReadU32(bytes, s + 16),
                    RawPointer = ReadU32(bytes, s + 20)
                });
            }

            Metadata md = new Metadata();
            md.Bytes = bytes;
            md.Path = path;
            md.Sections = sections;
            md.AssemblyName = Path.GetFileNameWithoutExtension(path);

            int cli = RvaToOffset(md, cliRva);
            uint metadataRva = ReadU32(bytes, cli + 8);
            int metadata = RvaToOffset(md, metadataRva);
            md.MetadataOffset = metadata;
            if (ReadU32(bytes, metadata) != 0x424a5342) {
                throw new InvalidOperationException("Missing CLR metadata signature: " + path);
            }

            int p = metadata + 4;
            p += 2; // major
            p += 2; // minor
            p += 4; // reserved
            int versionLength = (int)ReadU32(bytes, p);
            p += 4 + versionLength;
            p = Align4(p);
            p += 2; // flags
            int streamCount = ReadU16(bytes, p);
            p += 2;

            int tablesStream = 0;
            int stringsStream = 0;
            int userStringsStream = 0;
            int userStringsSize = 0;
            int blobStream = 0;

            for (int i = 0; i < streamCount; i++) {
                uint offset = ReadU32(bytes, p);
                uint size = ReadU32(bytes, p + 4);
                p += 8;
                int nameStart = p;
                while (p < bytes.Length && bytes[p] != 0) {
                    p++;
                }
                string name = Encoding.ASCII.GetString(bytes, nameStart, p - nameStart);
                p++;
                p = Align4(p);

                if (name == "#~" || name == "#-") {
                    tablesStream = metadata + (int)offset;
                }
                else if (name == "#Strings") {
                    stringsStream = metadata + (int)offset;
                }
                else if (name == "#US") {
                    userStringsStream = metadata + (int)offset;
                    userStringsSize = (int)size;
                }
                else if (name == "#Blob") {
                    blobStream = metadata + (int)offset;
                }
            }

            if (tablesStream == 0 || stringsStream == 0 || userStringsStream == 0 || blobStream == 0) {
                throw new InvalidOperationException("Required CLR metadata streams were not found: " + path);
            }

            md.TablesOffset = tablesStream;
            md.StringsOffset = stringsStream;
            md.UserStringsOffset = userStringsStream;
            md.UserStringsSize = userStringsSize;
            md.BlobOffset = blobStream;

            ParseTableLayout(md);
            return md;
        }

        private static void ParseTableLayout(Metadata md) {
            byte[] bytes = md.Bytes;
            int p = md.TablesOffset;
            p += 4; // reserved
            p += 1; // major
            p += 1; // minor
            md.HeapSizes = bytes[p];
            p += 1;
            p += 1; // reserved
            ulong valid = ReadU64(bytes, p);
            p += 8;
            p += 8; // sorted

            md.RowCounts = new int[64];
            md.TableOffsets = new int[64];
            for (int table = 0; table < 64; table++) {
                if (((valid >> table) & 1UL) != 0) {
                    md.RowCounts[table] = (int)ReadU32(bytes, p);
                    p += 4;
                }
            }

            for (int table = 0; table < 64; table++) {
                if (md.RowCounts[table] > 0) {
                    md.TableOffsets[table] = p;
                    p += RowSize(md, table) * md.RowCounts[table];
                }
            }
        }

        private static TypeRow[] ReadTypeRows(Metadata md) {
            int count = md.RowCounts[2];
            TypeRow[] rows = new TypeRow[count];
            int p = md.TableOffsets[2];
            int extendsSize = CodedIndexSize(md, new int[] { 2, 1, 27 }, 2);
            int fieldIndexSize = TableIndexSize(md, 4);
            int methodIndexSize = TableIndexSize(md, 6);

            for (int i = 0; i < count; i++) {
                p += 4; // flags
                int nameIndex = ReadIndex(md.Bytes, p, md.StringIndexSize);
                p += md.StringIndexSize;
                int namespaceIndex = ReadIndex(md.Bytes, p, md.StringIndexSize);
                p += md.StringIndexSize;
                p += extendsSize;
                p += fieldIndexSize;
                int methodList = ReadIndex(md.Bytes, p, methodIndexSize);
                p += methodIndexSize;

                string name = ReadMetadataString(md, nameIndex);
                string ns = ReadMetadataString(md, namespaceIndex);
                rows[i] = new TypeRow {
                    FullName = String.IsNullOrEmpty(ns) ? name : ns + "." + name,
                    MethodList = methodList
                };
            }
            return rows;
        }

        private static MethodRow[] ReadMethodRows(Metadata md) {
            int count = md.RowCounts[6];
            MethodRow[] rows = new MethodRow[count];
            int p = md.TableOffsets[6];
            int paramIndexSize = TableIndexSize(md, 8);

            for (int i = 0; i < count; i++) {
                uint rva = ReadU32(md.Bytes, p);
                p += 4;
                p += 2; // impl flags
                p += 2; // flags
                int nameIndex = ReadIndex(md.Bytes, p, md.StringIndexSize);
                p += md.StringIndexSize;
                p += md.BlobIndexSize;
                p += paramIndexSize;
                rows[i] = new MethodRow {
                    Rva = rva,
                    Name = ReadMetadataString(md, nameIndex)
                };
            }
            return rows;
        }

        private static bool TryReadMethodBody(byte[] bytes, int offset, out int codeOffset, out int codeSize) {
            codeOffset = 0;
            codeSize = 0;
            if (offset < 0 || offset >= bytes.Length) {
                return false;
            }

            byte first = bytes[offset];
            int format = first & 0x03;
            if (format == 0x02) {
                codeSize = first >> 2;
                codeOffset = offset + 1;
                return true;
            }

            if (format == 0x03) {
                if (offset + 12 > bytes.Length) {
                    return false;
                }
                int flags = ReadU16(bytes, offset);
                int headerDwords = (flags >> 12) & 0x0f;
                if (headerDwords == 0) {
                    return false;
                }
                codeSize = (int)ReadU32(bytes, offset + 4);
                codeOffset = offset + headerDwords * 4;
                return true;
            }

            return false;
        }

        private static int RowSize(Metadata md, int table) {
            int str = md.StringIndexSize;
            int guid = md.GuidIndexSize;
            int blob = md.BlobIndexSize;
            switch (table) {
                case 0: return 2 + str + guid + guid + guid;
                case 1: return CodedIndexSize(md, new int[] { 0, 26, 35, 1 }, 2) + str + str;
                case 2: return 4 + str + str + CodedIndexSize(md, new int[] { 2, 1, 27 }, 2) + TableIndexSize(md, 4) + TableIndexSize(md, 6);
                case 3: return TableIndexSize(md, 4);
                case 4: return 2 + str + blob;
                case 5: return TableIndexSize(md, 6);
                case 6: return 4 + 2 + 2 + str + blob + TableIndexSize(md, 8);
                case 7: return TableIndexSize(md, 8);
                case 8: return 2 + 2 + str;
                case 9: return TableIndexSize(md, 2) + CodedIndexSize(md, new int[] { 2, 1, 27 }, 2);
                case 10: return CodedIndexSize(md, new int[] { 2, 1, 26, 6, 27 }, 3) + str + blob;
                case 11: return 2 + CodedIndexSize(md, new int[] { 4, 8, 23 }, 2) + blob;
                case 12: return CodedIndexSize(md, new int[] { 6, 4, 1, 2, 8, 9, 10, 0, 14, 23, 20, 17, 26, 27, 32, 35, 38, 39, 40, 42, 43, 44 }, 5) + CodedIndexSize(md, new int[] { 0, 0, 6, 10, 0 }, 3) + blob;
                case 13: return CodedIndexSize(md, new int[] { 4, 8 }, 1) + blob;
                case 14: return 2 + CodedIndexSize(md, new int[] { 2, 6, 32 }, 2) + blob;
                case 15: return 2 + 4 + TableIndexSize(md, 2);
                case 16: return 4 + TableIndexSize(md, 4);
                case 17: return blob;
                case 18: return TableIndexSize(md, 2) + TableIndexSize(md, 20);
                case 19: return TableIndexSize(md, 20);
                case 20: return 2 + str + CodedIndexSize(md, new int[] { 2, 1, 27 }, 2);
                case 21: return TableIndexSize(md, 2) + TableIndexSize(md, 23);
                case 22: return TableIndexSize(md, 23);
                case 23: return 2 + str + blob;
                case 24: return 2 + TableIndexSize(md, 6) + CodedIndexSize(md, new int[] { 20, 23 }, 1);
                case 25: return TableIndexSize(md, 2) + CodedIndexSize(md, new int[] { 6, 10 }, 1) + CodedIndexSize(md, new int[] { 6, 10 }, 1);
                case 26: return str;
                case 27: return blob;
                case 28: return 2 + CodedIndexSize(md, new int[] { 4, 6 }, 1) + str + TableIndexSize(md, 26);
                case 29: return 4 + TableIndexSize(md, 4);
                case 30: return 4 + 4;
                case 31: return 4;
                case 32: return 4 + 2 + 2 + 2 + 2 + 4 + blob + str + str;
                case 33: return 4;
                case 34: return 4 + 4 + 4;
                case 35: return 2 + 2 + 2 + 2 + 4 + blob + str + str + blob;
                case 36: return 4 + TableIndexSize(md, 35);
                case 37: return 4 + 4 + 4 + TableIndexSize(md, 35);
                case 38: return 4 + str + blob;
                case 39: return 4 + 4 + str + str + CodedIndexSize(md, new int[] { 38, 35, 39 }, 2);
                case 40: return 4 + 4 + str + CodedIndexSize(md, new int[] { 38, 35, 39 }, 2);
                case 41: return TableIndexSize(md, 2) + TableIndexSize(md, 2);
                case 42: return 2 + 2 + CodedIndexSize(md, new int[] { 2, 6 }, 1) + str;
                case 43: return CodedIndexSize(md, new int[] { 6, 10 }, 1) + blob;
                case 44: return TableIndexSize(md, 42) + CodedIndexSize(md, new int[] { 2, 1, 27 }, 2);
                default: return 0;
            }
        }

        private static int TableIndexSize(Metadata md, int table) {
            return md.RowCounts[table] < 65536 ? 2 : 4;
        }

        private static int CodedIndexSize(Metadata md, int[] tables, int tagBits) {
            int maxRows = 0;
            for (int i = 0; i < tables.Length; i++) {
                if (tables[i] >= 0 && tables[i] < md.RowCounts.Length && md.RowCounts[tables[i]] > maxRows) {
                    maxRows = md.RowCounts[tables[i]];
                }
            }
            return maxRows < (1 << (16 - tagBits)) ? 2 : 4;
        }

        private static string ReadMetadataString(Metadata md, int index) {
            if (index <= 0) {
                return "";
            }
            int p = md.StringsOffset + index;
            int start = p;
            while (p < md.Bytes.Length && md.Bytes[p] != 0) {
                p++;
            }
            return Encoding.UTF8.GetString(md.Bytes, start, p - start);
        }

        private static int RvaToOffset(Metadata md, uint rva) {
            for (int i = 0; i < md.Sections.Count; i++) {
                Section s = md.Sections[i];
                uint size = Math.Max(s.VirtualSize, s.RawSize);
                if (rva >= s.VirtualAddress && rva < s.VirtualAddress + size) {
                    return (int)(s.RawPointer + (rva - s.VirtualAddress));
                }
            }
            throw new InvalidOperationException("Unable to map RVA 0x" + rva.ToString("x8") + " in " + md.Path);
        }

        private static int ReadIndex(byte[] bytes, int offset, int size) {
            return size == 2 ? ReadU16(bytes, offset) : (int)ReadU32(bytes, offset);
        }

        private static int Align4(int value) {
            return (value + 3) & ~3;
        }

        private static ushort ReadU16(byte[] bytes, int offset) {
            return (ushort)(bytes[offset] | (bytes[offset + 1] << 8));
        }

        private static int ReadI32(byte[] bytes, int offset) {
            return bytes[offset] |
                   (bytes[offset + 1] << 8) |
                   (bytes[offset + 2] << 16) |
                   (bytes[offset + 3] << 24);
        }

        private static uint ReadU32(byte[] bytes, int offset) {
            return (uint)(bytes[offset] |
                         (bytes[offset + 1] << 8) |
                         (bytes[offset + 2] << 16) |
                         (bytes[offset + 3] << 24));
        }

        private static ulong ReadU64(byte[] bytes, int offset) {
            uint lo = ReadU32(bytes, offset);
            uint hi = ReadU32(bytes, offset + 4);
            return ((ulong)hi << 32) | lo;
        }
    }
}
"@
