import Foundation

struct ShiftParser {
    private static let dayRegex = try? NSRegularExpression(pattern: "^\\s*(\\d{1,2})\\.")
    private static let timeRegex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})\\s*/\\s*(\\d{1,2})\\b")

    func parse(text: String, monthDate: Date, calendar: Calendar = .current) -> ShiftParseResult {
        let lines = text.components(separatedBy: .newlines)
        var currentDay: Int?
        var entries: [ShiftEntry] = []
        var warnings: [String] = []

        let year = calendar.component(.year, from: monthDate)
        let month = calendar.component(.month, from: monthDate)

        for rawLine in lines {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                continue
            }

            var lineToParse = trimmedLine
            if let match = Self.dayRegex?.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
               let dayRange = Range(match.range(at: 1), in: trimmedLine) {
                currentDay = Int(trimmedLine[dayRange])
                if let headerRange = Range(match.range(at: 0), in: trimmedLine) {
                    lineToParse = String(trimmedLine[headerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }

            let timeMatches = Self.timeRegex?.matches(in: lineToParse, range: NSRange(lineToParse.startIndex..., in: lineToParse)) ?? []
            if timeMatches.isEmpty {
                continue
            }

            guard let day = currentDay else {
                warnings.append("Missing day for line: \(trimmedLine)")
                continue
            }

            var parsedLine = false
            for (index, match) in timeMatches.enumerated() {
                guard let timeRange = Range(match.range(at: 0), in: lineToParse),
                      let startRange = Range(match.range(at: 1), in: lineToParse),
                      let endRange = Range(match.range(at: 2), in: lineToParse),
                      let startHour = Int(lineToParse[startRange]),
                      let endHour = Int(lineToParse[endRange]) else {
                    continue
                }

                let detailsStart = timeRange.upperBound
                let detailsEnd: String.Index
                if index + 1 < timeMatches.count,
                   let nextRange = Range(timeMatches[index + 1].range(at: 0), in: lineToParse) {
                    detailsEnd = nextRange.lowerBound
                } else {
                    detailsEnd = lineToParse.endIndex
                }
                let details = String(lineToParse[detailsStart..<detailsEnd]).trimmingCharacters(in: .whitespaces)

                let parts = details.split(whereSeparator: { $0.isWhitespace })
                guard let person = parts.first.map(String.init) else {
                    continue
                }

                let role = parts.dropFirst().joined(separator: " ")
                guard let startDate = makeDate(year: year, month: month, day: day, hour: startHour, calendar: calendar) else {
                    continue
                }

                var endDate = makeDate(year: year, month: month, day: day, hour: endHour, calendar: calendar) ?? startDate
                if endDate < startDate {
                    endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                }

                entries.append(ShiftEntry(start: startDate, end: endDate, person: person, role: role.isEmpty ? nil : role))
                parsedLine = true
            }

            if !parsedLine {
                warnings.append("Could not parse line: \(trimmedLine)")
            }
        }

        entries.sort { $0.start < $1.start }
        return ShiftParseResult(entries: entries, warnings: warnings)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components)
    }
}
