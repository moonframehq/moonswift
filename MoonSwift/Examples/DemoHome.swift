import Foundation
import MoonKit

/// Sheprd's Home on its demo data, as a provider: what the real app would
/// publish from its fleet, so `examples/sheprd` can be drawn beside it.
/// Mods read `app.home`; they ask it to mark read, favorite, close, answer.
final class DemoHome: Provider {
    let name = "home"
    private var link: ProviderLink?
    private var chats: [Chat]

    private struct Chat {
        var key, title, agent, status, computer, workspace, last: String
        var favorite = false, unread = false, unopened = false
        var pullRequest: (number: Int, tone: String)?
        var labels: [String] = []
        var started: Date?
        var question: (title: String, options: [(id: String, kind: String, name: String)])?

        var value: LuauValue {
            var fields: [String: LuauValue] = [
                "key": .string(key), "title": .string(title), "agent": .string(agent), "status": .string(status),
                "computer": .string(computer), "workspace": .string(workspace), "last": .string(last),
                "favorite": .bool(favorite), "unread": .bool(unread), "unopened": .bool(unopened),
                "labels": .table(array: labels.map(LuauValue.string), fields: [:]),
            ]
            if let pullRequest {
                fields["pr"] = .fields(["number": .number(Double(pullRequest.number)), "tone": .string(pullRequest.tone)])
            }
            if let started { fields["started"] = .number(started.timeIntervalSince1970) }
            if let question {
                fields["question"] = .fields([
                    "title": .string(question.title),
                    "options": .table(array: question.options.map {
                        .fields(["id": .string($0.id), "kind": .string($0.kind), "name": .string($0.name)])
                    }, fields: [:]),
                ])
            }
            return .fields(fields)
        }
    }

    init(now: Date = .now) {
        chats = [
            Chat(
                key: "c2", title: "Ship the widget fix", agent: "claude", status: "blocked", computer: "Studio",
                workspace: "forecast", last: "Tests pass. Pushing the branch for review.",
                pullRequest: (412, "waiting"), labels: ["Release", "Widgets"], started: now.addingTimeInterval(-95),
                question: ("Run `git push origin fix/widget-refresh`?", [
                    ("allow", "allow_once", "Allow once"), ("always", "allow_always", "Always allow"),
                    ("reject", "reject_once", "Deny"),
                ])
            ),
            Chat(
                key: "c1", title: "Weather widget", agent: "claude", status: "idle", computer: "Studio",
                workspace: "forecast", last: "The widget now reloads after a background fetch.",
                favorite: true, unread: true, pullRequest: (412, "waiting"), labels: ["Widgets"]
            ),
            Chat(
                key: "c4", title: "Show the chart legend", agent: "claude", status: "working", computer: "Studio",
                workspace: "chart legend", last: "Two sub-agents are mapping the chart views.",
                unopened: true, labels: ["Widgets"], started: now.addingTimeInterval(-184)
            ),
            Chat(
                key: "c5", title: "Landing page copy", agent: "codex", status: "idle", computer: "MacBook Air",
                workspace: "website", last: "Rewrote the hero and the three feature blurbs."
            ),
        ]
    }

    func start(_ link: ProviderLink) {
        self.link = link
        publish()
    }

    func receive(_ message: LuauValue, from mod: String?) {
        if message["readAll"] != nil {
            for index in chats.indices { chats[index].unread = false }
            return publish()
        }
        guard let key = (message["read"] ?? message["favorite"] ?? message["close"] ?? message["answer"])?.string,
              let index = chats.firstIndex(where: { $0.key == key })
        else { return }
        if message["read"] != nil { chats[index].unread = !(message["value"]?.bool ?? true) }
        if message["favorite"] != nil { chats[index].favorite = message["value"]?.bool ?? true }
        if message["close"] != nil { chats.remove(at: index) }
        if message["answer"] != nil {
            chats[index].question = nil
            chats[index].status = "working"
        }
        publish()
    }

    /// The computers, their repositories and workspaces, as Workspaces shows
    /// them: what Sheprd's demo has.
    private var machines: LuauValue {
        func workspace(
            _ key: String, label: String, branch: String, own: Bool, counts: String, status: String,
            uncommitted: Bool = false, pr: Int? = nil, unopened: Bool = false
        ) -> LuauValue {
            var fields: [String: LuauValue] = [
                "key": .string(key), "label": .string(label), "branch": .string(branch), "own": .bool(own),
                "counts": .string(counts), "status": .string(status), "uncommitted": .bool(uncommitted),
                "unopened": .bool(unopened),
            ]
            if let pr { fields["pr"] = .fields(["number": .number(Double(pr)), "tone": .string("waiting")]) }
            return .fields(fields)
        }
        let waiting = Double(chats.filter { $0.question != nil }.count)
        return .table(array: [
            .fields([
                "name": .string("Studio"), "waiting": .number(waiting), "cpu": .number(38), "memory": .number(54),
                "repositories": .table(array: [.fields([
                    "label": .string("forecast"),
                    "workspaces": .table(array: [
                        workspace("w1", label: "forecast", branch: "main", own: true, counts: "2 agents · 1 terminal",
                                  status: waiting > 0 ? "blocked" : "idle", pr: 412),
                        workspace("w4", label: "chart legend", branch: "feat/chart-legend", own: false, counts: "1 agent",
                                  status: "working", uncommitted: true, unopened: true),
                    ], fields: [:]),
                ])], fields: [:]),
            ]),
            .fields([
                "name": .string("MacBook Air"), "waiting": .number(0), "cpu": .number(12), "memory": .number(41),
                "repositories": .table(array: [.fields([
                    "label": .string("website"),
                    "workspaces": .table(array: [
                        workspace("w5", label: "website", branch: "main", own: true, counts: "1 agent", status: "idle"),
                    ], fields: [:]),
                ])], fields: [:]),
            ]),
        ], fields: [:])
    }

    /// The demo chat Sheprd opens for "Weather widget": its turns, a prompt
    /// and the agent's answer in markdown.
    private static let transcript: LuauValue = {
        let entries: [(String, String)] = [
            ("user", "Add a dark mode toggle to the settings screen."),
            ("agent", "Done: Settings has an Appearance row with System, Light, and Dark."),
            ("user", """
            The weather widget shows yesterday's forecast after the phone wakes up. \
            Find out why the timeline doesn't refresh, fix it so the widget reloads \
            when the app gets new data in the background, and add a test that covers \
            the stale case. Keep the refresh budget under the system's daily limit.
            """),
            ("agent", """
            ## Why it was stale

            The widget's timeline ends at midnight with a `.never` policy, so \
            WidgetKit only reloads it when the app asks. The background refresh \
            task fetched new forecasts into the shared container but never called \
            `WidgetCenter.shared.reloadTimelines(ofKind:)`.

            ## The fix

            - The refresh task now reloads the forecast widget after it saves new data.
            - It only reloads when the forecast changed, comparing the saved \
            `Forecast.revision`, which keeps the reloads well inside the daily budget.
            - The timeline policy is `.after(nextHour)`, so a missed background \
            refresh still recovers within the hour.

            ## The test

            `ForecastWidgetTests.testReloadsAfterBackgroundFetch` saves a forecast, \
            runs the refresh task against a stub fetcher that returns a newer one, \
            and checks the timeline provider returns the new entry. A second test \
            checks that an unchanged forecast does not ask for a reload.

            ## Checked

            - `swift test`: 148 tests pass.
            - In the simulator, after **Debug › Simulate Background Fetch**, \
            the widget showed today's forecast within a second.
            - Over a day of background fetches the widget asked for 9 reloads, \
            against a budget of 40 to 70.
            """),
        ]
        return .table(array: entries.enumerated().map { index, entry in
            .fields(["id": .number(Double(index + 1)), "kind": .string(entry.0), "text": .string(entry.1)])
        }, fields: [:])
    }()

    private func publish() {
        link?.publish(.fields([
            "machines": machines,
            "transcripts": .fields(["c1": Self.transcript]),
            "chats": .table(array: chats.map(\.value), fields: [:]),
            "waiting": .number(Double(chats.filter { $0.question != nil }.count)),
        ]))
    }
}
