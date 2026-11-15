namespace Relay;

using CarrierLib;
using Ghul;

// C# reaching the ghūl library's `T?` slots: an unconstrained `T?` is
// `MAYBE<T>` in the metadata, an `int?` is `Nullable<int>`.
public static class Relay
{
    public static string Describe(MAYBE<int> x, int? y) => MIXED.describe<int>(x, y);

    public static string ReadBox(SLOTS<string> box)
    {
        MAYBE<string> item = box.get();
        MAYBE<string> slot = box.slot;
        int? count = box.count;
        return $"item {(item.has_value ? item.value : "absent")} slot {(slot.has_value ? slot.value : "absent")} count {(count.HasValue ? count.Value.ToString() : "absent")}";
    }

    public static SLOTS<int> MakeBox(int item, int? count) => new SLOTS<int>(new MAYBE<int>(item), count);

    public static SLOTS<int> MakeEmptyBox() => new SLOTS<int>(new MAYBE<int>(), null);
}
