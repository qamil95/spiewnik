using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows.Data;

namespace SongChooser.Converters
{
    public class ListOfStringToJoinedStringConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            return string.Join(Environment.NewLine, (List<string>)value);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
