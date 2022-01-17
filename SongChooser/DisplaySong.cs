using SonglistGenerator;

namespace SongChooser
{
    class DisplaySong
    {
        public readonly Song song;

        public DisplaySong(Song song, string chapter)
        {
            this.song = song;
            this.Chapter = chapter;
            this.Print = true;
            this.NewSong = true;
        }
        public string Chapter { get; }
        public bool Print { get; set; }
        public string Title { get => song.Title; }
        public string Author { get => song.Author; }
        public string Artist { get => song.Artist; }
        public string Path { get => song.FilePath; }
        public bool NewSong { get; set; }
    }
}
