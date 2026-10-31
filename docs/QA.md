# Plan weryfikacji SortFlow 2.0

## Automatycznie na macOS

- Metadata i wykrywanie typu.
- Próba zastąpienia pliku samym sobą bez utraty danych.
- Zastąpienie z backupem, cofnięcie obu plików, kopiowanie i zachowanie obu nazw.
- Cofnięcie kopii, kopii z zastąpieniem i zmiany nazwy; kolizja przy cofaniu nie nadpisuje nowego pliku.
- Oczekiwany SHA-256, anulowanie i błąd odczytu/brak pliku.
- SQLite: duplikaty, pliki o tym samym rozmiarze i różnej zawartości, hardlinki, bajty do odzyskania.
- Porównanie bajtów, rekurencja, powiązane rozszerzenia z wielkimi literami, zmiana nazw i migracja starego profilu.
- Dziennik przerwanej partii i cofania, krótkie podsumowania historii w RAM oraz sprzątanie zapisów historii.
- Release arm64+x86_64, podpis ad-hoc, uruchomienie procesu GUI, pakowanie i weryfikacja obrazu DMG.

## Ręcznie na docelowym Macu

- Monitor aktywności / Instruments Allocations i Leaks: 10 minut przewijania dużych JPEG, HEIC i RAW; powtórz ten sam przebieg 3 razy. Sprawdź stabilizację żywych alokacji oraz osobno procesy Quick Look i pamięć graficzną.
- 30 razy zdjęcie → film 4K → PDF → inne zdjęcie; zamknij okno i sprawdź zwolnienie podglądów.
- Włącz/wyłącz tryb oszczędny i porównaj plateau pamięci, czas pierwszego podglądu i płynność.
- Skan 100 tys. plików: śledź RAM, wielkość tymczasowego indeksu i reakcję na anulowanie. Indeks zniknie po zakończeniu; wynikowe listy nadal są w RAM.
- Dysk zewnętrzny i udziały sieciowe: odłączenie w trakcie skanu/kopiowania, brak dostępu, brak miejsca, różne systemy plików.
- Konflikt pliku, wiele konfliktów i „zastosuj do wszystkich”; anulowanie między plikami, częściowe cofnięcie po restarcie.
- Przeciągnięcie wielu plików na cel i folderu źródłowego na okno; powiązane pliki i konflikt w zestawie.
- Porównanie dwóch zdjęć, zoom i gesty; podgląd dokumentów w małym oknie; audio i format bez obsługi przebiegu fali.
- PL/EN, jasny/ciemny wygląd, małe okno i pełny ekran; VoiceOver oraz klawiatura w polach tekstowych, ustawieniach i dialogach.
- Pamiętaj: test uruchomienia w CI nie zastępuje oceny wszystkich interakcji interfejsu.
