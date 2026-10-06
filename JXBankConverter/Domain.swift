import Foundation

struct JX8PTone: Identifiable, Equatable {
    let id: Int
    let name: String
    let parameters: [UInt8]   // 49 bytes
    let channel: UInt8
}

struct JX8PBank {
    let tones: [JX8PTone]
    let sourceMessages: [[UInt8]]
}

enum PatchStrategy: String, CaseIterable, Identifiable {
    case mirror = "One JX-8P tone per JX-10 patch"
    case pair = "Pair adjacent JX-8P tones"
    var id: String { rawValue }
}

enum Target: String, CaseIterable, Identifiable {
    case jx10 = "JX-10"
    case mks70 = "MKS-70"
    var id: String { rawValue }
}

struct ValidationIssue: Identifiable {
    let id = UUID()
    let severity: Severity
    let message: String

    enum Severity {
        case error, warning, info
    }
}

struct ValidationReport {
    let issues: [ValidationIssue]
    let messageCount: Int
    let byteCount: Int

    var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    var isValid: Bool { errors.isEmpty }
}
