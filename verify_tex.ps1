#!/usr/bin/env pwsh
# Weryfikator plikow .tex ze spiewnika
$MAIN_DIR = Join-Path $PSScriptRoot "main"

$KNOWN_COMMANDS = @(
    'tytul','begin','end','vin','hfill','break','chordfill',
    'textit','textbf','small','footnotesize','tiny','gtab',
    '\\' # linia kontynuacji
)
$KNOWN_ENVS = @('text','textn','textw','chord','chordw','footTwo','footnotesize')
# Wzorzec do dopasowania wszystkich wariantow text i chord
$TEXT_ENV_RE  = [regex]'\\begin\{(text[nw]?)\}'
$CHORD_ENV_RE = [regex]'\\begin\{(chord[w]?)\}'

# ── ODCZYT Z DETEKCJA KODOWANIA ───────────────────────────────────────────────
function Read-TexFile($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $utf8 = [System.Text.Encoding]::GetEncoding('utf-8',
        [System.Text.EncoderFallback]::ExceptionFallback,
        [System.Text.DecoderFallback]::ExceptionFallback)
    try   { return $utf8.GetString($bytes) }
    catch { return [System.Text.Encoding]::GetEncoding(1250).GetString($bytes) }
}

# ── LICZNIK LINII LOGICZNYCH W BLOKU ─────────────────────────────────────────
# Liczy linie tak jak parser: \\ = nowa linia, pusta linia = separator zwrotki
# Zwraca tablice strofek (kazda strofka to liczba linii)
function Count-Strophes($block) {
    $strophes = [System.Collections.Generic.List[int]]::new()
    $count = 0
    foreach ($line in ($block.Trim() -split "`n")) {
        $t = $line.Trim()
        if ($t -eq '') {
            if ($count -gt 0) { $strophes.Add($count); $count = 0 }
            continue
        }
        $parts = $t -split '\\\\'
        $n = $parts.Count
        if ($parts[-1].Trim() -eq '') { $n-- }
        $count += [Math]::Max(1, $n)
    }
    if ($count -gt 0) { $strophes.Add($count) }
    return [array]$strophes.ToArray()
}

# ── WERYFIKACJA JEDNEGO PLIKU ─────────────────────────────────────────────────
function Verify-File($path, $artistFolder) {
    $issues = @()
    $warn   = @()
    $info   = @()

    $raw = Read-TexFile $path
    $lines = $raw -split "`n"

    # 1. \tytul
    $mTytul = [regex]::Match($raw, '\\tytul\{([^}]*)\}\s*\{([^}]*)\}\s*\{([^}]*)\}')
    if (-not $mTytul.Success) {
        $issues += "Brak lub niepoprawny \tytul{}{}{}"
    } else {
        if ($mTytul.Groups[1].Value.Trim() -eq '') { $issues += "\tytul: pusty tytul" }
        if ($mTytul.Groups[3].Value.Trim() -eq '') { $warn   += "\tytul: pusty trzeci argument (wykonawca)" }
    }

    # 2. Sekcje begin/end - sprawdz dopasowanie tylko dla footTwo
    # (text/chord moga byc textn/textw/chordw - sprawdzamy je osobno)
    $envStack = [System.Collections.Generic.Stack[string]]::new()
    $envErrors = @()
    foreach ($m in [regex]::Matches($raw, '\\(begin|end)\{([^}]+)\}')) {
        $cmd = $m.Groups[1].Value
        $env = $m.Groups[2].Value
        # Sprawdzaj tylko footTwo - text/chord sprawdzamy przez dedykowane regeksy
        if ($env -ne 'footTwo') { continue }
        if ($cmd -eq 'begin') {
            $envStack.Push($env)
        } else {
            if ($envStack.Count -eq 0) {
                $envErrors += "Nadmiarowe \end{$env}"
            } elseif ($envStack.Peek() -ne $env) {
                $envErrors += "\end{$env} nie pasuje do \begin{$($envStack.Peek())}"
                $envStack.Pop() | Out-Null
            } else {
                $envStack.Pop() | Out-Null
            }
        }
    }
    foreach ($e in $envErrors) { $issues += $e }
    while ($envStack.Count -gt 0) {
        $issues += "Niezamkniety \begin{$($envStack.Pop())}"
    }

    # Sprawdz dopasowanie begin/end dla text i chord
    foreach ($pair in @(@('text[nw]?','text'),@('chord[w]?','chord'))) {
        $pat = $pair[0]; $label = $pair[1]
        $begins = ([regex]::Matches($raw, "\\\\begin\\{$pat\\}")).Count
        $ends   = ([regex]::Matches($raw, "\\\\end\\{$pat\\}")).Count
        if ($begins -gt $ends)   { $issues += "Niezamkniety \begin{$label} ($begins begin, $ends end)" }
        elseif ($ends -gt $begins) { $issues += "Nadmiarowe \end{$label} ($begins begin, $ends end)" }
    }

    # 3. Obecnosc sekcji text i chord
    $hasText  = $raw -match '\\begin\{text[nw]?\}'
    $hasChord = $raw -match '\\begin\{chord[w]?\}'
    if (-not $hasText)  { $issues += "Brak sekcji \begin{text}" }
    if (-not $hasChord) { $warn   += "Brak sekcji \begin{chord} (piosenka bez chwytow)" }

    # 4. Puste sekcje
    if ($hasText) {
        $mText = [regex]::Match($raw, '\\begin\{text[nw]?\}([\s\S]*?)\\end\{text[nw]?\}')
        if ($mText.Success -and $mText.Groups[1].Value.Trim() -eq '') {
            $issues += "Pusta sekcja tekstu"
        }
    }
    if ($hasChord) {
        $mChord = [regex]::Match($raw, '\\begin\{chord[w]?\}([\s\S]*?)\\end\{chord[w]?\}')
        if ($mChord.Success -and $mChord.Groups[1].Value.Trim() -eq '') {
            $info += "Pusta sekcja chwytow"
        }
    }

    # 5. Roznica liczby strofek tekst vs chwyty
    if ($hasText -and $hasChord) {
        $mText  = [regex]::Match($raw, '\\begin\{text[nw]?\}([\s\S]*?)\\end\{text[nw]?\}')
        $mChord = [regex]::Match($raw, '\\begin\{chord[w]?\}([\s\S]*?)\\end\{chord[w]?\}')
        if ($mText.Success -and $mChord.Success) {
            $textBlock  = $mText.Groups[1].Value  -replace '\\begin\{footTwo\}|\\end\{footTwo\}', ''
            $chordBlock = $mChord.Groups[1].Value -replace '\\begin\{footTwo\}|\\end\{footTwo\}', ''
            $tStrophes = Count-Strophes $textBlock
            $cStrophes = Count-Strophes $chordBlock
            if ($tStrophes.Count -ne $cStrophes.Count -and $cStrophes.Count -gt 0) {
                $info += "Rozna liczba strofek: tekst=$($tStrophes.Count), chwyty=$($cStrophes.Count)"
            }
        }
    }

    # 6. Niezbalansowane nawiasy klamrowe (poza komentarzami)
    $depth = 0; $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        $l = $line -replace '%.*$', ''  # usun komentarze
        foreach ($ch in $l.ToCharArray()) {
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') {
                $depth--
                if ($depth -lt 0) {
                    $issues += "Nadmiarowy } w linii $lineNum"
                    $depth = 0
                }
            }
        }
    }
    if ($depth -gt 0) { $issues += "Niezamkniete { (brakuje $depth x })" }

    # 7. Podejrzane komendy LaTeX (literowki - nieznane \cos)
    $knownPattern = '\\(' + ($KNOWN_COMMANDS -join '|') + ')(\{|\\\\|\s|$)'
    foreach ($m in [regex]::Matches($raw, '\\([a-zA-Z]+)')) {
        $cmd = $m.Groups[1].Value
        if ($cmd -notin $KNOWN_COMMANDS -and $cmd -notin $KNOWN_ENVS) {
            # ignoruj typowe LaTeX ktore moga sie pojawic w komentarzach/naglowkach
            if ($cmd -notin @('chapter','input','usepackage','documentclass','maketitle',
                              'tableofcontents','newpage','clearpage','noindent',
                              'hspace','vspace','newline','par','item','label','ref',
                              'index','pagebreak','linebreak','selectfont','normalsize',
                              'large','Large','huge','Huge','normalfont','bf','it','rm',
                              'sl','sc','tt','sf','em','up','md','bfseries','itshape')) {
                $warn += "Nieznana komenda: \$cmd"
            }
        }
    }
    # 8. Podejrzane uzycia hfill
    foreach ($line in $lines) {
        $l = $line -replace '%.*$', ''  # usun komentarze
        # \hfill bez \break
        if ($l -match '\\hfill(?!\\break)' -and $l -notmatch '\\hfill\\break') {
            $warn += "Podejrzane: \hfill bez \break"
        }
    }

    # 9. Skrocone refreny (\vin Tekst...) - sprawdz czy w chwytach jest cos na ich wysokosci
    # Jesli na wysokosci skroconego refrenu w chwytach jest cokolwiek (przeskok \hfill\break
    # lub prawdziwe chwyty), to ryzyko rozjazdu kolumn w PDF.
    # Pliki z ~ sa recznie poprawione - pomijamy
    if ($hasText -and $hasChord -and $raw -notmatch '~') {
        $mText2  = [regex]::Match($raw, '\\begin\{text[nw]?\}([\s\S]*?)\\end\{text[nw]?\}')
        $mChord2 = [regex]::Match($raw, '\\begin\{chord[w]?\}([\s\S]*?)\\end\{chord[w]?\}')
        if ($mText2.Success -and $mChord2.Success) {
            $tBlocks = @($mText2.Groups[1].Value.Trim() -replace "`r`n","`n" -split "`n\s*`n" | Where-Object { $_.Trim() -ne '' })
            $cBlocks = @($mChord2.Groups[1].Value.Trim() -replace "`r`n","`n" -split "`n\s*`n" | Where-Object { $_.Trim() -ne '' })

            for ($si = 0; $si -lt $tBlocks.Count; $si++) {
                $tbLines = @($tBlocks[$si] -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                $allParts = @()
                foreach ($tl in $tbLines) { $allParts += @($tl -split '\\\\' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
                $isShortenedRefrain = ($allParts.Count -eq 1 -and $allParts[0] -match '\\vin' -and $allParts[0] -match '\.\.\.')

                if ($isShortenedRefrain -and $si -lt $cBlocks.Count) {
                    # Sprawdz czy chwyty tez maja dokladnie 1 linie (1:1 = OK)
                    $cbLines = @($cBlocks[$si] -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                    $cParts = @()
                    foreach ($cl in $cbLines) { $cParts += @($cl -split '\\\\' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
                    if ($cParts.Count -gt 1) {
                        $cleanLine = ($allParts[0] -replace '\\vin\s*','').Trim()
                        $warn += "Skrocony refren z chwytami na jego wysokosci (ryzyko rozjazdu): '$cleanLine' [strofka $($si+1)]"
                    }
                }
            }
        }
    }
    $warn = $warn | Select-Object -Unique

    return [PSCustomObject]@{
        Path   = $path
        Artist = $artistFolder
        File   = [System.IO.Path]::GetFileName($path)
        Issues = $issues
        Warns  = $warn
        Infos  = $info
    }
}

# ── GLOWNA PETLA ──────────────────────────────────────────────────────────────
Write-Host "Weryfikacja plikow .tex..." -ForegroundColor Cyan

$results = @()
$totalFiles = 0

foreach ($dir in (Get-ChildItem $MAIN_DIR -Directory | Sort-Object Name)) {
    foreach ($sf in (Get-ChildItem $dir.FullName -Filter '*.tex' |
                     Where-Object Name -ne 'master.tex' | Sort-Object Name)) {
        $totalFiles++
        $r = Verify-File $sf.FullName $dir.Name
        if ($r.Issues.Count -gt 0 -or $r.Warns.Count -gt 0 -or $r.Infos.Count -gt 0) {
            $results += $r
        }
    }
}

# ── RAPORT (pogrupowany wg typu) ──────────────────────────────────────────────

# Funkcja kategoryzujaca komunikat
function Get-Category($msg) {
    if     ($msg -match 'Skrocony refren z chwytami')         { return 'Skrocony refren z chwytami na jego wysokosci (ryzyko rozjazdu)' }
    elseif ($msg -match 'Rozna liczba strofek')             { return 'Rozna liczba strofek tekst/chwyty' }
    elseif ($msg -match 'Pusta sekcja chwytow')             { return 'Pusta sekcja chwytow' }
    elseif ($msg -match 'Pusta sekcja tekstu')              { return 'Pusta sekcja tekstu' }
    elseif ($msg -match 'pusty trzeci')                     { return 'Brak wykonawcy w \tytul' }
    elseif ($msg -match 'pusty tytul')                      { return 'Pusty tytul w \tytul' }
    elseif ($msg -match 'Brak lub niepoprawny')             { return 'Brak lub niepoprawny \tytul' }
    elseif ($msg -match 'Nieznana komenda')                 { return 'Nieznana komenda LaTeX' }
    elseif ($msg -match 'Niezamkniet|Nadmiarow|nie pasuje') { return 'Niezbalansowane begin/end lub {}' }
    elseif ($msg -match 'Brak sekcji')                      { return 'Brak sekcji text lub chord' }
    elseif ($msg -match 'hfill bez')                        { return 'Podejrzane: \hfill bez \break' }
    else   { return $msg }
}

# Zbierz wszystkie komunikaty z przypisaniem pliku i poziomu
$allEntries = @()
foreach ($r in $results) {
    $label = "{0}/{1}" -f $r.Artist, $r.File
    foreach ($i in $r.Issues) { $allEntries += [PSCustomObject]@{ Level='ERR';  Category=(Get-Category $i); Detail=$i; Label=$label } }
    foreach ($w in $r.Warns)  { $allEntries += [PSCustomObject]@{ Level='WARN'; Category=(Get-Category $w); Detail=$w; Label=$label } }
    foreach ($i in $r.Infos)  { $allEntries += [PSCustomObject]@{ Level='INFO'; Category=(Get-Category $i); Detail=$i; Label=$label } }
}

$errCount  = @($allEntries | Where-Object Level -eq 'ERR').Count
$warnCount = @($allEntries | Where-Object Level -eq 'WARN').Count
$infoCount = @($allEntries | Where-Object Level -eq 'INFO').Count

Write-Host ""
Write-Host "Sprawdzono $totalFiles plikow." -ForegroundColor Cyan
Write-Host ("BLEDY: $errCount   OSTRZEZENIA: $warnCount   INFO: $infoCount") -ForegroundColor White
Write-Host ""

if ($allEntries.Count -eq 0) {
    Write-Host "Wszystkie pliki sa poprawne!" -ForegroundColor Green
} else {
    # Grupuj po kategorii, sortuj: ERR najpierw, potem WARN, potem INFO, w ramach tego po liczbie malejaco
    $levelOrder = @{ 'ERR'=0; 'WARN'=1; 'INFO'=2 }
    $grouped = $allEntries | Group-Object Category | Sort-Object {
        $minLevel = ($_.Group | ForEach-Object { $levelOrder[$_.Level] } | Measure-Object -Minimum).Minimum
        $minLevel * 10000 - $_.Count
    }

    foreach ($g in $grouped) {
        $topLevel = if ($g.Group | Where-Object Level -eq 'ERR')  { 'ERR' }
                    elseif ($g.Group | Where-Object Level -eq 'WARN') { 'WARN' }
                    else { 'INFO' }
        $color = switch ($topLevel) { 'ERR' { 'Red' } 'WARN' { 'DarkYellow' } 'INFO' { 'Gray' } }
        $fileColor = switch ($topLevel) { 'ERR' { 'Yellow' } 'WARN' { 'Yellow' } 'INFO' { 'DarkGray' } }

        Write-Host ("══ [{0}] {1} ({2}x) " -f $topLevel, $g.Name, $g.Count) -ForegroundColor $color
        # Lista plikow pod ta kategoria (unikalne, posortowane)
        $files = $g.Group | Sort-Object Label -Unique
        foreach ($f in $files) {
            Write-Host ("    {0}" -f $f.Label) -ForegroundColor $fileColor
            # Jesli detail rozni sie od kategorii (np. zawiera numer strofki), pokaz go
            $cat = Get-Category $f.Detail
            if ($f.Detail -ne $cat) {
                Write-Host ("      -> {0}" -f $f.Detail) -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }
}
