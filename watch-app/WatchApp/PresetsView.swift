import SwiftUI

/// Scrollable list of presets — tap one to log every item it contains to
/// today in one batch. Read-only from the Watch: building/editing presets
/// stays on the web app.
struct PresetsView: View {
    @State private var presets: [Preset] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loggedId: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if presets.isEmpty && !isLoading && errorMessage == nil {
                    Text("No presets yet — build one on the web app")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(presets) { preset in
                    Button {
                        Task { await log(preset) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(preset.name)
                                Spacer()
                                if loggedId == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(summary(for: preset))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(preset.items.isEmpty)
                }
            }
            .navigationTitle("Presets")
            .overlay {
                if isLoading && presets.isEmpty {
                    ProgressView()
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func summary(for preset: Preset) -> String {
        guard !preset.items.isEmpty else { return "No items in this preset" }
        let cal = preset.items.reduce(0) { $0 + Int((Double($1.cal) * $1.qty).rounded()) }
        let pro = preset.items.reduce(0) { $0 + Int((Double($1.pro) * $1.qty).rounded()) }
        return "\(preset.items.count) item\(preset.items.count == 1 ? "" : "s") · \(cal) kcal · \(pro)g protein"
    }

    private func refresh() async {
        guard TokenStore.shared.hasToken else {
            errorMessage = APIError.noToken.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            presets = try await CalProTrackAPI.shared.loadPresets()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func log(_ preset: Preset) async {
        do {
            try await CalProTrackAPI.shared.logPreset(preset, date: Date().apiDateKey)
            loggedId = preset.id
            try? await Task.sleep(for: .seconds(1))
            if loggedId == preset.id { loggedId = nil }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
