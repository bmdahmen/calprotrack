import SwiftUI

/// Two pages, swipeable — matches the "one page to view, one page to log"
/// request. Settings (the pasted session token) lives behind a gear icon on
/// the Today page rather than as a third swipe page, so those stay the two
/// primary pages.
struct ContentView: View {
    @State private var showSettings = false

    var body: some View {
        TabView {
            TodayView(showSettings: $showSettings)
            LogMealView()
        }
        .tabViewStyle(.page)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
