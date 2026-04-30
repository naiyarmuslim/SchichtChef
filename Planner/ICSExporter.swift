import Foundation

enum ICSExporter {
    static func makeExportURL(for entries: [ShiftEntry], person: String) -> URL? {
        guard !entries.isEmpty else {
            return nil
        }

        let fileName = defaultFileName(for: person)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            let ics = makeICS(entries: entries, calendarName: "\(person) Shifts")
            try ics.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    static func defaultFileName(for person: String) -> String {
        sanitizedFileName("ShiftPlan_\(person.isEmpty ? "Shifts" : person)") + ".ics"
    }

    static func writeICS(entries: [ShiftEntry], calendarName: String, to url: URL) throws {
        let ics = makeICS(entries: entries, calendarName: calendarName)
        try ics.write(to: url, atomically: true, encoding: .utf8)
    }

    static func makeICS(entries: [ShiftEntry], calendarName: String) -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCALENDAR")
        lines.append("VERSION:2.0")
        lines.append("PRODID:-//Plannr//Shift Export//EN")
        lines.append("CALSCALE:GREGORIAN")
        lines.append("METHOD:PUBLISH")
        lines.append("X-WR-CALNAME:\(escapeICS(calendarName))")
        lines.append("X-WR-TIMEZONE:UTC")

        let dtstamp = timestampFormatter.string(from: Date())
        for entry in entries {
            let start = eventUTCFormatter.string(from: entry.start)
            let end = eventUTCFormatter.string(from: entry.end)
            let summary = entry.role.map { "Shift - \($0)" } ?? "Shift"

            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(UUID().uuidString)")
            lines.append("DTSTAMP:\(dtstamp)")
            lines.append("DTSTART:\(start)")
            lines.append("DTEND:\(end)")
            lines.append("SUMMARY:\(escapeICS(summary))")
            if let role = entry.role, !role.isEmpty {
                lines.append("DESCRIPTION:\(escapeICS(role))")
            }
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("") { $0 + String($1) }
    }

    private static func escapeICS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static let eventUTCFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
