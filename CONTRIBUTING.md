# Wkład do projektu (CONTRIBUTING)

Dziękujemy za chęć współtworzenia śpiewnika! Poniżej znajdziesz szybkie instrukcje, jak dodać piosenkę lub poprawkę.

1. Fork → Branch
   - Zrób fork repozytorium na GitHubie.
   - Stwórz branch, np. `feature/nazwa-piosenki` lub `fix/poprawka-tytulu`.

2. Dodaj piosenkę
   - Dodaj pliki `.tex` z pojedynczymi piosenkami. Jako wzór użyj `main/template.tex`, lub dowolnej piosenki. Możesz też skorzystać z edytora w HTMLu.
   - Jeśli chcesz dodać nowego wykonawcę, w folderze `main/` utwórz folder o krótkiej nazwie (użyj `_` zamiast spacji). Dodaj tam poza piosenkami plik `master.tex` zawierający `\\chapter{Nazwa zespołu}`.

3. Lokalna weryfikacja
   - Uruchom validator TeX, który sprawdza strukturę piosenek:

     ```powershell
     cd HtmlGenerator
     .\\verify_tex.ps1
     ```

   - Wygeneruj lokalnie wersję HTML, żeby szybko podejrzeć rezultat:

     ```powershell
     cd HtmlGenerator
     .\\generate_web.ps1
     # wynik: HtmlGenerator\\spiewnik.html
     ```

   - (Opcjonalnie) Uruchom testy i snapshoty:

     ```powershell
     cd HtmlGenerator
     npm ci
     node functional_test.js
     # jeśli trzeba to na niezmodyfikowanej wersji HTML: node song_display_test.js --update
     ```

4. Commit i Pull Request
   - Zadbaj o czytelny opis commita.
   - Zrób push i otwórz Pull Request na `master`.
   - CI zbuduje artefakty (PDF/HTML) i uruchomi testy; sprawdź wyniki w zakładce Actions.

5. Review
   - Małe dodatki (pojedyncze piosenki) zwykle akceptuję bez dyskusji, większe zmiany mogą wymagać omówienia.

Wskazówki
- Preferuj UTF-8 dla plików tekstowych.
- Trzymaj piosenki zgodnie ze strukturą z `main/template.tex`.
- Jeśli nie jesteś pewien, otwórz Issue lub zostaw komentarz w PR.

Dziękujemy za wkład — każdy dodatek się liczy!
