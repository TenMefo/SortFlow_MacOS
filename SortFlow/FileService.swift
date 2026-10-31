import Foundation
import CryptoKit

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func check() throws { if isCancelled { throw CancellationError() } }
}

// Jedna kolejka operacji: konflikty i przeciąganie nie nadpisują stanu partii.
enum FileService {
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        if a.standardizedFileURL.resolvingSymlinksInPath() == b.standardizedFileURL.resolvingSymlinksInPath() { return true }
        if let x = try? FileEntry.read(a), let y = try? FileEntry.read(b) { return x.identity == y.identity }
        return false
    }
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        var result = url
        var number = 1
        while fm.fileExists(atPath: result.path) {
            let name = url.deletingPathExtension().lastPathComponent + " \(number)"
            result = url.deletingLastPathComponent().appendingPathComponent(name)
            if !url.pathExtension.isEmpty { result.appendPathExtension(url.pathExtension) }
            number += 1
        }
        return result
    }
    static func hash(_ url: URL, flag: CancellationFlag, progress: ((Int64) -> Void)? = nil) throws -> String {
        let before = try FileEntry.read(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count: Int64 = 0
        while true {
            try flag.check()
            let length: Int = try autoreleasepool {
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                hasher.update(data: data)
                return data.count
            }
            if length == 0 { break }
            count += Int64(length)
            progress?(Int64(length))
        }
        let after = try FileEntry.read(url)
        guard count == before.size, before.size == after.size, before.modified == after.modified, before.identity == after.identity else {
            throw NSError(domain: "SortFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("Plik zmienił się podczas odczytu", "File changed during reading")])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func sample(_ url: URL, flag: CancellationFlag) throws -> String {
        let entry = try FileEntry.read(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        for offset in Set([Int64(0), max(0, entry.size / 2 - 32768), max(0, entry.size - 65536)]).sorted() {
            try flag.check()
            try handle.seek(toOffset: UInt64(offset))
            hasher.update(data: try handle.read(upToCount: 65536) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func identical(_ a: URL, _ b: URL, flag: CancellationFlag) throws -> Bool {
        let x = try FileEntry.read(a), y = try FileEntry.read(b)
        guard x.size == y.size else { return false }
        let ah = try FileHandle(forReadingFrom: a), bh = try FileHandle(forReadingFrom: b)
        defer { try? ah.close(); try? bh.close() }
        while true {
            try flag.check()
            let result: (Bool, Bool) = try autoreleasepool {
                let ad = try ah.read(upToCount: 1024 * 1024) ?? Data()
                let bd = try bh.read(upToCount: 1024 * 1024) ?? Data()
                return (ad == bd, ad.isEmpty)
            }
            if !result.0 { return false }
            if result.1 { break }
        }
        let ax = try FileEntry.read(a), by = try FileEntry.read(b)
        guard ax.modified == x.modified, by.modified == y.modified, ax.size == x.size, by.size == y.size else { return false }
        return true
    }
    static func linkedFiles(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var results: [String: URL] = [:]
        for url in urls { results[url.standardizedFileURL.resolvingSymlinksInPath().path] = url }
        let families = [Set(["jpg", "jpeg", "heic", "cr2", "cr3", "nef", "arw", "dng", "raw", "orf", "raf", "rw2", "xmp", "aae"]),
                        Set(["mp4", "mov", "mkv", "avi", "m4v", "srt", "vtt", "ass"])]
        for url in urls {
            guard let family = families.first(where: { $0.contains(url.pathExtension.lowercased()) }) else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            let siblings = (try? fm.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
            for sibling in siblings where sibling.deletingPathExtension().lastPathComponent == stem && family.contains(sibling.pathExtension.lowercased()) {
                if (try? FileEntry.read(sibling)) != nil { results[sibling.standardizedFileURL.resolvingSymlinksInPath().path] = results[sibling.standardizedFileURL.resolvingSymlinksInPath().path] ?? sibling }
            }
        }
        return results.values.sorted { $0.path < $1.path }
    }
    static func transfer(_ plan: PlannedTransfer, mode: TransferMode, choice: ConflictChoice, backupRoot: URL) throws -> UndoItem? {
        let fm = FileManager.default
        let source = plan.source, destination = plan.destination
        guard !sameFile(source, destination) else {
            throw NSError(domain: "SortFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: tr("Źródło i cel to ten sam plik", "Source and destination are the same file")])
        }
        _ = try FileEntry.read(source)
        var target = destination
        var backup: URL?
        if fm.fileExists(atPath: target.path) {
            switch choice {
            case .skip: return nil
            case .keepBoth: target = uniqueURL(target)
            case .replace:
                // Najpierw przygotuj kompletny plik obok celu. Źródło i stary cel nadal istnieją.
                let temporary = target.deletingLastPathComponent().appendingPathComponent(".sortflow-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: temporary) }
                try fm.copyItem(at: source, to: temporary)
                try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)
                let saved = backupRoot.appendingPathComponent(UUID().uuidString)
                try fm.moveItem(at: target, to: saved)
                do { try fm.moveItem(at: temporary, to: target) }
                catch {
                    do { try fm.moveItem(at: saved, to: target) }
                    catch { throw NSError(domain: "SortFlow", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(tr("Kopia zapasowa pozostała w", "Backup remains at")) \(saved.path)"]) }
                    throw error
                }
                backup = saved
                if mode == .move {
                    do { try fm.removeItem(at: source) }
                    catch {
                        // Nie zgłaszamy udanego przeniesienia, jeżeli źródła nie usunięto.
                        try? fm.removeItem(at: target)
                        try fm.moveItem(at: saved, to: target)
                        throw error
                    }
                }
                return UndoItem(original: source, current: target, copied: mode == .copy, backup: backup)
            }
        }
        if mode == .copy { try fm.copyItem(at: source, to: target) }
        else { try fm.moveItem(at: source, to: target) }
        return UndoItem(original: source, current: target, copied: mode == .copy, backup: nil)
    }
    static func trash(_ url: URL) throws -> UndoItem {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let moved = result as URL? else { throw CocoaError(.fileNoSuchFile) }
        return UndoItem(original: url, current: moved, copied: false, backup: nil)
    }
    static func undo(_ item: UndoItem) throws {
        let fm = FileManager.default
        // Nie zastępuj niczego, co użytkownik utworzył po operacji.
        if !item.copied && fm.fileExists(atPath: item.original.path) { throw CocoaError(.fileWriteFileExists) }
        if let backup = item.backup {
            guard fm.fileExists(atPath: backup.path) else { throw CocoaError(.fileNoSuchFile) }
        }
        var trashedCopy: UndoItem?
        if item.copied {
            // Kosz zamiast trwałego kasowania kopii, którą użytkownik mógł już edytować.
            trashedCopy = try trash(item.current)
        } else { try fm.moveItem(at: item.current, to: item.original) }
        if let backup = item.backup {
            do { try fm.moveItem(at: backup, to: item.current) }
            catch {
                // Przywróć stan sprzed próby cofnięcia, o ile jest to możliwe.
                if !item.copied { try? fm.moveItem(at: item.original, to: item.current) }
                else if let trashedCopy { try? fm.moveItem(at: trashedCopy.current, to: item.current) }
                throw error
            }
        }
    }
    static func renamePlan(_ urls: [URL], prefix: String, start: Int, includeDate: Bool) -> [PlannedTransfer] {
        let date = DateFormatter(); date.dateFormat = "yyyy-MM-dd"
        return urls.enumerated().map { index, url in
            let base = (includeDate ? date.string(from: Date()) + "_" : "") + prefix + String(format: "%04lld", Int64(start) + Int64(index))
            var target = url.deletingLastPathComponent().appendingPathComponent(base)
            if !url.pathExtension.isEmpty { target.appendPathExtension(url.pathExtension) }
            return PlannedTransfer(source: url, destination: target)
        }
    }
}
