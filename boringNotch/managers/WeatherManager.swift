//
//  WeatherManager.swift
//  boringNotch
//
//  Spike: native port of items/widgets/weather.lua — same wttr.in endpoint
//  and fields, fetched with URLSession instead of shelling out to curl/jq.
//

import Foundation
import Combine

struct WeatherInfo: Equatable {
    var city: String = "—"
    var tempC: Int = 0
    var condition: String = "—"
    var feelsLikeC: Int = 0
    var humidity: Int = 0
    var windKmh: Int = 0
    var next1h: String = "—"
    var next3h: String = "—"
    var next6h: String = "—"
    var symbolName: String = "cloud.sun.fill"
}

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var info: WeatherInfo?
    @Published private(set) var isLoading = false

    private let city = "Paris" // matches items/widgets/weather.lua
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let city = self.city
        guard let url = URL(string: "https://wttr.in/\(city)?format=j1") else { return }
        isLoading = true

        Task.detached(priority: .utility) {
            let result: WeatherInfo?
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(WttrResponse.self, from: data)
                result = Self.map(decoded, city: city)
            } catch {
                result = nil
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isLoading = false
                if let result {
                    self.info = result
                }
            }
        }
    }

    private nonisolated static func map(_ r: WttrResponse, city: String) -> WeatherInfo {
        let cur = r.current_condition.first
        let hourly = r.weather.first?.hourly ?? []

        func hour(_ i: Int) -> String {
            guard hourly.indices.contains(i) else { return "—" }
            let h = hourly[i]
            return "\(h.tempC)°C, \(h.weatherDesc.first?.value ?? "—")"
        }

        let condition = cur?.weatherDesc.first?.value ?? "—"
        return WeatherInfo(
            // Display what was actually asked for — wttr.in's nearest_area
            // often resolves to a specific quartier (e.g. "Saint-Merri")
            // rather than the city itself.
            city: city,
            tempC: Int(cur?.temp_C ?? "") ?? 0,
            condition: condition,
            feelsLikeC: Int(cur?.FeelsLikeC ?? "") ?? 0,
            humidity: Int(cur?.humidity ?? "") ?? 0,
            windKmh: Int(cur?.windspeedKmph ?? "") ?? 0,
            next1h: hour(1),
            next3h: hour(3),
            next6h: hour(6),
            symbolName: symbol(for: condition)
        )
    }

    private nonisolated static func symbol(for condition: String) -> String {
        let c = condition.lowercased()
        if c.contains("storm") || c.contains("thunder") { return "cloud.bolt.rain.fill" }
        if c.contains("rain") || c.contains("drizzle") { return "cloud.rain.fill" }
        if c.contains("snow") || c.contains("sleet") || c.contains("hail") { return "cloud.snow.fill" }
        if c.contains("clear") || c.contains("sun") { return "sun.max.fill" }
        if c.contains("cloud") || c.contains("overcast") { return "cloud.fill" }
        return "cloud.sun.fill"
    }
}

// Minimal mirror of wttr.in's j1 response — only the fields the widget uses.
private struct WttrResponse: Decodable {
    let current_condition: [CurrentCondition]
    let nearest_area: [NearestArea]
    let weather: [WeatherDay]
}
private struct CurrentCondition: Decodable {
    let temp_C: String
    let FeelsLikeC: String
    let humidity: String
    let windspeedKmph: String
    let weatherDesc: [Desc]
}
private struct NearestArea: Decodable {
    let areaName: [Desc]
}
private struct WeatherDay: Decodable {
    let hourly: [Hourly]
}
private struct Hourly: Decodable {
    let tempC: String
    let weatherDesc: [Desc]
}
private struct Desc: Decodable {
    let value: String
}
