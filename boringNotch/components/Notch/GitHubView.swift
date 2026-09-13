//
//  GitHubView.swift
//  boringNotch
//
//  Spike: contribution graph + PRs/review-requests/issues on the left,
//  dirty-repo status (via iskra) as a narrow side column on the right.
//
//  Sizing follows CalendarView's pattern exactly: every leaf gets a
//  concrete width (no maxWidth: .infinity, no Spacer, no outer wrapper
//  frame) so the shared notch shape sizes the same way it does for
//  NotchHomeView/ShelfView.
//

import SwiftUI

struct GitHubView: View {
    @ObservedObject var manager = GitHubManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(manager.totalContributions) contributions")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 350, alignment: .leading)

                ContributionHeatmap(weeks: manager.weeks)
                    .frame(width: 350, height: 42, alignment: .leading)

                HStack(spacing: 0) {
                    statBadge(icon: "arrow.triangle.pull", count: manager.openPRs.count, label: "Open PRs")
                    statBadge(icon: "eye", count: manager.reviewRequests.count, label: "Reviews")
                    statBadge(icon: "exclamationmark.circle", count: manager.assignedIssues.count, label: "Issues")
                }
                .frame(width: 350, alignment: .leading)
            }
            .frame(width: 350, alignment: .leading)

            Divider().background(Color.white.opacity(0.15))

            VStack(alignment: .leading, spacing: 6) {
                Text("Dirty repos")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .frame(width: 130, alignment: .leading)

                if manager.dirtyRepos.isEmpty {
                    Text("All clean")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(width: 130, alignment: .leading)
                } else {
                    ForEach(manager.dirtyRepos.prefix(6)) { repo in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(repo.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(repo.statusText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                        .frame(width: 130, alignment: .leading)
                    }
                }
            }
            .frame(width: 130, alignment: .leading)
        }
        .padding(16)
        .frame(height: 130, alignment: .top)
    }

    private func statBadge(icon: String, count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Label("\(count)", systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(count > 0 ? Color.effectiveAccent : .gray)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .frame(width: 116)
    }
}

private struct ContributionHeatmap: View {
    let weeks: [[ContributionDay]]

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 1) {
                    ForEach(week, id: \.date) { day in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color(for: day.count))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
    }

    private var maxCount: Int {
        max(weeks.flatMap { $0 }.map(\.count).max() ?? 1, 1)
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return Color.white.opacity(0.08) }
        let intensity = min(1.0, Double(count) / Double(maxCount))
        return Color.effectiveAccent.opacity(0.25 + intensity * 0.75)
    }
}
