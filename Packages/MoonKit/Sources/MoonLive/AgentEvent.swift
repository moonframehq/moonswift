import Foundation

/// What matters in one line of `claude --output-format stream-json`.
public enum AgentEvent: Equatable, Sendable {
    case session(String)
    case said(String)
    /// A tool, and the file it works on, if any.
    case tool(String, String?)
    case finished(failed: Bool, message: String?)

    /// Lines that aren't JSON, such as a shell's startup noise, give nothing.
    public static func parse(_ line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        switch object["type"] as? String {
        case "system":
            return (object["session_id"] as? String).map { [.session($0)] } ?? []
        case "assistant":
            let message = object["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]] ?? []
            return content.compactMap { block in
                switch block["type"] as? String {
                case "text":
                    return (block["text"] as? String).map(AgentEvent.said)
                case "tool_use":
                    let input = block["input"] as? [String: Any]
                    return (block["name"] as? String).map { .tool($0, input?["file_path"] as? String) }
                default:
                    return nil
                }
            }
        case "result":
            return [.finished(failed: object["is_error"] as? Bool ?? false, message: object["result"] as? String)]
        default:
            return []
        }
    }
}
