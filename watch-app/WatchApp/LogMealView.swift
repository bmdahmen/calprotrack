import SwiftUI

struct LogMealView: View {
    @State private var desc = ""
    @State private var cal = 0
    @State private var pro = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var justLogged = false
    @State private var editingField: NumericField?

    private enum NumericField: Identifiable {
        case calories, protein
        var id: Self { self }
    }

    private var canSubmit: Bool {
        !desc.trimmingCharacters(in: .whitespaces).isEmpty && cal > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // watchOS has no numeric keyboard mode at all — not even
                // via TextField bound to a numeric value — so these open a
                // real digit keypad (NumericKeypadView) in a sheet instead.
                Section {
                    TextField("Description", text: $desc)
                }
                Section {
                    Button {
                        editingField = .calories
                    } label: {
                        HStack {
                            Text("Calories")
                            Spacer()
                            Text("\(cal)").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        editingField = .protein
                    } label: {
                        HStack {
                            Text("Protein (g)")
                            Spacer()
                            Text("\(pro)").foregroundStyle(.secondary)
                        }
                    }
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
            .sheet(item: $editingField) { field in
                switch field {
                case .calories:
                    NumericKeypadView(title: "Calories", value: cal) { cal = $0 }
                case .protein:
                    NumericKeypadView(title: "Protein (g)", value: pro) { pro = $0 }
                }
            }
        }
    }

    private func submit() async {
        guard cal > 0 else { return }
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
            desc = ""; cal = 0; pro = 0
            justLogged = true
            try? await Task.sleep(for: .seconds(1.2))
            justLogged = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
