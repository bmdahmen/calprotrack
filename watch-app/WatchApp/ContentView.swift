import SwiftUI

/// Four pages, swipeable: today's totals, manual meal entry, the food-items
/// catalog, and presets — the latter two are read/log-only from the Watch,
/// editing stays on the web app. Settings (the pasted session token) lives
/// behind a gear icon on the Today page rather than as its own swipe page.
struct ContentView: View {
    @State private var showSettings = false

    var body: some View {
        TabView {
            TodayView(showSettings: $showSettings)
            LogMealView()
            FoodItemsView()
            PresetsView()
        }
        .tabViewStyle(.page)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
