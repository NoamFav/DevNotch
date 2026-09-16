//
//  GitHubManager.swift
//  devNotch
//
//  Spike: contribution graph + open PRs/review-requests/issues via a
//  single `gh api graphql` call (reusing the already-authenticated `gh`
//  CLI), plus the "which repos are dirty" side panel via `iskra status
//  -json` — the same tool items/widgets/git_toolkit.lua's iskra_scan.sh
//  wraps for the sketchybar git widget.
//

import Foundation
import Combine

struct ContributionDay: Equatable {
    let date: String
    let count: Int
}

struct GHItem: Identifiable, Equatable {
    let id: String
    let number: Int
    let title: String
    let repo: String
    let url: String
}

struct DirtyRepo: Identifiable, Equatable {
    let id: String
    let name: String
    let branch: String
    let staged: Int
    let uncommitted: Int
    let untracked: Int
    let ahead: Int
    let behind: Int

    var statusText: String {
        var bits: [String] = []
        if ahead > 0 { bits.append("↑\(ahead)") }
        if behind > 0 { bits.append("↓\(behind)") }
        if staged > 0 { bits.append("+\(staged)") }
        if uncommitted > 0 { bits.append("~\(uncommitted)") }
        if untracked > 0 { bits.append("?\(untracked)") }
        return bits.joined(separator: " ")
    }
}

@MainActor
final class GitHubManager: ObservableObject {
    static let shared = GitHubManager()

    @Published private(set) var totalContributions = 0
    @Published private(set) var weeks: [[ContributionDay]] = []
    @Published private(set) var openPRs: [GHItem] = []
    @Published private(set) var reviewRequests: [GHItem] = []
    @Published private(set) var assignedIssues: [GHItem] = []
    @Published private(set) var dirtyRepos: [DirtyRepo] = []
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private let ghPath = "/opt/homebrew/bin/gh"
    private let iskraPath = NSString(string: "~/.local/bin/iskra").expandingTildeInPath

    private init() {
        refresh()
        // GitHub data changes slowly; iskra (local, cheap) could poll faster,
        // but one shared interval keeps this simple for the spike.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private nonisolated static func run(_ path: String, _ args: [String]) -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            return Data()
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return data
    }

    func refresh() {
        let ghPath = self.ghPath
        let iskraPath = self.iskraPath

        Task.detached(priority: .utility) {
            let ghData = Self.run(ghPath, ["api", "graphql", "-f", "query=\(Self.query)"])
            let iskraData = Self.run(iskraPath, ["status", "-json"])

            let ghResponse = try? JSONDecoder().decode(GHResponse.self, from: ghData)
            let iskraResponse = try? JSONDecoder().decode(IskraResponse.self, from: iskraData)

            await MainActor.run { [weak self] in
                guard let self else { return }

                if let gh = ghResponse?.data {
                    let calendar = gh.viewer.contributionsCollection.contributionCalendar
                    self.totalContributions = calendar.totalContributions
                    self.weeks = calendar.weeks.map { week in
                        week.contributionDays.map { ContributionDay(date: $0.date, count: $0.contributionCount) }
                    }
                    self.openPRs = gh.prs.nodes.map(Self.toItem)
                    self.reviewRequests = gh.reviewRequests.nodes.map(Self.toItem)
                    self.assignedIssues = gh.issues.nodes.map(Self.toItem)
                    self.lastError = nil
                } else if ghResponse == nil {
                    self.lastError = "GitHub fetch failed"
                }

                if let iskra = iskraResponse {
                    self.dirtyRepos = iskra.results
                        .filter { r in
                            r.changes.staged + r.changes.uncommitted + r.changes.untracked > 0
                                || r.remote.ahead > 0 || r.remote.behind > 0
                        }
                        .map { r in
                            DirtyRepo(
                                id: r.path,
                                name: r.name,
                                branch: r.branch,
                                staged: r.changes.staged,
                                uncommitted: r.changes.uncommitted,
                                untracked: r.changes.untracked,
                                ahead: r.remote.ahead,
                                behind: r.remote.behind
                            )
                        }
                        .sorted { $0.name < $1.name }
                }
            }
        }
    }

    private nonisolated static func toItem(_ node: GHNode) -> GHItem {
        GHItem(id: "\(node.repository.nameWithOwner)#\(node.number)", number: node.number, title: node.title, repo: node.repository.nameWithOwner, url: node.url)
    }

    private static let query = """
    query {
      viewer {
        contributionsCollection {
          contributionCalendar {
            totalContributions
            weeks { contributionDays { contributionCount date } }
          }
        }
      }
      prs: search(query: \"is:pr is:open author:@me\", type: ISSUE, first: 10) {
        nodes { ... on PullRequest { number title url repository { nameWithOwner } } }
      }
      reviewRequests: search(query: \"is:pr is:open review-requested:@me\", type: ISSUE, first: 10) {
        nodes { ... on PullRequest { number title url repository { nameWithOwner } } }
      }
      issues: search(query: \"is:issue is:open assignee:@me\", type: ISSUE, first: 10) {
        nodes { ... on Issue { number title url repository { nameWithOwner } } }
      }
    }
    """
}

// MARK: - GitHub GraphQL response shape

private struct GHResponse: Decodable { let data: GHData }
private struct GHData: Decodable {
    let viewer: GHViewer
    let prs: GHSearch
    let reviewRequests: GHSearch
    let issues: GHSearch
}
private struct GHViewer: Decodable { let contributionsCollection: GHContributions }
private struct GHContributions: Decodable { let contributionCalendar: GHCalendar }
private struct GHCalendar: Decodable {
    let totalContributions: Int
    let weeks: [GHWeek]
}
private struct GHWeek: Decodable { let contributionDays: [GHDay] }
private struct GHDay: Decodable { let contributionCount: Int; let date: String }
private struct GHSearch: Decodable { let nodes: [GHNode] }
private struct GHNode: Decodable {
    let number: Int
    let title: String
    let url: String
    let repository: GHRepo
}
private struct GHRepo: Decodable { let nameWithOwner: String }

// MARK: - iskra status -json response shape

private struct IskraResponse: Decodable { let results: [IskraRepo] }
private struct IskraRepo: Decodable {
    let path: String
    let name: String
    let branch: String
    let changes: IskraChanges
    let remote: IskraRemote
}
private struct IskraChanges: Decodable { let uncommitted: Int; let staged: Int; let untracked: Int }
private struct IskraRemote: Decodable { let ahead: Int; let behind: Int }
