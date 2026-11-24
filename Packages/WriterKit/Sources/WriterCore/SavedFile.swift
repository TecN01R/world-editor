import Foundation

/// A saved file this version of the app can't read: written by a newer version, or
/// damaged. It's left exactly as it is, never saved over or deleted, so nothing in it
/// is lost: a version that reads it finds everything still there.
public struct UnreadableFile: Error, Hashable, Sendable {
    public let url: URL
}

/// One value saved as a JSON file, by `UnreadableFile`'s rule.
struct SavedFile<Value: Codable> {
    let url: URL
    var encoder = JSONEncoder()
    var decoder = JSONDecoder()

    /// The saved value; nil when nothing is saved there yet.
    func read() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try decoder.decode(Value.self, from: Data(contentsOf: url)) }
        catch { throw UnreadableFile(url: url) }
    }

    /// Saves over what's there, unless what's there can't be read.
    func write(_ value: Value) throws {
        _ = try read()
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    /// Deletes it, unless it can't be read.
    func delete() throws {
        guard try read() != nil else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Each value saved in `directory`, and the files there that can't be read.
    static func all(in directory: URL, decoder: JSONDecoder = JSONDecoder()) -> (values: [Value], unreadable: [URL]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var values: [Value] = [], unreadable: [URL] = []
        for file in files where file.pathExtension == "json" {
            if let value = try? decoder.decode(Value.self, from: Data(contentsOf: file)) { values.append(value) }
            else { unreadable.append(file) }
        }
        return (values, unreadable)
    }
}
