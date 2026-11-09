namespace Rectangular;

public static class Grids
{
    public static int[,] Make() => new int[2, 3];

    public static int Rank(int[,] grid) => grid.Rank;

    public static int[][] Jagged() => new[] { new[] { 1 } };

    public static int[,]? Field;
}
