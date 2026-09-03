import SwiftUI

/// Mobile-friendly slider for scaling a food item's serving up/down before
/// logging — same 0–2.25× range and live-updating totals as the web app's
/// serving-size wizard (`openFoodItemServingWizard` in `index.html`).
struct ServingWizardView: View {
    @Environment(\.dismiss) private var dismiss
    let item: FoodItem
    var onLogged: () -> Void = {}

    @State private var mult: Double = 1
    @State private var isLogging = false
    @State private var errorMessage: String?

    private var scaledCal: Int { Int((Double(item.cal) * mult).rounded()) }
    private var scaledPro: Int { Int((Double(item.pro) * mult).rounded()) }
    private var scaledWeightText: String? {
        guard let w = item.weight_g else { return nil }
        let scaled = (w * mult * 10).rounded() / 10
        guard scaled > 0 else { return nil }
        return scaled.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(scaled))g" : String(format: "%.1fg", scaled)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(item.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                // Dragging the Slider itself is coarse on a screen this
                // small — a ~150pt track covering 0–2.25 means a tiny
                // finger movement swings the multiplier a lot. The +/-
                // buttons nudge in fixed quarter-steps for precise control;
                // the Slider/Crown stay for fast rough positioning.
                HStack(spacing: 14) {
                    Button {
                        nudge(-0.25)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)

                    Text(String(format: "%.2f×", mult))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(minWidth: 60)

                    Button {
                        nudge(0.25)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                Slider(value: $mult, in: 0...2.25)
                    // Digital Crown gives finer control than a touch drag —
                    // mirrors the trackpad-precision drag the web slider
                    // gets on a mouse.
                    .focusable(true)
                    .digitalCrownRotation($mult, from: 0, through: 2.25, by: 0.01)

                VStack(spacing: 2) {
                    Text("\(scaledCal) kcal")
                        .font(.subheadline.bold())
                    Text("\(scaledPro)g protein")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let scaledWeightText {
                        Text(scaledWeightText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await log() }
                } label: {
                    if isLogging {
                        ProgressView()
                    } else {
                        Text("Log")
                    }
                }
                .disabled(isLogging || mult <= 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func nudge(_ delta: Double) {
        mult = (min(2.25, max(0, mult + delta)) * 100).rounded() / 100
    }

    private func log() async {
        isLogging = true
        errorMessage = nil
        defer { isLogging = false }
        do {
            try await CalProTrackAPI.shared.logFoodItem(item, qty: mult, date: Date().apiDateKey)
            onLogged()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
