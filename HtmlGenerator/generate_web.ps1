#!/usr/bin/env pwsh
# Spiewnik Web Generator v2.0
$SCRIPT_VERSION = "2.0"
# Resolve repository root: if parent contains 'main', use it (script moved to HtmlGenerator)
$repoRoot = $PSScriptRoot
if (-not (Test-Path (Join-Path $repoRoot 'main'))) {
  $parent = Split-Path -Parent $PSScriptRoot
  if (Test-Path (Join-Path $parent 'main')) { $repoRoot = $parent }
}
$MAIN_DIR = Join-Path $repoRoot "main"

# ── PARSER ───────────────────────────────────────────────────────────────────

function Clean-Tex($line) {
    $line = $line -replace '\\vin\s*', ''
    $line = $line -replace '\\textit\{([^}]*)\}', '<<i>>$1<</i>>'
    $line = $line -replace '\\textbf\{([^}]*)\}', '$1'
    $line = $line -replace '\\small\{([^}]*)\}',   '$1'
    $line = $line -replace '\\footnotesize\{([^}]*)\}', '$1'
    $line = $line -replace '\\tiny\{([^}]*)\}',    '$1'
    $line = $line -replace '\\hfill\\break',        ''
    $line = $line -replace '\\chordfill',           ''
    $line = $line -replace '\\gtab\{[^}]*\}\{[^}]*\}', ''
    $line = $line -replace '\^\{([^}]*)\}',         '<<sup>>$1<</sup>>'
    $line = $line -replace '\\\w+(\{[^}]*\})*',    ''
    $line = $line -replace '\{|\}',                 ''
    $line = $line -replace '\^(\w+)',               '<<sup>>$1<</sup>>'
    $line = $line -replace '~',                     ' '
    return $line.Trim()
}

function Clean-Chord($line) {
    $line = $line -replace '\\hfill\\break',  ''
    $line = $line -replace '\\chordfill',     ''
    $line = $line -replace '\\textit\{([^}]*)\}', '<<i>>$1<</i>>'
    $line = $line -replace '\\textbf\{([^}]*)\}', '$1'
    $line = $line -replace '\^\{([^}]*)\}',   '<<sup>>$1<</sup>>'
    $line = $line -replace '_\{([^}]*)\}',    '_$1'
    $line = $line -replace '\\\w+(\{[^}]*\})*', ''
    $line = $line -replace '\{|\}',           ''
    $line = $line -replace '\^(\w+)',          '<<sup>>$1<</sup>>'
    $line = $line -replace '~',               ' '
    return $line.Trim()
}

# Rozbija raw blok na logiczne linie
function Split-TexBlock($raw) {
    $lines = @()
    foreach ($physical in ($raw -split "`n")) {
        $t = $physical.Trim()
        if ($t -eq '') {
            $lines += [PSCustomObject]@{ Text = ''; IsEmpty = $true }
            continue
        }
        $parts = $t -split '\\\\'
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $p = $parts[$i].Trim()
            if ($p -eq '' -and $i -eq $parts.Count - 1) { continue }
            $lines += [PSCustomObject]@{ Text = $p; IsEmpty = ($p -eq '') }
        }
    }
    return [array]$lines
}

function Parse-Song($filePath, $artistFolder, $artistNameFallback) {
    $rawBytes = [System.IO.File]::ReadAllBytes($filePath)
    $utf8Strict = [System.Text.Encoding]::GetEncoding('utf-8', [System.Text.EncoderFallback]::ExceptionFallback, [System.Text.DecoderFallback]::ExceptionFallback)
    try { $raw = $utf8Strict.GetString($rawBytes) }
    catch { $raw = [System.Text.Encoding]::GetEncoding(1250).GetString($rawBytes) }

    $m = [regex]::Match($raw, '\\tytul\{([^}]*)\}\s*\{([^}]*)\}\s*\{([^}]*)\}')
    if (-not $m.Success) { return $null }
    $title   = $m.Groups[1].Value.Trim()
    $authors = $m.Groups[2].Value.Trim()
    $artist  = $m.Groups[3].Value.Trim()
    if ($artist -eq '' -and $artistNameFallback) { $artist = $artistNameFallback }

    $mt = [regex]::Match($raw, '\\begin\{text[nw]?\}([\s\S]*?)\\end\{text[nw]?\}')
    $mc = [regex]::Match($raw, '\\begin\{chord[w]?\}([\s\S]*?)\\end\{chord[w]?\}')
    $rawText   = if ($mt.Success) { $mt.Groups[1].Value.Trim() } else { '' }
    $rawChords = if ($mc.Success) { $mc.Groups[1].Value.Trim() } else { '' }

    $textSplit  = Split-TexBlock $rawText
    $chordSplit = Split-TexBlock $rawChords

    # Podziel na strofki inline (unikamy osobnej funkcji - PS rozpakowuje zwracane tablice)
    $textStrophes  = [System.Collections.Generic.List[object]]::new()
    $chordStrophes = [System.Collections.Generic.List[object]]::new()
    foreach ($pair in @(@($textSplit, $textStrophes), @($chordSplit, $chordStrophes))) {
        $src = $pair[0]; $dst = $pair[1]
        $cur = [System.Collections.Generic.List[object]]::new()
        foreach ($obj in $src) {
            if ($obj.IsEmpty) {
                if ($cur.Count -gt 0) { $dst.Add($cur.ToArray()); $cur = [System.Collections.Generic.List[object]]::new() }
            } else { $cur.Add($obj) }
        }
        if ($cur.Count -gt 0) { $dst.Add($cur.ToArray()) }
    }

    $pairs = @()
    $firstVerse = ''; $firstRefrain = ''; $inRefrain = $false
    $nStrophes = [Math]::Max($textStrophes.Count, $chordStrophes.Count)

    for ($si = 0; $si -lt $nStrophes; $si++) {
        if ($si -gt 0) { $pairs += [PSCustomObject]@{ T=''; C=''; Refrain=$false; Empty=$true } }
        $tLines = if ($si -lt $textStrophes.Count)  { $textStrophes[$si] } else { @() }
        $cLines = if ($si -lt $chordStrophes.Count) { $chordStrophes[$si] } else { @() }
        if ($null -eq $tLines) { $tLines = @() }
        if ($null -eq $cLines) { $cLines = @() }
        $tLines = [array]$tLines
        $cLines = [array]$cLines
        $maxLen = [Math]::Max($tLines.Count, $cLines.Count)
        for ($i = 0; $i -lt $maxLen; $i++) {
            $tObj = if ($i -lt $tLines.Count)  { $tLines[$i]  } else { [PSCustomObject]@{Text='';IsEmpty=$true} }
            $cObj = if ($i -lt $cLines.Count)  { $cLines[$i]  } else { [PSCustomObject]@{Text='';IsEmpty=$true} }
            $tRaw = $tObj.Text; $cRaw = $cObj.Text
            $isEmptyBoth = ($tObj.IsEmpty -and $cObj.IsEmpty)
            $isRefrain = $tRaw -match '\\vin'
            $tClean = if ($tRaw -ne '') { Clean-Tex $tRaw } else { '' }
            $cClean = if ($cRaw -ne '') { Clean-Chord $cRaw } else { '' }
            if ($isRefrain -and -not $inRefrain -and $tClean -ne '') { $firstRefrain = $tClean }
            if (-not $isRefrain -and $tClean -ne '' -and $firstVerse -eq '') { $firstVerse = $tClean }
            $inRefrain = $isRefrain -and ($tClean -ne '')
            $pairs += [PSCustomObject]@{ T=$tClean; C=$cClean; Refrain=$isRefrain; Empty=$isEmptyBoth }
        }
    }

    while ($pairs.Count -gt 0 -and $pairs[0].Empty)  { $pairs = [array]$pairs[1..($pairs.Count-1)] }
    while ($pairs.Count -gt 0 -and $pairs[-1].Empty) { $pairs = [array]$pairs[0..($pairs.Count-2)] }

    $id = ($artistFolder + '_' + [System.IO.Path]::GetFileNameWithoutExtension($filePath)) -replace '[^a-zA-Z0-9_]','_'

    # Surowy widok: strofki z flagą refrenu, linie oczyszczone z LaTeX
    # Dzielimy rawText na strofki (puste linie = separator), wykrywamy refren przez \vin
    $rawStrophes = @()
    $curLines = [System.Collections.Generic.List[string]]::new(); $curIsRefrain = $false
    foreach ($physLine in ($rawText -split "`n")) {
        $t = $physLine.Trim()
        if ($t -eq '') {
            if ($curLines.Count -gt 0) {
                $rawStrophes += [PSCustomObject]@{ Lines = $curLines.ToArray(); Refrain = $curIsRefrain }
                $curLines = [System.Collections.Generic.List[string]]::new(); $curIsRefrain = $false
            }
            continue
        }
        $parts = $t -split '\\\\'
        foreach ($p in $parts) {
            $p = $p.Trim()
            if ($p -eq '') { continue }
            if ($p -match '\\vin') { $curIsRefrain = $true }
            $cleaned = Clean-Tex $p
            if ($cleaned -ne '') { $curLines.Add($cleaned) }
            else { $curLines.Add('') }
        }
    }
    if ($curLines.Count -gt 0) { $rawStrophes += [PSCustomObject]@{ Lines = $curLines.ToArray(); Refrain = $curIsRefrain } }

    # Chwyty - strofki z List[string] zeby uniknac problemu PS z += skalarow
    $rawChordStrophes = @()
    $curLines = [System.Collections.Generic.List[string]]::new()
    foreach ($physLine in ($rawChords -split "`n")) {
        $t = $physLine.Trim()
        if ($t -eq '') {
            if ($curLines.Count -gt 0) {
                $rawChordStrophes += [PSCustomObject]@{ Lines = $curLines.ToArray() }
                $curLines = [System.Collections.Generic.List[string]]::new()
            }
            continue
        }
        $parts = $t -split '\\\\'
        foreach ($p in $parts) {
            $p = $p.Trim()
            if ($p -eq '') { continue }
            $cleaned = Clean-Chord $p
            if ($cleaned -ne '') { $curLines.Add($cleaned) }
            else { $curLines.Add('') }
        }
    }
    if ($curLines.Count -gt 0) { $rawChordStrophes += [PSCustomObject]@{ Lines = $curLines.ToArray() } }

    $hasChords = ($rawChords -ne '') -and ($pairs | Where-Object { $_.C -ne '' }).Count -gt 0
    return [PSCustomObject]@{ Id=$id; Title=$title; Authors=$authors; Artist=$artist; ArtistFolder=$artistFolder; HasChords=$hasChords; Pairs=[array]$pairs; FirstVerse=$firstVerse; FirstRefrain=$firstRefrain; RawStrophes=$rawStrophes; RawChordStrophes=$rawChordStrophes }
}

function Get-AllSongs {
    $songs = [System.Collections.Generic.List[object]]::new()
    $count = 0
    foreach ($dir in (Get-ChildItem $MAIN_DIR -Directory | Sort-Object Name)) {
        $mf = Join-Path $dir.FullName 'master.tex'
        if (-not (Test-Path $mf)) { continue }
        $mfBytes = [System.IO.File]::ReadAllBytes($mf)
        $utf8Strict = [System.Text.Encoding]::GetEncoding('utf-8', [System.Text.EncoderFallback]::ExceptionFallback, [System.Text.DecoderFallback]::ExceptionFallback)
        try {
            $mfText = $utf8Strict.GetString($mfBytes)
        } catch {
            $mfText = [System.Text.Encoding]::GetEncoding(1250).GetString($mfBytes)
        }
        $mc = [regex]::Match($mfText, '\\chapter\{([^}]*)\}')
        $artistName = if ($mc.Success) { $mc.Groups[1].Value.Trim() } else { $dir.Name }
        foreach ($sf in (Get-ChildItem $dir.FullName -Filter '*.tex' | Where-Object Name -ne 'master.tex' | Sort-Object Name)) {
            $s = Parse-Song $sf.FullName $dir.Name $artistName
            if ($s) {
                $songs.Add($s)
                $count++
                if ($count % 100 -eq 0) { Write-Host "  Wczytano $count piosenek... (ostatnia: $($s.Artist) - $($s.Title))" }
            }
        }
    }
    return $songs.ToArray()
}

Write-Host "Wczytuje piosenki..."
$allSongs = Get-AllSongs
Write-Host "Wczytano $($allSongs.Count) piosenek."

# ── JSON ─────────────────────────────────────────────────────────────────────

function EJ($s) {  # Escape JSON string
    if ($null -eq $s) { return '' }
    $s = $s -replace '\\', '\\'
    $s = $s -replace '"',  '\"'
    $s = $s -replace "`r`n", '\n'
    $s = $s -replace "`n",   '\n'
    $s = $s -replace "`t",   '\t'
    return $s
}

function Songs-ToJson($songs) {
    $count = 0
    $items = foreach ($s in $songs) {
        $count++
        if ($count % 100 -eq 0) { Write-Host "  Serializuje $count/$($songs.Count)..." }
        # pairs: array of {t,c,r,e}  (text, chord, isRefrain, isEmpty)
        $pairsJson = ($s.Pairs | ForEach-Object {
            $r = if ($_.Refrain) { 'true' } else { 'false' }
            $e = if ($_.Empty)   { 'true' } else { 'false' }
            '{"t":"' + (EJ $_.T) + '","c":"' + (EJ $_.C) + '","r":' + $r + ',"e":' + $e + '}'
        }) -join ','
        # rawStrophes: [{lines:[...], refrain:bool}, ...]
        $rawStrophesJson = ($s.RawStrophes | ForEach-Object {
            $r = if ($_.Refrain) { 'true' } else { 'false' }
            $linesJson = ($_.Lines | ForEach-Object { '"' + (EJ $_) + '"' }) -join ','
            '{"lines":[' + $linesJson + '],"refrain":' + $r + '}'
        }) -join ','
        # rawChordStrophes: [{lines:[...]}, ...]
        $rawChordStrophesJson = ($s.RawChordStrophes | ForEach-Object {
            $linesJson = ($_.Lines | ForEach-Object { '"' + (EJ $_) + '"' }) -join ','
            '{"lines":[' + $linesJson + ']}'
        }) -join ','
        $hc = if ($s.HasChords) { 'true' } else { 'false' }
        '{"id":"'+(EJ $s.Id)+'","title":"'+(EJ $s.Title)+'","authors":"'+(EJ $s.Authors)+'","artist":"'+(EJ $s.Artist)+'","artistFolder":"'+(EJ $s.ArtistFolder)+'","hasChords":'+$hc+',"firstVerse":"'+(EJ $s.FirstVerse)+'","firstRefrain":"'+(EJ $s.FirstRefrain)+'","rawStrophes":['+ $rawStrophesJson +'],"rawChordStrophes":['+ $rawChordStrophesJson +'],"pairs":['+ $pairsJson +']}'
    }
    return '[' + ($items -join ',') + ']'
}

Write-Host "Serializuje..."
$songsJson = Songs-ToJson $allSongs

# ── CSS ──────────────────────────────────────────────────────────────────────

$css = @'
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#1a1a2e;--bg2:#16213e;--bg3:#0f3460;
  --accent:#e94560;--accent2:#f5a623;
  --text:#e0e0e0;--text2:#a0a0b0;
  --card:#1e2a45;--card2:#253555;--border:#2a3a5c;
  --refrain:#f5a623;--sung:#4caf50;
  --chord-color:#7ecfff;
}
:root.light{
  --bg:#f0f0f5;--bg2:#ffffff;--bg3:#e8e8f0;
  --accent:#d63050;--accent2:#c08000;
  --text:#1a1a2e;--text2:#555570;
  --card:#ffffff;--card2:#f5f5fa;--border:#d0d0dd;
  --refrain:#b07000;--sung:#2e8b40;
  --chord-color:#1565c0;
}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;min-height:100vh;overflow:hidden}

/* HEADER */
#header{background:var(--bg2);border-bottom:2px solid var(--accent);padding:10px 14px;position:sticky;top:0;z-index:100;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
#header-logo{font-size:1.2rem;font-weight:700;color:var(--accent);white-space:nowrap;cursor:pointer;background:none;border:none;padding:0}
#search-wrap{flex:1;min-width:160px;max-width:420px;position:relative}
#search{width:100%;padding:7px 30px 7px 14px;border-radius:20px;border:1px solid var(--border);background:var(--bg3);color:var(--text);font-size:0.95rem;outline:none}
#search:focus{border-color:var(--accent)}
.search-clear{position:absolute;right:8px;top:50%;transform:translateY(-50%);background:none;border:none;color:var(--text2);font-size:0.85rem;cursor:pointer;padding:2px 6px;display:none;line-height:1}
.search-clear:hover{color:var(--accent)}
.search-clear.visible{display:block}
#header-meta{font-size:0.68rem;color:var(--text2);white-space:nowrap}

/* LAYOUT */
#app{display:flex;height:calc(100vh - 48px);overflow:hidden}
#sidebar{width:260px;min-width:200px;background:var(--bg2);border-right:1px solid var(--border);overflow-y:auto;flex-shrink:0;transition:transform .25s}
#main{flex:1;overflow-y:auto;padding:16px}

/* TOC */
.toc-artist{padding:6px 12px;font-weight:700;color:var(--accent2);cursor:pointer;border-bottom:1px solid var(--border);font-size:0.83rem;display:flex;justify-content:space-between;align-items:center;user-select:none;position:sticky;top:0;z-index:10;background:var(--bg2)}
.toc-artist:hover{background:var(--card)}
.toc-arrow{width:10px;height:10px;flex-shrink:0;border-right:2px solid var(--accent2);border-bottom:2px solid var(--accent2);transform:rotate(-45deg);transition:transform .18s;margin-right:2px}
.toc-artist.open .toc-arrow{transform:rotate(45deg)}
.toc-songs{display:none}
.toc-songs.open{display:block}
.toc-song{padding:4px 12px 4px 22px;font-size:0.8rem;cursor:pointer;color:var(--text);border-bottom:1px solid #ffffff08}
.toc-song.nochords{color:var(--text2);opacity:0.6}
.toc-song:hover{background:var(--card);color:var(--accent)}
.toc-song.active{color:var(--accent);font-weight:600}
.toc-song.sung{color:var(--sung)}
.toc-song.sung::after{content:" \266a";font-size:0.72rem}

/* SEARCH DROPDOWN */
#search-results{background:var(--bg2);border:1px solid var(--border);border-radius:8px;max-height:65vh;overflow-y:auto;position:absolute;top:calc(100% + 4px);left:0;right:0;z-index:300;display:none;box-shadow:0 8px 24px #0006}
#search-results.open{display:block}
.sr-item{padding:8px 14px;cursor:pointer;border-bottom:1px solid var(--border);display:flex;flex-direction:column;gap:1px}
.sr-item:hover{background:var(--card)}
.sr-title{font-weight:600;font-size:0.88rem}
.sr-artist{font-size:0.73rem;color:var(--accent2)}
.sr-artist:hover{text-decoration:underline}
.sr-hint{font-size:0.7rem;color:var(--text2);font-style:italic}
.sr-item.sung .sr-title::after{content:" \266a";color:var(--sung);font-size:0.72rem}

/* HOME */
#home-view{max-width:860px;margin:0 auto}
.home-section{margin-bottom:24px}
.home-section h2{font-size:0.9rem;color:var(--accent2);margin-bottom:10px;text-transform:uppercase;letter-spacing:.06em}
.info-box{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:12px 16px;font-size:0.82rem;color:var(--text2);line-height:1.7}
.info-box strong{color:var(--text)}
.random-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}
.rcard{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:13px 15px;transition:border-color .15s,background .15s}
.rcard:hover{border-color:var(--accent);background:var(--card2)}
.rcard.top{border-left:3px solid var(--accent)}
.rcard.same{border-left:3px solid var(--accent2)}
.rcard.av-nochords{opacity:0.5}
.rcard.sung .rc-title::after{content:" \266a";color:var(--sung);font-size:0.8rem}
.rc-title{font-weight:600;font-size:1rem;margin-bottom:4px;cursor:pointer;white-space:normal;line-height:1.35}
.rc-title:hover{color:var(--accent)}
.rc-artist{font-size:0.82rem;color:var(--accent2);cursor:pointer}
.rc-artist:hover{text-decoration:underline}
.rc-plays{font-size:0.7rem;color:var(--sung);margin-top:3px}

/* SONG VIEW */
#song-view{display:none;width:100%}
.sv-header{margin-bottom:12px}
.sv-header-row{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 14px}
.sv-title{font-size:1.5rem;font-weight:700}
.sv-sep{color:var(--text2);font-size:1.2rem}
.sv-artist{font-size:1.15rem;color:var(--accent2);cursor:pointer;display:inline}
.sv-artist:hover{text-decoration:underline}
.sv-authors{font-size:0.9rem;color:var(--text2)}
.sv-play-count{font-size:0.9rem;color:var(--sung);margin-left:auto;white-space:nowrap}
/* Two-column layout: song body left, sidebar right */
.sv-layout{display:flex;gap:14px;align-items:flex-start;width:100%}
.sv-col-song{flex:1;min-width:0}
.sv-col-side{width:300px;flex-shrink:0;display:flex;flex-direction:column;gap:8px;align-self:flex-start;position:sticky;top:0;max-height:calc(100vh - 48px);overflow-y:auto}
.btn{padding:6px 0;border-radius:16px;border:1px solid var(--border);background:var(--card);color:var(--text);cursor:pointer;font-size:0.8rem;transition:border-color .15s,color .15s,background .15s;white-space:nowrap;width:100%;text-align:center;display:block}
.btn:hover{border-color:var(--accent);color:var(--accent)}
.btn:disabled{opacity:.4;cursor:default}
.btn:disabled:hover{border-color:var(--border);color:var(--text);background:var(--card)}
.btn-sung{border-color:var(--sung);color:var(--sung)}
.btn-sung:hover{background:var(--sung)!important;color:#000!important}
.btn-sung.active{background:var(--sung);color:#000}
.btn-home{border-color:var(--accent);color:var(--accent)}
.btn-home:hover{background:var(--accent);color:#fff}
.sv-actions{display:flex;flex-direction:column;gap:5px}
.sv-actions-row{display:flex;gap:5px}

/* SONG BODY */
.song-body{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:12px 16px;font-size:0.97rem;line-height:1.5}
.song-strophe{margin-bottom:18px}
.song-strophe:last-child{margin-bottom:0}

/* MODE: above (chwyty nad tekstem) */
.song-body.mode-above{columns:2 380px;column-gap:32px;column-rule:1px solid var(--border)}
.song-body.mode-above .song-strophe{display:block;break-inside:avoid;margin-bottom:18px}
.song-body.mode-above .song-strophe:last-child{margin-bottom:0}
.song-body.mode-above .song-pair{display:flex;flex-direction:column-reverse;break-inside:avoid}
.song-body.mode-above .song-strophe.no-chords .song-pair{display:block}
.song-body.mode-above .song-strophe.no-chords .pair-text{display:block;white-space:normal}
.song-body.mode-above .song-strophe.no-chords .pair-chord{display:none}
.song-body.mode-above .chord-only-pair{display:block}
.song-body.mode-above .pair-text{line-height:1.5}
.tex-it{font-style:italic;opacity:0.7}
.pair-chord sup,.raw-chord-line sup{font-size:0.85em;vertical-align:super;line-height:0}
.song-body.mode-above .pair-text.refrain{color:var(--refrain);padding-left:1.4em;font-style:italic}
.song-body.mode-above .pair-chord{font-family:'Courier New',monospace;font-size:0.8rem;color:var(--chord-color);line-height:1.2;min-height:1em;white-space:pre}
.song-body.mode-above .pair-chord:empty{min-height:0;line-height:0}
.song-body.mode-above .pair-chord.refrain-chord{padding-left:1.4em}
.song-body.mode-above .chord-only-pair .pair-text{display:none}
.song-body.mode-above .chord-only-pair .pair-chord{opacity:.85}

/* MODE: inline (tekst | chwyt w osobnej kolumnie) */
.song-body.mode-inline{columns:2 300px;column-gap:32px;column-rule:1px solid var(--border)}
.song-body.mode-inline .song-strophe{display:grid;grid-template-columns:auto auto;column-gap:20px;row-gap:0;margin-bottom:18px;break-inside:avoid;justify-content:start}
.song-body.mode-inline .song-pair{display:contents}
.song-body.mode-inline .pair-text{line-height:24px;white-space:nowrap}
.song-body.mode-inline .pair-text.refrain{color:var(--refrain);font-style:italic;padding-left:1.4em}
.song-body.mode-inline .pair-chord{font-family:'Courier New',monospace;font-size:0.8rem;color:var(--chord-color);line-height:24px;white-space:nowrap}
.song-body.mode-inline .pair-chord:empty{visibility:hidden}
.song-body.mode-inline .chord-only-pair .pair-text{visibility:hidden}
.song-body.mode-inline .chord-only-pair .pair-chord{opacity:.85}
.song-body.mode-inline .song-pair.text-only-pair .pair-chord{visibility:hidden}
.song-body.mode-inline .song-strophe.no-chords{display:block!important}
.song-body.mode-inline .song-strophe.no-chords .pair-text{display:block!important;white-space:normal;line-height:1.5}
.song-body.mode-inline .song-strophe.no-chords .pair-chord{display:none!important}

/* CHORD MODE TOGGLE */
.btn-mode{font-size:0.75rem;padding:4px 10px;border-radius:12px;border:1px solid var(--border);background:var(--card);color:var(--text2);cursor:pointer;transition:all .15s;white-space:nowrap}
.btn-mode:hover{border-color:var(--chord-color);color:var(--chord-color)}
.btn-mode.active{border-color:var(--chord-color);color:var(--chord-color);background:var(--bg3)}

/* SIDEBAR RANDOM */
.side-section-label{font-size:0.75rem;color:var(--accent2);text-transform:uppercase;letter-spacing:.06em;margin-bottom:5px}
.side-list{display:grid;grid-template-columns:1fr 1fr;gap:5px}
.sitem{background:var(--card);border:1px solid var(--border);border-radius:6px;padding:7px 9px;cursor:pointer;font-size:0.85rem;transition:border-color .15s;overflow:hidden}
.sitem:hover{border-color:var(--accent)}
.sitem.top{border-left:3px solid var(--accent)}
.sitem.same{border-left:3px solid var(--accent2)}
.sitem.sung .si-title::after{content:" \266a";color:var(--sung);font-size:0.75rem}
.si-title{font-weight:600;cursor:pointer;line-height:1.35;overflow:hidden;text-overflow:ellipsis;white-space:normal}
.si-title:hover{color:var(--accent)}
.si-artist{font-size:0.75rem;color:var(--accent2);cursor:pointer;margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.si-artist:hover{text-decoration:underline}

/* SEARCH SNIPPET */
.sr-snippet{font-size:0.7rem;color:var(--text2);font-style:italic;margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sr-snippet mark{background:none;color:var(--accent);font-style:normal;font-weight:600}

/* RAW DIALOG */
#raw-dialog{display:none;position:fixed;inset:0;z-index:500;background:#0009;align-items:center;justify-content:center}
#raw-dialog.open{display:flex}
#raw-box{background:var(--bg2);border:1px solid var(--border);border-radius:10px;width:min(900px,95vw);max-height:85vh;display:flex;flex-direction:column;overflow:hidden}
#raw-box-header{padding:10px 16px;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center;flex-shrink:0}
#raw-box-title{font-weight:700;font-size:0.95rem;color:var(--accent2)}
.raw-box-title-text{font-weight:700;font-size:0.95rem;color:var(--accent2)}
#raw-close{background:none;border:none;color:var(--text2);font-size:1.3rem;cursor:pointer;line-height:1;padding:0 4px}
#raw-close:hover{color:var(--accent)}
#hidden-dialog{display:none;position:fixed;inset:0;z-index:500;background:#0009;align-items:center;justify-content:center}
#hidden-dialog.open{display:flex}
#settings-dialog{display:none;position:fixed;inset:0;z-index:500;background:#0009;align-items:center;justify-content:center}
#settings-dialog.open{display:flex}
#settings-box{background:var(--bg2);border:1px solid var(--border);border-radius:10px;width:min(500px,95vw);max-height:85vh;display:flex;flex-direction:column;overflow:hidden}
#settings-content{padding:16px;overflow-y:auto}
.settings-section{margin-bottom:16px}
.settings-section:last-child{margin-bottom:0}
.settings-label{font-size:0.75rem;color:var(--accent2);text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px;font-weight:600}
.settings-row{display:flex;gap:6px;flex-wrap:wrap}
.settings-stats{font-size:0.82rem;color:var(--text2);line-height:1.7}
#hidden-box{background:var(--bg2);border:1px solid var(--border);border-radius:10px;width:min(600px,95vw);max-height:85vh;display:flex;flex-direction:column;overflow:hidden}
#hidden-list{overflow-y:auto;padding:8px 0}
.hidden-item{display:flex;justify-content:space-between;align-items:center;padding:6px 16px;border-bottom:1px solid var(--border);font-size:0.85rem}
.hidden-item-name{color:var(--text)}
.hidden-item-artist{color:var(--text2);margin-right:auto;margin-left:6px}
.hidden-item button{background:none;border:1px solid var(--accent2);color:var(--accent2);border-radius:4px;padding:2px 10px;cursor:pointer;font-size:0.75rem;flex-shrink:0}
.hidden-item button:hover{background:var(--accent2);color:var(--bg)}
.btn-danger{color:#e55!important;border-color:#e55!important}
.btn-danger:hover{background:#e55!important;color:#fff!important}
.btn-restore{color:#eb4!important;border-color:#eb4!important}
.btn-restore:hover{background:#eb4!important;color:#000!important}
.btn-muted{color:var(--text2)!important;border-color:var(--border)!important}
.header-right{margin-left:auto;display:flex;gap:6px;align-items:center}
.sr-item.hidden-song{opacity:0.4}
.sv-hidden-banner{background:#eb422a;color:#000;text-align:center;padding:4px 0;font-size:0.8rem;font-weight:600;border-radius:6px;margin-bottom:8px}
#raw-cols{display:grid;grid-template-columns:1fr 1fr;gap:0;flex:1;overflow-y:auto;align-items:start}
.raw-col-label{font-size:0.7rem;color:var(--accent2);text-transform:uppercase;letter-spacing:.06em;padding:12px 16px 6px}
.raw-strophe{padding:4px 16px 8px}
.raw-strophe:nth-child(odd){border-right:1px solid var(--border)}
.raw-col-label:first-child{border-right:1px solid var(--border)}
.raw-sep{border:none;border-top:1px solid var(--border);margin:0;padding:0;height:1px}
.raw-sep:nth-child(odd){border-right:1px solid var(--border)}
.raw-strophe.refrain .raw-line{color:var(--refrain);font-style:italic;padding-left:1.2em}
.raw-line,.raw-chord-line{font-size:0.9rem;line-height:22px;white-space:pre-wrap}
.raw-line{font-family:'Segoe UI',system-ui,sans-serif;color:var(--text)}
.raw-chord-line{font-family:'Courier New',monospace;color:var(--chord-color)}

/* SCROLLBARS */
::-webkit-scrollbar{width:6px;height:6px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px}
::-webkit-scrollbar-thumb:hover{background:var(--text2)}
*{scrollbar-width:thin;scrollbar-color:var(--border) transparent}

/* MOBILE */
#menu-btn{display:none;background:none;border:none;color:var(--text);font-size:1.3rem;cursor:pointer;padding:2px 6px;flex-shrink:0}
#sidebar-overlay{display:none;position:fixed;inset:0;background:#0009;z-index:90}
@media(max-width:1100px){
  .sv-col-side{width:220px}
  .side-list{grid-template-columns:1fr}
}
@media(max-width:900px){
  .sv-layout{flex-direction:column}
  .sv-col-side{width:100%;position:static;max-height:none}
  .side-list{grid-template-columns:repeat(3,1fr)}
  .song-body.mode-above{columns:1}
  .song-body.mode-inline{columns:1}
}
@media(max-width:780px){
  #menu-btn{display:block}
  #sidebar{position:fixed;top:0;left:0;height:100vh;z-index:95;transform:translateX(-100%)}
  #sidebar.open{transform:translateX(0)}
  #sidebar-overlay.open{display:block}
  #app{height:auto;overflow:visible}
  #main{padding:10px}
  .sv-title{font-size:1.15rem}
  .song-body{padding:10px 12px}
  .side-list{grid-template-columns:repeat(2,1fr)}
}
'@

# ── JS ───────────────────────────────────────────────────────────────────────

$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$js = @'
// ── CHORD MODE ──────────────────────────────────────────────────────────────
let chordMode=localStorage.getItem('sw_chordmode')||'above';
let theme=localStorage.getItem('sw_theme')||'dark';
function setTheme(t){
  theme=t;localStorage.setItem('sw_theme',t);
  document.documentElement.classList.toggle('light',t==='light');
  const d=el('set-theme-dark'),l=el('set-theme-light');
  if(d)d.classList.toggle('active',t==='dark');
  if(l)l.classList.toggle('active',t==='light');
}
function setChordMode(m){
  chordMode=m;
  localStorage.setItem('sw_chordmode',m);
  const body=el('sv-body');
  if(body){body.className='song-body mode-'+m;}
  const a=el('set-mode-above'),i=el('set-mode-inline');
  if(a)a.classList.toggle('active',m==='above');
  if(i)i.classList.toggle('active',m==='inline');
}

// ── LOCAL STORAGE ──────────────────────────────────────────────────────────
const LS_COUNTS='sw_counts', LS_TODAY='sw_today', LS_HIDDEN='sw_hidden';
const TODAY=new Date().toISOString().slice(0,10);
function getCounts(){try{return JSON.parse(localStorage.getItem(LS_COUNTS)||'{}')}catch{return{}}}
function saveCounts(c){localStorage.setItem(LS_COUNTS,JSON.stringify(c))}
function getTodaySet(){try{const d=JSON.parse(localStorage.getItem(LS_TODAY)||'{}');return new Set(d[TODAY]||[])}catch{return new Set()}}
function saveTodaySet(s){const d={};d[TODAY]=[...s];localStorage.setItem(LS_TODAY,JSON.stringify(d))}
function markSung(id){const c=getCounts();c[id]=(c[id]||0)+1;saveCounts(c);const s=getTodaySet();s.add(id);saveTodaySet(s)}
function unmarkSung(id){const s=getTodaySet();s.delete(id);saveTodaySet(s);const c=getCounts();if(c[id]>0)c[id]--;saveCounts(c)}
function isSungToday(id){return getTodaySet().has(id)}
function getHidden(){try{return new Set(JSON.parse(localStorage.getItem(LS_HIDDEN)||'[]'))}catch{return new Set()}}
function saveHidden(h){localStorage.setItem(LS_HIDDEN,JSON.stringify([...h]))}
function hideS(id){const h=getHidden();h.add(id);saveHidden(h)}
function unhideS(id){const h=getHidden();h.delete(id);saveHidden(h)}
function isHidden(id){return getHidden().has(id)}

// ── NORMALIZE / SEARCH ─────────────────────────────────────────────────────
function norm(s){if(!s)return'';s=s.toLowerCase();s=s.replace(/__PL_A__/g,'a').replace(/__PL_C__/g,'c').replace(/__PL_E__/g,'e').replace(/__PL_L__/g,'l').replace(/__PL_N__/g,'n').replace(/__PL_O__/g,'o').replace(/__PL_S__/g,'s').replace(/__PL_Z1__/g,'z').replace(/__PL_Z2__/g,'z');return s.replace(/[^a-z0-9 ]/g,' ').replace(/ +/g,' ').trim()}
function getSnippet(text, nq){
  const nt=norm(text);
  const i=nt.indexOf(nq);
  if(i<0)return null;
  const pre=text.substring(Math.max(0,i-20),i);
  const match=text.substring(i,i+nq.length);
  const post=text.substring(i+nq.length,i+nq.length+40);
  return {pre:(i>20?'...':'')+pre, match, post:post+(text.length>i+nq.length+40?'...':'')};
}
function search(q){
  if(!q.trim())return[];
  const nq=norm(q), res=[];
  for(const s of SONGS){
    let score=0,hint='',snippet=null;
    const nt=norm(s.title),na=norm(s.artist);
    if(nt===nq){score=100;hint='tytu\u0142';snippet=getSnippet(s.title,nq);}
    else if(nt.startsWith(nq)){score=90;hint='tytu\u0142';snippet=getSnippet(s.title,nq);}
    else if(nt.includes(nq)){score=80;hint='tytu\u0142';snippet=getSnippet(s.title,nq);}
    else if(na===nq){score=70;hint='wykonawca';snippet=getSnippet(s.artist,nq);}
    else if(na.includes(nq)){score=60;hint='wykonawca';snippet=getSnippet(s.artist,nq);}
    else{
      const fv=norm(s.firstVerse);
      if(fv&&fv.includes(nq)){score=50;hint='pierwszy wers';snippet=getSnippet(s.firstVerse,nq);}
      else{
        const fr=norm(s.firstRefrain);
        if(fr&&fr.includes(nq)){score=40;hint='refren';snippet=getSnippet(s.firstRefrain,nq);}
        else{
          for(const p of s.pairs){
            if(!p.t)continue;
            const np=norm(p.t);
            if(np.includes(nq)){score=20;hint='tekst';snippet=getSnippet(p.t,nq);break;}
          }
        }
      }
    }
    if(score>0)res.push({s,score,hint,snippet});
  }
  return res.sort((a,b)=>{const ha=isHidden(a.s.id)?1:0,hb=isHidden(b.s.id)?1:0;return ha-hb||b.score-a.score});
}

// ── RANDOM ─────────────────────────────────────────────────────────────────
function pickRandom(pool, n, usedIds, usedArtists, onePerArtist){
  const today=getTodaySet(),hidden=getHidden();
  const shuffled=pool.filter(s=>s.hasChords&&!usedIds.has(s.id)&&!today.has(s.id)&&!hidden.has(s.id));
  for(let i=shuffled.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[shuffled[i],shuffled[j]]=[shuffled[j],shuffled[i]]}
  const result=[];
  for(const s of shuffled){
    if(result.length>=n)break;
    if(onePerArtist&&usedArtists.has(s.artistFolder))continue;
    result.push(s);usedIds.add(s.id);usedArtists.add(s.artistFolder);
  }
  return result;
}
function pickFromTier(pool, n, usedIds, usedArtists){
  const shuffled=[...pool];
  for(let i=shuffled.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[shuffled[i],shuffled[j]]=[shuffled[j],shuffled[i]]}
  const result=[];
  for(const s of shuffled){
    if(result.length>=n)break;
    if(usedArtists.has(s.artistFolder))continue;
    result.push(s);usedIds.add(s.id);usedArtists.add(s.artistFolder);
  }
  return result;
}
function pickTop(n1, n2, usedIds, usedArtists){
  const today=getTodaySet(),hidden=getHidden();
  const c=getCounts();
  const pool=Object.entries(c).filter(e=>e[1]>0).sort((a,b)=>b[1]-a[1]).map(e=>byId[e[0]]).filter(s=>s&&s.hasChords&&!usedIds.has(s.id)&&!today.has(s.id)&&!hidden.has(s.id));
  if(pool.length===0)return [];
  const cut=Math.max(1,Math.ceil(pool.length*0.25));
  const top25=pool.slice(0,cut);
  const rest75=pool.slice(cut);
  const result=[];
  result.push(...pickFromTier(top25,n1,usedIds,usedArtists).map(s=>({s,top:true,same:false})));
  result.push(...pickFromTier(rest75,n2,usedIds,usedArtists).map(s=>({s,top:true,same:false})));
  return result;
}
function getRandomHome(){
  const usedIds=new Set(), usedArtists=new Set();
  const top=pickTop(3,3,usedIds,usedArtists);
  const rest=pickRandom(SONGS,15-top.length,usedIds,new Set(),true).map(s=>({s,top:false,same:false}));
  return top.concat(rest);
}
function getRandomSong(contextArtist){
  const usedIds=new Set([curId]), usedArtists=new Set();
  const top=pickTop(2,2,usedIds,usedArtists);
  const sameArtist=contextArtist?pickRandom(SONGS.filter(s=>s.artistFolder===contextArtist),2,usedIds,new Set(),false).map(s=>({s,top:false,same:true})):[];
  sameArtist.forEach(({s})=>usedIds.add(s.id));
  const rest=pickRandom(SONGS,12-top.length-sameArtist.length,usedIds,new Set(),true).map(s=>({s,top:false,same:false}));
  return top.concat(sameArtist).concat(rest);
}

// ── INDEX ──────────────────────────────────────────────────────────────────
const byId={}, byArtist={}, order=[];
for(const s of SONGS){
  byId[s.id]=s;
  (byArtist[s.artistFolder]=byArtist[s.artistFolder]||[]).push(s);
  order.push(s.id);
}

// ── STATE ──────────────────────────────────────────────────────────────────
let curId=null, curArtist=null, searchTimer=null;

// ── UTILS ──────────────────────────────────────────────────────────────────
function esc(s){return(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function marked(s){return esc(s).replace(/&lt;&lt;i&gt;&gt;/g,'<em class="tex-it">').replace(/&lt;&lt;\/i&gt;&gt;/g,'</em>').replace(/&lt;&lt;sup&gt;&gt;/g,'<sup>').replace(/&lt;&lt;\/sup&gt;&gt;/g,'</sup>')}
function el(id){return document.getElementById(id)}

// ── TOC ────────────────────────────────────────────────────────────────────
function buildToc(openArtist,scroll){
  const toc=el('toc'); toc.innerHTML='';
  const today=getTodaySet();
  const artists=Object.keys(byArtist).sort((a,b)=>{
    const na=byArtist[a][0].artist, nb=byArtist[b][0].artist;
    return na.localeCompare(nb,'pl',{sensitivity:'base'});
  });
  let activeSongEl=null;
  const hidden=getHidden();
  for(const af of artists){
    const songs=byArtist[af].filter(s=>!hidden.has(s.id)), name=byArtist[af][0].artist;
    if(!songs.length)continue;
    const isOpen=(af===openArtist)||(af===curArtist&&curId!==null);
    const hdr=document.createElement('div');
    hdr.className='toc-artist'+(isOpen?' open':'');
    hdr.innerHTML='<span>'+esc(name)+' <small style="color:var(--text2);font-weight:400">('+songs.length+')</small></span><span class="toc-arrow"></span>';
    const list=document.createElement('div');
    list.className='toc-songs'+(isOpen?' open':'');
    hdr.onclick=()=>{
      const o=hdr.classList.toggle('open');
      list.classList.toggle('open',o);
    };
    for(const s of songs){
      const d=document.createElement('div');
      const sung=today.has(s.id);
      const isActive=s.id===curId;
      d.className='toc-song'+(isActive?' active':'')+(sung?' sung':'')+(!s.hasChords?' nochords':'');
      d.textContent=s.title;
      d.onclick=()=>showSong(s.id,true);
      if(isActive)activeSongEl=d;
      list.appendChild(d);
    }
    toc.appendChild(hdr);
    toc.appendChild(list);
  }
  if(scroll&&activeSongEl){
    setTimeout(()=>activeSongEl.scrollIntoView({block:'center'}),60);
  }
}

// ── RENDER RANDOM ──────────────────────────────────────────────────────────
function renderRandom(containerId, contextArtist){
  const wrap=el(containerId); if(!wrap)return;
  const items=containerId==='random-grid'?getRandomHome():getRandomSong(contextArtist);
  const today=getTodaySet();
  wrap.innerHTML='';
  const isGrid=(containerId==='random-grid');
  const c=getCounts();
  for(const {s,top,same} of items){
    const sung=today.has(s.id);
    const d=document.createElement('div');
    d.className=(isGrid?'rcard':'sitem')+(top?' top':'')+(same?' same':'')+(sung?' sung':'');
    const t=document.createElement('div');
    t.className=isGrid?'rc-title':'si-title';
    t.textContent=s.title;
    t.onclick=(e)=>{e.stopPropagation();showSong(s.id)};
    const a=document.createElement('div');
    a.className=isGrid?'rc-artist':'si-artist';
    a.textContent=s.artist;
    a.onclick=(e)=>{e.stopPropagation();showArtist(s.artistFolder)};
    d.appendChild(t);d.appendChild(a);
    const pc=c[s.id]||0;
    if(pc>0){const badge=document.createElement('div');badge.className='rc-plays';badge.textContent='\u266A '+pc+'x';d.appendChild(badge)}
    if(!isGrid)d.onclick=()=>showSong(s.id);
    wrap.appendChild(d);
  }
}

// ── RENDER SONG BODY ───────────────────────────────────────────────────────
function renderSongBody(s){
  const body=el('sv-body');
  body.innerHTML='';
  body.className='song-body mode-'+chordMode;
  // Zbierz pary w strofki
  const stropheGroups=[];
  let cur=[];
  for(const p of s.pairs){
    if(p.e){if(cur.length){stropheGroups.push(cur);cur=[];}}else cur.push(p);
  }
  if(cur.length)stropheGroups.push(cur);
  // Renderuj - no-chords ustawione z gory przed wstawieniem dzieci
  for(const group of stropheGroups){
    const hasAnyChord=group.some(p=>p.c!=='');
    const stropheEl=document.createElement('div');
    stropheEl.className='song-strophe'+(hasAnyChord?'':' no-chords');
    body.appendChild(stropheEl);
    for(const p of group){
      const hasText=(p.t!=='');
      const hasChord=(p.c!=='');
      const isChordOnly=(!hasText&&hasChord);
      if(hasAnyChord){
        if(hasChord){
          const td=document.createElement('span');
          td.className='pair-text'+(p.r?' refrain':'');
          td.innerHTML=hasText?marked(p.t):'\u00a0';
          const row=document.createElement('div');
          row.className='song-pair'+(isChordOnly?' chord-only-pair':'');
          const cd=document.createElement('span');
          cd.className='pair-chord'+(p.r?' refrain-chord':'');
          cd.innerHTML=marked(p.c);
          row.appendChild(td);
          row.appendChild(cd);
          stropheEl.appendChild(row);
        } else {
          const row=document.createElement('div');
          row.className='song-pair text-only-pair';
          const td=document.createElement('span');
          td.className='pair-text'+(p.r?' refrain':'');
          td.innerHTML=marked(p.t);
          row.appendChild(td);
          const empty=document.createElement('span');
          empty.className='pair-chord';
          row.appendChild(empty);
          stropheEl.appendChild(row);
        }
      } else {
        const td=document.createElement('p');
        td.className='pair-text'+(p.r?' refrain':'');
        td.style.cssText='display:block;white-space:normal;margin:0;line-height:1.5';
        td.innerHTML=marked(p.t);
        stropheEl.appendChild(td);
      }
    }
  }
}

// ── VIEWS ──────────────────────────────────────────────────────────────────
function showHome(){
  curId=null;curArtist=null;
  el('home-view').style.display='block';
  el('song-view').style.display='none';
  el('artist-view').style.display='none';
  el('sv-raw-btn').style.display='none';
  el('sv-hide-btn').style.display='none';
  renderRandom('random-grid',null);
  buildToc(null);
  el('main').scrollTop=0;
}

function showArtist(af){
  curArtist=af;curId=null;
  const songs=byArtist[af];if(!songs)return;
  const name=songs[0].artist;
  el('av-artist-name').textContent=name;
  el('av-song-count').textContent=songs.length+' '+(songs.length===1?'utw\u00F3r':songs.length<5?'utwory':'utwor\u00F3w');
  const grid=el('av-grid');grid.innerHTML='';
  const today=getTodaySet(),c=getCounts();
  const sorted=[...songs].sort((a,b)=>a.title.localeCompare(b.title,'pl',{sensitivity:'base'}));
  // top 25% threshold
  const allCounts=Object.values(c).filter(v=>v>0).sort((a,b)=>b-a);
  const topThreshold=allCounts.length>0?allCounts[Math.floor(allCounts.length*0.25)]||1:0;
  for(const s of sorted){
    const sung=today.has(s.id);
    const isTop=c[s.id]>=topThreshold&&c[s.id]>0;
    const d=document.createElement('div');
    d.className='rcard'+(isTop?' top':'')+(sung?' sung':'')+(!s.hasChords?' av-nochords':'');
    const t=document.createElement('div');t.className='rc-title';t.textContent=s.title;
    t.onclick=()=>showSong(s.id);
    d.appendChild(t);
    if(c[s.id]>0){const cnt=document.createElement('div');cnt.className='rc-artist';cnt.textContent='\u266A '+c[s.id]+'x';d.appendChild(cnt)}
    grid.appendChild(d);
  }
  el('home-view').style.display='none';
  el('song-view').style.display='none';
  el('artist-view').style.display='block';
  el('sv-raw-btn').style.display='none';
  el('sv-hide-btn').style.display='none';
  buildToc(af);
  setTimeout(()=>{const e=document.querySelector('.toc-artist.open');if(e)e.scrollIntoView({behavior:'smooth',block:'start'})},60);
  el('main').scrollTop=0;
}

function showSong(id,fromToc){
  const s=byId[id]; if(!s)return;
  curId=id;curArtist=s.artistFolder;
  el('sv-title').textContent=s.title;
  el('sv-artist').textContent=s.artist;
  el('sv-authors').textContent=s.authors?('('+s.authors+')'):'';
  const pc=getCounts()[id]||0;
  el('sv-play-count').textContent=pc>0?('\u266A '+pc+'x'):'';
  updateSungBtn();
  updateHideBtn();
  const idx=order.indexOf(id);
  el('sv-prev').disabled=(idx<=0);
  el('sv-next').disabled=(idx>=order.length-1);
  renderSongBody(s);
  setChordMode(chordMode);
  renderRandom('sv-random-list',s.artistFolder);
  buildToc(null,!fromToc);
  // pokazujemy widok i scrollujemy dopiero po wyrenderowaniu tresci
  el('home-view').style.display='none';
  el('song-view').style.display='block';
  el('artist-view').style.display='none';
  el('sv-raw-btn').style.display='';
  el('sv-hide-btn').style.display='';
  el('main').scrollTop=0;
  closeSidebar();
}

// ── RAW VIEW ──────────────────────────────────────────────────────────────
function showRaw(id){
  const s=byId[id]; if(!s)return;
  el('raw-box-title').textContent=s.title+' \u2014 '+s.artist;
  const cols=el('raw-cols');
  cols.innerHTML='';
  // naglowki
  const hdrT=document.createElement('div');hdrT.className='raw-col-label';hdrT.textContent='Tekst';
  const hdrC=document.createElement('div');hdrC.className='raw-col-label';hdrC.textContent='Chwyty';
  cols.appendChild(hdrT);cols.appendChild(hdrC);
  const ts=s.rawStrophes||[], cs=s.rawChordStrophes||[];
  const n=Math.max(ts.length,cs.length);
  if(!n){
    const e1=document.createElement('div');e1.textContent='(brak)';cols.appendChild(e1);
    const e2=document.createElement('div');cols.appendChild(e2);
    return;
  }
  for(let i=0;i<n;i++){
    // separator miedzy strofkami - w obu kolumnach jednoczesnie
    if(i>0){
      const hr1=document.createElement('hr');hr1.className='raw-sep';
      const hr2=document.createElement('hr');hr2.className='raw-sep';
      cols.appendChild(hr1);cols.appendChild(hr2);
    }
    // lewa kolumna - tekst
    const tStrophe=i<ts.length?ts[i]:null;
    const tDiv=document.createElement('div');
    tDiv.className='raw-strophe'+(tStrophe&&tStrophe.refrain?' refrain':'');
    if(tStrophe){
      for(const line of tStrophe.lines){
        const d=document.createElement('div');d.className='raw-line';d.innerHTML=marked(line)||'\u00a0';
        tDiv.appendChild(d);
      }
    }
    cols.appendChild(tDiv);
    // prawa kolumna - chwyty
    const cStrophe=i<cs.length?cs[i]:null;
    const cDiv=document.createElement('div');cDiv.className='raw-strophe';
    if(cStrophe){
      for(const line of cStrophe.lines){
        const d=document.createElement('div');d.className='raw-chord-line';d.innerHTML=marked(line)||'\u00a0';
        cDiv.appendChild(d);
      }
    }
    cols.appendChild(cDiv);
  }
  el('raw-dialog').classList.add('open');
}
function closeRaw(){el('raw-dialog').classList.remove('open');}

function showHiddenDialog(){
  const list=el('hidden-list');list.innerHTML='';
  const hidden=getHidden();
  if(!hidden.size){list.innerHTML='<div style="padding:16px;color:var(--text2)">Brak usuni\u0119tych piosenek</div>';el('hidden-dialog').classList.add('open');return}
  const items=[...hidden].map(id=>byId[id]).filter(Boolean).sort((a,b)=>{
    const c=a.artist.localeCompare(b.artist,'pl',{sensitivity:'base'});
    return c||a.title.localeCompare(b.title,'pl',{sensitivity:'base'});
  });
  for(const s of items){
    const d=document.createElement('div');d.className='hidden-item';
    const name=document.createElement('span');name.className='hidden-item-name';name.textContent=s.title;
    name.style.cursor='pointer';
    name.onclick=()=>{closeHiddenDialog();showSong(s.id)};
    const artist=document.createElement('span');artist.className='hidden-item-artist';artist.textContent=' \u2014 '+s.artist;
    const btn=document.createElement('button');btn.textContent='przywr\u00F3\u0107';
    btn.onclick=()=>{unhideS(s.id);showHiddenDialog();buildToc(null)};
    d.appendChild(name);d.appendChild(artist);d.appendChild(btn);
    list.appendChild(d);
  }
  el('hidden-dialog').classList.add('open');
}
function closeHiddenDialog(){el('hidden-dialog').classList.remove('open');}

function showSettings(){
  el('set-mode-above').classList.toggle('active',chordMode==='above');
  el('set-mode-inline').classList.toggle('active',chordMode==='inline');
  el('set-theme-dark').classList.toggle('active',theme==='dark');
  el('set-theme-light').classList.toggle('active',theme==='light');
  // stats
  const c=getCounts(),hidden=getHidden(),today=getTodaySet();
  const total=SONGS.length,withChords=SONGS.filter(s=>s.hasChords).length;
  const played=Object.keys(c).filter(k=>c[k]>0).length;
  const totalPlays=Object.values(c).reduce((a,b)=>a+b,0);
  const todayCount=today.size;
  const hiddenCount=hidden.size;
  const active=total-hiddenCount,activeChords=SONGS.filter(s=>s.hasChords&&!hidden.has(s.id)).length;
  const topSongs=Object.entries(c).filter(e=>e[1]>0).sort((a,b)=>b[1]-a[1]).slice(0,5).map(e=>{const s=byId[e[0]];return s?(s.title+' \u2014 '+s.artist+' ('+e[1]+'x)'):(e[0]+' ('+e[1]+'x)')});
  let html='';
  html+='Piosenek: <b>'+active+'</b> (z chwytami: <b>'+activeChords+'</b>)'+(hiddenCount>0?' <small style="color:var(--text2)">[+'+hiddenCount+' usuni\u0119tych]</small>':'')+'<br>';
  html+='Zagrane kiedykolwiek: <b>'+played+'</b> / '+total+'<br>';
  html+='\u0141\u0105cznie odtworze\u0144: <b>'+totalPlays+'</b><br>';
  html+='Dzisiaj za\u015bpiewane: <b>'+todayCount+'</b><br>';
  html+='Usuni\u0119te: <b>'+hiddenCount+'</b><br>';
  if(topSongs.length){html+='<br><b>Top 5:</b><br>';for(const t of topSongs)html+='\u00a0\u00a0'+esc(t)+'<br>'}
  el('settings-stats').innerHTML=html;
  el('settings-dialog').classList.add('open');
}
function closeSettings(){el('settings-dialog').classList.remove('open');}

function exportData(){
  const data={counts:getCounts(),hidden:[...getHidden()],today:JSON.parse(localStorage.getItem(LS_TODAY)||'{}')};
  const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'});
  const a=document.createElement('a');a.href=URL.createObjectURL(blob);
  a.download='spiewnik_dane_'+new Date().toISOString().slice(0,10)+'.json';
  a.click();URL.revokeObjectURL(a.href);
}
function importData(json){
  try{
    const data=JSON.parse(json);
    if(data.counts){const cur=getCounts();for(const[k,v]of Object.entries(data.counts)){cur[k]=Math.max(cur[k]||0,v)}saveCounts(cur)}
    if(data.hidden){const cur=getHidden();for(const id of data.hidden)cur.add(id);saveHidden(cur)}
    if(data.today){const cur=JSON.parse(localStorage.getItem(LS_TODAY)||'{}');for(const[d,ids]of Object.entries(data.today)){cur[d]=[...new Set([...(cur[d]||[]),...ids])]}localStorage.setItem(LS_TODAY,JSON.stringify(cur))}
    buildToc(null);if(curId){updateSungBtn();updateHideBtn()}
    return true;
  }catch{return false}
}

function updateSungBtn(){
  const btn=el('sv-sung-btn');
  if(isSungToday(curId)){btn.textContent='\u2713 Za\u015bpiewana dzi\u015b';btn.classList.add('active')}
  else{btn.textContent='\u266a Za\u015bpiewana!';btn.classList.remove('active')}
  const pc=getCounts()[curId]||0;
  el('sv-play-count').textContent=pc>0?('\u266A '+pc+'x'):'';
}
function updateHideBtn(){
  const btn=el('sv-hide-btn'),h=isHidden(curId);
  btn.textContent=h?'\u21A9 przywr\u00F3\u0107':'\u2715 usu\u0144';
  btn.classList.toggle('btn-danger',!h);
  btn.classList.toggle('btn-restore',h);
  btn.classList.remove('btn-muted');
  el('sv-hidden-banner').style.display=h?'':'none';
}

// ── SEARCH UI ──────────────────────────────────────────────────────────────
function doSearch(q){
  const res=el('search-results');
  if(!q.trim()){res.classList.remove('open');return}
  const results=search(q);
  const today=getTodaySet();
  res.innerHTML='';
  if(!results.length){
    res.innerHTML='<div class="sr-item"><span class="sr-hint">Brak wynik\u00f3w</span></div>';
  } else {
    for(const {s,hint,snippet} of results.slice(0,30)){
      const d=document.createElement('div');
      d.className='sr-item'+(today.has(s.id)?' sung':'')+(isHidden(s.id)?' hidden-song':'');
      const t=document.createElement('div');t.className='sr-title';t.textContent=s.title;
      t.onclick=()=>{hideSearch();showSong(s.id)};
      const a=document.createElement('div');a.className='sr-artist';a.textContent=s.artist;
      a.onclick=(e)=>{e.stopPropagation();hideSearch();showArtist(s.artistFolder)};
      const h=document.createElement('div');h.className='sr-hint';h.textContent=hint;
      d.appendChild(t);d.appendChild(a);d.appendChild(h);
      if(snippet){
        const sn=document.createElement('div');sn.className='sr-snippet';
        sn.innerHTML=esc(snippet.pre)+'<mark>'+esc(snippet.match)+'</mark>'+esc(snippet.post);
        d.appendChild(sn);
      }
      res.appendChild(d);
    }
  }
  res.classList.add('open');
}
function hideSearch(){el('search-results').classList.remove('open');el('search').value='';el('search-clear').classList.remove('visible')}

// ── SIDEBAR MOBILE ─────────────────────────────────────────────────────────
function openSidebar(){el('sidebar').classList.add('open');el('sidebar-overlay').classList.add('open')}
function closeSidebar(){el('sidebar').classList.remove('open');el('sidebar-overlay').classList.remove('open')}

// ── INIT ───────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded',()=>{
  el('meta-info').textContent='v'+VERSION+' | '+SONGS.length+' piosenek | '+GENERATED;
  buildToc(null);
  showHome();

  el('search').addEventListener('input',e=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>doSearch(e.target.value),180);el('search-clear').classList.toggle('visible',e.target.value.length>0)});
  el('search').addEventListener('focus',e=>{if(e.target.value)doSearch(e.target.value)});
  el('search-clear').addEventListener('click',()=>{el('search').value='';el('search-clear').classList.remove('visible');hideSearch()});
  document.addEventListener('click',e=>{if(!e.target.closest('#search-wrap'))hideSearch()});

  el('header-logo').addEventListener('click',showHome);
  el('sv-artist').addEventListener('click',()=>{if(curArtist)showArtist(curArtist)});

  el('sv-sung-btn').addEventListener('click',()=>{
    if(!curId)return;
    if(isSungToday(curId))unmarkSung(curId);else markSung(curId);
    updateSungBtn();buildToc(null);
  });

  el('sv-prev').addEventListener('click',()=>{const i=order.indexOf(curId);if(i>0)showSong(order[i-1])});
  el('sv-next').addEventListener('click',()=>{const i=order.indexOf(curId);if(i<order.length-1)showSong(order[i+1])});

  el('sv-raw-btn').addEventListener('click',()=>{if(curId)showRaw(curId)});
  el('raw-close').addEventListener('click',closeRaw);
  el('raw-dialog').addEventListener('click',e=>{if(e.target===el('raw-dialog'))closeRaw();});

  el('sv-hide-btn').addEventListener('click',()=>{
    if(!curId)return;
    if(isHidden(curId)){unhideS(curId)}else{hideS(curId)}
    updateHideBtn();buildToc(null);
  });
  el('btn-hidden-list').addEventListener('click',showHiddenDialog);
  el('hidden-close').addEventListener('click',closeHiddenDialog);
  el('hidden-dialog').addEventListener('click',e=>{if(e.target===el('hidden-dialog'))closeHiddenDialog();});

  el('btn-settings').addEventListener('click',showSettings);
  el('settings-close').addEventListener('click',closeSettings);
  el('settings-dialog').addEventListener('click',e=>{if(e.target===el('settings-dialog'))closeSettings();});
  el('set-mode-above').addEventListener('click',()=>{setChordMode('above');el('set-mode-above').classList.add('active');el('set-mode-inline').classList.remove('active')});
  el('set-mode-inline').addEventListener('click',()=>{setChordMode('inline');el('set-mode-inline').classList.add('active');el('set-mode-above').classList.remove('active')});
  el('set-theme-dark').addEventListener('click',()=>setTheme('dark'));
  el('set-theme-light').addEventListener('click',()=>setTheme('light'));
  el('set-export').addEventListener('click',exportData);
  el('set-import').addEventListener('click',()=>el('import-file').click());
  el('import-file').addEventListener('change',e=>{
    const f=e.target.files[0];if(!f)return;
    const r=new FileReader();r.onload=()=>{
      if(importData(r.result)){renderRandom('random-grid',null);showSettings()}
      else{alert('Nieprawid\u0142owy plik')}
    };r.readAsText(f);e.target.value='';
  });

  document.addEventListener('keydown',e=>{if(e.key==='Escape'){closeRaw();closeHiddenDialog();closeSettings();}});

  el('menu-btn').addEventListener('click',openSidebar);
  el('sidebar-overlay').addEventListener('click',closeSidebar);

  setChordMode(chordMode);
  setTheme(theme);
});
'@

# ── HTML + ZAPIS ─────────────────────────────────────────────────────────────
# Zapisz JSON do pliku tymczasowego zeby uniknac uszkodzenia przez interpolacje PS
$tmpJson = [System.IO.Path]::GetTempFileName()
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmpJson, $songsJson, $utf8NoBom)
$songsJsonSafe = [System.IO.File]::ReadAllText($tmpJson, $utf8NoBom)
[System.IO.File]::Delete($tmpJson)

$html = @"
<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Spiewnik v2.0</title>
<style>$css</style>
</head>
<body>

<div id="header">
  <button id="menu-btn">&#9776;</button>
  <button id="header-logo">&#127928; Spiewnik v2.0</button>
  <div id="search-wrap">
    <input id="search" type="text" placeholder="Szukaj piosenki, wykonawcy, tekstu..." autocomplete="off" spellcheck="false">
    <button id="search-clear" class="search-clear">&#x2715;</button>
    <div id="search-results"></div>
  </div>
  <div id="header-meta"><span id="meta-info"></span></div>
  <button class="btn-mode" id="sv-raw-btn" style="display:none">&#128196; surowy plik</button>
  <span class="header-right">
    <button class="btn-mode btn-muted" id="btn-settings">&#9881; ustawienia</button>
    <button class="btn-mode btn-danger" id="sv-hide-btn" style="display:none">&#10005; usu&#x0144;</button>
    <button class="btn-mode btn-muted" id="btn-hidden-list">&#128465; usuni&#x0119;te</button>
  </span>
</div>

<div id="sidebar-overlay"></div>

<div id="app">
  <nav id="sidebar"><div id="toc"></div></nav>
  <div id="main">

    <div id="home-view">
      <div class="home-section">
        <div class="info-box">
          <strong>Spiewnik v2.0</strong> &mdash; baza piosenek na gitare.<br>
          Wersja: <strong>$SCRIPT_VERSION</strong> &nbsp;|&nbsp; Wygenerowano: <strong>$timestamp</strong>
        </div>
      </div>
      <div class="home-section">
        <h2>&#127922; Losowe propozycje</h2>
        <div id="random-grid" class="random-grid"></div>
      </div>
    </div>

    <div id="artist-view" style="display:none">
      <div class="sv-header">
        <div class="sv-title" id="av-artist-name"></div>
        <div class="sv-authors" id="av-song-count"></div>
      </div>
      <div id="av-grid" class="random-grid"></div>
    </div>

    <div id="song-view">
      <div class="sv-hidden-banner" id="sv-hidden-banner" style="display:none">&#128465; Ta piosenka jest usuni&#x0119;ta</div>
      <div class="sv-header">
        <div class="sv-header-row">
          <span class="sv-title" id="sv-title"></span>
          <span class="sv-sep">-</span>
          <span class="sv-artist" id="sv-artist"></span>
          <span class="sv-authors" id="sv-authors"></span>
          <span class="sv-play-count" id="sv-play-count"></span>
        </div>
      </div>
      <div class="sv-layout">
        <div class="sv-col-song">
          <div class="song-body mode-above" id="sv-body"></div>
        </div>
        <div class="sv-col-side">
          <div class="sv-actions">
            <div class="sv-actions-row">
              <button class="btn" id="sv-prev">&#9664; Poprzednia</button>
              <button class="btn" id="sv-next">Nast&#x0119;pna &#9654;</button>
            </div>
            <div class="sv-actions-row">
              <button class="btn btn-sung" id="sv-sung-btn">&#9836; Za&#x015B;piewana!</button>
              <button class="btn btn-home" onclick="showHome()">&#8962; Strona g&#x0142;&#x00F3;wna</button>
            </div>
          </div>
          <div>
            <div class="side-section-label">&#127922; Mo&#x017C;e teraz zagra&#x0107;...</div>
            <div class="side-list" id="sv-random-list"></div>
          </div>
        </div>
      </div>
    </div>

  </div>
</div>

<div id="raw-dialog">
  <div id="raw-box">
    <div id="raw-box-header">
      <span id="raw-box-title"></span>
      <button id="raw-close">&#x2715;</button>
    </div>
    <div id="raw-cols"></div>
  </div>
</div>

<div id="hidden-dialog">
  <div id="hidden-box">
    <div id="raw-box-header">
      <span class="raw-box-title-text">Usuni&#x0119;te piosenki</span>
      <button id="hidden-close" style="background:none;border:none;color:var(--text2);font-size:1.3rem;cursor:pointer;line-height:1;padding:0 4px">&#x2715;</button>
    </div>
    <div id="hidden-list"></div>
  </div>
</div>

<div id="settings-dialog">
  <div id="settings-box">
    <div id="raw-box-header">
      <span class="raw-box-title-text">&#9881; Ustawienia</span>
      <button id="settings-close" style="background:none;border:none;color:var(--text2);font-size:1.3rem;cursor:pointer;line-height:1;padding:0 4px">&#x2715;</button>
    </div>
    <div id="settings-content">
      <div class="settings-section">
        <div class="settings-label">Motyw</div>
        <div class="settings-row">
          <button class="btn-mode" id="set-theme-dark">&#127769; ciemny</button>
          <button class="btn-mode" id="set-theme-light">&#9728; jasny</button>
        </div>
      </div>
      <div class="settings-section">
        <div class="settings-label">Tryb chwyt&#243;w</div>
        <div class="settings-row">
          <button class="btn-mode" id="set-mode-above">chwyty nad</button>
          <button class="btn-mode" id="set-mode-inline">chwyty obok</button>
        </div>
      </div>
      <div class="settings-section">
        <div class="settings-label">Dane</div>
        <div class="settings-row">
          <button class="btn-mode btn-muted" id="set-export">&#128230; eksport</button>
          <button class="btn-mode btn-muted" id="set-import">&#128229; import</button>
          <input type="file" id="import-file" accept=".json" style="display:none">
        </div>
      </div>
      <div class="settings-section">
        <div class="settings-label">Statystyki</div>
        <div id="settings-stats" class="settings-stats"></div>
      </div>
    </div>
  </div>
</div>

<script>SONGS_PLACEHOLDER</script>
</body>
</html>
"@

# Podmien placeholder - JSON jest juz bezpieczny, JS tez zapisujemy przez bytes
$outPath = Join-Path $PSScriptRoot "spiewnik.html"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Zapisz JS do pliku tymczasowego zeby uniknac uszkodzenia przez interpolacje PS
$tmpJs = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpJs, $js, $utf8NoBom)
$jsSafe = [System.IO.File]::ReadAllText($tmpJs, $utf8NoBom)
[System.IO.File]::Delete($tmpJs)

$scriptContent = 'const SONGS=SONGS_JSON_HERE;' + "`nconst VERSION=`"$SCRIPT_VERSION`";`nconst GENERATED=`"$timestamp`";`n" + $jsSafe
$scriptContent = $scriptContent -replace 'SONGS_JSON_HERE', $songsJsonSafe
# Podmien placeholdery polskich liter w norm() - musza byc wstawione przez PS nie przez plik tymczasowy
$scriptContent = $scriptContent -replace '__PL_A__',  [char]0x0105  # a z ogonkiem
$scriptContent = $scriptContent -replace '__PL_C__',  [char]0x0107  # c z kreska
$scriptContent = $scriptContent -replace '__PL_E__',  [char]0x0119  # e z ogonkiem
$scriptContent = $scriptContent -replace '__PL_L__',  [char]0x0142  # l z kreska
$scriptContent = $scriptContent -replace '__PL_N__',  [char]0x0144  # n z kreska
$scriptContent = $scriptContent -replace '__PL_O__',  [char]0x00f3  # o z kreska
$scriptContent = $scriptContent -replace '__PL_S__',  [char]0x015b  # s z kreska
$scriptContent = $scriptContent -replace '__PL_Z1__', [char]0x017a  # z z kreska
$scriptContent = $scriptContent -replace '__PL_Z2__', [char]0x017c  # z z kropka
$finalHtml = $html -replace 'SONGS_PLACEHOLDER', $scriptContent
[System.IO.File]::WriteAllText($outPath, $finalHtml, $utf8NoBom)

Write-Host "Gotowe! -> $outPath  ($($allSongs.Count) piosenek)"
