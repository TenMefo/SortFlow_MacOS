import Foundation

// Mały dziennik dopisywany po jednym elemencie; nie przepisujemy całej partii po każdym pliku.
enum HistoryStore {
    static func append(_ record: HistoryRecord, directory: URL) throws {
        guard let last = record.items.last else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appendingPathComponent(record.id.uuidString + ".json")
        if !fm.fileExists(atPath: base.path) {
            var header = record; header.items = []; header.itemCount = nil
            try JSONEncoder().encode(header).write(to: base, options: .atomic)
        }
        let journal = directory.appendingPathComponent(record.id.uuidString + ".jsonl")
        if !fm.fileExists(atPath: journal.path) { fm.createFile(atPath: journal.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: journal)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONEncoder().encode(last); data.append(10)
        try handle.write(contentsOf: data)
        try JSONEncoder().encode(record.summary).write(to: directory.appendingPathComponent(record.id.uuidString + ".meta.json"), options: .atomic)
    }
    static func save(_ record: HistoryRecord, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var full = record; full.itemCount = nil
        try JSONEncoder().encode(full).write(to: directory.appendingPathComponent(record.id.uuidString + ".json"), options: .atomic)
        try JSONEncoder().encode(full.summary).write(to: directory.appendingPathComponent(record.id.uuidString + ".meta.json"), options: .atomic)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.id.uuidString + ".jsonl"))
    }
    static func load(_ id: UUID, directory: URL) throws -> HistoryRecord {
        var record = try JSONDecoder().decode(HistoryRecord.self, from: Data(contentsOf: directory.appendingPathComponent(id.uuidString + ".json")))
        let journal = directory.appendingPathComponent(id.uuidString + ".jsonl")
        if FileManager.default.fileExists(atPath: journal.path) {
            let data = try Data(contentsOf: journal)
            // Po przerwanym zapisie ostatnia niepełna linia nie jest potwierdzoną operacją.
            let lines = data.split(separator: 10)
            var known = Set(record.items.map { $0.original.path + "\n" + $0.current.path })
            for line in lines {
                guard let item = try? JSONDecoder().decode(UndoItem.self, from: Data(line)) else { continue }
                let key = item.original.path + "\n" + item.current.path
                if known.insert(key).inserted { record.items.append(item) }
            }
        }
        record.itemCount = nil; return record
    }
    static func remove(_ id: UUID, directory: URL) throws {
        let fm = FileManager.default
        try fm.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json"))
        for suffix in [".jsonl", ".meta.json"] { try? fm.removeItem(at: directory.appendingPathComponent(id.uuidString + suffix)) }
    }
}
