import SwiftUI

/// A real numeric keypad — watchOS has no built-in one (no `.keyboardType`,
/// no numeric-only mode on `TextField`; every option is "build it
/// yourself"), so this is a plain digit grid in a sheet: tap digits, ⌫ to
/// correct, ✓ to confirm.
struct NumericKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onDone: (Int) -> Void

    @State private var text: String

    init(title: String, value: Int, onDone: @escaping (Int) -> Void) {
        self.title = title
        self.onDone = onDone
        _text = State(initialValue: value > 0 ? String(value) : "")
    }

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["⌫", "0", "✓"],
    ]

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "0" : text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            tap(key)
                        } label: {
                            Text(key)
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity, minHeight: 18)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(key == "✓" ? .green : (key == "⌫" ? .red : .gray))
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func tap(_ key: String) {
        switch key {
        case "⌫":
            if !text.isEmpty { text.removeLast() }
        case "✓":
            onDone(Int(text) ?? 0)
            dismiss()
        default:
            guard text.count < 5 else { return }
            text += key
        }
    }
}
