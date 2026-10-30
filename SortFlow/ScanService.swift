import Foundation
import SQLite3

// Indeks na dysku: unikalne pliki i próbki nie tworzą wielkich słowników w RAM.
private final class ScanIndex {
    private var db: OpaquePointer?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("sortflow-\(UUID().uuidString).sqlite")
    init() throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        try execute("PRAGMA journal_mode=OFF; PRAGMA cache_size=-4096; PRAGMA temp_store=FILE; CREATE TABLE files(path TEXT PRIMARY KEY, size INTEGER, identity TEXT UNIQUE, sample TEXT, digest TEXT); CREATE INDEX sizes ON files(size);")
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> Error {
        NSError(domain: "SortFlow.Index", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
    func rows(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw failure() }
            try body(statement)
        }
    }
    static func string(_ row: OpaquePointer, _ column: Int32) -> String { String(cString: sqlite3_column_text(row, column)) }
    func insert(_ file: FileEntry) throws {
        try bind("INSERT OR IGNORE INTO files(path,size,identity) VALUES(?,?,?)", values: [file.url.path, String(file.size), file.identity])
    }
    func update(_ path: String, column: String, value: String) throws {
        try bind("UPDATE files SET \(column)=? WHERE path=?", values: [value, path])
    }
    private func bind(_ sql: String, values: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            _ = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
}
enum ScanService {
    static func list(_ folder: URL, recursive: Bool, flag: CancellationFlag) throws -> ([FileEntry], [String]) {
        let fm = FileManager.default
        var entries: [FileEntry] = [], errors: [String] = []
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey], options: options, errorHandler: { url, error in
            if errors.count < 1000 { errors.append("\(url.path): \(error.localizedDescription)") }; return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        for case let url as URL in enumerator {
            try flag.check()
            try autoreleasepool {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true || values?.isSymbolicLink == true { return }
                do { entries.append(try FileEntry.read(url)) }
                catch { if errors.count < 1000 { errors.append("\(url.path): \(error.localizedDescription)") } }
            }
        }
        return (entries, errors)
    }
    static func duplicates(_ folder: URL, recursive: Bool, flag: CancellationFlag, progress: @escaping @Sendable (ScanProgress) -> Void) throws -> ScanResult {
        let index = try ScanIndex()
        var status = ScanProgress(stage: tr("Indeksowanie", "Indexing")), errors: [String] = []
        var lastUpdate = Date.distantPast
        func publish(force: Bool = false) {
            if force || Date().timeIntervalSince(lastUpdate) > 0.12 { progress(status); lastUpdate = Date() }
        }
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: options, errorHandler: { url, error in
            if errors.count < 1000 { errors.append("\(url.path): \(error.localizedDescription)") }; return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        try index.execute("BEGIN")
        for case let url as URL in enumerator {
            try flag.check()
            try autoreleasepool {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true || values?.isSymbolicLink == true { return }
                do { try index.insert(FileEntry.read(url)); status.files += 1 }
                catch { if errors.count < 1000 { errors.append("\(url.path): \(error.localizedDescription)") } }
            }
            publish()
        }
        try index.execute("COMMIT")
        status.stage = tr("Porównanie próbek", "Comparing samples"); publish(force: true)
        try index.rows("SELECT path FROM files WHERE size IN (SELECT size FROM files GROUP BY size HAVING COUNT(*)>1)") { row in
            try flag.check()
            let path = ScanIndex.string(row, 0)
            do { try index.update(path, column: "sample", value: FileService.sample(URL(fileURLWithPath: path), flag: flag)) }
            catch is CancellationError { throw CancellationError() }
            catch { if errors.count < 1000 { errors.append("\(path): \(error.localizedDescription)") } }
            publish()
        }
        try index.execute("CREATE INDEX samples ON files(size,sample)")
        let candidates = "sample IS NOT NULL AND (size,sample) IN (SELECT size,sample FROM files WHERE sample IS NOT NULL GROUP BY size,sample HAVING COUNT(*)>1)"
        try index.rows("SELECT COALESCE(SUM(size),0) FROM files WHERE \(candidates)") { status.total = sqlite3_column_int64($0, 0) }
        status.stage = tr("Weryfikacja SHA-256", "SHA-256 verification"); publish(force: true)
        try index.rows("SELECT path FROM files WHERE \(candidates)") { row in
            try flag.check()
            let path = ScanIndex.string(row, 0)
            do {
                let digest = try FileService.hash(URL(fileURLWithPath: path), flag: flag) { bytes in status.done += bytes; publish() }
                try index.update(path, column: "digest", value: digest)
            } catch is CancellationError { throw CancellationError() }
            catch { if errors.count < 1000 { errors.append("\(path): \(error.localizedDescription)") } }
        }
        var groups: [DuplicateGroup] = []
        var currentID = "", currentFiles: [FileEntry] = []
        try index.rows("SELECT path,digest,size FROM files WHERE digest IN (SELECT digest FROM files WHERE digest IS NOT NULL GROUP BY digest HAVING COUNT(*)>1) ORDER BY digest,path") { row in
            try flag.check()
            let id = ScanIndex.string(row, 1)
            if id != currentID {
                if currentFiles.count > 1 { groups.append(DuplicateGroup(id: currentID, files: currentFiles)) }
                currentID = id; currentFiles = []
            }
            let url = URL(fileURLWithPath: ScanIndex.string(row, 0))
            do { currentFiles.append(try FileEntry.read(url)) }
            catch { if errors.count < 1000 { errors.append("\(url.path): \(error.localizedDescription)") } }
        }
        if currentFiles.count > 1 { groups.append(DuplicateGroup(id: currentID, files: currentFiles)) }
        status.stage = tr("Gotowe", "Finished"); publish(force: true)
        return ScanResult(groups: groups.sorted { $0.recoverable > $1.recoverable }, errors: errors)
    }
}
