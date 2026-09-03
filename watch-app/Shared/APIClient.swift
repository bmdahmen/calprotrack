import Foundation
import WidgetKit

/// One logged food entry — mirrors the shape the Worker stores/returns for
/// each row in the `meals` table. `id` and `time` are free-form strings as
/// far as the backend is concerned (nothing validates their format), so
/// this model only needs to round-trip whatever it sends.
struct Meal: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var desc: String
    var cal: Int
    var pro: Int
    var weight_g: Double? = nil
    var time: String
}

/// A reusable quick-add catalog entry — mirrors a `food_items` row.
struct FoodItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var cal: Int
    var pro: Int
    var weight_g: Double?
}

/// One component of a preset. `qty` scales cal/pro/weight_g at log time —
/// same convention the web app uses (`web/index.html`'s `logPreset`).
struct PresetItem: Codable, Hashable {
    var name: String
    var cal: Int
    var pro: Int
    var weight_g: Double?
    var qty: Double
}

/// A named bundle of items, logged together in one tap.
struct Preset: Identifiable, Hashable {
    var id: String
    var name: String
    var items: [PresetItem]
}

extension Preset: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, items }

    /// The `presets` table stores `items` as a JSON-encoded string column
    /// (see `worker.js`'s `/presets/save`, which does
    /// `JSON.stringify(p.items)`), not a nested JSON array — so decoding
    /// has to unwrap that string manually instead of relying on plain
    /// Codable synthesis. Mirrors the web app's `safeParseItems`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let raw = try? c.decode(String.self, forKey: .items), let data = raw.data(using: .utf8) {
            items = (try? JSONDecoder().decode([PresetItem].self, from: data)) ?? []
        } else {
            items = (try? c.decode([PresetItem].self, forKey: .items)) ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(items, forKey: .items)
    }
}

enum APIError: LocalizedError {
    case noToken
    case authExpired
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noToken: return "No session token saved yet — add one in Settings."
        case .authExpired: return "Session expired — paste a fresh token in Settings."
        case .server(let message): return message
        case .badResponse: return "Unexpected response from the server."
        }
    }
}

/// Talks to the same Cloudflare Worker the web app uses
/// (https://calorie.bmdahmen.workers.dev). Every endpoint is a POST with a
/// JSON body; auth is a bearer session token obtained from the web app's
/// localStorage (see Settings) since this scaffold doesn't implement
/// Google Sign-In natively.
actor CalProTrackAPI {
    static let shared = CalProTrackAPI()

    private let baseURL = URL(string: "https://calorie.bmdahmen.workers.dev")!

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let token = TokenStore.shared.token, !token.isEmpty else {
            throw APIError.noToken
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        if http.statusCode == 401 { throw APIError.authExpired }
        if http.statusCode >= 400 {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? String }
            throw APIError.server(message ?? "Request failed (\(http.statusCode))")
        }
        return data
    }

    /// All meals logged on `date` ("yyyy-MM-dd").
    func loadMeals(date: String) async throws -> [Meal] {
        let data = try await post("/meals/load", body: ["date": date])
        let meals = try JSONDecoder().decode([Meal].self, from: data)
        updateSharedTotalsIfToday(date: date, meals: meals)
        return meals
    }

    /// Overwrites the FULL day's meal list — the Worker deletes and
    /// re-inserts every row for `date`, same as the web app. So to add one
    /// meal, load the day first, append locally, then call this with the
    /// whole updated array.
    func saveMeals(date: String, meals: [Meal]) async throws {
        let mealDicts = meals.map { m -> [String: Any] in
            var d: [String: Any] = ["id": m.id, "desc": m.desc, "cal": m.cal, "pro": m.pro, "time": m.time]
            if let w = m.weight_g { d["weight_g"] = w }
            return d
        }
        _ = try await post("/meals/save", body: ["date": date, "meals": mealDicts])
        updateSharedTotalsIfToday(date: date, meals: meals)
    }

    /// Pushes a fresh snapshot to the widget's shared storage and kicks
    /// WidgetKit to redraw the complication — every load/save in this app
    /// targets "today" in practice, so this is the one choke point that
    /// keeps the complication in sync without threading a callback through
    /// every call site.
    private func updateSharedTotalsIfToday(date: String, meals: [Meal]) {
        guard date == Date().apiDateKey else { return }
        let cal = meals.reduce(0) { $0 + $1.cal }
        let pro = meals.reduce(0) { $0 + $1.pro }
        SharedTotals.save(TodayTotals(cal: cal, pro: pro, updatedAt: Date()))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Loads today, appends `meal`, saves the full day back. Returns the
    /// updated list so the caller can refresh its UI without a second
    /// round trip.
    @discardableResult
    func logMeal(_ meal: Meal) async throws -> [Meal] {
        var todays = try await loadMeals(date: meal.date)
        todays.append(meal)
        try await saveMeals(date: meal.date, meals: todays)
        return todays
    }

    // MARK: Food items catalog (read + log only — no editing from the Watch)

    func loadFoodItems() async throws -> [FoodItem] {
        let data = try await post("/fooditems/load", body: [:])
        return try JSONDecoder().decode([FoodItem].self, from: data)
    }

    /// Logs one catalog item to `date`, scaled by `qty` — mirrors the web
    /// app's `logFoodItem`.
    @discardableResult
    func logFoodItem(_ item: FoodItem, qty: Double = 1, date: String) async throws -> [Meal] {
        let meal = Meal(
            id: UUID().uuidString,
            date: date,
            desc: Self.loggedDesc(name: item.name, weightG: item.weight_g, qty: qty),
            cal: Int((Double(item.cal) * qty).rounded()),
            pro: Int((Double(item.pro) * qty).rounded()),
            weight_g: item.weight_g.map { ($0 * qty * 10).rounded() / 10 },
            time: Date().apiTimeString
        )
        return try await logMeal(meal)
    }

    // MARK: Presets (read + log only — no editing from the Watch)

    func loadPresets() async throws -> [Preset] {
        let data = try await post("/presets/load", body: [:])
        return try JSONDecoder().decode([Preset].self, from: data)
    }

    /// Logs every item in a preset to `date` in one batch — mirrors the web
    /// app's `logPreset`.
    @discardableResult
    func logPreset(_ preset: Preset, date: String) async throws -> [Meal] {
        var todays = try await loadMeals(date: date)
        let now = Date()
        for it in preset.items {
            todays.append(Meal(
                id: UUID().uuidString,
                date: date,
                desc: Self.loggedDesc(name: it.name, weightG: it.weight_g, qty: it.qty),
                cal: Int((Double(it.cal) * it.qty).rounded()),
                pro: Int((Double(it.pro) * it.qty).rounded()),
                weight_g: it.weight_g.map { ($0 * it.qty * 10).rounded() / 10 },
                time: now.apiTimeString
            ))
        }
        try await saveMeals(date: date, meals: todays)
        return todays
    }

    private static func loggedDesc(name: String, weightG: Double?, qty: Double) -> String {
        guard qty != 1 else { return name }
        if let w = weightG {
            let scaled = (w * qty * 10).rounded() / 10
            let text = scaled.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fg", scaled)
                : String(format: "%.1fg", scaled)
            return "\(name) (\(text))"
        }
        let qtyText = qty.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", qty) : String(qty)
        return "\(name) ×\(qtyText)"
    }
}

extension Date {
    /// Local calendar day as "yyyy-MM-dd" — matches the web app's
    /// per-day keying. Uses the device's current calendar/timezone.
    var apiDateKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    /// A short local time string for the meal's `time` field. Purely
    /// cosmetic — the backend stores it as free text and never parses it.
    var apiTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: self)
    }
}
