//
//  SystemMonitorView.swift
//  devNotch
//
//  Spike: minimal "short btop" — 4 compact sparklines (CPU/RAM/GPU/Net)
//  plus disk and wifi stat rows, sized like the other notch tabs.
//
//  Sizing follows CalendarView's pattern exactly: every leaf gets a
//  concrete width (no maxWidth: .infinity, no Spacer, no outer wrapper
//  frame) so the shared notch shape sizes the same way it does for
//  NotchHomeView/ShelfView.
//

import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var manager = SystemManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(manager.current.hostname)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 300, alignment: .leading)

                if let ssid = manager.current.wifiSSID {
                    Label(ssid, systemImage: "wifi")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(width: 220, alignment: .trailing)
                } else {
                    Label("No Wi-Fi", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(width: 220, alignment: .trailing)
                }
            }
            .frame(width: 520, alignment: .leading)

            HStack(spacing: 10) {
                graphTile(
                    title: "CPU",
                    value: "\(Int(manager.current.cpuPercent))%",
                    history: manager.cpuHistory,
                    color: color(for: manager.current.cpuPercent)
                )
                graphTile(
                    title: "RAM",
                    value: "\(Int(manager.current.memPercent))%",
                    history: manager.memHistory,
                    color: color(for: manager.current.memPercent)
                )
                graphTile(
                    title: "GPU",
                    value: "\(Int(manager.current.gpuPercent))%",
                    history: manager.gpuHistory,
                    color: color(for: manager.current.gpuPercent)
                )
                graphTile(
                    title: "Net",
                    value: formattedRate(manager.current.netUpBytesPerSec + manager.current.netDownBytesPerSec),
                    history: manager.netHistory,
                    color: .cyan,
                    normalize: true
                )
            }
            .frame(width: 520, alignment: .leading)

            HStack(spacing: 10) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.gray)
                    .frame(width: 20, alignment: .leading)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(manager.current.diskUsedFraction > 0.9 ? Color.red : Color.effectiveAccent)
                        .frame(width: 350 * manager.current.diskUsedFraction, height: 6)
                }
                .frame(width: 350, height: 6, alignment: .leading)

                Text("\(String(format: "%.0f", manager.current.diskFreeGB)) GB free")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .frame(width: 120, alignment: .trailing)
            }
            .frame(width: 520, alignment: .leading)
        }
        .padding(12)
    }

    private func graphTile(title: String, value: String, history: [Double], color: Color, normalize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Sparkline(values: history, color: color, normalizeToMax: normalize)
                .frame(width: 105, height: 16)
        }
        .frame(width: 121, alignment: .leading)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private func color(for percent: Double) -> Color {
        if percent > 80 { return .red }
        if percent > 50 { return .yellow }
        return .effectiveAccent
    }

    private func formattedRate(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1024 {
            return String(format: "%.0f KB/s", kb)
        }
        return String(format: "%.1f MB/s", kb / 1024)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    var normalizeToMax: Bool = false

    var body: some View {
        Path { path in
            guard values.count > 1 else { return }
            let width: CGFloat = 105
            let height: CGFloat = 16
            let maxValue = normalizeToMax ? max(values.max() ?? 1, 1) : 100
            let stepX = width / CGFloat(values.count - 1)
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = height * (1 - CGFloat(v / maxValue))
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .frame(width: 105, height: 16)
    }
}
