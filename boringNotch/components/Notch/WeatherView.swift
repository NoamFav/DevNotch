//
//  WeatherView.swift
//  boringNotch
//
//  Spike: native port of the items/widgets/weather.lua popup — same
//  wttr.in fields (condition, feels like, humidity, wind, next 1h/3h/6h).
//
//  Structured exactly like ShelfView/CalendarView: plain stacks, no
//  frame modifiers at the top level, just concrete-sized text and icons.
//

import SwiftUI

struct WeatherView: View {
    @ObservedObject var manager = WeatherManager.shared

    var body: some View {
        if let info = manager.info {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.city)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(info.condition)
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.65))
                    }
                    Image(systemName: info.symbolName)
                        .font(.system(size: 20))
                        .symbolRenderingMode(.multicolor)
                    Text("\(info.tempC)°")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                HStack {
                    Text("Feels \(info.feelsLikeC)°C")
                    Text("·")
                    Text("Humidity \(info.humidity)%")
                    Text("·")
                    Text("Wind \(info.windKmh) km/h")
                }
                .font(.caption)
                .foregroundColor(Color(white: 0.65))

                HStack {
                    Text("1h: \(info.next1h)")
                    Text("·")
                    Text("3h: \(info.next3h)")
                    Text("·")
                    Text("6h: \(info.next6h)")
                }
                .font(.caption2)
                .foregroundColor(Color(white: 0.5))
            }
            .padding(16)
            .frame(height: 130, alignment: .top)
            .onTapGesture { manager.refresh() }
        } else {
            Text("Loading weather…")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.65))
                .padding(16)
                .frame(height: 130, alignment: .top)
        }
    }
}
