using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace SonglistGenerator
{
    /// <summary>
    /// Representation of each song_title.tex file
    /// </summary>
    public class Song : IDiskLocationRepresentation
    {
        List<string> songFileContent;

        public Song(string filePath)
        {
            this.FilePath = filePath;
        }

        public void Initialize()
        {
            this.songFileContent = File.ReadAllLines(this.FilePath).ToList();

            var titleLine = this.songFileContent.Single(x => x.StartsWith("\\tytul"));

            if (!titleLine.ContainsThreeOpeningCurlyBraces())
            {
                // Title section is split into separate lines
                var mergedContent = string.Join("", this.songFileContent);
                var from = mergedContent.IndexOf("\\tytul") + "\\tytul".Length;
                var to = mergedContent.IndexOf("\\begin");
                titleLine = mergedContent[from..to];
            }

            var splitTitleLine = Regex.Matches(titleLine, "\\{(.*?)\\}");

            this.Title = splitTitleLine[0].Value;
            this.Author = splitTitleLine[1].Value;
            this.Artist = splitTitleLine[2].Value;

            var textStart = this.songFileContent.FindIndex(x => x.StartsWith("\\begin{text")) + 1;
            var textEnd = this.songFileContent.FindIndex(x => x.StartsWith("\\end{text"));

            var chordsStart = this.songFileContent.FindIndex(x => x.StartsWith("\\begin{chord")) + 1;
            var chordsEnd = this.songFileContent.FindIndex(x => x.StartsWith("\\end{chord"));

            this.Text = this.songFileContent.Take(new Range(new Index(textStart), new Index(textEnd))).ToList();

            if (chordsStart == 0 && chordsEnd == -1)
            {
                this.Chords = new List<string> { "BRAK CHWYTÓW" };
            }
            else
            {
                this.Chords = this.songFileContent.Take(new Range(new Index(chordsStart), new Index(chordsEnd))).ToList();
            }
        }

        public string FilePath { get; private set; }

        public string ContainingFolder => Path.GetFileName(Path.GetDirectoryName(this.FilePath));

        public string FileName => Path.GetFileName(this.FilePath);

        /// <summary>
        /// Song title, first {} in \tytul section.
        /// </summary>
        public string Title { get; private set; }

        /// <summary>
        /// Song author (text, music), second {} in \tytul section.
        /// </summary>
        public string Author { get; private set; }

        /// <summary>
        /// Song artist, third {} in \tytul section.
        /// Additionally used in "Rozne" directory, to allow multiple artists in one category.
        /// Visible if "\Zespoltrue" set in chapter master.tex file, otherwise ignored.
        /// </summary>
        public string Artist { get; private set; }

        /// <summary>
        /// First line of song, to use in alphabetical table of content.
        /// </summary>
        //string FirstLine { get; }

        /// <summary>
        /// First line of chorus, to use in alphabetical table of content.
        /// </summary>
        //string FirstLineOfChorus { get; }

        public List<string> Text { get; private set; }

        public List<string> Chords { get; private set; }

        public override string ToString()
        {
            return $"{this.Artist} - {this.Title}";
        }
    }
}
