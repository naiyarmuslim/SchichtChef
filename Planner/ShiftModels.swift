import Foundation

struct ShiftEntry: Identifiable, Hashable {
    let id = UUID()
    let start: Date
    let end: Date
    let person: String
    let role: String?
}

struct ShiftParseResult {
    let entries: [ShiftEntry]
    let warnings: [String]
}

// Replace the simplistic categories with German income tax classes (Steuerklassen)
enum Steuerklasse: String, CaseIterable, Identifiable {
    case I
    case II
    case III
    case IV
    case V
    case VI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .I: return "Steuerklasse I (single)"
        case .II: return "Steuerklasse II (single, single parent)"
        case .III: return "Steuerklasse III (married, spouse no income)"
        case .IV: return "Steuerklasse IV (married, both earn)"
        case .V: return "Steuerklasse V (married, partner in III)"
        case .VI: return "Steuerklasse VI (multiple jobs)"
        }
    }

    // Estimated effective income tax rate based on gross monthly pay and tax class.
    // This is a simplified estimator for planning purposes only. For authoritative
    // results use official Lohnsteuertabellen from the Bundesministerium der Finanzen
    // or implement the §32a EStG progressive formula.
    func estimatedTaxRate(forGrossMonthly gross: Double) -> Double {
        // Baseline progressive-like bands (monthly gross)
        let baseRate: Double
        switch gross {
        case ..<1000:
            baseRate = 0.00
        case 1000..<2000:
            baseRate = 0.10
        case 2000..<3000:
            baseRate = 0.15
        case 3000..<4000:
            baseRate = 0.20
        case 4000..<6000:
            baseRate = 0.25
        default:
            baseRate = 0.30
        }

        // Adjust per tax class (approximate modifiers)
        let modifier: Double
        switch self {
        case .I: modifier = 0.0
        case .II: modifier = -0.02 // slightly lower due to single parent relief
        case .III: modifier = -0.10 // often much lower withholding for class III
        case .IV: modifier = 0.0
        case .V: modifier = 0.12 // higher withholding in class V
        case .VI: modifier = 0.15 // highest withholding for secondary jobs
        }

        let rate = max(0, min(0.80, baseRate + modifier))
        return rate
    }
}

enum ContractType: String, Identifiable {
    case minijob
    case werkstudent
    case partTime
    case fullTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minijob:
            return "Minijob"
        case .werkstudent:
            return "Werkstudent"
        case .partTime:
            return "Part-time"
        case .fullTime:
            return "Full-time"
        }
    }

    var socialRate: Double {
        switch self {
        case .minijob:
            return 0.0
        case .werkstudent:
            return 0.095
        case .partTime, .fullTime:
            return 0.20
        }
    }

    static func from(totalHours: Double) -> ContractType {
        switch totalHours {
        case ..<40:
            return .minijob
        case 40..<80:
            return .werkstudent
        case 80..<120:
            return .partTime
        default:
            return .fullTime
        }
    }
}

struct PayrollProfile {
    var hourlyWage: Double
    var steuerklasse: Steuerklasse
}

struct PayrollSummary {
    let totalHours: Double
    let contractType: ContractType
    let grossSalary: Double
    let netSalary: Double
    let taxCategory: Steuerklasse
}

struct PayrollCalculator {
    static func summary(for entries: [ShiftEntry], profile: PayrollProfile) -> PayrollSummary {
        let totalHours = entries.totalHours
        let contractType = ContractType.from(totalHours: totalHours)
        let gross = max(0, totalHours * profile.hourlyWage)

        let net: Double
        if contractType == .minijob {
            // Minijobs are usually tax-free for the employee (employer handles contributions)
            net = gross
        } else {
            // Estimate tax using the Steuerklasse estimator (uses gross monthly approx)
            // The estimator expects a monthly gross; if the provided gross is not monthly
            // this remains a planning estimate. We treat 'gross' as the period gross.
            let taxRate = profile.steuerklasse.estimatedTaxRate(forGrossMonthly: gross)
            let tax = gross * taxRate

            // Social contributions: use the contractType socialRate as an estimate for employee share
            let social = gross * contractType.socialRate

            net = max(0, gross - tax - social)
        }

        return PayrollSummary(
            totalHours: totalHours,
            contractType: contractType,
            grossSalary: gross,
            netSalary: net,
            taxCategory: profile.steuerklasse
        )
    }
}

extension ShiftEntry {
    var durationHours: Double {
        max(0, end.timeIntervalSince(start) / 3600)
    }
}

extension Array where Element == ShiftEntry {
    var totalHours: Double {
        reduce(0) { $0 + $1.durationHours }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
