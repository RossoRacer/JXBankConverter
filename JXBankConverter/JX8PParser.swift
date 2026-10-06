import Foundation

struct JX8PParser {
    func parse(_ data: Data) throws -> JX8PBank {
        let messages = try splitSysEx(data)

        let toneMessages = messages.filter {
            $0.count == 67 &&
            $0.count > 18 &&
            $0[0] == 0xF0 &&
            $0[1] == Roland.manufacturer &&
            $0[2] == Roland.apr &&
            $0[4] == Roland.jx8pFormat &&
            $0[5] == Roland.jx8pToneLevel &&
            $0[6] == 0x01
        }

        guard toneMessages.count == 32 else {
            throw SysExError.noJX8PBank
        }

        let tones = toneMessages.enumerated().map { index, message in
            let name = asciiName(message[7..<17])
            return JX8PTone(
                id: index,
                name: name.isEmpty ? "TONE \(index + 1)" : name,
                parameters: Array(message[17..<66]),
                channel: message[3]
            )
        }

        return JX8PBank(tones: tones, sourceMessages: toneMessages)
    }
}
