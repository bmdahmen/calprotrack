import SwiftUI

/// Where you paste the session token once (good for ~90 days). Get it by
/// opening the CalProTrack web app in a desktop browser, opening dev tools,
/// and running: localStorage.getItem('bl_session')
/// Typing a long token on the Watch's tiny keyboard is real friction —
/// Scribble or dictation (say "token" then edit) both work, or use the
/// watch keyboard's "Continue on iPhone" prompt if one appears.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tokenText = TokenStore.shared.token ?? ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Session token") {
                    TextField("Paste token", text: $tokenText)
                    Text("From the web app: localStorage.getItem('bl_session')")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button(saved ? "Saved ✓" : "Save") {
                    TokenStore.shared.token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        dismiss()
                    }
                }
                .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
