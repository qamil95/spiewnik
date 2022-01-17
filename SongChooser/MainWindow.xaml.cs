using SonglistGenerator;
using System.Collections.Generic;
using System.IO;
using System.Windows;

namespace SongChooser
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        private ConsoleLogger logger;
        private Generator generator;
        private List<DisplaySong> displayedSongs;

        public MainWindow()
        {
            InitializeComponent();
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            this.logger = new ConsoleLogger();
        }

        private void LoadFolder(object sender, RoutedEventArgs e)
        {
            generator = new Generator(this.logger, folderPath.Text) { MinimumAllowedChapterSize = (int)minimumAllowedChapterSize.Value };
            generator.Initialize();

            this.displayedSongs = new List<DisplaySong>();

            foreach (var chapter in this.generator.Chapters)
            {
                foreach (var song in chapter.Songs)
                {
                    this.displayedSongs.Add(new DisplaySong(song, chapter.ChapterName));
                }
            }

            this.dataGrid.ItemsSource = this.displayedSongs;
        }

        private void LoadSettings(object sender, RoutedEventArgs e)
        {
            var loadedContent = File.ReadAllLines(Path.Combine(folderPath.Text, "settings.txt"));
            foreach (var line in loadedContent)
            {
                var loadedSong = line.Split(';');
                var songToUpdate = this.displayedSongs.Find(x => x.Chapter == loadedSong[0] && x.Title == loadedSong[1]);
                songToUpdate.NewSong = false;
                songToUpdate.Print = loadedSong[2] == "True";
            }
        }

        private void SaveSettings(object sender, RoutedEventArgs e)
        {
            var saveContent = new List<string>();
            foreach (var song in this.displayedSongs)
            {
                saveContent.Add($"{song.Chapter};{song.Title};{song.Print}");
            }
            File.WriteAllLines(Path.Combine(folderPath.Text, "settings.txt"), saveContent);
        }

        private void GenerateSongbook(object sender, RoutedEventArgs e)
        {
            foreach (var chapter in this.generator.Chapters)
            {
                chapter.Songs.RemoveAll(x => this.displayedSongs.Exists(y => !y.Print && y.Path == x.FilePath));
            }

            this.generator.Generate();
        }

        private void dataGrid_MouseDoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            var songView = new SongView(dataGrid);
            songView.Show();
        }
    }
}
