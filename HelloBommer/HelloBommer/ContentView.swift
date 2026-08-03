import SwiftUI

struct AppEntry: Identifiable {
    let id: String
    let name: String
    let dataPath: String
    let bundlePath: String

    var containerPath: String { dataPath.isEmpty ? bundlePath : dataPath }
}

private struct AppRow: View {
    let app: AppEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body)
                Text(app.id).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .onTapGesture(perform: onTap)
    }
}

struct ContentView: View {
    @State private var apps:       [AppEntry] = []
    @State private var selectedId: String?    = nil
    @State private var subPath                = "Documents"
    @State private var searchText             = ""
    @State private var running                = false
    @State private var showAlert              = false
    @State private var alertTitle             = ""
    @State private var alertMessage           = ""
    @State private var loading                = true
    @State private var debugInfo              = ""

    private var selected: AppEntry? { apps.first { $0.id == selectedId } }

    private var target: String {
        guard let app = selected else { return "" }
        let sub = subPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return sub.isEmpty ? app.containerPath : "\(app.containerPath)/\(sub)"
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

            // ── Search bar ─────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps…", text: $searchText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if loading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        alertTitle   = "Debug Info"
                        alertMessage = debugInfo.isEmpty ? "(no info)" : debugInfo
                        showAlert    = true
                    } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 12)

            // ── App list ───────────────────────────────────────────
            List(filtered) { app in
                AppRow(
                    app: app,
                    isSelected: selectedId == app.id,
                    onTap: { selectedId = (selectedId == app.id) ? nil : app.id }
                )
            }
            .listStyle(.plain)

            // ── Bottom panel (shown when app selected) ─────────────
            if let app = selected {
                Divider()
                VStack(spacing: 10) {
                    // Path display + sub-path editor
                    HStack(spacing: 4) {
                        Text(app.containerPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("/")
                            .foregroundStyle(.tertiary)
                        TextField("sub/path", text: $subPath)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(minWidth: 80, maxWidth: 160)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal)

                    // Action buttons
                    HStack(spacing: 16) {
                        Button("OK Bommer") { runWrite(app: app) }
                            .buttonStyle(.borderedProminent)
                            .disabled(running)

                        Button("Fuzz Read") { runFuzzRead(app: app) }
                            .buttonStyle(.bordered)
                            .disabled(running)

                        if running { ProgressView() }
                    }
                    .padding(.bottom, 16)
                }
                .background(Color(.systemBackground))
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear { loadApps() }
    }

    // MARK: - Write (OK Bommer)

    private func runWrite(app: AppEntry) {
        running = true
        let dest = target
        Task.detached {
            // 9 ../ levels → guaranteed to reach / from any daemon working dir
            let ident = "../../../../../../../../../../.." + dest
            // Confirm file appeared at dest
            let rc = dd_write(ident, dest)
            await finish(
                title:   rc == 0 ? "Write OK" : "Write Failed",
                message: rc == 0
                    ? "uid=0 file at:\n\(dest)"
                    : "dd_write → \(rc)\ntarget: \(dest)"
            )
        }
    }

    // MARK: - Fuzz Read

    private func runFuzzRead(app: AppEntry) {
        running = true
        let dest = target
        Task.detached {
            let ident   = "../../../../../../../../../../.." + dest
            let bufSize = 8192
            var buf     = [CChar](repeating: 0, count: bufSize)
            var outLen  = 0
            var cmd: Int32 = -1

            let rc = dd_fuzz_read(ident, &buf, bufSize, &outLen, &cmd)

            await finish(
                title:   rc == 0 ? "Read OK  (cmd \(cmd))" : "Read Failed",
                message: rc == 0
                    ? "\(app.name)\n\(dest)\n\n"
                      + (String(bytes: buf.prefix(outLen).map { UInt8(bitPattern: $0) },
                                encoding: .utf8) ?? "(non-UTF8, \(outLen) bytes)")
                    : "No command returned data.\n\(dest)"
            )
        }
    }

    // MARK: - Load apps

    private func loadApps() {
        loading = true
        Task.detached {
            let diag = dd_debug_info() ?? "(dd_debug_info returned nil)"
            let raw  = dd_installed_apps()
            let rawCount = raw?.count ?? -1
            var list = [AppEntry]()
            for item in (raw ?? []) {
                guard let bid = item["bundleId"], !bid.isEmpty else { continue }
                list.append(AppEntry(
                    id:         bid,
                    name:       item["name"] ?? bid,
                    dataPath:   item["dataPath"] ?? "",
                    bundlePath: item["bundlePath"] ?? ""
                ))
            }
            let info = "raw count: \(rawCount)\nparsed: \(list.count)\n\n\(diag)"
            await MainActor.run {
                apps      = list
                debugInfo = info
                loading   = false
                if list.isEmpty {
                    alertTitle   = "No Apps Found"
                    alertMessage = info
                    showAlert    = true
                }
            }
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
