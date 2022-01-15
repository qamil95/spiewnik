using System.Linq;

namespace SonglistGenerator
{
    internal static class StringExtensions
    {
        public static bool ContainsThreeOpeningCurlyBraces(this string line)
        {
            return line.Count(x => (x == '{')) == 3;
        }
    }
}
