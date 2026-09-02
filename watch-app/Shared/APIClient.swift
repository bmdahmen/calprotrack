import Foundation

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
    var time: String
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
        return try JSONDecoder().decode([Meal].self, from: data)
    }

    /// Overwrites the FULL day's meal list — the Worker deletes and
    /// re-inserts every row for `date`, same as the web app. So to add one
    /// meal, load the day first, append locally, then call this with the
    /// whole updated array.
    func saveMeals(date: String, meals: [Meal]) async throws {
        let mealDicts = meals.map { m -> [String: Any] in
            ["id": m.id, "desc": m.desc, "cal": m.cal, "pro": m.pro, "time": m.time]
        }
        _ = try await post("/meals/save", body: ["date": date, "meals": mealDicts])
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
