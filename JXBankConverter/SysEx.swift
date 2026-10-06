import Foundation

enum SysExError: LocalizedError {
    case malformed
    case noJX8PBank
    case invalidMessage(String)
    case invalidBank(String)

    var errorDescription: String? {
        switch self {
        case .malformed: return "The file contains an incomplete or malformed SysEx message."
        case .noJX8PBank: return "No complete 32-tone JX-8P bank was found."
        case .invalidMessage(let s): return s
        case .invalidBank(let s): return s
        }
    }
}

enum Roland {
    static let manufacturer: UInt8 = 0x41
    static let jx8pFormat: UInt8 = 0x21
    static let superJXFormat: UInt8 = 0x24
    static let apr: UInt8 = 0x35
    static let pgr: UInt8 = 0x34
    static let bld: UInt8 = 0x37
    static let jx8pToneLevel: UInt8 = 0x20
    static let superJXToneLevel: UInt8 = 0x20
    static let superJXPatchLevel: UInt8 = 0x30
}

func splitSysEx(_ data: Data) throws -> [[UInt8]] {
    var messages = [[UInt8]]()
    var current = [UInt8]()
    var open = false

    for byte in data {
        if byte == 0xF0 {
            if open { throw SysExError.malformed }
            current = [byte]
            open = true
        } else if byte == 0xF7 {
            guard open else { throw SysExError.malformed }
            current.append(byte)
            messages.append(current)
            current.removeAll(keepingCapacity: true)
            open = false
        } else if open {
            current.append(byte)
        }
    }

    guard !open, !messages.isEmpty else { throw SysExError.malformed }
    return messages
}

// Roland JX-10/MKS-70 bulk dumps store 8-bit data as high/low nibbles.
func nibblePack(_ bytes: [UInt8]) -> [UInt8] {
    bytes.flatMap { [($0 >> 4) & 0x0F, $0 & 0x0F] }
}

func nibbleUnpack(_ bytes: ArraySlice<UInt8>) throws -> [UInt8] {
    let a = Array(bytes)
    guard a.count % 2 == 0 else { throw SysExError.invalidBank("Odd number of nibbles.") }
    return stride(from: 0, to: a.count, by: 2).map {
        ((a[$0] & 0x0F) << 4) | (a[$0 + 1] & 0x0F)
    }
}

func asciiName(_ bytes: ArraySlice<UInt8>) -> String {
    String(bytes: bytes.map { $0 >= 0x20 && $0 < 0x7F ? $0 : 0x20 }, encoding: .ascii)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func fixedName(_ name: String, length: Int) -> [UInt8] {
    let raw = Array(name.uppercased().utf8.prefix(length))
    return raw + Array(repeating: 0x20, count: max(0, length - raw.count))
}
