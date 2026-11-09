namespace TwoArgumentIndexer;

public class Board
{
    private readonly string[] cells = new string[12];

    public string this[int row, int column]
    {
        get => cells[row * 4 + column] ?? ".";
        set => cells[row * 4 + column] = value;
    }

    public int this[string name, int offset] => name.Length + offset;
}
