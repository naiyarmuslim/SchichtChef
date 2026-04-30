//
//  PlannerTests.swift
//  PlannerTests
//
//  Created by Naiyar Gull on 30.04.26.
//

import XCTest
@testable import Planner

final class PlannerTests: XCTestCase {
    func testShiftParserFindsTargetEmployeeShifts() throws {
        let sampleText = """
01. Fr
17/22 Sajid Liefern
17/23 Naijar Kuche

02. Sa
15/21 Naijar
17/23 Johanna
17/23 Sajid
"""

        let calendar = Calendar(identifier: .gregorian)
        let monthDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))
        XCTAssertNotNil(monthDate)

        let parser = ShiftParser()
        let result = parser.parse(text: sampleText, monthDate: monthDate!, calendar: calendar)
        let naijarShifts = result.entries.filter { $0.person == "Naijar" }

        XCTAssertEqual(naijarShifts.count, 2)
        XCTAssertEqual(result.warnings.count, 0)
    }

    func testPayrollCalculatorMinijobNetEqualsGross() throws {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 8))
        XCTAssertNotNil(baseDate)

        var entries: [ShiftEntry] = []
        for offset in 0..<4 {
            let start = calendar.date(byAdding: .day, value: offset, to: baseDate!)!
            let end = calendar.date(byAdding: .hour, value: 8, to: start)!
            entries.append(ShiftEntry(start: start, end: end, person: "Naijar", role: "Service"))
        }

        let profile = PayrollProfile(hourlyWage: 12.0, taxCategory: .single)
        let summary = PayrollCalculator.summary(for: entries, profile: profile)

        XCTAssertEqual(summary.contractType, .minijob)
        XCTAssertEqual(summary.netSalary, summary.grossSalary, accuracy: 0.01)
    }

    func testICSExportBuildsCalendar() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
        let end = calendar.date(byAdding: .hour, value: 4, to: start)!
        let entry = ShiftEntry(start: start, end: end, person: "Naijar", role: "Kuche")

        let ics = ICSExporter.makeICS(entries: [entry], calendarName: "Naijar Shifts")

        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("BEGIN:VEVENT"))
        XCTAssertTrue(ics.contains("SUMMARY:Shift"))
    }
}
