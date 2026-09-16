//
//  WeatherManager.swift
//  devNotch
//
//  Spike: native port of items/widgets/weather.lua — same wttr.in endpoint
//  and fields, fetched with URLSession instead of shelling out to curl/jq.
//

import Foundation
import Combine

struct ForecastEntry: Equatable, Identifiable {
    var id: String { label }
    var label: String
    var isNow: Bool
    var tempC: Int
    var symbolName: String
    var chanceOfRain: Int
}

struct WeatherInfo: Equatable {
    var city: String = "—"
    var tempC: Int = 0
    var condition: String = "—"
    var feelsLikeC: Int = 0
    var humidity: Int = 0
    var windKmh: Int = 0
    var uvIndex: Int = 0
    var sunrise: String = "—"
    var sunset: String = "—"
    var forecast: [ForecastEntry] = []
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
        // All days wttr.in gives us (typically 3), concatenated into one
        // continuous strip like Apple Weather's — scroll goes as far as
        // the data actually allows, not an arbitrary cap. Each hour keeps
        // its day's date so we can mark day boundaries distinctly instead
        // of showing "9PM"/"12AM" two or three times with no distinction.
        let allHourly: [(date: String, hour: Hourly)] = r.weather.flatMap { day in
            day.hourly.map { (day.date, $0) }
        }
        let currentHour = Calendar.current.component(.hour, from: Date())

        // wttr.in encodes hour-of-day as "0", "300", ... "2100" (HMM/HHMM).
        func hour24(_ h: Hourly) -> Int { (Int(h.time) ?? 0) / 100 }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"

        func weekdayLabel(for dateString: String) -> String {
            guard let date = dateFormatter.date(from: dateString) else { return dateString }
            return weekdayFormatter.string(from: date)
        }

        let upcoming = Array(allHourly.drop { hour24($0.hour) < currentHour })
        var firstShown = true
        let forecast: [ForecastEntry] = upcoming.map { entry in
            let h = entry.hour
            let hr = hour24(h)
            let isNow = firstShown
            firstShown = false
            let label: String
            if isNow {
                label = "Now"
            } else if hr == 0 {
                // Midnight marks a new day — show the weekday instead of
                // a second, ambiguous "12AM" further down the strip.
                label = weekdayLabel(for: entry.date)
            } else {
                switch hr {
                case 1..<12: label = "\(hr)AM"
                case 12: label = "12PM"
                default: label = "\(hr - 12)PM"
                }
            }
            let cond = h.weatherDesc.first?.value ?? "—"
            return ForecastEntry(
                label: label,
                isNow: isNow,
                tempC: Int(h.tempC) ?? 0,
                symbolName: symbol(for: cond),
                chanceOfRain: Int(h.chanceofrain) ?? 0
            )
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
            uvIndex: Int(cur?.uvIndex ?? "") ?? 0,
            sunrise: r.weather.first?.astronomy.first?.sunrise ?? "—",
            sunset: r.weather.first?.astronomy.first?.sunset ?? "—",
            forecast: forecast,
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
    let uvIndex: String
    let weatherDesc: [Desc]
}
private struct NearestArea: Decodable {
    let areaName: [Desc]
}
private struct WeatherDay: Decodable {
    let date: String
    let astronomy: [Astronomy]
    let hourly: [Hourly]
}
private struct Astronomy: Decodable {
    let sunrise: String
    let sunset: String
}
private struct Hourly: Decodable {
    let time: String
    let tempC: String
    let chanceofrain: String
    let weatherDesc: [Desc]
}
private struct Desc: Decodable {
    let value: String
}
