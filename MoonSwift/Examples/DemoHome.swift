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

    private func publish() {
        link?.publish(.fields([
            "chats": .table(array: chats.map(\.value), fields: [:]),
            "waiting": .number(Double(chats.filter { $0.question != nil }.count)),
        ]))
    }
}
