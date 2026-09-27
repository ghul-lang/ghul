namespace CsLib;

public static class Tools
{
    [Obsolete("use Add instead")]
    public static int Plus(int a, int b) => a + b;

    public static int Add(int a, int b) => a + b;

    [Obsolete("gone", true)]
    public static int Minus(int a, int b) => a - b;
}

[Obsolete]
public class OldThing
{
    public int Value => 1;
}
