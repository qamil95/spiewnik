using System.Collections.Generic;

namespace SonglistGenerator;

public class DisplaySong
{
    public DisplaySong(Song song, string chapter) 
        : this(chapter, song.Title, song.Author, song.Artist, song.FilePath, song.Text, song.Chords)
    {
    }

    public DisplaySong(string chapter, string title, string author, string artist, string path, List<string> text, List<string> chords)
    {
        Chapter = chapter;
        Title = title;
        Author = author;
        Artist = artist;
        Path = path;
        Text = text;
        Chords = chords;

        // TODO: Move to another class, WPF-only
        this.Print = true;
        this.NewSong = true;
    }

    public string Chapter { get; }
    public string Title { get; }
    public string Author { get; }
    public string Artist { get; }
    public string Path { get; }
    public List<string> Text { get; }
    public List<string> Chords { get; }
    public bool Print { get; set; }
    public bool NewSong { get; set; }
}
