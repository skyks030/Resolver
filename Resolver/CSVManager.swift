import Foundation

struct CSVManager {
    
    // Default headers for Master VFX List
    static let headers = ["ID", "VFX Name", "Original VFX Name", "TC In", "TC Out", "Source TC In", "Source TC Out", "Reel Name", "File Names", "Frame Start", "Frame End", "Duration", "Resolve Unique ID"]
    
    static func escape(_ string: String) -> String {
        var escaped = string
        if escaped.contains("\"") {
            escaped = escaped.replacingOccurrences(of: "\"", with: "\"\"")
        }
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
    
    static func write(clips: [ClipData], to url: URL) throws {
        var allKeys = Set<String>()
        for clip in clips {
            allKeys.formUnion(clip.dict.keys)
        }
        
        let sortedKeys = allKeys.sorted()
        let allHeaders = ["ID"] + sortedKeys
        
        var csvString = allHeaders.joined(separator: ",") + "\n"
        
        for clip in clips {
            var row = [clip.id.uuidString]
            
            for key in sortedKeys {
                row.append(clip.dict[key] ?? "")
            }
            
            let escapedRow = row.map { escape($0) }.joined(separator: ",")
            csvString += escapedRow + "\n"
        }
        
        try csvString.write(to: url, atomically: true, encoding: .utf8)
    }
    static func detectDelimiter(in firstLine: String) -> Character {
        var commas = 0
        var semicolons = 0
        var inQuotes = false
        for ch in firstLine {
            if ch == "\"" { inQuotes.toggle() }
            else if !inQuotes {
                if ch == "," { commas += 1 }
                else if ch == ";" { semicolons += 1 }
            }
        }
        return semicolons > commas ? ";" : ","
    }
    
    static func parseCSVRow(_ rowString: String, delimiter: Character = ",") -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        
        let chars = Array(rowString)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i+1] == "\"" {
                    current.append("\"")
                    i += 1 // Skip escaped quote
                } else {
                    inQuotes.toggle()
                }
            } else if ch == delimiter && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        result.append(current) // End of row
        return result
    }
    
    /// Basic parsing. Note: This assumes no newlines inside actual CSV values since we split by .newlines beforehand.
    static func read(from url: URL) throws -> [ClipData] {
        let content = try String(contentsOf: url, encoding: .utf8)
        
        // Handle standard newlines
        let rawRows = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard rawRows.count > 1 else { return [] }
        let delimiter = detectDelimiter(in: rawRows[0])
        let headerRow = parseCSVRow(rawRows[0], delimiter: delimiter)
        guard headerRow.count > 0 else { return [] }
        
        // Build an index map based on file headers
        var map: [String: Int] = [:]
        for (index, h) in headerRow.enumerated() {
            let cleanH = h.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanH.isEmpty {
                map[cleanH] = index
            }
        }
        
        var clips: [ClipData] = []
        
        for rowRaw in rawRows.dropFirst() {
            let cols = parseCSVRow(rowRaw, delimiter: delimiter)
            
            // Helper to get safely
            func val(_ name: String) -> String {
                guard let i = map[name], i < cols.count else { return "" }
                return cols[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            let idStr = val("ID")
            let id = UUID(uuidString: idStr) ?? UUID()
            
            var dict: [String: String] = [:]
            for key in map.keys {
                if key == "ID" { continue }
                let rawVal = val(key)
                if !rawVal.isEmpty {
                    dict[key] = rawVal
                }
            }
            
            let clip = ClipData(id: id, dict: dict)
            clips.append(clip)
        }
        
        return clips
    }
}
