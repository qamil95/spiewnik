# Śpiewnik v2.0 - Kontekst projektu

## Co to jest
Śpiewnik gitarowy - baza piosenek w plikach .tex (LaTeX), generowana do jednego pliku HTML (spiewnik.html) przez skrypt PowerShell (generate_web.ps1). Offline, bez serwera.

## Kluczowe pliki
- `generate_web.ps1` - główny generator: parsuje .tex → JSON → HTML z CSS + JS w jednym pliku
- `spiewnik.html` - wygenerowany output (~3.5MB, zawiera ~500+ piosenek)
- `functional_test.js` - ~100 testów Playwright (logika, nawigacja, localStorage, responsive)
- `song_display_test.js` - 60 piosenek × 3 widoki = 180 screenshotów pixel-perfect
- `verify_tex.ps1` - walidacja plików .tex (błędy, ostrzeżenia)
- `main/` - foldery artystów z plikami .tex

## Architektura generate_web.ps1
1. **Parser** - Clean-Tex(), Clean-Chord(), Split-TexBlock(), Parse-Song(), Get-AllSongs()
2. **JSON** - EJ() (escape), Songs-ToJson() - ręczna serializacja (nie ConvertTo-Json)
3. **CSS** - here-string @'...'@ z CSS variables, dark/light mode, responsive breakpoints
4. **JS** - here-string @'...'@ z całą logiką frontendu
5. **HTML** - double-quoted here-string @"..."@ z interpolacją PS ($css, $SCRIPT_VERSION, $timestamp)
6. **Składanie** - placeholdery SONGS_PLACEHOLDER i __PL_*__ zamieniane na końcu

## Zaimplementowane funkcje (v2.0)
- **Widoki**: strona główna, artysta (kafelki), piosenka (chwyty nad/obok), raw view (surowy plik)
- **Losowanie**: top 25% (najczęściej grane) + reszta 75%, max 1 artysta raz, bez dzisiejszych/ukrytych/bez chwytów
- **Wyszukiwarka**: tytuł > artysta > pierwszy wers > refren > tekst, snippet z podświetleniem, przycisk X do czyszczenia
- **Zaśpiewana**: licznik w localStorage, oznaczenie w TOC (♪), toggle przycisk
- **Usuwanie piosenek**: flaga w localStorage, znika z TOC/losowania, w wyszukiwarce na dole (wyszarzone), dialog z listą usuniętych, przycisk toggle usuń/przywróć (czerwony/żółty), banner "Ta piosenka jest usunięta"
- **Ustawienia** (dialog ⚙): tryb chwytów (nad/obok), motyw (ciemny/jasny), eksport/import danych, statystyki
- **Eksport/import**: JSON z counts + hidden + today, merge przy imporcie (max dla liczników, suma dla ukrytych)
- **Light mode**: alternatywny zestaw CSS variables na :root.light
- **Superscript**: C^7 / C^{7+} → `<sup>` w chwytach (0.85em)
- **TOC**: rozwijane po artystach, counter (12) obok nazwy, wyszarzone piosenki bez chwytów, active/sung
- **Responsive**: 3 breakpointy (1100px, 900px, 780px), hamburger menu na mobile
- **Kafelki**: badge ♪ 3x z licznikiem odtworzeń

## Placeholdery polskich znaków w norm()
`__PL_A__` → ą, `__PL_C__` → ć, `__PL_E__` → ę, `__PL_L__` → ł, `__PL_N__` → ń, `__PL_O__` → ó, `__PL_S__` → ś, `__PL_Z1__` → ź, `__PL_Z2__` → ż
(zamieniane przez PS na końcu generowania, bo @'...'@ nie interpoluje)

## verify_tex.ps1 - zmiany
- Pomija WARN "Skrócony refren z chwytami" jeśli plik zawiera ~ (ręcznie poprawione)
- Pomija jeśli chwyty mają 1 linijkę (1:1 z refrenem = OK)

## Ostatnie porządki (ta sesja)
- Wersja 1.1 → 2.0
- Placeholdery c_PL → __PL_C__ (unikalne, bez ryzyka kolizji)
- Get-AllSongs: $songs += → List<object> (O(n) zamiast O(n²))
- Clean-Tex obsługuje ^ (superscript) tak jak Clean-Chord
- body overflow:hidden (scrollbar tylko w #main)
- Timeout testów 30s → 5s

## Co jeszcze do zrobienia (wspomniane ale odłożone)
- Skróty klawiaturowe (Ctrl+K do wyszukiwania, etc.) - osobny temat
- Smooth scroll w #main
- Dynamiczny info box na stronie głównej
