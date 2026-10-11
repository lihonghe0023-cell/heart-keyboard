import Foundation

/// One dictionary row.
struct T9Entry {
    let word: String
    let weight: Int
    let digits: String
}

/// Reads the generated 九宫格 resources straight out of the bundle.
///
/// Every file is sorted by its first column, so a lookup is a binary search over
/// the raw bytes plus a couple of parsed lines. Only the file itself stays in
/// memory — no dictionary is built at launch, which is what keeps this
/// affordable inside a keyboard extension.
final class T9Dictionary {

    static let shared = T9Dictionary()

    private struct Table {
        let data: Data
        /// Byte offset of each data line.
        let offsets: [Int32]
        var count: Int { offsets.count }
    }

    private lazy var fullTable: Table? = load("t9", "dict")
    private lazy var initialsTable: Table? = load("t9", "initials")
    private lazy var chainTable: Table? = load("t9", "chain")
    private lazy var syllableTable: Table? = load("t9", "syllable")

    private init() {}

    /// True when the resources made it into this target's bundle.
    var isReady: Bool { fullTable != nil }

    // MARK: - Lookups

    /// 全拼: the digits match the word's full pinyin.
    func exact(_ digits: String, limit: Int) -> [T9Entry] {
        guard let table = fullTable else { return [] }
        return rows(in: table, key: digits, limit: limit).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4, let weight = Int(fields[3]) else { return nil }
            return T9Entry(word: String(fields[2]), weight: weight, digits: String(fields[0]))
        }
    }

    /// 简拼: the digits match only the first letters, e.g. 25 -> 北京.
    func shorthand(_ digits: String, limit: Int) -> [T9Entry] {
        guard let table = initialsTable else { return [] }
        return rows(in: table, key: digits, limit: limit).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4, let weight = Int(fields[3]) else { return nil }
            return T9Entry(word: String(fields[2]), weight: weight, digits: String(fields[1]))
        }
    }

    /// 首音节联想: 54 offers 技术/里面/继续, because that is what typing "li"
    /// usually means once you keep going.
    func wordsStarting(withSyllable digits: String, limit: Int) -> [String] {
        words(in: syllableTable, key: digits, limit: limit)
    }

    /// 尾字联想: after sending 你好, offer words that start with 好.
    func chain(after character: String, limit: Int) -> [String] {
        words(in: chainTable, key: character, limit: limit)
    }

    // MARK: - Table plumbing

    private func words(in table: Table?, key: String, limit: Int) -> [String] {
        guard let table, let line = rows(in: table, key: key, limit: 1).first else { return [] }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return [] }
        return fields[1].split(separator: "|").prefix(limit).map(String.init)
    }

    private func rows(in table: Table, key: String, limit: Int) -> [String] {
        var row = lowerBound(key, in: table)
        var out: [String] = []
        while row < table.count, out.count < limit {
            guard key(at: row, in: table) == key else { break }
            if let line = line(at: row, in: table) { out.append(line) }
            row += 1
        }
        return out
    }

    private func lowerBound(_ key: String, in table: Table) -> Int {
        var low = 0
        var high = table.count
        while low < high {
            let mid = (low + high) / 2
            if self.key(at: mid, in: table) < key { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func line(at row: Int, in table: Table) -> String? {
        guard row >= 0, row < table.count else { return nil }
        let start = Int(table.offsets[row])
        var end = row + 1 < table.count ? Int(table.offsets[row + 1]) : table.data.count
        while end > start, table.data[end - 1] == UInt8(ascii: "\n") { end -= 1 }
        guard end > start else { return nil }
        return String(decoding: table.data[start..<end], as: UTF8.self)
    }

    private func key(at row: Int, in table: Table) -> String {
        guard let line = line(at: row, in: table) else { return "" }
        return String(line.prefix { $0 != "\t" })
    }

    private func load(_ name: String, _ ext: String) -> Table? {
        guard
            let url = resourceURL(name, ext),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        var offsets: [Int32] = []
        offsets.reserveCapacity(data.count / 24)
        var index = data.startIndex
        while index < data.endIndex {
            // Comment lines are skipped so binary search never sees them.
            if data[index] != UInt8(ascii: "#") {
                offsets.append(Int32(index - data.startIndex))
            }
            while index < data.endIndex, data[index] != UInt8(ascii: "\n") { index += 1 }
            if index < data.endIndex { index += 1 }
        }
        return Table(data: data, offsets: offsets)
    }

    /// Works whether the resources sit at the bundle root (group) or inside a
    /// blue "Resources" folder reference.
    private func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
}
