using SonglistGenerator;
using System;
using System.Windows;
using System.Windows.Controls;

namespace SongChooser
{
    /// <summary>
    /// Interaction logic for SongView.xaml
    /// </summary>
    public partial class SongView : Window
    {
        private readonly DataGrid dataGrid;
        public Song SelectedSong => (this.dataGrid.SelectedItem as DisplaySong).song;

        public SongView(DataGrid dataGrid)
        {
            this.dataGrid = dataGrid;

            InitializeComponent();
            this.text.Text = string.Join(Environment.NewLine, SelectedSong.Text);
            this.chords.Text = string.Join(Environment.NewLine, SelectedSong.Chords);
        }

        private void LeftButtonClick(object sender, RoutedEventArgs e)
        {
            dataGrid.SelectedIndex--;
        }

        private void RightButtonClick(object sender, RoutedEventArgs e)
        {
            dataGrid.SelectedIndex++;
        }
    }
}
