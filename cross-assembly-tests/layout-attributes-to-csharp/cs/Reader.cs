using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace LayoutAttributesReader;

// Reads the layouts a ghūl library declared through StructLayout and
// FieldOffset, which the runtime takes from the type's layout metadata
// rather than from the attributes themselves.
public class Reader
{
    static string Offset<T>(string field) => $"{field}@{Marshal.OffsetOf<T>(field)}";

    public static string Read()
    {
        var overlay = new LayoutAttributesToCSharp.OVERLAY(0x00020001);

        return string.Join("\n",
            $"overlay: {Offset<LayoutAttributesToCSharp.OVERLAY>("whole")} {Offset<LayoutAttributesToCSharp.OVERLAY>("low")} {Offset<LayoutAttributesToCSharp.OVERLAY>("high")} size {Marshal.SizeOf<LayoutAttributesToCSharp.OVERLAY>()}, low {overlay.low} high {overlay.high}",
            $"packed: {Offset<LayoutAttributesToCSharp.PACKED>("a")} {Offset<LayoutAttributesToCSharp.PACKED>("b")} size {Marshal.SizeOf<LayoutAttributesToCSharp.PACKED>()}",
            $"sized: size {Marshal.SizeOf<LayoutAttributesToCSharp.SIZED>()}",
            $"record: {Offset<LayoutAttributesToCSharp.RECORD>("first")} {Offset<LayoutAttributesToCSharp.RECORD>("second")} size {Marshal.SizeOf<LayoutAttributesToCSharp.RECORD>()}");
    }
}
