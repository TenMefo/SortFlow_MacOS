# SortFlow 

[🇺🇸 English version below](#-english-version)

Narzędzie na macOS do segregacji plików, odgracania dysków i usuwania duplikatów. Zbudowane natywnie w SwiftUI. 

Zamiast ręcznie przeklikiwać się przez Findera, wybierasz folder bazowy, zmapujesz swoje foldery docelowe (np. "Do obróbki", "Śmieci", "Prywatne") i segregujesz pliki jednym kliknięciem. 

<img width="2880" height="1698" alt="image" src="https://github.com/user-attachments/assets/4b07a557-aba7-44aa-b2e2-d2d282151652" />

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
1. Pobierz plik [`SortFlow.app.zip`](https://github.com/TenMefo/SortFlow_MacOS/releases/tag/v1.0) z zakładki Release.
2. Wypakuj pobrany plik .zip
3. Uruchom aplikację SortFlow.app

---

1. Sklonuj repozytorium na swój dysk.
2. Otwórz projekt w Xcode.
3. **Ważne:** Aplikacja ma celowo wyłączony `App Sandbox` (w zakładce *Signing & Capabilities*), aby mogła swobodnie operować na plikach i czytać metadane na dyskach zewnętrznych.
4. Wybierz schemat **Release** i urządzenie docelowe **My Mac**.
5. Zbuduj i uruchom (`Cmd + R`) lub wyeksportuj gotową aplikację (`Product -> Archive`).

## 👨‍💻 Autor
**[Ten_Mefo](https://www.instagram.com/ten_mefo/)** oraz Gemini 3.1 Pro


---

# 🇺🇸 English Version

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
1. Download the [`SortFlow.app.zip`](https://github.com/TenMefo/SortFlow_MacOS/releases/tag/v1.0) file from the Releases tab.
2. Extract the downloaded .zip file.
3. Run the SortFlow.app application.

---

1. Clone the repository to your local drive.
2. Open the project in Xcode.
3. **Important:** The application intentionally has `App Sandbox` disabled (in the *Signing & Capabilities* tab) so it can freely manage files and read metadata on external drives.
4. Select the **Release** scheme and **My Mac** as the destination device.
5. Build and run (`Cmd + R`) or export the finished app (`Product -> Archive`).

## 👨‍💻 Author
**[Ten_Mefo](https://www.instagram.com/ten_mefo/)** and Gemini 3.1 Pro
