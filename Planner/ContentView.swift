//
//  ContentView.swift
//  Planner
//
//  Created by Naiyar Gull on 30.04.26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var rawText = ""
    @State private var monthDate = Calendar.current.startOfMonth(for: Date())
    @State private var targetName = ""
    @State private var parseResult = ShiftParseResult(entries: [], warnings: [])
    @State private var hourlyWage: Double = 12.0
    @State private var steuerklasse: Steuerklasse = .I
    @State private var exportStatus: ExportStatus?
    @State private var lastAction: LastAction = .none
    @State private var lastResultText: String = ""

    private let sampleText = """
01. Fr
17/22 Sajid Liefern
17/23 Naijar Kuche

02. Sa
15/21 Naijar
17/23 Johanna
17/23 Sajid

03. So
15/21 Hamidullah Kuche
17/22 Koni Service
17/21 Sajid Liefern
17/22 Sany Kuche
"""

    private var people: [String] {
        Array(Set(parseResult.entries.map { $0.person })).sorted()
    }

    private var normalizedTarget: String {
        targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [ShiftEntry] {
        let target = normalizedTarget
        guard !target.isEmpty else {
            return []
        }

        return parseResult.entries
            .filter { $0.person.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            .sorted { $0.start < $1.start }
    }

    private var payrollSummary: PayrollSummary? {
        guard !filteredEntries.isEmpty, hourlyWage > 0 else {
            return nil
        }

        return PayrollCalculator.summary(
            for: filteredEntries,
            profile: PayrollProfile(hourlyWage: hourlyWage, steuerklasse: steuerklasse)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top input area: paste schedule and process button
            inputView

            // Action buttons shown after processing (or anytime) — only result of last clicked button is shown
            HStack(spacing: 12) {
                Button("Export to Calendar") {
                    lastAction = .exportCalendar
                    saveCalendarFile()
                    // saveCalendarFile updates exportStatus synchronously; reflect it in lastResultText
                    if let s = exportStatus {
                        lastResultText = s.message
                    }
                }
                .buttonStyle(.bordered)
                .disabled(filteredEntries.isEmpty)

                Button("Calculate Netto") {
                    lastAction = .calculateNetto
                    if let summary = payrollSummary {
                        let hoursStr = String(format: "%.1f", summary.totalHours)
                        let grossStr = Self.currencyFormatter.string(from: NSNumber(value: summary.grossSalary)) ?? String(format: "%.2f", summary.grossSalary)
                        let netStr = Self.currencyFormatter.string(from: NSNumber(value: summary.netSalary)) ?? String(format: "%.2f", summary.netSalary)
                        lastResultText = "Total hours: \(hoursStr)\nGross: \(grossStr)\nNet: \(netStr)\nContract: \(summary.contractType.title)"
                    } else {
                        lastResultText = "No payroll data — ensure a target name and hourly wage are set."
                    }
                }
                .buttonStyle(.bordered)
                .disabled(filteredEntries.isEmpty)

                Button("Calculate Work Hours") {
                    lastAction = .calculateHours
                    let total = filteredEntries.totalHours
                    let hoursStr = String(format: "%.1f", total)
                    lastResultText = "Total hours for \(normalizedTarget): \(hoursStr)"
                }
                .buttonStyle(.bordered)
                .disabled(filteredEntries.isEmpty)

                Spacer()
            }
            .padding(.top, 6)

            // Result area: only show result for the last action
            if lastAction != .none {
                GroupBox {
                    Text(lastResultText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            refreshParse()
        }
        .onChange(of: rawText) { _, _ in
            refreshParse()
        }
        .onChange(of: monthDate) { _, _ in
            refreshParse()
        }
    }

    private var inputView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shift Planner")
                        .font(.title2.weight(.semibold))
                    Text("Paste raw shifts, filter by person, then export or estimate payroll.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 220)
                        .font(.system(.body, design: .monospaced))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                    if rawText.isEmpty {
                        Text("Paste your raw shift plan here")
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 8)
                    }
                }

                HStack(spacing: 12) {
                    Button("Load Sample") {
                        rawText = sampleText
                    }
                    .buttonStyle(.bordered)
                    Button("Clear") {
                        rawText = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Process") {
                        // Run parsing and prepare results
                        refreshParse()
                        lastAction = .none
                        lastResultText = ""
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Text("\(parseResult.entries.count) shifts")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            } header: {
                Label("Plan Input", systemImage: "doc.text")
            }

            Section {
                DatePicker("Month", selection: $monthDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)

                TextField("Target Employee Name", text: $targetName)
                    .textFieldStyle(.roundedBorder)

                if !people.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(people, id: \.self) { person in
                                Button(person) {
                                    targetName = person
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            } header: {
                Label("Filter", systemImage: "person.crop.circle")
            } footer: {
                Text("Detected names appear as quick-select buttons.")
            }

            if !parseResult.warnings.isEmpty {
                Section {
                    ForEach(parseResult.warnings, id: \.self) { warning in
                        Text(warning)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Notes", systemImage: "info.circle")
                }
            }
            
            // Payroll quick controls (hourly + tax class)
            Section {
                TextField("Hourly Wage (EUR)", value: $hourlyWage, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)

                Picker("Steuerklasse", selection: $steuerklasse) {
                    ForEach(Steuerklasse.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Label("Payroll Settings", systemImage: "eurosign.circle")
            }
        }
        .navigationTitle("Input")
    }

    private var calendarView: some View {
        // Calendar view is now integrated into main screen flow. Keep for compatibility if needed.
        VStack {
            Text("Calendar export is available via the main input screen after processing.")
                .foregroundStyle(.secondary)
                .padding()
            Spacer()
        }
    }

    private var payrollView: some View {
        // Payroll view kept minimal because payroll is now initiated from the main input screen.
        VStack {
            Text("Use 'Calculate Netto' on the main screen after processing and selecting a person.")
                .foregroundStyle(.secondary)
                .padding()
            Spacer()
        }
    }

    private func refreshParse() {
        let parser = ShiftParser()
        parseResult = parser.parse(text: rawText, monthDate: monthDate)
    }

    private func saveCalendarFile() {
        guard !filteredEntries.isEmpty else {
            exportStatus = ExportStatus(message: "No shifts available for export.", isError: true)
            return
        }
        // Write the ICS to a temporary file and reveal it in Finder (if available).
        if let url = ICSExporter.makeExportURL(for: filteredEntries, person: normalizedTarget) {
            if NSApp != nil {
                // Reveal the temporary file in Finder so the user can move/save it.
                NSWorkspace.shared.activateFileViewerSelecting([url])
                exportStatus = ExportStatus(message: "Saved to temporary file and revealed in Finder: \(url.path)", isError: false)
            } else {
                exportStatus = ExportStatus(message: "Saved to temporary file: \(url.path)", isError: false)
            }
            lastAction = .exportCalendar
            lastResultText = exportStatus!.message
        } else {
            exportStatus = ExportStatus(message: "Failed to create temporary export.", isError: true)
            lastAction = .exportCalendar
            lastResultText = exportStatus!.message
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()
}

private struct ResultsCard: View {
    let summary: PayrollSummary

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Total Hours")
                        .foregroundStyle(.secondary)
                    Text(summary.totalHours, format: .number.precision(.fractionLength(1)))
                }
                GridRow {
                    Text("Contract Type")
                        .foregroundStyle(.secondary)
                    Text(summary.contractType.title)
                }
                GridRow {
                    Text("Estimated Netto")
                        .foregroundStyle(.secondary)
                    Text(summary.netSalary, format: .currency(code: "EUR"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExportStatus: Equatable {
    let message: String
    let isError: Bool
}

private enum LastAction {
    case none
    case exportCalendar
    case calculateNetto
    case calculateHours
}

private enum SidebarItem: String, CaseIterable, Identifiable {
    case input
    case calendar
    case payroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input:
            return "Input"
        case .calendar:
            return "Calendar View"
        case .payroll:
            return "Payroll Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .input:
            return "doc.text"
        case .calendar:
            return "calendar"
        case .payroll:
            return "chart.bar"
        }
    }
}

#Preview {
    ContentView()
}
