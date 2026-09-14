//
//  WeatherView.swift
//  boringNotch
//
//  Spike: native port of the items/widgets/weather.lua popup — same
//  wttr.in fields, restyled after Apple Weather's own hourly strip and
//  reusing CalendarView's WheelPicker convention (a horizontally
//  scrollable row of rounded cells) instead of a handful of static pills.
//
//  Sizing: height is centralized in ContentView; width is left intrinsic
//  like NotchHomeView/ShelfView, sized generously enough to naturally
//  reach the same width those do, not just fit inside it.
//

import SwiftUI
import AppKit

struct WeatherView: View {
    @ObservedObject var manager = WeatherManager.shared

    var body: some View {
        Group {
            if let info = manager.info {
                content(for: info)
                    .transition(.opacity)
            } else {
                Text("Loading weather…")
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.65))
            }
        }
        .padding(8)
        .animation(.easeInOut(duration: 0.35), value: manager.info)
    }

    private func content(for info: WeatherInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: info.symbolName)
                            .font(.system(size: 26))
                            .symbolRenderingMode(.multicolor)
                        Text("\(info.tempC)°")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.effectiveAccent)
                    }
                    .frame(width: 68)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.city)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(info.condition)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 130, alignment: .leading)

                detailCard(icon: "thermometer.medium", value: "\(info.feelsLikeC)°C", label: "Feels", tint: .orange)
                detailCard(icon: "humidity.fill", value: "\(info.humidity)%", label: "Humidity", tint: .cyan)
                detailCard(icon: "wind", value: "\(info.windKmh) km/h", label: "Wind", tint: .mint)
            }

            // Apple Weather-style hourly strip: every hour wttr.in gives us,
            // horizontally scrollable, reusing WheelPicker's rounded-cell
            // language from CalendarView instead of 3 static pills.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(info.forecast) { entry in
                        hourCell(entry)
                    }
                }
            }
            // Explicit width only: an unconstrained ScrollView is greedy
            // along its scroll axis — exactly the unbounded-size failure
            // mode that previously corrupted the shared notch shape/header.
            // Height is left intrinsic (safe — that's the non-scrolling axis).
            .frame(width: 524, alignment: .leading)
        }
        .onTapGesture { manager.refresh() }
    }

    private func detailCard(icon: String, value: String, label: String, tint: Color) -> some View {
        HoverCard {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }
            .frame(width: 90, height: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.15)))
        }
    }

    // Matches Apple Weather's own hourly strip: flat columns, no per-cell
    // card, bold white time/temp, blue precip % only when it's actually
    // likely to rain.
    private func hourCell(_ entry: ForecastEntry) -> some View {
        VStack(spacing: 2) {
            Text(entry.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            Image(systemName: entry.symbolName)
                .font(.system(size: 13))
                .symbolRenderingMode(.multicolor)
            Text(entry.chanceOfRain > 20 ? "\(entry.chanceOfRain)%" : " ")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.blue)
            Text("\(entry.tempC)°")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 40)
    }
}

/// Small reusable hover-scale wrapper, matching HoverButton's feel
/// (used for icon buttons elsewhere) but for arbitrary card content.
private struct HoverCard<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        content
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .brightness(isHovering ? 0.06 : 0)
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.2)) {
                    isHovering = hovering
                }
            }
    }
}
