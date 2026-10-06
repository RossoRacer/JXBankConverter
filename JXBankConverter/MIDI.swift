import Foundation
import Combine
import CoreMIDI

final class MIDIManager: ObservableObject {
    @Published private(set) var destinations: [MIDIDestination] = []

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()

    init() {
        MIDIClientCreate("JX Bank Converter" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "JX Bank Converter" as CFString, &port)
        refresh()
    }

    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func refresh() {
        var result = [MIDIDestination]()
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            guard endpoint != 0 else { continue }

            var property: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &property)
            let name = property?.takeRetainedValue() as String? ?? "MIDI \(i + 1)"
            result.append(MIDIDestination(name: name, endpoint: endpoint))
        }
        destinations = result
    }

    func send(messages: [[UInt8]], to destination: MIDIDestination, interMessageDelay: UInt64 = 15_000_000) async throws {
        for message in messages {
            try send(message, to: destination)
            try await Task.sleep(nanoseconds: interMessageDelay)
        }
    }

    private func send(_ bytes: [UInt8], to destination: MIDIDestination) throws {
        var list = MIDIPacketList()
        let timestamp = mach_absolute_time()
        var packet = MIDIPacketListInit(&list)

        bytes.withUnsafeBufferPointer { buffer in
            packet = MIDIPacketListAdd(
                &list,
                1024 * 1024,
                packet,
                timestamp,
                buffer.count,
                buffer.baseAddress!
            )
        }

        guard Int(bitPattern: packet) != 0 else {
            throw NSError(domain: "JXBankConverter.MIDI", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create MIDI packet."])
        }

        let status = MIDISend(port, destination.endpoint, &list)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "MIDI send failed (\(status))."])
        }
    }
}

struct MIDIDestination: Identifiable {
    let id = UUID()
    let name: String
    let endpoint: MIDIEndpointRef
}
