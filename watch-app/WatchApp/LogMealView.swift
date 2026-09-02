import SwiftUI

struct LogMealView: View {
    @State private var desc = ""
    @State private var calText = ""
    @State private var proText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var justLogged = false

    private var canSubmit: Bool {
        !desc.trimmingCharacters(in: .whitespaces).isEmpty && Int(calText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // No .keyboardType() here — that's a UIKit-bridged modifier
                // that isn't available on watchOS's TextField (watch text
                // entry goes through Scribble/dictation/the scrambled
                // keyboard instead). Numeric validation happens on submit.
                Section {
                    TextField("Description", text: $desc)
                    TextField("Calories", text: $calText)
                    TextField("Protein (g)", text: $proText)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(justLogged ? "Logged ✓" : "Log")
                    }
                }
                .disabled(!canSubmit || isSaving)
            }
            .navigationTitle("Log Meal")
        }
    }

    private func submit() async {
        guard let cal = Int(calText) else { return }
        let pro = Int(proText) ?? 0
        let now = Date()
        let meal = Meal(
            id: UUID().uuidString,
            date: now.apiDateKey,
            desc: desc.trimmingCharacters(in: .whitespaces),
            cal: cal,
            pro: pro,
            time: now.apiTimeString
        )

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await CalProTrackAPI.shared.logMeal(meal)
            desc = ""; calText = ""; proText = ""
            justLogged = true
            try? await Task.sleep(for: .seconds(1.2))
            justLogged = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
