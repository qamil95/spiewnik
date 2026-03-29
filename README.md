# Hej ho :)
Śpiewniki - są ich miliony, każdy jakiś ma: czy to na dysku, w internecie, czy w wersji papierowej, wiele różnych. Nie ma jednak żadnej spójnej wersji, a przy starcie każdego kursu przewodnickiego pojawia się dylemat "a co by tu dać kursantom do wydrukowania"? Może czas stworzyć coś bardziej uniwersalnego? Może czas na Śpiewnik v3.0?

## Trochę historii
### v1
Na początku był Kraków...
W maju 2018 ekipa z Krakowa zaczęła tworzyć "Śpiewnik krakowskich śpiewanek okołogórskich", dostępny pod rydzekkk/spiewnik (repo które aktualnie widzisz jest jego forkiem). Pomysł zacny: zamiast trzymać śpiewnik w jednym pliku worda, użyć struktury rozproszonej - pojedynczych plików latexa z jednym utworem na plik, całość wrzucić na githuba i pozwolić projektowi się rozrastać. Projekt żył przez rok, powstała w 2019 roku wersja jest całkiem użyteczna, ale jej rozwój się zatrzymał.
### v2
Nie pamiętam już w sumie jak to się zaczęło, w każdym razie Kijek poprawił kilka rzeczy w głównym pliku latexa, parę poprawek do piosenek zostało wrzuconych, do rozwoju dołączyłem się również ja i razem na osobnym forku coś tam dłubaliśmy. Powoli zaczynało coś sensownego z tego powstawać, pandemia dorzuciła nieco wolnego czasu więc rok 2020 to masowe poprawki w istniejących piosenkach, dodawanie nowych, a także dopisanie programów w C# pomagających automatycznie budować spis treści, konwertować format z przyjaźniejszego do pisania piosenek do przyjaźniejszego w kompilacji dla latexa. Kilku kursantów dołączyło też do dokładania piosenek i przepisywania ich z innych śpiewników, więc na koniec 2021 rok mieliśmy całkiem solidną wersję w PDF, i dalekie plany na przyszłość. No i, jak to zwykle bywa, zapał ustał, inne obowiązki spowodowały że plany zostały odłożone na dużo dalszą przyszłość, a po ostatnich podrygach w postaci jednego małego commita w 2023 roku wszystko ponownie stanęło w miejscu.
### v3
Kolejne lata minęły, dzień dobry z 2026 roku! Czasu podobnie mało co dawniej, ale dzisiaj mamy dostępne szeroko pojęte AI i LLMy, które przyspieszają pracę znacząco. W życiu nie odważyłbym się stworzyć z ich pomocą jakiejś poważnej aplikacji i udostępnić jej do szerokiego użytku - to jeszcze nie te czasy i nie te możliwości. Ale powiedzmy sobie szczerze, śpiewnik to nie jest infrastruktura krytyczna i do takich potrzeb skrypty wygenerowane przez modele językowe które utworzą statycznego HTMLa z listą piosenek to coś, do czego już teraz nadają się całkiem dobrze. Zapraszam więc do trzeciej wersji śpiewnika, tym razem w formie pliku HTML :)

## W czym to jest lepsze od obecnych śpiewników?
Teraz każdy trzyma w jakimś losowym formacie wybrane teksty piosenek, często muszą one być kombinowane z wielu miejsc, mają niespójną formę zapisu. Idea stojąca za tym śpiewnikiem jest następująca: prosty format bazy piosenek i jej otwartość na wszelkie utwory. Do bazy piosenek możemy wrzucić wszystko, co tylko ma chwyty i może być piosenką zagraną na gitarze. Dzięki temu, cała baza tekstów będzie szeroka, a każdy będzie mógł znaleźć w niej interesujące go utwory i utworzyć własną wersję śpiewnika w PDFie do wydrukowania. Czy też odpalić aplikację na telefon, gdzie wyszuka sobie każdy tekst z pełnej bazy. Jeśli jakiejś piosenki brakuje lub jest błędna, każdy może zaproponować do niej poprawkę, i ta od razu pojawi się we wszystkich nowszych instancjach śpiewnika.

## Co mamy dziś?
Mamy bazę piosenek odziedziczonych po Krakowie, mamy też automatyczny generator listy wszystkich piosenek - pierwotnie trzeba było trochę małpiej roboty, żeby po dodaniu nowej piosenki ręcznie dopisać w odpowiednich miejscach nazwy plików, teraz robi to za nas github action. Możemy także w miarę bezboleśnie wygenerować z tej listy piosenek PDFa z wszystkimi utworami, co dzieje się też automatycznie przy każdym pull requeście. Mamy też długą listę rzeczy, które trzeba jeszcze zrobić :) Powoli AI zaczyna robić niektóre z tych rzeczy dla nas, czego efektem jest chociażby generator HTMLa z plików tex.

# Struktura repozytorium
### .github
Folder zawierający githubowy workflow, który utworzy nam paczkę ze śpiewnikiem.
### HtmlGenerator
Twórczość AI. Kilka skryptów, pozwalających stworzyć z tych samych plików źródłowych w folderze main gotowy śpiewnik w formacie HTML. Detale wewnątrz tego folderu, bo może się to dość dynamicznie zmieniać z racji tego, że człowiek tego nie napisał więc też nie będzie poprawiał :)
### SonglistGenerator
Program w C# .NET Core, który na podstawie plików master.tex z nazwami zespołów oraz poszczególnymi piosenkami, tworzy nowe pliki master.tex z alfabetycznie posortowaną listą piosenek każdego zespołu, oraz plik main.tex z listą wszystkich zespołów. Program wrapuje też znaki indeksu górnego i dolnego w chwytach (^, _) aby śpiewnik skompilował się poprawnie bez wchodzenia w tryb matematyczny, a także ma możliwość złączenia rozdziałów w jeden, jeśli te zawierają określoną liczbę lub mniej utworów. Wynik jego działania jest dostępny w artefaktach każdego builda, to z nich należy kompilować śpiewnik.
### SonglistGeneratorTests
Testy programu z punktu wyżej, założone przy pisaniu wrapera indeksów górnych i dolnych - miało to namiastkę TDD, gdyż najpierw mieliśmy kilka utworów wraz z ich ręcznie poprawionymi wersjami, a później staraliśmy się napisać kod który automatycznie to wygeneruje.
### SongChooser
Program w C# .NET Core WPF, który daje możliwość wyboru piosenek do umieszczenia w śpiewniku. Graficzna nakładka na SonglistGenerator, pozwalająca ręcznie wybrać piosenki które nie będą zamieszczone w finalnym śpiewniku, a także ustawić minimalny wymagany rozmiar rozdziału (rozdziały mające mniej piosenek niż wskazana liczba, zostaną połączone w jeden, umieszczony na końcu śpiewnika). Raczej proof of concept, który jako tako działa, jednak nie jest idiotoodporny i trzeba by go stworzyć porządnie od nowa ;)
### main
Folder z ręcznie tworzonymi latexowymi plikami, z których należy zbudować śpiewnik. Pierwotnie bezpośrednio z niego tworzyło się śpiewnik, teraz jest to tylko katalog źródłowy do którego wrzucamy teksty piosenek - sam śpiewnik budowany jest z artefaktów builda (dostępne na githubie w zakłdace Actions).

# Dodawanie nowych piosenek
Czysto teoretycznie, do dodawania piosenek nie potrzeba nic prócz edytora tekstowego, wystarczy trzymać się schematu z pliku main\template.tex i dodawać każdą piosenkę w osobnym pliku. Najlepszym sposobem na poznanie struktury pliku z piosenką jest otwarcie kilku losowo wybranych, oraz porównanie ich z wygenerowanym PDFem.
Struktura śpiewnika jest oparta na zespołach, więc jeżeli chcemy dodać zespół którego nie ma, tworzymy folder o możliwie krótkiej nazwie, używając _ zamiast spacji.
W folderze tworzymy plik master.tex o zawartości:

`\chapter{Nazwa zespołu}`

Poza plikiem master.tex, w folderze zespołu mogą znaleźć się tylko pliki .tex z poszczególnymi piosenkami. Najważniejsze założenia struktury każdego pliku:
- Po nagłówku \tytul muszą się znaleźć trzy nawiasy klamrowe, zawierające odpowiednio tytuł utworu, autorów słów i muzyki oraz wykonwcę (nazwę folderu/rozdziału)
- Między \begin{text} i \end{text} musi znaleźć się tekst, z czterema spacjami wcięcia (samo begin i end są pisane bez wcięć)
- To samo dotyczy sekcji chwytów, między \begin{chord} i \end{chord}
- Wszystkie chwyty w jednej linii powinny być rozdzielone pojedynczą spacją.

# Składanie śpiewnika
Githubowe agenty są w stanie skompilować śpiewnik za nas, wystarczy stworzyć pull request do mastera a github action wygeneruje PDFa z wszystkimi utworami. Poniższa instrukcja jest przeznaczona dla tych, którzy chcą ręcznie zbudować śpiewnik na swoim komputerze (po wygenerowaniu go z tylko wybranymi piosenkami SongChooserem, lub dlatego że mają taki kaprys).

Potrzebujemy co najmniej instalacji LaTeXa, którego można pobrać tu: https://www.latex-project.org/get/
Pod Windowsem ja korzystam z MiKTeX i najlepiej będzie się w tym względzie unifikować, różne implementacje mogą mieć swoje smaczki.
Instalacja sprowadza sie do klikania "dalej" :)
W MiKTeXie jest też dostępny podstawowy edytor LaTeXa, ale zwykły notatnik wystarczy, polecam natomiast Notepad++ jako prostą alternatywę.
Jeżeli już mamy zainstalowanego LaTeXa, wystarczy otworzyć cmd i wpisać pdflatex (ścieżka do pliku)\Spiewnik_xxx.tex, zamiast xxx podając wybraną wersję śpiewnika. Można również uruchomić skrypt !compile_all.bat w głównym folderze śpiewnika, on automatycznie skompiluje wszystkie dostępne wersje, bądź !compile_chwyty.bat dla samej wersji z chwytami.
Rzecz jasna najpierw trzeba ten projekt gdzieś na dysk zassać :) Najnowsza wersja jest do pobrania z zakładki Actions (https://github.com/qamil95/spiewnik/actions), należy wejść w najnowszego builda (najlepiej mastera dla stabilnej wersji) i ściągnąć archiwym Songbook v2.0, po czym wypakować je na dysk.

Do współtworzenia projektu potrzebny nam będzie git, dostępny do pobrania tu: https://git-scm.com/downloads
konto na GitHubie i zgłoszenie się do mnie z prośbą o współtworzenie.

Poczytajcie też trochę o gicie, podczas rejestracji na githubie wyskoczy Wam instrukcja z podstawowymi informacjami, które w zupełności tutaj wystarczą.
Tak jak wspominałem, śpiewnik jest otwarty na wszystkie piosenki, jednak master jest zabezpieczony przed pushowaniem bezpośrednio do niego (aby nikt nic nie zepsuł). Polecam wrzucić zmiany do jakiegoś brancha i wystawić pull requesta, jeśli to tylko dodanie nowej piosenki to zaakceptuję bez dyskusji ;)

Przy każdym commicie starajcie się opisywać zmiany zwięźle, ale i konkretnie.
Powodzenia!
