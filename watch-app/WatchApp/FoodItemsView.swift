import SwiftUI

/// Scrollable catalog of quick-add items — tap one to log it to today.
/// Read-only from the Watch: editing the catalog stays on the web app.
struct FoodItemsView: View {
    @State private var items: [FoodItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loggedId: String?
    @State private var wizardItem: FoodItem?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if items.isEmpty && !isLoading && errorMessage == nil {
                    Text("No food items yet — add some on the web app")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    // A plain Button's built-in tap gesture fights a
                    // long-press gesture layered on top of it (both can
                    // fire off the same touch-up), so this uses manual tap
                    // + long-press gestures on a non-Button row instead:
                    // tap logs 1× immediately, hold opens the serving
                    // wizard to scale it first.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.name)
                            Spacer()
                            if loggedId == item.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(subtitle(for: item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await log(item) }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        wizardItem = item
                    }
                }
            }
            .navigationTitle("Food Items")
            .overlay {
                if isLoading && items.isEmpty {
                    ProgressView()
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .sheet(item: $wizardItem) { item in
                ServingWizardView(item: item) {
                    loggedId = item.id
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if loggedId == item.id { loggedId = nil }
                    }
                }
            }
        }
    }

    private func subtitle(for item: FoodItem) -> String {
        var parts = ["\(item.cal) kcal"]
        if item.pro > 0 { parts.append("\(item.pro)g protein") }
        if let w = item.weight_g, w > 0 {
            parts.append(w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))g" : String(format: "%.1fg", w))
        }
        return parts.joined(separator: " · ")
    }

    private func refresh() async {
        guard TokenStore.shared.hasToken else {
            errorMessage = APIError.noToken.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await CalProTrackAPI.shared.loadFoodItems()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func log(_ item: FoodItem) async {
        do {
            try await CalProTrackAPI.shared.logFoodItem(item, date: Date().apiDateKey)
            loggedId = item.id
            try? await Task.sleep(for: .seconds(1))
            if loggedId == item.id { loggedId = nil }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
