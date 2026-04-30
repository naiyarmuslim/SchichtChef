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
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var targetName = ""
    @State private var parseResult = ShiftParseResult(entries: [], warnings: [])
    @State private var hourlyWage: Double = 14.0
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

    private var personHours: [String: Double] {
        var dict: [String: Double] = [:]
        for e in parseResult.entries {
            dict[e.person, default: 0] += e.durationHours
        }
        return dict
    }

    private var normalizedTarget: String {
        targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [ShiftEntry] {
        let target = normalizedTarget
        guard !target.isEmpty else { return [] }
        return parseResult.entries
            .filter { $0.person.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            .sorted { $0.start < $1.start }
    }

    private var payrollSummary: PayrollSummary? {
        guard !filteredEntries.isEmpty, hourlyWage > 0 else { return nil }
        return PayrollCalculator.summary(
            for: filteredEntries,
            profile: PayrollProfile(hourlyWage: hourlyWage, steuerklasse: steuerklasse)
        )
    }

    // View body
    var body: some View {
        ZStack {
            // Dark dashboard-like gradient
            LinearGradient(
                colors: [Self.bgStart, Self.bgEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                Spacer(minLength: 24)

                                // Centered column containing header and card
                                VStack(alignment: .center, spacing: 18) {
                                    headerView

                                    contentCard
                                        .id("contentCard")
                                        .frame(maxWidth: 900)
                                }
                                .padding(18)

                                Spacer()
                            }
                            .onChange(of: lastAction) { new in
                                // when a result is produced, scroll to the content card so results are visible
                                if new != .none {
                                    DispatchQueue.main.async {
                                        withAnimation(.spring()) {
                                            proxy.scrollTo("contentCard", anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
        }
        .onAppear { refreshParse() }
        .onChange(of: rawText) { _ in refreshParse() }
        .onChange(of: monthDate) { _ in refreshParse() }
        .onChange(of: selectedMonth) { newMonth in
            // update monthDate to first day of selected month/year
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: monthDate)
            comps.month = selectedMonth
            comps.year = selectedYear
            comps.day = 1
            if let d = Calendar.current.date(from: comps) {
                monthDate = Calendar.current.startOfMonth(for: d)
                refreshParse()
            }
        }
        .onChange(of: selectedYear) { newYear in
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: monthDate)
            comps.month = selectedMonth
            comps.year = selectedYear
            comps.day = 1
            if let d = Calendar.current.date(from: comps) {
                monthDate = Calendar.current.startOfMonth(for: d)
                refreshParse()
            }
        }
    }

    // Header (centered)
    private var headerView: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("SchichtChef")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Quickly paste shifts, export calendar or estimate payroll")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // Main card
    private var contentCard: some View {
        VStack(spacing: 16) {
            inputView

            if lastAction != .none {
                GroupBox {
                    Text(lastResultText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .groupBoxStyle(DefaultGroupBoxStyle())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: lastAction)
            }
        }
        .padding(12)
        .frame(maxWidth: 820)
                .background(Self.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
    }

    // Input view
    private var inputView: some View {
        VStack(spacing: 16) {
            // Section title centered
            VStack(spacing: 4) {
                Text("Shift Planner")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Paste raw shifts, filter by person, then export or estimate payroll.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            // Inner card for the text editor to make it centered (square)
            VStack(spacing: 12) {
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 360, height: 360)

                    TextEditor(text: $rawText)
                        .padding(12)
                        .frame(width: 320, height: 320)
                        .font(.system(.body, design: .monospaced))
                        .background(Color.clear)
                        .cornerRadius(8)
                        .foregroundColor(.white)

                    if rawText.isEmpty {
                        Text("Paste your raw shift plan here")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 300)
                    }
                }

                // centered small info label
                Text("\(parseResult.entries.count) shifts")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                // Primary actions placed immediately below the paste square so they're easier to reach
                    HStack(spacing: 16) {
                    Spacer()
                    Button(action: { withAnimation(.spring()) { lastAction = .exportCalendar }; saveCalendarFile(); if let s = exportStatus { lastResultText = s.message } }) {
                        Label("📤 Export", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.accentGreen)
                    .disabled(filteredEntries.isEmpty)

                    Button(action: {
                        lastAction = .calculateNetto
                        if let summary = payrollSummary {
                            let hoursStr = String(format: "%.1f", summary.totalHours)
                            let grossStr = Self.currencyFormatter.string(from: NSNumber(value: summary.grossSalary)) ?? String(format: "%.2f", summary.grossSalary)
                            let netStr = Self.currencyFormatter.string(from: NSNumber(value: summary.netSalary)) ?? String(format: "%.2f", summary.netSalary)

                            // compute tax and social for display (same logic as PayrollCalculator)
                            let contract = summary.contractType
                            var tax: Double = 0
                            var social: Double = 0
                            if contract != .minijob {
                                let taxRate = summary.taxCategory.estimatedTaxRate(forGrossMonthly: summary.grossSalary)
                                tax = summary.grossSalary * taxRate
                                social = summary.grossSalary * contract.socialRate
                            }

                            let taxStr = Self.currencyFormatter.string(from: NSNumber(value: tax)) ?? String(format: "%.2f", tax)
                            let socialStr = Self.currencyFormatter.string(from: NSNumber(value: social)) ?? String(format: "%.2f", social)

                            lastResultText = "Total hours: \(hoursStr)\nContract: \(summary.contractType.title)\nGross: \(grossStr)\nTax (est): \(taxStr)\nSocial (est): \(socialStr)\nNet: \(netStr)"
                        } else {
                            lastResultText = "No payroll data — ensure a target name and hourly wage are set."
                        }
                    }) {
                        Label("💶 Calculate Netto", systemImage: "eurosign.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.accentBlue)
                    .disabled(filteredEntries.isEmpty)

                    Spacer()
                }
            }
            .frame(maxWidth: 760)

            // Filter and month selectors centered
            VStack(spacing: 10) {
                Text("Filter")
                    .font(.headline)
                    .foregroundColor(.white)

                // Month & Year pickers centered
                HStack(spacing: 12) {
                        Picker("", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { i in
                            Text(DateFormatter().monthSymbols[i-1]).tag(i)
                        }
                    }
                    .pickerStyle(.menu)

                        Picker("", selection: $selectedYear) {
                        let currentYear = Calendar.current.component(.year, from: Date())
                        ForEach((currentYear-5)...(currentYear+5), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .foregroundColor(.white)
            }

            // I am: centered and people buttons
            VStack(spacing: 8) {
                Text("I am:")
                    .font(.headline)
                    .foregroundColor(.white)

                if people.isEmpty {
                    Text("No detected names")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(people, id: \.self) { person in
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    targetName = person
                                    lastResultText = ""
                                    lastAction = .none
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Text(person)
                                        .font(.body)
                                        .fontWeight(person == normalizedTarget ? .semibold : .regular)
                                    if let hrs = personHours[person] {
                                        Text("\(hrs, format: .number.precision(.fractionLength(1)))h")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(person == normalizedTarget ? Self.accentBlue : Color.clear)
                                .clipShape(Capsule())
                                .foregroundColor(person == normalizedTarget ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Payroll settings centered
            VStack(spacing: 8) {
                Text("Hourly Wage (EUR)")
                    .foregroundStyle(.secondary)
                TextField("Hourly Wage", value: $hourlyWage, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                Text("Steuerklasse")
                    .foregroundStyle(.secondary)
                // Picker shown without side label (label handled above)
                Picker("", selection: $steuerklasse) {
                    ForEach(Steuerklasse.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Calendar and payroll views kept for compatibility
    private var calendarView: some View {
        VStack {
            Text("Calendar export is available via the main input screen after processing.")
                .foregroundStyle(.secondary)
                .padding()
            Spacer()
        }
    }

    private var payrollView: some View {
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
            lastAction = .exportCalendar
            lastResultText = exportStatus!.message
            return
        }

        if let url = ICSExporter.makeExportURL(for: filteredEntries, person: normalizedTarget) {
            if NSApp != nil {
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

    // Removed custom icon helpers to keep the app simple
}

// Static formatters used elsewhere
private extension ContentView {
    static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    static var currencyFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "de_DE")
        return f
    }

    // Theme colors inspired by the provided dashboard screenshot
    static var bgStart: Color { Color(red: 0.03, green: 0.06, blue: 0.10) }
    static var bgEnd: Color { Color(red: 0.06, green: 0.18, blue: 0.22) }
    static var cardBackground: Color { Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.95) }

    static var accentGreen: Color { Color(red: 0.08, green: 0.78, blue: 0.44) }
    static var accentBlue: Color { Color(red: 0.02, green: 0.68, blue: 0.83) }
    static var accentYellow: Color { Color(red: 0.98, green: 0.73, blue: 0.14) }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

private struct ResultsCard: View {
    let summary: PayrollSummary
    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow { Text("Total Hours").foregroundStyle(.secondary); Text(summary.totalHours, format: .number.precision(.fractionLength(1))) }
                GridRow { Text("Contract Type").foregroundStyle(.secondary); Text(summary.contractType.title) }
                GridRow { Text("Estimated Netto").foregroundStyle(.secondary); Text(summary.netSalary, format: .currency(code: "EUR")) }
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
    case none, exportCalendar, calculateNetto, calculateHours
}

private enum SidebarItem: String, CaseIterable, Identifiable {
    case input, calendar, payroll
    var id: String { rawValue }
    var title: String { switch self { case .input: return "Input" case .calendar: return "Calendar View" case .payroll: return "Payroll Summary" } }
    var systemImage: String { switch self { case .input: return "doc.text" case .calendar: return "calendar" case .payroll: return "chart.bar" } }
}
