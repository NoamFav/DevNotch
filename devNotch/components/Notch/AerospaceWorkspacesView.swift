//
//  AerospaceWorkspacesView.swift
//  devNotch
//
//  Spike: AeroSpace workspace row that lives inside the closed notch shape
//  itself, alongside the face/live-activity content — governed by the
//  same NotchLayout state as everything else in there.
//

import SwiftUI

struct AerospaceWorkspacesView: View {
    @ObservedObject var manager: AerospaceManager
    var emptySize: CGFloat

    var body: some View {
        Group {
            if manager.workspaces.isEmpty {
                Rectangle()
                    .fill(.clear)
                    .frame(width: emptySize, height: emptySize)
            } else {
                HStack(spacing: 6) {
                    ForEach(manager.workspaces) { ws in
                        WorkspaceChip(workspace: ws)
                    }
                }
                .padding(.leading, 6)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.workspaces)
    }
}

private struct WorkspaceChip: View {
    let workspace: AerospaceWorkspace

    var body: some View {
        HStack(spacing: 4) {
            Text(workspace.id)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(workspace.isFocused ? Color.effectiveAccent : .gray)

            ForEach(workspace.appBundleIDs, id: \.self) { bundleID in
                AppIcon(for: bundleID)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .opacity(workspace.isFocused ? 1 : 0.45)
                    .saturation(workspace.isFocused ? 1 : 0)
            }
        }
        // One shared pill enclosing the workspace key AND its app icons,
        // matching sketchybar's per-workspace chip (icon + label in one
        // bracket) instead of a separate badge nested inside it.
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(workspace.isFocused ? Color.effectiveAccentBackground : Color.white.opacity(0.06))
        )
    }
}
