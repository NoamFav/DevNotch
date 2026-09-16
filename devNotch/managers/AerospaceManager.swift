//
//  AerospaceManager.swift
//  devNotch
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

    // Keyboard-row layout keyed by AeroSpace's own monitor id, matching
    // [workspace-to-monitor-force-assignment] in aerospace.toml exactly —
    // NOT by NSScreen.screens ordering, which AeroSpace numbers monitors
    // independently of (and which can itself reorder on hotplug/wake).
    static let layout: [Int: [String]] = [
        1: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        2: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        3: ["A", "S", "D", "F", "G", "Z", "X", "C", "V", "B"],
    ]

    private let nsScreenIndex: Int
    private var timer: Timer?
    private let aerospacePath = "/opt/homebrew/bin/aerospace"

    init(nsScreenIndex: Int) {
        self.nsScreenIndex = nsScreenIndex
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

    // AeroSpace is the source of truth for monitor numbering: ask it which
    // of its monitor ids this NSScreen currently is, via the format field
    // AeroSpace exposes specifically for this correlation, instead of
    // assuming AeroSpace's ids match NSScreen.screens ordering (they don't).
    private nonisolated static func resolveMonitorID(nsScreenIndex: Int, aerospacePath: String) -> Int? {
        let raw = run(aerospacePath, ["list-monitors", "--format", "%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}"])
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "|")
            guard parts.count == 2,
                  let monitorID = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let screenIndex = Int(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            if screenIndex == nsScreenIndex {
                return monitorID
            }
        }
        return nil
    }

    func refresh() {
        let nsScreenIndex = self.nsScreenIndex
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
            guard let monitorID = Self.resolveMonitorID(nsScreenIndex: nsScreenIndex, aerospacePath: aerospacePath),
                  let keys = AerospaceManager.layout[monitorID]
            else {
                await MainActor.run { [weak self] in self?.workspaces = [] }
                return
            }

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
