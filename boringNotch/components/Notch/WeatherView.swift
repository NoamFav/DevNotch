//
//  WeatherView.swift
//  boringNotch
//
//  Spike: native port of the items/widgets/weather.lua popup — same
//  wttr.in fields (condition, feels like, humidity, wind, next 1h/3h/6h).
//
//  Sizing is centralized in ContentView (the switch wrapper forces every
//  tab to the same width/height), so this view only needs concrete leaf
//  widths, no top-level frame of its own.
//

import SwiftUI

struct WeatherView: View {
    @ObservedObject var manager = WeatherManager.shared

    var body: some View {
        Group {
            if let info = manager.info {
                content(for: info)
            } else {
                Text("Loading weather…")
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.65))
            }
        }
        .padding(8)
    }

    private func content(for info: WeatherInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Image(systemName: info.symbolName)
                        .font(.system(size: 30))
                        .symbolRenderingMode(.multicolor)
                    Text("\(info.tempC)°")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.effectiveAccent)
                }
                .frame(width: 66)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.city)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(info.condition)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }
                .frame(width: 100, alignment: .leading)

                detailCard(icon: "thermometer.medium", value: "\(info.feelsLikeC)°C", label: "Feels", tint: .orange)
                detailCard(icon: "humidity.fill", value: "\(info.humidity)%", label: "Humidity", tint: .cyan)
                detailCard(icon: "wind", value: "\(info.windKmh) km/h", label: "Wind", tint: .mint)
            }

            // Calendar-style forecast strip: each slot is its own rounded
            // cell with an icon, mirroring WheelPicker's date cells.
            HStack(spacing: 8) {
                ForEach(info.forecast, id: \.label) { entry in
                    forecastCell(entry)
                }
            }
        }
        .onTapGesture { manager.refresh() }
    }

    private func detailCard(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.gray)
        }
        .frame(width: 76, height: 52)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.15)))
    }

    private func forecastCell(_ entry: ForecastEntry) -> some View {
        VStack(spacing: 2) {
            Text(entry.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
            Image(systemName: entry.symbolName)
                .font(.system(size: 14))
                .symbolRenderingMode(.multicolor)
            Text("\(entry.tempC)°")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 56, height: 38)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.effectiveAccentBackground))
    }
}
