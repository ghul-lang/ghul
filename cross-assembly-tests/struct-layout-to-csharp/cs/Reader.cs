using System;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace StructLayoutReader;

// The same shapes declared in C#, which lays fields out in the order they
// are written. Reading a ghūl struct through one of these gives the right
// values only if ghūl laid its members out in declaration order too.
[StructLayout(LayoutKind.Sequential)]
struct CHeader
{
    public int Kind;
    public short Length;
    public byte Checksum;
}

[StructLayout(LayoutKind.Sequential)]
struct CMixed
{
    public int Zebra;
    public long Apple;
    public short Mango;
}

public class Reader
{
    static string Offsets(Type type) =>
        string.Join(" ", type.GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic)
            .Select(f => $"{f.Name}@{Marshal.OffsetOf(type, f.Name)}"));

    public static string Read()
    {
        var header = new StructLayoutToCSharp.HEADER(7, 300, 9);
        var viewed = Unsafe.As<StructLayoutToCSharp.HEADER, CHeader>(ref header);

        var renamed = new StructLayoutToCSharp.RENAMED_HEADER(7, 300, 9);
        var viewed_renamed = Unsafe.As<StructLayoutToCSharp.RENAMED_HEADER, CHeader>(ref renamed);

        var mixed = new StructLayoutToCSharp.MIXED(1, 2, 3);
        var viewed_mixed = Unsafe.As<StructLayoutToCSharp.MIXED, CMixed>(ref mixed);

        return string.Join("\n",
            $"header: {viewed.Kind} {viewed.Length} {viewed.Checksum}, size {Marshal.SizeOf<StructLayoutToCSharp.HEADER>()}",
            $"offsets: {Offsets(typeof(StructLayoutToCSharp.HEADER))}",
            $"renamed: {viewed_renamed.Kind} {viewed_renamed.Length} {viewed_renamed.Checksum}, size {Marshal.SizeOf<StructLayoutToCSharp.RENAMED_HEADER>()}",
            $"renamed offsets: {Offsets(typeof(StructLayoutToCSharp.RENAMED_HEADER))}",
            $"mixed: {viewed_mixed.Zebra} {viewed_mixed.Apple} {viewed_mixed.Mango}");
    }
}
