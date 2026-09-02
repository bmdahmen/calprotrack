import SwiftUI

struct TodayView: View {
    @Binding var showSettings: Bool

    @State private var meals: [Meal] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var totalCal: Int { meals.reduce(0) { $0 + $1.cal } }
    private var totalPro: Int { meals.reduce(0) { $0 + $1.pro } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        if !TokenStore.shared.hasToken {
                            Button("Open Settings") { showSettings = true }
                                .font(.footnote)
                        }
                    }

                    VStack(spacing: 2) {
                        Text("\(totalCal)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("kcal today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text("\(totalPro)g")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.purple)
                        Text("protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !meals.isEmpty {
                        Divider()
                        Text("\(meals.count) item\(meals.count == 1 ? "" : "s") logged")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay {
                if isLoading && meals.isEmpty {
                    ProgressView()
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func refresh() async {
        guard TokenStore.shared.hasToken else {
            errorMessage = APIError.noToken.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            meals = try await CalProTrackAPI.shared.loadMeals(date: Date().apiDateKey)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
