#if os(iOS)
import SwiftUI

/// Benchmark B6's baseline: `examples/prs` written by hand in SwiftUI, as
/// Sheprd writes its Pull Requests tab (sheprd-labs/sheprd#1715).
struct PullRequestsList: View {
    @State private var query = ""

    var body: some View {
        List {
            section("Review requested", pulls: BenchPull.all(mine: false), showsAuthor: true)
            section("Mine", pulls: BenchPull.all(mine: true), showsAuthor: false)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .refreshable {}
        .searchable(text: $query, prompt: "Title, repository, author, branch")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: BenchPull.self) { Text(verbatim: $0.title) }
    }

    private func section(_ title: String, pulls: [BenchPull], showsAuthor: Bool) -> some View {
        Section {
            ForEach(pulls) { pull in
                NavigationLink(value: pull) {
                    PullRequestRow(pull: pull, showsAuthor: showsAuthor)
                }
                .contextMenu {
                    ForEach(pull.places, id: \.self) { place in
                        Button("Open Workspace on \(place)", systemImage: "laptopcomputer") {}
                    }
                    Link(destination: pull.url) { Label("Open on GitHub", systemImage: "safari") }
                    ShareLink(item: pull.url)
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(pulls.count) of \(pulls.count * 2)").textCase(nil)
            }
        }
    }
}

/// The made-up pull requests both sides draw, as `examples/prs` makes them.
struct BenchPull: Identifiable, Hashable {
    static let count = 50
    private static let repos = ["sheprd", "sheprd-apns", "herdr-site", "infra"]
    private static let titles = [
        "Read pull requests on the phone with a lent GitHub sign-in", "Keep the relay's dial keys after a restart",
        "Docs: GitHub on the phone", "Group tabs by worktree in the iPad sidebar", "Bump relay droplets to 2 vCPU",
        "Teleport: carry checkpoints across hosts and keep their labels when the worktree moves",
    ]
    private static let decisions = ["none", "approved", "changesRequested", "reviewRequired"]
    private static let authors = ["octocat", "hubot", "monalisa", "dependabot"]
    private static let computers = ["Studio", "MacBook Pro", "Mac mini"]

    let id: Int
    let repository: String
    let title: String
    let draft: Bool
    let review: String
    let author: String
    let age: String
    let failing: Int, pending: Int, passed: Int
    let places: [String]
    let url: URL

    static func all(mine: Bool) -> [BenchPull] {
        (0..<count).map { BenchPull(index: $0, mine: mine) }
    }

    init(index: Int, mine: Bool) {
        let number = (mine ? 1000 : 2000) + index
        let repo = Self.repos[index % Self.repos.count]
        let minutes = index * 30
        id = number
        repository = "sheprd-labs/\(repo) #\(number)"
        title = Self.titles[index % Self.titles.count]
        draft = index % 9 == 4
        review = Self.decisions[index % Self.decisions.count]
        author = Self.authors[index % Self.authors.count]
        age = minutes < 60 ? (minutes == 0 ? "now" : "\(minutes)m") : "\(minutes / 60)h"
        failing = index % 4 == 2 ? 1 : 0
        pending = index % 3
        passed = 3 + index % 11
        places = index % 3 == 0 ? [Self.computers[index % Self.computers.count]] : []
        url = URL(string: "https://github.com/sheprd-labs/\(repo)/pull/\(number)")!
    }
}

/// Sheprd's `PullRequestListRow`, on the bench's data.
private struct PullRequestRow: View {
    var pull: BenchPull
    var showsAuthor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: pull.draft ? "pencil.circle" : "arrow.triangle.pull")
                    .font(.caption.weight(.semibold)).foregroundStyle(pull.draft ? Color.secondary : .green)
                Text(verbatim: pull.repository).font(.caption.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(verbatim: pull.age).font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: pull.title).lineLimit(2)
            HStack(spacing: 8) {
                if showsAuthor {
                    Avatar(login: pull.author, size: 16)
                    Text(verbatim: pull.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if let review = Review(pull.review) {
                    IconText(review.label, systemImage: review.symbol)
                        .font(.caption.weight(.medium)).foregroundStyle(review.color).lineLimit(1)
                } else {
                    Text(pull.draft ? "Draft" : "Open").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                CheckCounts(failing: pull.failing, pending: pull.pending, passed: pull.passed)
            }
            Group {
                if let first = pull.places.first {
                    IconText("Workspace on \(first)", systemImage: "laptopcomputer")
                } else {
                    IconText("No workspace on any computer", systemImage: "icloud")
                }
            }
            .font(.caption2)
            .foregroundStyle(pull.places.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct Review {
    let label: String, symbol: String, color: Color

    init?(_ name: String) {
        switch name {
        case "approved": (label, symbol, color) = ("Approved", "checkmark.seal.fill", .green)
        case "changesRequested": (label, symbol, color) = ("Changes requested", "exclamationmark.bubble.fill", .red)
        case "reviewRequired": (label, symbol, color) = ("Review required", "eye", .orange)
        default: return nil
        }
    }
}

private struct CheckCounts: View {
    let failing: Int, pending: Int, passed: Int

    var body: some View {
        HStack(spacing: 8) {
            if failing > 0 { count(failing, "xmark.circle.fill", .red) }
            if pending > 0 { count(pending, "clock.fill", .yellow) }
            if passed > 0 { count(passed, "checkmark.circle.fill", .green) }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .fixedSize()
    }

    private func count(_ value: Int, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(verbatim: "\(value)").foregroundStyle(.secondary)
        }
    }
}

private struct IconText: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(verbatim: title)
        }
    }
}

private struct Avatar: View {
    let login: String
    let size: CGFloat

    var body: some View {
        Text(login.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .circle)
    }

    private var tint: Color {
        let palette: [Color] = [.indigo, .teal, .pink, .orange, .blue, .purple, .mint, .red, .cyan, .brown]
        let sum = login.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}
#endif
