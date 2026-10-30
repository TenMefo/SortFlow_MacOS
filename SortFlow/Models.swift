import Foundation
import UniformTypeIdentifiers

// Dane nie przechowują obrazów ani odtwarzaczy. Podglądy żyją osobno.
enum AppLanguage: String, CaseIterable { case pl = "PL", en = "EN" }
func tr(_ pl: String, _ en: String) -> String {
    UserDefaults.standard.string(forKey: "appLanguage") == "EN" ? en : pl
}
enum AppMode: String, CaseIterable { case files, duplicates }
enum FileKind: String, CaseIterable, Codable {
    case all, image, raw, video, audio, document, other
    var title: String {
        switch self {
        case .all: return tr("Wszystkie", "All")
        case .image: return tr("Zdjęcia", "Photos")
        case .raw: return "RAW"
        case .video: return tr("Wideo", "Video")
        case .audio: return "Audio"
        case .document: return tr("Dokumenty", "Documents")
        case .other: return tr("Inne", "Other")
        }
    }
    var symbol: String {
        switch self {
        case .image, .raw: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc.text"
        case .all, .other: return "doc"
        }
    }
    static func detect(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ["cr2", "cr3", "nef", "arw", "dng", "raw", "orf", "raf", "rw2"].contains(ext) { return .raw }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || ["mkv", "avi"].contains(ext) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || ["doc", "docx", "pages", "xls", "xlsx", "ppt", "pptx", "rtf"].contains(ext) { return .document }
        return .other
    }
}
enum SortOrder: String, CaseIterable, Codable {
    case nameAZ, nameZA, sizeDesc, sizeAsc, newest, oldest, type
    var title: String {
        switch self {
        case .nameAZ: return "A → Z"
        case .nameZA: return "Z → A"
        case .sizeDesc: return tr("Największe", "Largest")
        case .sizeAsc: return tr("Najmniejsze", "Smallest")
        case .newest: return tr("Najnowsze", "Newest")
        case .oldest: return tr("Najstarsze", "Oldest")
        case .type: return tr("Typ pliku", "File type")
        }
    }
}
enum TransferMode: String, CaseIterable, Codable { case move, copy
    var title: String { self == .move ? tr("Przenieś", "Move") : tr("Kopiuj", "Copy") }
}
enum PreviewStyle: String, CaseIterable { case fit, fill, blur }
enum ConflictChoice: String { case keepBoth, replace, skip }
struct FileEntry: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let created: Date
    let modified: Date
    let kind: FileKind
    let identity: String
    var name: String { url.lastPathComponent }
    static func read(_ url: URL) throws -> FileEntry {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let identity = "\(attributes[.systemNumber] ?? 0):\(attributes[.systemFileNumber] ?? 0)"
        return FileEntry(url: url.standardizedFileURL, size: Int64(values.fileSize ?? 0), created: values.creationDate ?? .distantPast,
                         modified: values.contentModificationDate ?? .distantPast, kind: .detect(url), identity: identity)
    }
}
struct MappedFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var colorHex: String = "#8A2BE2"
    var alias: String?
    var title: String { alias?.isEmpty == false ? alias! : url.lastPathComponent }
}
struct Workspace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var folders: [MappedFolder]
    var source: URL?
    var selected: URL?
    var recursive: Bool?
    var filter: FileKind?
    var sort: SortOrder?
    var transfer: TransferMode?
    var deferred: [URL]?
    var preferredFolder: URL?
}
struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    var files: [FileEntry]
    var recoverable: Int64 { Int64(max(0, files.count - 1)) * (files.first?.size ?? 0) }
}
struct ScanProgress: Sendable {
    var stage = ""
    var files = 0
    var done: Int64 = 0
    var total: Int64 = 0
}
struct ScanResult: Sendable { var groups: [DuplicateGroup]; var errors: [String] }
struct Rule: Identifiable, Codable {
    var id = UUID()
    var name: String
    var kind: FileKind = .all
    var contains: String = ""
    var target: URL
    var enabled = true
    func matches(_ file: FileEntry) -> Bool {
        enabled && (kind == .all || kind == file.kind) && (contains.isEmpty || file.name.localizedCaseInsensitiveContains(contains))
    }
}
struct PlannedTransfer: Identifiable, Sendable {
    var id: URL { source }
    let source: URL
    var destination: URL
}
struct UndoItem: Codable, Sendable {
    // Pierwotne i aktualne położenie oraz ewentualna kopia zastąpionego pliku.
    var original: URL
    var current: URL
    var copied: Bool
    var backup: URL?
}
struct HistoryRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    var date = Date()
    var title: String
    var items: [UndoItem]
}
struct OperationReport: Sendable {
    var items: [UndoItem] = []
    var errors: [String] = []
    var cancelled = false
}
struct SessionStats {
    var moved = 0
    var copied = 0
    var trashed = 0
    var bytes: Int64 = 0
    var destinations: [String: Int] = [:]
}
struct FileConflict: Identifiable {
    var id: URL { plan.source }
    let plan: PlannedTransfer
}
extension Int64 {
    var byteLabel: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
