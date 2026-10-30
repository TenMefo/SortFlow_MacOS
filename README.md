# 🇵🇱 SortFlow 

[🇺🇸 English version below](#-english-version)

Narzędzie na macOS do segregacji plików, odgracania dysków i usuwania duplikatów. Zbudowane natywnie w SwiftUI. 

Zamiast ręcznie przeklikiwać się przez Findera, wybierasz folder bazowy, zmapujesz swoje foldery docelowe (np. "Do obróbki", "Śmieci", "Prywatne") i segregujesz pliki jednym kliknięciem. 

<img width="3024" height="1898" alt="image" src="https://github.com/user-attachments/assets/f0c9ddc7-5643-4369-87ff-6d47270254cb" />


## Główne funkcje

* **Segregacja:** Przeglądaj pliki i przenoś je do wcześniej zmapowanych folderów docelowych. W razie co masz opcję cofnięcia ostatniej akcji (Undo).
* **Duplikaty:** Apka skanuje wybraną ścieżkę (razem z podfolderami) i grupuje identyczne pliki. Możesz porównać ich metadane i usunąć wybrane sztuki lub całe grupy naraz.
* **Podgląd multimediów:** 
  * Obsługa zdjęć z wymuszonym ładowaniem surowych bajtów (omija ograniczenia systemowego Sandboxa i QuickLooka dla dysków zewnętrznych). 
  * Wideo z opcją auto-odtwarzania i wyciszenia.
* **Dwujęzyczność (PL / EN):** Pełne tłumaczenie interfejsu przełączane w locie jednym guzikiem.
* **Integracja z macOS:** Bezpośrednie linki otwierające i podświetlające konkretne pliki prosto w systemowym Finderze.

## 🛠 Technologie

* **Język:** Swift
* **UI:** SwiftUI
* **Frameworki:** `QuickLookThumbnailing`, `AVKit`, `UniformTypeIdentifiers`

## 🚀 Instalacja i uruchomienie
1. Pobierz plik [`SortFlow.dmg`](https://github.com/TenMefo/SortFlow_MacOS/releases/tag/v1.1) z zakładki Release.
2. Zamontuj (kliknij dwukrotnie) plik SortFlow.dmg.
3. Przenieś plik SortFlow.app do folderu Aplikacje.
4. Uruchom aplikację SortFlow.app.
5. Wejdź w `Ustawienia systemowe`, przejdź do zakładki `Prywatność i ochrona` i naciśnij `Otwórz mimo to` przy komunikacie o zablokowaniu aplikacji.

   <img width="535" height="104" alt="image" src="https://github.com/user-attachments/assets/41434964-562b-4e85-8672-c4e23984f8c8" />

6. Od teraz aplikacja działa prawidłowo!


---

1. Sklonuj repozytorium na swój dysk.
2. Otwórz projekt w Xcode.
3. **Ważne:** Aplikacja ma celowo wyłączony `App Sandbox` (w zakładce *Signing & Capabilities*), aby mogła swobodnie operować na plikach i czytać metadane na dyskach zewnętrznych.
4. Wybierz schemat **Release** i urządzenie docelowe **My Mac**.
5. Zbuduj i uruchom (`Cmd + R`) lub wyeksportuj gotową aplikację (`Product -> Archive`).

## 👨‍💻 Autor
**[Ten_Mefo](https://www.instagram.com/ten_mefo/)** oraz Gemini 3.1 Pro


---

# 🇺🇸 SortFlow

A macOS tool for file organization, decluttering drives, and removing duplicates. Built natively in SwiftUI.

Instead of manually clicking through Finder, choose a base folder, map your target folders (e.g., "To edit", "Trash", "Private"), and sort your files with a single click.

## Key Features

* **Sorting:** Browse files and move them to previously mapped target folders. If needed, you can undo your last action (Undo).
* **Duplicates:** The app scans the selected path (including subfolders) and groups identical files. You can compare their metadata and delete individual files or entire groups at once.
* **Media Preview:** 
  * Photo support with forced raw byte loading (bypasses system Sandbox and QuickLook limitations for external drives). 
  * Video playback with auto-play and mute options.
* **Bilingual (PL / EN):** Full interface translation, switchable on the fly with a single button.
* **macOS Integration:** Direct links that open and highlight specific files right in the system Finder.

## 🛠 Technologies

* **Language:** Swift
* **UI:** SwiftUI
* **Frameworks:** `QuickLookThumbnailing`, `AVKit`, `UniformTypeIdentifiers`

## 🚀 Installation & Setup
1. Download the [`SortFlow.dmg`](https://github.com/TenMefo/SortFlow_MacOS/releases/tag/v1.1) file from the Releases tab.
2. Mount (double-click) the SortFlow.dmg file.
3. Move the SortFlow.app file to the Applications folder.
4. Launch the SortFlow.app application.
5. Go to `System Settings`, navigate to the `Privacy & Security` tab, and click `Open Anyway` next to the message about the blocked application.
6. From now on, the application will work correctly!

---

1. Clone the repository to your local drive.
2. Open the project in Xcode.
3. **Important:** The application intentionally has `App Sandbox` disabled (in the *Signing & Capabilities* tab) so it can freely manage files and read metadata on external drives.
4. Select the **Release** scheme and **My Mac** as the destination device.
5. Build and run (`Cmd + R`) or export the finished app (`Product -> Archive`).

## 👨‍💻 Author
**[Ten_Mefo](https://www.instagram.com/ten_mefo/)** and Gemini 3.1 Pro

