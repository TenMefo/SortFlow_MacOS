//
//  ContentView.swift
//  SwipeCleaner_MacOS
//
//  Created by Mateusz Parciak on 19/07/2026.
//

import SwiftUI
import AVKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// Konwerter HEX
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
        let uti = try? self.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        return uti?.contains("movie") == true || uti?.contains("video") == true || ["mp4", "mov", "mkv", "avi"].contains(self.pathExtension.lowercased())
    }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case aspectFit = "Dopasuj do okna"
    case aspectFill = "Wypełnij"
    case fitWithBlur = "Całe zdjęcie + Blur"
    var id: Self { self }
}

let predefinedColors: [(name: String, hex: String)] = [
    ("Czerwony", "#FF3B30"), ("Pomarańczowy", "#FF9500"), ("Żółty", "#FFCC00"),
    ("Zielony", "#28CD41"), ("Miętowy", "#00C7BE"), ("Niebieski", "#007AFF"),
    ("Fioletowy", "#8A2BE2"), ("Różowy", "#FF2D55"), ("Szary", "#8E8E93")
]

struct ContentView: View {
    @StateObject var manager = FolderManager()
    @AppStorage("previewMode") private var previewMode: PreviewMode = .aspectFit
    @AppStorage("videoAutoplay") private var videoAutoplay = true
    @AppStorage("videoSound") private var videoSound = false
    
    // Nowy przełącznik do miniatur
    @AppStorage("showListThumbnails") private var showListThumbnails = true
    
    var body: some View {
        NavigationSplitView {
            // LEWA STRONA (Filtry i lista)
            VStack(spacing: 0) {
                Button("Wybierz folder bazowy") { manager.selectFolderToBrowse() }
                    .padding()
                    .buttonStyle(.borderedProminent)
                
                VStack(spacing: 8) {
                    TextField("Szukaj...", text: $manager.searchText)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        Picker("Filtr", selection: $manager.filterType) { ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                        Picker("Sort", selection: $manager.sortType) { ForEach(SortType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                    }
                    
                    // Przełączniki na dole sekcji z filtrami
                    HStack {
                        Toggle("Płaski widok", isOn: $manager.isRecursive)
                        Spacer()
                        Toggle("Miniatury", isOn: $showListThumbnails)
                    }
                    .font(.caption)
                }
                .padding(.horizontal).padding(.bottom, 8)
                
                List(selection: $manager.selectedFiles) {
                    ForEach(manager.displayFiles, id: \.self) { file in
                        HStack {
                            // Warunkowe wyświetlanie miniaturki lub systemowej ikony
                            if showListThumbnails {
                                AsyncThumbnail(url: file, size: CGSize(width: 30, height: 30))
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
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            
        } detail: {
            HStack(spacing: 0) {
                // ŚRODEK (Podgląd)
                VStack(spacing: 0) {
                    if let folder = manager.currentFolder {
                        Text(folder.lastPathComponent).font(.title2).fontWeight(.semibold).padding(.vertical, 10)
                    }
                    
                    if manager.selectedFiles.count > 1 {
                        VStack(spacing: 16) {
                            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 60))
                            Text("Wybrano \(manager.selectedFiles.count) plików").font(.title).fontWeight(.bold)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let selected = manager.selectedFiles.first {
                        FilePreview(url: selected, previewMode: previewMode, autoplay: videoAutoplay, sound: videoSound)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                            .onDrag { NSItemProvider(object: selected as NSURL) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // PRAWA STRONA (Operacje)
                VStack(spacing: 12) {
                    GroupBox("Ustawienia") {
                        Picker("Styl", selection: $previewMode) { ForEach(PreviewMode.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
                        Toggle("Auto-wideo", isOn: $videoAutoplay).padding(.top, 4)
                        Toggle("Dźwięk wideo", isOn: $videoSound).disabled(!videoAutoplay)
                    }.padding(.top)
                    
                    Text("Przenieś do:").font(.headline)
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
                                    Text("Zmień kolor"); Divider()
                                    ForEach(predefinedColors, id: \.hex) { color in
                                        Button(color.name) { manager.updateFolderColor(id: folder.id, newHex: color.hex) }
                                    }
                                    Divider()
                                    Button("Usuń z listy", role: .destructive) { manager.removeMappedFolder(id: folder.id) }
                                } label: { Image(systemName: "ellipsis.circle").foregroundColor(.gray) }
                                .menuStyle(.borderlessButton).frame(width: 30)
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
                    Button("Zmapuj nowe foldery...") { manager.addTargetFolders() }
                    
                    VStack(spacing: 8) {
                        Button(action: { manager.deleteSelectedFiles() }) {
                            HStack { Image(systemName: "trash.fill"); Text(manager.selectedFiles.count > 1 ? "Usuń (\(manager.selectedFiles.count))" : "Usuń do kosza") }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).tint(.red).disabled(manager.selectedFiles.isEmpty)
                        
                        Menu {
                            if manager.history.isEmpty {
                                Text("Brak operacji do cofnięcia")
                            } else {
                                ForEach(manager.history.suffix(5).reversed()) { action in
                                    Button(action.description) { manager.undoAction(id: action.id) }
                                }
                            }
                        } label: {
                            HStack { Image(systemName: "arrow.uturn.backward"); Text("Cofnij...") }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .menuStyle(.borderlessButton).buttonStyle(.bordered).disabled(manager.history.isEmpty)
                    }.padding(.bottom)
                }
                .padding(.horizontal).frame(width: 260).background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
}

// ASYNCHRONICZNE MINIATURKI (Z systemem opóźnienia)
struct AsyncThumbnail: View {
    let url: URL
    let size: CGSize
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ProgressView().scaleEffect(0.5)
            }
        }
        .task(id: url) {
            image = nil
            
            // Czekamy 0.1 sekundy. Jeśli użytkownik poleci dalej, zadanie się anuluje i w ogóle nie odpali QuickLooka!
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
            
            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
                if !Task.isCancelled { await MainActor.run { self.image = rep.nsImage } }
            } catch {
                if !Task.isCancelled { await MainActor.run { self.image = NSWorkspace.shared.icon(forFile: url.path) } }
            }
        }
    }
}

// PODGLĄD Z NAKŁADKĄ METADANYCH (Zoptymalizowany)
struct FilePreview: View {
    let url: URL
    let previewMode: PreviewMode
    let autoplay: Bool
    let sound: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Bezpośrednie sprawdzenie rozszerzenia, ZERO wycieków pamięci
                if url.isVideo {
                    AutoVideoPlayer(url: url, autoplay: autoplay, sound: sound)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    AsyncThumbnail(url: url, size: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                
                VStack {
                    Spacer()
                    MetadataOverlay(url: url)
                }
            }
        }
    }
}

// WIDOK NAKŁADKI Z INFO (Z systemem opóźnienia)
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
                // Krótkie opóźnienie przed odczytem z dysku (0.05 sekundy)
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

// 1. NATYWNY ODTWARZACZ Z APPKIT (Omija zbugowany _AVKit_SwiftUI)
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer?
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect // Zapobiega wylewaniu się wideo
        view.player = player
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player != player {
            nsView.player = player
        }
    }
}

// 2. ZOPTYMALIZOWANY KONTENER WIDEO
struct AutoVideoPlayer: View {
    let url: URL
    let autoplay: Bool
    let sound: Bool
    
    @State private var player: AVPlayer?
    @State private var ratio: CGFloat = 16/9
    @State private var isReady = false
    
    var body: some View {
        ZStack {
            // Trik na stabilność: wymuszamy proporcje i nakładamy cień na "głupim",
            // całkowicie przezroczystym widoku, a odtwarzacz po prostu go wypełnia.
            // Eliminuje to wszelkie nieskończone pętle renderowania.
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
            // 1. Reset na starcie zadania
            isReady = false
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            
            // 2. Debounce - czekamy 0.15s, zanim dotkniemy dysku
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            
            // 3. Ładowanie metadanych w tle
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
            
            // Sprawdzamy, czy użytkownik nie przeskoczył w międzyczasie na inny plik
            if Task.isCancelled { return }
            
            // 4. Inicjalizacja i publikacja na głównym wątku
            let newItem = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: newItem)
            newPlayer.isMuted = !sound
            
            await MainActor.run {
                self.ratio = newRatio
                self.player = newPlayer
                // Pokazujemy natychmiast bez .withAnimation (animacja też psuła logikę layoutu)
                self.isReady = true
                if autoplay { self.player?.play() }
            }
        }
        .onChange(of: sound) { _, newSound in player?.isMuted = !newSound }
        .onDisappear {
            // Twarde czyszczenie zasobów
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
}
