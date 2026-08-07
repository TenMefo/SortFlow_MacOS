import SwiftUI
import AVKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Rozszerzenia (Extensions)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (138, 43, 226) // Fiolet
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension URL {
    var isVideo: Bool {
        let ext = self.pathExtension.lowercased()
        
        if ["mp4", "mov", "mkv", "avi", "m4v"].contains(ext) { return true}
        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "raw"].contains(ext) { return false}
        
        let uti = try? self.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        return uti?.contains("movie") == true || uti?.contains("video") == true
    }
}

// MARK: - Typy (Enums) i Modele

enum AppLanguage: String, CaseIterable, Identifiable {
    case pl = "PL"
    case en = "EN"
    var id: String { rawValue }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case aspectFit = "aspectFit"
    case aspectFill = "aspectFill"
    case fitWithBlur = "fitWithBlur"
    var id: Self { self }
    
    func localized(_ lang: AppLanguage) -> String {
        switch self {
        case .aspectFit: return lang == .pl ? "Dopasuj do okna" : "Fit to window"
        case .aspectFill: return lang == .pl ? "Wypełnij" : "Fill"
        case .fitWithBlur: return lang == .pl ? "Całe zdjęcie + Blur" : "Full image + Blur"
        }
    }
}

enum AppMode {
    case browsing
    case duplicates
}

let predefinedColors: [(namePL: String, nameEN: String, hex: String)] = [
    ("Czerwony", "Red", "#FF3B30"), ("Pomarańczowy", "Orange", "#FF9500"), ("Żółty", "Yellow", "#FFCC00"),
    ("Zielony", "Green", "#28CD41"), ("Miętowy", "Mint", "#00C7BE"), ("Niebieski", "Blue", "#007AFF"),
    ("Fioletowy", "Purple", "#8A2BE2"), ("Różowy", "Pink", "#FF2D55"), ("Szary", "Gray", "#8E8E93")
]

struct FileMetadataModel {
    let url: URL
    let name: String
    let path: String
    let size: Int64
    let creationDate: Date?
    let modDate: Date?
}

// MARK: - Główny Widok (ContentView)

struct ContentView: View {
    @StateObject var manager = FolderManager()
    
    @AppStorage("previewMode") private var previewMode: PreviewMode = .aspectFit
    @AppStorage("videoAutoplay") private var videoAutoplay = true
    @AppStorage("videoSound") private var videoSound = false
    @AppStorage("showListThumbnails") private var showListThumbnails = true
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .pl
    
    @State private var currentMode: AppMode = .browsing
    @State private var selectedDuplicateGroupIndex: Int?
    
    // Helper do łatwego tłumaczenia w widoku
    private func t(_ pl: String, _ en: String) -> String { appLanguage == .pl ? pl : en }
    
    var body: some View {
        NavigationSplitView {
            // ==========================================
            // LEWA KOLUMNA: Nawigacja i listy
            // ==========================================
            VStack(spacing: 0) {
                // Przełącznik języka na samej górze
                Picker(t("Język", "Language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                VStack(spacing: 8) {
                    Button(action: {
                        manager.selectFolderToBrowse()
                        currentMode = .browsing
                    }) {
                        Text(t("Wybierz folder bazowy", "Select base folder"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if currentMode == .browsing {
                        Button(action: {
                            currentMode = .duplicates
                            selectedDuplicateGroupIndex = nil
                            manager.findDuplicates()
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text(t("Znajdź duplikaty", "Find duplicates"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.currentFolder == nil || manager.isScanningDuplicates)
                    } else {
                        Button(action: {
                            currentMode = .browsing
                        }) {
                            HStack {
                                Image(systemName: "arrow.left")
                                Text(t("Wróć do przeglądania", "Back to browsing"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                
                Divider()
                
                if currentMode == .browsing {
                    // --- TRYB: PRZEGLĄDANIE ---
                    VStack(spacing: 8) {
                        
                        // Wyłączone zgodnie z prośbą, ale nie usunięte z kodu:
                        /*
                        TextField(t("Szukaj...", "Search..."), text: $manager.searchText)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Picker("Filtr", selection: $manager.filterType) { ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                            Picker("Sort", selection: $manager.sortType) { ForEach(SortType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                        }
                        */
                        
                        HStack {
                            // "Płaski widok" zamienione na "Uwzględnij podfoldery"
                            Toggle(t("Uwzględnij podfoldery", "Include subfolders"), isOn: $manager.isRecursive)
                            Spacer()
                            Toggle(t("Miniatury", "Thumbnails"), isOn: $showListThumbnails)
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    
                    List(selection: $manager.selectedFiles) {
                        ForEach(manager.displayFiles, id: \.self) { file in
                            HStack {
                                if showListThumbnails {
                                    AsyncThumbnail(url: file, size: CGSize(width: 30, height: 30), isIcon: true)
                                        .frame(width: 30, height: 30)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .padding(.horizontal, 5)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text(file.lastPathComponent).lineLimit(1)
                                    if manager.isRecursive {
                                        Text(file.deletingLastPathComponent().lastPathComponent).font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }.tag(file)
                        }
                    }
                } else {
                    // --- TRYB: DUPLIKATY ---
                    if manager.isScanningDuplicates {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                            Text(t("Skanowanie plików...", "Scanning files..."))
                                .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center).padding()
                            Spacer()
                        }
                    } else if manager.duplicateGroups.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundColor(.green)
                            Text(t("Brak duplikatów!", "No duplicates found!")).font(.headline).padding(.top, 4)
                            Spacer()
                        }
                    } else {
                        List(selection: $selectedDuplicateGroupIndex) {
                            ForEach(manager.duplicateGroups.indices, id: \.self) { index in
                                HStack {
                                    Image(systemName: "folder.fill.badge.person.crop").foregroundColor(.purple)
                                    VStack(alignment: .leading) {
                                        Text(t("Grupa \(index + 1)", "Group \(index + 1)")).bold()
                                        Text(t("\(manager.duplicateGroups[index].count) plików", "\(manager.duplicateGroups[index].count) files"))
                                            .font(.caption).foregroundColor(.gray)
                                    }
                                }
                                .tag(index)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            
        } detail: {
            HStack(spacing: 0) {
                if currentMode == .browsing {
                    // ==========================================
                    // ŚRODKOWA KOLUMNA: Podgląd pliku
                    // ==========================================
                    VStack(spacing: 0) {
                        if let folder = manager.currentFolder {
                            Text(folder.lastPathComponent).font(.title2).fontWeight(.semibold).padding(.vertical, 10)
                        }
                        
                        if manager.selectedFiles.count > 1 {
                            VStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 60))
                                Text(t("Wybrano \(manager.selectedFiles.count) plików", "Selected \(manager.selectedFiles.count) files"))
                                    .font(.title).fontWeight(.bold)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let selected = manager.selectedFiles.first {
                            FilePreview(url: selected, previewMode: previewMode, autoplay: videoAutoplay, sound: videoSound, isFitted: false)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                                .onDrag { NSItemProvider(object: selected as NSURL) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Divider()
                    
                    // ==========================================
                    // PRAWA KOLUMNA: Opcje i mapowanie
                    // ==========================================
                    VStack(spacing: 12) {
                        GroupBox(t("Ustawienia", "Settings")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker(t("Styl", "Style"), selection: $previewMode) {
                                    ForEach(PreviewMode.allCases) { Text($0.localized(appLanguage)).tag($0) }
                                }.labelsHidden()
                                
                                Text(t("Opcje stylu dotyczą tylko zdjęć", "Style options apply to photos only"))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.bottom, 4)
                                
                                Toggle(t("Auto-wideo", "Auto-video"), isOn: $videoAutoplay)
                                Toggle(t("Dźwięk wideo", "Video sound"), isOn: $videoSound).disabled(!videoAutoplay)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading) // Wyrównanie do lewej
                        }.padding(.top)
                        
                        Text(t("Przenieś do:", "Move to:")).font(.headline)
                        List {
                            ForEach(manager.targetFolders) { folder in
                                HStack {
                                    Button(action: { manager.moveSelectedFiles(to: folder.url) }) {
                                        HStack {
                                            Image(systemName: "folder.fill").foregroundColor(Color(hex: folder.colorHex))
                                            Text(folder.url.lastPathComponent).fontWeight(.medium)
                                        }
                                        .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).disabled(manager.selectedFiles.isEmpty)
                                    
                                    Menu {
                                        // Opcja 1: Kolory (zagnieżdżone)
                                        Menu(t("Kolor", "Color")) {
                                            ForEach(predefinedColors, id: \.hex) { color in
                                                Button(appLanguage == .pl ? color.namePL : color.nameEN) { manager.updateFolderColor(id: folder.id, newHex: color.hex) }
                                            }
                                        }
                                        
                                        // Opcja 2: Usuń tylko przypisanie folderu
                                        Button(role: .destructive, action: { manager.removeMappedFolder(id: folder.id) }) {
                                            Text(t("Usuń z listy", "Remove from list"))
                                        }
                                        
                                        // Opcja 3: Otwórz w systemowym finderze
                                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }) {
                                            Text(t("Otwórz w Finder", "Open in Finder"))
                                        }
                                        
                                    } label: { Image(systemName: "ellipsis.circle").foregroundColor(.gray) }
                                    .menuStyle(.borderlessButton).frame(width: 30)
                                    .menuIndicator(.hidden)
                                }
                                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                    for provider in providers {
                                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                            if let fileURL = url { DispatchQueue.main.async { manager.moveFile(fileURL, to: folder.url) } }
                                        }
                                    }
                                    return true
                                }
                            }
                            .onMove { i, o in manager.moveTargetFolders(from: i, to: o) }
                        }
                        Button(t("Zmapuj nowe foldery...", "Map new folders...")) { manager.addTargetFolders() }
                        
                        VStack(spacing: 8) {
                            Button(action: { manager.deleteSelectedFiles() }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text(manager.selectedFiles.count > 1 ? t("Usuń (\(manager.selectedFiles.count))", "Delete (\(manager.selectedFiles.count))") : t("Usuń do kosza", "Move to trash"))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent).tint(.red).disabled(manager.selectedFiles.isEmpty)
                            
                            Menu {
                                if manager.history.isEmpty {
                                    Text(t("Brak operacji do cofnięcia", "No operations to undo"))
                                } else {
                                    ForEach(manager.history.suffix(5).reversed()) { action in
                                        Button(action.description) { manager.undoAction(id: action.id) }
                                    }
                                }
                            } label: {
                                HStack { Image(systemName: "arrow.uturn.backward"); Text(t("Cofnij...", "Undo...")) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .menuStyle(.borderlessButton).buttonStyle(.bordered).disabled(manager.history.isEmpty)
                        }.padding(.bottom)
                    }
                    .padding(.horizontal).frame(width: 260).background(Color(NSColor.controlBackgroundColor))
                    
                } else {
                    // ==========================================
                    // TRYB: PORÓWNANIE DUPLIKATÓW
                    // ==========================================
                    if let groupIndex = selectedDuplicateGroupIndex, manager.duplicateGroups.indices.contains(groupIndex) {
                        DuplicateCompareView(
                            groupIndex: groupIndex,
                            urls: manager.duplicateGroups[groupIndex],
                            manager: manager,
                            previewMode: previewMode,
                            autoplay: videoAutoplay,
                            sound: videoSound
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text(t("Wybierz grupę duplikatów z listy po lewej stronie", "Select a duplicate group from the left list"))
                            .foregroundColor(.gray)
                            .font(.title2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Moduł Porównywania Duplikatów

struct DuplicateCompareView: View {
    let groupIndex: Int
    let urls: [URL]
    @ObservedObject var manager: FolderManager
    let previewMode: PreviewMode
    let autoplay: Bool
    let sound: Bool
    
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .pl
    private func t(_ pl: String, _ en: String) -> String { appLanguage == .pl ? pl : en }
    
    @State private var metas: [FileMetadataModel] = []
    
    var body: some View {
        HStack(spacing: 0) {
            // LEWA STRONA: Lista detali
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    Text(t("Porównanie (\(urls.count) plików)", "Comparison (\(urls.count) files)"))
                        .font(.title2).bold().padding(.top)
                    
                    Button(role: .destructive, action: {
                        manager.trashDuplicateGroup(groupIndex)
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(t("Usuń wszystkie (\(urls.count)) pliki z grupy", "Delete all (\(urls.count)) files from group"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                    
                    ForEach(urls, id: \.self) { url in
                        if let meta = metas.first(where: { $0.url == url }) {
                            DuplicateDetailCard(
                                url: url,
                                meta: meta,
                                groupIndex: groupIndex,
                                manager: manager,
                                isNameDiff: differs(in: \.name),
                                isCreationDiff: differs(in: \.creationDate),
                                isModDiff: differs(in: \.modDate)
                            )
                        }
                    }
                }
                .padding(.bottom)
            }
            .frame(width: 350)
            
            Divider()
            
            // PRAWA STRONA: Pełny podgląd (wymuszamy isFitted: true)
            if let firstUrl = urls.first {
                VStack(spacing: 0) {
                    Text(firstUrl.lastPathComponent)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.vertical, 10)
                    
                    FilePreview(url: firstUrl, previewMode: previewMode, autoplay: autoplay, sound: sound, isFitted: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadMetas)
        .onChange(of: urls) { _, _ in loadMetas() }
    }
    
    private func differs<T: Hashable>(in keyPath: KeyPath<FileMetadataModel, T>) -> Bool {
        let uniqueValues = Set(metas.map { $0[keyPath: keyPath] })
        return uniqueValues.count > 1
    }
    
    private func loadMetas() {
        var newMetas: [FileMetadataModel] = []
        for url in urls {
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            let res = try? url.resourceValues(forKeys: [.creationDateKey])
            newMetas.append(FileMetadataModel(
                url: url,
                name: url.lastPathComponent,
                path: url.path,
                size: (attr?[.size] as? Int64) ?? 0,
                creationDate: res?.creationDate,
                modDate: attr?[.modificationDate] as? Date
            ))
        }
        self.metas = newMetas
    }
}

// Osobny komponent dla karty
struct DuplicateDetailCard: View {
    let url: URL
    let meta: FileMetadataModel
    let groupIndex: Int
    @ObservedObject var manager: FolderManager
    let isNameDiff: Bool
    let isCreationDiff: Bool
    let isModDiff: Bool
    
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .pl
    private func t(_ pl: String, _ en: String) -> String { appLanguage == .pl ? pl : en }
    
    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: t("Nazwa:", "Name:"), value: meta.name, isDiff: isNameDiff)
                InfoRow(title: t("Rozmiar:", "Size:"), value: formatSize(meta.size), isDiff: false)
                InfoRow(title: t("Utworzono:", "Created:"), value: formatDate(meta.creationDate), isDiff: isCreationDiff)
                InfoRow(title: t("Zmieniono:", "Modified:"), value: formatDate(meta.modDate), isDiff: isModDiff)
                InfoRow(title: t("Ścieżka:", "Path:"), value: url.path, isDiff: true, urlToOpen: url)
            }
            .font(.system(size: 12))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            
            Button(role: .destructive, action: {
                manager.trashDuplicate(url, from: groupIndex)
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text(t("Usuń ten plik", "Delete this file"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal)
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        String(format: "%.2f MB", Double(bytes) / 1048576)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return t("Brak", "N/A") }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df.string(from: date)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let isDiff: Bool
    var urlToOpen: URL? = nil
    
    var body: some View {
        HStack(alignment: .top) {
            Text(title).foregroundColor(.gray).frame(width: 75, alignment: .leading)
            
            if let targetUrl = urlToOpen {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([targetUrl.absoluteURL])
                }) {
                    Text(value)
                        .foregroundColor(isDiff ? .red : .blue)
                        .underline()
                        .bold(isDiff)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                Text(value)
                    .foregroundColor(isDiff ? .red : .primary)
                    .bold(isDiff)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Komponenty Multimedialne

struct AsyncThumbnail: View {
    let url: URL
    let size: CGSize
    var isIcon: Bool = false // Dla małych miniaturek
    
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if let img = image {
                if isIcon {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Image(nsImage: img).resizable()
                }
            } else {
                ProgressView().scaleEffect(0.5)
            }
        }
        .onDisappear{
            image = nil
        }
        .task(id: url) {
            image = nil
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            
            if !url.isVideo {
                let directImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                    if let data = try? Data(contentsOf: url, options: .mappedIfSafe), let img = NSImage(data: data) {
                        return img
                    }
                    return NSImage(contentsOf: url) // Fallback
                }.value
                
                if let valid = directImage, !Task.isCancelled {
                    await MainActor.run { self.image = valid }
                    return
                }
            }
            
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let targetSize = isIcon ? size : CGSize(width: size.width * 2, height: size.height * 2)
            let reqTypes: QLThumbnailGenerator.Request.RepresentationTypes = isIcon ? .thumbnail : .all
            
            let req = QLThumbnailGenerator.Request(fileAt: url, size: targetSize, scale: scale, representationTypes: reqTypes)
            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
                if !Task.isCancelled { await MainActor.run { self.image = rep.nsImage } }
            } catch {
                if !Task.isCancelled { await MainActor.run { self.image = NSWorkspace.shared.icon(forFile: url.path) } }
            }
        }
    }
}

struct FilePreview: View {
    let url: URL
    let previewMode: PreviewMode
    let autoplay: Bool
    let sound: Bool
    var isFitted: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if url.isVideo {
                    AutoVideoPlayer(url: url, autoplay: autoplay, sound: sound)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    if isFitted {
                        AsyncThumbnail(url: url, size: geo.size, isIcon: false)
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        if previewMode == .fitWithBlur {
                            ZStack {
                                AsyncThumbnail(url: url, size: geo.size, isIcon: false)
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .blur(radius: 40)
                                    .clipped()
                                
                                AsyncThumbnail(url: url, size: geo.size, isIcon: false)
                                    .scaledToFit()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .shadow(color: .black.opacity(0.6), radius: 15, x: 0, y: 5)
                            }
                        } else if previewMode == .aspectFill {
                            AsyncThumbnail(url: url, size: geo.size, isIcon: false)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            AsyncThumbnail(url: url, size: geo.size, isIcon: false)
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }
                
                VStack {
                    Spacer()
                    MetadataOverlay(url: url)
                }
            }
        }
    }
}

struct MetadataOverlay: View {
    let url: URL
    @State private var info = ""
    
    var body: some View {
        Text(info)
            .font(.caption).fontWeight(.medium).foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(.bottom, 70)
            .task(id: url) {
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
                
                let detailsStr = await Task.detached(priority: .userInitiated) {
                    var details: [String] = []
                    if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attr[.size] as? Int64 { details.append(String(format: "%.1f MB", Double(size) / 1048576)) }
                    
                    if let res = try? url.resourceValues(forKeys: [.creationDateKey]), let date = res.creationDate {
                        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
                        details.append(df.string(from: date))
                    }
                    
                    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                       let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                       let w = props["PixelWidth"] as? Int, let h = props["PixelHeight"] as? Int {
                        details.append("\(w)x\(h)")
                    }
                    return details.joined(separator: " • ")
                }.value
                
                if !Task.isCancelled { await MainActor.run { self.info = detailsStr } }
            }
    }
}

struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer?
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player != player {
            nsView.player = player
        }
    }
}

struct AutoVideoPlayer: View {
    let url: URL
    let autoplay: Bool
    let sound: Bool
    
    @State private var player: AVPlayer?
    @State private var ratio: CGFloat = 16/9
    @State private var isReady = false
    
    var body: some View {
        ZStack {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .shadow(color: isReady ? .black.opacity(0.4) : .clear, radius: 8)
                .overlay(
                    NativeVideoPlayer(player: player)
                        .opacity(isReady ? 1 : 0)
                )
            
            if !isReady {
                ProgressView()
            }
        }
        .task(id: url) {
            isReady = false
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            
            let asset = AVURLAsset(url: url)
            var newRatio: CGFloat = 16/9
            
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                
                let realSize = size.applying(transform)
                if realSize.height > 0 {
                    newRatio = abs(realSize.width / realSize.height)
                }
            }
            
            if Task.isCancelled { return }
            
            let newItem = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: newItem)
            newPlayer.isMuted = !sound
            
            await MainActor.run {
                self.ratio = newRatio
                self.player = newPlayer
                self.isReady = true
                if autoplay { self.player?.play() }
            }
        }
        .onChange(of: sound) { _, newSound in player?.isMuted = !newSound }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
}
