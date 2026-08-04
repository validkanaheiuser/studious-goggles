import SwiftUI

final class WriteModel: ObservableObject {
    @Published var log = ""
    @Published var running = false
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    func appendLog(_ line: String) {
        log += line + "\n"
    }
}

struct ContentView: View {
    @StateObject private var model = WriteModel()

    private let targetPath = "/var/mobile/Containers/Data/Application/6A65489C-F668-4C29-AFA2-4B1FE2C4C645/Documents/hellobommer_test"
    private let traversalPrefix = "../../../../../../../../../../.."

    var body: some View {
        VStack(spacing: 20) {
            Button("Write") { runWrite() }
                .buttonStyle(.borderedProminent)
                .disabled(model.running)

            if model.running || !model.log.isEmpty {
                ScrollView {
                    Text(model.log)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 260)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            if model.running {
                ProgressView()
            }
        }
        .padding()
        .alert(model.alertTitle, isPresented: $model.showAlert) {
            Button("OK") {}
        } message: {
            Text(model.alertMessage)
        }
    }

    private func runWrite() {
        model.running = true
        model.log = ""
        let destination = targetPath
        let identifier = traversalPrefix + destination
        let m = model

        DispatchQueue.global(qos: .userInitiated).async {
            let result = dd_write(identifier, destination) { step in
                // already dispatched to main queue by ObjC
                m.appendLog(step ?? "")
            }

            var exists = false
            var uid: UInt32 = 0
            var fileSize: Int64 = 0
            destination.withCString { cPath in
                var buf = Darwin.stat()
                if lstat(cPath, &buf) == 0 {
                    exists = true
                    uid = buf.st_uid
                    fileSize = buf.st_size
                }
            }

            let fileInfo = exists ? "uid=\(uid) size=\(fileSize)" : "file not found"
            DispatchQueue.main.async {
                m.appendLog("→ " + fileInfo)
                m.running = false
                m.alertTitle = result == 0 ? "Write OK" : "Write Failed"
                m.alertMessage = "\(destination)\n\(fileInfo)"
                m.showAlert = true
            }
        }
    }
}
