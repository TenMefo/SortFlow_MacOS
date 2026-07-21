//
//  FolderManager.swift
//  SwipeCleaner_MacOS
//
//  Created by Mateusz Parciak on 19/07/2026.
//

import Foundation
import AppKit
import Combine
import SwiftUI

enum FilterType: String, CaseIterable {
    case all = "Wszystkie"
    case video = "Wideo"
    case image = "Zdjęcia"
    case raw = "RAW"
}

enum SortType: String, CaseIterable {
    case name = "Nazwa"
    case size = "Rozmiar"
    case date = "Data"
}

struct FileAction: Identifiable {
    let id = UUID()
    let description: String
    let items: [(original: URL, destination: URL)]
    let isDeletion: Bool
}

struct MappedFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    let url: URL
    var colorHex: String
}

class FolderManager: ObservableObject {
    @Published var currentFolder: URL?
    @Published var files: [URL] = []
    
    @Published var isRecursive = false { didSet { loadFiles() } }
    @Published var searchText = ""
    @Published var filterType: FilterType = .all
    @Published var sortType: SortType = .name
    
    @Published var selectedFiles: Set<URL> = []
    @Published var targetFolders: [MappedFolder] = []
    @Published var history: [FileAction] = []
    
    var displayFiles: [URL] {
        var result = files
        
        if !searchText.isEmpty {
            result = result.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
        }
        
        result = result.filter { url in
            switch filterType {
            case .all: return true
            case .video: return isVideo(url: url)
            case .image: return isImage(url: url) && !isRAW(url: url)
            case .raw: return isRAW(url: url)
            }
        }
        
        result.sort { u1, u2 in
            switch sortType {
            case .name: return u1.lastPathComponent.lowercased() < u2.lastPathComponent.lowercased()
            case .size: return (getFileSize(url: u1) ?? 0) > (getFileSize(url: u2) ?? 0)
            case .date: return (getCreationDate(url: u1) ?? Date.distantPast) > (getCreationDate(url: u2) ?? Date.distantPast)
            }
        }
        return result
    }
    
    init() { loadTargets() }
    
    func selectFolderToBrowse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            currentFolder = panel.url
            loadFiles()
            history.removeAll()
        }
    }
    
    func loadFiles() {
        guard let folder = currentFolder else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var fetchedURLs: [URL] = []
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .creationDateKey]
            let options: FileManager.DirectoryEnumerationOptions = self.isRecursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            
            if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: options) {
                for case let url as URL in enumerator {
                    if let res = try? url.resourceValues(forKeys: Set(keys)), res.isDirectory == false {
                        fetchedURLs.append(url)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.files = fetchedURLs
                let validSelection = self.selectedFiles.intersection(self.files)
                self.selectedFiles = validSelection.isEmpty ? (self.displayFiles.first.map { [$0] } ?? []) : validSelection
            }
        }
    }
    
    func moveSelectedFiles(to target: URL) {
        guard !selectedFiles.isEmpty else { return }
        var movedItems: [(URL, URL)] = []
        
        for file in selectedFiles {
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if (try? FileManager.default.moveItem(at: file, to: destination)) != nil {
                movedItems.append((file, destination))
            }
        }
        if !movedItems.isEmpty {
            history.append(FileAction(description: "Przeniesiono \(movedItems.count) plik(ów)", items: movedItems, isDeletion: false))
            advanceSelection(removing: Set(movedItems.map { $0.0 }))
        }
    }
    
    func moveFile(_ url: URL, to target: URL) {
        let destination = target.appendingPathComponent(url.lastPathComponent)
        if (try? FileManager.default.moveItem(at: url, to: destination)) != nil {
            history.append(FileAction(description: "Przeniesiono 1 plik", items: [(url, destination)], isDeletion: false))
            advanceSelection(removing: [url])
        }
    }
    
    func deleteSelectedFiles() {
        guard !selectedFiles.isEmpty else { return }
        var deletedItems: [(URL, URL)] = []
        
        for file in selectedFiles {
            var trashedURL: NSURL?
            if (try? FileManager.default.trashItem(at: file, resultingItemURL: &trashedURL)) != nil, let trashed = trashedURL as URL? {
                deletedItems.append((file, trashed))
            }
        }
        if !deletedItems.isEmpty {
            history.append(FileAction(description: "Usunięto \(deletedItems.count) plik(ów)", items: deletedItems, isDeletion: true))
            advanceSelection(removing: Set(deletedItems.map { $0.0 }))
        }
    }
    
    func undoAction(id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        let action = history.remove(at: index)
        var restoredFiles: Set<URL> = []
        
        for item in action.items {
            let currentPath = action.isDeletion ? item.destination : item.destination
            if (try? FileManager.default.moveItem(at: currentPath, to: item.original)) != nil {
                restoredFiles.insert(item.original)
            }
        }
        loadFiles()
        if !restoredFiles.isEmpty { selectedFiles = restoredFiles }
    }
    
    // NAPRAWIONA LOGIKA ZAZNACZANIA KOLEJNEGO PLIKU
    private func advanceSelection(removing removedURLs: Set<URL>) {
        let currentDisplay = displayFiles
        
        // Szukamy indeksu ostatniego z plików, który właśnie usuwamy/przenosimy
        var maxIndex = -1
        for url in removedURLs {
            if let idx = currentDisplay.firstIndex(of: url), idx > maxIndex {
                maxIndex = idx
            }
        }
        
        // Zapisujemy, jaki plik jest tuż pod nim, ZANIM fizycznie wywalimy dane
        var nextURLToSelect: URL? = nil
        if maxIndex >= 0 && maxIndex + 1 < currentDisplay.count {
            nextURLToSelect = currentDisplay[maxIndex + 1]
        }
        
        // Właściwe usunięcie
        files.removeAll { removedURLs.contains($0) }
        
        // Zaznaczamy plik, który zapisaliśmy wcześniej
        let newDisplay = displayFiles
        if newDisplay.isEmpty {
            selectedFiles = []
        } else if let next = nextURLToSelect, newDisplay.contains(next) {
            selectedFiles = [next]
        } else {
            // Jeśli przenieśliśmy ostatni plik na liście, zaznaczamy nowy ostatni element
            selectedFiles = [newDisplay.last!]
        }
    }
    
    func addTargetFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !targetFolders.contains(where: { $0.url == url }) { targetFolders.append(MappedFolder(url: url, colorHex: "#8A2BE2")) }
            }
            saveTargets()
        }
    }
    
    func moveTargetFolders(from source: IndexSet, to destination: Int) {
        targetFolders.move(fromOffsets: source, toOffset: destination)
        saveTargets()
    }
    
    func updateFolderColor(id: UUID, newHex: String) {
        if let index = targetFolders.firstIndex(where: { $0.id == id }) {
            targetFolders[index].colorHex = newHex
            saveTargets()
        }
    }
    
    func removeMappedFolder(id: UUID) {
        targetFolders.removeAll(where: { $0.id == id })
        saveTargets()
    }
    
    private func saveTargets() {
        if let encoded = try? JSONEncoder().encode(targetFolders) { UserDefaults.standard.set(encoded, forKey: "mappedFolders") }
    }
    
    private func loadTargets() {
        if let data = UserDefaults.standard.data(forKey: "mappedFolders"), let decoded = try? JSONDecoder().decode([MappedFolder].self, from: data) {
            targetFolders = decoded
        }
    }
    
    func isVideo(url: URL) -> Bool {
        let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        return uti?.contains("movie") == true || uti?.contains("video") == true || ["mp4", "mov", "mkv"].contains(url.pathExtension.lowercased())
    }
    func isImage(url: URL) -> Bool {
        let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        return uti?.contains("image") == true
    }
    func isRAW(url: URL) -> Bool {
        ["cr2", "cr3", "nef", "arw", "dng", "raw"].contains(url.pathExtension.lowercased())
    }
    func getFileSize(url: URL) -> Int? { try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize }
    func getCreationDate(url: URL) -> Date? { try? url.resourceValues(forKeys: [.creationDateKey]).creationDate }
}
