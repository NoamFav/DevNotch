//
//  AerospaceManager.swift
//  boringNotch
//
//  Spike: per-screen AeroSpace workspace row, mirroring the static
//  keyboard-row layout convention and "show if focused or has windows"
//  visibility rule from the sketchybar config
//  (items/aerospace_workspaces.lua WORKSPACE_LAYOUT), but living inside
//  the notch shape itself and enriched with real app icons.
//

import Foundation
import AppKit
import Combine

struct AerospaceWorkspace: Identifiable, Equatable {
    let id: String // workspace key, e.g. "1", "Q", "A"
    var isFocused: Bool
    var appBundleIDs: [String] // deduped, running apps with windows in this workspace
}

@MainActor
final class AerospaceManager: ObservableObject {
    @Published private(set) var workspaces: [AerospaceWorkspace] = []

    // display 1 = left monitor, 2 = center, 3 = right — matches
    // items/aerospace_workspaces.lua WORKSPACE_LAYOUT exactly.
    static let layout: [Int: [String]] = [
        1: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        2: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        3: ["A", "S", "D", "F", "G", "Z", "X", "C", "V", "B"],
    ]

    private let keys: [String]
    private var timer: Timer?
    private let aerospacePath = "/opt/homebrew/bin/aerospace"

    init(screenIndex: Int) {
        keys = AerospaceManager.layout[screenIndex] ?? []
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    // Off the main actor: subprocess + parsing must not block the UI thread
    // the way the sketchybar/lua widgets' shelling-out does today.
    private nonisolated static func run(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func refresh() {
        guard !keys.isEmpty else { return }
        let keys = self.keys
        let aerospacePath = self.aerospacePath

        // Resolve running-app name -> bundle id on the main actor (AppKit
        // API), then hop off to do the subprocess + text work.
        var nameToBundleID: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, let bundleID = app.bundleIdentifier {
                nameToBundleID[name] = bundleID
            }
        }

        Task.detached(priority: .utility) {
            let focused = Self.run(aerospacePath, ["list-workspaces", "--focused"])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // One call for every window on every workspace, instead of one
            // `list-windows` call per key — 2 subprocess spawns per refresh
            // total, not up to 11.
            let raw = Self.run(aerospacePath, ["list-windows", "--all", "--format", "%{workspace}|%{app-name}"])

            var appsByWorkspace: [String: [String]] = [:]
            for line in raw.split(separator: "\n") {
                let parts = line.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let workspace = String(parts[0])
                let appName = String(parts[1])
                appsByWorkspace[workspace, default: []].append(appName)
            }

            var result: [AerospaceWorkspace] = []
            for key in keys {
                let appNames = appsByWorkspace[key] ?? []
                let isFocused = key == focused
                guard isFocused || !appNames.isEmpty else { continue }

                var seen = Set<String>()
                var bundleIDs: [String] = []
                for name in appNames {
                    guard !seen.contains(name) else { continue }
                    seen.insert(name)
                    if let bundleID = nameToBundleID[name] {
                        bundleIDs.append(bundleID)
                    }
                    if bundleIDs.count >= 3 { break }
                }

                result.append(AerospaceWorkspace(id: key, isFocused: isFocused, appBundleIDs: bundleIDs))
            }

            await MainActor.run { [weak self] in
                guard let self, result != self.workspaces else { return }
                self.workspaces = result
            }
        }
    }
}
