using SonglistGenerator;
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;

namespace SongChooser
{
    /// <summary>
    /// Interaction logic for SongView.xaml
    /// </summary>
    public partial class SongView : Window, INotifyPropertyChanged
    {
        private readonly DataGrid dataGrid;

        public event PropertyChangedEventHandler PropertyChanged;

        private void NotifyPropertyChanged([CallerMemberName] string propertyName = "")
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }

        public Song SelectedSong => (this.dataGrid.SelectedItem as DisplaySong).song;

        public SongView(DataGrid dataGrid)
        {
            this.dataGrid = dataGrid;

            InitializeComponent();
        }

        private void LeftButtonClick(object sender, RoutedEventArgs e)
        {
            dataGrid.SelectedIndex--;
            NotifyPropertyChanged(nameof(SelectedSong));
        }

        private void RightButtonClick(object sender, RoutedEventArgs e)
        {
            dataGrid.SelectedIndex++;
            NotifyPropertyChanged(nameof(SelectedSong));
        }

        private void RandomButtonClick(object sender, RoutedEventArgs e)
        {
            dataGrid.SelectedIndex = new Random().Next(dataGrid.Items.Count);
            NotifyPropertyChanged(nameof(SelectedSong));
        }

        private void OpenFileButtonClick(object sender, RoutedEventArgs e)
        {
            Process.Start(new ProcessStartInfo()
            {
                FileName = SelectedSong.FilePath,
                UseShellExecute = true,
            });
        }
    }
}
