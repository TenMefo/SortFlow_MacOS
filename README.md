# SortFlow 2.0

Natywna aplikacja macOS do szybkiego segregowania plików i porządkowania duplikatów. SwiftUI, macOS 14+, Apple Silicon i Intel.

## Instalacja

W gałęzi `codex/sortflow-2.0` każdy push uruchamia workflow **Build SortFlow macOS**. Po udanym przebiegu pobierz artefakt **SortFlow-2.0-macOS**, rozpakuj go, otwórz `SortFlow-2.0.dmg` i przenieś aplikację do Aplikacji. Alternatywnie rozpakuj `SortFlow-2.0.zip`.

Build jest podpisany ad-hoc, bez Developer ID i notaryzacji. macOS może wymagać potwierdzenia w **Ustawienia systemowe → Prywatność i ochrona → Otwórz mimo to**. Szczegóły: [instrukcja instalacji](docs/INSTALACJA.txt).

## Praca z plikami

- Wybór lub upuszczenie folderu źródłowego; opcjonalne podfoldery, wyszukiwanie, filtrowanie typu, rozmiaru i daty modyfikacji.
- Sortowanie po nazwie, rozmiarze, dacie i typie bez odczytów metadanych w komparatorze.
- Foldery docelowe z własną nazwą, kolorem, skrótem 1–9 i obsługą przeciągania całych partii.
- Przenoszenie lub kopiowanie, obsługa konfliktów z zastosowaniem wyboru do pozostałych plików.
- Kolejka „Do decyzji później”, tryb skupienia, opcjonalne przejście do następnego pliku.
- Profile zapamiętują źródło, cele, kolejność celów (a tym samym skróty), filtr, sortowanie, zaznaczenie i odłożone pliki. Migracja profili 1.x.
- Reguły typu i fragmentu nazwy z podglądem planu przed zatwierdzeniem; pierwsza pasująca reguła wygrywa.
- Wsadowe nazwy: prefiks, numer początkowy, opcjonalna dzisiejsza data i zachowanie rozszerzeń.
- Opcjonalne przenoszenie/kopiowanie par RAW/JPG/XMP/AAE oraz filmu i napisów o wspólnej nazwie w jednym folderze.
- Historia na dysku, stronicowana po 100 rekordów; cofanie po restarcie aplikacji, raport częściowych błędów i podsumowanie sesji.

## Podglądy i RAM

Tryb oszczędny jest domyślnie włączony:

- 1 aktywne dekodowanie dużego podglądu i najwyżej 2 miniatury naraz. Nieaktualne zlecenia nie rozpoczynają dekodowania; aktywne ImageIO może dokończyć bieżące wywołanie.
- Zdjęcia do 1024 px w trybie oszczędnym, adaptacyjne do wielkości okna (maks. 4096 px) poza nim. Oryginalna rozdzielczość pliku nie jest domyślnie dekodowana.
- Miniatury 60/90 px; wspólny LRU z limitem 16 MiB bitmap i czyszczeniem przy presji pamięci. Limit cache nie obejmuje obrazów trzymanych przez widoki, dekoderów ani procesów Quick Look.
- Powiększanie, przesuwanie, obrót podglądu, dopasowanie, skala 1:1 (jakość nadal ograniczona budżetem podglądu) oraz porównanie dwóch zdjęć ze wspólnym zoomem.
- Podgląd dokumentów Quick Look z jawnym zamknięciem przy usunięciu widoku.
- Odtwarzanie wideo i audio; w trybie oszczędnym bez autoplay i blur, z sugestią mniejszego bufora i rozdzielczości wideo. Kodeki i lokalne pliki nie zawsze respektują wszystkie sugestie AVPlayer.
- Przebieg audio generowany na żądanie strumieniowo do 400 próbek; obsługa zależy od formatu obsługiwanego przez AVAudioFile.

Nie ma deklarowanego limitu RAM dla całego procesu. Lista plików i wynikowe grupy nadal rosną z liczbą elementów. Wymagane są pomiary na rzeczywistych kolekcjach, zwłaszcza RAW, HEIC i filmach 4K.

## Duplikaty i bezpieczeństwo

- Tymczasowy indeks SQLite na dysku (cache stron ok. 4 MiB), odsiew rozmiarem i próbkami, następnie pełny strumieniowy SHA-256.
- Odczyt porcjami 1 MiB, anulowanie pomiędzy porcjami, błędy odczytu nigdy nie są traktowane jak poprawny EOF.
- Dowiązania symboliczne i zawartość pakietów aplikacji są pomijane. Hardlinki są liczone jako jeden fizyczny plik.
- Stabilne identyfikatory grup, wybór kopii chronionej, preferowany folder i główna akcja usuwająca pozostałe kopie. Usunięcie wszystkich wymaga potwierdzenia.
- Przed usunięciem sprawdzane są ponownie metadane i zawartość; przy pozostawieniu jednej kopii porównywane są też bajty. Nie daje to blokady przed zmianami z innego procesu pomiędzy weryfikacją a operacją.
- Zastępowanie najpierw przygotowuje kompletny plik przy celu i odkłada stary cel do kopii zapasowej. Cofanie nie nadpisuje istniejących plików; nieudane elementy pozostają w historii.
- Kopie zapasowe i historia: `~/Library/Application Support/SortFlow/`. Kopie zajmują miejsce do czasu ręcznego usunięcia — ich usunięcie uniemożliwia pełne cofnięcie zastąpienia.
- Rozmiar zbędnych kopii jest szacunkiem logicznym; klony APFS mogą współdzielić bloki. Miejsce w Koszu nie jest jeszcze odzyskanym miejscem.
- Raport zawiera do 1000 problemów na skan. Brak wyniku przy niepełnym skanie nie oznacza braku duplikatów.

## Skróty

| Skrót | Działanie |
|---|---|
| 1–9 | Akcja do folderu o danym numerze |
| ← / → | Poprzedni / następny plik |
| L | Odłóż / przywróć do kolejki |
| F | Tryb skupienia |
| Cmd+O | Wybierz folder |
| Cmd+Z | Cofnij ostatnią operację |
| Cmd+, | Ustawienia |

## Kompilacja i testy

Wymagany Mac z Xcode 16 lub nowszym. Projekt nie używa zewnętrznych paczek.

```bash
bash scripts/build-macos.sh
```

Skrypt kompiluje testy operacji na plikach, buduje uniwersalną aplikację Release, uruchamia testy, sprawdza podpis i architektury, wykonuje próbę uruchomienia oraz tworzy i weryfikuje DMG. Wyniki: `dist/`, logi: `build/`.

Dodatkowe sprawdzenia ręczne: [plan QA](docs/QA.md).

---

SortFlow is a native macOS file organizer. Version 2.0 adds bounded preview decoding, safe replacement with persistent undo, disk-backed duplicate indexing, keyboard sorting, deferred decisions, copy/move, rules, batch rename, image comparison and audio previews. The interface supports Polish and English. See the installation note above for ad-hoc signing limitations.

Autor: TenMefo. Licencja: [MIT](LICENSE).
