import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sourceBank: JX8PBank?
    @State private var reference: JX10ReferenceBank?
    @State private var converted = Data()
    @State private var validation: ValidationReport?
    @State private var sourceName = "No JX-8P bank loaded"
    @State private var referenceName = "GSCUSTOM-A.SYX (Default Reference)"
    @State private var status = "Load a JX-8P bank to begin."
    @State private var errorMessage: String?
    @State private var strategy: PatchStrategy = .mirror
    @State private var target: Target = .jx10
    @State private var channel = 0
    
    @State private var showSourceImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sourceSection
            settingsSection
            actionSection
            validationSection
            toneList
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            loadDefaultReference()
        }
        .fileImporter(
            isPresented: $showSourceImporter,
            allowedContentTypes: [.data]
        ) { result in
            loadSource(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("JX-8P → JX-10 / MKS-70 Converter")
                .font(.largeTitle.bold())
            Text("Production-oriented SysEx bank file conversion and validation")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceSection: some View {
        GroupBox("Source Bank") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(sourceName, systemImage: sourceBank == nil ? "doc" : "checkmark.circle.fill")
                    Spacer()
                    Button("Open JX-8P .SYX…") {
                        showSourceImporter = true
                    }
                }
            }
            .padding(6)
        }
    }

    private var settingsSection: some View {
        GroupBox("Conversion settings") {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
                GridRow {
                    Text("Target")
                    Picker("", selection: $target) {
                        ForEach(Target.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                GridRow {
                    Text("Patch strategy")
                    Picker("", selection: $strategy) {
                        ForEach(PatchStrategy.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                GridRow {
                    Text("MIDI channel")
                    Picker("", selection: $channel) {
                        ForEach(0..<16, id: \.self) { Text("Channel \($0 + 1)").tag($0) }
                    }
                }
            }
            .padding(6)

            Text("The JX-10 and MKS-70 use the same Super JX bulk format. A JX-8P tone is placed in both layers for a faithful single-tone patch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button("Convert") { convert() }
                .buttonStyle(.borderedProminent)
                .disabled(sourceBank == nil || reference == nil)

            Button("Validate Output") {
                validation = BankValidator().validate(converted)
                status = validation?.isValid == true ? "Output validation passed." : "Output validation found errors."
            }
            .disabled(converted.isEmpty)

            Button("Save .SYX Bank…") {
                saveSyxFile()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(converted.isEmpty)

            Spacer()
        }
    }

    private var validationSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 6) {
                Text(status)
                if let validation {
                    Text("\(validation.messageCount) messages • \(validation.byteCount) bytes")
                        .foregroundStyle(.secondary)
                    ForEach(validation.issues) { issue in
                        HStack {
                            Image(systemName: issue.severity == .error ? "xmark.circle" :
                                      issue.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                            Text(issue.message)
                        }
                        .foregroundStyle(issue.severity == .error ? .red :
                                             issue.severity == .warning ? .orange : .secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(6)
        }
    }

    private var toneList: some View {
        GroupBox("JX-8P tones") {
            if let sourceBank {
                List(sourceBank.tones) { tone in
                    HStack {
                        Text(String(format: "%02d", tone.id + 1)).monospacedDigit().foregroundStyle(.secondary)
                        Text(tone.name)
                        Spacer()
                        Text("\(tone.parameters.count) parameters")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No source bank loaded.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func loadDefaultReference() {
        if let bundleURL = Bundle.main.url(forResource: "GSCUSTOM-A", withExtension: "syx") ??
                          Bundle.main.url(forResource: "GSCUSTOM-A", withExtension: "SYX") {
            do {
                let data = try Data(contentsOf: bundleURL)
                reference = try JX10ReferenceBank.parse(data)
                referenceName = "GSCUSTOM-A.SYX (Default)"
            } catch {
                errorMessage = "Failed to parse default reference: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Default reference bank GSCUSTOM-A.syx missing from app bundle."
        }
    }

    private func loadSource(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                sourceBank = try JX8PParser().parse(Data(contentsOf: url))
                sourceName = "\(url.lastPathComponent) • 32 tones"
                status = "JX-8P bank loaded. Ready to convert."
                errorMessage = nil
            } catch let err {
                errorMessage = err.localizedDescription
            }
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }

    private func convert() {
        guard let sourceBank, let reference else { return }
        do {
            converted = try JX10BankEncoder().makeBank(
                source: sourceBank,
                reference: reference,
                strategy: strategy,
                channel: UInt8(channel)
            )
            validation = BankValidator().validate(converted)
            status = "Conversion complete: 64 patches + 50 tones. Ready to save."
            errorMessage = nil
        } catch let err {
            errorMessage = err.localizedDescription
        }
    }

    private func saveSyxFile() {
            // Run off the direct debugger-monitored synchronous stack frame
            Task { @MainActor in
                let panel = NSSavePanel()
                panel.title = "Save JX-10 Bank"
                panel.nameFieldStringValue = "JX8P_to_JX10_Converted.syx"
                panel.allowedContentTypes = [.data]

                let response = panel.runModal()
                if response == .OK, let url = panel.url {
                    self.writeConvertedFile(to: url)
                }
            }
        }

    private func writeConvertedFile(to url: URL) {
        do {
            try converted.write(to: url)
            status = "Saved converted file as \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }
}
