import Foundation

struct JX10ReferenceBank {
    let patchMessages: [[UInt8]]
    let toneMessages: [[UInt8]]

    static func parse(_ data: Data) throws -> JX10ReferenceBank {
        let messages = try splitSysEx(data)

        let patches = messages.filter {
            $0.count == 106 &&
            $0[0] == 0xF0 && $0[1] == Roland.manufacturer &&
            $0[2] == Roland.bld && $0[4] == Roland.superJXFormat &&
            $0[5] == Roland.superJXPatchLevel
        }

        let tones = messages.filter {
            $0.count == 69 &&
            $0[0] == 0xF0 && $0[1] == Roland.manufacturer &&
            $0[2] == Roland.bld && $0[4] == Roland.superJXFormat &&
            $0[5] == Roland.superJXToneLevel
        }

        guard patches.count == 64, tones.count == 50 else {
            throw SysExError.invalidBank(
                "Reference bank must contain 64 patch BLD messages and 50 tone BLD messages."
            )
        }

        return JX10ReferenceBank(patchMessages: patches, toneMessages: tones)
    }
}

struct JX10BankEncoder {
    private func convertToneParameters(_ source: [UInt8]) throws -> [UInt8] {
        guard source.count == 49 else {
            throw SysExError.invalidBank("JX-8P tone does not contain 49 parameter bytes.")
        }

        var p = source

        // Shared parameter ordering is used by the JX-8P and Super JX.
        // The waveform bands differ:
        // JX-8P  0..31 Noise, 32..63 Saw, 64..95 Pulse, 96..127 Square
        // SuperJX 0..31 Noise, 32..63 Square, 64..95 Pulse, 96..127 Saw
        for index in [2, 7] {
            switch p[index] {
            case 32...63: p[index] += 64
            case 96...127: p[index] -= 64
            default: break
            }
        }

        return p
    }

    func toneMessage(_ tone: JX8PTone, slot: Int, channel: UInt8) throws -> [UInt8] {
        let params = try convertToneParameters(tone.parameters)
        let payload = fixedName(tone.name, length: 10) + params // 59 bytes

        // Tone BLD data is transmitted as 59 direct 7-bit values.
        // Patch BLD data is the format that uses high/low nibbles.
        return [
            0xF0, Roland.manufacturer, Roland.bld, channel,
            Roland.superJXFormat, Roland.superJXToneLevel,
            0x01, 0x00, UInt8(slot & 0x7F)
        ] + payload.map { $0 & 0x7F } + [0xF7]
    }

    func patchMessage(
        reference: [UInt8],
        patchNumber: Int,
        name: String,
        upperTone: Int,
        lowerTone: Int,
        channel: UInt8
    ) throws -> [UInt8] {
        guard reference.count == 106 else {
            throw SysExError.invalidMessage("Reference patch is not 106 bytes.")
        }

        let packed = try nibbleUnpack(reference[9..<105])
        guard packed.count == 48 else {
            throw SysExError.invalidBank("Reference patch payload is not 48 bytes.")
        }

        var patch = packed

        // The first 18 bytes are the patch name. The remaining 30 bytes are
        // Roland's compact patch-memory representation. In that representation
        // the A/B tone references are stored at offsets 9 and 14 with bit 7 set.
        // This matches the factory JX10/MKS70 BLD bank representation.
        patch.replaceSubrange(0..<18, with: fixedName(name, length: 18))
        patch[9] = 0x80 | UInt8(upperTone & 0x7F)
        patch[14] = 0x80 | UInt8(lowerTone & 0x7F)

        return [
            0xF0, Roland.manufacturer, Roland.bld, channel,
            Roland.superJXFormat, Roland.superJXPatchLevel,
            0x01, 0x00, UInt8(patchNumber & 0x3F)
        ] + nibblePack(patch) + [0xF7]
    }

    func makeBank(
        source: JX8PBank,
        reference: JX10ReferenceBank,
        strategy: PatchStrategy,
        channel: UInt8
    ) throws -> Data {
        var messages = [[UInt8]]()

        // 64 patches. A JX-8P patch is one tone, so the default faithful
        // representation is to put the same tone in both Super JX layers.
        for patch in 0..<64 {
            let a: Int
            let b: Int

            switch strategy {
            case .mirror:
                a = patch % 32
                b = a
            case .pair:
                let base = (patch % 16) * 2
                a = base
                b = base + 1
            }

            let name = source.tones[a].name
            messages.append(try patchMessage(
                reference: reference.patchMessages[patch],
                patchNumber: patch,
                name: name,
                upperTone: a,
                lowerTone: b,
                channel: channel
            ))
        }

        // Tone slots 0..31 are the converted JX-8P tones.
        for index in 0..<32 {
            messages.append(try toneMessage(
                source.tones[index],
                slot: index,
                channel: channel
            ))
        }

        // Preserve the reference bank's remaining 18 tone slots.
        for index in 32..<50 {
            var m = reference.toneMessages[index]
            m[3] = channel
            messages.append(m)
        }

        return Data(messages.flatMap { $0 })
    }
}
