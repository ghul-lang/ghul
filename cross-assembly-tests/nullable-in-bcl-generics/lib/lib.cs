namespace NullableGenerics {
    // BCL generics instantiated at a value-type `int?`, which is
    // `Nullable<int>` in every one of these signatures, in both directions.
    public static class Source {
        public static List<int?> Numbers() => new List<int?> { 1, null, 3 };

        public static Dictionary<string, int?> Scores() =>
            new Dictionary<string, int?> { ["alice"] = 10, ["bob"] = null };

        public static IEnumerable<int?> Stream() {
            yield return null;
            yield return 5;
        }
    }

    public static class Sink {
        public static string Count(IEnumerable<int?> values) =>
            $"{values.Count(v => v.HasValue)} present of {values.Count()}";

        public static string Keys(Dictionary<string, int?> scores) =>
            string.Join(",", scores.OrderBy(p => p.Key).Select(p => $"{p.Key}={(p.Value.HasValue ? p.Value.Value.ToString() : "null")}"));

        public static int Sum(List<int?> values) => values.Sum(v => v ?? 0);
    }
}
