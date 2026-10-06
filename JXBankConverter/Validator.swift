import Foundation

struct BankValidator {
    func validate(_ data: Data) -> ValidationReport {
        var issues = [ValidationIssue]()

        do {
            let messages = try splitSysEx(data)

            let patches = messages.filter {
                $0.count == 106 && $0.count > 6 &&
                $0[1] == Roland.manufacturer &&
                $0[2] == Roland.bld &&
                $0[4] == Roland.superJXFormat &&
                $0[5] == Roland.superJXPatchLevel
            }

            let tones = messages.filter {
                $0.count == 69 && $0.count > 6 &&
                $0[1] == Roland.manufacturer &&
                $0[2] == Roland.bld &&
                $0[4] == Roland.superJXFormat &&
                $0[5] == Roland.superJXToneLevel
            }

            if patches.count != 64 {
                issues.append(.init(severity: .error,
                                    message: "Expected 64 JX-10/MKS-70 patch messages; found \(patches.count)."))
            }
            if tones.count != 50 {
                issues.append(.init(severity: .error,
                                    message: "Expected 50 JX-10/MKS-70 tone messages; found \(tones.count)."))
            }

            for (i, m) in patches.enumerated() {
                if m.first != 0xF0 || m.last != 0xF7 {
                    issues.append(.init(severity: .error, message: "Patch message \(i + 1) has invalid F0/F7 framing."))
                }
                if !m[9..<105].allSatisfy({ $0 <= 0x0F }) {
                    issues.append(.init(severity: .error, message: "Patch \(i + 1) contains a non-nibble payload byte."))
                }
            }

            for (i, m) in tones.enumerated() {
                if m.first != 0xF0 || m.last != 0xF7 {
                    issues.append(.init(severity: .error, message: "Tone message \(i + 1) has invalid F0/F7 framing."))
                }
                if !m[9..<68].allSatisfy({ $0 <= 0x7F }) {
                    issues.append(.init(severity: .error, message: "Tone \(i + 1) contains a non-7-bit payload byte."))
                }
            }

            if issues.isEmpty {
                issues.append(.init(severity: .info,
                                    message: "Valid Super JX bulk structure: 64 patches + 50 tones."))
            }

            return ValidationReport(
                issues: issues,
                messageCount: messages.count,
                byteCount: data.count
            )
        } catch {
            issues.append(.init(severity: .error, message: error.localizedDescription))
            return ValidationReport(issues: issues, messageCount: 0, byteCount: data.count)
        }
    }
}
